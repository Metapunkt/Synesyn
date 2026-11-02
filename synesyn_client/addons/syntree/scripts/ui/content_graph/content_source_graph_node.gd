## Purpose: Visual representation of content nodes in graph view
"""
COMPONENT: ContentSourceGraphNode
RESPONSIBILITY: Visual representation of content nodes in graph view

PUBLIC API:
  - node_id: String - Unique identifier for the node
  - node_data: Dictionary - Complete data for the node
  - node_content: String - Content text of the node
  - path: String - File path associated with the node
  - update_ui_from_data(): Updates all UI elements based on node_data
  - initialize_slots(): Configures connection slots based on relationships

CONNECTION WORKFLOW:
  1. Set basic properties (node_id, node_data, node_content, path)
  2. Add node to scene tree (must be in tree before UI update)
  3. Call update_ui_from_data() to refresh UI and initialize slots
  4. Create connections between nodes using GraphEdit.connect_node()
  5. Use slot index 0 for all connections

DEPENDENCIES:
  - GraphNode: Inherits from Godot's GraphNode
  - ContentGraphController: For graph operations
"""
@tool
class_name ContentSourceGraphNode
extends GraphNode

const DEBUG: bool = false

# Only keep the metaprompt signal
signal metaprompt_toggled(node_id: String, is_metaprompt: bool)
signal active_source_toggled(node_id: String, is_active: bool)
signal delete_requested(node_id: String)

# Node references
@onready var name_label: Label = %NameLabel
@onready var id_label: Label = %IDLabel
@onready var provenance_badge: Label = %ProvenanceBadge
@onready var state_badge: Label = %StateBadge
@onready var is_meta_checkbox: CheckBox = %IsMeta
@onready var is_active_checkbox: CheckBox = %IsActiveSource
@onready var content_label: RichTextLabel = %ContentLabel
@onready var parents_count: Label = %ParentsCount
@onready var children_count: Label = %ChildrenCount
@onready var dependencies_count: Label = %DependenciesCount
@onready var path_label: Label = %PathLabel
@onready var delete_button: Button = %DeleteButton
#@onready var graph_view_button: Button = %GraphView_Button
#@onready var show_hierarchy_button: Button = %Show_Hierarchy_Button

# Properties
var node_id: String = ""
var node_content: String = ""
var node_title: String = ""
var is_metaprompt: bool = false
var is_active: bool = false
var node_data: Dictionary = {}
var path: String = ""

# Injected state (preferred). Graph nodes should not discover ContentBus.
var _content_state: ContentStateResource = null

func set_resources(content_state: ContentStateResource) -> void:
	_content_state = content_state

var _pending_data: Dictionary = {}
var _is_updating_active_state: bool = false
var _is_updating_metaprompt: bool = false
var _is_prompt_highlighted: bool = false
var _context_trace_state: String = ""
var _is_diagnostic_highlighted: bool = false

func _ready() -> void:
	if DEBUG:
		print("ContentSourceGraphNode ready! Name: " + name)
	
	# Set some visual properties
	custom_minimum_size = Vector2(650, 150)
	resizable = true
	# NOTE: Keep styling theme-driven for determinism.
	# GraphNode theme items are defined in `SynesynUtility_light/dark` (GraphNode, GraphEdit).
	# Avoid ad-hoc overrides here because editor themes can mask missing keys and diverge at runtime.
	
	# Connect signals FOR THIS NODE ITSELF
	if has_signal("node_selected") and not is_connected("node_selected", _on_node_selected):
		connect("node_selected", _on_node_selected)
		
	if has_signal("node_deselected") and not is_connected("node_deselected", _on_node_deselected):
		connect("node_deselected", _on_node_deselected)
	
	if not position_offset_changed.is_connected(_on_position_changed):
		position_offset_changed.connect(_on_position_changed)
	
	# Connect metaprompt checkbox TO ITSELF (for emitting its own signal)
	if is_meta_checkbox and not is_meta_checkbox.toggled.is_connected(_on_is_meta_toggled):
		is_meta_checkbox.toggled.connect(_on_is_meta_toggled)
		
	# Connect active source checkbox TO ITSELF (for emitting its own signal)
	if is_active_checkbox and not is_active_checkbox.toggled.is_connected(_on_is_active_toggled):
		is_active_checkbox.toggled.connect(_on_is_active_toggled)

	# Delete button (node-scoped)
	if is_instance_valid(delete_button) and not delete_button.pressed.is_connected(_on_delete_pressed):
		delete_button.pressed.connect(_on_delete_pressed)

	# Initialize slots immediately with default state
	initialize_slots()

	# Allow row clicks to reach the GraphNode for selection (labels/containers should not swallow input).
	_set_noninteractive_children_mouse_filter(self)
	
	# Apply any pending data
	if not _pending_data.is_empty():
		# Ensure UI updates occur only after we are in the tree.
		var tmp: Dictionary = _pending_data
		_pending_data = {}
		set_node_data(tmp)
	elif not node_data.is_empty():
		# Safety: if data was set after insertion but UI didn't refresh for some reason.
		call_deferred("update_ui_from_data")
	
	# Visual states are set via set_active_state/set_metaprompt_state called by the controller
	# Don't sync checkboxes here - that's done in update_ui_from_data()

