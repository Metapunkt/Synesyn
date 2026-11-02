extends SceneTree

const ProfileScript = preload("res://ScenSyn/scripts/agents/session_type_runtime_profile.gd")
const CoordinatorScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_specialist_coordinator.gd"
)
const TraceStoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_specialist_trace_store.gd"
)
const WorkspaceControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_controller.gd"
)
const WorkspaceScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_workspace_shell.tscn"
)
const SESSION_RECORD_PATH := (
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_session_record.gd"
)

var _failures: Array[String] = []


class FakeConversation:
	extends RefCounted
	var requests: Array[Dictionary] = []
	var response_text: String = ""
	var response_queue: Array[String] = []
	var should_succeed: bool = true
	var success_queue: Array[bool] = []

	func chat(prompt: String, thread_id: String = "", model_id: String = "") -> Dictionary:
		requests.append({
			"prompt": prompt,
			"thread_id": thread_id,
			"model_id": model_id,
		})
		var next_text: String = response_text
		if not response_queue.is_empty():
			next_text = String(response_queue.pop_front())
		var next_success: bool = should_succeed
		if not success_queue.is_empty():
			next_success = bool(success_queue.pop_front())
		return {"success": next_success, "response": next_text}

	func get_current_thread() -> String:
		return "test_thread"


class FakeModelManager:
	extends RefCounted
	var current_model: String = "llama2"
	var provider_id: String = "ollama"

	func get_current_model() -> String:
		return current_model

	func get_provider_for_model(_model_id: String) -> String:
		return provider_id


class FakeApiService:
	extends RefCounted
	var requests: Array[Dictionary] = []
	var response_text: String = ""
	var response_queue: Array[String] = []
	var should_succeed: bool = true
	var success_queue: Array[bool] = []

	func chat_completion(
		model_id: String,
		messages: Array,
		settings: Dictionary = {}
	) -> Dictionary:
		requests.append({
			"model_id": model_id,
			"messages": messages.duplicate(true),
			"settings": settings.duplicate(true),
		})
		var next_text: String = response_text
		if not response_queue.is_empty():
			next_text = String(response_queue.pop_front())
		var next_success: bool = should_succeed
		if not success_queue.is_empty():
			next_success = bool(success_queue.pop_front())
		return {
			"success": next_success,
			"response": next_text,
			"error": "" if next_success else "Could not connect",
		}


class FakeStatelessConversation:
	extends RefCounted
	var api_service: RefCounted
	var ai_model_manager: RefCounted = FakeModelManager.new()
	var persisted_requests: int = 0

	func chat(
		_prompt: String,
		_thread_id: String = "",
		_model_id: String = ""
	) -> Dictionary:
		persisted_requests += 1
		return {"success": false}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_profile_selection()
	await _test_single_batch_and_parsing()
	await _test_adaptive_two_phase_recovery()
	await _test_stateless_ollama_task()
	await _test_stateless_cloud_task_timeout()
	await _test_synthesis_and_vote_boundary()
	await _test_reasoning_panel_states()
	_test_trace_contract_and_nonblocking_source()
	_test_finalization_seam_and_story_nonregression()
	_test_session_record_pulse_helper()
	_test_synthesis_recall_command_wiring()
	_test_session_record_status_bar_wiring()
	_test_hidden_synthesis_watchdog_outlasts_cloud_timeout()
	_finish()


func _test_profile_selection() -> void:
	_expect(
		ProfileScript.for_session_type("workshop_catalyst") == ProfileScript.HIDDEN_SYNTHESIS,
		"Workshop profile is not hidden_synthesis"
	)
	_expect(
		ProfileScript.for_session_type("story_catalyst") == ProfileScript.VISIBLE_ENSEMBLE,
		"Story profile is not visible_ensemble"
	)
	_expect(
		ProfileScript.for_session_type("future_session_type") == ProfileScript.VISIBLE_ENSEMBLE,
		"Unknown Session Type did not safely default to visible_ensemble"
	)


