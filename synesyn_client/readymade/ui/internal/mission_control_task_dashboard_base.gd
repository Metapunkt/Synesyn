extends "res://readymade/ui/internal/mission_control_dashboard_base.gd"
class_name MissionControlTaskDashboardBase

func _ready() -> void:
	# Add to group for easy debugging
	add_to_group("mission_control")
	
	# Wait for the orchestrator to load the data before we try to display it
	# Use a deferred call to ensure autoloads are ready
	call_deferred("_connect_to_orchestrator")
	
	_setup_ui()
	_setup_connections()
	_setup_refresh_timer()

func _connect_to_orchestrator():
	# Try to access the orchestrator directly
	if ReadyMadeOrchestrator:
		orchestrator = ReadyMadeOrchestrator
		ReadyMadeOrchestrator.workplan_loaded.connect(_on_workplan_loaded)
		print("MissionControl: ✅ Connected to ReadyMadeOrchestrator")
		
		# Connect to WorkplanManager
		workplan_manager = ReadyMadeOrchestrator.get_workplan_manager()
		if workplan_manager:
			workplan_manager.workplan_changed.connect(_on_workplan_changed)
			workplan_manager.workplan_list_updated.connect(_on_workplan_list_updated)
			print("MissionControl: ✅ Connected to WorkplanManager")
			_setup_workplan_ui()
		else:
			print("MissionControl: ⚠️ WorkplanManager not yet available")
			# Retry after a short delay
			await get_tree().create_timer(0.1).timeout
			_connect_to_orchestrator()
			return
		
		# Connect to ModeManager
		if ModeManager:
			ModeManager.mode_changed.connect(_on_mode_changed)
			print("MissionControl: ✅ Connected to ModeManager")
			_setup_mode_ui()
		else:
			print("MissionControl: ⚠️ ModeManager not available")
		
		# Connect to WorkflowManager
		if WorkflowManager:
			WorkflowManager.workflow_changed.connect(_on_workflow_changed)
			print("MissionControl: ✅ Connected to WorkflowManager")
			_setup_workflow_ui()
			# Apply initial workflow state
			_apply_workflow_ui_changes(WorkflowManager.get_current_workflow_name())
		else:
			print("MissionControl: ⚠️ WorkflowManager not available")
		
		# Connect to DocumentSessionManager
		if DocumentSessionManager:
			DocumentSessionManager.document_loaded.connect(_on_document_loaded)
			DocumentSessionManager.primary_document_changed.connect(_on_primary_document_changed)
			DocumentSessionManager.document_removed.connect(_on_document_removed)
			DocumentSessionManager.session_cleared.connect(_on_session_cleared)
			# Phase 4.5: Session management signals
			DocumentSessionManager.session_saved.connect(_on_session_saved)
			DocumentSessionManager.session_loaded.connect(_on_session_loaded_success)
			DocumentSessionManager.session_save_failed.connect(_on_session_save_failed)
			DocumentSessionManager.session_load_failed.connect(_on_session_load_failed)
			print("MissionControl: ✅ Connected to DocumentSessionManager")
			_setup_edit_session_ui()
		else:
			print("MissionControl: ⚠️ DocumentSessionManager not available")
		
		# Connect to SynTreeDocumentProcessor
		if SynTreeDocumentProcessor:
			SynTreeDocumentProcessor.document_analysis_completed.connect(_on_document_analysis_completed)
			SynTreeDocumentProcessor.document_analysis_failed.connect(_on_document_analysis_failed)
			SynTreeDocumentProcessor.syntree_processing_started.connect(_on_syntree_processing_started)
			print("MissionControl: ✅ Connected to SynTreeDocumentProcessor")
		else:
			print("MissionControl: ⚠️ SynTreeDocumentProcessor not available")
		
		# If orchestrator is already loaded, trigger the workplan loaded event
		if ReadyMadeOrchestrator.workplan:
			_on_workplan_loaded()
	else:
		push_error("MissionControlDashboard: ReadyMadeOrchestrator not found!")
		# Try again after a short delay
		await get_tree().create_timer(0.1).timeout
		_connect_to_orchestrator()

func _setup_keyboard_shortcuts():
	"""Setup keyboard shortcuts for common actions"""
	# Make sure we can receive input
	set_process_input(true)

func _is_text_input_focused() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null:
		return false
	return focused is LineEdit or focused is TextEdit or focused is CodeEdit

