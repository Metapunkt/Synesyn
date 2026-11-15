extends "res://readymade/ui/internal/mission_control_task_list_base.gd"
class_name MissionControlCalendarBase

const WorkplanDependenciesScript = preload("res://readymade/scripts/workplan_dependencies.gd")
const DayCardsScript = preload("res://readymade/scripts/workplan_calendar_day_cards.gd")

var _calendar_empty_banner: Control = null

func _update_calendar():
	"""Update calendar with current tasks"""
	if not calendar_grid or calendar_day_cells.size() == 0:
		return
	
	# Only update if calendar is properly initialized
	if current_calendar_year > 0 and current_calendar_month > 0:
		# Check if tasks have changed since last calendar update
		var workplan_obj = ReadyMadeOrchestrator.workplan if ReadyMadeOrchestrator else null
		if not workplan_obj:
			return
			
		var current_task_count = workplan_obj.get_total_tasks()
		if calendar_last_task_count != current_task_count:
			print("Calendar: Task count changed from %d to %d, refreshing calendar" % [calendar_last_task_count, current_task_count])
			calendar_last_task_count = current_task_count
			_populate_calendar_with_tasks()
		# If task count is the same, don't repopulate to avoid clearing existing cards

# Calendar functionality
func _setup_calendar():
	"""Initialize the calendar view"""
	# Set current month and year
	var current_date = Time.get_datetime_dict_from_system()
	current_calendar_year = current_date.year
	current_calendar_month = current_date.month
	
	# Setup month and year selectors
	_setup_month_year_selectors()
	_setup_calendar_view_mode_selector()
	_maybe_show_calendar_drag_hint()
	
	# Build the calendar grid
	_build_calendar_grid()

func _setup_calendar_view_mode_selector() -> void:
	"""Add Month/Week/Agenda switcher beside calendar navigation."""
	if calendar_view_mode_button != null and is_instance_valid(calendar_view_mode_button):
		return
	if today_btn == null or today_btn.get_parent() == null:
		return
	calendar_view_mode_button = OptionButton.new()
	calendar_view_mode_button.name = "CalendarViewModeButton"
	calendar_view_mode_button.tooltip_text = "Switch calendar view"
	calendar_view_mode_button.add_item("Month")
	calendar_view_mode_button.add_item("Week")
	calendar_view_mode_button.add_item("Agenda")
	calendar_view_mode_button.selected = 0
	calendar_view_mode_button.item_selected.connect(_on_calendar_view_mode_selected)
	today_btn.get_parent().add_child(calendar_view_mode_button)
	today_btn.get_parent().move_child(calendar_view_mode_button, today_btn.get_index() + 1)

func _on_calendar_view_mode_selected(index: int) -> void:
	match index:
		1:
			calendar_view_mode = "week"
		2:
			calendar_view_mode = "agenda"
		_:
			calendar_view_mode = "month"
	calendar_last_task_count = -1
	_build_calendar_grid()

func _maybe_show_calendar_drag_hint() -> void:
	"""One-time dismissible tip that calendar cards can be dragged between days."""
	if _is_calendar_drag_hint_dismissed():
		return
	if calendar_drag_hint_banner != null and is_instance_valid(calendar_drag_hint_banner):
		return
	var header: Node = null
	if today_btn:
		header = today_btn.get_parent()
		if header:
			header = header.get_parent()
	if header == null:
		return
	calendar_drag_hint_banner = HBoxContainer.new()
	calendar_drag_hint_banner.name = "CalendarDragHintBanner"
	var tip := Label.new()
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.text = "Tip: drag a task card onto another day to reschedule it."
	calendar_drag_hint_banner.add_child(tip)
	var dismiss := Button.new()
	dismiss.text = "Got it"
	dismiss.pressed.connect(_on_calendar_drag_hint_dismissed)
	calendar_drag_hint_banner.add_child(dismiss)
	header.add_child(calendar_drag_hint_banner)

func _is_calendar_drag_hint_dismissed() -> bool:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	if typeof(apps_any) != TYPE_DICTIONARY:
		return false
	var readymade_any: Variant = (apps_any as Dictionary).get("readymade", {})
	if typeof(readymade_any) != TYPE_DICTIONARY:
		return false
	return bool((readymade_any as Dictionary).get("calendar_drag_hint_dismissed", false))

func _on_calendar_drag_hint_dismissed() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	if not cfg.has("apps") or typeof(cfg["apps"]) != TYPE_DICTIONARY:
		cfg["apps"] = {}
	var apps: Dictionary = cfg["apps"]
	if not apps.has("readymade") or typeof(apps["readymade"]) != TYPE_DICTIONARY:
		apps["readymade"] = {}
	(apps["readymade"] as Dictionary)["calendar_drag_hint_dismissed"] = true
	RuntimeConfig.save_config(cfg)
	if calendar_drag_hint_banner and is_instance_valid(calendar_drag_hint_banner):
		calendar_drag_hint_banner.queue_free()
		calendar_drag_hint_banner = null

func _setup_month_year_selectors():
	"""Setup month and year dropdown options"""
	if month_selector:
		month_selector.clear()
		var months = ["January", "February", "March", "April", "May", "June",
					  "July", "August", "September", "October", "November", "December"]
		for i in range(months.size()):
			month_selector.add_item(months[i])
		month_selector.selected = current_calendar_month - 1
	
	if year_selector:
		year_selector.clear()
		# Add years from 2020 to 2030
		for year in range(2020, 2031):
			year_selector.add_item(str(year))
		# Select current year
		var year_index = current_calendar_year - 2020
		if year_index >= 0 and year_index < year_selector.get_item_count():
			year_selector.selected = year_index