func _set_noninteractive_children_mouse_filter(n: Node) -> void:
	for c in n.get_children():
		# Keep interactive widgets behaving normally.
		if c is Button or c is CheckBox or c is LineEdit or c is TextEdit:
			continue
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		_set_noninteractive_children_mouse_filter(c)

func _gui_input(event: InputEvent) -> void:
	# Deterministic selection: clicking anywhere on the node selects it.
	# This avoids relying on GraphEdit/GraphNode selection signal quirks (and child controls swallowing input).
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var nid := String(node_id).strip_edges()
	if nid.is_empty():
		# Fallback to node name (should be the node_id), but avoid emitting empty.
		nid = String(name).strip_edges()
	if nid.is_empty():
		return
	selected = true
	var p = get_parent()
	if p and p.has_signal("content_node_selected"):
		p.content_node_selected.emit(nid)

func set_node_data(node_data: Dictionary) -> void:
	# If we're not in the scene tree yet, defer application until _ready().
	# GraphController often calls set_node_data before add_child(graph_node_instance).
	if not is_inside_tree():
		_pending_data = node_data.duplicate(true)
		# Still store a copy so other code can inspect metadata early if needed.
		self.node_data = _pending_data
		return
	
	# Store the data
	self.node_data = node_data
	
	# Set core properties
	node_id = node_data.get("node_id", "")
	node_content = node_data.get("content", "")
	path = node_data.get("path", "")  # Get path from root level first
	
	# Get source info from node data
	var source_id = ""
	var source_name = ""
	
	# First try to get source info from meta
	if node_data.has("meta"):
		source_id = node_data.meta.get("source_id", "")
		source_name = node_data.meta.get("source_name", "")
		# Get path from meta if not found at root level
		if path.is_empty():
			path = node_data.meta.get("path", "")
	
	# Fallback to direct source_id if not in meta
	if source_id.is_empty() and node_data.has("source_id"):
		source_id = node_data.source_id
	
	if DEBUG:
		print("ContentSourceGraphNode: Source info for node %s:" % node_id)
		print("  - Source ID: %s" % source_id)
		print("  - Source Name: %s" % source_name)
		print("  - Path: %s" % path)
	
	# First try getting states from node data
	if node_data.has("meta") and node_data.meta.has("ai_context"):
		is_metaprompt = node_data.meta.ai_context.get("metaprompt", false)
		# Accept both legacy `active` and canonical `is_active`.
		is_active = node_data.meta.ai_context.get("is_active", node_data.meta.ai_context.get("active", false))
		if DEBUG:
			print("Got states from node data meta.ai_context:")
			print("  - Metaprompt: %s" % str(is_metaprompt))
			print("  - Active: %s" % str(is_active))
	
	# If not found in node data and we have a source ID, try getting from content state
	if not source_id.is_empty():
		if is_instance_valid(_content_state):
			var source_data = _content_state.get_source_data(source_id)
			if not source_data.is_empty():
				# Only update if we didn't get values from node data
				if not node_data.has("meta") or not node_data.meta.has("ai_context"):
					is_metaprompt = source_data.get("meta", {}).get("ai_context", {}).get("metaprompt", false)
					is_active = source_data.get("meta", {}).get("ai_context", {}).get("is_active", false)
					if DEBUG:
						print("Got states from content state:")
						print("  - Metaprompt: %s" % str(is_metaprompt))
						print("  - Active: %s" % str(is_active))
	
	if DEBUG:
		print("ContentSourceGraphNode: States for node %s - Active: %s, Metaprompt: %s" % [node_id, str(is_active), str(is_metaprompt)])
	
	# Set title using source name first, then fallback to content
	title = source_name  # Use source name first
	if title.is_empty():
		title = node_data.get("title", "")  # Then try explicit title
	if title.is_empty() and not node_content.is_empty():
		var lines = node_content.split("\n")
		if lines.size() > 0:
			var first_line = lines[0].strip_edges()
			if first_line.begins_with("#"):
				title = first_line.trim_prefix("#").strip_edges()
			else:
				title = first_line
	if title.is_empty():
		title = node_id  # Final fallback to node ID
	
	# Update UI elements (labels, counts, checkboxes)
	update_ui_from_data()

