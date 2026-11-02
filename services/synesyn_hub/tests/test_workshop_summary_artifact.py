from __future__ import annotations

from copy import deepcopy

import pytest

from app.substrate.workshop_artifacts import (
	WORKSHOP_SUMMARY_TYPE,
	read_workshop_summary,
	validate_workshop_artifact,
)


def summary_payload(previous_version_id: str = "") -> dict:
	return {
		"schema_version": 1,
		"session_id": "sess_stage7",
		"review_status": "facilitator_reviewed",
		"proposal_status": "review_complete",
		"decisions": [_item("wsi_decision", "Adopt the reviewed option.")],
		"risks": [_item("wsi_risk", "Delivery capacity remains constrained.")],
		"open_questions": [_item("wsi_question", "Who approves the exception?")],
		"owners": [_item("wsi_owner", "Programme lead")],
		"next_steps": [_item("wsi_next", "Publish the implementation brief.")],
		"proposal_decisions": [
			{
				"proposal_id": "wsp_accepted",
				"decision": "accepted",
				"original_text": "Adopt the reviewed option.",
				"reviewed_text": "",
				"reviewed_by": "Facilitator",
				"reviewed_at": "2026-07-11T00:00:00Z",
			},
			{
				"proposal_id": "wsp_rejected",
				"decision": "rejected",
				"original_text": "Automatically close the workshop.",
				"reviewed_text": "",
				"reviewed_by": "Facilitator",
				"reviewed_at": "2026-07-11T00:01:00Z",
			},
		],
		"facilitator_provenance": {
			"reviewed_by": "Facilitator",
			"authorship_kind": "user_authored",
			"reviewed_at": "2026-07-11T00:02:00Z",
		},
		"previous_version_id": previous_version_id,
		"closure_refs": ["art_closure_1"],
	}


def _item(item_id: str, text: str) -> dict:
	return {
		"id": item_id,
		"text": text,
		"provenance_refs": [],
		"provenance": {
			"authorship_kind": "user_authored",
			"origin_ref": "facilitator",
			"review_status": "reviewed",
		},
		"reviewed_by": "Facilitator",
		"facilitator_edited": True,
		"updated_at": "2026-07-11T00:00:00Z",
	}


def test_summary_validator_round_trip_and_lineage() -> None:
	first = validate_workshop_artifact(WORKSHOP_SUMMARY_TYPE, summary_payload())
	second_payload = summary_payload("art_summary_v1")
	second = read_workshop_summary(second_payload)

	assert first["previous_version_id"] == ""
	assert second == second_payload
	assert second["previous_version_id"] == "art_summary_v1"
	assert second["proposal_decisions"][1]["decision"] == "rejected"


@pytest.mark.parametrize(
	"mutation",
	[
		lambda value: value.update({"review_status": "model_reviewed"}),
		lambda value: value["decisions"].append(deepcopy(value["risks"][0])),
		lambda value: value["proposal_decisions"][0].update({"decision": "auto_merged"}),
		lambda value: value["facilitator_provenance"].pop("reviewed_by"),
		lambda value: value.update({"api_key": "secret"}),
	],
)
def test_summary_validator_rejects_invalid_or_unsafe_payloads(mutation) -> None:
	payload = summary_payload()
	mutation(payload)

	with pytest.raises(ValueError):
		validate_workshop_artifact(WORKSHOP_SUMMARY_TYPE, payload)
