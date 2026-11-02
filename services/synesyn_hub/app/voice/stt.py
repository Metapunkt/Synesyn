from __future__ import annotations

import base64
import io
import logging
import os
from pathlib import Path
import sys
import tempfile
import wave
from dataclasses import dataclass
from typing import Optional, Tuple

try:
	import whisper  # type: ignore
	WHISPER_AVAILABLE: bool = True
	WHISPER_IMPORT_ERROR: Optional[str] = None
except Exception as e:
	# Whisper is an optional dependency. Hub packaging may exclude it to keep binaries small.
	# Voice STT routes must degrade gracefully instead of crashing the whole server at import-time.
	whisper = None  # type: ignore
	WHISPER_AVAILABLE = False
	WHISPER_IMPORT_ERROR = str(e)


log = logging.getLogger("synesyn_hub.voice.stt")


def bundled_model_dir() -> Optional[Path]:
	"""Directory of Whisper weights shipped inside a packaged build, if any.

	Whisper otherwise downloads its weights on first use into the user's cache.
	In a packaged --noconsole build that download runs inside a request the client
	is already awaiting, with no console and no progress, so a first-time user on
	a slow connection sees the hub hang rather than transcribe. Shipping the
	weights removes both the stall and the need for a network at all.
	"""
	meipass = getattr(sys, "_MEIPASS", None)
	if not meipass:
		return None
	candidate = Path(meipass) / "models"
	return candidate if candidate.is_dir() else None


def whisper_runtime_status() -> Tuple[bool, Optional[str]]:
	if not WHISPER_AVAILABLE or whisper is None:
		return False, (
			"optional dependency 'whisper' is unavailable: "
			f"{WHISPER_IMPORT_ERROR}"
		)
	module_file = getattr(whisper, "__file__", "")
	if not module_file:
		return False, "Whisper module path is unavailable"
	mel_filters = Path(module_file).resolve().parent / "assets" / "mel_filters.npz"
	if not mel_filters.is_file():
		return False, f"Whisper runtime asset is missing: {mel_filters}"
	return True, None


@dataclass
class WhisperBackend:
	model_name: str = "base"
	device: str = "cpu"
	_model = None

	def load(self) -> None:
		is_ready, runtime_error = whisper_runtime_status()
		if not is_ready:
			raise RuntimeError(f"Whisper STT unavailable: {runtime_error}")
		if self._model is None:
			model_dir = bundled_model_dir()
			log.info(
				"Loading Whisper model: %s (device=%s, weights=%s)",
				self.model_name,
				self.device,
				str(model_dir) if model_dir else "user cache",
			)
			self._model = whisper.load_model(
				self.model_name,
				device=self.device,
				download_root=str(model_dir) if model_dir else None,
			)

	def transcribe_bytes(self, audio_bytes: bytes, audio_format: str = "wav", language: Optional[str] = None) -> str:
		self.load()
		if (audio_format or "").lower().lstrip(".") == "wav":
			audio = self._decode_wav(audio_bytes)
			result = self._model.transcribe(audio, fp16=False, language=language)
			return str(result.get("text", "")).strip()
		with tempfile.NamedTemporaryFile(delete=False, suffix=f".{audio_format}") as f:
			f.write(audio_bytes)
			path = f.name
		try:
			result = self._model.transcribe(path, fp16=False, language=language)
			return str(result.get("text", "")).strip()
		finally:
			try:
				os.remove(path)
			except OSError:
				pass

	@staticmethod
	def _decode_wav(audio_bytes: bytes):
		import numpy as np

		with wave.open(io.BytesIO(audio_bytes), "rb") as wav_file:
			channel_count = int(wav_file.getnchannels())
			sample_width = int(wav_file.getsampwidth())
			sample_rate = int(wav_file.getframerate())
			frame_count = int(wav_file.getnframes())
			raw_frames = wav_file.readframes(frame_count)
		if sample_width != 2:
			raise ValueError(
				f"Unsupported WAV sample width: {sample_width * 8}-bit"
			)
		audio = np.frombuffer(raw_frames, dtype="<i2").astype(np.float32)
		audio /= 32768.0
		if channel_count > 1:
			audio = audio.reshape(-1, channel_count).mean(axis=1)
		if sample_rate != 16000 and audio.size > 0:
			target_size = max(1, int(round(audio.size * 16000 / sample_rate)))
			source_positions = np.linspace(0.0, 1.0, audio.size, endpoint=False)
			target_positions = np.linspace(0.0, 1.0, target_size, endpoint=False)
			audio = np.interp(
				target_positions,
				source_positions,
				audio,
			).astype(np.float32)
		return audio


def decode_base64_audio(audio_base64: str) -> bytes:
	return base64.b64decode(audio_base64)