func _input(event):
	"""Handle keyboard shortcuts and global mouse events for drag-drop."""
	# --- Global Drag and Drop Handling ---
	if dragging_task:
		if event is InputEventMouseMotion:
			# Highlight cell under mouse during drag
			var _day = _get_day_under_mouse(event.position)
			# This logic can be expanded to show a "ghost" of the card etc.
			
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# Handle drop when mouse is released
			var drop_day = _get_day_under_mouse(event.position)
			if drop_day > 0:
				_handle_drop_on_day(drop_day)
			else:
				# If dropped outside a valid cell, just cancel the drag
				_stop_drag()
			get_viewport().set_input_as_handled()

	# --- Keyboard Shortcut Handling ---
	if event is InputEventKey and event.pressed:
		# Leave clipboard / editing shortcuts (Ctrl+V paste, Ctrl+A select-all)
		# for focused text fields such as Scratchpad and Brainstorming.
		if _is_text_input_focused():
			return

		# Check for Ctrl+key combinations
		if event.ctrl_pressed:
			match event.keycode:
				KEY_N:  # Ctrl+N - New Task
					_on_add_task_pressed()
					get_viewport().set_input_as_handled()
				KEY_R:  # Ctrl+R - Refresh
					_on_refresh_pressed()
					get_viewport().set_input_as_handled()
				KEY_S:  # Ctrl+S - Save Task List
					if not event.shift_pressed:
						_on_save_task_list_pressed()
					else:  # Ctrl+Shift+S - Save As
						_on_save_as_task_list_pressed()
					get_viewport().set_input_as_handled()
				KEY_O:  # Ctrl+O - Open Task List
					_on_open_task_list_pressed()
					get_viewport().set_input_as_handled()
				KEY_Q:  # Ctrl+Q - Stop Agent
					_on_stop_agent_pressed()
					get_viewport().set_input_as_handled()
				KEY_L:  # Ctrl+L - New Task List
					_on_new_task_list_pressed()
					get_viewport().set_input_as_handled()
				KEY_A:  # Ctrl+A - Toggle Select/Deselect All
					if main_tab_container.current_tab == 0:  # Only in Tasks tab
						_on_select_all_pressed()
						get_viewport().set_input_as_handled()
				KEY_V:  # Ctrl+Shift+V - View All Tasks (Ctrl+V is paste)
					if event.shift_pressed:
						_on_view_all_tasks_pressed()
						get_viewport().set_input_as_handled()
				KEY_W:  # Ctrl+W - Workplan Manager
					_on_workplan_manager_pressed()
					get_viewport().set_input_as_handled()
		
		# Check for Ctrl+Shift combinations
		if event.ctrl_pressed and event.shift_pressed:
			match event.keycode:
				KEY_R:  # Ctrl+Shift+R - Reset Workplan (for testing)
					if ReadyMadeOrchestrator:
						ReadyMadeOrchestrator.reset_workplan()
						print("MissionControl: 🔄 Workplan reset to defaults")
					get_viewport().set_input_as_handled()
		
		# Function keys
		match event.keycode:
			KEY_F5:  # F5 - Refresh
				_on_refresh_pressed()
				get_viewport().set_input_as_handled()

func _setup_ui():
	# Create task dialog
	task_dialog = preload("res://readymade/ui/task_dialog.tscn").instantiate()
	add_child(task_dialog)
	# Connect to the existing signals
	if task_dialog.has_signal("task_created"):
		task_dialog.task_created.connect(_on_task_saved)
	if task_dialog.has_signal("task_updated"):
		task_dialog.task_updated.connect(_on_task_saved)
	
	# Create and setup the calendar context menu
	calendar_context_menu = PopupMenu.new()
	add_child(calendar_context_menu)
	calendar_context_menu.id_pressed.connect(_on_calendar_context_menu_id_pressed)
	
	# Create the day overflow popup
	day_overflow_popup = PopupPanel.new()
	day_overflow_popup.name = "DayOverflowPopup"
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 200)
	overflow_tasks_container = VBoxContainer.new()
	overflow_tasks_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(overflow_tasks_container)
	margin.add_child(scroll)
	day_overflow_popup.add_child(margin)
	add_child(day_overflow_popup)
	
	# Setup filter options
	_setup_filter_options()
	
	# Setup content viewer
	if content_viewer:
		if content_viewer.has_signal("task_selected"):
			content_viewer.task_selected.connect(_on_content_viewer_task_selected)
		if content_viewer.has_signal("content_modified"):
			content_viewer.content_modified.connect(_on_content_modified)
	
	# Setup calendar
	_setup_calendar()
	
	# Setup task list management
	_setup_task_list_management()

