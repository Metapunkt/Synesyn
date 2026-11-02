extends RefCounted
class_name WorkshopComparePathsController

signal state_changed(path_state: Dictionary)

const AutoloadsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_autoloads.gd"
)
const StoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_path_store.gd"
)
const ProposalEngineScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_path_proposal_engine.gd"
)
const EvidenceRetrieverScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_path_evidence_retriever.gd"
)
const PersistenceScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_path_persistence_coordinator.gd"
)
const CardScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_compare_path_card.tscn"
)
const ReviewGateScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_review_gate.gd"
)

var _panel_node: Control = null
var _path_store: RefCounted = null
var _proposal_engine: RefCounted = null
var _evidence_retriever: Node = null
var _persistence: Node = null
var _record_store: RefCounted = null
var _preview_payload: Dictionary = {}
var _combination_ids: Array[String] = []


func mount(
	panel_node: Control,
	hub_client: Object,
	closure_bus: Object,
	record_store: RefCounted,
	session_id: String,
	scenario_id: String,
	saved_state: Dictionary = {}
) -> bool:
	_panel_node = panel_node
	_record_store = record_store
	if not is_instance_valid(_panel_node):
		return false
	_path_store = StoreScript.new()
	_path_store.initialize(session_id, scenario_id, saved_state)
	_proposal_engine = ProposalEngineScript.new()
	_evidence_retriever = EvidenceRetrieverScript.new()
	_evidence_retriever.name = "WorkshopPathEvidenceRetriever"
	_panel_node.add_child(_evidence_retriever)
	_evidence_retriever.configure(hub_client)
	_evidence_retriever.retrieval_started.connect(_on_retrieval_started)
	_evidence_retriever.retrieval_completed.connect(_on_retrieval_completed)
	_persistence = PersistenceScript.new()
	_persistence.name = "WorkshopPathPersistenceCoordinator"
	_panel_node.add_child(_persistence)
	_persistence.configure(hub_client, closure_bus, _path_store)
	_persistence.commit_started.connect(_on_commit_started)
	_persistence.commit_succeeded.connect(_on_commit_succeeded)
	_persistence.commit_failed.connect(_on_commit_failed)
	if not _connect_controls():
		return false
	_panel_node.visible = true
	refresh()
	return true


func propose_from_reviewed_record() -> int:
	if not _record_store:
		return 0
	var candidates: Array[Dictionary] = _proposal_engine.candidates_from_reviewed_record(
		_record_store.get_reviewed()
	)
	var imported: Array[Dictionary] = _proposal_engine.import_candidates(
		candidates,
		_path_store,
		"session_record_review"
	)
	if not imported.is_empty():
		_after_local_change("Reviewed notes became path proposals; facilitator review is required.")
		return imported.size()
	# An import that finds nothing used to return silently, which reads as a dead
	# button. Say which of the two reasons applies.
	_set_status(ReviewGateScript.empty_import_status(_record_store.get_reviewed()))
	return 0


func request_evidence() -> String:
	_invalidate_preview()
	return _evidence_retriever.request_evidence(_path_store.get_paths())


func show_preview() -> Dictionary:
	var preview: Dictionary = _path_store.build_preview("Facilitator")
	var preview_panel_node: Control = _control("PathPreviewPanel")
	var preview_text_node: TextEdit = _control("PathPreviewText") as TextEdit
	var commit_button_node: Button = _control("CommitPathsButton") as Button
	preview_panel_node.visible = true
	preview_text_node.text = JSON.stringify(preview, "\t")
	if bool(preview.get("valid", false)) and not bool(preview.get("mutated", true)):
		_preview_payload = (
			preview.get("resulting_path_set", {}) as Dictionary
		).duplicate(true)
		commit_button_node.disabled = false
		_set_status("Preview ready. Commit remains an explicit facilitator action.")
	else:
		_preview_payload = {}
		commit_button_node.disabled = true
		_set_status("Preview is not committable: " + "; ".join(preview.get("errors", []) as Array))
	return preview


