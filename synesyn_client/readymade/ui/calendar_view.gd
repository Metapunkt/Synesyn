extends Control
class_name CalendarView
## Calendar view for content scheduling and deadline management

signal task_selected(task: WorkplanTask)
signal date_selected(date: String)

@onready var month_label: Label = $VBox/Header/MonthLabel
@onready var prev_button: Button = $VBox/Header/PrevButton
@onready var next_button: Button = $VBox/Header/NextButton
@onready var today_button: Button = $VBox/Header/TodayButton
@onready var view_mode_button: OptionButton = $VBox/Header/ViewModeButton
@onready var filter_button: OptionButton = $VBox/Header/FilterButton
@onready var filter_value_button: OptionButton = $VBox/Header/FilterValueButton
@onready var search_edit: LineEdit = $VBox/Header/SearchEdit
@onready var calendar_grid: GridContainer = $VBox/HSplitContainer/CalendarContainer/CalendarGrid
@onready var task_details: VBoxContainer = $VBox/HSplitContainer/TaskDetails/ScrollContainer/TaskDetails

var current_date: Dictionary
var tasks: Array[WorkplanTask] = []
var filtered_tasks: Array[WorkplanTask] = []
var view_mode: String = "month"  # month, week, agenda
var filter_mode: String = "all"  # all, channel, content_status, campaign, theme, overdue, due_soon
var filter_value: String = ""
var search_query: String = ""
var _empty_state_banner: VBoxContainer = null

func _ready():
	_setup_ui()
	_setup_signals()
	current_date = Time.get_datetime_dict_from_system()
	_refresh_calendar()

func _setup_ui():
	"""Initialize UI components"""
	# Setup view mode options
	view_mode_button.add_item("Month View")
	view_mode_button.add_item("Week View") 
	view_mode_button.add_item("Agenda View")
	
	# Setup filter options
	filter_button.add_item("All Tasks")
	filter_button.add_item("By Channel")
	filter_button.add_item("By Content Status")
	filter_button.add_item("By Campaign")
	filter_button.add_item("By Theme")
	filter_button.add_item("Overdue Only")
	filter_button.add_item("Due Soon")
	_rebuild_filter_values()
	
	# Setup calendar grid (7 columns for days of week)
	calendar_grid.columns = 7

func _setup_signals():
	"""Connect UI signals"""
	prev_button.pressed.connect(_on_prev_month)
	next_button.pressed.connect(_on_next_month)
	today_button.pressed.connect(_on_today_pressed)
	view_mode_button.item_selected.connect(_on_view_mode_changed)
	filter_button.item_selected.connect(_on_filter_changed)
	if filter_value_button:
		filter_value_button.item_selected.connect(_on_filter_value_changed)
	if search_edit:
		search_edit.text_changed.connect(_on_search_changed)

func set_tasks(task_list: Array[WorkplanTask]):
	"""Update the task list and refresh calendar"""
	tasks = task_list
	_rebuild_filter_values()
	_apply_filters()
	_refresh_calendar()


func matches_filters(task: WorkplanTask) -> bool:
	"""Public helper for acceptance tests and list views."""
	return _task_matches_filters(task)


func _task_matches_filters(task: WorkplanTask) -> bool:
	if task == null:
		return false
	if not search_query.is_empty():
		var hay: String = (
			"%s %s %s %s %s"
			% [task.title, task.channel, task.content_theme, task.campaign_tag, task.get_content_status()]
		).to_lower()
		if hay.find(search_query.to_lower()) < 0:
			return false
	match filter_mode:
		"all":
			return true
		"overdue":
			return task.is_overdue()
		"due_soon":
			return task.is_due_soon(7)
		"channel":
			if filter_value.is_empty() or filter_value == "(any)":
				return not task.channel.is_empty()
			return task.channel == filter_value or task.channels.has(filter_value)
		"content_status":
			task.migrate_content_status_from_notes()
			if filter_value.is_empty() or filter_value == "(any)":
				return true
			return task.get_content_status() == filter_value
		"campaign":
			if filter_value.is_empty() or filter_value == "(any)":
				return not task.campaign_tag.is_empty()
			return task.campaign_tag == filter_value
		"theme":
			if filter_value.is_empty() or filter_value == "(any)":
				return not task.content_theme.is_empty()
			return task.content_theme == filter_value
		_:
			return true