func _test_single_batch_and_parsing() -> void:
	var coordinator: RefCounted = CoordinatorScript.new()
	var fake_conversation := FakeConversation.new()
	fake_conversation.response_text = JSON.stringify({
		"schema_version": 1,
		"contributions": [
			{"role_id": "systems_consequences", "summary": "Map the dependency chain."},
			{"role_id": "stakeholder_communication", "summary": "Clarify who bears the cost."},
			{"role_id": "risk_feasibility", "summary": "Test implementation capacity."},
			{"role_id": "options_innovation", "summary": "Compare a phased alternative."},
		],
		"map_candidates": [],
		"assistant_response": "Capacity and cost allocation need clarification before comparing options.",
	})
	var result: Dictionary = await coordinator.collect(
		fake_conversation,
		[{"sender": "Facilitator", "message": "What should we examine?"}],
		{"sender": "Facilitator", "message": "What should we examine?"},
		{"name": "Test Workshop"},
		{"current_stage_name": "Frame"}
	)
	_expect(fake_conversation.requests.size() == 1, "Specialists used more than one batch request")
	_expect(result.get("status", "") == "complete", "Valid specialist JSON was degraded")
	_expect(
		result.get("assistant_response", "") == (
			"Capacity and cost allocation need clarification before comparing options."
		),
		"Single specialist batch did not retain its participant-facing synthesis"
	)
	var contributions: Array = result.get("contributions", [])
	_expect(contributions.size() == 4, "Controlled specialist set was not complete")
	for contribution_any: Variant in contributions:
		var contribution: Dictionary = contribution_any
		_expect(contribution.get("vote") == null, "A specialist contribution contained a vote")
	var prose_wrapped: Dictionary = coordinator.parse_response(
		"Here are the concise summaries for each role:\n"
		+ fake_conversation.response_text
	)
	_expect(
		prose_wrapped.get("status", "") == "complete",
		"Valid specialist JSON with a prose prefix was degraded"
	)

	var malformed: Dictionary = coordinator.parse_response("not json")
	_expect(malformed.get("status", "") == "degraded", "Malformed JSON did not degrade")
	var malformed_contributions: Array = malformed.get("contributions", [])
	_expect(
		malformed_contributions.size() == 4,
		"Malformed JSON fallback did not preserve deterministic role shape"
	)
	var missing_synthesis: Dictionary = coordinator.parse_response(JSON.stringify({
		"schema_version": 1,
		"contributions": [
			{"role_id": "systems_consequences", "summary": "Map the dependency chain."},
			{"role_id": "stakeholder_communication", "summary": "Clarify who bears the cost."},
			{"role_id": "risk_feasibility", "summary": "Test implementation capacity."},
			{"role_id": "options_innovation", "summary": "Compare a phased alternative."},
		],
		"map_candidates": [],
	}))
	_expect(
		missing_synthesis.get("status", "") == "complete"
		and missing_synthesis.get("synthesis_source", "") == "deterministic"
		and not String(missing_synthesis.get("assistant_response", "")).is_empty(),
		"Missing assistant_response did not fall back to deterministic synthesis"
	)