func _on_is_meta_toggled(button_pressed: bool) -> void:
	# Prevent signal emission if this is a programmatic update
	if _is_updating_metaprompt:
		return
	is_metaprompt = button_pressed
	_update_metaprompt_visual_state(button_pressed)
	metaprompt_toggled.emit(node_id, button_pressed)

func _on_is_active_toggled(button_pressed: bool) -> void:
	# Prevent signal emission if this is a programmatic update
	if _is_updating_active_state:
		return
	is_active = button_pressed
	_update_active_visual_state(button_pressed)
	active_source_toggled.emit(node_id, button_pressed)

func _on_delete_pressed() -> void:
	var nid := String(node_id).strip_edges()
	if nid.is_empty():
		nid = String(name).strip_edges()
	if nid.is_empty():
		return
	delete_requested.emit(nid)

func initialize_slots() -> void:
	if DEBUG:
		print("ContentSourceGraphNode: Initializing slots for node %s" % node_id)
	
	# Clear any existing slots first
	clear_all_slots()
	
	# Always enable at least one slot (index 0) for potential connections
	# This ensures the node can always accept connections
	set_slot_enabled_left(0, true)
	set_slot_enabled_right(0, true)
	set_slot_color_left(0, Color.BLUE)
	set_slot_color_right(0, Color.GREEN)
	set_slot_type_left(0, 0)  # Use type 0 for all connections
	set_slot_type_right(0, 0)
	var category_colors: Array[Color] = [
		Color("#6f8fb3"),
		Color("#b58b4b"),
		Color("#4f9b72"),
		Color("#8a72b5"),
	]
	for category_index in range(category_colors.size()):
		var slot_index: int = category_index + 1
		set_slot_enabled_left(slot_index, true)
		set_slot_enabled_right(slot_index, true)
		set_slot_color_left(slot_index, category_colors[category_index])
		set_slot_color_right(slot_index, category_colors[category_index])
		set_slot_type_left(slot_index, 0)
		set_slot_type_right(slot_index, 0)
	
	if DEBUG:
		print("ContentSourceGraphNode: Slots initialized with default enabled state")

func _on_node_selected() -> void:
	# Always use the stored node_id, never fallback to name
	if node_id.is_empty():
		if DEBUG:
			print("ContentSourceGraphNode: Warning - empty node_id during selection")
		return
	
	# Get source ID from node data first
	var source_id = ""
	if node_data.has("source_id"):
		source_id = node_data.source_id
	elif node_data.has("meta") and node_data.meta.has("source_id"):
		source_id = node_data.meta.source_id
	
	# If still empty, try to get it from content state
	if source_id.is_empty():
		if is_instance_valid(_content_state) and _content_state.has_method("get_source_for_node"):
			source_id = _content_state.get_source_for_node(node_id)
	
	if DEBUG:
		print("ContentSourceGraphNode: Node selected with ID: %s (Source: %s)" % [node_id, source_id])
	if get_parent() and get_parent().has_signal("content_node_selected"):
		# Always pass the node_id, not the node instance
		get_parent().content_node_selected.emit(node_id)

