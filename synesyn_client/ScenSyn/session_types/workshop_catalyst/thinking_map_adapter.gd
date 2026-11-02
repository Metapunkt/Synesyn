extends RefCounted
class_name ThinkingMapAdapter

## WC-owned mapping between live Workshop events and the domain-neutral graph
## envelope. This module has no SynTree content, compiler, or editor dependency.

const GraphWorkspaceDocumentScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_document.gd"
)
const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)
const ContestationRegisterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_contestation_register.gd"
)

const ARTIFACT_TYPE: String = "ui.workshop_thinking_map"
const GRAPH_KIND: String = "workshop_thinking_map"
const CATEGORIES: Array[String] = ["cause", "effect", "opportunity"]
const OUTCOME_CATEGORIES: Array[String] = ["decision", "risk", "owner", "next_step"]
const RELATIONS: Array[String] = ["causes", "supports", "contradicts", "evidenced_by", "related_to"]
const SOURCE_CLASSES: Array[String] = [
	"participant_said",
	"ai_inferred",
	"external_evidence_supported",
]
const REVIEW_ACTIONS: Array[String] = ["accepted", "edited", "rejected", "deferred"]

var _session_id: String = ""
var _scenario_id: String = ""
var _collection_id: String = ""
var _document: Dictionary = {}
var _last_committed_document: Dictionary = {}
var _last_committed_artifact_id: String = ""
var _decision_ledger: Array[Dictionary] = []
var _applied_batch_ids: Dictionary = {}
var _latest_replace_tokens: Dictionary = {}
var _full_rebuild_count: int = 0
var _specialist_context_enabled: bool = false
var _views_revealed: bool = false
var _specialist_context_trace: Dictionary = {}


func initialize(
	session_id: String,
	scenario_id: String = "",
	collection_id: String = "decision_triage",
	saved_state: Dictionary = {}
) -> void:
	_session_id = session_id.strip_edges()
	_scenario_id = scenario_id.strip_edges()
	_collection_id = collection_id.strip_edges()
	_document = GraphWorkspaceDocumentScript.create_empty(
		GRAPH_KIND,
		"Workshop Thinking Map"
	)
	_document["schema_version"] = 1
	if not saved_state.is_empty():
		_load_state(saved_state)


func transcript_command(
	event_id: String,
	text: String,
	category_id: String,
	transcript_ref: String,
	author_id: String,
	timestamp_text: String
) -> Dictionary:
	return {
		"operation": "propose_node",
		"id": _stable_id("tmn", event_id),
		"category": category_id,
		"label": text,
		"source_class": "participant_said",
		"provenance_refs": _nonempty_refs([transcript_ref, event_id]),
		"provenance": {
			"author_id": author_id,
			"produced_by": "scensyn.workshop_transcript@1",
			"created_at": timestamp_text,
			"review_status": "unreviewed",
			"evidence_status": "unknown",
		},
	}


func synthesis_command(
	trace_id: String,
	text: String,
	category_id: String,
	timestamp_text: String
) -> Dictionary:
	return {
		"operation": "propose_node",
		"id": _stable_id("tmn", trace_id + "|" + text),
		"category": category_id,
		"label": text,
		"source_class": "ai_inferred",
		"provenance_refs": _nonempty_refs([trace_id]),
		"provenance": {
			"produced_by": "scensyn.workshop_hidden_synthesis@1",
			"created_at": timestamp_text,
			"review_status": "unreviewed",
			"evidence_status": "unsupported",
			"specialist_synthesis_trace_ref": trace_id,
		},
	}


func specialist_candidate_command(
	candidate: Dictionary,
	trace_id: String,
	timestamp_text: String,
	stage_name: String = ""
) -> Dictionary:
	var candidate_id: String = String(candidate.get("id", "")).strip_edges()
	var proposition: String = String(candidate.get("proposition", "")).strip_edges()
	var provenance_refs: Array = _array_from(candidate.get("source_refs", []))
	if not trace_id.strip_edges().is_empty() and trace_id not in provenance_refs:
		provenance_refs.append(trace_id)
	var command: Dictionary = {
		"operation": "propose_node",
		"id": _stable_id("tmn", candidate_id + "|" + proposition),
		"category": String(candidate.get("category", "")).strip_edges(),
		"label": proposition,
		"source_class": String(candidate.get("source_class", "")).strip_edges(),
		"provenance_refs": _nonempty_refs(provenance_refs),
		"provenance": {
			"produced_by": "scensyn.workshop_map_candidate_extraction@1",
			"created_at": timestamp_text,
			"review_status": "unreviewed",
			"evidence_status": String(candidate.get("evidence_status", "unknown")),
			"specialist_trace_ref": trace_id,
			"candidate_id": candidate_id,
			"rationale": String(candidate.get("rationale", "")).left(500),
			"confidence": clampf(float(candidate.get("confidence", 0.0)), 0.0, 1.0),
		},
	}
	var normalized_stage: String = stage_name.strip_edges()
	if not normalized_stage.is_empty():
		command["group_key"] = "stage:" + normalized_stage
		command["group_label"] = normalized_stage
	return command


