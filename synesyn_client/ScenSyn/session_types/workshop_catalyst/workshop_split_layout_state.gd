extends RefCounted
class_name WorkshopSplitLayoutState

## Owns Workshop split offsets and drag persistence. The split hierarchy itself
## remains scene-authored; this helper only binds and validates layout state.

signal split_state_changed

const SynesynUiTokensScript = preload(
	"res://ScenSyn/scripts/core/synesyn_ui_tokens.gd"
)

const SPLIT_NODE_IDS: Dictionary = {
	"left_rail": "DashboardBody",
	"right_rail": "MainRegionSplit",
	"center_vertical": "CenterVerticalSplit",
	"right_vertical": "RightVerticalSplit",
	"conversation_input": "ConversationAndDockSplit",
}

const DEFAULT_OFFSETS: Dictionary = {
	"left_rail": 0,
	"right_rail": 0,
	"center_vertical": 0,
	"right_vertical": 0,
	# Prefer a tall transcript; the input dock keeps its minimum height.
	"conversation_input": 10000,
}

const INVALID_OFFSET_LIMIT := 100000

var _shell_root_node: Control
var _split_nodes: Dictionary = {}
var _stored_offsets: Dictionary = {}
var _is_applying_offsets: bool = false
var _has_restored_offsets: bool = false


func mount(shell_root_node: Control) -> bool:
	_shell_root_node = shell_root_node
	for split_id: String in SPLIT_NODE_IDS:
		var split_node: SplitContainer = shell_root_node.find_child(
			String(SPLIT_NODE_IDS[split_id]), true, false
		) as SplitContainer
		if not split_node:
			return false
		_split_nodes[split_id] = split_node
		if not split_node.dragged.is_connected(_on_split_dragged.bind(split_id)):
			split_node.dragged.connect(_on_split_dragged.bind(split_id))
	if not shell_root_node.resized.is_connected(_on_shell_resized):
		shell_root_node.resized.connect(_on_shell_resized)
	return true


func restore_state(offsets_any: Variant) -> void:
	_stored_offsets.clear()
	var offsets: Dictionary = (
		offsets_any if typeof(offsets_any) == TYPE_DICTIONARY else {}
	)
	for split_id: String in SPLIT_NODE_IDS:
		var offset_any: Variant = offsets.get(split_id)
		if _is_valid_offset_value(offset_any):
			_stored_offsets[split_id] = int(offset_any)
		else:
			_stored_offsets[split_id] = int(DEFAULT_OFFSETS[split_id])
	_has_restored_offsets = true
	call_deferred("_apply_stored_offsets")


func get_state() -> Dictionary:
	var result: Dictionary = {}
	for split_id: String in SPLIT_NODE_IDS:
		if _stored_offsets.has(split_id):
			result[split_id] = int(_stored_offsets[split_id])
		else:
			result[split_id] = int(DEFAULT_OFFSETS[split_id])
	return result


func reset_to_defaults() -> void:
	for split_id: String in SPLIT_NODE_IDS:
		_stored_offsets[split_id] = int(DEFAULT_OFFSETS[split_id])
	_has_restored_offsets = true
	_apply_stored_offsets()
	split_state_changed.emit()


func set_split_offset(split_id: String, requested_offset: int) -> void:
	if split_id not in _split_nodes:
		return
	var split_node: SplitContainer = _split_nodes[split_id] as SplitContainer
	var safe_offset: int = _clamp_offset(split_node, requested_offset)
	_is_applying_offsets = true
	split_node.split_offset = safe_offset
	_is_applying_offsets = false
	_stored_offsets[split_id] = safe_offset
	_has_restored_offsets = true
	split_state_changed.emit()


func get_split_offset(split_id: String) -> int:
	var split_node: SplitContainer = _split_nodes.get(split_id) as SplitContainer
	return split_node.split_offset if split_node else 0


func set_splitters_enabled(is_enabled: bool) -> void:
	for split_any: Variant in _split_nodes.values():
		var split_node: SplitContainer = split_any as SplitContainer
		split_node.dragger_visibility = (
			SplitContainer.DRAGGER_VISIBLE
			if is_enabled
			else SplitContainer.DRAGGER_HIDDEN_COLLAPSED
		)


