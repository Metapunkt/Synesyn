## Purpose: ContentHierarchyView (script)
@tool  # Still needed as part of editor plugin
extends VBoxContainer
class_name ContentHierarchyView

const DEBUG: bool = false

const ContentSourceItemScene = preload("res://addons/syntree/scenes/content_source_item.tscn")
const ContentSourceItem = preload("res://addons/syntree/scripts/ui/content_source_list/content_source_item.gd")

var _current_source_data: Dictionary
var _parent_source_id: String = ""  # Track the source that got us into hierarchy view
var _last_displayed_source_id: String = "" # Prevent re-entrant refresh loops

# Add debugging variables to detect recursion
var _hierarchy_display_calls := 0
var _max_hierarchy_calls := 10
var _is_processing_hierarchy := false

var _state_transitions := 0
var _max_state_transitions := 5

var _setup_calls := 0
var _max_setup_calls := 5

var _content_state: ContentStateResource = null
var _view_state: ViewStateResource = null
var _selected_node_ids: Array[String] = [] # composed ids when available (supports multi-select)
var _primary_selected_node_id: String = "" # the most recently selected node id (composed)

# Add guard flag for metaprompt processing
var _is_processing_metaprompt := false

# Add to existing signals
signal metaprompt_toggled(source_id: String, is_metaprompt: bool)

var _initialized := false
var _plugin_ref = null # Add plugin reference

# setup function called by SyntreePanel
func setup_hierarchy(state_resource: ContentStateResource, view_state: ViewStateResource = null, plugin_ref = null) -> void:
	if DEBUG:
		print("ContentHierarchyView: setup_hierarchy called")
	_plugin_ref = plugin_ref
	
	if not is_instance_valid(state_resource):
		push_error("ContentHierarchyView: Invalid ContentStateResource passed to setup_hierarchy.")
		return
	_content_state = state_resource
	_view_state = view_state

	# Wire to injected ViewStateResource instead of discovering ContentBus.
	if is_instance_valid(_view_state):
		# IMPORTANT: do NOT rebuild hierarchy on source selection changes.
		# In hierarchy view, selection is used for menus; displayed root is controlled by change_view/current_source_id.
		if _view_state.has_signal("view_state_changed") and not _view_state.view_state_changed.is_connected(_on_view_state_changed):
			_view_state.view_state_changed.connect(_on_view_state_changed)

	_initialized = true
	if DEBUG:
		print("ContentHierarchyView: Setup complete.")
func _on_hierarchy_requested(source_id: String) -> void:
	if not is_instance_valid(_content_state):
		return
	var source_data = _content_state.get_source_data(source_id)
	if source_data.is_empty():
		push_error("Failed to retrieve source data for ID: " + source_id)
		return
		
	display_hierarchy(source_data)
