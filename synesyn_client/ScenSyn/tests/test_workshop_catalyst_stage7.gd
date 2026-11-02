extends SceneTree

const StoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_store.gd"
)
const ProposalEngineScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_proposal_engine.gd"
)
const PersistenceScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_summary_persistence_coordinator.gd"
)
const PanelControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_panel_controller.gd"
)
const PanelScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_panel.tscn"
)
const WorkspaceScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_workspace_shell.tscn"
)
const ExportUtilsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_export_utils.gd"
)

var _failures: Array[String] = []


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
		return {"ok": true, "id": "art_summary_%d" % artifacts.size()}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_proposal_isolation_and_review_actions()
	_test_facilitator_precedence_and_repeat_suppression()
	_test_preview_non_mutation()
	await _test_immutable_lineage_degraded_retry_and_export()
	await _test_scene_controls()
	_test_module_limits()
	_finish()


func _test_proposal_isolation_and_review_actions() -> void:
	var store: RefCounted = StoreScript.new()
	var engine: RefCounted = ProposalEngineScript.new()
	store.initialize("sess_isolation")
	var created: Array[Dictionary] = engine.propose_bucket_diff(store, {
		"decisions": ["Adopt option A"],
		"risks": ["Capacity may be insufficient"],
		"open_questions": ["Who approves the exception?"],
		"next_steps": ["Draft the implementation brief"],
	})
	_expect(created.size() == 4, "Proposal engine did not isolate all candidate items")
	_expect(
		(store.get_reviewed()["decisions"] as Array).is_empty(),
		"AI proposal automatically mutated the reviewed draft"
	)
	_expect(store.accept(created[0]["id"]), "Accept action failed")
	_expect(
		(store.get_reviewed()["decisions"] as Array).size() == 1,
		"Accepted proposal did not enter the reviewed local draft"
	)
	_expect(
		store.edit_proposal(created[1]["id"], "Capacity risk owned by Operations"),
		"Edit action failed"
	)
	_expect(store.reject(created[2]["id"]), "Reject action failed")
	_expect(store.defer(created[3]["id"]), "Defer action failed")
	var decisions: Array[Dictionary] = store.get_state()["proposal_decisions"]
	var statuses: Array[String] = []
	for decision: Dictionary in decisions:
		statuses.append(String(decision.get("decision", "")))
	_expect(
		statuses == ["accepted", "edited", "rejected", "deferred"],
		"Proposal decision ledger did not retain all review actions"
	)


func _test_facilitator_precedence_and_repeat_suppression() -> void:
	var store: RefCounted = StoreScript.new()
	store.initialize("sess_suppression")
	var edited_proposal: Dictionary = store.propose("decisions", "Adopt option alpha")
	store.edit_proposal(edited_proposal["id"], "Adopt option beta")
	_expect(
		store.propose("decisions", "Adopt option alpha").is_empty(),
		"Later model suggestion overrode facilitator-edited source wording"
	)
	var rejected: Dictionary = store.propose("risks", "Supplier delay threatens launch")
	store.reject(rejected["id"])
	_expect(
		store.propose("risks", "Launch is threatened by supplier delay").is_empty(),
		"Semantically keyed rejected suggestion was repeated"
	)
	var deferred: Dictionary = store.propose("owners", "Programme lead owns approval")
	store.defer(deferred["id"])
	_expect(
		store.propose("owners", "Approval is owned by programme lead").is_empty(),
		"Semantically keyed deferred suggestion was repeated"
	)


func _test_preview_non_mutation() -> void:
	var store: RefCounted = StoreScript.new()
	store.initialize("sess_preview")
	store.add_facilitator_item("decisions", "Keep the human review gate")
	var state_before: Dictionary = store.get_state()
	var preview: Dictionary = store.build_preview("Facilitator", ["art_closure"])
	_expect(not bool(preview.get("mutated", true)), "Preview claims to mutate state")
	_expect(store.get_state() == state_before, "Preview mutated the local reviewed draft")
	_expect(
		preview["resulting_summary"]["previous_version_id"] == "",
		"First preview has unexpected version lineage"
	)


