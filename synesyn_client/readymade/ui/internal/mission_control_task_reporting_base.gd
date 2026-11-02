extends "res://readymade/ui/internal/mission_control_workflow_edit_base.gd"
class_name MissionControlTaskReportingBase

func _show_analytics_dialog():
	"""Show comprehensive analytics dialog"""
	var analytics_data = DocumentSessionManager._compile_comprehensive_report_data()
	
	# Create analytics dialog
	var dialog = AcceptDialog.new()
	dialog.title = "Session Analytics & Insights"
	dialog.size = Vector2(900, 700)
	
	# Create tabbed interface for different analytics views
	var tab_container_local = TabContainer.new()
	tab_container_local.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Overview tab
	var overview_scroll = ScrollContainer.new()
	var overview_label = RichTextLabel.new()
	overview_label.fit_content = true
	overview_label.bbcode_enabled = true
	overview_label.text = _format_analytics_overview_as_bbcode(analytics_data)
	overview_scroll.add_child(overview_label)
	tab_container_local.add_child(overview_scroll)
	tab_container_local.set_tab_title(0, "Overview")
	
	# Productivity metrics tab
	var productivity_scroll = ScrollContainer.new()
	var productivity_label = RichTextLabel.new()
	productivity_label.fit_content = true
	productivity_label.bbcode_enabled = true
	productivity_label.text = _format_productivity_metrics_as_bbcode(analytics_data.productivity_metrics)
	productivity_scroll.add_child(productivity_label)
	tab_container_local.add_child(productivity_scroll)
	tab_container_local.set_tab_title(1, "Productivity")
	
	# Document analysis tab
	var documents_scroll = ScrollContainer.new()
	var documents_label = RichTextLabel.new()
	documents_label.fit_content = true
	documents_label.bbcode_enabled = true
	documents_label.text = _format_document_analysis_as_bbcode(analytics_data.document_analysis)
	documents_scroll.add_child(documents_label)
	tab_container_local.add_child(documents_scroll)
	tab_container_local.set_tab_title(2, "Documents")
	
	# Recommendations tab
	if analytics_data.recommendations.size() > 0:
		var recommendations_scroll = ScrollContainer.new()
		var recommendations_label = RichTextLabel.new()
		recommendations_label.fit_content = true
		recommendations_label.bbcode_enabled = true
		recommendations_label.text = _format_recommendations_as_bbcode(analytics_data.recommendations)
		recommendations_scroll.add_child(recommendations_label)
		tab_container.add_child(recommendations_scroll)
		tab_container.set_tab_title(3, "Recommendations")
	
	# Timeline tab
	var timeline_scroll = ScrollContainer.new()
	var timeline_label = RichTextLabel.new()
	timeline_label.fit_content = true
	timeline_label.bbcode_enabled = true
	timeline_label.text = _format_timeline_as_bbcode(analytics_data.change_timeline)
	timeline_scroll.add_child(timeline_label)
	tab_container.add_child(timeline_scroll)
	tab_container.set_tab_title(4, "Timeline")
	
	dialog.add_child(tab_container)
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

func _format_analytics_overview_as_bbcode(data: Dictionary) -> String:
	"""Format analytics overview as BBCode"""
	var bbcode = "[b][color=blue]📊 Session Analytics Overview[/color][/b]\n\n"
	
	var metadata = data.metadata
	var overview = data.session_overview
	
	bbcode += "[b]Session Information[/b]\n"
	bbcode += "• Session: [color=green]%s[/color]\n" % metadata.session_name
	bbcode += "• Duration: [color=orange]%.1f minutes[/color]\n" % (metadata.session_duration / 60.0)
	bbcode += "• Edit Mode: [color=purple]%s[/color]\n" % metadata.edit_mode
	bbcode += "• Complexity: [color=red]%s[/color]\n\n" % overview.session_complexity
	
	bbcode += "[b]Performance Metrics[/b]\n"
	bbcode += "• Productivity Score: [color=blue]%.1f%%[/color]\n" % (overview.productivity_score * 100)
	bbcode += "• Documents: [color=green]%d[/color]\n" % overview.total_documents
	bbcode += "• Total Words: [color=cyan]%d[/color]\n" % overview.total_words
	bbcode += "• Total Edits: [color=orange]%d[/color]\n" % overview.total_edits
	bbcode += "• Avg Words/Doc: [color=gray]%.1f[/color]\n\n" % overview.average_words_per_document
	
	return bbcode

