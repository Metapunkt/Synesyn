extends Control
class_name CampaignDashboard
## Per-campaign / per-theme content planning dashboard.


signal refresh_requested

@onready var group_by_option: OptionButton = $VBox/Header/GroupByOption
@onready var refresh_button: Button = $VBox/Header/RefreshButton
@onready var summary_label: Label = $VBox/SummaryLabel
@onready var report_text: TextEdit = $VBox/Scroll/ReportText
@onready var cadence_label: Label = $VBox/CadenceLabel

var _workplan: Resource = null
var _last_report: Dictionary = {}


func _ready() -> void:
	if group_by_option:
		group_by_option.clear()
		group_by_option.add_item("By campaign", 0)
		group_by_option.add_item("By theme", 1)
		group_by_option.item_selected.connect(_on_group_by_changed)
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)
	_apply_report_contrast()
	_refresh()


func _apply_report_contrast() -> void:
	"""Read-only TextEdit otherwise uses washed font_readonly_color on a mid-grey panel."""
	const ReadableTextScript = preload("res://readymade/scripts/readymade_readable_text.gd")
	if report_text != null:
		ReadableTextScript.apply_report_text_edit(report_text)


func set_workplan(workplan: Resource) -> void:
	_workplan = workplan
	_refresh()


func get_last_report() -> Dictionary:
	return _last_report


func _group_mode() -> String:
	if group_by_option and group_by_option.selected == 1:
		return "theme"
	return "campaign"


func _on_group_by_changed(_index: int) -> void:
	_refresh()


func _on_refresh_pressed() -> void:
	refresh_requested.emit()
	_refresh()


func _refresh() -> void:
	const DashboardScript = preload("res://readymade/scripts/workplan_campaign_dashboard.gd")
	if _workplan == null:
		var manager: Node = get_node_or_null("/root/WorkplanManager")
		if manager != null and manager.has_method("get_current_workplan"):
			_workplan = manager.get_current_workplan()
	_last_report = DashboardScript.build(_workplan, _group_mode())
	if report_text:
		report_text.text = DashboardScript.render_text(_last_report)
	var totals: Dictionary = _last_report.get("totals", {})
	if summary_label:
		summary_label.text = (
			"%d tasks · %d upcoming · %d overdue · %d open slots · %.0f%% posted"
			% [
				int(totals.get("total", 0)),
				int(totals.get("upcoming", 0)),
				int(totals.get("overdue", 0)),
				int(totals.get("open_slots", 0)),
				DashboardScript.completion_ratio(totals) * 100.0,
			]
		)
	if cadence_label:
		var cadence: Array = _last_report.get("cadence", [])
		if cadence.is_empty():
			cadence_label.text = "Cadence: within caps"
			cadence_label.modulate = Color(0.7, 0.95, 0.7)
		else:
			cadence_label.text = "Cadence: %d warning(s)" % cadence.size()
			cadence_label.modulate = Color(0.95, 0.75, 0.35)
