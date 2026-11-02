# Location: ScenSyn/scripts/agents/ai_character_agent.gd
# MODIFIED: This agent now orchestrates the Director/Actor model.

extends Node

const DirectorAgent = preload("res://ScenSyn/scripts/agents/DirectorAgent.gd")
const ActorAgentScript = preload("res://ScenSyn/scripts/agents/ActorAgent.gd")
const SessionTypeRuntimeProfileScript = preload(
	"res://ScenSyn/scripts/agents/session_type_runtime_profile.gd"
)
const WorkshopSpecialistCoordinatorScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_specialist_coordinator.gd"
)
const WorkshopSpecialistTraceStoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_specialist_trace_store.gd"
)
const WorkshopSessionRecordPulseScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_pulse.gd"
)
const WORKSHOP_SESSION_RECORD_PATH := (
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_session_record.gd"
)
const WORKSHOP_SYNTHESIS_SENDER := "Session Record"

# GUARDRAIL: No hardcoded character names
# - This orchestrator must not special-case any character by name.
# - Opening constraints, addressing defaults, and delivery specifics
#   must be sourced from the active scenario through the metaprompt manager
#   (e.g., get_opening_constraints, get_character_delivery_rules).
# - Speaker planning logic should be statistical/structural (e.g., least-recent),
#   not name-based.
var director_agent: DirectorAgent
var actor_agent: ActorAgent # A single instance reused for all actor calls
var ai_controlled_names: Array = []
var allow_ai_for_player_characters: bool = false
var _awaiting_response := false
var _response_timer := 0.0
const RESPONSE_TIMEOUT := 90.0
## Workshop Catalyst's hidden-synthesis call budgets up to
## workshop_stateless_model_task.gd::CLOUD_TIMEOUT_SECONDS (120s) for cloud
## providers. This in-scene watchdog is a separate, independent timer from
## that HTTP-layer timeout, so it must stay comfortably above it (matching
## the +30s buffer already used for OLLAMA_RESPONSE_TIMEOUT below) or it
## fires first: it posts a spurious "Timed out" Narrator error and marks the
## generation stale via _generation_id, while the still-in-flight request
## later succeeds anyway and quietly populates the AI Assistant/Session
## Record panels — looking like the log "forgot" a response that arrived.
const WORKSHOP_CLOUD_RESPONSE_TIMEOUT := 150.0
const OLLAMA_RESPONSE_TIMEOUT := 210.0
var _generation_id := 0
var _opening_exchange_done := false
var _ai_turn_count := 0 # Count of completed AI turns (used to space system cues)
var _last_cue_ai_turn := -1 # Last AI turn index when a system cue was emitted
var _next_cue_gap := 3 # Next AI-turn gap before emitting a cue (randomized)
var _last_turn_outcome := "" # Track last turn_outcome to encourage rotation
var _last_processed_index := -1 # Prevent double-firing before human input lands
var _workshop_specialist_coordinator: RefCounted
var _workshop_session_record: RefCounted
var _workshop_trace_store: Node

const _AI_ERROR_USER_MESSAGE := "The AI couldn't generate a response right now. Check your Hub/API settings in \u2630 \u2192 Settings, or try another model (for example Ollama if you use it locally)."

var _cached_metaprompt_manager = null
var _cached_conv_manager = null
var _cached_game_flow_manager = null
var _cache_refresh_time := 0.0
const CACHE_REFRESH_INTERVAL := 10.0

func _ready():
	print("[AICharacterAgent] Initializing...")
	add_to_group("AICharacterAgent")
	
	_refresh_caches()
	
	# Instantiate our new agents
	director_agent = DirectorAgent.new()
	print("[AICharacterAgent] Initializing DirectorAgent with metaprompt_manager: ", _cached_metaprompt_manager, " (class: ", _cached_metaprompt_manager.get_class(), ")")
	director_agent.initialize(_cached_conv_manager, _cached_metaprompt_manager)
	
	actor_agent = ActorAgentScript.new()
	actor_agent.initialize(_cached_conv_manager, _cached_metaprompt_manager)
	_workshop_specialist_coordinator = WorkshopSpecialistCoordinatorScript.new()
	var workshop_record_script: GDScript = load(WORKSHOP_SESSION_RECORD_PATH) as GDScript
	if workshop_record_script:
		_workshop_session_record = workshop_record_script.new()
	_workshop_trace_store = WorkshopSpecialistTraceStoreScript.new()
	_workshop_trace_store.name = "WorkshopSpecialistTraceStore"
	add_child(_workshop_trace_store)
	
	if StoryState and StoryState.has_signal("state_updated"):
			StoryState.state_updated.connect(_on_state_updated)
	if Network and Network.has_signal("peer_character_selected"):
			Network.peer_character_selected.connect(_on_character_control_changed)
	if Global and Global.has_signal("scenario_changed"):
		Global.scenario_changed.connect(_on_scenario_changed)
	
	_update_ai_character_list()
	var pai = Global.get_player_auto_input() if Global and Global.has_method("get_player_auto_input") else null
	if pai and pai.has_signal("auto_input_changed"):
		pai.auto_input_changed.connect(_on_auto_input_changed)
		if pai.is_enabled():
			_set_allow_ai_for_player_characters(true)
	print("[AICharacterAgent] Ready.")

func _process(delta: float):
	if _awaiting_response:
		_response_timer += delta
		if _response_timer > _response_timeout_seconds():
			print("[AICharacterAgent] ERROR: Response timed out (gen %d). Resetting state." % _generation_id)
			_generation_id += 1
			_awaiting_response = false
			_response_timer = 0.0
			_show_ai_error_to_user("Timed out waiting for an AI response.", "The current request exceeded the in-scene response timeout.")
			var game_session = get_tree().get_first_node_in_group("game_session")
			if game_session: game_session.animate_progress_complete(false)


	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _cache_refresh_time > CACHE_REFRESH_INTERVAL:
		_refresh_caches()
		_cache_refresh_time = current_time


func _response_timeout_seconds() -> float:
	if (
		_cached_conv_manager
		and "ai_model_manager" in _cached_conv_manager
		and _cached_conv_manager.ai_model_manager
	):
		var model_manager: Object = _cached_conv_manager.ai_model_manager
		var model_id: String = String(
			model_manager.call("get_current_model")
		).strip_edges()
		if (
			not model_id.is_empty()
			and String(
				model_manager.call("get_provider_for_model", model_id)
			) == "ollama"
		):
			return OLLAMA_RESPONSE_TIMEOUT
	if _get_runtime_profile_id() == SessionTypeRuntimeProfileScript.HIDDEN_SYNTHESIS:
		return WORKSHOP_CLOUD_RESPONSE_TIMEOUT
	return RESPONSE_TIMEOUT


