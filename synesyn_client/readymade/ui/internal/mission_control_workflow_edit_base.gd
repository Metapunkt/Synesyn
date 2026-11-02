extends "res://readymade/ui/internal/mission_control_calendar_base.gd"
class_name MissionControlWorkflowEditBase

func _setup_workplan_ui():
	"""Setup the workplan selector with available workplans"""
	if not workplan_manager:
		return
	
	var available_workplans = workplan_manager.get_available_workplans()
	var current_workplan_name = workplan_manager.get_current_workplan_name()
	
	# Update workplan selector
	workplan_selector.clear()
	for workplan_name in available_workplans:
		workplan_selector.add_item(workplan_name)
	
	# Select current workplan
	for i in range(workplan_selector.get_item_count()):
		if workplan_selector.get_item_text(i) == current_workplan_name:
			workplan_selector.selected = i
			break
	
	print("MissionControl: Workplan UI setup complete - ", available_workplans.size(), " workplans available")

func _on_workplan_changed(_new_workplan):
	"""Handle workplan changes from WorkplanManager"""
	print("MissionControl: Workplan changed to: ", workplan_manager.get_current_workplan_name())
	
	# Clear current task list filter state
	is_filtered_view = false
	filtered_tasks.clear()
	current_task_list_path = ""
	current_task_list_name = ""
	workplan_replaced = false
	_clear_task_selection()
	
	# Update UI to reflect new workplan
	workplan = ReadyMadeOrchestrator.get_all_tasks() if ReadyMadeOrchestrator else {}
	_update_status_display()
	_update_task_list()
	_update_statistics()
	_update_calendar()
	_update_content_viewer()
	
	# Update workplan selector to show current selection
	var current_name = workplan_manager.get_current_workplan_name()
	for i in range(workplan_selector.get_item_count()):
		if workplan_selector.get_item_text(i) == current_name:
			workplan_selector.selected = i
			break

func _on_workplan_list_updated(workplan_list: Array):
	"""Handle updates to the available workplan list"""
	print("MissionControl: Workplan list updated - ", workplan_list.size(), " workplans")
	_setup_workplan_ui()

func _on_workplan_selected(index: int):
	"""Handle workplan selection from dropdown"""
	if not workplan_manager or index < 0:
		return
	
	var selected_workplan_name = workplan_selector.get_item_text(index)
	var current_workplan_name = workplan_manager.get_current_workplan_name()
	
	if selected_workplan_name != current_workplan_name:
		print("MissionControl: Switching to workplan: ", selected_workplan_name)
		workplan_manager.switch_to_workplan(selected_workplan_name)

func _on_workplan_manager_pressed():
	"""Open the workplan manager dialog"""
	print("MissionControl: Opening workplan manager")
	_show_workplan_manager_dialog()

# Mode Management Functions
func _setup_mode_ui():
	"""Setup the mode selector with available modes"""
	if not ModeManager or not mode_selector:
		return
	
	var available_modes = ModeManager.get_available_modes()
	var current_mode = ModeManager.get_current_mode()
	
	# Clear and populate mode selector
	mode_selector.clear()
	for mode_key in available_modes:
		var config = ModeManager.get_mode_config(mode_key)
		mode_selector.add_item(config.icon + " " + config.name)
		mode_selector.set_item_metadata(mode_selector.get_item_count() - 1, mode_key)
	
	# Select current mode
	_update_mode_selector(current_mode)
	
	# Connect mode selector signal
	if not mode_selector.item_selected.is_connected(_on_mode_selected):
		mode_selector.item_selected.connect(_on_mode_selected)
	
	print("MissionControl: Mode UI setup complete - current mode: ", current_mode)

func _update_mode_selector(mode_key: String):
	"""Update mode selector to show current mode"""
	for i in range(mode_selector.get_item_count()):
		if mode_selector.get_item_metadata(i) == mode_key:
			mode_selector.selected = i
			break

func _on_mode_changed(new_mode: String):
	"""Handle mode changes from ModeManager"""
	print("MissionControl: Mode changed to: ", new_mode)
	_update_mode_selector(new_mode)
	
	# Update UI elements that depend on mode
	# This is where mode-specific UI adaptations would go
	var config = ModeManager.get_current_config()
	print("MissionControl: Mode config - ", config.name, " with ", config.default_task_templates.size(), " templates")

func _on_mode_selected(index: int):
	"""Handle mode selection from dropdown"""
	if not ModeManager or index < 0:
		return
	
	var selected_mode = mode_selector.get_item_metadata(index)
	if selected_mode != ModeManager.get_current_mode():
		print("MissionControl: Switching to mode: ", selected_mode)
		ModeManager.set_mode(selected_mode)