func _test_adaptive_two_phase_recovery() -> void:
	var coordinator: RefCounted = CoordinatorScript.new()
	var fake_conversation := FakeConversation.new()
	var roles_json: String = JSON.stringify({
		"contributions": [
			{"role_id": "systems_consequences", "summary": "Handoffs concentrate risk."},
			{"role_id": "stakeholder_communication", "summary": "Patients absorb delay costs."},
			{"role_id": "risk_feasibility", "summary": "Capacity cannot absorb a sudden surge."},
			{"role_id": "options_innovation", "summary": "A staged referral limit is available."},
		],
	})
	var synthesis_json: String = JSON.stringify({
		"schema_version": 1,
		"map_candidates": [
			{
				"id": "c1",
				"category": "cause",
				"proposition": "Primary care to specialist handoffs concentrate unmet demand.",
				"source_class": "ai_inferred",
				"source_refs": ["turn-1"],
				"rationale": "From systems and stakeholder summaries.",
				"confidence": 0.7,
				"evidence_status": "unsupported",
			}
		],
		"facilitator_cues": ["Ask who owns the handoff."],
		"assistant_response": "The handoff is the fragile point; patients absorb the delay.",
	})
	fake_conversation.response_queue = [
		"not a valid specialist envelope",
		roles_json,
		synthesis_json,
	]
	var recovered: Dictionary = await coordinator.collect(
		fake_conversation,
		[{"sender": "Facilitator", "message": "Where does the pathway break?"}],
		{"sender": "Facilitator", "message": "Where does the pathway break?"},
		{"name": "Recovery Workshop"},
		{"current_stage_name": "Map Causes and Effects"}
	)
	_expect(fake_conversation.requests.size() == 3, "Two-phase recovery did not use three requests")
	_expect(recovered.get("status", "") == "complete", "Two-phase recovery stayed degraded")
	_expect(recovered.get("recovery_path", "") == "two_phase", "Recovery path was not recorded")
	_expect(
		recovered.get("assistant_response", "")
		== "The handoff is the fragile point; patients absorb the delay.",
		"Two-phase synthesis response was not retained"
	)
	_expect(
		(recovered.get("map_candidates", []) as Array).size() == 1,
		"Two-phase map candidates were not retained"
	)
	_expect(
		String(fake_conversation.requests[1].get("prompt", "")).contains(
			"four independent specialist summaries"
		),
		"Phase-1 roles prompt was not used"
	)
	_expect(
		String(fake_conversation.requests[2].get("prompt", "")).contains(
			"FIXED SPECIALIST SUMMARIES"
		),
		"Phase-2 synthesis prompt was not used"
	)

	var roles_only_conversation := FakeConversation.new()
	roles_only_conversation.response_queue = [
		"not a valid specialist envelope",
		roles_json,
	]
	roles_only_conversation.success_queue = [true, true, false]
	var roles_only: Dictionary = await coordinator.collect(
		roles_only_conversation,
		[],
		{"sender": "Facilitator", "message": "Where does the pathway break?"},
		{"name": "Recovery Workshop"},
		{"current_stage_name": "Map Causes and Effects"}
	)
	_expect(
		roles_only.get("recovery_path", "") == "two_phase_roles_only"
		and roles_only.get("status", "") == "degraded"
		and roles_only.get("synthesis_source", "") == "deterministic"
		and (roles_only.get("map_candidates", []) as Array).is_empty(),
		"Phase-2 failure did not keep roles with deterministic synthesis"
	)


func _test_stateless_ollama_task() -> void:
	var coordinator: RefCounted = CoordinatorScript.new()
	var conversation := FakeStatelessConversation.new()
	var api_service := FakeApiService.new()
	conversation.api_service = api_service
	api_service.response_text = JSON.stringify({
		"schema_version": 1,
		"contributions": [
			{"role_id": "systems_consequences", "summary": "Dependency summary."},
			{"role_id": "stakeholder_communication", "summary": "Stakeholder summary."},
			{"role_id": "risk_feasibility", "summary": "Risk summary."},
			{"role_id": "options_innovation", "summary": "Options summary."},
		],
		"map_candidates": [],
		"assistant_response": "One bounded response.",
	})
	var result: Dictionary = await coordinator.collect(
		conversation,
		[
			{"sender": "Narrator", "message": "The AI couldn't generate a response right now."},
			{"sender": "Facilitator", "message": "Earlier relevant exchange."},
		],
		{
			"sender": "Facilitator",
			"message": "We can invest in grid storage to improve resilience.",
		},
		{"name": "Test Workshop", "objective": "Reach a bounded recommendation."},
		{
			"current_stage_name": "Frame",
			"buckets": {"risks": ["Capacity"]},
		}
	)
	_expect(result.get("status", "") == "complete", "Stateless task was degraded")
	_expect(
		(result.get("map_candidates", []) as Array).size() == 1
		and result.get("candidate_delivery_status", "") == "local_validated",
		"Substantive participant input did not create a validated map fallback"
	)
	_expect(
		conversation.persisted_requests == 0 and api_service.requests.size() == 1,
		"Workshop inference used persistent chat history"
	)
	var request: Dictionary = api_service.requests[0]
	var settings: Dictionary = request.get("settings", {})
	var request_prompt: String = request.get("messages", [])[0].get("content", "")
	_expect(
		settings.get("max_retries") == 1
		and settings.get("force_json") == true
		and settings.get("timeout_sec") == 180.0,
		"Ollama task budgets were not applied"
	)
	_expect(
		request_prompt.contains("Reach a bounded recommendation.")
		and request_prompt.contains("Capacity")
		and not request_prompt.contains("couldn't generate a response"),
		"Curated Workshop context was incomplete or retained an error entry"
	)
	api_service.should_succeed = false
	var unavailable_result: Dictionary = await coordinator.collect(
		conversation,
		[],
		{
			"sender": "Facilitator",
			"message": "We could use modular storage to reduce transition risk.",
		},
		{"name": "Test Workshop"},
		{"current_stage_name": "Frame"}
	)
	_expect(
		unavailable_result.get("status", "") == "degraded"
		and (
			unavailable_result.get("map_candidates", []) as Array
		).size() == 1
		and unavailable_result.get("candidate_delivery_status", "")
		== "local_validated",
		"Provider failure discarded a valid participant-stated map proposition"
	)


