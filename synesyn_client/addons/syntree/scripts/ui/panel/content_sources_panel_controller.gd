## Purpose: Panel controller for the content-sources domain (menus + Add Child flow + Move Up/Down)
@tool
extends Node
class_name ContentSourcesPanelController

# This controller deliberately consolidates multiple content-sources behaviors to avoid over-atomization.

const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")

# --- Menu IDs (formerly in SyntreePanel / SourceMenuController) ---
const SRC_MENU_OPEN_HIERARCHY := 1001
const SRC_MENU_OPEN_GRAPH := 1002
const SRC_MENU_REFRESH_CONTENT := 1003
const SRC_MENU_TOGGLE_ACTIVE := 1004
const SRC_MENU_TOGGLE_METAPROMPT := 1005
const SRC_MENU_COPY_ID := 1006
const SRC_MENU_COPY_PATH := 1007
const SRC_MENU_REVEAL_ON_DISK := 1008
const SRC_MENU_DELETE := 1009
const SRC_MENU_STACK_TOGGLE_INCLUDE_UNWIRED := 1010
const SRC_MENU_EDIT_SOURCE := 1011
const SRC_MENU_SELECT_ALL_TOGGLE := 1012
const SRC_MENU_SELECT_ALL_NODES_TOGGLE := 1013

const TREE_MENU_EDIT := 100
const TREE_MENU_ADD_CHILD := 101
const TREE_MENU_DELETE := 102
const TREE_MENU_MOVE_UP := 103
const TREE_MENU_MOVE_DOWN := 104
const TREE_MENU_SAVE_HIERARCHY := 105
const TREE_MENU_IMPORT_HIERARCHY := 106
const TREE_MENU_REFRESH_CONTENT := 107
const TREE_MENU_REVEAL_ON_DISK := 108
const TREE_MENU_COPY_ID := 109
const TREE_MENU_COPY_PATH := 110
const TREE_MENU_OPEN_GRAPH := 111
const TREE_MENU_DELETE_SOURCE := 112
const TREE_MENU_SELECT_ALL_NODES_TOGGLE := 114

var _content_state: ContentStateResource = null
var _view_state: ViewStateResource = null
var _hierarchy_view: Node = null
var _graph_edit: GraphEdit = null
var _create_dialog: Node = null

# Disk/content ops dependencies (kept here so the content-sources domain stays cohesive).
var _plugin_manager: Object = null
var _notification_manager: Object = null
var _content_list_view: Node = null
var _content_dir_path_label: Label = null
var _show_error_cb: Callable = Callable()

const DEFAULT_CONTENT_SOURCES_DIR := "res://addons/syntree/content_source_lists/"

var _get_action_source_id_cb: Callable = Callable()
var _get_source_display_name_cb: Callable = Callable()
var _popup_centered_cb: Callable = Callable()
var _show_warning_cb: Callable = Callable()

var _get_selected_node_id_cb: Callable = Callable()
var _raw_node_id_cb: Callable = Callable()
var _refresh_hierarchy_cb: Callable = Callable()

# Side-effect callbacks we keep in SyntreePanel for now (UI dialogs).
var _open_edit_dialog_cb: Callable = Callable()
var _refresh_source_content_cb: Callable = Callable()
var _toggle_select_all_sources_cb: Callable = Callable()
var _toggle_select_all_graph_nodes_cb: Callable = Callable()
var _toggle_select_all_hierarchy_nodes_cb: Callable = Callable()
var _request_delete_selected_node_cb: Callable = Callable()

# Captured menu target to support node-driven context even when multi-select is active.
var _source_menu_target_source_id: String = ""

# Pending Add Child flow state (formerly AddChildFlowController)
var _pending_add_child_link: Dictionary = {} # {"parent_node_id": String, "parent_source_id": String}
var _pending_add_child_link_by_name: Dictionary = {} # name -> pending dict (URL “late resolve”)

