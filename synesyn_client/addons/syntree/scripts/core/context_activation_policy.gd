## Purpose: Deterministically evaluate Context Graph node activation.
extends RefCounted

const MODES: Array[String] = [
	"always",
	"when_relevant",
	"conditional",
	"manual_only",
	"excluded",
]


func evaluate(
	node_data: Dictionary,
	evaluation_context: Dictionary,
	is_entry: bool,
	is_reachable: bool,
	is_pinned: bool
) -> Dictionary:
	if str(node_data.get("status", "")) == "rejected":
		return {"include": false, "reason": "rejected"}
	if is_pinned:
		return {"include": true, "reason": "pinned"}
	var activation: Dictionary = node_data.get("activation", {})
	var activation_mode: String = str(
		activation.get("mode", "when_relevant")
	).to_lower()
	if not MODES.has(activation_mode):
		return {"include": false, "reason": "unknown_activation_mode"}
	match activation_mode:
		"excluded":
			return {"include": false, "reason": "activation:excluded"}
		"always":
			return {"include": true, "reason": "activation:always"}
		"manual_only":
			return {
				"include": is_entry,
				"reason": "entry" if is_entry else "activation:manual_only",
			}
		"conditional":
			var conditions: Dictionary = activation.get("conditions", {})
			var conditions_match: bool = (
				not conditions.is_empty()
				and _conditions_match(conditions, evaluation_context)
			)
			return {
				"include": conditions_match and is_reachable,
				"reason": (
					"activation:conditional"
					if conditions_match and is_reachable
					else "activation:condition_not_met"
				),
			}
	return {
		"include": is_reachable,
		"reason": (
			"activation:relevant"
			if is_reachable
			else "activation:not_relevant"
		),
	}


func always_node_ids(
	nodes_any: Variant,
	evaluation_context: Dictionary
) -> Array[String]:
	var node_ids: Array[String] = []
	if typeof(nodes_any) != TYPE_ARRAY:
		return node_ids
	for node_any in (nodes_any as Array):
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		var activation: Dictionary = node_data.get("activation", {})
		if str(activation.get("mode", "")).to_lower() != "always":
			continue
		if bool(evaluate(
			node_data,
			evaluation_context,
			false,
			false,
			false
		).get("include", false)):
			node_ids.append(str(node_data.get("id", "")))
	node_ids.sort()
	return node_ids


func _conditions_match(
	conditions: Dictionary,
	evaluation_context: Dictionary
) -> bool:
	for scope_key in ["thread_scope", "app_scope", "prompt_chain_id"]:
		if (
			conditions.has(scope_key)
			and str(conditions.get(scope_key, ""))
			!= str(evaluation_context.get(scope_key, ""))
		):
			return false
	var required_tags: Array[String] = _string_array(conditions.get("tags", []))
	var active_tags: Array[String] = _string_array(
		evaluation_context.get("tags", [])
	)
	for tag_id in required_tags:
		if not active_tags.has(tag_id):
			return false
	var required_slots: Dictionary = conditions.get("slots", {})
	var active_slots: Dictionary = evaluation_context.get("slots", {})
	for slot_id in required_slots:
		if active_slots.get(slot_id) != required_slots[slot_id]:
			return false
	return true


func _string_array(values_any: Variant) -> Array[String]:
	var values: Array[String] = []
	if typeof(values_any) != TYPE_ARRAY:
		return values
	for value_any in (values_any as Array):
		values.append(str(value_any))
	return values
