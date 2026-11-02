extends RefCounted
class_name WorkshopThinkingMapSymbolicRules

## Purpose: The neurosymbolic bridge over the Thinking Map's typed graph.
##
## Specialists and facilitators produce typed claims (nodes) and typed
## relations (edges) — that half is neural/human judgment. This module runs
## deterministic, explainable rules over that structure: no prompt can
## reliably guarantee a model notices a contradiction buried three turns
## back, or that a claim it is leaning on is still evidentially unsupported.
## Read-only: it only derives findings, never mutates the document, and it
## has no opinion on review actions (that stays the facilitator's call).

## Rejected nodes/edges are dead weight for reasoning purposes; everything
## still under active consideration (suggested, accepted, edited) counts.
const _INACTIVE_STATUSES: Array[String] = ["rejected"]
const _WEAK_EVIDENCE_STATUSES: Array[String] = ["unknown", "unsupported"]
const _LOAD_BEARING_RELATIONS: Array[String] = ["causes", "supports"]
## Longest causal path (in nodes) worth reporting. Kept small: a chain this
## long is already a lot for a facilitator to hold in view, and unbounded
## depth risks combinatorial blowup on a busy map.
const MAX_CHAIN_LENGTH: int = 4


static func evaluate(document: Dictionary) -> Dictionary:
	var nodes_by_id: Dictionary = _nodes_by_id(document)
	var edges: Array[Dictionary] = _active_edges(document, nodes_by_id)
	return {
		"contradictions": _find_contradictions(edges, nodes_by_id),
		"causal_chains": _find_causal_chains(edges, nodes_by_id),
		"evidence_gaps": _find_evidence_gaps(edges, nodes_by_id),
	}


static func _nodes_by_id(document: Dictionary) -> Dictionary:
	var nodes_by_id: Dictionary = {}
	var nodes_any: Variant = document.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return nodes_by_id
	for node_any: Variant in (nodes_any as Array):
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		var node_id: String = String(node_data.get("id", "")).strip_edges()
		if not node_id.is_empty():
			nodes_by_id[node_id] = node_data
	return nodes_by_id


static func _active_edges(document: Dictionary, nodes_by_id: Dictionary) -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	var edges_any: Variant = document.get("edges", [])
	if typeof(edges_any) != TYPE_ARRAY:
		return active
	for edge_any: Variant in (edges_any as Array):
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		if String(edge_data.get("status", "")) in _INACTIVE_STATUSES:
			continue
		var from_id: String = String(edge_data.get("from", ""))
		var to_id: String = String(edge_data.get("to", ""))
		if not nodes_by_id.has(from_id) or not nodes_by_id.has(to_id):
			continue
		if (
			String((nodes_by_id[from_id] as Dictionary).get("status", "")) in _INACTIVE_STATUSES
			or String((nodes_by_id[to_id] as Dictionary).get("status", "")) in _INACTIVE_STATUSES
		):
			continue
		active.append(edge_data)
	return active


static func _find_contradictions(
	edges: Array[Dictionary],
	nodes_by_id: Dictionary
) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	for edge_data: Dictionary in edges:
		if String(edge_data.get("relation", "")) != "contradicts":
			continue
		var from_id: String = String(edge_data.get("from", ""))
		var to_id: String = String(edge_data.get("to", ""))
		var from_label: String = _label_for(nodes_by_id, from_id)
		var to_label: String = _label_for(nodes_by_id, to_id)
		findings.append({
			"kind": "contradiction",
			"edge_id": String(edge_data.get("id", "")),
			"from_id": from_id,
			"to_id": to_id,
			"summary": "\"%s\" contradicts \"%s\"." % [from_label.left(80), to_label.left(80)],
		})
	return findings


