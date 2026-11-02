## Purpose: Internal helpers for SyntreePanel content-sources glue (list/hierarchy/graph selection + dialog wiring).
@tool
extends RefCounted
class_name SyntreePanelContentSourcesGlue

const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")
const ContentBusScript = preload("res://addons/syntree/scripts/autoload/content_bus.gd")

static func _bus() -> ContentBusScript:
	return SynTreeAutoloads.content_bus()

static func setup_content_source_manager(panel: Object) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel._content_state_resource) or not is_instance_valid(panel._view_state_resource):
		return
	setup_content_list_view(panel)
	wire_content_state_signals(panel)
	wire_content_source_dialog_signals(panel)

static func setup_content_list_view(panel: Object) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel.content_list_view):
		return
	if panel.content_list_view.has_method("setup_list"):
		panel.content_list_view.setup_list(panel._plugin_ref, panel._content_state_resource, panel._view_state_resource)

static func wire_content_source_dialog_signals(panel: Object) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel.save_custom_sources_popup):
		return
	if panel.save_custom_sources_popup.has_signal("source_confirmed"):
		if not panel.save_custom_sources_popup.source_confirmed.is_connected(panel._on_source_created_confirmed):
			panel.save_custom_sources_popup.source_confirmed.connect(panel._on_source_created_confirmed)
	if panel.save_custom_sources_popup.has_signal("source_cancelled"):
		if not panel.save_custom_sources_popup.source_cancelled.is_connected(panel._on_content_source_cancelled):
			panel.save_custom_sources_popup.source_cancelled.connect(panel._on_content_source_cancelled)
	if panel.save_custom_sources_popup.has_signal("operation_failed"):
		if not panel.save_custom_sources_popup.operation_failed.is_connected(panel._on_operation_failed):
			panel.save_custom_sources_popup.operation_failed.connect(func(op: String, err: String):
				panel._on_operation_failed(op, err, "")
			)

