extends SceneTree

const AdapterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/thinking_map_adapter.gd"
)
const ControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map_controller.gd"
)
const PersistenceScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/thinking_map_persistence_coordinator.gd"
)
const RecordStoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_store.gd"
)
const SpecialistCoordinatorScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_specialist_coordinator.gd"
)
const MapScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map.tscn"
)
const WorkspaceScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_workspace_shell.tscn"
)
const AuditControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_controller.gd"
)
const AuditPanelScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_panel.tscn"
)
const OrientationPresenterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_orientation_presenter.gd"
)
const ClosureAuditRulesScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_rules.gd"
)
const MapLayoutUtilsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_map_layout_utils.gd"
)
const AuditRecordScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_record.gd"
)
const AuditSuggesterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_suggester.gd"
)
const MapPanelTogglesScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_map_panel_toggles.gd"
)

## A well-formed reply carrying two deliberate defects: a classification that is not in the
## vocabulary, and an action with no falsifier. Both must be dropped rather than repaired.
const _AUDIT_MODEL_REPLY: String = """
{
  "decision": "Whether to move night triage to the new ward.",
  "absences": [
    {"quadrant": "C", "classification": "unknown", "reason": "Nobody asked what the team does at night.",
     "consequence": "high", "confidence": "low"},
    {"quadrant": "D", "classification": "not_yet_formed", "reason": "The capability does not exist yet.",
     "consequence": "medium", "confidence": "medium"},
    {"quadrant": "B", "classification": "wishful_thinking", "reason": "Not a real classification."}
  ],
  "concentration": {"classification": "expertise_bias", "reason": "Both clinicians supplied it."},
  "transition": {"from": "A", "to": "C", "action": "Shadow one night shift and write down what happens."},
  "reopening_actions": [
    {"action": "Shadow a night shift", "falsifier": "If handover already covers triage, the move is moot."},
    {"action": "An action with no falsifier"}
  ]
}
"""

const _AUDIT_FINDINGS: Dictionary = {
	"has_reading": true,
	"tagged_count": 9,
	"min_tagged_for_reading": 4,
	"dominant_quadrant": "A",
	"empty_quadrants": ["C"],
	"weak_quadrants": ["D"],
	"coverage": {"A": 7, "B": 2, "C": 0, "D": 1},
}

var _failures: Array[String] = []
var _closure_route_count: int = 0


class FakeHub:
	extends Node
	var artifacts: Array[Dictionary] = []
	var should_succeed: bool = true

	func create_artifact_inline_json(
		artifact_type: String,
		payload: Dictionary,
		metadata: Dictionary = {}
	) -> Dictionary:
		if not should_succeed:
			return {"ok": false, "error": "hub_offline"}
		artifacts.append({
			"artifact_type": artifact_type,
			"payload": payload.duplicate(true),
			"metadata": metadata.duplicate(true),
		})
		return {"ok": true, "id": "art_map_%d" % artifacts.size()}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_adapter_boundary_and_incremental_lifecycle()
	_test_preview_and_specialist_safety()
	await _test_commit_retry_lineage_and_routing()
	await _test_scene_projection()
	await _test_graph_view_projection()
	await _test_closure_audit_surface()
	await _test_audit_does_not_crowd_out_the_columns()
	_test_custom_drawer_map_sub_toggles()
	_test_audit_step_wiring()
	_test_audit_suggestions_are_proposals()
	_finish()


