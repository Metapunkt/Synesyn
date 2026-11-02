extends RefCounted
class_name SynpunktEdgelessLayoutBuilderUtils

static func build_edgeless_layout_from_projection(owner: Control, keep_edits: bool) -> void:
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		owner.call("_set_status", "Load or generate a SynDoc first.")
		return
	var ref_projection: LineEdit = owner.get("_ref_projection")
	var proj_id := ref_projection.text.strip_edges() if ref_projection else ""
	if proj_id.is_empty():
		owner.call("_set_status", "No projection ref set; building edgeless layout from frames…")
		await build_edgeless_layout_from_frames(owner, keep_edits)
		return
	owner.call("_set_status", "Loading projection %s…" % proj_id.left(12))
	var hub: Node = owner.get("_hub")
	var proj_res: Dictionary = await hub.get_artifact_json(proj_id)
	if not bool(proj_res.get("ok", false)):
		owner.call("_set_status", "Failed to load projection: %s" % str(proj_res.get("error", proj_res)))
		return
	var proj: Dictionary = proj_res.get("json", {})
	var coords_any: Variant = proj.get("coords", {})
	if typeof(coords_any) != TYPE_DICTIONARY:
		owner.call("_set_status", "Projection artifact missing coords map.")
		return
	var coords: Dictionary = coords_any
	var selected_item_ids: Array[String] = []
	var active_closure_json_any: Variant = owner.get("_active_closure_json")
	var active_closure_json: Dictionary = active_closure_json_any if typeof(active_closure_json_any) == TYPE_DICTIONARY else {}
	if not active_closure_json.is_empty():
		var sel_any: Variant = active_closure_json.get("selection", null)
		if typeof(sel_any) == TYPE_DICTIONARY:
			var sel: Dictionary = sel_any
			var ids_any: Variant = sel.get("item_ids", [])
			if typeof(ids_any) == TYPE_ARRAY:
				for it_any in (ids_any as Array):
					selected_item_ids.append(str(it_any))
	if selected_item_ids.is_empty():
		for k in coords.keys():
			selected_item_ids.append(str(k))
	var points: Array = []
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for item_id in selected_item_ids:
		if not coords.has(item_id):
			continue
		var v_any: Variant = coords[item_id]
		if typeof(v_any) != TYPE_ARRAY:
			continue
		var v: Array = v_any
		if v.size() < 2:
			continue
		var x := float(v[0])
		var y := float(v[1])
		var z := float(v[2]) if v.size() >= 3 else 0.0
		min_x = min(min_x, x)
		max_x = max(max_x, x)
		min_y = min(min_y, y)
		max_y = max(max_y, y)
		points.append({"id": item_id, "x": x, "y": y, "z": z})
	if points.is_empty():
		owner.call("_set_status", "No usable points found in projection coords for selected items (projection=%s)." % proj_id.left(12))
		return
	var range_x: float = max(max_x - min_x, 0.00001)
	var range_y: float = max(max_y - min_y, 0.00001)
	var canvas_w: float = 2000.0
	var canvas_h: float = 1200.0
	var pad: float = 80.0
	var nodes: Array = []
	for p_any in points:
		var p: Dictionary = p_any
		var nx: float = ((float(p["x"]) - min_x) / range_x - 0.5) * (canvas_w - pad * 2.0)
		var ny: float = ((float(p["y"]) - min_y) / range_y - 0.5) * (canvas_h - pad * 2.0)
		nodes.append({
			"id": "item:%s" % str(p["id"]),
			"ref": {"kind": "context_graph_node", "id": str(p["id"])},
			"pos": [nx, ny],
			"z": float(p["z"]),
			"label": str(p["id"]),
		})
	var ref_cluster: LineEdit = owner.get("_ref_cluster")
	var cluster_art_id := ref_cluster.text.strip_edges() if ref_cluster else ""
	var clusters_out: Array = []
	var node_cluster: Dictionary = {}
	if not cluster_art_id.is_empty():
		var c_res: Dictionary = await hub.get_artifact_json(cluster_art_id)
		if bool(c_res.get("ok", false)):
			var cjson: Dictionary = c_res.get("json", {})
			var c_any: Variant = cjson.get("clusters", [])
			if typeof(c_any) == TYPE_ARRAY:
				var clusters_in: Array = c_any
				for c_one_any in clusters_in:
					if typeof(c_one_any) != TYPE_DICTIONARY:
						continue
					var c_one: Dictionary = c_one_any
					var cid := int(c_one.get("cluster_id", -1))
					if cid < 0:
						continue
					var center_any: Variant = c_one.get("center", null)
					var center: Array = center_any if typeof(center_any) == TYPE_ARRAY else []
					var cx: float = float(center[0]) if center.size() >= 1 else 0.0
					var cy: float = float(center[1]) if center.size() >= 2 else 0.0
					var cz: float = float(center[2]) if center.size() >= 3 else 0.0
					var cnx: float = ((cx - min_x) / range_x - 0.5) * (canvas_w - pad * 2.0)
					var cny: float = ((cy - min_y) / range_y - 0.5) * (canvas_h - pad * 2.0)
					var item_ids_any: Variant = c_one.get("item_ids", [])
					var item_ids: Array = item_ids_any if typeof(item_ids_any) == TYPE_ARRAY else []
					for it_any in item_ids:
						var it_id := str(it_any).strip_edges()
						if it_id.is_empty():
							continue
						node_cluster["item:%s" % it_id] = cid
					clusters_out.append({
						"id": "cluster:%d" % cid,
						"cluster_id": cid,
						"pos": [cnx, cny],
						"z": cz,
						"label": "Cluster #%d" % cid,
						"ref": {"kind": "cluster", "cluster_id": cid},
						"item_ids": item_ids,
					})
	var new_edgeless := {
		"schema_version": 1,
		"projection_artifact_id": proj_id,
		"cluster_artifact_id": cluster_art_id,
		"nodes": nodes,
		"clusters": clusters_out,
		"node_cluster": node_cluster,
	}
	if keep_edits:
		var old_ed := owner.call("_get_edgeless_layout", flowdoc_model)
		if typeof(old_ed) == TYPE_DICTIONARY and not (old_ed as Dictionary).is_empty():
			merge_edgeless_keep_edits(old_ed, new_edgeless)
	var layout_any: Variant = flowdoc_model.get("layout", {})
	var layout: Dictionary = layout_any if typeof(layout_any) == TYPE_DICTIONARY else {}
	layout["edgeless"] = new_edgeless
	flowdoc_model["layout"] = layout
	owner.set("_flowdoc_model", flowdoc_model)
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	if flowdoc_json:
		flowdoc_json.text = JSON.stringify(flowdoc_model, "\t")
	owner.call("_sync_from_raw_json")
	if keep_edits:
		owner.call("_set_status", "Rebuilt edgeless layout (%d nodes) and kept manual edits." % nodes.size())
	else:
		owner.call("_set_status", "Built edgeless layout (%d nodes). z kept as metadata." % nodes.size())


