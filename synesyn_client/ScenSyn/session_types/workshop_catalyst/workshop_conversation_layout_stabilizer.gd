extends RefCounted
class_name WorkshopConversationLayoutStabilizer


static func stabilize(shell_root_node: Control) -> void:
	if not is_instance_valid(shell_root_node):
		return
	var conversation_panel_node: Control = _find(shell_root_node, "ConversationPanel")
	var conversation_box_node: Control = _find(shell_root_node, "ConversationBox")
	var transcript_scroll_node: ScrollContainer = (
		_find(shell_root_node, "ConversationTranscriptScroll") as ScrollContainer
	)
	var content_slot_node: VBoxContainer = (
		_find(shell_root_node, "ConversationContentSlot") as VBoxContainer
	)
	if not content_slot_node:
		return
	for bounded_node: Control in [
		conversation_panel_node,
		conversation_box_node,
		transcript_scroll_node,
	]:
		if bounded_node:
			bounded_node.clip_contents = true
	var story_log_node: Control = content_slot_node.find_child(
		"StoryLogSystem",
		true,
		false
	) as Control
	if story_log_node:
		_stabilize_story_log_embed(story_log_node)
	for layout_node: Control in [
		content_slot_node,
		transcript_scroll_node,
		conversation_box_node,
	]:
		if layout_node:
			layout_node.update_minimum_size()
			if layout_node is Container:
				(layout_node as Container).queue_sort()


static func _stabilize_story_log_embed(story_log_node: Control) -> void:
	# ConversationContentSlot is a VBoxContainer: expand-fill, do not pin
	# full-rect anchors (those fight the container and clip the first line).
	story_log_node.custom_minimum_size = Vector2.ZERO
	story_log_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_log_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	story_log_node.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var scroll_node: ScrollContainer = (
		story_log_node.get_node_or_null("ScrollContainer") as ScrollContainer
	)
	if scroll_node:
		scroll_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll_node.offset_left = 8.0
		scroll_node.offset_top = 8.0
		scroll_node.offset_right = -8.0
		scroll_node.offset_bottom = -8.0
		scroll_node.custom_minimum_size = Vector2.ZERO
		scroll_node.clip_contents = true
		scroll_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll_node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var message_box_node: VBoxContainer = story_log_node.get_node_or_null(
		"%VBoxContainer"
	) as VBoxContainer
	if message_box_node:
		# Shrink-to-content so short welcomes sit at the top instead of leaving
		# a tall empty band above after scroll-to-bottom.
		message_box_node.custom_minimum_size = Vector2.ZERO
		message_box_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		message_box_node.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		message_box_node.alignment = BoxContainer.ALIGNMENT_BEGIN


static func _find(shell_root_node: Control, control_id: String) -> Control:
	return shell_root_node.find_child(control_id, true, false) as Control


## The transcript overlays share one height-capped scroll, so two open editors
## cannot stack an uncompressible ~370px above the conversation — enough to push
## the session header off screen in presets that also keep the map and input
## dock open. That cap is a minimum size, so the scroll has to leave the layout
## entirely whenever no overlay is up.
static func sync_overlay_scroll(
	shell_root_node: Control,
	overlay_control_ids: Array
) -> void:
	if not is_instance_valid(shell_root_node):
		return
	var scroll_node: Control = _find(shell_root_node, "ConversationOverlayScroll")
	if not scroll_node:
		return
	var is_any_overlay_visible: bool = false
	for overlay_control_id: Variant in overlay_control_ids:
		var panel_node: Control = _find(shell_root_node, String(overlay_control_id))
		if panel_node and panel_node.visible:
			is_any_overlay_visible = true
			break
	scroll_node.visible = is_any_overlay_visible


static func sync_input_dock_controls(
	shell_root_node: Control,
	is_conversation_visible: bool,
	is_input_dock_visible: bool
) -> void:
	if not is_instance_valid(shell_root_node):
		return
	var is_dock_shown: bool = is_conversation_visible and is_input_dock_visible
	var input_dock_node: Control = _find(shell_root_node, "ConversationInputDock")
	var input_toggle_node: CheckButton = (
		_find(shell_root_node, "ConversationInputToggle") as CheckButton
	)
	if input_dock_node:
		input_dock_node.visible = is_dock_shown
	if input_toggle_node:
		input_toggle_node.disabled = not is_conversation_visible
		input_toggle_node.set_pressed_no_signal(is_input_dock_visible)


static func compact_input_actions(actions_slot_node: Control) -> void:
	if not actions_slot_node:
		return
	const ACTION_FONT_SIZE := 11
	const ACTION_ICON_WIDTH := 14
	for group_node: Node in actions_slot_node.get_children():
		var group_control_node: Control = group_node as Control
		if group_control_node is BoxContainer:
			group_control_node.add_theme_constant_override("separation", 6)
			group_control_node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for descendant_node: Node in actions_slot_node.find_children("*", "Control", true, false):
		var control_node: Control = descendant_node as Control
		if control_node is BaseButton:
			control_node.add_theme_font_size_override("font_size", ACTION_FONT_SIZE)
			control_node.add_theme_constant_override("icon_max_width", ACTION_ICON_WIDTH)
			control_node.custom_minimum_size = Vector2.ZERO
			control_node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			control_node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		elif control_node is Label and control_node.name == "PhaseDisplayLabel":
			control_node.add_theme_font_size_override("font_size", ACTION_FONT_SIZE)
			control_node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
