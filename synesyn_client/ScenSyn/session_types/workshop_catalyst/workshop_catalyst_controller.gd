extends Node
class_name WorkshopCatalystController
const WS_KEY := "workshop_catalyst"
const WorkshopCatalystExportUtilsScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_export_utils.gd")
const WorkshopCatalystSettingsBindingScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_settings_binding.gd")
const WorkshopCatalystTimingScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_timing.gd")
const WorkshopWorkspaceControllerScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_controller.gd")
const WorkshopTranscriptControllerScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_transcript_controller.gd")
const WorkshopSessionRecordStoreScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_store.gd")
const ReviewGateScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_review_gate.gd")
const WorkshopSessionRecordProposalEngineScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_proposal_engine.gd")
const WorkshopSessionRecordPanelControllerScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_panel_controller.gd")
const WorkshopSummaryPersistenceCoordinatorScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_summary_persistence_coordinator.gd")
const WorkshopThinkingMapControllerScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map_controller.gd")
const WorkshopComparePathsMountScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_compare_paths_mount.gd")
const ControllerUtilsScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_controller_utils.gd")
const WorkshopAssistPassesScript = preload("res://ScenSyn/session_types/workshop_catalyst/workshop_assist_passes.gd")

var _is_processing := false

var _timer_node: Timer
var _remaining_sec: int = 0
var _is_running := false

var _settings_binding: WorkshopCatalystSettingsBinding
var _workspace_controller: RefCounted
var _transcript_controller: Node
var _story_log_system_node: Control
var _presence_controller: RefCounted

var _session_record_panel_node: Control
var _record_store: RefCounted
var _record_proposal_engine: RefCounted
var _record_panel_controller: RefCounted
var _summary_persistence: Node
var _thinking_map_controller: RefCounted
var _compare_paths_controller: RefCounted

var _session_record: WorkshopCatalystSessionRecord
var _last_session_record_pulse: String = ""
var _session_warned_minutes: Array = []
var _last_proactive_log_index: int = -1  # Prevents timer ticks from inflating stage turn count
var _session_auto_opened: bool = false   # True once the "Session open" post has been made
var _mgr_wired: bool = false             # True once session_record has been wired to the metaprompt manager
var _last_synced_workshop_fingerprint: String = ""

func initialize(
	settings_container_node: VBoxContainer,
	session_record_panel: Control = null
) -> void:
	_session_record = WorkshopCatalystSessionRecord.new()
	_session_record_panel_node = session_record_panel
	_settings_binding = WorkshopCatalystSettingsBindingScript.new()
	if not _settings_binding.mount(settings_container_node):
		push_error("WorkshopCatalystController: Settings panel failed to mount.")
		return
	_connect_settings_binding()
	_ensure_workshop_state_initialized()
	_mount_workspace()
	_timer_node = Timer.new()
	_timer_node.one_shot = false
	_timer_node.wait_time = 1.0
	_timer_node.timeout.connect(_on_timer_tick)
	add_child(_timer_node)
	_mount_session_record_review()
	_refresh_ui_from_state()
	_connect_story_state()
	var mgr = Global.get_metaprompt_manager() if Global else null
	if mgr and mgr.has_method("set_session_record"):
		mgr.set_session_record(_session_record)

func _mount_workspace() -> void:
	var session_root_node: Node = get_parent()
	var workspace_shell_node: Control = (
		session_root_node.get_node_or_null("%WorkshopWorkspaceShell") as Control
	)
	var conversation_region_node: Control = (
		session_root_node.get_node_or_null("%TabContainer") as Control
	)
	var record_button_node: Button = session_root_node.get_node_or_null("%RecordButton") as Button
	var consent_toggle_node: CheckButton = (
		session_root_node.get_node_or_null("%SaveRecordingsToggle") as CheckButton
	)
	_story_log_system_node = session_root_node.get_node_or_null("%StoryLogSystem") as Control
	var session_record_region_node: Control = (
		session_root_node.get_node_or_null("%Session Record") as Control
	)
	if not workspace_shell_node:
		push_error("WorkshopCatalystController: Workspace shell is unavailable.")
		return
	_workspace_controller = WorkshopWorkspaceControllerScript.new()
	_workspace_controller.end_and_save_requested.connect(_on_end_and_save_requested)
	if not _workspace_controller.mount(
		workspace_shell_node,
		conversation_region_node,
		session_record_region_node,
		record_button_node,
		consent_toggle_node
	):
		push_error("WorkshopCatalystController: Workspace shell failed to mount safely.")
		return
	var scenario_for_how_to: Dictionary = Global.get_current_scenario() if Global else {}
	_workspace_controller.set_how_to_text(String(scenario_for_how_to.get("how_to_text", "")))
	_presence_controller = ControllerUtilsScript.mount_presence_controller(
		workspace_shell_node, Callable(self, "_on_facilitator_authority_changed")
	)
	var voice_bridge_node: Node = session_root_node.get_node_or_null("VoiceBridge")
	if voice_bridge_node and voice_bridge_node.has_method("set_voice_enabled_for_character"):
		voice_bridge_node.call("set_voice_enabled_for_character", "Session Record", true)
	if not WorkshopTranscriptControllerScript.is_feature_enabled():
		return
	_transcript_controller = WorkshopTranscriptControllerScript.new()
	_transcript_controller.name = "WorkshopTranscriptController"
	add_child(_transcript_controller)
	var hub_client: Object = session_root_node.get("_hub") as Object
	if not _transcript_controller.mount(
		workspace_shell_node, session_root_node, hub_client,
		_workspace_controller
	):
		push_error("WorkshopCatalystController: Transcript controls failed to mount.")