func _rebuild_filter_values() -> void:
	if filter_value_button == null:
		return
	filter_value_button.clear()
	filter_value_button.add_item("(any)")
	var values: Array[String] = []
	match filter_mode:
		"channel":
			for task in tasks:
				if not task.channel.is_empty() and not values.has(task.channel):
					values.append(task.channel)
		"content_status":
			for status_id in WorkplanTask.CONTENT_STATUSES:
				values.append(String(status_id))
		"campaign":
			for task2 in tasks:
				if not task2.campaign_tag.is_empty() and not values.has(task2.campaign_tag):
					values.append(task2.campaign_tag)
		"theme":
			for task3 in tasks:
				if not task3.content_theme.is_empty() and not values.has(task3.content_theme):
					values.append(task3.content_theme)
		_:
			filter_value_button.disabled = true
			filter_value = ""
			return
	filter_value_button.disabled = false
	for value_label in values:
		filter_value_button.add_item(value_label)
	filter_value_button.selected = 0
	filter_value = "(any)"


func _apply_filters():
	"""Apply current filter to task list"""
	filtered_tasks.clear()
	for task in tasks:
		if _task_matches_filters(task):
			filtered_tasks.append(task)

func _refresh_calendar():
	"""Refresh the entire calendar display"""
	_clear_calendar()
	
	match view_mode:
		"month":
			_draw_month_view()
		"week":
			_draw_week_view()
		"agenda":
			_draw_agenda_view()

func _clear_calendar():
	"""Clear all calendar content"""
	for child in calendar_grid.get_children():
		child.queue_free()

func _draw_month_view():
	"""Draw the monthly calendar view"""
	# Update month label
	var month_names = ["January", "February", "March", "April", "May", "June",
					   "July", "August", "September", "October", "November", "December"]
	month_label.text = "%s %d" % [month_names[current_date.month - 1], current_date.year]
	
	# Add day headers
	var day_headers = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	for header in day_headers:
		var label = Label.new()
		label.text = header
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_stylebox_override("normal", _create_header_style())
		calendar_grid.add_child(label)
	
	# Calculate first day of month and days in month
	var first_day_date = {"year": current_date.year, "month": current_date.month, "day": 1}
	var first_weekday = Time.get_datetime_dict_from_datetime_string(
		Time.get_datetime_string_from_datetime_dict(first_day_date, false), false
	).weekday
	
	var days_in_month = _get_days_in_month(current_date.month, current_date.year)
	
	# Add empty cells for days before month starts
	for i in range(first_weekday):
		var empty_cell = Control.new()
		empty_cell.custom_minimum_size = Vector2(100, 80)
		calendar_grid.add_child(empty_cell)
	
	# Add day cells
	var month_task_count := 0
	for day in range(1, days_in_month + 1):
		var day_cell = _create_day_cell(day)
		calendar_grid.add_child(day_cell)
		var day_date = "%04d-%02d-%02d" % [current_date.year, current_date.month, day]
		month_task_count += _get_tasks_for_date(day_date).size()

	_update_empty_state_banner(month_task_count)


func _update_empty_state_banner(month_task_count: int) -> void:
	"""Show a clear empty-state when this month has no scheduled tasks."""
	if _empty_state_banner != null and is_instance_valid(_empty_state_banner):
		_empty_state_banner.queue_free()
		_empty_state_banner = null
	if month_task_count > 0:
		return

	_empty_state_banner = VBoxContainer.new()
	_empty_state_banner.name = "EmptyStateBanner"
	var message := Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if filtered_tasks.is_empty() and tasks.is_empty():
		message.text = "No tasks yet. Create a task or load a workplan to see deadlines here."
	else:
		message.text = "No tasks scheduled in this month. Jump to a task date or return to today."
	_empty_state_banner.add_child(message)

	var actions := HBoxContainer.new()
	var today_btn := Button.new()
	today_btn.text = "Today"
	today_btn.pressed.connect(_on_today_pressed)
	actions.add_child(today_btn)

	var next_btn := Button.new()
	next_btn.text = "Jump to next task"
	next_btn.pressed.connect(_jump_to_next_task_month)
	var next_date: String = _find_next_task_date()
	next_btn.disabled = next_date.is_empty()
	actions.add_child(next_btn)
	_empty_state_banner.add_child(actions)

	# Prefer placing under the header if the scene has a VBox parent.
	if month_label and month_label.get_parent() and month_label.get_parent().get_parent():
		var outer: Node = month_label.get_parent().get_parent()
		outer.add_child(_empty_state_banner)
		outer.move_child(_empty_state_banner, mini(2, outer.get_child_count() - 1))
	else:
		add_child(_empty_state_banner)


