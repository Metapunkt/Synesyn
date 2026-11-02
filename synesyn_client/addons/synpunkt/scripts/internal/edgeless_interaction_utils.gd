extends RefCounted
class_name SynpunktEdgelessInteractionUtils

static func on_edgeless_selection_changed(owner: Control, node_id: String, ref: Dictionary) -> void:
	owner.set("_design_selected_node_id", node_id)
	var edgeless_label_edit: LineEdit = owner.get("_edgeless_label_edit")
	var edgeless_apply_label: Button = owner.get("_edgeless_apply_label")
	if node_id.is_empty():
		owner.call("_set_status", "Edgeless: selection cleared.")
		if edgeless_label_edit:
			edgeless_label_edit.text = ""
			edgeless_label_edit.editable = false
			edgeless_label_edit.placeholder_text = "(click a node/cluster, then rename it here)"
		if edgeless_apply_label:
			edgeless_apply_label.disabled = true
		return
	var edgeless_preview: Control = owner.get("_edgeless_preview")
	if edgeless_label_edit and edgeless_preview:
		edgeless_label_edit.text = str(edgeless_preview.call("get_node_label", node_id))
		edgeless_label_edit.editable = true
		edgeless_label_edit.placeholder_text = "Selected: %s" % node_id
	if edgeless_apply_label:
		edgeless_apply_label.disabled = false
	var kind := str(ref.get("kind", "")).strip_edges()
	if kind == "syndoc_frame":
		var frame_id := str(ref.get("frame_id", "")).strip_edges()
		if not frame_id.is_empty():
			owner.call("_jump_to_frame_id", frame_id)
	var ref_s := ""
	if not ref.is_empty():
		ref_s = " ref=%s" % str(ref)
	owner.call("_set_status", "Edgeless: selected %s%s" % [node_id, ref_s])