func _build_calendar_grid():
	"""Build the calendar grid with day cells"""
	if has_method("_ensure_left_sidebar_split"):
		call("_ensure_left_sidebar_split")
	if not calendar_grid:
		return
	# Clear existing calendar
	for child in calendar_grid.get_children():
		child.queue_free()
	calendar_day_cells.clear()

	if calendar_view_mode == "week":
		_build_week_calendar_grid()
		return
	if calendar_view_mode == "agenda":
		_build_agenda_calendar_grid()
		return
	
	calendar_grid.columns = 7
	# Add day headers
	var day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	for day_name in day_names:
		var header = Label.new()
		header.text = day_name
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_theme_color_override("font_color", Color.GRAY)
		header.add_theme_font_size_override("font_size", 12)
		calendar_grid.add_child(header)
	
	# Calculate calendar layout
	var first_day_of_month = Time.get_datetime_dict_from_datetime_string("%04d-%02d-01" % [current_calendar_year, current_calendar_month], false)
	var first_unix_time = Time.get_unix_time_from_datetime_dict(first_day_of_month)
	var first_weekday = Time.get_datetime_dict_from_unix_time(first_unix_time).weekday
	var days_in_month = _get_days_in_month(current_calendar_year, current_calendar_month)
	print("Calendar: Month %d-%d has %d days, first weekday: %d" % [current_calendar_year, current_calendar_month, days_in_month, first_weekday])
	
	# Add empty cells for days before the first day of the month
	for i in range(first_weekday):
		var empty_cell = Control.new()
		# Keep mins low so 7 weekday columns fit at 1152x648 without horizontal scroll.
		empty_cell.custom_minimum_size = Vector2(48, 72)
		empty_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		calendar_grid.add_child(empty_cell)
	
	# Add day cells
	for day in range(1, days_in_month + 1):
		var day_cell = _create_day_cell(day)
		calendar_grid.add_child(day_cell)
		calendar_day_cells.append(day_cell)
	
	print("Calendar: Built calendar with %d day cells for %d-%d" % [calendar_day_cells.size(), current_calendar_year, current_calendar_month])
	
	# Populate with tasks after a short delay to ensure nodes are in scene tree
	call_deferred("_populate_calendar_with_tasks")

func _build_week_calendar_grid() -> void:
	"""Seven day columns for the week containing the currently selected month/day context."""
	calendar_grid.columns = 7
	var day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	for day_name in day_names:
		var header = Label.new()
		header.text = day_name
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_theme_color_override("font_color", Color.GRAY)
		header.add_theme_font_size_override("font_size", 12)
		calendar_grid.add_child(header)

	var today: Dictionary = Time.get_datetime_dict_from_system()
	var anchor_day: int = int(today.day)
	if current_calendar_year != int(today.year) or current_calendar_month != int(today.month):
		anchor_day = 1
	var anchor := {
		"year": current_calendar_year,
		"month": current_calendar_month,
		"day": anchor_day,
		"hour": 0,
		"minute": 0,
		"second": 0,
	}
	var anchor_unix: int = int(Time.get_unix_time_from_datetime_dict(anchor))
	var weekday: int = int(Time.get_datetime_dict_from_unix_time(anchor_unix).weekday)
	var week_start_unix: int = anchor_unix - (weekday * 86400)
	for offset in range(7):
		var day_unix: int = week_start_unix + (offset * 86400)
		var day_dict: Dictionary = Time.get_datetime_dict_from_unix_time(day_unix)
		var day_num: int = int(day_dict.day)
		# Reuse month cell renderer when the day belongs to the visible month.
		if int(day_dict.year) == current_calendar_year and int(day_dict.month) == current_calendar_month:
			var day_cell: Control = _create_day_cell(day_num)
			calendar_grid.add_child(day_cell)
			calendar_day_cells.append(day_cell)
		else:
			var filler := PanelContainer.new()
			filler.custom_minimum_size = Vector2(48, 72)
			filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var lbl := Label.new()
			lbl.text = str(day_num)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_color_override("font_color", Color.GRAY)
			filler.add_child(lbl)
			calendar_grid.add_child(filler)
	call_deferred("_populate_calendar_with_tasks")

func _build_agenda_calendar_grid() -> void:
	"""Chronological upcoming-task list grouped by date."""
	calendar_grid.columns = 1
	var workplan_obj = ReadyMadeOrchestrator.workplan if ReadyMadeOrchestrator else null
	var all_tasks: Array = workplan_obj.get_all_tasks() if workplan_obj else []
	var by_date: Dictionary = {}
	for task_any in all_tasks:
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		var raw_date: String = task.get_calendar_display_date()
		if raw_date.is_empty():
			continue
		var day_prefix: String = raw_date.substr(0, mini(10, raw_date.length()))
		if not by_date.has(day_prefix):
			by_date[day_prefix] = []
		(by_date[day_prefix] as Array).append(task)
	var dates: Array = by_date.keys()
	dates.sort()
	var today: String = Time.get_date_string_from_system()
	var shown := 0
	for date_any in dates:
		var date_key: String = String(date_any)
		if date_key < today:
			continue
		var header := Label.new()
		header.text = date_key
		header.add_theme_font_size_override("font_size", 14)
		calendar_grid.add_child(header)
		for task_any2 in by_date[date_key]:
			var agenda_task: WorkplanTask = task_any2 as WorkplanTask
			if agenda_task == null:
				continue
			var row := Label.new()
			row.text = "• %s (%s)" % [agenda_task.title, agenda_task.status]
			calendar_grid.add_child(row)
			shown += 1
	if shown == 0:
		var empty := Label.new()
		empty.text = "No upcoming tasks in the agenda."
		calendar_grid.add_child(empty)

