@tool
extends PanelContainer

signal save_requested(edge_data: Dictionary)
signal cancel_new_requested
signal reverse_requested(edge_id: String)
signal disconnect_requested(edge_id: String)
signal edge_selected(edge_id: String)
signal endpoints_create_requested(from_id: String, to_id: String)

const RelationshipRegistryScript = preload(
	"res://addons/syntree/scripts/core/context_graph_relationship_registry.gd"
)
const ContextGraphProvenanceScript = preload(
	"res://addons/syntree/scripts/core/context_graph_provenance.gd"
)

@onready var edge_selector: OptionButton = %EdgeSelector
@onready var from_selector: OptionButton = %FromSelector
@onready var to_selector: OptionButton = %ToSelector
@onready var create_endpoints_button: Button = %CreateEndpointsButton
@onready var empty_label: Label = %EmptyLabel
@onready var editor_container: VBoxContainer = %EditorContainer
@onready var endpoints_label: Label = %EndpointsLabel
@onready var relation_selector: OptionButton = %RelationSelector
@onready var notes_edit: TextEdit = %NotesEdit
@onready var confidence_spin: SpinBox = %ConfidenceSpin
@onready var authorship_selector: OptionButton = %AuthorshipSelector
@onready var evidence_selector: OptionButton = %EvidenceSelector
@onready var review_selector: OptionButton = %ReviewSelector
@onready var provenance_summary: RichTextLabel = %ProvenanceSummary
@onready var save_button: Button = %SaveButton
@onready var cancel_button: Button = %CancelButton
@onready var reverse_button: Button = %ReverseButton
@onready var disconnect_button: Button = %DisconnectButton
@onready var disconnect_confirmation: ConfirmationDialog = %DisconnectConfirmation

var _edges: Array = []
var _current_edge: Dictionary = {}
var _is_new_edge: bool = false
var _provenance: RefCounted = ContextGraphProvenanceScript.new()


