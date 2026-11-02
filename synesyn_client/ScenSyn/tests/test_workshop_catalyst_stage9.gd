extends SceneTree

const StoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_path_store.gd"
)
const ProposalEngineScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_path_proposal_engine.gd"
)
const RetrieverScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_path_evidence_retriever.gd"
)
const PersistenceScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_path_persistence_coordinator.gd"
)
const ControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_compare_paths_controller.gd"
)
const RecordStoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_store.gd"
)
const CompareScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_compare_paths.tscn"
)
const WorkspaceScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_workspace_shell.tscn"
)

var _failures: Array[String] = []
var _retrieval_results: Array[Dictionary] = []


class FakeHub:
	extends Node
	var artifacts: Array[Dictionary] = []
	var retrieve_calls: int = 0
	var should_commit: bool = true

	func create_artifact_inline_json(
		artifact_type: String,
		payload: Dictionary,
		metadata: Dictionary = {}
	) -> Dictionary:
		if not should_commit:
			return {"ok": false, "error": "hub_offline"}
		artifacts.append({
			"artifact_type": artifact_type,
			"payload": payload.duplicate(true),
			"metadata": metadata.duplicate(true),
		})
		return {"ok": true, "id": "art_path_%d" % artifacts.size()}

	func stfx_store_retrieve(
		_query: String,
		_active_source_ids: Array[String] = [],
		_seed_family: String = "",
		_top_k: int = 5,
		_expansion_depth: int = 1
	) -> Dictionary:
		retrieve_calls += 1
		await get_tree().process_frame
		return {
			"ok": true,
			"trace": {"trace_id": "ret_%d" % retrieve_calls},
			"context_pack": {
				"context_pack_id": "ctx_%d" % retrieve_calls,
				"trace_id": "ret_%d" % retrieve_calls,
				"chunks": [{
					"chunk_id": "chunk-%d" % retrieve_calls,
					"source_id": "source",
					"citation": "Source > Relevant section",
					"text": "Relevant source excerpt.",
				}],
			},
		}


class FakeClosureBus:
	extends RefCounted
	var should_succeed: bool = true
	var payloads: Array[Dictionary] = []

	func emit_captured(payload: Dictionary) -> bool:
		if not should_succeed:
			return false
		payloads.append(payload.duplicate(true))
		return true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_contract_invariant_and_proposals()
	_test_preview_selection_and_evidence_none()
	await _test_retrieval_cancellation_and_degraded_state()
	await _test_commit_lineage_closure_retry_and_record_routing()
	await _test_scene_structure()
	_finish()


func _test_contract_invariant_and_proposals() -> void:
	var path_store: RefCounted = StoreScript.new()
	path_store.initialize("sess-stage9", "scenario")
	var initial_paths: Array[Dictionary] = path_store.get_paths()
	_expect(initial_paths.size() == 1, "Initial comparison did not contain one path")
	_expect(
		bool(initial_paths[0].get("is_do_nothing", false)),
		"Required explicit do-nothing proposal is missing"
	)
	_expect(
		String(initial_paths[0].get("evidence_status", "")) == "none",
		"Unsourced do-nothing path did not state evidence none"
	)
	var engine: RefCounted = ProposalEngineScript.new()
	var imported: Array[Dictionary] = engine.import_candidates(
		[_candidate("Act now", false), _candidate("Alternative baseline", true)],
		path_store,
		"test"
	)
	_expect(imported.size() == 2, "Candidate import did not preserve proposal isolation")
	var all_paths: Array[Dictionary] = path_store.get_paths()
	var do_nothing_count: int = 0
	for path_data: Dictionary in all_paths:
		do_nothing_count += int(bool(path_data.get("is_do_nothing", false)))
	_expect(do_nothing_count == 1, "Store did not enforce exactly one do-nothing path")
	var action_id: String = String(imported[0].get("id", ""))
	_expect(
		path_store.review_path(action_id, "edited", {
			"title": "Facilitator path",
			"label": "Facilitator path",
		}),
		"Facilitator path edit failed"
	)
	_expect(
		path_store.propose_path(_candidate("Act now", false)).is_empty(),
		"Later proposal overwrote facilitator-reviewed path"
	)