func _refresh_caches():
	_cached_metaprompt_manager = Global.get_metaprompt_manager()
	_cached_conv_manager = Global.get_conversation_manager()
	_cached_game_flow_manager = Global.get_game_flow_manager()

func _on_state_updated(_new_state: Dictionary):
	# AI generation must only run on the server (or in single-player).
	# Clients receive state updates via sync_story_state and must not generate independently.
	if Network.get_connected_peers().size() > 0 and not Network.is_server():
		return
	if not _awaiting_response:
		_maybe_generate_ai_response()

func _on_character_control_changed(_peer_id: int, _character_data: Dictionary):
	_update_ai_character_list()

func _on_scenario_changed(_scenario_name: String):
	print("[AICharacterAgent] Scenario changed, refreshing caches and re-initializing agents...")
	_refresh_caches()
	# Re-initialize agents with the new metaprompt_manager
	if director_agent:
		director_agent.initialize(_cached_conv_manager, _cached_metaprompt_manager)
	if actor_agent:
		actor_agent.initialize(_cached_conv_manager, _cached_metaprompt_manager)
	# Scenario selection materially changes which characters exist.
	# Refresh the AI-controlled character list so we can respond immediately after load.
	_opening_exchange_done = false
	_update_ai_character_list()

func _update_ai_character_list():
	if _get_runtime_profile_id() == SessionTypeRuntimeProfileScript.HIDDEN_SYNTHESIS:
		ai_controlled_names = []
		if _cached_metaprompt_manager and _cached_metaprompt_manager.has_method("set_cast"):
			_cached_metaprompt_manager.set_cast([])
		return
	if Network and Network.has_method("get_ai_controlled_character_names"):
		ai_controlled_names = Network.get_ai_controlled_character_names()
		if allow_ai_for_player_characters:
			_expand_ai_names_with_all_scenario_characters()
		var named_cast: Array = []
		for cast_name_any in ai_controlled_names:
			var cast_name := String(cast_name_any).strip_edges()
			if cast_name.is_empty() or cast_name in named_cast:
				continue
			named_cast.append(cast_name)
		ai_controlled_names = named_cast
		print("[AICharacterAgent] Updated AI character list: ", ai_controlled_names,
			" (allow_player=%s)" % str(allow_ai_for_player_characters))
	# Notify theme of the full cast (AI + human) for voting threshold calculation.
	# Uses all named scenario characters so a human participant's vote counts too.
	if _cached_metaprompt_manager and _cached_metaprompt_manager.has_method("set_cast"):
		var all_cast: Array = []
		if Global and Global.has_method("get_current_scenario"):
			var scenario: Dictionary = Global.get_current_scenario()
			var chars_any: Variant = scenario.get("characters", [])
			var chars: Array = chars_any if typeof(chars_any) == TYPE_ARRAY else []
			for c_any in chars:
				var cname: String = c_any.get("name", "") if typeof(c_any) == TYPE_DICTIONARY else str(c_any)
				if not cname.is_empty():
					all_cast.append(cname)
		if all_cast.is_empty():
			all_cast = ai_controlled_names.duplicate()
		_cached_metaprompt_manager.set_cast(all_cast)

func _expand_ai_names_with_all_scenario_characters() -> void:
	if not Global or not Global.has_method("get_game_flow_manager"):
		return
	var gfm = Global.get_game_flow_manager()
	if gfm == null or not gfm.has_method("get_current_scenario"):
		return
	var scenario: Dictionary = gfm.get_current_scenario()
	var characters: Array = scenario.get("characters", [])
	for c in characters:
		var cname: String = c.get("name", "") if typeof(c) == TYPE_DICTIONARY else str(c)
		if not cname.is_empty() and cname not in ai_controlled_names:
			ai_controlled_names.append(cname)

func _on_auto_input_changed(enabled: bool) -> void:
	_set_allow_ai_for_player_characters(enabled)

func _set_allow_ai_for_player_characters(enabled: bool) -> void:
	if allow_ai_for_player_characters == enabled:
		return
	allow_ai_for_player_characters = enabled
	print("[AICharacterAgent] allow_ai_for_player_characters = %s" % str(enabled))
	_update_ai_character_list()

func set_allow_ai_for_player_characters(enabled: bool) -> void:
	_set_allow_ai_for_player_characters(enabled)

func is_busy() -> bool:
	return _awaiting_response

func mark_story_log_caught_up() -> void:
	var story_log = StoryState.get_state().get("story_log", []) if StoryState else []
	_last_processed_index = story_log.size() - 1

func _maybe_generate_ai_response():
	if Global and Global.is_loading_story_log:
		return
	var story_log = StoryState.get_state().get("story_log", [])
	if story_log.is_empty(): return

	var last_entry = story_log.back()
	var last_sender = last_entry.get("sender", "")
	var last_index: int = story_log.size() - 1
	# The cached cast can still list the human (single-player never writes peer_info).
	# Refresh before deciding, or a typed line is declined as "an AI character".
	_update_ai_character_list()
	
	# Only respond to human-player turns.
	# Build the full set of non-triggering senders: AI characters plus all system voices
	# reported by the active metaprompt manager (Narrator, Facilitator, Session Record, etc.).
	var system_senders: Array[String] = ["Narrator", "Facilitator", "Facilitator Note"]
	if _cached_metaprompt_manager and _cached_metaprompt_manager.has_method("get_system_senders"):
		system_senders = _cached_metaprompt_manager.get_system_senders()
	var should_trigger_from_system := false
	if last_sender in system_senders and _cached_metaprompt_manager and _cached_metaprompt_manager.has_method("should_trigger_ai_from_system_entry"):
		should_trigger_from_system = bool(_cached_metaprompt_manager.should_trigger_ai_from_system_entry(String(last_sender), String(last_entry.get("message", ""))))
	if last_sender in ai_controlled_names or (last_sender in system_senders and not should_trigger_from_system):
		# Named, because declining to answer is indistinguishable from a model that never
		# replied: a session whose human turns were attributed to a system voice simply
		# stopped answering, with nothing in the log saying why.
		print("[AICharacterAgent] Not answering '%s' — %s" % [
			last_sender,
			"an AI character" if last_sender in ai_controlled_names else "a system voice"
		])
		return
	# Debounce: only respond once per new human message
	if last_index <= _last_processed_index:
		return

	print("[AICharacterAgent] Triggering Director/Actor response flow...")
	await generate_ai_character_response(last_sender, last_entry.get("message", ""))
	_last_processed_index = last_index

