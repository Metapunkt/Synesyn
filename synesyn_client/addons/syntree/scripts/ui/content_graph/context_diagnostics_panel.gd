## Purpose: Display graph diagnostics, repair previews, and version comparisons.
extends PanelContainer

signal analyze_requested
signal compare_requested(version_id: String)
signal fork_requested(version_id: String)
signal focus_requested(record_ids: Array[String])

@onready var diagnostics_list: ItemList = %DiagnosticsList
@onready var repair_preview: TextEdit = %RepairPreview
@onready var version_edit: LineEdit = %CompareVersionEdit
@onready var comparison_text: TextEdit = %ComparisonText
@onready var status_label: Label = %DiagnosticsStatus

var _diagnostics: Array[Dictionary] = []


func _ready() -> void:
	%AnalyzeButton.pressed.connect(
		func() -> void: analyze_requested.emit()
	)
	%CompareButton.pressed.connect(
		func() -> void:
			compare_requested.emit(version_edit.text.strip_edges())
	)
	%ForkButton.pressed.connect(
		func() -> void:
			fork_requested.emit(version_edit.text.strip_edges())
	)
	%FocusDiagnosticButton.pressed.connect(_on_focus_pressed)
	diagnostics_list.item_selected.connect(_on_diagnostic_selected)


func set_diagnostics(diagnostics: Array) -> void:
	_diagnostics.clear()
	diagnostics_list.clear()
	for diagnostic_any in diagnostics:
		if typeof(diagnostic_any) != TYPE_DICTIONARY:
			continue
		var diagnostic: Dictionary = (
			diagnostic_any as Dictionary
		).duplicate(true)
		_diagnostics.append(diagnostic)
		diagnostics_list.add_item("%s · %s" % [
			str(diagnostic.get("severity", "")).to_upper(),
			str(diagnostic.get("message", "")),
		])
	if diagnostics_list.item_count > 0:
		diagnostics_list.select(0)
		_show_diagnostic(_diagnostics[0])
	status_label.text = "%d diagnostic(s)." % _diagnostics.size()


func show_comparison(comparison: Dictionary) -> void:
	comparison_text.text = JSON.stringify(comparison, "  ")
	status_label.text = "Version comparison ready."


func show_status(status_text: String) -> void:
	status_label.text = status_text


func _on_diagnostic_selected(item_index: int) -> void:
	if item_index >= 0 and item_index < _diagnostics.size():
		_show_diagnostic(_diagnostics[item_index])


func _show_diagnostic(diagnostic: Dictionary) -> void:
	repair_preview.text = JSON.stringify({
		"type": diagnostic.get("type", ""),
		"affected_record_ids": diagnostic.get(
			"affected_record_ids",
			[]
		),
		"safe_repair_preview": diagnostic.get("repair_preview", {}),
	}, "  ")


func _on_focus_pressed() -> void:
	var selected_items: PackedInt32Array = (
		diagnostics_list.get_selected_items()
	)
	if selected_items.is_empty():
		return
	var diagnostic: Dictionary = _diagnostics[selected_items[0]]
	var record_ids: Array[String] = []
	for record_id_any in diagnostic.get("affected_record_ids", []):
		record_ids.append(str(record_id_any))
	focus_requested.emit(record_ids)