static func on_edgeless_preview_gui_input(owner: Control, event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		return
	if not owner.call("_get_edgeless_layout", flowdoc_model).is_empty():
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	owner.call("_set_status", "Building edgeless layout…")
	await owner.call("_build_edgeless_layout_from_projection", false)


static func on_edgeless_resize_gui_input(owner: Control, event: InputEvent) -> void:
	var edgeless_preview: Control = owner.get("_edgeless_preview")
	var edgeless_resize_handle: Control = owner.get("_edgeless_resize_handle")
	if not edgeless_preview or not edgeless_resize_handle:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				owner.set("_edgeless_resizing", true)
				owner.set("_edgeless_resize_start_y", mb.position.y)
				owner.set("_edgeless_resize_start_h", float(edgeless_preview.custom_minimum_size.y))
				edgeless_resize_handle.accept_event()
			else:
				owner.set("_edgeless_resizing", false)
				edgeless_resize_handle.accept_event()
		return
	if event is InputEventMouseMotion and bool(owner.get("_edgeless_resizing")):
		var mm := event as InputEventMouseMotion
		var delta := mm.position.y - float(owner.get("_edgeless_resize_start_y"))
		var h := clamp(float(owner.get("_edgeless_resize_start_h")) + delta, 140.0, 1200.0)
		edgeless_preview.custom_minimum_size = Vector2(edgeless_preview.custom_minimum_size.x, h)
		edgeless_preview.queue_redraw()
		edgeless_resize_handle.accept_event()


static func on_flowdoc_json_resize_gui_input(owner: Control, event: InputEvent) -> void:
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	var flowdoc_json_resize_handle: Control = owner.get("_flowdoc_json_resize_handle")
	if not flowdoc_json or not flowdoc_json_resize_handle:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				owner.set("_flowdoc_json_resizing", true)
				owner.set("_flowdoc_json_resize_start_y", mb.position.y)
				owner.set("_flowdoc_json_resize_start_h", float(flowdoc_json.custom_minimum_size.y))
				flowdoc_json_resize_handle.accept_event()
			else:
				owner.set("_flowdoc_json_resizing", false)
				flowdoc_json_resize_handle.accept_event()
		return
	if event is InputEventMouseMotion and bool(owner.get("_flowdoc_json_resizing")):
		var mm := event as InputEventMouseMotion
		var delta := mm.position.y - float(owner.get("_flowdoc_json_resize_start_y"))
		var h := clamp(float(owner.get("_flowdoc_json_resize_start_h")) + delta, 120.0, 1800.0)
		flowdoc_json.custom_minimum_size = Vector2(flowdoc_json.custom_minimum_size.x, h)
		flowdoc_json.queue_redraw()
		flowdoc_json_resize_handle.accept_event()


static func update_flowdoc_edgeless_node_pos(owner: Control, node_id: String, new_pos: Array) -> void:
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty() or new_pos.size() < 2:
		return
	var layout_any: Variant = flowdoc_model.get("layout", null)
	if typeof(layout_any) != TYPE_DICTIONARY:
		return
	var layout: Dictionary = layout_any
	var ed_any: Variant = layout.get("edgeless", null)
	if typeof(ed_any) != TYPE_DICTIONARY:
		return
	var ed: Dictionary = ed_any
	if node_id.begins_with("cluster:"):
		var clusters_any: Variant = ed.get("clusters", [])
		if typeof(clusters_any) != TYPE_ARRAY:
			return
		var clusters: Array = clusters_any
		for i in range(clusters.size()):
			if typeof(clusters[i]) != TYPE_DICTIONARY:
				continue
			var c: Dictionary = clusters[i]
			if str(c.get("id", "")).strip_edges() != node_id:
				continue
			c["pos"] = [float(new_pos[0]), float(new_pos[1])]
			clusters[i] = c
			ed["clusters"] = clusters
			layout["edgeless"] = ed
			flowdoc_model["layout"] = layout
			owner.set("_flowdoc_model", flowdoc_model)
			return
	else:
		var nodes_any: Variant = ed.get("nodes", [])
		if typeof(nodes_any) != TYPE_ARRAY:
			return
		var nodes: Array = nodes_any
		for i in range(nodes.size()):
			if typeof(nodes[i]) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = nodes[i]
			if str(n.get("id", "")).strip_edges() != node_id:
				continue
			n["pos"] = [float(new_pos[0]), float(new_pos[1])]
			nodes[i] = n
			ed["nodes"] = nodes
			layout["edgeless"] = ed
			flowdoc_model["layout"] = layout
			owner.set("_flowdoc_model", flowdoc_model)
			return


static func update_flowdoc_edgeless_node_label(owner: Control, node_id: String, label: String) -> void:
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		return
	var layout_any: Variant = flowdoc_model.get("layout", null)
	if typeof(layout_any) != TYPE_DICTIONARY:
		return
	var layout: Dictionary = layout_any
	var ed_any: Variant = layout.get("edgeless", null)
	if typeof(ed_any) != TYPE_DICTIONARY:
		return
	var ed: Dictionary = ed_any
	if node_id.begins_with("cluster:"):
		var clusters_any: Variant = ed.get("clusters", [])
		if typeof(clusters_any) != TYPE_ARRAY:
			return
		var clusters: Array = clusters_any
		for i in range(clusters.size()):
			if typeof(clusters[i]) != TYPE_DICTIONARY:
				continue
			var c: Dictionary = clusters[i]
			if str(c.get("id", "")).strip_edges() != node_id:
				continue
			c["label"] = label
			clusters[i] = c
			ed["clusters"] = clusters
			layout["edgeless"] = ed
			flowdoc_model["layout"] = layout
			owner.set("_flowdoc_model", flowdoc_model)
			return
	else:
		var nodes_any: Variant = ed.get("nodes", [])
		if typeof(nodes_any) != TYPE_ARRAY:
			return
		var nodes: Array = nodes_any
		for i in range(nodes.size()):
			if typeof(nodes[i]) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = nodes[i]
			if str(n.get("id", "")).strip_edges() != node_id:
				continue
			n["label"] = label
			nodes[i] = n
			ed["nodes"] = nodes
			layout["edgeless"] = ed
			flowdoc_model["layout"] = layout
			owner.set("_flowdoc_model", flowdoc_model)
			return


static func get_flowdoc_edgeless_node_pos(owner: Control, node_id: String) -> Array:
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	var ed: Dictionary = owner.call("_get_edgeless_layout", flowdoc_model)
	if ed.is_empty():
		return []
	if node_id.begins_with("cluster:"):
		var clusters_any: Variant = ed.get("clusters", [])
		if typeof(clusters_any) != TYPE_ARRAY:
			return []
		for c_any in (clusters_any as Array):
			if typeof(c_any) != TYPE_DICTIONARY:
				continue
			var c: Dictionary = c_any
			if str(c.get("id", "")).strip_edges() == node_id:
				var pos_any: Variant = c.get("pos", [])
				return pos_any if typeof(pos_any) == TYPE_ARRAY else []
	else:
		var nodes_any: Variant = ed.get("nodes", [])
		if typeof(nodes_any) != TYPE_ARRAY:
			return []
		for n_any in (nodes_any as Array):
			if typeof(n_any) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = n_any
			if str(n.get("id", "")).strip_edges() == node_id:
				var pos_any: Variant = n.get("pos", [])
				return pos_any if typeof(pos_any) == TYPE_ARRAY else []
	return []


static func refresh_edgeless_preview(owner: Control) -> void:
	var edgeless_preview: Control = owner.get("_edgeless_preview")
	if not edgeless_preview:
		return
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		edgeless_preview.call("clear")
		return
	var layout_any: Variant = flowdoc_model.get("layout", null)
	if typeof(layout_any) != TYPE_DICTIONARY:
		edgeless_preview.call("clear")
		return
	var layout: Dictionary = layout_any
	var ed_any: Variant = layout.get("edgeless", null)
	if typeof(ed_any) != TYPE_DICTIONARY:
		edgeless_preview.call("clear")
		return
	var ed: Dictionary = ed_any
	edgeless_preview.call("set_edgeless", ed)
	var edgeless_show_labels: BaseButton = owner.get("_edgeless_show_labels")
	if edgeless_show_labels:
		edgeless_preview.call("set_show_labels", edgeless_show_labels.button_pressed)


static func on_align_selected_to_grid(owner: Control) -> void:
	var selected_node_id := str(owner.get("_design_selected_node_id")).strip_edges()
	if selected_node_id.is_empty():
		owner.call("_set_status", "Select a node/cluster first.")
		return
	var pos := get_flowdoc_edgeless_node_pos(owner, selected_node_id)
	if pos.size() < 2:
		return
	var gs: float = 50.0
	var edgeless_grid_size: SpinBox = owner.get("_edgeless_grid_size")
	if edgeless_grid_size:
		gs = max(float(edgeless_grid_size.value), 1.0)
	var x: float = snapped(float(pos[0]), gs)
	var y: float = snapped(float(pos[1]), gs)
	update_flowdoc_edgeless_node_pos(owner, selected_node_id, [x, y])
	owner.call("_write_model_to_raw_json")
	refresh_edgeless_preview(owner)
	owner.call("_set_status", "Aligned to grid.")


static func center_selected_axis(owner: Control, is_x: bool) -> void:
	var selected_node_id := str(owner.get("_design_selected_node_id")).strip_edges()
	if selected_node_id.is_empty():
		owner.call("_set_status", "Select a node/cluster first.")
		return
	var pos := get_flowdoc_edgeless_node_pos(owner, selected_node_id)
	if pos.size() < 2:
		return
	var x: float = float(pos[0])
	var y: float = float(pos[1])
	if is_x:
		x = 0.0
	else:
		y = 0.0
	update_flowdoc_edgeless_node_pos(owner, selected_node_id, [x, y])
	owner.call("_write_model_to_raw_json")
	refresh_edgeless_preview(owner)
	owner.call("_set_status", "Centered %s." % ("X" if is_x else "Y"))


static func collect_image_artifact_ids_from_frames(frames: Array) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	for frame_any in frames:
		if typeof(frame_any) != TYPE_DICTIONARY:
			continue
		var frame: Dictionary = frame_any
		var blocks_any: Variant = frame.get("blocks", [])
		if typeof(blocks_any) != TYPE_ARRAY:
			continue
		for block_any in (blocks_any as Array):
			if typeof(block_any) != TYPE_DICTIONARY:
				continue
			var block: Dictionary = block_any
			var t := str(block.get("type", "")).to_lower()
			if t != "image" and t != "img":
				continue
			var aid := str(block.get("artifact_id", block.get("image_artifact_id", block.get("id", "")))).strip_edges()
			if aid.is_empty():
				aid = str(block.get("image_id", "")).strip_edges()
			if aid.is_empty() or seen.has(aid):
				continue
			seen[aid] = true
			out.append(aid)
	return out


static func resolve_next_present_image_uri(owner: Control) -> void:
	if bool(owner.get("_present_image_resolve_inflight")):
		return
	var queue_any: Variant = owner.get("_present_image_resolve_queue")
	var queue: Array = queue_any if typeof(queue_any) == TYPE_ARRAY else []
	if queue.is_empty():
		var present_edgeless_preview: Control = owner.get("_present_edgeless_preview")
		if present_edgeless_preview:
			present_edgeless_preview.call("set_image_uri_map", owner.get("_present_image_uri_map"))
			present_edgeless_preview.call("set_syndoc_frames", owner.call("_get_frames"))
		return
	var present_image_resolve_http: HTTPRequest = owner.get("_present_image_resolve_http")
	if not present_image_resolve_http:
		return
	var aid := str(queue.pop_front()).strip_edges()
	owner.set("_present_image_resolve_queue", queue)
	if aid.is_empty():
		resolve_next_present_image_uri(owner)
		return
	var hub: Node = owner.get("_hub")
	var base_url := str(hub.base_url if hub else "").rstrip("/")
	var url := base_url + "/substrate/query"
	var headers := ["Content-Type: application/json"]
	if hub and hub.auth_enabled and not String(hub.auth_token).is_empty():
		headers.append("Authorization: Bearer %s" % hub.auth_token)
	var payload := {"table": "artifacts", "where": {"id": aid}, "limit": 1}
	var body := JSON.stringify(payload)
	owner.set("_present_image_resolve_inflight", true)
	var err := present_image_resolve_http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		owner.set("_present_image_resolve_inflight", false)
		resolve_next_present_image_uri(owner)


static func on_present_image_resolve_completed(owner: Control, body_bytes: PackedByteArray) -> void:
	owner.set("_present_image_resolve_inflight", false)
	var body_s := body_bytes.get_string_from_utf8()
	var parsed_any: Variant = JSON.parse_string(body_s)
	if typeof(parsed_any) == TYPE_DICTIONARY:
		var parsed: Dictionary = parsed_any
		if bool(parsed.get("ok", false)):
			var result: Dictionary = parsed.get("result", {})
			var cols: Array = result.get("columns", [])
			var rows: Array = result.get("rows", [])
			if rows.size() > 0 and typeof(rows[0]) == TYPE_ARRAY:
				var row: Array = rows[0]
				var idx_id := cols.find("id")
				var idx_uri := cols.find("uri")
				if idx_id != -1 and idx_uri != -1 and idx_id < row.size() and idx_uri < row.size():
					var aid := str(row[idx_id]).strip_edges()
					var uri := str(row[idx_uri]).strip_edges()
					if not aid.is_empty() and not uri.is_empty():
						var present_image_uri_map_any: Variant = owner.get("_present_image_uri_map")
						var present_image_uri_map: Dictionary = present_image_uri_map_any if typeof(present_image_uri_map_any) == TYPE_DICTIONARY else {}
						present_image_uri_map[aid] = uri
						owner.set("_present_image_uri_map", present_image_uri_map)
	resolve_next_present_image_uri(owner)


static func on_present_make_frame_from_cluster(owner: Control) -> void:
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		owner.call("_set_status", "Load a SynDoc first.")
		return
	var ed: Dictionary = owner.call("_get_edgeless_layout", flowdoc_model)
	if ed.is_empty():
		owner.call("_set_status", "No edgeless layout in this SynDoc. Build it in Design first.")
		return
	var present_selected_node_id := str(owner.get("_present_selected_node_id")).strip_edges()
	if present_selected_node_id.is_empty():
		owner.call("_set_status", "Select a cluster (or an item) in the Edgeless view first.")
		return
	var cluster_node_id := present_selected_node_id
	if cluster_node_id.begins_with("item:"):
		var node_cluster_any: Variant = ed.get("node_cluster", {})
		if typeof(node_cluster_any) == TYPE_DICTIONARY:
			var node_cluster: Dictionary = node_cluster_any
			if node_cluster.has(cluster_node_id):
				var cid := int(node_cluster.get(cluster_node_id, -1))
				if cid >= 0:
					cluster_node_id = "cluster:%d" % cid
	var cluster: Dictionary = owner.call("_find_edgeless_cluster", ed, cluster_node_id)
	if cluster.is_empty():
		owner.call("_set_status", "Selected cluster not found in layout: %s" % cluster_node_id)
		return
	var frame: Dictionary = build_frame_from_cluster(owner, cluster, ed)
	var frames: Array = owner.call("_get_frames")
	if frames.is_empty():
		frames = []
	var new_id := str(frame.get("id", "cluster_frame")).strip_edges()
	new_id = make_unique_frame_id(frames, new_id)
	frame["id"] = new_id
	frames.append(frame)
	flowdoc_model["frames"] = frames
	owner.set("_flowdoc_model", flowdoc_model)
	owner.set("_active_frame_idx", frames.size() - 1)
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	if flowdoc_json:
		flowdoc_json.text = JSON.stringify(flowdoc_model, "\t")
	owner.call("_sync_from_raw_json")
	owner.call("_set_status", "Created frame '%s' from %s. Save as new version when ready." % [new_id, cluster_node_id])


static func build_frame_from_cluster(owner: Control, cluster: Dictionary, edgeless: Dictionary) -> Dictionary:
	var cid := int(cluster.get("cluster_id", -1))
	var title := str(cluster.get("label", "Cluster")).strip_edges()
	if title.is_empty():
		title = "Cluster #%d" % cid
	var blocks: Array = []
	blocks.append({"type": "h1", "text": title})
	var ref_closure: LineEdit = owner.get("_ref_closure")
	var closure_id := ref_closure.text.strip_edges() if ref_closure else ""
	if not closure_id.is_empty():
		blocks.append({"type": "p", "text": "Source closure: %s" % closure_id})
	var ref_projection: LineEdit = owner.get("_ref_projection")
	var proj_id := ref_projection.text.strip_edges() if ref_projection else ""
	if not proj_id.is_empty():
		blocks.append({"type": "p", "text": "Projection: %s" % proj_id})
	var ref_cluster: LineEdit = owner.get("_ref_cluster")
	var cluster_art_id := ref_cluster.text.strip_edges() if ref_cluster else ""
	if not cluster_art_id.is_empty():
		blocks.append({"type": "p", "text": "Cluster result: %s" % cluster_art_id})
	var item_ids_any: Variant = cluster.get("item_ids", [])
	var item_ids: Array = item_ids_any if typeof(item_ids_any) == TYPE_ARRAY else []
	blocks.append({"type": "h2", "text": "Items"})
	if item_ids.is_empty():
		blocks.append({"type": "p", "text": "(none)"})
	else:
		var label_map := edgeless_item_label_map(edgeless)
		for it_any in item_ids:
			var iid := str(it_any).strip_edges()
			if iid.is_empty():
				continue
			var label := str(label_map.get(iid, iid))
			blocks.append({"type": "li", "text": label})
	return {
		"id": ("cluster_%d" % cid) if cid >= 0 else "cluster_frame",
		"kind": "document",
		"transform": {"x": 0, "y": 0, "w": 960, "h": 540},
		"blocks": blocks,
	}


static func edgeless_item_label_map(edgeless: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var nodes_any: Variant = edgeless.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return out
	for n_any in (nodes_any as Array):
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		var ref_any: Variant = n.get("ref", null)
		if typeof(ref_any) != TYPE_DICTIONARY:
			continue
		var ref: Dictionary = ref_any
		if str(ref.get("kind", "")) != "context_graph_node":
			continue
		var iid := str(ref.get("id", "")).strip_edges()
		if iid.is_empty():
			continue
		var label := str(n.get("label", "")).strip_edges()
		if label.is_empty():
			label = iid
		out[iid] = label
	return out


static func make_unique_frame_id(frames: Array, desired: String) -> String:
	var existing: Dictionary = {}
	for f_any in frames:
		if typeof(f_any) != TYPE_DICTIONARY:
			continue
		var f: Dictionary = f_any
		existing[str(f.get("id", "")).strip_edges()] = true
	if not existing.has(desired):
		return desired
	var i: int = 2
	while i < 100000:
		var cand := "%s_%d" % [desired, i]
		if not existing.has(cand):
			return cand
		i += 1
	return desired