## Builds propose_node commands for every candidate, then resolves each
## candidate's relates_to entries into propose_edge commands once every
## candidate's stable node id is known. Nodes are returned first so a batch
## never contains an edge command listed ahead of the node commands it wires
## together (readability only — apply_command_batch validates once at the end).
func specialist_candidate_commands(
	candidates: Array,
	trace_id: String,
	timestamp_text: String,
	stage_name: String = ""
) -> Array:
	var commands: Array = []
	var node_id_by_candidate_id: Dictionary = {}
	for candidate_any: Variant in candidates:
		if typeof(candidate_any) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = candidate_any
		var node_command: Dictionary = specialist_candidate_command(
			candidate,
			trace_id,
			timestamp_text,
			stage_name
		)
		commands.append(node_command)
		var local_candidate_id: String = String(candidate.get("id", "")).strip_edges()
		if not local_candidate_id.is_empty():
			node_id_by_candidate_id[local_candidate_id] = String(node_command.get("id", ""))
	for candidate_any: Variant in candidates:
		if typeof(candidate_any) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = candidate_any
		var local_candidate_id: String = String(candidate.get("id", "")).strip_edges()
		var from_node_id: String = String(node_id_by_candidate_id.get(local_candidate_id, ""))
		if from_node_id.is_empty():
			continue
		var relates_to_any: Variant = candidate.get("relates_to", [])
		if typeof(relates_to_any) != TYPE_ARRAY:
			continue
		for relation_any: Variant in (relates_to_any as Array):
			if typeof(relation_any) != TYPE_DICTIONARY:
				continue
			var relation_entry: Dictionary = relation_any
			var relation_id: String = String(relation_entry.get("relation", "")).strip_edges()
			var target_candidate_id: String = String(
				relation_entry.get("target_id", "")
			).strip_edges()
			if relation_id not in RELATIONS or target_candidate_id.is_empty():
				continue
			var to_node_id: String = String(
				node_id_by_candidate_id.get(target_candidate_id, "")
			)
			# Target may have been dropped upstream (e.g. deduplicated as a
			# duplicate semantic key); silently skip rather than fail the batch.
			if to_node_id.is_empty() or to_node_id == from_node_id:
				continue
			commands.append(_specialist_relation_edge_command(
				from_node_id,
				to_node_id,
				relation_id,
				candidate,
				trace_id,
				timestamp_text
			))
	return commands


func _specialist_relation_edge_command(
	from_node_id: String,
	to_node_id: String,
	relation_id: String,
	candidate: Dictionary,
	trace_id: String,
	timestamp_text: String
) -> Dictionary:
	var provenance_refs: Array = []
	if not trace_id.strip_edges().is_empty():
		provenance_refs.append(trace_id)
	return {
		"operation": "propose_edge",
		"id": _stable_id("tme", "%s|%s|%s" % [from_node_id, relation_id, to_node_id]),
		"from": from_node_id,
		"to": to_node_id,
		"relation": relation_id,
		"confidence": clampf(float(candidate.get("confidence", 0.0)), 0.0, 1.0),
		"provenance_refs": _nonempty_refs(provenance_refs),
		"provenance": {
			"produced_by": "scensyn.workshop_map_candidate_relation@1",
			"created_at": timestamp_text,
			"review_status": "unreviewed",
			"specialist_trace_ref": trace_id,
			"source_candidate_id": String(candidate.get("id", "")),
		},
	}


## Facilitator-drawn correction: the facilitator authored this edge directly by
## dragging a connection in the graph view, so it starts pre-accepted rather
## than "suggested" — there is no separate author to review it against.
func manual_edge_command(
	from_id: String,
	to_id: String,
	relation_id: String,
	facilitator_ref: String
) -> Dictionary:
	var normalized_from: String = from_id.strip_edges()
	var normalized_to: String = to_id.strip_edges()
	var normalized_relation: String = relation_id.strip_edges().to_lower()
	return {
		"operation": "propose_edge",
		"id": _stable_id("tme", "%s|%s|%s" % [normalized_from, normalized_relation, normalized_to]),
		"from": normalized_from,
		"to": normalized_to,
		"relation": normalized_relation,
		"confidence": 1.0,
		"initial_status": "accepted",
		"provenance_refs": _nonempty_refs([]),
		"provenance": {
			"produced_by": "scensyn.workshop_facilitator_manual_edge@1",
			"created_at": Time.get_datetime_string_from_system(true),
			"review_status": "reviewed",
			"reviewed_by": facilitator_ref,
			"authorship_kind": "facilitator_manual",
		},
	}