func _require_facilitator_claim(action_label: String) -> bool:
	if ControllerUtilsScript.has_local_facilitator_claim(_presence_controller):
		return true
	_set_action_status("%s requires a Facilitator claim. Use the Facilitator needed dialog." % action_label)
	return false

func _on_facilitator_authority_changed(_has_claim: bool) -> void:
	_refresh_ui_from_state()

func _mount_session_record_review() -> void:
	if not _session_record_panel_node:
		push_error("WorkshopCatalystController: Session Record panel is unavailable.")
		return
	var ws: Dictionary = _get_ws()
	var saved_state_any: Variant = ws.get("session_record_review", {})
	var saved_state: Dictionary = (
		saved_state_any if typeof(saved_state_any) == TYPE_DICTIONARY else {}
	)
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	_record_store = WorkshopSessionRecordStoreScript.new()
	_record_store.initialize(_get_current_session_id(), saved_state, buckets)
	_record_proposal_engine = WorkshopSessionRecordProposalEngineScript.new()
	_summary_persistence = WorkshopSummaryPersistenceCoordinatorScript.new()
	_summary_persistence.name = "WorkshopSummaryPersistenceCoordinator"
	add_child(_summary_persistence)
	var session_root_node: Node = get_parent()
	var hub_client: Object = session_root_node.get("_hub") as Object
	_summary_persistence.configure(hub_client, _record_store)
	_record_panel_controller = WorkshopSessionRecordPanelControllerScript.new()
	_record_panel_controller.connect("state_changed", _persist_session_record_state)
	if not _record_panel_controller.mount(
		_session_record_panel_node,
		_record_store,
		_summary_persistence
	):
		push_error("WorkshopCatalystController: Session Record review controls failed to mount.")
		return
	_persist_session_record_state()
	_mount_thinking_map()


func _mount_thinking_map() -> void:
	if not _workspace_controller:
		return
	var map_panel_node: Control = _workspace_controller.get_control("WorkshopThinkingMap")
	if not map_panel_node:
		push_error("WorkshopCatalystController: Thinking Map panel is unavailable.")
		return
	var ws: Dictionary = _get_ws()
	var saved_map_any: Variant = ws.get("thinking_map", {})
	var saved_map: Dictionary = (
		saved_map_any if typeof(saved_map_any) == TYPE_DICTIONARY else {}
	)
	var scenario: Dictionary = Global.get_current_scenario() if Global else {}
	var scenario_id: String = String(scenario.get("id", scenario.get("name", "")))
	var hub_client: Object = get_parent().get("_hub") as Object
	_thinking_map_controller = WorkshopThinkingMapControllerScript.new()
	_thinking_map_controller.state_changed.connect(_persist_thinking_map_state)
	_thinking_map_controller.specialist_context_changed.connect(
		_on_thinking_map_context_changed
	)
	_thinking_map_controller.closure_route_requested.connect(
		_on_thinking_map_closure_requested
	)
	# Model access stays out of the map controller; see `workshop_assist_passes.gd`.
	_thinking_map_controller.orientation_suggestions_requested.connect(
		func(claims: Array) -> void:
			await WorkshopAssistPassesScript.run_orientation_pass(
				_thinking_map_controller, claims
			)
	)
	_thinking_map_controller.audit_suggestions_requested.connect(
		func(request: Dictionary) -> void:
			await WorkshopAssistPassesScript.run_audit_pass(_thinking_map_controller, request)
	)
	if not _thinking_map_controller.mount(
		map_panel_node,
		hub_client,
		_record_store,
		_get_current_session_id(),
		scenario_id,
		saved_map
	):
		push_error("WorkshopCatalystController: Thinking Map failed to mount.")
		return
	var saved_paths_any: Variant = ws.get("compare_paths", {})
	var saved_paths: Dictionary = (
		saved_paths_any if typeof(saved_paths_any) == TYPE_DICTIONARY else {}
	)
	_compare_paths_controller = WorkshopComparePathsMountScript.mount(
		_workspace_controller,
		hub_client,
		_record_store,
		_get_current_session_id(),
		scenario_id,
		saved_paths,
		_persist_compare_paths_state
	)