func _determine_priority_speaker(human_input: String) -> String:
	# Check if the human input explicitly names one of the AI characters
	for ai_name in ai_controlled_names:
		# Use word boundaries to avoid a short name matching inside a longer one.
		var pattern = "\\b" + ai_name + "\\b"
		var regex = RegEx.new()
		regex.compile(pattern)
		if regex.search(human_input):
			print("[AICharacterAgent] Priority speaker identified: ", ai_name)
			return ai_name
	return ""

func generate_ai_character_response(human_character_name: String, human_input: String, forced_priority_speaker: String = ""):
	if ai_controlled_names.is_empty():
		_update_ai_character_list()
	var runtime_profile_id: String = _get_runtime_profile_id()
	if (
		_awaiting_response
		or (
			runtime_profile_id != SessionTypeRuntimeProfileScript.HIDDEN_SYNTHESIS
			and ai_controlled_names.is_empty()
		)
	):
		if ai_controlled_names.is_empty():
			print("[AICharacterAgent] Not answering — no AI-controlled characters in the current scenario")
		return
	_generation_id += 1
	var my_gen := _generation_id
	_awaiting_response = true
	_response_timer = 0.0
	var turn_started_ms: int = Time.get_ticks_msec()
	var first_line_ms: int = -1
	
	var game_session = get_tree().get_first_node_in_group("game_session")
	if game_session: game_session.animate_progress_start()

	var story_log = StoryState.get_state().get("story_log", [])
	var scenario = _cached_game_flow_manager.get_current_scenario() if _cached_game_flow_manager else {}
	if Global and Global.has_method("get_conversation_manager"):
		var latest_conv := Global.get_conversation_manager()
		if latest_conv != null and latest_conv != _cached_conv_manager:
			_cached_conv_manager = latest_conv
			if director_agent:
				director_agent.initialize(_cached_conv_manager, _cached_metaprompt_manager)
			if actor_agent:
				actor_agent.initialize(_cached_conv_manager, _cached_metaprompt_manager)
	if Global and Global.has_method("get_metaprompt_manager"):
		var latest_manager = Global.get_metaprompt_manager()
		if latest_manager and latest_manager != _cached_metaprompt_manager:
			_cached_metaprompt_manager = latest_manager
			if director_agent:
				director_agent.initialize(_cached_conv_manager, _cached_metaprompt_manager)
			if actor_agent:
				actor_agent.initialize(_cached_conv_manager, _cached_metaprompt_manager)
	var current_phase = StoryState.get_narrative_phase() if StoryState else "setup"
	if runtime_profile_id == SessionTypeRuntimeProfileScript.HIDDEN_SYNTHESIS:
		var hidden_messages_added: int = await _generate_hidden_synthesis_turn(
			story_log,
			{"sender": human_character_name, "message": human_input},
			scenario,
			runtime_profile_id
		)
		if my_gen != _generation_id:
			return
		if hidden_messages_added > 0:
			StoryState.advance_turn()
			_ai_turn_count += 1
		else:
			_show_ai_error_to_user(
				"Hidden synthesis returned no usable response.",
				"The deterministic fallback could not be posted."
			)
		if game_session:
			game_session.animate_progress_complete(hidden_messages_added > 0)
		_awaiting_response = false
		call_deferred("_maybe_generate_ai_response")
		return

	# 1. Narrative mandate. The cast list is filled in after the speaker plan,
	# because that plan is what adds scenario characters the network list omitted.
	var narrative_mandate = ""
	if _cached_metaprompt_manager and _cached_metaprompt_manager.has_method("get_theme_creative_mission"):
		narrative_mandate = _cached_metaprompt_manager.get_theme_creative_mission(current_phase, scenario)

	# 2. Plan Speakers, now with Addressee Priority.
	# Naming someone puts them first. It does not collapse the turn to a single
	# reply: the short range in _plan_next_response_speakers still decides how
	# many characters speak.
	var priority_speaker = forced_priority_speaker if forced_priority_speaker != "" else _determine_priority_speaker(human_input)
	var planned_speakers: Array = _plan_next_response_speakers(story_log, human_character_name)
	var rolled_count: int = maxi(planned_speakers.size(), 1)
	if not priority_speaker.is_empty() and priority_speaker not in _non_actor_names(human_character_name):
		planned_speakers.erase(priority_speaker)
		planned_speakers.push_front(priority_speaker)
		if planned_speakers.size() > rolled_count:
			planned_speakers = planned_speakers.slice(0, rolled_count)
	# Enforce opening constraints (scenario-driven)
	planned_speakers = _enforce_opening_constraints(scenario, story_log, planned_speakers, human_character_name)
	if planned_speakers.is_empty():
		print("[AICharacterAgent] No speakers planned. Aborting.")
		_awaiting_response = false
		if game_session: game_session.animate_progress_complete(false)
		return
	var all_ai_character_data = []
	for char_name in ai_controlled_names:
		all_ai_character_data.append(_get_enriched_character_data(scenario, char_name))
	
	# 3. Call Director for a scene plan, passing the scenario data directly.
	var human_input_dict = {"sender": human_character_name, "message": human_input}
	var plan_result = await director_agent.generate_scene_plan(story_log, human_input_dict, all_ai_character_data, planned_speakers, current_phase, narrative_mandate, scenario)
	_response_timer = 0.0
	if my_gen != _generation_id:
		return
	_log_model_diagnostics()
	
	if plan_result.has("error") or not plan_result.has("plan"):
		print("[AICharacterAgent] ERROR: Director failed to return a valid plan. Triggering fallback. ", plan_result.get("error", "Reason unknown."))
		var fallback_ok := await _trigger_fallback_response(story_log, human_character_name)
		if not fallback_ok:
			_show_ai_error_to_user(str(plan_result.get("error", "Director failed to return a valid plan.")), str(plan_result.get("details", "")))
		_awaiting_response = false
		_response_timer = 0.0
		if game_session: game_session.animate_progress_complete(fallback_ok)
		return
	
	# 4. Validate the plan and call Actors using Cue Cards
	var processed_plan: Array = plan_result.get("plan", [])
	# Accumulates actual prior responses so later speakers in the same batch
	# can hear what earlier speakers already said (injected via weaver_context).
	var in_batch_responses: Array[Dictionary] = []
	# Each line is posted as soon as it exists rather than the cluster landing at once. A
	# turn plans up to three speakers and their calls run in sequence, so holding the first
	# line until the last one returned left the session silent for the length of all of
	# them — the wait a participant notices, and it grew with every extra speaker.
	var messages_added: int = 0
	# What the actors see stays the log as it was when the scene was planned; posting
	# earlier lines mid-batch would otherwise feed them back a second time, once here and
	# once as weaver_context.
	var planning_log: Array = story_log.duplicate()

	var verse_marker := ""
	if _cached_metaprompt_manager and _cached_metaprompt_manager.has_method("get_verse_precomposed_marker"):
		verse_marker = str(_cached_metaprompt_manager.get_verse_precomposed_marker())

	for cue_card in processed_plan:
		var character_name = cue_card.get("character_name", "")
		if character_name not in ai_controlled_names:
			print("[AICharacterAgent] WARNING: Director tried to generate a line for non-AI character '", character_name, "'. Skipping.")
			continue

		cue_card["full_log_for_context"] = planning_log

		# Inject prior responses from this same batch into weaver_context so later speakers
		# are aware of — and can react to — what earlier speakers in this turn actually said.
		if not in_batch_responses.is_empty():
			var weaver_lines: Array[String] = []
			for prior: Dictionary in in_batch_responses:
				weaver_lines.append("%s: %s" % [String(prior.get("character", "")), String(prior.get("dialogue", ""))])
			cue_card["weaver_context"] = "\n".join(weaver_lines)

		var response_text := ""
		if not verse_marker.is_empty() and _cached_metaprompt_manager and _cached_metaprompt_manager.has_method("get_character_turn_obligation"):
			var obligation: String = _cached_metaprompt_manager.get_character_turn_obligation(character_name)
			if obligation.begins_with(verse_marker):
				response_text = obligation.substr(verse_marker.length()).strip_edges()
				print("[AICharacterAgent] Injecting precomposed text for %s" % character_name)
		if response_text.is_empty():
			response_text = await actor_agent.generate_dialogue_line(cue_card)
		_response_timer = 0.0
		if my_gen != _generation_id:
			return

		response_text = _coerce_opening_stall(response_text)

		# Allow theme to scan for structured tokens (vote signals, proposals) and strip them.
		if not (response_text == "..." or response_text.is_empty()):
			if _cached_metaprompt_manager and _cached_metaprompt_manager.has_method("process_actor_dialogue"):
				response_text = _cached_metaprompt_manager.process_actor_dialogue(character_name, response_text)

		var response_dict = {
			"character": character_name,
			"dialogue": response_text
		}
		if response_text == "..." or response_text.is_empty():
			response_dict["error"] = "Actor failed to generate line."
			# A planned speaker that says nothing is silently absent from the scene, which
			# reads as the turn having planned fewer speakers than it did.
			print("[AICharacterAgent] %s was planned but produced no line; skipping." % character_name)
		else:
			in_batch_responses.append({"character": character_name, "dialogue": response_text})

		# 5. Post this line through the runtime-profile seam, which stays the only place a
		# visible line is written, so a lost or rejected line is still just skipped.
		messages_added += await _finalize_turn(
			runtime_profile_id,
			{
				"processed_plan": [cue_card],
				"actor_responses": [response_dict],
			}
		)
		if messages_added > 0 and first_line_ms < 0:
			first_line_ms = Time.get_ticks_msec() - turn_started_ms

	# What the turn cost, so a slow provider can be told apart from a slow client: the
	# per-call [budget] lines add up to the model's share, and the rest is ours.
	# Planned and spoken are reported separately: the two differ when an actor's line is
	# rejected, and a turn that planned three speakers and posted one is a lost line rather
	# than a quiet scene.
	print("[turn] %d speaker(s) planned, %d spoke: first line %.1fs, all lines %.1fs" % [
		processed_plan.size(),
		messages_added,
		float(first_line_ms) / 1000.0,
		float(Time.get_ticks_msec() - turn_started_ms) / 1000.0,
	])
	if messages_added > 0:
		StoryState.advance_turn()
		_ai_turn_count += 1
		# Emit system cue after advancing the turn to avoid pre-planning interference
		_emit_system_cue_if_due(current_phase, scenario, StoryState.get_state().get("story_log", []))
	else:
		print("[AICharacterAgent] WARNING: Actors produced no valid dialogue. Triggering fallback.")
		var fallback_ok := await _trigger_fallback_response(story_log)
		if my_gen != _generation_id:
			return
		if not fallback_ok:
			_show_ai_error_to_user("The active AI model returned no usable dialogue.", "")
	# Against the log as it was before the turn: `story_log` is the live array, so
	# comparing it to itself could never report the entry a theme posted mid-turn.
	if game_session: game_session.animate_progress_complete(messages_added > 0 or StoryState.get_state().get("story_log", []).size() > planning_log.size())
	_awaiting_response = false
	# A theme-level system entry (e.g. a Session Record PROPOSAL) may have been
	# posted while this actor batch was still running. Re-check once idle so
	# themes that opt in via should_trigger_ai_from_system_entry can fire.
	call_deferred("_maybe_generate_ai_response")