func display_hierarchy(source_data: Dictionary) -> void:
	if DEBUG:
		print("ContentHierarchyView: Displaying hierarchy")
	
	# --- Clear existing items first --- 
	clear()
	# --- End Clear --- 
	
	# NOTE (Godot 4.4 safety): this function can be invoked through deferred calls where the
	# argument may arrive as a non-Dictionary Variant. Guard before using Dictionary-only APIs.
	if typeof(source_data) != TYPE_DICTIONARY:
		push_error("ContentHierarchyView: Invalid source_data type for hierarchy display: %s" % typeof(source_data))
		return
	if source_data.is_empty():
		push_error("ContentHierarchyView: Empty source data for hierarchy display")
		return
	var content_any: Variant = source_data.get("content", null)
	if typeof(content_any) != TYPE_DICTIONARY:
		push_error("ContentHierarchyView: Missing/invalid content{} for hierarchy display")
		return
	var nodes_any: Variant = (content_any as Dictionary).get("nodes", null)
	if typeof(nodes_any) != TYPE_ARRAY:
		push_error("ContentHierarchyView: Missing/invalid content.nodes[] for hierarchy display")
		return

	if not _initialized:
		return
	if _is_processing_hierarchy:
		push_warning("Already processing hierarchy, deferring call.")
		call_deferred("display_hierarchy", source_data)
		return

	_is_processing_hierarchy = true
	_hierarchy_display_calls += 1

	if _hierarchy_display_calls > _max_hierarchy_calls:
		push_error("Too many hierarchy display calls - potential infinite recursion detected, aborting!")
		_is_processing_hierarchy = false
		_hierarchy_display_calls = 0
		return

	_current_source_data = source_data
	var _sid_for_guard := str(source_data.get("meta", {}).get("source_id", "")).strip_edges()
	if not _sid_for_guard.is_empty():
		_last_displayed_source_id = _sid_for_guard
		# Normalize graph invariants before rendering (parents rebuilt from children, stale refs removed).
		if is_instance_valid(_content_state) and _content_state.has_method("normalize_source_graph"):
			_content_state.normalize_source_graph(_sid_for_guard)
			# Refresh source_data after normalization (in case parents/children were repaired).
			source_data = _content_state.get_source_data(_sid_for_guard)
			_current_source_data = source_data
	
	if typeof(source_data) != TYPE_DICTIONARY or source_data.is_empty() or typeof(source_data.get("content", null)) != TYPE_DICTIONARY:
		push_error("Invalid source data for hierarchy display")
		_is_processing_hierarchy = false
		_hierarchy_display_calls -= 1
		return
	
	# Get source name from metadata
	var source_name = source_data.get("meta", {}).get("name", "Unnamed Source")

	# Stack expansion: if this source is a stack, show each member source “opened out”.
	if is_instance_valid(_content_state) and _content_state.has_method("is_stack_source") and _content_state.is_stack_source(source_data.get("meta", {}).get("source_id", "")):
		var stack_id := str(source_data.get("meta", {}).get("source_id", "")).strip_edges()
		_display_stack_hierarchy(stack_id, source_data, source_name)
		_is_processing_hierarchy = false
		_hierarchy_display_calls = 0
		return
	
	var content: Dictionary = source_data.get("content", {})
	if not content.has("nodes") or content.nodes.is_empty():
		push_error("No nodes found in content data")
		_is_processing_hierarchy = false
		_hierarchy_display_calls -= 1
		return
		
	# First pass: collect all valid node IDs
	var valid_node_ids = []
	for node in content.nodes:
		if node.has("node_id"):
			valid_node_ids.append(node.node_id)
		else:
			push_warning("Found node without node_id in source data")
	
	# Create root items first
	var found_roots = false
	
	# Safety check for valid nodes array
	if valid_node_ids.is_empty():
		push_error("No valid nodes with node_id found")
		_create_error_display("No Valid Nodes", "The source contains no nodes with valid node_id fields")
		_is_processing_hierarchy = false
		_hierarchy_display_calls -= 1
		return
	
	# Track visited nodes to prevent infinite recursion with circular relationships
	var visited_nodes = {}
	
	for node in content.nodes:
		# Skip nodes without node_id
		if not node.has("node_id"):
			continue
			
		# A node is a root if:
		# 1. It's explicitly marked as root, OR
		# 2. It has no parents or all its parents are invalid
		var parents = node.get("relationships", {}).get("parents", [])
		var has_valid_parent = false
		for parent_id in parents:
			if parent_id in valid_node_ids:
				has_valid_parent = true
				break
				
		var is_root = node.get("is_root", false) or not has_valid_parent
		
		if is_root:
			# Start processing this root node
			visited_nodes.clear()  # Reset for each root
			_create_hierarchy_item(node, 0, source_data.meta.path, source_name, visited_nodes)
			found_roots = true
	
	if not found_roots:
		push_error("No root nodes found in content")
		_create_error_display("No Root Nodes", "The source contains no root nodes. Add 'is_root: true' to at least one node.")
	
	# CRITICAL: Force a refresh of all items' states from the content state resource
	# This ensures that each item shows the correct state after hierarchy is built
	call_deferred("_refresh_all_item_states_from_resource")
	
	_is_processing_hierarchy = false
	_hierarchy_display_calls -= 1

# Helper function to create and display error messages
func _create_error_display(title: String, message: String) -> void:
	# Main container with padding and styling
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)
	
	# Error title
	var title_label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	vbox.add_child(title_label)
	
	# Error message
	var msg_label = Label.new()
	msg_label.text = message
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(msg_label)
	
	# Back button
	var back_button = Button.new()
	back_button.text = "Back to List View"
	back_button.pressed.connect(_on_back_to_list_pressed)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(back_button)

