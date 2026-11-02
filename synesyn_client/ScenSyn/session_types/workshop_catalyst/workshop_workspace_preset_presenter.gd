extends RefCounted
class_name WorkshopWorkspacePresetPresenter

## Purpose: how the Workshop header reflects preset state.
##
## Split out of `workshop_workspace_controller.gd`, which owns composition —
## deciding which panes exist, reparenting regions, clamping splits. Telling the
## facilitator which preset is active, and which are open to them, is a separate and
## purely presentational concern with no layout consequences, so it lives here and
## the controller stays under its size budget.

const ReviewGateScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_review_gate.gd"
)

## Header button node id to the preset it requests.
const PRESET_BUTTONS: Dictionary = {
	"TalkPresetButton": "talk",
	"MapPresetButton": "map",
	"ReviewPresetButton": "review",
	"HowToPresetButton": "how_to",
	"FullDashboardPresetButton": "full_dashboard",
	"CustomPresetButton": "custom",
}


static func apply_button_variations(shell_root_node: Control, active_preset_id: String) -> void:
	for button_id: String in PRESET_BUTTONS:
		var preset_button_node: Button = _button(shell_root_node, button_id)
		if preset_button_node == null:
			continue
		if String(PRESET_BUTTONS[button_id]) == active_preset_id:
			preset_button_node.theme_type_variation = &"SynesynNavigationSelected"
		else:
			preset_button_node.theme_type_variation = &"SynesynNavigation"


static func apply_active_label(shell_root_node: Control, active_preset_id: String) -> void:
	var active_label_node: Label = shell_root_node.find_child(
		"ActivePresetLabel", true, false
	) as Label
	if not active_label_node:
		return
	active_label_node.text = "Active: " + active_preset_id.replace("_", " ").capitalize()


## A disabled button with an explanatory tooltip, rather than a hidden one: a
## facilitator should be able to see that Review exists and find out what it needs.
static func apply_review_availability(
	shell_root_node: Control,
	is_review_available: bool
) -> void:
	var review_button_node: Button = _button(shell_root_node, "ReviewPresetButton")
	if not review_button_node:
		return
	review_button_node.disabled = not is_review_available
	if is_review_available:
		review_button_node.tooltip_text = ReviewGateScript.available_tooltip()
	else:
		review_button_node.tooltip_text = ReviewGateScript.unavailable_tooltip()


static func _button(shell_root_node: Control, button_id: String) -> Button:
	if not is_instance_valid(shell_root_node):
		return null
	return shell_root_node.find_child(button_id, true, false) as Button