func _create_day_cell(day: int) -> Control:
	"""Create a day cell for the calendar"""
	var cell = PanelContainer.new()
	cell.name = "DayCell_%d" % day
	# Allow horizontal shrink so a 7-column month grid does not crush the left sidebar.
	cell.custom_minimum_size = Vector2(48, 72)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Add drop functionality feedback (drop logic is handled in global _input)
	cell.mouse_entered.connect(_on_day_cell_mouse_entered.bind(day))
	cell.mouse_exited.connect(_on_day_cell_mouse_exited.bind(day))
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"  # Explicitly set the name
	cell.add_child(vbox)
	
	# Day number header
	var day_label = Label.new()
	day_label.text = str(day)
	day_label.name = "DayLabel"
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_label.add_theme_font_size_override("font_size", 14)
	
	# Highlight today
	var current_date = Time.get_datetime_dict_from_system()
	if current_date.year == current_calendar_year and current_date.month == current_calendar_month and current_date.day == day:
		day_label.add_theme_color_override("font_color", Color.CYAN)
		cell.modulate = Color(1.2, 1.2, 1.0)  # Slight yellow tint
	
	vbox.add_child(day_label)
	
	# Clip overflow inside the cell — avoid nested scrollbars that force outer scroll.
	var scroll_container = ScrollContainer.new()
	scroll_container.name = "ScrollContainer" # Explicitly set the name
	scroll_container.mouse_filter = MOUSE_FILTER_PASS # CRUCIAL: Allow clicks to pass through to content
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll_container)

	# Task container now goes inside the ScrollContainer
	var task_container = VBoxContainer.new()
	task_container.name = "TaskContainer"
	task_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(task_container)
	
	return cell

func _populate_calendar_with_tasks():
	"""(REFACTORED) Groups tasks by day, then populates the calendar in a single pass."""
	var workplan_obj = ReadyMadeOrchestrator.workplan if ReadyMadeOrchestrator else null
	if not workplan_obj:
		print("Calendar: No workplan available for population.")
		return
	
	# Step 1: Group all relevant task events (start/deadline) by day
	var tasks_by_day: Dictionary = {}
	var all_tasks = workplan_obj.get_all_tasks()
	
	for task in all_tasks:
		# Check start date
		if not task.start_date.is_empty():
			var start_date = _parse_date_string(task.start_date)
			if start_date.year == current_calendar_year and start_date.month == current_calendar_month:
				var day = start_date.day
				if not tasks_by_day.has(day): tasks_by_day[day] = []
				tasks_by_day[day].append({"task": task, "type": "start"})
		
		# Check deadline
		if not task.deadline.is_empty():
			var deadline_date = _parse_date_string(task.deadline)
			if deadline_date.year == current_calendar_year and deadline_date.month == current_calendar_month:
				var day = deadline_date.day
				if not tasks_by_day.has(day): tasks_by_day[day] = []
				tasks_by_day[day].append({"task": task, "type": "deadline"})

		# Publish date (content-plan scheduling)
		if not task.publish_date.is_empty():
			var publish_date = _parse_date_string(task.publish_date)
			if publish_date.year == current_calendar_year and publish_date.month == current_calendar_month:
				var pub_day = publish_date.day
				if not tasks_by_day.has(pub_day):
					tasks_by_day[pub_day] = []
				tasks_by_day[pub_day].append({"task": task, "type": "publish"})

	# Store for later use by popups
	calendar_tasks_by_day = tasks_by_day

	# Step 2: Clear all existing cards from the UI
	for cell in calendar_day_cells:
		var task_container = _get_task_container_from_cell(cell)
		if task_container:
			for child in task_container.get_children():
				child.queue_free()

	# Step 3: Render the new state deterministically
	for day in tasks_by_day.keys():
		var cell_index = day - 1
		if cell_index < 0 or cell_index >= calendar_day_cells.size():
			continue
			
		var cell = calendar_day_cells[cell_index]
		var task_container = _get_task_container_from_cell(cell)
		if not task_container:
			continue
		
		var tasks_for_day: Array = DayCardsScript.merge_day_task_events(tasks_by_day[day])
		tasks_by_day[day] = tasks_for_day
		
		# Render visible task cards (merged same-task / same-day kinds)
		for i in range(mini(tasks_for_day.size(), max_cards_per_day)):
			var task_event: Dictionary = tasks_for_day[i]
			var kinds: Array = task_event.get("types", [task_event.get("type", "deadline")])
			var card = _create_calendar_task_card(
				task_event.task,
				String(task_event.get("type", "deadline")),
				kinds,
				day
			)
			task_container.add_child(card)
			
		# Render overflow indicator if necessary
		if tasks_for_day.size() > max_cards_per_day:
			var hidden_count = tasks_for_day.size() - max_cards_per_day
			var expand_indicator = Label.new()
			expand_indicator.name = "ExpandIndicator"
			expand_indicator.text = "📋 +%d more" % hidden_count
			expand_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			expand_indicator.add_theme_color_override("font_color", Color.YELLOW)
			expand_indicator.add_theme_font_size_override("font_size", 10)
			expand_indicator.mouse_filter = MOUSE_FILTER_PASS
			expand_indicator.gui_input.connect(func(event): _on_expand_indicator_clicked(event, day))
			task_container.add_child(expand_indicator)

	_update_calendar_empty_state(tasks_by_day.size(), all_tasks.size())

