from __future__ import annotations

import asyncio
import logging
import os
import tempfile
import time
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple

try:
	import pyttsx3  # type: ignore
	PYTTSX3_AVAILABLE: bool = True
	PYTTSX3_IMPORT_ERROR: Optional[str] = None
except Exception as e:
	# Optional dependency: hub must boot even if SAPI TTS isn't packaged.
	pyttsx3 = None  # type: ignore
	PYTTSX3_AVAILABLE = False
	PYTTSX3_IMPORT_ERROR = str(e)

from .tts import EDGE_TTS_AVAILABLE, EDGE_TTS_IMPORT_ERROR, VoiceParams, synthesize_audio_bytes

log = logging.getLogger("synesyn_hub.voice.providers")


@dataclass(frozen=True)
class TtsResult:
	wav_bytes: bytes        # audio payload (may be WAV *or* MP3 depending on provider)
	duration_sec: float
	provider: str
	voice_used: str
	audio_format: str = "wav"   # "wav" | "mp3"


class EdgeTtsProvider:
	name = "edge_tts"

	async def speak(self, text: str, params: VoiceParams) -> TtsResult:
		if not EDGE_TTS_AVAILABLE:
			raise RuntimeError(f"edge_tts unavailable: {EDGE_TTS_IMPORT_ERROR}")
		audio_bytes, dur, fmt = await synthesize_audio_bytes(text, params)
		return TtsResult(wav_bytes=audio_bytes, duration_sec=dur, provider=self.name, voice_used=params.name, audio_format=fmt)


class SapiProvider:
	"""
	Windows fallback using SAPI via pyttsx3.
	This is not as high quality as Edge voices, but is robust and offline.
	"""

	name = "sapi"

	def __init__(self):
		# pyttsx3 engine is not async; initialize lazily per call for safety.
		pass

	def _sync_speak_to_wav(self, text: str, voice_name: Optional[str] = None, rate: Optional[int] = None) -> Tuple[bytes, float, str]:
		if not PYTTSX3_AVAILABLE:
			raise RuntimeError(f"pyttsx3 unavailable: {PYTTSX3_IMPORT_ERROR}")
		engine = pyttsx3.init()
		try:
			if rate is not None:
				engine.setProperty("rate", rate)
			# Optional: attempt to select a specific SAPI voice by substring match
			voice_used = "sapi_default"
			if voice_name:
				for v in engine.getProperty("voices"):
					if voice_name.lower() in (v.name or "").lower() or voice_name.lower() in (v.id or "").lower():
						engine.setProperty("voice", v.id)
						voice_used = v.name or v.id
						break

			with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as f:
				wav_path = f.name

			engine.save_to_file(text, wav_path)
			engine.runAndWait()

			data = open(wav_path, "rb").read()
			# Duration calc: cheap approximation by parsing WAV header is possible; keep 0 for v0.
			return data, 0.0, voice_used
		finally:
			try:
				engine.stop()
			except Exception:
				pass
			try:
				engine = None
			except Exception:
				pass
			try:
				if "wav_path" in locals() and os.path.exists(wav_path):
					os.remove(wav_path)
			except Exception:
				pass

	async def speak(self, text: str, params: VoiceParams) -> TtsResult:
		# Map Edge-style rate string to a coarse SAPI rate integer (optional; keep default for v0)
		wav_bytes, dur, voice_used = await asyncio.to_thread(self._sync_speak_to_wav, text, None, None)
		return TtsResult(wav_bytes=wav_bytes, duration_sec=dur, provider=self.name, voice_used=voice_used)


class ProviderChain:
	def __init__(self):
		self.edge = EdgeTtsProvider()
		self.sapi = SapiProvider()
		self.edge_ok: Optional[bool] = None
		self.last_edge_error: Optional[str] = None
		self.last_edge_error_ts: Optional[float] = None
		self.last_provider_used: Optional[str] = None

	async def speak(self, text: str, params: VoiceParams) -> TtsResult:
		# Try Edge first, fallback to SAPI on any failure.
		try:
			res = await self.edge.speak(text, params)
			self.edge_ok = True
			self.last_edge_error = None
			self.last_edge_error_ts = None
			self.last_provider_used = res.provider
			log.info("edge_tts succeeded for voice=%s", params.name)
			return res
		except Exception as e:
			self.edge_ok = False
			self.last_edge_error = str(e)
			self.last_edge_error_ts = time.time()
			log.warning("edge_tts FAILED (falling back to SAPI): %s", e, exc_info=True)
			res = await self.sapi.speak(text, params)
			self.last_provider_used = res.provider
			return res

	async def speak_with_preference(self, text: str, params: VoiceParams, preference: str | None = None) -> TtsResult:
		pref = (preference or "auto").strip().lower()
		if pref in ("", "auto"):
			return await self.speak(text, params)
		if pref in ("edge", "edge_tts", "edgetts"):
			res = await self.edge.speak(text, params)
			self.edge_ok = True
			self.last_edge_error = None
			self.last_edge_error_ts = None
			self.last_provider_used = res.provider
			return res
		if pref in ("sapi", "pyttsx3"):
			res = await self.sapi.speak(text, params)
			self.last_provider_used = res.provider
			return res
		if pref in ("sidecar", "voice_sidecar"):
			raise RuntimeError("provider_preference=sidecar must be handled by sidecar routing")
		raise RuntimeError(f"unknown provider_preference: {preference}")

	def status(self) -> Dict[str, Any]:
		return {
			"edge_available": bool(EDGE_TTS_AVAILABLE),
			"edge_import_error": EDGE_TTS_IMPORT_ERROR,
			"sapi_available": bool(PYTTSX3_AVAILABLE),
			"sapi_import_error": PYTTSX3_IMPORT_ERROR,
			"edge_ok": self.edge_ok,
			"last_edge_error": self.last_edge_error,
			"last_edge_error_ts": self.last_edge_error_ts,
			"last_provider_used": self.last_provider_used,
		}

	async def self_test_edge(self, voice_name: str = "en-US-AriaNeural") -> None:
		"""
		Best-effort Edge-only probe so the UI can immediately show whether Edge voices are usable.
		Does NOT fall back to SAPI; it only updates status fields.
		"""
		import ssl as _ssl
		log.info("edge_tts self-test starting (SSL_CERT_FILE=%s)", os.environ.get("SSL_CERT_FILE", "<unset>"))
		try:
			ctx = _ssl.create_default_context()
			log.info("SSL default context: ca_certs loaded=%s", bool(ctx.get_ca_certs()))
		except Exception:
			pass
		try:
			params = VoiceParams(name=voice_name)
			# very short probe; discard bytes
			await self.edge.speak("ok", params)
			self.edge_ok = True
			self.last_edge_error = None
			self.last_edge_error_ts = None
			log.info("edge_tts self-test PASSED")
		except Exception as e:
			self.edge_ok = False
			self.last_edge_error = str(e)
			self.last_edge_error_ts = time.time()
			log.warning("edge_tts self-test FAILED: %s", e, exc_info=True)


