from __future__ import annotations

import pytest

from app.substrate.workshop_artifacts import (
	WORKSHOP_SPECIALIST_TRACE_TYPE,
	read_workshop_specialist_trace,
	validate_workshop_artifact,
)


def trace_payload() -> dict:
	return {
		"schema_version": 1,
		"session_id": "sess_stage5",
		"turn_id": "turn_000001",
		"specialist_roles": ["risk_feasibility", "institutional_dynamics"],
		"contributions": [
			{
				"role_id": "risk_feasibility",
				"role_title": "Risk & Feasibility Analyst",
				"summary": "A concise risk summary.",
				"created_at": "2026-07-11T00:00:01Z",
			},
			{
				"role_id": "institutional_dynamics",
				"role_title": "Institutional Dynamics Analyst",
				"summary": "A concise institutional summary.",
				"created_at": "2026-07-11T00:00:01Z",
			},
		],
		"model_id": "test-model",
		"started_at": "2026-07-11T00:00:00Z",
		"completed_at": "2026-07-11T00:00:01Z",
		"synthesis_reference": {
			"sender": "Session Record",
			"story_log_index": 2,
			"message_hash": "abc123",
		},
		"privacy": {
			"classification": "workshop_participant_visible_on_request",
			"contains_chain_of_thought": False,
			"contains_credentials": False,
		},
		"retention": {
			"status": "retained_local_pending_hub",
			"scope": "session",
			"revocable_display": True,
		},
		"status": "complete",
		"failure_reason": "",
		"persistence_status": "pending",
	}


def test_specialist_trace_round_trip_matches_stage5_writer() -> None:
	validated = validate_workshop_artifact(
		WORKSHOP_SPECIALIST_TRACE_TYPE,
		trace_payload(),
	)

	assert read_workshop_specialist_trace(validated) == validated
	assert validated["synthesis_reference"]["sender"] == "Session Record"


def test_specialist_trace_v2_retains_safe_map_extraction() -> None:
	payload = trace_payload()
	payload["schema_version"] = 2
	payload["map_candidate_extraction"] = {
		"schema_version": 1,
		"accepted": [
			{
				"id": "candidate-1",
				"category": "cause",
				"proposition": "Fragmented procurement drives supply instability.",
				"source_class": "ai_inferred",
				"source_refs": ["turn-1"],
				"rationale": "Concise retained basis.",
				"confidence": 0.7,
				"evidence_status": "unsupported",
			},
		],
		"rejected": [{"reason": "facilitation_or_meta_guidance", "id": "meta-1"}],
		"facilitator_cues": ["Ask for the missing threshold."],
	}

	validated = validate_workshop_artifact(WORKSHOP_SPECIALIST_TRACE_TYPE, payload)

	assert validated["map_candidate_extraction"]["accepted"][0]["category"] == "cause"
	assert read_workshop_specialist_trace(validated) == validated


def test_specialist_trace_v2_rejects_malformed_map_extraction() -> None:
	payload = trace_payload()
	payload["schema_version"] = 2
	payload["map_candidate_extraction"] = {
		"schema_version": 1,
		"accepted": [
			{
				"id": "candidate-1",
				"category": "instruction",
				"proposition": "Ask the group to decide.",
				"source_class": "ai_inferred",
				"source_refs": ["turn-1"],
				"confidence": 0.7,
				"evidence_status": "unsupported",
			},
		],
		"rejected": [],
		"facilitator_cues": [],
	}

	with pytest.raises(ValueError, match="category is invalid"):
		validate_workshop_artifact(WORKSHOP_SPECIALIST_TRACE_TYPE, payload)


def test_specialist_trace_rejects_sensitive_or_misaligned_content() -> None:
	chain_of_thought = trace_payload()
	chain_of_thought["privacy"]["contains_chain_of_thought"] = True
	with pytest.raises(ValueError, match="chain-of-thought"):
		validate_workshop_artifact(WORKSHOP_SPECIALIST_TRACE_TYPE, chain_of_thought)

	misaligned = trace_payload()
	misaligned["specialist_roles"].reverse()
	with pytest.raises(ValueError, match="match contribution order"):
		validate_workshop_artifact(WORKSHOP_SPECIALIST_TRACE_TYPE, misaligned)

	credentials = trace_payload()
	credentials["contributions"][0]["api_key"] = "secret"
	with pytest.raises(ValueError, match="cannot contain"):
		validate_workshop_artifact(WORKSHOP_SPECIALIST_TRACE_TYPE, credentials)


def test_specialist_trace_requires_truthful_degraded_status() -> None:
	degraded = trace_payload()
	degraded["status"] = "degraded"
	degraded["failure_reason"] = "malformed_json"
	assert (
		validate_workshop_artifact(WORKSHOP_SPECIALIST_TRACE_TYPE, degraded)["status"]
		== "degraded"
	)

	degraded["failure_reason"] = ""
	with pytest.raises(ValueError, match="requires a failure_reason"):
		validate_workshop_artifact(WORKSHOP_SPECIALIST_TRACE_TYPE, degraded)

	prematurely_persisted = trace_payload()
	prematurely_persisted["persistence_status"] = "persisted"
	with pytest.raises(ValueError, match="must be pending"):
		validate_workshop_artifact(
			WORKSHOP_SPECIALIST_TRACE_TYPE,
			prematurely_persisted,
		)
