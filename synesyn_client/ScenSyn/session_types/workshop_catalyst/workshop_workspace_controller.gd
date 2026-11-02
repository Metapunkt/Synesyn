extends RefCounted
class_name WorkshopWorkspaceController

## Binds the scene-authored Workshop shell to the pure preset model. This module
## owns layout preference persistence only; workshop meaning remains in StoryState.

signal end_and_save_requested

const PresetModelScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_preset_model.gd"
)
const TargetSurfacesControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_target_surfaces_controller.gd"
)
const SplitLayoutStateScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_split_layout_state.gd"
)
const ConversationLayoutStabilizerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_conversation_layout_stabilizer.gd"
)
const MapLayoutUtilsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_map_layout_utils.gd"
)
const SynesynUiTokensScript = preload(
	"res://ScenSyn/scripts/core/synesyn_ui_tokens.gd"
)
const LayoutDiagnosticsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_layout_diagnostics.gd"
)
const SpecialistTraceViewScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_specialist_trace_view.gd"
)
const PresetPresenterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_preset_presenter.gd"
)
const SafetyStatusScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_safety_status.gd"
)
const RegionMountScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_region_mount.gd"
)
const HowToTextScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_how_to_text.gd"
)

const CONFIG_PRESET_KEY := "workshop_workspace_preset"
const CONFIG_CUSTOM_KEY := "workshop_workspace_custom_panels"
const CONFIG_RAILS_KEY := "workshop_workspace_collapsed_rails"
const CONFIG_SPLITS_KEY := "workshop_workspace_split_offsets"
const CONFIG_INPUT_DOCK_KEY := "workshop_workspace_input_dock_visible"
const LAYOUT_WIDE := "wide"
const LAYOUT_MEDIUM := "medium"
const LAYOUT_NARROW := "narrow"

const PANEL_NODE_IDS: Dictionary = {
	"conversation": "ConversationAndDockSplit",
	"thinking_map": "ThinkingMapPanel",
	"ai_assistant": "AiAssistantPanel",
	"session_record": "SessionRecordPanel",
	# Presence strip only — never the whole SafetyBar (pulse + alerts must stay).
	"participants": "ParticipantsPanel",
	"session_menu": "SessionMenuPanel",
}

const TOGGLE_NODE_IDS: Dictionary = {
	"conversation": "ConversationToggle",
	"thinking_map": "ThinkingMapToggle",
	"ai_assistant": "AiAssistantToggle",
	"session_record": "SessionRecordToggle",
	"participants": "ParticipantsToggle",
	"session_menu": "SessionMenuToggle",
}

const SAFETY_ALWAYS_VISIBLE_IDS: Array[String] = [
	"EndAndSaveButton",
	"SafetyBar",
	"SessionRecordPulseLabel",
]

const SAFETY_NODE_IDS: Array[String] = [
	"SafetyBar",
	"SessionRecordPulseLabel",
	"ListeningStatusLabel",
	"MicrophoneStatusLabel",
	"ConsentStatusLabel",
	"EndAndSaveButton",
	"ConnectionErrorLabel",
	"TranscriptionErrorLabel",
	"UncommittedWarningLabel",
]

var _shell_root_node: Control
var _panels: Dictionary = {}
var _toggles: Dictionary = {}
var _active_preset_id: String = PresetModelScript.PRESET_FULL_DASHBOARD
var _custom_visibility: Dictionary = {}
var _desired_visibility: Dictionary = {}
var _is_applying_state: bool = false
var _responsive_layout_id: String = LAYOUT_WIDE
var _is_left_rail_collapsed: bool = false
var _is_right_rail_collapsed: bool = false
var _is_input_dock_visible: bool = true
var _open_narrow_drawer_id: String = ""
var _last_viewport_width: float = SynesynUiTokensScript.BREAKPOINT_WIDE
var _target_surfaces_controller: RefCounted
var _session_record_region_node: Control
var _split_layout_state: RefCounted
var _layout_diagnostics: RefCounted
var _specialist_trace_view: RefCounted
var _is_review_available: bool = true
var _has_evaluated_review_gate: bool = false


