## Purpose: Configure deterministic Context Graph focus and visibility filters.
extends PanelContainer

signal apply_requested(options: Dictionary)
signal reset_requested
signal fit_relevant_requested

@onready var node_selector: OptionButton = %FocusNodeSelector
@onready var status_label: Label = %FocusStatus


func _ready() -> void:
	%ApplyFocusButton.pressed.connect(
		func() -> void: apply_requested.emit(get_options())
	)
	%ResetFocusButton.pressed.connect(
		func() -> void: reset_requested.emit()
	)
	%FitRelevantButton.pressed.connect(
		func() -> void: fit_relevant_requested.emit()
	)


func set_node_ids(node_ids: Array[String]) -> void:
	node_selector.clear()
	node_selector.add_item("No neighborhood focus")
	node_selector.set_item_metadata(0, "")
	for node_id in node_ids:
		node_selector.add_item(node_id)
		node_selector.set_item_metadata(
			node_selector.item_count - 1,
			node_id
		)


func get_options() -> Dictionary:
	var focus_node_id: String = ""
	if node_selector.selected >= 0:
		focus_node_id = str(
			node_selector.get_item_metadata(node_selector.selected)
		)
	return {
		"search_text": %SearchEdit.text,
		"tag": %TagEdit.text,
		"relationship_types": _comma_values(%RelationsEdit.text),
		"activation_modes": _comma_values(%ActivationEdit.text),
		"authorship_kinds": _comma_values(%AuthorshipEdit.text),
		"review_states": _comma_values(%ReviewStateEdit.text),
		"focus_node_id": focus_node_id,
		"focus_depth": int(%FocusDepth.value),
		"collapsed_node_ids": _comma_values(%CollapsedEdit.text, false),
		"show_inactive": %ShowInactive.button_pressed,
		"show_rejected": %ShowRejected.button_pressed,
		"show_low_confidence": %ShowLowConfidence.button_pressed,
		"show_unrelated": %ShowUnrelated.button_pressed,
		"confidence_threshold": %ConfidenceThreshold.value,
	}


func show_result(result: Dictionary) -> void:
	status_label.text = "Showing %d nodes/%d edges; hidden %d/%d." % [
		(result.get("visible_node_ids", []) as Array).size(),
		(result.get("visible_edge_ids", []) as Array).size(),
		int(result.get("hidden_node_count", 0)),
		int(result.get("hidden_edge_count", 0)),
	]


func show_reset() -> void:
	status_label.text = "All graph records are visible."


func show_status(status_text: String) -> void:
	status_label.text = status_text


func _comma_values(
	value_text: String,
	normalize_case: bool = true
) -> Array[String]:
	var result: Array[String] = []
	for value_any in value_text.split(",", false):
		var item_text: String = str(value_any).strip_edges()
		if normalize_case:
			item_text = item_text.to_lower()
		if not item_text.is_empty() and not result.has(item_text):
			result.append(item_text)
	return result
