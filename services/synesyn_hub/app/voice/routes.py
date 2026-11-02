from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import re
import time
from pathlib import Path
from typing import Any, Dict, Optional
from urllib.parse import urlparse, unquote

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from ..substrate.artifact_store import ArtifactStore
from ..utils import new_id
from .lipsync import generate_simple_lipsync
from .stt import (
	WhisperBackend,
	decode_base64_audio,
	whisper_runtime_status,
)
from .tts import VoiceParams
from .providers import ProviderChain
from .sidecar import VoiceSidecarManager


log = logging.getLogger("synesyn_hub.voice")
router = APIRouter()

_whisper = WhisperBackend(model_name="base")
_providers = ProviderChain()

# Intent:
# - The hub is the system-of-record for voice artifacts and provenance (audio.tts, text.transcript, audio.input).
# - Compute can be provided either by:
#   (1) in-hub providers (edge-tts + SAPI fallback; Whisper), OR
#   (2) an optional hub-managed sidecar process (legacy syntree-voice-service) for compute only.
# - `character_mapping` is an optional provenance field that records *how* a character name resolved to a voice id.
#   This is critical for auditability once characters have overrides/mappings that evolve over time.


_tts_cache_lock = asyncio.Lock()
_TTS_CACHE_MAX_ENTRIES = 500
_RATE_RE = re.compile(r"^[+-]?\d+%$")
_PITCH_RE = re.compile(r"^[+-]?\d+Hz$")


def _best_effort_module_version(module_name: str) -> str:
	try:
		mod = __import__(module_name)
		v = getattr(mod, "__version__", None)
		if v:
			return str(v)
	except Exception:
		pass
	return "unknown"


def _uri_to_path(uri: str) -> Optional[Path]:
	try:
		u = (uri or "").strip()
		if not u:
			return None
		parsed = urlparse(u)
		if parsed.scheme != "file":
			return None
		p = unquote(parsed.path or "")
		# Windows file URIs are typically /C:/...
		if len(p) >= 3 and p[0] == "/" and p[2] == ":":
			p = p[1:]
		return Path(p)
	except Exception:
		return None


def _tts_cache_index_path(request: Request) -> Optional[Path]:
	try:
		cfg = request.app.state.cfg
		if not cfg.workspace:
			return None
		cache_dir = cfg.workspace.artifacts_dir / "_cache"
		cache_dir.mkdir(parents=True, exist_ok=True)
		return cache_dir / "tts_cache.json"
	except Exception:
		return None


def _load_tts_cache(path: Path) -> Dict[str, Any]:
	try:
		if not path.exists():
			return {}
		obj = json.loads(path.read_text(encoding="utf-8"))
		return obj if isinstance(obj, dict) else {}
	except Exception:
		return {}


def _save_tts_cache(path: Path, cache: Dict[str, Any]) -> None:
	try:
		path.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
	except Exception:
		# Cache must never break voice.
		return


def get_voice_providers_status() -> Dict[str, Any]:
	status = _providers.status()
	whisper_ready, whisper_error = whisper_runtime_status()
	# Include STT availability so /status and /health can report accurately even when optional
	# deps are not packaged (e.g. PyInstaller onefile builds without Whisper).
	status["stt"] = {
		"whisper": {
			"available": whisper_ready,
			"import_error": whisper_error,
		}
	}
	return status


async def self_test_edge_tts() -> None:
	await _providers.self_test_edge()


class VoiceConfig(BaseModel):
	name: str = "en-US-AriaNeural"
	rate: str = "+0%"
	volume: str = "+0%"
	pitch: str = "+0Hz"


class SpeakRequest(BaseModel):
	text: str
	character: str = "Narrator"
	voice: VoiceConfig = Field(default_factory=VoiceConfig)
	# Provider preference for hub mode:
	# - "auto" (default): edge_tts then sapi fallback
	# - "edge_tts": force Edge TTS (no SAPI fallback)
	# - "sapi": force pyttsx3/SAPI
	# - "sidecar": force sidecar if configured and healthy
	provider_preference: Optional[str] = None
	format: str = "wav"
	return_lipsync: bool = True
	session_id: Optional[str] = None
	# v1: provenance can include the specific character mapping that selected this voice (if any).
	# Example: {"source":"user://syntree_voice/character_voices.json","version":3,"character":"Narrator","voice":"en-US-AriaNeural"}
	character_mapping: Optional[Dict[str, Any]] = None