func setup(
		content_state: ContentStateResource,
		view_state: ViewStateResource,
		hierarchy_view: Node,
		graph_edit: GraphEdit,
		create_dialog: Node,
		plugin_manager: Object,
		notification_manager: Object,
		content_list_view: Node,
		content_dir_path_label: Label,
		get_action_source_id_cb: Callable,
		get_source_display_name_cb: Callable,
		popup_centered_cb: Callable,
		show_warning_cb: Callable,
		show_error_cb: Callable,
		get_selected_node_id_cb: Callable,
		raw_node_id_cb: Callable,
		refresh_hierarchy_cb: Callable,
		open_edit_dialog_cb: Callable,
		refresh_source_content_cb: Callable,
		toggle_select_all_sources_cb: Callable,
		toggle_select_all_graph_nodes_cb: Callable,
		toggle_select_all_hierarchy_nodes_cb: Callable,
		request_delete_selected_node_cb: Callable
	) -> void:
	_content_state = content_state
	_view_state = view_state
	_hierarchy_view = hierarchy_view
	_graph_edit = graph_edit
	_create_dialog = create_dialog
	_plugin_manager = plugin_manager
	_notification_manager = notification_manager
	_content_list_view = content_list_view
	_content_dir_path_label = content_dir_path_label
	_get_action_source_id_cb = get_action_source_id_cb
	_get_source_display_name_cb = get_source_display_name_cb
	_popup_centered_cb = popup_centered_cb
	_show_warning_cb = show_warning_cb
	_show_error_cb = show_error_cb
	_get_selected_node_id_cb = get_selected_node_id_cb
	_raw_node_id_cb = raw_node_id_cb
	_refresh_hierarchy_cb = refresh_hierarchy_cb
	_open_edit_dialog_cb = open_edit_dialog_cb
	_refresh_source_content_cb = refresh_source_content_cb
	_toggle_select_all_sources_cb = toggle_select_all_sources_cb
	_toggle_select_all_graph_nodes_cb = toggle_select_all_graph_nodes_cb
	_toggle_select_all_hierarchy_nodes_cb = toggle_select_all_hierarchy_nodes_cb
	_request_delete_selected_node_cb = request_delete_selected_node_cb

func on_source_menu_button_pressed(tree_menu: PopupMenu, source_menu: PopupMenu) -> void:
	if not is_instance_valid(_view_state):
		return
	var mode := int(_view_state.current_mode)
	if mode == 1:
		if is_instance_valid(tree_menu):
			var sid := _get_action_source_id()
			_prepare_tree_context_menu(tree_menu, sid)
			_popup(tree_menu)
		return
	_show_source_context_menu(source_menu)

func move_selected(delta: int) -> void:
	# Former MoveNodeController
	if not is_instance_valid(_content_state) or not _get_selected_node_id_cb.is_valid():
		return
	var nid := String(_get_selected_node_id_cb.call("")).strip_edges()
	if nid.is_empty():
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Select a Node", "Click a node in the hierarchy (or graph) first, then try again.")
		return
	if not _content_state.has_method("move_hierarchy_node"):
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Move Failed", "ContentStateResource missing move_hierarchy_node().")
		return
	var stack_context := ""
	if is_instance_valid(_view_state):
		stack_context = String(_view_state.current_source_id).strip_edges()
	var result: Dictionary = _content_state.move_hierarchy_node(nid, delta, stack_context)
	if not bool(result.get("success", false)):
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Move Failed", str(result.get("error", "Unknown error")))
		return
	if _refresh_hierarchy_cb.is_valid():
		_refresh_hierarchy_cb.call()

func begin_add_child(fallback_source_id: String) -> void:
	# Former AddChildFlowController.begin_add_child
	if not is_instance_valid(_content_state) or not is_instance_valid(_create_dialog) or not _get_selected_node_id_cb.is_valid():
		return
	var parent_node_id := String(_get_selected_node_id_cb.call(fallback_source_id)).strip_edges()
	if parent_node_id.is_empty():
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Select a Node", "Click a node in the hierarchy (or graph) first, then try again.")
		return
	var parent_src := String(_content_state.get_source_for_node(parent_node_id)).strip_edges()
	if parent_src.is_empty():
		parent_src = String(fallback_source_id).strip_edges()
	if parent_src.is_empty():
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Add Child Failed", "Could not resolve the parent source.")
		return
	_pending_add_child_link = {"parent_node_id": parent_node_id, "parent_source_id": parent_src}
	if _create_dialog.has_method("show_dialog"):
		_create_dialog.call("show_dialog")
	else:
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Add Child Failed", "Create Source(s) dialog is not available.")

func note_url_child_pending(child_name: String, child_path: String) -> void:
	# Former AddChildFlowController.note_url_child_pending
	var nm := String(child_name).strip_edges()
	if nm.is_empty() or _pending_add_child_link.is_empty():
		return
	var p := _pending_add_child_link.duplicate(true)
	p["child_name"] = nm
	p["child_path"] = String(child_path).strip_edges()
	_pending_add_child_link_by_name[nm] = p
	_pending_add_child_link.clear()

func on_source_created_confirmed(created_source_id: String, user_name: String, user_path: String) -> void:
	# Former AddChildFlowController.on_source_created_confirmed
	var created_sid := String(created_source_id).strip_edges()
	if created_sid.is_empty() or _pending_add_child_link.is_empty():
		return
	var pnode := str(_pending_add_child_link.get("parent_node_id", "")).strip_edges()
	var psrc := str(_pending_add_child_link.get("parent_source_id", "")).strip_edges()
	_pending_add_child_link.clear()
	if pnode.is_empty() or psrc.is_empty():
		return
	if _attach_linked_child_source(pnode, psrc, created_sid, user_name, user_path):
		if _refresh_hierarchy_cb.is_valid():
			_refresh_hierarchy_cb.call()
	else:
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Add Child Failed", "Could not attach the new child source.")