func _update_calendar_empty_state(days_with_tasks: int, total_tasks: int) -> void:
	"""Visible empty-state when the open month has no cards."""
	if _calendar_empty_banner != null and is_instance_valid(_calendar_empty_banner):
		_calendar_empty_banner.queue_free()
		_calendar_empty_banner = null
	if days_with_tasks > 0 or calendar_grid == null:
		return

	var banner := VBoxContainer.new()
	banner.name = "CalendarEmptyState"
	var message := Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if total_tasks == 0:
		message.text = "No tasks yet. Use New Task or Manage Workplans to get started."
	else:
		message.text = "No tasks in this month. Jump to the next scheduled task or return to Today."
	banner.add_child(message)

	var row := HBoxContainer.new()
	var today_btn := Button.new()
	today_btn.text = "Today"
	today_btn.pressed.connect(_on_today_pressed)
	row.add_child(today_btn)

	var jump_btn := Button.new()
	jump_btn.text = "Jump to next task"
	jump_btn.pressed.connect(_jump_calendar_to_next_task)
	jump_btn.disabled = total_tasks == 0
	row.add_child(jump_btn)
	banner.add_child(row)

	var host: Node = _calendar_banner_host()
	if host:
		host.add_child(banner)
		# Own row above the scroll/grid — never a ScrollContainer sibling of CalendarGrid.
		var scroll: Node = calendar_grid.get_parent() if calendar_grid else null
		if scroll != null and scroll.get_parent() == host:
			host.move_child(banner, scroll.get_index())
		else:
			host.move_child(banner, 0)
	_calendar_empty_banner = banner

func _jump_calendar_to_next_task() -> void:
	var workplan_obj = ReadyMadeOrchestrator.workplan if ReadyMadeOrchestrator else null
	if workplan_obj == null:
		_on_today_pressed()
		return
	var today: String = Time.get_date_string_from_system()
	var best_future: String = ""
	var best_any: String = ""
	for task_any in workplan_obj.get_all_tasks():
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		for candidate in [task.scheduled_date, task.deadline, task.start_date]:
			var date_str: String = String(candidate).substr(0, mini(10, String(candidate).length()))
			if date_str.length() < 7:
				continue
			if best_any.is_empty() or date_str < best_any:
				best_any = date_str
			if date_str >= today and (best_future.is_empty() or date_str < best_future):
				best_future = date_str
	var target: String = best_future if not best_future.is_empty() else best_any
	if target.is_empty():
		_on_today_pressed()
		return
	var parts: PackedStringArray = target.split("-")
	if parts.size() < 2:
		_on_today_pressed()
		return
	current_calendar_year = int(parts[0])
	current_calendar_month = int(parts[1])
	_setup_month_year_selectors()
	_build_calendar_grid()

func _on_expand_indicator_clicked(event: InputEvent, day: int):
	"""Handle clicks on the '+X more' label."""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_show_day_overflow_popup(day)

func _show_day_overflow_popup(day: int):
	"""Populates and displays the popup with all tasks for a given day."""
	if not calendar_tasks_by_day.has(day):
		return

	# Clear previous content
	for child in overflow_tasks_container.get_children():
		child.queue_free()

	# Set popup title
	var month_name = month_selector.get_item_text(current_calendar_month - 1)
	day_overflow_popup.title = "All Tasks for %s %d" % [month_name, day]

	# Populate with full task cards
	var tasks_for_day = calendar_tasks_by_day[day]
	for task_event in tasks_for_day:
		# Use a popup-specific task card that doesn't auto-add to containers
		var card = _create_popup_task_card(task_event.task)
		overflow_tasks_container.add_child(card)

	# Position and show the popup
	var cell = calendar_day_cells[day - 1]
	var popup_pos = cell.get_global_rect().end + Vector2(5, 0)
	day_overflow_popup.position = popup_pos
	day_overflow_popup.popup()

func _create_popup_task_card(task: WorkplanTask) -> Control:
	"""Create a task card for popup display (doesn't auto-add to containers)"""
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 120)
	
	var vbox = VBoxContainer.new()
	card.add_child(vbox)
	
	# Header with title and status
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var title_label = Label.new()
	title_label.text = task.title
	title_label.theme_type_variation = "HeaderSmall"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title_label)
	
	var status_label = Label.new()
	status_label.text = task.status
	status_label.modulate = task.get_status_color()
	header.add_child(status_label)
	
	# Details
	var details = Label.new()
	var format_text = task.format if not task.format.is_empty() else "Not specified"
	var channel_text = task.channel if not task.channel.is_empty() else "Not specified"
	details.text = "📹 %s | 📱 %s | ⚡ Priority %d" % [format_text, channel_text, task.priority]
	details.modulate = Color.GRAY
	vbox.add_child(details)
	
	# Progress info
	if not task.deliverable_path.is_empty():
		var file_info = Label.new()
		file_info.text = "📄 " + task.deliverable_path.get_file()
		file_info.modulate = Color.GREEN
		vbox.add_child(file_info)
	
	# Deadline info — Done tasks never use red OVERDUE styling.
	if not task.deadline.is_empty() or task.status == "Done":
		var deadline_info = Label.new()
		_apply_deadline_label(deadline_info, task)
		vbox.add_child(deadline_info)
	
	# Action buttons
	var buttons = HBoxContainer.new()
	vbox.add_child(buttons)
	
	# Edit button
	var edit_btn = Button.new()
	edit_btn.text = "✏️ Edit"
	edit_btn.pressed.connect(_on_edit_task_pressed.bind(task))
	buttons.add_child(edit_btn)
	
	# Status-specific buttons
	match task.status:
		"To Do":
			var start_btn = Button.new()
			start_btn.text = "▶️ Start"
			start_btn.pressed.connect(_on_start_task_pressed.bind(task))
			buttons.add_child(start_btn)
		
		"In Progress":
			var review_btn = Button.new()
			review_btn.text = "👁️ Review"
			review_btn.pressed.connect(_on_review_task_pressed.bind(task))
			buttons.add_child(review_btn)
		
		"Review":
			var complete_btn = Button.new()
			complete_btn.text = "✅ Complete"
			complete_btn.pressed.connect(_on_complete_task_pressed.bind(task))
			buttons.add_child(complete_btn)
		
		"Done":
			var rerun_btn = Button.new()
			rerun_btn.text = "🔄 Rerun"
			rerun_btn.pressed.connect(_on_rerun_task_pressed.bind(task))
			buttons.add_child(rerun_btn)
	
	# Delete button
	var delete_btn = Button.new()
	delete_btn.text = "🗑️ Delete"
	delete_btn.add_theme_color_override("font_color", Color.RED)
	delete_btn.pressed.connect(_on_delete_task_pressed.bind(task))
	buttons.add_child(delete_btn)
	
	# Note: Unlike _create_task_card, this doesn't auto-add to tasks_container
	return card

