## Purpose: Internal helpers for mutating persisted node fields (no saving, no signals)
extends RefCounted

func set_node_position(nodes: Array, node_id: String, position: Vector2) -> Dictionary:
	# Returns: { success: bool, error: String, changed: bool, nodes: Array }
	var nid := String(node_id).strip_edges()
	if nid.is_empty():
		return {"success": false, "error": "Empty node id", "changed": false, "nodes": nodes}
	for i in range(nodes.size()):
		var n_any: Variant = nodes[i]
		if not (n_any is Dictionary):
			continue
		var n: Dictionary = n_any
		if String(n.get("node_id", "")).strip_edges() != nid:
			continue
		n["position"] = {"x": position.x, "y": position.y}
		nodes[i] = n
		return {"success": true, "error": "", "changed": true, "nodes": nodes}
	return {"success": false, "error": "Node not found: %s" % nid, "changed": false, "nodes": nodes}

func remove_node_and_unlink(
	nodes: Array,
	node_id: String,
	relationship_keys: Array[String]
) -> Dictionary:
	var node_id_clean: String = node_id.strip_edges()
	if node_id_clean.is_empty():
		return {
			"success": false,
			"error": "Empty node id",
			"changed": false,
			"nodes": nodes,
		}
	var has_removed: bool = false
	for node_index in range(nodes.size() - 1, -1, -1):
		var node_any: Variant = nodes[node_index]
		if (
			node_any is Dictionary
			and str((node_any as Dictionary).get("node_id", "")).strip_edges()
				== node_id_clean
		):
			nodes.remove_at(node_index)
			has_removed = true
			break
	if not has_removed:
		return {
			"success": false,
			"error": "Node not found: %s" % node_id_clean,
			"changed": false,
			"nodes": nodes,
		}

	for node_any in nodes:
		if not node_any is Dictionary:
			continue
		var node_data: Dictionary = node_any
		var relationships_any: Variant = node_data.get("relationships", null)
		if typeof(relationships_any) != TYPE_DICTIONARY:
			continue
		var relationships: Dictionary = relationships_any
		for relationship_key in relationship_keys:
			var refs_any: Variant = relationships.get(relationship_key, [])
			if refs_any is Array:
				(refs_any as Array).erase(node_id_clean)
				relationships[relationship_key] = refs_any
		node_data["relationships"] = relationships
	return {"success": true, "error": "", "changed": true, "nodes": nodes}


