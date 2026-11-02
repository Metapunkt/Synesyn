extends RefCounted
class_name WorkshopSessionRecordStore

const SCHEMA_VERSION: int = 1
const CATEGORIES: Array[String] = [
	"decisions",
	"risks",
	"open_questions",
	"owners",
	"next_steps",
]

var _session_id: String = ""
var _reviewed: Dictionary = {}
var _proposals: Array[Dictionary] = []
var _proposal_decisions: Array[Dictionary] = []
var _suppressed_keys: Dictionary = {}
var _protected_keys: Dictionary = {}
var _last_committed_artifact_id: String = ""
var _last_committed_payload: Dictionary = {}
var _is_dirty: bool = false


func initialize(session_id: String, saved_state: Dictionary = {}, legacy_buckets: Dictionary = {}) -> void:
	_session_id = session_id.strip_edges()
	_reviewed = _empty_reviewed()
	if not saved_state.is_empty():
		_load(saved_state)
	else:
		_import_authoritative_buckets(legacy_buckets, "legacy_closure")


func get_session_id() -> String:
	return _session_id


func reconcile_authoritative_buckets(buckets: Dictionary) -> bool:
	return _import_authoritative_buckets(buckets, "facilitator_closure")


func propose(category_id: String, suggestion_text: String, provenance: Dictionary = {}) -> Dictionary:
	var normalized_category: String = _normalize_category(category_id)
	var clean_text: String = suggestion_text.strip_edges()
	if normalized_category.is_empty() or clean_text.is_empty():
		return {}
	var exact_key: String = exact_key_for(clean_text)
	var semantic_key: String = semantic_key_for(clean_text)
	if _is_key_blocked(exact_key, semantic_key):
		return {}
	if _contains_reviewed_key(normalized_category, exact_key, semantic_key):
		return {}
	for existing_proposal: Dictionary in _proposals:
		if (
			String(existing_proposal.get("category", "")) == normalized_category
			and String(existing_proposal.get("status", "")) == "suggested"
			and (
				String(existing_proposal.get("exact_key", "")) == exact_key
				or String(existing_proposal.get("semantic_key", "")) == semantic_key
			)
		):
			return {}
	var proposal_id: String = _stable_id(
		"wsp",
		"%s|%s|%s|%d" % [_session_id, normalized_category, exact_key, _proposals.size()]
	)
	var proposal: Dictionary = {
		"id": proposal_id,
		"category": normalized_category,
		"text": clean_text,
		"status": "suggested",
		"exact_key": exact_key,
		"semantic_key": semantic_key,
		"provenance": provenance.duplicate(true),
		"created_at": Time.get_datetime_string_from_system(true),
		"reviewed_at": "",
		"reviewer_note": "",
	}
	_proposals.append(proposal)
	_is_dirty = true
	return proposal.duplicate(true)


func accept(proposal_id: String, facilitator_ref: String = "Facilitator") -> bool:
	var proposal_index: int = _proposal_index(proposal_id)
	if proposal_index < 0:
		return false
	var proposal: Dictionary = _proposals[proposal_index]
	if String(proposal.get("status", "")) != "suggested":
		return false
	var category_id: String = String(proposal.get("category", ""))
	var item: Dictionary = _make_reviewed_item(
		category_id,
		String(proposal.get("text", "")),
		"ai_proposal",
		proposal_id,
		facilitator_ref
	)
	_reviewed[category_id].append(item)
	_record_decision(proposal_index, "accepted", facilitator_ref, "")
	return true