func _format_productivity_metrics_as_bbcode(metrics: Dictionary) -> String:
	"""Format productivity metrics as BBCode"""
	var bbcode = "[b][color=green]⚡ Productivity Analysis[/color][/b]\n\n"
	
	bbcode += "[b]Speed Metrics[/b]\n"
	bbcode += "• Words per Minute: [color=blue]%.1f[/color]\n" % metrics.words_per_minute
	bbcode += "• Edits per Minute: [color=orange]%.1f[/color]\n" % metrics.edits_per_minute
	bbcode += "• Efficiency Score: [color=green]%.1f%%[/color]\n\n" % (metrics.efficiency_score * 100)
	
	bbcode += "[b]Work Patterns[/b]\n"
	bbcode += "• Peak Productivity: [color=purple]%s[/color]\n" % metrics.peak_productivity_time
	bbcode += "• Consistency Score: [color=cyan]%.1f%%[/color]\n" % (metrics.consistency_score * 100)
	bbcode += "• Focus Periods: [color=gray]%d identified[/color]\n\n" % metrics.focus_periods.size()
	
	return bbcode

func _format_document_analysis_as_bbcode(documents: Array) -> String:
	"""Format document analysis as BBCode"""
	var bbcode = "[b][color=purple]📄 Document Analysis[/color][/b]\n\n"
	
	for doc in documents:
		bbcode += "[b]%s[/b] %s\n" % [doc.name, "[color=gold](PRIMARY)[/color]" if doc.is_primary else ""]
		bbcode += "• Word Count: [color=blue]%d[/color]\n" % doc.metrics.word_count
		bbcode += "• Characters: [color=gray]%d[/color]\n" % doc.metrics.character_count
		bbcode += "• Lines: [color=cyan]%d[/color]\n" % doc.metrics.line_count
		bbcode += "• Edits: [color=orange]%d[/color]\n" % doc.change_analysis.get("total_edits", 0)
		bbcode += "• Quality Score: [color=green]%.1f%%[/color]\n\n" % (doc.content_quality.get("readability_score", 0.0) * 100)
	
	return bbcode

# === PHASE 5.1: TASK INTEGRATION HANDLERS ===

func _on_create_task_pressed():
	"""Handle create task button press"""
	if not DocumentSessionManager or DocumentSessionManager.get_active_documents().size() == 0:
		_show_error_dialog("No documents loaded to create task.")
		return
	
	# Pre-populate task creation dialog with session data
	_populate_task_creation_dialog()
	task_creation_dialog.popup_centered()

func _on_task_suggestions_pressed():
	"""Handle task suggestions button press"""
	if not DocumentSessionManager or DocumentSessionManager.get_active_documents().size() == 0:
		_show_error_dialog("No session data available for task suggestions.")
		return
	
	# Generate and show AI-powered suggestions
	_show_task_suggestions_dialog()

func _on_multiple_tasks_pressed():
	"""Handle multiple tasks button press"""
	if not DocumentSessionManager or DocumentSessionManager.get_active_documents().size() == 0:
		_show_error_dialog("No session data available for batch task creation.")
		return
	
	# Show batch task creation dialog
	_show_batch_task_creation_dialog()

func _on_task_creation_confirmed():
	"""Handle task creation dialog confirmation"""
	var task_title = task_title_edit.text.strip_edges()
	var task_notes = task_notes_edit.text.strip_edges()
	
	# Create task using DocumentSessionManager
	var created_task = DocumentSessionManager.create_task_from_edit_session(task_title, task_notes)
	
	if created_task:
		# Apply user-selected properties
		if task_priority_selector.selected >= 0:
			created_task.priority = task_priority_selector.get_selected_id()
		
		if task_format_selector.selected >= 0:
			var format_text = task_format_selector.get_item_text(task_format_selector.selected)
			created_task.formats = [format_text.to_lower()]
		
		if task_channel_selector.selected >= 0:
			var channel_text = task_channel_selector.get_item_text(task_channel_selector.selected)
			created_task.channels = [channel_text.to_lower()]
		
		# Add task to current workplan
		if _add_task_to_workplan(created_task):
			_show_success_dialog("Task created successfully!\n\nTitle: %s\nPriority: %d\nDocuments: %d referenced" % [
				created_task.title,
				created_task.priority,
				created_task.get_document_count()
			])
			
			# Refresh task list
			_update_task_list()
		else:
			_show_error_dialog("Task created but failed to add to workplan.")
	else:
		_show_error_dialog("Failed to create task from edit session.")