func _test_adapter_boundary_and_incremental_lifecycle() -> void:
	for script_path: String in [
		"res://ScenSyn/session_types/workshop_catalyst/thinking_map_adapter.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map_controller.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map_graph_projection.gd",
		"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_canvas.gd",
	]:
		var script_source: String = FileAccess.get_file_as_string(script_path)
		for forbidden_text: String in [
			"ContentGraphController",
			"ContentStateResource",
			"ContextCompiler",
			"PromptChain",
			"ContextGraphAdapter",
			"addons/syntree",
		]:
			_expect(
				not script_source.contains(forbidden_text),
				script_path.get_file()
				+ " contains forbidden dependency: "
				+ forbidden_text
			)

	var adapter_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/session_types/workshop_catalyst/thinking_map_adapter.gd"
	)
	_expect(not adapter_source.is_empty(), "ThinkingMapAdapter source missing")

	var adapter: RefCounted = AdapterScript.new()
	adapter.initialize("sess_stage8", "scenario_stage8")
	var participant_command: Dictionary = adapter.transcript_command(
		"turn-1",
		"Budget pressure is delaying delivery.",
		"cause",
		"segment-1",
		"Participant A",
		"2026-07-11T00:00:00Z"
	)
	var ai_command: Dictionary = adapter.synthesis_command(
		"trace-1",
		"A phased rollout may reduce exposure.",
		"opportunity",
		"2026-07-11T00:01:00Z"
	)
	var first_batch: Dictionary = adapter.apply_command_batch(
		"batch-1",
		[participant_command, ai_command],
		"live",
		2
	)
	_expect(bool(first_batch.get("ok", false)), "Incremental proposal batch failed")
	_expect(not bool(first_batch.get("full_rebuild", true)), "Live batch reported a full rebuild")
	_expect(adapter.get_full_rebuild_count() == 0, "Live batch rebuilt the full map")
	var stale_result: Dictionary = adapter.apply_command_batch(
		"batch-stale",
		[participant_command],
		"live",
		1
	)
	_expect(bool(stale_result.get("cancelled", false)), "Stale replaceable batch was not cancelled")
	var document: Dictionary = adapter.get_document()
	_expect((document.get("nodes", []) as Array).size() == 2, "Incremental nodes were not retained")
	var participant_node: Dictionary = document["nodes"][0]
	var ai_node: Dictionary = document["nodes"][1]
	_expect(participant_node["kind"] == "cause", "Cause category was not preserved")
	_expect(
		participant_node["annotations"]["source_label"] == "Participant said",
		"Participant provenance label is missing"
	)
	_expect(
		ai_node["annotations"]["source_label"] == "AI inferred",
		"Unsourced AI proposal was not labelled AI inferred"
	)
	_expect(
		(ai_node["provenance_refs"] as Array).has("trace-1"),
		"Specialist synthesis trace reference was lost"
	)
	var participant_id: String = String(participant_node["id"])
	var ai_id: String = String(ai_node["id"])
	_expect(adapter.review_proposal(participant_id, "accepted"), "Accept failed")
	_expect(
		adapter.review_proposal(ai_id, "edited", "Pilot a phased rollout."),
		"Edit failed"
	)
	var rejected_command: Dictionary = adapter.transcript_command(
		"turn-2", "Discarded claim", "effect", "segment-2", "Participant B", "2026-07-11T00:02:00Z"
	)
	adapter.apply_command_batch("batch-2", [rejected_command])
	var rejected_id: String = String(rejected_command["id"])
	_expect(adapter.review_proposal(rejected_id, "rejected"), "Reject failed")
	var deferred_command: Dictionary = adapter.synthesis_command(
		"trace-2", "Consider this later.", "effect", "2026-07-11T00:03:00Z"
	)
	adapter.apply_command_batch("batch-3", [deferred_command])
	_expect(
		adapter.review_proposal(String(deferred_command["id"]), "deferred"),
		"Defer failed"
	)
	var reviewed: Dictionary = adapter.get_document()
	_expect(reviewed["nodes"][0]["status"] == "accepted", "Accepted state was not visible")
	_expect(reviewed["nodes"][1]["status"] == "edited", "Edited state was not visible")
	_expect(reviewed["nodes"][2]["status"] == "rejected", "Rejected state was not visible")


func _test_preview_and_specialist_safety() -> void:
	var adapter: RefCounted = AdapterScript.new()
	adapter.initialize("sess_preview")
	var command: Dictionary = adapter.transcript_command(
		"turn-preview", "A reviewed effect", "effect", "segment-preview",
		"Participant", "2026-07-11T00:00:00Z"
	)
	adapter.apply_command_batch("preview-batch", [command])
	adapter.review_proposal(String(command["id"]), "accepted")
	var before: Dictionary = adapter.get_state()
	var preview: Dictionary = adapter.build_preview()
	_expect(not bool(preview.get("mutated", true)), "Map preview claims mutation")
	_expect(adapter.get_state() == before, "Map preview mutated adapter state")
	_expect(
		adapter.get_specialist_prompt_context().is_empty(),
		"Thinking Map injected specialist context by default"
	)
	var coordinator: RefCounted = SpecialistCoordinatorScript.new()
	var base_prompt: String = coordinator.build_prompt([], {"message": "Hello"}, {}, {})
	_expect(
		not base_prompt.contains("COMMITTED THINKING MAP CONTEXT"),
		"Absent map changed the specialist prompt"
	)
	var disabled_prompt: String = coordinator.build_prompt(
		[],
		{"message": "Hello"},
		{},
		{"thinking_map_prompt_context": {}}
	)
	_expect(base_prompt == disabled_prompt, "Disabled map had specialist prompt side effects")
	adapter.mark_committed("art_map_preview", preview["resulting_map"])
	var trace: Dictionary = adapter.set_specialist_context_enabled(true, "Facilitator")
	var context_payload: Dictionary = adapter.get_specialist_prompt_context()
	_expect(not context_payload.is_empty(), "Visible specialist toggle did not enable committed context")
	_expect(not String(trace.get("trace_id", "")).is_empty(), "Toggle did not create a trace")
	var enabled_prompt: String = coordinator.build_prompt(
		[],
		{"message": "Hello"},
		{},
		{"thinking_map_prompt_context": context_payload}
	)
	_expect(
		enabled_prompt.contains("COMMITTED THINKING MAP CONTEXT"),
		"Explicit committed map context was not included"
	)
	adapter.set_specialist_context_enabled(false, "Facilitator")
	_expect(
		adapter.get_specialist_prompt_context().is_empty(),
		"Revoking specialist map context had no effect"
	)