static func on_add_source_btn_pressed(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	if is_instance_valid(panel.save_custom_sources_popup) and panel.save_custom_sources_popup.has_method("show_dialog"):
		panel.save_custom_sources_popup.show_dialog()
	else:
		push_warning("SyntreePanel: SaveCustomSourcesPopUp not available; cannot open Add Source dialog.")

static func on_delete_source_btn_pressed(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	panel._setup_content_sources_panel_controller()
	if is_instance_valid(panel._content_sources_panel_controller):
		panel._content_sources_panel_controller.delete_selected_sources()

static func on_footer_filter_pressed(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	var filter_popup = panel.get_node_or_null("%FilterPopup")
	if is_instance_valid(filter_popup) and filter_popup.has_method("show_dialog"):
		filter_popup.show_dialog()
	else:
		push_warning("SyntreePanel: FilterPopup node invalid or missing show_dialog method.")

static func on_footer_stats_pressed(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	var stats_popup = panel.get_node_or_null("%StatsPopup")
	if is_instance_valid(stats_popup) and stats_popup.has_method("show_dialog"):
		stats_popup.show_dialog()
	else:
		push_warning("SyntreePanel: StatsPopup node invalid or missing show_dialog method.")

static func setup_footer_refresh_menu(panel: Object) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel.refresh_menu_button):
		return
	var mb: MenuButton = panel.refresh_menu_button as MenuButton
	if not is_instance_valid(mb):
		return
	var popup: PopupMenu = mb.get_popup()
	if not is_instance_valid(popup):
		return
	popup.clear()
	popup.add_item("Refresh Active", 1)
	popup.add_item("Refresh List", 2)
	popup.set_item_tooltip(0, "Reload content for active sources (file/remote refresh as applicable).")
	popup.set_item_tooltip(1, "Rebuild the displayed source list (does not reread file contents).")
	if not popup.id_pressed.is_connected(panel._on_footer_refresh_menu_id_pressed):
		popup.id_pressed.connect(panel._on_footer_refresh_menu_id_pressed)

static func on_footer_refresh_menu_id_pressed(panel: Object, id: int) -> void:
	if not is_instance_valid(panel):
		return
	match id:
		1:
			if _bus() and _bus().has_method("refresh_active_sources"):
				_bus().refresh_active_sources()
		2:
			if is_instance_valid(panel.content_list_view) and panel.content_list_view.has_method("refresh_sources"):
				panel.content_list_view.refresh_sources()

static func on_footer_search_submitted(panel: Object, query: String) -> void:
	if not is_instance_valid(panel):
		return
	var q := String(query).strip_edges()
	if q.is_empty():
		return
	if not is_instance_valid(panel._content_state_resource) or not is_instance_valid(panel._view_state_resource):
		return

	var q_lc := q.to_lower()
	var tokens := q_lc.split(" ", false)
	if tokens.is_empty():
		tokens = [q_lc]

	var best_id := ""
	var best_score := -999999
	for sid_any in panel._content_state_resource.get_source_ids():
		var sid := str(sid_any)
		var sd: Dictionary = panel._content_state_resource.get_source_data(sid)
		var meta: Dictionary = sd.get("meta", {})
		var name := str(meta.get("name", sid))
		var path := str(meta.get("path", ""))
		var hay := ("%s %s %s" % [sid, name, path]).to_lower()
		var ok := true
		for t in tokens:
			if t.is_empty():
				continue
			if hay.find(t) == -1:
				ok = false
				break
		if not ok:
			continue
		var score := 0
		if name.to_lower().find(q_lc) != -1:
			score += 50
		if sid.to_lower().find(q_lc) != -1:
			score += 40
		if path.to_lower().find(q_lc) != -1:
			score += 10
		score -= int(name.length() / 50)
		if score > best_score:
			best_score = score
			best_id = sid

	if best_id.is_empty():
		panel._show_warning_dialog("No Match", "No content sources matched: %s" % q)
		return

	panel._view_state_resource.select_source(best_id, true)
	if is_instance_valid(panel.search_box):
		panel.search_box.text = ""

static func wire_content_state_signals(panel: Object) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel._content_state_resource):
		return
	if panel._content_state_resource.has_signal("node_selected"):
		if not panel._content_state_resource.node_selected.is_connected(panel._on_content_node_selected):
			panel._content_state_resource.node_selected.connect(panel._on_content_node_selected)
	if is_instance_valid(panel._view_state_resource) and panel._content_state_resource.has_signal("source_selected"):
		if not panel._content_state_resource.source_selected.is_connected(panel._on_content_source_selected_from_state):
			panel._content_state_resource.source_selected.connect(panel._on_content_source_selected_from_state)

static func on_content_source_selected_from_state(panel: Object, source_id: String, selected: bool) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel._view_state_resource):
		return
	var sid := String(source_id)
	var sel := bool(selected)
	if panel._view_state_resource.has_method("set_source_selected_no_change_current"):
		panel._view_state_resource.set_source_selected_no_change_current(sid, sel)
	else:
		panel._view_state_resource.select_source(sid, sel)

static func on_content_node_selected(panel: Object, node_id: String) -> void:
	if not is_instance_valid(panel):
		return
	print("[SELECT] SyntreePanel._on_content_node_selected received: '%s'" % node_id)
	panel._last_selected_node_id = String(node_id)
	if is_instance_valid(panel._content_state_resource):
		panel._last_action_source_id = String(panel._content_state_resource.get_source_for_node(panel._last_selected_node_id)).strip_edges()
	print("[SELECT] Updated _last_selected_node_id = '%s', _last_action_source_id = '%s'" % [panel._last_selected_node_id, panel._last_action_source_id])

static func get_action_source_id_for_menu(panel: Object) -> String:
	if not is_instance_valid(panel) or not is_instance_valid(panel._view_state_resource) or not is_instance_valid(panel._content_state_resource):
		return ""
	var nid := String(panel._last_selected_node_id).strip_edges()
	if nid.is_empty() and is_instance_valid(panel.content_hierarchy) and panel.content_hierarchy.has_method("get_primary_selected_node_id"):
		nid = String(panel.content_hierarchy.get_primary_selected_node_id()).strip_edges()
	if not nid.is_empty():
		var sid_from_node := String(panel._content_state_resource.get_source_for_node(nid)).strip_edges()
		if not sid_from_node.is_empty():
			return sid_from_node
	var selected: Array[String] = panel._view_state_resource.selected_source_ids.duplicate()
	if selected.size() == 1:
		return selected[0]
	return String(panel._view_state_resource.current_source_id).strip_edges()

static func popup_menu_centered(panel: Object, pm: PopupMenu) -> void:
	if not is_instance_valid(pm):
		return
	pm.reset_size()
	pm.popup_centered()

static func get_selected_single_source_id_for_menu(panel: Object) -> String:
	if not is_instance_valid(panel) or not is_instance_valid(panel._view_state_resource):
		return ""
	var selected: Array[String] = panel._view_state_resource.selected_source_ids.duplicate()
	return selected[0] if selected.size() == 1 else ""

static func get_source_display_name(panel: Object, source_id: String) -> String:
	if not is_instance_valid(panel) or not is_instance_valid(panel._content_state_resource) or source_id.is_empty():
		return source_id
	var sd: Dictionary = panel._content_state_resource.get_source_data(source_id)
	var meta: Dictionary = sd.get("meta", {})
	var name := str(meta.get("name", "")).strip_edges()
	return name if not name.is_empty() else source_id

static func are_all_sources_selected(panel: Object, all_ids: Array[String]) -> bool:
	if not is_instance_valid(panel) or not is_instance_valid(panel._view_state_resource):
		return false
	var ids: Array[String] = []
	for sid in all_ids:
		var s := String(sid).strip_edges()
		if s.is_empty():
			continue
		ids.append(s)
	if ids.is_empty():
		return false
	for sid in ids:
		if not panel._view_state_resource.selected_source_ids.has(sid):
			return false
	return true

static func toggle_select_all_sources(panel: Object) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel._view_state_resource) or not is_instance_valid(panel._content_state_resource):
		return
	var all_ids: Array[String] = []
	for sid_any in panel._content_state_resource.get_source_ids():
		all_ids.append(String(sid_any))
	var all_selected := are_all_sources_selected(panel, all_ids)
	if panel._view_state_resource.has_method("set_all_sources_selected"):
		panel._view_state_resource.set_all_sources_selected(all_ids, not all_selected)
	else:
		if all_selected:
			panel._view_state_resource.clear_selection()
		else:
			panel._view_state_resource.clear_selection()
			for sid in all_ids:
				panel._view_state_resource.set_source_selected_no_change_current(sid, true)
			if not all_ids.is_empty():
				panel._view_state_resource.current_source_id = all_ids[-1]
			panel._view_state_resource.view_state_changed.emit()