func _setup_connections():
	# Quick action buttons
	new_task_button.pressed.connect(_on_add_task_pressed)
	start_agent_button.pressed.connect(_on_start_agent_pressed)
	stop_agent_button.pressed.connect(_on_stop_agent_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	
	# Task list management buttons
	new_task_list_button.pressed.connect(_on_new_task_list_pressed)
	open_task_list_button.pressed.connect(_on_open_task_list_pressed)
	open_task_list_button.tooltip_text = "Load task list - filters existing tasks or imports new ones if no matches found"
	view_all_tasks_button.pressed.connect(_on_view_all_tasks_pressed)
	save_task_list_button.pressed.connect(_on_save_task_list_pressed)
	save_as_task_list_button.pressed.connect(_on_save_as_task_list_pressed)
	select_all_button.pressed.connect(_on_select_all_pressed)
	
	# Workplan management UI
	workplan_selector.item_selected.connect(_on_workplan_selected)
	workplan_manager_button.pressed.connect(_on_workplan_manager_pressed)
	
	# Filter and search connections
	search_edit.text_changed.connect(_on_search_text_changed)
	status_filter.item_selected.connect(_on_status_filter_changed)
	priority_filter.item_selected.connect(_on_priority_filter_changed)
	sort_option.item_selected.connect(_on_sort_option_changed)
	
	# Calendar connections
	prev_month_btn.pressed.connect(_on_prev_month_pressed)
	next_month_btn.pressed.connect(_on_next_month_pressed)
	month_selector.item_selected.connect(_on_month_selected)
	year_selector.item_selected.connect(_on_year_selected)
	today_btn.pressed.connect(_on_today_pressed)

func _setup_refresh_timer():
	refresh_timer = Timer.new()
	add_child(refresh_timer)
	refresh_timer.wait_time = 5.0  # Refresh every 5 seconds
	refresh_timer.timeout.connect(_refresh_dashboard)
	refresh_timer.start()

func _on_workplan_loaded():
	# Access the actual workplan object, not the dictionary
	var workplan_obj = ReadyMadeOrchestrator.workplan
	workplan = ReadyMadeOrchestrator.get_all_tasks()  # Keep dictionary for compatibility
	
	_setup_filter_options()
	_update_task_list()
	_update_statistics()
	
	# Setup and update calendar
	_setup_calendar()
	_update_calendar()
	
	# Load completed tasks into content viewer
	var content_viewer_node = $HSplitContainer/MainTabContainer/ContentViewer/ContentMarginContainer/ContentViewer_tab
	print("MissionControl: Content viewer node found: ", content_viewer_node != null)
	if content_viewer_node and content_viewer_node.has_method("load_completed_tasks"):
		var all_tasks = workplan_obj.get_all_tasks()
		print("MissionControl: Got ", all_tasks.size(), " total tasks from workplan")
		# Load all tasks with generated content, not just completed ones
		var tasks_with_content = []
		for task in all_tasks:
			if not task.generated_content.is_empty():
				tasks_with_content.append(task)
				print("MissionControl: Task with content: ", task.title, " (status: ", task.status, ")")
		content_viewer_node.load_completed_tasks(tasks_with_content)
		print("MissionControl: Loaded ", tasks_with_content.size(), " tasks with content into content viewer")
	else:
		print("MissionControl: ⚠️ Content viewer not found or method missing")

func _refresh_dashboard():
	_update_task_list()
	_update_statistics()
	# The calendar refresh can be intensive, so maybe call it selectively
	_update_calendar()

func _update_statistics():
	"""Update the statistics display"""
	var workplan_obj = ReadyMadeOrchestrator.workplan if ReadyMadeOrchestrator else null
	
	if workplan_obj:
		var total_tasks = workplan_obj.get_total_tasks()
		var completed_tasks = workplan_obj.get_completed_tasks()
		var _in_progress_tasks = workplan_obj.get_in_progress_tasks()
		
		# Calculate due soon tasks (tasks with deadlines within 7 days)
		var due_soon_count = 0
		var all_tasks = workplan_obj.get_all_tasks()
		for task in all_tasks:
			if task.is_due_soon():
				due_soon_count += 1
		
		# Update labels
		if active_tasks_label:
			active_tasks_label.text = str(total_tasks - completed_tasks)
		if due_soon_label:
			due_soon_label.text = str(due_soon_count)
		if completed_label:
			completed_label.text = str(completed_tasks)
		
		print("MissionControl: Statistics updated - Total: %d, Active: %d, Due Soon: %d, Completed: %d" % 
			[total_tasks, total_tasks - completed_tasks, due_soon_count, completed_tasks])
	else:
		# Set default values if no workplan
		if active_tasks_label:
			active_tasks_label.text = "0"
		if due_soon_label:
			due_soon_label.text = "0"
		if completed_label:
			completed_label.text = "0"

func _update_task_list():
	"""Updates the task list display with current workplan data"""
	if not tasks_container:
		print("MissionControl: ⚠️ Tasks container not found!")
		return
	
	# Clear existing task cards and checkbox references
	for child in tasks_container.get_children():
		child.queue_free()
	task_checkboxes.clear()
	
	var tasks_to_display = []
	
	if is_filtered_view and not filtered_tasks.is_empty():
		# Show filtered tasks from task list
		tasks_to_display = filtered_tasks
		print("MissionControl: Displaying filtered view - ", tasks_to_display.size(), " tasks from task list")
	else:
		# Show all tasks from workplan
		if not workplan or workplan.is_empty():
			print("MissionControl: ⚠️ No workplan data available")
			return
	
	# Get all tasks from all months
	for month_name in workplan.keys():
		var month_tasks = workplan[month_name]
		if month_tasks is Array:
				tasks_to_display.append_array(month_tasks)
		print("MissionControl: Displaying full workplan - ", tasks_to_display.size(), " tasks")
	
	# Apply search filters and sorting (but not task list filtering)
	var search_filtered_tasks = _apply_search_filters(tasks_to_display)
	var sorted_tasks = _sort_tasks(search_filtered_tasks)
	
	print("MissionControl: Final display count: ", sorted_tasks.size(), " tasks")
	
	# Create task cards
	for task in sorted_tasks:
		_create_task_card(task)
	
	# Update button states since the displayed tasks may have changed
	_update_task_list_buttons()

func _sort_tasks_by_priority(a: WorkplanTask, b: WorkplanTask) -> bool:
	# Sort by priority (higher first), then by status
	if a.priority != b.priority:
		return a.priority > b.priority
	
	# Status priority: In Progress > To Do > Review > Done
	var status_priority = {
		"In Progress": 4,
		"To Do": 3,
		"Review": 2,
		"Done": 1
	}
	
	var a_priority = status_priority.get(a.status, 0)
	var b_priority = status_priority.get(b.status, 0)
	
	return a_priority > b_priority

func _create_task_card(task: WorkplanTask) -> Control:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 120)
	
	var vbox = VBoxContainer.new()
	card.add_child(vbox)
	
	# Header with checkbox, title and status
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	# Add checkbox for task selection
	var checkbox = CheckBox.new()
	checkbox.button_pressed = task in selected_tasks
	checkbox.toggled.connect(_on_task_checkbox_toggled.bind(task))
	checkbox.tooltip_text = "Select for task list operations"
	header.add_child(checkbox)
	
	# Store checkbox reference for later updates
	task_checkboxes[task] = checkbox
	
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
	
	# Add the card to the tasks container
	tasks_container.add_child(card)
	
	return card