func apply_pane_visibility(
	is_left_visible: bool,
	is_center_visible: bool,
	is_right_visible: bool,
	is_conversation_visible: bool,
	is_secondary_visible: bool,
	is_assistant_visible: bool,
	is_record_visible: bool,
	is_input_dock_visible: bool,
	is_narrow_layout: bool
) -> void:
	_apply_two_pane_visibility(
		"left_rail", is_left_visible, is_center_visible or is_right_visible,
		not is_narrow_layout
	)
	_apply_two_pane_visibility(
		"right_rail", is_center_visible, is_right_visible, not is_narrow_layout
	)
	_apply_two_pane_visibility(
		"center_vertical",
		is_conversation_visible or is_input_dock_visible,
		is_secondary_visible,
		not is_narrow_layout
	)
	_apply_two_pane_visibility(
		"right_vertical", is_assistant_visible, is_record_visible,
		not is_narrow_layout
	)
	_apply_two_pane_visibility(
		"conversation_input",
		is_conversation_visible,
		is_conversation_visible and is_input_dock_visible,
		not is_narrow_layout
	)


func clamp_for_current_viewport() -> void:
	if not _has_restored_offsets:
		return
	_apply_stored_offsets()


func _apply_stored_offsets() -> void:
	if not is_instance_valid(_shell_root_node):
		return
	_is_applying_offsets = true
	for split_id: String in SPLIT_NODE_IDS:
		var split_node: SplitContainer = _split_nodes.get(split_id) as SplitContainer
		if not split_node:
			continue
		var requested_offset: int = int(
			_stored_offsets.get(split_id, DEFAULT_OFFSETS[split_id])
		)
		var safe_offset: int = _clamp_offset(split_node, requested_offset)
		split_node.split_offset = safe_offset
		_stored_offsets[split_id] = safe_offset
	_is_applying_offsets = false


func _clamp_offset(split_node: SplitContainer, requested_offset: int) -> int:
	var available_extent: int = int(
		split_node.size.x if split_node is HSplitContainer else split_node.size.y
	)
	if available_extent <= SynesynUiTokensScript.SPLIT_MIN_PANE_EXTENT * 2:
		return 0
	var maximum_magnitude: int = maxi(
		0,
		available_extent - SynesynUiTokensScript.SPLIT_MIN_PANE_EXTENT
	)
	return clampi(requested_offset, -maximum_magnitude, maximum_magnitude)


func _apply_two_pane_visibility(
	split_id: String,
	is_first_visible: bool,
	is_second_visible: bool,
	allow_dragging: bool
) -> void:
	var split_node: SplitContainer = _split_nodes.get(split_id) as SplitContainer
	if not split_node:
		return
	_is_applying_offsets = true
	split_node.collapsed = not is_first_visible and is_second_visible
	if is_first_visible and not is_second_visible:
		split_node.split_offset = INVALID_OFFSET_LIMIT
	elif is_first_visible and is_second_visible:
		var requested_offset: int = int(
			_stored_offsets.get(split_id, DEFAULT_OFFSETS[split_id])
		)
		split_node.split_offset = _clamp_offset(split_node, requested_offset)
	split_node.dragger_visibility = (
		SplitContainer.DRAGGER_VISIBLE
		if allow_dragging and is_first_visible and is_second_visible
		else SplitContainer.DRAGGER_HIDDEN_COLLAPSED
	)
	_is_applying_offsets = false


func _is_valid_offset_value(offset_any: Variant) -> bool:
	if typeof(offset_any) != TYPE_INT and typeof(offset_any) != TYPE_FLOAT:
		return false
	var offset_value: int = int(offset_any)
	return absi(offset_value) <= INVALID_OFFSET_LIMIT


func _on_split_dragged(split_offset: int, split_id: String) -> void:
	if _is_applying_offsets:
		return
	var split_node: SplitContainer = _split_nodes.get(split_id) as SplitContainer
	if not split_node:
		return
	var previous_offset: int = int(_stored_offsets.get(split_id, DEFAULT_OFFSETS[split_id]))
	var safe_offset: int = _clamp_offset(split_node, split_offset)
	_stored_offsets[split_id] = safe_offset
	if safe_offset != split_offset:
		_is_applying_offsets = true
		split_node.split_offset = safe_offset
		_is_applying_offsets = false
	if split_id == "center_vertical":
		# Keep transcript height stable so the outer drag grows/shrinks the
		# message dock into the secondary pane (downward resize).
		var offset_delta: int = safe_offset - previous_offset
		if offset_delta != 0 and "conversation_input" in _split_nodes:
			var input_split_node: SplitContainer = (
				_split_nodes["conversation_input"] as SplitContainer
			)
			var input_offset: int = int(
				_stored_offsets.get(
					"conversation_input",
					DEFAULT_OFFSETS["conversation_input"]
				)
			)
			var adjusted_input_offset: int = _clamp_offset(
				input_split_node,
				input_offset - offset_delta
			)
			_is_applying_offsets = true
			input_split_node.split_offset = adjusted_input_offset
			_is_applying_offsets = false
			_stored_offsets["conversation_input"] = adjusted_input_offset
	_has_restored_offsets = true
	split_state_changed.emit()


func _on_shell_resized() -> void:
	call_deferred("clamp_for_current_viewport")