func route_committed_outcomes_to_session_record() -> int:
	if not _record_store:
		return 0
	var outcomes: Array[Dictionary] = _path_store.build_session_record_outcomes()
	var added_count: int = 0
	for outcome: Dictionary in outcomes:
		var added: Dictionary = _record_store.add_facilitator_item(
			String(outcome.get("category", "decisions")),
			String(outcome.get("text", "")),
			"Facilitator",
			{
				"provenance_refs": [
					String(outcome.get("path_id", "")),
					String(outcome.get("path_set_artifact_id", "")),
				],
				"provenance": {
					"authorship_kind": "facilitator_routed",
					"origin_ref": String(outcome.get("path_id", "")),
					"path_set_artifact_id": String(outcome.get("path_set_artifact_id", "")),
					"review_status": "reviewed",
				},
			}
		)
		if not added.is_empty():
			added_count += 1
	if added_count > 0:
		_set_status("%d committed outcome(s) added to the editable Session Record." % added_count)
	return added_count


func get_path_store() -> RefCounted:
	return _path_store


func get_state() -> Dictionary:
	return _path_store.get_state() if _path_store else {}


func refresh() -> void:
	if not is_instance_valid(_panel_node) or not _path_store:
		return
	var cards_node: HBoxContainer = _control("PathCards") as HBoxContainer
	for child_node: Node in cards_node.get_children():
		child_node.queue_free()
	for path_data: Dictionary in _path_store.get_paths():
		_add_card(cards_node, path_data)
	_refresh_selection_status()


func _add_card(cards_node: HBoxContainer, path_data: Dictionary) -> void:
	var card_node: Control = CardScene.instantiate() as Control
	cards_node.add_child(card_node)
	var path_id: String = String(path_data.get("id", ""))
	var title_node: LineEdit = card_node.find_child("PathTitle", true, false) as LineEdit
	var outcomes_node: TextEdit = card_node.find_child("OutcomesEdit", true, false) as TextEdit
	var risk_node: TextEdit = card_node.find_child("BiggestRiskEdit", true, false) as TextEdit
	var assumptions_node: TextEdit = card_node.find_child("AssumptionsEdit", true, false) as TextEdit
	var uncertainty_node: LineEdit = card_node.find_child("UncertaintyEdit", true, false) as LineEdit
	var horizon_node: LineEdit = card_node.find_child("TimeHorizonEdit", true, false) as LineEdit
	title_node.text = String(path_data.get("title", ""))
	outcomes_node.text = "\n".join(path_data.get("outcomes", []) as Array)
	risk_node.text = String(path_data.get("biggest_risk", ""))
	assumptions_node.text = "\n".join(path_data.get("assumptions", []) as Array)
	uncertainty_node.text = String(path_data.get("uncertainty", ""))
	horizon_node.text = String(path_data.get("time_horizon", ""))
	var do_nothing_label_node: Label = card_node.find_child(
		"DoNothingLabel", true, false
	) as Label
	do_nothing_label_node.visible = bool(path_data.get("is_do_nothing", false))
	var evidence_status_id: String = String(path_data.get("evidence_status", "none"))
	var evidence_label_node: Label = card_node.find_child(
		"EvidenceStatus", true, false
	) as Label
	var refs: Array = path_data.get("evidence_refs", [])
	evidence_label_node.text = (
		"Evidence: none — no supporting references"
		if refs.is_empty()
		else "Evidence: %s — %d reference(s), relevance requires review"
		% [evidence_status_id, refs.size()]
	)
	var references_node: RichTextLabel = card_node.find_child(
		"EvidenceReferences", true, false
	) as RichTextLabel
	references_node.text = _reference_text(refs)
	var review_state: String = String(path_data.get("review_state", "suggested"))
	var state_node: Label = card_node.find_child("ReviewState", true, false) as Label
	state_node.text = review_state.capitalize()
	var is_suggested: bool = review_state == "suggested"
	for button_id: String in ["AcceptButton", "EditButton", "RejectButton", "DeferButton"]:
		var review_button_node: Button = card_node.find_child(
			button_id, true, false
		) as Button
		review_button_node.disabled = not is_suggested
	(card_node.find_child("AcceptButton", true, false) as Button).pressed.connect(
		func() -> void: _review(path_id, "accepted", {})
	)
	(card_node.find_child("EditButton", true, false) as Button).pressed.connect(
		func() -> void:
			_review(path_id, "edited", {
				"title": title_node.text,
				"label": title_node.text,
				"outcomes": _lines(outcomes_node.text),
				"biggest_risk": risk_node.text,
				"assumptions": _lines(assumptions_node.text),
				"uncertainty": uncertainty_node.text,
				"time_horizon": horizon_node.text,
				"evidence_refs": refs,
				"evidence_status": evidence_status_id,
			})
	)
	(card_node.find_child("RejectButton", true, false) as Button).pressed.connect(
		func() -> void: _review(path_id, "rejected", {})
	)
	(card_node.find_child("DeferButton", true, false) as Button).pressed.connect(
		func() -> void: _review(path_id, "deferred", {})
	)
	var select_button_node: Button = card_node.find_child("SelectButton", true, false) as Button
	select_button_node.disabled = review_state not in ["accepted", "edited"]
	select_button_node.pressed.connect(func() -> void: _select(path_id))
	var combine_toggle_node: CheckButton = card_node.find_child(
		"CombineToggle", true, false
	) as CheckButton
	combine_toggle_node.disabled = select_button_node.disabled
	combine_toggle_node.button_pressed = path_id in _combination_ids
	combine_toggle_node.toggled.connect(
		func(is_checked: bool) -> void: _toggle_combination(path_id, is_checked)
	)