func _populate_task_creation_dialog():
	"""Pre-populate the task creation dialog with session data"""
	if not DocumentSessionManager:
		return
	
	# Auto-generate title and notes if empty
	var suggested_title = DocumentSessionManager._generate_task_title_from_session()
	var suggested_notes = DocumentSessionManager._generate_task_notes_from_session()
	
	task_title_edit.text = suggested_title
	task_title_edit.placeholder_text = suggested_title
	
	task_notes_edit.text = suggested_notes
	task_notes_edit.placeholder_text = "Auto-generated from session analysis"
	
	# Set suggested priority
	var suggested_priority = 1  # Default medium
	var insights = DocumentSessionManager.get_session_summary()
	if insights.has("document_count"):
		# Simple complexity assessment based on document count and words
		var doc_count = insights.document_count
		var total_words = insights.get("total_words", 0)
		var session_complexity = "Simple"
		
		if doc_count > 5 or total_words > 10000:
			session_complexity = "Complex"
		elif doc_count > 10 or total_words > 25000:
			session_complexity = "Very Complex"
		
		match session_complexity:
			"Simple": suggested_priority = 0
			"Complex": suggested_priority = 2
			"Very Complex": suggested_priority = 3
	
	task_priority_selector.selected = suggested_priority
	
	# Set suggested format and channel based on document analysis
	var suggested_formats = DocumentSessionManager._suggest_formats_from_documents()
	var suggested_channels = DocumentSessionManager._suggest_channels_from_documents()
	
	if suggested_formats.size() > 0:
		var format_to_find = suggested_formats[0].capitalize()
		for i in range(task_format_selector.get_item_count()):
			if task_format_selector.get_item_text(i) == format_to_find:
				task_format_selector.selected = i
				break
	
	if suggested_channels.size() > 0:
		var channel_to_find = suggested_channels[0].capitalize()
		for i in range(task_channel_selector.get_item_count()):
			if task_channel_selector.get_item_text(i) == channel_to_find:
				task_channel_selector.selected = i
				break
	
	# Update session info display
	var info_text = task_creation_dialog.get_node("VBoxContainer/VBoxContainer3/SessionInfoText") as RichTextLabel
	if info_text:
		var _session_summary = DocumentSessionManager.get_session_summary()
		var productivity_metrics = DocumentSessionManager.get_session_productivity_metrics()
		
		var info_bbcode = "[b]Session Summary[/b]\n"
		info_bbcode += "• Documents: %d\n" % DocumentSessionManager.get_active_documents().size()
		info_bbcode += "• Total Words: %d\n" % productivity_metrics.get("total_words", 0)
		info_bbcode += "• Total Edits: %d\n" % productivity_metrics.get("total_edits", 0)
		info_bbcode += "• Productivity: %.1f%%\n" % (productivity_metrics.get("productivity_score", 0.0) * 100)
		info_bbcode += "• Session Duration: %.1f min\n" % (productivity_metrics.get("session_duration", 0) / 60.0)
		
		info_text.text = info_bbcode

func _show_task_suggestions_dialog():
	"""Show AI-powered task suggestions dialog"""
	var suggestions_data = DocumentSessionManager.get_task_creation_suggestions()
	
	if suggestions_data.has("error"):
		_show_error_dialog(suggestions_data.error)
		return
	
	# Clear previous suggestions
	var suggestions_container = task_suggestions_dialog.get_node("VBoxContainer/ScrollContainer/SuggestionsContainer")
	if suggestions_container:
		for child in suggestions_container.get_children():
			child.queue_free()
		
		# Add new suggestions
		_populate_suggestions_container(suggestions_container, suggestions_data)
	
	task_suggestions_dialog.popup_centered()