func _get_runtime_profile_id() -> String:
	var session_type_id: String = "story_catalyst"
	if Global and "current_session_type" in Global:
		session_type_id = String(Global.current_session_type).strip_edges()
	return SessionTypeRuntimeProfileScript.for_session_type(session_type_id)


func _generate_hidden_synthesis_turn(
	story_log: Array,
	human_input: Dictionary,
	scenario: Dictionary,
	runtime_profile_id: String
) -> int:
	var state: Dictionary = StoryState.get_state() if StoryState else {}
	var workshop_state_any: Variant = state.get("workshop_catalyst", {})
	var workshop_state: Dictionary = (
		workshop_state_any if typeof(workshop_state_any) == TYPE_DICTIONARY else {}
	)
	var batch_result: Dictionary = await _workshop_specialist_coordinator.collect(
		_cached_conv_manager,
		story_log,
		human_input,
		scenario,
		workshop_state
	)
	_response_timer = 0.0
	return await _finalize_turn(
		runtime_profile_id,
		{
			"batch_result": batch_result,
			"human_input": human_input,
			"scenario": scenario,
			"workshop_state": workshop_state,
		}
	)


func _finalize_turn(runtime_profile_id: String, turn_payload: Dictionary) -> int:
	if runtime_profile_id == SessionTypeRuntimeProfileScript.HIDDEN_SYNTHESIS:
		return await _finalize_turn_hidden_synthesis(turn_payload)
	return _finalize_turn_visible_ensemble(turn_payload)