func edit_proposal(
	proposal_id: String,
	edited_text: String,
	facilitator_ref: String = "Facilitator"
) -> bool:
	var proposal_index: int = _proposal_index(proposal_id)
	var clean_text: String = edited_text.strip_edges()
	if proposal_index < 0 or clean_text.is_empty():
		return false
	var proposal: Dictionary = _proposals[proposal_index]
	if String(proposal.get("status", "")) != "suggested":
		return false
	var category_id: String = String(proposal.get("category", ""))
	var item: Dictionary = _make_reviewed_item(
		category_id,
		clean_text,
		"facilitator_edit",
		proposal_id,
		facilitator_ref
	)
	item["facilitator_edited"] = true
	_reviewed[category_id].append(item)
	_protected_keys[String(proposal.get("exact_key", ""))] = true
	_protected_keys[String(proposal.get("semantic_key", ""))] = true
	_protected_keys[exact_key_for(clean_text)] = true
	_protected_keys[semantic_key_for(clean_text)] = true
	_record_decision(proposal_index, "edited", facilitator_ref, clean_text)
	return true


func reject(proposal_id: String, facilitator_ref: String = "Facilitator") -> bool:
	return _suppress_proposal(proposal_id, "rejected", facilitator_ref)


func defer(proposal_id: String, facilitator_ref: String = "Facilitator") -> bool:
	return _suppress_proposal(proposal_id, "deferred", facilitator_ref)


func add_facilitator_item(
	category_id: String,
	item_text: String,
	facilitator_ref: String = "Facilitator",
	provenance_override: Dictionary = {}
) -> Dictionary:
	var normalized_category: String = _normalize_category(category_id)
	var clean_text: String = item_text.strip_edges()
	if normalized_category.is_empty() or clean_text.is_empty():
		return {}
	var item: Dictionary = _make_reviewed_item(
		normalized_category,
		clean_text,
		"facilitator_authored",
		"",
		facilitator_ref
	)
	if not provenance_override.is_empty():
		var provenance_any: Variant = provenance_override.get("provenance", {})
		if typeof(provenance_any) == TYPE_DICTIONARY:
			item["provenance"] = (provenance_any as Dictionary).duplicate(true)
		var refs_any: Variant = provenance_override.get("provenance_refs", [])
		if typeof(refs_any) == TYPE_ARRAY:
			item["provenance_refs"] = (refs_any as Array).duplicate(true)
	item["facilitator_edited"] = true
	_reviewed[normalized_category].append(item)
	_protected_keys[exact_key_for(clean_text)] = true
	_protected_keys[semantic_key_for(clean_text)] = true
	_is_dirty = true
	return item.duplicate(true)


func edit_reviewed_item(
	category_id: String,
	item_id: String,
	edited_text: String,
	facilitator_ref: String = "Facilitator"
) -> bool:
	var normalized_category: String = _normalize_category(category_id)
	var clean_text: String = edited_text.strip_edges()
	if normalized_category.is_empty() or clean_text.is_empty():
		return false
	var items: Array = _reviewed.get(normalized_category, [])
	for item_index: int in range(items.size()):
		var item_any: Variant = items[item_index]
		if typeof(item_any) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_any
		if String(item.get("id", "")) != item_id:
			continue
		var prior_text: String = String(item.get("text", ""))
		_protected_keys[exact_key_for(prior_text)] = true
		_protected_keys[semantic_key_for(prior_text)] = true
		item["text"] = clean_text
		item["facilitator_edited"] = true
		item["updated_at"] = Time.get_datetime_string_from_system(true)
		item["reviewed_by"] = facilitator_ref
		items[item_index] = item
		_reviewed[normalized_category] = items
		_protected_keys[exact_key_for(clean_text)] = true
		_protected_keys[semantic_key_for(clean_text)] = true
		_is_dirty = true
		return true
	return false


func remove_reviewed_item(category_id: String, item_id: String) -> bool:
	var normalized_category: String = _normalize_category(category_id)
	if normalized_category.is_empty():
		return false
	var items: Array = _reviewed.get(normalized_category, [])
	for item_index: int in range(items.size()):
		var item_any: Variant = items[item_index]
		if typeof(item_any) == TYPE_DICTIONARY and String(item_any.get("id", "")) == item_id:
			var item_text: String = String(item_any.get("text", ""))
			_suppressed_keys[exact_key_for(item_text)] = true
			_suppressed_keys[semantic_key_for(item_text)] = true
			items.remove_at(item_index)
			_reviewed[normalized_category] = items
			_is_dirty = true
			return true
	return false


