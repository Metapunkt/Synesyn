from __future__ import annotations

import unittest

from app.substrate.workshop_artifacts import (
	WORKSHOP_TRANSCRIPT_TYPE,
	read_workshop_transcript_segment,
	validate_workshop_artifact,
)


def original_payload() -> dict:
	return {
		"schema_version": 1,
		"version_id": "seg_1_v1",
		"session_id": "sess_1",
		"segment_id": "seg_1",
		"origin": "user",
		"capture_started_at": "2026-07-11T00:00:00Z",
		"capture_completed_at": "2026-07-11T00:00:01Z",
		"created_at": "2026-07-11T00:00:01Z",
		"original_text": "Original spoken text.",
		"submitted_text": "Original spoken text.",
		"provider": {"provider_id": "hub", "model_id": "whisper-base"},
		"consent": {"voice_transcription": True, "save_recordings": False},
		"retention": {
			"classification": "session_transcript",
			"transcript_retained": True,
			"raw_audio_retained": False,
		},
		"previous_version_id": "",
		"corrected_text": "",
		"correction_reason": "",
		"source_audio_artifact_id": "",
	}


class WorkshopTranscriptArtifactTests(unittest.TestCase):
	def test_original_and_correction_round_trip_preserve_lineage(self) -> None:
		original = validate_workshop_artifact(WORKSHOP_TRANSCRIPT_TYPE, original_payload())
		corrected = dict(original)
		corrected.update(
			{
				"version_id": "seg_1_v2",
				"previous_version_id": original["version_id"],
				"corrected_text": "Corrected spoken text.",
				"correction_reason": "Speaker clarified the product name.",
				"corrected_at": "2026-07-11T00:01:00Z",
				"created_at": "2026-07-11T00:01:00Z",
			}
		)
		round_tripped = validate_workshop_artifact(WORKSHOP_TRANSCRIPT_TYPE, corrected)
		self.assertEqual(round_tripped["original_text"], "Original spoken text.")
		self.assertEqual(round_tripped["submitted_text"], "Original spoken text.")
		self.assertEqual(round_tripped["corrected_text"], "Corrected spoken text.")
		self.assertEqual(round_tripped["previous_version_id"], "seg_1_v1")

	def test_rejects_silent_rewrite_and_sensitive_audio_payloads(self) -> None:
		silent_rewrite = original_payload()
		silent_rewrite["corrected_text"] = "Changed without lineage."
		with self.assertRaisesRegex(ValueError, "Original Workshop transcript"):
			validate_workshop_artifact(WORKSHOP_TRANSCRIPT_TYPE, silent_rewrite)
		raw_audio = original_payload()
		raw_audio["audio_base64"] = "secret-bytes"
		with self.assertRaisesRegex(ValueError, "cannot contain"):
			validate_workshop_artifact(WORKSHOP_TRANSCRIPT_TYPE, raw_audio)

	def test_compatibility_reader_normalizes_draft_timestamp(self) -> None:
		legacy = original_payload()
		legacy.pop("capture_started_at")
		legacy.pop("capture_completed_at")
		legacy["captured_at"] = "2026-07-11T00:00:00Z"
		normalized = read_workshop_transcript_segment(legacy)
		self.assertEqual(normalized["capture_started_at"], legacy["captured_at"])
		self.assertEqual(normalized["capture_completed_at"], legacy["captured_at"])


if __name__ == "__main__":
	unittest.main()