## Re-hydrates Session Record, Thinking Map, and Compare Paths after "Load
## Story Log" / "My Sessions" loads a prior session's .workshop.json sidecar.
## See ControllerUtilsScript.reload_workshop_panels_from_state() for the
## actual reload logic (kept out of this file for the line-limit ratchet).
func reload_from_loaded_state() -> void:
	var scenario: Dictionary = Global.get_current_scenario() if Global else {}
	ControllerUtilsScript.reload_workshop_panels_from_state(
		_get_ws(),
		_get_current_session_id(),
		String(scenario.get("id", scenario.get("name", ""))),
		_record_store,
		_record_panel_controller,
		_thinking_map_controller,
		_compare_paths_controller
	)
	_refresh_ui_from_state()

func handle_transcription_completed(transcribed_text: String, error_text: String) -> bool:
	if not _transcript_controller:
		return false
	return _transcript_controller.handle_transcription_completed(transcribed_text, error_text)


func should_speak_workshop_message(sender_id: String) -> bool:
	return sender_id == "Session Record"

func _on_end_and_save_requested() -> void:
	if not _require_facilitator_claim("End & Save"):
		return
	if _timer_node:
		_timer_node.stop()
	_is_running = false
	var ws: Dictionary = _get_ws()
	ws["stage_status"] = "completed"
	ws["stage_completed_at_unix"] = Time.get_unix_time_from_system()
	_update_ws_runtime_fields(ws)
	if _story_log_system_node and _story_log_system_node.has_method("save_story_log"):
		_story_log_system_node.call("save_story_log")
		if _workspace_controller:
			_workspace_controller.set_end_save_status("Session ended and story log saved.")
	else:
		if _workspace_controller:
			_workspace_controller.set_end_save_status(
				"Session ended, but the story log service was unavailable.",
				true
			)

func _connect_settings_binding() -> void:
	_settings_binding.start_requested.connect(_on_start_pressed)
	_settings_binding.pause_requested.connect(_on_pause_pressed)
	_settings_binding.next_stage_requested.connect(_on_next_pressed)
	_settings_binding.add_time_requested.connect(_add_time_minutes)
	_settings_binding.note_only_changed.connect(_on_add_note_toggled)
	_settings_binding.facilitator_sender_changed.connect(_on_send_as_facilitator_toggled)
	_settings_binding.duration_changed.connect(_on_session_duration_changed)
	_settings_binding.multi_day_changed.connect(_on_multi_day_toggled)
	_settings_binding.update_buckets_requested.connect(_on_update_buckets_pressed)
	_settings_binding.export_summary_requested.connect(_on_export_summary_pressed)
	_settings_binding.export_decision_record_requested.connect(_on_export_decision_record_pressed)
	_settings_binding.inject_stress_requested.connect(_on_inject_stress_pressed)

func _connect_story_state() -> void:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return
	if StoryState.has_signal("state_updated"):
		if not StoryState.state_updated.is_connected(_on_story_state_updated):
			StoryState.state_updated.connect(_on_story_state_updated)

func _ensure_workshop_state_initialized() -> void:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return
	var state_dict: Dictionary = StoryState.get_state()
	var scenario: Dictionary = Global.get_current_scenario() if Global else {}
	var ws_any: Variant = state_dict.get(WS_KEY, {})
	var ws: Dictionary = ws_any if typeof(ws_any) == TYPE_DICTIONARY else {}
	ws = WorkshopCatalystTimingScript.normalize_state(ws, scenario)
	_set_ws(ws)

func _parse_agenda_from_scenario(scenario: Dictionary) -> Array:
	return WorkshopCatalystTimingScript.parse_agenda(scenario)

func _apply_session_timing_to_agenda(agenda: Array, session_duration_minutes: int, uses_scaled_timing: bool) -> Array:
	return WorkshopCatalystTimingScript.apply_session_timing_to_agenda(
		agenda,
		session_duration_minutes,
		uses_scaled_timing
	)

func _build_session_label(ws: Dictionary) -> String:
	return WorkshopCatalystTimingScript.build_session_label(ws)

func _get_current_day_number(ws: Dictionary) -> int:
	return WorkshopCatalystTimingScript.get_current_day_number(ws)

func _get_stage_duration_sec(stage_info: Dictionary) -> int:
	return WorkshopCatalystTimingScript.get_stage_duration_sec(stage_info)

func _get_ws() -> Dictionary:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return {}
	var state_dict: Dictionary = StoryState.get_state()
	var ws_any: Variant = state_dict.get(WS_KEY, {})
	return ws_any if typeof(ws_any) == TYPE_DICTIONARY else {}

func _set_ws(ws: Dictionary) -> void:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return
	var state_dict: Dictionary = StoryState.get_state()
	var new_state: Dictionary = state_dict.duplicate(true)
	new_state[WS_KEY] = ws
	StoryState.set_state(new_state)
	ControllerUtilsScript.sync_workshop_state_to_peers_if_host()

func _get_current_stage_info(ws: Dictionary) -> Dictionary:
	return WorkshopCatalystTimingScript.get_current_stage_info(ws)

