extends RefCounted
class_name SynpunktFrameBlockEditorUtils

static func get_frames(owner: Control) -> Array:
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	var frames_any: Variant = flowdoc_model.get("frames", [])
	if typeof(frames_any) != TYPE_ARRAY:
		return []
	return frames_any


static func get_active_frame(owner: Control) -> Dictionary:
	var frames := get_frames(owner)
	if frames.is_empty():
		return {}
	var idx := int(owner.get("_active_frame_idx"))
	idx = clamp(idx, 0, frames.size() - 1)
	owner.set("_active_frame_idx", idx)
	var f_any: Variant = frames[idx]
	if typeof(f_any) != TYPE_DICTIONARY:
		return {}
	return f_any


static func get_active_frame_id(owner: Control) -> String:
	var f := get_active_frame(owner)
	var fid := str(f.get("id", "")).strip_edges()
	var idx := int(owner.get("_active_frame_idx"))
	return fid if not fid.is_empty() else "frame_%d" % (idx + 1)


static func get_blocks(owner: Control) -> Array:
	var frame := get_active_frame(owner)
	if frame.is_empty():
		return []
	var blocks_any: Variant = frame.get("blocks", [])
	if typeof(blocks_any) != TYPE_ARRAY:
		return []
	return blocks_any


static func set_blocks(owner: Control, blocks: Array) -> void:
	var frames := get_frames(owner)
	if frames.is_empty():
		return
	var idx := int(owner.get("_active_frame_idx"))
	idx = clamp(idx, 0, frames.size() - 1)
	owner.set("_active_frame_idx", idx)
	if typeof(frames[idx]) != TYPE_DICTIONARY:
		return
	var frame: Dictionary = frames[idx]
	frame["blocks"] = blocks
	frames[idx] = frame
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	flowdoc_model["frames"] = frames
	owner.set("_flowdoc_model", flowdoc_model)


static func write_model_to_raw_json(owner: Control) -> void:
	owner.set("_updating_ui", true)
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_json:
		flowdoc_json.text = JSON.stringify(flowdoc_model, "\t")
	owner.set("_updating_ui", false)


static func block_type_display_name(code: String) -> String:
	match String(code).strip_edges():
		"h1":
			return "Heading"
		"h2":
			return "Subheading"
		"li":
			return "Bullet"
		"p":
			return "Paragraph"
		_:
			return String(code).strip_edges()


static func frame_id_for_index(owner: Control, i: int) -> String:
	var frames := get_frames(owner)
	if i < 0 or i >= frames.size():
		return ""
	var f_any: Variant = frames[i]
	if typeof(f_any) != TYPE_DICTIONARY:
		return "frame_%d" % (i + 1)
	var f: Dictionary = f_any
	var fid := str(f.get("id", "")).strip_edges()
	return fid if not fid.is_empty() else "frame_%d" % (i + 1)


static func refresh_send_targets(owner: Control) -> void:
	var send_to_frame: OptionButton = owner.get("_send_to_frame")
	if not send_to_frame:
		return
	send_to_frame.clear()
	var frames := get_frames(owner)
	if frames.is_empty():
		send_to_frame.add_item("(no frames)", 0)
		send_to_frame.select(0)
		return
	var added := 0
	for i in range(frames.size()):
		var fid := frame_id_for_index(owner, i)
		send_to_frame.add_item(fid, i)
		added += 1
	if added == 0:
		send_to_frame.add_item("(no frames)", 0)
		send_to_frame.select(0)
		return
	var active_frame_idx := int(owner.get("_active_frame_idx"))
	var default_idx := clamp(active_frame_idx + 1, 0, frames.size() - 1)
	send_to_frame.select(default_idx)


static func refresh_frames_ui(owner: Control) -> void:
	owner.set("_updating_ui", true)
	var frames_list: ItemList = owner.get("_frames_list")
	if not frames_list:
		owner.set("_updating_ui", false)
		return
	frames_list.clear()
	var frames := get_frames(owner)
	for i in range(frames.size()):
		var f_any: Variant = frames[i]
		if typeof(f_any) != TYPE_DICTIONARY:
			frames_list.add_item("%d: (invalid)" % i)
			continue
		var f: Dictionary = f_any
		var fid := str(f.get("id", "frame_%d" % (i + 1)))
		frames_list.add_item("%d: %s" % [i, fid])
	if frames.is_empty():
		owner.set("_active_frame_idx", 0)
	else:
		var idx := int(owner.get("_active_frame_idx"))
		idx = clamp(idx, 0, frames.size() - 1)
		owner.set("_active_frame_idx", idx)
		frames_list.select(idx)
		var frame_id_le: LineEdit = owner.get("_frame_id")
		if frame_id_le:
			frame_id_le.text = get_active_frame_id(owner)
		refresh_send_targets(owner)
	owner.set("_updating_ui", false)