static func get_all_visible_graph_node_ids(panel: Object) -> Array[String]:
	var out: Array[String] = []
	if not is_instance_valid(panel):
		return out
	var ge: Node = panel.get_node_or_null("%ContentGraph")
	if not is_instance_valid(ge) or not (ge is GraphEdit):
		return out
	for child in (ge as GraphEdit).get_children():
		if child is GraphNode:
			var nid := String(child.name).strip_edges()
			if nid.is_empty():
				continue
			out.append(nid)
	return out

static func are_all_graph_nodes_selected(panel: Object, node_ids: Array[String]) -> bool:
	if node_ids.is_empty():
		return false
	if not is_instance_valid(panel):
		return false
	var ge: Node = panel.get_node_or_null("%ContentGraph")
	if not is_instance_valid(ge) or not (ge is GraphEdit):
		return false
	var set := {}
	for nid in node_ids:
		set[nid] = true
	for child in (ge as GraphEdit).get_children():
		if not (child is GraphNode):
			continue
		var gn := child as GraphNode
		if not set.has(gn.name):
			continue
		if not gn.selected:
			return false
	return true

static func toggle_select_all_graph_nodes(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	var ge: Node = panel.get_node_or_null("%ContentGraph")
	if not is_instance_valid(ge) or not (ge is GraphEdit):
		return
	var node_ids := get_all_visible_graph_node_ids(panel)
	if node_ids.is_empty():
		return
	var select_all := not are_all_graph_nodes_selected(panel, node_ids)
	for child in (ge as GraphEdit).get_children():
		if child is GraphNode:
			(child as GraphNode).selected = select_all

static func refresh_selected_source_content(panel: Object, source_id: String) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel._content_state_resource):
		return
	var sd: Dictionary = panel._content_state_resource.get_source_data(source_id)
	var meta: Dictionary = sd.get("meta", {})
	var origin := str(meta.get("source_origin", "file"))
	var p := str(meta.get("path", "")).strip_edges()
	if origin == "remote":
		if p.is_empty():
			panel._show_warning_dialog("Refresh Failed", "Remote source has no URL.")
			return
		if _bus() and _bus().has_method("trigger_remote_source_refresh"):
			_bus().trigger_remote_source_refresh(source_id, p)
		return
	if p.is_empty():
		panel._show_warning_dialog("Refresh Failed", "Source has no path.")
		return
	p = p.replace("\\", "/")
	if not FileAccess.file_exists(p):
		panel._show_warning_dialog("Refresh Failed", "File not found:\n%s" % p)
		return
	var f := FileAccess.open(p, FileAccess.READ)
	if not f:
		panel._show_warning_dialog("Refresh Failed", "Failed to open:\n%s" % p)
		return
	var txt := f.get_as_text()
	f.close()
	panel._content_state_resource.update_source_content(source_id, txt)

