extends RefCounted
class_name SynpunktRenderResultsBrowserUtils

static func ensure_render_results_bound(owner: Control) -> void:
	var render_results: Variant = owner.get("_render_results")
	if render_results != null:
		return
	var root: Variant = owner.get("_root")
	if not is_instance_valid(root):
		return
	var n := (root as Node).get_node_or_null("Body/Right/ModeTabs/Render/RenderResults")
	if n != null and n is ItemList:
		owner.set("_render_results", n as ItemList)
		var rr: ItemList = owner.get("_render_results")
		rr.select_mode = ItemList.SELECT_MULTI
		var on_activated := Callable(owner, "_on_render_result_activated")
		var on_selected := Callable(owner, "_on_render_results_item_selected")
		var on_clicked := Callable(owner, "_on_render_results_item_clicked")
		var on_multi := Callable(owner, "_on_render_results_multi_selected")
		if not rr.item_activated.is_connected(on_activated):
			rr.item_activated.connect(on_activated)
		if not rr.item_selected.is_connected(on_selected):
			rr.item_selected.connect(on_selected)
		if rr.has_signal("item_clicked") and not rr.item_clicked.is_connected(on_clicked):
			rr.item_clicked.connect(on_clicked)
		if rr.has_signal("multi_selected") and not rr.multi_selected.is_connected(on_multi):
			rr.multi_selected.connect(on_multi)


static func get_selected_render_artifact_id(owner: Control) -> String:
	var rr: ItemList = owner.get("_render_results")
	if not rr:
		return ""
	var sel := rr.get_selected_items()
	if sel.is_empty():
		return ""
	var idx := int(sel[0])
	if idx < 0 or idx >= rr.item_count:
		return ""
	var meta := rr.get_item_metadata(idx)
	if meta != null and typeof(meta) == TYPE_DICTIONARY:
		var aid := str((meta as Dictionary).get("artifact_id", "")).strip_edges()
		if not aid.is_empty():
			return aid
	return str(owner.call("_parse_artifact_id_from_render_results_item", rr.get_item_text(idx)))


static func get_selected_render_artifact_ids(owner: Control) -> Array[String]:
	var out: Array[String] = []
	var rr: ItemList = owner.get("_render_results")
	if not rr:
		return out
	var sel := rr.get_selected_items()
	for idx_any in sel:
		var idx := int(idx_any)
		if idx < 0 or idx >= rr.item_count:
			continue
		var aid := ""
		var meta := rr.get_item_metadata(idx)
		if meta != null and typeof(meta) == TYPE_DICTIONARY:
			aid = str((meta as Dictionary).get("artifact_id", "")).strip_edges()
		if aid.is_empty():
			aid = str(owner.call("_parse_artifact_id_from_render_results_item", rr.get_item_text(idx)))
		if not aid.is_empty() and not out.has(aid):
			out.append(aid)
	return out


static func artifact_uri_from_id(owner: Control, artifact_id: String) -> String:
	var aid := String(artifact_id).strip_edges()
	if aid.is_empty():
		return ""
	var hub: Object = owner.get("_hub")
	if not hub:
		return ""
	var rec_res: Dictionary = await hub.call("get_artifact_record_by_id", aid)
	if not bool(rec_res.get("ok", false)):
		return ""
	var result: Dictionary = rec_res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	if rows.is_empty() or typeof(rows[0]) != TYPE_ARRAY:
		return ""
	var row: Array = rows[0]
	var idx_uri := cols.find("uri")
	if idx_uri == -1 or idx_uri >= row.size():
		return ""
	return str(row[idx_uri]).strip_edges()


static func path_from_file_uri(uri: String) -> String:
	var u := String(uri).strip_edges()
	if u.is_empty():
		return ""
	if not u.to_lower().begins_with("file:"):
		return ""
	var path := u
	path = path.replace("file:///", "/")
	path = path.replace("file://", "")
	if path.length() > 2 and path[0] == "/" and path[2] == ":":
		path = path.substr(1)
	path = path.uri_decode()
	return path


static func copy_selected_render_artifact_id(owner: Control) -> void:
	ensure_render_results_bound(owner)
	var aid := get_selected_render_artifact_id(owner)
	if aid.is_empty():
		owner.call("_set_status", "Render: select an artifact result first.")
		return
	DisplayServer.clipboard_set(aid)
	owner.call("_set_status", "Copied artifact id: %s" % aid)