class TranscribeRequest(BaseModel):
	audio_base64: str
	audio_format: str = "wav"
	language: Optional[str] = "en"
	save_recordings: bool = False
	session_id: Optional[str] = None
	# v1: optional provenance for how STT input relates to a character/speaker mapping (if any).
	character: Optional[str] = None
	character_mapping: Optional[Dict[str, Any]] = None


def _require_workspace_store(request: Request) -> ArtifactStore:
	cfg = request.app.state.cfg
	if not cfg.workspace:
		raise HTTPException(status_code=503, detail="Workspace not configured")
	return ArtifactStore(cfg.workspace.artifacts_dir)


@router.post("/speak")
async def speak(req: SpeakRequest, request: Request):
	try:
		store = _require_workspace_store(request)
		text = req.text.strip()
		if not text:
			raise HTTPException(status_code=400, detail="Text is empty")

		# Be tolerant of malformed per-scenario tuning values so TTS doesn't fully fail.
		voice_name = str(req.voice.name or "").strip() or "en-US-AriaNeural"
		rate = str(req.voice.rate or "").strip() or "+0%"
		volume = str(req.voice.volume or "").strip() or "+0%"
		pitch = str(req.voice.pitch or "").strip() or "+0Hz"
		if not _RATE_RE.fullmatch(rate):
			rate = "+0%"
		if not _RATE_RE.fullmatch(volume):
			volume = "+0%"
		if not _PITCH_RE.fullmatch(pitch):
			pitch = "+0Hz"

		params = VoiceParams(
			name=voice_name,
			rate=rate,
			volume=volume,
			pitch=pitch,
		)
		used_voice_params: Dict[str, Any] = {
			"name": voice_name,
			"rate": rate,
			"volume": volume,
			"pitch": pitch,
		}

		provider_pref = str(req.provider_preference or "auto").strip().lower()
		if provider_pref in ("",):
			provider_pref = "auto"
		if provider_pref in ("edge", "edge_tts", "edgetts"):
			provider_pref = "edge_tts"
		elif provider_pref in ("pyttsx3",):
			provider_pref = "sapi"
		elif provider_pref in ("voice_sidecar",):
			provider_pref = "sidecar"

		# v1 caching: reuse artifacts for identical (text + voice params) requests.
		text_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
		cache_key_payload = {
			"text_sha256": text_hash,
			"voice": req.voice.model_dump(),
			"provider_preference": (req.provider_preference or "auto"),
			"format": req.format or "wav",
		}
		cache_key = hashlib.sha256(json.dumps(cache_key_payload, sort_keys=True).encode("utf-8")).hexdigest()

		cache_path = _tts_cache_index_path(request)
		if cache_path:
			async with _tts_cache_lock:
				cache = _load_tts_cache(cache_path)
				entry_any = cache.get(cache_key)
				if isinstance(entry_any, dict):
					audio_uri = str(entry_any.get("audio_uri", "")).strip()
					audio_art_id = str(entry_any.get("audio_artifact_id", "")).strip()
					audio_hash = str(entry_any.get("audio_hash", "")).strip()
					duration = float(entry_any.get("duration_sec", 0.0) or 0.0)
					voice_used = entry_any.get("voice_used")
					provider_used = entry_any.get("provider_used")
					voice_params_used = entry_any.get("voice_params_used")

					audio_ok = False
					audio_path = _uri_to_path(audio_uri)
					if audio_path and audio_path.exists():
						audio_ok = True
					# A SAPI fallback cached during an earlier Edge failure must
					# not replace the requested neural voice on later runs.
					if provider_pref != "sapi" and (
						str(provider_used or "").strip().lower() == "sapi"
						or (voice_name and str(voice_used or "").strip() != voice_name)
					):
						audio_ok = False

					# If lipsync requested, ensure lipsync artifact exists too.
					lipsync_art_id = None
					lipsync_uri = None
					if req.return_lipsync:
						lid = str(entry_any.get("lipsync_artifact_id", "")).strip()
						luri = str(entry_any.get("lipsync_uri", "")).strip()
						lpath = _uri_to_path(luri)
						if lid and luri and lpath and lpath.exists():
							lipsync_art_id = lid
							lipsync_uri = luri
						else:
							audio_ok = False

					if audio_ok and audio_art_id and audio_uri:
						cached_audio_fmt = str(entry_any.get("audio_format", "wav")).strip() or "wav"
						return {
							"ok": True,
							"cached": True,
							"audio_artifact_id": audio_art_id,
							"audio_url": audio_uri,
							"audio_format": cached_audio_fmt,
							"lipsync_artifact_id": lipsync_art_id,
							"lipsync_url": lipsync_uri,
							"duration_sec": duration,
							"voice_used": voice_used,
							"provider_used": provider_used,
							"voice_params_used": voice_params_used or used_voice_params,
						}
					# Stale cache entry; drop it.
					cache.pop(cache_key, None)
					_save_tts_cache(cache_path, cache)

		# Packaging topology option 2: hub-managed sidecar (compute via sidecar, persist via hub).
		sidecar: Optional[VoiceSidecarManager] = getattr(request.app.state, "voice_sidecar", None)
		use_sidecar = False
		if provider_pref == "sidecar":
			# Fail-safe: if forced sidecar is unavailable, degrade to auto instead of hard-failing TTS.
			if not sidecar or not sidecar.is_enabled():
				log.warning("voice.speak: sidecar forced but not enabled; falling back to provider_preference=auto")
				provider_pref = "auto"
			else:
				use_sidecar = await sidecar.check_health()
				if not use_sidecar:
					log.warning("voice.speak: sidecar forced but unhealthy; falling back to provider_preference=auto")
					provider_pref = "auto"
		elif provider_pref == "auto":
			if sidecar and sidecar.is_enabled():
				use_sidecar = await sidecar.check_health()

		if use_sidecar:
			side_res = await sidecar.synthesize(text=text, character=req.character, voice_name=req.voice.name)
			if not bool(side_res.get("success", False)):
				raise HTTPException(status_code=502, detail=str(side_res.get("error", "sidecar_synthesize_failed")))
			import base64
			audio_b64 = str(side_res.get("audio", "")).strip()
			if not audio_b64:
				raise HTTPException(status_code=502, detail="sidecar returned empty audio")
			wav_bytes = base64.b64decode(audio_b64)
			duration = float(side_res.get("duration", 0.0) or 0.0)
			# Prefer sidecar-provided lipsync if available; otherwise hub fallback.
			side_lipsync = side_res.get("lipsync", None)
			tts_provider = "voice_sidecar"
			tts_voice_used = req.voice.name
			tts_audio_format = "wav"
		else:
			try:
				tts = await _providers.speak_with_preference(text, params, provider_pref)
			except Exception:
				# Fail-safe: if a forced provider fails, try auto-chain before surfacing error.
				if provider_pref != "auto":
					log.exception("voice.speak: provider_preference=%s failed; retrying with auto", provider_pref)
					tts = await _providers.speak_with_preference(text, params, "auto")
				elif params.rate != "+0%" or params.volume != "+0%" or params.pitch != "+0Hz":
					# Additional fail-safe for tuned scenario voices: retry once with neutral tuning.
					log.exception("voice.speak: tuned voice params failed; retrying with neutral params")
					params = VoiceParams(name=params.name, rate="+0%", volume="+0%", pitch="+0Hz")
					used_voice_params = {
						"name": params.name,
						"rate": params.rate,
						"volume": params.volume,
						"pitch": params.pitch,
					}
					tts = await _providers.speak_with_preference(text, params, "auto")
				else:
					raise
			wav_bytes, duration = tts.wav_bytes, tts.duration_sec
			side_lipsync = None
			tts_provider = tts.provider
			tts_voice_used = tts.voice_used
			tts_audio_format = getattr(tts, "audio_format", "wav")
		audio_ext = tts_audio_format if tts_audio_format in ("wav", "mp3") else "wav"
		audio_art_id, audio_uri, audio_hash = store.write_bytes("audio.tts", wav_bytes, audio_ext)

		lipsync_art_id = None
		lipsync_uri = None
		if req.return_lipsync:
			frames = side_lipsync if isinstance(side_lipsync, list) and len(side_lipsync) > 0 else generate_simple_lipsync(text, duration)
			lipsync_art_id, lipsync_uri, _ = store.write_json("json.lipsync", frames, "json")

		# Update cache (best-effort, bounded). Never cache a SAPI fallback under
		# a neural voice key, or that phrase stays on the default voice after
		# Edge recovers.
		should_cache = provider_pref == "sapi" or (
			str(tts_provider or "").strip().lower() != "sapi"
			and (not voice_name or str(tts_voice_used or "").strip() == voice_name)
		)
		if cache_path and should_cache:
			async with _tts_cache_lock:
				cache = _load_tts_cache(cache_path)
				cache[cache_key] = {
					"t": time.time(),
					"audio_artifact_id": audio_art_id,
					"audio_uri": audio_uri,
					"audio_hash": audio_hash,
					"audio_format": audio_ext,
					"duration_sec": duration,
					"lipsync_artifact_id": lipsync_art_id,
					"lipsync_uri": lipsync_uri,
					"provider_used": tts_provider,
					"voice_used": tts_voice_used,
					"voice_params_used": used_voice_params,
				}
				# Prune oldest entries to avoid unbounded growth.
				if len(cache) > _TTS_CACHE_MAX_ENTRIES:
					items = []
					for k, v in cache.items():
						if isinstance(v, dict):
							items.append((k, float(v.get("t", 0.0) or 0.0)))
					items.sort(key=lambda kv: kv[1])  # oldest first
					for k, _t in items[: max(0, len(cache) - _TTS_CACHE_MAX_ENTRIES)]:
						cache.pop(k, None)
				_save_tts_cache(cache_path, cache)

		# Persist artifact index into substrate (best-effort v0)
		repo = getattr(request.app.state, "substrate_repo", None)
		if repo:
			await repo.insert_artifact(
				{
					"id": audio_art_id,
					"artifact_type": "audio.tts",
					"uri": audio_uri,
					"hash": audio_hash,
					"metadata": {
						"input_text_hash": text_hash,
						"voice_params": used_voice_params,
						"engine": {
							"name": str(tts_provider),
							"version": _best_effort_module_version("edge_tts") if str(tts_provider) == "edge_tts" else "unknown",
						},
						"provenance": {
							"generated_by": "voice.speak",
							"provider": tts_provider,
							"voice_used": tts_voice_used,
							"character": req.character,
							"character_mapping": req.character_mapping,
							"session_id": req.session_id,
							"inputs": [{"type": "text", "sha256": text_hash}],
						}
					},
				}
			)
			if lipsync_art_id and lipsync_uri:
				await repo.insert_artifact(
					{
						"id": lipsync_art_id,
						"artifact_type": "json.lipsync",
						"uri": lipsync_uri,
						"hash": "na",
						"metadata": {
							"provenance": {
								"generated_by": "voice.lipsync",
								"session_id": req.session_id,
								"inputs": [{"type": "artifact", "id": audio_art_id}],
							}
						},
					}
				)
			await repo.commit()

		return {
			"ok": True,
			"audio_artifact_id": audio_art_id,
			"audio_url": audio_uri,
			"audio_format": audio_ext,
			"lipsync_artifact_id": lipsync_art_id,
			"lipsync_url": lipsync_uri,
			"duration_sec": duration,
			"voice_used": tts_voice_used,
			"provider_used": tts_provider,
			"voice_params_used": used_voice_params,
		}
	except HTTPException:
		raise
	except Exception as e:
		log.exception("/voice/speak failed")
		raise HTTPException(status_code=500, detail=str(e))


