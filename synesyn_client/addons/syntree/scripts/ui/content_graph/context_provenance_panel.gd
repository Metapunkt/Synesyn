## Purpose: Inspect and edit auditable provenance for Context Graph nodes.
extends PanelContainer

signal node_selected(node_id: String)
signal save_requested(node_id: String, provenance: Dictionary)
signal open_source_requested(source_uri: String)

const ContextGraphProvenanceScript = preload(
	"res://addons/syntree/scripts/core/context_graph_provenance.gd"
)

@onready var node_selector: OptionButton = %ProvenanceNodeSelector
@onready var authorship_selector: OptionButton = %AuthorshipSelector
@onready var evidence_selector: OptionButton = %EvidenceSelector
@onready var review_selector: OptionButton = %ReviewSelector
@onready var origin_edit: LineEdit = %OriginEdit
@onready var source_uri_edit: LineEdit = %SourceUriEdit
@onready var artifact_edit: LineEdit = %SourceArtifactEdit
@onready var version_edit: LineEdit = %SourceVersionEdit
@onready var author_edit: LineEdit = %AuthorEdit
@onready var produced_by_edit: LineEdit = %ProducedByEdit
@onready var model_edit: LineEdit = %ModelEdit
@onready var created_at_edit: LineEdit = %CreatedAtEdit
@onready var derivation_edit: TextEdit = %DerivationEdit
@onready var evidence_paths: RichTextLabel = %EvidencePaths
@onready var status_label: Label = %ProvenanceStatus

var _provenance: RefCounted = ContextGraphProvenanceScript.new()


func _ready() -> void:
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
	node_selector.item_selected.connect(_on_node_selected)
	%SaveProvenanceButton.pressed.connect(_on_save_pressed)
	%OpenSourceButton.pressed.connect(_on_open_source_pressed)


func set_node_ids(node_ids: Array[String]) -> void:
	node_selector.clear()
	for node_id in node_ids:
		node_selector.add_item(node_id)
		node_selector.set_item_metadata(
			node_selector.item_count - 1,
			node_id
		)
	if node_selector.item_count > 0:
		node_selector.select(0)
		node_selected.emit(str(node_selector.get_item_metadata(0)))


func show_provenance(provenance: Dictionary) -> void:
	var normalized: Dictionary = _provenance.call(
		"normalize",
		provenance
	)
	_select_option(
		authorship_selector,
		str(normalized.get("authorship_kind", "unknown"))
	)
	_select_option(
		evidence_selector,
		str(normalized.get("evidence_status", "unknown"))
	)
	_select_option(
		review_selector,
		str(normalized.get("review_status", "unknown"))
	)
	origin_edit.text = str(normalized.get("origin_ref", "unknown"))
	var source_location: Dictionary = normalized.get(
		"source_location",
		{}
	)
	source_uri_edit.text = str(source_location.get("uri", ""))
	artifact_edit.text = str(normalized.get("source_artifact_id", ""))
	version_edit.text = str(normalized.get("source_version_id", ""))
	author_edit.text = str(normalized.get("author_id", ""))
	produced_by_edit.text = str(normalized.get("produced_by", ""))
	model_edit.text = str(normalized.get("model_id", ""))
	created_at_edit.text = str(normalized.get("created_at", ""))
	derivation_edit.text = "\n".join(
		_unique_strings(normalized.get("derivation_refs", []))
	)
	status_label.text = "Loaded recorded provenance."


func show_status(status_text: String) -> void:
	status_label.text = status_text


func show_evidence_paths(
	supporting_paths: Array[String],
	conflicting_paths: Array[String]
) -> void:
	var supporting_text: String = (
		"none recorded"
		if supporting_paths.is_empty()
		else "\n".join(supporting_paths)
	)
	var conflicting_text: String = (
		"none recorded"
		if conflicting_paths.is_empty()
		else "\n".join(conflicting_paths)
	)
	evidence_paths.text = (
		"[color=#73d7a0]Supporting[/color]\n%s\n"
		+ "[color=#ef799b]Conflicting[/color]\n%s"
	) % [supporting_text, conflicting_text]


func _current_node_id() -> String:
	if node_selector.selected < 0:
		return ""
	return str(node_selector.get_item_metadata(node_selector.selected))


func _current_provenance() -> Dictionary:
	return _provenance.call("normalize", {
		"authorship_kind": _selected_id(authorship_selector),
		"evidence_status": _selected_id(evidence_selector),
		"review_status": _selected_id(review_selector),
		"origin_ref": origin_edit.text,
		"source_location": {"uri": source_uri_edit.text},
		"source_artifact_id": artifact_edit.text,
		"source_version_id": version_edit.text,
		"author_id": author_edit.text,
		"produced_by": produced_by_edit.text,
		"model_id": model_edit.text,
		"created_at": created_at_edit.text,
		"derivation_refs": _lines(derivation_edit.text),
	})


func _on_node_selected(item_index: int) -> void:
	node_selected.emit(str(node_selector.get_item_metadata(item_index)))


func _on_save_pressed() -> void:
	var node_id: String = _current_node_id()
	if not node_id.is_empty():
		save_requested.emit(node_id, _current_provenance())


func _on_open_source_pressed() -> void:
	var source_uri: String = source_uri_edit.text.strip_edges()
	if not source_uri.is_empty():
		open_source_requested.emit(source_uri)


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


func _selected_id(selector: OptionButton) -> String:
	if selector.selected < 0:
		return "unknown"
	return str(selector.get_item_metadata(selector.selected))


func _lines(value_text: String) -> Array[String]:
	return _unique_strings(value_text.split("\n", false))


func _unique_strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	for value_any in values:
		var value_text: String = str(value_any).strip_edges()
		if not value_text.is_empty() and not result.has(value_text):
			result.append(value_text)
	return result