# Workflow Management Functions
func _setup_workflow_ui():
	"""Setup the workflow selector with available workflows"""
	if not WorkflowManager or not workflow_selector:
		return
	
	var available_workflows = WorkflowManager.get_workflow_display_names()
	var current_workflow = WorkflowManager.get_current_workflow_name()
	
	# Clear and populate workflow selector
	workflow_selector.clear()
	for display_name in available_workflows:
		workflow_selector.add_item(display_name)
		# Use the display name to get the workflow enum, then get the internal name
		var workflow_name = ""
		if display_name == "Task Management":
			workflow_name = "task_management"
		elif display_name == "Edit Session":
			workflow_name = "edit_session"
		elif display_name == "Brainstorm":
			workflow_name = "brainstorm"
		workflow_selector.set_item_metadata(workflow_selector.get_item_count() - 1, workflow_name)
	
	# Select current workflow
	_update_workflow_selector(current_workflow)
	
	# Connect workflow selector signal
	if not workflow_selector.item_selected.is_connected(_on_workflow_selected):
		workflow_selector.item_selected.connect(_on_workflow_selected)
	
	print("MissionControl: Workflow UI setup complete - current workflow: ", current_workflow)

func _update_workflow_selector(workflow_name: String):
	"""Update workflow selector to show current workflow"""
	for i in range(workflow_selector.get_item_count()):
		if workflow_selector.get_item_metadata(i) == workflow_name:
			workflow_selector.selected = i
			break

func _on_workflow_changed(new_workflow: String):
	"""Handle workflow changes from WorkflowManager"""
	print("MissionControl: Workflow changed to: ", new_workflow)
	_update_workflow_selector(new_workflow)
	
	# Update UI elements that depend on workflow
	_apply_workflow_ui_changes(new_workflow)
	
	var display_name = WorkflowManager.get_current_workflow_display_name()
	print("MissionControl: Workflow config - ", display_name)

func _on_workflow_selected(index: int):
	"""Handle workflow selection from dropdown"""
	if not WorkflowManager or index < 0:
		return
	
	var selected_workflow = workflow_selector.get_item_metadata(index)
	if selected_workflow != WorkflowManager.get_current_workflow_name():
		print("MissionControl: Switching to workflow: ", selected_workflow)
		WorkflowManager.set_workflow(selected_workflow)

func _apply_workflow_ui_changes(workflow_name: String):
	"""Apply UI changes based on current workflow"""
	print("MissionControl: Applying UI changes for workflow: ", workflow_name)
	
	match workflow_name:
		"task_management":
			_show_task_management_ui()
		"edit_session":
			_show_edit_session_ui()
		"brainstorm":
			_show_brainstorm_ui()
		_:
			print("MissionControl: Unknown workflow: ", workflow_name)

func _show_task_management_ui():
	"""Show Task Management workflow UI components"""
	print("MissionControl: Showing Task Management UI")
	# Phase 3: Show task management, hide others
	if task_management_container:
		task_management_container.visible = true
	if edit_session_container:
		edit_session_container.visible = false
	if brainstorming_container:
		brainstorming_container.visible = false
	
	# Keep other components visible
	_set_other_components_visible(true)

func _show_edit_session_ui():
	"""Show Edit Session workflow UI components"""
	print("MissionControl: Showing Edit Session UI")
	# Phase 3: Show edit session, hide others
	if task_management_container:
		task_management_container.visible = false
	if edit_session_container:
		edit_session_container.visible = true
	if brainstorming_container:
		brainstorming_container.visible = false
	
	# Keep other components visible
	_set_other_components_visible(true)

func _show_brainstorm_ui():
	"""Show Brainstorm workflow UI components"""  
	print("MissionControl: Showing Brainstorm UI")
	# Phase 3: Show brainstorming, hide others
	if task_management_container:
		task_management_container.visible = false
	if edit_session_container:
		edit_session_container.visible = false
	if brainstorming_container:
		brainstorming_container.visible = true
	
	# Keep other components visible
	_set_other_components_visible(true)

func _set_other_components_visible(should_show: bool):
	"""Helper function to set visibility of non-workflow specific UI components"""
	# This controls the main tab container and other global UI elements
	if main_tab_container:
		main_tab_container.visible = should_show
	
	print("MissionControl: Set other components visible: ", should_show)

# Edit Session Management Functions
func _setup_edit_session_ui():
	"""Setup the edit session UI components"""
	if not DocumentSessionManager or not edit_mode_selector:
		return
	
	# Setup edit mode selector
	var edit_modes = DocumentSessionManager.get_available_edit_modes()
	var display_names = DocumentSessionManager.get_edit_mode_display_names()
	
	edit_mode_selector.clear()
	for mode in edit_modes:
		edit_mode_selector.add_item(display_names[mode])
		edit_mode_selector.set_item_metadata(edit_mode_selector.get_item_count() - 1, mode)
	
	# Set initial selection
	_update_edit_mode_selector(DocumentSessionManager.get_current_edit_mode())
	
	# Setup existing context mode selector
	_setup_context_mode_selector()
	
	# Create session management UI
	_create_session_management_ui()
	
	# Connect signals
	edit_mode_selector.item_selected.connect(_on_edit_mode_selected)
	if context_mode_selector:
		context_mode_selector.item_selected.connect(_on_context_mode_selected)
	load_document_button.pressed.connect(_on_load_document_pressed)
	load_string_button.pressed.connect(_on_load_string_pressed)
	set_primary_button.pressed.connect(_on_set_primary_pressed)
	remove_doc_button.pressed.connect(_on_remove_document_pressed)
	clear_session_button.pressed.connect(_on_clear_session_pressed)
	
	# Phase 4.5: Session management connections (after buttons are created)
	if save_session_button:
		save_session_button.pressed.connect(_on_save_session_pressed)
	if load_session_button:
		load_session_button.pressed.connect(_on_load_session_pressed)
	if view_history_button:
		view_history_button.pressed.connect(_on_view_history_pressed)
	if session_stats_button:
		session_stats_button.pressed.connect(_on_session_stats_pressed)
	if export_session_button:
		export_session_button.pressed.connect(_on_export_session_pressed)
	
	# Connect dialog signals
	document_file_dialog.file_selected.connect(_on_document_file_selected)
	load_text_dialog.confirmed.connect(_on_load_text_confirmed)
	
	# Connect session dialog signals (after dialogs are created)
	if session_save_dialog:
		session_save_dialog.file_selected.connect(_on_session_save_file_selected)
	if session_load_dialog:
		session_load_dialog.file_selected.connect(_on_session_load_file_selected)
	
	# Setup document list
	active_documents_list.item_selected.connect(_on_document_list_item_selected)
	
	# Initial UI update
	_update_edit_session_ui()
	
	print("MissionControl: Edit Session UI setup complete")