func on_source_loaded_or_updated(source_id: String) -> void:
	# Former AddChildFlowController.on_source_loaded_or_updated
	if _pending_add_child_link_by_name.is_empty() or not is_instance_valid(_content_state):
		return
	var sid := String(source_id).strip_edges()
	if sid.is_empty():
		return
	var sd: Dictionary = _content_state.get_source_data(sid)
	var meta: Dictionary = sd.get("meta", {})
	var nm := str(meta.get("name", "")).strip_edges()
	var pending: Dictionary = {}
	if _pending_add_child_link_by_name.has(sid):
		pending = _pending_add_child_link_by_name[sid]
		_pending_add_child_link_by_name.erase(sid)
	elif not nm.is_empty() and _pending_add_child_link_by_name.has(nm):
		pending = _pending_add_child_link_by_name[nm]
		_pending_add_child_link_by_name.erase(nm)
	if pending.is_empty():
		return
	var pnode := str(pending.get("parent_node_id", "")).strip_edges()
	var psrc := str(pending.get("parent_source_id", "")).strip_edges()
	var cname := str(pending.get("child_name", nm)).strip_edges()
	var cpath := str(pending.get("child_path", "")).strip_edges()
	if pnode.is_empty() or psrc.is_empty():
		return
	if _attach_linked_child_source(pnode, psrc, sid, cname, cpath):
		if _refresh_hierarchy_cb.is_valid():
			_refresh_hierarchy_cb.call()

func _get_action_source_id() -> String:
	if _get_action_source_id_cb.is_valid():
		return String(_get_action_source_id_cb.call()).strip_edges()
	return ""

func _popup(pm: PopupMenu) -> void:
	if _popup_centered_cb.is_valid():
		_popup_centered_cb.call(pm)
	else:
		pm.reset_size()
		pm.popup_centered()

func _show_source_context_menu(pm: PopupMenu) -> void:
	if not is_instance_valid(pm) or not is_instance_valid(_view_state) or not is_instance_valid(_content_state):
		return
	_source_menu_target_source_id = ""
	var source_id := _get_action_source_id()
	if source_id.is_empty():
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Nothing Selected", "Select a content source (or click a node in Hierarchy/Graph) first.")
		return
	_source_menu_target_source_id = source_id
	var sd: Dictionary = _content_state.get_source_data(source_id)
	var meta: Dictionary = sd.get("meta", {})
	var ai: Dictionary = meta.get("ai_context", {})
	var is_stack := bool(ai.get("is_stack", false))
	var source_name := source_id
	if _get_source_display_name_cb.is_valid():
		source_name = String(_get_source_display_name_cb.call(source_id)).strip_edges()
		if source_name.is_empty():
			source_name = source_id

	pm.clear()
	pm.add_item("Source: %s" % source_name, -1)
	pm.set_item_disabled(0, true)
	pm.add_separator()

	var mode := int(_view_state.current_mode)
	if mode == 0:
		var all_ids: Array[String] = []
		if _content_state.has_method("get_source_ids"):
			for sid_any in _content_state.get_source_ids():
				all_ids.append(String(sid_any))
		var all_selected := _are_all_sources_selected(all_ids)
		pm.add_check_item("Select All Sources", SRC_MENU_SELECT_ALL_TOGGLE)
		var idx := pm.get_item_count() - 1
		pm.set_item_checked(idx, all_selected)
		pm.set_item_disabled(idx, all_ids.is_empty())
		pm.add_separator()
	elif mode == 2:
		var node_ids := _get_all_visible_graph_node_ids()
		var all_nodes_selected := _are_all_graph_nodes_selected(node_ids)
		pm.add_check_item("Select All Nodes", SRC_MENU_SELECT_ALL_NODES_TOGGLE)
		var idx2 := pm.get_item_count() - 1
		pm.set_item_checked(idx2, all_nodes_selected)
		pm.set_item_disabled(idx2, node_ids.is_empty())
		pm.add_separator()

	pm.add_item("Edit Source…", SRC_MENU_EDIT_SOURCE)
	pm.add_separator()
	pm.add_item("Open in Hierarchy", SRC_MENU_OPEN_HIERARCHY)
	pm.add_item("Open in Context Graph", SRC_MENU_OPEN_GRAPH)
	pm.add_separator()

	var is_active := bool(ai.get("is_active", false))
	var is_meta := bool(ai.get("metaprompt", false))
	pm.add_item(("Set Active: ON" if not is_active else "Set Active: OFF"), SRC_MENU_TOGGLE_ACTIVE)
	pm.add_item(("Set Metaprompt: ON" if not is_meta else "Set Metaprompt: OFF"), SRC_MENU_TOGGLE_METAPROMPT)
	pm.add_separator()
	pm.add_item("Refresh Content", SRC_MENU_REFRESH_CONTENT)
	if is_stack:
		var include_unwired := true
		if _content_state.has_method("get_stack_include_unwired_nodes"):
			include_unwired = bool(_content_state.get_stack_include_unwired_nodes(source_id))
		pm.add_item(("Stack: Include unwired (ON)" if include_unwired else "Stack: Include unwired (OFF)"), SRC_MENU_STACK_TOGGLE_INCLUDE_UNWIRED)
	pm.add_separator()
	pm.add_item("Copy Source ID", SRC_MENU_COPY_ID)
	pm.add_item("Copy Path", SRC_MENU_COPY_PATH)
	pm.add_item("Reveal on Disk", SRC_MENU_REVEAL_ON_DISK)
	pm.add_separator()
	pm.add_item("Delete Source…", SRC_MENU_DELETE)

	if not pm.id_pressed.is_connected(_on_source_menu_id_pressed):
		pm.id_pressed.connect(_on_source_menu_id_pressed)
	_popup(pm)