func _refresh_ui_from_state() -> void:
	var ws: Dictionary = _get_ws()
	var stage_info: Dictionary = _get_current_stage_info(ws)
	if not _is_running:
		_remaining_sec = int(ws.get("stage_remaining_sec", _remaining_sec))

	var stage_title: String = String(stage_info.get("name", ""))
	if stage_title.is_empty():
		stage_title = "(no agenda)"
	if _settings_binding:
		_settings_binding.refresh(ws, stage_title, _remaining_sec)
	if _record_store:
		var buckets_any: Variant = ws.get("buckets", {})
		var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
		if _record_store.reconcile_authoritative_buckets(buckets):
			ws["session_record_review"] = _record_store.get_state()
			_set_ws(ws)
	if _record_panel_controller:
		_record_panel_controller.set_context(
			String(ws.get("session_label", "")).strip_edges(),
			stage_title
		)
		var closure_refs_any: Variant = ws.get("closure_refs", [])
		var closure_refs: Array = (
			closure_refs_any if typeof(closure_refs_any) == TYPE_ARRAY else []
		)
		_record_panel_controller.set_closure_refs(closure_refs)
		_record_panel_controller.refresh()
	_apply_session_record_pulse(String(ws.get("session_record_pulse", "")))


func _persist_session_record_state() -> void:
	if not _record_store:
		return
	var ws: Dictionary = _get_ws()
	ws["session_record_review"] = _record_store.get_state()
	_set_ws(ws)
	# Review only works once the record holds a decision, so its button follows the
	# record and opens the moment the first decision lands.
	if _workspace_controller:
		_workspace_controller.set_review_available(
			ReviewGateScript.is_available(_record_store.get_reviewed())
		)

func _update_time_label() -> void:
	var ws: Dictionary = _get_ws()
	if _settings_binding:
		_settings_binding.update_time(ws, _remaining_sec)

func _on_start_pressed() -> void:
	if not _mgr_wired:
		var mgr_now = Global.get_metaprompt_manager() if Global else null
		if mgr_now and mgr_now.has_method("set_session_record") and _session_record:
			mgr_now.set_session_record(_session_record)
			_mgr_wired = true
	var ws := _get_ws()
	var stage_info := _get_current_stage_info(ws)
	var duration_sec := _get_stage_duration_sec(stage_info)
	if duration_sec <= 0:
		return
	var stage_status: String = String(ws.get("stage_status", "not_started")).strip_edges()
	var stored_remaining_sec: int = int(ws.get("stage_remaining_sec", 0))
	if stage_status == "paused" and stored_remaining_sec > 0:
		_remaining_sec = stored_remaining_sec
	elif stage_status != "running":
		if stored_remaining_sec > 0 and stage_status == "not_started":
			_remaining_sec = stored_remaining_sec
		else:
			_remaining_sec = duration_sec
	_is_running = true
	_timer_node.start()
	ws["stage_status"] = "running"
	if int(ws.get("stage_started_at_unix", 0)) <= 0 or stage_status == "completed":
		ws["stage_started_at_unix"] = Time.get_unix_time_from_system()
	ws["stage_completed_at_unix"] = 0
	_session_auto_opened = true
	if _session_record:
		var is_first_start: bool = float(ws.get("session_started_at_unix", 0.0)) <= 0.0
		if is_first_start:
			ws["session_started_at_unix"] = Time.get_unix_time_from_system()
			_session_warned_minutes = []
			var scenario_sr: Dictionary = Global.get_current_scenario() if Global else {}
			var scenario_name_sr: String = String(scenario_sr.get("name", "Workshop")).strip_edges()
			var dur_min_sr: int = int(ws.get("session_duration_minutes", 120))
			var stage_name_sr: String = String(ws.get("current_stage_name", "")).strip_edges()
			_session_record.post("Session open. Scenario: %s. Duration: %d minutes. Target: 3 decisions | 2 risks | 1 deferred question with owner. Opening stage: %s." % [scenario_name_sr, dur_min_sr, stage_name_sr])
		elif stage_status != "paused":
			var stage_name_sr2: String = String(ws.get("current_stage_name", "")).strip_edges()
			var stage_min_sr: int = int(duration_sec / 60)
			_session_record.post("Stage started: %s (%d min). %s." % [stage_name_sr2, stage_min_sr, _session_record.build_decision_record_status(ws)])
	_update_ws_runtime_fields(ws)
	_refresh_ui_from_state()

func _on_pause_pressed() -> void:
	_is_running = false
	if _timer_node:
		_timer_node.stop()
	var ws: Dictionary = _get_ws()
	ws["stage_status"] = "paused"
	_update_ws_runtime_fields(ws)
	_refresh_ui_from_state()