## Human-authored map item: someone typed this claim directly rather than the
## specialists proposing it. It starts pre-accepted because the author holds
## review authority — making them approve their own typing is friction, not a
## safeguard. `author_ref` and `authorship_kind` are parameters so participant
## proposals can reuse this path once multi-instance sync lands (ADR 0013);
## a participant would pass `initial_status = "suggested"` so the facilitator
## still reviews it.
func manual_node_command(
	category_id: String,
	label_text: String,
	author_ref: String,
	authorship_kind: String = "facilitator_manual",
	initial_status: String = "accepted"
) -> Dictionary:
	var normalized_category: String = category_id.strip_edges().to_lower()
	var normalized_label: String = label_text.strip_edges()
	var timestamp_text: String = Time.get_datetime_string_from_system(true)
	var is_pre_accepted: bool = initial_status == "accepted"
	return {
		"operation": "propose_node",
		# Seeded from category + wording only, so pressing Add twice on the same
		# text is a no-op rather than creating a twin card.
		"id": _stable_id("tmn", "manual|%s|%s" % [normalized_category, normalized_label]),
		"category": normalized_category,
		"label": normalized_label,
		"source_class": "participant_said",
		"initial_status": initial_status,
		"authorship_kind": authorship_kind,
		"provenance_refs": _nonempty_refs(["author:" + author_ref.strip_edges()]),
		"provenance": {
			"produced_by": "scensyn.workshop_manual_map_item@1",
			"created_at": timestamp_text,
			"authored_by": author_ref,
			"authorship_kind": authorship_kind,
			"review_status": "reviewed" if is_pre_accepted else "unreviewed",
			"reviewed_by": author_ref if is_pre_accepted else "",
			"reviewed_at": timestamp_text if is_pre_accepted else "",
			"evidence_status": "unknown",
		},
	}


## True for a human-authored item that no commit has published yet — the window
## in which its author may still revise or retract it. AI proposals never qualify:
## rejecting them keeps the record so the specialists do not silently re-suggest
## the same claim.
func is_own_uncommitted(record_id: String) -> bool:
	var location: Dictionary = _find_record_location(record_id)
	if location.is_empty() or String(location.get("collection", "")) != "nodes":
		return false
	var node_data: Dictionary = (_document["nodes"] as Array)[int(location["index"])]
	var annotations: Dictionary = _dictionary_from(node_data.get("annotations", {}))
	if String(annotations.get("authorship_kind", "")).strip_edges().is_empty():
		return false
	return not _is_in_last_commit(record_id)


func is_withdrawable(record_id: String) -> bool:
	return is_own_uncommitted(record_id)


## Corrects the wording of your own uncommitted item. Deliberately not
## review_proposal("edited"): that models reviewing someone else's proposal and
## requires the item to still be "suggested", whereas fixing your own typo is not
## a review decision and has to work on an already-accepted card.
func revise_own_node(record_id: String, new_label: String, author_ref: String) -> Dictionary:
	if not is_own_uncommitted(record_id):
		return {"ok": false, "error": "not_revisable"}
	var clean_label: String = new_label.strip_edges()
	if clean_label.is_empty():
		return {"ok": false, "error": "empty_label"}
	var nodes: Array = _document.get("nodes", [])
	var node_index: int = _record_index(nodes, record_id)
	if node_index < 0:
		return {"ok": false, "error": "not_found"}
	var node_data: Dictionary = nodes[node_index]
	var previous_label: String = String(node_data.get("label", ""))
	if previous_label == clean_label:
		return {"ok": true, "changed": false}
	# The id stays keyed to the original wording so edges and saved node
	# positions keep resolving. The cost is that Add-dedupe still matches the
	# original text, which at worst lets a twin card through for the author to
	# withdraw — cheaper than re-keying and orphaning every reference.
	node_data["label"] = clean_label
	var provenance: Dictionary = _dictionary_from(node_data.get("provenance", {}))
	if not provenance.has("original_label"):
		provenance["original_label"] = previous_label
	provenance["revised_by"] = author_ref
	provenance["revised_at"] = Time.get_datetime_string_from_system(true)
	node_data["provenance"] = provenance
	nodes[node_index] = node_data
	_document["nodes"] = nodes
	return {"ok": true, "changed": true, "previous_label": previous_label}