func _find_next_task_date() -> String:
	"""Nearest future (or any) task display date, YYYY-MM-DD prefix."""
	var today: String = Time.get_date_string_from_system()
	var best_future: String = ""
	var best_any: String = ""
	for task in tasks:
		var task_date: String = task.get_calendar_display_date()
		if task_date.is_empty():
			continue
		var day_prefix: String = task_date.substr(0, mini(10, task_date.length()))
		if best_any.is_empty() or day_prefix < best_any:
			best_any = day_prefix
		if day_prefix >= today and (best_future.is_empty() or day_prefix < best_future):
			best_future = day_prefix
	if not best_future.is_empty():
		return best_future
	return best_any


func _jump_to_next_task_month() -> void:
	var next_date: String = _find_next_task_date()
	if next_date.is_empty() or next_date.length() < 7:
		_on_today_pressed()
		return
	var parts: PackedStringArray = next_date.split("-")
	if parts.size() < 2:
		_on_today_pressed()
		return
	current_date.year = int(parts[0])
	current_date.month = int(parts[1])
	_refresh_calendar()

func _create_day_cell(day: int) -> Control:
	"""Create a calendar day cell with tasks"""
	var cell = VBoxContainer.new()
	cell.custom_minimum_size = Vector2(100, 80)
	cell.add_theme_stylebox_override("panel", _create_day_cell_style())
	
	# Day number label
	var day_label = Label.new()
	day_label.text = str(day)
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(day_label)
	
	# Find tasks for this day
	var day_date = "%04d-%02d-%02d" % [current_date.year, current_date.month, day]
	var day_tasks = _get_tasks_for_date(day_date)
	
	# Add task indicators
	for task in day_tasks:
		if cell.get_child_count() > 4:  # Limit display to avoid overcrowding
			var more_label = Label.new()
			more_label.text = "+%d more" % (day_tasks.size() - 3)
			more_label.add_theme_font_size_override("font_size", 10)
			cell.add_child(more_label)
			break
		
		var task_indicator = _create_task_indicator(task)
		cell.add_child(task_indicator)
	
	# Make cell clickable
	var button = Button.new()
	button.flat = true
	button.custom_minimum_size = Vector2(100, 80)
	button.pressed.connect(_on_day_selected.bind(day_date, day_tasks))
	cell.add_child(button)
	
	return cell

func _create_task_indicator(task: WorkplanTask) -> Control:
	"""Create a small task indicator for calendar cells"""
	var indicator = Label.new()
	indicator.text = task.title.substr(0, 15) + ("..." if task.title.length() > 15 else "")
	task.migrate_content_status_from_notes()
	var plan_status: String = task.get_content_status()
	indicator.tooltip_text = "%s [%s]" % [task.title, plan_status]
	indicator.add_theme_font_size_override("font_size", 9)
	indicator.add_theme_color_override("font_color", Color.WHITE)
	
	# Color based on status and priority — Done never uses OVERDUE red.
	var bg_color = task.get_status_color()
	if task.status != "Done" and task.is_overdue():
		bg_color = Color.RED
	elif task.status != "Done" and task.is_due_soon():
		bg_color = Color.ORANGE
	elif plan_status == "open_slot":
		bg_color = Color(0.35, 0.35, 0.55)
	elif plan_status == "needs_approval":
		bg_color = Color(0.55, 0.4, 0.15)
	elif plan_status == "placeholder":
		bg_color = Color(0.4, 0.4, 0.4)
	
	indicator.add_theme_stylebox_override("normal", _create_colored_style(bg_color))
	return indicator

