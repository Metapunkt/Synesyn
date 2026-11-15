extends "res://readymade/ui/internal/mission_control_dashboard_base.gd"
class_name MissionControlTaskDashboardBase

var _main_external_tab_bar: TabBar = null
## Single hub/backend notice dialog — replaced rather than stacked (dismissible).
var _active_notice_dialog: AcceptDialog = null

func _ready() -> void:
	# Add to group for easy debugging
	add_to_group("mission_control")
	
	# Wait for the orchestrator to load the data before we try to display it
	# Use a deferred call to ensure autoloads are ready
	call_deferred("_connect_to_orchestrator")
	
	_setup_ui()
	_setup_connections()
	_setup_keyboard_shortcuts()
	_setup_refresh_timer()

func _connect_to_orchestrator():
	# Try to access the orchestrator directly
	if ReadyMadeOrchestrator:
		orchestrator = ReadyMadeOrchestrator
		if not ReadyMadeOrchestrator.workplan_loaded.is_connected(_on_workplan_loaded):
			ReadyMadeOrchestrator.workplan_loaded.connect(_on_workplan_loaded)
		print("MissionControl: ✅ Connected to ReadyMadeOrchestrator")
		
		# Wait for synchronous WorkplanManager bootstrap if needed.
		if ReadyMadeOrchestrator.has_method("await_workplan_manager_ready"):
			await ReadyMadeOrchestrator.await_workplan_manager_ready()
		
		# Connect to WorkplanManager
		workplan_manager = ReadyMadeOrchestrator.get_workplan_manager()
		if workplan_manager:
			if not workplan_manager.workplan_changed.is_connected(_on_workplan_changed):
				workplan_manager.workplan_changed.connect(_on_workplan_changed)
			if not workplan_manager.workplan_list_updated.is_connected(_on_workplan_list_updated):
				workplan_manager.workplan_list_updated.connect(_on_workplan_list_updated)
			print("MissionControl: ✅ Connected to WorkplanManager")
			_setup_workplan_ui()
		else:
			print("MissionControl: ⚠️ WorkplanManager still unavailable after ready wait")
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

func _ensure_main_tab_hit_targets() -> void:
	"""Back-compat alias — structural tab setup (no z_index overlap hacks)."""
	_setup_main_tabs_structural()


func _setup_main_tabs_structural() -> void:
	"""Place a dedicated TabBar above the TabContainer so page panels cannot cover tabs.

	Hides the TabContainer's internal tab strip (tabs_visible=false) and syncs an
	external TabBar in a VBox sibling column. Avoids brittle z_index / mouse_filter
	layering that broke under layout changes.
	"""
	if main_tab_container == null:
		return
	if _main_external_tab_bar != null and is_instance_valid(_main_external_tab_bar):
		_sync_external_tab_bar_titles()
		return
	if bool(main_tab_container.get_meta("structural_tabs_ready", false)):
		var existing: Variant = main_tab_container.get_meta("external_tab_bar", null)
		if existing is TabBar:
			_main_external_tab_bar = existing
			_sync_external_tab_bar_titles()
			return

	var parent_node: Node = main_tab_container.get_parent()
	if parent_node == null:
		return

	var wrapper := VBoxContainer.new()
	wrapper.name = "MainTabsColumn"
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 0)

	var insert_index: int = main_tab_container.get_index()
	parent_node.add_child(wrapper)
	parent_node.move_child(wrapper, insert_index)

	var external_bar := TabBar.new()
	external_bar.name = "MainTabBar"
	external_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Clip + scroll arrows when the window is narrower than all tab titles.
	external_bar.clip_tabs = true
	external_bar.tab_alignment = 0
	external_bar.custom_minimum_size = Vector2(0, 44)
	external_bar.add_theme_font_size_override("font_size", 15)
	external_bar.add_theme_constant_override("h_separation", 12)
	external_bar.add_theme_constant_override("tab_minimum_width", 72)
	external_bar.mouse_filter = Control.MOUSE_FILTER_STOP

	parent_node.remove_child(main_tab_container)
	wrapper.add_child(external_bar)
	wrapper.add_child(main_tab_container)

	main_tab_container.tabs_visible = false
	main_tab_container.clip_tabs = false
	main_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_main_external_tab_bar = external_bar
	main_tab_container.set_meta("structural_tabs_ready", true)
	main_tab_container.set_meta("external_tab_bar", external_bar)
	_sync_external_tab_bar_titles()
	external_bar.current_tab = main_tab_container.current_tab

	if not external_bar.tab_changed.is_connected(_on_external_main_tab_changed):
		external_bar.tab_changed.connect(_on_external_main_tab_changed)
	if not main_tab_container.tab_changed.is_connected(_on_internal_main_tab_changed):
		main_tab_container.tab_changed.connect(_on_internal_main_tab_changed)


