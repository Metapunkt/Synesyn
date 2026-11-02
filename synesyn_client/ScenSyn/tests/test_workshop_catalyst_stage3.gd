extends SceneTree

const SettingsBindingScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_settings_binding.gd"
)
const TimingScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_timing.gd"
)

var _failures: Array[String] = []
var _requested_actions: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_module_ownership()
	_test_defaults_and_timing_persistence()
	await _test_scene_structure_and_binding()
	_finish()


func _test_module_ownership() -> void:
	var script_paths: Array[String] = [
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_controller.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_settings_binding.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_timing.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_export_utils.gd",
	]
	for script_path: String in script_paths:
		var parsed_script: GDScript = load(script_path) as GDScript
		_expect(parsed_script != null, "Script did not parse: " + script_path)
		var source_text: String = FileAccess.get_file_as_string(script_path)
		_expect(
			source_text.count("\n") + 1 <= 900,
			"Stage 3 script exceeds 900 lines: " + script_path
		)
	var controller_source: String = FileAccess.get_file_as_string(script_paths[0])
	_expect(
		controller_source.contains("WorkshopCatalystSettingsBindingScript")
		and controller_source.contains("WorkshopCatalystTimingScript"),
		"Main controller does not delegate settings and timing ownership"
	)
	for static_ui_constructor: String in [
		"Label.new()",
		"Button.new()",
		"CheckButton.new()",
		"OptionButton.new()",
		"TextureRect.new()",
		"VBoxContainer.new()",
		"HBoxContainer.new()",
	]:
		_expect(
			not controller_source.contains(static_ui_constructor),
			"Main controller still builds static UI: " + static_ui_constructor
		)


func _test_defaults_and_timing_persistence() -> void:
	var scenario: Dictionary = {
		"time_model": {
			"default_session_duration_hours": "3",
			"default_multi_day": "true",
			"stage_timing_mode": "scalable",
		},
		"workshop_agenda_text": JSON.stringify([
			{
				"day": 1,
				"stages": [
					{"name": "Frame", "duration": 3600},
					{"name": "Decide", "duration": 3600},
				],
			},
		]),
	}
	var normalized: Dictionary = TimingScript.normalize_state(
		{"existing_setting": "preserved"},
		scenario
	)
	_expect(
		normalized.get("session_duration_minutes", 0) == 180,
		"Scenario duration default was not preserved"
	)
	_expect(
		normalized.get("is_multi_day", false) == true,
		"Scenario multi-day default was not preserved"
	)
	_expect(
		normalized.get("existing_setting", "") == "preserved",
		"Normalization discarded existing persisted state"
	)
	var agenda_value: Variant = normalized.get("agenda", [])
	var agenda: Array = agenda_value if typeof(agenda_value) == TYPE_ARRAY else []
	var first_day: Dictionary = agenda[0] if not agenda.is_empty() else {}
	var stages_value: Variant = first_day.get("stages", [])
	var stages: Array = stages_value if typeof(stages_value) == TYPE_ARRAY else []
	_expect(
		stages.size() == 2
		and int(stages[0].get("duration", 0)) == 5400
		and int(stages[1].get("duration", 0)) == 5400,
		"Scalable agenda timing no longer matches the selected duration"
	)
	_expect(
		TimingScript.get_int_setting(null, 7) == 7
		and TimingScript.get_bool_setting(null, true) == true,
		"Null timing settings did not use safe fallback values"
	)