func _ready() -> void:
	_populate_relations()
	_populate_provenance_options()
	edge_selector.item_selected.connect(_on_edge_selected)
	create_endpoints_button.pressed.connect(_on_create_endpoints_pressed)
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	reverse_button.pressed.connect(_on_reverse_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	disconnect_confirmation.confirmed.connect(_on_disconnect_confirmed)
	clear_editor()


func set_edges(edges: Array) -> void:
	_edges = edges.duplicate(true)
	edge_selector.clear()
	edge_selector.add_item("Select a relationship…")
	edge_selector.set_item_metadata(0, "")
	for edge_any in _edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		var relation_id: String = str(edge_data.get("relation", ""))
		var relation_definition: Dictionary = RelationshipRegistryScript.definition(
			relation_id
		)
		var relation_label: String = str(
			relation_definition.get("label", relation_id)
		)
		var item_text: String = "%s → %s · %s" % [
			str(edge_data.get("from", "")),
			str(edge_data.get("to", "")),
			relation_label,
		]
		edge_selector.add_item(item_text)
		edge_selector.set_item_metadata(
			edge_selector.item_count - 1,
			str(edge_data.get("id", ""))
		)


func set_node_ids(node_ids: Array[String]) -> void:
	from_selector.clear()
	to_selector.clear()
	for node_id in node_ids:
		from_selector.add_item(node_id)
		from_selector.set_item_metadata(from_selector.item_count - 1, node_id)
		to_selector.add_item(node_id)
		to_selector.set_item_metadata(to_selector.item_count - 1, node_id)
	if to_selector.item_count > 1:
		to_selector.select(1)
	create_endpoints_button.disabled = node_ids.size() < 2


func show_new_connection(from_id: String, to_id: String) -> void:
	_is_new_edge = true
	_current_edge = {"from": from_id, "to": to_id}
	empty_label.visible = false
	editor_container.visible = true
	endpoints_label.text = "%s → %s" % [from_id, to_id]
	_select_relation("contains")
	notes_edit.text = ""
	confidence_spin.value = 1.0
	_select_option(authorship_selector, "user_authored")
	_select_option(evidence_selector, "unknown")
	_select_option(review_selector, "reviewed")
	provenance_summary.text = "Origin: unknown"
	save_button.text = "Create relationship"
	cancel_button.visible = true
	reverse_button.visible = false
	disconnect_button.visible = false
	relation_selector.grab_focus()


func show_edge(edge_data: Dictionary) -> void:
	_is_new_edge = false
	_current_edge = edge_data.duplicate(true)
	empty_label.visible = false
	editor_container.visible = true
	endpoints_label.text = "%s → %s" % [
		str(edge_data.get("from", "")),
		str(edge_data.get("to", "")),
	]
	_select_relation(str(edge_data.get("relation", "related_to")))
	notes_edit.text = str(edge_data.get("notes", ""))
	confidence_spin.value = float(edge_data.get("confidence", 1.0))
	var edge_provenance: Dictionary = _provenance.call(
		"normalize",
		edge_data.get("provenance", {})
	)
	_select_option(
		authorship_selector,
		str(edge_provenance.get("authorship_kind", "unknown"))
	)
	_select_option(
		evidence_selector,
		str(edge_provenance.get("evidence_status", "unknown"))
	)
	_select_option(
		review_selector,
		str(edge_provenance.get("review_status", "unknown"))
	)
	provenance_summary.text = (
		"Origin: %s\nProduced by: %s\nSource artifact/version: %s / %s"
		% [
			str(edge_provenance.get("origin_ref", "unknown")),
			str(edge_provenance.get("produced_by", "")),
			str(edge_provenance.get("source_artifact_id", "")),
			str(edge_provenance.get("source_version_id", "")),
		]
	)
	save_button.text = "Save changes"
	cancel_button.visible = false
	reverse_button.visible = true
	disconnect_button.visible = true


func clear_editor() -> void:
	_current_edge = {}
	_is_new_edge = false
	empty_label.visible = true
	editor_container.visible = false


func _populate_relations() -> void:
	relation_selector.clear()
	for relation_id in RelationshipRegistryScript.relation_ids():
		var relation_definition: Dictionary = RelationshipRegistryScript.definition(
			relation_id
		)
		relation_selector.add_item(str(relation_definition.get("label", relation_id)))
		relation_selector.set_item_metadata(
			relation_selector.item_count - 1,
			relation_id
		)


func _populate_provenance_options() -> void:
	_populate_option(
		authorship_selector,
		ContextGraphProvenanceScript.AUTHORSHIP_KINDS
	)
	_populate_option(
		evidence_selector,
		ContextGraphProvenanceScript.EVIDENCE_STATUSES
	)
	_populate_option(
		review_selector,
		ContextGraphProvenanceScript.REVIEW_STATUSES
	)


func _populate_option(
	selector: OptionButton,
	value_ids: Array[String]
) -> void:
	selector.clear()
	for value_id in value_ids:
		selector.add_item(value_id.replace("_", " ").capitalize())
		selector.set_item_metadata(selector.item_count - 1, value_id)


func _select_option(selector: OptionButton, value_id: String) -> void:
	for item_index in range(selector.item_count):
		if str(selector.get_item_metadata(item_index)) == value_id:
			selector.select(item_index)
			return
	selector.select(0)


func _select_relation(relation_id: String) -> void:
	for item_index in range(relation_selector.item_count):
		if str(relation_selector.get_item_metadata(item_index)) == relation_id:
			relation_selector.select(item_index)
			return
	relation_selector.select(0)


func _on_edge_selected(item_index: int) -> void:
	var edge_id: String = str(edge_selector.get_item_metadata(item_index))
	if edge_id.is_empty():
		clear_editor()
		return
	for edge_any in _edges:
		var edge_data: Dictionary = edge_any
		if str(edge_data.get("id", "")) == edge_id:
			show_edge(edge_data)
			edge_selected.emit(edge_id)
			return


func _on_create_endpoints_pressed() -> void:
	if (
		from_selector.selected < 0
		or to_selector.selected < 0
		or from_selector.selected == to_selector.selected
	):
		return
	var from_id: String = str(
		from_selector.get_item_metadata(from_selector.selected)
	)
	var to_id: String = str(to_selector.get_item_metadata(to_selector.selected))
	endpoints_create_requested.emit(from_id, to_id)


func _on_save_pressed() -> void:
	if _current_edge.is_empty():
		return
	var selected_index: int = relation_selector.selected
	var relation_id: String = str(
		relation_selector.get_item_metadata(selected_index)
	)
	var provenance_refs: Array = _current_edge.get("provenance_refs", [])
	var edge_data: Dictionary = RelationshipRegistryScript.make_edge(
		relation_id,
		str(_current_edge.get("from", "")),
		str(_current_edge.get("to", "")),
		notes_edit.text,
		confidence_spin.value,
		provenance_refs,
		str(_current_edge.get("id", ""))
	)
	edge_data["status"] = str(_current_edge.get("status", "committed"))
	var provenance_data: Dictionary = _current_edge.get(
		"provenance",
		{}
	)
	provenance_data["authorship_kind"] = str(
		authorship_selector.get_item_metadata(authorship_selector.selected)
	)
	provenance_data["evidence_status"] = str(
		evidence_selector.get_item_metadata(evidence_selector.selected)
	)
	provenance_data["review_status"] = str(
		review_selector.get_item_metadata(review_selector.selected)
	)
	edge_data["provenance"] = _provenance.call(
		"normalize",
		provenance_data
	)
	if _current_edge.has("created_at"):
		edge_data["created_at"] = _current_edge["created_at"]
	save_requested.emit(edge_data)


func _on_cancel_pressed() -> void:
	if _is_new_edge:
		cancel_new_requested.emit()
	clear_editor()


func _on_reverse_pressed() -> void:
	var edge_id: String = str(_current_edge.get("id", ""))
	if not edge_id.is_empty():
		reverse_requested.emit(edge_id)


func _on_disconnect_pressed() -> void:
	if not _current_edge.is_empty():
		disconnect_confirmation.popup_centered()


func _on_disconnect_confirmed() -> void:
	var edge_id: String = str(_current_edge.get("id", ""))
	if not edge_id.is_empty():
		disconnect_requested.emit(edge_id)