func _on_next_pressed() -> void:
	if not _require_facilitator_claim("Next Stage"):
		return
	if _settings_binding:
		_settings_binding.set_next_stage_busy("Capturing…", true)
	await get_tree().process_frame
	var story_log: Array = StoryState.get_state().get("story_log", []) if StoryState else []
	var has_character_turns := false
	for entry_any: Variant in story_log:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender: String = String(entry.get("sender", "")).strip_edges()
		if sender not in ["Narrator", "Session Record", "Facilitator Note", "Facilitator", ""]:
			has_character_turns = true
			break
	if has_character_turns:
		_set_action_status("Capturing decisions from this stage's discussion…")
		await _update_buckets_from_recent_log()
	if _settings_binding:
		_settings_binding.set_next_stage_busy("Advancing…", true)
	await get_tree().process_frame
	_advance_stage()
	if _settings_binding:
		_settings_binding.set_next_stage_busy("Next Stage", false)
	_set_action_status("Stage advanced. Timer started.")

func _add_time_minutes(minutes: int) -> void:
	if minutes <= 0:
		return
	_remaining_sec += int(minutes) * 60
	_update_ws_runtime_fields()
	_refresh_ui_from_state()

func _on_add_note_toggled(is_pressed: bool) -> void:
	var ws := _get_ws()
	ws["is_note_only_next_input"] = (is_pressed == true)
	_set_ws(ws)

func _on_send_as_facilitator_toggled(is_pressed: bool) -> void:
	var ws := _get_ws()
	ws["send_as_facilitator"] = (is_pressed == true)
	_set_ws(ws)

func _on_session_duration_changed(session_minutes: int) -> void:
	if session_minutes <= 0:
		return
	var scenario: Dictionary = Global.get_current_scenario() if Global else {}
	var ws: Dictionary = _get_ws()
	ws["session_duration_minutes"] = session_minutes
	ws["agenda"] = _apply_session_timing_to_agenda(_parse_agenda_from_scenario(scenario), session_minutes, bool(ws.get("uses_scaled_stage_timing", false)))
	var stage_info: Dictionary = _get_current_stage_info(ws)
	if String(ws.get("stage_status", "not_started")) != "running":
		ws["stage_remaining_sec"] = _get_stage_duration_sec(stage_info)
		_remaining_sec = int(ws.get("stage_remaining_sec", 0))
	ws["current_stage_name"] = String(stage_info.get("name", ""))
	ws["day"] = _get_current_day_number(ws)
	ws["session_label"] = _build_session_label(ws)
	_set_ws(ws)
	_refresh_ui_from_state()

func _on_multi_day_toggled(is_pressed: bool) -> void:
	var ws: Dictionary = _get_ws()
	ws["is_multi_day"] = (is_pressed == true)
	if ws["is_multi_day"] == true and String(ws.get("series_id", "")).strip_edges().is_empty():
		ws["series_id"] = String(ws.get("session_id", ""))
	ws["session_label"] = _build_session_label(ws)
	_set_ws(ws)
	_refresh_ui_from_state()

func _on_timer_tick() -> void:
	if not _is_running:
		return
	_remaining_sec -= 1
	if _remaining_sec <= 0:
		_remaining_sec = 0
		_is_running = false
		_timer_node.stop()
		var ws: Dictionary = _get_ws()
		ws["stage_status"] = "completed"
		ws["stage_completed_at_unix"] = Time.get_unix_time_from_system()
		_update_ws_runtime_fields(ws)
		_refresh_ui_from_state()
	else:
		var ws_running: Dictionary = _get_ws()
		_update_ws_runtime_fields(ws_running)
		_update_time_label()
		_check_session_time_warnings(ws_running)

func _check_session_time_warnings(ws: Dictionary) -> void:
	if not _session_record:
		return
	var session_started_unix: float = float(ws.get("session_started_at_unix", 0.0))
	if session_started_unix <= 0.0:
		return
	var session_duration_sec: float = float(int(ws.get("session_duration_minutes", 120))) * 60.0
	var elapsed_sec: float = Time.get_unix_time_from_system() - session_started_unix
	var remaining_min: int = int((session_duration_sec - elapsed_sec) / 60.0)
	var warning_thresholds: Array[int] = [20, 10, 5]
	for threshold: int in warning_thresholds:
		if remaining_min <= threshold and not _session_warned_minutes.has(threshold):
			_session_warned_minutes.append(threshold)
			var scenario_sr: Dictionary = Global.get_current_scenario() if Global else {}
			var conv = Global.get_conversation_manager() if Global else null
			var trigger_text := "%d minutes remaining in session" % threshold
			_session_record.generate_lm_entry(conv, ws, scenario_sr, trigger_text)
			break

func _update_ws_runtime_fields(ws: Dictionary = {}) -> void:
	if ws.is_empty():
		ws = _get_ws()
	ws["stage_remaining_sec"] = _remaining_sec
	var stage_info := _get_current_stage_info(ws)
	ws["current_stage_name"] = String(stage_info.get("name", ""))
	ws["day"] = _get_current_day_number(ws)
	ws["session_label"] = _build_session_label(ws)
	_set_ws(ws)