func _test_stateless_cloud_task_timeout() -> void:
	# Regression guard: a cloud/"thinking" model (e.g. Grok) generating the
	# full specialist JSON envelope can legitimately take longer than the
	# api_service default 25s read timeout. Without a per-task override this
	# surfaces as a generic connection error and the degraded fallback even
	# though the model is capable — see workshop_stateless_model_task.gd.
	var coordinator: RefCounted = CoordinatorScript.new()
	var conversation := FakeStatelessConversation.new()
	var api_service := FakeApiService.new()
	conversation.api_service = api_service
	conversation.ai_model_manager.current_model = "grok-4.5"
	conversation.ai_model_manager.provider_id = "xai"
	api_service.response_text = JSON.stringify({
		"schema_version": 1,
		"contributions": [
			{"role_id": "systems_consequences", "summary": "Dependency summary."},
			{"role_id": "stakeholder_communication", "summary": "Stakeholder summary."},
			{"role_id": "risk_feasibility", "summary": "Risk summary."},
			{"role_id": "options_innovation", "summary": "Options summary."},
		],
		"map_candidates": [],
		"assistant_response": "One bounded cloud response.",
	})
	var result: Dictionary = await coordinator.collect(
		conversation,
		[],
		{
			"sender": "Facilitator",
			"message": "We can invest in grid storage to improve resilience.",
		},
		{"name": "Test Workshop", "objective": "Reach a bounded recommendation."},
		{"current_stage_name": "Frame"}
	)
	_expect(result.get("status", "") == "complete", "Cloud stateless task was degraded")
	_expect(api_service.requests.size() == 1, "Cloud stateless task issued an unexpected request count")
	var settings: Dictionary = api_service.requests[0].get("settings", {})
	_expect(
		settings.get("max_retries") == 1
		and settings.get("timeout_sec") == 120.0
		and not settings.has("force_json"),
		"Cloud provider task did not receive extended-timeout budgets"
	)


func _test_synthesis_and_vote_boundary() -> void:
	var story_state_node: Node = root.get_node_or_null("StoryState")
	_expect(story_state_node != null, "StoryState autoload is unavailable")
	if not story_state_node:
		return
	story_state_node.call("set_state", {
		"story_log": [],
		"current_turn": 0,
		"current_phase": "setup",
		"phase_turn_count": 0,
	})
	var fake_conversation := FakeConversation.new()
	fake_conversation.response_text = (
		"Two implementation constraints and a phased option need facilitator review. " +
		"No decision has been recorded."
	)
	var session_record_script: GDScript = load(SESSION_RECORD_PATH) as GDScript
	_expect(session_record_script != null, "Session Record script did not load")
	if not session_record_script:
		return
	var session_record: RefCounted = session_record_script.new()
	var initial_state: Dictionary = story_state_node.call("get_state")
	var before_count: int = initial_state.get("story_log", []).size()
	var result: Dictionary = await session_record.synthesize_turn(
		fake_conversation,
		[
			{"role_title": "Risk & Feasibility Analyst", "summary": "Capacity is constrained."},
			{"role_title": "Options & Innovation Analyst", "summary": "A phased option is available."},
		],
		{"buckets": {}, "current_stage_name": "Frame"},
		{"name": "Test Workshop"},
		{"message": "What should we do?"}
	)
	var updated_state: Dictionary = story_state_node.call("get_state")
	var story_log: Array = updated_state.get("story_log", [])
	_expect(fake_conversation.requests.size() == 1, "Synthesis did not use one request")
	_expect(story_log.size() == before_count + 1, "Synthesis did not post exactly one message")
	_expect(
		String(story_log.back().get("sender", "")) == "Session Record",
		"Workshop synthesis used the wrong visible sender"
	)
	_expect(result.get("status", "") == "complete", "Successful synthesis was marked degraded")

	fake_conversation.response_text = ""
	var fallback_result: Dictionary = await session_record.synthesize_turn(
		fake_conversation,
		[],
		{},
		{},
		{}
	)
	_expect(
		not String(fallback_result.get("message", "")).is_empty(),
		"Empty synthesis did not produce a deterministic fallback"
	)