func build_preview(
	facilitator_ref: String,
	closure_refs: Array = []
) -> Dictionary:
	var resulting_summary: Dictionary = build_commit_payload(facilitator_ref, closure_refs)
	var previous_reviewed: Dictionary = {}
	if not _last_committed_payload.is_empty():
		for category_id: String in CATEGORIES:
			previous_reviewed[category_id] = _last_committed_payload.get(category_id, [])
	var semantic_diff: Dictionary = {}
	for category_id: String in CATEGORIES:
		var previous_items: Array = previous_reviewed.get(category_id, [])
		var current_items: Array = resulting_summary.get(category_id, [])
		semantic_diff[category_id] = _diff_items(previous_items, current_items)
	return {
		"resulting_summary": resulting_summary,
		"semantic_diff": semantic_diff,
		"mutated": false,
	}


func build_commit_payload(
	facilitator_ref: String,
	closure_refs: Array = []
) -> Dictionary:
	var payload: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"session_id": _session_id,
		"review_status": "facilitator_reviewed",
		"proposal_status": "review_complete",
		"proposal_decisions": _proposal_decisions.duplicate(true),
		"facilitator_provenance": {
			"reviewed_by": facilitator_ref,
			"authorship_kind": "user_authored",
			"reviewed_at": Time.get_datetime_string_from_system(true),
		},
		"previous_version_id": _last_committed_artifact_id,
		"closure_refs": closure_refs.duplicate(true),
	}
	for category_id: String in CATEGORIES:
		payload[category_id] = (_reviewed.get(category_id, []) as Array).duplicate(true)
	return payload


func mark_committed(artifact_id: String, payload: Dictionary) -> void:
	_last_committed_artifact_id = artifact_id.strip_edges()
	_last_committed_payload = payload.duplicate(true)
	_is_dirty = false


func get_reviewed() -> Dictionary:
	return _reviewed.duplicate(true)


func get_proposals() -> Array[Dictionary]:
	return _proposals.duplicate(true)


func get_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"session_id": _session_id,
		"reviewed": _reviewed.duplicate(true),
		"proposals": _proposals.duplicate(true),
		"proposal_decisions": _proposal_decisions.duplicate(true),
		"suppressed_keys": _suppressed_keys.duplicate(true),
		"protected_keys": _protected_keys.duplicate(true),
		"last_committed_artifact_id": _last_committed_artifact_id,
		"last_committed_payload": _last_committed_payload.duplicate(true),
		"is_dirty": _is_dirty,
	}


func get_last_committed_artifact_id() -> String:
	return _last_committed_artifact_id


func get_last_committed_payload() -> Dictionary:
	return _last_committed_payload.duplicate(true)


func is_dirty() -> bool:
	return _is_dirty


static func exact_key_for(item_text: String) -> String:
	var lowered: String = item_text.to_lower().strip_edges()
	var regex := RegEx.new()
	regex.compile("[^a-z0-9]+")
	return regex.sub(lowered, " ", true).strip_edges()


static func semantic_key_for(item_text: String) -> String:
	var stop_words: Array[String] = [
		"a", "an", "and", "are", "as", "at", "be", "by", "for", "from",
		"in", "is", "it", "of", "on", "or", "that", "the", "to", "we", "with",
	]
	var tokens: PackedStringArray = exact_key_for(item_text).split(" ", false)
	var meaningful: Array[String] = []
	for token: String in tokens:
		var stemmed_token: String = _semantic_stem(token)
		if (
			stemmed_token.length() > 2
			and stemmed_token not in stop_words
			and stemmed_token not in meaningful
		):
			meaningful.append(stemmed_token)
	meaningful.sort()
	return "sem:" + "|".join(meaningful)