## Removes a human-authored, uncommitted item plus any edge touching it. Dropping
## the node alone would leave dangling endpoints, which the graph validator
## rejects outright.
func withdraw_node(record_id: String, author_ref: String) -> Dictionary:
	if not is_withdrawable(record_id):
		return {"ok": false, "error": "not_withdrawable"}
	var candidate: Dictionary = _document.duplicate(true)
	var nodes: Array = candidate.get("nodes", [])
	var node_index: int = _record_index(nodes, record_id)
	if node_index < 0:
		return {"ok": false, "error": "not_found"}
	var removed_label: String = String((nodes[node_index] as Dictionary).get("label", ""))
	nodes.remove_at(node_index)
	candidate["nodes"] = nodes
	var kept_edges: Array = []
	var removed_edge_ids: Array[String] = []
	for edge_any: Variant in candidate.get("edges", []):
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		var touches_removed_node: bool = (
			String(edge_data.get("from", "")) == record_id
			or String(edge_data.get("to", "")) == record_id
		)
		if touches_removed_node:
			removed_edge_ids.append(String(edge_data.get("id", "")))
			continue
		kept_edges.append(edge_data)
	candidate["edges"] = kept_edges
	var validation: Dictionary = GraphWorkspaceDocumentScript.validate(candidate, GRAPH_KIND)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"error": "invalid_after_withdraw",
			"validation_errors": validation.get("errors", []),
		}
	_document = candidate
	# Kept in the ledger even though the node is gone: that a human retracted a
	# claim is part of the session's decision history.
	_decision_ledger.append({
		"record_id": record_id,
		"decision": "withdrawn",
		"reviewed_by": author_ref,
		"reviewed_at": Time.get_datetime_string_from_system(true),
		"removed_edge_ids": removed_edge_ids,
	})
	return {
		"ok": true,
		"label": removed_label,
		"removed_edges": removed_edge_ids.size(),
	}


## Records or clears a claim's Closure Map orientation (ADR 0020). Pass an empty
## quadrant to untag.
##
## Deliberately not gated on `is_own_uncommitted`, unlike revise and withdraw.
## Those change what a claim *says*, so they close once anyone else could have
## acted on it. Orientation says nothing about the claim's content — it records
## which mode of situatedness the room decided it belongs to — and an audit run
## after a map commit is the expected case, not an edge case. The change shows up
## in the next preview diff like any other correction.
##
## Not a review decision either, so it leaves `status` and `review_status` alone
## and appends nothing to the decision ledger: orienting a suggested claim must
## not quietly promote it past the facilitator.
## `suggested_quadrant` is what a model proposed for this claim, or "" when it
## proposed that none applies. `was_suggested` distinguishes those two from the case
## where no suggestion existed at all, which "" alone cannot express.
##
## Recording this is what makes assisted orientation auditable rather than merely
## convenient (REQ-CA-004b): a session whose tags almost always match what was
## suggested is evidence of rubber-stamping, and that cannot be detected after the
## fact unless the suggestion is kept beside the choice.
func set_node_orientation(
	record_id: String,
	quadrant_id: String,
	author_ref: String,
	suggested_quadrant: String = "",
	was_suggested: bool = false
) -> Dictionary:
	var location: Dictionary = _find_record_location(record_id)
	if location.is_empty() or String(location.get("collection", "")) != "nodes":
		return {"ok": false, "error": "not_found"}
	var requested_quadrant: String = quadrant_id.strip_edges()
	var normalized_quadrant: String = ClosureOrientationScript.normalize_quadrant(
		requested_quadrant
	)
	# Reject an unrecognised quadrant rather than normalising it to "", which
	# would read as a successful clear and lose the caller's mistake.
	if not requested_quadrant.is_empty() and normalized_quadrant.is_empty():
		return {"ok": false, "error": "invalid_quadrant"}
	var nodes: Array = _document.get("nodes", [])
	var node_index: int = int(location["index"])
	var node_data: Dictionary = nodes[node_index]
	var previous_quadrant: String = ClosureOrientationScript.get_node_quadrant(node_data)
	if previous_quadrant == normalized_quadrant:
		return {"ok": true, "changed": false, "quadrant": normalized_quadrant}
	var annotations: Dictionary = _dictionary_from(node_data.get("annotations", {}))
	if normalized_quadrant.is_empty():
		annotations.erase("orientation")
	else:
		annotations["orientation"] = ClosureOrientationScript.build_annotation(
			normalized_quadrant
		)
	node_data["annotations"] = annotations
	var provenance: Dictionary = _dictionary_from(node_data.get("provenance", {}))
	provenance["oriented_by"] = author_ref
	provenance["oriented_at"] = Time.get_datetime_string_from_system(true)
	var normalized_suggestion: String = ClosureOrientationScript.normalize_quadrant(
		suggested_quadrant
	)
	if not was_suggested:
		provenance["orientation_authorship"] = "unaided"
		provenance.erase("suggested_quadrant")
	else:
		provenance["suggested_quadrant"] = normalized_suggestion
		if normalized_suggestion == normalized_quadrant:
			provenance["orientation_authorship"] = "accepted_suggestion"
		else:
			provenance["orientation_authorship"] = "changed_suggestion"
	node_data["provenance"] = provenance
	nodes[node_index] = node_data
	_document["nodes"] = nodes
	return {
		"ok": true,
		"changed": true,
		"quadrant": normalized_quadrant,
		"previous_quadrant": previous_quadrant,
		"orientation_authorship": String(provenance["orientation_authorship"]),
	}