func _on_source_menu_id_pressed(id: int) -> void:
	if not is_instance_valid(_view_state) or not is_instance_valid(_content_state):
		return
	var source_id := String(_source_menu_target_source_id).strip_edges()
	if source_id.is_empty():
		source_id = _get_action_source_id()
	if source_id.is_empty():
		return
	var sd: Dictionary = _content_state.get_source_data(source_id)
	var meta: Dictionary = sd.get("meta", {})
	var ai: Dictionary = meta.get("ai_context", {})
	match id:
		SRC_MENU_SELECT_ALL_TOGGLE:
			if _toggle_select_all_sources_cb.is_valid():
				_toggle_select_all_sources_cb.call()
		SRC_MENU_SELECT_ALL_NODES_TOGGLE:
			if _toggle_select_all_graph_nodes_cb.is_valid():
				_toggle_select_all_graph_nodes_cb.call()
		SRC_MENU_EDIT_SOURCE:
			if _open_edit_dialog_cb.is_valid():
				_open_edit_dialog_cb.call(source_id)
		SRC_MENU_OPEN_HIERARCHY:
			_view_state.change_view(1, source_id)
		SRC_MENU_OPEN_GRAPH:
			_view_state.change_view(2, source_id)
		SRC_MENU_TOGGLE_ACTIVE:
			_content_state.set_source_active_state(source_id, not bool(ai.get("is_active", false)))
		SRC_MENU_TOGGLE_METAPROMPT:
			_content_state.set_metaprompt_state(source_id, not bool(ai.get("metaprompt", false)))
		SRC_MENU_STACK_TOGGLE_INCLUDE_UNWIRED:
			if _content_state.has_method("set_stack_include_unwired_nodes"):
				var cur := true
				if _content_state.has_method("get_stack_include_unwired_nodes"):
					cur = bool(_content_state.get_stack_include_unwired_nodes(source_id))
				_content_state.set_stack_include_unwired_nodes(source_id, not cur)
		SRC_MENU_COPY_ID:
			DisplayServer.clipboard_set(source_id)
		SRC_MENU_COPY_PATH:
			DisplayServer.clipboard_set(str(meta.get("path", "")))
		SRC_MENU_REVEAL_ON_DISK:
			reveal_source_on_disk(meta)
		SRC_MENU_REFRESH_CONTENT:
			if _refresh_source_content_cb.is_valid():
				_refresh_source_content_cb.call(source_id)
		SRC_MENU_DELETE:
			delete_selected_sources()

func _prepare_tree_context_menu(pm: PopupMenu, source_id: String) -> void:
	if not is_instance_valid(pm):
		return
	pm.clear()
	var source_name := source_id
	if _get_source_display_name_cb.is_valid():
		source_name = String(_get_source_display_name_cb.call(source_id)).strip_edges()
		if source_name.is_empty():
			source_name = source_id
	pm.add_item("Source: %s" % source_name, -1)
	pm.set_item_disabled(0, true)
	pm.add_separator()
	var all_selected := false
	var has_any := false
	if is_instance_valid(_hierarchy_view) and _hierarchy_view.has_method("get_all_visible_node_ids"):
		var node_ids: Array[String] = _hierarchy_view.get_all_visible_node_ids()
		has_any = not node_ids.is_empty()
		if _hierarchy_view.has_method("are_all_visible_nodes_selected"):
			all_selected = bool(_hierarchy_view.are_all_visible_nodes_selected())
	pm.add_check_item("Select All Nodes", TREE_MENU_SELECT_ALL_NODES_TOGGLE)
	var sel_idx := pm.get_item_count() - 1
	pm.set_item_checked(sel_idx, all_selected)
	pm.set_item_disabled(sel_idx, not has_any)
	pm.add_separator()
	pm.add_item("Edit Source…", TREE_MENU_EDIT)
	pm.add_item("Open in Context Graph", TREE_MENU_OPEN_GRAPH)
	pm.add_separator()
	pm.add_item("Copy Source ID", TREE_MENU_COPY_ID)
	pm.add_item("Copy Path", TREE_MENU_COPY_PATH)
	pm.add_item("Reveal on Disk", TREE_MENU_REVEAL_ON_DISK)
	pm.add_separator()
	pm.add_separator()
	pm.add_item("Refresh Content", TREE_MENU_REFRESH_CONTENT)
	pm.add_separator()
	pm.add_item("Save Hierarchy", TREE_MENU_SAVE_HIERARCHY)
	pm.add_item("Import Hierarchy", TREE_MENU_IMPORT_HIERARCHY)
	pm.add_separator()
	pm.add_item("Add Child", TREE_MENU_ADD_CHILD)
	pm.add_item("Delete Node", TREE_MENU_DELETE)
	pm.add_separator()
	pm.add_item("Move Up", TREE_MENU_MOVE_UP)
	pm.add_item("Move Down", TREE_MENU_MOVE_DOWN)
	pm.add_separator()
	pm.add_item("Delete Source…", TREE_MENU_DELETE_SOURCE)
	if not pm.id_pressed.is_connected(_on_tree_menu_id_pressed):
		pm.id_pressed.connect(_on_tree_menu_id_pressed)