func _test_reasoning_panel_states() -> void:
	var shell_node: Control = WorkspaceScene.instantiate() as Control
	var conversation_region_node := TabContainer.new()
	var session_record_region_node := VBoxContainer.new()
	var record_button_node := Button.new()
	var story_log_system_node := Control.new()
	story_log_system_node.name = "StoryLogSystem"
	root.add_child(shell_node)
	root.add_child(conversation_region_node)
	conversation_region_node.add_child(session_record_region_node)
	conversation_region_node.add_child(story_log_system_node)
	root.add_child(record_button_node)
	var workspace_controller: RefCounted = WorkspaceControllerScript.new()
	_expect(
		workspace_controller.mount(
			shell_node,
			conversation_region_node,
			session_record_region_node,
			record_button_node
		),
		"Reasoning fixture workspace failed to mount"
	)
	var toggle_node: CheckButton = (
		workspace_controller.get_control("ShowReasoningToggle") as CheckButton
	)
	var disclosure_node: Control = (
		workspace_controller.get_control("ReasoningDisclosure") as Control
	)
	_expect(not toggle_node.button_pressed, "Reasoning control was not collapsed by default")
	_expect(not disclosure_node.visible, "Reasoning disclosure was visible by default")
	toggle_node.button_pressed = true
	_expect(disclosure_node.visible, "Reasoning disclosure did not expand")
	workspace_controller.call("_on_specialist_trace_updated", {
		"turn_id": "turn_1",
		"status": "degraded",
		"persistence_status": "unavailable",
		"model_id": "test-model",
		"contributions": [],
	})
	var status_node: Label = workspace_controller.get_control("ReasoningStatus") as Label
	_expect(
		status_node.text.contains("degraded") and status_node.text.contains("unavailable"),
		"Reasoning panel did not truthfully show degraded/unavailable state"
	)
	toggle_node.button_pressed = false
	_expect(not disclosure_node.visible, "Reasoning disclosure was not revocable")
	shell_node.queue_free()
	conversation_region_node.queue_free()
	record_button_node.queue_free()
	await process_frame


func _test_trace_contract_and_nonblocking_source() -> void:
	var trace_store: Node = TraceStoreScript.new()
	var trace: Dictionary = trace_store.build_trace(
		"turn_1",
		{
			"status": "degraded",
			"failure_reason": "malformed_json",
			"model_id": "test-model",
			"contributions": [
				{
					"role_id": "risk_feasibility",
					"role_title": "Risk & Feasibility Analyst",
					"summary": "No role-specific claim retained.",
				},
			],
		},
		{"story_log_index": 1}
	)
	for required_key: String in [
		"session_id",
		"turn_id",
		"specialist_roles",
		"model_id",
		"synthesis_reference",
		"privacy",
		"retention",
		"status",
	]:
		_expect(trace.has(required_key), "Trace is missing field: " + required_key)
	var privacy: Dictionary = trace.get("privacy", {})
	_expect(
		privacy.get("contains_chain_of_thought", true) == false,
		"Trace contract permits chain-of-thought retention"
	)
	var source_text: String = FileAccess.get_file_as_string(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_specialist_trace_store.gd"
	)
	_expect(
		source_text.contains('call_deferred("_persist_latest_trace"'),
		"Trace persistence is not fire-and-forget"
	)
	trace_store.free()


