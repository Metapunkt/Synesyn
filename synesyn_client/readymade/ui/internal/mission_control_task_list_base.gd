extends "res://readymade/ui/internal/mission_control_task_dashboard_base.gd"
class_name MissionControlTaskListBase

func _setup_task_list_management():
	"""Setup file dialog for task list operations"""
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.add_filter("*.json", "Task List Files")
	file_dialog.current_dir = OS.get_user_data_dir()
	file_dialog.file_selected.connect(_on_file_dialog_file_selected)
	add_child(file_dialog)
	
	# Initialize button states
	_update_task_list_buttons()
	
	print("MissionControl: Task list management initialized")

func _on_task_checkbox_toggled(pressed: bool, task: WorkplanTask):
	"""Handle task checkbox being toggled"""
	if pressed:
		if task not in selected_tasks:
			selected_tasks.append(task)
	else:
		if task in selected_tasks:
			selected_tasks.erase(task)
	
	print("MissionControl: Task selection changed - ", selected_tasks.size(), " tasks selected")
	_update_task_list_buttons()  # This will update both save buttons and select all button

func _update_task_list_buttons():
	"""Update task list button states based on selection"""
	var has_selection = selected_tasks.size() > 0
	save_task_list_button.disabled = not has_selection
	save_as_task_list_button.disabled = not has_selection
	
	# Update button text to show selection count
	if has_selection:
		save_task_list_button.text = "💾 Save Task List (%d)" % selected_tasks.size()
		save_as_task_list_button.text = "💾 Save As... (%d)" % selected_tasks.size()
	else:
		save_task_list_button.text = "💾 Save Task List"
		save_as_task_list_button.text = "💾 Save As..."
	
	# Update select all button text based on current selection state
	_update_select_all_button_text()

func _update_select_all_button_text():
	"""Update the select all button text based on current selection state"""
	if not select_all_button:
		return
	
	# Get all tasks currently displayed
	var all_visible_tasks = []
	if is_filtered_view and not filtered_tasks.is_empty():
		all_visible_tasks = filtered_tasks
	else:
		# Get all tasks from workplan
		if workplan and not workplan.is_empty():
			for month_name in workplan.keys():
				var month_tasks = workplan[month_name]
				if month_tasks is Array:
					all_visible_tasks.append_array(month_tasks)
	
	# Apply current search filters to get final visible list
	all_visible_tasks = _apply_search_filters(all_visible_tasks)
	
	if all_visible_tasks.is_empty():
		select_all_button.text = "☑️ Select All"
		select_all_button.disabled = true
		return
	
	# Check if all visible tasks are selected
	var all_selected = true
	for task in all_visible_tasks:
		if task not in selected_tasks:
			all_selected = false
			break
	
	select_all_button.disabled = false
	if all_selected:
		select_all_button.text = "☐ Deselect All (%d)" % all_visible_tasks.size()
	else:
		var selected_count = 0
		for task in all_visible_tasks:
			if task in selected_tasks:
				selected_count += 1
		
		if selected_count > 0:
			select_all_button.text = "☑️ Select All (%d/%d)" % [selected_count, all_visible_tasks.size()]
		else:
			select_all_button.text = "☑️ Select All (%d)" % all_visible_tasks.size()

func _on_new_task_list_pressed():
	"""Create a new task list (clear selection)"""
	print("MissionControl: Creating new task list")
	_clear_task_selection()
	current_task_list_path = ""
	current_task_list_name = ""
	workplan_replaced = false
	_update_status_display()
	print("MissionControl: ✅ New task list created - ready for selection")

func _on_view_all_tasks_pressed():
	"""Show all tasks from the workplan (clear filter)"""
	print("MissionControl: Switching to full workplan view")
	is_filtered_view = false
	filtered_tasks.clear()
	current_task_list_path = ""
	current_task_list_name = ""
	workplan_replaced = false
	_clear_task_selection()
	_update_status_display()
	_update_task_list()
	print("MissionControl: ✅ Now showing all tasks from workplan")