func _create_hierarchy_item(node: Dictionary, indent_level: int, source_path: String, source_name: String = "", visited_nodes: Dictionary = {}) -> void:
	# Prevent infinite recursion with circular relationships
	var node_id: String = str(node.get("node_id", "")).strip_edges()
	if node_id.is_empty():
		push_warning("ContentHierarchyView: Attempted to create hierarchy item with empty node_id")
		return
	
	if visited_nodes.has(node_id):
		push_warning("ContentHierarchyView: Circular relationship detected for node: " + node_id)
		return
	
	# Mark this node as visited during this branch of recursion
	visited_nodes[node_id] = true
	
	# Get source ID for this node
	var source_id: String = ""
	# Prefer the currently displayed source's ID (stack member / normal source),
	# because node_id is not globally unique across sources.
	if _current_source_data and _current_source_data.has("meta"):
		source_id = str(_current_source_data.get("meta", {}).get("source_id", "")).strip_edges()
	if source_id.is_empty() and is_instance_valid(_content_state):
		source_id = _content_state.get_source_for_node(node_id)
	
	if source_id.is_empty():
		push_warning("ContentHierarchyView: Could not determine source for node: " + node_id)
		return

	# If this node is a "linked child source" placeholder, render/toggle as the linked source.
	var node_meta: Dictionary = node.get("meta", {})
	var linked_source_id := str(node_meta.get("linked_source_id", "")).strip_edges()
	var item_source_id := source_id
	if not linked_source_id.is_empty() and is_instance_valid(_content_state) and _content_state.has_method("has_source") and bool(_content_state.has_source(linked_source_id)):
		item_source_id = linked_source_id
	
	# Get states directly from content state (for the item source id)
	var source_data = _content_state.get_source_data(item_source_id)
	var is_metaprompt = source_data.get("meta", {}).get("ai_context", {}).get("metaprompt", false)
	var is_active = source_data.get("meta", {}).get("ai_context", {}).get("is_active", false)
	
	if DEBUG:
		print("ContentHierarchyView: Creating item for node %s (source: %s) with states: metaprompt=%s, active=%s" % 
			[node_id, source_id, str(is_metaprompt), str(is_active)])
	
	# Create the item
	var item = ContentSourceItemScene.instantiate()
	
	# Determine the best name to display:
	# 1. If node has a title or content, use extracted node title
	var node_title = _get_node_title(node)
	
	# 2. If this is a linked source, use the linked source's name from metadata
	if source_data.has("meta") and source_data.meta.has("name"):
		node_title = source_data.meta.get("name")
	
	# Set up the item with hierarchy mode
	var node_path: String = str(node.get("path", source_path))
	
	# Inject resources BEFORE setup so ContentSourceItem can fetch/persist states correctly.
	if item.has_method("set_resources"):
		item.set_resources(_content_state, _view_state)

	# Setup the item with source ID, NODE TITLE (not source name), path
	var effective_path: String = String(node_path)
	if not linked_source_id.is_empty():
		# Prefer the node's stored path (set from Create dialog) if present;
		# otherwise fall back to linked source meta.path.
		if effective_path.is_empty():
			var lm: Dictionary = source_data.get("meta", {})
			var lp := str(lm.get("path", "")).strip_edges()
			if not lp.is_empty():
				effective_path = String(lp)
	item.setup(item_source_id, node_title, effective_path)

	# In hierarchy mode, we also want clicks to select the underlying node for context-menu actions.
	# Use composed ids (source__node) to avoid ambiguity across sources that share node ids like "root".
	var composed_id: String = node_id
	if is_instance_valid(_content_state) and _content_state.has_method("make_composed_node_id") and not source_id.is_empty():
		composed_id = str(_content_state.make_composed_node_id(source_id, node_id))
	item.set_meta("syntree_node_id", composed_id)
	# Make row clicks reliable: connect gui_input on the root item AND all non-interactive descendants.
	_wire_click_selection(item, composed_id)

	# IMPORTANT: in hierarchy view, the "select" checkbox should select the SOURCE (so SourceMenu works),
	# IMPORTANT: In hierarchy view, this checkbox must mean "selected NODE" (single selection),
	# otherwise selecting a child will make all siblings appear selected (they share the same source_id).
	if item.select_check:
		item.select_check.set_block_signals(true)
		item.select_check.button_pressed = false
		item.select_check.set_block_signals(false)
	if item.has_signal("select_toggled"):
		if not item.select_toggled.is_connected(_on_node_checkbox_toggled.bind(composed_id)):
			item.select_toggled.connect(_on_node_checkbox_toggled.bind(composed_id))
	
	# Set hierarchy mode
	item.set_hierarchy_mode(true)
	
	# Set indent level
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", indent_level * 20)
	# Add item to margin FIRST
	margin.add_child(item) 
	# IMPORTANT: do NOT intercept mouse events at the row wrapper level.
	# `MOUSE_FILTER_STOP` here makes checkboxes/buttons feel "unselectable" by swallowing clicks.
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# THEN add margin to self (ContentHierarchyView)
	add_child(margin)
	
	# Connect state change signals
	if not item.metaprompt_toggled.is_connected(_on_item_metaprompt_toggled):
		item.metaprompt_toggled.connect(_on_item_metaprompt_toggled)
	if not item.active_source_toggled.is_connected(_on_item_active_toggled):
		item.active_source_toggled.connect(_on_item_active_toggled)

	# Connect navigation intent: GraphView button -> ViewStateResource.change_view(GRAPH, source_id)
	if is_instance_valid(_view_state) and item.has_signal("view_requested"):
		if not item.view_requested.is_connected(_view_state.change_view):
			item.view_requested.connect(_view_state.change_view)

	# Connect delete: in hierarchy view delete button deletes ONLY this node (not the source).
	if item.has_signal("delete_requested"):
		if not item.delete_requested.is_connected(_on_node_delete_requested.bind(composed_id)):
			item.delete_requested.connect(_on_node_delete_requested.bind(composed_id))
	
	# Process child nodes
	var children = node.get("relationships", {}).get("children", [])
	for child_id in children:
		# Find child node in current source data
		for child_node in _current_source_data.content.nodes:
			if child_node.has("node_id") and child_node.node_id == child_id:
				_create_hierarchy_item(child_node, indent_level + 1, source_path, source_name, visited_nodes.duplicate())
				break