func _finalize_turn_visible_ensemble(turn_payload: Dictionary) -> int:
	var processed_plan_any: Variant = turn_payload.get("processed_plan", [])
	var processed_plan: Array = (
		processed_plan_any if typeof(processed_plan_any) == TYPE_ARRAY else []
	)
	var actor_responses_any: Variant = turn_payload.get("actor_responses", [])
	var actor_responses: Array = (
		actor_responses_any if typeof(actor_responses_any) == TYPE_ARRAY else []
	)
	var messages_added: int = 0
	for cue_card_any: Variant in processed_plan:
		if typeof(cue_card_any) != TYPE_DICTIONARY:
			continue
		var cue_card: Dictionary = cue_card_any
		var character_name: String = String(cue_card.get("character_name", ""))
		for response_any: Variant in actor_responses:
			if typeof(response_any) != TYPE_DICTIONARY:
				continue
			var response: Dictionary = response_any
			if response.get("character") == character_name and not response.has("error"):
				var dialogue: String = String(response.get("dialogue", "")).strip_edges()
				if not dialogue.is_empty():
					StoryState.add_log_entry(character_name, dialogue)
					messages_added += 1
					break
	return messages_added


func _finalize_turn_hidden_synthesis(turn_payload: Dictionary) -> int:
	var batch_result_any: Variant = turn_payload.get("batch_result", {})
	var batch_result: Dictionary = (
		batch_result_any if typeof(batch_result_any) == TYPE_DICTIONARY else {}
	)
	var message_text: String = String(
		batch_result.get("assistant_response", "")
	).strip_edges()
	var candidates_any: Variant = batch_result.get("map_candidates", [])
	var has_map_candidates: bool = (
		typeof(candidates_any) == TYPE_ARRAY and not (candidates_any as Array).is_empty()
	)
	# Map can still be populated when the narrative field is blank; keep pulse +
	# retain so the facilitator gets footer feedback whenever analysis ran.
	if message_text.is_empty() and not has_map_candidates:
		return 0
	if message_text.is_empty():
		message_text = (
			"Specialist analysis retained map candidates for this turn. "
			+ "Type /synthesis after the next full narrative pass for a prose recap."
		)
	# Full synthesis is cached for on-demand recall (facilitator types /synthesis)
	# rather than posted to the visible log every turn — see ADR 0009's
	# 2026-08-03 clarification.
	_cache_session_record_synthesis(message_text, batch_result)
	var synthesis_result: Dictionary = {
		"message": message_text,
		"status": String(batch_result.get("status", "degraded")),
		"failure_reason": String(batch_result.get("failure_reason", "")),
		"model_id": String(batch_result.get("model_id", "default")),
		"created_at": String(batch_result.get("completed_at", "")),
	}
	var turn_id: String = "turn_%06d" % (_ai_turn_count + 1)
	var synthesis_reference: Dictionary = {
		"sender": WORKSHOP_SYNTHESIS_SENDER,
		"story_log_index": StoryState.get_state().get("story_log", []).size() - 1,
		"message_hash": message_text.sha256_text(),
		"model_id": String(synthesis_result.get("model_id", "default")),
		"status": String(synthesis_result.get("status", "degraded")),
	}
	var workshop_state_any: Variant = turn_payload.get("workshop_state", {})
	var workshop_state: Dictionary = (
		workshop_state_any if typeof(workshop_state_any) == TYPE_DICTIONARY else {}
	)
	var stage_name: String = String(
		workshop_state.get("current_stage_name", "")
	).strip_edges()
	_workshop_trace_store.retain_and_persist(
		turn_id,
		batch_result,
		synthesis_reference,
		stage_name
	)
	return 1


## Stores the full Session Record narrative for on-demand recall (the /synthesis
## facilitator command) and refreshes the ambient status-bar pulse, instead of
## posting the full narrative into the visible log every turn.
func _cache_session_record_synthesis(message_text: String, batch_result: Dictionary) -> void:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return
	var state: Dictionary = StoryState.get_state()
	var ws_any: Variant = state.get("workshop_catalyst", {})
	var ws: Dictionary = (
		(ws_any as Dictionary).duplicate(true)
		if typeof(ws_any) == TYPE_DICTIONARY
		else {}
	)
	ws["session_record_latest_text"] = message_text
	ws["session_record_pulse"] = WorkshopSessionRecordPulseScript.build_pulse(batch_result)
	var new_state: Dictionary = state.duplicate(true)
	new_state["workshop_catalyst"] = ws
	StoryState.set_state(new_state)


func trigger_external_response(trigger_sender: String, trigger_text: String, preferred_speaker: String = "") -> bool:
	if (
		_awaiting_response
		or (
			_get_runtime_profile_id() != SessionTypeRuntimeProfileScript.HIDDEN_SYNTHESIS
			and ai_controlled_names.is_empty()
		)
	):
		return false
	call_deferred("_run_external_response_async", trigger_sender, trigger_text, preferred_speaker)
	return true

func _run_external_response_async(trigger_sender: String, trigger_text: String, preferred_speaker: String = "") -> void:
	var _ignored_sender: String = trigger_sender
	await generate_ai_character_response("", trigger_text, preferred_speaker)

# --- Helper Functions ---

func _coerce_opening_stall(response_text: String) -> String:
	var txt: String = response_text.strip_edges()
	if txt.is_empty() or txt == "...":
		return response_text
	var lower_txt: String = txt.to_lower()
	var before_idx: int = lower_txt.find("before we ")
	if before_idx == -1:
		before_idx = lower_txt.find("before i ")
	if before_idx == -1:
		return response_text
	# Only clean stalling gambits in the opening stretch, including after a greeting.
	if before_idx > 120:
		return response_text
	var comma_after: int = txt.find(",", before_idx)
	if comma_after == -1:
		return response_text
	var replacement: String = txt.substr(comma_after + 1).strip_edges()
	if replacement.is_empty():
		return response_text
	print("[AICharacterAgent] Removed opening stall phrase before logging actor response.")
	return replacement

func _show_ai_error_to_user(error_text: String = "", details: String = "") -> void:
	"""Add a user-visible message to the story log when AI fails (timeout, network, parse, etc.)."""
	if not StoryState:
		return
	StoryState.add_log_entry("Narrator", _build_ai_error_user_message(error_text, details))