static func refresh_blocks_ui(owner: Control) -> void:
	owner.set("_updating_ui", true)
	var blocks_list: ItemList = owner.get("_blocks_list")
	if not blocks_list:
		owner.set("_updating_ui", false)
		return
	blocks_list.clear()
	var prev_idx := int(owner.get("_active_block_idx"))
	owner.set("_active_block_idx", -1)
	var blocks := get_blocks(owner)
	var blocks_label: Label = owner.get("_blocks_label")
	if blocks_label:
		blocks_label.text = "Contents (%s)" % get_active_frame_id(owner)
	for i in range(blocks.size()):
		var b_any: Variant = blocks[i]
		if typeof(b_any) != TYPE_DICTIONARY:
			blocks_list.add_item("%d: (invalid)" % i)
			continue
		var b: Dictionary = b_any
		var t := str(b.get("type", ""))
		var txt := str(b.get("text", ""))
		if txt.length() > 36:
			txt = txt.left(36) + "…"
		blocks_list.add_item("%d: %s — %s" % [i, block_type_display_name(t), txt])
	var block_text: TextEdit = owner.get("_block_text")
	if block_text:
		block_text.text = ""
	var block_type: OptionButton = owner.get("_block_type")
	if block_type:
		block_type.select(1)
	if blocks.size() > 0:
		var idx := prev_idx if (prev_idx >= 0 and prev_idx < blocks.size()) else 0
		owner.set("_active_block_idx", idx)
		blocks_list.select(idx)
	owner.set("_updating_ui", false)
	var active_block_idx := int(owner.get("_active_block_idx"))
	if active_block_idx >= 0:
		on_block_selected(owner, active_block_idx)


static func on_block_selected(owner: Control, idx: int) -> void:
	if bool(owner.get("_updating_ui")):
		return
	owner.set("_active_block_idx", idx)
	var blocks := get_blocks(owner)
	if idx < 0 or idx >= blocks.size():
		return
	var b_any: Variant = blocks[idx]
	if typeof(b_any) != TYPE_DICTIONARY:
		return
	var b: Dictionary = b_any
	owner.set("_updating_ui", true)
	var block_text: TextEdit = owner.get("_block_text")
	if block_text:
		block_text.text = str(b.get("text", ""))
	owner.set("_updating_ui", false)


static func select_block_type(owner: Control, t: String) -> void:
	var block_type: OptionButton = owner.get("_block_type")
	if not block_type:
		return
	match t:
		"h1":
			block_type.select(0)
		"p":
			block_type.select(1)
		"h2":
			block_type.select(2)
		"li":
			block_type.select(3)
		_:
			block_type.select(1)


static func selected_block_type_code(owner: Control) -> String:
	var block_type: OptionButton = owner.get("_block_type")
	var selected := int(block_type.selected) if block_type else 1
	match selected:
		0:
			return "h1"
		1:
			return "p"
		2:
			return "h2"
		3:
			return "li"
		_:
			return "p"


static func update_block_list_item(owner: Control, idx: int) -> void:
	var blocks_list: ItemList = owner.get("_blocks_list")
	if not blocks_list:
		return
	var blocks := get_blocks(owner)
	if idx < 0 or idx >= blocks.size():
		return
	var b_any: Variant = blocks[idx]
	if typeof(b_any) != TYPE_DICTIONARY:
		return
	var b: Dictionary = b_any
	var t := block_type_display_name(str(b.get("type", "")))
	var txt := str(b.get("text", ""))
	if txt.length() > 36:
		txt = txt.left(36) + "…"
	blocks_list.set_item_text(idx, "%d: %s — %s" % [idx, t, txt])