func _on_select_all_pressed():
	"""Toggle between select all and deselect all visible tasks"""
	
	# Get all tasks currently displayed
	var all_visible_tasks = []
	if is_filtered_view and not filtered_tasks.is_empty():
		all_visible_tasks = filtered_tasks
	else:
		# Get all tasks from workplan
		if workplan and not workplan.is_empty():
			for month_name in workplan.keys():
				var month_tasks = workplan[month_name]
				if month_tasks is Array:
					all_visible_tasks.append_array(month_tasks)
	
	# Apply current search filters to get final visible list
	all_visible_tasks = _apply_search_filters(all_visible_tasks)
	
	# Check if all visible tasks are already selected
	var all_selected = true
	for task in all_visible_tasks:
		if task not in selected_tasks:
			all_selected = false
			break
	
	if all_selected:
		# Deselect all
		print("MissionControl: Deselecting all visible tasks")
		for task in all_visible_tasks:
			selected_tasks.erase(task)
			# Update checkbox if it exists
			if task_checkboxes.has(task):
				task_checkboxes[task].button_pressed = false
		print("MissionControl: ✅ Deselected all visible tasks")
	else:
		# Select all
		print("MissionControl: Selecting all visible tasks")
		for task in all_visible_tasks:
			if task not in selected_tasks:
				selected_tasks.append(task)
			# Update checkbox if it exists
			if task_checkboxes.has(task):
				task_checkboxes[task].button_pressed = true
		print("MissionControl: ✅ Selected ", selected_tasks.size(), " visible tasks")
	
	_update_task_list_buttons()

func _on_open_task_list_pressed():
	"""Load a task list - filter existing tasks or import new ones"""
	print("MissionControl: Loading task list...")
	if file_dialog:
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.popup_centered(Vector2(800, 600))

func _on_save_task_list_pressed():
	"""Save current selection to existing file or prompt for new file"""
	if selected_tasks.is_empty():
		print("MissionControl: ⚠️ No tasks selected to save")
		return
	
	if current_task_list_path.is_empty():
		_on_save_as_task_list_pressed()
	else:
		_save_task_list_to_file(current_task_list_path)

func _on_save_as_task_list_pressed():
	"""Save current selection to a new file"""
	if selected_tasks.is_empty():
		print("MissionControl: ⚠️ No tasks selected to save")
		return
	
	print("MissionControl: Save as task list...")
	if file_dialog:
		file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		file_dialog.popup_centered(Vector2(800, 600))

func _on_file_dialog_file_selected(path: String):
	"""Handle file dialog selection"""
	# Close the file dialog first to avoid window exclusivity issues
	file_dialog.hide()
	
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		_save_task_list_to_file(path)
	else:  # FILE_MODE_OPEN_FILE
		# Use call_deferred to ensure file dialog is fully closed before proceeding
		call_deferred("_load_task_list_from_file", path)

func _save_task_list_to_file(path: String):
	"""Save selected tasks to JSON file"""
	var task_list_data = {
		"metadata": {
			"created_date": Time.get_datetime_string_from_system(),
			"task_count": selected_tasks.size(),
			"readymade_version": "1.0"
		},
		"tasks": []
	}
	
	for task in selected_tasks:
		var task_data = {
			"title": task.title,
			"core_idea": task.core_idea,
			"cosmic_instrument": task.cosmic_instrument,
			"format": task.format,
			"channel": task.channel,
			"status": task.status,
			"priority": task.priority,
			"deadline": task.deadline,
			"start_date": task.start_date,
			"completion_date": task.completion_date,
			"created_date": task.created_date,
			"notes": task.notes,
			"deliverable_path": task.deliverable_path,
			"generated_content": task.generated_content
		}
		task_list_data.tasks.append(task_data)
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(task_list_data, "\t")
		file.store_string(json_string)
		file.close()
		current_task_list_path = path
		print("MissionControl: ✅ Task list saved to: ", path)
		print("MissionControl: Saved ", selected_tasks.size(), " tasks")
	else:
		push_error("MissionControl: Failed to save task list to: " + path)