func _connect_controls() -> bool:
	for control_id: String in [
		"ImportReviewedRecordButton", "RetrieveEvidenceButton", "PathCards",
		"CombinationLabel", "CombineSelectedButton", "ClearSelectionButton",
		"PreviewPathsButton", "CommitPathsButton", "RetryPathCommitButton",
		"RoutePathOutcomesButton", "PathCommitStatus", "PathPreviewPanel",
		"PathPreviewText", "EvidenceRetrievalStatus", "SelectionStatus",
	]:
		if not _control(control_id):
			return false
	(_control("ImportReviewedRecordButton") as Button).pressed.connect(
		propose_from_reviewed_record
	)
	(_control("RetrieveEvidenceButton") as Button).pressed.connect(request_evidence)
	(_control("CombineSelectedButton") as Button).pressed.connect(_combine_checked)
	(_control("ClearSelectionButton") as Button).pressed.connect(_clear_selection)
	(_control("PreviewPathsButton") as Button).pressed.connect(show_preview)
	(_control("CommitPathsButton") as Button).pressed.connect(_commit_preview)
	(_control("RetryPathCommitButton") as Button).pressed.connect(_persistence.retry)
	(_control("RoutePathOutcomesButton") as Button).pressed.connect(
		route_committed_outcomes_to_session_record
	)
	for button_id: String in [
		"ImportReviewedRecordButton", "RetrieveEvidenceButton",
		"CombineSelectedButton", "ClearSelectionButton",
		"PreviewPathsButton", "CommitPathsButton", "RoutePathOutcomesButton",
	]:
		(_control(button_id) as Button).visible = true
	return true


func _review(path_id: String, action_id: String, edited_fields: Dictionary) -> void:
	if _path_store.review_path(path_id, action_id, edited_fields):
		_after_local_change("Path review changed — Preview required before Commit.")


func _select(path_id: String) -> void:
	if _path_store.select_path(path_id):
		_after_local_change("Path selected as a draft — Preview required before Commit.")


func _toggle_combination(path_id: String, is_checked: bool) -> void:
	if is_checked and path_id not in _combination_ids:
		_combination_ids.append(path_id)
	elif not is_checked:
		_combination_ids.erase(path_id)
	_refresh_selection_status()


func _combine_checked() -> void:
	var combination_label_node: LineEdit = _control("CombinationLabel") as LineEdit
	if _path_store.combine_paths(_combination_ids, combination_label_node.text):
		_after_local_change("Combined path selected as a draft — Preview required.")
	else:
		_set_status("Choose at least two accepted paths and name the combination.")