func _on_node_delete_requested(_source_id: String, node_id: String) -> void:
	# In hierarchy view, the delete button is node-scoped.
	var nid := String(node_id).strip_edges()
	if nid.is_empty():
		return
	if not is_instance_valid(_content_state):
		return

	var parsed: Dictionary = {}
	if _content_state.has_method("parse_composed_node_id"):
		parsed = _content_state.parse_composed_node_id(nid)
	var src := ""
	var raw := nid
	if bool(parsed.get("is_composed", false)):
		src = str(parsed.get("source_id", "")).strip_edges()
		raw = str(parsed.get("node_id", "")).strip_edges()
	if src.is_empty() and _content_state.has_method("get_source_for_node"):
		src = str(_content_state.get_source_for_node(nid)).strip_edges()

	if src.is_empty() or raw.is_empty():
		push_warning("ContentHierarchyView: Cannot resolve source/raw node id for deletion: %s" % nid)
		return

	var confirm_dialog := ConfirmationDialog.new()
	confirm_dialog.title = "Confirm Node Deletion"
	confirm_dialog.ok_button_text = "Delete"
	confirm_dialog.cancel_button_text = "Cancel"
	confirm_dialog.dialog_text = "Delete this node?\n\nNode: %s\nSource: %s\n\nThis cannot be undone." % [raw, src]
	confirm_dialog.confirmed.connect(func() -> void:
		_delete_node_by_id(nid)
		confirm_dialog.queue_free()
	)
	confirm_dialog.canceled.connect(func() -> void:
		confirm_dialog.queue_free()
	)
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()

func _delete_node_by_id(node_id: String) -> void:
	var nid := String(node_id).strip_edges()
	if nid.is_empty():
		return
	if not is_instance_valid(_content_state):
		return

	var parsed: Dictionary = {}
	if _content_state.has_method("parse_composed_node_id"):
		parsed = _content_state.parse_composed_node_id(nid)
	var src := ""
	var raw := nid
	if bool(parsed.get("is_composed", false)):
		src = str(parsed.get("source_id", "")).strip_edges()
		raw = str(parsed.get("node_id", "")).strip_edges()
	if src.is_empty() and _content_state.has_method("get_source_for_node"):
		src = str(_content_state.get_source_for_node(nid)).strip_edges()
	if src.is_empty() or raw.is_empty():
		return

	if (
		not _content_state.has_method("remove_node_from_source")
		or not bool(_content_state.remove_node_from_source(src, raw))
	):
		return

	# Update local selection state (remove deleted node if selected)
	_selected_node_ids.erase(nid)
	if _primary_selected_node_id == nid:
		_primary_selected_node_id = ""
	_update_node_checkbox_states()

	# Refresh current hierarchy view from source-of-truth
	if not _last_displayed_source_id.is_empty():
		call_deferred("display_hierarchy", _content_state.get_source_data(_last_displayed_source_id))

func _on_hierarchy_item_gui_input(event: InputEvent, item: Control) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not is_instance_valid(_content_state):
		return
	var node_id := str(item.get_meta("syntree_node_id", "")).strip_edges()
	if node_id.is_empty():
		return
	_select_node(node_id, mb.ctrl_pressed)

func _on_node_checkbox_toggled(_source_id: String, selected: bool, node_id: String) -> void:
	# Source_id is ignored here; checkbox is node-scoped.
	var nid := String(node_id).strip_edges()
	if nid.is_empty():
		return
	if selected:
		_select_node(nid, true)
	else:
		_selected_node_ids.erase(nid)
		_update_node_checkbox_states()

func _select_node(node_id: String, additive: bool = false) -> void:
	if DEBUG:
		print("[SELECT] ContentHierarchyView._select_node called with: '%s'" % node_id)
	if not is_instance_valid(_content_state):
		if DEBUG:
			print("[SELECT] _content_state not valid, returning")
		return
	var nid := String(node_id).strip_edges()
	if nid.is_empty():
		if DEBUG:
			print("[SELECT] node_id empty after strip, returning")
		return
	if not additive:
		_selected_node_ids.clear()
	if not _selected_node_ids.has(nid):
		_selected_node_ids.append(nid)
	_primary_selected_node_id = nid
	if DEBUG:
		print("[SELECT] Set _primary_selected_node_id = '%s'" % _primary_selected_node_id)
	# Emit selection for the most recently clicked node (used by menus/actions).
	if DEBUG:
		print("[SELECT] Calling _content_state.select_node('%s')" % nid)
	_content_state.select_node(nid)
	_update_node_checkbox_states()