# Calendar navigation handlers
func _on_prev_month_pressed():
	"""Navigate to previous month"""
	current_calendar_month -= 1
	if current_calendar_month < 1:
		current_calendar_month = 12
		current_calendar_year -= 1
	
	_setup_month_year_selectors()
	_build_calendar_grid()

func _on_next_month_pressed():
	"""Navigate to next month"""
	current_calendar_month += 1
	if current_calendar_month > 12:
		current_calendar_month = 1
		current_calendar_year += 1
	
	_setup_month_year_selectors()
	_build_calendar_grid()

func _on_month_selected(index: int):
	"""Handle month selection"""
	current_calendar_month = index + 1
	_build_calendar_grid()

func _on_year_selected(index: int):
	"""Handle year selection"""
	current_calendar_year = 2020 + index
	_build_calendar_grid()

func _on_today_pressed():
	"""Navigate to current month"""
	var current_date = Time.get_datetime_dict_from_system()
	current_calendar_year = current_date.year
	current_calendar_month = current_date.month
	_setup_month_year_selectors()
	_build_calendar_grid()

func _clear_pending_calendar_drag() -> void:
	_pending_drag_task = null
	_pending_drag_card = null
	_pending_drag_date_type = ""
	_pending_drag_pos = Vector2.ZERO

func _on_task_card_input(card: Control, task: WorkplanTask, date_type: String, event: InputEvent):
	"""Right-click menu, double-click edit; drag only after move threshold."""
	if event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event
		if mouse_btn.button_index == MOUSE_BUTTON_RIGHT and mouse_btn.pressed:
			_clear_pending_calendar_drag()
			_show_task_context_menu(task, date_type)
			get_viewport().set_input_as_handled()
			return
		if mouse_btn.button_index == MOUSE_BUTTON_LEFT and mouse_btn.pressed:
			if mouse_btn.double_click:
				_clear_pending_calendar_drag()
				if dragging_task != null:
					_stop_drag()
				_on_edit_task_pressed(task)
			else:
				_pending_drag_task = task
				_pending_drag_card = card
				_pending_drag_date_type = date_type
				_pending_drag_pos = mouse_btn.position
			get_viewport().set_input_as_handled()
			return
		if mouse_btn.button_index == MOUSE_BUTTON_LEFT and not mouse_btn.pressed:
			_clear_pending_calendar_drag()
			return
	elif event is InputEventMouseMotion and _pending_drag_task != null:
		var motion: InputEventMouseMotion = event
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) and motion.position.distance_to(_pending_drag_pos) >= _CALENDAR_DRAG_THRESHOLD_PX:
			var drag_task: WorkplanTask = _pending_drag_task
			var drag_card: Control = _pending_drag_card
			var drag_type: String = _pending_drag_date_type
			_clear_pending_calendar_drag()
			_start_drag(drag_task, drag_type, drag_card)
			get_viewport().set_input_as_handled()

func _on_day_cell_mouse_entered(day: int):
	if dragging_task == null:
		return
	var cell_index = day - 1
	if cell_index >= 0 and cell_index < calendar_day_cells.size():
		var cell = calendar_day_cells[cell_index]
		if cell and is_instance_valid(cell):
			cell.modulate = Color(1.3, 1.3, 1.0)

func _on_day_cell_mouse_exited(day: int):
	if dragging_task == null:
		return
	var cell_index = day - 1
	if cell_index >= 0 and cell_index < calendar_day_cells.size():
		var cell = calendar_day_cells[cell_index]
		if cell and is_instance_valid(cell):
			cell.modulate = Color(1.1, 1.1, 1.0)

func _dismiss_calendar_context_menu() -> void:
	"""Hide then free the calendar PopupMenu on this frame (before Undo/rebuild)."""
	if calendar_context_menu == null or not is_instance_valid(calendar_context_menu):
		calendar_context_menu = null
		return
	var menu: PopupMenu = calendar_context_menu
	calendar_context_menu = null
	var status_submenu = menu.get_node_or_null("StatusSubmenu")
	if status_submenu is PopupMenu:
		(status_submenu as PopupMenu).hide()
		(status_submenu as PopupMenu).visible = false
	# Hide synchronously so the menu is gone before calendar rebuild paints.
	menu.hide()
	menu.visible = false
	if menu.get_parent() != null:
		menu.get_parent().remove_child(menu)
	# queue_free after hide/remove; free() is unsafe while id_pressed is still unwinding.
	menu.queue_free()

func _ensure_calendar_context_menu() -> PopupMenu:
	_dismiss_calendar_context_menu()
	var menu := PopupMenu.new()
	menu.name = "CalendarContextMenu"
	# PopupMenu is a Window in Godot 4 — never assign Control.top_level (4.7+ errors).
	menu.hide_on_item_selection = true
	menu.hide_on_checkable_item_selection = true
	menu.hide_on_state_item_selection = true
	add_child(menu)
	menu.id_pressed.connect(_on_calendar_context_menu_id_pressed)
	calendar_context_menu = menu
	return menu

