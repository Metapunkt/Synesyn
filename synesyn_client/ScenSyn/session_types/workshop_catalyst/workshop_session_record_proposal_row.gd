extends VBoxContainer
class_name WorkshopSessionRecordProposalRow

signal accept_requested(proposal_id: String)
signal edit_requested(proposal_id: String, edited_text: String)
signal reject_requested(proposal_id: String)
signal defer_requested(proposal_id: String)

var _proposal_id: String = ""
@onready var _category_label_node: Label = %ProposalCategoryLabel
@onready var _editor_node: LineEdit = %ProposalEditor
@onready var _accept_button_node: Button = %AcceptProposalButton
@onready var _edit_button_node: Button = %EditProposalButton
@onready var _reject_button_node: Button = %RejectProposalButton
@onready var _defer_button_node: Button = %DeferProposalButton


func _ready() -> void:
	_accept_button_node.pressed.connect(func() -> void: accept_requested.emit(_proposal_id))
	_edit_button_node.pressed.connect(
		func() -> void: edit_requested.emit(_proposal_id, _editor_node.text)
	)
	_reject_button_node.pressed.connect(func() -> void: reject_requested.emit(_proposal_id))
	_defer_button_node.pressed.connect(func() -> void: defer_requested.emit(_proposal_id))


func configure(proposal: Dictionary) -> void:
	_proposal_id = String(proposal.get("id", ""))
	_category_label_node.text = String(proposal.get("category", "")).replace("_", " ").capitalize()
	_editor_node.text = String(proposal.get("text", ""))
