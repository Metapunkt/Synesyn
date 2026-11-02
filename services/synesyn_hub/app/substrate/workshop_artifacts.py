from __future__ import annotations

from typing import Any, Dict


WORKSHOP_TRANSCRIPT_TYPE = "json.workshop_transcript_segment"
WORKSHOP_SPECIALIST_TRACE_TYPE = "json.workshop_specialist_trace"
WORKSHOP_SUMMARY_TYPE = "ui.workshop_summary"
WORKSHOP_THINKING_MAP_TYPE = "ui.workshop_thinking_map"
WORKSHOP_PATH_SET_TYPE = "ui.workshop_path_set"
_SUMMARY_CATEGORIES = (
	"decisions",
	"risks",
	"open_questions",
	"owners",
	"next_steps",
)
_PROPOSAL_DECISIONS = {"accepted", "edited", "rejected", "deferred"}
_GRAPH_STATUSES = {"committed", "suggested", "accepted", "edited", "rejected"}
_MAP_NODE_KINDS = {
	"cause", "effect", "opportunity", "question", "decision", "risk", "owner", "next_step"
}
_MAP_RELATIONS = {"causes", "supports", "contradicts", "evidenced_by", "related_to"}
_MAP_SOURCE_CLASSES = {
	"participant_said", "ai_inferred", "external_evidence_supported"
}
_FORBIDDEN_KEYS = {
	"audio_base64",
	"raw_audio",
	"raw_audio_base64",
	"credentials",
	"api_key",
	"authorization",
}