## Finds every distinct causes-chain of 3+ nodes (A causes B causes C, ...).
## These are *derived* insights for the facilitator to weigh, never written
## back as new edges — materializing them would blur what the room actually
## asserted versus what this layer inferred from what they asserted.
static func _find_causal_chains(
	edges: Array[Dictionary],
	nodes_by_id: Dictionary
) -> Array[Dictionary]:
	var adjacency: Dictionary = {}
	for edge_data: Dictionary in edges:
		if String(edge_data.get("relation", "")) != "causes":
			continue
		var from_id: String = String(edge_data.get("from", ""))
		if not adjacency.has(from_id):
			adjacency[from_id] = [] as Array[String]
		(adjacency[from_id] as Array).append(String(edge_data.get("to", "")))
	var chains: Array[Dictionary] = []
	var seen_chain_keys: Dictionary = {}
	for start_id_any: Variant in adjacency.keys():
		var start_path: Array[String] = [String(start_id_any)]
		_walk_causal_chain(String(start_id_any), adjacency, start_path, nodes_by_id, chains, seen_chain_keys)
	return chains


static func _walk_causal_chain(
	current_id: String,
	adjacency: Dictionary,
	path: Array[String],
	nodes_by_id: Dictionary,
	chains: Array[Dictionary],
	seen_chain_keys: Dictionary
) -> void:
	if path.size() >= MAX_CHAIN_LENGTH:
		return
	var next_ids_any: Variant = adjacency.get(current_id, [])
	if typeof(next_ids_any) != TYPE_ARRAY:
		return
	for next_id_any: Variant in (next_ids_any as Array):
		var next_id: String = String(next_id_any)
		if next_id in path:
			continue  # guard against cycles; this is a facilitator-editable graph
		var extended_path: Array[String] = path.duplicate()
		extended_path.append(next_id)
		if extended_path.size() >= 3:
			var chain_key: String = "|".join(extended_path)
			if not seen_chain_keys.has(chain_key):
				seen_chain_keys[chain_key] = true
				var labels: Array[String] = []
				for node_id: String in extended_path:
					labels.append(_label_for(nodes_by_id, node_id))
				chains.append({
					"kind": "transitive_causal_chain",
					"node_ids": extended_path.duplicate(),
					"summary": " \u2192 ".join(labels.map(
						func(label_text: String) -> String: return label_text.left(60)
					)),
				})
		_walk_causal_chain(next_id, adjacency, extended_path, nodes_by_id, chains, seen_chain_keys)


## Flags a node that other accepted-or-suggested claims are structurally
## leaning on (it feeds a causes/supports edge) while its own evidence is
## still "unknown" or "unsupported" — the facilitator-visible version of a
## missing premise.
static func _find_evidence_gaps(
	edges: Array[Dictionary],
	nodes_by_id: Dictionary
) -> Array[Dictionary]:
	var findings: Array[Dictionary] = []
	var flagged_node_ids: Dictionary = {}
	for edge_data: Dictionary in edges:
		var relation_id: String = String(edge_data.get("relation", ""))
		if relation_id not in _LOAD_BEARING_RELATIONS:
			continue
		var from_id: String = String(edge_data.get("from", ""))
		if flagged_node_ids.has(from_id):
			continue
		var from_node: Dictionary = nodes_by_id.get(from_id, {})
		var provenance_any: Variant = from_node.get("provenance", {})
		var provenance: Dictionary = (
			provenance_any if typeof(provenance_any) == TYPE_DICTIONARY else {}
		)
		var evidence_status: String = String(provenance.get("evidence_status", "unknown"))
		if evidence_status not in _WEAK_EVIDENCE_STATUSES:
			continue
		flagged_node_ids[from_id] = true
		var label_text: String = _label_for(nodes_by_id, from_id)
		findings.append({
			"kind": "evidence_gap",
			"node_id": from_id,
			"evidence_status": evidence_status,
			"summary": "\"%s\" carries weight via %s but its evidence is %s." % [
				label_text.left(80),
				relation_id,
				evidence_status,
			],
		})
	return findings


static func _label_for(nodes_by_id: Dictionary, node_id: String) -> String:
	var node_any: Variant = nodes_by_id.get(node_id, {})
	if typeof(node_any) != TYPE_DICTIONARY:
		return node_id
	return String((node_any as Dictionary).get("label", node_id)).strip_edges()
