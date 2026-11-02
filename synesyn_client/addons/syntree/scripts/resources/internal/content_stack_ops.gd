## Purpose: Internal stack mutation helpers for ContentStateResource (no persistence, no signals)
extends RefCounted

## Internal helper: stack-related pure(ish) ops over a stack source data dictionary.
## No signals, no saving, no ContentBus. Returns a result dictionary.

func _ensure_meta_ai_context(d: Dictionary) -> Dictionary:
	# Ensures d.meta.ai_context exists (as dictionaries). Returns the mutated dictionary.
	if not d.has("meta") or not (d.get("meta") is Dictionary):
		d["meta"] = {}
	if not (d["meta"] as Dictionary).has("ai_context") or not ((d["meta"] as Dictionary).get("ai_context") is Dictionary):
		(d["meta"] as Dictionary)["ai_context"] = {}
	return d

func reorder_stack_member_source(stack_source_data: Dictionary, member_source_id: String, delta: int) -> Dictionary:
	# Returns:
	# { success: bool, error: String, changed: bool, data: Dictionary }
	var sid := String(member_source_id).strip_edges()
	if sid.is_empty():
		return {"success": false, "error": "Empty member source id", "changed": false, "data": stack_source_data}
	if delta == 0:
		return {"success": true, "error": "", "changed": false, "data": stack_source_data}

	var d: Dictionary = stack_source_data
	var ai: Variant = d.get("meta", {}).get("ai_context", {})
	if not (ai is Dictionary):
		return {"success": false, "error": "Stack has no ai_context", "changed": false, "data": d}
	var arr_any: Variant = (ai as Dictionary).get("stack_sources", [])
	if not (arr_any is Array):
		return {"success": false, "error": "Stack has no stack_sources array", "changed": false, "data": d}

	var sources_arr: Array = arr_any
	var cur_idx := -1
	for i in range(sources_arr.size()):
		var entry: Variant = sources_arr[i]
		var entry_id := ""
		if entry is Dictionary:
			entry_id = String(entry.get("id", entry.get("source_id", ""))).strip_edges()
		else:
			entry_id = String(entry).strip_edges()
		if entry_id == sid:
			cur_idx = i
			break

	if cur_idx == -1:
		return {"success": false, "error": "Member source not found in stack: %s" % sid, "changed": false, "data": d}

	var new_idx := cur_idx + delta
	if new_idx < 0 or new_idx >= sources_arr.size():
		return {"success": true, "error": "", "changed": false, "data": d} # no-op at bounds

	var tmp: Variant = sources_arr[cur_idx]
	sources_arr[cur_idx] = sources_arr[new_idx]
	sources_arr[new_idx] = tmp

	(ai as Dictionary)["stack_sources"] = sources_arr
	d["meta"] = d.get("meta", {})
	(d["meta"] as Dictionary)["ai_context"] = ai

	return {"success": true, "error": "", "changed": true, "data": d}

func set_stack_edges_data(stack_source_data: Dictionary, stack_edges_key: String, edges: Array) -> Dictionary:
	# { success, error, changed, data }
	var d: Dictionary = _ensure_meta_ai_context(stack_source_data)
	var ai: Dictionary = (d["meta"] as Dictionary).get("ai_context", {})
	var before: Variant = ai.get(stack_edges_key)
	ai[stack_edges_key] = edges
	(d["meta"] as Dictionary)["ai_context"] = ai
	var changed := true
	if before is Array and (before as Array) == edges:
		changed = false
	return {"success": true, "error": "", "changed": changed, "data": d}