func get_primary_selected_node_id() -> String:
	# Used by SyntreePanel as a robust fallback for menu actions.
	return String(_primary_selected_node_id).strip_edges()

func get_selected_node_ids() -> Array[String]:
	return _selected_node_ids.duplicate()

func get_all_visible_node_ids() -> Array[String]:
	# Returns composed node ids (source__node) stored on each hierarchy row via meta `syntree_node_id`.
	var out: Array[String] = []
	for child in get_children():
		var item: ContentSourceItem = null
		if child is MarginContainer and child.get_child_count() > 0 and child.get_child(0) is ContentSourceItem:
			item = child.get_child(0) as ContentSourceItem
		elif child is ContentSourceItem:
			item = child as ContentSourceItem
		if item == null:
			continue
		var nid := str(item.get_meta("syntree_node_id", "")).strip_edges()
		if nid.is_empty():
			continue
		out.append(nid)
	return out

func are_all_visible_nodes_selected() -> bool:
	var all_ids := get_all_visible_node_ids()
	if all_ids.is_empty():
		return false
	for nid in all_ids:
		if not _selected_node_ids.has(nid):
			return false
	return true

func set_all_visible_nodes_selected(selected: bool) -> void:
	var all_ids := get_all_visible_node_ids()
	if selected:
		_selected_node_ids = all_ids.duplicate()
		_primary_selected_node_id = _selected_node_ids[-1] if not _selected_node_ids.is_empty() else ""
		# Update action context to something stable (used by SourceMenu node actions).
		if not _primary_selected_node_id.is_empty() and is_instance_valid(_content_state):
			_content_state.select_node(_primary_selected_node_id)
	else:
		_selected_node_ids.clear()
		_primary_selected_node_id = ""
	_update_node_checkbox_states()

func _update_node_checkbox_states() -> void:
	# Ensure checkboxes reflect multi-select state.
	for child in get_children():
		var item: ContentSourceItem = null
		if child is MarginContainer and child.get_child_count() > 0 and child.get_child(0) is ContentSourceItem:
			item = child.get_child(0) as ContentSourceItem
		elif child is ContentSourceItem:
			item = child as ContentSourceItem
		if item == null or not is_instance_valid(item.select_check):
			continue
		var nid := str(item.get_meta("syntree_node_id", "")).strip_edges()
		var should := _selected_node_ids.has(nid)
		item.select_check.set_block_signals(true)
		item.select_check.button_pressed = should
		item.select_check.set_block_signals(false)

func _wire_click_selection(root: Control, node_id: String) -> void:
	# Clicking on labels/containers should select; interactive widgets (checkbox/buttons) keep their behavior.
	if not is_instance_valid(root):
		return
	if not root.gui_input.is_connected(_on_hierarchy_item_gui_input.bind(root)):
		root.gui_input.connect(_on_hierarchy_item_gui_input.bind(root))
	_wire_click_selection_children(root)

func _wire_click_selection_children(n: Node) -> void:
	for c in n.get_children():
		if c is Button or c is CheckBox:
			continue
		if c is Control:
			var ctrl := c as Control
			ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
		_wire_click_selection_children(c)

func _get_node_title(node: Dictionary) -> String:
	# First try to use the explicitly defined title field
	if node.has("title") and not node.get("title").is_empty():
		return node.get("title")
		
	# Then try to parse content - handles two different formats:
	# 1. If content is directly a string
	var content_text = ""
	if node.has("content") and node.get("content") is String:
		content_text = node.get("content")
	# 2. If content is in the standard format structure (content.content)
	elif node.has("content") and node.get("content") is Dictionary and node.get("content").has("content"):
		content_text = node.get("content").get("content")
		
	# Extract title from first line if we have content text
	if not content_text.is_empty():
		var lines = content_text.split("\n")
		if not lines.is_empty():
			# Handle common markdown title patterns
			var line = lines[0].strip_edges()
			if line.begins_with("#"):
				return line.replace("#", "").strip_edges()
			# Handle triple quoted strings common in code files
			elif line.begins_with("\"\"\"") and lines.size() > 1:
				return lines[1].strip_edges()
			else:
				return line

	# Use node ID as fallback
	if node.has("node_id"):
		return node.get("node_id").replace("_", " ").capitalize()
		
	# Last resort fallback
	return "Untitled Node"