func _setup_context_mode_selector():
	"""Setup the existing context mode selector UI component"""
	if not context_mode_selector:
		push_error("MissionControl: ContextModeSelector not found in scene")
		return
	
	# Clear existing items
	context_mode_selector.clear()
	
	# Set tooltip
	context_mode_selector.tooltip_text = "Select how documents are included in prompts"
	
	# Populate with context modes
	for mode in context_modes:
		context_mode_selector.add_item(context_mode_display_names[mode])
		context_mode_selector.set_item_metadata(context_mode_selector.get_item_count() - 1, mode)
	
	# Set initial selection based on current mode
	_update_context_mode_selector(document_context_mode)
	
	print("MissionControl: Context mode selector setup complete")

func _create_session_management_ui():
	"""Create the session management buttons dynamically"""
	if not edit_session_container:
		push_error("MissionControl: EditSessionContainer not found")
		return
	
	# Create container for session management buttons
	session_management_container = HBoxContainer.new()
	session_management_container.name = "SessionManagementContainer"
	
	# Create session management buttons
	save_session_button = Button.new()
	save_session_button.name = "SaveSessionButton"
	save_session_button.text = "Save Session"
	save_session_button.tooltip_text = "Save current editing session to file"
	
	load_session_button = Button.new()
	load_session_button.name = "LoadSessionButton"
	load_session_button.text = "Load Session"
	load_session_button.tooltip_text = "Load previously saved editing session"
	
	view_history_button = Button.new()
	view_history_button.name = "ViewHistoryButton"
	view_history_button.text = "View History"
	view_history_button.tooltip_text = "View change history for current session"
	
	session_stats_button = Button.new()
	session_stats_button.name = "SessionStatsButton"
	session_stats_button.text = "Statistics"
	session_stats_button.tooltip_text = "View session statistics and analytics"
	
	export_session_button = Button.new()
	export_session_button.name = "ExportSessionButton"
	export_session_button.text = "Export"
	export_session_button.tooltip_text = "Export session data for analysis"
	
	# Add buttons to container
	session_management_container.add_child(save_session_button)
	session_management_container.add_child(load_session_button)
	session_management_container.add_child(view_history_button)
	session_management_container.add_child(session_stats_button)
	session_management_container.add_child(export_session_button)
	
	# Add container to EditSessionContainer
	edit_session_container.add_child(session_management_container)
	
	# Create Phase 4.6 reporting and export UI
	_create_phase_4_6_ui()
	
	# Create session file dialogs
	_create_session_dialogs()
	
	print("MissionControl: Session management UI created")

func _create_session_dialogs():
	"""Create the session file dialogs"""
	# Create save dialog
	session_save_dialog = FileDialog.new()
	session_save_dialog.name = "SessionSaveDialog"
	session_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	session_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	session_save_dialog.add_filter("*.json", "Session Files")
	session_save_dialog.size = Vector2(800, 600)
	add_child(session_save_dialog)
	
	# Create load dialog
	session_load_dialog = FileDialog.new()
	session_load_dialog.name = "SessionLoadDialog"
	session_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	session_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	session_load_dialog.add_filter("*.json", "Session Files")
	session_load_dialog.size = Vector2(800, 600)
	add_child(session_load_dialog)
	
	print("MissionControl: Session dialogs created")

