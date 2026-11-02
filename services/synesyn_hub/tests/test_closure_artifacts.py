"""Contract tests for the two closure artifact types (ADR 0026).

The payload builders below mirror what the real producers emit, so that a change
in either client stops here rather than in a facilitator's session.
"""

from copy import deepcopy

import pytest

from app.substrate.closure_artifacts import (
	SYNAXES_CLOSURE_TYPE,
	WORKSHOP_CLOSURE_TYPE,
	validate_closure_artifact,
)


def synaxes_closure_payload(schema_version: int = 1) -> dict:
	"""Mirrors synaxes_closure_controller.gd commit_closure()."""
	payload = {
		"schema_version": schema_version,
		"name": "Care work under automation",
		"intent": "Track where the argument is thinning out",
		"selection": {
			"pattern_ids": ["p1"],
			"item_ids": ["i1", "i2"],
			"context_graph_artifact_id": "ctx-1",
			"projection_artifact_id": "proj-1",
			"cluster_artifact_id": "clust-1",
			"analysis_run_artifact_id": "run-1",
		},
		"time_window": {"start": "2026-01-01", "end": "2026-02-01"},
	}
	if schema_version == 2:
		payload["orientation"] = {"quadrant": "B"}
	return payload


def session_record_capture_payload() -> dict:
	"""Mirrors workshop_catalyst_session_record.gd, after emitter mapping."""
	return {
		"schema_version": 1,
		"session_type_id": "workshop_catalyst",
		"scenario_id": "clinic_rollout",
		"scenario_name": "Clinic Rollout",
		"kind": "decision",
		"statement": "Pilot in two clinics before the regional rollout.",
		"owner": "Operations lead",
		"confidence": "Medium",
		"voters_yes": ["Ada", "Bo"],
		"voters_no": ["Cy"],
		"outcome": "yes",
		"reason": "Plurality (Yes)",
		"trigger": "facilitator_vote",
		"stage_name": "Decide",
		"stage_turn": 4,
		"session_turn": -1,
		"source_log_index_open": 11,
		"source_log_index_close": 18,
		"human_commit": {
			"committed_by": "scensyn.closure_bus",
			"decision": "yes",
			"voters_yes": ["Ada", "Bo"],
			"voters_no": ["Cy"],
			"captured_at_unix": 1789000000.0,
		},
	}


def compare_paths_capture_payload() -> dict:
	"""Mirrors workshop_path_persistence_coordinator.gd, after emitter mapping."""
	return {
		"schema_version": 1,
		"session_type_id": "workshop_catalyst",
		"scenario_id": "clinic_rollout",
		"kind": "workshop_path_set",
		"statement": "Staged rollout with an explicit stop condition",
		"outcome": "committed",
		"reason": "Explicit facilitator Compare Paths commit",
		"trigger": "compare_paths_commit",
		"artifact_id": "art-42",
		"path_ids": ["path-a", "path-b"],
		"selection_kind": "combined",
		"store_trace_ids": [],
		"previous_version_id": "",
		"human_commit": {
			"committed_by": "scensyn.closure_bus",
			"decision": "committed",
			"voters_yes": [],
			"voters_no": [],
			"captured_at_unix": 1789000100.0,
		},
	}


def thinking_map_capture_payload() -> dict:
	"""Mirrors workshop_catalyst_controller.gd, after emitter mapping."""
	return {
		"schema_version": 1,
		"session_type_id": "workshop_catalyst",
		"scenario_id": "clinic_rollout",
		"scenario_name": "Clinic Rollout",
		"kind": "risk",
		"statement": "Staffing cover is unresolved for the second clinic.",
		"owner": "Facilitator",
		"outcome": "yes",
		"reason": "Explicit facilitator Thinking Map action",
		"trigger": "thinking_map_facilitator_route",
		"stage_name": "Map",
		"thinking_map_item_id": "node-7",
		"thinking_map_artifact_id": "map-3",
		"human_commit": {
			"committed_by": "scensyn.closure_bus",
			"decision": "yes",
			"voters_yes": [],
			"voters_no": [],
			"captured_at_unix": 1789000200.0,
		},
	}


# ── SynAxes closures ──────────────────────────────────────────────────────


@pytest.mark.parametrize("schema_version", [1, 2])
def test_synaxes_closure_accepts_both_versions(schema_version) -> None:
	payload = synaxes_closure_payload(schema_version)
	validated = validate_closure_artifact(SYNAXES_CLOSURE_TYPE, deepcopy(payload))
	assert validated["name"] == payload["name"]
	assert validated["schema_version"] == schema_version


