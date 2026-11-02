extends "res://readymade/ui/internal/mission_control_task_list_base.gd"
class_name MissionControlCalendarBase

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
	
	# Build the calendar grid
	_build_calendar_grid()

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
	if not calendar_grid:
		return
	
	# Clear existing calendar
	for child in calendar_grid.get_children():
		child.queue_free()
	calendar_day_cells.clear()
	
	# Add day headers
	var day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	for day_name in day_names:
		var header = Label.new()
		header.text = day_name
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
		empty_cell.custom_minimum_size = Vector2(120, 100)
		calendar_grid.add_child(empty_cell)
	
	# Add day cells
	for day in range(1, days_in_month + 1):
		var day_cell = _create_day_cell(day)
		calendar_grid.add_child(day_cell)
		calendar_day_cells.append(day_cell)
	
	print("Calendar: Built calendar with %d day cells for %d-%d" % [calendar_day_cells.size(), current_calendar_year, current_calendar_month])
	
	# Populate with tasks after a short delay to ensure nodes are in scene tree
	call_deferred("_populate_calendar_with_tasks")

func _create_day_cell(day: int) -> Control:
	"""Create a day cell for the calendar"""
	var cell = PanelContainer.new()
	cell.name = "DayCell_%d" % day
	cell.custom_minimum_size = Vector2(120, 100)
	
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
	
	# Add a ScrollContainer to handle task overflow
	var scroll_container = ScrollContainer.new()
	scroll_container.name = "ScrollContainer" # Explicitly set the name
	scroll_container.mouse_filter = MOUSE_FILTER_PASS # CRUCIAL: Allow clicks to pass through to content
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
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
		
		var tasks_for_day = tasks_by_day[day]
		
		# Render visible task cards
		for i in range(min(tasks_for_day.size(), max_cards_per_day)):
			var task_event = tasks_for_day[i]
			var card = _create_calendar_task_card(task_event.task, task_event.type)
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
	
	# Deadline info
	if not task.deadline.is_empty():
		var deadline_info = Label.new()
		if task.is_overdue():
			deadline_info.text = "⚠️ OVERDUE: " + task.deadline
			deadline_info.modulate = Color.RED
		elif task.is_due_soon():
			deadline_info.text = "⏰ Due Soon: " + task.deadline
			deadline_info.modulate = Color.ORANGE
		else:
			deadline_info.text = "📅 Due: " + task.deadline
			deadline_info.modulate = Color.YELLOW
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

func _on_task_card_input(card: Control, task: WorkplanTask, date_type: String, event: InputEvent):
	"""Handle initial input on a task card to start a drag or handle clicks."""
	# --- The cell inspector has done its job. This can be removed. ---
	# var date_dict = _parse_date_string(task.start_date if date_type == "start" else task.deadline)
	# if date_dict.has("day"):
	# 	_debug_print_cell_structure(date_dict.day)
	# --------------------------------------------------------------------
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.double_click:
			_on_edit_task_pressed(task)
		else:
			# Single click: Start the drag operation
			_start_drag(task, date_type, card)
		get_viewport().set_input_as_handled()
	
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_show_task_context_menu(task, date_type)
		get_viewport().set_input_as_handled()

func _on_task_card_clicked(_task: WorkplanTask, _date_type: String, _event: InputEvent):
	"""Legacy function - kept for compatibility"""
	# This function is no longer used but kept to avoid breaking existing connections
	pass

func _on_day_cell_mouse_entered(day: int):
	"""Handle mouse entering day cell (for drop feedback)"""
	if dragging_task:
		# Highlight this cell as a drop target
		var cell_index = day - 1
		if cell_index >= 0 and cell_index < calendar_day_cells.size():
			var cell = calendar_day_cells[cell_index]
			if cell and is_instance_valid(cell):
				cell.modulate = Color(1.3, 1.3, 1.0)  # Bright yellow highlight

func _on_day_cell_mouse_exited(day: int):
	"""Handle mouse exiting day cell"""
	if dragging_task:
		# Reset cell highlight to normal drop zone color
		var cell_index = day - 1
		if cell_index >= 0 and cell_index < calendar_day_cells.size():
			var cell = calendar_day_cells[cell_index]
			if cell and is_instance_valid(cell):
				cell.modulate = Color(1.1, 1.1, 1.0)  # Back to normal drop zone highlight