static func open_edit_content_source_dialog(panel: Object, source_id: String) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel._content_state_resource) or not is_instance_valid(panel.save_custom_sources_popup):
		return
	var sd: Dictionary = panel._content_state_resource.get_source_data(source_id)
	if sd.is_empty():
		return
	var meta: Dictionary = sd.get("meta", {})
	var name := str(meta.get("name", source_id))
	var path := str(meta.get("path", ""))
	var ai: Dictionary = meta.get("ai_context", {})
	var is_active := bool(ai.get("is_active", false))
	var is_metaprompt := bool(ai.get("metaprompt", false))
	if panel.save_custom_sources_popup.has_method("show_edit_dialog"):
		if panel.save_custom_sources_popup.has_method("show_edit_dialog_full"):
			panel.save_custom_sources_popup.show_edit_dialog_full(source_id, name, path, is_active, is_metaprompt)
		else:
			panel.save_custom_sources_popup.show_edit_dialog(source_id, name, path)
	else:
		panel.save_custom_sources_popup.show_dialog()

static func apply_edited_content_source(panel: Object, source_id: String, new_name: String, new_path: String) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel._content_state_resource):
		return
	var sid := String(source_id).strip_edges()
	if sid.is_empty():
		return
	var sd: Dictionary = panel._content_state_resource.get_source_data(sid)
	if sd.is_empty():
		return
	if not sd.has("meta") or not (sd.meta is Dictionary):
		sd["meta"] = {}
	var meta: Dictionary = sd["meta"]
	meta["name"] = String(new_name).strip_edges()
	meta["path"] = String(new_path).strip_edges()
	meta["modified"] = Time.get_datetime_string_from_system()
	var p := String(meta.get("path", ""))
	if p.begins_with("http://") or p.begins_with("https://"):
		meta["source_origin"] = "remote"
		meta["source_type"] = ""
	else:
		meta["source_origin"] = "file"
		meta["source_type"] = p.get_extension().to_lower()
	sd["meta"] = meta
	var ok: bool = bool(panel._content_state_resource.update_source(sid, sd))
	if ok:
		panel._content_state_resource.save_source(sid)
		if is_instance_valid(panel.content_list_view):
			panel.content_list_view.call_deferred("refresh_sources")
	else:
		panel._show_warning_dialog("Edit Failed", "Could not update content source metadata.")

