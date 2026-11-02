extends RefCounted
class_name SynpunktPresentNavigationUtils

static func select_frame_delta(owner: Control, delta: int) -> void:
	var frames: Array = owner.call("_get_frames")
	if frames.is_empty():
		return
	var active_frame_idx := int(owner.get("_active_frame_idx"))
	var next := clamp(active_frame_idx + delta, 0, frames.size() - 1)
	if next == active_frame_idx:
		return
	owner.set("_active_frame_idx", next)
	owner.call("_refresh_frames_ui")
	owner.call("_refresh_blocks_ui")
	owner.call("_refresh_performer_ui")


static func on_present_prev_next(owner: Control, delta: int) -> void:
	var present_view_tabs: TabContainer = owner.get("_present_view_tabs")
	if is_instance_valid(present_view_tabs) and int(present_view_tabs.current_tab) == 1:
		select_present_edgeless_delta(owner, delta)
	else:
		select_frame_delta(owner, delta)


static func select_present_edgeless_delta(owner: Control, delta: int) -> void:
	var steps: Array = owner.call("_get_presentation_steps")
	if steps.size() > 0:
		var present_deck_step_idx := int(owner.get("_present_deck_step_idx"))
		if present_deck_step_idx < 0:
			present_deck_step_idx = 0
		var step_delta := (1 if delta > 0 else -1)
		present_deck_step_idx = wrapi(present_deck_step_idx + step_delta, 0, steps.size())
		owner.set("_present_deck_step_idx", present_deck_step_idx)
		owner.call("_apply_present_deck_step", present_deck_step_idx, true, true)
		return
	select_present_step_delta(owner, delta)


static func select_present_step_delta(owner: Control, delta: int) -> void:
	var frames: Array = owner.call("_get_frames")
	if frames.is_empty():
		return
	var active_frame_idx := int(owner.get("_active_frame_idx"))
	var cam_step_indices: Array[int] = []
	for i in range(frames.size()):
		var f_any: Variant = frames[i]
		if typeof(f_any) != TYPE_DICTIONARY:
			continue
		var f: Dictionary = f_any
		if typeof(f.get("camera", null)) == TYPE_DICTIONARY:
			cam_step_indices.append(i)
	var next := -1
	if cam_step_indices.size() > 0:
		var cur_step_pos := cam_step_indices.find(active_frame_idx)
		if cur_step_pos == -1:
			if delta > 0:
				for si in cam_step_indices:
					if si > active_frame_idx:
						next = si
						break
				if next == -1:
					next = cam_step_indices[0]
			else:
				for k in range(cam_step_indices.size() - 1, -1, -1):
					var si := cam_step_indices[k]
					if si < active_frame_idx:
						next = si
						break
				if next == -1:
					next = cam_step_indices[cam_step_indices.size() - 1]
		else:
			var step_delta := (1 if delta > 0 else -1)
			var new_pos := wrapi(cur_step_pos + step_delta, 0, cam_step_indices.size())
			next = cam_step_indices[new_pos]
	else:
		next = clamp(active_frame_idx + delta, 0, frames.size() - 1)
	if next == active_frame_idx:
		return
	owner.set("_active_frame_idx", next)
	owner.call("_refresh_frames_ui")
	owner.call("_refresh_blocks_ui")
	owner.call("_refresh_performer_ui")
	sync_present_edgeless_to_active_frame(owner)


static func sync_present_edgeless_to_active_frame(owner: Control) -> void:
	var present_edgeless_preview: Control = owner.get("_present_edgeless_preview")
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if not present_edgeless_preview or flowdoc_model.is_empty():
		return
	var active_frame_idx := int(owner.get("_active_frame_idx"))
	var fid := str(owner.call("_frame_id_for_index", active_frame_idx))
	if fid.is_empty():
		return
	var ed: Dictionary = owner.call("_get_edgeless_layout", flowdoc_model)
	if ed.is_empty():
		return
	var nodes_any: Variant = ed.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return
	var nodes: Array = nodes_any
	var node_id := ""
	for n_any in nodes:
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		var ref_any: Variant = n.get("ref", {})
		if typeof(ref_any) != TYPE_DICTIONARY:
			continue
		var ref: Dictionary = ref_any
		if str(ref.get("kind", "")).strip_edges() != "syndoc_frame":
			continue
		if str(ref.get("frame_id", "")).strip_edges() != fid:
			continue
		node_id = str(n.get("id", "")).strip_edges()
		break
	if node_id.is_empty():
		return
	present_edgeless_preview.call("select_node", node_id)
	var f: Dictionary = owner.call("_get_active_frame")
	if typeof(f.get("camera", null)) != TYPE_DICTIONARY:
		present_edgeless_preview.call("focus_node", node_id)


