extends RefCounted
class_name WorkshopSessionRecordPanelController

signal state_changed

const AutoloadsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_autoloads.gd"
)
const ItemRowScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_item_row.tscn"
)
const ProposalRowScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_proposal_row.tscn"
)
const ProposeThemesEntryScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_propose_themes_entry.gd"
)
const CATEGORIES: Array[String] = [
	"decisions",
	"risks",
	"open_questions",
	"owners",
	"next_steps",
]

var _panel_node: Control = null
var _store: RefCounted = null
var _persistence: Node = null
var _facilitator_ref: String = "Facilitator"
var _closure_refs: Array = []
var _category_controls: Dictionary = {}
var _previewed_summary_hash: String = ""


func mount(
	panel_node: Control,
	store: RefCounted,
	persistence: Node
) -> bool:
	_panel_node = panel_node
	_store = store
	_persistence = persistence
	if not is_instance_valid(_panel_node) or not _store or not _persistence:
		return false
	_category_controls = {
		"decisions": {
			"items": _panel_node.get_node_or_null("%DecisionsItems"),
			"editor": _panel_node.get_node_or_null("%DecisionDraftEditor"),
			"button": _panel_node.get_node_or_null("%AddDecisionButton"),
		},
		"risks": {
			"items": _panel_node.get_node_or_null("%RisksItems"),
			"editor": _panel_node.get_node_or_null("%RiskDraftEditor"),
			"button": _panel_node.get_node_or_null("%AddRiskButton"),
		},
		"open_questions": {
			"items": _panel_node.get_node_or_null("%OpenQuestionsItems"),
			"editor": _panel_node.get_node_or_null("%OpenQuestionDraftEditor"),
			"button": _panel_node.get_node_or_null("%AddOpenQuestionButton"),
		},
		"owners": {
			"items": _panel_node.get_node_or_null("%OwnersItems"),
			"editor": _panel_node.get_node_or_null("%OwnerDraftEditor"),
			"button": _panel_node.get_node_or_null("%AddOwnerButton"),
		},
		"next_steps": {
			"items": _panel_node.get_node_or_null("%NextStepsItems"),
			"editor": _panel_node.get_node_or_null("%NextStepDraftEditor"),
			"button": _panel_node.get_node_or_null("%AddNextStepButton"),
		},
	}
	for category_id: String in _category_controls:
		var controls: Dictionary = _category_controls[category_id]
		if not controls["items"] or not controls["editor"] or not controls["button"]:
			return false
		(controls["button"] as Button).pressed.connect(
			func() -> void: _add_facilitator_item(category_id)
		)
	var preview_button_node: Button = _panel_node.get_node_or_null("%PreviewSummaryButton")
	var commit_button_node: Button = _panel_node.get_node_or_null("%CommitSummaryButton")
	var retry_button_node: Button = _panel_node.get_node_or_null("%RetryCommitButton")
	var propose_themes_button_node: Button = _panel_node.get_node_or_null("%ProposeThemesButton")
	if not preview_button_node or not commit_button_node or not retry_button_node:
		return false
	preview_button_node.pressed.connect(show_preview)
	commit_button_node.pressed.connect(_request_commit)
	retry_button_node.pressed.connect(_persistence.retry)
	if propose_themes_button_node and not propose_themes_button_node.pressed.is_connected(_on_propose_themes_pressed):
		propose_themes_button_node.pressed.connect(_on_propose_themes_pressed)
	_persistence.commit_started.connect(_on_commit_started)
	_persistence.commit_succeeded.connect(_on_commit_succeeded)
	_persistence.commit_failed.connect(_on_commit_failed)
	refresh()
	return true


func set_context(session_label: String, stage_title: String) -> void:
	if not is_instance_valid(_panel_node):
		return
	var context_label_node: Label = _panel_node.get_node_or_null("%RecordContextLabel")
	if context_label_node:
		context_label_node.text = (
			"%s • %s\nReview AI proposals below. Nothing is committed automatically."
			% [session_label, stage_title]
		)


