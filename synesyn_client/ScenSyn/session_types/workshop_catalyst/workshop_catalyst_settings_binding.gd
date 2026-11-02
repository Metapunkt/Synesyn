extends RefCounted
class_name WorkshopCatalystSettingsBinding

signal start_requested
signal pause_requested
signal next_stage_requested
signal add_time_requested(minutes: int)
signal note_only_changed(is_enabled: bool)
signal facilitator_sender_changed(is_enabled: bool)
signal duration_changed(session_minutes: int)
signal multi_day_changed(is_enabled: bool)
signal update_buckets_requested
signal export_summary_requested
signal export_decision_record_requested
signal inject_stress_requested

const SettingsPanelScene := preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_settings_panel.tscn"
)

var _scene_root_node: Node
var _content_node: VBoxContainer
var _stage_label_node: Label
var _time_label_node: Label
var _session_status_label_node: Label
var _mode_status_label_node: Label
var _session_duration_option_node: OptionButton
var _multi_day_toggle_node: CheckButton
var _add_note_toggle_node: CheckButton
var _next_button_node: Button
var _update_buckets_button_node: Button
var _send_as_facilitator_toggle_node: CheckButton
var _export_summary_button_node: Button
var _export_decision_record_button_node: Button
var _inject_stress_button_node: Button
var _action_status_label_node: Label


func mount(settings_container_node: VBoxContainer) -> bool:
	if not settings_container_node:
		return false
	_scene_root_node = SettingsPanelScene.instantiate()
	if not _scene_root_node:
		return false
	var background_node: TextureRect = _scene_root_node.get_node_or_null("WorkshopCatalystBg") as TextureRect
	_content_node = _scene_root_node.get_node_or_null("SettingsContent") as VBoxContainer
	if not _content_node:
		return false
	_cache_controls()
	_clear_scene_owners(background_node)
	_clear_scene_owners(_content_node)
	_mount_background(settings_container_node, background_node)
	_content_node.reparent(settings_container_node)
	_scene_root_node.free()
	_scene_root_node = null
	_populate_duration_options()
	_connect_controls()
	return has_required_controls()


func has_required_controls() -> bool:
	return (
		_stage_label_node != null
		and _time_label_node != null
		and _session_status_label_node != null
		and _mode_status_label_node != null
		and _session_duration_option_node != null
		and _multi_day_toggle_node != null
		and _add_note_toggle_node != null
		and _next_button_node != null
		and _update_buckets_button_node != null
		and _send_as_facilitator_toggle_node != null
		and _export_summary_button_node != null
		and _export_decision_record_button_node != null
		and _inject_stress_button_node != null
		and _action_status_label_node != null
	)


func refresh(ws: Dictionary, stage_title: String, remaining_sec: int) -> void:
	if _stage_label_node:
		_stage_label_node.text = "Stage: " + stage_title
	if _session_status_label_node:
		var timing_label: String = "scaled" if ws.get("uses_scaled_stage_timing", false) == true else "fixed"
		_session_status_label_node.text = "Session: %s | Timing: %s" % [
			String(ws.get("session_label", "Workshop")),
			timing_label,
		]
	if _session_duration_option_node:
		var duration_index: int = _find_duration_index(int(ws.get("session_duration_minutes", 120)))
		if duration_index >= 0:
			_session_duration_option_node.select(duration_index)
	if _multi_day_toggle_node:
		_multi_day_toggle_node.set_pressed_no_signal(ws.get("is_multi_day", false) == true)
	if _add_note_toggle_node:
		_add_note_toggle_node.set_pressed_no_signal(ws.get("is_note_only_next_input", false) == true)
	if _send_as_facilitator_toggle_node:
		_send_as_facilitator_toggle_node.set_pressed_no_signal(ws.get("send_as_facilitator", false) == true)
	if _mode_status_label_node:
		_mode_status_label_node.text = "Input Mode: " + _build_input_status_text(ws)
	if _inject_stress_button_node:
		_inject_stress_button_node.disabled = not stage_title.to_lower().begins_with("stress injection")
	update_time(ws, remaining_sec)


func update_time(ws: Dictionary, remaining_sec: int) -> void:
	if not _time_label_node:
		return
	var minutes_remaining: int = int(remaining_sec / 60)
	var seconds_remaining: int = int(remaining_sec % 60)
	var stage_status: String = String(ws.get("stage_status", "not_started")).strip_edges()
	_time_label_node.text = "Time (%s): %02d:%02d" % [
		stage_status,
		minutes_remaining,
		seconds_remaining,
	]


func set_next_stage_busy(button_text: String, is_disabled: bool) -> void:
	if _next_button_node:
		_next_button_node.text = button_text
		_next_button_node.disabled = is_disabled


func set_bucket_update_busy(is_busy: bool) -> void:
	if _update_buckets_button_node:
		_update_buckets_button_node.text = "Updating notes…" if is_busy else "Update Workshop Notes"
		_update_buckets_button_node.disabled = is_busy


func set_summary_export_busy(is_busy: bool) -> void:
	if _export_summary_button_node:
		_export_summary_button_node.text = "Exporting…" if is_busy else "Export Workshop Summary"
		_export_summary_button_node.disabled = is_busy