func _advance_stage() -> void:
	var ws := _get_ws()
	var agenda_any: Variant = ws.get("agenda", [])
	var agenda: Array = agenda_any if typeof(agenda_any) == TYPE_ARRAY else []
	if agenda.is_empty():
		return
	var day_idx: int = int(ws.get("day_index", 0))
	if day_idx < 0 or day_idx >= agenda.size():
		return
	var day_entry: Dictionary = agenda[day_idx] if typeof(agenda[day_idx]) == TYPE_DICTIONARY else {}
	var stages: Array = day_entry.get("stages", []) if typeof(day_entry.get("stages", [])) == TYPE_ARRAY else []
	if stages.is_empty():
		return
	var stage_history_any: Variant = ws.get("stage_history", [])
	var stage_history: Array = stage_history_any if typeof(stage_history_any) == TYPE_ARRAY else []
	var current_stage_info: Dictionary = _get_current_stage_info(ws)
	var closing_stage_name: String = String(current_stage_info.get("name", "")).strip_edges()
	if not current_stage_info.is_empty():
		stage_history.append(
			ControllerUtilsScript.build_stage_history_entry(ws, current_stage_info)
		)
	ws["stage_history"] = stage_history
	# If a pending_vote was never resolved, surface it as a note and clear it.
	var pending_vote_any: Variant = ws.get("pending_vote", {})
	if typeof(pending_vote_any) == TYPE_DICTIONARY:
		var pv: Dictionary = pending_vote_any
		var pv_text: String = String(pv.get("text", "")).strip_edges()
		if not pv_text.is_empty():
			var pv_yes_any: Variant = pv.get("votes_yes", [])
			var pv_no_any: Variant = pv.get("votes_no", [])
			var pv_yes: Array = pv_yes_any if typeof(pv_yes_any) == TYPE_ARRAY else []
			var pv_no: Array = pv_no_any if typeof(pv_no_any) == TYPE_ARRAY else []
			StoryState.add_log_entry("Session Record",
				"Stage closed with an unresolved proposal (Yes: %d, No: %d): \"%s\"\nThe facilitator can still capture it with /decide if appropriate." \
				% [pv_yes.size(), pv_no.size(), pv_text])
	ws.erase("pending_vote")
	var next_stage_idx := int(ws.get("stage_index", 0)) + 1
	if next_stage_idx >= stages.size():
		var next_day_idx := day_idx + 1
		if next_day_idx < agenda.size():
			ws["day_index"] = next_day_idx
			ws["stage_index"] = 0
		else:
			ws["stage_index"] = stages.size() - 1
	else:
		ws["stage_index"] = next_stage_idx

	_is_running = false
	if _timer_node:
		_timer_node.stop()
	ws["stage_status"] = "not_started"
	ws["stage_started_at_unix"] = 0
	ws["stage_completed_at_unix"] = 0
	var next_stage_info: Dictionary = _get_current_stage_info(ws)
	_remaining_sec = _get_stage_duration_sec(next_stage_info)
	ws["stage_remaining_sec"] = _remaining_sec
	ws["current_stage_name"] = String(next_stage_info.get("name", ""))
	ws["day"] = _get_current_day_number(ws)
	ws["session_label"] = _build_session_label(ws)
	_set_ws(ws)
	# Session Record: reset stage turn count and log index tracker, then fire LLM stage summary
	_last_proactive_log_index = -1
	if _session_record:
		_session_record.reset_stage_turn_count()
		var next_stage_name: String = String(next_stage_info.get("name", "")).strip_edges()
		var scenario_sr: Dictionary = Global.get_current_scenario() if Global else {}
		var conv = Global.get_conversation_manager() if Global else null
		var trigger_text: String = "stage_advance: \"%s\" has closed. Next stage: \"%s\"." % [closing_stage_name, next_stage_name]
		_session_record.generate_lm_entry(conv, ws, scenario_sr, trigger_text)
	_refresh_ui_from_state()
	_on_start_pressed()

