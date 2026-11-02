from copy import deepcopy

import pytest

from app.substrate.workshop_artifacts import (
	WORKSHOP_PATH_SET_TYPE,
	read_workshop_path_set,
	validate_workshop_artifact,
)


def path_set_payload(previous_version_id: str = "") -> dict:
	return {
		"schema_version": 1,
		"session_id": "sess-stage9",
		"scenario_id": "scenario",
		"session_type_id": "workshop_catalyst",
		"collection_id": "decision_triage",
		"review_status": "facilitator_reviewed",
		"proposal_status": "review_complete",
		"paths": [
			_path("path-act", "Pilot the change", False, ["chunk-1"]),
			_path("path-baseline", "Continue current course", True, []),
		],
		"proposal_decisions": [],
		"selection": {
			"kind": "single",
			"path_ids": ["path-act"],
			"label": "Pilot the change",
			"selected_by": "Facilitator",
			"selected_at": "2026-07-11T01:00:00Z",
		},
		"evidence_retrieval": {
			"status": "available",
			"trace_id": "ret-stage9",
			"context_pack_id": "ctx-stage9",
		},
		"store_trace_ids": ["ret-stage9"],
		"facilitator_provenance": {
			"reviewed_by": "Facilitator",
			"authorship_kind": "user_reviewed",
			"reviewed_at": "2026-07-11T01:01:00Z",
		},
		"previous_version_id": previous_version_id,
		"closure_ref": "",
	}


def _path(path_id: str, title: str, is_do_nothing: bool, ref_ids: list[str]) -> dict:
	refs = [
		{"id": ref_id, "title": f"Source {ref_id}", "excerpt": "", "source_uri": ""}
		for ref_id in ref_ids
	]
	return {
		"id": path_id,
		"title": title,
		"label": title,
		"outcomes": ["A stated outcome"],
		"biggest_risk": "A stated risk",
		"assumptions": ["A stated assumption"],
		"uncertainty": "Material uncertainty remains",
		"time_horizon": "Six months",
		"is_do_nothing": is_do_nothing,
		"evidence_refs": refs,
		"evidence_status": "supported" if refs else "none",
		"proposal_state": "proposal",
		"review_state": "accepted",
		"facilitator_edited": False,
		"provenance": {"authorship_kind": "proposal"},
		"created_at": "2026-07-11T00:00:00Z",
		"updated_at": "2026-07-11T00:01:00Z",
		"reviewed_at": "2026-07-11T00:01:00Z",
		"reviewed_by": "Facilitator",
		"previous_path_id": "",
	}


def test_path_set_round_trip_and_lineage() -> None:
	first = validate_workshop_artifact(WORKSHOP_PATH_SET_TYPE, path_set_payload())
	second_payload = path_set_payload("art-path-v1")
	second = read_workshop_path_set(second_payload)

	assert first["paths"][1]["evidence_status"] == "none"
	assert second == second_payload
	assert second["previous_version_id"] == "art-path-v1"
	assert sum(path["is_do_nothing"] for path in second["paths"]) == 1


@pytest.mark.parametrize(
	"mutation",
	[
		lambda value: value["paths"].append(deepcopy(value["paths"][1])),
		lambda value: value["paths"][1].update({"evidence_status": "supported"}),
		lambda value: value["selection"].update({"path_ids": ["missing"]}),
		lambda value: value.update({"closure_ref": "preclaimed"}),
		lambda value: value.update({"api_key": "secret"}),
	],
)
def test_path_set_rejects_unsafe_or_untruthful_payloads(mutation) -> None:
	payload = path_set_payload()
	mutation(payload)

	with pytest.raises(ValueError):
		validate_workshop_artifact(WORKSHOP_PATH_SET_TYPE, payload)