func _load_task_list_from_file(path: String):
	"""Load task list from JSON file as a filter for the Tasks tab"""
	print("MissionControl: 📂 Loading task list from: ", path.get_file())
	print("MissionControl: 🗂️ Current workplan state check:")
	print("  - orchestrator: ", orchestrator != null)
	var orchestrator_workplan_text := "N/A"
	if orchestrator:
		orchestrator_workplan_text = "true" if orchestrator.workplan != null else "false"
	print("  - orchestrator.workplan: ", orchestrator_workplan_text)
	print("  - workplan_manager: ", workplan_manager != null)
	print("  - current workplan name: ", workplan_manager.get_current_workplan_name() if workplan_manager else "Unknown")
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("MissionControl: Failed to open task list file: " + path)
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		push_error("MissionControl: Failed to parse task list JSON: " + path)
		return
	
	var task_list_data = json.data
	if not task_list_data.has("tasks"):
		push_error("MissionControl: Invalid task list format: " + path)
		return
	
	print("MissionControl: 📋 Task list contains ", task_list_data.tasks.size(), " tasks")
	
	# Clear current selection
	_clear_task_selection()
	
	# Find matching tasks from the current workplan
	filtered_tasks.clear()
	var found_count = 0
	var unmatched_tasks = []
	
	for task_data in task_list_data.tasks:
		var matching_task = _find_matching_task(task_data)
		if matching_task:
			filtered_tasks.append(matching_task)
			found_count += 1
		else:
			unmatched_tasks.append(task_data)
			print("MissionControl: ⚠️ Task not found in workplan: ", task_data.get("title", "Unknown"))
	
	# If no matches found, offer to import tasks into current workplan
	print("MissionControl: 🔍 Import check - found_count: ", found_count, ", unmatched_tasks.size(): ", unmatched_tasks.size())
	if found_count == 0 and not unmatched_tasks.is_empty():
		print("MissionControl: 📋 Triggering import choice dialog")
		_show_import_choice_dialog(path, task_list_data, unmatched_tasks)
		return
	else:
		print("MissionControl: ⚠️ Import dialog NOT triggered - found_count: ", found_count, ", unmatched_tasks empty: ", unmatched_tasks.is_empty())
	
	# Set filtered view state
	is_filtered_view = true
	current_task_list_path = path
	current_task_list_name = path.get_file().get_basename()
	workplan_replaced = false  # Not replacing, just filtering
	
	_update_task_list_buttons()
	_update_status_display()
	_update_task_list()  # Update display to show filtered tasks
	
	print("MissionControl: ✅ Task list loaded as filter")
	print("MissionControl: Found ", found_count, " matching tasks from: ", path.get_file())
	print("MissionControl: Tasks tab now shows filtered view with ", filtered_tasks.size(), " tasks")

func _find_matching_task(task_data: Dictionary) -> WorkplanTask:
	"""Find a task in the current workplan that matches the loaded task data"""
	if not orchestrator or not orchestrator.workplan:
		return null
	
	var all_tasks = orchestrator.workplan.get_all_tasks()
	for task in all_tasks:
		# Match by title and core_idea for uniqueness
		if task.title == task_data.get("title", "") and task.core_idea == task_data.get("core_idea", ""):
			return task
	
	return null

func _clear_task_selection():
	"""Clear all task selections"""
	selected_tasks.clear()
	
	# Update all checkboxes
	for task in task_checkboxes.keys():
		if task_checkboxes[task]:
			task_checkboxes[task].button_pressed = false
	
	_update_task_list_buttons()  # Update button states including select all button
	print("MissionControl: Task selection cleared")

func _clear_current_workplan():
	"""Clear all tasks from the current workplan"""
	if not orchestrator or not orchestrator.workplan:
		print("MissionControl: ⚠️ No orchestrator or workplan to clear")
		return
	
	# Clear all months in the workplan
	orchestrator.workplan.months.clear()
	orchestrator.workplan.months["Month 1"] = []
	
	# Save the cleared workplan
	orchestrator.save_workplan()
	
	print("MissionControl: ✅ Current workplan cleared")