func _populate_suggestions_container(container: VBoxContainer, suggestions_data: Dictionary):
	"""Populate the suggestions container with AI recommendations"""
	var recommendations = suggestions_data.get("recommended_tasks", [])
	
	if recommendations.is_empty():
		var no_suggestions_label = Label.new()
		no_suggestions_label.text = "No specific task recommendations available for this session."
		no_suggestions_label.add_theme_color_override("font_color", Color.GRAY)
		container.add_child(no_suggestions_label)
		return
	
	for i in range(recommendations.size()):
		var rec = recommendations[i]
		
		# Create suggestion card
		var card = PanelContainer.new()
		var card_container = VBoxContainer.new()
		
		# Header with checkbox and title
		var header = HBoxContainer.new()
		
		var checkbox = CheckBox.new()
		checkbox.name = "Suggestion_%d_CheckBox" % i
		checkbox.button_pressed = true  # Selected by default
		
		var title_label = Label.new()
		title_label.text = rec.get("title", "Untitled Task")
		title_label.add_theme_color_override("font_color", Color.WHITE)
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		header.add_child(checkbox)
		header.add_child(title_label)
		card_container.add_child(header)
		
		# Details
		var details_label = Label.new()
		var priority_text = ["Low", "Medium", "High", "Critical"][rec.get("priority", 0)]
		var duration = rec.get("estimated_duration", 60)
		
		details_label.text = "Priority: %s | Duration: %d min | Reason: %s" % [
			priority_text,
			duration,
			rec.get("reason", "AI recommendation")
		]
		details_label.add_theme_color_override("font_color", Color.GRAY)
		details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_container.add_child(details_label)
		
		card.add_child(card_container)
		container.add_child(card)
	
	# Connect create buttons
	var create_all_button = task_suggestions_dialog.get_node("VBoxContainer/HBoxContainer/CreateAllButton")
	var create_selected_button = task_suggestions_dialog.get_node("VBoxContainer/HBoxContainer/CreateSelectedButton")
	
	if create_all_button and not create_all_button.pressed.is_connected(_on_create_all_suggested_tasks):
		create_all_button.pressed.connect(_on_create_all_suggested_tasks.bind(recommendations))
	
	if create_selected_button and not create_selected_button.pressed.is_connected(_on_create_selected_suggested_tasks):
		create_selected_button.pressed.connect(_on_create_selected_suggested_tasks.bind(recommendations))

func _show_batch_task_creation_dialog():
	"""Show batch task creation dialog"""
	var batch_dialog = AcceptDialog.new()
	batch_dialog.title = "Batch Task Creation"
	batch_dialog.size = Vector2(700, 500)
	
	var main_container = VBoxContainer.new()
	
	# Instructions
	var instructions = Label.new()
	instructions.text = "Create multiple tasks from the current edit session with different configurations:"
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(instructions)
	
	# Quick presets
	var presets_container = VBoxContainer.new()
	var presets_label = Label.new()
	presets_label.text = "Quick Presets:"
	presets_container.add_child(presets_label)
	
	var preset_buttons = HBoxContainer.new()
	
	var review_preset = Button.new()
	review_preset.text = "Review Tasks"
	review_preset.tooltip_text = "Create review tasks for each document"
	
	var follow_up_preset = Button.new()
	follow_up_preset.text = "Follow-up Tasks"
	follow_up_preset.tooltip_text = "Create follow-up tasks based on session insights"
	
	var collaboration_preset = Button.new()
	collaboration_preset.text = "Collaboration Tasks"
	collaboration_preset.tooltip_text = "Create tasks for collaborative work"
	
	preset_buttons.add_child(review_preset)
	preset_buttons.add_child(follow_up_preset)
	preset_buttons.add_child(collaboration_preset)
	presets_container.add_child(preset_buttons)
	main_container.add_child(presets_container)
	
	batch_dialog.add_child(main_container)
	add_child(batch_dialog)
	
	# Connect preset buttons
	review_preset.pressed.connect(_create_review_tasks_preset.bind(batch_dialog))
	follow_up_preset.pressed.connect(_create_follow_up_tasks_preset.bind(batch_dialog))
	collaboration_preset.pressed.connect(_create_collaboration_tasks_preset.bind(batch_dialog))
	
	batch_dialog.popup_centered()

func _on_create_all_suggested_tasks(recommendations: Array):
	"""Create tasks for all suggestions"""
	_create_tasks_from_recommendations(recommendations)
	task_suggestions_dialog.hide()

func _on_create_selected_suggested_tasks(recommendations: Array):
	"""Create tasks for selected suggestions"""
	var selected_recommendations = []
	var suggestions_container = task_suggestions_dialog.get_node("VBoxContainer/ScrollContainer/SuggestionsContainer")
	
	if suggestions_container:
		for i in range(recommendations.size()):
			var checkbox = suggestions_container.get_node("PanelContainer%d/VBoxContainer/HBoxContainer/Suggestion_%d_CheckBox" % [i, i])
			if checkbox and checkbox.button_pressed:
				selected_recommendations.append(recommendations[i])
	
	if selected_recommendations.size() > 0:
		_create_tasks_from_recommendations(selected_recommendations)
		task_suggestions_dialog.hide()
	else:
		_show_error_dialog("No suggestions selected.")

