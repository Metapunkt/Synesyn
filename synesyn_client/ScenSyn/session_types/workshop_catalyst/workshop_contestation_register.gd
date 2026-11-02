extends RefCounted
class_name WorkshopContestationRegister

## Mutation and validation for the contestation register (REQ-CA-010, REQ-CA-011).
##
## Reading lives in `ClosureOrientation` in `synesyn_core`, because a stored register has
## to be legible to anything that reads a Closure Map — SynAxes included — and reading it
## must not require the workshop's editing rules. Editing lives here, because *who may
## record a position, when a view counts as reviewed, and what makes a register
## well-formed* are Workshop Catalyst's ritual, not shared vocabulary.
##
## Split out from `thinking_map_adapter.gd` rather than added to it: the adapter is over
## the 900-line soft limit already, and these are pure functions over a node dictionary
## with no document, session, or sync concerns.
##
## Every function takes and mutates a node dictionary in place and returns a result
## dictionary in the adapter's shape (`ok`, `changed`, and an `error` on failure), so the
## adapter can delegate without translating.

const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)

## A view recorded by a participant who is not the facilitator arrives unreviewed and
## stays visible as such. Views reuse the map's existing propose → review → commit
## vocabulary rather than introducing a second authority model: a participant proposes a
## reading, the facilitator reviews it, and only the facilitator's tag is canonical
## (ADR 0019, ADR 0020 amended 2026-09-06).
const REVIEW_UNREVIEWED: String = "unreviewed"
const REVIEW_REVIEWED: String = "reviewed"


## Records or replaces one participant's view on a dimension.
##
## Replacement rather than accumulation per holder: a participant who changes their mind
## holds one view, not a history of views, and a register that listed both would
## misreport the spread. `previous_view` comes back so callers can tell a correction from
## a first entry.
static func record_position(
	node_data: Dictionary,
	dimension: String,
	held_by: String,
	view_text: String,
	evidence: String,
	is_facilitator: bool
) -> Dictionary:
	if not ClosureOrientationScript.is_valid_dimension(dimension):
		return {"ok": false, "error": "unknown_dimension"}
	var normalized_dimension: String = dimension.strip_edges().to_lower()
	var holder: String = held_by.strip_edges()
	if holder.is_empty():
		return {"ok": false, "error": "missing_holder"}
	var normalized_view: String = _normalize_view(normalized_dimension, view_text)
	if normalized_view.is_empty():
		return {"ok": false, "error": "invalid_view"}
	var dimension_data: Dictionary = _mutable_dimension(node_data, normalized_dimension)
	var positions: Array = dimension_data.get("positions", [])
	var previous_view: String = ""
	var holder_index: int = -1
	for index: int in positions.size():
		var candidate: Dictionary = positions[index]
		if String(candidate.get("held_by", "")).strip_edges() == holder:
			holder_index = index
			previous_view = String(candidate.get("view", "")).strip_edges()
			break
	var position: Dictionary = {
		"held_by": holder,
		"view": normalized_view,
		"evidence": evidence.strip_edges(),
		"review_status": REVIEW_REVIEWED if is_facilitator else REVIEW_UNREVIEWED,
		"recorded_at": Time.get_datetime_string_from_system(true),
	}
	if holder_index >= 0:
		if (
			previous_view == normalized_view
			and String(positions[holder_index].get("evidence", "")).strip_edges()
			== position["evidence"]
		):
			return {"ok": true, "changed": false, "view": normalized_view}
		positions[holder_index] = position
	else:
		positions.append(position)
	dimension_data["positions"] = positions
	_store_dimension(node_data, normalized_dimension, dimension_data)
	return {
		"ok": true,
		"changed": true,
		"view": normalized_view,
		"previous_view": previous_view,
		"distinct_views": ClosureOrientationScript.get_distinct_views(
			node_data, normalized_dimension
		).size(),
	}


static func remove_position(
	node_data: Dictionary,
	dimension: String,
	held_by: String
) -> Dictionary:
	if not ClosureOrientationScript.is_valid_dimension(dimension):
		return {"ok": false, "error": "unknown_dimension"}
	var normalized_dimension: String = dimension.strip_edges().to_lower()
	var holder: String = held_by.strip_edges()
	var dimension_data: Dictionary = _mutable_dimension(node_data, normalized_dimension)
	var positions: Array = dimension_data.get("positions", [])
	for index: int in positions.size():
		if String((positions[index] as Dictionary).get("held_by", "")).strip_edges() == holder:
			positions.remove_at(index)
			dimension_data["positions"] = positions
			_store_dimension(node_data, normalized_dimension, dimension_data)
			return {"ok": true, "changed": true}
	return {"ok": true, "changed": false}