func mount(
	shell_root_node: Control,
	conversation_region_node: Control,
	session_record_region_node: Control,
	record_button_node: Button,
	consent_toggle_node: CheckButton = null
) -> bool:
	if not shell_root_node or not conversation_region_node or not session_record_region_node:
		return false
	_shell_root_node = shell_root_node
	if not _cache_required_nodes():
		return false
	_split_layout_state = SplitLayoutStateScript.new()
	if not _split_layout_state.mount(_shell_root_node):
		return false
	_split_layout_state.split_state_changed.connect(_persist_state)
	_layout_diagnostics = LayoutDiagnosticsScript.new()
	_layout_diagnostics.mount(_shell_root_node, Callable(self, "get_layout_snapshot"))
	if not _move_existing_regions(
		conversation_region_node,
		session_record_region_node,
		record_button_node
	):
		return false
	_connect_controls(record_button_node, consent_toggle_node)
	_target_surfaces_controller = TargetSurfacesControllerScript.new()
	if not _target_surfaces_controller.mount(_shell_root_node):
		return false
	_specialist_trace_view = SpecialistTraceViewScript.new()
	if not _specialist_trace_view.mount(_shell_root_node):
		return false
	_load_persisted_state()
	apply_preset(_active_preset_id, false)
	_connect_responsive_layout()
	_refresh_responsive_layout()
	_refresh_safety_status(record_button_node)
	_shell_root_node.visible = true
	return safety_controls_are_visible()


func update_responsive_layout(viewport_width: float) -> void:
	if not is_instance_valid(_shell_root_node):
		return
	_last_viewport_width = viewport_width
	if viewport_width >= SynesynUiTokensScript.BREAKPOINT_WIDE:
		_responsive_layout_id = LAYOUT_WIDE
	elif viewport_width >= SynesynUiTokensScript.BREAKPOINT_MEDIUM:
		_responsive_layout_id = LAYOUT_MEDIUM
	else:
		_responsive_layout_id = LAYOUT_NARROW
	var left_rail_node: Control = _find_control("SessionMenuPanel")
	var right_rail_node: Control = _find_control("RightRailContainer")
	var center_workspace_node: Control = _find_control("CenterWorkspace")
	var has_left_content: bool = _desired_visibility.get("session_menu", false) == true
	var has_right_content: bool = _right_rail_has_content()
	if (
		(_open_narrow_drawer_id == "left" and not has_left_content)
		or (_open_narrow_drawer_id == "right" and not has_right_content)
	):
		_open_narrow_drawer_id = ""
	if left_rail_node:
		left_rail_node.custom_minimum_size.x = (
			SynesynUiTokensScript.RAIL_LEFT_MEDIUM
			if _responsive_layout_id == LAYOUT_MEDIUM
			else SynesynUiTokensScript.RAIL_LEFT_WIDE
		)
	if right_rail_node:
		right_rail_node.custom_minimum_size.x = (
			SynesynUiTokensScript.RAIL_RIGHT_MEDIUM
			if _responsive_layout_id == LAYOUT_MEDIUM
			else SynesynUiTokensScript.RAIL_RIGHT_WIDE
		)
	if _responsive_layout_id == LAYOUT_NARROW:
		if center_workspace_node:
			center_workspace_node.visible = _open_narrow_drawer_id.is_empty()
		if left_rail_node:
			left_rail_node.visible = (
				_open_narrow_drawer_id == "left"
				and _desired_visibility.get("session_menu", false) == true
			)
			left_rail_node.custom_minimum_size.x = 0.0
		if right_rail_node:
			right_rail_node.visible = _open_narrow_drawer_id == "right" and _right_rail_has_content()
			right_rail_node.custom_minimum_size.x = 0.0
	else:
		if center_workspace_node:
			center_workspace_node.visible = true
		if left_rail_node:
			left_rail_node.visible = (
				_desired_visibility.get("session_menu", false) == true
				and not _is_left_rail_collapsed
			)
		if right_rail_node:
			right_rail_node.visible = _right_rail_has_content() and not _is_right_rail_collapsed
	if _split_layout_state:
		_split_layout_state.set_splitters_enabled(
			_responsive_layout_id != LAYOUT_NARROW
		)
		_split_layout_state.clamp_for_current_viewport()
		var conversation_panel_node: Control = _find_control("ConversationAndDockSplit")
		var thinking_map_panel_node: Control = _find_control("ThinkingMapPanel")
		var review_surface_node: Control = _find_control("CenterReviewSurface")
		var assistant_panel_node: Control = _find_control("AiAssistantPanel")
		var record_panel_node: Control = _find_control("SessionRecordPanel")
		_split_layout_state.apply_pane_visibility(
			left_rail_node != null and left_rail_node.visible,
			center_workspace_node != null and center_workspace_node.visible,
			right_rail_node != null and right_rail_node.visible,
			conversation_panel_node != null and conversation_panel_node.visible,
			(
				thinking_map_panel_node != null and thinking_map_panel_node.visible
			) or (review_surface_node != null and review_surface_node.visible),
			assistant_panel_node != null and assistant_panel_node.visible,
			record_panel_node != null and record_panel_node.visible,
			_is_input_dock_visible,
			_responsive_layout_id == LAYOUT_NARROW
		)
		_sync_input_dock_controls()
	MapLayoutUtilsScript.apply_responsive_map_columns(
		_shell_root_node,
		viewport_width,
		left_rail_node,
		right_rail_node,
		center_workspace_node
	)
	_sync_rail_toggles(left_rail_node, right_rail_node, has_right_content)
	call_deferred("_stabilize_conversation_layout")
	call_deferred("_request_header_banner_refit")
	if _layout_diagnostics:
		_layout_diagnostics.refresh()