func add_stack_edge_data(
	stack_source_data: Dictionary,
	stack_edges_key: String,
	from_id: String,
	to_id: String
) -> Dictionary:
	var from_node_id: String = from_id.strip_edges()
	var to_node_id: String = to_id.strip_edges()
	if from_node_id.is_empty() or to_node_id.is_empty():
		return {
			"success": false,
			"error": "Empty from/to node id",
			"changed": false,
			"data": stack_source_data,
		}
	var d: Dictionary = _ensure_meta_ai_context(stack_source_data)
	var ai_context: Dictionary = (d["meta"] as Dictionary).get(
		"ai_context",
		{}
	)
	var edges_any: Variant = ai_context.get(stack_edges_key, [])
	var edges: Array = edges_any if edges_any is Array else []
	for edge_any in edges:
		if edge_any is Dictionary:
			var edge_data: Dictionary = edge_any
			if (
				str(edge_data.get("from", "")) == from_node_id
				and str(edge_data.get("to", "")) == to_node_id
			):
				return {
					"success": true,
					"error": "",
					"changed": false,
					"data": d,
				}
	edges.append({"from": from_node_id, "to": to_node_id})
	ai_context[stack_edges_key] = edges
	(d["meta"] as Dictionary)["ai_context"] = ai_context
	return {"success": true, "error": "", "changed": true, "data": d}

func remove_stack_edge_data(
	stack_source_data: Dictionary,
	stack_edges_key: String,
	from_id: String,
	to_id: String
) -> Dictionary:
	var from_node_id: String = from_id.strip_edges()
	var to_node_id: String = to_id.strip_edges()
	if from_node_id.is_empty() or to_node_id.is_empty():
		return {
			"success": false,
			"error": "Empty from/to node id",
			"changed": false,
			"data": stack_source_data,
		}
	var d: Dictionary = _ensure_meta_ai_context(stack_source_data)
	var ai_context: Dictionary = (d["meta"] as Dictionary).get(
		"ai_context",
		{}
	)
	var edges_any: Variant = ai_context.get(stack_edges_key, [])
	var edges: Array = edges_any if edges_any is Array else []
	var kept_edges: Array = []
	var has_changed: bool = false
	for edge_any in edges:
		if edge_any is Dictionary:
			var edge_data: Dictionary = edge_any
			if (
				str(edge_data.get("from", "")) == from_node_id
				and str(edge_data.get("to", "")) == to_node_id
			):
				has_changed = true
				continue
		kept_edges.append(edge_any)
	ai_context[stack_edges_key] = kept_edges
	(d["meta"] as Dictionary)["ai_context"] = ai_context
	return {
		"success": true,
		"error": "",
		"changed": has_changed,
		"data": d,
	}

func set_stack_include_unwired_nodes_data(stack_source_data: Dictionary, include_unwired_key: String, enabled: bool) -> Dictionary:
	# { success, error, changed, data }
	var d: Dictionary = _ensure_meta_ai_context(stack_source_data)
	var ai: Dictionary = (d["meta"] as Dictionary).get("ai_context", {})
	var before: bool = bool(ai.get(include_unwired_key, true))
	ai[include_unwired_key] = enabled
	(d["meta"] as Dictionary)["ai_context"] = ai
	return {"success": true, "error": "", "changed": before != enabled, "data": d}

func set_stack_layout_position_data(stack_source_data: Dictionary, layout_key: String, positions_key: String, composed_node_id: String, position: Vector2) -> Dictionary:
	# { success, error, changed, data }
	var cid := String(composed_node_id).strip_edges()
	if cid.is_empty():
		return {"success": false, "error": "Empty composed_node_id", "changed": false, "data": stack_source_data}
	var d: Dictionary = _ensure_meta_ai_context(stack_source_data)
	var ai: Dictionary = (d["meta"] as Dictionary).get("ai_context", {})

	var layout_any: Variant = ai.get(layout_key, {})
	var layout: Dictionary = layout_any if layout_any is Dictionary else {}

	var pos_any: Variant = layout.get(positions_key, {})
	var pos: Dictionary = pos_any if pos_any is Dictionary else {}

	var before: Variant = pos.get(cid)
	var entry := {"x": position.x, "y": position.y}
	pos[cid] = entry
	layout[positions_key] = pos
	ai[layout_key] = layout
	(d["meta"] as Dictionary)["ai_context"] = ai

	var changed := true
	if before is Dictionary and (before as Dictionary).get("x") == position.x and (before as Dictionary).get("y") == position.y:
		changed = false
	return {"success": true, "error": "", "changed": changed, "data": d}