func _create_tasks_from_recommendations(recommendations: Array):
	"""Create WorkplanTasks from AI recommendations"""
	var created_count = 0
	
	for rec in recommendations:
		var task = DocumentSessionManager.create_task_from_edit_session(
			rec.get("title", ""),
			rec.get("reason", "")
		)
		
		if task:
			# Apply recommendation properties
			task.priority = rec.get("priority", 1)
			task.estimated_duration = rec.get("estimated_duration", 60)
			
			if _add_task_to_workplan(task):
				created_count += 1
	
	if created_count > 0:
		_show_success_dialog("Successfully created %d tasks from AI suggestions!" % created_count)
		_update_task_list()
	else:
		_show_error_dialog("Failed to create tasks from suggestions.")

func _create_review_tasks_preset(dialog: AcceptDialog):
	"""Create review tasks preset"""
	var documents = DocumentSessionManager.get_active_documents()
	var task_configs = []
	
	for doc in documents:
		task_configs.append({
			"title": "Review %s" % doc.file_name,
			"notes": "Editorial review and quality check",
			"priority": 1,
			"estimated_duration": 30,
			"documents": [doc.file_name]
		})
	
	var created_tasks = DocumentSessionManager.create_multiple_tasks_from_session(task_configs)
	_add_multiple_tasks_to_workplan(created_tasks)
	
	dialog.hide()
	_show_success_dialog("Created %d review tasks!" % created_tasks.size())

func _create_follow_up_tasks_preset(dialog: AcceptDialog):
	"""Create follow-up tasks preset"""
	var task_configs = [
		{
			"title": "Follow-up: Session Review",
			"notes": "Review and validate changes from edit session",
			"priority": 1,
			"estimated_duration": 45
		},
		{
			"title": "Follow-up: Quality Assurance",
			"notes": "Perform quality check on edited documents",
			"priority": 2,
			"estimated_duration": 30
		}
	]
	
	var created_tasks = DocumentSessionManager.create_multiple_tasks_from_session(task_configs)
	_add_multiple_tasks_to_workplan(created_tasks)
	
	dialog.hide()
	_show_success_dialog("Created %d follow-up tasks!" % created_tasks.size())

func _create_collaboration_tasks_preset(dialog: AcceptDialog):
	"""Create collaboration tasks preset"""
	var collab_opportunities = DocumentSessionManager._identify_collaboration_opportunities()
	var task_configs = []
	
	for opportunity in collab_opportunities:
		match opportunity.type:
			"cross_functional_review":
				task_configs.append({
					"title": "Cross-Functional Review",
					"notes": opportunity.description,
					"priority": 2,
					"estimated_duration": 60
				})
			"collaborative_editing":
				task_configs.append({
					"title": "Collaborative Review: %s" % opportunity.document,
					"notes": opportunity.description,
					"priority": 1,
					"estimated_duration": 45
				})
	
	if task_configs.is_empty():
		task_configs.append({
			"title": "Team Review Session",
			"notes": "Collaborative review of edit session changes",
			"priority": 1,
			"estimated_duration": 60
		})
	
	var created_tasks = DocumentSessionManager.create_multiple_tasks_from_session(task_configs)
	_add_multiple_tasks_to_workplan(created_tasks)
	
	dialog.hide()
	_show_success_dialog("Created %d collaboration tasks!" % created_tasks.size())

func _add_task_to_workplan(task: WorkplanTask) -> bool:
	"""Add a single task to the current workplan"""
	if orchestrator and orchestrator.workplan:
		orchestrator.add_task_to_month("Month 1", task)
		return true
	return false

func _add_multiple_tasks_to_workplan(tasks: Array):
	"""Add multiple tasks to the current workplan"""
	var added_count = 0
	for task in tasks:
		if _add_task_to_workplan(task):
			added_count += 1
	
	if added_count > 0:
		_update_task_list()

func _show_success_dialog(message: String):
	"""Show success dialog with green color theme"""
	var dialog = AcceptDialog.new()
	dialog.title = "Success"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