static func on_block_edited(owner: Control) -> void:
	if bool(owner.get("_updating_ui")):
		return
	var active_block_idx := int(owner.get("_active_block_idx"))
	if active_block_idx < 0:
		return
	var blocks := get_blocks(owner)
	if active_block_idx >= blocks.size():
		return
	var b_any: Variant = blocks[active_block_idx]
	if typeof(b_any) != TYPE_DICTIONARY:
		return
	var b: Dictionary = b_any
	var block_text: TextEdit = owner.get("_block_text")
	b["text"] = block_text.text if block_text else ""
	blocks[active_block_idx] = b
	set_blocks(owner, blocks)
	write_model_to_raw_json(owner)
	update_block_list_item(owner, active_block_idx)
	var blocks_list: ItemList = owner.get("_blocks_list")
	if blocks_list:
		blocks_list.select(active_block_idx)


static func insert_block_after(owner: Control) -> void:
	var blocks := get_blocks(owner)
	var active_block_idx := int(owner.get("_active_block_idx"))
	var insert_at := active_block_idx + 1 if active_block_idx >= 0 else blocks.size()
	var t := selected_block_type_code(owner)
	var new_block := {"type": t, "text": ""}
	blocks.insert(insert_at, new_block)
	set_blocks(owner, blocks)
	owner.set("_active_block_idx", insert_at)
	write_model_to_raw_json(owner)
	refresh_blocks_ui(owner)
	var blocks_list: ItemList = owner.get("_blocks_list")
	if blocks_list:
		blocks_list.select(insert_at)
	on_block_selected(owner, insert_at)


static func delete_selected_block(owner: Control) -> void:
	var active_block_idx := int(owner.get("_active_block_idx"))
	if active_block_idx < 0:
		return
	var blocks := get_blocks(owner)
	if active_block_idx >= blocks.size():
		return
	blocks.remove_at(active_block_idx)
	set_blocks(owner, blocks)
	active_block_idx = min(active_block_idx, blocks.size() - 1)
	owner.set("_active_block_idx", active_block_idx)
	write_model_to_raw_json(owner)
	refresh_blocks_ui(owner)
	if active_block_idx >= 0:
		var blocks_list: ItemList = owner.get("_blocks_list")
		if blocks_list:
			blocks_list.select(active_block_idx)
		on_block_selected(owner, active_block_idx)


static func move_block(owner: Control, delta: int) -> void:
	var active_block_idx := int(owner.get("_active_block_idx"))
	if active_block_idx < 0:
		return
	var blocks := get_blocks(owner)
	var j := active_block_idx + delta
	if j < 0 or j >= blocks.size():
		return
	var tmp: Variant = blocks[active_block_idx]
	blocks[active_block_idx] = blocks[j]
	blocks[j] = tmp
	owner.set("_active_block_idx", j)
	set_blocks(owner, blocks)
	write_model_to_raw_json(owner)
	refresh_blocks_ui(owner)
	var blocks_list: ItemList = owner.get("_blocks_list")
	if blocks_list:
		blocks_list.select(j)
	on_block_selected(owner, j)


static func on_frame_selected(owner: Control, idx: int) -> void:
	if bool(owner.get("_updating_ui")):
		return
	owner.set("_active_frame_idx", idx)
	var frame_id: LineEdit = owner.get("_frame_id")
	if frame_id:
		frame_id.text = get_active_frame_id(owner)
	refresh_send_targets(owner)
	refresh_blocks_ui(owner)
	owner.call("_refresh_performer_ui")


static func jump_to_frame_id(owner: Control, frame_id: String) -> void:
	if bool(owner.get("_updating_ui")):
		return
	var fid := String(frame_id).strip_edges()
	if fid.is_empty():
		return
	var frames := get_frames(owner)
	if frames.is_empty():
		return
	var idx := -1
	for i in range(frames.size()):
		var f_any: Variant = frames[i]
		if typeof(f_any) != TYPE_DICTIONARY:
			continue
		var f: Dictionary = f_any
		if str(f.get("id", "")).strip_edges() == fid:
			idx = i
			break
	if idx < 0:
		return
	var active_frame_idx := int(owner.get("_active_frame_idx"))
	if idx == active_frame_idx:
		return
	var frames_list: ItemList = owner.get("_frames_list")
	if frames_list:
		owner.set("_updating_ui", true)
		frames_list.select(idx)
		owner.set("_updating_ui", false)
		if frames_list.has_method("ensure_current_is_visible"):
			frames_list.ensure_current_is_visible()
	on_frame_selected(owner, idx)


