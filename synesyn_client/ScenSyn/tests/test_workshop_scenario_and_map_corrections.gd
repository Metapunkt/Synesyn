extends SceneTree

const ScenarioLoaderScript = preload("res://ScenSyn/scripts/core/scenario_loader.gd")
const WorkshopScenarioContractScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_scenario_contract.gd"
)
const CoordinatorScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_specialist_coordinator.gd"
)
const ThinkingMapAdapterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/thinking_map_adapter.gd"
)
const ThinkingMapControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map_controller.gd"
)
const GraphWorkspaceCanvasScene = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_canvas.tscn"
)
const SymbolicRulesScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map_symbolic_rules.gd"
)
const WORKSHOP_SCENARIOS: Array[String] = [
	"karlsruhe_library_future_design",
	"workshop_catalyst_demo",
]
const LEGACY_NAMES: Array[String] = [
	"Dr. Alice Carter",
	"Gareth Price",
	"Maya Desai",
	"Samira Okoye",
]

var _failures: Array[String] = []
# GDScript lambdas capture outer locals by value, not by reference, so a
# lambda body can't mutate a caller's local var to report a signal payload
# back out. Use instance fields + a bound method instead.
var _captured_manual_connect_from: String = ""
var _captured_manual_connect_to: String = ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_templates_and_compatibility()
	_test_story_characters_preserved()
	_test_fixed_specialists_and_prompt_isolation()
	_test_facilitation_method_in_specialist_prompt()
	_test_custom_scenario_round_trip()
	await _test_scenario_editor_source_clarity()
	_test_default_stage_contracts()
	_test_structured_candidate_validation()
	_test_suggested_delivery_and_raw_ingest_removal()
	_test_relates_to_resolves_to_edges()
	_test_manual_edge_starts_accepted()
	await _test_graph_canvas_manual_connect_and_grouping()
	_test_symbolic_rules_layer()
	_test_no_forced_glp_default()
	_finish()


func _test_templates_and_compatibility() -> void:
	for scenario_id: String in WORKSHOP_SCENARIOS:
		var path: String = ScenarioLoaderScript.get_scenario_path(
			scenario_id,
			"workshop_catalyst",
			"decision_triage"
		)
		var source_text: String = FileAccess.get_file_as_string(path)
		for banned_text: String in [
			"[CHARACTERS]",
			"4 characters",
			"stay in-role",
			"stay in role",
			"AI- or human-controlled",
		]:
			_expect(
				not source_text.to_lower().contains(banned_text.to_lower()),
				"%s retains Workshop role-play text: %s" % [scenario_id, banned_text]
			)
		var loader: RefCounted = ScenarioLoaderScript.new()
		_expect(
			loader.load_scenario(scenario_id, "workshop_catalyst", "decision_triage"),
			"Workshop template failed to load: " + scenario_id
		)
		var loaded: Dictionary = loader.get_current_scenario()
		_expect(not loaded.has("characters") or loaded["characters"].is_empty(), "Template exposed characters")
	var legacy: Dictionary = WorkshopScenarioContractScript.normalize({
		"name": "Legacy Workshop",
		"objective": "Make a decision",
		"workshop_packet_text": "Roles in this workshop (4 characters total)\n- Dr. Alice Carter\nStay in-role.",
		"characters": [{"name": "Dr. Alice Carter", "role": "Legacy role"}],
	})
	_expect(not legacy.has("characters"), "Compatibility normalization retained characters")
	_expect(
		not JSON.stringify(legacy).contains("Dr. Alice Carter"),
		"Compatibility normalization leaked a legacy character name"
	)


func _test_story_characters_preserved() -> void:
	var loader: RefCounted = ScenarioLoaderScript.new()
	_expect(
		loader.load_scenario("hello_trondheim", "story_catalyst", "sustainability"),
		"Story scenario failed to load"
	)
	_expect(
		not (loader.get_current_scenario().get("characters", []) as Array).is_empty(),
		"Story Catalyst characters were removed"
	)


