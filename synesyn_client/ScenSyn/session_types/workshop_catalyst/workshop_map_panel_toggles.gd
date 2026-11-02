extends RefCounted
class_name WorkshopMapPanelToggles

## The Custom drawer's two Thinking Map sub-switches: the claims pane (the Causes / Effects /
## Opportunities / Outcomes columns, and the Graph view that replaces them) and the Closure
## panel beneath it.
##
## They live in the drawer beside the other panel switches, but the nodes they act on live
## inside the Thinking Map scene, so neither the workspace controller nor the map controller
## owns the pairing outright. This file does, and both sides call into it: the map controller
## connects the switches when it mounts, and pushes state back whenever the Closure panel is
## opened or closed by its own footer toggle or its Hide button.
##
## Deliberately not persisted. These are within-session view controls, in the same class as
## the Columns / Graph buttons on the map toolbar, and a session that reopened with its claims
## hidden would look broken rather than remembered.

const MapLayoutUtilsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_map_layout_utils.gd"
)

const CLAIMS_TOGGLE_NAME := "MapClaimsToggle"
const CLOSURE_TOGGLE_NAME := "MapClosureToggle"


## Wires both switches, if the embedding shell has them. Older shells simply keep the map's
## own footer toggle and lose nothing else, which is why every lookup here is optional.
##
## `on_closure_toggled` is a callable rather than a direct poke at `%ClosureAuditToggle`,
## because opening the audit does more than reveal a panel: it shows the per-card orientation
## pickers and expires undecided suggestions. Only the map controller knows that.
static func connect_sub_toggles(
	map_root_node: Control,
	on_closure_toggled: Callable
) -> void:
	var claims_toggle: CheckButton = find_sub_toggle(map_root_node, CLAIMS_TOGGLE_NAME)
	if claims_toggle:
		_clear_connections(claims_toggle)
		claims_toggle.toggled.connect(
			func(is_pressed: bool) -> void:
				set_claims_pane_visible(map_root_node, is_pressed)
		)
	var closure_toggle: CheckButton = find_sub_toggle(map_root_node, CLOSURE_TOGGLE_NAME)
	if closure_toggle:
		_clear_connections(closure_toggle)
		closure_toggle.toggled.connect(on_closure_toggled)


## The switches outlive the map: the drawer belongs to the shell, and a second session mounts a
## fresh map controller under the same shell. Both handlers close over the map that was current
## when they were made, so leaving the first one attached would have a switch driving a freed
## node while the live map ignored it.
static func _clear_connections(toggle_node: CheckButton) -> void:
	for connection: Dictionary in toggle_node.toggled.get_connections():
		toggle_node.toggled.disconnect(connection["callable"])


## Hides or shows the upper half of the map's split: the claim columns, or the Graph view when
## that is the active view. The split offset is cleared either way, so whichever pane is left
## takes the full height instead of honouring a divider position dragged for two panes.
static func set_claims_pane_visible(map_root_node: Control, is_pane_visible: bool) -> void:
	if not is_instance_valid(map_root_node):
		return
	var body_pane_node: Control = (
		map_root_node.get_node_or_null("%MapBodyPane") as Control
	)
	if body_pane_node == null:
		return
	body_pane_node.visible = is_pane_visible
	var split_node: VSplitContainer = (
		map_root_node.get_node_or_null("%MapBodySplit") as VSplitContainer
	)
	if split_node:
		split_node.split_offset = 0


## Brings the drawer switches back into line with the map. Called after the Closure panel is
## opened or closed by any route, so the drawer never reads "on" over a shut panel.
static func sync_sub_toggles(map_root_node: Control, is_closure_active: bool) -> void:
	var closure_toggle: CheckButton = find_sub_toggle(map_root_node, CLOSURE_TOGGLE_NAME)
	if closure_toggle and closure_toggle.button_pressed != is_closure_active:
		closure_toggle.set_pressed_no_signal(is_closure_active)
	var claims_toggle: CheckButton = find_sub_toggle(map_root_node, CLAIMS_TOGGLE_NAME)
	var body_pane_node: Control = (
		map_root_node.get_node_or_null("%MapBodyPane") as Control
		if is_instance_valid(map_root_node)
		else null
	)
	if claims_toggle and body_pane_node:
		claims_toggle.set_pressed_no_signal(body_pane_node.visible)


## The switches sit in the workspace shell, the map sits several levels below it, and unique
## names do not cross a scene boundary. Walking to the outermost ancestor and searching down
## from there is what makes the pairing work without either scene naming the other's paths.
static func find_sub_toggle(map_root_node: Control, toggle_name: String) -> CheckButton:
	if not is_instance_valid(map_root_node):
		return null
	var ancestor_node: Node = map_root_node
	while ancestor_node.get_parent() != null:
		ancestor_node = ancestor_node.get_parent()
	return ancestor_node.find_child(toggle_name, true, false) as CheckButton