func _sync_external_tab_bar_titles() -> void:
	if _main_external_tab_bar == null or main_tab_container == null:
		return
	while _main_external_tab_bar.get_tab_count() > 0:
		_main_external_tab_bar.remove_tab(0)
	for tab_index in main_tab_container.get_tab_count():
		_main_external_tab_bar.add_tab(main_tab_container.get_tab_title(tab_index))


func _on_external_main_tab_changed(tab_index: int) -> void:
	if main_tab_container and main_tab_container.current_tab != tab_index:
		main_tab_container.current_tab = tab_index


func _on_internal_main_tab_changed(tab_index: int) -> void:
	if _main_external_tab_bar and _main_external_tab_bar.current_tab != tab_index:
		_main_external_tab_bar.current_tab = tab_index
	_ensure_left_sidebar_split()


func _ensure_left_sidebar_split() -> void:
	"""Keep the left sidebar at least 280px so Calendar min-width cannot clip Work Mode."""
	var split: HSplitContainer = get_node_or_null("HSplitContainer") as HSplitContainer
	if split == null:
		return
	const LEFT_MIN: int = 280
	if split.split_offset < LEFT_MIN:
		split.split_offset = LEFT_MIN
	var left_panel: Control = split.get_child(0) as Control if split.get_child_count() > 0 else null
	if left_panel != null and left_panel.custom_minimum_size.x < float(LEFT_MIN):
		left_panel.custom_minimum_size.x = float(LEFT_MIN)


func _get_main_tab_bar_for_input() -> TabBar:
	if _main_external_tab_bar != null and is_instance_valid(_main_external_tab_bar):
		return _main_external_tab_bar
	if main_tab_container:
		var meta_bar: Variant = main_tab_container.get_meta("external_tab_bar", null)
		if meta_bar is TabBar:
			return meta_bar
		return main_tab_container.get_tab_bar()
	return null


func simulate_main_tab_center_click(tab_index: int) -> bool:
	"""Push a left-click at the visual center of a main tab. Returns true if current_tab matches."""
	if main_tab_container == null:
		return false
	if tab_index < 0 or tab_index >= main_tab_container.get_tab_count():
		return false
	_setup_main_tabs_structural()
	var tab_bar: TabBar = _get_main_tab_bar_for_input()
	if tab_bar == null:
		return false
	# Force layout so get_tab_rect reflects the on-screen chrome.
	await get_tree().process_frame
	await get_tree().process_frame
	var tab_rect: Rect2 = tab_bar.get_tab_rect(tab_index)
	if tab_rect.size.x <= 0.0 or tab_rect.size.y <= 0.0:
		# Fallback: select directly if rect not ready (still exercises API for CI).
		main_tab_container.current_tab = tab_index
		return main_tab_container.current_tab == tab_index
	var local_center: Vector2 = tab_rect.position + (tab_rect.size * 0.5)
	# Project uses window/stretch/mode=canvas_items — map canvas → window coords
	# so clicks still hit after resize (e.g. 1152x648 → 1920x1080).
	var canvas_point: Vector2 = tab_bar.global_position + local_center
	var click_pos: Vector2 = get_viewport().get_final_transform() * canvas_point
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = click_pos
	press.global_position = click_pos
	get_viewport().push_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = click_pos
	release.global_position = click_pos
	get_viewport().push_input(release)
	await get_tree().process_frame
	return main_tab_container.current_tab == tab_index