def test_synaxes_closure_v2_requires_an_orientation_quadrant() -> None:
	payload = synaxes_closure_payload(2)
	del payload["orientation"]
	with pytest.raises(ValueError, match="orientation"):
		validate_closure_artifact(SYNAXES_CLOSURE_TYPE, payload)


def test_synaxes_closure_rejects_unknown_quadrant() -> None:
	payload = synaxes_closure_payload(2)
	payload["orientation"] = {"quadrant": "E"}
	with pytest.raises(ValueError, match="quadrant"):
		validate_closure_artifact(SYNAXES_CLOSURE_TYPE, payload)


@pytest.mark.parametrize(
	"mutation",
	[
		{"schema_version": "1.0"},
		{"schema_version": 3},
		{"schema_version": True},
		{"name": "   "},
		{"selection": []},
		{"time_window": "2026"},
	],
)
def test_synaxes_closure_rejects_malformed_payloads(mutation) -> None:
	payload = synaxes_closure_payload()
	payload.update(mutation)
	with pytest.raises(ValueError):
		validate_closure_artifact(SYNAXES_CLOSURE_TYPE, payload)


def test_synaxes_closure_rejects_a_session_capture_and_names_the_right_type() -> None:
	"""The regression this split exists to prevent."""
	with pytest.raises(ValueError, match=WORKSHOP_CLOSURE_TYPE):
		validate_closure_artifact(SYNAXES_CLOSURE_TYPE, session_record_capture_payload())


# ── Session captures ──────────────────────────────────────────────────────


@pytest.mark.parametrize(
	"builder",
	[
		session_record_capture_payload,
		compare_paths_capture_payload,
		thinking_map_capture_payload,
	],
)
def test_workshop_closure_accepts_every_real_producer(builder) -> None:
	payload = builder()
	validated = validate_closure_artifact(WORKSHOP_CLOSURE_TYPE, deepcopy(payload))
	assert validated["statement"] == payload["statement"]
	assert validated["outcome"] == payload["outcome"]


def test_workshop_closure_outcome_vocabulary_is_not_constrained() -> None:
	"""Votes say yes/no, a Compare Paths commit says committed; both are valid."""
	outcomes = {
		session_record_capture_payload()["outcome"],
		compare_paths_capture_payload()["outcome"],
	}
	assert outcomes == {"yes", "committed"}


@pytest.mark.parametrize(
	"mutation",
	[
		{"schema_version": "1.0"},
		{"schema_version": 2},
		{"statement": "  "},
		{"kind": ""},
		{"session_type_id": ""},
		{"outcome": ""},
		{"voters_yes": "Ada"},
		{"human_commit": {}},
		{"human_commit": "scensyn"},
	],
)
def test_workshop_closure_rejects_malformed_payloads(mutation) -> None:
	payload = session_record_capture_payload()
	payload.update(mutation)
	with pytest.raises(ValueError):
		validate_closure_artifact(WORKSHOP_CLOSURE_TYPE, payload)


# ── Shared behaviour ──────────────────────────────────────────────────────


@pytest.mark.parametrize(
	"artifact_type,builder",
	[
		(SYNAXES_CLOSURE_TYPE, synaxes_closure_payload),
		(WORKSHOP_CLOSURE_TYPE, session_record_capture_payload),
	],
)
def test_closures_cannot_carry_credentials_or_audio(artifact_type, builder) -> None:
	payload = builder()
	payload["api_key"] = "sk-live-should-never-persist"
	with pytest.raises(ValueError):
		validate_closure_artifact(artifact_type, payload)


def test_unrelated_artifact_types_pass_through_untouched() -> None:
	payload = {"anything": "at all"}
	assert validate_closure_artifact("json.notes", payload) is payload


def test_route_validator_composition_reaches_closure_validation() -> None:
	"""Mirrors how create_artifact chains the two seams.

	The workshop validator runs first and must pass closure types through so the
	closure validator still sees them; otherwise a malformed closure would be
	stored unchecked.
	"""
	from app.substrate.workshop_artifacts import validate_workshop_artifact

	def as_route_does(artifact_type: str, payload: dict) -> dict:
		return validate_closure_artifact(
			artifact_type,
			validate_workshop_artifact(artifact_type, payload),
		)

	assert as_route_does(SYNAXES_CLOSURE_TYPE, synaxes_closure_payload())["schema_version"] == 1
	assert as_route_does(WORKSHOP_CLOSURE_TYPE, session_record_capture_payload())["outcome"] == "yes"
	with pytest.raises(ValueError):
		as_route_does(SYNAXES_CLOSURE_TYPE, session_record_capture_payload())