func _on_story_state_updated(new_state: Dictionary) -> void:
	if not Global or Global.current_session_type != "workshop_catalyst" or Global.is_loading_story_log:
		return
	_refresh_ui_from_state()
	_refresh_session_record_pulse(new_state)
	var sync_check: Dictionary = ControllerUtilsScript.client_workshop_fingerprint_changed(
		new_state, WS_KEY, _last_synced_workshop_fingerprint
	)
	_last_synced_workshop_fingerprint = String(sync_check.get("fingerprint", ""))
	if bool(sync_check.get("changed", false)):
		reload_from_loaded_state()
	# Proactive Session Record: count character turns and run observation checks.
	# Not gated on _is_running — session record activates on first character turn
	# even if the facilitator has not pressed Start yet.
	if not _session_record:
		return
	# Retry manager wiring on every call until it succeeds (manager becomes available
	# only after a scenario is selected, which may be after initialize()).
	if not _mgr_wired:
		var mgr_now = Global.get_metaprompt_manager() if Global else null
		if mgr_now and mgr_now.has_method("set_session_record"):
			mgr_now.set_session_record(_session_record)
			_mgr_wired = true
	var story_log_any: Variant = new_state.get("story_log", [])
	var story_log: Array = story_log_any if typeof(story_log_any) == TYPE_ARRAY else []
	if story_log.is_empty():
		return
	var last_index: int = story_log.size() - 1
	if _thinking_map_controller:
		var map_entry_any: Variant = story_log.back()
		if typeof(map_entry_any) == TYPE_DICTIONARY:
			_thinking_map_controller.ingest_story_entry(map_entry_any, last_index)
	# Guard: only fire once per new log entry (timer ticks also emit state_updated,
	# which would otherwise increment the stage turn count every second).
	if last_index <= _last_proactive_log_index:
		return
	var last_entry_any: Variant = story_log.back()
	if typeof(last_entry_any) != TYPE_DICTIONARY:
		return
	var last_sender: String = String(last_entry_any.get("sender", "")).strip_edges()
	var system_senders: Array[String] = ["Session Record", "Narrator", "Facilitator Note", "Facilitator", ""]
	if last_sender in system_senders:
		_last_proactive_log_index = last_index
		return
	_last_proactive_log_index = last_index
	var ws: Dictionary = _get_ws()
	var scenario_sr: Dictionary = Global.get_current_scenario() if Global else {}
	var conv = Global.get_conversation_manager() if Global else null
	var recent_log: Array = story_log.slice(maxi(0, story_log.size() - 6), story_log.size())
	# Auto-open: post the "Session open" entry on the very first character turn when
	# the facilitator has not pressed Start yet (informal session start).
	if not _session_auto_opened:
		_session_auto_opened = true
		var is_first_start: bool = float(ws.get("session_started_at_unix", 0.0)) <= 0.0
		if is_first_start:
			ws["session_started_at_unix"] = Time.get_unix_time_from_system()
			_session_warned_minutes = []
			var scenario_name_ao: String = String(scenario_sr.get("name", "Workshop")).strip_edges()
			var dur_min_ao: int = int(ws.get("session_duration_minutes", 120))
			var stage_name_ao: String = String(ws.get("current_stage_name", "")).strip_edges()
			_session_record.post("Session open. Scenario: %s. Duration: %d minutes. Target: 3 decisions | 2 risks | 1 deferred question with owner. Opening stage: %s." % [scenario_name_ao, dur_min_ao, stage_name_ao])
	_session_record.on_character_turn(ws, scenario_sr, conv, recent_log)


func _refresh_session_record_pulse(new_state: Dictionary) -> void:
	var ws_any: Variant = new_state.get("workshop_catalyst", {})
	var ws: Dictionary = ws_any if typeof(ws_any) == TYPE_DICTIONARY else {}
	var pulse_text: String = String(ws.get("session_record_pulse", "")).strip_edges()
	if pulse_text.is_empty():
		pulse_text = String(_get_ws().get("session_record_pulse", "")).strip_edges()
	_apply_session_record_pulse(pulse_text)


func _apply_session_record_pulse(pulse_text: String) -> void:
	var trimmed: String = pulse_text.strip_edges()
	if trimmed.is_empty() or not _workspace_controller:
		return
	_last_session_record_pulse = trimmed
	_workspace_controller.set_session_record_pulse(trimmed)


func _persist_thinking_map_state(map_state: Dictionary) -> void:
	var ws: Dictionary = _get_ws()
	ws["thinking_map"] = map_state.duplicate(true)
	_set_ws(ws)


func _persist_compare_paths_state(path_state: Dictionary) -> void:
	var ws: Dictionary = _get_ws()
	ws["compare_paths"] = path_state.duplicate(true)
	_set_ws(ws)


func _on_thinking_map_context_changed(
	context_payload: Dictionary,
	trace: Dictionary
) -> void:
	var ws: Dictionary = _get_ws()
	ws["thinking_map_prompt_context"] = context_payload.duplicate(true)
	ws["thinking_map_context_trace"] = trace.duplicate(true)
	_set_ws(ws)


func _on_thinking_map_closure_requested(outcome: Dictionary) -> void:
	if not Global or not Global.get_closure_bus():
		return
	var scenario: Dictionary = Global.get_current_scenario()
	var ws: Dictionary = _get_ws()
	Global.get_closure_bus().emit_captured({
		"session_type_id": "workshop_catalyst",
		"scenario_id": String(scenario.get("id", scenario.get("name", ""))),
		"scenario_name": String(scenario.get("name", "Workshop")),
		"kind": String(outcome.get("record_category", "")).trim_suffix("s"),
		"statement": String(outcome.get("text", "")),
		"owner": "Facilitator",
		"outcome": "yes",
		"reason": "Explicit facilitator Thinking Map action",
		"trigger": "thinking_map_facilitator_route",
		"stage_name": String(ws.get("current_stage_name", "")),
		"thinking_map_item_id": String(outcome.get("map_item_id", "")),
		"thinking_map_artifact_id": String(outcome.get("map_artifact_id", "")),
	})