func _display_stack_hierarchy(stack_id: String, stack_data: Dictionary, stack_name: String) -> void:
	# Render a grouped-by-source hierarchy for each member source.
	# This is “stack-root-only” orchestration: we do not mutate member sources in stack mode.
	if not is_instance_valid(_content_state):
		return

	var header := Label.new()
	var uw := 0
	var include_unwired := true
	if is_instance_valid(_content_state):
		if _content_state.has_method("get_stack_unwired_member_count"):
			uw = int(_content_state.get_stack_unwired_member_count(stack_id))
		if _content_state.has_method("get_stack_include_unwired_nodes"):
			include_unwired = bool(_content_state.get_stack_include_unwired_nodes(stack_id))
	var suffix := ""
	if uw > 0:
		suffix = " (Unwired: %d)" % uw
	header.text = "STACK: %s%s — Include unwired: %s" % [stack_name, suffix, "on" if include_unwired else "off"]
	header.add_theme_font_size_override("font_size", 16)
	add_child(header)

	# Include member sources in declared order.
	var members: Array[String] = []
	if _content_state.has_method("get_stack_member_source_ids"):
		members = _content_state.get_stack_member_source_ids(stack_id)

	for member_id in members:
		# Normalize each member before projecting to hierarchy.
		if is_instance_valid(_content_state) and _content_state.has_method("normalize_source_graph"):
			_content_state.normalize_source_graph(member_id)
		var member_data: Dictionary = _content_state.get_source_data(member_id)
		if member_data.is_empty():
			continue

		var member_name: String = str(member_data.get("meta", {}).get("name", member_id))
		var member_path: String = str(member_data.get("meta", {}).get("path", ""))

		var sub := Label.new()
		sub.text = "— %s" % member_name
		sub.add_theme_font_size_override("font_size", 14)
		add_child(sub)

		# Reuse existing tree builder by temporarily setting _current_source_data.
		_current_source_data = member_data

		var content = member_data.get("content", {})
		if not (content is Dictionary) or not content.has("nodes") or not (content.nodes is Array):
			continue

		# Collect valid ids for root detection.
		var valid_node_ids: Array = []
		for n in content.nodes:
			if n is Dictionary and n.has("node_id"):
				valid_node_ids.append(n.node_id)

		if valid_node_ids.is_empty():
			_create_error_display("No Nodes", "Member source '%s' has no nodes yet.\n\nTip: Create/Edit sources now include a default root node. For older sources, use 'Import Hierarchy' (or edit the source) to initialize a root." % member_name)
			continue

		var visited_nodes := {}
		var found_roots := false
		for n in content.nodes:
			if not (n is Dictionary) or not n.has("node_id"):
				continue
			var parents = n.get("relationships", {}).get("parents", [])
			var has_valid_parent := false
			for pid in parents:
				if pid in valid_node_ids:
					has_valid_parent = true
					break
			var is_root := bool(n.get("is_root", false)) or not has_valid_parent
			if not is_root:
				continue
			visited_nodes.clear()
			_create_hierarchy_item(n, 1, member_path, member_name, visited_nodes)
			found_roots = true

		if not found_roots:
			_create_error_display("No Root Nodes", "Member source '%s' contains no root nodes.\nTip: mark one node with 'is_root: true' or remove invalid parent links." % member_name)

func _find_node_by_id(node_id: String, nodes: Array) -> Dictionary:
	for node in nodes:
		if node.node_id == node_id:
			return node
	return {}

func clear() -> void:
	for child in get_children():
		child.queue_free()

func _on_view_state_changed() -> void:
	if not is_instance_valid(_view_state):
		return

	# Node selection UI is managed locally; do not sync checkboxes to source selection.

	var mode := int(_view_state.current_mode)
	if mode != 1: # ViewStateResource.ViewMode.HIERARCHY
		visible = false
		clear()
		return

	visible = true
	var source_id := String(_view_state.current_source_id)
	if source_id.is_empty():
		_create_error_display("Invalid Source",
			"Cannot display hierarchy: No source ID provided. Please select a content source.")
		return

	# Guard: if already displaying this source, don't clear/rebuild on redundant signals.
	if source_id == _last_displayed_source_id and get_child_count() > 0:
		_parent_source_id = source_id
		return

	_parent_source_id = source_id

	# Use a timer to defer view updates, breaking recursion
	var timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.05
	timer.timeout.connect(func():
		if visible and source_id == _parent_source_id and is_instance_valid(_content_state):
			var source_data = _content_state.get_source_data(source_id)
			if not source_data.is_empty():
				display_hierarchy(source_data)
		timer.queue_free()
	)
	add_child(timer)
	timer.start()

## selection checkboxes in hierarchy are node-scoped; see _update_node_checkbox_states()