func _format_recommendations_as_bbcode(recommendations: Array) -> String:
	"""Format recommendations as BBCode"""
	var bbcode = "[b][color=orange]💡 Improvement Recommendations[/color][/b]\n\n"
	
	for rec in recommendations:
		var priority_color = "green"
		match rec.priority:
			"high": priority_color = "red"
			"medium": priority_color = "orange"
			"low": priority_color = "gray"
		
		bbcode += "[b][color=%s]%s[/color][/b] ([color=%s]%s priority[/color])\n" % [priority_color, rec.title, priority_color, rec.priority]
		bbcode += "%s\n\n" % rec.description
	
	return bbcode

func _format_timeline_as_bbcode(timeline: Array) -> String:
	"""Format change timeline as BBCode"""
	var bbcode = "[b][color=cyan]⏱️ Change Timeline[/color][/b]\n\n"
	
	var recent_changes = timeline.slice(-20)  # Last 20 changes
	
	for change in recent_changes:
		var time_str = Time.get_datetime_string_from_unix_time(change.timestamp)
		var significance = "[color=red]●[/color]" if change.significant else "[color=gray]○[/color]"
		
		bbcode += "%s [color=blue]%s[/color] - [color=green]%s[/color]\n" % [significance, time_str, change.document]
		bbcode += "   %s ([color=purple]%s[/color])\n\n" % [change.description, change.edit_mode]
	
	if timeline.size() > 20:
		bbcode += "[color=gray]... and %d earlier changes[/color]\n" % (timeline.size() - 20)
	
	return bbcode

func _format_session_history_as_bbcode() -> String:
	"""Format session history as BBCode"""
	var bbcode = "[b]Session Change History[/b]\n\n"
	
	var session_summary = DocumentSessionManager.get_session_change_summary()
	var lines = session_summary.split("\n")
	
	for line in lines:
		if line.begins_with("Edit Session Change Summary"):
			bbcode += "[b][color=blue]" + line + "[/color][/b]\n"
		elif line.begins_with("="):
			bbcode += "[color=gray]" + line + "[/color]\n"
		elif line.begins_with("Session Overview:"):
			bbcode += "\n[b][color=green]" + line + "[/color][/b]\n"
		elif line.begins_with("Document Details:"):
			bbcode += "\n[b][color=orange]" + line + "[/color][/b]\n"
		elif line.begins_with("•"):
			bbcode += "[color=cyan]" + line + "[/color]\n"
		elif line.strip_edges().ends_with("(PRIMARY)"):
			bbcode += "\n[b][color=purple]" + line + "[/color][/b]\n"
		elif line.strip_edges().match("*. *"):
			bbcode += "\n[b]" + line + "[/b]\n"
		elif line.strip_edges().is_empty():
			bbcode += "\n"
		else:
			bbcode += line + "\n"
	
	return bbcode

func _format_document_history_as_bbcode(document: DocumentSessionManager.DocumentContext) -> String:
	"""Format individual document history as BBCode"""
	var bbcode = "[b]Document: %s[/b]\n\n" % document.file_name
	
	var change_summary = document.generate_change_summary()
	var lines = change_summary.split("\n")
	
	for line in lines:
		if line.begins_with("Document Change Summary"):
			bbcode += "[b][color=blue]" + line + "[/color][/b]\n"
		elif line.begins_with("•"):
			bbcode += "[color=green]" + line + "[/color]\n"
		elif line.begins_with("Significant Changes:"):
			bbcode += "\n[b][color=orange]" + line + "[/color][/b]\n"
		elif line.strip_edges().is_empty():
			bbcode += "\n"
		else:
			bbcode += line + "\n"
	
	return bbcode