func _create_phase_4_6_ui():
	"""Create Phase 4.6 export and reporting UI components"""
	if not edit_session_container:
		push_error("MissionControl: EditSessionContainer not found for Phase 4.6 UI")
		return
	
	# Create main container for Phase 4.6 features
	phase_4_6_container = VBoxContainer.new()
	phase_4_6_container.name = "Phase46Container"
	
	# Add section label
	var section_label = Label.new()
	section_label.text = "Advanced Export & Reporting"
	section_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	section_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	phase_4_6_container.add_child(section_label)
	
	# Create report generation section
	var report_container = HBoxContainer.new()
	report_container.name = "ReportContainer"
	
	# Report format selector
	report_format_selector = OptionButton.new()
	report_format_selector.name = "ReportFormatSelector"
	report_format_selector.add_item("HTML Report", DocumentSessionManager.ExportFormat.HTML)
	report_format_selector.add_item("Markdown", DocumentSessionManager.ExportFormat.MARKDOWN)
	report_format_selector.add_item("JSON Data", DocumentSessionManager.ExportFormat.JSON)
	report_format_selector.add_item("Plain Text", DocumentSessionManager.ExportFormat.PLAIN_TEXT)
	report_format_selector.add_item("PDF-Ready", DocumentSessionManager.ExportFormat.PDF_READY)
	report_format_selector.tooltip_text = "Select report format"
	report_format_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Generate report button
	generate_report_button = Button.new()
	generate_report_button.name = "GenerateReportButton"
	generate_report_button.text = "Generate Report"
	generate_report_button.tooltip_text = "Generate comprehensive session report"
	
	report_container.add_child(report_format_selector)
	report_container.add_child(generate_report_button)
	phase_4_6_container.add_child(report_container)
	
	# Create document export section
	var export_container = HBoxContainer.new()
	export_container.name = "ExportContainer"
	
	# Export format selector
	export_format_selector = OptionButton.new()
	export_format_selector.name = "ExportFormatSelector"
	export_format_selector.add_item("HTML", DocumentSessionManager.ExportFormat.HTML)
	export_format_selector.add_item("Markdown", DocumentSessionManager.ExportFormat.MARKDOWN)
	export_format_selector.add_item("JSON", DocumentSessionManager.ExportFormat.JSON)
	export_format_selector.add_item("Plain Text", DocumentSessionManager.ExportFormat.PLAIN_TEXT)
	export_format_selector.add_item("PDF-Ready", DocumentSessionManager.ExportFormat.PDF_READY)
	export_format_selector.tooltip_text = "Select document export format"
	export_format_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Export documents button
	export_documents_button = Button.new()
	export_documents_button.name = "ExportDocumentsButton"
	export_documents_button.text = "Export Docs"
	export_documents_button.tooltip_text = "Export all documents with change tracking"
	
	export_container.add_child(export_format_selector)
	export_container.add_child(export_documents_button)
	phase_4_6_container.add_child(export_container)
	
	# Create advanced features section
	var advanced_container = HBoxContainer.new()
	advanced_container.name = "AdvancedContainer"
	
	# Analytics button
	analytics_button = Button.new()
	analytics_button.name = "AnalyticsButton"
	analytics_button.text = "Analytics"
	analytics_button.tooltip_text = "View detailed productivity and editing analytics"
	
	# Share session button
	share_session_button = Button.new()
	share_session_button.name = "ShareSessionButton"
	share_session_button.text = "Share Session"
	share_session_button.tooltip_text = "Create shareable session package (anonymized)"
	
	advanced_container.add_child(analytics_button)
	advanced_container.add_child(share_session_button)
	phase_4_6_container.add_child(advanced_container)
	
	# Add Phase 4.6 container to EditSessionContainer
	edit_session_container.add_child(phase_4_6_container)
	
	# Connect signals
	_connect_phase_4_6_signals()
	
	print("MissionControl: Phase 4.6 UI created")
	
	# Create Phase 5.1 Task Integration UI
	_create_phase_5_1_ui()

func _connect_phase_4_6_signals():
	"""Connect Phase 4.6 signal handlers"""
	if generate_report_button:
		generate_report_button.pressed.connect(_on_generate_report_pressed)
	
	if export_documents_button:
		export_documents_button.pressed.connect(_on_export_documents_pressed)
	
	if analytics_button:
		analytics_button.pressed.connect(_on_analytics_pressed)
	
	if share_session_button:
		share_session_button.pressed.connect(_on_share_session_pressed)
	
	# Connect DocumentSessionManager Phase 4.6 signals
	if DocumentSessionManager:
		DocumentSessionManager.report_generated.connect(_on_report_generated)
		DocumentSessionManager.document_exported.connect(_on_document_exported)
		DocumentSessionManager.session_shared.connect(_on_session_shared)
		DocumentSessionManager.export_failed.connect(_on_export_failed)

func _create_phase_5_1_ui():
	"""Create Phase 5.1 task integration UI components"""
	if not edit_session_container:
		push_error("MissionControl: EditSessionContainer not found for Phase 5.1 UI")
		return
	
	# Create main container for Phase 5.1 features
	phase_5_1_container = VBoxContainer.new()
	phase_5_1_container.name = "Phase51Container"
	
	# Add section label
	var section_label = Label.new()
	section_label.text = "Task Integration"
	section_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	section_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	phase_5_1_container.add_child(section_label)
	
	# Create main task integration section
	var task_integration_container = HBoxContainer.new()
	task_integration_container.name = "TaskIntegrationContainer"
	
	# Create task from session button
	create_task_button = Button.new()
	create_task_button.name = "CreateTaskButton"
	create_task_button.text = "Create Task"
	create_task_button.tooltip_text = "Create a WorkplanTask from current edit session"
	create_task_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Task suggestions button
	task_suggestions_button = Button.new()
	task_suggestions_button.name = "TaskSuggestionsButton"
	task_suggestions_button.text = "AI Suggestions"
	task_suggestions_button.tooltip_text = "Get AI-powered task creation suggestions"
	task_suggestions_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Multiple tasks button
	multiple_tasks_button = Button.new()
	multiple_tasks_button.name = "MultipleTasksButton"
	multiple_tasks_button.text = "Batch Create"
	multiple_tasks_button.tooltip_text = "Create multiple tasks from session with different configurations"
	multiple_tasks_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	task_integration_container.add_child(create_task_button)
	task_integration_container.add_child(task_suggestions_button)
	task_integration_container.add_child(multiple_tasks_button)
	phase_5_1_container.add_child(task_integration_container)
	
	# Create task creation dialog
	_create_task_creation_dialog()
	
	# Create task suggestions dialog
	_create_task_suggestions_dialog()
	
	# Add Phase 5.1 container to EditSessionContainer
	edit_session_container.add_child(phase_5_1_container)
	
	# Connect signals
	_connect_phase_5_1_signals()
	
	print("MissionControl: Phase 5.1 UI created")
	
	# Create Phase 5.2 Performance Optimization UI
	_create_phase_5_2_ui()
	_connect_phase_5_2_signals()
	
	# Create export file dialogs
	_create_export_dialogs()