func _test_finalization_seam_and_story_nonregression() -> void:
	var source_text: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/agents/ai_character_agent.gd"
	)
	_expect(source_text.contains("func _finalize_turn("), "Shared finalization seam is missing")
	_expect(
		source_text.contains("func _finalize_turn_visible_ensemble(")
		and source_text.contains("func _finalize_turn_hidden_synthesis("),
		"Finalization helpers are incomplete"
	)
	_expect(
		source_text.contains('batch_result.get("assistant_response", "")')
		and not source_text.contains(
			"_workshop_session_record.synthesize_turn("
		),
		"Workshop hidden synthesis still performs a second model call"
	)
	_expect(
		not source_text.contains("_workshop_session_record.post(message_text)"),
		"Hidden synthesis still posts the full narrative to the log every turn"
	)
	_expect(
		source_text.contains("_cache_session_record_synthesis(message_text, batch_result)"),
		"Hidden synthesis no longer caches the narrative for on-demand /synthesis recall"
	)
	_expect(
		source_text.contains('ws["session_record_latest_text"] = message_text')
		and source_text.contains(
			"ws[\"session_record_pulse\"] = WorkshopSessionRecordPulseScript.build_pulse(batch_result)"
		),
		"Session Record caching no longer stores both the full text and the ambient pulse"
	)
	var director_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/agents/DirectorAgent.gd"
	)
	var actor_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/agents/ActorAgent.gd"
	)
	_expect(not director_source.is_empty() and not actor_source.is_empty(), "Story agents failed to load")
	_expect(
		source_text.contains("StoryState.add_log_entry(character_name, dialogue)"),
		"Visible ensemble posting behavior is no longer present"
	)


func _test_session_record_pulse_helper() -> void:
	var pulse_script: GDScript = load(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_pulse.gd"
	) as GDScript
	_expect(pulse_script != null, "Session Record pulse helper script did not load")
	if not pulse_script:
		return
	var multi_category_pulse: String = pulse_script.build_pulse({
		"map_candidates": [
			{"id": "a", "category": "cause"},
			{"id": "b", "category": "cause"},
			{"id": "c", "category": "opportunity"},
			{"id": "d", "category": ""},
			{"id": "e"},
			"not-a-dictionary",
		],
	})
	_expect(
		multi_category_pulse.contains("2 causes") and multi_category_pulse.contains("1 opportunity"),
		"Pulse text did not summarize mixed categories correctly: " + multi_category_pulse
	)
	_expect(
		multi_category_pulse.contains("/synthesis"),
		"Pulse text is missing the /synthesis recall hint: " + multi_category_pulse
	)
	var singular_pulse: String = pulse_script.build_pulse({
		"map_candidates": [{"id": "a", "category": "effect"}],
	})
	_expect(
		singular_pulse.contains("1 effect") and not singular_pulse.contains("1 effects"),
		"Pulse text pluralized a singular count: " + singular_pulse
	)
	var empty_pulse: String = pulse_script.build_pulse({})
	_expect(
		empty_pulse.contains("no new claims"),
		"Empty batch result should produce a no-new-claims pulse: " + empty_pulse
	)
	var missing_candidates_pulse: String = pulse_script.build_pulse({"map_candidates": "not-an-array"})
	_expect(
		missing_candidates_pulse.contains("no new claims"),
		"Malformed map_candidates should fall back to the no-new-claims pulse: " + missing_candidates_pulse
	)
	var unknown_category_pulse: String = pulse_script.build_pulse({
		"map_candidates": [{"id": "a", "category": "unexpected_future_category"}],
	})
	_expect(
		unknown_category_pulse.contains("1 unexpected_future_category"),
		"Pulse text dropped an unrecognized category instead of listing it: " + unknown_category_pulse
	)


func _test_synthesis_recall_command_wiring() -> void:
	var flow_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/core/game_session_ai_flow_utils.gd"
	)
	_expect(
		flow_source.contains("_handle_workshop_synthesis_command(trimmed_input, owner)"),
		"/synthesis command handler is not wired into player input dispatch"
	)
	_expect(
		flow_source.contains('lower == "/synthesis" or lower.begins_with("/synthesis ")'),
		"/synthesis command no longer recognizes its own slash syntax"
	)
	_expect(
		flow_source.contains('ws.get("session_record_latest_text", "")'),
		"/synthesis command no longer recalls the cached Session Record narrative"
	)
	var settings_panel_text: String = FileAccess.get_file_as_string(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_settings_panel.tscn"
	)
	_expect(
		settings_panel_text.contains("/synthesis"),
		"Facilitator command reference does not document /synthesis"
	)