func _get_tasks_for_date(date: String) -> Array[WorkplanTask]:
	"""Get all tasks for a specific date"""
	var day_tasks: Array[WorkplanTask] = []
	
	for task in filtered_tasks:
		var task_date = task.get_calendar_display_date()
		if task_date.begins_with(date):  # Simple date matching
			day_tasks.append(task)
	
	return day_tasks

func _draw_week_view():
	"""Draw a simple 7-day week columns view with tasks."""
	calendar_grid.columns = 7
	var week_start: Dictionary = _week_start_for_current_date()
	var month_names = ["January", "February", "March", "April", "May", "June",
					   "July", "August", "September", "October", "November", "December"]
	month_label.text = "Week of %s %d, %d" % [
		month_names[int(week_start.month) - 1], int(week_start.day), int(week_start.year)
	]

	var day_headers = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	for header in day_headers:
		var label = Label.new()
		label.text = header
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_stylebox_override("normal", _create_header_style())
		calendar_grid.add_child(label)

	for offset in range(7):
		var day_unix: int = int(Time.get_unix_time_from_datetime_dict(week_start)) + (offset * 86400)
		var day_dict: Dictionary = Time.get_datetime_dict_from_unix_time(day_unix)
		var day_date: String = "%04d-%02d-%02d" % [int(day_dict.year), int(day_dict.month), int(day_dict.day)]
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(100, 120)
		cell.add_theme_stylebox_override("panel", _create_day_cell_style())
		var day_label := Label.new()
		day_label.text = "%d" % int(day_dict.day)
		day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(day_label)
		var day_tasks: Array[WorkplanTask] = _get_tasks_for_date(day_date)
		for task in day_tasks:
			if cell.get_child_count() > 5:
				var more_label := Label.new()
				more_label.text = "+%d more" % (day_tasks.size() - 4)
				more_label.add_theme_font_size_override("font_size", 10)
				cell.add_child(more_label)
				break
			cell.add_child(_create_task_indicator(task))
		calendar_grid.add_child(cell)


func _draw_agenda_view():
	"""Draw a chronological agenda list grouped by date."""
	calendar_grid.columns = 1
	month_label.text = "Agenda"

	var by_date: Dictionary = {}
	for task in filtered_tasks:
		var raw_date: String = task.get_calendar_display_date()
		if raw_date.is_empty():
			continue
		var day_prefix: String = raw_date.substr(0, mini(10, raw_date.length()))
		if not by_date.has(day_prefix):
			by_date[day_prefix] = []
		(by_date[day_prefix] as Array).append(task)

	var dates: Array = by_date.keys()
	dates.sort()
	if dates.is_empty():
		var empty := Label.new()
		empty.text = "No upcoming tasks in the agenda."
		calendar_grid.add_child(empty)
		return

	var today: String = Time.get_date_string_from_system()
	for date_any in dates:
		var date_key: String = String(date_any)
		if date_key < today:
			continue
		var header := Label.new()
		header.text = date_key
		header.add_theme_font_size_override("font_size", 14)
		calendar_grid.add_child(header)
		for task_any in by_date[date_key]:
			var task: WorkplanTask = task_any as WorkplanTask
			if task == null:
				continue
			var row := Label.new()
			row.text = "• %s (%s)" % [task.title, task.status]
			calendar_grid.add_child(row)


func _week_start_for_current_date() -> Dictionary:
	"""Return Sunday-starting week dict for current_date."""
	var as_date := {
		"year": int(current_date.year),
		"month": int(current_date.month),
		"day": int(current_date.day),
		"hour": 0,
		"minute": 0,
		"second": 0,
	}
	var unix: int = int(Time.get_unix_time_from_datetime_dict(as_date))
	var weekday: int = int(Time.get_datetime_dict_from_unix_time(unix).weekday)  # 0=Sunday
	var start_unix: int = unix - (weekday * 86400)
	return Time.get_datetime_dict_from_unix_time(start_unix)