func _on_tree_menu_id_pressed(id: int) -> void:
	if not is_instance_valid(_view_state) or not is_instance_valid(_content_state):
		return
	var source_id := _get_action_source_id()
	if source_id.is_empty():
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("No Source", "No current content source in hierarchy view.")
		return
	var sd: Dictionary = _content_state.get_source_data(source_id)
	var meta: Dictionary = sd.get("meta", {})
	match id:
		TREE_MENU_SELECT_ALL_NODES_TOGGLE:
			if _toggle_select_all_hierarchy_nodes_cb.is_valid():
				_toggle_select_all_hierarchy_nodes_cb.call()
		TREE_MENU_EDIT:
			if _open_edit_dialog_cb.is_valid():
				_open_edit_dialog_cb.call(source_id)
		TREE_MENU_OPEN_GRAPH:
			_view_state.change_view(2, source_id)
		TREE_MENU_COPY_ID:
			DisplayServer.clipboard_set(source_id)
		TREE_MENU_COPY_PATH:
			DisplayServer.clipboard_set(str(meta.get("path", "")))
		TREE_MENU_REVEAL_ON_DISK:
			reveal_source_on_disk(meta)
		TREE_MENU_REFRESH_CONTENT:
			if _refresh_source_content_cb.is_valid():
				_refresh_source_content_cb.call(source_id)
		TREE_MENU_SAVE_HIERARCHY:
			_content_state.save_source(source_id)
		TREE_MENU_IMPORT_HIERARCHY:
			import_hierarchy_from_disk(source_id)
		TREE_MENU_ADD_CHILD:
			begin_add_child(source_id)
		TREE_MENU_DELETE:
			if _request_delete_selected_node_cb.is_valid():
				_request_delete_selected_node_cb.call()
		TREE_MENU_MOVE_UP:
			move_selected(-1)
		TREE_MENU_MOVE_DOWN:
			move_selected(1)
		TREE_MENU_DELETE_SOURCE:
			delete_selected_sources()

func begin_change_content_dir() -> void:
	# Open a directory picker, then reload sources from the chosen directory.
	var dialog := FileDialog.new()
	dialog.title = "Select Content Sources Directory"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = false
	dialog.transient = true
	dialog.always_on_top = true
	dialog.exclusive = false

	var start_dir := ""
	if is_instance_valid(_content_dir_path_label):
		start_dir = str(_content_dir_path_label.text).strip_edges()
	if start_dir.is_empty():
		start_dir = DEFAULT_CONTENT_SOURCES_DIR
	if start_dir.begins_with("res://") or start_dir.begins_with("user://"):
		start_dir = ProjectSettings.globalize_path(start_dir)
	dialog.current_dir = start_dir

	dialog.dir_selected.connect(func(dir: String) -> void:
		_on_content_dir_selected(dir)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)

	get_tree().root.add_child(dialog)

	var win_size_i: Vector2i = DisplayServer.window_get_size()
	var win_pos: Vector2i = DisplayServer.window_get_position()
	var desired_size := Vector2i(900, 650)
	var max_w := max(480, win_size_i.x - 80)
	var max_h := max(300, win_size_i.y - 120)
	desired_size.x = min(desired_size.x, max_w)
	desired_size.y = min(desired_size.y, max_h)
	dialog.size = desired_size
	dialog.position = Vector2i(
		win_pos.x + int((win_size_i.x - desired_size.x) * 0.5),
		win_pos.y + int((win_size_i.y - desired_size.y) * 0.5)
	)
	dialog.popup()
	dialog.grab_focus()