func _test_fixed_specialists_and_prompt_isolation() -> void:
	var expected_ids: Array[String] = [
		"systems_consequences",
		"stakeholder_communication",
		"risk_feasibility",
		"options_innovation",
	]
	var actual_ids: Array[String] = []
	for role_definition: Dictionary in CoordinatorScript.ROLE_DEFINITIONS:
		actual_ids.append(String(role_definition.get("id", "")))
	_expect(actual_ids == expected_ids, "Fixed specialist ids changed")
	var coordinator: RefCounted = CoordinatorScript.new()
	var legacy_characters: Array[Dictionary] = []
	for legacy_name: String in LEGACY_NAMES:
		legacy_characters.append({"name": legacy_name})
	var prompt: String = coordinator.build_prompt(
		[],
		{"message": "Review the issue"},
		{
			"name": "Legacy Workshop",
			"characters": legacy_characters,
		},
		{"current_stage_name": "Frame"}
	)
	for legacy_name: String in LEGACY_NAMES:
		_expect(not prompt.contains(legacy_name), "Specialist prompt leaked " + legacy_name)
	var normalized: Dictionary = WorkshopScenarioContractScript.normalize({
		"name": "Legacy Workshop",
		"objective": "Review the issue",
		"characters": legacy_characters,
	})
	var session_record_script: GDScript = load(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_session_record.gd"
	) as GDScript
	var session_record: RefCounted = session_record_script.new()
	var synthesis_prompt: String = session_record.call(
		"_build_turn_synthesis_prompt",
		[],
		{},
		normalized,
		{"message": "Review the issue"}
	)
	var scenario_display_script: GDScript = load(
		"res://ScenSyn/scripts/core/game_session_scenario_utils.gd"
	) as GDScript
	var scenario_display: RefCounted = scenario_display_script.new()
	var ui_description: String = scenario_display.call(
		"_scenario_description",
		normalized
	)
	var metaprompt_script: GDScript = load(
		"res://ScenSyn/session_types/workshop_catalyst/metaprompt_manager_workshop_catalyst.gd"
	) as GDScript
	var metaprompt_manager: Node = metaprompt_script.new()
	var continuity_output: String = metaprompt_manager.call(
		"generate_game_session_metaprompt",
		normalized,
		legacy_characters,
		{}
	)
	for legacy_name: String in LEGACY_NAMES:
		_expect(not synthesis_prompt.contains(legacy_name), "Synthesis prompt leaked " + legacy_name)
		_expect(not ui_description.contains(legacy_name), "Workshop UI leaked " + legacy_name)
		_expect(not continuity_output.contains(legacy_name), "Continuity output leaked " + legacy_name)
	metaprompt_manager.free()


func _test_facilitation_method_in_specialist_prompt() -> void:
	_expect(
		CoordinatorScript.CROSS_CHECKS.size() == 6,
		"Four lenses must yield six cross-lens checks"
	)
	for role_definition: Dictionary in CoordinatorScript.ROLE_DEFINITIONS:
		_expect(
			not String(role_definition.get("method", "")).strip_edges().is_empty(),
			"Specialist lens is missing its reasoning method: " + String(role_definition.get("id", ""))
		)
	var coordinator: RefCounted = CoordinatorScript.new()
	var prompt: String = coordinator.build_prompt(
		[],
		{"message": "The primary care handoff is the weak point."},
		{"name": "Method Workshop"},
		{"current_stage_name": "Map Causes and Effects"}
	)
	_expect(prompt.contains("DOMAIN ADOPTION"), "Specialist prompt lost domain adoption rules")
	_expect(prompt.contains("CROSS-LENS CHECKS"), "Specialist prompt lost cross-lens checks")
	_expect(not prompt.contains("%s"), "Specialist prompt left an unfilled format token")
	for cross_check: String in CoordinatorScript.CROSS_CHECKS:
		_expect(prompt.contains(cross_check), "Specialist prompt dropped a cross-lens check")
	# Adopted expertise must never become a visible or authoritative persona.
	_expect(
		prompt.contains("never introduce it as a participant"),
		"Specialist prompt lost the never-surface constraint on adopted expertise"
	)
	_expect(
		prompt.contains("Adopted expertise does not raise the evidential standing"),
		"Specialist prompt lost the evidential guard on adopted expertise"
	)