func _on_add_task_pressed():
	print("MissionControl: Add new task button pressed")
	_show_task_template_selector()

func _show_task_template_selector():
	"""Show template selection dialog for mode-aware task creation"""
	if not TaskTemplateManager or not ModeManager:
		print("MissionControl: ⚠️ TaskTemplateManager or ModeManager not available, using default dialog")
		_show_default_task_dialog()
		return
	
	var templates = TaskTemplateManager.get_current_mode_templates()
	if templates.is_empty():
		print("MissionControl: ⚠️ No templates available for current mode, using default dialog")
		_show_default_task_dialog()
		return
	
	var dialog = AcceptDialog.new()
	dialog.title = "Select Task Template"
	dialog.size = Vector2(500, 400)
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	# Mode indicator
	var current_mode = ModeManager.get_current_config()
	var mode_label = Label.new()
	mode_label.text = "Creating task for: " + current_mode.icon + " " + current_mode.name
	mode_label.theme_type_variation = "HeaderMedium"
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(mode_label)
	
	vbox.add_child(HSeparator.new())
	
	# Template selection
	var template_label = Label.new()
	template_label.text = "Choose a template:"
	vbox.add_child(template_label)
	
	var template_list = ItemList.new()
	template_list.custom_minimum_size = Vector2(0, 250)
	template_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Populate template list
	for template in templates:
		template_list.add_item(template.name)
		template_list.set_item_tooltip(template_list.get_item_count() - 1, template.description)
		template_list.set_item_metadata(template_list.get_item_count() - 1, template.id)
	
	vbox.add_child(template_list)
	
	# Action buttons
	var button_container = HBoxContainer.new()
	vbox.add_child(button_container)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(func(): dialog.queue_free())
	button_container.add_child(cancel_button)
	
	var custom_button = Button.new()
	custom_button.text = "Custom Task"
	custom_button.pressed.connect(func(): 
		dialog.queue_free()
		_show_default_task_dialog()
	)
	button_container.add_child(custom_button)
	
	var create_button = Button.new()
	create_button.text = "Create from Template"
	create_button.pressed.connect(func():
		var selected_items = template_list.get_selected_items()
		if selected_items.is_empty():
			_show_error_dialog("Please select a template.")
			return
		
		var template_id = template_list.get_item_metadata(selected_items[0])
		dialog.queue_free()
		_create_task_from_template(template_id)
	)
	button_container.add_child(create_button)
	
	# Double-click to create
	template_list.item_activated.connect(func(index: int):
		var template_id = template_list.get_item_metadata(index)
		dialog.queue_free()
		_create_task_from_template(template_id)
	)
	
	add_child(dialog)
	dialog.popup_centered()
	print("MissionControl: Template selector opened with ", templates.size(), " templates")