static func add_new_frame(owner: Control) -> void:
	var frames := get_frames(owner)
	if frames.is_empty():
		frames = []
	var next_n := frames.size() + 1
	var new_id := "frame_%d" % next_n
	var existing := {}
	for f_any in frames:
		if typeof(f_any) == TYPE_DICTIONARY:
			existing[str((f_any as Dictionary).get("id", ""))] = true
	while existing.has(new_id):
		next_n += 1
		new_id = "frame_%d" % next_n
	var new_frame := {
		"id": new_id,
		"kind": "document",
		"transform": {"x": 0, "y": 0, "w": 960, "h": 540},
		"blocks": [],
	}
	frames.append(new_frame)
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	flowdoc_model["frames"] = frames
	owner.set("_flowdoc_model", flowdoc_model)
	owner.set("_active_frame_idx", frames.size() - 1)
	write_model_to_raw_json(owner)
	refresh_frames_ui(owner)
	refresh_blocks_ui(owner)
	owner.call("_refresh_performer_ui")


static func delete_selected_frame(owner: Control) -> void:
	var frames := get_frames(owner)
	if frames.size() <= 1:
		owner.call("_set_status", "Can't delete the last frame.")
		return
	var active_frame_idx := int(owner.get("_active_frame_idx"))
	if active_frame_idx < 0 or active_frame_idx >= frames.size():
		return
	frames.remove_at(active_frame_idx)
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	flowdoc_model["frames"] = frames
	owner.set("_flowdoc_model", flowdoc_model)
	owner.set("_active_frame_idx", clamp(active_frame_idx, 0, frames.size() - 1))
	write_model_to_raw_json(owner)
	refresh_frames_ui(owner)
	refresh_blocks_ui(owner)
	owner.call("_refresh_performer_ui")


static func move_frame(owner: Control, delta: int) -> void:
	var frames := get_frames(owner)
	if frames.size() < 2:
		return
	var active_frame_idx := int(owner.get("_active_frame_idx"))
	var j := active_frame_idx + delta
	if j < 0 or j >= frames.size():
		return
	var tmp: Variant = frames[active_frame_idx]
	frames[active_frame_idx] = frames[j]
	frames[j] = tmp
	owner.set("_active_frame_idx", j)
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	flowdoc_model["frames"] = frames
	owner.set("_flowdoc_model", flowdoc_model)
	write_model_to_raw_json(owner)
	refresh_frames_ui(owner)
	refresh_blocks_ui(owner)
	owner.call("_refresh_performer_ui")


static func move_selected_block_to_target_frame(owner: Control) -> void:
	var active_block_idx := int(owner.get("_active_block_idx"))
	if active_block_idx < 0:
		owner.call("_set_status", "Select a block first.")
		return
	var send_to_frame: OptionButton = owner.get("_send_to_frame")
	if not send_to_frame:
		return
	var target_idx := int(send_to_frame.get_selected_id())
	var frames := get_frames(owner)
	if frames.is_empty() or target_idx < 0 or target_idx >= frames.size():
		return
	var active_frame_idx := int(owner.get("_active_frame_idx"))
	if active_frame_idx < 0 or active_frame_idx >= frames.size():
		return
	if typeof(frames[active_frame_idx]) != TYPE_DICTIONARY or typeof(frames[target_idx]) != TYPE_DICTIONARY:
		return
	var src: Dictionary = frames[active_frame_idx]
	var dst: Dictionary = frames[target_idx]
	var src_blocks: Array = src.get("blocks", [])
	var dst_blocks: Array = dst.get("blocks", [])
	if active_block_idx < 0 or active_block_idx >= src_blocks.size():
		return
	var moved: Variant = src_blocks[active_block_idx]
	src_blocks.remove_at(active_block_idx)
	dst_blocks.append(moved)
	src["blocks"] = src_blocks
	dst["blocks"] = dst_blocks
	frames[active_frame_idx] = src
	frames[target_idx] = dst
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	flowdoc_model["frames"] = frames
	owner.set("_flowdoc_model", flowdoc_model)
	active_block_idx = clamp(active_block_idx, 0, src_blocks.size() - 1)
	owner.set("_active_block_idx", active_block_idx)
	write_model_to_raw_json(owner)
	refresh_blocks_ui(owner)
	owner.call("_refresh_performer_ui")
	if active_block_idx >= 0:
		var blocks_list: ItemList = owner.get("_blocks_list")
		if blocks_list:
			blocks_list.select(active_block_idx)
		on_block_selected(owner, active_block_idx)
	owner.call("_set_status", "Moved block to frame '%s'." % frame_id_for_index(owner, target_idx))
