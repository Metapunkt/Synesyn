## Purpose: Internal hierarchy mutation helpers for ContentStateResource (no persistence, no signals)
extends RefCounted

## Internal helper: pure(ish) hierarchy reordering ops over a source's `content.nodes` array.
## No signals, no saving, no ContentBus. Returns a result dictionary.
##
## Expected input: nodes already normalized so relationships arrays contain valid ids.
func move_node(nodes: Array, raw_id: String, delta: int, rel_parents_key: String, rel_children_key: String) -> Dictionary:
	# Returns:
	# { success: bool, error: String, changed: bool, nodes: Array }
	var rid := String(raw_id).strip_edges()
	if rid.is_empty():
		return {"success": false, "error": "Empty node id", "changed": false, "nodes": nodes}
	if delta == 0:
		return {"success": true, "error": "", "changed": false, "nodes": nodes}

	# Build id -> index map
	var id_to_index := {}
	for i in range(nodes.size()):
		var n_any: Variant = nodes[i]
		if n_any is Dictionary:
			var idv := String((n_any as Dictionary).get("node_id", "")).strip_edges()
			if not idv.is_empty():
				id_to_index[idv] = i

	if not id_to_index.has(rid):
		return {"success": false, "error": "Node not found: %s" % rid, "changed": false, "nodes": nodes}

	# Find first valid parent (authoritative).
	var parent_id := ""
	var node_dict: Dictionary = nodes[int(id_to_index[rid])]
	var rel_v: Variant = node_dict.get("relationships", {})
	if rel_v is Dictionary:
		var parents_v: Variant = (rel_v as Dictionary).get(rel_parents_key, [])
		if parents_v is Array:
			for pid_any in (parents_v as Array):
				var pid := String(pid_any).strip_edges()
				if id_to_index.has(pid):
					parent_id = pid
					break

	# If it has a parent: reorder within parent's children list.
	if not parent_id.is_empty():
		var pidx := int(id_to_index[parent_id])
		var parent_node: Dictionary = nodes[pidx]
		var prel_v: Variant = parent_node.get("relationships", {})
		if not (prel_v is Dictionary):
			return {"success": false, "error": "Parent relationships missing for: %s" % parent_id, "changed": false, "nodes": nodes}
		var children_v: Variant = (prel_v as Dictionary).get(rel_children_key, [])
		if not (children_v is Array):
			return {"success": false, "error": "Parent children list missing for: %s" % parent_id, "changed": false, "nodes": nodes}
		var children: Array = children_v
		var cur := children.find(rid)
		if cur == -1:
			return {"success": false, "error": "Child not present in parent's children list", "changed": false, "nodes": nodes}
		var nxt := cur + delta
		if nxt < 0 or nxt >= children.size():
			return {"success": true, "error": "", "changed": false, "nodes": nodes} # no-op at bounds
		var tmp: Variant = children[cur]
		children[cur] = children[nxt]
		children[nxt] = tmp
		var prel: Dictionary = prel_v
		prel[rel_children_key] = children
		parent_node["relationships"] = prel
		nodes[pidx] = parent_node
		return {"success": true, "error": "", "changed": true, "nodes": nodes}

	# Root node: reorder among root nodes by swapping their positions in the nodes array.
	var root_indices: Array[int] = []
	for i in range(nodes.size()):
		var n_any2: Variant = nodes[i]
		if not (n_any2 is Dictionary):
			continue
		var n2: Dictionary = n_any2 as Dictionary
		var id2 := String(n2.get("node_id", "")).strip_edges()
		if id2.is_empty():
			continue
		var rel2_v: Variant = n2.get("relationships", {})
		var parents2: Array = []
		if rel2_v is Dictionary:
			var pv: Variant = (rel2_v as Dictionary).get(rel_parents_key, [])
			if pv is Array:
				parents2 = pv
		var has_valid_parent := false
		for pid_any2 in parents2:
			var pid2 := String(pid_any2).strip_edges()
			if id_to_index.has(pid2):
				has_valid_parent = true
				break
		var is_root := bool(n2.get("is_root", false)) or not has_valid_parent
		if is_root:
			root_indices.append(i)

	var cur_pos := -1
	for ri in range(root_indices.size()):
		var idx := int(root_indices[ri])
		if nodes[idx] is Dictionary and String((nodes[idx] as Dictionary).get("node_id", "")).strip_edges() == rid:
			cur_pos = ri
			break
	if cur_pos == -1:
		return {"success": false, "error": "Root node not found among roots", "changed": false, "nodes": nodes}

	var new_pos := cur_pos + delta
	if new_pos < 0 or new_pos >= root_indices.size():
		return {"success": true, "error": "", "changed": false, "nodes": nodes} # no-op at bounds

	var a := int(root_indices[cur_pos])
	var b := int(root_indices[new_pos])
	var tmpn: Variant = nodes[a]
	nodes[a] = nodes[b]
	nodes[b] = tmpn
	return {"success": true, "error": "", "changed": true, "nodes": nodes}


