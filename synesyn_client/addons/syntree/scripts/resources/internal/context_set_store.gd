## Purpose: Validate and persist named Context Graph sets in source data.
extends RefCounted

const CONTEXT_SETS_KEY: String = "context_sets"


func get_sets(content_state: Object, owner_source_id: String) -> Array:
	if not is_instance_valid(content_state):
		return []
	var source_data: Dictionary = content_state.call(
		"get_source_data",
		owner_source_id
	)
	var source_meta: Dictionary = source_data.get("meta", {})
	var ai_context: Dictionary = source_meta.get("ai_context", {})
	var context_sets_any: Variant = ai_context.get(CONTEXT_SETS_KEY, [])
	if typeof(context_sets_any) != TYPE_ARRAY:
		return []
	return (context_sets_any as Array).duplicate(true)


func upsert_set(
	content_state: Object,
	owner_source_id: String,
	context_set: Dictionary
) -> Dictionary:
	var normalized: Dictionary = normalize(context_set)
	if not bool(normalized.get("ok", false)):
		return normalized
	var source_data: Dictionary = content_state.call(
		"get_source_data",
		owner_source_id
	)
	if source_data.is_empty():
		return {"ok": false, "errors": ["owner_source_not_found"]}
	var context_sets: Array = get_sets(content_state, owner_source_id)
	var normalized_set: Dictionary = normalized.get("context_set", {})
	var context_set_id: String = str(normalized_set.get("id", ""))
	var did_replace: bool = false
	for item_index in range(context_sets.size()):
		var existing: Dictionary = context_sets[item_index]
		if str(existing.get("id", "")) == context_set_id:
			context_sets[item_index] = normalized_set
			did_replace = true
			break
	if not did_replace:
		context_sets.append(normalized_set)
	context_sets.sort_custom(_sort_sets)
	_write_sets(source_data, context_sets)
	var did_save: bool = bool(content_state.call(
		"update_source",
		owner_source_id,
		source_data
	))
	return {
		"ok": did_save,
		"context_sets": context_sets,
		"errors": [] if did_save else ["source_update_failed"],
	}


func remove_set(
	content_state: Object,
	owner_source_id: String,
	context_set_id: String
) -> Dictionary:
	var source_data: Dictionary = content_state.call(
		"get_source_data",
		owner_source_id
	)
	if source_data.is_empty():
		return {"ok": false, "errors": ["owner_source_not_found"]}
	var context_sets: Array = get_sets(content_state, owner_source_id)
	var filtered: Array = []
	for context_set_any in context_sets:
		var context_set: Dictionary = context_set_any
		if str(context_set.get("id", "")) != context_set_id:
			filtered.append(context_set)
	if filtered.size() == context_sets.size():
		return {"ok": false, "errors": ["context_set_not_found"]}
	_write_sets(source_data, filtered)
	var did_save: bool = bool(content_state.call(
		"update_source",
		owner_source_id,
		source_data
	))
	return {
		"ok": did_save,
		"context_sets": filtered,
		"errors": [] if did_save else ["source_update_failed"],
	}


func normalize(context_set: Dictionary) -> Dictionary:
	var context_set_id: String = str(context_set.get("id", "")).strip_edges()
	if context_set_id.is_empty():
		return {"ok": false, "errors": ["missing_context_set_id"]}
	var entry_node_ids: Array[String] = _unique_strings(
		context_set.get("entry_node_ids", [])
	)
	var relation_ids: Array[String] = _unique_strings(
		context_set.get("allowed_relationship_types", [])
	)
	var activation_rules_any: Variant = context_set.get(
		"activation_rules",
		{"mode": "manual_only"}
	)
	var activation_rules: Dictionary = (
		(activation_rules_any as Dictionary).duplicate(true)
		if typeof(activation_rules_any) == TYPE_DICTIONARY
		else {"mode": "manual_only"}
	)
	var budget_policy_any: Variant = context_set.get("budget_policy", {})
	var budget_policy: Dictionary = (
		(budget_policy_any as Dictionary).duplicate(true)
		if typeof(budget_policy_any) == TYPE_DICTIONARY
		else {}
	)
	var normalized_set: Dictionary = {
		"id": context_set_id,
		"label": str(context_set.get("label", context_set_id)),
		"entry_node_ids": entry_node_ids,
		"allowed_relationship_types": relation_ids,
		"traversal_depth": maxi(0, int(context_set.get("traversal_depth", 0))),
		"activation_rules": activation_rules,
		"budget_policy": budget_policy,
		"status": str(context_set.get("status", "draft")),
	}
	if context_set.has("prompt_chain_ids"):
		normalized_set["prompt_chain_ids"] = _unique_strings(
			context_set.get("prompt_chain_ids", [])
		)
	return {"ok": true, "context_set": normalized_set, "errors": []}


func _write_sets(source_data: Dictionary, context_sets: Array) -> void:
	var source_meta: Dictionary = source_data.get("meta", {})
	var ai_context: Dictionary = source_meta.get("ai_context", {})
	ai_context[CONTEXT_SETS_KEY] = context_sets
	source_meta["ai_context"] = ai_context
	source_data["meta"] = source_meta


func _unique_strings(values_any: Variant) -> Array[String]:
	var values: Array[String] = []
	if typeof(values_any) != TYPE_ARRAY:
		return values
	for value_any in (values_any as Array):
		var value_id: String = str(value_any).strip_edges()
		if not value_id.is_empty() and not values.has(value_id):
			values.append(value_id)
	return values


func _sort_sets(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("id", "")) < str(right.get("id", ""))
