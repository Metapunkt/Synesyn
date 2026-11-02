extends RefCounted
class_name SynpunktPresentCameraUtils

static func frame_idx_by_id(frames: Array, frame_id: String) -> int:
	var target := String(frame_id).strip_edges()
	if target.is_empty():
		return -1
	for i in range(frames.size()):
		var f_any: Variant = frames[i]
		if typeof(f_any) != TYPE_DICTIONARY:
			continue
		var f: Dictionary = f_any
		if str(f.get("id", "")).strip_edges() == target:
			return i
	return -1


static func present_target_frame_idx(owner: Control, frames: Array) -> int:
	var present_selected_ref_any: Variant = owner.get("_present_selected_ref")
	var present_selected_ref: Dictionary = present_selected_ref_any if typeof(present_selected_ref_any) == TYPE_DICTIONARY else {}
	if not present_selected_ref.is_empty() and str(present_selected_ref.get("kind", "")).strip_edges() == "syndoc_frame":
		var fid := str(present_selected_ref.get("frame_id", "")).strip_edges()
		var idx := frame_idx_by_id(frames, fid)
		if idx != -1:
			return idx
	return int(owner.get("_active_frame_idx"))


static func on_present_capture_camera(owner: Control) -> void:
	var present_edgeless_preview: Control = owner.get("_present_edgeless_preview")
	if not present_edgeless_preview:
		return
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		owner.call("_set_status", "Load a SynDoc first.")
		return
	var present_deck_capture: BaseButton = owner.get("_present_deck_capture")
	if present_deck_capture and present_deck_capture.button_pressed:
		capture_present_deck_step(owner)
		return
	var frames: Array = owner.call("_get_frames")
	var idx := present_target_frame_idx(owner, frames)
	if frames.is_empty() or idx < 0 or idx >= frames.size():
		return
	if typeof(frames[idx]) != TYPE_DICTIONARY:
		return
	var cam: Dictionary = present_edgeless_preview.call("get_camera")
	var f: Dictionary = frames[idx]
	f["camera"] = cam
	frames[idx] = f
	flowdoc_model["frames"] = frames
	owner.set("_flowdoc_model", flowdoc_model)
	owner.call("_write_model_to_raw_json")
	owner.call("_set_status", "Captured camera for frame %s. (Save SynDoc to persist)" % str(owner.call("_frame_id_for_index", idx)))


static func get_presentation_dict(owner: Control) -> Dictionary:
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	var p_any: Variant = flowdoc_model.get("presentation", {})
	return p_any if typeof(p_any) == TYPE_DICTIONARY else {}


static func get_presentation_steps(owner: Control) -> Array:
	var p := get_presentation_dict(owner)
	var s_any: Variant = p.get("steps", [])
	return s_any if typeof(s_any) == TYPE_ARRAY else []


static func set_presentation_steps(owner: Control, steps: Array) -> void:
	var p := get_presentation_dict(owner)
	p["steps"] = steps
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	flowdoc_model["presentation"] = p
	owner.set("_flowdoc_model", flowdoc_model)


static func capture_present_deck_step(owner: Control) -> void:
	var present_edgeless_preview: Control = owner.get("_present_edgeless_preview")
	if not present_edgeless_preview:
		return
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		return
	var cam: Dictionary = present_edgeless_preview.call("get_camera")
	var step: Dictionary = {"id": "step_%d" % int(Time.get_unix_time_from_system() * 1000.0), "camera": cam}
	var present_selected_ref_any: Variant = owner.get("_present_selected_ref")
	var present_selected_ref: Dictionary = present_selected_ref_any if typeof(present_selected_ref_any) == TYPE_DICTIONARY else {}
	if not present_selected_ref.is_empty() and str(present_selected_ref.get("kind", "")).strip_edges() == "syndoc_frame":
		var fid := str(present_selected_ref.get("frame_id", "")).strip_edges()
		if not fid.is_empty():
			step["frame_id"] = fid
			step["label"] = fid
	var steps := get_presentation_steps(owner)
	steps.append(step)
	set_presentation_steps(owner, steps)
	owner.set("_present_deck_step_idx", steps.size() - 1)
	owner.call("_write_model_to_raw_json")
	owner.call("_set_status", "Deck: captured step %d/%d%s (Save SynDoc to persist)" % [
		int(owner.get("_present_deck_step_idx")) + 1,
		steps.size(),
		(" for %s" % str(step.get("frame_id", ""))) if step.has("frame_id") else ""
	])