func _show_task_context_menu(task: WorkplanTask, _date_type: String):
	"""Clears, populates, and shows the context menu for a calendar task."""
	context_menu_task = task # Store the task for the handler
	
	calendar_context_menu.clear()
	# HACK: For some reason, submenus added at index 0 don't work reliably.
	# So we add a dummy item first and will handle the submenu logic via ID.
	calendar_context_menu.add_item("Edit Task", 0)

	var status_submenu = calendar_context_menu.get_node_or_null("StatusSubmenu")
	if not status_submenu:
		status_submenu = PopupMenu.new()
		status_submenu.name = "StatusSubmenu"
		calendar_context_menu.add_child(status_submenu)
		status_submenu.id_pressed.connect(func(id): _on_calendar_context_menu_id_pressed(100 + id))

	status_submenu.clear()
	var statuses = ["To Do", "In Progress", "Review", "Done"]
	for i in statuses.size():
		status_submenu.add_item(statuses[i], i)
		
	calendar_context_menu.add_submenu_item("Change Status", "StatusSubmenu")
	
	calendar_context_menu.add_separator()
	calendar_context_menu.add_item("Delete Task", 2)
	
	calendar_context_menu.position = get_viewport().get_mouse_position()
	calendar_context_menu.popup()

func _on_calendar_context_menu_id_pressed(id: int):
	"""Handle context menu actions"""
	if not context_menu_task:
		return

	if id == 0: # Edit Task
		_on_edit_task_pressed(context_menu_task)
	elif id == 2: # Delete Task
		_on_delete_task_pressed(context_menu_task)
	elif id >= 100: # Change Status
		var statuses = ["To Do", "In Progress", "Review", "Done"]
		var status_index = id - 100
		if status_index >= 0 and status_index < statuses.size():
			context_menu_task.status = statuses[status_index]
			if orchestrator and orchestrator.workplan:
				orchestrator.workplan.update_task() # Save the change
			_refresh_dashboard()
			print("MissionControl: Changed status of '%s' to '%s'" % [context_menu_task.title, context_menu_task.status])

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

func _add_test_calendar_tasks():
	"""Add some test tasks with dates in current month for testing"""
	if not orchestrator or not orchestrator.workplan:
		return
	
	print("Calendar: Adding test tasks for current month %d-%d" % [current_calendar_year, current_calendar_month])
	
	# Create a few test tasks with dates in the current month
	var test_tasks = []
	
	# Task 1: Start date today
	var task1 = WorkplanTask.new()
	task1.title = "Test Start Task"
	task1.core_idea = "Testing start date display"
	task1.format = "Article"
	task1.channel = "LinkedIn"
	task1.start_date = "%04d-%02d-%02d" % [current_calendar_year, current_calendar_month, 5]
	test_tasks.append(task1)
	
	# Task 2: Deadline in current month
	var task2 = WorkplanTask.new()
	task2.title = "Test Deadline Task"
	task2.core_idea = "Testing deadline display"
	task2.format = "Video"
	task2.channel = "YouTube"
	task2.deadline = "%04d-%02d-%02d" % [current_calendar_year, current_calendar_month, 15]
	test_tasks.append(task2)
	
	# Task 3: Both start and deadline
	var task3 = WorkplanTask.new()
	task3.title = "Test Both Dates"
	task3.core_idea = "Testing both date types"
	task3.format = "Carousel"
	task3.channel = "Instagram"
	task3.start_date = "%04d-%02d-%02d" % [current_calendar_year, current_calendar_month, 10]
	task3.deadline = "%04d-%02d-%02d" % [current_calendar_year, current_calendar_month, 20]
	test_tasks.append(task3)
	
	# Add test tasks to the workplan
	for task in test_tasks:
		orchestrator.add_task_to_month("Month 1", task)
		print("Calendar: Added test task '%s'" % task.title)