def validate_workshop_artifact(artifact_type: str, payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Validate and normalize Workshop artifacts accepted by the generic seam."""
	if artifact_type == WORKSHOP_SPECIALIST_TRACE_TYPE:
		return validate_workshop_specialist_trace(payload)
	if artifact_type == WORKSHOP_SUMMARY_TYPE:
		return validate_workshop_summary(payload)
	if artifact_type == WORKSHOP_THINKING_MAP_TYPE:
		return validate_workshop_thinking_map(payload)
	if artifact_type == WORKSHOP_PATH_SET_TYPE:
		return validate_workshop_path_set(payload)
	if artifact_type != WORKSHOP_TRANSCRIPT_TYPE:
		return payload
	normalized = read_workshop_transcript_segment(payload)
	_validate_no_forbidden_fields(normalized)
	_require_nonempty_strings(
		normalized,
		(
			"version_id",
			"session_id",
			"segment_id",
			"origin",
			"capture_started_at",
			"capture_completed_at",
			"created_at",
			"original_text",
			"submitted_text",
		),
	)
	if normalized["schema_version"] != 1:
		raise ValueError("Workshop transcript schema_version must be 1")
	if normalized["origin"] != "user":
		raise ValueError("Workshop transcript origin must be 'user'")
	for key in ("provider", "consent", "retention"):
		if not isinstance(normalized.get(key), dict):
			raise ValueError(f"Workshop transcript {key} must be an object")
	previous_version_id = str(normalized.get("previous_version_id", "")).strip()
	corrected_text = str(normalized.get("corrected_text", "")).strip()
	correction_reason = str(normalized.get("correction_reason", "")).strip()
	if previous_version_id:
		if not corrected_text or not correction_reason:
			raise ValueError(
				"Corrected Workshop transcript versions require corrected_text and correction_reason"
			)
		if str(normalized.get("corrected_at", "")).strip() == "":
			raise ValueError("Corrected Workshop transcript versions require corrected_at")
	elif corrected_text or correction_reason:
		raise ValueError("Original Workshop transcript version cannot contain correction fields")
	if bool(normalized["retention"].get("raw_audio_retained", False)):
		if not bool(normalized["consent"].get("save_recordings", False)):
			raise ValueError("Raw-audio retention requires explicit save_recordings consent")
	return normalized


def validate_workshop_specialist_trace(payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Validate a privacy-controlled, per-turn hidden-synthesis trace."""
	if not isinstance(payload, dict):
		raise ValueError("Workshop specialist trace payload must be an object")
	normalized = dict(payload)
	_validate_no_forbidden_fields(normalized)
	schema_version = normalized.get("schema_version")
	if schema_version not in {1, 2}:
		raise ValueError("Workshop specialist trace schema_version must be 1 or 2")
	_require_nonempty_strings(
		normalized,
		(
			"session_id",
			"turn_id",
			"model_id",
			"started_at",
			"completed_at",
			"status",
			"persistence_status",
		),
	)
	if normalized["status"] not in {"complete", "degraded"}:
		raise ValueError("Workshop specialist trace status is invalid")
	failure_reason = normalized.get("failure_reason", "")
	if not isinstance(failure_reason, str):
		raise ValueError("Workshop specialist trace failure_reason must be a string")
	if normalized["status"] == "degraded" and not failure_reason.strip():
		raise ValueError("Degraded Workshop specialist trace requires a failure_reason")
	if normalized["status"] == "complete" and failure_reason.strip():
		raise ValueError("Complete Workshop specialist trace cannot claim a failure_reason")
	if normalized["persistence_status"] != "pending":
		raise ValueError("New Workshop specialist trace persistence_status must be pending")

	roles = normalized.get("specialist_roles")
	contributions = normalized.get("contributions")
	if not isinstance(roles, list) or not roles or not all(
		isinstance(role_id, str) and role_id.strip() for role_id in roles
	):
		raise ValueError("Workshop specialist trace specialist_roles must contain role ids")
	if len(set(roles)) != len(roles):
		raise ValueError("Workshop specialist trace specialist_roles must be unique")
	if not isinstance(contributions, list) or not contributions:
		raise ValueError("Workshop specialist trace contributions must be a non-empty array")
	contribution_roles: list[str] = []
	for contribution in contributions:
		if not isinstance(contribution, dict):
			raise ValueError("Workshop specialist contribution must be an object")
		_require_nonempty_strings(
			contribution,
			("role_id", "role_title", "summary", "created_at"),
		)
		contribution_roles.append(contribution["role_id"])
	if contribution_roles != roles:
		raise ValueError("Workshop specialist trace roles must match contribution order")
	if schema_version == 2:
		_validate_map_candidate_extraction(normalized.get("map_candidate_extraction"))

	synthesis_reference = normalized.get("synthesis_reference")
	if not isinstance(synthesis_reference, dict):
		raise ValueError("Workshop specialist trace synthesis_reference must be an object")
	_require_nonempty_strings(synthesis_reference, ("sender", "message_hash"))
	if not isinstance(synthesis_reference.get("story_log_index"), int):
		raise ValueError("Workshop specialist trace story_log_index must be an integer")

	privacy = normalized.get("privacy")
	if not isinstance(privacy, dict):
		raise ValueError("Workshop specialist trace privacy must be an object")
	_require_nonempty_strings(privacy, ("classification",))
	if privacy.get("contains_chain_of_thought") is not False:
		raise ValueError("Workshop specialist trace cannot retain chain-of-thought")
	if privacy.get("contains_credentials") is not False:
		raise ValueError("Workshop specialist trace cannot retain credentials")

	retention = normalized.get("retention")
	if not isinstance(retention, dict):
		raise ValueError("Workshop specialist trace retention must be an object")
	_require_nonempty_strings(retention, ("status", "scope"))
	if retention["scope"] != "session":
		raise ValueError("Workshop specialist trace retention scope must be session")
	if not isinstance(retention.get("revocable_display"), bool):
		raise ValueError("Workshop specialist trace revocable_display must be boolean")
	return normalized


def read_workshop_specialist_trace(payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Compatibility reader and validator for Workshop specialist trace schemas."""
	return validate_workshop_specialist_trace(payload)


def _validate_map_candidate_extraction(extraction: Any) -> None:
	if not isinstance(extraction, dict) or extraction.get("schema_version") != 1:
		raise ValueError("Workshop map candidate extraction schema_version must be 1")
	accepted = extraction.get("accepted")
	rejected = extraction.get("rejected")
	facilitator_cues = extraction.get("facilitator_cues")
	if not isinstance(accepted, list) or not isinstance(rejected, list):
		raise ValueError("Workshop map candidate extraction arrays are required")
	if not isinstance(facilitator_cues, list) or not all(
		isinstance(cue, str) and cue.strip() for cue in facilitator_cues
	):
		raise ValueError("Workshop facilitator cues must contain non-empty strings")
	for candidate in accepted:
		if not isinstance(candidate, dict):
			raise ValueError("Workshop map candidate must be an object")
		_require_nonempty_strings(
			candidate,
			("id", "category", "proposition", "source_class", "evidence_status"),
		)
		if candidate["category"] not in {"cause", "effect", "opportunity"}:
			raise ValueError("Workshop map candidate category is invalid")
		if candidate["source_class"] not in {
			"participant_said",
			"ai_inferred",
			"external_evidence_supported",
		}:
			raise ValueError("Workshop map candidate source_class is invalid")
		source_refs = candidate.get("source_refs")
		if not isinstance(source_refs, list) or not source_refs or not all(
			isinstance(source_ref, str) and source_ref.strip()
			for source_ref in source_refs
		):
			raise ValueError("Workshop map candidate source_refs are invalid")
		confidence = candidate.get("confidence")
		if not isinstance(confidence, (int, float)) or not 0.0 <= confidence <= 1.0:
			raise ValueError("Workshop map candidate confidence is invalid")
	for rejection in rejected:
		if not isinstance(rejection, dict):
			raise ValueError("Workshop map candidate rejection must be an object")
		_require_nonempty_strings(rejection, ("reason",))


def validate_workshop_summary(payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Validate one immutable facilitator-reviewed Workshop summary snapshot."""
	if not isinstance(payload, dict):
		raise ValueError("Workshop summary payload must be an object")
	normalized = dict(payload)
	_validate_no_forbidden_fields(normalized)
	if normalized.get("schema_version") != 1:
		raise ValueError("Workshop summary schema_version must be 1")
	_require_nonempty_strings(
		normalized,
		("session_id", "review_status", "proposal_status"),
	)
	if normalized["review_status"] != "facilitator_reviewed":
		raise ValueError("Workshop summary must be facilitator_reviewed")
	if not isinstance(normalized.get("facilitator_provenance"), dict):
		raise ValueError("Workshop summary facilitator_provenance must be an object")
	_require_nonempty_strings(
		normalized["facilitator_provenance"],
		("reviewed_by", "authorship_kind", "reviewed_at"),
	)
	previous_version_id = normalized.get("previous_version_id", "")
	if not isinstance(previous_version_id, str):
		raise ValueError("Workshop summary previous_version_id must be a string")
	closure_refs = normalized.get("closure_refs", [])
	if not isinstance(closure_refs, list) or not all(
		isinstance(value, (str, dict)) for value in closure_refs
	):
		raise ValueError("Workshop summary closure_refs must be an array of references")
	seen_ids: set[str] = set()
	for category in _SUMMARY_CATEGORIES:
		items = normalized.get(category)
		if not isinstance(items, list):
			raise ValueError(f"Workshop summary {category} must be an array")
		for item in items:
			_validate_summary_item(category, item, seen_ids)
	decisions = normalized.get("proposal_decisions")
	if not isinstance(decisions, list):
		raise ValueError("Workshop summary proposal_decisions must be an array")
	for decision in decisions:
		if not isinstance(decision, dict):
			raise ValueError("Workshop summary proposal decision must be an object")
		_require_nonempty_strings(
			decision,
			("proposal_id", "decision", "original_text", "reviewed_by", "reviewed_at"),
		)
		if decision["decision"] not in _PROPOSAL_DECISIONS:
			raise ValueError("Workshop summary proposal decision has invalid status")
	return normalized


def read_workshop_summary(payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Compatibility reader and validator for Workshop summary schema v1."""
	return validate_workshop_summary(payload)


def validate_workshop_thinking_map(payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Validate a facilitator-reviewed WC map without accepting context graphs."""
	if not isinstance(payload, dict):
		raise ValueError("Workshop Thinking Map payload must be an object")
	normalized = dict(payload)
	_validate_no_forbidden_fields(normalized)
	if normalized.get("schema_version") != 1:
		raise ValueError("Workshop Thinking Map schema_version must be 1")
	if normalized.get("graph_schema_version") != 1:
		raise ValueError("Workshop Thinking Map graph_schema_version must be 1")
	if normalized.get("graph_kind") != "workshop_thinking_map":
		raise ValueError("Workshop Thinking Map graph_kind must be workshop_thinking_map")
	_require_nonempty_strings(normalized, ("session_id", "session_type_id", "collection_id"))
	if normalized["session_type_id"] != "workshop_catalyst":
		raise ValueError("Workshop Thinking Map session_type_id must be workshop_catalyst")
	if not isinstance(normalized.get("previous_version_id", ""), str):
		raise ValueError("Workshop Thinking Map previous_version_id must be a string")
	provenance = normalized.get("facilitator_provenance")
	if not isinstance(provenance, dict):
		raise ValueError("Workshop Thinking Map facilitator_provenance must be an object")
	_require_nonempty_strings(provenance, ("reviewed_by", "authorship_kind", "reviewed_at"))
	nodes = normalized.get("nodes")
	edges = normalized.get("edges")
	if not isinstance(nodes, list) or not isinstance(edges, list):
		raise ValueError("Workshop Thinking Map nodes and edges must be arrays")
	node_ids: set[str] = set()
	for node in nodes:
		_validate_map_record(node, "node")
		if node["id"] in node_ids:
			raise ValueError(f"Workshop Thinking Map duplicate node id: {node['id']}")
		node_ids.add(node["id"])
		if node.get("kind") not in _MAP_NODE_KINDS:
			raise ValueError("Workshop Thinking Map node kind is invalid")
		annotations = node.get("annotations")
		if not isinstance(annotations, dict):
			raise ValueError("Workshop Thinking Map node annotations must be an object")
		source_class = annotations.get("source_class")
		if source_class not in _MAP_SOURCE_CLASSES:
			raise ValueError("Workshop Thinking Map source_class is invalid")
		if source_class == "ai_inferred" and annotations.get("source_label") != "AI inferred":
			raise ValueError("Unsourced AI Thinking Map items must remain labelled AI inferred")
		if not isinstance(node.get("provenance"), dict):
			raise ValueError("Workshop Thinking Map node provenance must be an object")
	edges_seen: set[str] = set()
	for edge in edges:
		_validate_map_record(edge, "edge")
		if edge["id"] in edges_seen:
			raise ValueError(f"Workshop Thinking Map duplicate edge id: {edge['id']}")
		edges_seen.add(edge["id"])
		if edge.get("relation") not in _MAP_RELATIONS:
			raise ValueError("Workshop Thinking Map relation is invalid")
		if edge.get("from") not in node_ids or edge.get("to") not in node_ids:
			raise ValueError("Workshop Thinking Map edge endpoint is missing")
		if "confidence" in edge and (
			not isinstance(edge["confidence"], (int, float))
			or not 0 <= edge["confidence"] <= 1
		):
			raise ValueError("Workshop Thinking Map confidence must be between 0 and 1")
	decisions = normalized.get("proposal_decisions")
	if not isinstance(decisions, list):
		raise ValueError("Workshop Thinking Map proposal_decisions must be an array")
	for decision in decisions:
		if not isinstance(decision, dict):
			raise ValueError("Workshop Thinking Map proposal decision must be an object")
		_require_nonempty_strings(decision, ("record_id", "decision", "reviewed_by", "reviewed_at"))
		if decision["decision"] not in _PROPOSAL_DECISIONS:
			raise ValueError("Workshop Thinking Map proposal decision is invalid")
	return normalized


def read_workshop_thinking_map(payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Compatibility reader for the initial immutable Thinking Map contract."""
	return validate_workshop_thinking_map(payload)


def validate_workshop_path_set(payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Validate a facilitator-reviewed comparison with one explicit baseline path."""
	if not isinstance(payload, dict):
		raise ValueError("Workshop path-set payload must be an object")
	normalized = dict(payload)
	_validate_no_forbidden_fields(normalized)
	if normalized.get("schema_version") != 1:
		raise ValueError("Workshop path-set schema_version must be 1")
	_require_nonempty_strings(
		normalized,
		("session_id", "session_type_id", "collection_id", "review_status", "proposal_status"),
	)
	if normalized["session_type_id"] != "workshop_catalyst":
		raise ValueError("Workshop path-set session_type_id must be workshop_catalyst")
	if normalized["review_status"] != "facilitator_reviewed":
		raise ValueError("Workshop path-set must be facilitator_reviewed")
	if not isinstance(normalized.get("previous_version_id", ""), str):
		raise ValueError("Workshop path-set previous_version_id must be a string")
	paths = normalized.get("paths")
	if not isinstance(paths, list) or not paths:
		raise ValueError("Workshop path-set paths must be a non-empty array")
	path_ids: set[str] = set()
	do_nothing_count = 0
	for path in paths:
		_validate_workshop_path(path)
		if path["id"] in path_ids:
			raise ValueError("Workshop path-set path ids must be unique")
		path_ids.add(path["id"])
		do_nothing_count += int(path["is_do_nothing"])
	if do_nothing_count != 1:
		raise ValueError("Workshop path-set requires exactly one do-nothing path")
	selection = normalized.get("selection")
	if not isinstance(selection, dict):
		raise ValueError("Workshop path-set selection must be an object")
	_require_nonempty_strings(selection, ("kind", "label", "selected_by", "selected_at"))
	selected_ids = selection.get("path_ids")
	if not isinstance(selected_ids, list) or not selected_ids:
		raise ValueError("Workshop path-set selection requires path_ids")
	if any(not isinstance(path_id, str) or path_id not in path_ids for path_id in selected_ids):
		raise ValueError("Workshop path-set selection references an unknown path")
	if selection["kind"] == "combined" and len(set(selected_ids)) < 2:
		raise ValueError("Combined Workshop path selection requires two paths")
	if selection["kind"] not in {"single", "combined"}:
		raise ValueError("Workshop path-set selection kind is invalid")
	trace_ids = normalized.get("store_trace_ids")
	if not isinstance(trace_ids, list) or not all(isinstance(value, str) for value in trace_ids):
		raise ValueError("Workshop path-set store_trace_ids must be an array of strings")
	retrieval = normalized.get("evidence_retrieval")
	if not isinstance(retrieval, dict):
		raise ValueError("Workshop path-set evidence_retrieval must be an object")
	provenance = normalized.get("facilitator_provenance")
	if not isinstance(provenance, dict):
		raise ValueError("Workshop path-set facilitator_provenance must be an object")
	_require_nonempty_strings(provenance, ("reviewed_by", "authorship_kind", "reviewed_at"))
	if str(normalized.get("closure_ref", "")).strip():
		raise ValueError("Uncommitted Hub path-set payload cannot pre-claim a ClosureBus reference")
	return normalized


def read_workshop_path_set(payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Compatibility reader for immutable Workshop path-set schema v1."""
	return validate_workshop_path_set(payload)


def read_workshop_transcript_segment(payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Compatibility reader for the drafted pre-v1 capture timestamp aliases."""
	if not isinstance(payload, dict):
		raise ValueError("Workshop transcript payload must be an object")
	normalized = dict(payload)
	if "capture_started_at" not in normalized and "captured_at" in normalized:
		normalized["capture_started_at"] = normalized["captured_at"]
	if "capture_completed_at" not in normalized and "captured_at" in normalized:
		normalized["capture_completed_at"] = normalized["captured_at"]
	normalized.setdefault("previous_version_id", "")
	normalized.setdefault("corrected_text", "")
	normalized.setdefault("correction_reason", "")
	normalized.setdefault("source_audio_artifact_id", "")
	normalized.setdefault("submitted_text", normalized.get("original_text", ""))
	return normalized


def _require_nonempty_strings(payload: Dict[str, Any], keys: tuple[str, ...]) -> None:
	for key in keys:
		if not isinstance(payload.get(key), str) or not payload[key].strip():
			raise ValueError(f"Workshop transcript {key} is required")


def _validate_summary_item(category: str, item: Any, seen_ids: set[str]) -> None:
	if not isinstance(item, dict):
		raise ValueError(f"Workshop summary {category} item must be an object")
	_require_nonempty_strings(item, ("id", "text"))
	item_id = item["id"]
	if item_id in seen_ids:
		raise ValueError(f"Workshop summary contains duplicate item id: {item_id}")
	seen_ids.add(item_id)
	if not isinstance(item.get("provenance_refs"), list):
		raise ValueError(f"Workshop summary {category} item provenance_refs must be an array")
	if not isinstance(item.get("provenance"), dict):
		raise ValueError(f"Workshop summary {category} item provenance must be an object")


def _validate_map_record(record: Any, record_kind: str) -> None:
	if not isinstance(record, dict):
		raise ValueError(f"Workshop Thinking Map {record_kind} must be an object")
	_require_nonempty_strings(record, ("id",))
	if record.get("status") not in _GRAPH_STATUSES:
		raise ValueError(f"Workshop Thinking Map {record_kind} status is invalid")
	if not isinstance(record.get("provenance_refs"), list):
		raise ValueError(f"Workshop Thinking Map {record_kind} provenance_refs must be an array")


def _validate_workshop_path(path: Any) -> None:
	if not isinstance(path, dict):
		raise ValueError("Workshop path must be an object")
	_require_nonempty_strings(
		path,
		(
			"id",
			"title",
			"label",
			"biggest_risk",
			"uncertainty",
			"time_horizon",
			"proposal_state",
			"review_state",
			"created_at",
			"updated_at",
		),
	)
	if path["review_state"] not in {"accepted", "edited"}:
		raise ValueError("Committed Workshop paths must be accepted or edited")
	if not isinstance(path.get("is_do_nothing"), bool):
		raise ValueError("Workshop path is_do_nothing must be boolean")
	for field in ("outcomes", "assumptions"):
		values = path.get(field)
		if not isinstance(values, list) or not values or not all(
			isinstance(value, str) and value.strip() for value in values
		):
			raise ValueError(f"Workshop path {field} must contain non-empty strings")
	refs = path.get("evidence_refs")
	if not isinstance(refs, list):
		raise ValueError("Workshop path evidence_refs must be an array")
	for ref in refs:
		if not isinstance(ref, dict):
			raise ValueError("Workshop path evidence reference must be an object")
		_require_nonempty_strings(ref, ("id", "title"))
	status = path.get("evidence_status")
	if status not in {"supported", "partial", "none", "degraded", "unavailable"}:
		raise ValueError("Workshop path evidence_status is invalid")
	if not refs and status not in {"none", "degraded", "unavailable"}:
		raise ValueError("Workshop path without references must state none or unavailable")
	if refs and status == "none":
		raise ValueError("Workshop path evidence_status none cannot include references")
	if not isinstance(path.get("provenance"), dict):
		raise ValueError("Workshop path provenance must be an object")
	if not isinstance(path.get("previous_path_id", ""), str):
		raise ValueError("Workshop path previous_path_id must be a string")


def _validate_no_forbidden_fields(value: Any, path: str = "payload") -> None:
	if isinstance(value, dict):
		for key, child in value.items():
			normalized_key = str(key).strip().lower()
			if normalized_key in _FORBIDDEN_KEYS:
				raise ValueError(f"Workshop transcript cannot contain {path}.{key}")
			_validate_no_forbidden_fields(child, f"{path}.{key}")
	elif isinstance(value, list):
		for index, child in enumerate(value):
			_validate_no_forbidden_fields(child, f"{path}[{index}]")