static func apply_source_ai_flags(panel: Object, source_id: String, is_active: bool, is_metaprompt: bool) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel._content_state_resource):
		return
	var sid := String(source_id).strip_edges()
	if sid.is_empty():
		return
	if panel._content_state_resource.has_method("set_source_active_state"):
		panel._content_state_resource.set_source_active_state(sid, bool(is_active))
	if panel._content_state_resource.has_method("set_metaprompt_state"):
		panel._content_state_resource.set_metaprompt_state(sid, bool(is_metaprompt))
	panel._content_state_resource.save_source(sid)

static func on_source_created_confirmed(panel: Object, source_info: Dictionary) -> void:
	if not is_instance_valid(panel):
		return
	# Edit mode: override existing source metadata and persist.
	if str(source_info.get("mode", "create")) == "edit":
		var sid := str(source_info.get("source_id", "")).strip_edges()
		var new_name := str(source_info.get("name", "")).strip_edges()
		var new_path := str(source_info.get("path", "")).strip_edges()
		var is_active := bool(source_info.get("is_active", false))
		var is_metaprompt := bool(source_info.get("is_metaprompt", false))
		if sid.is_empty():
			panel._show_error_dialog("Edit Failed", "Missing source_id for edit operation.")
			return
		if new_name.is_empty() or new_path.is_empty():
			panel._show_error_dialog("Edit Failed", "Name/path cannot be empty.")
			return
		apply_edited_content_source(panel, sid, new_name, new_path)
		apply_source_ai_flags(panel, sid, is_active, is_metaprompt)
		return

	var user_path := str(source_info.get("path", "")).strip_edges()
	var user_name := str(source_info.get("name", "")).strip_edges()
	var desired_active := bool(source_info.get("is_active", false))
	var desired_metaprompt := bool(source_info.get("is_metaprompt", false))

	if user_path.is_empty() or user_name.is_empty():
		panel._show_error_dialog("Invalid Data", "Received invalid data from create dialog.")
		return

	if user_path.begins_with("http://") or user_path.begins_with("https://"):
		if _bus() and _bus().has_method("request_load_source_from_url"):
			_bus().request_load_source_from_url(user_path, user_name)
		panel._pending_state_overrides_by_source_id[user_name] = {"is_active": desired_active, "is_metaprompt": desired_metaprompt}
		if is_instance_valid(panel._content_sources_panel_controller):
			panel._content_sources_panel_controller.note_url_child_pending(user_name, user_path)
		return

	var content_service = panel._plugin_manager.get_content_service()
	if is_instance_valid(content_service) and content_service.has_method("create_source_from_file"):
		var result = await content_service.create_source_from_file(user_name, user_path)
		if result.success:
			var created_sid := ""
			var data: Variant = result.get("data", {})
			if data is Dictionary:
				created_sid = str((data as Dictionary).get("meta", {}).get("source_id", "")).strip_edges()
			if created_sid.is_empty():
				created_sid = user_name.to_lower().replace(" ", "_").replace("-", "_")
			apply_source_ai_flags(panel, created_sid, desired_active, desired_metaprompt)

			if is_instance_valid(panel._content_sources_panel_controller):
				panel._content_sources_panel_controller.on_source_created_confirmed(created_sid, user_name, user_path)
			if is_instance_valid(panel.content_list_view):
				if panel.content_list_view.has_method("clear_filters"):
					panel.content_list_view.clear_filters()
				panel.content_list_view.call_deferred("refresh_sources")
			else:
				push_warning("SyntreePanel: content_list_view invalid, cannot refresh.")
		else:
			panel._show_error_dialog("Creation Failed", result.get("error", "Failed to create local source via service."))
	else:
		panel._show_error_dialog("Creation Failed", "ContentService unavailable or missing create_source_from_file method.")