func _on_update_buckets_pressed() -> void:
	if _is_processing:
		return
	if not Global or Global.current_session_type != "workshop_catalyst":
		return
	_is_processing = true
	if _settings_binding:
		_settings_binding.set_bucket_update_busy(true)
	await _update_buckets_from_recent_log()
	_is_processing = false
	if _settings_binding:
		_settings_binding.set_bucket_update_busy(false)
	_refresh_ui_from_state()

func _on_export_summary_pressed() -> void:
	if _is_processing:
		return
	if not Global or Global.current_session_type != "workshop_catalyst":
		return
	if _settings_binding:
		_settings_binding.set_summary_export_busy(true)
	var exported_path := _export_workshop_summary()
	if _settings_binding:
		_settings_binding.set_summary_export_busy(false)
	if not exported_path.is_empty():
		_set_action_status("Exported: " + exported_path.get_file())
	else:
		_set_action_status("Export failed — check Godot output.")

func _export_workshop_summary() -> String:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return ""
	var ws := _get_ws()
	var out_path: String = ControllerUtilsScript.export_workshop_summary(
		WorkshopCatalystExportUtilsScript,
		ws,
		_get_current_session_id(),
		Global.get_current_scenario() if Global else {},
		_get_current_stage_info(ws),
		_record_store
	)
	if not out_path.is_empty():
		print("WorkshopCatalystController: Exported workshop summary: ", out_path)
	return out_path

func _get_current_session_id() -> String:
	return ControllerUtilsScript.find_current_session_id(get_tree(), _get_ws())

func _on_inject_stress_pressed() -> void:
	if not _require_facilitator_claim("Inject Stress"):
		return
	var ws := _get_ws()
	var stage_info := _get_current_stage_info(ws)
	var stage_name: String = String(stage_info.get("name", "")).strip_edges()
	if stage_name.is_empty() or not stage_name.to_lower().begins_with("stress injection"):
		_set_action_status("Inject Stress is only available during Stress Injection stages.")
		return
	var scenario: Dictionary = Global.get_current_scenario() if Global else {}
	var result: Dictionary = ControllerUtilsScript.build_stress_injection_post(scenario, stage_name)
	var post_text: String = String(result.get("post_text", ""))
	if post_text.is_empty():
		_set_action_status(String(result.get("status", "No stress injection text found.")))
		return
	StoryState.add_log_entry("Facilitator Note", post_text)
	_set_action_status("Stress injection posted for: " + stage_name)

func _on_export_decision_record_pressed() -> void:
	if _is_processing:
		return
	if not Global or Global.current_session_type != "workshop_catalyst":
		return
	if _settings_binding:
		_settings_binding.set_decision_export_busy(true)
	var exported_path := _export_decision_record_only()
	if _settings_binding:
		_settings_binding.set_decision_export_busy(false)
	if not exported_path.is_empty():
		_set_action_status("Decision record exported: " + exported_path.get_file())
	else:
		_set_action_status("Export failed — check Godot output.")

func _export_decision_record_only() -> String:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return ""
	var out_path: String = ControllerUtilsScript.export_decision_record_only(
		WorkshopCatalystExportUtilsScript,
		_get_ws(),
		_get_current_session_id(),
		Global.get_current_scenario() if Global else {},
		_record_store
	)
	if not out_path.is_empty():
		print("WorkshopCatalystController: Exported decision record: ", out_path)
	return out_path

func _set_action_status(msg: String) -> void:
	if not _settings_binding:
		return
	_settings_binding.set_action_status(msg)
	await get_tree().create_timer(8.0).timeout
	if _settings_binding and _settings_binding.get_action_status() == msg:
		_settings_binding.set_action_status("")

func _update_buckets_from_recent_log() -> void:
	if (
		not _record_store
		or not _record_proposal_engine
		or typeof(StoryState) == TYPE_NIL
		or not StoryState
	):
		return
	var conversation: Variant = Global.get_conversation_manager() if Global else null
	var scenario: Dictionary = Global.get_current_scenario() if Global else {}
	var ws: Dictionary = _get_ws()
	var recent_log_any: Variant = StoryState.get_state().get("story_log", [])
	var recent_log: Array = recent_log_any if typeof(recent_log_any) == TYPE_ARRAY else []
	if recent_log.size() > 40:
		recent_log = recent_log.slice(recent_log.size() - 40, recent_log.size())
	var stage_title: String = String(_get_current_stage_info(ws).get("name", ""))
	var result: Dictionary = await _record_proposal_engine.request_proposals(
		conversation,
		scenario,
		stage_title,
		recent_log,
		_record_store
	)
	if not bool(result.get("ok", false)):
		_set_action_status(
			"Proposal extraction failed; reviewed Session Record was not changed."
		)
		return
	var proposals_any: Variant = result.get("proposals", [])
	var proposals: Array = proposals_any if typeof(proposals_any) == TYPE_ARRAY else []
	_persist_session_record_state()
	if _record_panel_controller:
		_record_panel_controller.refresh()
	_set_action_status(
		"%d new proposal(s) ready for facilitator review; none accepted automatically."
		% proposals.size()
	)