static func _semantic_stem(token: String) -> String:
	if token.ends_with("ies") and token.length() > 4:
		return token.left(token.length() - 3) + "y"
	for suffix: String in ["ing", "ed", "es", "s"]:
		if token.ends_with(suffix) and token.length() > suffix.length() + 2:
			return token.left(token.length() - suffix.length())
	return token


func _load(saved_state: Dictionary) -> void:
	var reviewed_any: Variant = saved_state.get("reviewed", {})
	if typeof(reviewed_any) == TYPE_DICTIONARY:
		for category_id: String in CATEGORIES:
			var items_any: Variant = reviewed_any.get(category_id, [])
			_reviewed[category_id] = items_any.duplicate(true) if typeof(items_any) == TYPE_ARRAY else []
	# JSON / Variant-backed arrays are untyped Array; .assign() coerces into
	# Array[Dictionary] (direct assignment raises a runtime type error).
	_proposals.clear()
	var proposals_any: Variant = saved_state.get("proposals", [])
	if typeof(proposals_any) == TYPE_ARRAY:
		_proposals.assign((proposals_any as Array).duplicate(true))
	_proposal_decisions.clear()
	var decisions_any: Variant = saved_state.get("proposal_decisions", [])
	if typeof(decisions_any) == TYPE_ARRAY:
		_proposal_decisions.assign((decisions_any as Array).duplicate(true))
	var suppressed_any: Variant = saved_state.get("suppressed_keys", {})
	_suppressed_keys = suppressed_any.duplicate(true) if typeof(suppressed_any) == TYPE_DICTIONARY else {}
	var protected_any: Variant = saved_state.get("protected_keys", {})
	_protected_keys = protected_any.duplicate(true) if typeof(protected_any) == TYPE_DICTIONARY else {}
	_last_committed_artifact_id = String(saved_state.get("last_committed_artifact_id", ""))
	var committed_any: Variant = saved_state.get("last_committed_payload", {})
	_last_committed_payload = committed_any.duplicate(true) if typeof(committed_any) == TYPE_DICTIONARY else {}
	_is_dirty = bool(saved_state.get("is_dirty", false))


func _import_authoritative_buckets(buckets: Dictionary, source_id: String) -> bool:
	var imported_any: bool = false
	var category_map: Dictionary = {
		"decisions": "decisions",
		"risks": "risks",
		"open_questions": "open_questions",
		"next_steps": "next_steps",
	}
	for source_category: String in category_map:
		var category_id: String = String(category_map[source_category])
		var items_any: Variant = buckets.get(source_category, [])
		if typeof(items_any) != TYPE_ARRAY:
			continue
		for item_any: Variant in items_any:
			var item_text: String = String(item_any).strip_edges()
			if item_text.is_empty():
				continue
			if _contains_reviewed_key(
				category_id,
				exact_key_for(item_text),
				semantic_key_for(item_text)
			):
				continue
			_reviewed[category_id].append(
				_make_reviewed_item(category_id, item_text, source_id, "", "Facilitator")
			)
			imported_any = true
	if imported_any:
		_is_dirty = true
	return imported_any


func _make_reviewed_item(
	category_id: String,
	item_text: String,
	source_id: String,
	proposal_id: String,
	facilitator_ref: String
) -> Dictionary:
	var stable_input: String = "%s|%s|%s" % [_session_id, category_id, exact_key_for(item_text)]
	return {
		"id": _stable_id("wsi", stable_input),
		"text": item_text.strip_edges(),
		"provenance_refs": [proposal_id] if not proposal_id.is_empty() else [],
		"provenance": {
			"authorship_kind": "user_authored" if source_id != "ai_proposal" else "ai_inference",
			"origin_ref": proposal_id if not proposal_id.is_empty() else source_id,
			"review_status": "reviewed",
		},
		"reviewed_by": facilitator_ref,
		"facilitator_edited": source_id in ["facilitator_edit", "facilitator_authored"],
		"updated_at": Time.get_datetime_string_from_system(true),
	}