static func build_edgeless_layout_from_frames(owner: Control, keep_edits: bool) -> void:
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		owner.call("_set_status", "Load or generate a SynDoc first.")
		return
	var frames: Array = owner.call("_get_frames")
	if frames.is_empty():
		owner.call("_set_status", "No frames found. Add a frame, then build an edgeless layout.")
		return
	var n := frames.size()
	var cols := int(ceil(sqrt(float(n))))
	cols = max(cols, 1)
	var spacing_x := 560.0
	var spacing_y := 360.0
	var origin_x := -((float(cols) - 1.0) * spacing_x) * 0.5
	var rows := int(ceil(float(n) / float(cols)))
	var origin_y := -((float(rows) - 1.0) * spacing_y) * 0.5
	var nodes: Array = []
	for i in range(n):
		var f_any: Variant = frames[i]
		if typeof(f_any) != TYPE_DICTIONARY:
			continue
		var f: Dictionary = f_any
		var fid := str(f.get("id", "")).strip_edges()
		if fid.is_empty():
			fid = "frame_%d" % (i + 1)
		var c := i % cols
		var r := int(floor(float(i) / float(cols)))
		var x := origin_x + float(c) * spacing_x
		var y := origin_y + float(r) * spacing_y
		nodes.append({
			"id": "frame:%s" % fid,
			"ref": {"kind": "syndoc_frame", "frame_id": fid},
			"pos": [x, y],
			"z": 0.0,
			"label": fid,
		})
	var new_edgeless := {
		"schema_version": 1,
		"projection_artifact_id": "",
		"cluster_artifact_id": "",
		"nodes": nodes,
		"clusters": [],
		"node_cluster": {},
	}
	if keep_edits:
		var old_ed := owner.call("_get_edgeless_layout", flowdoc_model)
		if typeof(old_ed) == TYPE_DICTIONARY and not (old_ed as Dictionary).is_empty():
			merge_edgeless_keep_edits(old_ed, new_edgeless)
	var layout_any: Variant = flowdoc_model.get("layout", {})
	var layout: Dictionary = layout_any if typeof(layout_any) == TYPE_DICTIONARY else {}
	layout["edgeless"] = new_edgeless
	flowdoc_model["layout"] = layout
	owner.set("_flowdoc_model", flowdoc_model)
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	if flowdoc_json:
		flowdoc_json.text = JSON.stringify(flowdoc_model, "\t")
	owner.call("_sync_from_raw_json")
	if keep_edits:
		owner.call("_set_status", "No projection ref; rebuilt a basic frame-grid edgeless layout (%d nodes) and kept manual edits." % nodes.size())
	else:
		owner.call("_set_status", "No projection ref; built a basic frame-grid edgeless layout (%d nodes)." % nodes.size())