func _test_session_record_status_bar_wiring() -> void:
	var shell_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_workspace_shell.tscn"
	)
	_expect(
		shell_source.contains('name="SessionRecordPulseLabel"')
		and shell_source.contains("unique_name_in_owner = true")
		and shell_source.contains("clip_text = false")
		and shell_source.contains("autowrap_mode = 3")
		and shell_source.contains('name="WaitProgressSlot"'),
		"Workspace shell no longer defines a wrapping Session Record pulse with a wait-progress slot"
	)
	var workspace_controller_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_controller.gd"
	)
	_expect(
		workspace_controller_source.contains("func set_session_record_pulse("),
		"Workspace controller no longer exposes set_session_record_pulse"
	)
	_expect(
		workspace_controller_source.contains('"participants": "ParticipantsPanel"')
		and workspace_controller_source.contains('"SessionRecordPulseLabel"'),
		"Status footer pulse must not be gated behind the hideable participants panel"
	)
	var controller_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_controller.gd"
	)
	_expect(
		controller_source.contains("_refresh_session_record_pulse(new_state)")
		and controller_source.contains("_workspace_controller.set_session_record_pulse(trimmed)"),
		"Story-state updates no longer forward the Session Record pulse to the status bar"
	)
	var ui_utils_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/core/game_session_ui_utils.gd"
	)
	_expect(
		ui_utils_source.contains("func _resolve_progress_bar(")
		and ui_utils_source.contains("as Range")
		and ui_utils_source.contains("func _fit_wait_progress_host(")
		and not ui_utils_source.contains("as ProgressBar"),
		"AI wait progress bar must resolve TextureProgressBar via Range and host in the footer slot"
	)


## Regression guard for the bug where a facilitator turn shows a Narrator
## "Timed out waiting for an AI response" error while the AI Assistant/Session
## Record panels still fill in moments later. Root cause: ai_character_agent.gd
## runs its own in-scene watchdog timer independent of the HTTP-layer timeout
## in workshop_stateless_model_task.gd, and the watchdog used to fire first for
## cloud providers (90s watchdog vs. a 120s HTTP budget), marking the
## generation stale before the (still-successful) response could be posted.
func _test_hidden_synthesis_watchdog_outlasts_cloud_timeout() -> void:
	var agent_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/agents/ai_character_agent.gd"
	)
	var task_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_stateless_model_task.gd"
	)
	var cloud_timeout_regex: RegEx = RegEx.new()
	cloud_timeout_regex.compile("CLOUD_TIMEOUT_SECONDS:\\s*float\\s*=\\s*([0-9.]+)")
	var cloud_timeout_match: RegExMatch = cloud_timeout_regex.search(task_source)
	_expect(
		cloud_timeout_match != null,
		"Could not find CLOUD_TIMEOUT_SECONDS in workshop_stateless_model_task.gd"
	)
	if cloud_timeout_match == null:
		return
	var cloud_timeout_seconds: float = float(cloud_timeout_match.get_string(1))
	var watchdog_regex: RegEx = RegEx.new()
	watchdog_regex.compile("WORKSHOP_CLOUD_RESPONSE_TIMEOUT\\s*:=\\s*([0-9.]+)")
	var watchdog_match: RegExMatch = watchdog_regex.search(agent_source)
	_expect(
		watchdog_match != null,
		"ai_character_agent.gd no longer defines a workshop-specific cloud watchdog timeout"
	)
	if watchdog_match == null:
		return
	var watchdog_seconds: float = float(watchdog_match.get_string(1))
	_expect(
		watchdog_seconds > cloud_timeout_seconds,
		(
			"In-scene watchdog (%.0fs) no longer outlasts the cloud HTTP timeout (%.0fs) — "
			+ "it will fire before a slow-but-successful response can be posted"
		) % [watchdog_seconds, cloud_timeout_seconds]
	)
	_expect(
		agent_source.contains(
			"if _get_runtime_profile_id() == SessionTypeRuntimeProfileScript.HIDDEN_SYNTHESIS:"
		)
		and agent_source.contains("return WORKSHOP_CLOUD_RESPONSE_TIMEOUT"),
		"_response_timeout_seconds() no longer applies the workshop cloud watchdog timeout"
	)


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst Stage 5 tests: all passed")
		quit(0)
		return
	for failure_message: String in _failures:
		push_error(failure_message)
	quit(1)