static func open_selected_render_artifact_folder(owner: Control) -> void:
	ensure_render_results_bound(owner)
	var aid := get_selected_render_artifact_id(owner)
	if aid.is_empty():
		owner.call("_set_status", "Render: select an artifact result first.")
		return
	var uri := await artifact_uri_from_id(owner, aid)
	var path := path_from_file_uri(uri)
	if path.is_empty():
		owner.call("_set_status", "Open folder failed: no file uri for %s" % aid)
		return
	var folder := path.get_base_dir()
	if folder.is_empty():
		owner.call("_set_status", "Open folder failed: invalid path for %s" % aid)
		return
	if OS.has_method("shell_show_in_file_manager"):
		OS.shell_show_in_file_manager(path, true)
		return
	var err := OS.shell_open(folder)
	if err != OK:
		owner.call("_set_status", "Open folder failed: shell_open error %s" % str(err))


static func clear_render_results_list(owner: Control) -> void:
	ensure_render_results_bound(owner)
	var rr: ItemList = owner.get("_render_results")
	if rr:
		rr.clear()
	owner.set("_render_results_cache", [])
	owner.call("_update_render_artifact_details")
	owner.call("_set_status", "Render results list cleared.")


static func rename_selected_render_artifact(owner: Control) -> void:
	var render_artifact_name_edit: LineEdit = owner.get("_render_artifact_name_edit")
	var render_results: ItemList = owner.get("_render_results")
	var hub: Node = owner.get("_hub")
	if not render_artifact_name_edit or not render_results or not hub:
		return
	var new_name := render_artifact_name_edit.text.strip_edges()
	if new_name.is_empty():
		owner.call("_set_status", "Render: name cannot be empty.")
		return
	var aids: Array[String] = owner.call("_get_selected_render_artifact_ids")
	if aids.size() != 1:
		owner.call("_set_status", "Render: select exactly one artifact to rename.")
		return
	var aid := aids[0]
	var res: Dictionary = await hub.update_artifact_metadata(aid, {"ui": {"display_name": new_name}}, true)
	if not bool(res.get("ok", false)):
		owner.call("_set_status", "Render: rename failed for %s: %s" % [aid.left(12), owner.call("_error_details_text", res)])
		return
	await owner.call("_refresh_render_results_from_hub")
	owner.call("_on_render_results_item_selected", -1)
	owner.call("_set_status", "Render: renamed %s to '%s'." % [aid.left(12), new_name])


static func reset_selected_render_artifact_name(owner: Control) -> void:
	var render_results: ItemList = owner.get("_render_results")
	var hub: Node = owner.get("_hub")
	if not render_results or not hub:
		return
	var aids: Array[String] = owner.call("_get_selected_render_artifact_ids")
	if aids.size() != 1:
		owner.call("_set_status", "Render: select exactly one artifact to reset name.")
		return
	var aid := aids[0]
	var res: Dictionary = await hub.update_artifact_metadata(aid, {"ui": {"display_name": ""}}, true)
	if not bool(res.get("ok", false)):
		owner.call("_set_status", "Render: reset name failed for %s: %s" % [aid.left(12), owner.call("_error_details_text", res)])
		return
	await owner.call("_refresh_render_results_from_hub")
	owner.call("_on_render_results_item_selected", -1)
	owner.call("_set_status", "Render: reset name override for %s." % aid.left(12))


static func refresh_render_results_labels(owner: Control) -> void:
	var render_results: ItemList = owner.get("_render_results")
	if not render_results:
		return
	for i in range(render_results.item_count):
		var meta: Variant = render_results.get_item_metadata(i)
		if meta == null or typeof(meta) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = meta
		if str(m.get("kind", "")).strip_edges() != "artifact":
			continue
		var aid := str(m.get("artifact_id", "")).strip_edges()
		if aid.is_empty():
			continue
		var created := str(m.get("created_at", "")).strip_edges()
		var meta_txt := str(m.get("metadata_json", "")).strip_edges()
		render_results.set_item_text(i, owner.call("_artifact_item_label", aid, created, meta_txt))


static func on_render_results_item_selected(owner: Control, idx: int) -> void:
	var aid := ""
	var render_results: ItemList = owner.get("_render_results")
	if render_results and idx >= 0 and idx < render_results.item_count:
		var md_any: Variant = render_results.get_item_metadata(idx)
		if md_any != null and typeof(md_any) == TYPE_DICTIONARY:
			aid = str((md_any as Dictionary).get("artifact_id", "")).strip_edges()
		if aid.is_empty():
			aid = parse_artifact_id_from_render_results_item(render_results.get_item_text(idx))
	if aid.is_empty():
		var aids: Array[String] = owner.call("_get_selected_render_artifact_ids")
		if aids.size() == 1:
			aid = aids[0]
	owner.set("_last_render_selected_artifact_id", aid)
	var render_artifact_name_edit: LineEdit = owner.get("_render_artifact_name_edit")
	if not render_artifact_name_edit:
		owner.call("_update_render_artifact_details")
		return
	if aid.is_empty():
		render_artifact_name_edit.text = ""
		owner.call("_update_render_artifact_details")
		return
	var meta_txt := ""
	var sel := render_results.get_selected_items() if render_results else []
	if not sel.is_empty():
		var i := int(sel[0])
		if render_results and i >= 0 and i < render_results.item_count:
			var md: Variant = render_results.get_item_metadata(i)
			if md != null and typeof(md) == TYPE_DICTIONARY:
				meta_txt = str((md as Dictionary).get("metadata_json", "")).strip_edges()
	render_artifact_name_edit.text = str(owner.call("_artifact_display_name_for_id", aid, meta_txt))
	owner.call("_update_render_artifact_details")