## Records that the room did not converge on this claim's orientation.
##
## The facilitator closes orientation alone (ADR 0020, amended 2026-09-06), which keeps
## the audit inside its 20–30 minute budget but flattens one signal worth keeping: a
## room split over whether something is inherited from outside or already embedded in
## how it works is telling you it does not share a reading of its own situation. That
## is a finding about the group, not about the claim, and it is exactly what a closure
## audit should catch. Without somewhere to put it, the disagreement leaves no trace and
## the recorded tag reads as though it were uncontroversial.
##
## Marking is orthogonal to the tag: it neither requires nor blocks one, and it never
## affects review or commit.
func set_node_orientation_contested(
	record_id: String,
	is_contested: bool,
	author_ref: String
) -> Dictionary:
	var location: Dictionary = _find_record_location(record_id)
	if location.is_empty() or String(location.get("collection", "")) != "nodes":
		return {"ok": false, "error": "not_found"}
	var nodes: Array = _document.get("nodes", [])
	var node_index: int = int(location["index"])
	var node_data: Dictionary = nodes[node_index]
	if ClosureOrientationScript.is_orientation_contested(node_data) == is_contested:
		return {"ok": true, "changed": false, "contested": is_contested}
	var annotations: Dictionary = _dictionary_from(node_data.get("annotations", {}))
	var provenance: Dictionary = _dictionary_from(node_data.get("provenance", {}))
	if is_contested:
		annotations[ClosureOrientationScript.CONTESTED_ANNOTATION_KEY] = true
		provenance["orientation_contested_by"] = author_ref
		provenance["orientation_contested_at"] = Time.get_datetime_string_from_system(true)
	else:
		annotations.erase(ClosureOrientationScript.CONTESTED_ANNOTATION_KEY)
		provenance.erase("orientation_contested_by")
		provenance.erase("orientation_contested_at")
	node_data["annotations"] = annotations
	node_data["provenance"] = provenance
	nodes[node_index] = node_data
	_document["nodes"] = nodes
	return {"ok": true, "changed": true, "contested": is_contested}


## Contestation register entry points (REQ-CA-010, REQ-CA-011). Thin on purpose: the
## register's rules live in `WorkshopContestationRegister`, and the adapter's only job
## here is to locate the node and hand it over. Like orienting, none of these is a review
## decision — they leave status, review status, and the decision ledger untouched
## (REQ-CA-015), because recording that people read a claim differently says nothing about
## whether the claim belongs on the map.
func record_contestation_position(
	record_id: String,
	dimension: String,
	held_by: String,
	view_text: String,
	evidence: String,
	is_facilitator: bool
) -> Dictionary:
	var node_data: Dictionary = _find_node_for_contestation(record_id)
	if node_data.is_empty():
		return {"ok": false, "error": "not_found"}
	return ContestationRegisterScript.record_position(
		node_data, dimension, held_by, view_text, evidence, is_facilitator
	)


func remove_contestation_position(
	record_id: String,
	dimension: String,
	held_by: String
) -> Dictionary:
	var node_data: Dictionary = _find_node_for_contestation(record_id)
	if node_data.is_empty():
		return {"ok": false, "error": "not_found"}
	return ContestationRegisterScript.remove_position(node_data, dimension, held_by)


func review_contestation_position(
	record_id: String,
	dimension: String,
	held_by: String,
	reviewed_by: String
) -> Dictionary:
	var node_data: Dictionary = _find_node_for_contestation(record_id)
	if node_data.is_empty():
		return {"ok": false, "error": "not_found"}
	return ContestationRegisterScript.review_position(
		node_data, dimension, held_by, reviewed_by
	)


func set_contestation_field(
	record_id: String,
	dimension: String,
	field_id: String,
	value_text: String
) -> Dictionary:
	var node_data: Dictionary = _find_node_for_contestation(record_id)
	if node_data.is_empty():
		return {"ok": false, "error": "not_found"}
	return ContestationRegisterScript.set_dimension_field(
		node_data, dimension, field_id, value_text
	)


## Returns the live node dictionary, not a copy, so the register module can mutate it in
## place. Dictionaries are reference types in GDScript, so the write lands in `_document`
## without a store-back step; returning empty means the id did not resolve to a node.
func _find_node_for_contestation(record_id: String) -> Dictionary:
	var location: Dictionary = _find_record_location(record_id)
	if location.is_empty() or String(location.get("collection", "")) != "nodes":
		return {}
	var nodes: Array = _document.get("nodes", [])
	return nodes[int(location["index"])]


func _is_in_last_commit(record_id: String) -> bool:
	for node_any: Variant in _last_committed_document.get("nodes", []):
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		if String((node_any as Dictionary).get("id", "")) == record_id:
			return true
	return false