## Marks a participant's view as seen by the facilitator. Reviewing a view does not
## change it, adopt it, or promote it: the facilitator's own tag remains the only
## canonical orientation, so review here means acknowledged, not accepted.
static func review_position(
	node_data: Dictionary,
	dimension: String,
	held_by: String,
	reviewed_by: String
) -> Dictionary:
	if not ClosureOrientationScript.is_valid_dimension(dimension):
		return {"ok": false, "error": "unknown_dimension"}
	var normalized_dimension: String = dimension.strip_edges().to_lower()
	var holder: String = held_by.strip_edges()
	var dimension_data: Dictionary = _mutable_dimension(node_data, normalized_dimension)
	var positions: Array = dimension_data.get("positions", [])
	for index: int in positions.size():
		var position: Dictionary = positions[index]
		if String(position.get("held_by", "")).strip_edges() != holder:
			continue
		if String(position.get("review_status", "")) == REVIEW_REVIEWED:
			return {"ok": true, "changed": false}
		position["review_status"] = REVIEW_REVIEWED
		position["reviewed_by"] = reviewed_by.strip_edges()
		position["reviewed_at"] = Time.get_datetime_string_from_system(true)
		positions[index] = position
		dimension_data["positions"] = positions
		_store_dimension(node_data, normalized_dimension, dimension_data)
		return {"ok": true, "changed": true}
	return {"ok": false, "error": "not_found"}


## Sets what hangs on the disagreement and what would settle it — the two elements that
## turn a recorded split into something the room can act on.
static func set_dimension_field(
	node_data: Dictionary,
	dimension: String,
	field_id: String,
	value_text: String
) -> Dictionary:
	if not ClosureOrientationScript.is_valid_dimension(dimension):
		return {"ok": false, "error": "unknown_dimension"}
	var normalized_field: String = field_id.strip_edges().to_lower()
	if normalized_field not in ["decision_at_stake", "discriminating_test"]:
		return {"ok": false, "error": "unknown_field"}
	var normalized_dimension: String = dimension.strip_edges().to_lower()
	var dimension_data: Dictionary = _mutable_dimension(node_data, normalized_dimension)
	var clean_value: String = value_text.strip_edges()
	if String(dimension_data.get(normalized_field, "")) == clean_value:
		return {"ok": true, "changed": false}
	if clean_value.is_empty():
		dimension_data.erase(normalized_field)
	else:
		dimension_data[normalized_field] = clean_value
	_store_dimension(node_data, normalized_dimension, dimension_data)
	return {"ok": true, "changed": true}


## Names what the register is still missing, in facilitator language, for a claim whose
## views diverge. Empty when nothing is outstanding.
static func describe_gaps(node_data: Dictionary, dimension: String) -> Array[String]:
	var gaps: Array[String] = []
	if not ClosureOrientationScript.is_dimension_contested(node_data, dimension):
		return gaps
	var dimension_data: Dictionary = ClosureOrientationScript.get_contestation_dimension(
		node_data, dimension
	)
	if String(dimension_data.get("decision_at_stake", "")).strip_edges().is_empty():
		gaps.append("which decision would differ")
	if String(dimension_data.get("discriminating_test", "")).strip_edges().is_empty():
		gaps.append("what test would discriminate")
	var unsupported: Array[String] = []
	for position_any: Variant in ClosureOrientationScript.get_positions(node_data, dimension):
		var position: Dictionary = position_any
		if String(position.get("evidence", "")).strip_edges().is_empty():
			var holder: String = String(position.get("held_by", "")).strip_edges()
			if not holder.is_empty():
				unsupported.append(holder)
	if not unsupported.is_empty():
		gaps.append("supporting evidence from %s" % ", ".join(unsupported))
	return gaps


## A quadrant id for placement, free text for substance. Rejecting an unrecognised
## quadrant rather than storing it keeps REQ-CA-016's guarantee on this path too: a
## caller's mistake must not read as a deliberate position.
static func _normalize_view(dimension: String, view_text: String) -> String:
	var clean_view: String = view_text.strip_edges()
	if dimension != ClosureOrientationScript.DIMENSION_PLACEMENT:
		return clean_view
	return ClosureOrientationScript.normalize_quadrant(clean_view)


static func _mutable_dimension(node_data: Dictionary, dimension: String) -> Dictionary:
	var dimension_data: Dictionary = ClosureOrientationScript.get_contestation_dimension(
		node_data, dimension
	).duplicate(true)
	if not dimension_data.has("positions"):
		dimension_data["positions"] = []
	return dimension_data


## Prunes an emptied dimension, and the register with it, so that a claim whose positions
## were all withdrawn is indistinguishable from one that never had any. Otherwise an empty
## register would linger in the document and in every export that reads it.
static func _store_dimension(
	node_data: Dictionary,
	dimension: String,
	dimension_data: Dictionary
) -> void:
	var annotations_any: Variant = node_data.get("annotations", {})
	var annotations: Dictionary = (
		annotations_any if typeof(annotations_any) == TYPE_DICTIONARY else {}
	)
	var register_any: Variant = annotations.get(
		ClosureOrientationScript.CONTESTATION_ANNOTATION_KEY, {}
	)
	var register: Dictionary = register_any if typeof(register_any) == TYPE_DICTIONARY else {}
	var positions_any: Variant = dimension_data.get("positions", [])
	var has_positions: bool = (
		typeof(positions_any) == TYPE_ARRAY and not (positions_any as Array).is_empty()
	)
	var has_fields: bool = (
		not String(dimension_data.get("decision_at_stake", "")).is_empty()
		or not String(dimension_data.get("discriminating_test", "")).is_empty()
	)
	if has_positions or has_fields:
		register[dimension] = dimension_data
	else:
		register.erase(dimension)
	if register.is_empty():
		annotations.erase(ClosureOrientationScript.CONTESTATION_ANNOTATION_KEY)
	else:
		annotations[ClosureOrientationScript.CONTESTATION_ANNOTATION_KEY] = register
	node_data["annotations"] = annotations