func _build_ai_error_user_message(error_text: String = "", details: String = "") -> String:
	var combined_text: String = ("%s %s" % [error_text, details]).strip_edges().to_lower()
	var diagnostic: String = ""
	if combined_text.find("401") != -1 or combined_text.find("403") != -1 or combined_text.find("auth") != -1 or combined_text.find("api key") != -1:
		diagnostic = "The selected provider is rejecting the request. Open \u2630 \u2192 Settings and verify the API key for the current provider."
	elif combined_text.find("404") != -1 or combined_text.find("not found") != -1 or combined_text.find("unknown model") != -1:
		diagnostic = "The selected model or endpoint could not be found. Verify the chosen model in \u2630 \u2192 Settings. If you are using Ollama, confirm it appears in 'ollama list'."
	elif combined_text.find("timeout") != -1 or combined_text.find("timed out") != -1:
		diagnostic = "The model took too long to answer. This usually means the selected model is overloaded, unavailable, or too slow for the amount of context being sent."
	elif combined_text.find("connect") != -1 or combined_text.find("unavailable") != -1 or combined_text.find("refused") != -1:
		diagnostic = "Synesyn could not reach the AI service. If you are using Ollama locally, make sure it is running. Otherwise verify your Hub URL, provider settings, and network connection."
	elif combined_text.find("no usable dialogue") != -1 or combined_text.find("empty") != -1:
		diagnostic = "The AI call completed, but the model did not return a usable in-character line. Try another model or retry after reducing workload on local models."
	elif combined_text.find("no model") != -1 or combined_text.find("manager not available") != -1:
		diagnostic = "No working AI model is configured right now. Open \u2630 \u2192 Settings and select a valid model."
	else:
		diagnostic = "Open \u2630 \u2192 Settings to verify the selected model, Hub connection, and provider settings."

	var current_model: String = _get_active_model_name_for_diagnostics()
	var detail_suffix: String = ""
	if not current_model.is_empty():
		detail_suffix = " Current model: %s." % current_model
	if error_text.strip_edges() != "":
		var trimmed_error: String = error_text.strip_edges()
		if trimmed_error.length() > 120:
			trimmed_error = trimmed_error.substr(0, 117) + "..."
		detail_suffix += " Detail: %s." % trimmed_error
	return "%s %s%s" % [_AI_ERROR_USER_MESSAGE, diagnostic, detail_suffix]

func _get_active_model_name_for_diagnostics() -> String:
	if _cached_conv_manager and "ai_model_manager" in _cached_conv_manager and _cached_conv_manager.ai_model_manager and _cached_conv_manager.ai_model_manager.has_method("get_current_model"):
		return String(_cached_conv_manager.ai_model_manager.get_current_model()).strip_edges()
	if Global and Global.has_method("get_plugin_manager"):
		var plugin_manager_node = Global.get_plugin_manager()
		if plugin_manager_node and plugin_manager_node.has_method("get_ai_model_manager"):
			var ai_manager = plugin_manager_node.get_ai_model_manager()
			if ai_manager and ai_manager.has_method("get_current_model"):
				return String(ai_manager.get_current_model()).strip_edges()
	return ""

func _trigger_fallback_response(story_log: Array, _last_human: String = "") -> bool:
	"""
	Generates a simple, generic response if the main Director/Actor flow fails.
	Ensures the player is never ignored.
	"""
	if ai_controlled_names.is_empty():
		return false

	# Pick the character who has spoken least recently as the fallback speaker
	var fallback_plan: Array = _plan_next_response_speakers(story_log, _last_human)
	if fallback_plan.is_empty():
		return false
	var fallback_speaker_name = fallback_plan[0]
	var scenario = _cached_game_flow_manager.get_current_scenario() if _cached_game_flow_manager else {}

	# Build a contextual fallback cue — vary it to avoid repetitive output
	var last_msg: String = ""
	if not story_log.is_empty():
		last_msg = String(story_log[-1].get("message", "")).strip_edges()
	var cue_variants: Array[String] = [
		"Respond to the last line with a brief, substantive observation that advances the discussion.",
		"Offer a short, grounded reaction that moves the conversation forward rather than stalling.",
		"Build on what was just said with a concrete thought or question, not a hedge.",
		"Engage directly with the last point and push the discussion toward a decision.",
		"React with a concise insight that shows you have been listening and have something at stake.",
	]
	var variant_idx: int = (story_log.size() + Time.get_ticks_msec()) % cue_variants.size()
	var fallback_cue = {
		"text": cue_variants[variant_idx],
		"word_count_hint": "brief",
	}
	var fallback_cue_card = {
		"character_name": fallback_speaker_name,
		"persona": _get_persona_summary(scenario, fallback_speaker_name),
		"cue": fallback_cue,
		"scene_partners": [],
		"full_log_for_context": story_log
	}

	print("[AICharacterAgent] Triggering fallback with cue card: ", fallback_cue_card)
	var response_text = await actor_agent.generate_dialogue_line(fallback_cue_card)

	if not response_text.is_empty() and response_text != "...":
		StoryState.add_log_entry(fallback_speaker_name, response_text)
		StoryState.advance_turn()
		return true
	return false

func _emit_system_cue_if_due(current_phase: String, scenario: Dictionary, _story_log: Array, last_outcome: String = "") -> void:
	if not _cached_metaprompt_manager:
		return
	if not _cached_metaprompt_manager.has_method("pick_system_notification"):
		return
	# Relative cadence by AI turn count with randomized gap (3–7)
	var due := false
	if _last_cue_ai_turn < 0:
		# First cue after at least _next_cue_gap AI turns
		due = _ai_turn_count >= _next_cue_gap
	else:
		due = (_ai_turn_count - _last_cue_ai_turn) >= _next_cue_gap
	if not due:
		return
	var template_text := String(_cached_metaprompt_manager.pick_system_notification(current_phase, scenario)).strip_edges()
	if _cached_metaprompt_manager.has_method("get_latest_turn_system_cue"):
		var scenario_turn_cue := String(_cached_metaprompt_manager.get_latest_turn_system_cue(current_phase)).strip_edges()
		if scenario_turn_cue != "":
			template_text = scenario_turn_cue
	if template_text == "":
		return
	# Ask LLM to produce a concise variation of the template
	var variation_prompt := "Paraphrase this system notification into a concise, poetic status cue (<= 12 words).\n" \
		+ "Preserve meaning; do not quote verbatim; avoid numeric gauges and brackets; no direct address.\n" \
		+ "Template: \"" + template_text + "\"\n\nOutput only the cue."
	var variation := template_text
	if _cached_conv_manager:
		var resp = await _cached_conv_manager.chat(variation_prompt, _scoped_thread_name("system_cue_variation"))
		if resp and resp.success:
			var out := String(resp.response).strip_edges()
			if out != "":
				# Strip any surrounding quotes added by the LLM
				if out.begins_with("\"") and out.ends_with("\"") and out.length() >= 2:
					out = out.substr(1, out.length() - 2)
				variation = out
	# Emit under the system speaker name provided by the metaprompt manager
	var speaker := "Narrator"
	if _cached_metaprompt_manager.has_method("get_system_cue_tag"):
		speaker = _cached_metaprompt_manager.get_system_cue_tag()
	# Optionally append a brief metric provided by the active scenario manager
	if _cached_metaprompt_manager.has_method("get_system_metric_line"):
		var outcome_to_use := String(last_outcome)
		if outcome_to_use == "":
			outcome_to_use = String(_last_turn_outcome)
		var metric := str(_cached_metaprompt_manager.get_system_metric_line(current_phase, outcome_to_use))
		if metric != "":
			variation = variation.rstrip(".") + "...." + metric
	StoryState.add_log_entry(speaker, variation)
	_last_cue_ai_turn = _ai_turn_count
	_next_cue_gap = randi_range(3, 7)

