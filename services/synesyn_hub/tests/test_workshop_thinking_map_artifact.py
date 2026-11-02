from __future__ import annotations

from copy import deepcopy

import pytest

from app.substrate.workshop_artifacts import (
	WORKSHOP_THINKING_MAP_TYPE,
	read_workshop_thinking_map,
	validate_workshop_artifact,
)


def map_payload(previous_version_id: str = "") -> dict:
	return {
		"schema_version": 1,
		"graph_schema_version": 1,
		"graph_kind": "workshop_thinking_map",
		"name": "Workshop Thinking Map",
		"session_id": "sess_stage8",
		"scenario_id": "scenario",
		"session_type_id": "workshop_catalyst",
		"collection_id": "decision_triage",
		"previous_version_id": previous_version_id,
		"nodes": [
			_node("cause-1", "cause", "Participant statement", "participant_said", "Participant said"),
			_node("effect-1", "effect", "Possible consequence", "ai_inferred", "AI inferred"),
		],
		"edges": [
			{
				"id": "edge-1",
				"from": "cause-1",
				"to": "effect-1",
				"relation": "causes",
				"status": "accepted",
				"confidence": 0.7,
				"provenance_refs": ["trace-1"],
				"provenance": {"review_status": "reviewed"},
			}
		],
		"proposal_decisions": [
			{
				"record_id": "cause-1",
				"decision": "accepted",
				"reviewed_by": "Facilitator",
				"reviewed_at": "2026-07-11T00:00:00Z",
			}
		],
		"facilitator_provenance": {
			"reviewed_by": "Facilitator",
			"authorship_kind": "user_reviewed",
			"reviewed_at": "2026-07-11T00:01:00Z",
		},
	}


def _node(node_id: str, kind: str, label: str, source_class: str, source_label: str) -> dict:
	return {
		"id": node_id,
		"kind": kind,
		"label": label,
		"status": "accepted",
		"annotations": {
			"column": kind,
			"source_class": source_class,
			"source_label": source_label,
		},
		"provenance_refs": ["segment-1"],
		"provenance": {
			"author_id": "Participant",
			"produced_by": "scensyn.workshop_thinking_map@1",
			"created_at": "2026-07-11T00:00:00Z",
			"review_status": "reviewed",
			"evidence_status": "unsupported" if source_class == "ai_inferred" else "unknown",
		},
	}


def test_thinking_map_round_trip_and_lineage() -> None:
	first = validate_workshop_artifact(WORKSHOP_THINKING_MAP_TYPE, map_payload())
	second_payload = map_payload("art_map_v1")
	second = read_workshop_thinking_map(second_payload)

	assert first["graph_kind"] == "workshop_thinking_map"
	assert second == second_payload
	assert second["previous_version_id"] == "art_map_v1"
	assert second["nodes"][1]["annotations"]["source_label"] == "AI inferred"


@pytest.mark.parametrize(
	"mutation",
	[
		lambda value: value.update({"graph_kind": "context_graph"}),
		lambda value: value["nodes"][1]["annotations"].update({"source_label": "Participant said"}),
		lambda value: value["edges"][0].update({"to": "missing"}),
		lambda value: value["proposal_decisions"][0].update({"decision": "auto_committed"}),
		lambda value: value.update({"api_key": "secret"}),
	],
)
def test_thinking_map_rejects_cross_contract_or_unsafe_payloads(mutation) -> None:
	payload = deepcopy(map_payload())
	mutation(payload)

	with pytest.raises(ValueError):
		validate_workshop_artifact(WORKSHOP_THINKING_MAP_TYPE, payload)