func _test_preview_selection_and_evidence_none() -> void:
	var path_store: RefCounted = _reviewed_store()
	var paths: Array[Dictionary] = path_store.get_paths()
	var action_id: String = _path_id(paths, false)
	_expect(path_store.select_path(action_id), "Explicit single-path selection failed")
	var before: Dictionary = path_store.get_state()
	var preview: Dictionary = path_store.build_preview()
	_expect(bool(preview.get("valid", false)), "Complete reviewed comparison was not valid")
	_expect(not bool(preview.get("mutated", true)), "Preview reported mutation")
	_expect(path_store.get_state() == before, "Preview mutated path state")
	var resulting: Dictionary = preview.get("resulting_path_set", {})
	var do_nothing_count: int = 0
	for path_any: Variant in resulting.get("paths", []):
		if typeof(path_any) == TYPE_DICTIONARY:
			do_nothing_count += int(bool(path_any.get("is_do_nothing", false)))
			if (path_any as Dictionary).get("evidence_refs", []).is_empty():
				_expect(
					String((path_any as Dictionary).get("evidence_status", "")) == "none",
					"Missing evidence was not honestly labelled none"
				)
	_expect(do_nothing_count == 1, "Preview did not contain exactly one do-nothing path")

	var combined_store: RefCounted = _reviewed_store()
	var combined_paths: Array[Dictionary] = combined_store.get_paths()
	var path_ids: Array = [
		String(combined_paths[0].get("id", "")),
		String(combined_paths[1].get("id", "")),
	]
	_expect(
		combined_store.combine_paths(path_ids, "Combined route"),
		"Explicit accepted-path combination failed"
	)
	_expect(
		String(combined_store.get_selection().get("kind", "")) == "combined",
		"Combined selection state was not retained as a draft"
	)


func _test_retrieval_cancellation_and_degraded_state() -> void:
	var hub_node := FakeHub.new()
	root.add_child(hub_node)
	var retriever_node: Node = RetrieverScript.new()
	root.add_child(retriever_node)
	retriever_node.configure(hub_node)
	retriever_node.retrieval_completed.connect(
		func(result: Dictionary) -> void: _retrieval_results.append(result)
	)
	retriever_node.request_evidence([_candidate("First", false)])
	retriever_node.request_evidence([_candidate("Second", false)])
	await process_frame
	await process_frame
	_expect(_retrieval_results.size() == 1, "Stale evidence request was not cancelled")
	_expect(
		String(_retrieval_results[0].get("trace_id", "")) == "ret_2",
		"Latest retrieval trace was not retained"
	)
	var unavailable_retriever: Node = RetrieverScript.new()
	root.add_child(unavailable_retriever)
	var unavailable_results: Array[Dictionary] = []
	unavailable_retriever.retrieval_completed.connect(
		func(result: Dictionary) -> void: unavailable_results.append(result)
	)
	unavailable_retriever.request_evidence([_candidate("Offline", false)])
	await process_frame
	_expect(
		not unavailable_results.is_empty()
		and String(unavailable_results[0].get("status", "")) == "unavailable",
		"Unavailable evidence seam was not reported truthfully"
	)
	hub_node.queue_free()
	retriever_node.queue_free()
	unavailable_retriever.queue_free()
	await process_frame


func _test_commit_lineage_closure_retry_and_record_routing() -> void:
	var path_store: RefCounted = _reviewed_store()
	var action_id: String = _path_id(path_store.get_paths(), false)
	path_store.select_path(action_id)
	var preview: Dictionary = path_store.build_preview()
	var hub_node := FakeHub.new()
	root.add_child(hub_node)
	var closure_bus := FakeClosureBus.new()
	closure_bus.should_succeed = false
	var persistence_node: Node = PersistenceScript.new()
	root.add_child(persistence_node)
	persistence_node.configure(hub_node, closure_bus, path_store)
	_expect(hub_node.artifacts.is_empty(), "Path set auto-committed before explicit action")
	persistence_node.request_commit_payload(preview["resulting_path_set"])
	await process_frame
	_expect(hub_node.artifacts.size() == 1, "Explicit path-set commit did not reach Hub")
	_expect(
		hub_node.artifacts[0]["artifact_type"] == "ui.workshop_path_set",
		"Path comparison used the wrong Hub artifact type"
	)
	_expect(
		path_store.get_last_committed_artifact_id().is_empty(),
		"ClosureBus failure incorrectly advanced committed lineage"
	)
	_expect(persistence_node.has_retryable_commit(), "Closure failure was not retryable")
	closure_bus.should_succeed = true
	persistence_node.retry()
	await process_frame
	_expect(hub_node.artifacts.size() == 1, "Closure retry duplicated the Hub artifact")
	_expect(closure_bus.payloads.size() == 1, "Explicit ClosureBus action was not delivered")
	_expect(
		path_store.get_last_committed_artifact_id() == "art_path_1",
		"Successful closure delivery did not advance lineage"
	)
	_expect(
		closure_bus.payloads[0]["trigger"] == "compare_paths_commit",
		"ClosureBus payload did not identify explicit Compare Paths commit"
	)

	var record_store: RefCounted = RecordStoreScript.new()
	record_store.initialize("sess-route")
	var panel_node: Control = CompareScene.instantiate() as Control
	root.add_child(panel_node)
	var controller: RefCounted = ControllerScript.new()
	_expect(
		controller.mount(
			panel_node,
			hub_node,
			closure_bus,
			record_store,
			"sess-route",
			"scenario"
		),
		"Compare Paths controller failed to mount"
	)
	var controller_store: RefCounted = controller.get_path_store()
	var controller_paths: Array[Dictionary] = controller_store.get_paths()
	var baseline_id: String = String(controller_paths[0].get("id", ""))
	controller_store.review_path(baseline_id, "accepted")
	var proposed: Dictionary = controller_store.propose_path(_candidate("Route path", false))
	controller_store.review_path(String(proposed.get("id", "")), "accepted")
	controller_store.select_path(String(proposed.get("id", "")))
	var controller_payload: Dictionary = controller_store.build_commit_payload()
	controller_store.mark_committed("art-route", controller_payload, "closure:path-set:art-route")
	_expect(
		(record_store.get_reviewed()["decisions"] as Array).is_empty(),
		"Committed path automatically mutated Session Record"
	)
	_expect(
		controller.route_committed_outcomes_to_session_record() == 1,
		"Explicit Session Record routing did not add selected outcome"
	)
	panel_node.queue_free()
	hub_node.queue_free()
	persistence_node.queue_free()
	await process_frame