func _stabilize_conversation_layout() -> void:
	ConversationLayoutStabilizerScript.stabilize(_shell_root_node)


func _request_header_banner_refit() -> void:
	MapLayoutUtilsScript.request_header_banner_refit(_shell_root_node)


func get_responsive_layout_id() -> String:
	return _responsive_layout_id


func get_open_narrow_drawer_id() -> String:
	return _open_narrow_drawer_id


func _sync_rail_toggles(
	left_rail_node: Control,
	right_rail_node: Control,
	has_right_content: bool
) -> void:
	var session_menu_toggle_node: CheckButton = (
		_toggles.get("session_menu") as CheckButton
	)
	var insights_toggle_node: CheckButton = (
		_find_control("InsightsToggle") as CheckButton
	)
	if session_menu_toggle_node:
		session_menu_toggle_node.set_pressed_no_signal(
			left_rail_node != null and left_rail_node.visible
		)
	if insights_toggle_node:
		insights_toggle_node.disabled = not has_right_content
		insights_toggle_node.set_pressed_no_signal(
			right_rail_node != null and right_rail_node.visible
		)


func _right_rail_has_content() -> bool:
	if _active_preset_id == PresetModelScript.PRESET_REVIEW:
		return _desired_visibility.get("ai_assistant", false) == true
	return (
		_desired_visibility.get("ai_assistant", false) == true
		or _desired_visibility.get("session_record", false) == true
	)


func _connect_responsive_layout() -> void:
	if not _shell_root_node.resized.is_connected(
		_refresh_responsive_layout
	):
		_shell_root_node.resized.connect(_refresh_responsive_layout)
	var viewport_node: Viewport = _shell_root_node.get_viewport()
	if (
		viewport_node
		and not viewport_node.size_changed.is_connected(
			_refresh_responsive_layout
		)
	):
		viewport_node.size_changed.connect(_refresh_responsive_layout)


func _refresh_responsive_layout() -> void:
	if not is_instance_valid(_shell_root_node):
		return
	var viewport_width: float = (
		_shell_root_node.get_viewport_rect().size.x
	)
	update_responsive_layout(viewport_width)


func apply_preset(preset_id: String, should_persist: bool = true) -> void:
	_active_preset_id = PresetModelScript.sanitize_preset_id(preset_id)
	var panel_visibility: Dictionary = PresetModelScript.visibility_for_preset(
		_active_preset_id,
		_custom_visibility
	)
	_apply_visibility(panel_visibility)
	_apply_preset_composition()
	_update_active_preset_label()
	_update_preset_button_variations()
	_refresh_responsive_layout()
	if should_persist:
		_persist_state()