func _format_session_statistics_as_bbcode() -> String:
	"""Format session statistics as BBCode"""
	var bbcode = "[b]Session Statistics[/b]\n\n"
	
	var stats = DocumentSessionManager._calculate_session_statistics()
	
	bbcode += "[b]📊 Overall Statistics[/b]\n"
	bbcode += "• Total Documents: [color=blue]%d[/color]\n" % stats.total_documents
	bbcode += "• Total Words: [color=green]%d[/color]\n" % stats.total_words
	bbcode += "• Total Edits: [color=orange]%d[/color]\n" % stats.total_edits
	bbcode += "• Documents with Changes: [color=red]%d[/color]\n" % stats.documents_with_changes
	
	if stats.total_time_span > 0:
		var hours = stats.total_time_span / 3600
		var minutes = (stats.total_time_span % 3600) / 60
		bbcode += "• Session Duration: [color=purple]%d hours, %d minutes[/color]\n" % [hours, minutes]
	
	if stats.edit_modes_used.size() > 0:
		bbcode += "\n[b]🎯 Edit Modes Used[/b]\n"
		for mode in stats.edit_modes_used:
			bbcode += "• %s\n" % mode.capitalize()
	
	bbcode += "\n[b]📈 Document Breakdown[/b]\n"
	var documents = DocumentSessionManager.get_active_documents()
	for document in documents:
		var doc_stats = document.change_statistics
		bbcode += "\n[b]%s[/b] %s\n" % [document.file_name, "(PRIMARY)" if document.is_primary else ""]
		bbcode += "• Words: %d\n" % document.word_count
		bbcode += "• Edits: %d\n" % doc_stats.get("total_edits", 0)
		bbcode += "• Velocity: %.1f changes/min\n" % doc_stats.get("change_velocity", 0.0)
		bbcode += "• Status: %s\n" % ("Unsaved Changes" if document.has_unsaved_changes() else "Saved")
	
	return bbcode

func _save_session_analysis_to_file(data: Dictionary, path: String):
	"""Save session analysis data to file"""
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		_show_error_dialog("Failed to create export file: " + path)
		return
	
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	
	_show_info_dialog("Session analysis exported successfully to:\n" + path)

# SynTreeDocumentProcessor signal handlers
func _on_document_analysis_completed(document: DocumentSessionManager.DocumentContext, analysis: Dictionary):
	"""Handle document analysis completion from SynTree processor"""
	print("MissionControl: Document analysis completed for: ", document.file_name)
	_update_syntree_analysis_ui(document, analysis, true)

func _on_document_analysis_failed(document: DocumentSessionManager.DocumentContext, error: String):
	"""Handle document analysis failure from SynTree processor"""
	print("MissionControl: Document analysis failed for %s: %s" % [document.file_name, error])
	_update_syntree_analysis_ui(document, {}, false)

func _on_syntree_processing_started(document: DocumentSessionManager.DocumentContext):
	"""Handle start of SynTree document processing"""
	print("MissionControl: Started SynTree analysis for: ", document.file_name)
	_show_syntree_processing_status(document.file_name)

func _update_edit_session_ui():
	"""Update the edit session UI to reflect current state"""
	if not DocumentSessionManager:
		return
	
	var documents = DocumentSessionManager.get_active_documents()
	var summary = DocumentSessionManager.get_session_summary()
	
	# Update documents list
	active_documents_list.clear()
	for document in documents:
		var item_text = document.file_name
		if document.is_primary:
			item_text = "🎯 " + item_text
		if document.has_unsaved_changes():
			item_text = item_text + " *"
		
		active_documents_list.add_item(item_text)
	
	# Update session info
	if documents.size() == 0:
		session_info_label.text = "No documents loaded"
	else:
		session_info_label.text = "%d documents | %d words | Primary: %s" % [
			summary.document_count,
			summary.total_words,
			summary.primary_document
		]
		
		if summary.unsaved_changes > 0:
			session_info_label.text += " | %d unsaved" % summary.unsaved_changes
	
	# Update button states
	var has_selection = not active_documents_list.get_selected_items().is_empty()
	var has_documents = documents.size() > 0
	
	if has_selection and has_documents:
		var selected_doc = documents[active_documents_list.get_selected_items()[0]]
		set_primary_button.disabled = selected_doc.is_primary
	else:
		set_primary_button.disabled = true
	
	remove_doc_button.disabled = not has_selection
	clear_session_button.disabled = not has_documents
	
	# Update multi-document context information
	_update_document_context_ui()
	
	# Update context mode selector
	_update_context_mode_selector(document_context_mode)
	
	print("MissionControl: Edit session UI updated - %d documents" % documents.size())

# Multi-Document Context Management Functions
func _update_document_context_ui():
	"""Update UI elements related to document context management"""
	if not DocumentSessionManager:
		return
	
	var documents = DocumentSessionManager.get_active_documents()
	
	# Update context mode availability
	if documents.size() > 1:
		# Enable multi-document context options
		_set_context_mode_enabled(true)
		_update_document_relationships()
	else:
		# Only single document context available
		_set_context_mode_enabled(false)
		document_context_mode = "single_document"