func _test_default_stage_contracts() -> void:
	var custom: Dictionary = WorkshopScenarioContractScript.create_custom({
		"title": "Default Contract Workshop",
		"objective": "Which boundary should we commit to?",
		"context": "Practice is inconsistent across departments.",
	})
	var guidance: Dictionary = custom.get("stage_guidance", {})
	_expect(not guidance.is_empty(), "Custom Scenario received no stage guidance")
	var agenda_parsed: Variant = JSON.parse_string(
		String(custom.get("workshop_agenda_text", ""))
	)
	_expect(typeof(agenda_parsed) == TYPE_ARRAY, "Custom Scenario agenda did not parse")
	var day_entry: Dictionary = (agenda_parsed as Array)[0]
	var stages_any: Variant = day_entry.get("stages", [])
	var stages: Array = stages_any if typeof(stages_any) == TYPE_ARRAY else []
	var has_stakeholder_beat: bool = false
	for stage_any: Variant in stages:
		var stage_name: String = String((stage_any as Dictionary).get("name", ""))
		var stage_text: String = String(guidance.get(stage_name, "")).strip_edges()
		_expect(not stage_text.is_empty(), "Default stage has no contract: " + stage_name)
		for required_line: String in [
			"Facilitator goal:",
			"AI goal:",
			"Decision-forcing question:",
		]:
			_expect(
				stage_text.contains(required_line),
				"Stage contract is incomplete for %s (missing %s)" % [stage_name, required_line]
			)
		_expect(
			stage_text.contains("Required output"),
			"Stage contract has no required output: " + stage_name
		)
		if stage_name == "Weigh Who Is Affected":
			has_stakeholder_beat = true
	_expect(has_stakeholder_beat, "Default agenda has no stage for the Stakeholder lens")
	_expect(
		String(guidance.get("Frame the Scenario", "")).contains("Which boundary should we commit to?"),
		"Default framing contract did not carry the Scenario objective"
	)
	var authored: Dictionary = WorkshopScenarioContractScript.normalize({
		"name": "Authored Workshop",
		"objective": "Authored guidance must win",
		"stage_guidance": {"Kickoff": "Facilitator goal: authored."},
	})
	_expect(
		(authored.get("stage_guidance", {}) as Dictionary).keys() == ["Kickoff"],
		"Default stage guidance overwrote authored guidance"
	)


func _test_custom_scenario_round_trip() -> void:
	var custom: Dictionary = WorkshopScenarioContractScript.create_custom({
		"title": "Local Energy Transition",
		"objective": "Which transition path should the city test first?",
		"context": "The city must reduce emissions without worsening energy poverty.",
		"desired_outcomes": ["Select a pilot", "Name an owner"],
		"constraints": ["Fixed annual budget"],
		"time_horizon": "18 months",
		"relevant_perspectives": ["Residents", "Grid operator", "City finance"],
		"evidence_notes": "Demand data is incomplete.",
	})
	_expect(not custom.has("characters"), "Custom Scenario contract contains characters")
	var save_result: Dictionary = WorkshopScenarioContractScript.save_local_draft(custom)
	_expect(bool(save_result.get("ok", false)), "Custom Scenario local save failed")
	var reloaded: Dictionary = WorkshopScenarioContractScript.load_local_draft()
	_expect(reloaded.get("name") == custom.get("name"), "Custom Scenario title did not reload")
	_expect(
		reloaded.get("persistence_state") == "local_draft",
		"Custom Scenario was not labelled local draft"
	)
	_expect(not reloaded.has("characters"), "Reloaded custom Scenario contains characters")


func _test_scenario_editor_source_clarity() -> void:
	var editor_scene: PackedScene = load(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_scenario_editor.tscn"
	) as PackedScene
	_expect(editor_scene != null, "WorkshopScenarioEditor scene missing")
	if editor_scene == null:
		return
	var editor_node: Control = editor_scene.instantiate() as Control
	root.add_child(editor_node)
	await process_frame
	var custom: Dictionary = WorkshopScenarioContractScript.create_custom({
		"title": "Local Energy Transition",
		"objective": "Which transition path should the city test first?",
		"context": "The city must reduce emissions without worsening energy poverty.",
	})
	WorkshopScenarioContractScript.save_local_draft(custom)
	editor_node.call("open_editor")
	await process_frame
	_expect(
		String(editor_node.call("get_source_kind")) == "local_draft",
		"Editor should detect existing local draft as source"
	)
	var banner_node: Label = editor_node.find_child("SourceBannerLabel", true, false) as Label
	_expect(banner_node != null, "Source banner label missing")
	if banner_node:
		_expect(
			banner_node.text.contains("already saved on this device"),
			"Local draft banner should explain shared device draft"
		)
	var fresh_button_node: Button = editor_node.find_child(
		"FreshWorkshopScenarioButton", true, false
	) as Button
	_expect(fresh_button_node != null, "Start a new draft button missing")
	if fresh_button_node:
		fresh_button_node.pressed.emit()
		await process_frame
		_expect(
			String(editor_node.call("get_source_kind")) == "empty",
			"Start a new draft should clear to empty source"
		)
	editor_node.call("open_editor", custom, "host_synced", true)
	await process_frame
	_expect(
		String(editor_node.call("get_source_kind")) == "host_synced",
		"Editor should accept host_synced source kind"
	)
	var join_hint_node: Label = editor_node.find_child("JoinHintLabel", true, false) as Label
	_expect(join_hint_node != null and join_hint_node.visible, "Join hint should show for multiplayer")
	editor_node.queue_free()
	await process_frame