static func on_batched_sources_created_confirmed(panel: Object, sources_array: Array) -> void:
	if not is_instance_valid(panel):
		return
	print("SyntreePanel: _on_batched_sources_created_confirmed received. Triggering list refresh.")
	if is_instance_valid(panel.content_list_view):
		panel.content_list_view.call_deferred("refresh_sources")
	else:
		push_warning("SyntreePanel: content_list_view invalid, cannot refresh after batch source confirmed.")

static func on_remote_source_processed(panel: Object, source_id: String) -> void:
	if not is_instance_valid(panel):
		return
	print("SyntreePanel: Received remote_source_processed signal for %s. Refreshing list view." % source_id)
	if panel._pending_state_overrides_by_source_id.has(source_id):
		var o1: Dictionary = panel._pending_state_overrides_by_source_id[source_id]
		apply_source_ai_flags(panel, source_id, bool(o1.get("is_active", false)), bool(o1.get("is_metaprompt", false)))
		panel._pending_state_overrides_by_source_id.erase(source_id)
	else:
		if is_instance_valid(panel._content_state_resource):
			var sd: Dictionary = panel._content_state_resource.get_source_data(source_id)
			var meta: Dictionary = sd.get("meta", {})
			var nm := str(meta.get("name", "")).strip_edges()
			if not nm.is_empty() and panel._pending_state_overrides_by_source_id.has(nm):
				var o2: Dictionary = panel._pending_state_overrides_by_source_id[nm]
				apply_source_ai_flags(panel, source_id, bool(o2.get("is_active", false)), bool(o2.get("is_metaprompt", false)))
				panel._pending_state_overrides_by_source_id.erase(nm)

	if is_instance_valid(panel._content_sources_panel_controller):
		panel._content_sources_panel_controller.on_source_loaded_or_updated(source_id)
	if is_instance_valid(panel.content_list_view):
		if panel.content_list_view.has_method("clear_filters"):
			panel.content_list_view.clear_filters()
		panel.content_list_view.call_deferred("refresh_sources")
	else:
		push_warning("SyntreePanel: ContentListView invalid, cannot refresh after remote source processed.")

static func update_active_filters_label(panel: Object, filters: Dictionary) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel.active_filters_label):
		push_warning("SyntreePanel: ActiveFiltersLabel node is not valid.")
		return
	if filters.is_empty():
		panel.active_filters_label.text = "Filters: None"
		panel.active_filters_label.tooltip_text = "No filters currently active."
		return
	var filter_count := filters.size()
	var filter_strings: Array = []
	var key_names = {
		"source_origin": "Origin",
		"source_type": "Type",
		"is_active": "Active",
		"is_metaprompt": "Metaprompt"
	}
	for key in filters:
		var value = filters[key]
		var key_display = key_names.get(key, String(key).capitalize())
		var value_display = str(value).capitalize()
		filter_strings.append("%s=%s" % [key_display, value_display])
	var joined_filters := ", ".join(filter_strings)
	panel.active_filters_label.text = "Filters (%d): %s" % [filter_count, joined_filters]
	panel.active_filters_label.tooltip_text = panel.active_filters_label.text

static func toggle_select_all_hierarchy_nodes(panel: Object) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel.content_hierarchy):
		return
	if not panel.content_hierarchy.has_method("are_all_visible_nodes_selected") or not panel.content_hierarchy.has_method("set_all_visible_nodes_selected"):
		return
	var all_selected := bool(panel.content_hierarchy.are_all_visible_nodes_selected())
	panel.content_hierarchy.set_all_visible_nodes_selected(not all_selected)