func apply_command_batch(
	batch_id: String,
	commands: Array,
	replace_key: String = "",
	replace_token: int = 0
) -> Dictionary:
	var normalized_batch_id: String = batch_id.strip_edges()
	if normalized_batch_id.is_empty():
		return {"ok": false, "error": "batch_id_required"}
	if _applied_batch_ids.has(normalized_batch_id):
		return {"ok": true, "duplicate": true, "applied": 0}
	var normalized_replace_key: String = replace_key.strip_edges()
	if not normalized_replace_key.is_empty():
		var current_token: int = int(_latest_replace_tokens.get(normalized_replace_key, -1))
		if replace_token < current_token:
			return {"ok": false, "cancelled": true, "error": "stale_batch"}
		_latest_replace_tokens[normalized_replace_key] = replace_token
	var candidate: Dictionary = _document.duplicate(true)
	var applied_count: int = 0
	for command_any: Variant in commands:
		if typeof(command_any) != TYPE_DICTIONARY:
			continue
		var command_result: Dictionary = _apply_command(candidate, command_any)
		if not bool(command_result.get("ok", false)):
			return command_result
		applied_count += int(command_result.get("applied", 0))
	var validation: Dictionary = GraphWorkspaceDocumentScript.validate(candidate, GRAPH_KIND)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"error": "invalid_incremental_batch",
			"validation_errors": validation.get("errors", []),
		}
	_document = candidate
	_applied_batch_ids[normalized_batch_id] = true
	return {"ok": true, "applied": applied_count, "full_rebuild": false}


func review_proposal(
	record_id: String,
	action_id: String,
	edited_label: String = "",
	facilitator_ref: String = "Facilitator"
) -> bool:
	var normalized_action: String = action_id.strip_edges().to_lower()
	if normalized_action not in REVIEW_ACTIONS:
		return false
	var location: Dictionary = _find_record_location(record_id)
	if location.is_empty():
		return false
	var collection_key: String = String(location["collection"])
	var record_index: int = int(location["index"])
	var records: Array = _document.get(collection_key, [])
	var record_data: Dictionary = records[record_index]
	if String(record_data.get("status", "")) != "suggested":
		return false
	var clean_edit: String = edited_label.strip_edges()
	if normalized_action == "edited" and clean_edit.is_empty():
		return false
	if normalized_action == "edited":
		record_data["label"] = clean_edit
	if normalized_action == "deferred":
		var annotations: Dictionary = _dictionary_from(record_data.get("annotations", {}))
		annotations["proposal_state"] = "deferred"
		record_data["annotations"] = annotations
	else:
		record_data["status"] = normalized_action
	var provenance: Dictionary = _dictionary_from(record_data.get("provenance", {}))
	provenance["review_status"] = "reviewed"
	provenance["reviewed_by"] = facilitator_ref
	provenance["reviewed_at"] = Time.get_datetime_string_from_system(true)
	record_data["provenance"] = provenance
	records[record_index] = record_data
	_document[collection_key] = records
	_decision_ledger.append({
		"record_id": record_id,
		"decision": normalized_action,
		"reviewed_by": facilitator_ref,
		"reviewed_at": provenance["reviewed_at"],
	})
	return true


func build_preview(facilitator_ref: String = "Facilitator") -> Dictionary:
	var candidate: Dictionary = build_commit_document(facilitator_ref)
	var validation: Dictionary = GraphWorkspaceDocumentScript.validate(candidate, GRAPH_KIND)
	return {
		"mutated": false,
		"valid": bool(validation.get("ok", false)),
		"validation_errors": validation.get("errors", []),
		"semantic_diff": GraphWorkspaceDocumentScript.semantic_diff(
			_last_committed_document,
			candidate
		),
		"resulting_map": candidate,
	}


func build_commit_document(facilitator_ref: String = "Facilitator") -> Dictionary:
	var payload: Dictionary = _document.duplicate(true)
	payload["schema_version"] = 1
	payload["session_id"] = _session_id
	payload["scenario_id"] = _scenario_id
	payload["session_type_id"] = "workshop_catalyst"
	payload["collection_id"] = _collection_id
	payload["previous_version_id"] = _last_committed_artifact_id
	payload["proposal_decisions"] = _decision_ledger.duplicate(true)
	payload["facilitator_provenance"] = {
		"reviewed_by": facilitator_ref,
		"authorship_kind": "user_reviewed",
		"reviewed_at": Time.get_datetime_string_from_system(true),
	}
	return payload


func mark_committed(artifact_id: String, payload: Dictionary) -> void:
	_last_committed_artifact_id = artifact_id.strip_edges()
	_last_committed_document = payload.duplicate(true)


func set_specialist_context_enabled(is_enabled: bool, facilitator_ref: String) -> Dictionary:
	_specialist_context_enabled = is_enabled
	_specialist_context_trace = {
		"trace_id": _stable_id(
			"tmt",
			"%s|%s|%s" % [
				_session_id,
				str(is_enabled),
				Time.get_datetime_string_from_system(true),
			]
		),
		"enabled": is_enabled,
		"map_artifact_id": _last_committed_artifact_id,
		"changed_by": facilitator_ref,
		"changed_at": Time.get_datetime_string_from_system(true),
	}
	return _specialist_context_trace.duplicate(true)


