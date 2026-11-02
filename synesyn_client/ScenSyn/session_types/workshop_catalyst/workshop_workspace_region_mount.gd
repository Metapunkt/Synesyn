extends RefCounted
class_name WorkshopWorkspaceRegionMount

## One-time region reparenting mechanics used when the Workshop dashboard shell
## first mounts: moves the pre-existing conversation transcript, text input,
## input-action buttons, and Session Record region out of their original
## scene locations and into the shell's slots. Split out of
## workshop_workspace_controller.gd (script size ratchet) since this logic is
## only ever exercised once, at mount time, and has no runtime/preset state.

const ConversationLayoutStabilizerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_conversation_layout_stabilizer.gd"
)


static func move_existing_regions(
	shell_root_node: Control,
	conversation_region_node: Control,
	session_record_region_node: Control,
	record_button_node: Button
) -> bool:
	var conversation_slot_node: VBoxContainer = (
		_find_control(shell_root_node, "ConversationContentSlot") as VBoxContainer
	)
	var text_input_slot_node: VBoxContainer = (
		_find_control(shell_root_node, "ConversationTextInputSlot") as VBoxContainer
	)
	var input_actions_slot_node: HFlowContainer = (
		_find_control(shell_root_node, "ConversationInputActionsSlot") as HFlowContainer
	)
	var record_slot_node: VBoxContainer = (
		_find_control(shell_root_node, "SessionRecordContentSlot") as VBoxContainer
	)
	var original_conversation_parent_node: Node = conversation_region_node.get_parent()
	var story_log_system_node: Control = conversation_region_node.find_child(
		"StoryLogSystem", true, false
	) as Control
	if not story_log_system_node:
		return false
	var text_input_node: Control = conversation_region_node.find_child(
		"InputField", true, false
	) as Control
	var input_actions_region_node: Control = _find_input_actions_region(
		record_button_node,
		original_conversation_parent_node
	)
	session_record_region_node.reparent(record_slot_node)
	story_log_system_node.reparent(conversation_slot_node)
	conversation_region_node.visible = false
	if text_input_node:
		text_input_node.reparent(text_input_slot_node)
	if input_actions_region_node:
		for action_group_node: Node in input_actions_region_node.get_children():
			var action_group_control_node: Control = action_group_node as Control
			if action_group_control_node:
				action_group_control_node.reparent(input_actions_slot_node)
				normalize_reparented_region(action_group_control_node)
				action_group_control_node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				action_group_control_node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		input_actions_region_node.visible = false
		ConversationLayoutStabilizerScript.compact_input_actions(input_actions_slot_node)
	normalize_reparented_region(story_log_system_node)
	normalize_reparented_region(session_record_region_node)
	if text_input_node:
		text_input_node.custom_minimum_size = Vector2.ZERO
		text_input_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_record_region_node.visible = true
	_mount_wait_progress(shell_root_node)
	return true


static func _mount_wait_progress(shell_root_node: Control) -> void:
	var slot_node: Control = _find_control(shell_root_node, "WaitProgressSlot")
	if not slot_node:
		return
	var scene_tree: SceneTree = shell_root_node.get_tree()
	if scene_tree == null:
		return
	var game_session_node: Node = scene_tree.get_first_node_in_group("game_session")
	if game_session_node == null:
		return
	var progress_bar_node: Control = (
		game_session_node.get_node_or_null("%ProgressBar") as Control
	)
	if progress_bar_node == null or progress_bar_node.get_parent() == slot_node:
		return
	progress_bar_node.reparent(slot_node)
	progress_bar_node.z_index = 0
	progress_bar_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	progress_bar_node.offset_left = 0.0
	progress_bar_node.offset_top = 0.0
	progress_bar_node.offset_right = 0.0
	progress_bar_node.offset_bottom = 0.0
	progress_bar_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	progress_bar_node.custom_minimum_size = Vector2(0, 16)
	progress_bar_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_node.visible = progress_bar_node.visible


static func _find_input_actions_region(
	record_button_node: Button,
	expected_parent_node: Node
) -> Control:
	if not record_button_node or not expected_parent_node:
		return null
	var voice_actions_node: Control = record_button_node.get_parent() as Control
	if not voice_actions_node:
		return null
	var combined_actions_node: Control = voice_actions_node.get_parent() as Control
	if combined_actions_node and combined_actions_node.get_parent() == expected_parent_node:
		return combined_actions_node
	return null


static func normalize_reparented_region(region_node: Control) -> void:
	region_node.custom_minimum_size = Vector2.ZERO
	region_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	region_node.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	for child_node: Node in region_node.get_children():
		var child_control_node: Control = child_node as Control
		if child_control_node:
			child_control_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			child_control_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for descendant_node: Node in region_node.find_children("*", "Control", true, false):
		var descendant_control_node: Control = descendant_node as Control
		if (
			descendant_control_node is TabContainer
			or descendant_control_node is ScrollContainer
			or descendant_control_node is BoxContainer
		):
			descendant_control_node.custom_minimum_size.x = 0.0
			descendant_control_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elif (
			descendant_control_node is MarginContainer
			or descendant_control_node is PanelContainer
		):
			descendant_control_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elif (
			descendant_control_node is Label
			or descendant_control_node is RichTextLabel
			or descendant_control_node is LineEdit
			or descendant_control_node is TextEdit
			or descendant_control_node.name in ["StoryLogSystem", "ChatSystem"]
		):
			descendant_control_node.custom_minimum_size.x = 0.0
			descendant_control_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func _find_control(shell_root_node: Control, control_id: String) -> Control:
	if not shell_root_node:
		return null
	return shell_root_node.find_child(control_id, true, false) as Control