# Modify how the hierarchy handles back button
func _on_back_to_list_pressed() -> void:
	visible = false
	clear()
	if is_instance_valid(_view_state):
		_view_state.change_view(0, "") # ViewStateResource.ViewMode.LIST

# Add a new function to refresh metaprompt states
func _refresh_metaprompt_states() -> void:
	# Skip if we're already processing metaprompt changes
	if _is_processing_metaprompt:
		return
		
	_is_processing_metaprompt = true
	if DEBUG:
		print("ContentHierarchyView: Refreshing metaprompt states from content state")
	if not is_instance_valid(_content_state):
		_is_processing_metaprompt = false
		return
	
	# Iterate through all child items
	for child in get_children():
		if child is ContentSourceItem and child._source_id:
			var source_id = child._source_id
			var normalized_source = _content_state.get_normalized_id(source_id)
			var is_metaprompt = false
			
			# Get source data - try direct match first
			var source_data = _content_state.get_source_data(normalized_source)
			if not source_data.is_empty():
				is_metaprompt = source_data.get("meta", {}).get("ai_context", {}).get("metaprompt", false)
				if DEBUG:
					print("ContentHierarchyView: Refreshed state for %s: %s" % [normalized_source, str(is_metaprompt)])
			else:
				# Try parent source if this is a node
				var parent_id = _content_state.get_source_for_node(source_id)
				if not parent_id.is_empty():
					var normalized_parent = _content_state.get_normalized_id(parent_id)
					source_data = _content_state.get_source_data(normalized_parent)
					if not source_data.is_empty():
						is_metaprompt = source_data.get("meta", {}).get("ai_context", {}).get("metaprompt", false)
						if DEBUG:
							print("ContentHierarchyView: Using parent %s state for %s: %s" % 
								[normalized_parent, source_id, str(is_metaprompt)])
						
			# Update the item's metaprompt state
			if child.metaprompt_check:
				child.metaprompt_check.button_pressed = is_metaprompt
				
	_is_processing_metaprompt = false

func clear_all_selections() -> void:
	# Clear selections for all hierarchy items
	for child in get_children():
		if child is ContentSourceItem and child.select_check:
			# Prevent feedback loop: programmatic toggle -> select_toggled -> ViewStateResource -> re-entry
			child.select_check.set_block_signals(true)
			child.select_check.button_pressed = false
			child.select_check.set_block_signals(false)
	
	# Don't clear _parent_source_id here; it retains the source that got us into hierarchy view

func _on_item_graph_requested(source_id: String) -> void:
	if is_instance_valid(_view_state):
		_view_state.change_view(2, source_id) # ViewStateResource.ViewMode.GRAPH

func _on_graph_view_requested(node_id: String) -> void:
	if is_instance_valid(_view_state):
		# IMPORTANT: Keep view_state.current_source_id as a SOURCE id, not an arbitrary node id.
		# Some nodes are not mapped in node_to_source_map which causes hierarchy to clear on view switching.
		var sid := node_id
		if is_instance_valid(_content_state):
			var resolved := _content_state.get_source_for_node(node_id)
			if not resolved.is_empty():
				sid = resolved
		_view_state.change_view(2, sid) # ViewStateResource.ViewMode.GRAPH

func display_hierarchy_with_id(source_id: String) -> void:
	if _is_processing_hierarchy:
		push_warning("Already processing hierarchy, deferring nested call.")
		call_deferred("display_hierarchy_with_id", source_id)
		return

	_is_processing_hierarchy = true
	_hierarchy_display_calls += 1

	if _hierarchy_display_calls > _max_hierarchy_calls:
		push_error("Too many hierarchy display calls - potential infinite recursion detected, aborting!")
		_is_processing_hierarchy = false
		_hierarchy_display_calls = 0
		return

	call_deferred("_display_hierarchy_with_id_internal", source_id)

func _display_hierarchy_with_id_internal(source_id: String) -> void:
	if DEBUG:
		print("ContentHierarchyView: Attempting to display hierarchy for ID: " + source_id)

	if source_id.is_empty():
		push_error("ContentHierarchyView: Cannot display hierarchy for empty source ID")
		clear()
		_create_error_display("Empty Source ID", "Cannot display hierarchy with an empty ID")
		_is_processing_hierarchy = false
		_hierarchy_display_calls = 0
		return

	var actual_source_id = _get_source_id(source_id)
	var source_data = _content_state.get_source_data(actual_source_id) if is_instance_valid(_content_state) else {}

	if source_data.is_empty():
		push_error("ContentHierarchyView: Failed to retrieve source data for ID: " + actual_source_id)
		clear()
		_create_error_display("Source Data Not Found", "Failed to retrieve source data for ID: " + actual_source_id)
		_is_processing_hierarchy = false
		_hierarchy_display_calls = 0
		return

	display_hierarchy(source_data)

	_is_processing_hierarchy = false
	_hierarchy_display_calls = 0