static func on_render_results_item_clicked(owner: Control, idx: int) -> void:
	var render_results: ItemList = owner.get("_render_results")
	if not render_results or idx < 0 or idx >= render_results.item_count:
		return
	var md_any: Variant = render_results.get_item_metadata(idx)
	if md_any != null and typeof(md_any) == TYPE_DICTIONARY:
		var md: Dictionary = md_any
		var aid := str(md.get("artifact_id", "")).strip_edges()
		if not aid.is_empty():
			owner.set("_last_render_selected_artifact_id", aid)
			on_render_results_item_selected(owner, idx)
			return
	on_render_results_item_selected(owner, idx)


static func on_render_results_multi_selected(owner: Control, idx: int, selected: bool) -> void:
	if not selected:
		return
	on_render_results_item_clicked(owner, idx)


static func select_render_result_by_artifact_id(owner: Control, artifact_id: String) -> void:
	var render_results: ItemList = owner.get("_render_results")
	if not render_results:
		return
	var target := String(artifact_id).strip_edges()
	if target.is_empty():
		return
	for i in range(render_results.item_count):
		var md: Variant = render_results.get_item_metadata(i)
		if md == null or typeof(md) != TYPE_DICTIONARY:
			continue
		var meta: Dictionary = md
		if str(meta.get("kind", "")).strip_edges() != "artifact":
			continue
		if str(meta.get("artifact_id", "")).strip_edges() == target:
			render_results.select(i)
			if render_results.has_method("ensure_current_is_visible"):
				render_results.ensure_current_is_visible()
			on_render_results_item_selected(owner, i)
			return


static func parse_artifact_id_from_render_results_item(txt: String) -> String:
	var t := String(txt).strip_edges()
	if t.is_empty():
		return ""
	var i := t.find("art_")
	if i == -1:
		return ""
	var out := ""
	for j in range(i, t.length()):
		var ch := t[j]
		var code := ch.unicode_at(0)
		var is_digit := code >= 48 and code <= 57
		var is_upper := code >= 65 and code <= 90
		var is_lower := code >= 97 and code <= 122
		if ch == "_" or is_digit or is_upper or is_lower:
			out += ch
			continue
		break
	return out if out.begins_with("art_") else ""


static func on_render_result_activated(owner: Control, idx: int) -> void:
	var render_results: ItemList = owner.get("_render_results")
	var hub: Node = owner.get("_hub")
	if not render_results or not hub:
		return
	if idx < 0 or idx >= render_results.item_count:
		return
	var meta := render_results.get_item_metadata(idx)
	var aid := ""
	if meta != null and typeof(meta) == TYPE_DICTIONARY:
		aid = str((meta as Dictionary).get("artifact_id", "")).strip_edges()
	if aid.is_empty():
		aid = parse_artifact_id_from_render_results_item(render_results.get_item_text(idx))
	if aid.is_empty():
		return
	owner.set("_last_render_selected_artifact_id", aid)
	owner.call("_update_render_artifact_details")
	owner.call("_set_status", "Opening image artifact: %s" % aid)
	var rec_res: Dictionary = await hub.get_artifact_record_by_id(aid)
	if not bool(rec_res.get("ok", false)):
		owner.call("_set_status", "Open image failed (hub query): %s" % str(rec_res.get("error", rec_res)))
		return
	var result: Dictionary = rec_res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	if rows.is_empty() or typeof(rows[0]) != TYPE_ARRAY:
		owner.call("_set_status", "Open image failed: artifact not found: %s" % aid)
		return
	var row: Array = rows[0]
	var idx_uri := cols.find("uri")
	if idx_uri == -1 or idx_uri >= row.size():
		owner.call("_set_status", "Open image failed: missing uri for %s" % aid)
		return
	var uri := str(row[idx_uri]).strip_edges()
	if uri.is_empty():
		owner.call("_set_status", "Open image failed: empty uri for %s" % aid)
		return
	var err := OS.shell_open(uri)
	if err != OK:
		owner.call("_set_status", "Open image failed: shell_open error %s" % str(err))