func _test_structured_candidate_validation() -> void:
	var coordinator: RefCounted = CoordinatorScript.new()
	var contributions: Array[Dictionary] = []
	for role_definition: Dictionary in CoordinatorScript.ROLE_DEFINITIONS:
		contributions.append({
			"role_id": role_definition["id"],
			"summary": "A concise specialist summary.",
		})
	var valid: Dictionary = coordinator.parse_response(JSON.stringify({
		"schema_version": 1,
		"contributions": contributions,
		"map_candidates": [
			_candidate("cause", "Fragmented procurement drives supply instability.", "c1"),
			_candidate("effect", "Patients may move toward unsafe informal suppliers.", "e1"),
			_candidate("opportunity", "A verified fallback pathway could preserve continuity.", "o1"),
			_candidate("effect", "Patients may move toward unsafe informal suppliers.", "duplicate"),
			_candidate("opportunity", "The group should decide what to preview.", "meta"),
		],
		"facilitator_cues": ["Ask for the missing threshold."],
	}))
	_expect((valid.get("map_candidates", []) as Array).size() == 3, "Valid category set was not retained")
	_expect((valid.get("facilitator_cues", []) as Array).size() == 1, "Facilitator cue was not routed")
	var rejected: Array = valid.get("rejected_candidates", [])
	var has_duplicate_rejection: bool = false
	var has_meta_rejection: bool = false
	for rejected_any: Variant in rejected:
		if typeof(rejected_any) != TYPE_DICTIONARY:
			continue
		var rejected_record: Dictionary = rejected_any
		has_duplicate_rejection = (
			has_duplicate_rejection
			or rejected_record.get("reason") == "duplicate_semantic_key"
		)
		has_meta_rejection = (
			has_meta_rejection
			or rejected_record.get("reason") == "facilitation_or_meta_guidance"
		)
	_expect(has_duplicate_rejection, "Duplicate semantic candidate was not rejected")
	_expect(has_meta_rejection, "Meta instruction was not rejected")
	var malformed: Dictionary = coordinator.parse_response("not-json")
	_expect((malformed.get("map_candidates", []) as Array).is_empty(), "Malformed batch created candidates")


func _test_suggested_delivery_and_raw_ingest_removal() -> void:
	var adapter: RefCounted = ThinkingMapAdapterScript.new()
	adapter.initialize("session_test", "scenario_test")
	var command: Dictionary = adapter.specialist_candidate_command(
		_candidate("cause", "Capacity constraints delay safe pathway expansion.", "candidate-1"),
		"trace-1",
		"2026-07-11T12:00:00Z"
	)
	var result: Dictionary = adapter.apply_command_batch("batch-1", [command])
	_expect(bool(result.get("ok", false)), "Validated candidate delivery failed")
	var nodes: Array = adapter.get_document().get("nodes", [])
	_expect(nodes.size() == 1 and nodes[0].get("status") == "suggested", "Candidate was not Suggested")
	_expect(
		(nodes[0].get("provenance_refs", []) as Array).has("trace-1"),
		"Candidate provenance was not retained"
	)
	var map_controller: RefCounted = ThinkingMapControllerScript.new()
	var raw_result: Dictionary = map_controller.ingest_story_entry(
		{"sender": "Session Record", "message": "Entire response"},
		0
	)
	_expect(int(raw_result.get("applied", -1)) == 0, "Whole Session Record response was inserted")


