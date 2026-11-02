from __future__ import annotations

"""Validators for the two kinds of committed closure.

Both are human-committed boundaries, which is why they were once written under one
artifact type, but they are not the same record and are not interchangeable:

- ``ui.closure`` is a **SynAxes slice**: a saved way of looking at accumulated
  material, carrying a selection and an optional Closure Map orientation.
- ``ui.workshop_closure`` is a **session capture**: a decision, risk or deferred
  question a room committed during a session, carrying a statement and an outcome.

They are defined side by side here on purpose. Writing both under ``ui.closure``
corrupted SynAxes' orientation coverage figures and let session captures crowd
genuine slices out of its query window. ADR 0026 records the split.
"""

from typing import Any, Dict

from .workshop_artifacts import _validate_no_forbidden_fields


SYNAXES_CLOSURE_TYPE = "ui.closure"
WORKSHOP_CLOSURE_TYPE = "ui.workshop_closure"

_ORIENTATION_QUADRANTS = {"A", "B", "C", "D"}

# Fields only a session capture carries. Their presence in a ui.closure payload
# means a client is still writing session captures under the SynAxes type.
_WORKSHOP_ONLY_FIELDS = ("statement", "voters_yes", "voters_no", "stage_name")


def validate_closure_artifact(artifact_type: str, payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Validate closure payloads; pass anything else through untouched."""
	if artifact_type == SYNAXES_CLOSURE_TYPE:
		return validate_synaxes_closure(payload)
	if artifact_type == WORKSHOP_CLOSURE_TYPE:
		return validate_workshop_closure(payload)
	return payload


def validate_synaxes_closure(payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Validate a SynAxes closure: a named, navigable slice of the substrate."""
	if not isinstance(payload, dict):
		raise ValueError("Closure payload must be an object")
	normalized = dict(payload)
	_validate_no_forbidden_fields(normalized)

	misplaced = [field for field in _WORKSHOP_ONLY_FIELDS if field in normalized]
	if misplaced:
		raise ValueError(
			"Session captures must be written as "
			f"'{WORKSHOP_CLOSURE_TYPE}', not '{SYNAXES_CLOSURE_TYPE}' "
			f"(payload carries {', '.join(sorted(misplaced))}). See ADR 0026."
		)

	schema_version = normalized.get("schema_version")
	# bool is an int subclass in Python; reject it explicitly.
	if isinstance(schema_version, bool) or schema_version not in {1, 2}:
		raise ValueError("Closure schema_version must be the integer 1 or 2")
	if not isinstance(normalized.get("name"), str) or not normalized["name"].strip():
		raise ValueError("Closure name is required")
	if not isinstance(normalized.get("intent", ""), str):
		raise ValueError("Closure intent must be a string")
	if not isinstance(normalized.get("selection"), dict):
		raise ValueError("Closure selection must be an object")
	if not isinstance(normalized.get("time_window"), dict):
		raise ValueError("Closure time_window must be an object")

	orientation = normalized.get("orientation")
	if schema_version == 2:
		if not isinstance(orientation, dict):
			raise ValueError("Closure schema_version 2 requires an orientation object")
		quadrant = orientation.get("quadrant")
		if not isinstance(quadrant, str) or quadrant.strip().upper() not in _ORIENTATION_QUADRANTS:
			raise ValueError("Closure orientation quadrant must be A, B, C or D")
	elif orientation is not None and not isinstance(orientation, dict):
		raise ValueError("Closure orientation must be an object when present")
	return normalized


def validate_workshop_closure(payload: Dict[str, Any]) -> Dict[str, Any]:
	"""Validate a session capture committed through the ClosureBus."""
	if not isinstance(payload, dict):
		raise ValueError("Workshop closure payload must be an object")
	normalized = dict(payload)
	_validate_no_forbidden_fields(normalized)

	schema_version = normalized.get("schema_version")
	if isinstance(schema_version, bool) or schema_version != 1:
		raise ValueError("Workshop closure schema_version must be the integer 1")

	# `outcome` is deliberately not drawn from a fixed set: the session record
	# records "yes"/"no" votes, while a Compare Paths commit records "committed".
	# Requiring one vocabulary here would silently drop the other.
	for key in ("session_type_id", "kind", "statement", "outcome"):
		if not isinstance(normalized.get(key), str) or not normalized[key].strip():
			raise ValueError(f"Workshop closure {key} is required")

	for key in ("voters_yes", "voters_no"):
		if key in normalized and not isinstance(normalized[key], list):
			raise ValueError(f"Workshop closure {key} must be an array")

	human_commit = normalized.get("human_commit")
	if not isinstance(human_commit, dict):
		raise ValueError("Workshop closure human_commit must be an object")
	if not isinstance(human_commit.get("committed_by"), str) or not human_commit["committed_by"].strip():
		raise ValueError("Workshop closure human_commit.committed_by is required")
	return normalized