func _create_task_creation_dialog():
	"""Create the task creation dialog for Phase 5.1"""
	task_creation_dialog = AcceptDialog.new()
	task_creation_dialog.title = "Create Task from Edit Session"
	task_creation_dialog.size = Vector2(600, 500)
	
	var main_container = VBoxContainer.new()
	
	# Task title section
	var title_container = VBoxContainer.new()
	var title_label = Label.new()
	title_label.text = "Task Title:"
	title_container.add_child(title_label)
	
	task_title_edit = LineEdit.new()
	task_title_edit.placeholder_text = "Auto-generated from session context"
	title_container.add_child(task_title_edit)
	main_container.add_child(title_container)
	
	# Task notes section
	var notes_container = VBoxContainer.new()
	var notes_label = Label.new()
	notes_label.text = "Task Notes:"
	notes_container.add_child(notes_label)
	
	task_notes_edit = TextEdit.new()
	task_notes_edit.placeholder_text = "Auto-generated from session analysis"
	task_notes_edit.custom_minimum_size = Vector2(0, 120)
	notes_container.add_child(task_notes_edit)
	main_container.add_child(notes_container)
	
	# Task properties section
	var properties_container = GridContainer.new()
	properties_container.columns = 2
	
	# Priority selector
	var priority_label = Label.new()
	priority_label.text = "Priority:"
	properties_container.add_child(priority_label)
	
	task_priority_selector = OptionButton.new()
	task_priority_selector.add_item("Low (0)", 0)
	task_priority_selector.add_item("Medium (1)", 1)
	task_priority_selector.add_item("High (2)", 2)
	task_priority_selector.add_item("Critical (3)", 3)
	properties_container.add_child(task_priority_selector)
	
	# Format selector
	var format_label = Label.new()
	format_label.text = "Format:"
	properties_container.add_child(format_label)
	
	task_format_selector = OptionButton.new()
	task_format_selector.add_item("Document")
	task_format_selector.add_item("Blog Post")
	task_format_selector.add_item("Report")
	task_format_selector.add_item("Proposal")
	task_format_selector.add_item("Email")
	task_format_selector.add_item("Social Media")
	task_format_selector.add_item("Documentation")
	properties_container.add_child(task_format_selector)
	
	# Channel selector
	var channel_label = Label.new()
	channel_label.text = "Channel:"
	properties_container.add_child(channel_label)
	
	task_channel_selector = OptionButton.new()
	task_channel_selector.add_item("Direct")
	task_channel_selector.add_item("Website")
	task_channel_selector.add_item("Email")
	task_channel_selector.add_item("Social Media")
	task_channel_selector.add_item("Internal")
	task_channel_selector.add_item("Presentation")
	properties_container.add_child(task_channel_selector)
	
	main_container.add_child(properties_container)
	
	# Add info section
	var info_container = VBoxContainer.new()
	var info_label = Label.new()
	info_label.text = "Session Info (auto-populated):"
	info_label.add_theme_color_override("font_color", Color.GRAY)
	info_container.add_child(info_label)
	
	var info_text = RichTextLabel.new()
	info_text.name = "SessionInfoText"
	info_text.custom_minimum_size = Vector2(0, 80)
	info_text.bbcode_enabled = true
	info_text.scroll_active = true
	info_container.add_child(info_text)
	main_container.add_child(info_container)
	
	task_creation_dialog.add_child(main_container)
	add_child(task_creation_dialog)

func _create_task_suggestions_dialog():
	"""Create the task suggestions dialog for Phase 5.1"""
	task_suggestions_dialog = AcceptDialog.new()
	task_suggestions_dialog.title = "AI-Powered Task Suggestions"
	task_suggestions_dialog.size = Vector2(700, 600)
	
	var main_container = VBoxContainer.new()
	
	# Header
	var header_label = Label.new()
	header_label.text = "Based on your edit session, here are AI-generated task suggestions:"
	header_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	main_container.add_child(header_label)
	
	# Suggestions content
	var suggestions_scroll = ScrollContainer.new()
	suggestions_scroll.custom_minimum_size = Vector2(0, 400)
	
	var suggestions_container = VBoxContainer.new()
	suggestions_container.name = "SuggestionsContainer"
	suggestions_scroll.add_child(suggestions_container)
	main_container.add_child(suggestions_scroll)
	
	# Action buttons
	var action_container = HBoxContainer.new()
	
	var create_all_button = Button.new()
	create_all_button.name = "CreateAllButton"
	create_all_button.text = "Create All"
	create_all_button.tooltip_text = "Create tasks for all suggestions"
	
	var create_selected_button = Button.new()
	create_selected_button.name = "CreateSelectedButton"
	create_selected_button.text = "Create Selected"
	create_selected_button.tooltip_text = "Create tasks for selected suggestions"
	
	action_container.add_child(create_all_button)
	action_container.add_child(create_selected_button)
	main_container.add_child(action_container)
	
	task_suggestions_dialog.add_child(main_container)
	add_child(task_suggestions_dialog)

