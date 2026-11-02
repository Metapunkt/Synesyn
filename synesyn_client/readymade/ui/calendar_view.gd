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
@onready var calendar_grid: GridContainer = $VBox/CalendarContainer/CalendarGrid
@onready var task_details: VBoxContainer = $VBox/TaskDetails

var current_date: Dictionary
var tasks: Array[WorkplanTask] = []
var filtered_tasks: Array[WorkplanTask] = []
var view_mode: String = "month"  # month, week, agenda
var filter_mode: String = "all"  # all, channel, status, priority, overdue

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
	filter_button.add_item("By Status")
	filter_button.add_item("Overdue Only")
	filter_button.add_item("Due Soon")
	
	# Setup calendar grid (7 columns for days of week)
	calendar_grid.columns = 7

func _setup_signals():
	"""Connect UI signals"""
	prev_button.pressed.connect(_on_prev_month)
	next_button.pressed.connect(_on_next_month)
	today_button.pressed.connect(_on_today_pressed)
	view_mode_button.item_selected.connect(_on_view_mode_changed)
	filter_button.item_selected.connect(_on_filter_changed)

func set_tasks(task_list: Array[WorkplanTask]):
	"""Update the task list and refresh calendar"""
	tasks = task_list
	_apply_filters()
	_refresh_calendar()

func _apply_filters():
	"""Apply current filter to task list"""
	filtered_tasks.clear()
	
	for task in tasks:
		var include_task = false
		
		match filter_mode:
			"all":
				include_task = true
			"overdue":
				include_task = task.is_overdue()
			"due_soon":
				include_task = task.is_due_soon(7)  # Due within a week
			"channel":
				# TODO: Add channel filter UI
				include_task = true
			"status":
				# TODO: Add status filter UI  
				include_task = true
		
		if include_task:
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
	for day in range(1, days_in_month + 1):
		var day_cell = _create_day_cell(day)
		calendar_grid.add_child(day_cell)

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
	indicator.add_theme_font_size_override("font_size", 9)
	indicator.add_theme_color_override("font_color", Color.WHITE)
	
	# Color based on status and priority
	var bg_color = task.get_status_color()
	if task.is_overdue():
		bg_color = Color.RED
	elif task.is_due_soon():
		bg_color = Color.ORANGE
	
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
	"""Draw the weekly calendar view"""
	# TODO: Implement week view
	month_label.text = "Week View - Coming Soon"

func _draw_agenda_view():
	"""Draw the agenda/list view"""
	# TODO: Implement agenda view
	month_label.text = "Agenda View - Coming Soon"

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
		2: filter_mode = "status"
		3: filter_mode = "overdue"
		4: filter_mode = "due_soon"
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
	
	var details = Label.new()
	details.text = "%s | %s | %s" % [task.format, task.channel, task.status]
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
 
