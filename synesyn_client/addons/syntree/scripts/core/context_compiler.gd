## Purpose: Deterministically compile a Context Graph set into model context.
extends RefCounted

const ContextActivationPolicyScript = preload(
	"res://addons/syntree/scripts/core/context_activation_policy.gd"
)
const ESTIMATOR_ID: String = "heuristic_unicode_chars_div_4_v1"

const PRESETS: Dictionary = {
	"full": {
		"max_tokens": 16000,
		"traversal_depth": 4,
		"allowed_relationship_types": [],
	},
	"balanced": {
		"max_tokens": 8000,
		"traversal_depth": 2,
		"allowed_relationship_types": [
			"contains", "depends_on", "supports", "derived_from", "refines",
		],
	},
	"minimal": {
		"max_tokens": 3000,
		"traversal_depth": 1,
		"allowed_relationship_types": ["contains", "supports"],
	},
}

var _activation_policy: RefCounted = ContextActivationPolicyScript.new()


func compile(
	document: Dictionary,
	context_set: Dictionary,
	options: Dictionary = {}
) -> Dictionary:
	var node_by_id: Dictionary = _records_by_id(document.get("nodes", []))
	var adjacency: Dictionary = _build_adjacency(document.get("edges", []))
	var preset_id: String = str(options.get("preset", "balanced")).to_lower()
	var policy: Dictionary = PRESETS.get(preset_id, PRESETS["balanced"]).duplicate(true)
	_merge_policy(policy, context_set)
	_merge_policy(policy, options)
	var entry_ids: Array[String] = _string_array(
		context_set.get("entry_node_ids", [])
	)
	var pinned_ids: Array[String] = _string_array(options.get("pinned_node_ids", []))
	var traversal: Dictionary = _traverse(
		entry_ids,
		node_by_id,
		adjacency,
		int(policy.get("traversal_depth", 0)),
		_string_array(policy.get("allowed_relationship_types", []))
	)
	var ordered_ids: Array[String] = traversal.get("ordered_ids", [])
	var activation_context: Dictionary = options.get("activation_context", {})
	var always_ids: Array[String] = _activation_policy.call(
		"always_node_ids",
		document.get("nodes", []),
		activation_context
	)
	for always_id in always_ids:
		if not ordered_ids.has(always_id):
			ordered_ids.append(always_id)
	for pinned_id in pinned_ids:
		if node_by_id.has(pinned_id) and not ordered_ids.has(pinned_id):
			ordered_ids.push_front(pinned_id)
	ordered_ids = _pinned_first(ordered_ids, pinned_ids)

	var max_tokens: int = maxi(0, int(policy.get("max_tokens", 0)))
	var included: Array = []
	var omitted: Array = []
	var text_parts: Array[String] = []
	var used_tokens: int = 0
	for node_id in ordered_ids:
		var node_data: Dictionary = node_by_id.get(node_id, {})
		var node_text: String = _node_text(node_data)
		var token_estimate: int = estimate_tokens(node_text)
		var is_pinned: bool = pinned_ids.has(node_id)
		var activation_result: Dictionary = _activation_policy.call(
			"evaluate",
			node_data,
			activation_context,
			entry_ids.has(node_id),
			bool((traversal.get("paths", {}) as Dictionary).has(node_id)),
			is_pinned
		)
		if not bool(activation_result.get("include", false)):
			omitted.append({
				"node_id": node_id,
				"reason": str(activation_result.get("reason", "activation")),
				"estimated_tokens": token_estimate,
			})
			continue
		if (
			not is_pinned
			and max_tokens > 0
			and used_tokens + token_estimate > max_tokens
		):
			omitted.append({
				"node_id": node_id,
				"reason": "token_budget",
				"estimated_tokens": token_estimate,
			})
			continue
		included.append({
			"node_id": node_id,
			"order": included.size(),
			"reason": _inclusion_reason(
				activation_result,
				traversal,
				node_id,
				is_pinned
			),
			"traversal_path": traversal.get("paths", {}).get(node_id, [node_id]),
			"estimated_tokens": token_estimate,
		})
		text_parts.append(node_text)
		used_tokens += token_estimate
	return {
		"ok": true,
		"included_nodes": included,
		"omitted_nodes": omitted,
		"compiled_text": "\n\n".join(text_parts),
		"estimated_tokens": used_tokens,
		"token_budget": max_tokens,
		"is_over_budget": max_tokens > 0 and used_tokens > max_tokens,
		"estimator_id": ESTIMATOR_ID,
		"model_id": str(options.get("model_id", "")),
		"graph_artifact_id": str(options.get("graph_artifact_id", "")),
		"graph_version_id": str(options.get("graph_version_id", "")),
		"context_set_id": str(context_set.get("id", "")),
		"policy": policy,
	}


func _inclusion_reason(
	activation_result: Dictionary,
	traversal: Dictionary,
	node_id: String,
	is_pinned: bool
) -> String:
	if is_pinned:
		return "pinned"
	var activation_reason: String = str(activation_result.get("reason", ""))
	if activation_reason in ["activation:always", "activation:conditional"]:
		return activation_reason
	return str(traversal.get("reasons", {}).get(node_id, activation_reason))