static func merge_edgeless_keep_edits(old_ed: Dictionary, new_ed: Dictionary) -> void:
	var new_nodes_any: Variant = new_ed.get("nodes", [])
	var old_nodes_any: Variant = old_ed.get("nodes", [])
	if typeof(new_nodes_any) == TYPE_ARRAY and typeof(old_nodes_any) == TYPE_ARRAY:
		var new_nodes: Array = new_nodes_any
		var old_nodes: Array = old_nodes_any
		var old_by_id: Dictionary = {}
		for n_any in old_nodes:
			if typeof(n_any) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = n_any
			old_by_id[str(n.get("id", "")).strip_edges()] = n
		var seen: Dictionary = {}
		for i in range(new_nodes.size()):
			if typeof(new_nodes[i]) != TYPE_DICTIONARY:
				continue
			var n2: Dictionary = new_nodes[i]
			var nid := str(n2.get("id", "")).strip_edges()
			seen[nid] = true
			if old_by_id.has(nid):
				var o: Dictionary = old_by_id[nid]
				if o.has("pos"):
					n2["pos"] = o.get("pos")
				if o.has("label"):
					n2["label"] = o.get("label")
				new_nodes[i] = n2
		for nid in old_by_id.keys():
			if not seen.has(nid):
				new_nodes.append(old_by_id[nid])
		new_ed["nodes"] = new_nodes
	var new_clusters_any: Variant = new_ed.get("clusters", [])
	var old_clusters_any: Variant = old_ed.get("clusters", [])
	if typeof(new_clusters_any) == TYPE_ARRAY and typeof(old_clusters_any) == TYPE_ARRAY:
		var new_clusters: Array = new_clusters_any
		var old_clusters: Array = old_clusters_any
		var old_by_idc: Dictionary = {}
		for c_any in old_clusters:
			if typeof(c_any) != TYPE_DICTIONARY:
				continue
			var c: Dictionary = c_any
			old_by_idc[str(c.get("id", "")).strip_edges()] = c
		var seen_c: Dictionary = {}
		for i in range(new_clusters.size()):
			if typeof(new_clusters[i]) != TYPE_DICTIONARY:
				continue
			var c2: Dictionary = new_clusters[i]
			var cid := str(c2.get("id", "")).strip_edges()
			seen_c[cid] = true
			if old_by_idc.has(cid):
				var o2: Dictionary = old_by_idc[cid]
				if o2.has("pos"):
					c2["pos"] = o2.get("pos")
				if o2.has("label"):
					c2["label"] = o2.get("label")
				new_clusters[i] = c2
		for cid in old_by_idc.keys():
			if not seen_c.has(cid):
				new_clusters.append(old_by_idc[cid])
		new_ed["clusters"] = new_clusters
	var old_map_any: Variant = old_ed.get("node_cluster", {})
	var new_map_any: Variant = new_ed.get("node_cluster", {})
	if typeof(old_map_any) == TYPE_DICTIONARY and typeof(new_map_any) == TYPE_DICTIONARY:
		var old_map: Dictionary = old_map_any
		var new_map: Dictionary = new_map_any
		for k in old_map.keys():
			if not new_map.has(k):
				new_map[k] = old_map[k]
		new_ed["node_cluster"] = new_map