func set_panel_visible(
	group_id: String,
	is_panel_visible: bool,
	should_persist: bool = true
) -> void:
	if group_id not in PresetModelScript.GROUP_IDS:
		return
	var current_visibility: Dictionary = get_panel_visibility()
	_custom_visibility = PresetModelScript.with_manual_toggle(
		current_visibility,
		group_id,
		is_panel_visible
	)
	_active_preset_id = PresetModelScript.PRESET_CUSTOM
	_apply_visibility(_custom_visibility)
	_apply_preset_composition()
	_update_active_preset_label()
	_update_preset_button_variations()
	update_responsive_layout(_last_viewport_width)
	if should_persist:
		_persist_state()


func get_active_preset_id() -> String:
	return _active_preset_id


## Gates entry to Review on the precondition Compare Paths actually has (see
## `workshop_review_gate.gd`). Entry only: a facilitator already working in Review
## is never ejected, because paths that have been proposed remain valid work even if
## the decision behind them is later withdrawn.
func set_review_available(is_review_available: bool) -> void:
	_is_review_available = is_review_available
	PresetPresenterScript.apply_review_availability(_shell_root_node, is_review_available)
	# A session can be restored pointing at Review with the precondition no longer
	# met, which would strand it behind its own disabled button. Correct that once,
	# on the first evaluation, before any live choice exists to override.
	var is_first_evaluation: bool = not _has_evaluated_review_gate
	_has_evaluated_review_gate = true
	if (
		is_first_evaluation
		and not is_review_available
		and _active_preset_id == PresetModelScript.PRESET_REVIEW
	):
		apply_preset(PresetModelScript.PRESET_FULL_DASHBOARD)


func restore_persisted_state(scensyn_cfg: Dictionary) -> void:
	_active_preset_id = PresetModelScript.sanitize_preset_id(
		String(scensyn_cfg.get(CONFIG_PRESET_KEY, PresetModelScript.PRESET_FULL_DASHBOARD))
	)
	var custom_any: Variant = scensyn_cfg.get(CONFIG_CUSTOM_KEY, {})
	var custom_candidate: Dictionary = custom_any if typeof(custom_any) == TYPE_DICTIONARY else {}
	_custom_visibility = PresetModelScript.sanitize_visibility(custom_candidate)
	var rails_any: Variant = scensyn_cfg.get(CONFIG_RAILS_KEY, {})
	var rails_state: Dictionary = rails_any if typeof(rails_any) == TYPE_DICTIONARY else {}
	_is_left_rail_collapsed = rails_state.get("left", false) == true
	_is_right_rail_collapsed = rails_state.get("right", false) == true
	_is_input_dock_visible = scensyn_cfg.get(CONFIG_INPUT_DOCK_KEY, true) != false
	if _split_layout_state:
		_split_layout_state.restore_state(scensyn_cfg.get(CONFIG_SPLITS_KEY, {}))
	if _shell_root_node:
		apply_preset(_active_preset_id, false)


func get_persisted_state() -> Dictionary:
	return {
		CONFIG_PRESET_KEY: _active_preset_id,
		CONFIG_CUSTOM_KEY: _custom_visibility.duplicate(true),
		CONFIG_RAILS_KEY: {
			"left": _is_left_rail_collapsed,
			"right": _is_right_rail_collapsed,
		},
		CONFIG_SPLITS_KEY: (
			_split_layout_state.get_state() if _split_layout_state else {}
		),
		CONFIG_INPUT_DOCK_KEY: _is_input_dock_visible,
	}


func get_panel_visibility() -> Dictionary:
	var panel_visibility: Dictionary = {}
	for group_id: String in PresetModelScript.GROUP_IDS:
		var panel_node: Control = _panels.get(group_id) as Control
		panel_visibility[group_id] = panel_node != null and panel_node.visible
	return panel_visibility


func get_control(control_id: String) -> Control:
	return _find_control(control_id)


func set_conversation_overlay(overlay_id: String, is_visible: bool) -> bool:
	var control_id_by_overlay: Dictionary = {
		"transcript_preview": "TranscriptPreviewPanel",
		"transcript_correction": "TranscriptCorrectionPanel",
	}
	if overlay_id not in control_id_by_overlay:
		return false
	var overlay_node: Control = _find_control(
		String(control_id_by_overlay[overlay_id])
	)
	if not overlay_node:
		return false
	overlay_node.visible = is_visible
	ConversationLayoutStabilizerScript.sync_overlay_scroll(
		_shell_root_node, control_id_by_overlay.values()
	)
	call_deferred("_stabilize_conversation_layout")
	if _layout_diagnostics:
		_layout_diagnostics.refresh()
	return true