func _test_commit_retry_lineage_and_routing() -> void:
	var adapter: RefCounted = AdapterScript.new()
	adapter.initialize("sess_commit")
	var outcome_command: Dictionary = {
		"operation": "propose_node",
		"id": "decision-1",
		"category": "decision",
		"label": "Adopt the reviewed pilot.",
		"source_class": "participant_said",
		"provenance_refs": ["segment-decision"],
		"provenance": {"review_status": "unreviewed"},
	}
	adapter.apply_command_batch("outcome", [outcome_command])
	adapter.review_proposal("decision-1", "accepted")
	var hub_node := FakeHub.new()
	var persistence_node: Node = PersistenceScript.new()
	root.add_child(hub_node)
	root.add_child(persistence_node)
	persistence_node.configure(hub_node, adapter)
	_expect(hub_node.artifacts.is_empty(), "Thinking Map auto-committed")
	var preview: Dictionary = adapter.build_preview()
	persistence_node.request_commit_payload(preview["resulting_map"])
	await process_frame
	_expect(hub_node.artifacts.size() == 1, "Explicit map commit did not persist")
	_expect(
		hub_node.artifacts[0]["artifact_type"] == "ui.workshop_thinking_map",
		"Map used the wrong product artifact type"
	)
	_expect(
		hub_node.artifacts[0]["payload"]["graph_kind"] == "workshop_thinking_map",
		"Map silently converted to context_graph"
	)
	adapter.apply_command_batch("second", [{
		"operation": "propose_node",
		"id": "risk-1",
		"category": "risk",
		"label": "Pilot capacity may be insufficient.",
		"source_class": "ai_inferred",
		"provenance_refs": ["trace-risk"],
		"provenance": {"review_status": "unreviewed", "evidence_status": "unsupported"},
	}])
	adapter.review_proposal("risk-1", "accepted")
	var second_preview: Dictionary = adapter.build_preview()
	_expect(
		second_preview["resulting_map"]["previous_version_id"] == "art_map_1",
		"Second map preview lacks previous_version_id lineage"
	)
	hub_node.should_succeed = false
	persistence_node.request_commit_payload(second_preview["resulting_map"])
	await process_frame
	_expect(persistence_node.has_retryable_commit(), "Degraded Hub did not retain retryable draft")
	_expect(
		adapter.get_last_committed_artifact_id() == "art_map_1",
		"Failed map commit advanced canonical lineage"
	)
	hub_node.should_succeed = true
	persistence_node.retry()
	await process_frame
	_expect(hub_node.artifacts.size() == 2, "Retained map retry did not persist")

	var record_store: RefCounted = RecordStoreScript.new()
	record_store.initialize("sess_route")
	var panel_node: Control = MapScene.instantiate() as Control
	var route_controller: RefCounted = ControllerScript.new()
	root.add_child(panel_node)
	_expect(
		route_controller.mount(
			panel_node,
			hub_node,
			record_store,
			"sess_route",
			"scenario"
		),
		"Thinking Map controller did not mount"
	)
	var route_adapter: RefCounted = route_controller.get_adapter()
	var local_candidate_result: Dictionary = (
		route_controller.ingest_specialist_candidate_batch({
			"status": "degraded",
			"candidate_delivery_status": "local_validated",
			"turn_id": "turn_7",
			"trace_ref": "specialist-trace:turn_7",
			"created_at": "2026-07-11T20:00:00Z",
			"map_candidates": [{
				"id": "participant-opportunity",
				"category": "opportunity",
				"proposition": "Modular storage could reduce transition risk.",
				"source_class": "participant_said",
				"source_refs": ["facilitator-input:test"],
				"rationale": "Structured from submitted facilitator text.",
				"confidence": 1.0,
				"evidence_status": "unsupported",
			}],
		})
	)
	_expect(
		int(local_candidate_result.get("applied", 0)) == 1,
		"Validated participant candidate was lost when the model batch degraded"
	)
	var opportunity_items_node: VBoxContainer = panel_node.get_node_or_null(
		"%OpportunitiesItems"
	) as VBoxContainer
	var rendered_card_node: Control = opportunity_items_node.get_child(0) as Control
	var rendered_text_node: TextEdit = rendered_card_node.get_node_or_null(
		"%ItemText"
	) as TextEdit
	_expect(
		rendered_text_node.custom_minimum_size.y >= 96.0
		and rendered_card_node.find_child(
			"ReviewActions",
			true,
			false
		) is HFlowContainer,
		"Thinking Map card text or review actions remain cramped"
	)
	route_controller.closure_route_requested.connect(
		func(_outcome: Dictionary) -> void: _closure_route_count += 1
	)
	route_adapter.apply_command_batch("route", [outcome_command])
	_expect(
		not route_controller.route_outcome_to_session_record("decision-1"),
		"Unapproved map outcome routed automatically"
	)
	_expect(_closure_route_count == 0, "Unapproved map outcome created closure")
	route_adapter.review_proposal("decision-1", "accepted")
	_expect(
		route_controller.route_outcome_to_session_record("decision-1"),
		"Explicit approved outcome did not route to Session Record"
	)
	_expect(
		(record_store.get_reviewed()["decisions"] as Array).size() == 1,
		"Session Record did not receive explicitly routed outcome"
	)
	_expect(
		route_controller.request_closure_route("decision-1"),
		"Explicit approved outcome did not route to ClosureBus seam"
	)
	_expect(_closure_route_count == 1, "Closure route did not require exactly one explicit action")
	panel_node.queue_free()
	hub_node.queue_free()
	persistence_node.queue_free()
	await process_frame