func preset(preset_id: String) -> Dictionary:
	return PRESETS.get(
		preset_id.to_lower(),
		PRESETS["balanced"]
	).duplicate(true)


func estimate_tokens(content_text: String) -> int:
	if content_text.is_empty():
		return 0
	return maxi(1, int(ceil(float(content_text.length()) / 4.0)))


func _traverse(
	entry_ids: Array[String],
	node_by_id: Dictionary,
	adjacency: Dictionary,
	max_depth: int,
	allowed_relations: Array[String]
) -> Dictionary:
	var ordered_ids: Array[String] = []
	var reasons: Dictionary = {}
	var paths: Dictionary = {}
	var visited_depth: Dictionary = {}
	var pending: Array = []
	for entry_id in entry_ids:
		pending.append({"id": entry_id, "depth": 0, "path": [entry_id]})
		reasons[entry_id] = "entry"
	while not pending.is_empty():
		var current: Dictionary = pending.pop_front()
		var node_id: String = str(current.get("id", ""))
		var depth: int = int(current.get("depth", 0))
		if not node_by_id.has(node_id):
			continue
		if visited_depth.has(node_id) and int(visited_depth[node_id]) <= depth:
			continue
		visited_depth[node_id] = depth
		if not ordered_ids.has(node_id):
			ordered_ids.append(node_id)
			paths[node_id] = current.get("path", [node_id])
		if depth >= max_depth:
			continue
		var outgoing: Array = adjacency.get(node_id, [])
		for edge_any in outgoing:
			var edge_data: Dictionary = edge_any
			var relation_id: String = str(edge_data.get("relation", ""))
			if not allowed_relations.is_empty() and not allowed_relations.has(relation_id):
				continue
			var to_id: String = str(edge_data.get("to", ""))
			var next_path: Array = (current.get("path", []) as Array).duplicate()
			next_path.append(to_id)
			if not reasons.has(to_id):
				reasons[to_id] = "via:%s" % relation_id
			pending.append({"id": to_id, "depth": depth + 1, "path": next_path})
	return {"ordered_ids": ordered_ids, "reasons": reasons, "paths": paths}


func _build_adjacency(edges_any: Variant) -> Dictionary:
	var adjacency: Dictionary = {}
	if typeof(edges_any) != TYPE_ARRAY:
		return adjacency
	for edge_any in (edges_any as Array):
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		if str(edge_data.get("status", "")) == "rejected":
			continue
		var from_id: String = str(edge_data.get("from", ""))
		var outgoing: Array = adjacency.get(from_id, [])
		outgoing.append(edge_data)
		outgoing.sort_custom(_sort_edges)
		adjacency[from_id] = outgoing
	return adjacency


func _sort_edges(left: Dictionary, right: Dictionary) -> bool:
	var left_key: String = "%s|%s|%s" % [
		str(left.get("relation", "")),
		str(left.get("to", "")),
		str(left.get("id", "")),
	]
	var right_key: String = "%s|%s|%s" % [
		str(right.get("relation", "")),
		str(right.get("to", "")),
		str(right.get("id", "")),
	]
	return left_key < right_key


func _pinned_first(
	ordered_ids: Array[String],
	pinned_ids: Array[String]
) -> Array[String]:
	var result: Array[String] = []
	for pinned_id in pinned_ids:
		if ordered_ids.has(pinned_id) and not result.has(pinned_id):
			result.append(pinned_id)
	for node_id in ordered_ids:
		if not result.has(node_id):
			result.append(node_id)
	return result


func _node_text(node_data: Dictionary) -> String:
	var annotations: Dictionary = node_data.get("annotations", {})
	var content_text: String = str(annotations.get("content", ""))
	if content_text.is_empty():
		content_text = str(node_data.get("label", ""))
	return content_text


func _records_by_id(records_any: Variant) -> Dictionary:
	var by_id: Dictionary = {}
	if typeof(records_any) != TYPE_ARRAY:
		return by_id
	for record_any in (records_any as Array):
		if typeof(record_any) != TYPE_DICTIONARY:
			continue
		var record_data: Dictionary = record_any
		var record_id: String = str(record_data.get("id", ""))
		if not record_id.is_empty():
			by_id[record_id] = record_data
	return by_id


func _string_array(values_any: Variant) -> Array[String]:
	var values: Array[String] = []
	if typeof(values_any) != TYPE_ARRAY:
		return values
	for value_any in (values_any as Array):
		values.append(str(value_any))
	return values


func _merge_policy(target: Dictionary, source: Dictionary) -> void:
	for key_id in [
		"max_tokens",
		"traversal_depth",
		"allowed_relationship_types",
		"truncation_policy",
	]:
		if source.has(key_id):
			target[key_id] = source[key_id]
	var budget_policy_any: Variant = source.get("budget_policy", null)
	if typeof(budget_policy_any) == TYPE_DICTIONARY:
		_merge_policy(target, budget_policy_any)
