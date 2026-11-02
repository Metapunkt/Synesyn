## Purpose: Review AI-assisted Context Graph proposals before any commit.
extends PanelContainer

signal generate_requested(request_text: String)
signal review_requested(
	proposal_ids: Array[String],
	decision: String,
	edited_payload: Dictionary,
	reviewer_note: String
)
signal preview_requested(proposal_ids: Array[String])
signal commit_requested

@onready var request_edit: TextEdit = %ProposalRequest
@onready var proposal_list: ItemList = %ProposalList
@onready var payload_edit: TextEdit = %ProposalPayload
@onready var reviewer_note: LineEdit = %ReviewerNote
@onready var impact_text: TextEdit = %ProposalImpact
@onready var status_label: Label = %ProposalStatus

var _proposals: Array[Dictionary] = []


func _ready() -> void:
	%GenerateButton.pressed.connect(_on_generate_pressed)
	%AcceptButton.pressed.connect(
		func() -> void: _emit_review("accepted")
	)
	%SaveEditButton.pressed.connect(
		func() -> void: _emit_review("edited")
	)
	%RejectButton.pressed.connect(
		func() -> void: _emit_review("rejected")
	)
	%DeferButton.pressed.connect(
		func() -> void: _emit_review("deferred")
	)
	%PreviewButton.pressed.connect(
		func() -> void:
			preview_requested.emit(_selected_ids())
	)
	%CommitAcceptedButton.pressed.connect(
		func() -> void: commit_requested.emit()
	)
	proposal_list.item_selected.connect(_on_proposal_selected)


func set_proposals(proposals: Array) -> void:
	_proposals.clear()
	proposal_list.clear()
	for proposal_any in proposals:
		if typeof(proposal_any) != TYPE_DICTIONARY:
			continue
		var proposal: Dictionary = (
			proposal_any as Dictionary
		).duplicate(true)
		_proposals.append(proposal)
		proposal_list.add_item("%s · %s · %s" % [
			str(proposal.get("status", "suggested")),
			str(proposal.get("proposal_type", "")),
			str(proposal.get("id", "")),
		])
		proposal_list.set_item_metadata(
			proposal_list.item_count - 1,
			str(proposal.get("id", ""))
		)
	if proposal_list.item_count > 0:
		proposal_list.select(0)
		_show_proposal(_proposals[0])


func show_impact(impact: Dictionary) -> void:
	impact_text.text = JSON.stringify(impact, "  ")
	status_label.text = (
		"Impact preview ready."
		if bool(impact.get("ok", false))
		else "Impact preview found validation errors."
	)


func show_status(status_text: String) -> void:
	status_label.text = status_text


func _on_generate_pressed() -> void:
	var request_text: String = request_edit.text.strip_edges()
	if not request_text.is_empty():
		generate_requested.emit(request_text)


func _on_proposal_selected(item_index: int) -> void:
	if item_index >= 0 and item_index < _proposals.size():
		_show_proposal(_proposals[item_index])


func _show_proposal(proposal: Dictionary) -> void:
	payload_edit.text = JSON.stringify(
		proposal.get("payload", {}),
		"  "
	)
	status_label.text = (
		"%s\nEvidence: %s\nModel/provider: %s / %s\n"
		+ "Confidence: %.2f · Prompt/config: %s"
	) % [
		str(proposal.get("rationale", "")),
		", ".join(proposal.get("evidence_refs", [])),
		str(proposal.get("model_id", "")),
		str(proposal.get("provider_id", "")),
		float(proposal.get("confidence", 0.0)),
		JSON.stringify(proposal.get("prompt_config", {})),
	]


func _emit_review(decision: String) -> void:
	var proposal_ids: Array[String] = _selected_ids()
	if proposal_ids.is_empty():
		return
	var edited_payload: Dictionary = {}
	if decision == "edited":
		var parsed: Variant = JSON.parse_string(payload_edit.text)
		if typeof(parsed) != TYPE_DICTIONARY:
			show_status("Edited payload must be a JSON object.")
			return
		edited_payload = parsed
	review_requested.emit(
		proposal_ids,
		decision,
		edited_payload,
		reviewer_note.text
	)


func _selected_ids() -> Array[String]:
	var proposal_ids: Array[String] = []
	for item_index in proposal_list.get_selected_items():
		proposal_ids.append(str(
			proposal_list.get_item_metadata(item_index)
		))
	return proposal_ids