func _test_graph_view_projection() -> void:
	var hub_node: FakeHub = FakeHub.new()
	root.add_child(hub_node)
	var record_store: RefCounted = RecordStoreScript.new()
	record_store.initialize("sess_graph_view")
	var panel_node: Control = MapScene.instantiate() as Control
	root.add_child(panel_node)
	var controller: RefCounted = ControllerScript.new()
	_expect(
		controller.mount(
			panel_node,
			hub_node,
			record_store,
			"sess_graph_view",
			"scenario"
		),
		"Graph view controller did not mount"
	)
	controller.ingest_specialist_candidate_batch({
		"status": "complete",
		"turn_id": "turn_graph",
		"trace_ref": "specialist-trace:turn_graph",
		"created_at": "2026-07-19T20:00:00Z",
		"map_candidates": [{
			"id": "graph-cause-1",
			"category": "cause",
			"proposition": "Supplier delay compounds budget risk.",
			"source_class": "ai_inferred",
			"source_refs": ["specialist-trace:turn_graph"],
			"rationale": "Structured candidate for graph projection.",
			"confidence": 0.8,
			"evidence_status": "unsupported",
		}],
	})
	_expect(
		controller.get_map_view_mode() == "columns",
		"Map view did not default to columns"
	)
	controller.set_map_view_mode("graph")
	await process_frame
	_expect(
		controller.get_map_view_mode() == "graph",
		"Map view did not switch to graph"
	)
	var host_node: Control = panel_node.get_node_or_null("%MapGraphHost") as Control
	var columns_node: Control = panel_node.get_node_or_null("%MapColumns") as Control
	_expect(
		host_node != null and host_node.visible and columns_node != null and not columns_node.visible,
		"Graph host/columns visibility incorrect after toggle"
	)
	var canvas_node: Control = host_node.find_child("GraphWorkspaceCanvas", true, false) as Control
	_expect(canvas_node != null, "Shared graph canvas was not mounted")
	var graph_edit_node: GraphEdit = canvas_node.get_node_or_null("GraphEdit") as GraphEdit
	var rendered_count: int = 0
	for child_node: Node in graph_edit_node.get_children():
		if child_node is GraphNode:
			rendered_count += 1
	_expect(rendered_count >= 1, "Graph view did not render map nodes")
	controller.set_map_view_mode("columns")
	await process_frame
	_expect(
		columns_node.visible and not host_node.visible,
		"Columns view did not restore after leaving graph"
	)
	panel_node.queue_free()
	hub_node.queue_free()
	await process_frame


func _test_scene_projection() -> void:
	var panel_node: Control = MapScene.instantiate() as Control
	root.add_child(panel_node)
	_expect(panel_node.get_node_or_null("%CausesItems") != null, "Causes column is missing")
	_expect(panel_node.get_node_or_null("%EffectsItems") != null, "Effects column is missing")
	_expect(
		panel_node.get_node_or_null("%OpportunitiesItems") != null,
		"Opportunities column is missing or singular"
	)
	_expect(
		panel_node.get_node_or_null("%ColumnsViewButton") != null
		and panel_node.get_node_or_null("%GraphViewButton") != null
		and panel_node.get_node_or_null("%MapGraphHost") != null,
		"Map Columns/Graph view controls are missing"
	)
	for column_id: String in ["Causes", "Effects", "Opportunities"]:
		var items_node: Control = panel_node.get_node_or_null(
			"%" + column_id + "Items"
		) as Control
		_expect(
			items_node != null
			and items_node.get_parent() is ScrollContainer,
			column_id + " cards are not contained by a column scroll"
		)
	var context_toggle_node: CheckButton = panel_node.get_node_or_null("%MapContextToggle")
	_expect(not context_toggle_node.button_pressed, "Specialist context toggle did not default OFF")
	var commit_button_node: Button = panel_node.get_node_or_null("%CommitMapButton")
	_expect(commit_button_node.disabled, "Commit was enabled before Preview")
	panel_node.queue_free()
	var shell_node: Control = WorkspaceScene.instantiate() as Control
	root.add_child(shell_node)
	var center_node: Control = shell_node.find_child("CenterWorkspace", true, false) as Control
	var map_panel_node: Control = shell_node.find_child("ThinkingMapPanel", true, false) as Control
	var map_box_node: Control = shell_node.find_child(
		"ThinkingMapBox", true, false
	) as Control
	_expect(
		center_node != null and center_node.is_ancestor_of(map_panel_node),
		"Stage 8 Thinking Map is not the main center canvas"
	)
	_expect(
		map_box_node != null
		and map_panel_node.is_ancestor_of(map_box_node)
		and map_panel_node.clip_contents
		and map_box_node.size_flags_vertical == Control.SIZE_EXPAND_FILL,
		"Stage 8 Thinking Map is not a bounded expand-fill center surface"
	)
	_expect(
		shell_node.find_child("WorkspacePanels", true, false) == null,
		"Stage 8 map remains inside the obsolete six-panel grid"
	)
	shell_node.queue_free()
	await process_frame