func _test_scene_structure() -> void:
	var panel_node: Control = CompareScene.instantiate() as Control
	root.add_child(panel_node)
	_expect(
		panel_node.find_child("PathCards", true, false) != null,
		"Scene-authored dynamic path-card slot is missing"
	)
	_expect(
		(panel_node.find_child("CommitPathsButton", true, false) as Button).disabled,
		"Commit was enabled before Preview"
	)
	_expect(
		panel_node.find_child("RoutePathOutcomesButton", true, false) != null,
		"Explicit Session Record route control is missing"
	)
	panel_node.queue_free()
	var shell_node: Control = WorkspaceScene.instantiate() as Control
	root.add_child(shell_node)
	var compare_node: Control = shell_node.find_child("WorkshopComparePaths", true, false) as Control
	var review_node: Control = shell_node.find_child("CenterReviewSurface", true, false) as Control
	var review_scroll_node: ScrollContainer = shell_node.find_child(
		"ReviewScroll", true, false
	) as ScrollContainer
	var right_record_node: Control = shell_node.find_child("SessionRecordPanel", true, false) as Control
	_expect(
		review_node != null and review_node.is_ancestor_of(compare_node),
		"Compare Paths is not owned by the center Review surface"
	)
	_expect(
		not right_record_node.is_ancestor_of(compare_node),
		"Compare Paths is still embedded in the right Session Record"
	)
	_expect(
		review_scroll_node != null
		and review_scroll_node.is_ancestor_of(compare_node)
		and review_scroll_node.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
		and review_scroll_node.size_flags_vertical == Control.SIZE_EXPAND_FILL,
		"Stage 9 Review content lacks bounded vertical scroll ownership"
	)
	var path_scroll_node: ScrollContainer = compare_node.find_child(
		"PathScroll", true, false
	) as ScrollContainer
	_expect(
		path_scroll_node != null
		and path_scroll_node.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
		"Intentional Compare Paths card scrolling was disabled"
	)
	shell_node.queue_free()
	await process_frame


func _reviewed_store() -> RefCounted:
	var path_store: RefCounted = StoreScript.new()
	path_store.initialize("sess-reviewed", "scenario")
	var baseline_id: String = String(path_store.get_paths()[0].get("id", ""))
	path_store.review_path(baseline_id, "accepted")
	var proposed: Dictionary = path_store.propose_path(_candidate("Act now", false))
	path_store.review_path(String(proposed.get("id", "")), "accepted")
	return path_store


func _candidate(title_text: String, is_do_nothing_path: bool) -> Dictionary:
	return {
		"title": title_text,
		"label": title_text,
		"outcomes": ["Outcome for " + title_text],
		"biggest_risk": "Risk for " + title_text,
		"assumptions": ["Assumption for " + title_text],
		"uncertainty": "Material uncertainty",
		"time_horizon": "Six months",
		"is_do_nothing": is_do_nothing_path,
		"evidence_refs": [],
		"evidence_status": "none",
	}


func _path_id(paths: Array[Dictionary], is_do_nothing_path: bool) -> String:
	for path_data: Dictionary in paths:
		if bool(path_data.get("is_do_nothing", false)) == is_do_nothing_path:
			return String(path_data.get("id", ""))
	return ""


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures.append(failure_message)
	push_error(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst Stage 9 tests: all passed")
		quit(0)
	else:
		push_error("Workshop Catalyst Stage 9: %d failure(s)" % _failures.size())
		quit(1)