func create_source_stack_from_active() -> void:
	if not is_instance_valid(_content_state):
		if _show_error_cb.is_valid():
			_show_error_cb.call("Stack Creation Failed", "Could not access content state resource.")
		return
	var active_sources: Array = []
	if _content_state.has_method("get_active_sources"):
		active_sources = _content_state.get_active_sources()
	if active_sources.is_empty():
		if _show_error_cb.is_valid():
			_show_error_cb.call("Stack Creation Failed", "No active sources found. Please activate some sources first.\nTo activate a source, click the 'Active' checkbox next to the source in the list view.")
		return
	var name_dialog := AcceptDialog.new()
	name_dialog.title = "Create Source Stack"
	var vbox := VBoxContainer.new()
	vbox.set_custom_minimum_size(Vector2(300, 150))
	var sources_label := Label.new()
	sources_label.text = "Including active sources:"
	vbox.add_child(sources_label)
	var sources_list_text := ""
	for source_id_any in active_sources:
		var source_id := String(source_id_any).strip_edges()
		if source_id.is_empty():
			continue
		var source_data: Dictionary = _content_state.get_source_data(source_id)
		var source_name := source_id
		if not source_data.is_empty():
			var meta: Dictionary = source_data.get("meta", {})
			source_name = str(meta.get("name", source_id))
		sources_list_text += "• %s\n" % source_name
	var scroll_container := ScrollContainer.new()
	scroll_container.custom_minimum_size.y = 300
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sources_list_label := Label.new()
	sources_list_label.text = sources_list_text
	sources_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sources_list_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(sources_list_label)
	vbox.add_child(scroll_container)
	vbox.add_child(HSeparator.new())
	var label := Label.new()
	label.text = "\nEnter a name for the source stack:"
	vbox.add_child(label)
	var name_input := LineEdit.new()
	name_input.placeholder_text = "My Source Stack"
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_input)
	name_dialog.add_child(vbox)
	add_child(name_dialog)
	name_dialog.confirmed.connect(func() -> void:
		var stack_name := name_input.text.strip_edges()
		call_deferred("_create_source_stack_async", stack_name, name_dialog)
	)
	name_dialog.canceled.connect(func() -> void:
		if is_instance_valid(name_dialog):
			name_dialog.queue_free()
	)
	name_dialog.popup_centered()
	name_input.call_deferred("grab_focus")

func _create_source_stack_async(stack_name: String, name_dialog: AcceptDialog) -> void:
	if not is_instance_valid(_plugin_manager) or not _plugin_manager.has_method("get_content_service"):
		if _show_error_cb.is_valid():
			_show_error_cb.call("Stack Creation Failed", "PluginManager not available.")
		if is_instance_valid(name_dialog):
			name_dialog.queue_free()
		return

	var content_service: Object = _plugin_manager.get_content_service()
	if not is_instance_valid(content_service) or not content_service.has_method("create_source_stack"):
		if _show_error_cb.is_valid():
			_show_error_cb.call("Stack Creation Failed", "ContentService not available or missing method.")
		if is_instance_valid(name_dialog):
			name_dialog.queue_free()
		return

	var result_any: Variant = await content_service.create_source_stack(stack_name)
	var d: Dictionary = (result_any as Dictionary) if result_any is Dictionary else {}
	if bool(d.get("success", false)):
		var created_name := ""
		var data_any: Variant = d.get("data", {})
		if data_any is Dictionary:
			created_name = str((data_any as Dictionary).get("meta", {}).get("name", "")).strip_edges()
		if is_instance_valid(_notification_manager) and _notification_manager.has_method("success"):
			var msg := "Successfully created source stack"
			if not created_name.is_empty():
				msg += ": " + created_name
			_notification_manager.success(msg)
		var warning := str(d.get("warning", "")).strip_edges()
		if not warning.is_empty():
			push_warning(warning)
	else:
		if _show_error_cb.is_valid():
			var err := str(d.get("error", "")).strip_edges()
			_show_error_cb.call("Stack Creation Failed", (err if not err.is_empty() else "Unknown error from ContentService"))

	if is_instance_valid(name_dialog):
		name_dialog.queue_free()

func _on_content_dir_selected(dir: String) -> void:
	var chosen := String(dir).strip_edges()
	if chosen.is_empty():
		return
	var localized := ProjectSettings.localize_path(chosen)
	if not localized.is_empty():
		chosen = localized
	if is_instance_valid(_content_dir_path_label):
		_content_dir_path_label.text = chosen

	# Persist into ContentSourceResource so future loads/saves use the chosen directory.
	if is_instance_valid(_content_state):
		var cs_any: Variant = _content_state.get("content_source")
		if is_instance_valid(cs_any) and (cs_any as Object).has_method("set"):
			(cs_any as Object).set("sources_directory", chosen)

	# Reload sources via service (best-effort).
	if is_instance_valid(_plugin_manager) and _plugin_manager.has_method("get_content_service"):
		var content_service = _plugin_manager.get_content_service()
		if is_instance_valid(content_service) and content_service.has_method("load_all_sources"):
			var result: Dictionary = await content_service.load_all_sources(chosen)
			if not bool(result.get("success", false)):
				if _show_error_cb.is_valid():
					_show_error_cb.call("Load Failed", "Failed to load sources from new directory: " + str(result.get("error", "Unknown error")))
		else:
			if _show_error_cb.is_valid():
				_show_error_cb.call("Service Error", "ContentService not available or missing load_all_sources().")