func _test_relates_to_resolves_to_edges() -> void:
	var coordinator: RefCounted = CoordinatorScript.new()
	var contributions: Array[Dictionary] = []
	for role_definition: Dictionary in CoordinatorScript.ROLE_DEFINITIONS:
		contributions.append({
			"role_id": role_definition["id"],
			"summary": "A concise specialist summary.",
		})
	# relates_to is attached to the candidate that is the *subject* of the
	# relation ("this candidate --relation--> target"), so the causal claim
	# belongs on the cause candidate, pointing at the effect it produces.
	var cause_candidate: Dictionary = _candidate(
		"cause", "Fragmented procurement drives supply instability.", "c1"
	)
	cause_candidate["relates_to"] = [
		{"target_id": "e1", "relation": "causes"},
		{"target_id": "e1", "relation": "causes"},
		{"target_id": "c1", "relation": "related_to"},
		{"target_id": "missing-candidate", "relation": "supports"},
		{"target_id": "e1", "relation": "not_a_real_relation"},
	]
	var effect_candidate: Dictionary = _candidate(
		"effect", "Patients may move toward unsafe informal suppliers.", "e1"
	)
	var parsed: Dictionary = coordinator.parse_response(JSON.stringify({
		"schema_version": 1,
		"contributions": contributions,
		"map_candidates": [cause_candidate, effect_candidate],
	}))
	var accepted: Array = parsed.get("map_candidates", [])
	_expect(accepted.size() == 2, "Related candidate pair was not both accepted")
	var cause_accepted: Dictionary = {}
	for candidate_any: Variant in accepted:
		if String((candidate_any as Dictionary).get("id", "")) == "c1":
			cause_accepted = candidate_any
	var relates_to: Array = cause_accepted.get("relates_to", [])
	# Structural normalization only dedupes, drops self-references, and drops
	# unknown relations. "missing-candidate" is a structurally valid reference
	# that simply won't resolve to a real node later — that's the adapter's
	# job (see the edge_commands == 1 assertion below), not this stage's.
	_expect(
		relates_to.size() == 2
		and String(relates_to[0].get("target_id", "")) == "e1"
		and String(relates_to[0].get("relation", "")) == "causes"
		and String(relates_to[1].get("target_id", "")) == "missing-candidate",
		"relates_to was not deduplicated/filtered to the two structurally valid references"
	)

	var adapter: RefCounted = ThinkingMapAdapterScript.new()
	adapter.initialize("session_relates_to", "scenario_test")
	var commands: Array = adapter.specialist_candidate_commands(
		accepted,
		"trace-relates-to",
		"2026-08-02T00:00:00Z",
		"Frame"
	)
	var node_commands: int = 0
	var edge_commands: int = 0
	for command_any: Variant in commands:
		var command: Dictionary = command_any
		if String(command.get("operation", "")) == "propose_node":
			node_commands += 1
		elif String(command.get("operation", "")) == "propose_edge":
			edge_commands += 1
	_expect(node_commands == 2, "Batch did not emit exactly one node command per candidate")
	_expect(
		edge_commands == 1,
		"Batch did not resolve the single valid relates_to entry into exactly one edge"
	)
	var result: Dictionary = adapter.apply_command_batch("relates-to-batch", commands)
	_expect(bool(result.get("ok", false)), "Node+edge batch with resolved relation failed to apply")
	var document: Dictionary = adapter.get_document()
	var edges: Array = document.get("edges", [])
	_expect(edges.size() == 1, "Resolved relation did not produce exactly one persisted edge")
	var edge: Dictionary = edges[0]
	_expect(String(edge.get("relation", "")) == "causes", "Edge relation was not carried through")
	_expect(String(edge.get("status", "")) == "suggested", "Model-derived edge did not start suggested")
	var nodes: Array = document.get("nodes", [])
	var from_node_id: String = ""
	var to_node_id: String = ""
	for node_any: Variant in nodes:
		var node_data: Dictionary = node_any
		var annotations: Dictionary = node_data.get("annotations", {})
		_expect(
			String(annotations.get("group_key", "")) == "stage:Frame",
			"Specialist node was not annotated with its originating stage group"
		)
		if String(node_data.get("kind", "")) == "cause":
			from_node_id = String(node_data.get("id", ""))
		elif String(node_data.get("kind", "")) == "effect":
			to_node_id = String(node_data.get("id", ""))
	_expect(
		String(edge.get("from", "")) == from_node_id
		and String(edge.get("to", "")) == to_node_id,
		"Edge did not wire the cause node to the effect node it relates to"
	)