static func refresh_performer_ui(owner: Control) -> void:
	var perform_preview: RichTextLabel = owner.get("_perform_preview")
	var perform_frame_label: Label = owner.get("_perform_frame_label")
	if not perform_preview or not perform_frame_label:
		return
	var frames: Array = owner.call("_get_frames")
	if frames.is_empty():
		perform_frame_label.text = "Frame: (none)"
		perform_preview.text = "[i]No SynDoc loaded.[/i]"
		return
	var active_frame_idx := int(owner.get("_active_frame_idx"))
	active_frame_idx = clamp(active_frame_idx, 0, frames.size() - 1)
	owner.set("_active_frame_idx", active_frame_idx)
	var f_any: Variant = frames[active_frame_idx]
	if typeof(f_any) != TYPE_DICTIONARY:
		perform_frame_label.text = "Frame: (invalid)"
		perform_preview.text = "[i]Invalid frame.[/i]"
		return
	var f: Dictionary = f_any
	var fid := str(f.get("id", ""))
	perform_frame_label.text = "Frame: %s (%d/%d)" % [fid, active_frame_idx + 1, frames.size()]
	var blocks_any: Variant = f.get("blocks", [])
	var out := ""
	if typeof(blocks_any) == TYPE_ARRAY:
		for b_any in (blocks_any as Array):
			if typeof(b_any) != TYPE_DICTIONARY:
				continue
			var b: Dictionary = b_any
			var t := str(b.get("type", "p"))
			var txt := str(b.get("text", ""))
			match t:
				"h1":
					out += "[center][b]%s[/b][/center]\n\n" % txt
				"h2":
					out += "[b]%s[/b]\n" % txt
				"li":
					out += "• %s\n" % txt
				_:
					out += "%s\n\n" % txt
	if out.is_empty():
		out = "[i](no content)[/i]"
	perform_preview.text = out
	var steps: Array = owner.call("_get_presentation_steps")
	var present_view_tabs: TabContainer = owner.get("_present_view_tabs")
	var in_edgeless := is_instance_valid(present_view_tabs) and int(present_view_tabs.current_tab) == 1
	if not (steps.size() > 0 and in_edgeless):
		owner.call("_apply_present_camera_for_active_frame", false, false)


static func refresh_present_edgeless(owner: Control) -> void:
	var present_edgeless_preview: Control = owner.get("_present_edgeless_preview")
	if not present_edgeless_preview:
		return
	present_edgeless_preview.call("set_render_frames_as_controls", true)
	present_edgeless_preview.call("set_frame_card_size_px", Vector2(240.0, 150.0))
	present_edgeless_preview.call("set_presentation_style", true)
	present_edgeless_preview.call("set_syndoc_frames", owner.call("_get_frames"))
	present_edgeless_preview.call("set_image_uri_map", owner.get("_present_image_uri_map"))
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	var present_edgeless_selection: Label = owner.get("_present_edgeless_selection")
	if flowdoc_model.is_empty():
		present_edgeless_preview.call("clear")
		owner.set("_present_image_uri_map", {})
		owner.set("_present_cluster_ids", [])
		owner.set("_present_cluster_idx", -1)
		owner.set("_present_selected_node_id", "")
		owner.set("_present_selected_ref", {})
		owner.set("_present_deck_step_idx", -1)
		if present_edgeless_selection:
			present_edgeless_selection.text = "Selection: (none)"
		owner.call("_update_present_cluster_nav")
		return
	var layout_any: Variant = flowdoc_model.get("layout", null)
	if typeof(layout_any) != TYPE_DICTIONARY:
		present_edgeless_preview.call("clear")
		owner.set("_present_cluster_ids", [])
		owner.set("_present_cluster_idx", -1)
		owner.set("_present_selected_node_id", "")
		owner.set("_present_selected_ref", {})
		owner.set("_present_deck_step_idx", -1)
		if present_edgeless_selection:
			present_edgeless_selection.text = "Selection: (none)"
		owner.call("_update_present_cluster_nav")
		return
	var layout: Dictionary = layout_any
	var ed_any: Variant = layout.get("edgeless", null)
	if typeof(ed_any) != TYPE_DICTIONARY:
		present_edgeless_preview.call("clear")
		owner.set("_present_cluster_ids", [])
		owner.set("_present_cluster_idx", -1)
		owner.set("_present_selected_node_id", "")
		owner.set("_present_selected_ref", {})
		owner.set("_present_deck_step_idx", -1)
		if present_edgeless_selection:
			present_edgeless_selection.text = "Selection: (none)"
		owner.call("_update_present_cluster_nav")
		return
	var ed: Dictionary = ed_any
	var ed_for_present: Dictionary = owner.call("_edgeless_with_all_frames", ed, owner.call("_get_frames"))
	present_edgeless_preview.call("set_edgeless", ed_for_present)
	var present_show_labels: BaseButton = owner.get("_present_show_labels")
	if present_show_labels:
		present_edgeless_preview.call("set_show_labels", present_show_labels.button_pressed)
	present_edgeless_preview.call("select_node", "")
	owner.set("_present_selected_node_id", "")
	owner.set("_present_selected_ref", {})
	if present_edgeless_selection:
		present_edgeless_selection.text = "Selection: (none)"
	var steps: Array = owner.call("_get_presentation_steps")
	var present_deck_step_idx := int(owner.get("_present_deck_step_idx"))
	if steps.is_empty():
		present_deck_step_idx = -1
	else:
		present_deck_step_idx = clamp(present_deck_step_idx, 0, steps.size() - 1)
	owner.set("_present_deck_step_idx", present_deck_step_idx)
	var cluster_ids: Array[String] = []
	var clusters_any: Variant = ed_for_present.get("clusters", [])
	if typeof(clusters_any) == TYPE_ARRAY:
		for c_any in (clusters_any as Array):
			if typeof(c_any) != TYPE_DICTIONARY:
				continue
			var c: Dictionary = c_any
			var cid := str(c.get("id", "")).strip_edges()
			if not cid.is_empty():
				cluster_ids.append(cid)
	owner.set("_present_cluster_ids", cluster_ids)
	var present_cluster_idx := int(owner.get("_present_cluster_idx"))
	if present_cluster_idx < 0 and cluster_ids.size() > 0:
		present_cluster_idx = 0
		present_edgeless_preview.call("select_node", cluster_ids[0])
		present_edgeless_preview.call("focus_node", cluster_ids[0])
	owner.set("_present_cluster_idx", present_cluster_idx)
	owner.call("_update_present_cluster_nav")
	owner.call("_start_present_image_uri_resolve")