func import_hierarchy_from_disk(source_id: String) -> void:
	if not is_instance_valid(_content_state):
		return
	var sid := String(source_id).strip_edges()
	if sid.is_empty():
		return
	var base_dir := "res://addons/syntree/content_source_lists"
	if is_instance_valid(_content_state.content_source) and _content_state.content_source.has("sources_directory"):
		base_dir = str(_content_state.content_source.sources_directory)
	var json_path := base_dir.replace("\\", "/").path_join("%s.json" % sid)
	if not FileAccess.file_exists(json_path):
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Import Failed", "Metadata JSON not found:\n%s" % json_path)
		return
	var loaded := _content_state.load_source_from_file(json_path)
	if String(loaded).strip_edges().is_empty():
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Import Failed", "Failed to load:\n%s" % json_path)
		return

	# Migration helper: older sources may have no nodes. Initialize a default root node on import.
	var sd2: Dictionary = _content_state.get_source_data(sid)
	var content_any: Variant = sd2.get("content", {})
	if content_any is Dictionary:
		var nodes_any: Variant = (content_any as Dictionary).get("nodes", [])
		if nodes_any is Array and (nodes_any as Array).is_empty():
			(sd2["content"] as Dictionary)["nodes"] = [
				{
					"node_id": "%s_root" % sid,
					"title": "Root",
					"is_root": true,
					"position": {"x": 0, "y": 0},
					"content": "# %s" % str(sd2.get("meta", {}).get("name", sid)),
					"relationships": {"parents": [], "children": [], "dependencies": []},
				}
			]
			_content_state.update_source(sid, sd2)
			_content_state.save_source(sid)

	if _refresh_hierarchy_cb.is_valid():
		_refresh_hierarchy_cb.call()
	if is_instance_valid(_notification_manager) and _notification_manager.has_method("info"):
		_notification_manager.info("Imported from disk.", "Hierarchy")

func reveal_source_on_disk(meta: Dictionary) -> void:
	var p := str(meta.get("path", "")).strip_edges()
	if p.is_empty():
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("No Path", "This source has no local path to reveal.")
		return
	if p.begins_with("http://") or p.begins_with("https://"):
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Remote Source", "This source is remote (URL).")
		return
	p = p.replace("\\", "/")
	p = _globalize_path_for_os(p)
	var folder := p.get_base_dir()
	if folder.is_empty():
		folder = p
	OS.shell_open(folder)

func delete_selected_sources() -> void:
	if not is_instance_valid(_view_state):
		if _show_error_cb.is_valid():
			_show_error_cb.call("Delete Failed", "Cannot access view state to get selections.")
		return
	var selected_ids: Array = _view_state.selected_source_ids.duplicate()
	if selected_ids.is_empty():
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Nothing Selected", "No content sources are currently selected.")
		return

	var confirm_dialog := ConfirmationDialog.new()
	confirm_dialog.title = "Confirm Deletion"
	confirm_dialog.dialog_text = "Are you sure you want to delete the following %d selected source(s)?\n\n" % selected_ids.size()

	var list_text := ""
	var max_list := 5
	for i in min(selected_ids.size(), max_list):
		var sid := str(selected_ids[i])
		var list_bus := SynTreeAutoloads.content_bus()
		var source_data: Dictionary = list_bus.get_source_data(sid) if is_instance_valid(list_bus) else {}
		var name := sid
		if not source_data.is_empty() and source_data.has("meta") and source_data.meta.has("name"):
			name = source_data.meta.get("name")
		list_text += "• %s\n" % name
	if selected_ids.size() > max_list:
		list_text += "...and %d more." % (selected_ids.size() - max_list)

	confirm_dialog.dialog_text += list_text
	confirm_dialog.dialog_text += "\n\nThis action cannot be undone."

	confirm_dialog.confirmed.connect(func():
		for source_id_any in selected_ids:
			var sid := str(source_id_any)
			var delete_bus := SynTreeAutoloads.content_bus()
			if is_instance_valid(delete_bus) and delete_bus.has_method("request_source_deletion"):
				delete_bus.request_source_deletion(sid)

		# Update ViewStateResource AFTER deletion loop
		for source_id_any in selected_ids:
			_view_state.select_source(str(source_id_any), false)

		# Refresh list view
		if is_instance_valid(_content_list_view) and _content_list_view.has_method("refresh_sources"):
			_content_list_view.refresh_sources()

		if is_instance_valid(_notification_manager) and _notification_manager.has_method("success"):
			_notification_manager.success("%d source(s) deleted." % selected_ids.size(), "Deletion Complete")

		confirm_dialog.queue_free()
	)
	confirm_dialog.canceled.connect(func():
		confirm_dialog.queue_free()
	)
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()

