## Purpose: utils/ui/resize_handle.gd
@tool
extends Control

# Theme constants
const THEME = {
	"normal_color": Color(0.5, 0.5, 0.5, 0.15),  # Slightly visible when not hovered
	"hover_color": Color(0.7, 0.7, 0.7, 0.5),    # More visible when hovered
	"border_color": Color(0.3, 0.3, 0.35, 0.5),
	"border_width": 1,
	"hover_border_width": 2,
	"corner_radius": 2
}

# Parent container to resize
var parent_container: Control
var min_size: float = 50.0

# State tracking
var dragging: bool = false
var start_position: Vector2
var start_size: Vector2
var is_hovered: bool = false

func _ready() -> void:
	# Set up the handle
	custom_minimum_size = Vector2(0, 16)  # Increased for better targeting
	mouse_default_cursor_shape = Control.CURSOR_VSIZE
	
	# Add margins for better visibility
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)
	
	_update_style()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if dragging:
				start_position = get_global_mouse_position()
				start_size = parent_container.size
				get_viewport().gui_release_focus()
	
	elif event is InputEventMouseMotion:
		if dragging:
			var delta = get_global_mouse_position().y - start_position.y
			var new_size = start_size.y + delta
			parent_container.custom_minimum_size.y = max(new_size, min_size)
			get_parent().queue_sort()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			is_hovered = true
			_update_style()
		NOTIFICATION_MOUSE_EXIT:
			is_hovered = false
			_update_style()

func _update_style() -> void:
	var style = StyleBoxFlat.new()
	
	if is_hovered or dragging:
		style.bg_color = THEME.hover_color
		style.set_border_width_all(THEME.hover_border_width)
	else:
		style.bg_color = THEME.normal_color
		style.set_border_width_all(THEME.border_width)
	
	style.border_color = THEME.border_color
	style.set_corner_radius_all(THEME.corner_radius)
	add_theme_stylebox_override("normal", style) 