func _record_decision(
	proposal_index: int,
	status_id: String,
	facilitator_ref: String,
	edited_text: String
) -> void:
	var proposal: Dictionary = _proposals[proposal_index]
	proposal["status"] = status_id
	proposal["reviewed_at"] = Time.get_datetime_string_from_system(true)
	proposal["reviewed_by"] = facilitator_ref
	if not edited_text.is_empty():
		proposal["reviewed_text"] = edited_text
	_proposals[proposal_index] = proposal
	_proposal_decisions.append({
		"proposal_id": String(proposal.get("id", "")),
		"decision": status_id,
		"original_text": String(proposal.get("text", "")),
		"reviewed_text": edited_text,
		"reviewed_by": facilitator_ref,
		"reviewed_at": proposal["reviewed_at"],
	})
	_is_dirty = true


func _suppress_proposal(
	proposal_id: String,
	status_id: String,
	facilitator_ref: String
) -> bool:
	var proposal_index: int = _proposal_index(proposal_id)
	if proposal_index < 0:
		return false
	var proposal: Dictionary = _proposals[proposal_index]
	if String(proposal.get("status", "")) != "suggested":
		return false
	_suppressed_keys[String(proposal.get("exact_key", ""))] = true
	_suppressed_keys[String(proposal.get("semantic_key", ""))] = true
	_record_decision(proposal_index, status_id, facilitator_ref, "")
	return true


func _contains_reviewed_key(category_id: String, exact_key: String, semantic_key: String) -> bool:
	var items: Array = _reviewed.get(category_id, [])
	for item_any: Variant in items:
		if typeof(item_any) != TYPE_DICTIONARY:
			continue
		var item_text: String = String(item_any.get("text", ""))
		if exact_key_for(item_text) == exact_key or semantic_key_for(item_text) == semantic_key:
			return true
	return false


func _is_key_blocked(exact_key: String, semantic_key: String) -> bool:
	return (
		_suppressed_keys.has(exact_key)
		or _suppressed_keys.has(semantic_key)
		or _protected_keys.has(exact_key)
		or _protected_keys.has(semantic_key)
	)


func _proposal_index(proposal_id: String) -> int:
	for proposal_index: int in range(_proposals.size()):
		if String(_proposals[proposal_index].get("id", "")) == proposal_id:
			return proposal_index
	return -1


func _normalize_category(category_id: String) -> String:
	var normalized: String = category_id.strip_edges().to_lower()
	return normalized if normalized in CATEGORIES else ""


func _empty_reviewed() -> Dictionary:
	var result: Dictionary = {}
	for category_id: String in CATEGORIES:
		result[category_id] = []
	return result


func _diff_items(previous_items: Array, current_items: Array) -> Dictionary:
	var previous_by_id: Dictionary = {}
	for item_any: Variant in previous_items:
		if typeof(item_any) == TYPE_DICTIONARY:
			previous_by_id[String(item_any.get("id", ""))] = item_any
	var current_by_id: Dictionary = {}
	for item_any: Variant in current_items:
		if typeof(item_any) == TYPE_DICTIONARY:
			current_by_id[String(item_any.get("id", ""))] = item_any
	var added: Array = []
	var removed: Array = []
	var changed: Array = []
	for item_id: String in current_by_id:
		if not previous_by_id.has(item_id):
			added.append(current_by_id[item_id])
		elif String(previous_by_id[item_id].get("text", "")) != String(current_by_id[item_id].get("text", "")):
			changed.append({"before": previous_by_id[item_id], "after": current_by_id[item_id]})
	for item_id: String in previous_by_id:
		if not current_by_id.has(item_id):
			removed.append(previous_by_id[item_id])
	return {"added": added, "changed": changed, "removed": removed}


func _stable_id(prefix: String, source_text: String) -> String:
	return "%s_%s" % [prefix, source_text.sha256_text().left(20)]