## The closure audit surface, covering the two defects that reached a screenshot: an audit
## that called itself complete over a map nobody had oriented, and rows that demanded more
## width than the column they sit in and so rendered a label one character wide.
## Each step, checked against what its own text promises. Every case here was a live defect:
## the audit shipped with triage unreachable, debt answers leaking between quadrants, and
## field-level errors written into the completion gate.
func _test_audit_step_wiring() -> void:
	var record: RefCounted = AuditRecordScript.new()
	record.initialize({})
	record.classify_absence("C", "unknown")
	# Step 2. The surface sends one band per selection, so a record that refused a half-answer
	# made the verdict unreachable: neither band could ever be the second one.
	_expect(
		bool(record.triage_absence("C", "high", "").get("ok", false))
		and String(record.get_absence("C").get("consequence", "")) == "high",
		"a lone triage band is refused, which makes the verdict unreachable"
	)
	_expect(
		not record.get_absence("C").has("verdict"),
		"a verdict was invented from half a pair"
	)
	record.triage_absence("C", "high", "low")
	_expect(
		String(record.get_absence("C").get("verdict", "")) == "reopen",
		"the second band did not complete the pair"
	)
	record.triage_absence("C", "", "low")
	_expect(
		not record.get_absence("C").has("verdict"),
		"clearing a band left a verdict standing that was reached about a different pair"
	)
	var mounted: Array = _mounted_audit_panel()
	var audit_controller: RefCounted = mounted[0]
	var panel_node: Control = mounted[1]
	audit_controller.refresh(_AUDIT_FINDINGS)
	# Step 4. The four answers are about one quadrant's gap; carried over, they would record
	# the next quadrant as debt on evidence gathered about another.
	for child_node: Node in panel_node.get_node("%DebtConditions").get_children():
		(child_node as CheckBox).button_pressed = true
	var debt_picker: OptionButton = panel_node.get_node("%DebtQuadrantPicker") as OptionButton
	debt_picker.select(2)
	debt_picker.item_selected.emit(2)
	var still_ticked: int = 0
	for child_node: Node in panel_node.get_node("%DebtConditions").get_children():
		if (child_node as CheckBox).button_pressed:
			still_ticked += 1
	_expect(
		still_ticked == 0,
		"debt answers survived a change of quadrant: %d still ticked" % still_ticked
	)
	# Step 5. The step promises the move runs from the busiest quadrant into a thin one, so the
	# reading points the pickers there and says so when the facilitator chooses otherwise.
	var from_picker: OptionButton = panel_node.get_node("%TransitionFromPicker") as OptionButton
	var to_picker: OptionButton = panel_node.get_node("%TransitionToPicker") as OptionButton
	_expect(
		from_picker.selected == 0 and to_picker.selected == 2,
		"the pickers do not open on the move the reading points at: from=%d to=%d" % [
			from_picker.selected, to_picker.selected
		]
	)
	to_picker.select(1)
	to_picker.item_selected.emit(1)
	_expect(
		(panel_node.get_node("%TransitionStatus") as Label).text.contains("not one of the"),
		"a move into a well-covered quadrant passed without comment"
	)
	# Step 6. A missing owner is a fact about the fields, not about completion, and the gate
	# rewrites itself from the record on every refresh — so a message left there vanishes.
	var gate_before: String = (panel_node.get_node("%AuditGateStatus") as Label).text
	(panel_node.get_node("%ActionInput") as LineEdit).text = "Interview two ward staff"
	(panel_node.get_node("%ActionAddButton") as Button).pressed.emit()
	_expect(
		(panel_node.get_node("%ActionStatus") as Label).text.contains("owner"),
		"the missing-owner message does not appear beside the fields it is about"
	)
	_expect(
		(panel_node.get_node("%AuditGateStatus") as Label).text == gate_before,
		"a field-level error overwrote the completion gate"
	)
	panel_node.queue_free()


## REQ-CA-021. Drafts are offered, never applied: the record stays untouched until a press, and
## no quantity of drafts can satisfy the completion gate.
func _test_audit_suggestions_are_proposals() -> void:
	var parsed: Dictionary = AuditSuggesterScript.parse_response(
		_AUDIT_MODEL_REPLY, ["C", "D"], _AUDIT_FINDINGS
	)
	_expect(bool(parsed.get("ok", false)), "a well-formed audit reply does not parse")
	var suggestions: Dictionary = parsed.get("suggestions", {})
	var absences: Dictionary = suggestions.get("absences", {})
	_expect(
		absences.size() == 2 and not absences.has("B"),
		"drafts survived that name an unknown classification or a well-covered quadrant: %s"
		% str(absences.keys())
	)
	_expect(
		(suggestions.get("reopening_actions", []) as Array).size() == 1,
		"an action with no falsifier was kept, which the record would then refuse"
	)
	var prompt_text: String = AuditSuggesterScript.build_prompt(
		[{"kind": "cause", "label": "Night handover is verbal", "orientation": "A"}],
		_AUDIT_FINDINGS,
		["C", "D"],
		""
	)
	_expect(
		prompt_text.contains("not_applicable") and prompt_text.contains("expertise_bias"),
		"the prompt paraphrases the vocabularies instead of carrying them"
	)
	_expect(
		not prompt_text.contains("\"debt\"") and prompt_text.contains("not name an owner"),
		"the prompt invites drafts of the two things only the room can state"
	)
	var mounted: Array = _mounted_audit_panel()
	var audit_controller: RefCounted = mounted[0]
	var panel_node: Control = mounted[1]
	audit_controller.refresh(_AUDIT_FINDINGS)
	audit_controller.set_suggestions(suggestions)
	var record: RefCounted = audit_controller.get_record()
	_expect(
		record.get_decision_under_audit().is_empty() and record.get_absences().is_empty(),
		"a draft reached the record without anyone accepting it"
	)
	_expect(
		not record.is_complete(["C", "D"], 9, 4, "A"),
		"the audit completed on drafts alone"
	)
	_first_button_under(panel_node.get_node("%DecisionSuggestion")).pressed.emit()
	_expect(
		record.get_decision_under_audit().contains("night triage")
		and panel_node.get_node("%DecisionSuggestion").get_child_count() == 0,
		"accepting the decision draft did not record it and clear the strip"
	)
	_first_button_under(panel_node.get_node("%ConcentrationSuggestion")).pressed.emit()
	_expect(
		String(record.get_concentration().get("classification", "")) == "expertise_bias",
		"accepting the pile-up draft did not record it"
	)
	var absence_buttons: Array[Button] = []
	_collect_buttons_under(panel_node.get_node("%AbsenceList"), absence_buttons)
	for accept_button: Button in absence_buttons:
		if accept_button.text == "Accept":
			accept_button.pressed.emit()
	_expect(
		record.get_absences().size() == 2
		and String(record.get_absence("C").get("verdict", "")) == "reopen",
		"accepting an absence draft did not carry its triage through to a verdict"
	)
	# The one draft that must not become a record entry on a single press: an action needs an
	# owner and a date, and only the room can commit those.
	var action_buttons: Array[Button] = []
	_collect_buttons_under(panel_node.get_node("%ActionSuggestion"), action_buttons)
	_expect(
		not action_buttons.is_empty() and action_buttons[0].text == "Fill in",
		"a drafted action offers to file itself rather than to fill the form"
	)
	action_buttons[0].pressed.emit()
	_expect(
		record.get_reopening_actions().is_empty()
		and (panel_node.get_node("%ActionInput") as LineEdit).text == "Shadow a night shift"
		and (panel_node.get_node("%ActionOwnerInput") as LineEdit).text.is_empty(),
		"filling the form filed the action, or left the owner pre-filled"
	)
	panel_node.queue_free()