func set_decision_export_busy(is_busy: bool) -> void:
	if _export_decision_record_button_node:
		_export_decision_record_button_node.text = "Exporting…" if is_busy else "Export Decision Record"
		_export_decision_record_button_node.disabled = is_busy


func set_action_status(status_text: String) -> void:
	if _action_status_label_node:
		_action_status_label_node.text = status_text


func get_action_status() -> String:
	return _action_status_label_node.text if _action_status_label_node else ""


func get_control(control_name: StringName) -> Control:
	if not _content_node:
		return null
	return _content_node.find_child(String(control_name), true, false) as Control


func _mount_background(settings_container_node: VBoxContainer, background_node: TextureRect) -> void:
	if not background_node:
		return
	var settings_parent_node: Node = settings_container_node.get_parent()
	if not settings_parent_node:
		return
	var actual_panel_node: Control = settings_parent_node.get_parent() as Control
	if not actual_panel_node:
		actual_panel_node = settings_parent_node as Control
	if not actual_panel_node:
		return
	background_node.reparent(actual_panel_node)
	actual_panel_node.move_child(background_node, 0)


func _clear_scene_owners(root_node: Node) -> void:
	if not root_node:
		return
	root_node.owner = null
	for child_node: Node in root_node.get_children():
		_clear_scene_owners(child_node)


func _cache_controls() -> void:
	_stage_label_node = get_control(&"StageLabel") as Label
	_time_label_node = get_control(&"TimeLabel") as Label
	_session_status_label_node = get_control(&"SessionStatusLabel") as Label
	_mode_status_label_node = get_control(&"ModeStatusLabel") as Label
	_session_duration_option_node = get_control(&"SessionDurationOption") as OptionButton
	_multi_day_toggle_node = get_control(&"MultiDayToggle") as CheckButton
	_add_note_toggle_node = get_control(&"AddNoteToggle") as CheckButton
	_next_button_node = get_control(&"NextStageButton") as Button
	_update_buckets_button_node = get_control(&"UpdateBucketsButton") as Button
	_send_as_facilitator_toggle_node = get_control(&"SendAsFacilitatorToggle") as CheckButton
	_export_summary_button_node = get_control(&"ExportSummaryButton") as Button
	_export_decision_record_button_node = get_control(&"ExportDecisionRecordButton") as Button
	_inject_stress_button_node = get_control(&"InjectStressButton") as Button
	_action_status_label_node = get_control(&"ActionStatusLabel") as Label


func _populate_duration_options() -> void:
	if not _session_duration_option_node:
		return
	_session_duration_option_node.clear()
	for hour_value: int in [1, 2, 3, 4]:
		var label_text: String = "%d hour" % hour_value
		if hour_value != 1:
			label_text += "s"
		_session_duration_option_node.add_item(label_text)
		_session_duration_option_node.set_item_metadata(
			_session_duration_option_node.item_count - 1,
			hour_value * 60
		)


func _connect_controls() -> void:
	(get_control(&"StartButton") as Button).pressed.connect(start_requested.emit)
	(get_control(&"PauseButton") as Button).pressed.connect(pause_requested.emit)
	_next_button_node.pressed.connect(next_stage_requested.emit)
	(get_control(&"AddFiveMinutesButton") as Button).pressed.connect(
		func() -> void: add_time_requested.emit(5)
	)
	(get_control(&"AddTenMinutesButton") as Button).pressed.connect(
		func() -> void: add_time_requested.emit(10)
	)
	_add_note_toggle_node.toggled.connect(note_only_changed.emit)
	_send_as_facilitator_toggle_node.toggled.connect(facilitator_sender_changed.emit)
	_session_duration_option_node.item_selected.connect(_on_duration_selected)
	_multi_day_toggle_node.toggled.connect(multi_day_changed.emit)
	_update_buckets_button_node.pressed.connect(update_buckets_requested.emit)
	_export_summary_button_node.pressed.connect(export_summary_requested.emit)
	_export_decision_record_button_node.pressed.connect(export_decision_record_requested.emit)
	_inject_stress_button_node.pressed.connect(inject_stress_requested.emit)
	var commands_toggle_node: CheckButton = get_control(&"CommandsToggle") as CheckButton
	var commands_label_node: RichTextLabel = get_control(&"CommandsLabel") as RichTextLabel
	commands_toggle_node.toggled.connect(
		func(is_enabled: bool) -> void: commands_label_node.visible = is_enabled
	)


func _on_duration_selected(item_index: int) -> void:
	if not _session_duration_option_node:
		return
	var minutes_value: Variant = _session_duration_option_node.get_item_metadata(item_index)
	var session_minutes: int = int(minutes_value)
	if session_minutes > 0:
		duration_changed.emit(session_minutes)


func _find_duration_index(session_minutes: int) -> int:
	if not _session_duration_option_node:
		return -1
	for item_index: int in range(_session_duration_option_node.item_count):
		if int(_session_duration_option_node.get_item_metadata(item_index)) == session_minutes:
			return item_index
	return -1


func _build_input_status_text(ws: Dictionary) -> String:
	if ws.get("is_note_only_next_input", false) == true:
		return "next input note only"
	if ws.get("send_as_facilitator", false) == true:
		return "facilitator-visible"
	return "normal"