func _show_task_context_menu(task: WorkplanTask, _date_type: String):
	context_menu_task = task
	var menu: PopupMenu = _ensure_calendar_context_menu()
	if menu == null:
		return
	menu.add_item("Edit Task", 0)
	var status_submenu := PopupMenu.new()
	status_submenu.name = "StatusSubmenu"
	menu.add_child(status_submenu)
	status_submenu.id_pressed.connect(func(id): _on_calendar_context_menu_id_pressed(100 + id))
	var statuses = ["To Do", "In Progress", "Review", "Done"]
	for i in statuses.size():
		status_submenu.add_item(statuses[i], i)
	menu.add_submenu_item("Change Status", "StatusSubmenu")
	menu.add_separator()
	menu.add_item("Move to date…", 3)
	menu.add_item(
		"Reschedule series (title+channel)" if calendar_series_mode != "series" else "Reschedule instance only",
		4
	)
	menu.add_item("Undo last reschedule", 5)
	menu.add_item("Copy as Markdown", 6)
	menu.add_separator()
	menu.add_item("Delete Task", 2)
	menu.position = Vector2i(get_viewport().get_mouse_position())
	menu.popup()  # bare popup auto-sizes (zero-size rect collapses Window)

func _on_calendar_context_menu_id_pressed(id: int):
	"""Hide/free menu first (same frame), then run the action including Undo rebuild."""
	var task: WorkplanTask = context_menu_task
	context_menu_task = null
	_dismiss_calendar_context_menu()
	if task == null and id != 5:
		return
	_run_calendar_context_action(id, task)

func _run_calendar_context_action(id: int, task: WorkplanTask) -> void:
	if id == 0: # Edit Task
		_on_edit_task_pressed(task)
	elif id == 2: # Delete Task
		_on_delete_task_pressed(task)
	elif id == 3:
		_prompt_move_task_to_date(task)
	elif id == 4:
		calendar_series_mode = "instance" if calendar_series_mode == "series" else "series"
		print("Calendar: series mode → ", calendar_series_mode)
	elif id == 5:
		_undo_calendar_reschedule()
	elif id == 6:
		_on_copy_task_markdown_pressed(task, null)
	elif id >= 100: # Change Status
		var statuses = ["To Do", "In Progress", "Review", "Done"]
		var status_index = id - 100
		if task != null and status_index >= 0 and status_index < statuses.size():
			task.status = statuses[status_index]
			if orchestrator and orchestrator.workplan:
				orchestrator.workplan.update_task() # Save the change
			_refresh_dashboard()
			print("MissionControl: Changed status of '%s' to '%s'" % [task.title, task.status])

# Helper functions
func _get_days_in_month(year: int, month: int) -> int:
	"""Get number of days in a month"""
	var days_in_months = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	
	# Check for leap year
	if month == 2 and ((year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)):
		return 29
	
	return days_in_months[month - 1]

func _parse_date_string(date_string: String) -> Dictionary:
	"""Parse date string into year/month/day dictionary"""
	if date_string.is_empty():
		return {}
	
	# Handle datetime format (YYYY-MM-DDTHH:MM:SS) by extracting just the date part
	var date_part = date_string
	if date_string.contains("T"):
		date_part = date_string.split("T")[0]
	
	# Handle different date formats
	var parts = []
	if date_part.contains("-"):
		parts = date_part.split("-")
	elif date_part.contains("/"):
		parts = date_part.split("/")
	else:
		return {}
	
	if parts.size() >= 3:
		return {
			"year": int(parts[0]),
			"month": int(parts[1]),
			"day": int(parts[2])
		}
	
	return {}

# Drag & Drop handlers
func _on_task_card_mouse_entered(card: Control, task: WorkplanTask, date_type: String):
	"""Handle mouse entering task card"""
	var base_modulate: Color = card.get_meta("base_modulate", card.modulate)
	card.modulate = base_modulate * 1.15  # Brighten on hover
	# Never replace the rich tooltip built by DayCardsScript (kind + Publish/Start/Deadline dates).
	if card.has_meta("tooltip_text_full"):
		card.tooltip_text = String(card.get_meta("tooltip_text_full"))
	elif card.tooltip_text.is_empty():
		var workplan_obj = orchestrator.workplan if orchestrator else null
		var is_blocked: bool = WorkplanDependenciesScript.is_blocked(task, workplan_obj)
		card.tooltip_text = DayCardsScript.build_tooltip(
			task, [date_type], "", date_type, is_blocked, workplan_obj
		)
	Input.set_default_cursor_shape(Input.CURSOR_MOVE)

func _on_task_card_mouse_exited(card: Control):
	"""Handle mouse exiting task card"""
	if card.has_meta("base_modulate"):
		card.modulate = card.get_meta("base_modulate")
	elif card.name.contains("start"):
		card.modulate = Color(0.8, 1.0, 0.8)
	elif card.name.contains("publish"):
		card.modulate = Color(0.8, 0.88, 1.0)
	else:
		card.modulate = Color(1.0, 0.8, 0.8)
	
	# Reset cursor
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _start_drag(task: WorkplanTask, date_type: String, card: Control):
	"""Start dragging a task card"""
	dragging_task = task
	drag_source_date_type = date_type
	
	# Visual feedback for dragging
	card.modulate = Color(1.0, 1.0, 1.0, 0.7)  # Semi-transparent
	
	# Highlight valid drop zones
	_highlight_drop_zones(true)
	
	print("Calendar: 🎯 Drag started - Move '%s' %s date to a new day" % [task.title, date_type])

func _stop_drag():
	"""Stop dragging and reset visual state"""
	if dragging_task:
		print("Calendar: Stopped dragging %s" % dragging_task.title)
		dragging_task = null
		drag_source_date_type = ""
		
		# Remove drop zone highlights
		_highlight_drop_zones(false)