func _on_node_deselected() -> void:
	# Always use the stored node_id, never fallback to name
	if node_id.is_empty():
		if DEBUG:
			print("ContentSourceGraphNode: Warning - empty node_id during deselection")
		return
	
	# Get source ID from node data first
	var source_id = ""
	if node_data.has("source_id"):
		source_id = node_data.source_id
	elif node_data.has("meta") and node_data.meta.has("source_id"):
		source_id = node_data.meta.source_id
	
	# If still empty, try to get it from content state
	if source_id.is_empty():
		if is_instance_valid(_content_state) and _content_state.has_method("get_source_for_node"):
			source_id = _content_state.get_source_for_node(node_id)
	
	if DEBUG:
		print("ContentSourceGraphNode: Node deselected with ID: %s (Source: %s)" % [node_id, source_id])
	if get_parent() and get_parent().has_signal("content_node_deselected"):
		# Always pass the node_id, not the node instance
		get_parent().content_node_deselected.emit(node_id)

func _on_position_changed() -> void:
	if node_id.is_empty():
		return
	if get_parent() and get_parent().has_signal("content_node_moved"):
		get_parent().content_node_moved.emit(node_id, position_offset)

func cleanup() -> void:
	if DEBUG:
		print("ContentSourceGraphNode: Explicit cleanup called for node ", name)
	
	# Disconnect all signals
	if is_connected("node_selected", _on_node_selected):
		disconnect("node_selected", _on_node_selected)
		
	if is_connected("node_deselected", _on_node_deselected):
		disconnect("node_deselected", _on_node_deselected)
		
	if position_offset_changed.is_connected(_on_position_changed):
		position_offset_changed.disconnect(_on_position_changed)
		
	if is_meta_checkbox and is_meta_checkbox.toggled.is_connected(_on_is_meta_toggled):
		is_meta_checkbox.toggled.disconnect(_on_is_meta_toggled)
		
	if is_active_checkbox and is_active_checkbox.toggled.is_connected(_on_is_active_toggled):
		is_active_checkbox.toggled.disconnect(_on_is_active_toggled)
	
	# Clear references
	node_id = ""
	node_content = ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		cleanup()
	elif what == NOTIFICATION_EXIT_TREE:
		cleanup()

func _enter_tree() -> void:
	if DEBUG:
		print("ContentSourceGraphNode: Entering tree: ", name)
	
	# Reconnect signals
	if has_signal("node_selected") and not is_connected("node_selected", _on_node_selected):
		connect("node_selected", _on_node_selected)
		
	if has_signal("node_deselected") and not is_connected("node_deselected", _on_node_deselected):
		connect("node_deselected", _on_node_deselected)
		
	if not position_offset_changed.is_connected(_on_position_changed):
		position_offset_changed.connect(_on_position_changed)
		
	if is_meta_checkbox and not is_meta_checkbox.toggled.is_connected(_on_is_meta_toggled):
		is_meta_checkbox.toggled.connect(_on_is_meta_toggled)
		
	if is_active_checkbox and not is_active_checkbox.toggled.is_connected(_on_is_active_toggled):
		is_active_checkbox.toggled.connect(_on_is_active_toggled)