func set_closure_refs(closure_refs: Array) -> void:
	_closure_refs = closure_refs.duplicate(true)


func refresh() -> void:
	if not is_instance_valid(_panel_node) or not _store:
		return
	var reviewed: Dictionary = _store.get_reviewed()
	for category_id: String in CATEGORIES:
		var controls: Dictionary = _category_controls.get(category_id, {})
		var items_node: VBoxContainer = controls.get("items") as VBoxContainer
		if not items_node:
			continue
		_clear_children(items_node)
		var items_any: Variant = reviewed.get(category_id, [])
		var items: Array = items_any if typeof(items_any) == TYPE_ARRAY else []
		for item_any: Variant in items:
			if typeof(item_any) != TYPE_DICTIONARY:
				continue
			var row_node: Node = ItemRowScene.instantiate()
			items_node.add_child(row_node)
			row_node.call("configure", item_any)
			row_node.connect(
				"save_requested",
				func(item_id: String, edited_text: String) -> void:
					if _store.edit_reviewed_item(
						category_id,
						item_id,
						edited_text,
						_facilitator_ref
					):
						_after_local_change()
			)
			row_node.connect(
				"remove_requested",
				func(item_id: String) -> void:
					if _store.remove_reviewed_item(category_id, item_id):
						_after_local_change()
			)
	_refresh_proposals()
	_refresh_commit_state()


func _on_propose_themes_pressed() -> void:
	## REQ-NDP-016: open SynAxes with current/last session preloaded; discover queued.
	if not is_instance_valid(_panel_node):
		return
	var tree_ref: SceneTree = _panel_node.get_tree()
	var session_id: String = ""
	if _store and _store.has_method("get_session_id"):
		session_id = str(_store.call("get_session_id")).strip_edges()
	ProposeThemesEntryScript.open(tree_ref, session_id)


func show_preview() -> Dictionary:
	var preview: Dictionary = _store.build_preview(_facilitator_ref, _closure_refs)
	var preview_panel_node: VBoxContainer = _panel_node.get_node_or_null("%PreviewPanel")
	var preview_text_node: TextEdit = _panel_node.get_node_or_null("%PreviewText")
	if preview_panel_node and preview_text_node:
		preview_panel_node.visible = true
		preview_text_node.text = JSON.stringify(preview, "\t")
	_previewed_summary_hash = JSON.stringify(
		preview.get("resulting_summary", {})
	).sha256_text()
	var commit_button_node: Button = _panel_node.get_node_or_null("%CommitSummaryButton")
	if commit_button_node:
		commit_button_node.disabled = false
	return preview


func _refresh_proposals() -> void:
	var proposal_items_node: VBoxContainer = _panel_node.get_node_or_null("%ProposalItems")
	var no_proposals_label_node: Label = _panel_node.get_node_or_null("%NoProposalsLabel")
	if not proposal_items_node or not no_proposals_label_node:
		return
	_clear_children(proposal_items_node)
	var pending_count: int = 0
	for proposal: Dictionary in _store.get_proposals():
		if String(proposal.get("status", "")) != "suggested":
			continue
		pending_count += 1
		var row_node: Node = ProposalRowScene.instantiate()
		proposal_items_node.add_child(row_node)
		row_node.call("configure", proposal)
		row_node.connect("accept_requested", _accept_proposal)
		row_node.connect("edit_requested", _edit_proposal)
		row_node.connect("reject_requested", _reject_proposal)
		row_node.connect("defer_requested", _defer_proposal)
	no_proposals_label_node.visible = pending_count == 0


func _add_facilitator_item(category_id: String) -> void:
	var controls: Dictionary = _category_controls[category_id]
	var editor_node: LineEdit = controls["editor"] as LineEdit
	if _store.add_facilitator_item(
		category_id,
		editor_node.text,
		_facilitator_ref
	).is_empty():
		return
	editor_node.text = ""
	_after_local_change()