func _get_enriched_character_data(scenario: Dictionary, character_name: String) -> Dictionary:
	"""
	Gets the base character data. No longer enriches with behavioral guidance,
	as that is now handled by the Director in the persona summary.
	"""
	return _get_character_data(scenario, character_name).duplicate()

func _scoped_thread_name(suffix: String) -> String:
	var cleaned_suffix := suffix.replace(" ", "_")
	if _cached_conv_manager and _cached_conv_manager.has_method("get_current_thread"):
		var base_thread := str(_cached_conv_manager.get_current_thread()).strip_edges()
		if base_thread != "":
			return base_thread + "__" + cleaned_suffix
	return cleaned_suffix

func _sanitize_instruction(instruction: Dictionary) -> Dictionary:
	# DEPRECATED in Cue Card architecture. The Director now generates the cue directly.
	# This function is kept for now to avoid breaking old references but should be removed.
	return instruction

func _ensure_connective_prefix(text: String) -> String:
	# No longer enforce a fixed connective; return text as-is to avoid lexical inertia
	return text

func _rotate_outcome_if_same(outcome: String) -> String:
	var order = ["reveal", "escalate", "decision", "reframe"]
	var o := outcome.to_lower()
	if o == "":
		return ""
	if _last_turn_outcome.to_lower() == o:
		var idx := order.find(o)
		if idx == -1:
			return ""
		return order[(idx + 1) % order.size()]
	return ""

func _enforce_opening_constraints(scenario: Dictionary, story_log: Array, planned_speakers: Array, human_character_name: String) -> Array:
	# GUARDRAIL: Opening logic is scenario-driven. Do not prefer or forbid
	# any specific character here unless specified by scenario rules.
	# The cap is the first exchange only. A sender that does not match the
	# cast list must not keep every later turn sliced down to that cap.
	if _opening_exchange_done:
		return planned_speakers
	# A line already spoken by someone other than the human and the system
	# voices ends the opening. Matching only the current AI-name list left
	# every later turn under the first-exchange cap when that list and the
	# log disagreed, so the scene stayed at one speaker.
	if _opening_already_happened(story_log, human_character_name):
		_opening_exchange_done = true
		return planned_speakers

	# First exchange: use scenario-driven constraints only
	if _cached_metaprompt_manager and _cached_metaprompt_manager.has_method("get_opening_constraints"):
		var rules: Dictionary = _cached_metaprompt_manager.get_opening_constraints(scenario)
		# Filter forbidden
		if rules.forbidden.size() > 0:
			planned_speakers = planned_speakers.filter(func(n): return not rules.forbidden.has(String(n)))
		# If allowed is specified, intersect (supports "__ANY_AI__" directive)
		if rules.allowed.size() > 0:
			if rules.allowed.has("__ANY_AI__"):
				var allowed_pool: Array = []
				for ai_name in ai_controlled_names:
					var pooled := String(ai_name).strip_edges()
					if pooled.is_empty() or pooled == human_character_name:
						continue
					if rules.forbidden.has(pooled):
						continue
					allowed_pool.append(pooled)
				if not allowed_pool.is_empty():
					allowed_pool.shuffle()
					planned_speakers = allowed_pool.duplicate()
			else:
				var filtered: Array = []
				for n in planned_speakers:
					if rules.allowed.has(n):
						filtered.append(n)
				if not filtered.is_empty():
					planned_speakers = filtered
		# Enforce max speakers (default 1)
		var max_s := int(rules.get("max_speakers", 1))
		if planned_speakers.size() > max_s:
			planned_speakers = planned_speakers.slice(0, max_s)
	# Ensure at least one remains (randomized to avoid favoritism)
	_opening_exchange_done = true
	if planned_speakers.is_empty() and not ai_controlled_names.is_empty():
		var idx := randi() % ai_controlled_names.size()
		return [ai_controlled_names[idx]]
	return planned_speakers

func _opening_already_happened(story_log: Array, human_character_name: String) -> bool:
	var cast: Array = _scenario_cast_names()
	var human := human_character_name.strip_edges()
	for entry in story_log:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sender := String(entry.get("sender", "")).strip_edges()
		if sender == "" or sender == human or sender.begins_with("["):
			continue
		# A cast member has already spoken. The system-sender list is not a
		# reason to treat that line as still the opening.
		if sender in cast:
			return true
	return false


func _non_actor_names(human_character_name: String) -> Array:
	var blocked: Array = ["Narrator", "Facilitator", "Facilitator Note", "System Message"]
	var human := human_character_name.strip_edges()
	if human == "" and Global and Global.has_method("get_current_character"):
		human = String(Global.get_current_character().get("name", "")).strip_edges()
	if human != "" and human not in blocked:
		blocked.append(human)
	if _cached_metaprompt_manager and _cached_metaprompt_manager.has_method("get_system_senders"):
		for sender_any in _cached_metaprompt_manager.get_system_senders():
			var sender := String(sender_any).strip_edges()
			if sender != "" and sender not in blocked:
				blocked.append(sender)
	return blocked

func _scenario_cast_names() -> Array:
	var names := _names_on_scenario(_flow_scenario())
	# The flow manager's snapshot can hold one character. The loader still has
	# the scenario's cast, and a one-name list is what kept every turn to one reply.
	if names.size() <= 1:
		for name in _names_on_scenario(_loader_scenario()):
			if name not in names:
				names.append(name)
	return names