func _mounted_audit_panel() -> Array:
	var panel_node: Control = AuditPanelScene.instantiate() as Control
	root.add_child(panel_node)
	var audit_controller: RefCounted = AuditControllerScript.new()
	audit_controller.mount(panel_node)
	return [audit_controller, panel_node]


func _first_button_under(parent_node: Node) -> Button:
	var buttons: Array[Button] = []
	_collect_buttons_under(parent_node, buttons)
	return buttons[0] if not buttons.is_empty() else null


func _collect_buttons_under(parent_node: Node, found: Array[Button]) -> void:
	for child_node: Node in parent_node.get_children():
		if child_node is Button:
			found.append(child_node)
		_collect_buttons_under(child_node, found)


func _test_closure_audit_surface() -> void:
	var panel_node: Control = AuditPanelScene.instantiate() as Control
	root.add_child(panel_node)
	var audit_controller = AuditControllerScript.new()
	audit_controller.mount(panel_node, {})
	audit_controller.get_record().set_decision_under_audit("Ward staffing")

	# `has_reading` false is the state behind an empty map: the rules module withholds its
	# empty and weak readings, so nothing is thin and every other condition is vacuously met.
	audit_controller.refresh({"has_reading": false})
	var gate_label: Label = panel_node.get_node_or_null("%AuditGateStatus") as Label
	_expect(gate_label != null, "audit surface exposes AuditGateStatus")
	_expect(
		not gate_label.text.begins_with("Audit complete"),
		"audit reported complete over a map with too little oriented to read: " + gate_label.text
	)
	_expect(
		not audit_controller.get_record().is_complete([], 0, 4),
		"the record's own gate admitted an unread map"
	)
	_expect(
		audit_controller.get_record().is_complete([], 4, 4),
		"the gate blocked a readable map that has no empty or weak quadrant to classify"
	)
	# The third diagnostic gates too: a dominant quadrant with nothing said about what its
	# concentration means is an unanswered reading, not a completed audit.
	_expect(
		not audit_controller.get_record().is_complete([], 4, 4, "A"),
		"the gate completed an audit with a dominant quadrant and no concentration reading"
	)
	var concentration_gaps: Array[String] = (
		audit_controller.get_record().describe_completion_gaps([], 4, 4, "A")
	)
	_expect(
		" ".join(concentration_gaps).contains("Distal Past"),
		"the concentration gap names the quadrant by letter rather than canonical term: "
		+ " ".join(concentration_gaps)
	)
	audit_controller.get_record().classify_concentration("A", "legitimate_focus")
	_expect(
		audit_controller.get_record().is_complete([], 4, 4, "A"),
		"classifying the concentration did not clear the gate"
	)
	# The gate has to say how far off the room is, not just that it is short.
	var counted_gaps: Array[String] = audit_controller.get_record().describe_completion_gaps(
		[], 2, 4
	)
	_expect(
		" ".join(counted_gaps).contains("at least 4") and " ".join(counted_gaps).contains("2"),
		"the orientation gap does not name the threshold and the current count: "
		+ " ".join(counted_gaps)
	)
	# "No quadrant dominates" is a finding of balance; it must not be shown for a map that
	# simply has too little oriented to say either way.
	var concentration_label: Label = panel_node.get_node_or_null(
		"%ConcentrationTarget"
	) as Label
	_expect(
		concentration_label != null
		and not concentration_label.text.begins_with("No single quadrant dominates"),
		"unread map reported an absence of dominance as a finding: " + concentration_label.text
	)

	# Widths, at the narrowest the audit is ever asked to render: a single map column.
	panel_node.custom_minimum_size = Vector2(260, 0)
	panel_node.size = Vector2(260, 900)
	audit_controller.refresh({
		"has_reading": true,
		"dominant_quadrant": "A",
		"empty_quadrants": ["C"],
		"weak_quadrants": [],
	})
	await process_frame
	var widest: float = 0.0
	var widest_path: String = ""
	for node_any: Node in panel_node.find_children("*", "Control", true, false):
		var control_node: Control = node_any as Control
		var needed: float = control_node.get_combined_minimum_size().x
		if needed > widest:
			widest = needed
			widest_path = String(panel_node.get_path_to(control_node))
	_expect(
		widest <= 260.0,
		"an audit row demands more than a map column's width: %s needs %.0fpx" % [
			widest_path, widest
		]
	)
	# Step 0 carries the precondition and the way to satisfy it, so it has to name both the
	# progress and the affordance rather than describing a state the facilitator cannot act on.
	var orient_status: Label = panel_node.get_node_or_null("%OrientStatus") as Label
	_expect(orient_status != null, "audit surface exposes the step 0 status")
	audit_controller.refresh({"has_reading": false, "tagged_count": 2})
	_expect(
		orient_status.text.contains("2 of 4") and orient_status.text.contains("Suggest"),
		"step 0 does not report progress toward the threshold and how to get there: "
		+ orient_status.text
	)
	audit_controller.refresh({"has_reading": true, "tagged_count": 6, "untagged_count": 3})
	_expect(
		orient_status.text.contains("6") and orient_status.text.contains("3")
		and orient_status.text.contains("untagged"),
		"a satisfied step 0 hides how much of the map the reading is silent about: "
		+ orient_status.text
	)

	# Coverage names quadrants by canonical term, since a bare "A:3 B:0" requires a mapping
	# the surrounding tooltip never supplied.
	var coverage_line: String = ClosureAuditRulesScript.format_summary({
		"coverage": {"A": 3, "B": 0, "C": 1, "D": 2},
		"tagged_count": 6,
		"has_reading": true,
		"dominant_quadrant": "A",
		"empty_quadrants": ["B"],
	})
	_expect(
		coverage_line.contains("Distal Past 3") and coverage_line.contains("empty Distal Future"),
		"coverage summary still reads in bare quadrant letters: " + coverage_line
	)

	# The footer's two labels must not contradict each other on an empty map, which is what
	# "Every claim is already oriented" beside "no claims oriented yet" amounted to.
	_expect(
		not OrientationPresenterScript.format_nothing_to_suggest(0).contains("already oriented"),
		"empty map reported every claim as already oriented: "
		+ OrientationPresenterScript.format_nothing_to_suggest(0)
	)
	_expect(
		OrientationPresenterScript.format_nothing_to_suggest(3).contains("already oriented"),
		"a fully oriented map lost its explanation"
	)
	panel_node.queue_free()