func _test_manual_edge_starts_accepted() -> void:
	var adapter: RefCounted = ThinkingMapAdapterScript.new()
	adapter.initialize("session_manual_edge", "scenario_test")
	var node_a: Dictionary = adapter.specialist_candidate_command(
		_candidate("cause", "A facilitator-observed constraint.", "manual-a"),
		"trace-manual",
		"2026-08-02T00:00:00Z"
	)
	var node_b: Dictionary = adapter.specialist_candidate_command(
		_candidate("effect", "A facilitator-observed downstream effect.", "manual-b"),
		"trace-manual",
		"2026-08-02T00:00:00Z"
	)
	adapter.apply_command_batch("manual-nodes", [node_a, node_b])
	var edge_command: Dictionary = adapter.manual_edge_command(
		String(node_a.get("id", "")),
		String(node_b.get("id", "")),
		"causes",
		"Facilitator"
	)
	var result: Dictionary = adapter.apply_command_batch("manual-edge", [edge_command])
	_expect(bool(result.get("ok", false)), "Manual edge command failed to apply")
	var edges: Array = adapter.get_document().get("edges", [])
	_expect(edges.size() == 1, "Manual edge was not persisted")
	_expect(
		String(edges[0].get("status", "")) == "accepted",
		"Facilitator-drawn manual edge did not start pre-accepted"
	)
	var repeat_result: Dictionary = adapter.apply_command_batch(
		"manual-edge-repeat",
		[adapter.manual_edge_command(
			String(node_a.get("id", "")),
			String(node_b.get("id", "")),
			"causes",
			"Facilitator"
		)]
	)
	_expect(bool(repeat_result.get("ok", false)), "Idempotent manual edge re-apply failed")
	_expect(
		(adapter.get_document().get("edges", []) as Array).size() == 1,
		"Redrawing the same manual edge created a duplicate"
	)


func _test_graph_canvas_manual_connect_and_grouping() -> void:
	var canvas_node: Control = GraphWorkspaceCanvasScene.instantiate() as Control
	root.add_child(canvas_node)
	await process_frame
	canvas_node.set_document({
		"graph_schema_version": 1,
		"graph_kind": "workshop_thinking_map",
		"nodes": [
			{
				"id": "node-a", "kind": "cause", "label": "A", "status": "suggested",
				"annotations": {"group_key": "stage:Frame", "group_label": "Frame"},
				"provenance_refs": [],
			},
			{
				"id": "node-b", "kind": "effect", "label": "B", "status": "suggested",
				"annotations": {"group_key": "stage:Frame", "group_label": "Frame"},
				"provenance_refs": [],
			},
			{
				"id": "node-c", "kind": "opportunity", "label": "C", "status": "suggested",
				"annotations": {},
				"provenance_refs": [],
			},
		],
		"edges": [],
	})
	var graph_edit_node: GraphEdit = canvas_node.get_node_or_null("GraphEdit") as GraphEdit
	_expect(graph_edit_node != null, "Canvas did not expose an inner GraphEdit")
	var rendered_node_names: Dictionary = {}
	var frame_count: int = 0
	for child_node: Node in graph_edit_node.get_children():
		if child_node is GraphNode:
			rendered_node_names[String(child_node.get("workspace_node_id"))] = child_node.name
		elif child_node is GraphFrame:
			frame_count += 1
			_expect(
				(child_node as GraphFrame).title == "Frame",
				"Grouped frame did not carry the group_label as its title"
			)
	_expect(rendered_node_names.size() == 3, "Canvas did not render all three nodes")
	_expect(
		frame_count == 1,
		"Canvas did not cluster the two same-stage nodes into exactly one GraphFrame"
	)
	_captured_manual_connect_from = ""
	_captured_manual_connect_to = ""
	canvas_node.connect("connection_requested", Callable(self, "_on_test_manual_connect_captured"))
	canvas_node.call(
		"_on_connection_request",
		StringName(rendered_node_names["node-a"]),
		0,
		StringName(rendered_node_names["node-c"]),
		0
	)
	_expect(
		_captured_manual_connect_from == "node-a" and _captured_manual_connect_to == "node-c",
		"Manual connection request did not resolve node names back to workspace node ids"
	)
	canvas_node.queue_free()
	await process_frame