func get_layout_snapshot() -> Dictionary:
	return {
		"layout_id": _responsive_layout_id,
		"viewport_width": _last_viewport_width,
		"drawer_id": (
			_open_narrow_drawer_id
			if not _open_narrow_drawer_id.is_empty()
			else "none"
		),
		"split_offsets": (
			_split_layout_state.get_state() if _split_layout_state else {}
		),
		"controls": (
			_layout_diagnostics.collect_controls()
			if _layout_diagnostics
			else []
		),
	}


func get_target_surfaces_controller() -> RefCounted:
	return _target_surfaces_controller


func set_split_offset(split_id: String, requested_offset: int) -> void:
	if _split_layout_state:
		_split_layout_state.set_split_offset(split_id, requested_offset)


func get_split_offset(split_id: String) -> int:
	return (
		_split_layout_state.get_split_offset(split_id)
		if _split_layout_state
		else 0
	)


func reset_panel_sizes() -> void:
	if _split_layout_state:
		_split_layout_state.reset_to_defaults()


func safety_controls_are_visible() -> bool:
	if not _shell_root_node or not _shell_root_node.visible:
		return false
	for control_id: String in SAFETY_ALWAYS_VISIBLE_IDS:
		var safety_node: CanvasItem = _shell_root_node.find_child(control_id, true, false) as CanvasItem
		if not safety_node or not safety_node.visible:
			return false
	return true


func set_end_save_status(status_text: String, has_uncommitted_changes: bool = false) -> void:
	SafetyStatusScript.set_end_save_status(
		Callable(self, "_find_control"),
		status_text,
		has_uncommitted_changes
	)


func set_session_record_pulse(pulse_text: String) -> void:
	SafetyStatusScript.set_session_record_pulse(
		_shell_root_node,
		Callable(self, "_find_control"),
		pulse_text
	)


func set_how_to_text(scenario_how_to_text: String) -> void:
	var content_label_node: RichTextLabel = _find_control("HowToContentLabel") as RichTextLabel
	if not content_label_node:
		return
	var trimmed_scenario_text: String = scenario_how_to_text.strip_edges()
	var full_text: String = HowToTextScript.BASE_TEXT
	if not trimmed_scenario_text.is_empty():
		full_text += "\n\n[b]This scenario's guidance[/b]\n" + trimmed_scenario_text
	content_label_node.text = full_text


func _cache_required_nodes() -> bool:
	for group_id: String in PresetModelScript.GROUP_IDS:
		var panel_node: Control = _find_control(String(PANEL_NODE_IDS[group_id]))
		var toggle_node: CheckButton = _find_control(String(TOGGLE_NODE_IDS[group_id])) as CheckButton
		if not panel_node or not toggle_node:
			return false
		_panels[group_id] = panel_node
		_toggles[group_id] = toggle_node
	for safety_id: String in SAFETY_NODE_IDS:
		if not _find_control(safety_id):
			return false
	return (
		_find_control("ConversationContentSlot") != null
		and _find_control("ConversationTranscriptScroll") != null
		and _find_control("ConversationTextInputSlot") != null
		and _find_control("ConversationInputActionsSlot") != null
		and _find_control("ConversationAndDockSplit") != null
		and _find_control("ConversationInputToggle") != null
		and _find_control("SessionRecordContentSlot") != null
		and _find_control("SessionRecordScroll") != null
		and _find_control("CenterSessionRecordSlot") != null
		and _find_control("CenterReviewSurface") != null
		and _find_control("ReviewScroll") != null
		and _find_control("HowToSurface") != null
		and _find_control("HowToContentLabel") != null
		and _find_control("LeftRailScroll") != null
		and _find_control("AiAssistantScroll") != null
		and _find_control("RightRailContainer") != null
		and _find_control("ActivePresetLabel") != null
		and _find_control("InsightsToggle") != null
	)


func _move_existing_regions(
	conversation_region_node: Control,
	session_record_region_node: Control,
	record_button_node: Button
) -> bool:
	_session_record_region_node = session_record_region_node
	return RegionMountScript.move_existing_regions(
		_shell_root_node,
		conversation_region_node,
		session_record_region_node,
		record_button_node
	)