func update_ui_from_data() -> void:
	if DEBUG:
		print("ContentSourceGraphNode: Updating UI for node: " + name)
	
	# Make sure we have the required UI elements
	if not is_inside_tree():
		if DEBUG:
			print("ContentSourceGraphNode: Not in tree yet, deferring UI update")
		return
	
	# Wait for _ready to complete
	if not name_label or not id_label or not content_label or not path_label:
		if DEBUG:
			print("ContentSourceGraphNode: UI elements not ready yet")
		await ready
	
	# Update labels with node data
	if name_label:
		# Use source name if available, otherwise use title
		var display_name = ""
		if node_data.has("meta"):
			display_name = node_data.meta.get("source_name", "")
		if display_name.is_empty():
			display_name = title
		name_label.text = "Source Name: " + display_name
		# (no noisy logging)
	
	if id_label:
		var source_id_txt := ""
		var container_id_txt := ""
		var linked_id_txt := ""
		if node_data is Dictionary:
			var meta: Dictionary = node_data.get("meta", {})
			source_id_txt = str(meta.get("source_id", "")).strip_edges()
			container_id_txt = str(meta.get("container_source_id", "")).strip_edges()
			linked_id_txt = str(meta.get("linked_source_id", "")).strip_edges()
		if source_id_txt.is_empty() and node_data is Dictionary:
			source_id_txt = str(node_data.get("source_id", "")).strip_edges()
		var txt := "Node ID: %s" % node_id
		if not source_id_txt.is_empty():
			txt += "\nSource ID: %s" % source_id_txt
		if not container_id_txt.is_empty() and container_id_txt != source_id_txt:
			txt += "\nContainer: %s" % container_id_txt
		if not linked_id_txt.is_empty() and linked_id_txt != source_id_txt:
			txt += "\nLinked: %s" % linked_id_txt
		id_label.text = txt
	if provenance_badge:
		var provenance: Dictionary = node_data.get("provenance", {})
		var authorship_kind: String = str(
			provenance.get("authorship_kind", "unknown")
		)
		var evidence_status: String = str(
			provenance.get("evidence_status", "unknown")
		)
		provenance_badge.text = "Origin: %s · Evidence: %s" % [
			authorship_kind.replace("_", " "),
			evidence_status,
		]
		provenance_badge.modulate = _provenance_badge_color(
			authorship_kind
		)
	
	if content_label and not node_content.is_empty():
		# Format content for better readability
		# IMPORTANT: do not force a hardcoded font color here.
		# Hardcoding white text breaks light themes and can look "un-themed" at runtime.
		content_label.text = node_content.replace("\n", "\n\n")
	
	if path_label:
		var p := String(path).strip_edges()
		path_label.text = ("Path: " + p) if not p.is_empty() else ""
	
	# Update relationship counts
	if node_data.has("relationships"):
		var relationships = node_data.relationships
		
		if parents_count and relationships.has("parents"):
			parents_count.text = str(relationships.parents.size())
		
		if children_count and relationships.has("children"):
			children_count.text = str(relationships.children.size())
		
		if dependencies_count and relationships.has("dependencies"):
			dependencies_count.text = str(relationships.dependencies.size())
	
	# Initialize slots based on relationships
	initialize_slots()
	
	# Update checkbox states - flags prevent handlers from emitting signals
	_is_updating_metaprompt = true
	_is_updating_active_state = true
	if is_meta_checkbox:
		is_meta_checkbox.button_pressed = is_metaprompt
	_update_metaprompt_visual_state(is_metaprompt)
	if is_active_checkbox:
		is_active_checkbox.button_pressed = is_active
	_update_active_visual_state(is_active)
	_is_updating_metaprompt = false
	_is_updating_active_state = false
	
	# (no noisy logging)

func _update_metaprompt_visual_state(is_meta: bool) -> void:
	_refresh_state_style_override()

func set_metaprompt_state(new_state: bool) -> void:
	if _is_updating_metaprompt:
		return
	_is_updating_metaprompt = true
	
	if is_meta_checkbox and is_meta_checkbox.button_pressed != new_state:
		is_meta_checkbox.button_pressed = new_state
	
	if is_metaprompt != new_state:
		is_metaprompt = new_state
		_update_metaprompt_visual_state(new_state)
	
	_is_updating_metaprompt = false

func _update_active_visual_state(is_act: bool) -> void:
	_refresh_state_style_override()

func _provenance_badge_color(authorship_kind: String) -> Color:
	match authorship_kind:
		"imported_quotation":
			return Color(0.45, 0.78, 1.0)
		"user_authored":
			return Color(0.55, 1.0, 0.62)
		"deterministic_summary":
			return Color(0.75, 0.72, 1.0)
		"ai_summary":
			return Color(0.95, 0.72, 0.35)
		"ai_inference":
			return Color(1.0, 0.52, 0.7)
		_:
			return Color(0.72, 0.72, 0.72)

