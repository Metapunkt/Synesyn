extends RefCounted
class_name SynpunktSyndocFrameSyncUtils

static func rename_selected_frame(owner: Control) -> void:
	var frame_id: LineEdit = owner.get("_frame_id")
	var new_id := frame_id.text.strip_edges() if frame_id else ""
	if new_id.is_empty():
		owner.call("_set_status", "Frame id is empty.")
		return
	var frames: Array = owner.call("_get_frames")
	if frames.is_empty():
		return
	var active_frame_idx := int(owner.get("_active_frame_idx"))
	if active_frame_idx < 0 or active_frame_idx >= frames.size():
		return
	for i in range(frames.size()):
		if i == active_frame_idx:
			continue
		if typeof(frames[i]) == TYPE_DICTIONARY and str((frames[i] as Dictionary).get("id", "")) == new_id:
			owner.call("_set_status", "Frame id already exists.")
			return
	if typeof(frames[active_frame_idx]) != TYPE_DICTIONARY:
		return
	var f: Dictionary = frames[active_frame_idx]
	var old_id := str(f.get("id", "")).strip_edges()
	f["id"] = new_id
	frames[active_frame_idx] = f
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	flowdoc_model["frames"] = frames
	owner.set("_flowdoc_model", flowdoc_model)
	if not old_id.is_empty() and old_id != new_id:
		remap_edgeless_frame_node_id(owner, old_id, new_id)
	owner.call("_write_model_to_raw_json")
	owner.call("_refresh_frames_ui")
	owner.call("_set_status", "Frame renamed.")
	owner.call("_refresh_edgeless_preview")
	owner.call("_refresh_present_edgeless")
	owner.call("_refresh_performer_ui")


static func remap_edgeless_frame_node_id(owner: Control, old_frame_id: String, new_frame_id: String) -> void:
	var old_id := String(old_frame_id).strip_edges()
	var new_id := String(new_frame_id).strip_edges()
	if old_id.is_empty() or new_id.is_empty() or old_id == new_id:
		return
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		return
	var ed: Dictionary = owner.call("_get_edgeless_layout", flowdoc_model)
	if ed.is_empty():
		return
	var nodes_any: Variant = ed.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return
	var nodes: Array = nodes_any
	for i in range(nodes.size()):
		if typeof(nodes[i]) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = nodes[i]
		var ref_any: Variant = n.get("ref", null)
		if typeof(ref_any) != TYPE_DICTIONARY:
			continue
		var ref: Dictionary = ref_any
		if str(ref.get("kind", "")).strip_edges() != "syndoc_frame":
			continue
		var fid := str(ref.get("frame_id", "")).strip_edges()
		if fid != old_id:
			continue
		ref["frame_id"] = new_id
		n["ref"] = ref
		var nid := str(n.get("id", "")).strip_edges()
		if nid == "frame:%s" % old_id:
			n["id"] = "frame:%s" % new_id
		n["label"] = new_id
		nodes[i] = n
	ed["nodes"] = nodes
	var layout_any: Variant = flowdoc_model.get("layout", {})
	var layout: Dictionary = layout_any if typeof(layout_any) == TYPE_DICTIONARY else {}
	layout["edgeless"] = ed
	flowdoc_model["layout"] = layout
	owner.set("_flowdoc_model", flowdoc_model)


static func reconcile_edgeless_frame_nodes_with_frames(owner: Control) -> void:
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		return
	var frames: Array = owner.call("_get_frames")
	if frames.is_empty():
		return
	var frame_id_set: Dictionary = {}
	for f_any in frames:
		if typeof(f_any) != TYPE_DICTIONARY:
			continue
		var fid := str((f_any as Dictionary).get("id", "")).strip_edges()
		if not fid.is_empty():
			frame_id_set[fid] = true
	var ed: Dictionary = owner.call("_get_edgeless_layout", flowdoc_model)
	if ed.is_empty():
		return
	var nodes_any: Variant = ed.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return
	var nodes: Array = nodes_any
	var fixed := 0
	var still_missing := 0
	for i in range(nodes.size()):
		if typeof(nodes[i]) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = nodes[i]
		var ref_any: Variant = n.get("ref", null)
		if typeof(ref_any) != TYPE_DICTIONARY:
			continue
		var ref: Dictionary = ref_any
		if str(ref.get("kind", "")).strip_edges() != "syndoc_frame":
			continue
		var fid := str(ref.get("frame_id", "")).strip_edges()
		if fid.is_empty() or frame_id_set.has(fid):
			continue
		var desired := ""
		var nid := str(n.get("id", "")).strip_edges()
		if nid.begins_with("frame:"):
			var suffix := nid.substr(6).strip_edges()
			if frame_id_set.has(suffix):
				desired = suffix
		if desired.is_empty():
			var label := str(n.get("label", "")).strip_edges()
			if frame_id_set.has(label):
				desired = label
		if desired.is_empty():
			still_missing += 1
			continue
		ref["frame_id"] = desired
		n["ref"] = ref
		var label2 := str(n.get("label", "")).strip_edges()
		if label2.is_empty() or label2 == fid:
			n["label"] = desired
		if nid == "frame:%s" % fid:
			n["id"] = "frame:%s" % desired
		nodes[i] = n
		fixed += 1
	if fixed > 0:
		ed["nodes"] = nodes
		var layout_any: Variant = flowdoc_model.get("layout", {})
		var layout: Dictionary = layout_any if typeof(layout_any) == TYPE_DICTIONARY else {}
		layout["edgeless"] = ed
		flowdoc_model["layout"] = layout
		owner.set("_flowdoc_model", flowdoc_model)
		owner.call("_set_status", "Reconciled edgeless layout: fixed %d stale frame refs%s." % [fixed, ("; %d still missing" % still_missing) if still_missing > 0 else ""])


static func validate_flowdoc(flowdoc: Dictionary) -> Dictionary:
	if str(flowdoc.get("schema", "")) != "ui.syndoc":
		return {"ok": false, "error": "schema must be 'ui.syndoc'"}
	var v := str(flowdoc.get("schema_version", "")).strip_edges()
	if v.is_empty():
		return {"ok": false, "error": "schema_version is required"}
	var title := str(flowdoc.get("title", "")).strip_edges()
	if title.is_empty():
		return {"ok": false, "error": "title is required"}
	var frames_any: Variant = flowdoc.get("frames", [])
	if typeof(frames_any) != TYPE_ARRAY:
		return {"ok": false, "error": "frames must be an array"}
	var frames: Array = frames_any
	if frames.is_empty():
		return {"ok": false, "error": "frames must not be empty"}
	return {"ok": true}


static func row_get(columns: Array, row: Array, key: String) -> String:
	var idx := columns.find(key)
	if idx == -1:
		return ""
	if idx < 0 or idx >= row.size():
		return ""
	return str(row[idx])


static func find_row_by_id(columns: Array, rows: Array, artifact_id: String) -> Array:
	var target := String(artifact_id).strip_edges()
	if target.is_empty():
		return []
	for r_any in rows:
		if typeof(r_any) != TYPE_ARRAY:
			continue
		var r: Array = r_any
		if row_get(columns, r, "id") == target:
			return r
	return []


static func load_json_from_uri(uri: String) -> Variant:
	if not uri.begins_with("file://"):
		return null
	var path := uri.replace("file://", "")
	if not FileAccess.file_exists(path):
		return null
	var s := FileAccess.get_file_as_string(path)
	if s.is_empty():
		return null
	return JSON.parse_string(s)