func _globalize_path_for_os(p: String) -> String:
	var s := String(p).strip_edges()
	if s.is_empty():
		return ""
	if s.begins_with("res://") or s.begins_with("user://"):
		return ProjectSettings.globalize_path(s)
	return s

func _are_all_sources_selected(all_ids: Array[String]) -> bool:
	if not is_instance_valid(_view_state):
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
		if not _view_state.selected_source_ids.has(sid):
			return false
	return true

func _get_all_visible_graph_node_ids() -> Array[String]:
	var out: Array[String] = []
	if not is_instance_valid(_graph_edit):
		return out
	for child in _graph_edit.get_children():
		if child is GraphNode:
			var nid := String(child.name).strip_edges()
			if nid.is_empty():
				continue
			out.append(nid)
	return out

func _are_all_graph_nodes_selected(node_ids: Array[String]) -> bool:
	if node_ids.is_empty() or not is_instance_valid(_graph_edit):
		return false
	var set := {}
	for nid in node_ids:
		set[nid] = true
	for child in _graph_edit.get_children():
		if not (child is GraphNode):
			continue
		var gn := child as GraphNode
		if not set.has(gn.name):
			continue
		if not gn.selected:
			return false
	return true

func _raw_node_id(any_id: String) -> String:
	if _raw_node_id_cb.is_valid():
		return String(_raw_node_id_cb.call(any_id)).strip_edges()
	return String(any_id).strip_edges()

func _attach_linked_child_source(parent_node_id: String, parent_source_id: String, child_source_id: String, preferred_name: String = "", preferred_path: String = "") -> bool:
	if not is_instance_valid(_content_state):
		return false
	var pnode := String(parent_node_id).strip_edges()
	var psrc := String(parent_source_id).strip_edges()
	var csid := String(child_source_id).strip_edges()
	if pnode.is_empty() or psrc.is_empty() or csid.is_empty():
		return false
	var child_name := String(preferred_name).strip_edges()
	var child_path := String(preferred_path).strip_edges()
	if child_name.is_empty() or child_path.is_empty():
		var child_data: Dictionary = _content_state.get_source_data(csid)
		if child_data.is_empty():
			return false
		var child_meta: Dictionary = child_data.get("meta", {})
		if child_name.is_empty():
			child_name = str(child_meta.get("name", csid))
		if child_path.is_empty():
			child_path = str(child_meta.get("path", ""))

	var d: Dictionary = _content_state.get_source_data(psrc)
	if d.is_empty():
		return false
	if not (d.get("content", {}) is Dictionary):
		d["content"] = {}
	if not d.content.has("nodes") or not (d.content.nodes is Array):
		d.content["nodes"] = []

	var nodes: Array = d.content.nodes
	var existing := {}
	for n_any in nodes:
		if n_any is Dictionary:
			var nid := str((n_any as Dictionary).get("node_id", "")).strip_edges()
			if not nid.is_empty():
				existing[nid] = true

	var raw_parent := _raw_node_id(pnode)
	var base_id := "%s%s%s" % [raw_parent, _content_state.COMPOSED_NODE_SEP, csid]
	var link_node_id := base_id
	if existing.has(link_node_id):
		link_node_id = "%s_link" % base_id
	var suffix := 1
	while existing.has(link_node_id):
		link_node_id = "%s_link_%d" % [base_id, suffix]
		suffix += 1

	var link_node := {
		"node_id": link_node_id,
		"title": child_name,
		"content": "",
		"meta": {"linked_source_id": csid},
		"relationships": {"parents": [], "children": [], "dependencies": []},
		"position": {"x": 0, "y": 0},
	}
	if not child_path.is_empty():
		link_node["path"] = child_path
		(link_node.meta as Dictionary)["path"] = child_path
	(link_node.meta as Dictionary)["source_name"] = child_name
	nodes.append(link_node)
	d.content["nodes"] = nodes
	_content_state.register_node_source_relationship(link_node_id, psrc)
	if not _content_state.update_source(psrc, d):
		return false
	var from_comp := pnode
	if not from_comp.contains(_content_state.COMPOSED_NODE_SEP) and _content_state.has_method("make_composed_node_id"):
		from_comp = _content_state.make_composed_node_id(psrc, raw_parent)
	var to_comp := link_node_id
	if _content_state.has_method("make_composed_node_id"):
		to_comp = _content_state.make_composed_node_id(psrc, link_node_id)
	if _content_state.has_method("add_edge"):
		_content_state.add_edge("child", from_comp, to_comp)
	else:
		_content_state.add_relationship(from_comp, to_comp)
	_content_state.save_source(psrc)
	if _content_state.has_method("normalize_source_graph"):
		_content_state.normalize_source_graph(psrc)
	return true


