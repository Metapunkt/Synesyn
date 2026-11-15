extends Control
class_name StageBoardView
## Kanban view for workflow or content-plan status columns.


const StageBoardScript = preload("res://readymade/scripts/workplan_stage_board.gd")
const DragCardScript = preload("res://readymade/ui/stage_board_drag_card.gd")
const ColumnDropScript = preload("res://readymade/ui/stage_board_column_drop.gd")

@onready var mode_option: OptionButton = $VBox/Header/ModeOption
@onready var search_edit: LineEdit = $VBox/Header/SearchEdit
@onready var assignee_filter: OptionButton = $VBox/Header/AssigneeFilter
@onready var refresh_button: Button = $VBox/Header/RefreshButton
@onready var columns_hbox: HBoxContainer = $VBox/BoardScroll/ColumnsHBox

var _workplan: Resource = null
var _board_mode: String = "workflow"


func _ready() -> void:
	if mode_option:
		mode_option.clear()
		mode_option.add_item("Workflow", 0)
		mode_option.add_item("Content status", 1)
		mode_option.item_selected.connect(_on_mode_changed)
	if assignee_filter:
		assignee_filter.item_selected.connect(_on_assignee_filter_changed)
	if search_edit:
		search_edit.text_changed.connect(_on_search_changed)
	if refresh_button:
		refresh_button.pressed.connect(refresh)
	_board_mode = _board_mode_id()
	refresh()


func set_workplan(workplan: Resource) -> void:
	_workplan = workplan
	_rebuild_assignee_filter()
	refresh()


func refresh() -> void:
	if columns_hbox == null:
		return
	for child in columns_hbox.get_children():
		child.queue_free()
	var filters: Dictionary = _current_filters()
	var columns: Array = StageBoardScript.build_columns(_workplan, _board_mode, filters)
	for column_any in columns:
		var column: Dictionary = column_any
		columns_hbox.add_child(_build_column_panel(column))


func _board_mode_id() -> String:
	if mode_option and mode_option.selected == 1:
		return "content_status"
	return "workflow"


func _current_filters() -> Dictionary:
	var assignee_val: String = "(any)"
	if assignee_filter and assignee_filter.item_count > 0:
		assignee_val = assignee_filter.get_item_text(assignee_filter.selected)
	var search_val: String = ""
	if search_edit:
		search_val = search_edit.text
	return {
		"channel": "",
		"assignee": assignee_val,
		"search": search_val,
	}


func _rebuild_assignee_filter() -> void:
	if assignee_filter == null:
		return
	assignee_filter.clear()
	assignee_filter.add_item("(any)")
	var seen: Dictionary = {}
	if _workplan != null and _workplan.has_method("get_all_tasks"):
		for task_any in _workplan.get_all_tasks():
			var task: WorkplanTask = task_any as WorkplanTask
			if task == null:
				continue
			var assignee_label: String = task.assignee.strip_edges()
			if assignee_label.is_empty():
				continue
			var key: String = assignee_label.to_lower()
			if seen.has(key):
				continue
			seen[key] = true
			assignee_filter.add_item(assignee_label)
	assignee_filter.selected = 0


func _build_column_panel(column: Dictionary) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(220, 320)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var col_id: String = String(column.get("id", ""))
	var title: String = String(column.get("title", col_id))
	var vbox: VBoxContainer = ColumnDropScript.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.call("configure", col_id, Callable(self, "_on_drop_task"))
	margin.add_child(vbox)
	var tasks: Array = column.get("tasks", [])
	var header: Label = Label.new()
	header.text = "%s (%d)" % [title, tasks.size()]
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)
	var task_scroll: ScrollContainer = ScrollContainer.new()
	task_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	task_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(task_scroll)
	var task_list: VBoxContainer = VBoxContainer.new()
	task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_scroll.add_child(task_list)
	for task_any in tasks:
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		task_list.add_child(_build_task_card(task, col_id))
	return panel


func _build_task_card(task: WorkplanTask, column_id: String) -> PanelContainer:
	var card: PanelContainer = DragCardScript.new()
	card.call("setup_drag", task)
	card.set_meta("task_ref", task)
	card.set_meta("column_id", column_id)
	var is_blocked: bool = StageBoardScript.is_blocked(task, _workplan)
	if is_blocked:
		card.modulate = Color(1.0, 0.85, 0.7)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	card.add_child(margin)
	var inner: VBoxContainer = VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(inner)
	var title_label: Label = Label.new()
	title_label.text = ("⛔ " if is_blocked else "") + task.title
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(title_label)
	var nav: HBoxContainer = HBoxContainer.new()
	inner.add_child(nav)
	var prev_btn: Button = Button.new()
	prev_btn.text = "←"
	prev_btn.pressed.connect(_on_move_task.bind(task, column_id, -1))
	nav.add_child(prev_btn)
	var next_btn: Button = Button.new()
	next_btn.text = "→"
	next_btn.pressed.connect(_on_move_task.bind(task, column_id, 1))
	nav.add_child(next_btn)
	return card


func _on_move_task(task: WorkplanTask, column_id: String, direction: int) -> void:
	var column_ids: Array[String] = _column_id_list()
	var index: int = column_ids.find(column_id)
	if index < 0:
		return
	var next_index: int = index + direction
	if next_index < 0 or next_index >= column_ids.size():
		return
	_apply_move(task, column_ids[next_index])


func _on_drop_task(target_column_id: String, task: WorkplanTask) -> void:
	_apply_move(task, target_column_id)


func _apply_move(task: WorkplanTask, target_column_id: String) -> void:
	if task == null:
		return
	var moved: bool = StageBoardScript.move_task_to_column(task, target_column_id, _board_mode)
	if not moved:
		return
	if _workplan != null and _workplan.has_method("update_task"):
		_workplan.update_task()
	refresh()


func _column_id_list() -> Array[String]:
	if _board_mode == "content_status":
		return StageBoardScript.content_status_column_ids()
	return StageBoardScript.workflow_column_ids()


func _on_mode_changed(_index: int) -> void:
	_board_mode = _board_mode_id()
	refresh()


func _on_search_changed(_new_text: String) -> void:
	refresh()


func _on_assignee_filter_changed(_index: int) -> void:
	refresh()