func get_specialist_prompt_context() -> Dictionary:
	if (
		not _specialist_context_enabled
		or _last_committed_artifact_id.is_empty()
		or _last_committed_document.is_empty()
	):
		return {}
	var approved_items: Array[Dictionary] = []
	for node_any: Variant in _last_committed_document.get("nodes", []):
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		if String(node_data.get("status", "")) in ["accepted", "edited", "committed"]:
			approved_items.append({
				"id": String(node_data.get("id", "")),
				"category": String(node_data.get("kind", "")),
				"label": String(node_data.get("label", "")),
			})
	return {
		"artifact_id": _last_committed_artifact_id,
		"trace_ref": String(_specialist_context_trace.get("trace_id", "")),
		"items": approved_items,
	}


func get_routable_outcome(record_id: String) -> Dictionary:
	var location: Dictionary = _find_record_location(record_id)
	if location.is_empty() or String(location.get("collection", "")) != "nodes":
		return {}
	var node_data: Dictionary = (_document["nodes"] as Array)[int(location["index"])]
	var category_id: String = String(node_data.get("kind", ""))
	if category_id not in OUTCOME_CATEGORIES:
		return {}
	if String(node_data.get("status", "")) not in ["accepted", "edited", "committed"]:
		return {}
	var record_category: String = category_id + "s"
	if category_id == "next_step":
		record_category = "next_steps"
	return {
		"record_category": record_category,
		"text": String(node_data.get("label", "")),
		"map_item_id": record_id,
		"map_artifact_id": _last_committed_artifact_id,
	}


func get_document() -> Dictionary:
	return _document.duplicate(true)


func get_state() -> Dictionary:
	return {
		"document": _document.duplicate(true),
		"last_committed_document": _last_committed_document.duplicate(true),
		"last_committed_artifact_id": _last_committed_artifact_id,
		"decision_ledger": _decision_ledger.duplicate(true),
		"applied_batch_ids": _applied_batch_ids.duplicate(true),
		"latest_replace_tokens": _latest_replace_tokens.duplicate(true),
		"specialist_context_enabled": _specialist_context_enabled,
		"specialist_context_trace": _specialist_context_trace.duplicate(true),
		"views_revealed": _views_revealed,
	}


## Whether recorded orientation views are open to the room yet.
##
## Session state rather than an annotation on the document: reveal is a facilitation
## moment, not a property of any claim, and putting it in the document would push it into
## the committed artifact and every export that reads one. It rides the map's existing
## state so it survives a reload and reaches peers by the path the map already uses.
##
## Held closed by default, which is the whole point — views entered while the spread is
## visible are no longer independent, and independence is the only thing private entry
## buys. Once open it stays open: re-hiding views the room has already discussed would
## record a retraction that did not happen.
func are_views_revealed() -> bool:
	return _views_revealed


func reveal_views() -> bool:
	if _views_revealed:
		return false
	_views_revealed = true
	return true


func get_last_committed_artifact_id() -> String:
	return _last_committed_artifact_id


func get_full_rebuild_count() -> int:
	return _full_rebuild_count


func _apply_command(candidate: Dictionary, command: Dictionary) -> Dictionary:
	var operation_id: String = String(command.get("operation", "")).strip_edges()
	if operation_id == "propose_node":
		return _apply_propose_node(candidate, command)
	if operation_id == "propose_edge":
		return _apply_propose_edge(candidate, command)
	return {"ok": false, "error": "unsupported_thinking_map_command:%s" % operation_id}


func _apply_propose_node(candidate: Dictionary, command: Dictionary) -> Dictionary:
	var category_id: String = String(command.get("category", "")).strip_edges()
	var node_id: String = String(command.get("id", "")).strip_edges()
	var label_text: String = String(command.get("label", "")).strip_edges()
	var source_class: String = String(command.get("source_class", "")).strip_edges()
	if category_id not in CATEGORIES + OUTCOME_CATEGORIES + ["question"]:
		return {"ok": false, "error": "invalid_map_category"}
	if node_id.is_empty() or label_text.is_empty() or source_class not in SOURCE_CLASSES:
		return {"ok": false, "error": "invalid_map_node"}
	var nodes: Array = candidate.get("nodes", [])
	if _record_index(nodes, node_id) >= 0:
		return {"ok": true, "applied": 0}
	# Mirrored into annotations so the card UI can offer Withdraw without having
	# to read provenance, matching how source_class is surfaced.
	var authorship_kind: String = String(command.get("authorship_kind", "")).strip_edges()
	var annotations: Dictionary = {
		"column": category_id,
		"source_class": source_class,
		"source_label": _source_label(source_class, authorship_kind),
	}
	if not authorship_kind.is_empty():
		annotations["authorship_kind"] = authorship_kind
	var group_key: String = String(command.get("group_key", "")).strip_edges()
	if not group_key.is_empty():
		annotations["group_key"] = group_key
		annotations["group_label"] = String(
			command.get("group_label", group_key)
		).strip_edges()
	# Model proposals start "suggested"; a human-authored item (see
	# manual_node_command) may start pre-"accepted", as manual edges already do.
	var initial_status: String = String(command.get("initial_status", "suggested"))
	if initial_status not in ["suggested", "accepted"]:
		initial_status = "suggested"
	nodes.append({
		"id": node_id,
		"kind": category_id,
		"label": label_text,
		"status": initial_status,
		"annotations": annotations,
		"provenance_refs": _array_from(command.get("provenance_refs", [])),
		"provenance": _dictionary_from(command.get("provenance", {})),
	})
	candidate["nodes"] = nodes
	return {"ok": true, "applied": 1}