func _on_test_manual_connect_captured(from_id: String, to_id: String) -> void:
	_captured_manual_connect_from = from_id
	_captured_manual_connect_to = to_id


func _test_symbolic_rules_layer() -> void:
	var document: Dictionary = {
		"graph_schema_version": 1,
		"graph_kind": "workshop_thinking_map",
		"nodes": [
			_rule_node("n1", "cause", "Fragmented procurement", "suggested", "unsupported"),
			_rule_node("n2", "effect", "Supply gaps widen", "accepted", "supported"),
			_rule_node("n3", "effect", "Patients seek informal supply", "accepted", "supported"),
			_rule_node("n4", "opportunity", "Centralized buying resolves this cleanly", "accepted", "unknown"),
			_rule_node("n5", "effect", "Rejected side note", "rejected", "unknown"),
		],
		"edges": [
			_rule_edge("e1", "n1", "n2", "causes", "suggested"),
			_rule_edge("e2", "n2", "n3", "causes", "suggested"),
			_rule_edge("e3", "n2", "n4", "contradicts", "suggested"),
			_rule_edge("e4", "n5", "n2", "causes", "rejected"),
		],
	}
	var insights: Dictionary = SymbolicRulesScript.evaluate(document)
	var contradictions: Array = insights.get("contradictions", [])
	var causal_chains: Array = insights.get("causal_chains", [])
	var evidence_gaps: Array = insights.get("evidence_gaps", [])
	_expect(contradictions.size() == 1, "Contradiction edge was not flagged")
	if contradictions.size() == 1:
		_expect(
			String(contradictions[0].get("from_id", "")) == "n2"
			and String(contradictions[0].get("to_id", "")) == "n4",
			"Contradiction finding did not carry the correct endpoints"
		)
	_expect(
		causal_chains.size() == 1
		and (causal_chains[0].get("node_ids", []) as Array) == ["n1", "n2", "n3"],
		"Transitive causal chain n1->n2->n3 was not derived"
	)
	_expect(
		evidence_gaps.size() == 1
		and String(evidence_gaps[0].get("node_id", "")) == "n1",
		"Weakly-evidenced load-bearing node n1 was not flagged as an evidence gap"
	)
	var rejected_edge_ids: Array = []
	for finding_any: Variant in causal_chains:
		rejected_edge_ids.append_array(finding_any.get("node_ids", []) as Array)
	_expect(
		not rejected_edge_ids.has("n5"),
		"Rejected edge/node leaked into derived causal chains"
	)


func _rule_node(
	node_id: String,
	kind_id: String,
	label_text: String,
	status_id: String,
	evidence_status: String
) -> Dictionary:
	return {
		"id": node_id,
		"kind": kind_id,
		"label": label_text,
		"status": status_id,
		"annotations": {},
		"provenance_refs": ["test"],
		"provenance": {"evidence_status": evidence_status},
	}


func _rule_edge(
	edge_id: String,
	from_id: String,
	to_id: String,
	relation_id: String,
	status_id: String
) -> Dictionary:
	return {
		"id": edge_id,
		"from": from_id,
		"to": to_id,
		"relation": relation_id,
		"status": status_id,
		"confidence": 0.7,
		"provenance_refs": ["test"],
		"provenance": {},
	}


func _test_no_forced_glp_default() -> void:
	var popup_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scenes/game_mode_popup.gd"
	)
	_expect(
		popup_source.contains('selected_scenario_name = ""')
		and popup_source.contains("_open_workshop_scenario_editor()")
		and popup_source.contains('call("open_editor"'),
		"Workshop entry still forces an authored template"
	)


func _candidate(category_id: String, proposition: String, candidate_id: String) -> Dictionary:
	return {
		"id": candidate_id,
		"category": category_id,
		"proposition": proposition,
		"source_class": "ai_inferred",
		"source_refs": ["turn-1"],
		"rationale": "Supported by the current workshop exchange.",
		"confidence": 0.7,
		"evidence_status": "unsupported",
	}


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Scenario and Thinking Map correction tests: all passed")
		quit(0)
		return
	for failure_message: String in _failures:
		push_error(failure_message)
	quit(1)
