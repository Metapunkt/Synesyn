extends SceneTree

## Resume must restore Scenario, transcript, Session Record text, and Thinking
## Map into specialist context instead of leaving a filename-only placeholder.

const HydrateScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_resume_hydrate.gd"
)
const PromptBuilderScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_prompt_context_builder.gd"
)
const SpecialistPromptsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_specialist_prompts.gd"
)
const TimingScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_timing.gd"
)
const CoordinatorScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_specialist_coordinator.gd"
)

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_source_load_order()
	_test_snapshot_restore_and_legacy_fallback()
	_test_prompt_includes_resumed_context()
	_test_thinking_map_default_off_unless_resume()
	_test_normalize_preserves_resumed_agenda()
	_finish()


func _test_source_load_order() -> void:
	var game_session_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/game_session.gd"
	)
	_expect(
		not game_session_source.contains(
			'call_deferred("_on_story_log_file_selected"'
		),
		"Resume still defers story-log load until after specialists can run"
	)
	var startup_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/core/game_session_startup_utils.gd"
	)
	_expect(
		startup_source.contains("_prepare_pending_workshop_resume")
		and startup_source.contains("_apply_pending_workshop_resume"),
		"Startup no longer hydrates a pending workshop resume before/after init"
	)
	var storylog_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/core/game_session_storylog_utils.gd"
	)
	_expect(
		storylog_source.contains("prepare_workshop_resume")
		and storylog_source.contains("_fork_workshop_save_stem")
		and storylog_source.contains("_acknowledge_workshop_resume"),
		"Story-log loader does not restore Scenario or fork the save stem on resume"
	)
	var agent_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/agents/ai_character_agent.gd"
	)
	_expect(
		agent_source.contains("is_loading_story_log")
		and agent_source.contains("mark_story_log_caught_up"),
		"AI agent still answers while a story log is being replayed"
	)


func _test_snapshot_restore_and_legacy_fallback() -> void:
	var scratch_dir: String = ProjectSettings.globalize_path(
		"user://wc_resume_hydrate_test/"
	)
	DirAccess.make_dir_recursive_absolute(scratch_dir)
	var json_path: String = scratch_dir + "local-energy-transition_fixture.json"
	_write_text(json_path, JSON.stringify([
		{
			"sender": "Workshop Catalyst",
			"message": "[font_size=15]Which transition path should the city test first?[/font_size]",
		},
		{
			"sender": "niks (Facilitator)",
			"message": "We need to consider the use of microgrids",
		},
	], "  "))
	_write_text(scratch_dir + "local-energy-transition_fixture.provenance.json", JSON.stringify({
		"scenario": "Local Energy Transition",
		"session_type": "workshop_catalyst",
		"file_stem": "local-energy-transition_fixture",
	}, "  "))
	_write_text(scratch_dir + "local-energy-transition_fixture.workshop.json", JSON.stringify({
		"agenda": [{"day": 1, "stages": [{"name": "Frame the Scenario", "duration": 600}]}],
		"buckets": {"decisions": [], "ideas": []},
		"session_record_latest_text": "Prior record: grid congestion and equity remain open.",
		"thinking_map": {
			"document": {
				"nodes": [{
					"id": "cause-1",
					"kind": "cause",
					"label": "Peak demand outstrips feeder capacity",
				}],
			},
		},
		"scenario_snapshot": {
			"name": "Local Energy Transition",
			"objective": "Which transition path should the city test first?",
			"description": "A municipal energy-transition workshop.",
			"workshop_packet": {
				"title": "Local Energy Transition",
				"objective": "Which transition path should the city test first?",
				"context": "Feeder congestion, equity, and microgrid options.",
			},
		},
	}, "  "))
	var restored: Dictionary = HydrateScript.scenario_from_resume_path(json_path)
	_expect(
		String(restored.get("name", "")) == "Local Energy Transition",
		"Resume hydrate did not restore the saved Scenario name"
	)
	_expect(
		String(restored.get("objective", "")).contains("transition path"),
		"Resume hydrate did not restore the saved objective"
	)
	_expect(
		String(restored.get("workshop_packet_text", "")).contains("microgrid")
		or String(restored.get("description", "")).contains("municipal"),
		"Resume hydrate dropped the Scenario packet"
	)

	var legacy_path: String = scratch_dir + "legacy_resume.json"
	_write_text(legacy_path, JSON.stringify([
		{
			"sender": "Workshop Catalyst",
			"message": "[font_size=15]Which transition path should the city test first?[/font_size]",
		},
	], "  "))
	_write_text(scratch_dir + "legacy_resume.provenance.json", JSON.stringify({
		"scenario": "Local Energy Transition",
	}, "  "))
	_write_text(scratch_dir + "legacy_resume.workshop.json", JSON.stringify({
		"agenda": [{"day": 1, "stages": [{"name": "Map Causes and Effects", "duration": 900}]}],
	}, "  "))
	var legacy: Dictionary = HydrateScript.scenario_from_resume_path(legacy_path)
	_expect(
		String(legacy.get("name", "")) == "Local Energy Transition",
		"Legacy resume did not recover the provenance Scenario name"
	)
	_expect(
		String(legacy.get("objective", "")).contains("transition path"),
		"Legacy resume did not recover the welcome-line objective"
	)
	_cleanup_dir(scratch_dir)