func _highlight_drop_zones(highlight: bool):
	"""Highlight or unhighlight valid drop zones"""
	for cell in calendar_day_cells:
		if not cell or not is_instance_valid(cell):
			continue
			
		if highlight:
			# Add subtle border/glow effect
			cell.modulate = Color(1.1, 1.1, 1.0) # Slight yellow tint
		else:
			# Reset to normal
			var current_date = Time.get_datetime_dict_from_system()
			if current_date.year == current_calendar_year and current_date.month == current_calendar_month and current_date.day == int(cell.name.split("_")[1]):
				cell.modulate = Color(1.2, 1.2, 1.0)
			else:
				cell.modulate = Color.WHITE

func _ensure_calendar_rescheduler():
	if calendar_rescheduler != null:
		return
	const RescheduleScript = preload("res://readymade/scripts/workplan_calendar_reschedule.gd")
	calendar_rescheduler = RescheduleScript.new()
	calendar_rescheduler.cadence_changed.connect(_on_calendar_cadence_changed)

func _on_calendar_cadence_changed(warnings: Array) -> void:
	_ensure_calendar_cadence_banner()
	if calendar_cadence_banner == null:
		return
	if warnings.is_empty():
		calendar_cadence_banner.text = "Cadence: OK"
		calendar_cadence_banner.modulate = Color(0.7, 0.95, 0.7)
	else:
		calendar_cadence_banner.text = "Cadence: %d warning(s) after reschedule" % warnings.size()
		calendar_cadence_banner.modulate = Color(0.95, 0.75, 0.35)

func _calendar_banner_host() -> Node:
	"""CalendarVBoxContainer (own row). Never parent banners beside CalendarGrid in ScrollContainer."""
	if calendar_grid == null:
		return null
	var scroll: Node = calendar_grid.get_parent()
	if scroll != null and scroll.get_parent() != null:
		return scroll.get_parent()
	return scroll


func _ensure_calendar_cadence_banner() -> void:
	if calendar_cadence_banner != null and is_instance_valid(calendar_cadence_banner):
		return
	var host: Node = _calendar_banner_host()
	if host == null:
		return
	calendar_cadence_banner = Label.new()
	calendar_cadence_banner.name = "CalendarCadenceBanner"
	# Single-line row with a floor width so it never collapses to ~10px vertical letters.
	calendar_cadence_banner.autowrap_mode = TextServer.AUTOWRAP_OFF
	calendar_cadence_banner.clip_text = true
	calendar_cadence_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	calendar_cadence_banner.custom_minimum_size = Vector2(160, 0)
	host.add_child(calendar_cadence_banner)
	var scroll: Node = calendar_grid.get_parent() if calendar_grid else null
	if scroll != null and scroll.get_parent() == host:
		host.move_child(calendar_cadence_banner, scroll.get_index())
	else:
		host.move_child(calendar_cadence_banner, 0)

func _handle_drop_on_day(day: int):
	"""Handle dropping a task on a specific day (preserves publish timezone)."""
	if not dragging_task:
		return
	if drag_source_date_type != "publish" and not _is_valid_date_change(dragging_task, drag_source_date_type, day):
		_stop_drag()
		return
	var new_date = "%04d-%02d-%02d" % [current_calendar_year, current_calendar_month, day]
	_reschedule_task(dragging_task, new_date, drag_source_date_type)
	_stop_drag()

func _reschedule_task(task: WorkplanTask, new_date: String, date_type: String) -> void:
	_ensure_calendar_rescheduler()
	var fields: Array = []
	match date_type:
		"start":
			fields = ["start_date"]
		"deadline":
			fields = ["deadline"]
		"publish":
			fields = ["publish_date", "scheduled_date", "deadline"]
		_:
			fields = ["publish_date", "scheduled_date", "deadline"]
	var cascade_fields: Array = WorkplanDependenciesScript.cascade_fields_preserving_duration(fields)
	var workplan_obj = orchestrator.workplan if orchestrator else null
	var old_anchor: String = ""
	if task != null:
		match date_type:
			"start":
				old_anchor = task.start_date
			"deadline":
				old_anchor = task.deadline
			_:
				old_anchor = task.publish_date if not task.publish_date.is_empty() else task.get_calendar_display_date()
	var result: Dictionary = calendar_rescheduler.move_task_to_date(
		task,
		new_date,
		fields,
		true,
		workplan_obj,
		calendar_series_mode
	)
	print(
		"Calendar: rescheduled %d task(s) → %s (series=%s, warnings=%d)"
		% [int(result.get("moved", 0)), new_date, calendar_series_mode, (result.get("warnings", []) as Array).size()]
	)
	calendar_last_task_count = -1
	_populate_calendar_with_tasks()
	_offer_move_dependents(task, old_anchor, new_date, cascade_fields, workplan_obj)

func _offer_move_dependents(
	task: WorkplanTask,
	old_date: String,
	new_date: String,
	fields: Array,
	workplan_obj: Resource
) -> void:
	if task == null or workplan_obj == null:
		return
	task.ensure_task_id()
	var dependents: Array = WorkplanDependenciesScript.get_dependents(task.task_id, workplan_obj)
	if dependents.is_empty():
		return
	var offset_days: int = WorkplanDependenciesScript.day_offset(old_date, new_date)
	if offset_days == 0:
		return
	var cascade_fields: Array = WorkplanDependenciesScript.cascade_fields_preserving_duration(fields)
	var confirm := ConfirmationDialog.new()
	confirm.title = "Move dependents?"
	confirm.dialog_text = (
		"Move %d dependent task(s) by the same offset (%+d day(s))?"
		% [dependents.size(), offset_days]
	)
	# Exclusive + deferred popup: drag mouse-up must finish before OK can take a single click.
	confirm.exclusive = true
	confirm.transient = true
	var applied_box: Array = [false]
	var apply_cascade := func():
		if bool(applied_box[0]) or not is_instance_valid(confirm):
			return
		applied_box[0] = true
		confirm.hide()
		var moved: Dictionary = WorkplanDependenciesScript.move_dependents_by_offset(
			task, offset_days, workplan_obj, cascade_fields
		)
		# Fold cascade into the same undo record so Undo restores start_date too.
		_ensure_calendar_rescheduler()
		calendar_rescheduler.extend_last_undo(moved.get("snapshots", []))
		print("Calendar: cascaded %d dependent task(s)" % int(moved.get("moved", 0)))
		calendar_last_task_count = -1
		_populate_calendar_with_tasks()
		confirm.queue_free()
	confirm.confirmed.connect(apply_cascade, CONNECT_ONE_SHOT)
	confirm.canceled.connect(func():
		confirm.hide()
		confirm.queue_free()
	, CONNECT_ONE_SHOT)
	add_child(confirm)
	# Wait for drag release to settle so the first OK click applies (not just focuses).
	get_tree().create_timer(0.12).timeout.connect(func():
		if not is_instance_valid(confirm):
			return
		confirm.popup_centered()
		var ok_btn: Button = confirm.get_ok_button()
		if ok_btn != null:
			ok_btn.grab_focus()
	, CONNECT_ONE_SHOT)