func _get_days_in_month(month: int, year: int) -> int:
	"""Get number of days in a specific month"""
	var days_in_months = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	
	# Check for leap year
	if month == 2 and _is_leap_year(year):
		return 29
	
	return days_in_months[month - 1]

func _is_leap_year(year: int) -> bool:
	"""Check if year is a leap year"""
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)

func _create_header_style() -> StyleBox:
	"""Create style for day headers"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.3, 0.3)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color.GRAY
	return style

func _create_day_cell_style() -> StyleBox:
	"""Create style for day cells"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color.GRAY
	return style

func _create_colored_style(color: Color) -> StyleBox:
	"""Create colored style for task indicators"""
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style

# Signal handlers
func _on_prev_month():
	"""Navigate to previous month"""
	current_date.month -= 1
	if current_date.month < 1:
		current_date.month = 12
		current_date.year -= 1
	_refresh_calendar()

func _on_next_month():
	"""Navigate to next month"""
	current_date.month += 1
	if current_date.month > 12:
		current_date.month = 1
		current_date.year += 1
	_refresh_calendar()

func _on_today_pressed():
	"""Navigate to current month"""
	current_date = Time.get_datetime_dict_from_system()
	_refresh_calendar()

func _on_view_mode_changed(index: int):
	"""Handle view mode change"""
	match index:
		0: view_mode = "month"
		1: view_mode = "week"
		2: view_mode = "agenda"
	_refresh_calendar()

func _on_filter_changed(index: int):
	"""Handle filter change"""
	match index:
		0: filter_mode = "all"
		1: filter_mode = "channel"
		2: filter_mode = "content_status"
		3: filter_mode = "campaign"
		4: filter_mode = "theme"
		5: filter_mode = "overdue"
		6: filter_mode = "due_soon"
		_: filter_mode = "all"
	_rebuild_filter_values()
	_apply_filters()
	_refresh_calendar()


func _on_filter_value_changed(index: int) -> void:
	if filter_value_button == null or index < 0:
		filter_value = ""
	else:
		filter_value = filter_value_button.get_item_text(index)
	_apply_filters()
	_refresh_calendar()


func _on_search_changed(new_text: String) -> void:
	search_query = new_text.strip_edges()
	_apply_filters()
	_refresh_calendar()

func _on_day_selected(date: String, day_tasks: Array[WorkplanTask]):
	"""Handle day cell selection"""
	date_selected.emit(date)
	if day_tasks.size() > 0:
		_show_task_details(day_tasks)

func _show_task_details(day_tasks: Array[WorkplanTask]):
	"""Show task details panel"""
	# Clear existing details
	for child in task_details.get_children():
		child.queue_free()
	
	var title = Label.new()
	title.text = "Tasks for Selected Day (%d)" % day_tasks.size()
	title.add_theme_font_size_override("font_size", 14)
	task_details.add_child(title)
	
	for task in day_tasks:
		var task_item = _create_task_detail_item(task)
		task_details.add_child(task_item)

func _create_task_detail_item(task: WorkplanTask) -> Control:
	"""Create detailed task item for side panel"""
	var item = VBoxContainer.new()
	
	var title = Label.new()
	title.text = task.title
	title.add_theme_font_size_override("font_size", 12)
	item.add_child(title)
	
	task.migrate_content_status_from_notes()
	var details = Label.new()
	details.text = "%s | %s | %s | plan:%s" % [
		task.format, task.channel, task.status, task.get_content_status()
	]
	details.add_theme_font_size_override("font_size", 10)
	details.add_theme_color_override("font_color", Color.GRAY)
	item.add_child(details)
	
	if task.is_overdue():
		var overdue = Label.new()
		overdue.text = "⚠ OVERDUE"
		overdue.add_theme_color_override("font_color", Color.RED)
		item.add_child(overdue)
	
	# Add click handler
	var button = Button.new()
	button.text = "Edit Task"
	button.pressed.connect(_on_task_selected.bind(task))
	item.add_child(button)
	
	return item

func _on_task_selected(task: WorkplanTask):
	"""Handle task selection"""
	task_selected.emit(task) 
 