func _flow_scenario() -> Dictionary:
	if _cached_game_flow_manager and _cached_game_flow_manager.has_method("get_current_scenario"):
		var raw: Variant = _cached_game_flow_manager.get_current_scenario()
		if typeof(raw) == TYPE_DICTIONARY:
			return raw
	return {}


func _loader_scenario() -> Dictionary:
	if Global == null or not Global.has_method("get_scenario_loader"):
		return {}
	var loader: Object = Global.get_scenario_loader()
	if loader == null or not loader.has_method("get_current_scenario"):
		return {}
	var raw: Variant = loader.get_current_scenario()
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw


func _names_on_scenario(scenario: Dictionary) -> Array:
	var names: Array = []
	var chars_any: Variant = scenario.get("characters", [])
	var chars: Array = chars_any if typeof(chars_any) == TYPE_ARRAY else []
	for c_any in chars:
		var name := ""
		if typeof(c_any) == TYPE_DICTIONARY:
			name = String((c_any as Dictionary).get("name", "")).strip_edges()
		else:
			name = String(c_any).strip_edges()
		if name != "" and name not in names:
			names.append(name)
	return names

func _get_persona_summary(scenario: Dictionary, character_name: String) -> String:
	if not scenario or not scenario.has("characters"):
		return "A character in a scene."

	for character in scenario.characters:
		if character.get("name") == character_name:
			var role_str: String = String(character.get("role", "")).strip_edges()
			var instructions: String = String(character.get("behavioral_instructions", "")).strip_edges()
			if instructions.is_empty():
				return role_str if not role_str.is_empty() else "A character with unknown motives."
			var parts: Array[String] = []
			if not role_str.is_empty():
				parts.append("Role: " + role_str)
			parts.append(instructions)
			return "\n".join(parts)

	return "A character with unknown motives."

func _plan_next_response_speakers(story_log: Array, human_character_name: String = "") -> Array:
	var last_index: Dictionary = {}
	for i in range(story_log.size() - 1, -1, -1):
		var entry: Dictionary = story_log[i]
		var s := String(entry.get("sender", "")).strip_edges()
		if s != "" and not last_index.has(s):
			last_index[s] = i

	# The network list can shrink to the one character it still has a peer for.
	# The scenario cast is the rest of the company, minus the human and the
	# system cue, so a turn is not stuck with a single name.
	var blocked: Array = _non_actor_names(human_character_name)
	var candidates: Array = []
	for source_any in [ai_controlled_names, _scenario_cast_names()]:
		for cast_name_any in source_any:
			var cast_name := String(cast_name_any).strip_edges()
			if cast_name.is_empty() or cast_name in blocked or cast_name in candidates:
				continue
			candidates.append(cast_name)
	# The actor loop only speaks names on this list. A cast member who was
	# missing from it was planned and then dropped, which left one line.
	for cast_name in candidates:
		if cast_name not in ai_controlled_names:
			ai_controlled_names.append(cast_name)
	candidates.sort_custom(func(a, b):
		var va = int(last_index.get(a, -1))
		var vb = int(last_index.get(b, -1))
		return va < vb # older index first
	)
	
	# Short range: one speaker about a fifth of the time, two most often,
	# three the rest. The cast size still caps it. Later speakers hear the
	# earlier lines in this batch.
	var roll := randf()
	var speaker_count: int
	if roll < 0.22:
		speaker_count = 1
	elif roll < 0.72:
		speaker_count = 2
	else:
		speaker_count = 3
	speaker_count = mini(speaker_count, candidates.size())
	if speaker_count == 0 and not candidates.is_empty():
		speaker_count = 1

	# Theme-driven bound: themes can request a hard ceiling on the speaker count
	# (e.g. workshop closure mode prefers a single focused contribution).
	if _cached_metaprompt_manager and _cached_metaprompt_manager.has_method("get_max_speakers_this_turn"):
		var max_speakers: int = int(_cached_metaprompt_manager.get_max_speakers_this_turn())
		if max_speakers > 0 and speaker_count > max_speakers:
			speaker_count = max_speakers
	var asked: Array = candidates.slice(0, speaker_count)
	print("[AICharacterAgent] This turn asks for %d speaker(s) from a cast of %d: %s" % [speaker_count, candidates.size(), asked])

	return asked

func _get_character_data(scenario: Dictionary, character_name: String) -> Dictionary:
	if scenario.has("characters"):
		for character in scenario.characters:
			if character.get("name") == character_name:
				return character
	# No matching entry in scenario.characters (e.g. name mismatch, or a
	# custom/Open Play roster that doesn't fully enumerate this character).
	# Always return a dict with at least "name" so downstream dot-access
	# on ai_character data (DirectorAgent, persona lookups, etc.) doesn't
	# crash with "Invalid access to property or key 'name'".
	return {"name": character_name}

func await_all(coroutines: Array):
	# Helper to await multiple coroutines in parallel
	var results = []
	for co in coroutines:
		results.append(await co)
	return results

# --- Diagnostics ---
func _log_model_diagnostics() -> void:
	var pm_name := ""
	var cm_name := ""
	var final_name := ""
	var pm_id := "null"
	var cm_id := "null"
	var conv_id := "null"
	# UI/Plugin manager model
	if Global and Global.has_method("get_plugin_manager"):
		var _pm = Global.get_plugin_manager()
		if _pm and _pm.has_method("get_ai_model_manager"):
			var _pmm = _pm.get_ai_model_manager()
			if _pmm and _pmm.has_method("get_current_model"):
				pm_name = String(_pmm.get_current_model())
				pm_id = str(_pmm.get_instance_id())
	# Conversation manager model
	if _cached_conv_manager and "ai_model_manager" in _cached_conv_manager and _cached_conv_manager.ai_model_manager and _cached_conv_manager.ai_model_manager.has_method("get_current_model"):
		cm_name = String(_cached_conv_manager.ai_model_manager.get_current_model())
		cm_id = str(_cached_conv_manager.ai_model_manager.get_instance_id())
		conv_id = str(_cached_conv_manager.get_instance_id())
	final_name = cm_name if cm_name != "" else pm_name
	print("[AICharacterAgent] Model diag — UI:", pm_name, " CM:", cm_name, " Active:", final_name)
	print("[AICharacterAgent] Instances — UI_mgr:", pm_id, " CM_mgr:", cm_id, " ConvMgr:", conv_id)