func _clear_selection() -> void:
	_path_store.clear_selection()
	_combination_ids.clear()
	_after_local_change("Selection cleared. No commit can occur until a path is selected.")


func _commit_preview() -> void:
	if _preview_payload.is_empty():
		return
	var presence_node: Node = AutoloadsScript.workshop_presence()
	if (
		presence_node
		and presence_node.has_method("is_active")
		and presence_node.is_active()
		and not bool(presence_node.call("has_local_facilitator_claim"))
	):
		var status_node: Label = _control("PathCommitStatus") as Label
		if status_node:
			status_node.text = "Commit requires a Facilitator claim."
		return
	_persistence.request_commit_payload(_preview_payload)


func _on_retrieval_started(_request_id: String) -> void:
	var status_node: Label = _control("EvidenceRetrievalStatus") as Label
	status_node.text = "Retrieving evidence without blocking the live session…"


func _on_retrieval_completed(result: Dictionary) -> void:
	_path_store.apply_evidence_result(result)
	var status_node: Label = _control("EvidenceRetrievalStatus") as Label
	status_node.text = String(result.get("message", "Evidence retrieval completed."))
	_after_local_change("Evidence changed — facilitator review and Preview are required.")


func _on_commit_started() -> void:
	_set_status("Persisting reviewed path set, then delivering explicit ClosureBus action…")


func _on_commit_succeeded(
	artifact_id: String,
	closure_ref: String,
	_payload: Dictionary
) -> void:
	_preview_payload = {}
	(_control("CommitPathsButton") as Button).disabled = true
	(_control("RetryPathCommitButton") as Button).visible = false
	(_control("RoutePathOutcomesButton") as Button).disabled = false
	_set_status("Committed %s with explicit closure %s." % [artifact_id, closure_ref])
	state_changed.emit(_path_store.get_state())


func _on_commit_failed(error_text: String) -> void:
	(_control("RetryPathCommitButton") as Button).visible = _persistence.has_retryable_commit()
	_set_status(error_text)
	state_changed.emit(_path_store.get_state())


func _after_local_change(status_text: String) -> void:
	_invalidate_preview()
	_set_status(status_text)
	refresh()
	state_changed.emit(_path_store.get_state())


func _invalidate_preview() -> void:
	_preview_payload = {}
	if _control("CommitPathsButton"):
		(_control("CommitPathsButton") as Button).disabled = true


func _refresh_selection_status() -> void:
	var selection: Dictionary = _path_store.get_selection()
	var status_node: Label = _control("SelectionStatus") as Label
	if selection.is_empty():
		status_node.text = "No path selected. Selection remains a draft."
	else:
		status_node.text = "Draft %s selection: %s" % [
			String(selection.get("kind", "")),
			String(selection.get("label", "")),
		]


func _reference_text(refs: Array) -> String:
	if refs.is_empty():
		return "No supporting references."
	var lines: Array[String] = []
	for ref_any: Variant in refs:
		if typeof(ref_any) == TYPE_DICTIONARY:
			var ref_data: Dictionary = ref_any
			lines.append(
				"• %s%s"
				% [
					String(ref_data.get("title", ref_data.get("id", "Source"))),
					(
						": " + String(ref_data.get("excerpt", "")).left(180)
						if not String(ref_data.get("excerpt", "")).is_empty()
						else ""
					),
				]
			)
	return "\n".join(lines)


func _lines(text_value: String) -> Array[String]:
	var output: Array[String] = []
	for line_text: String in text_value.split("\n", false):
		var clean_text: String = line_text.strip_edges()
		if not clean_text.is_empty():
			output.append(clean_text)
	return output


func _set_status(status_text: String) -> void:
	var status_node: Label = _control("PathCommitStatus") as Label
	if status_node:
		status_node.text = status_text


func _control(control_id: String) -> Control:
	return (
		_panel_node.find_child(control_id, true, false) as Control
		if is_instance_valid(_panel_node)
		else null
	)
