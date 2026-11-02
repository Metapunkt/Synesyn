## Purpose: Internal edge mutation helpers for ContentStateResource (no persistence, no signals)
extends RefCounted

## Mutate a normalized nodes array to add/remove an edge.
## This does not normalize, save, or emit signals.
##
## Returns:
## { success: bool, error: String, changed: bool, nodes: Array }
func mutate_edge(nodes: Array, kind: String, from_node_id: String, to_node_id: String, add: bool, rel_parents_key: String, rel_children_key: String, rel_deps_key: String, rel_assoc_key: String) -> Dictionary:
	var k := String(kind).strip_edges()
	var from_n := String(from_node_id).strip_edges()
	var to_n := String(to_node_id).strip_edges()
	if k.is_empty():
		k = "child"
	if from_n.is_empty() or to_n.is_empty():
		return {"success": false, "error": "Empty from/to node id", "changed": false, "nodes": nodes}
	if from_n == to_n:
		return {"success": false, "error": "Self-edge not allowed", "changed": false, "nodes": nodes}

	# Build id -> index map
	var id_to_index := {}
	for i in range(nodes.size()):
		var n_any: Variant = nodes[i]
		if n_any is Dictionary:
			var nid := String((n_any as Dictionary).get("node_id", "")).strip_edges()
			if not nid.is_empty():
				id_to_index[nid] = i

	if not id_to_index.has(from_n) or not id_to_index.has(to_n):
		return {"success": false, "error": "from/to node not found in nodes array", "changed": false, "nodes": nodes}

	var fi := int(id_to_index[from_n])
	var ti := int(id_to_index[to_n])
	var fn: Dictionary = nodes[fi]
	var tn: Dictionary = nodes[ti]
	var fr_any: Variant = fn.get("relationships", {})
	var tr_any: Variant = tn.get("relationships", {})
	if not (fr_any is Dictionary) or not (tr_any is Dictionary):
		return {"success": false, "error": "relationships missing (expected normalized nodes)", "changed": false, "nodes": nodes}
	var fr: Dictionary = fr_any
	var tr: Dictionary = tr_any

	var changed := false
	match k:
		"child":
			if add:
				var children: Array = fr.get(rel_children_key, [])
				if not children.has(to_n):
					children.append(to_n)
					fr[rel_children_key] = children
					changed = true
				# Keep symmetric for immediate correctness (parents are rebuilt by normalization anyway).
				var parents: Array = tr.get(rel_parents_key, [])
				if not parents.has(from_n):
					parents.append(from_n)
					tr[rel_parents_key] = parents
					changed = true
			else:
				var children2: Array = fr.get(rel_children_key, [])
				if children2.has(to_n):
					children2.erase(to_n)
					fr[rel_children_key] = children2
					changed = true
				var parents2: Array = tr.get(rel_parents_key, [])
				if parents2.has(from_n):
					parents2.erase(from_n)
					tr[rel_parents_key] = parents2
					changed = true
		"depends":
			if add:
				var deps: Array = fr.get(rel_deps_key, [])
				if not deps.has(to_n):
					deps.append(to_n)
					fr[rel_deps_key] = deps
					changed = true
			else:
				var deps2: Array = fr.get(rel_deps_key, [])
				if deps2.has(to_n):
					deps2.erase(to_n)
					fr[rel_deps_key] = deps2
					changed = true
		"assoc":
			if add:
				var assoc: Array = fr.get(rel_assoc_key, [])
				if not assoc.has(to_n):
					assoc.append(to_n)
					fr[rel_assoc_key] = assoc
					changed = true
			else:
				var assoc2: Array = fr.get(rel_assoc_key, [])
				if assoc2.has(to_n):
					assoc2.erase(to_n)
					fr[rel_assoc_key] = assoc2
					changed = true
		_:
			return {"success": false, "error": "Unknown edge kind: %s" % k, "changed": false, "nodes": nodes}

	if not changed:
		return {"success": true, "error": "", "changed": false, "nodes": nodes}

	fn["relationships"] = fr
	tn["relationships"] = tr
	nodes[fi] = fn
	nodes[ti] = tn
	return {"success": true, "error": "", "changed": true, "nodes": nodes}
