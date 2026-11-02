from __future__ import annotations

import io
import unittest
import wave
from pathlib import Path
from unittest.mock import Mock, patch

import numpy as np

from app.voice import stt
from app.voice.stt import WhisperBackend, whisper_runtime_status


def wav_bytes(sample_rate: int = 8000) -> bytes:
	buffer = io.BytesIO()
	with wave.open(buffer, "wb") as wav_file:
		wav_file.setnchannels(1)
		wav_file.setsampwidth(2)
		wav_file.setframerate(sample_rate)
		samples = (np.sin(np.linspace(0, np.pi * 4, sample_rate)) * 12000)
		wav_file.writeframes(samples.astype("<i2").tobytes())
	return buffer.getvalue()


class FakeWhisperModel:
	def __init__(self) -> None:
		self.audio = None

	def transcribe(self, audio, **_kwargs):
		self.audio = audio
		return {"text": "captured speech"}


class StubWhisperBackend(WhisperBackend):
	def load(self) -> None:
		return


class VoiceSttTests(unittest.TestCase):
	def test_model_load_defaults_to_cpu(self) -> None:
		backend = WhisperBackend()
		fake_whisper = Mock()
		# bundled_model_dir() is patched so the assertion does not depend on
		# whether this machine happens to have bundled weights present.
		with (
			patch(
				"app.voice.stt.whisper_runtime_status",
				return_value=(True, None),
			),
			patch.object(stt, "bundled_model_dir", return_value=None),
			patch.object(stt, "whisper", fake_whisper),
		):
			backend.load()
		fake_whisper.load_model.assert_called_once_with(
			"base",
			device="cpu",
			download_root=None,
		)

	def test_model_load_uses_bundled_weights_when_present(self) -> None:
		backend = WhisperBackend()
		fake_whisper = Mock()
		with (
			patch(
				"app.voice.stt.whisper_runtime_status",
				return_value=(True, None),
			),
			patch.object(stt, "bundled_model_dir", return_value=Path("/opt/synesyn/whisper")),
			patch.object(stt, "whisper", fake_whisper),
		):
			backend.load()
		fake_whisper.load_model.assert_called_once_with(
			"base",
			device="cpu",
			download_root=str(Path("/opt/synesyn/whisper")),
		)

	def test_wav_decode_resamples_to_whisper_rate(self) -> None:
		audio = WhisperBackend._decode_wav(wav_bytes())
		self.assertEqual(audio.dtype, np.float32)
		self.assertEqual(audio.shape, (16000,))

	def test_wav_transcription_uses_in_memory_audio(self) -> None:
		backend = StubWhisperBackend()
		fake_model = FakeWhisperModel()
		backend._model = fake_model
		text = backend.transcribe_bytes(wav_bytes(), "wav", "en")
		self.assertEqual(text, "captured speech")
		self.assertEqual(fake_model.audio.shape, (16000,))

	def test_runtime_status_has_actionable_reason_when_unavailable(self) -> None:
		is_ready, error = whisper_runtime_status()
		if is_ready:
			self.assertIsNone(error)
		else:
			self.assertTrue(error)


if __name__ == "__main__":
	unittest.main()