func _test_immutable_lineage_degraded_retry_and_export() -> void:
	var store: RefCounted = StoreScript.new()
	store.initialize("sess_lineage")
	store.add_facilitator_item("decisions", "Commit only after preview")
	var hub_node := FakeHub.new()
	var persistence_node: Node = PersistenceScript.new()
	root.add_child(hub_node)
	root.add_child(persistence_node)
	persistence_node.configure(hub_node, store)
	_expect(hub_node.artifacts.is_empty(), "Summary auto-committed before explicit request")
	persistence_node.request_commit("Facilitator", ["art_closure_1"])
	await process_frame
	_expect(hub_node.artifacts.size() == 1, "Explicit first commit did not persist")
	_expect(
		hub_node.artifacts[0]["payload"]["previous_version_id"] == "",
		"First immutable summary has incorrect lineage"
	)
	store.add_facilitator_item("next_steps", "Publish the reviewed record")
	persistence_node.request_commit("Facilitator", ["art_closure_1"])
	await process_frame
	_expect(hub_node.artifacts.size() == 2, "Second explicit commit did not persist")
	_expect(
		hub_node.artifacts[1]["payload"]["previous_version_id"] == "art_summary_1",
		"Second immutable summary did not reference the previous artifact"
	)
	store.add_facilitator_item("risks", "Hub may be temporarily unavailable")
	hub_node.should_succeed = false
	persistence_node.request_commit("Facilitator")
	await process_frame
	_expect(store.is_dirty(), "Hub failure discarded or marked the local draft committed")
	_expect(persistence_node.has_retryable_commit(), "Hub failure was not retryable")
	_expect(hub_node.artifacts.size() == 2, "Failed Hub request created an artifact")
	hub_node.should_succeed = true
	persistence_node.retry()
	await process_frame
	_expect(hub_node.artifacts.size() == 3, "Retry did not persist the retained draft")
	_expect(not store.is_dirty(), "Successful retry did not mark the draft committed")

	var export_path: String = ExportUtilsScript.export_decision_record_only(
		{"buckets": {}},
		"sess_stage7_export",
		{"name": "Stage 7"},
		"2026-07-11 00:00:00",
		store.get_last_committed_payload(),
		store.get_last_committed_artifact_id()
	)
	var export_text: String = FileAccess.get_file_as_string(export_path)
	_expect(
		export_text.contains("art_summary_3"),
		"Export did not reference the last committed summary artifact"
	)
	var fallback_path: String = ExportUtilsScript.export_decision_record_only(
		{"buckets": {"decisions": ["Local draft"]}},
		"sess_stage7_fallback",
		{"name": "Stage 7"},
		"2026-07-11 00:00:00"
	)
	var fallback_text: String = FileAccess.get_file_as_string(fallback_path)
	_expect(
		fallback_text.contains("Uncommitted fallback export"),
		"Fallback export falsely implied a committed summary"
	)
	hub_node.queue_free()
	persistence_node.queue_free()
	await process_frame


func _test_scene_controls() -> void:
	var panel_node: Control = PanelScene.instantiate() as Control
	var store: RefCounted = StoreScript.new()
	store.initialize("sess_scene")
	var hub_node := FakeHub.new()
	var persistence_node: Node = PersistenceScript.new()
	var panel_controller: RefCounted = PanelControllerScript.new()
	root.add_child(panel_node)
	root.add_child(hub_node)
	root.add_child(persistence_node)
	persistence_node.configure(hub_node, store)
	_expect(
		panel_controller.mount(panel_node, store, persistence_node),
		"Panel controller did not bind scene-authored controls"
	)
	var commit_button_node: Button = panel_node.get_node_or_null(
		"%CommitSummaryButton"
	) as Button
	_expect(commit_button_node.disabled, "Commit was enabled before explicit preview")
	var scene_state_before: Dictionary = store.get_state()
	panel_controller.show_preview()
	_expect(not commit_button_node.disabled, "Explicit preview did not enable commit")
	_expect(
		store.get_state() == scene_state_before,
		"Scene Preview control mutated the reviewed draft"
	)
	for control_id: String in [
		"DecisionsItems",
		"RisksItems",
		"OpenQuestionsItems",
		"OwnersItems",
		"NextStepsItems",
		"PreviewSummaryButton",
		"CommitSummaryButton",
		"RetryCommitButton",
	]:
		_expect(
			panel_node.get_node_or_null("%" + control_id) != null,
			"Session Record scene is missing control: " + control_id
		)
	var game_scene_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scenes/game_session.tscn"
	)
	_expect(
		not game_scene_source.contains("SessionRecordTabLabel"),
		"Read-only SessionRecordTabLabel remains in the game scene"
	)
	var shell_node: Control = WorkspaceScene.instantiate() as Control
	root.add_child(shell_node)
	var record_scroll_node: ScrollContainer = shell_node.find_child(
		"SessionRecordScroll", true, false
	) as ScrollContainer
	var record_slot_node: Control = shell_node.find_child(
		"SessionRecordContentSlot", true, false
	) as Control
	var end_button_node: Control = shell_node.find_child(
		"EndAndSaveButton", true, false
	) as Control
	_expect(
		record_scroll_node != null
		and record_scroll_node.is_ancestor_of(record_slot_node)
		and record_scroll_node.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"Stage 7 Session Record lacks bounded vertical scroll ownership"
	)
	_expect(
		not record_scroll_node.is_ancestor_of(end_button_node),
		"Stage 7 End & Save is inside Session Record scrolling content"
	)
	shell_node.queue_free()
	panel_node.queue_free()
	hub_node.queue_free()
	persistence_node.queue_free()
	await process_frame


func _test_module_limits() -> void:
	for script_path: String in [
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_controller.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_session_record.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_store.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_proposal_engine.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_panel_controller.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_summary_persistence_coordinator.gd",
	]:
		var parsed_script: GDScript = load(script_path) as GDScript
		_expect(parsed_script != null, "Stage 7 script did not parse: " + script_path)
		var source_text: String = FileAccess.get_file_as_string(script_path)
		_expect(
			source_text.count("\n") + 1 <= 900,
			"Stage 7 module exceeds 900 lines: " + script_path
		)


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst Stage 7 tests: all passed")
		quit(0)
		return
	for failure_message: String in _failures:
		push_error(failure_message)
	quit(1)