func _normalize_reparented_region(region_node: Control) -> void:
	RegionMountScript.normalize_reparented_region(region_node)


func _connect_controls(
	record_button_node: Button,
	consent_toggle_node: CheckButton
) -> void:
	for button_id: String in PresetPresenterScript.PRESET_BUTTONS:
		var preset_button_node: Button = _find_control(button_id) as Button
		if preset_button_node:
			preset_button_node.pressed.connect(
				_on_preset_requested.bind(
					String(PresetPresenterScript.PRESET_BUTTONS[button_id])
				)
			)
	var custom_panel_button_node: Button = (
		_find_control("CustomPresetButton") as Button
	)
	if custom_panel_button_node:
		custom_panel_button_node.pressed.connect(_toggle_custom_panel_popup)
	for group_id: String in PresetModelScript.GROUP_IDS:
		var toggle_node: CheckButton = _toggles[group_id] as CheckButton
		toggle_node.toggled.connect(_on_panel_toggled.bind(group_id))
	var end_button_node: Button = _find_control("EndAndSaveButton") as Button
	end_button_node.pressed.connect(end_and_save_requested.emit)
	var reset_sizes_button_node: Button = _find_control("ResetPanelSizesButton") as Button
	if reset_sizes_button_node:
		reset_sizes_button_node.pressed.connect(reset_panel_sizes)
	var insights_toggle_node: CheckButton = (
		_find_control("InsightsToggle") as CheckButton
	)
	if insights_toggle_node:
		insights_toggle_node.toggled.connect(_on_insights_toggled)
	var input_dock_toggle_node: CheckButton = (
		_find_control("ConversationInputToggle") as CheckButton
	)
	if input_dock_toggle_node:
		input_dock_toggle_node.toggled.connect(_on_input_dock_toggled)
	var talk_entry_node: Button = _find_control("NewConversationButton") as Button
	if talk_entry_node:
		talk_entry_node.pressed.connect(_on_preset_requested.bind("talk"))
	var insights_button_node: Button = _find_control("InsightsButton") as Button
	if insights_button_node:
		insights_button_node.pressed.connect(_on_insights_button_pressed)
	var settings_button_node: Button = _find_control("SettingsButton") as Button
	if settings_button_node:
		settings_button_node.pressed.connect(_on_settings_button_pressed)
	if record_button_node:
		record_button_node.toggled.connect(_on_record_button_toggled)
	if consent_toggle_node:
		consent_toggle_node.toggled.connect(_on_consent_toggled)
	var voice_service_node: Node = _get_voice_service()
	if voice_service_node:
		var transcription_callable := Callable(self, "_on_transcription_completed")
		var error_callable := Callable(self, "_on_voice_service_error")
		var ready_callable := Callable(self, "_on_voice_service_ready")
		if not voice_service_node.is_connected("transcription_completed", transcription_callable):
			voice_service_node.connect("transcription_completed", transcription_callable)
		if not voice_service_node.is_connected("voice_service_error", error_callable):
			voice_service_node.connect("voice_service_error", error_callable)
		if not voice_service_node.is_connected("voice_service_ready", ready_callable):
			voice_service_node.connect("voice_service_ready", ready_callable)


func _load_persisted_state() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	var apps: Dictionary = apps_any if typeof(apps_any) == TYPE_DICTIONARY else {}
	var scensyn_any: Variant = apps.get("scensyn", {})
	var scensyn_cfg: Dictionary = (
		scensyn_any if typeof(scensyn_any) == TYPE_DICTIONARY else {}
	)
	restore_persisted_state(scensyn_cfg)


func _persist_state() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	var apps: Dictionary = apps_any if typeof(apps_any) == TYPE_DICTIONARY else {}
	var scensyn_any: Variant = apps.get("scensyn", {})
	var scensyn_cfg: Dictionary = (
		scensyn_any.duplicate(true) if typeof(scensyn_any) == TYPE_DICTIONARY else {}
	)
	scensyn_cfg[CONFIG_PRESET_KEY] = _active_preset_id
	scensyn_cfg[CONFIG_CUSTOM_KEY] = _custom_visibility.duplicate(true)
	scensyn_cfg[CONFIG_RAILS_KEY] = {
		"left": _is_left_rail_collapsed,
		"right": _is_right_rail_collapsed,
	}
	scensyn_cfg[CONFIG_SPLITS_KEY] = (
		_split_layout_state.get_state() if _split_layout_state else {}
	)
	scensyn_cfg[CONFIG_INPUT_DOCK_KEY] = _is_input_dock_visible
	apps["scensyn"] = scensyn_cfg
	cfg["apps"] = apps
	if not RuntimeConfig.save_config(cfg):
		set_end_save_status("Layout preference could not be saved.", true)