func _show_default_task_dialog():
	"""Show the default task creation dialog"""
	if task_dialog and task_dialog.has_method("show_add_dialog"):
		task_dialog.show_add_dialog()
		print("MissionControl: Opening default task creation dialog")
	else:
		print("MissionControl: ⚠️ Task dialog not available or missing show_add_dialog method")

func _create_task_from_template(template_id: String):
	"""Create a task from a template and show customization dialog"""
	if not TaskTemplateManager:
		return
	
	var task = TaskTemplateManager.create_task_from_template(template_id)
	if not task:
		_show_error_dialog("Failed to create task from template.")
		return
	
	print("MissionControl: Created task from template: ", task.title)
	
	# Show task dialog with pre-filled template data for customization
	if task_dialog and task_dialog.has_method("show_edit_dialog"):
		task_dialog.show_edit_dialog(task)
		print("MissionControl: Opening task customization dialog")
	else:
		# Fallback: add task directly without customization
		_add_task_directly(task)

func _add_task_directly(task: WorkplanTask):
	"""Add a task directly to the workplan without dialog"""
	if not orchestrator:
		return
	
	orchestrator.add_task_to_month("Month 1", task)
	print("MissionControl: ✅ Task added directly: ", task.title)
	_refresh_dashboard()

func _show_error_dialog(message: String):
	"""Show a simple error dialog"""
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.title = "Error"
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

func _show_info_dialog(message: String):
	"""Show a simple info dialog"""
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.title = "Information"
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

func _on_refresh_pressed():
	_refresh_dashboard()

func _on_start_agent_pressed():
	print("Start agent batch pressed.")
	if Engine.has_singleton("ReadyMadeOrchestrator"):
		var orchestrator_singleton = ReadyMadeOrchestrator
		if orchestrator_singleton.a1_agent:
			# Start batch processing of all available tasks
			if orchestrator_singleton.a1_agent.has_method("start_batch_processing"):
				orchestrator_singleton.a1_agent.start_batch_processing()
				print("MissionControl: 🚀 Agent batch processing started")
			elif orchestrator_singleton.a1_agent.has_method("execute_all_tasks"):
				orchestrator_singleton.a1_agent.execute_all_tasks()
				print("MissionControl: 🚀 Agent processing all tasks")
			else:
				# Fallback: continuously execute tasks until queue is empty
				orchestrator_singleton.a1_agent.execute_next_task()
				print("MissionControl: 🚀 Agent started (single task mode - batch processing not available)")
		else:
			print("MissionControl: ⚠️ A1 Agent not found")
	else:
		print("MissionControl: ⚠️ ReadyMadeOrchestrator not found")