func _prompt_move_task_to_date(task: WorkplanTask) -> void:
	"""Keyboard-accessible alternative to drag-and-drop."""
	if task == null:
		return
	var dialog := AcceptDialog.new()
	dialog.title = "Move to date"
	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)
	var hint := Label.new()
	hint.text = "YYYY-MM-DD (preserves publish time/timezone)"
	vbox.add_child(hint)
	var edit := LineEdit.new()
	edit.placeholder_text = "2026-11-20"
	edit.text = task.publish_date if not task.publish_date.is_empty() else task.deadline
	vbox.add_child(edit)
	dialog.confirmed.connect(func():
		var date_str: String = edit.text.strip_edges()
		dialog.queue_free()
		if date_str.length() >= 10:
			_reschedule_task(task, date_str, "publish")
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _undo_calendar_reschedule() -> void:
	# Menu already hidden in id_pressed; never re-show during rebuild.
	_dismiss_calendar_context_menu()
	_ensure_calendar_rescheduler()
	var workplan_obj = orchestrator.workplan if orchestrator else null
	if calendar_rescheduler.undo_last(workplan_obj):
		calendar_last_task_count = -1
		_populate_calendar_with_tasks()
		print("Calendar: undid last reschedule")
	else:
		print("Calendar: nothing to undo")
	_dismiss_calendar_context_menu()

func _get_day_under_mouse(mouse_pos: Vector2) -> int:
	"""Get the calendar day number under the mouse position"""
	for i in range(calendar_day_cells.size()):
		var cell = calendar_day_cells[i]
		if not cell or not is_instance_valid(cell):
			continue
			
		# Get the cell's global rect
		var cell_rect = Rect2(cell.global_position, cell.size)
		if cell_rect.has_point(mouse_pos):
			return i + 1  # Day numbers are 1-based
	
	return -1  # No valid day found

func _is_valid_date_change(task: WorkplanTask, date_type: String, new_day: int) -> bool:
	"""Check if the date change is valid (e.g., start date before deadline)"""
	var _new_date = "%04d-%02d-%02d" % [current_calendar_year, current_calendar_month, new_day]
	
	if date_type == "start":
		# Check if new start date is before deadline (if deadline exists)
		if not task.deadline.is_empty():
			var deadline_parts = task.deadline.split("-")
			if deadline_parts.size() >= 3:
				var deadline_year = int(deadline_parts[0])
				var deadline_month = int(deadline_parts[1])
				var deadline_day = int(deadline_parts[2])
				
				# Simple date comparison for same month/year
				if deadline_year == current_calendar_year and deadline_month == current_calendar_month:
					if new_day > deadline_day:
						print("Calendar: ⚠️ Cannot set start date after deadline")
						return false
	else:  # deadline
		# Check if new deadline is after start date (if start date exists)
		if not task.start_date.is_empty():
			var start_parts = task.start_date.split("-")
			if start_parts.size() >= 3:
				var start_year = int(start_parts[0])
				var start_month = int(start_parts[1])
				var start_day = int(start_parts[2])
				
				# Simple date comparison for same month/year
				if start_year == current_calendar_year and start_month == current_calendar_month:
					if new_day < start_day:
						print("Calendar: ⚠️ Cannot set deadline before start date")
						return false
	
	return true

func _get_task_container_from_cell(cell: Control) -> VBoxContainer:
	"""Robustly finds the TaskContainer node within a day cell."""
	if not cell or not is_instance_valid(cell):
		return null
		
	var path = "VBoxContainer/ScrollContainer/TaskContainer"
	var task_container = cell.get_node_or_null(path)
	
	if not task_container:
		print("Calendar Error: Could not find TaskContainer in cell '%s' using path '%s'. Check cell structure." % [cell.name, path])
	
	return task_container

func _create_calendar_task_card(
	task: WorkplanTask,
	date_type: String,
	date_types: Array = [],
	day_number: int = 0
) -> Control:
	"""Create a compact task card for calendar display"""
	var workplan_obj = orchestrator.workplan if orchestrator else null
	var is_blocked: bool = WorkplanDependenciesScript.is_blocked(task, workplan_obj)
	var day_date: String = ""
	if day_number > 0:
		day_date = "%04d-%02d-%02d" % [current_calendar_year, current_calendar_month, day_number]
	var card: PanelContainer = DayCardsScript.create_month_card(
		task, date_type, date_types, day_date, is_blocked, workplan_obj
	)
	var primary_type: String = String(card.get_meta("primary_type", date_type))
	card.gui_input.connect(func(event): _on_task_card_input(card, task, primary_type, event))
	card.mouse_entered.connect(_on_task_card_mouse_entered.bind(card, task, primary_type))
	card.mouse_exited.connect(_on_task_card_mouse_exited.bind(card))
	return card