func _apply_visibility(panel_visibility: Dictionary) -> void:
	_is_applying_state = true
	_desired_visibility = PresetModelScript.sanitize_visibility(panel_visibility)
	for group_id: String in PresetModelScript.GROUP_IDS:
		var is_panel_visible: bool = _desired_visibility.get(group_id, false) == true
		var panel_node: Control = _panels[group_id] as Control
		var toggle_node: CheckButton = _toggles[group_id] as CheckButton
		panel_node.visible = is_panel_visible
		toggle_node.set_pressed_no_signal(is_panel_visible)
	SafetyStatusScript.ensure_footer_visible(Callable(self, "_find_control"))
	_sync_input_dock_controls()
	_is_applying_state = false


func _sync_input_dock_controls() -> void:
	ConversationLayoutStabilizerScript.sync_input_dock_controls(
		_shell_root_node,
		_desired_visibility.get("conversation", false) == true,
		_is_input_dock_visible
	)


func _apply_preset_composition() -> void:
	var is_review_preset: bool = (
		_active_preset_id == PresetModelScript.PRESET_REVIEW
	)
	var is_how_to_preset: bool = (
		_active_preset_id == PresetModelScript.PRESET_HOW_TO
	)
	var review_surface_node: Control = _find_control("CenterReviewSurface")
	var compare_paths_node: Control = _find_control("WorkshopComparePaths")
	var how_to_surface_node: Control = _find_control("HowToSurface")
	var right_record_panel_node: Control = _find_control("SessionRecordPanel")
	var destination_slot_node: VBoxContainer
	if is_review_preset:
		destination_slot_node = _find_control("CenterSessionRecordSlot") as VBoxContainer
	else:
		destination_slot_node = _find_control("SessionRecordContentSlot") as VBoxContainer
	if (
		is_instance_valid(_session_record_region_node)
		and destination_slot_node
		and _session_record_region_node.get_parent() != destination_slot_node
	):
		_session_record_region_node.reparent(destination_slot_node)
		_normalize_reparented_region(_session_record_region_node)
	if review_surface_node:
		review_surface_node.visible = is_review_preset
	if compare_paths_node:
		compare_paths_node.visible = is_review_preset
	if how_to_surface_node:
		how_to_surface_node.visible = is_how_to_preset
	if right_record_panel_node:
		right_record_panel_node.visible = (
			not is_review_preset
			and _desired_visibility.get("session_record", false) == true
		)


func _update_active_preset_label() -> void:
	PresetPresenterScript.apply_active_label(_shell_root_node, _active_preset_id)


func _update_preset_button_variations() -> void:
	PresetPresenterScript.apply_button_variations(_shell_root_node, _active_preset_id)


func _refresh_safety_status(record_button_node: Button) -> void:
	SafetyStatusScript.refresh_idle_state(
		Callable(self, "_find_control"),
		record_button_node,
		_get_voice_service()
	)


func _on_preset_requested(preset_id: String) -> void:
	apply_preset(preset_id)


func _toggle_custom_panel_popup() -> void:
	if not is_instance_valid(_shell_root_node):
		return
	var popup_node: Control = _find_control("CustomPanelPopup")
	if not popup_node:
		return
	var should_show: bool = not popup_node.visible
	if should_show:
		var button_node: Control = _find_control("CustomPresetButton")
		if button_node:
			popup_node.reset_size()
			popup_node.global_position = (
				button_node.get_global_rect().position
				+ Vector2(0.0, button_node.size.y + 4.0)
			)
	popup_node.visible = should_show


func _on_insights_toggled(is_pressed: bool) -> void:
	if _is_applying_state:
		return
	_is_right_rail_collapsed = not is_pressed
	if _responsive_layout_id == LAYOUT_NARROW:
		_open_narrow_drawer_id = (
			"right" if is_pressed else ""
		)
	update_responsive_layout(_last_viewport_width)
	_persist_state()