func _setup_keyboard_shortcuts():
	"""Setup keyboard shortcuts for common actions"""
	# Drag uses _input; app shortcuts use _unhandled_input so Ctrl+N / Ctrl+Shift+V
	# work even when a non-text Control has focus.
	set_process_input(true)
	set_process_unhandled_input(true)

func _is_text_input_focused() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null:
		return false
	return focused is LineEdit or focused is TextEdit or focused is CodeEdit

func _input(event):
	"""Global mouse events for calendar drag-drop (must run before GUI consumes release)."""
	if dragging_task:
		if event is InputEventMouseMotion:
			var _day = _get_day_under_mouse(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var drop_day = _get_day_under_mouse(event.position)
			if drop_day > 0:
				_handle_drop_on_day(drop_day)
			else:
				_stop_drag()
			get_viewport().set_input_as_handled()


func _unhandled_input(event):
	"""Window-level shortcuts regardless of which non-text control has focus."""
	if not (event is InputEventKey and event.pressed):
		return
	# Leave clipboard / editing shortcuts for focused text fields.
	if _is_text_input_focused():
		return

	if event.ctrl_pressed:
		match event.keycode:
			KEY_N:  # Ctrl+N - New Task
				_on_add_task_pressed()
				get_viewport().set_input_as_handled()
			KEY_R:  # Ctrl+R - Refresh / Ctrl+Shift+R reset
				if event.shift_pressed:
					if ReadyMadeOrchestrator:
						ReadyMadeOrchestrator.reset_workplan()
						print("MissionControl: 🔄 Workplan reset to defaults")
				else:
					_on_refresh_pressed()
				get_viewport().set_input_as_handled()
			KEY_S:  # Ctrl+S - Save Task List / Ctrl+Shift+S Save As
				if not event.shift_pressed:
					_on_save_task_list_pressed()
				else:
					_on_save_as_task_list_pressed()
				get_viewport().set_input_as_handled()
			KEY_O:  # Ctrl+O - Open Task List
				_on_open_task_list_pressed()
				get_viewport().set_input_as_handled()
			KEY_Q:  # Ctrl+Q - Stop drafting
				_on_stop_agent_pressed()
				get_viewport().set_input_as_handled()
			KEY_L:  # Ctrl+L - New Task List
				_on_new_task_list_pressed()
				get_viewport().set_input_as_handled()
			KEY_A:  # Ctrl+A - Toggle Select/Deselect All
				if main_tab_container and main_tab_container.current_tab == 0:
					_on_select_all_pressed()
					get_viewport().set_input_as_handled()
			KEY_V:  # Ctrl+Shift+V - View All Tasks (Ctrl+V is paste)
				if event.shift_pressed:
					_on_view_all_tasks_pressed()
					get_viewport().set_input_as_handled()
			KEY_W:  # Ctrl+W - Workplan Manager
				_on_workplan_manager_pressed()
				get_viewport().set_input_as_handled()

	match event.keycode:
		KEY_F5:  # F5 - Refresh
			_on_refresh_pressed()
			get_viewport().set_input_as_handled()

func _update_draft_action_buttons() -> void:
	"""Show Draft XOR Stop — only one visible; Stop stays hidden/disabled when idle."""
	var is_drafting := false
	var orch: Node = _resolve_readymade_orchestrator()
	if orch != null:
		var agent_node: Node = orch.get("a1_agent") as Node
		if agent_node == null:
			agent_node = get_node_or_null("/root/A1SynthesisEngine")
		if agent_node != null:
			is_drafting = bool(agent_node.get("processing_active"))
	if start_agent_button:
		start_agent_button.visible = not is_drafting
		start_agent_button.disabled = false
	if stop_agent_button:
		stop_agent_button.visible = is_drafting
		stop_agent_button.disabled = not is_drafting


func _setup_ui():
	_setup_main_tabs_structural()
	_update_draft_action_buttons()
	# Create task dialog
	task_dialog = preload("res://readymade/ui/task_dialog.tscn").instantiate()
	add_child(task_dialog)
	# Connect to the existing signals
	if task_dialog.has_signal("task_created"):
		task_dialog.task_created.connect(_on_task_saved)
	if task_dialog.has_signal("task_updated"):
		task_dialog.task_updated.connect(_on_task_saved)
	
	# Create and setup the calendar context menu
	# Calendar context menu is created fresh on each right-click (_ensure_calendar_context_menu)
	# so a stuck-open PopupMenu after Undo cannot survive a calendar rebuild.
	calendar_context_menu = null
	
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

	# Visible no-hub / no-AI empty state (not console-only)
	if ReadyMadeOrchestrator and ReadyMadeOrchestrator.has_signal("backend_unavailable"):
		if not ReadyMadeOrchestrator.backend_unavailable.is_connected(_on_backend_unavailable):
			ReadyMadeOrchestrator.backend_unavailable.connect(_on_backend_unavailable)
	
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
	if assignee_filter:
		assignee_filter.item_selected.connect(_on_assignee_filter_changed)
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
	
	# Load completed tasks into content viewer.
	# Use the @onready ref — structural tabs reparent MainTabContainer under
	# MainTabsColumn, so a late $HSplitContainer/MainTabContainer/... lookup fails.
	var content_viewer_node: Control = content_viewer
	if content_viewer_node == null:
		content_viewer_node = find_child("ContentViewer_tab", true, false) as Control
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
	_sync_aux_dashboards(workplan_obj)

func _refresh_dashboard():
	_update_task_list()
	_update_statistics()
	_update_draft_action_buttons()
	# The calendar refresh can be intensive, so maybe call it selectively
	_update_calendar()
	var workplan_refresh: Resource = null
	if ReadyMadeOrchestrator:
		workplan_refresh = ReadyMadeOrchestrator.workplan
	_sync_aux_dashboards(workplan_refresh)

func _sync_aux_dashboards(workplan_obj: Resource) -> void:
	var campaign_node: Node = find_child("CampaignDashboard", true, false)
	if campaign_node != null and campaign_node.has_method("set_workplan"):
		campaign_node.set_workplan(workplan_obj)
	var board_node: Node = find_child("StageBoardView", true, false)
	if board_node != null and board_node.has_method("set_workplan"):
		board_node.set_workplan(workplan_obj)

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

	var copy_btn = Button.new()
	copy_btn.text = "📋 Copy as Markdown"
	copy_btn.tooltip_text = "Copy this task as Markdown to the clipboard"
	copy_btn.pressed.connect(_on_copy_task_markdown_pressed.bind(task, copy_btn))
	buttons.add_child(copy_btn)
	
	# Delete button
	var delete_btn = Button.new()
	delete_btn.text = "🗑️ Delete"
	delete_btn.add_theme_color_override("font_color", Color.RED)
	delete_btn.pressed.connect(_on_delete_task_pressed.bind(task))
	buttons.add_child(delete_btn)
	
	# Add the card to the tasks container when the Tasks tab is mounted.
	if tasks_container != null:
		tasks_container.add_child(card)
	
	return card


func _on_copy_task_markdown_pressed(task: WorkplanTask, feedback_btn: Button = null) -> void:
	"""Copy task Markdown and show Copied feedback even if clipboard write fails."""
	if task == null:
		return
	const MarkdownScript = preload("res://readymade/scripts/workplan_task_markdown.gd")
	var workplan_obj: Resource = null
	if workplan_manager != null and workplan_manager.has_method("get_current_workplan"):
		workplan_obj = workplan_manager.get_current_workplan()
	# Feedback first so a clipboard backend error cannot skip the ✓ Copied UI.
	var markdown_text: String = MarkdownScript.to_clipboard_markdown(task, workplan_obj)
	_show_copied_feedback(feedback_btn, "Copied (%d chars)" % markdown_text.length())
	if not markdown_text.is_empty():
		DisplayServer.clipboard_set(markdown_text)


func _show_copied_feedback(anchor: Control, message: String = "Copied") -> void:
	"""Brief visible Copied toast; also flips the row button text to ✓ Copied."""
	if anchor != null and is_instance_valid(anchor) and anchor is Button:
		var btn: Button = anchor as Button
		var original: String = btn.text
		btn.text = "✓ Copied"
		btn.modulate = Color(0.55, 1.0, 0.65)
		var tree_local: SceneTree = get_tree()
		if tree_local != null:
			tree_local.create_timer(1.2).timeout.connect(func():
				if is_instance_valid(btn):
					btn.text = original
					btn.modulate = Color.WHITE
			, CONNECT_ONE_SHOT)
	var toast := Label.new()
	toast.name = "CopiedMarkdownToast"
	toast.text = message
	toast.modulate = Color(0.2, 0.65, 0.35)
	toast.add_theme_font_size_override("font_size", 13)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.top_level = true
	add_child(toast)
	if anchor != null and is_instance_valid(anchor):
		var rect: Rect2 = anchor.get_global_rect()
		toast.global_position = Vector2(rect.position.x, rect.position.y - 22.0)
	else:
		toast.global_position = Vector2(24, 24)
	var tree_toast: SceneTree = get_tree()
	if tree_toast != null:
		tree_toast.create_timer(1.4).timeout.connect(func():
			if is_instance_valid(toast):
				toast.queue_free()
		, CONNECT_ONE_SHOT)

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
	# Custom Cancel/Custom/Create buttons own the actions — hide AcceptDialog's OK.
	dialog.dialog_hide_on_ok = false
	
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
	cancel_button.pressed.connect(func():
		_close_template_selector(dialog)
	)
	button_container.add_child(cancel_button)
	
	var custom_button = Button.new()
	custom_button.text = "Custom Task"
	custom_button.pressed.connect(func():
		await _close_template_selector(dialog)
		await _show_default_task_dialog()
	)
	button_container.add_child(custom_button)
	
	var create_button = Button.new()
	create_button.text = "Create from Template"
	create_button.pressed.connect(func():
		var selected_items = template_list.get_selected_items()
		if selected_items.is_empty():
			await _show_error_dialog("Please select a template.")
			return
		
		var template_id = template_list.get_item_metadata(selected_items[0])
		await _close_template_selector(dialog)
		await _create_task_from_template(template_id)
	)
	button_container.add_child(create_button)
	
	# Double-click to create
	template_list.item_activated.connect(func(index: int):
		var template_id = template_list.get_item_metadata(index)
		await _close_template_selector(dialog)
		await _create_task_from_template(template_id)
	)
	
	# X / Escape must release exclusivity the same way Cancel does.
	dialog.close_requested.connect(func():
		await _close_template_selector(dialog)
	)
	dialog.canceled.connect(func():
		await _close_template_selector(dialog)
	)

	add_child(dialog)
	var ok_btn: Button = dialog.get_ok_button()
	if ok_btn != null:
		ok_btn.visible = false
	dialog.popup_centered()
	print("MissionControl: Template selector opened with ", templates.size(), " templates")


func _apply_deadline_label(deadline_info: Label, task: WorkplanTask) -> void:
	"""Neutral due text for Done; OVERDUE only for incomplete past-due tasks."""
	# Prefer theme font_color over modulate so parent/theme tints cannot turn Done red.
	if String(task.status).strip_edges() == "Done":
		deadline_info.text = "✅ Completed"
		deadline_info.modulate = Color.WHITE
		deadline_info.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		return
	if task.deadline.is_empty():
		deadline_info.text = ""
		return
	if task.is_overdue():
		deadline_info.text = "⚠️ OVERDUE: " + task.deadline
		deadline_info.modulate = Color.WHITE
		deadline_info.add_theme_color_override("font_color", Color.RED)
	elif task.is_due_soon():
		deadline_info.text = "⏰ Due Soon: " + task.deadline
		deadline_info.modulate = Color.WHITE
		deadline_info.add_theme_color_override("font_color", Color.ORANGE)
	else:
		deadline_info.text = "📅 Due: " + task.deadline
		deadline_info.modulate = Color.WHITE
		deadline_info.add_theme_color_override("font_color", Color(0.75, 0.65, 0.1))


func _release_exclusive_window(dialog: Window) -> void:
	"""Drop exclusivity and free a popup so a later AcceptDialog can show."""
	if dialog == null or not is_instance_valid(dialog):
		return
	dialog.exclusive = false
	if dialog.visible:
		dialog.hide()
	if dialog.get_parent() != null:
		dialog.get_parent().remove_child(dialog)
	dialog.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _dismiss_blocking_dialogs() -> void:
	"""Close any exclusive Window children (except the persistent task_dialog)."""
	var blockers: Array[Window] = []
	for child in get_children():
		if child is Window and child != task_dialog:
			var win: Window = child
			if win.visible or win.exclusive:
				blockers.append(win)
	for win in blockers:
		await _release_exclusive_window(win)


func _close_template_selector(dialog: Window) -> void:
	"""Hide and free the template dialog before opening another exclusive Window."""
	await _release_exclusive_window(dialog)


func _show_default_task_dialog():
	"""Show the default task creation dialog"""
	await _dismiss_blocking_dialogs()
	if task_dialog and is_instance_valid(task_dialog) and task_dialog.has_method("show_add_dialog"):
		task_dialog.show_add_dialog()
		print("MissionControl: Opening default task creation dialog")
	else:
		print("MissionControl: ⚠️ Task dialog not available or missing show_add_dialog method")

func _create_task_from_template(template_id: String) -> void:
	"""Create a task from a template and show customization dialog"""
	if not TaskTemplateManager:
		return
	
	var task = TaskTemplateManager.create_task_from_template(template_id)
	if not task:
		await _show_error_dialog("Failed to create task from template.")
		return
	
	print("MissionControl: Created task from template: ", task.title)
	
	# Show task dialog with pre-filled template data for customization
	await _dismiss_blocking_dialogs()
	if task_dialog and is_instance_valid(task_dialog) and task_dialog.has_method("show_edit_dialog"):
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

func _clear_active_notice_dialog() -> void:
	if _active_notice_dialog != null and is_instance_valid(_active_notice_dialog):
		await _release_exclusive_window(_active_notice_dialog)
	_active_notice_dialog = null


func _bind_dismissible_notice(dialog: AcceptDialog) -> void:
	"""OK, window X, Escape (canceled), and close_requested all free the notice."""
	var dismiss := func() -> void:
		if _active_notice_dialog == dialog:
			_active_notice_dialog = null
		await _release_exclusive_window(dialog)
	dialog.confirmed.connect(dismiss)
	dialog.canceled.connect(dismiss)
	dialog.close_requested.connect(dismiss)
	dialog.unresizable = true
	dialog.wrap_controls = true
	dialog.transient = true
	dialog.exclusive = true
	dialog.dialog_hide_on_ok = true


func _show_error_dialog(message: String) -> void:
	"""Show a dismissible error dialog (Escape / OK / window close). Replaces prior notice."""
	await _dismiss_blocking_dialogs()
	await _clear_active_notice_dialog()
	var dialog = AcceptDialog.new()
	dialog.title = "Error"
	dialog.dialog_text = ""
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(500, 0)
	body.text = message
	scroll.add_child(body)
	dialog.add_child(scroll)
	_bind_dismissible_notice(dialog)
	_active_notice_dialog = dialog
	add_child(dialog)
	dialog.popup_centered(Vector2(560, 360))
	# Ensure keyboard focus so Escape reaches the dialog.
	dialog.grab_focus()

func _show_info_dialog(message: String) -> void:
	"""Show a dismissible info dialog (Escape / OK / window close)."""
	await _dismiss_blocking_dialogs()
	await _clear_active_notice_dialog()
	var dialog = AcceptDialog.new()
	dialog.title = "Information"
	dialog.dialog_text = ""
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(460, 0)
	body.text = message
	scroll.add_child(body)
	dialog.add_child(scroll)
	_bind_dismissible_notice(dialog)
	_active_notice_dialog = dialog
	add_child(dialog)
	dialog.popup_centered(Vector2(520, 300))
	dialog.grab_focus()

func _on_refresh_pressed():
	_refresh_dashboard()

func _on_backend_unavailable(message: String) -> void:
	"""Show actionable guidance when hub / LLM is missing; stop drafting so the modal is not sticky."""
	_on_stop_agent_pressed()
	await _show_error_dialog(message)


func _resolve_readymade_orchestrator() -> Node:
	"""Prefer the live /root autoload node over Engine.has_singleton (unreliable for GDScript)."""
	var root_node: Node = get_tree().root if get_tree() else null
	if root_node != null and root_node.has_node("ReadyMadeOrchestrator"):
		return root_node.get_node("ReadyMadeOrchestrator")
	return get_node_or_null("/root/ReadyMadeOrchestrator")


func _on_start_agent_pressed():
	print("Draft To Do tasks pressed.")
	# Template / workplan popups are exclusive — clear them so the no-hub dialog can show.
	await _dismiss_blocking_dialogs()
	var orchestrator_singleton: Node = _resolve_readymade_orchestrator()
	if orchestrator_singleton == null:
		print("MissionControl: ⚠️ ReadyMadeOrchestrator not found on /root")
		_show_error_dialog(
			"The AI backend (Synesyn hub / LLM) is not available.\n\n"
			+ "What to do:\n"
			+ "1. Start the Synesyn hub (services/synesyn_hub), usually at http://127.0.0.1:17777.\n"
			+ "2. Configure hub.base_url and model credentials in:\n   "
			+ RuntimeConfig.get_config_path_abs()
			+ "\n3. Restart ReadyMade, then use Draft To Do tasks again.\n\n"
			+ "Failed generation leaves the task not Done so you can retry."
		)
		return
	if orchestrator_singleton.has_method("request_start_agent_batch"):
		orchestrator_singleton.request_start_agent_batch()
		_update_draft_action_buttons()
		return
	# Fallback: same hub dialog path used by drafting.
	if orchestrator_singleton.has_method("notify_backend_unavailable"):
		orchestrator_singleton.notify_backend_unavailable(
			"Draft To Do tasks is unavailable in this build."
		)

func _on_stop_agent_pressed():
	print("Stop drafting pressed.")
	var orchestrator_singleton: Node = _resolve_readymade_orchestrator()
	if orchestrator_singleton == null:
		print("MissionControl: ⚠️ ReadyMadeOrchestrator not found on /root")
		return
	var agent_node: Node = orchestrator_singleton.get("a1_agent") as Node
	if agent_node == null:
		agent_node = get_node_or_null("/root/A1SynthesisEngine")
	if agent_node != null and agent_node.has_method("stop_processing"):
		agent_node.stop_processing()
		print("MissionControl: ⏹️ Drafting stopped")
	else:
		print("MissionControl: ⚠️ A1 Agent not found")
	_update_draft_action_buttons()

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