## Opening the Closure audit must not take the map's own cards off screen. It did: the audit
## host carried an expand flag and a tall minimum, the columns had a zero vertical minimum, and
## the map has no ancestor scroll container — so the columns flattened to a strip of headings
## with nothing to scroll back to. The columns and the audit now share a draggable split, and
## the columns have a height floor.
func _test_audit_does_not_crowd_out_the_columns() -> void:
	var map_node: Control = MapScene.instantiate() as Control
	root.add_child(map_node)
	map_node.visible = true
	var split_node: Node = map_node.get_node_or_null("%MapBodySplit")
	_expect(
		split_node is VSplitContainer,
		"the map body is not a draggable split, so neither region can be resized"
	)
	# Order as the facilitator reads it: columns, then the footer, then the audit beneath it.
	_expect(
		split_node.get_child(0) == map_node.get_node_or_null("%MapBodyPane")
		and split_node.get_child(1) == map_node.get_node_or_null("%MapLowerPane"),
		"split panes are ordered so the footer would render above the columns"
	)
	var columns_node: Control = map_node.get_node_or_null("%MapColumns") as Control
	var audit_host: Control = map_node.get_node_or_null("%ClosureAuditHost") as Control
	MapLayoutUtilsScript.apply_responsive_map_columns(map_node, 1024.0, null, null, null)
	audit_host.visible = true
	# Stands in for the mounted audit panel, which is far taller than the space it is given.
	var tall_filler := Control.new()
	tall_filler.custom_minimum_size = Vector2(0, 900)
	audit_host.add_child(tall_filler)
	map_node.size = Vector2(1024, 520)
	await process_frame
	await process_frame
	# The floor was 132px and is now 96, so the divider can travel much further than it could.
	# What it still has to prevent is the accidental collapse to a strip of headings; hiding the
	# columns on purpose is what the Custom drawer's Claim columns switch is for.
	_expect(
		columns_node.size.y >= 90.0,
		"columns collapsed when the audit opened: %.0fpx tall" % columns_node.size.y
	)
	_expect(
		audit_host.size.y <= 520.0,
		"the audit host grew past the panel instead of scrolling: %.0fpx" % audit_host.size.y
	)
	# The divider has to be draggable to nothing, so the host carries no height floor of its
	# own; the lower pane instead takes a share of the height only while the audit is open,
	# or the footer would float mid-panel with the audit shut.
	_expect(
		audit_host.custom_minimum_size.y == 0.0,
		"the audit host has a height floor, so the divider cannot be dragged shut"
	)
	var lower_pane: Control = map_node.get_node_or_null("%MapLowerPane") as Control
	MapLayoutUtilsScript.apply_audit_split(map_node, true)
	var expands_when_open: bool = lower_pane.size_flags_vertical == Control.SIZE_EXPAND_FILL
	MapLayoutUtilsScript.apply_audit_split(map_node, false)
	_expect(
		expands_when_open and lower_pane.size_flags_vertical == Control.SIZE_FILL,
		"the lower pane does not hand its height back when the audit closes"
	)
	_expect(
		AuditPanelScene.instantiate().get_node_or_null("%AuditHideButton") != null,
		"the audit panel carries no way to close itself"
	)
	# The footer's buttons stretched to the height of whichever wrapping label was tallest,
	# and the coverage reading wrapped to several lines because it was competing for width
	# with three labels and three buttons on one row.
	_expect(
		map_node.get_node("%ClosureCoverageLabel").get_parent()
		!= map_node.get_node("%MapLowerPane/MapFooterRow"),
		"the coverage reading is still squeezed onto the row of buttons"
	)
	for button_name: String in [
		"%ClosureAuditToggle", "%SuggestOrientationsButton", "%ViewsReviewButton"
	]:
		_expect(
			(map_node.get_node(button_name) as Control).size_flags_vertical
			== Control.SIZE_SHRINK_CENTER,
			"%s stretches to the footer row's height" % button_name
		)
	map_node.queue_free()