static func edgeless_with_all_frames(edgeless: Dictionary, frames: Array) -> Dictionary:
	var out: Dictionary = edgeless.duplicate(true)
	var nodes_any: Variant = out.get("nodes", [])
	var nodes: Array = nodes_any if typeof(nodes_any) == TYPE_ARRAY else []
	var frame_ids: Array[String] = []
	var frame_id_set: Dictionary = {}
	for f_any in frames:
		if typeof(f_any) != TYPE_DICTIONARY:
			continue
		var f: Dictionary = f_any
		var fid := str(f.get("id", "")).strip_edges()
		if fid.is_empty():
			continue
		frame_ids.append(fid)
		frame_id_set[fid] = true
	var existing: Dictionary = {}
	var missing_node_indices: Array[int] = []
	for n_any in nodes:
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		var ref_any: Variant = n.get("ref", null)
		if typeof(ref_any) != TYPE_DICTIONARY:
			continue
		var ref: Dictionary = ref_any
		if str(ref.get("kind", "")).strip_edges() != "syndoc_frame":
			continue
		var fid2 := str(ref.get("frame_id", "")).strip_edges()
		if fid2.is_empty():
			continue
		if frame_id_set.has(fid2):
			existing[fid2] = true
		else:
			missing_node_indices.append(nodes.find(n_any))
	var missing_frame_ids: Array[String] = []
	for fid3 in frame_ids:
		if not existing.has(fid3):
			missing_frame_ids.append(fid3)
	if missing_node_indices.size() > 0 and missing_node_indices.size() == missing_frame_ids.size():
		for i in range(missing_node_indices.size()):
			var idx := int(missing_node_indices[i])
			if idx < 0 or idx >= nodes.size():
				continue
			var n_any2: Variant = nodes[idx]
			if typeof(n_any2) != TYPE_DICTIONARY:
				continue
			var n2: Dictionary = n_any2
			var ref_any2: Variant = n2.get("ref", null)
			if typeof(ref_any2) != TYPE_DICTIONARY:
				continue
			var ref2: Dictionary = ref_any2
			ref2["frame_id"] = missing_frame_ids[i]
			n2["ref"] = ref2
			n2["label"] = missing_frame_ids[i]
			nodes[idx] = n2
		existing = {}
		for n_any3 in nodes:
			if typeof(n_any3) != TYPE_DICTIONARY:
				continue
			var n3: Dictionary = n_any3
			var ref_any3: Variant = n3.get("ref", null)
			if typeof(ref_any3) != TYPE_DICTIONARY:
				continue
			var ref3: Dictionary = ref_any3
			if str(ref3.get("kind", "")).strip_edges() != "syndoc_frame":
				continue
			var fid4 := str(ref3.get("frame_id", "")).strip_edges()
			if not fid4.is_empty():
				existing[fid4] = true
	var idx2 := 0
	for f_any2 in frames:
		if typeof(f_any2) != TYPE_DICTIONARY:
			continue
		var f2: Dictionary = f_any2
		var fid5 := str(f2.get("id", "")).strip_edges()
		if fid5.is_empty() or existing.has(fid5):
			continue
		var cols := 3
		var c := idx2 % cols
		var r := int(floor(float(idx2) / float(cols)))
		var x := float(c) * 900.0
		var y := float(r) * 620.0
		nodes.append({
			"id": "frame:%s" % fid5,
			"ref": {"kind": "syndoc_frame", "frame_id": fid5},
			"pos": [x, y],
			"z": 0.0,
			"label": fid5,
		})
		idx2 += 1
	out["nodes"] = nodes
	return out