func _connect_phase_5_1_signals():
	"""Connect Phase 5.1 signal handlers"""
	if create_task_button:
		create_task_button.pressed.connect(_on_create_task_pressed)
	
	if task_suggestions_button:
		task_suggestions_button.pressed.connect(_on_task_suggestions_pressed)
	
	if multiple_tasks_button:
		multiple_tasks_button.pressed.connect(_on_multiple_tasks_pressed)
	
	if task_creation_dialog:
		task_creation_dialog.confirmed.connect(_on_task_creation_confirmed)

func _update_edit_mode_selector(mode: String):
	"""Update edit mode selector to show current mode"""
	for i in range(edit_mode_selector.get_item_count()):
		if edit_mode_selector.get_item_metadata(i) == mode:
			edit_mode_selector.selected = i
			break

func _on_edit_mode_selected(index: int):
	"""Handle edit mode selection"""
	if not DocumentSessionManager or index < 0:
		return
	
	var selected_mode = edit_mode_selector.get_item_metadata(index)
	DocumentSessionManager.set_edit_mode(selected_mode)
	print("MissionControl: Edit mode changed to: ", selected_mode)

func _on_context_mode_selected(index: int):
	"""Handle context mode selection change"""
	if not context_mode_selector or index < 0:
		return
	
	var mode = context_mode_selector.get_item_metadata(index)
	set_document_context_mode(mode)
	print("MissionControl: Context mode changed to: ", mode)

func _update_context_mode_selector(mode: String):
	"""Update the context mode selector to reflect the current mode"""
	if not context_mode_selector:
		return
	
	for i in range(context_mode_selector.get_item_count()):
		if context_mode_selector.get_item_metadata(i) == mode:
			context_mode_selector.selected = i
			break

func _on_load_document_pressed():
	"""Handle load document button press"""
	document_file_dialog.popup_centered()

func _on_load_string_pressed():
	"""Handle load from string button press"""
	load_text_edit.text = ""
	load_text_name_edit.text = "Untitled Document"
	load_text_dialog.popup_centered()

func _on_document_file_selected(path: String):
	"""Handle document file selection"""
	print("MissionControl: Loading document from file: ", path)
	var document = DocumentSessionManager.load_document(path)
	if document:
		print("MissionControl: Document loaded successfully: ", document.file_name)
	else:
		_show_error_dialog("Failed to load document: " + path)

func _on_load_text_confirmed():
	"""Handle load text dialog confirmation"""
	var content = load_text_edit.text
	var doc_name = load_text_name_edit.text
	
	if content.strip_edges().is_empty():
		_show_error_dialog("Please enter some text content.")
		return
	
	if doc_name.strip_edges().is_empty():
		doc_name = "Untitled Document"
	
	print("MissionControl: Loading document from string: ", doc_name)
	var document = DocumentSessionManager.load_document_from_string(content, doc_name)
	if document:
		print("MissionControl: Document from string loaded successfully: ", document.file_name)

func _on_set_primary_pressed():
	"""Handle set primary document button press"""
	var selected_items = active_documents_list.get_selected_items()
	if selected_items.is_empty():
		_show_error_dialog("Please select a document to set as primary.")
		return
	
	var documents = DocumentSessionManager.get_active_documents()
	if selected_items[0] < documents.size():
		var document = documents[selected_items[0]]
		DocumentSessionManager.set_primary_document(document)
		print("MissionControl: Set primary document: ", document.file_name)

func _on_remove_document_pressed():
	"""Handle remove document button press"""
	var selected_items = active_documents_list.get_selected_items()
	if selected_items.is_empty():
		_show_error_dialog("Please select a document to remove.")
		return
	
	var documents = DocumentSessionManager.get_active_documents()
	if selected_items[0] < documents.size():
		var document = documents[selected_items[0]]
		DocumentSessionManager.remove_document(document)
		print("MissionControl: Removed document: ", document.file_name)

func _on_clear_session_pressed():
	"""Handle clear session button press"""
	if DocumentSessionManager.get_active_documents().size() == 0:
		_show_error_dialog("No documents to clear.")
		return
	
	# Show confirmation dialog
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_text = "Are you sure you want to clear all documents from the session?"
	add_child(confirm_dialog)
	
	confirm_dialog.confirmed.connect(func():
		DocumentSessionManager.clear_session()
		confirm_dialog.queue_free()
	)
	
	confirm_dialog.canceled.connect(func():
		confirm_dialog.queue_free()
	)
	
	confirm_dialog.popup_centered()