## The Custom drawer offers a switch per panel, and the Thinking Map is two panels stacked in a
## split: the claims and the Closure audit. Without sub-switches the drawer could only take the
## whole map away, and the Closure panel could only be reached from the map's own footer.
func _test_custom_drawer_map_sub_toggles() -> void:
	var shell_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_workspace_shell.tscn"
	)
	for toggle_name: String in [
		MapPanelTogglesScript.CLAIMS_TOGGLE_NAME, MapPanelTogglesScript.CLOSURE_TOGGLE_NAME
	]:
		_expect(
			shell_source.contains("\"%s\"" % toggle_name),
			"the Custom drawer has no %s switch" % toggle_name
		)
	_expect(
		shell_source.contains("ThinkingMapSubPanels"),
		"the map's sub-switches are not indented under the Thinking Map switch"
	)
	# Stands in for the drawer: the switches live in the shell, several levels above the map,
	# and are found by walking to the outermost ancestor rather than by a hardcoded path.
	var drawer_stub := Control.new()
	root.add_child(drawer_stub)
	var claims_toggle := CheckButton.new()
	claims_toggle.name = MapPanelTogglesScript.CLAIMS_TOGGLE_NAME
	claims_toggle.button_pressed = true
	drawer_stub.add_child(claims_toggle)
	var closure_toggle := CheckButton.new()
	closure_toggle.name = MapPanelTogglesScript.CLOSURE_TOGGLE_NAME
	drawer_stub.add_child(closure_toggle)
	var map_node: Control = MapScene.instantiate() as Control
	drawer_stub.add_child(map_node)
	map_node.visible = true
	var body_pane: Control = map_node.get_node("%MapBodyPane") as Control
	var split_node: VSplitContainer = map_node.get_node("%MapBodySplit") as VSplitContainer
	var closure_calls: Array[bool] = []
	MapPanelTogglesScript.connect_sub_toggles(
		map_node,
		func(is_pressed: bool) -> void: closure_calls.append(is_pressed)
	)
	split_node.split_offset = 120
	claims_toggle.button_pressed = false
	_expect(
		not body_pane.visible,
		"turning off Claim columns left the claims pane on screen"
	)
	# A divider dragged for two panes would leave a gap above the one pane that is left.
	_expect(
		split_node.split_offset == 0,
		"the divider kept its position after one pane was hidden: %d" % split_node.split_offset
	)
	claims_toggle.button_pressed = true
	_expect(body_pane.visible, "turning Claim columns back on did not restore the pane")
	# The Closure switch must not hide the panel behind the map controller's back: opening the
	# audit also reveals the per-card pickers and expires undecided suggestions.
	closure_toggle.button_pressed = true
	_expect(
		closure_calls == [true],
		"the Closure switch did not reach the map controller: %s" % [closure_calls]
	)
	# The footer toggle and the audit's own Hide button are two more routes into the same
	# state, so the drawer has to be told rather than left reading "on" over a shut panel.
	MapPanelTogglesScript.sync_sub_toggles(map_node, false)
	_expect(
		not closure_toggle.button_pressed and closure_calls == [true],
		"closing the audit elsewhere left the drawer switch on, or looped back into it"
	)
	body_pane.visible = false
	MapPanelTogglesScript.sync_sub_toggles(map_node, false)
	_expect(
		not claims_toggle.button_pressed,
		"the Claim columns switch does not follow the pane it controls"
	)
	# A second session mounts a fresh map under the same drawer. The first map's handlers close
	# over a node that is about to be freed, so reconnecting has to replace them, not stack on
	# top of them, or the switches would drive the map that is gone.
	var second_map_node: Control = MapScene.instantiate() as Control
	drawer_stub.add_child(second_map_node)
	MapPanelTogglesScript.connect_sub_toggles(second_map_node, func(_p: bool) -> void: pass)
	_expect(
		claims_toggle.toggled.get_connections().size() == 1,
		"remounting the map stacked a second handler on the Claim columns switch"
	)
	claims_toggle.button_pressed = true
	_expect(
		(second_map_node.get_node("%MapBodyPane") as Control).visible,
		"the switch still drives the map from the previous session"
	)
	drawer_stub.queue_free()


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures.append(failure_message)
	push_error(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst Stage 8 tests: all passed")
		quit(0)
	else:
		push_error("Workshop Catalyst Stage 8: %d failure(s)" % _failures.size())
		quit(1)