# Drag & Drop handlers
func _on_task_card_mouse_entered(card: Control, _task: WorkplanTask, date_type: String):
	"""Handle mouse entering task card"""
	card.modulate = card.modulate * 1.2  # Brighten on hover
	card.tooltip_text = "🎯 Drag to move %s date\n🖱️ Right-click for options\n📝 Double-click to edit" % date_type
	
	# Change cursor to indicate draggable
	Input.set_default_cursor_shape(Input.CURSOR_MOVE)

func _on_task_card_mouse_exited(card: Control):
	"""Handle mouse exiting task card"""
	# Reset modulation to original based on date type
	if card.name.contains("start"):
		card.modulate = Color(0.8, 1.0, 0.8)  # Light green for start dates
	else:
		card.modulate = Color(1.0, 0.8, 0.8)  # Light red for deadlines
	
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

func _handle_drop_on_day(day: int):
	"""Handle dropping a task on a specific day"""
	if not dragging_task:
		return
	
	# Validate the date change
	if not _is_valid_date_change(dragging_task, drag_source_date_type, day):
		_stop_drag()
		return
		
	var new_date = "%04d-%02d-%02d" % [current_calendar_year, current_calendar_month, day]
	var old_date = ""
	
	# Update the appropriate date field
	if drag_source_date_type == "start":
		old_date = dragging_task.start_date
		dragging_task.start_date = new_date
		print("Calendar: ✅ Updated '%s' start date: %s → %s" % [dragging_task.title, old_date, new_date])
	else:  # deadline
		old_date = dragging_task.deadline
		dragging_task.deadline = new_date
		print("Calendar: ✅ Updated '%s' deadline: %s → %s" % [dragging_task.title, old_date, new_date])
	
	# Save the updated task by notifying the workplan
	if orchestrator and orchestrator.workplan:
		orchestrator.workplan.update_task()
		print("Calendar: Saved task changes to workplan")
	
	# Force calendar refresh to show the change
	calendar_last_task_count = -1  # Force refresh
	_populate_calendar_with_tasks()
	
	# Stop dragging
	_stop_drag()

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

func _create_calendar_task_card(task: WorkplanTask, date_type: String) -> Control:
	"""Create a compact task card for calendar display"""
	var card = PanelContainer.new()
	card.name = "TaskCard_%s_%s" % [task.title.replace(" ", "_"), date_type]
	card.custom_minimum_size = Vector2(0, 20)
	
	# Color coding based on date type
	if date_type == "start":
		card.modulate = Color(0.8, 1.0, 0.8)  # Light green for start dates
	else:  # deadline
		card.modulate = Color(1.0, 0.8, 0.8)  # Light red for deadlines
	
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = MOUSE_FILTER_PASS
	card.add_child(hbox)
	
	# Date type icon
	var icon_label = Label.new()
	if date_type == "start":
		icon_label.text = "🚀"
		icon_label.tooltip_text = "Start Date"
	else:
		icon_label.text = "🎯"
		icon_label.tooltip_text = "Deadline"
	icon_label.add_theme_font_size_override("font_size", 10)
	icon_label.mouse_filter = MOUSE_FILTER_PASS
	hbox.add_child(icon_label)
	
	# Task title (truncated)
	var title_label = Label.new()
	var display_title = task.title
	if display_title.length() > 12:
		display_title = display_title.substr(0, 12) + "..."
	title_label.text = display_title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 9)
	title_label.tooltip_text = "%s\nStatus: %s\nPriority: %d" % [task.title, task.status, task.priority]
	title_label.mouse_filter = MOUSE_FILTER_PASS
	hbox.add_child(title_label)
	
	# Status indicator
	var status_icon = Label.new()
	match task.status:
		"To Do":
			status_icon.text = "📝"
		"In Progress":
			status_icon.text = "🔄"
		"Review":
			status_icon.text = "👀"
		"Done":
			status_icon.text = "✅"
	status_icon.add_theme_font_size_override("font_size", 8)
	status_icon.mouse_filter = MOUSE_FILTER_PASS
	hbox.add_child(status_icon)
	
	# Add click and drag handlers
	card.gui_input.connect(func(event): _on_task_card_input(card, task, date_type, event))
	
	# Enable drag and drop
	card.mouse_entered.connect(_on_task_card_mouse_entered.bind(card, task, date_type))
	card.mouse_exited.connect(_on_task_card_mouse_exited.bind(card))
	
	return card