static func get_selected_node_id_for_tree_actions(panel: Object, source_id: String) -> String:
	var nid := String(panel._last_selected_node_id).strip_edges()
	if nid.is_empty() and is_instance_valid(panel.content_hierarchy) and panel.content_hierarchy.has_method("get_primary_selected_node_id"):
		nid = String(panel.content_hierarchy.get_primary_selected_node_id()).strip_edges()
	if nid.is_empty():
		return ""
	if is_instance_valid(panel._content_state_resource):
		var esrc := String(panel._content_state_resource.get_source_for_node(nid)).strip_edges()
		if esrc.is_empty():
			return ""
	return nid

static func raw_node_id(panel: Object, any_id: String) -> String:
	var s := String(any_id).strip_edges()
	if s.is_empty():
		return ""
	if is_instance_valid(panel._content_state_resource) and panel._content_state_resource.has_method("parse_composed_node_id"):
		var parsed: Dictionary = panel._content_state_resource.parse_composed_node_id(s)
		if bool(parsed.get("is_composed", false)):
			return str(parsed.get("node_id", "")).strip_edges()
	return s

static func request_delete_selected_node(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	var nid := get_selected_node_id_for_tree_actions(panel, "")
	if nid.is_empty():
		panel._show_warning_dialog("Select a Node", "Click a node in the hierarchy (or graph) first, then try again.")
		return
	var nid_raw := raw_node_id(panel, nid)
	var src: String = str(panel._content_state_resource.get_source_for_node(nid))
	if src.is_empty():
		panel._show_warning_dialog("Delete Failed", "Could not resolve source for node:\n%s" % nid)
		return
	var confirm_dialog := ConfirmationDialog.new()
	confirm_dialog.title = "Confirm Node Deletion"
	confirm_dialog.dialog_text = "Delete this node?\n\nNode: %s\nSource: %s\n\nThis cannot be undone." % [nid_raw, src]
	confirm_dialog.confirmed.connect(func():
		delete_selected_node(panel)
		confirm_dialog.queue_free()
	)
	confirm_dialog.canceled.connect(func(): confirm_dialog.queue_free())
	panel.add_child(confirm_dialog)
	confirm_dialog.popup_centered()

static func delete_selected_node(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	var nid := get_selected_node_id_for_tree_actions(panel, "")
	if nid.is_empty():
		panel._show_warning_dialog("Select a Node", "Click a node in the hierarchy (or graph) first, then try again.")
		return
	var nid_raw := raw_node_id(panel, nid)
	var src: String = str(panel._content_state_resource.get_source_for_node(nid))
	if src.is_empty():
		panel._show_warning_dialog("Delete Failed", "Could not resolve source for node:\n%s" % nid)
		return
	var d: Dictionary = panel._content_state_resource.get_source_data(src)
	if d.is_empty() or not (d.get("content", {}) is Dictionary) or not d.content.has("nodes") or not (d.content.nodes is Array):
		return
	var nodes: Array = d.content.nodes
	var removed := false
	for i in range(nodes.size() - 1, -1, -1):
		var n = nodes[i]
		if n is Dictionary and str(n.get("node_id", "")) == nid_raw:
			nodes.remove_at(i)
			removed = true
			break
	if not removed:
		panel._show_warning_dialog("Delete Failed", "Node not found in source.")
		return
	for n_any in nodes:
		if not (n_any is Dictionary) or not n_any.has("relationships"):
			continue
		var rel_v: Variant = n_any.relationships
		if rel_v is Dictionary:
			var rel: Dictionary = rel_v
			var children_v: Variant = rel.get("children", [])
			if children_v is Array:
				(children_v as Array).erase(nid_raw)
				rel["children"] = children_v
			var parents_v: Variant = rel.get("parents", [])
			if parents_v is Array:
				(parents_v as Array).erase(nid_raw)
				rel["parents"] = parents_v
			n_any["relationships"] = rel
	d.content["nodes"] = nodes
	if panel._content_state_resource.update_source(src, d):
		panel._content_state_resource.save_source(src)
		if panel._content_state_resource.has_method("normalize_source_graph"):
			panel._content_state_resource.normalize_source_graph(src)
		panel._last_selected_node_id = ""
		panel._refresh_hierarchy_view_deferred()
	else:
		panel._show_warning_dialog("Delete Failed", "Could not update source after deletion.")

static func on_manage_sources_menu_pressed(panel: Object, id: int) -> void:
	if not is_instance_valid(panel):
		return
	match id:
		0:
			var filter_popup = panel.get_node_or_null("%FilterPopup")
			if is_instance_valid(filter_popup) and filter_popup.has_method("show_dialog"):
				filter_popup.show_dialog()
			else:
				push_error("SyntreePanel: FilterPopup node invalid or missing show_dialog method.")
		1:
			if panel.has_node("%StatsPopup"):
				panel.get_node("%StatsPopup").show_dialog()
		2:
			if _bus() and _bus().has_method("refresh_active_sources"):
				_bus().refresh_active_sources()
		3:
			panel.content_list_view.refresh_sources()
		4:
			panel._setup_content_sources_panel_controller()
			if is_instance_valid(panel._content_sources_panel_controller):
				panel._content_sources_panel_controller.delete_selected_sources()
		panel.MENU_ID_PUBLISH_CONTEXT_GRAPH:
			# Side-effect action (Hub write). Gate behind Dev Agent toggle.
			if _bus() and _bus().has_method("is_dev_agent_enabled") and not bool(_bus().is_dev_agent_enabled()):
				panel._show_warning_dialog("Dev Agent is OFF", "Enable Dev Agent to publish context graphs.")
				return
			print("SynTree: Publish Context Graph clicked")
			if not is_instance_valid(panel._publish_context_graph_controller):
				panel._setup_publish_context_graph_controller()
			if is_instance_valid(panel._publish_context_graph_controller):
				panel._publish_context_graph_controller.start_publish()

static func on_content_source_selected(panel: Object, index: int) -> void:
	if not is_instance_valid(panel):
		return
	var content_state = _bus().get_content_state_resource() if _bus() and _bus().has_method("get_content_state_resource") else null
	if not is_instance_valid(content_state):
		panel.operation_failed.emit("load_content", "Content state resource not available", "")
		return

	if content_state.has_method("clear_all_sources"):
		content_state.clear_all_sources()
	else:
		push_warning("SyntreePanel: ContentStateResource missing clear_all_sources method.")

	if index == 0:
		if _bus() and _bus().has_method("request_view_change"):
			await _bus().request_view_change(ContentBusScript.ViewMode.LIST)
		load_all_content_sources(panel)
		return

	var source_name = panel.content_source_list_options.get_item_text(index)
	if source_name.begins_with("[📁] ") or source_name.begins_with("[🌐] "):
		source_name = source_name.substr(4)

	if content_state.has_method("load_source_content"):
		var result = content_state.load_source_content(source_name)
		if not result.get("success", false):
			panel.operation_failed.emit("load_content", "Failed to load content source: " + source_name, result.get("error", ""))
			return
	else:
		push_warning("SyntreePanel: ContentStateResource missing load_source_content method.")
		return

	if _bus() and _bus().has_method("request_view_change"):
		await _bus().request_view_change(ContentBusScript.ViewMode.HIERARCHY, source_name)

static func load_all_content_sources(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	var content_state = _bus().get_content_state_resource() if _bus() and _bus().has_method("get_content_state_resource") else null
	if not is_instance_valid(content_state):
		panel.operation_failed.emit("load_content", "Content state resource not available", "")
		return
	if content_state.has_method("initialize_content_sources"):
		var result = content_state.initialize_content_sources("res://addons/syntree/content_source_lists/")
		if result.get("success", false):
			print("SyntreePanel: Successfully initialized/loaded %d content sources" % result.get("sources_loaded", 0))
		else:
			push_error("SyntreePanel: Failed to load sources: " + result.get("error", ""))
	else:
		push_error("SyntreePanel: ContentStateResource missing initialize_content_sources method. Cannot load all sources.")