func get_parent_source_id() -> String:
	return _parent_source_id

func _get_source_id(source_id: String) -> String:
	# Uses _content_state.get_normalized_id and potentially .node_to_source_map
	# Access the map via _content_state.content_source.node_to_source_map if needed
	if not is_instance_valid(_content_state):
		push_error("ContentHierarchyView: Cannot get source ID, ContentStateResource invalid.")
		return source_id # Return original if state is missing
		
	var actual_source_id = source_id
	if _content_state.has_method("get_normalized_id"):
		actual_source_id = _content_state.get_normalized_id(source_id)
	
	# Check the map within the nested resource
	if is_instance_valid(_content_state.content_source) and _content_state.content_source.node_to_source_map.has(source_id):
		actual_source_id = _content_state.content_source.node_to_source_map[source_id]
		
	return actual_source_id

func _on_item_metaprompt_toggled(source_id: String, is_metaprompt: bool) -> void:
	if not is_instance_valid(_content_state):
		push_error("ContentHierarchyView: Cannot handle metaprompt toggle - no content state")
		return
	
	# Set state in content state
	var success = _content_state.set_metaprompt_state(source_id, is_metaprompt)
	if not success:
		push_error("ContentHierarchyView: Failed to set metaprompt state for %s" % source_id)
		return
	
	# Also update parent source if this is a node
	var parent_source_id = _content_state.get_source_for_node(source_id)
	if not parent_source_id.is_empty() and parent_source_id != source_id:
		_content_state.set_metaprompt_state(parent_source_id, is_metaprompt)

func _on_item_active_toggled(source_id: String, is_active: bool) -> void:
	if not is_instance_valid(_content_state):
		push_error("ContentHierarchyView: Cannot handle active toggle - no content state")
		return
	
	# Set state in content state
	var success = _content_state.set_source_active_state(source_id, is_active)
	if not success:
		push_error("ContentHierarchyView: Failed to set active state for %s" % source_id)
		return
	
	# Also update parent source if this is a node
	var parent_source_id = _content_state.get_source_for_node(source_id)
	if not parent_source_id.is_empty() and parent_source_id != source_id:
		_content_state.set_source_active_state(parent_source_id, is_active)

# New function to refresh all item states from the resource after hierarchy is built
func _refresh_all_item_states_from_resource() -> void:
	if not is_instance_valid(_content_state):
		push_error("ContentHierarchyView: Cannot refresh states - content state is invalid")
		return
		
	# Process all child items (and those within margins)
	for child in get_children():
		if child is MarginContainer and child.get_child_count() > 0:
			var item = child.get_child(0)
			if item is ContentSourceItem and item._source_id and item._initialized:
				_refresh_item_state(item)
		elif child is ContentSourceItem and child._source_id and child._initialized:
			_refresh_item_state(child)

# Helper to refresh a single item's state
func _refresh_item_state(item: ContentSourceItem) -> void:
	var source_id = item._source_id
	if source_id.is_empty():
		return
		
	# Fetch current states directly from the resource
	var current_active = _content_state.get_source_active_state(source_id)
	var current_metaprompt = _content_state.get_metaprompt_state(source_id)
	# Update the checkboxes directly with block signals
	if item.metaprompt_check:
		item.metaprompt_check.set_block_signals(true)
		item.metaprompt_check.button_pressed = current_metaprompt
		item.metaprompt_check.set_block_signals(false)
		
	if item.active_source_check:
		item.active_source_check.set_block_signals(true)
		item.active_source_check.button_pressed = current_active
		item.active_source_check.set_block_signals(false)
	
	# Refresh the node title if this is a node in the hierarchy
	if _current_source_data and _current_source_data.has("content") and _current_source_data.content.has("nodes"):
		var nodes = _current_source_data.content.nodes
		var matching_node = null
		
		# Try to find node with a matching node_id or source_id
		for node in nodes:
			# Direct node_id match
			if node.has("node_id") and node.node_id == source_id:
				matching_node = node
				break
		
		# If we found a matching node, update the title
		if matching_node:
			var node_title = _get_node_title(matching_node)
			if item.name_label and node_title != item.name_label.text:
				item.name_label.text = node_title
				if DEBUG:
					print("ContentHierarchyView: Updated title for node %s to: %s" % [source_id, node_title])
		else:
			# If no matching node, look at the source itself for a name
			var source_data = _content_state.get_source_data(source_id)
			if not source_data.is_empty() and source_data.has("meta") and source_data.meta.has("name"):
				var source_name = source_data.meta.get("name")
				if item.name_label and source_name != item.name_label.text:
					item.name_label.text = source_name
					if DEBUG:
						print("ContentHierarchyView: Updated title for source %s to: %s" % [source_id, source_name])