func _refresh_state_style_override() -> void:
	_refresh_accessible_state_label()
	# IMPORTANT: GraphNode's theme properties are `panel`, `panel_selected`, `slot`,
	# `titlebar`, `titlebar_selected` (not "frame"). Using an invalid key can appear
	# to work in-editor (due to editor theme fallbacks) but diverge in-game.
	var needs_override := (
		is_metaprompt
		or is_active
		or _is_prompt_highlighted
		or not _context_trace_state.is_empty()
		or _is_diagnostic_highlighted
	)

	if not needs_override:
		if has_theme_stylebox_override("panel"):
			remove_theme_stylebox_override("panel")
		return

	var base := get_theme_stylebox("panel", "GraphNode")
	if base == null:
		# Defensive: should not happen if the active theme defines GraphNode/panel.
		return

	var style := base.duplicate()
	if style is StyleBoxFlat:
		# Start with sane defaults (ensure our overrides are deterministic).
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1

		# Metaprompt gives the node a subtle blue "tint".
		if is_metaprompt:
			style.bg_color = Color(0.2, 0.6, 1.0, 0.10)
			style.border_color = Color(0.2, 0.6, 1.0, 0.85)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2

		# Active state "wins" for the border (keeps metaprompt tint if both).
		if is_active:
			style.border_color = Color(0.4, 1.0, 0.4, 0.85)
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 3
		if _context_trace_state == "included":
			style.border_color = Color(0.2, 0.78, 0.92, 0.95)
			style.border_width_left = 4
			style.border_width_top = 4
			style.border_width_right = 4
			style.border_width_bottom = 4
		elif _context_trace_state == "omitted":
			style.border_color = Color(0.48, 0.5, 0.55, 0.9)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
		if _is_diagnostic_highlighted:
			style.border_color = Color(1.0, 0.45, 0.18, 0.98)
			style.border_width_left = 5
			style.border_width_top = 5
			style.border_width_right = 5
			style.border_width_bottom = 5
		if _is_prompt_highlighted:
			style.border_color = Color(0.95, 0.72, 0.25, 0.95)
			style.border_width_left = 4
			style.border_width_top = 4
			style.border_width_right = 4
			style.border_width_bottom = 4

	add_theme_stylebox_override("panel", style)


func _refresh_accessible_state_label() -> void:
	if not is_instance_valid(state_badge):
		return
	var labels: Array[String] = []
	labels.append("active" if is_active else "inactive")
	labels.append("metaprompt" if is_metaprompt else "standard")
	if _is_prompt_highlighted:
		labels.append("prompt-chain preview")
	if not _context_trace_state.is_empty():
		labels.append("context %s" % _context_trace_state)
	if _is_diagnostic_highlighted:
		labels.append("diagnostic warning")
	state_badge.text = "State: %s" % " · ".join(labels)


func set_prompt_chain_highlight(is_highlighted: bool) -> void:
	if _is_prompt_highlighted == is_highlighted:
		return
	_is_prompt_highlighted = is_highlighted
	_refresh_state_style_override()


func set_context_trace_state(trace_state: String) -> void:
	var normalized_state: String = trace_state
	if not normalized_state in ["", "included", "omitted"]:
		normalized_state = ""
	if _context_trace_state == normalized_state:
		return
	_context_trace_state = normalized_state
	_refresh_state_style_override()


func set_diagnostic_highlight(is_highlighted: bool) -> void:
	if _is_diagnostic_highlighted == is_highlighted:
		return
	_is_diagnostic_highlighted = is_highlighted
	_refresh_state_style_override()


func set_active_state(new_state: bool) -> void:
	if _is_updating_active_state:
		return
	_is_updating_active_state = true
	
	if is_active_checkbox and is_active_checkbox.button_pressed != new_state:
		is_active_checkbox.button_pressed = new_state
	
	if is_active != new_state:
		is_active = new_state
		_update_active_visual_state(new_state)
	
	_is_updating_active_state = false
