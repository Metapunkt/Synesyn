## Purpose: Internal stack ordering helpers for ContentStateResource (read-only; no persistence, no signals)
extends RefCounted

func _parse_source_id_from_composed_id(composed_id: String, sep: String) -> String:
	var s := String(composed_id).strip_edges()
	if s.is_empty():
		return ""
	var idx := s.find(sep)
	if idx == -1:
		return ""
	return s.substr(0, idx).strip_edges()

## Computes unwired member source ids.
## A member source is “wired” if it appears in any cross-source stack edge (in or out).
func compute_unwired_members(members: Array[String], edges: Array, composed_sep: String) -> Array[String]:
	if members.is_empty():
		return []
	var member_set := {}
	for m in members:
		member_set[m] = true

	var wired := {}
	for e_any in edges:
		if not (e_any is Dictionary):
			continue
		var e: Dictionary = e_any
		var from_id := String(e.get("from", "")).strip_edges()
		var to_id := String(e.get("to", "")).strip_edges()
		if from_id.is_empty() or to_id.is_empty():
			continue
		if not from_id.contains(composed_sep) or not to_id.contains(composed_sep):
			continue
		var sf := _parse_source_id_from_composed_id(from_id, composed_sep)
		var st := _parse_source_id_from_composed_id(to_id, composed_sep)
		if sf == "" or st == "" or sf == st:
			continue
		if member_set.has(sf):
			wired[sf] = true
		if member_set.has(st):
			wired[st] = true

	var unwired: Array[String] = []
	for m2 in members:
		if not wired.has(m2):
			unwired.append(m2)
	return unwired

## Deterministic ordering:
## - if include_unwired=true: stable topological order induced by stack edges, with unwired appended in declared order.
## - if include_unwired=false: topo order of “wired” members only; if none wired, fall back to declared member order.
func compute_ordered_members(members: Array[String], edges: Array, include_unwired: bool, composed_sep: String) -> Array[String]:
	if members.is_empty():
		return []

	var member_index := {}
	for i in range(members.size()):
		member_index[members[i]] = i

	# adjacency + indegree over member sources
	var adj := {}        # src -> Array[String]
	var indeg := {}      # src -> int
	for m in members:
		adj[m] = []
		indeg[m] = 0

	for e_any in edges:
		if not (e_any is Dictionary):
			continue
		var e: Dictionary = e_any
		var from_id := String(e.get("from", "")).strip_edges()
		var to_id := String(e.get("to", "")).strip_edges()
		if from_id.is_empty() or to_id.is_empty():
			continue
		if not from_id.contains(composed_sep) or not to_id.contains(composed_sep):
			continue
		var sf := _parse_source_id_from_composed_id(from_id, composed_sep)
		var st := _parse_source_id_from_composed_id(to_id, composed_sep)
		if sf == "" or st == "" or sf == st:
			continue
		if not member_index.has(sf) or not member_index.has(st):
			continue
		var out: Array = adj[sf]
		if not out.has(st):
			out.append(st)
			adj[sf] = out
			indeg[st] = int(indeg[st]) + 1

	# If strict mode, restrict universe to nodes that appear in any edge.
	var universe: Array[String] = members
	if not include_unwired:
		var wired_set := {}
		for m in members:
			if int(indeg[m]) > 0:
				wired_set[m] = true
		for m in members:
			if (adj[m] as Array).size() > 0:
				wired_set[m] = true
		universe = []
		for m in members:
			if wired_set.has(m):
				universe.append(m)
		# If nothing is wired, fall back to including all members in declared order.
		if universe.is_empty():
			return members

	# Kahn topo sort with stable tie-break using member list order.
	var indeg2 := {}
	for m in universe:
		indeg2[m] = int(indeg[m])
	var ready: Array[String] = []
	for m in universe:
		if int(indeg2[m]) == 0:
			ready.append(m)
	ready.sort_custom(func(a, b): return int(member_index[a]) < int(member_index[b]))

	var out_order: Array[String] = []
	while not ready.is_empty():
		var n := ready.pop_front()
		out_order.append(n)
		for nei in (adj[n] as Array):
			if not indeg2.has(nei):
				continue
			indeg2[nei] = int(indeg2[nei]) - 1
			if int(indeg2[nei]) == 0:
				ready.append(nei)
				ready.sort_custom(func(a, b): return int(member_index[a]) < int(member_index[b]))

	# Cycle fallback: if we couldn't order all, return declared order (restricted to universe).
	if out_order.size() != universe.size():
		var fallback: Array[String] = []
		for m in members:
			if universe.has(m):
				fallback.append(m)
		return fallback

	# If include_unwired, append unwired in declared order (those not present in out_order).
	if include_unwired and out_order.size() < members.size():
		var seen := {}
		for x in out_order:
			seen[x] = true
		for m in members:
			if not seen.has(m):
				out_order.append(m)

	return out_order