## Session Menu's "Insights" button: a plain-language shortcut for the same
## show/hide toggle as the Custom panel's InsightsToggle CheckButton (the
## Insights rail holds the AI Assistant panel and Session Record). Reuses
## _on_insights_toggled() rather than duplicating the rail/drawer logic, and
## keeps InsightsToggle's pressed state in sync so the two controls never
## disagree about whether the rail is open.
func _on_insights_button_pressed() -> void:
	var will_be_open: bool = _is_right_rail_collapsed
	var insights_toggle_node: CheckButton = _find_control("InsightsToggle") as CheckButton
	if insights_toggle_node:
		insights_toggle_node.set_pressed_no_signal(will_be_open)
	_on_insights_toggled(will_be_open)


## Session Menu's "Settings" button: opens the same hamburger (☰) settings
## drawer that already hosts the live Workshop Catalyst controls (stage
## timer, Next Stage, notes, exports, Inject Stress, facilitator command
## reference) — there is no separate Workshop settings surface to build.
## The workspace controller is a RefCounted with no scene-tree access of its
## own, so it reaches the mounted game_session.gd instance the same way
## workshop_catalyst_controller_utils.gd::find_current_session_id() does: via
## the "game_session" group, not a direct node reference.
func _on_settings_button_pressed() -> void:
	if not is_instance_valid(_shell_root_node):
		return
	var scene_tree: SceneTree = _shell_root_node.get_tree()
	if not scene_tree:
		return
	var game_session_node: Node = scene_tree.get_first_node_in_group("game_session")
	if game_session_node and game_session_node.has_method("_on_hamburger_menu_pressed"):
		game_session_node.call("_on_hamburger_menu_pressed")


func _on_input_dock_toggled(is_pressed: bool) -> void:
	if _is_applying_state:
		return
	_is_input_dock_visible = is_pressed
	update_responsive_layout(_last_viewport_width)
	_persist_state()


func _on_panel_toggled(is_pressed: bool, group_id: String) -> void:
	if _is_applying_state:
		return
	if group_id == "session_menu":
		_is_left_rail_collapsed = false
		if _responsive_layout_id == LAYOUT_NARROW:
			_open_narrow_drawer_id = "left" if is_pressed else ""
	set_panel_visible(group_id, is_pressed)


func _on_record_button_toggled(is_pressed: bool) -> void:
	SafetyStatusScript.set_attention_label(
		_find_control("ListeningStatusLabel") as Label,
		"Listening…" if is_pressed else "Transcribing…",
		true
	)


func _on_consent_toggled(is_enabled: bool) -> void:
	SafetyStatusScript.set_attention_label(
		_find_control("ConsentStatusLabel") as Label,
		"Saving audio",
		is_enabled
	)


func _on_reasoning_toggled(is_expanded: bool) -> void:
	if _specialist_trace_view:
		_specialist_trace_view.set_expanded(is_expanded)


func _on_specialist_trace_updated(trace: Dictionary) -> void:
	if _specialist_trace_view:
		_specialist_trace_view.set_trace(trace)


func _on_transcription_completed(_text: String, error_text: String) -> void:
	var trimmed_error: String = error_text.strip_edges()
	SafetyStatusScript.set_attention_label(
		_find_control("ListeningStatusLabel") as Label,
		"",
		false
	)
	SafetyStatusScript.set_attention_label(
		_find_control("TranscriptionErrorLabel") as Label,
		"Transcription: " + trimmed_error,
		not trimmed_error.is_empty()
	)


func _on_voice_service_error(error_text: String) -> void:
	var trimmed_error: String = error_text.strip_edges()
	SafetyStatusScript.set_attention_label(
		_find_control("ConnectionErrorLabel") as Label,
		"Connection: " + trimmed_error,
		not trimmed_error.is_empty()
	)


func _on_voice_service_ready() -> void:
	SafetyStatusScript.set_attention_label(
		_find_control("ConnectionErrorLabel") as Label,
		"",
		false
	)


func _get_voice_service() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("VoiceService") if tree else null


func _find_control(control_id: String) -> Control:
	if not _shell_root_node:
		return null
	return _shell_root_node.find_child(control_id, true, false) as Control