func _on_document_list_item_selected(index: int):
	"""Handle document list item selection"""
	var documents = DocumentSessionManager.get_active_documents()
	if index < documents.size():
		var document = documents[index]
		print("MissionControl: Selected document: ", document.file_name)
		# Update button states
		set_primary_button.disabled = document.is_primary
		remove_doc_button.disabled = false
	else:
		set_primary_button.disabled = true
		remove_doc_button.disabled = true

# DocumentSessionManager signal handlers
func _on_document_loaded(document):
	"""Handle document loaded signal"""
	print("MissionControl: Document loaded signal received: ", document.file_name)
	_update_edit_session_ui()

func _on_primary_document_changed(document):
	"""Handle primary document changed signal"""
	print("MissionControl: Primary document changed: ", document.file_name)
	_update_edit_session_ui()

func _on_document_removed(document_path: String):
	"""Handle document removed signal"""
	print("MissionControl: Document removed: ", document_path)
	_update_edit_session_ui()

func _on_session_cleared():
	"""Handle session cleared signal"""
	print("MissionControl: Session cleared")
	_update_edit_session_ui()

# === PHASE 4.5: SESSION MANAGEMENT HANDLERS ===

func _on_save_session_pressed():
	"""Handle save session button press"""
	if not DocumentSessionManager or DocumentSessionManager.get_active_documents().size() == 0:
		_show_error_dialog("No documents to save in session.")
		return
	
	# Setup save dialog
	session_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	session_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	session_save_dialog.clear_filters()
	session_save_dialog.add_filter("*.json", "Session Files")
	session_save_dialog.current_file = "editing_session_" + str(Time.get_unix_time_from_system()) + ".json"
	session_save_dialog.popup_centered(Vector2(800, 600))

func _on_load_session_pressed():
	"""Handle load session button press"""
	if not DocumentSessionManager:
		_show_error_dialog("DocumentSessionManager not available.")
		return
	
	# Setup load dialog
	session_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	session_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	session_load_dialog.clear_filters()
	session_load_dialog.add_filter("*.json", "Session Files")
	session_load_dialog.popup_centered(Vector2(800, 600))

func _on_view_history_pressed():
	"""Handle view history button press"""
	if not DocumentSessionManager:
		_show_error_dialog("DocumentSessionManager not available.")
		return
	
	var documents = DocumentSessionManager.get_active_documents()
	if documents.size() == 0:
		_show_info_dialog("No documents loaded to view history.")
		return
	
	# Show session change history dialog
	var dialog = AcceptDialog.new()
	dialog.title = "Session Change History"
	dialog.size = Vector2(800, 600)
	
	var container = VBoxContainer.new()
	
	# Add tabs for session overview and individual documents
	var tab_container_local = TabContainer.new()
	tab_container_local.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Session overview tab
	var session_scroll = ScrollContainer.new()
	var session_label = RichTextLabel.new()
	session_label.fit_content = true
	session_label.bbcode_enabled = true
	session_label.text = _format_session_history_as_bbcode()
	session_scroll.add_child(session_label)
	tab_container_local.add_child(session_scroll)
	tab_container_local.set_tab_title(0, "Session Overview")
	
	# Individual document tabs
	for i in range(documents.size()):
		var document = documents[i]
		var doc_scroll = ScrollContainer.new()
		var doc_label = RichTextLabel.new()
		doc_label.fit_content = true
		doc_label.bbcode_enabled = true
		doc_label.text = _format_document_history_as_bbcode(document)
		doc_scroll.add_child(doc_label)
		tab_container_local.add_child(doc_scroll)
		var tab_title = document.file_name
		if document.is_primary:
			tab_title = "🎯 " + tab_title
		tab_container_local.set_tab_title(i + 1, tab_title)
	
	container.add_child(tab_container_local)
	dialog.add_child(container)
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

func _on_session_stats_pressed():
	"""Handle session stats button press"""
	if not DocumentSessionManager:
		_show_error_dialog("DocumentSessionManager not available.")
		return
	
	var documents = DocumentSessionManager.get_active_documents()
	if documents.size() == 0:
		_show_info_dialog("No documents loaded to show statistics.")
		return
	
	# Show session statistics dialog
	var dialog = AcceptDialog.new()
	dialog.title = "Session Statistics"
	dialog.size = Vector2(600, 500)
	
	var scroll = ScrollContainer.new()
	var label = RichTextLabel.new()
	label.fit_content = true
	label.bbcode_enabled = true
	label.text = _format_session_statistics_as_bbcode()
	scroll.add_child(label)
	dialog.add_child(scroll)
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

func _on_export_session_pressed():
	"""Handle export session button press"""
	if not DocumentSessionManager:
		_show_error_dialog("DocumentSessionManager not available.")
		return
	
	var documents = DocumentSessionManager.get_active_documents()
	if documents.size() == 0:
		_show_info_dialog("No documents loaded to export.")
		return
	
	# Export session analysis data
	var export_data = DocumentSessionManager.export_session_for_analysis()
	
	# Create export dialog
	var file_dialog_local = FileDialog.new()
	file_dialog_local.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog_local.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog_local.add_filter("*.json", "JSON Files")
	file_dialog_local.current_file = "session_analysis_" + str(Time.get_unix_time_from_system()) + ".json"
	
	file_dialog_local.file_selected.connect(func(path: String):
		_save_session_analysis_to_file(export_data, path)
		file_dialog_local.queue_free()
	)
	
	get_tree().current_scene.add_child(file_dialog_local)
	file_dialog_local.popup_centered(Vector2(800, 600))