@router.post("/transcribe")
async def transcribe(req: TranscribeRequest, request: Request):
	try:
		store = _require_workspace_store(request)
		audio_bytes = decode_base64_audio(req.audio_base64)

		# Always compute an input hash for traceability/dedupe
		input_hash = hashlib.sha256(audio_bytes).hexdigest()

		# Packaging topology option 2: hub-managed sidecar (compute via sidecar, persist via hub).
		sidecar: Optional[VoiceSidecarManager] = getattr(request.app.state, "voice_sidecar", None)
		use_sidecar = False
		if sidecar and sidecar.is_enabled():
			use_sidecar = await sidecar.check_health()

		if use_sidecar:
			side_res = await sidecar.transcribe(audio_base64=req.audio_base64, audio_format=req.audio_format, language=req.language or "en")
			if bool(side_res.get("success", False)):
				text = str(side_res.get("text", "")).strip()
			else:
				raise HTTPException(status_code=502, detail=str(side_res.get("error", "sidecar_transcribe_failed")))
		else:
			whisper_ready, whisper_error = whisper_runtime_status()
			if not whisper_ready:
				raise HTTPException(
					status_code=503,
					detail=f"STT unavailable: {whisper_error}",
				)
			# Whisper transcription is CPU/GPU-heavy and must not block the event loop.
			text = await asyncio.to_thread(_whisper.transcribe_bytes, audio_bytes, req.audio_format, req.language)
		transcript_id, transcript_uri, transcript_hash = store.write_text("text.transcript", text, "txt")

		# Recording storage is opt-in and requires consent recorded in session metadata.
		# v0 policy: if session_id not provided, deny recording persistence.
		recording_artifact_id = None
		if req.save_recordings:
			if not req.session_id:
				raise HTTPException(status_code=400, detail="save_recordings requires session_id and consent")
			repo = getattr(request.app.state, "substrate_repo", None)
			if not repo or not hasattr(repo, "get_session"):
				raise HTTPException(status_code=503, detail="Substrate unavailable for consent check")
			sess = await repo.get_session(req.session_id)
			if not sess:
				raise HTTPException(status_code=404, detail="Session not found for consent check")
			meta = sess.get("metadata", {}) if isinstance(sess, dict) else {}
			consent = meta.get("consent", {}) if isinstance(meta, dict) else {}
			if not bool(consent.get("save_recordings", False)):
				raise HTTPException(status_code=403, detail="Recording persistence requires consent.save_recordings=true in session metadata")

			# Consent granted: persist the input recording as an artifact.
			ext = (req.audio_format or "wav").lstrip(".")
			recording_artifact_id, recording_uri, recording_hash = store.write_bytes("audio.input", audio_bytes, ext)

		repo = getattr(request.app.state, "substrate_repo", None)
		if repo:
			whisper_version = _best_effort_module_version("whisper")
			model_used = f"whisper-{getattr(_whisper, 'model_name', 'unknown')}"
			engine_name = "voice_sidecar" if use_sidecar else "whisper"
			engine_version = "unknown" if use_sidecar else whisper_version
			await repo.insert_artifact({
				"id": transcript_id,
				"artifact_type": "text.transcript",
				"uri": transcript_uri,
				"hash": transcript_hash,
				"metadata": {
					"input_audio_hash": input_hash,
					"model_used": model_used,
					"params": {
						"audio_format": req.audio_format,
						"language": req.language,
						"save_recordings": bool(req.save_recordings),
					},
					"engine": {"name": engine_name, "version": engine_version},
					"provenance": {
						"generated_by": "voice.transcribe",
						"session_id": req.session_id,
						"character": req.character,
						"character_mapping": req.character_mapping,
						"inputs": [{"type": "audio", "sha256": input_hash}],
					},
				},
			})

			# If input recording was stored (consent granted), index it too with provenance.
			if recording_artifact_id:
				await repo.insert_artifact({
					"id": recording_artifact_id,
					"artifact_type": "audio.input",
					"uri": recording_uri,
					"hash": recording_hash,
					"metadata": {
						"input_audio_hash": input_hash,
						"audio_format": req.audio_format,
						"provenance": {
							"generated_by": "voice.transcribe_input_audio",
							"session_id": req.session_id,
							"inputs": [{"type": "audio", "sha256": input_hash}],
							"consent": {"save_recordings": True},
						},
					},
				})
			await repo.commit()

		return {
			"ok": True,
			"text": text,
			"transcript_artifact_id": transcript_id,
			"transcript_url": transcript_uri,
			"recording_artifact_id": recording_artifact_id,
			"model_used": f"whisper-{getattr(_whisper, 'model_name', 'unknown')}",
		}
	except HTTPException:
		raise
	except Exception as e:
		log.exception("/voice/transcribe failed")
		raise HTTPException(status_code=500, detail=str(e))