func _create_task_from_data(task_data: Dictionary) -> WorkplanTask:
	"""Create a WorkplanTask object from JSON data"""
	var task = WorkplanTask.new()
	
	# Set all task properties from the loaded data
	task.title = task_data.get("title", "")
	task.core_idea = task_data.get("core_idea", "")
	task.cosmic_instrument = task_data.get("cosmic_instrument", "")
	task.format = task_data.get("format", "")
	task.channel = task_data.get("channel", "")
	task.status = task_data.get("status", "To Do")
	task.priority = task_data.get("priority", 1)
	task.deadline = task_data.get("deadline", "")
	task.start_date = task_data.get("start_date", "")
	task.completion_date = task_data.get("completion_date", "")
	task.created_date = task_data.get("created_date", Time.get_datetime_string_from_system())
	task.notes = task_data.get("notes", "")
	task.deliverable_path = task_data.get("deliverable_path", "")
	task.generated_content = task_data.get("generated_content", "")
	
	return task

func _show_import_choice_dialog(path: String, task_list_data: Dictionary, unmatched_tasks: Array):
	"""Show dialog asking user how to handle task list with no matching tasks"""
	print("MissionControl: 🎭 _show_import_choice_dialog called with ", unmatched_tasks.size(), " unmatched tasks")
	
	var dialog = AcceptDialog.new()
	dialog.title = "Task List Import Options"
	dialog.set_flag(Window.FLAG_RESIZE_DISABLED, false)
	dialog.min_size = Vector2(500, 300)
	
	# Create main container
	var main_container = VBoxContainer.new()
	main_container.add_theme_constant_override("separation", 15)
	dialog.add_child(main_container)
	
	# Header section
	var header_label = Label.new()
	header_label.text = "📋 Task List: %s" % path.get_file()
	header_label.theme_type_variation = "HeaderMedium"
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(header_label)
	
	# Problem description
	var problem_container = VBoxContainer.new()
	problem_container.add_theme_constant_override("separation", 5)
	main_container.add_child(problem_container)
	
	var problem_title = Label.new()
	problem_title.text = "⚠️ No Matching Tasks Found"
	problem_title.theme_type_variation = "HeaderSmall"
	problem_title.modulate = Color.ORANGE
	problem_container.add_child(problem_title)
	
	var problem_desc = Label.new()
	problem_desc.text = "This task list contains %d tasks that don't exist in the current workplan '%s'." % [unmatched_tasks.size(), workplan_manager.get_current_workplan_name()]
	problem_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	problem_desc.custom_minimum_size.x = 450
	problem_container.add_child(problem_desc)
	
	# Separator
	var separator = HSeparator.new()
	main_container.add_child(separator)
	
	# Options section
	var options_label = Label.new()
	options_label.text = "How would you like to proceed?"
	options_label.theme_type_variation = "HeaderSmall"
	main_container.add_child(options_label)
	
	# Option descriptions
	var options_container = VBoxContainer.new()
	options_container.add_theme_constant_override("separation", 10)
	main_container.add_child(options_container)
	
	# Import option
	var import_option = HBoxContainer.new()
	options_container.add_child(import_option)
	
	var import_icon = Label.new()
	import_icon.text = "📥"
	import_icon.custom_minimum_size.x = 30
	import_option.add_child(import_icon)
	
	var import_desc = VBoxContainer.new()
	import_option.add_child(import_desc)
	
	var import_title = Label.new()
	import_title.text = "Import Tasks (Recommended)"
	import_title.add_theme_color_override("font_color", Color.GREEN)
	import_desc.add_child(import_title)
	
	var import_detail = Label.new()
	import_detail.text = "Add all %d tasks from the list to this workplan and show them as a filtered view." % unmatched_tasks.size()
	import_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	import_detail.modulate = Color.LIGHT_GRAY
	import_detail.custom_minimum_size.x = 400
	import_desc.add_child(import_detail)
	
	# Filter option
	var filter_option = HBoxContainer.new()
	options_container.add_child(filter_option)
	
	var filter_icon = Label.new()
	filter_icon.text = "🔍"
	filter_icon.custom_minimum_size.x = 30
	filter_option.add_child(filter_icon)
	
	var filter_desc = VBoxContainer.new()
	filter_option.add_child(filter_desc)
	
	var filter_title = Label.new()
	filter_title.text = "Filter Only (Empty View)"
	filter_title.add_theme_color_override("font_color", Color.YELLOW)
	filter_desc.add_child(filter_title)
	
	var filter_detail = Label.new()
	filter_detail.text = "Show empty filtered view without changing the current workplan."
	filter_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	filter_detail.modulate = Color.LIGHT_GRAY
	filter_detail.custom_minimum_size.x = 400
	filter_desc.add_child(filter_detail)
	
	# Buttons section
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 15)
	main_container.add_child(button_container)
	
	var import_button = Button.new()
	import_button.text = "📥 Import Tasks"
	import_button.custom_minimum_size = Vector2(150, 35)
	import_button.modulate = Color(0.8, 1.0, 0.8)  # Light green
	button_container.add_child(import_button)
	
	var filter_button = Button.new()
	filter_button.text = "🔍 Filter Only"
	filter_button.custom_minimum_size = Vector2(150, 35)
	filter_button.modulate = Color(1.0, 1.0, 0.8)  # Light yellow
	button_container.add_child(filter_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "❌ Cancel"
	cancel_button.custom_minimum_size = Vector2(100, 35)
	button_container.add_child(cancel_button)
	
	add_child(dialog)
	print("MissionControl: 🪟 About to show import dialog...")
	
	# Ensure dialog is properly configured for visibility
	dialog.min_size = Vector2(500, 300)
	dialog.size = Vector2(500, 300)
	
	# Try to bring dialog to front
	dialog.popup_centered()
	dialog.move_to_foreground()
	print("MissionControl: ✅ Import dialog popup_centered() called")
	print("MissionControl: Dialog visible: ", dialog.visible)
	print("MissionControl: Dialog size: ", dialog.size)
	print("MissionControl: Dialog position: ", dialog.position)
	
	# Add dialog lifecycle debugging
	dialog.about_to_popup.connect(func(): print("MissionControl: 📺 Dialog about_to_popup"))
	dialog.visibility_changed.connect(func(): print("MissionControl: 👁️ Dialog visibility changed to: ", dialog.visible))
	dialog.confirmed.connect(func(): print("MissionControl: ✅ Dialog confirmed"))
	dialog.canceled.connect(func(): print("MissionControl: ❌ Dialog canceled"))
	
	# Store choice on dialog object to avoid scoping issues
	dialog.set_meta("user_choice", "")
	
	import_button.pressed.connect(func(): 
		print("MissionControl: ✅ Import button pressed")
		dialog.set_meta("user_choice", "import")
		print("MissionControl: 🎯 Choice stored on dialog: ", dialog.get_meta("user_choice"))
		dialog.hide()
		call_deferred("_close_dialog", dialog)
	)
	
	filter_button.pressed.connect(func(): 
		print("MissionControl: 🔍 Filter button pressed") 
		dialog.set_meta("user_choice", "filter")
		print("MissionControl: 🎯 Choice stored on dialog: ", dialog.get_meta("user_choice"))
		dialog.hide()
		call_deferred("_close_dialog", dialog)
	)
	
	cancel_button.pressed.connect(func(): 
		print("MissionControl: ❌ Cancel button pressed")
		dialog.set_meta("user_choice", "cancel")
		print("MissionControl: 🎯 Choice stored on dialog: ", dialog.get_meta("user_choice"))
		dialog.hide()
		call_deferred("_close_dialog", dialog)
	)
	
	# Wait for user decision
	await dialog.tree_exited
	var user_choice = dialog.get_meta("user_choice", "")
	print("MissionControl: 🏁 Dialog tree_exited with choice: ", user_choice)
	
	match user_choice:
		"import":
			_import_tasks_to_workplan(path, task_list_data, unmatched_tasks)
		"filter":
			_proceed_with_empty_filter(path, task_list_data)
		"cancel":
			print("MissionControl: Task list loading canceled")

func _close_dialog(dialog: AcceptDialog):
	"""Helper function to properly close dialog after choice is made"""
	if dialog and is_instance_valid(dialog):
		dialog.queue_free()

func _import_tasks_to_workplan(path: String, _task_list_data: Dictionary, unmatched_tasks: Array):
	"""Import tasks from task list into current workplan"""
	print("MissionControl: 🚀 Starting import of ", unmatched_tasks.size(), " tasks into current workplan")
	print("MissionControl: Current workplan: ", workplan_manager.get_current_workplan_name() if workplan_manager else "Unknown")
	print("MissionControl: Orchestrator available: ", orchestrator != null)
	var has_workplan := false
	if orchestrator and orchestrator.has("workplan"):
		has_workplan = orchestrator.workplan != null
	var workplan_availability_text := "N/A"
	if orchestrator:
		workplan_availability_text = "true" if has_workplan else "false"
	print("MissionControl: Orchestrator workplan available: ", workplan_availability_text)
	
	var imported_tasks: Array[WorkplanTask] = []
	for task_data in unmatched_tasks:
		var new_task = _create_task_from_data(task_data)
		print("MissionControl: Created task object: ", new_task.title, " (", new_task.core_idea, ")")
		
		# Add to current workplan
		if orchestrator and orchestrator.workplan:
			orchestrator.add_task_to_month("Month 1", new_task)
			imported_tasks.append(new_task)
			print("MissionControl: ✅ Added task to workplan: ", new_task.title)
		else:
			print("MissionControl: ❌ Failed to add task - orchestrator or workplan not available")
	
	print("MissionControl: Successfully imported ", imported_tasks.size(), " tasks")
	
	# Set up filtered view with imported tasks
	filtered_tasks = imported_tasks
	is_filtered_view = true
	current_task_list_path = path
	current_task_list_name = path.get_file().get_basename()
	workplan_replaced = false
	
	print("MissionControl: Setting up filtered view with ", filtered_tasks.size(), " tasks")
	
	_update_task_list_buttons()
	_update_status_display()
	_update_task_list()
	_update_statistics()  # Update stats since we added tasks
	_update_calendar()    # Update calendar with new task dates
	
	print("MissionControl: ✅ Task list imported to workplan")
	print("MissionControl: Imported ", imported_tasks.size(), " tasks from: ", path.get_file())
	print("MissionControl: Tasks tab now shows filtered view with imported tasks")
	print("MissionControl: Current workplan task count: ", orchestrator.workplan.get_total_tasks() if orchestrator and orchestrator.workplan else "Unknown")

func _proceed_with_empty_filter(path: String, _task_list_data: Dictionary):
	"""Proceed with empty filter (original behavior)"""
	print("MissionControl: Proceeding with empty filter")
	
	# Set filtered view state with empty tasks
	filtered_tasks.clear()
	is_filtered_view = true
	current_task_list_path = path
	current_task_list_name = path.get_file().get_basename()
	workplan_replaced = false
	
	_update_task_list_buttons()
	_update_status_display()
	_update_task_list()
	
	print("MissionControl: ✅ Task list loaded as empty filter")
	print("MissionControl: Showing empty filtered view from: ", path.get_file())

func _update_status_display():
	"""Update the status label to show current view state"""
	if not task_list_status_label:
		return
	
	var status_text = ""
	var status_color = Color.WHITE
	
	# Add workplan context
	if workplan_manager:
		var workplan_name = workplan_manager.get_current_workplan_name()
		status_text = "📋 " + workplan_name
		
		if is_filtered_view and not current_task_list_name.is_empty():
			status_text += " | 🔍 " + current_task_list_name + " (" + str(filtered_tasks.size()) + " tasks)"
			status_color = Color.YELLOW
		elif is_filtered_view:
			status_text += " | 🔍 Filtered (" + str(filtered_tasks.size()) + " tasks)"
			status_color = Color.YELLOW
		else:
			status_text += " | 👁️ All tasks"
			status_color = Color.CYAN
	else:
		# Fallback for when workplan manager isn't available yet
		if is_filtered_view and not current_task_list_name.is_empty():
			status_text = "🔍 Filtered: " + current_task_list_name + " (" + str(filtered_tasks.size()) + " tasks)"
			status_color = Color.YELLOW
		elif is_filtered_view:
			status_text = "🔍 Filtered view (" + str(filtered_tasks.size()) + " tasks)"
			status_color = Color.YELLOW
		else:
			status_text = "👁️ All tasks"
			status_color = Color.WHITE
	
	task_list_status_label.text = status_text
	task_list_status_label.modulate = status_color

# Filter and search functionality
func _setup_filter_options():
	"""Initialize filter dropdown options"""
	# Status filter options
	status_filter.clear()
	status_filter.add_item("All Status")
	status_filter.add_item("To Do")
	status_filter.add_item("In Progress")
	status_filter.add_item("Review")
	status_filter.add_item("Done")
	
	# Priority filter options
	priority_filter.clear()
	priority_filter.add_item("All Priorities")
	priority_filter.add_item("Critical (3)")
	priority_filter.add_item("High (2)")
	priority_filter.add_item("Medium (1)")
	priority_filter.add_item("Low (0)")
	
	# Sort options
	sort_option.clear()
	sort_option.add_item("Sort by Priority")
	sort_option.add_item("Sort by Status")
	sort_option.add_item("Sort by Deadline")
	sort_option.add_item("Sort by Created Date")

func _on_search_text_changed(new_text: String):
	"""Handle search text changes"""
	current_search_text = new_text.to_lower()
	_update_task_list()

func _on_status_filter_changed(index: int):
	"""Handle status filter changes"""
	var items = ["All", "To Do", "In Progress", "Review", "Done"]
	current_status_filter = items[index] if index < items.size() else "All"
	_update_task_list()

func _on_priority_filter_changed(index: int):
	"""Handle priority filter changes"""
	var priorities = ["All", "3", "2", "1", "0"]
	current_priority_filter = priorities[index] if index < priorities.size() else "All"
	_update_task_list()

func _on_sort_option_changed(index: int):
	"""Handle sort option changes"""
	var sorts = ["Priority", "Status", "Deadline", "Created"]
	current_sort_mode = sorts[index] if index < sorts.size() else "Priority"
	_update_task_list()

func _apply_search_filters(tasks: Array) -> Array:
	"""Apply current search and filter options to task list (not task list filtering)"""
	var filtered_tasks_local = []
	
	for task in tasks:
		# Search filter
		if not current_search_text.is_empty():
			var searchable_text = (task.title + " " + task.core_idea + " " + task.format + " " + task.channel + " " + task.notes).to_lower()
			if not searchable_text.contains(current_search_text):
				continue
		
		# Status filter
		if current_status_filter != "All" and task.status != current_status_filter:
			continue
		
		# Priority filter
		if current_priority_filter != "All" and str(task.priority) != current_priority_filter:
			continue
		
		filtered_tasks_local.append(task)
	
	return filtered_tasks_local

func _sort_tasks(tasks: Array) -> Array:
	"""Sort tasks based on current sort mode"""
	match current_sort_mode:
		"Priority":
			tasks.sort_custom(_sort_tasks_by_priority)
		"Status":
			tasks.sort_custom(_sort_tasks_by_status)
		"Deadline":
			tasks.sort_custom(_sort_tasks_by_deadline)
		"Created":
			tasks.sort_custom(_sort_tasks_by_created_date)
	
	return tasks

func _sort_tasks_by_status(a: WorkplanTask, b: WorkplanTask) -> bool:
	"""Sort by status priority"""
	var status_priority = {
		"In Progress": 4,
		"To Do": 3,
		"Review": 2,
		"Done": 1
	}
	
	var a_priority = status_priority.get(a.status, 0)
	var b_priority = status_priority.get(b.status, 0)
	
	return a_priority > b_priority

func _sort_tasks_by_deadline(a: WorkplanTask, b: WorkplanTask) -> bool:
	"""Sort by deadline (earliest first)"""
	if a.deadline.is_empty() and b.deadline.is_empty():
		return false
	if a.deadline.is_empty():
		return false
	if b.deadline.is_empty():
		return true
	
	# Simple string comparison for now - could be enhanced with proper date parsing
	return a.deadline < b.deadline

func _sort_tasks_by_created_date(a: WorkplanTask, b: WorkplanTask) -> bool:
	"""Sort by created date (newest first)"""
	return a.created_date > b.created_date

# Performance tracking and enhanced statistics
func _track_task_performance(task: WorkplanTask, processing_time: float, success: bool):
	"""Track task processing performance"""
	performance_data.task_processing_times[task.title] = processing_time
	performance_data.total_processed += 1
	if success:
		performance_data.successful_completions += 1
	
	performance_data.agent_success_rate = float(performance_data.successful_completions) / float(performance_data.total_processed) * 100.0

func _get_average_processing_time() -> float:
	"""Calculate average task processing time"""
	if performance_data.task_processing_times.is_empty():
		return 0.0
	
	var total_time = 0.0
	for time in performance_data.task_processing_times.values():
		total_time += time
	
	return total_time / performance_data.task_processing_times.size()

func _detect_bottlenecks() -> Array[String]:
	"""Identify potential bottlenecks in the system"""
	var bottlenecks: Array[String] = []
	
	if not orchestrator or not orchestrator.workplan:
		return bottlenecks
	
	var tasks = orchestrator.workplan.get_all_tasks()
	var overdue_count = 0
	var stuck_in_progress = 0
	
	for task in tasks:
		if task.is_overdue():
			overdue_count += 1
		if task.status == "In Progress" and not task.start_date.is_empty():
			# Check if task has been in progress for more than a week
			var start_time = Time.get_datetime_dict_from_datetime_string(task.start_date, false)
			var _current_time = Time.get_datetime_dict_from_system()
			var start_unix = Time.get_unix_time_from_datetime_dict(start_time)
			var current_unix = Time.get_unix_time_from_system()
			var days_in_progress = (current_unix - start_unix) / (24 * 60 * 60)
			
			if days_in_progress > 7:
				stuck_in_progress += 1
	
	if overdue_count > 0:
		bottlenecks.append("⚠️ %d overdue tasks" % overdue_count)
	if stuck_in_progress > 0:
		bottlenecks.append("🔄 %d tasks stuck in progress" % stuck_in_progress)
	if performance_data.agent_success_rate < 80.0 and performance_data.total_processed > 5:
		bottlenecks.append("🤖 Low agent success rate: %.1f%%" % performance_data.agent_success_rate)
	
	return bottlenecks

func _on_content_viewer_task_selected(task: WorkplanTask):
	"""Handle task selection from content viewer"""
	print("MissionControl: Task selected in content viewer: ", task.title)
	# Stay in ContentViewer tab - no need to switch tabs when selecting a task

func _on_content_modified(task: WorkplanTask, new_content: String):
	"""Handle content modification in content viewer"""
	task.generated_content = new_content
	if orchestrator:
		orchestrator.update_task(task)
	print("MissionControl: Content modified for task: ", task.title)

func _update_content_viewer():
	"""Update content viewer with latest tasks"""
	var workplan_obj = ReadyMadeOrchestrator.workplan if ReadyMadeOrchestrator else null
	if not content_viewer or not workplan_obj:
		return
	
	if content_viewer.has_method("load_completed_tasks"):
		var all_tasks = workplan_obj.get_all_tasks()
		content_viewer.load_completed_tasks(all_tasks)