func _apply_propose_edge(candidate: Dictionary, command: Dictionary) -> Dictionary:
	var relation_id: String = String(command.get("relation", "")).strip_edges()
	var edge_id: String = String(command.get("id", "")).strip_edges()
	if relation_id not in RELATIONS or edge_id.is_empty():
		return {"ok": false, "error": "invalid_map_edge"}
	var edges: Array = candidate.get("edges", [])
	if _record_index(edges, edge_id) >= 0:
		return {"ok": true, "applied": 0}
	# Model-proposed edges start "suggested" like nodes. A facilitator-drawn
	# manual edge (see manual_edge_command) starts pre-"accepted" instead.
	var initial_status: String = String(command.get("initial_status", "suggested"))
	if initial_status not in ["suggested", "accepted"]:
		initial_status = "suggested"
	edges.append({
		"id": edge_id,
		"from": String(command.get("from", "")),
		"to": String(command.get("to", "")),
		"relation": relation_id,
		"status": initial_status,
		"confidence": float(command.get("confidence", 0.0)),
		"provenance_refs": _array_from(command.get("provenance_refs", [])),
		"provenance": _dictionary_from(command.get("provenance", {})),
	})
	candidate["edges"] = edges
	return {"ok": true, "applied": 1}


func _find_record_location(record_id: String) -> Dictionary:
	for collection_key: String in ["nodes", "edges"]:
		var records: Array = _document.get(collection_key, [])
		var record_index: int = _record_index(records, record_id)
		if record_index >= 0:
			return {"collection": collection_key, "index": record_index}
	return {}


func _record_index(records: Array, record_id: String) -> int:
	for record_index: int in range(records.size()):
		var record_any: Variant = records[record_index]
		if typeof(record_any) == TYPE_DICTIONARY and String(record_any.get("id", "")) == record_id:
			return record_index
	return -1


func _load_state(saved_state: Dictionary) -> void:
	var document_any: Variant = saved_state.get("document", {})
	if typeof(document_any) == TYPE_DICTIONARY:
		var validation: Dictionary = GraphWorkspaceDocumentScript.validate(document_any, GRAPH_KIND)
		if bool(validation.get("ok", false)):
			_document = (document_any as Dictionary).duplicate(true)
	_last_committed_document = _dictionary_from(saved_state.get("last_committed_document", {}))
	_last_committed_artifact_id = String(saved_state.get("last_committed_artifact_id", ""))
	_decision_ledger.assign(_array_from(saved_state.get("decision_ledger", [])))
	_applied_batch_ids = _dictionary_from(saved_state.get("applied_batch_ids", {}))
	_latest_replace_tokens = _dictionary_from(saved_state.get("latest_replace_tokens", {}))
	_specialist_context_enabled = saved_state.get("specialist_context_enabled", false) == true
	_specialist_context_trace = _dictionary_from(saved_state.get("specialist_context_trace", {}))
	_views_revealed = saved_state.get("views_revealed", false) == true


## A human-typed item is also `participant_said`, but "Participant said" reads as
## a transcript quote. Name the authoring act instead so the card does not imply
## the claim was lifted from the conversation.
func _source_label(source_class: String, authorship_kind: String = "") -> String:
	if authorship_kind == "facilitator_manual":
		return "Added by facilitator"
	if authorship_kind == "participant_manual":
		return "Added by participant"
	if source_class == "participant_said":
		return "Participant said"
	if source_class == "external_evidence_supported":
		return "External evidence supported"
	return "AI inferred"


func _nonempty_refs(values: Array) -> Array:
	var refs: Array = []
	for value_any: Variant in values:
		var ref_text: String = String(value_any).strip_edges()
		if not ref_text.is_empty():
			refs.append(ref_text)
	if refs.is_empty():
		refs.append("provenance:unavailable")
	return refs


func _array_from(value_any: Variant) -> Array:
	return (value_any as Array).duplicate(true) if typeof(value_any) == TYPE_ARRAY else []


func _dictionary_from(value_any: Variant) -> Dictionary:
	return (value_any as Dictionary).duplicate(true) if typeof(value_any) == TYPE_DICTIONARY else {}


func _stable_id(prefix: String, seed_text: String) -> String:
	return "%s_%s" % [prefix, seed_text.sha256_text().left(16)]
