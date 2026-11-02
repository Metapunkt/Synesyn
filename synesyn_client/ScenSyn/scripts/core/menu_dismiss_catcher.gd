## Purpose: Dismiss an open menu or drawer when the user clicks outside it.
##
## This is a full-rect Control placed directly beneath the menu panel in draw
## order, so the panel keeps receiving its own clicks while everything behind it
## is covered. It mirrors the panel's visibility rather than being toggled by
## callers, so every existing place that opens or closes the panel keeps working
## without knowing this node exists.
##
## Like a normal modal overlay, the dismissing click is consumed: it closes the
## menu instead of also activating whatever sits underneath. That includes the
## button that opened the menu, so clicking it again reads as "close" — which is
## why this only suits panels toggled by a plain button. A panel whose open state
## is mirrored by a CheckButton would leave that button stuck pressed.
##
## Do not use this for dialogs that must be answered: a modal asking for a
## decision should not vanish on a stray click.
##
## Native Popup, PopupPanel, and PopupMenu already dismiss themselves; this
## exists for hand-rolled panels built from Control nodes.
extends Control

## Panel to dismiss. When unset, the next sibling Control is used, which matches
## the convention of placing this node immediately before the panel.
@export var panel_path: NodePath

var _panel: Control = null

func _ready() -> void:
	visible = false
	_panel = _resolve_panel()
	if _panel == null:
		# Nothing to guard. Stay transparent to input rather than swallowing clicks.
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		push_warning("MenuDismissCatcher: no panel found; catcher disabled at %s" % get_path())
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visibility_changed.connect(_sync_to_panel)
	gui_input.connect(_on_gui_input)
	_sync_to_panel()

func _resolve_panel() -> Control:
	if not panel_path.is_empty():
		return get_node_or_null(panel_path) as Control
	var parent := get_parent()
	if parent == null:
		return null
	# Convention: the panel is the sibling drawn immediately above this node.
	for i in range(get_index() + 1, parent.get_child_count()):
		var sibling := parent.get_child(i) as Control
		if sibling != null:
			return sibling
	return null

func _sync_to_panel() -> void:
	if _panel == null:
		return
	visible = _panel.is_visible_in_tree()

func _on_gui_input(event: InputEvent) -> void:
	var is_press := false
	if event is InputEventMouseButton:
		is_press = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		is_press = event.pressed
	if not is_press:
		return
	if _panel != null and _panel.visible:
		_panel.visible = false
	accept_event()