func _test_scene_structure_and_binding() -> void:
	var panel_node := PanelContainer.new()
	var outer_box_node := VBoxContainer.new()
	var settings_container_node := VBoxContainer.new()
	root.add_child(panel_node)
	panel_node.add_child(outer_box_node)
	outer_box_node.add_child(settings_container_node)

	var binding: WorkshopCatalystSettingsBinding = SettingsBindingScript.new()
	_expect(binding.mount(settings_container_node), "Settings scene failed to mount")
	_expect(binding.has_required_controls(), "Settings binding missed required controls")
	_connect_action_probes(binding)

	var expected_controls: Array[String] = [
		"StartButton",
		"PauseButton",
		"NextStageButton",
		"AddFiveMinutesButton",
		"AddTenMinutesButton",
		"AddNoteToggle",
		"UpdateBucketsButton",
		"ExportSummaryButton",
		"ExportDecisionRecordButton",
		"InjectStressButton",
		"CommandsToggle",
		"SendAsFacilitatorToggle",
		"SessionDurationOption",
		"MultiDayToggle",
	]
	for control_id: String in expected_controls:
		_expect(binding.get_control(control_id) != null, "Missing scene control: " + control_id)
	for button_id: String in [
		"StartButton",
		"PauseButton",
		"NextStageButton",
		"AddFiveMinutesButton",
		"AddTenMinutesButton",
		"UpdateBucketsButton",
		"ExportSummaryButton",
		"ExportDecisionRecordButton",
		"InjectStressButton",
	]:
		var action_button_node: Button = binding.get_control(button_id) as Button
		_expect(
			not action_button_node.pressed.get_connections().is_empty(),
			"Visible button has no action binding: " + button_id
		)
	for toggle_id: String in [
		"AddNoteToggle",
		"CommandsToggle",
		"SendAsFacilitatorToggle",
		"MultiDayToggle",
	]:
		var action_toggle_node: CheckButton = binding.get_control(toggle_id) as CheckButton
		_expect(
			not action_toggle_node.toggled.get_connections().is_empty(),
			"Visible toggle has no action binding: " + toggle_id
		)
	var duration_option_node: OptionButton = binding.get_control(&"SessionDurationOption") as OptionButton
	_expect(
		not duration_option_node.item_selected.get_connections().is_empty(),
		"Duration option has no persistence binding"
	)

	var note_toggle_node: CheckButton = binding.get_control(&"AddNoteToggle") as CheckButton
	var facilitator_toggle_node: CheckButton = binding.get_control(&"SendAsFacilitatorToggle") as CheckButton
	var stress_button_node: Button = binding.get_control(&"InjectStressButton") as Button
	_expect(
		note_toggle_node.tooltip_text.begins_with("Next message will be saved"),
		"Note-only tooltip changed or disappeared"
	)
	_expect(
		facilitator_toggle_node.tooltip_text.contains("human runtime identity"),
		"Facilitator sender tooltip changed or disappeared"
	)
	_expect(stress_button_node.disabled, "Stress action is not clearly disabled by default")

	(binding.get_control(&"StartButton") as Button).pressed.emit()
	(binding.get_control(&"PauseButton") as Button).pressed.emit()
	(binding.get_control(&"AddFiveMinutesButton") as Button).pressed.emit()
	note_toggle_node.toggled.emit(true)
	facilitator_toggle_node.toggled.emit(true)
	_expect(_requested_actions.has("start"), "Start action is not bound")
	_expect(_requested_actions.has("pause"), "Pause action is not bound")
	_expect(_requested_actions.has("add:5"), "Add-time action is not bound")
	_expect(_requested_actions.has("note:true"), "Note-only persistence action is not bound")
	_expect(
		_requested_actions.has("facilitator:true"),
		"Facilitator sender persistence action is not bound"
	)

	var persisted_state: Dictionary = {
		"session_duration_minutes": 120,
		"is_multi_day": true,
		"is_note_only_next_input": true,
		"send_as_facilitator": true,
		"uses_scaled_stage_timing": false,
		"session_label": "2-hour session (multi-day)",
		"stage_status": "paused",
	}
	binding.refresh(persisted_state, "Stress Injection A", 305)
	_expect(note_toggle_node.button_pressed, "Persisted note-only state was not restored")
	_expect(
		facilitator_toggle_node.button_pressed,
		"Persisted facilitator sender state was not restored"
	)
	_expect(not stress_button_node.disabled, "Stress action did not enable for its valid stage")
	var time_label_node: Label = binding.get_control(&"TimeLabel") as Label
	_expect(time_label_node.text == "Time (paused): 05:05", "Timer display binding changed")

	panel_node.queue_free()
	await process_frame


func _connect_action_probes(binding: WorkshopCatalystSettingsBinding) -> void:
	binding.start_requested.connect(func() -> void: _requested_actions.append("start"))
	binding.pause_requested.connect(func() -> void: _requested_actions.append("pause"))
	binding.add_time_requested.connect(
		func(minutes: int) -> void: _requested_actions.append("add:%d" % minutes)
	)
	binding.note_only_changed.connect(
		func(is_enabled: bool) -> void: _requested_actions.append("note:%s" % is_enabled)
	)
	binding.facilitator_sender_changed.connect(
		func(is_enabled: bool) -> void:
			_requested_actions.append("facilitator:%s" % is_enabled)
	)


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst Stage 3 tests: all passed")
		quit(0)
		return
	for failure_message: String in _failures:
		push_error(failure_message)
	quit(1)