func _test_prompt_includes_resumed_context() -> void:
	var builder: RefCounted = PromptBuilderScript.new()
	var story_log: Array = [
		{"sender": "Workshop Catalyst", "message": "Which transition path should the city test first?"},
		{"sender": "aeon", "message": "Solar plus storage on the south feeder."},
		{"sender": "niks (Facilitator)", "message": "We need to consider the use of microgrids"},
	]
	var human_input: Dictionary = {
		"sender": "niks (Facilitator)",
		"message": "We need to consider the use of microgrids",
	}
	var scenario: Dictionary = {
		"name": "Local Energy Transition",
		"objective": "Which transition path should the city test first?",
		"workshop_packet_text": "Context: feeder congestion and equity.",
	}
	var workshop_state: Dictionary = {
		"resume_mode": "continue_prior_session",
		"resume_summary": "Resumed from wc_prior.",
		"buckets": {"ideas": [], "decisions": []},
		"session_record_latest_text": "Prior record: grid congestion and equity remain open.",
		"session_record_review": {
			"reviewed": {
				"decisions": [{"text": "Pilot a south-feeder microgrid first."}],
			},
		},
		"thinking_map": {
			"document": {
				"nodes": [{
					"id": "cause-1",
					"kind": "cause",
					"label": "Peak demand outstrips feeder capacity",
				}],
			},
		},
	}
	var curated: Dictionary = builder.call(
		"build", story_log, human_input, scenario, workshop_state
	)
	_expect(
		String(curated.get("scenario", "")).contains("Local Energy Transition"),
		"Specialist scenario context omitted the restored title"
	)
	_expect(
		String(curated.get("recent_transcript", "")).contains("south feeder"),
		"Specialist transcript omitted prior participant turns on resume"
	)
	_expect(
		String(curated.get("session_record", "")).contains("grid congestion"),
		"Specialist session record omitted latest saved Session Record text"
	)
	_expect(
		String(curated.get("session_record", "")).contains("south-feeder microgrid"),
		"Specialist session record omitted reviewed items when buckets were empty"
	)
	var prompt: String = SpecialistPromptsScript.build_full(
		CoordinatorScript.ROLE_DEFINITIONS,
		CoordinatorScript.CROSS_CHECKS,
		story_log,
		human_input,
		scenario,
		workshop_state
	)
	_expect(
		prompt.contains("RESUMED THINKING MAP")
		and prompt.contains("Peak demand outstrips feeder capacity"),
		"Resumed Thinking Map was not injected into specialist prompts"
	)
	_expect(
		not prompt.contains("Resumed from a previously saved story log."),
		"Placeholder resume copy leaked into the specialist prompt"
	)


func _test_thinking_map_default_off_unless_resume() -> void:
	var fresh_section: String = SpecialistPromptsScript.thinking_map_context_section({
		"thinking_map": {
			"document": {
				"nodes": [{"id": "x", "kind": "cause", "label": "Should stay private"}],
			},
		},
	})
	_expect(
		fresh_section.is_empty(),
		"Thinking Map leaked into specialist prompts on a fresh session"
	)


func _test_normalize_preserves_resumed_agenda() -> void:
	var loaded_agenda: Array = [{
		"day": 1,
		"stages": [{"name": "Weigh Who Is Affected", "duration": 1234}],
	}]
	var normalized: Dictionary = TimingScript.normalize_state(
		{
			"resume_mode": "continue_prior_session",
			"agenda": loaded_agenda,
			"session_duration_minutes": 120,
		},
		{"workshop_agenda_text": JSON.stringify([{
			"day": 1,
			"stages": [{"name": "Frame the Scenario", "duration": 600}],
		}])}
	)
	var agenda_any: Variant = normalized.get("agenda", [])
	var agenda: Array = agenda_any if typeof(agenda_any) == TYPE_ARRAY else []
	var first_day: Dictionary = agenda[0] if not agenda.is_empty() else {}
	var stages_any: Variant = first_day.get("stages", [])
	var stages: Array = stages_any if typeof(stages_any) == TYPE_ARRAY else []
	_expect(
		not stages.is_empty()
		and String(stages[0].get("name", "")) == "Weigh Who Is Affected"
		and int(stages[0].get("duration", 0)) == 1234,
		"normalize_state overwrote a resumed agenda from the placeholder Scenario"
	)


func _write_text(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "Could not write test fixture: " + path)
	if file:
		file.store_string(contents)
		file.close()


func _cleanup_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir():
			dir.remove(entry_name)
		entry_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures.append(failure_message)
	push_error(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst resume hydrate tests: all passed")
		quit(0)
	else:
		push_error("Workshop Catalyst resume hydrate: %d failure(s)" % _failures.size())
		quit(1)