func _set_context_mode_enabled(enabled: bool):
	"""Enable or disable multi-document context mode"""
	# For now, we'll handle this in the background
	# UI components for context mode will be added in future updates
	if enabled:
		print("MissionControl: Multi-document context available")
	else:
		print("MissionControl: Single document context only")

func _update_document_relationships():
	"""Update the display of document relationships"""
	if not DocumentSessionManager:
		return
	
	var context = DocumentSessionManager.get_multi_document_context()
	var relationships = context.get("relationships", [])
	
	if relationships.is_empty():
		print("MissionControl: No document relationships detected")
		return
	
	print("MissionControl: Found %d document relationships:" % relationships.size())
	for relationship in relationships:
		print("  - %s <-> %s: %s (%.2f similarity)" % [
			relationship.doc1_name,
			relationship.doc2_name, 
			relationship.relationship_type,
			relationship.similarity
		])

func get_current_document_context() -> Dictionary:
	"""Get current document context based on selected mode"""
	if not DocumentSessionManager:
		return {}
	
	match document_context_mode:
		"single_document":
			return DocumentSessionManager.get_document_context_for_llm(false)
		"multi_document":
			return DocumentSessionManager.get_document_context_for_llm(true)
		"auto":
			# Auto mode: use multi-document if more than 1 document and they're related
			var documents = DocumentSessionManager.get_active_documents()
			if documents.size() > 1:
				var context = DocumentSessionManager.get_multi_document_context()
				var relationships = context.get("relationships", [])
				# Use multi-document context if any relationships are found
				var has_relationships = false
				for rel in relationships:
					if rel.similarity > 0.2:  # Threshold for auto-inclusion
						has_relationships = true
						break
				return DocumentSessionManager.get_document_context_for_llm(has_relationships)
			else:
				return DocumentSessionManager.get_document_context_for_llm(false)
		_:
			return DocumentSessionManager.get_document_context_for_llm(false)

func set_document_context_mode(mode: String):
	"""Set the document context mode"""
	if mode in context_modes:
		document_context_mode = mode
		print("MissionControl: Document context mode changed to: ", mode)
		_update_document_context_ui()
	else:
		push_error("MissionControl: Invalid context mode: " + mode)

func get_document_context_mode() -> String:
	"""Get the current document context mode"""
	return document_context_mode

func get_context_summary_for_display() -> String:
	"""Get a formatted context summary for UI display"""
	var context = get_current_document_context()
	var summary = "Context Mode: %s\n" % context_mode_display_names.get(document_context_mode, document_context_mode)
	
	if context.has("primary_document") and context.primary_document:
		summary += "Primary: %s (%d words)\n" % [
			context.primary_document.name,
			context.primary_document.word_count
		]
	
	if context.get("context_type") == "multi_document" and context.has("supporting_documents"):
		summary += "Supporting Documents: %d\n" % context.supporting_documents.size()
		for doc in context.supporting_documents:
			summary += "  - %s (%d words)\n" % [doc.name, doc.word_count]
	
	return summary

func load_additional_document():
	"""Load an additional document to the session"""
	# This uses the same document loading functionality but with different messaging
	print("MissionControl: Loading additional document for multi-document session")
	_on_load_document_pressed()

func compare_selected_documents():
	"""Compare selected documents in the session"""
	var selected_items = active_documents_list.get_selected_items()
	if selected_items.size() < 1:
		_show_error_dialog("Please select a document to compare.")
		return
	
	var documents = DocumentSessionManager.get_active_documents()
	if selected_items[0] >= documents.size():
		return
	
	var selected_doc = documents[selected_items[0]]
	var primary_doc = DocumentSessionManager.get_primary_document()
	
	if not primary_doc or selected_doc == primary_doc:
		_show_error_dialog("Please select a different document to compare with the primary document.")
		return
	
	# Show comparison information
	var comparison = DocumentSessionManager._compare_documents(primary_doc, selected_doc)
	var comparison_text = "Comparison: %s vs %s\n\n" % [primary_doc.file_name, selected_doc.file_name]
	comparison_text += "Similarity: %.1f%%\n" % (comparison.similarity * 100)
	comparison_text += "Relationship: %s\n\n" % comparison.relationship_type
	
	if comparison.common_keywords.size() > 0:
		comparison_text += "Common keywords: %s" % ", ".join(comparison.common_keywords.slice(0, 5))
	
	_show_info_dialog(comparison_text)