func _accept_proposal(proposal_id: String) -> void:
	if _store.accept(proposal_id, _facilitator_ref):
		_after_local_change()


func _edit_proposal(proposal_id: String, edited_text: String) -> void:
	if _store.edit_proposal(proposal_id, edited_text, _facilitator_ref):
		_after_local_change()


func _reject_proposal(proposal_id: String) -> void:
	if _store.reject(proposal_id, _facilitator_ref):
		_after_local_change()


func _defer_proposal(proposal_id: String) -> void:
	if _store.defer(proposal_id, _facilitator_ref):
		_after_local_change()


func _after_local_change() -> void:
	_previewed_summary_hash = ""
	state_changed.emit()
	refresh()


func _request_commit() -> void:
	var presence_node: Node = AutoloadsScript.workshop_presence()
	if (
		presence_node
		and presence_node.has_method("is_active")
		and presence_node.is_active()
		and not bool(presence_node.call("has_local_facilitator_claim"))
	):
		var blocked_status_node: Label = _panel_node.get_node_or_null("%PersistenceStatusLabel")
		if blocked_status_node:
			blocked_status_node.text = "Commit requires a Facilitator claim."
		return
	var current_preview: Dictionary = _store.build_preview(_facilitator_ref, _closure_refs)
	var current_hash: String = JSON.stringify(
		current_preview.get("resulting_summary", {})
	).sha256_text()
	if _previewed_summary_hash.is_empty() or current_hash != _previewed_summary_hash:
		show_preview()
		var status_label_node: Label = _panel_node.get_node_or_null("%PersistenceStatusLabel")
		if status_label_node:
			status_label_node.text = (
				"Preview refreshed. Review the complete summary and diff, then commit."
			)
		return
	_persistence.request_commit(_facilitator_ref, _closure_refs)


func _on_commit_started() -> void:
	var status_label_node: Label = _panel_node.get_node_or_null("%PersistenceStatusLabel")
	var commit_button_node: Button = _panel_node.get_node_or_null("%CommitSummaryButton")
	if status_label_node:
		status_label_node.text = "Committing a new immutable Workshop summary version…"
	if commit_button_node:
		commit_button_node.disabled = true


func _on_commit_succeeded(artifact_id: String, _payload: Dictionary) -> void:
	_previewed_summary_hash = ""
	var status_label_node: Label = _panel_node.get_node_or_null("%PersistenceStatusLabel")
	if status_label_node:
		status_label_node.text = "Committed Workshop summary: %s" % artifact_id
	state_changed.emit()
	_refresh_commit_state()


func _on_commit_failed(error_text: String) -> void:
	var status_label_node: Label = _panel_node.get_node_or_null("%PersistenceStatusLabel")
	if status_label_node:
		status_label_node.text = error_text
	_refresh_commit_state()


func _refresh_commit_state() -> void:
	var commit_state_label_node: Label = _panel_node.get_node_or_null("%CommitStateLabel")
	var commit_button_node: Button = _panel_node.get_node_or_null("%CommitSummaryButton")
	var retry_button_node: Button = _panel_node.get_node_or_null("%RetryCommitButton")
	if commit_button_node:
		commit_button_node.disabled = (
			_persistence.is_committing() or _previewed_summary_hash.is_empty()
		)
	if retry_button_node:
		retry_button_node.visible = _persistence.has_retryable_commit()
	if not commit_state_label_node:
		return
	var artifact_id: String = _store.get_last_committed_artifact_id()
	if artifact_id.is_empty():
		commit_state_label_node.text = "Uncommitted draft"
	elif _store.is_dirty():
		commit_state_label_node.text = "Draft changed since %s" % artifact_id
	else:
		commit_state_label_node.text = "Committed %s" % artifact_id


func _clear_children(parent_node: Node) -> void:
	for child_node: Node in parent_node.get_children():
		parent_node.remove_child(child_node)
		child_node.queue_free()