func _on_session_save_file_selected(path: String):
	"""Handle session save file selection"""
	if DocumentSessionManager:
		var success = DocumentSessionManager.save_session(path)
		if not success:
			_show_error_dialog("Failed to save session to: " + path)

func _on_session_load_file_selected(path: String):
	"""Handle session load file selection"""
	if DocumentSessionManager:
		var success = DocumentSessionManager.load_session(path)
		if not success:
			_show_error_dialog("Failed to load session from: " + path)

func _on_session_saved(session_path: String):
	"""Handle session saved signal"""
	print("MissionControl: Session saved to: ", session_path)
	_show_info_dialog("Session saved successfully to:\n" + session_path)
	_update_edit_session_ui()

func _on_session_loaded_success(session_path: String):
	"""Handle session loaded signal"""
	print("MissionControl: Session loaded from: ", session_path)
	_show_info_dialog("Session loaded successfully from:\n" + session_path)
	_update_edit_session_ui()

func _on_session_save_failed(error: String):
	"""Handle session save failed signal"""
	print("MissionControl: Session save failed: ", error)
	_show_error_dialog("Failed to save session:\n" + error)

func _on_session_load_failed(error: String):
	"""Handle session load failed signal"""
	print("MissionControl: Session load failed: ", error)
	_show_error_dialog("Failed to load session:\n" + error)

# === PHASE 4.6: EXPORT AND REPORTING HANDLERS ===

func _on_generate_report_pressed():
	"""Handle generate report button press"""
	if not DocumentSessionManager or DocumentSessionManager.get_active_documents().size() == 0:
		_show_error_dialog("No documents loaded to generate report.")
		return
	
	# Store format for use after dialog selection
	pending_export_format = report_format_selector.get_selected_id() if report_format_selector else DocumentSessionManager.ExportFormat.HTML
	
	# Set default filename with format extension
	var format_extensions = {
		DocumentSessionManager.ExportFormat.HTML: ".html",
		DocumentSessionManager.ExportFormat.MARKDOWN: ".md", 
		DocumentSessionManager.ExportFormat.JSON: ".json",
		DocumentSessionManager.ExportFormat.PLAIN_TEXT: ".txt",
		DocumentSessionManager.ExportFormat.PDF_READY: ".html",
		DocumentSessionManager.ExportFormat.RTFD: ".rtfd"
	}
	
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var session_name_clean = DocumentSessionManager.session_name.replace(" ", "_") if not DocumentSessionManager.session_name.is_empty() else "session"
	var default_filename = "edit_session_report_%s_%s%s" % [session_name_clean, timestamp, format_extensions.get(pending_export_format, ".html")]
	
	report_export_dialog.current_file = default_filename
	report_export_dialog.popup_centered(Vector2i(800, 600))

func _on_export_documents_pressed():
	"""Handle export documents button press"""
	if not DocumentSessionManager or DocumentSessionManager.get_active_documents().size() == 0:
		_show_error_dialog("No documents to export.")
		return
	
	# Store format for use after dialog selection
	pending_export_format = export_format_selector.get_selected_id() if export_format_selector else DocumentSessionManager.ExportFormat.HTML
	
	# Set default directory
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var _default_dirname = "session_export_%s" % timestamp
	
	documents_export_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	documents_export_dialog.popup_centered(Vector2i(800, 600))

func _on_analytics_pressed():
	"""Handle analytics button press"""
	if not DocumentSessionManager or DocumentSessionManager.get_active_documents().size() == 0:
		_show_error_dialog("No session data available for analytics.")
		return
	
	# Show comprehensive analytics dialog
	_show_analytics_dialog()

func _on_share_session_pressed():
	"""Handle share session button press"""
	if not DocumentSessionManager or DocumentSessionManager.get_active_documents().size() == 0:
		_show_error_dialog("No session to share.")
		return
	
	# Set default filename
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var session_name_clean = DocumentSessionManager.session_name.replace(" ", "_") if not DocumentSessionManager.session_name.is_empty() else "session"
	var default_filename = "session_share_%s_%s.json" % [session_name_clean, timestamp]
	
	session_share_dialog.current_file = default_filename
	session_share_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	session_share_dialog.popup_centered(Vector2i(800, 600))

# Phase 4.6 signal handlers
func _on_report_generated(report_path: String, report_type: String):
	"""Handle report generated signal"""
	print("MissionControl: Report generated: ", report_path)
	_show_info_dialog("Report generated successfully!\n\nType: %s\nLocation: %s" % [report_type, report_path])

func _on_document_exported(document_path: String, _export_format: String):
	"""Handle document exported signal"""
	print("MissionControl: Document exported: ", document_path)
	# Individual export notifications are handled in batch by export_all_documents

func _on_session_shared(share_data: Dictionary):
	"""Handle session shared signal"""
	print("MissionControl: Session shared - %d documents, anonymized" % share_data.get("session_info", {}).get("document_count", 0))

func _on_export_failed(error: String):
	"""Handle export failed signal"""
	print("MissionControl: Export failed: ", error)
	_show_error_dialog("Export operation failed:\n" + error)