func _on_stop_agent_pressed():
	print("Stop agent batch pressed.")
	if Engine.has_singleton("ReadyMadeOrchestrator"):
		var orchestrator_singleton = ReadyMadeOrchestrator
		if orchestrator_singleton.a1_agent:
			orchestrator_singleton.a1_agent.stop_processing()
			print("MissionControl: ⏹️ Agent batch processing stopped")
		else:
			print("MissionControl: ⚠️ A1 Agent not found")
	else:
		print("MissionControl: ⚠️ ReadyMadeOrchestrator not found")

func _on_task_saved(task: WorkplanTask):
	if not orchestrator:
		return
	
	var workplan_obj = orchestrator.workplan
	if not workplan_obj:
		return
	
	# Check if task already exists in workplan
	var all_tasks = workplan_obj.get_all_tasks()
	var task_exists = false
	for existing_task in all_tasks:
		if existing_task == task:
			task_exists = true
			break
	
	if not task_exists:
		# Add to first month if new task
		orchestrator.add_task_to_month("Month 1", task)
		print("MissionControl: ✅ New task added: ", task.core_idea)
	else:
		orchestrator.update_task(task)
		print("MissionControl: ✏️ Task updated: ", task.core_idea)
	
	_refresh_dashboard()

func _on_edit_task_pressed(task: WorkplanTask):
	"""Handle edit task button press"""
	task_dialog.show_edit_dialog(task)

func _on_start_task_pressed(task: WorkplanTask):
	print("MissionControl: 🎯 Individual task start button pressed for: ", task.title)
	
	# Check orchestrator availability
	if not orchestrator:
		print("MissionControl: ❌ Orchestrator not available!")
		return
	
	# First mark the task as started
	task.start_task()
	orchestrator.update_task(task)
	print("MissionControl: ✅ Task status updated to: ", task.status)
	
	# Process this specific task with the AI if agent is available
	var agent = orchestrator.a1_agent
	print("MissionControl: Agent reference: ", agent != null, " (", agent.get_class() if agent else "null", ")")
	
	if agent and agent.has_method("process_specific_task"):
		print("MissionControl: 🚀 Calling process_specific_task()...")
		agent.process_specific_task(task)
		print("MissionControl: ✅ AI processing started for task: ", task.title)
	elif agent and agent.has_method("prioritize_task"):
		# Fallback: add task to front of queue and start agent
		print("MissionControl: 🔄 Using fallback: prioritize_task() + execute_next_task()...")
		agent.prioritize_task(task)
		agent.execute_next_task()
		print("MissionControl: ✅ Task prioritized and agent started for: ", task.title)
	elif agent:
		print("MissionControl: ⚠️ Agent found but missing required methods!")
		print("  - has process_specific_task: ", agent.has_method("process_specific_task"))
		print("  - has prioritize_task: ", agent.has_method("prioritize_task"))
		print("  - has execute_next_task: ", agent.has_method("execute_next_task"))
	else:
		print("MissionControl: ❌ No agent available to process task: ", task.title)
		print("  - Orchestrator exists: ", orchestrator != null)
		print("  - Agent reference: ", orchestrator.a1_agent if orchestrator else "N/A")
	
	_refresh_dashboard()

func _on_review_task_pressed(task: WorkplanTask):
	task.send_for_review()
	orchestrator.update_task(task)
	_refresh_dashboard()

func _on_complete_task_pressed(task: WorkplanTask):
	task.complete_task()
	orchestrator.update_task(task)
	_refresh_dashboard()

func _on_rerun_task_pressed(task: WorkplanTask):
	# Reset task to "To Do" status for reprocessing
	task.status = "To Do"
	task.start_date = ""
	task.completion_date = ""
	task.generated_content = ""
	orchestrator.update_task(task)
	_refresh_dashboard()
	print("MissionControl: 🔄 Task reset for rerun: ", task.core_idea)

func _on_delete_task_pressed(task: WorkplanTask):
	"""Handle deleting a task from a card"""
	print("MissionControl: Deleting task: ", task.core_idea)
	if orchestrator:
		# Assuming tasks are stored in "Month 1" for now. This may need to be more robust.
		orchestrator.remove_task_from_month("Month 1", task)
	_refresh_dashboard()

# Task List Management Functions