static func on_present_clear_deck(owner: Control) -> void:
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		return
	var p := get_presentation_dict(owner)
	p["steps"] = []
	flowdoc_model["presentation"] = p
	owner.set("_flowdoc_model", flowdoc_model)
	owner.set("_present_deck_step_idx", -1)
	owner.call("_write_model_to_raw_json")
	owner.call("_set_status", "Deck: cleared. (Save SynDoc to persist)")


static func apply_present_deck_step(owner: Control, idx: int, force: bool = false, sync_frame: bool = true) -> void:
	var present_edgeless_preview: Control = owner.get("_present_edgeless_preview")
	if not present_edgeless_preview:
		return
	var steps := get_presentation_steps(owner)
	if idx < 0 or idx >= steps.size():
		return
	var s_any: Variant = steps[idx]
	if typeof(s_any) != TYPE_DICTIONARY:
		return
	var s: Dictionary = s_any
	var cam_any: Variant = s.get("camera", null)
	if typeof(cam_any) != TYPE_DICTIONARY:
		return
	var cam: Dictionary = cam_any
	var center_any: Variant = cam.get("center", [])
	var center: Array = center_any if typeof(center_any) == TYPE_ARRAY else []
	var zoom := float(cam.get("zoom", 1.0))
	present_edgeless_preview.call("set_camera", center, zoom)
	if sync_frame:
		var fid := str(s.get("frame_id", "")).strip_edges()
		if not fid.is_empty():
			var frames: Array = owner.call("_get_frames")
			var fidx := frame_idx_by_id(frames, fid)
			if fidx != -1:
				owner.set("_active_frame_idx", fidx)
				owner.call("_refresh_frames_ui")
				owner.call("_refresh_blocks_ui")
				owner.call("_refresh_performer_ui")
			owner.call("_sync_present_edgeless_to_active_frame")
	if force:
		var label := str(s.get("label", "")).strip_edges()
		owner.call("_set_status", "Deck: applied step %d/%d%s" % [idx + 1, steps.size(), (": %s" % label) if not label.is_empty() else ""])


static func apply_present_camera_for_frame_idx(owner: Control, idx: int, force: bool = false) -> void:
	var present_edgeless_preview: Control = owner.get("_present_edgeless_preview")
	if not present_edgeless_preview:
		return
	var frames: Array = owner.call("_get_frames")
	if frames.is_empty() or idx < 0 or idx >= frames.size():
		return
	if typeof(frames[idx]) != TYPE_DICTIONARY:
		return
	var f: Dictionary = frames[idx]
	var cam_any: Variant = f.get("camera", null)
	if typeof(cam_any) != TYPE_DICTIONARY:
		if force:
			owner.call("_set_status", "No camera saved for this frame.")
		return
	var cam: Dictionary = cam_any
	var center_any: Variant = cam.get("center", [])
	var center: Array = center_any if typeof(center_any) == TYPE_ARRAY else []
	var zoom := float(cam.get("zoom", 1.0))
	present_edgeless_preview.call("set_camera", center, zoom)
	if force:
		owner.call("_set_status", "Applied camera for frame %s." % str(owner.call("_frame_id_for_index", idx)))


static func apply_present_camera_for_active_frame(owner: Control, force: bool = false, prefer_selection: bool = true) -> void:
	var frames: Array = owner.call("_get_frames")
	if frames.is_empty():
		return
	var idx := present_target_frame_idx(owner, frames) if prefer_selection else int(owner.get("_active_frame_idx"))
	apply_present_camera_for_frame_idx(owner, idx, force)


static func frame_has_saved_camera(frames: Array, idx: int) -> bool:
	if idx < 0 or idx >= frames.size():
		return false
	var f_any: Variant = frames[idx]
	if typeof(f_any) != TYPE_DICTIONARY:
		return false
	var f: Dictionary = f_any
	return typeof(f.get("camera", null)) == TYPE_DICTIONARY


static func find_deck_step_idx_for_frame_id(owner: Control, frame_id: String) -> int:
	var fid := String(frame_id).strip_edges()
	if fid.is_empty():
		return -1
	var steps := get_presentation_steps(owner)
	for i in range(steps.size() - 1, -1, -1):
		var s_any: Variant = steps[i]
		if typeof(s_any) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = s_any
		if str(s.get("frame_id", "")).strip_edges() == fid:
			return i
	return -1
