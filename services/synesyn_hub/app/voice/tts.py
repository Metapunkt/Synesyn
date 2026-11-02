from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Optional, Tuple

try:
	import edge_tts  # type: ignore
	EDGE_TTS_AVAILABLE: bool = True
	EDGE_TTS_IMPORT_ERROR: Optional[str] = None
except Exception as e:
	# Optional dependency: hub must boot even if edge-tts isn't packaged.
	edge_tts = None  # type: ignore
	EDGE_TTS_AVAILABLE = False
	EDGE_TTS_IMPORT_ERROR = str(e)


log = logging.getLogger("synesyn_hub.voice.tts")


@dataclass(frozen=True)
class VoiceParams:
	name: str
	rate: str = "+0%"
	volume: str = "+0%"
	pitch: str = "+0Hz"


async def synthesize_audio_bytes(text: str, params: VoiceParams) -> Tuple[bytes, float, str]:
	"""
	Generate audio bytes, duration seconds, and format string using edge-tts.

	Returns:
		(audio_bytes, duration_sec, fmt) where fmt is ``"wav"`` or ``"mp3"``.

	edge-tts 7.x no longer accepts an ``output_format`` constructor arg and
	always returns MP3 (24 kHz / 48 kbps / mono).  We collect the MP3 bytes
	from ``stream()`` and return them as-is; the caller/client is responsible
	for playing the correct format.
	"""
	if not EDGE_TTS_AVAILABLE:
		raise RuntimeError(f"edge-tts unavailable (missing optional dependency 'edge_tts'): {EDGE_TTS_IMPORT_ERROR}")

	communicate = edge_tts.Communicate(
		text=text,
		voice=params.name,
		rate=params.rate,
		volume=params.volume,
		pitch=params.pitch,
	)

	audio_bytes = b""
	async for chunk in communicate.stream():
		# TTSChunk supports dict-like access: chunk["type"], chunk["data"]
		try:
			if chunk["type"] == "audio":
				audio_bytes += bytes(chunk["data"])
		except (KeyError, TypeError):
			continue

	if not audio_bytes:
		raise RuntimeError("edge-tts returned zero audio bytes")

	# Best-effort duration estimate for MP3.
	# MP3 at 48 kbps mono → bytes_per_sec ≈ 6000.  Very rough but better than 0.
	duration = len(audio_bytes) / 6000.0

	log.info(
		"edge-tts synthesized %d bytes (mp3, ~%.1fs) for voice=%s",
		len(audio_bytes), duration, params.name,
	)
	return audio_bytes, duration, "mp3"


# ── Legacy alias kept so callers that still import the old name get a
#    clear error rather than an ImportError at module level.
async def synthesize_wav_bytes(text: str, params: VoiceParams) -> Tuple[bytes, float]:
	"""Deprecated wrapper — prefer synthesize_audio_bytes()."""
	audio, dur, _fmt = await synthesize_audio_bytes(text, params)
	return audio, dur

 
