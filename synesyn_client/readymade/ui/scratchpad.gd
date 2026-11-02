extends VBoxContainer

@onready var text_edit = $MarginContainer/VBoxContainer/TextEdit
@onready var open_dialog = $OpenDialog
@onready var save_dialog = $SaveDialog
@onready var new_button = $MarginContainer/VBoxContainer/PanelContainer/HBoxContainer/NewButton
@onready var open_button = $MarginContainer/VBoxContainer/PanelContainer/HBoxContainer/OpenButton
@onready var save_button = $MarginContainer/VBoxContainer/PanelContainer/HBoxContainer/SaveButton
@onready var paste_button = $MarginContainer/VBoxContainer/PanelContainer/HBoxContainer/PasteButton

# Document editing mode variables
var enhanced_document_mode: bool = false
var current_document_context = null  # DocumentSessionManager.DocumentContext
var selection_start: int = -1
var selection_end: int = -1
var original_placeholder_text: String = ""

# Selection tracking variables
var last_caret_line: int = -1
var last_caret_column: int = -1

# Change tracking and visualization
var change_markers_visible: bool = false
var change_history_panel: Control = null
var change_summary_label: Label = null
var auto_save_timer: Timer = null

func _ready():
	# Add to scratchpad group for easy discovery
	add_to_group("scratchpad")
	
	# Store original placeholder text
	original_placeholder_text = text_edit.placeholder_text
	_configure_text_edit_for_editing()
	
	# Connect dialog signals (only if not already connected)
	if not open_dialog.is_connected("file_selected", Callable(self, "_on_open_dialog_file_selected")):
		open_dialog.file_selected.connect(_on_open_dialog_file_selected)
	if not save_dialog.is_connected("file_selected", Callable(self, "_on_save_dialog_file_selected")):
		save_dialog.file_selected.connect(_on_save_dialog_file_selected)
	
	# Connect button signals (only if not already connected)
	if not new_button.is_connected("pressed", Callable(self, "_on_new_button_pressed")):
		new_button.pressed.connect(_on_new_button_pressed)
	if not open_button.is_connected("pressed", Callable(self, "_on_open_button_pressed")):
		open_button.pressed.connect(_on_open_button_pressed)
	if not save_button.is_connected("pressed", Callable(self, "_on_save_button_pressed")):
		save_button.pressed.connect(_on_save_button_pressed)
	if paste_button and not paste_button.is_connected("pressed", Callable(self, "_on_paste_button_pressed")):
		paste_button.pressed.connect(_on_paste_button_pressed)
	
	# Connect text edit signals for selection tracking
	text_edit.caret_changed.connect(_on_text_edit_caret_changed)
	text_edit.text_changed.connect(_on_text_edit_text_changed)
	
	# Setup change tracking
	_setup_change_tracking()
	
	# Connect to DocumentSessionManager if available
	call_deferred("_connect_to_document_session_manager")

func _connect_to_document_session_manager():
	"""Connect to DocumentSessionManager signals"""
	if DocumentSessionManager:
		DocumentSessionManager.primary_document_changed.connect(_on_primary_document_changed)
		DocumentSessionManager.session_cleared.connect(_on_session_cleared)
		print("Scratchpad: ✅ Connected to DocumentSessionManager")
		
		# Check current workflow to set enhanced mode
		if WorkflowManager and WorkflowManager.get_current_workflow_name() == "edit_session":
			set_enhanced_document_mode(true)
		
		# Connect to workflow changes
		if WorkflowManager:
			WorkflowManager.workflow_changed.connect(_on_workflow_changed)
	else:
		print("Scratchpad: ⚠️ DocumentSessionManager not available")

func _on_new_button_pressed():
	if enhanced_document_mode and current_document_context:
		# In document mode, clear current document
		current_document_context.update_content("")
		text_edit.text = ""
	else:
		text_edit.clear()

func _on_open_button_pressed():
	if enhanced_document_mode:
		# In document mode, suggest loading through DocumentSessionManager
		_show_info_dialog("To load documents in Edit Session mode, use the 'Load Document' button in the left panel.")
	else:
		open_dialog.popup_centered()

func _configure_text_edit_for_editing() -> void:
	text_edit.editable = true
	text_edit.shortcut_keys_enabled = true
	text_edit.context_menu_enabled = true
	text_edit.selecting_enabled = true
	text_edit.focus_mode = Control.FOCUS_ALL
	text_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY

func _on_paste_button_pressed() -> void:
	var clipboard_text: String = DisplayServer.clipboard_get()
	if clipboard_text.is_empty():
		return
	text_edit.grab_focus()
	text_edit.insert_text_at_caret(clipboard_text)

func _on_save_button_pressed():
	if enhanced_document_mode and current_document_context:
		# In document mode, save current document
		if current_document_context.file_path.is_empty():
			save_dialog.popup_centered()
		else:
			_save_current_document()
	else:
		save_dialog.popup_centered()

func _on_open_dialog_file_selected(path: String):
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		
		if enhanced_document_mode and DocumentSessionManager:
			# Load through DocumentSessionManager
			DocumentSessionManager.load_document(path)
		else:
			text_edit.text = content

func _on_save_dialog_file_selected(path: String):
	if enhanced_document_mode and current_document_context:
		# Save current document to new path
		DocumentSessionManager.save_document_as(current_document_context, path)
	else:
		var file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text_edit.text)
		file.close()

# Enhanced Document Mode Functions
func set_enhanced_document_mode(enabled: bool):
	"""Enable or disable enhanced document editing mode"""
	enhanced_document_mode = enabled
	
	if enabled:
		text_edit.placeholder_text = "📝 Document editing mode - Load a document to begin editing"
		# Update visual indicators
		_update_document_mode_ui()
		print("Scratchpad: Enhanced document mode enabled")
	else:
		text_edit.placeholder_text = original_placeholder_text
		current_document_context = null
		print("Scratchpad: Enhanced document mode disabled")

func load_document_content(document):
	"""Load document content into the scratchpad"""
	if not enhanced_document_mode:
		return
	
	current_document_context = document
	text_edit.text = document.content
	
	# Update UI to show document info
	_update_document_mode_ui()
	print("Scratchpad: Loaded document content: ", document.file_name)

func get_selected_text() -> String:
	"""Get currently selected text"""
	return text_edit.get_selected_text()

func get_selection_context(context_lines: int = 2) -> Dictionary:
	"""Get context around current selection"""
	var selected_text = get_selected_text()
	if selected_text.is_empty():
		return {}
	
	var lines = text_edit.text.split("\n")
	var start_line = text_edit.get_caret_line() - context_lines
	var end_line = text_edit.get_caret_line() + context_lines
	
	# Clamp to valid range
	start_line = max(0, start_line)
	end_line = min(lines.size() - 1, end_line)
	
	var context_text = ""
	for i in range(start_line, end_line + 1):
		if i < lines.size():
			context_text += lines[i] + "\n"
	
	return {
		"selected_text": selected_text,
		"context_text": context_text,
		"selection_start": selection_start,
		"selection_end": selection_end,
		"line_number": text_edit.get_caret_line(),
		"column_number": text_edit.get_caret_column()
	}

func update_document_content():
	"""Update the current document with scratchpad content"""
	if enhanced_document_mode and current_document_context:
		current_document_context.update_content(text_edit.text)
		print("Scratchpad: Updated document content")

# Signal handlers
func _on_text_edit_caret_changed():
	"""Handle caret position changes for selection tracking"""
	var new_line = text_edit.get_caret_line()
	var new_column = text_edit.get_caret_column()
	
	if new_line != last_caret_line or new_column != last_caret_column:
		last_caret_line = new_line
		last_caret_column = new_column
		
		# Update selection if text is selected
		if text_edit.has_selection():
			selection_start = text_edit.get_selection_from_line() * 1000 + text_edit.get_selection_from_column()
			selection_end = text_edit.get_selection_to_line() * 1000 + text_edit.get_selection_to_column()
		else:
			selection_start = -1
			selection_end = -1

func _on_text_edit_text_changed():
	"""Handle text changes to update document content"""
	if enhanced_document_mode and current_document_context:
		# Start auto-save timer to batch changes
		if auto_save_timer:
			auto_save_timer.start()
		
		# Update change visualization
		_update_change_visualization()

func _on_workflow_changed(new_workflow: String):
	"""Handle workflow changes"""
	if new_workflow == "edit_session":
		set_enhanced_document_mode(true)
	else:
		set_enhanced_document_mode(false)

func _on_primary_document_changed(document):
	"""Handle primary document changes"""
	if enhanced_document_mode:
		load_document_content(document)

func _on_session_cleared():
	"""Handle session cleared"""
	if enhanced_document_mode:
		current_document_context = null
		text_edit.text = ""
		_update_document_mode_ui()

# Helper functions

func _save_current_document():
	"""Save the current document"""
	if current_document_context and DocumentSessionManager:
		update_document_content()  # Sync content first
		var success = DocumentSessionManager.save_document(current_document_context)
		if success:
			_show_info_dialog("Document saved successfully!")
		else:
			_show_error_dialog("Failed to save document.")

func _show_info_dialog(message: String):
	"""Show an info dialog"""
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

func _show_error_dialog(message: String):
	"""Show an error dialog"""
	var dialog = AcceptDialog.new()
	dialog.dialog_text = "Error: " + message
	dialog.title = "Error"
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

# === CHANGE TRACKING AND VISUALIZATION ===

func _setup_change_tracking():
	"""Initialize change tracking and visualization components"""
	# Create auto-save timer
	auto_save_timer = Timer.new()
	auto_save_timer.wait_time = 2.0  # 2 second delay
	auto_save_timer.one_shot = true
	auto_save_timer.timeout.connect(_on_auto_save_timeout)
	add_child(auto_save_timer)
	
	# Create change summary label
	change_summary_label = Label.new()
	change_summary_label.text = ""
	change_summary_label.modulate = Color(0.8, 0.8, 0.8, 1.0)
	change_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Add change summary to the UI (after the TextEdit)
	var text_container = $MarginContainer/VBoxContainer
	text_container.add_child(change_summary_label)
	text_container.move_child(change_summary_label, text_container.get_child_count() - 1)
	
	print("Scratchpad: Change tracking initialized")

func _on_auto_save_timeout():
	"""Handle auto-save timer timeout"""
	if enhanced_document_mode and current_document_context:
		update_document_content()
		_update_change_summary()

func _update_change_visualization():
	"""Update visual indicators of changes"""
	if not enhanced_document_mode or not current_document_context:
		return
	
	# Update change summary
	_update_change_summary()
	
	# Update change markers if visible
	if change_markers_visible:
		_display_change_markers()

func _update_change_summary():
	"""Update the change summary display"""
	if not change_summary_label or not current_document_context:
		return
	
	var stats = current_document_context.change_statistics
	var total_edits = stats.get("total_edits", 0)
	var words_added = stats.get("words_added", 0)
	var words_removed = stats.get("words_removed", 0)
	var velocity = stats.get("change_velocity", 0.0)
	
	var summary = ""
	if total_edits > 0:
		summary = "📊 Edits: %d | Words: +%d/-%d | Velocity: %.1f/min" % [
			total_edits, words_added, words_removed, velocity
		]
		
		if current_document_context.has_unsaved_changes():
			summary += " | ⚠️ Unsaved"
		else:
			summary += " | ✅ Saved"
	
	change_summary_label.text = summary

func toggle_change_markers():
	"""Toggle visibility of change markers"""
	change_markers_visible = not change_markers_visible
	
	if change_markers_visible:
		_display_change_markers()
		print("Scratchpad: Change markers enabled")
	else:
		_hide_change_markers()
		print("Scratchpad: Change markers disabled")

func _display_change_markers():
	"""Display visual change markers in the text"""
	if not current_document_context:
		return
	
	# Get change markers from document
	var markers = current_document_context.get_change_markers_for_visualization()
	
	# Add visual highlighting for recent changes
	# This is a simplified implementation - could be enhanced with actual text highlighting
	print("Scratchpad: Displaying %d change markers" % markers.size())

func _hide_change_markers():
	"""Hide change markers"""
	# Remove any highlighting
	print("Scratchpad: Change markers hidden")

func show_change_history():
	"""Show detailed change history dialog"""
	if not enhanced_document_mode or not current_document_context:
		_show_info_dialog("No document loaded for change history.")
		return
	
	var history_summary = current_document_context.get_change_history_summary()
	var change_summary = current_document_context.generate_change_summary()
	
	# Create change history dialog
	var dialog = AcceptDialog.new()
	dialog.title = "Change History - " + current_document_context.file_name
	dialog.size = Vector2(700, 500)
	
	var container = VBoxContainer.new()
	
	# Add tabs for different views
	var tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Summary tab
	var summary_scroll = ScrollContainer.new()
	var summary_label = RichTextLabel.new()
	summary_label.fit_content = true
	summary_label.bbcode_enabled = true
	summary_label.text = _format_change_summary_as_bbcode(change_summary)
	summary_scroll.add_child(summary_label)
	tab_container.add_child(summary_scroll)
	tab_container.set_tab_title(0, "Summary")
	
	# Recent changes tab
	var recent_scroll = ScrollContainer.new()
	var recent_label = RichTextLabel.new()
	recent_label.fit_content = true
	recent_label.bbcode_enabled = true
	recent_label.text = _format_recent_changes_as_bbcode(history_summary.recent_changes)
	recent_scroll.add_child(recent_label)
	tab_container.add_child(recent_scroll)
	tab_container.set_tab_title(1, "Recent Changes")
	
	# Statistics tab
	var stats_scroll = ScrollContainer.new()
	var stats_label = RichTextLabel.new()
	stats_label.fit_content = true
	stats_label.bbcode_enabled = true
	stats_label.text = _format_statistics_as_bbcode(history_summary.statistics)
	stats_scroll.add_child(stats_label)
	tab_container.add_child(stats_scroll)
	tab_container.set_tab_title(2, "Statistics")
	
	container.add_child(tab_container)
	dialog.add_child(container)
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

func _format_change_summary_as_bbcode(summary: String) -> String:
	"""Format change summary with BBCode styling"""
	var lines = summary.split("\n")
	var formatted = ""
	
	for line in lines:
		if line.begins_with("Document Change Summary"):
			formatted += "[b][color=blue]" + line + "[/color][/b]\n"
		elif line.begins_with("•"):
			formatted += "[color=green]" + line + "[/color]\n"
		elif line.begins_with("Significant Changes:"):
			formatted += "\n[b][color=orange]" + line + "[/color][/b]\n"
		elif line.strip_edges().is_empty():
			formatted += "\n"
		else:
			formatted += line + "\n"
	
	return formatted

func _format_recent_changes_as_bbcode(recent_changes: Array) -> String:
	"""Format recent changes list with BBCode styling"""
	var formatted = "[b]Recent Changes[/b]\n\n"
	
	if recent_changes.is_empty():
		formatted += "[i]No recent changes to display.[/i]"
		return formatted
	
	for i in range(recent_changes.size()):
		var change = recent_changes[i]
		var time_str = Time.get_datetime_string_from_unix_time(change.timestamp)
		var significance = "[color=red]Major[/color]" if change.significant else "[color=blue]Minor[/color]"
		
		formatted += "[b]%d.[/b] %s\n" % [i + 1, time_str]
		formatted += "   Type: %s | Significance: %s\n" % [change.type.capitalize(), significance]
		formatted += "   Description: %s\n" % change.description
		
		if change.edit_mode != "":
			formatted += "   Edit Mode: [color=purple]%s[/color]\n" % change.edit_mode.capitalize()
		
		formatted += "\n"
	
	return formatted

func _format_statistics_as_bbcode(statistics: Dictionary) -> String:
	"""Format statistics with BBCode styling"""
	var formatted = "[b]Document Change Statistics[/b]\n\n"
	
	formatted += "[b]📊 Edit Counts[/b]\n"
	formatted += "• Total Edits: [color=blue]%d[/color]\n" % statistics.get("total_edits", 0)
	formatted += "• Words Added: [color=green]+%d[/color]\n" % statistics.get("words_added", 0)
	formatted += "• Words Removed: [color=red]-%d[/color]\n" % statistics.get("words_removed", 0)
	formatted += "• Characters Added: [color=green]+%d[/color]\n" % statistics.get("characters_added", 0)
	formatted += "• Characters Removed: [color=red]-%d[/color]\n" % statistics.get("characters_removed", 0)
	
	formatted += "\n[b]⚡ Performance Metrics[/b]\n"
	formatted += "• Edit Velocity: [color=orange]%.1f changes/minute[/color]\n" % statistics.get("change_velocity", 0.0)
	formatted += "• Time Spent Editing: [color=purple]%d minutes[/color]\n" % (statistics.get("time_spent_editing", 0) / 60)
	
	var modes_used = statistics.get("edit_modes_used", [])
	if modes_used.size() > 0:
		formatted += "\n[b]🎯 Edit Modes Used[/b]\n"
		for mode in modes_used:
			formatted += "• %s\n" % mode.capitalize()
	
	var last_significant = statistics.get("last_significant_change", 0)
	if last_significant > 0:
		var time_str = Time.get_datetime_string_from_unix_time(last_significant)
		formatted += "\n[b]🕒 Last Significant Change[/b]\n"
		formatted += time_str + "\n"
	
	return formatted

func export_change_history():
	"""Export change history to file"""
	if not enhanced_document_mode or not current_document_context:
		_show_info_dialog("No document loaded for export.")
		return
	
	var export_data = current_document_context.export_change_history()
	
	var file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.json", "JSON Files")
	file_dialog.current_file = current_document_context.file_name.get_basename() + "_change_history.json"
	
	file_dialog.file_selected.connect(func(path: String):
		_save_change_history_to_file(export_data, path)
		file_dialog.queue_free()
	)
	
	get_tree().current_scene.add_child(file_dialog)
	file_dialog.popup_centered(Vector2(800, 600))

func _save_change_history_to_file(data: Dictionary, path: String):
	"""Save change history data to file"""
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		_show_error_dialog("Failed to create export file: " + path)
		return
	
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	
	_show_info_dialog("Change history exported successfully to:\n" + path)

func compare_with_original():
	"""Show comparison with original document content"""
	if not enhanced_document_mode or not current_document_context:
		_show_info_dialog("No document loaded for comparison.")
		return
	
	var dialog = AcceptDialog.new()
	dialog.title = "Compare with Original - " + current_document_context.file_name
	dialog.size = Vector2(800, 600)
	
	var hsplit = HSplitContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Original content
	var original_container = VBoxContainer.new()
	var original_label = Label.new()
	original_label.text = "Original Content"
	original_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var original_text = TextEdit.new()
	original_text.text = current_document_context.original_content
	original_text.editable = false
	original_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	original_container.add_child(original_label)
	original_container.add_child(original_text)
	
	# Current content
	var current_container = VBoxContainer.new()
	var current_label = Label.new()
	current_label.text = "Current Content"
	current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var current_text = TextEdit.new()
	current_text.text = current_document_context.content
	current_text.editable = false
	current_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	current_container.add_child(current_label)
	current_container.add_child(current_text)
	
	hsplit.add_child(original_container)
	hsplit.add_child(current_container)
	hsplit.split_offset = 400
	
	dialog.add_child(hsplit)
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

# Enhanced document mode UI updates
func _update_document_mode_ui():
	"""Update UI elements for document mode with change tracking"""
	if not enhanced_document_mode:
		return
	
	if current_document_context:
		# Update change summary
		_update_change_summary()
		
		# Update document info
		var _doc_info = "📝 Editing: %s" % current_document_context.file_name
		if current_document_context.has_unsaved_changes():
			_doc_info += " *"
		
		# Add edit statistics
		var stats = current_document_context.change_statistics
		if stats.get("total_edits", 0) > 0:
			_doc_info += " (%d edits)" % stats.get("total_edits", 0)
		
		# Add SynTree analysis info if available
		if current_document_context.syntree_analysis:
			var analysis = current_document_context.syntree_analysis
			var quality = analysis.get("quality_metrics", {}).get("overall_readability", 0.0)
			_doc_info += " | Quality: %.0f%%" % (quality * 100)
		
		# Could add a status label here for doc_info
	else:
		# Clear change summary when no document
		if change_summary_label:
			change_summary_label.text = ""

# SynTree Analysis Integration Functions
func get_current_document_analysis() -> Dictionary:
	"""Get SynTree analysis for the current document"""
	if not enhanced_document_mode or not current_document_context:
		return {}
	
	if current_document_context.syntree_analysis:
		return current_document_context.syntree_analysis
	
	# If no analysis exists, trigger one
	if SynTreeDocumentProcessor:
		SynTreeDocumentProcessor.process_document_with_syntree(current_document_context)
	
	return {}

func get_selection_analysis_context() -> String:
	"""Get analysis-enhanced context for selected text"""
	var selection_context = get_selection_context()
	if selection_context.is_empty():
		return ""
	
	var analysis = get_current_document_analysis()
	if analysis.is_empty():
		return selection_context.get("context_text", "")
	
	# Enhanced context with analysis information
	var enhanced_context = "Selected Text Analysis Context:\n\n"
	enhanced_context += "Selection: \"%s\"\n\n" % selection_context.get("selected_text", "")
	enhanced_context += "Context:\n%s\n" % selection_context.get("context_text", "")
	
	# Add relevant analysis info
	var stats = analysis.get("statistics", {})
	var quality = analysis.get("quality_metrics", {})
	
	enhanced_context += "Document Analysis:\n"
	enhanced_context += "- Document Length: %s (%d words)\n" % [
		stats.get("document_length_category", "unknown"),
		stats.get("total_words", 0)
	]
	enhanced_context += "- Readability: %.0f%%\n" % (quality.get("overall_readability", 0.0) * 100)
	enhanced_context += "- Structure Quality: %.0f%%\n" % (quality.get("structure_quality", 0.0) * 100)
	
	# Find which section this selection belongs to
	var nodes = analysis.get("nodes", [])
	var line_number = selection_context.get("line_number", 0)
	var relevant_section = _find_section_for_line(nodes, line_number)
	
	if relevant_section:
		enhanced_context += "\nSection Context:\n"
		enhanced_context += "- Section: %s\n" % relevant_section.get("title", "Unknown")
		enhanced_context += "- Section Words: %d\n" % relevant_section.get("word_count", 0)
		enhanced_context += "- Section Quality: %.0f%%\n" % (relevant_section.get("readability_score", 0.0) * 100)
	
	return enhanced_context

func get_document_editing_suggestions() -> Array[String]:
	"""Get editing suggestions based on SynTree analysis"""
	var analysis = get_current_document_analysis()
	if analysis.is_empty():
		return []
	
	var suggestions = []
	var quality = analysis.get("quality_metrics", {})
	var structure = analysis.get("structure", {})
	var stats = analysis.get("statistics", {})
	
	# Readability suggestions
	var readability = quality.get("overall_readability", 0.0)
	if readability < 0.6:
		suggestions.append("Consider breaking up long sentences to improve readability")
	
	# Structure suggestions
	var has_sections = structure.get("has_clear_sections", false)
	if not has_sections and stats.get("total_words", 0) > 500:
		suggestions.append("Consider adding section headers to improve document structure")
	
	var balance = structure.get("section_balance", 1.0)
	if balance < 0.5:
		suggestions.append("Some sections are much longer than others - consider rebalancing content")
	
	var flow = structure.get("logical_flow", 1.0)
	if flow < 0.3:
		suggestions.append("Consider improving transitions between sections")
	
	# Consistency suggestions
	var consistency = quality.get("consistency_score", 1.0)
	if consistency < 0.6:
		suggestions.append("Writing style varies significantly - consider consistent tone and structure")
	
	# Completeness suggestions
	var completeness = quality.get("completeness_score", 1.0)
	if completeness < 0.5:
		suggestions.append("Document may benefit from additional content or better structure")
	
	# Length-based suggestions
	var word_count = stats.get("total_words", 0)
	if word_count < 100:
		suggestions.append("Document is quite short - consider expanding key points")
	elif word_count > 5000:
		suggestions.append("Document is quite long - consider breaking into multiple documents")
	
	return suggestions

func trigger_document_reanalysis():
	"""Manually trigger re-analysis of the current document"""
	if not enhanced_document_mode or not current_document_context:
		return
	
	# Update document content first
	update_document_content()
	
	# Trigger new analysis
	if SynTreeDocumentProcessor:
		print("Scratchpad: Triggering document re-analysis")
		SynTreeDocumentProcessor.process_document_with_syntree(current_document_context)

func _find_section_for_line(nodes: Array, line_number: int) -> Dictionary:
	"""Find which section/node contains the given line number"""
	# This is a simplified implementation
	# In practice, you'd need to track line numbers when creating nodes
	if nodes.is_empty():
		return {}
	
	# For simplicity, estimate based on document position
	var total_lines = text_edit.get_line_count()
	var section_index = int(float(line_number) / total_lines * nodes.size())
	section_index = clamp(section_index, 0, nodes.size() - 1)
	
	return nodes[section_index]

func show_document_analysis_summary():
	"""Show a dialog with comprehensive document analysis"""
	var analysis = get_current_document_analysis()
	if analysis.is_empty():
		_show_info_dialog("No analysis available. Analysis will begin automatically when you load a document.")
		return
	
	# Create summary dialog
	var dialog = AcceptDialog.new()
	dialog.title = "Document Analysis Summary"
	dialog.size = Vector2(600, 400)
	
	var scroll = ScrollContainer.new()
	var label = RichTextLabel.new()
	label.fit_content = true
	label.bbcode_enabled = true
	
	# Format analysis as BBCode
	var summary = _format_analysis_as_bbcode(analysis)
	label.text = summary
	
	scroll.add_child(label)
	dialog.add_child(scroll)
	
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func(): dialog.queue_free())

func _format_analysis_as_bbcode(analysis: Dictionary) -> String:
	"""Format analysis data as BBCode for rich text display"""
	var bbcode = "[b]Document Analysis Report[/b]\n\n"
	
	# Statistics
	var stats = analysis.get("statistics", {})
	bbcode += "[b]📊 Basic Statistics[/b]\n"
	bbcode += "• Word Count: %d\n" % stats.get("total_words", 0)
	bbcode += "• Character Count: %d\n" % stats.get("total_characters", 0)
	bbcode += "• Sentences: %d\n" % stats.get("total_sentences", 0)
	bbcode += "• Average Words per Sentence: %.1f\n" % stats.get("average_words_per_sentence", 0.0)
	bbcode += "• Document Length: %s\n\n" % stats.get("document_length_category", "unknown").capitalize()
	
	# Quality Metrics
	var quality = analysis.get("quality_metrics", {})
	bbcode += "[b]🎯 Quality Metrics[/b]\n"
	bbcode += "• Overall Readability: [color=green]%.0f%%[/color]\n" % (quality.get("overall_readability", 0.0) * 100)
	bbcode += "• Structure Quality: [color=blue]%.0f%%[/color]\n" % (quality.get("structure_quality", 0.0) * 100)
	bbcode += "• Content Density: [color=purple]%.0f%%[/color]\n" % (quality.get("content_density", 0.0) * 100)
	bbcode += "• Consistency: [color=orange]%.0f%%[/color]\n" % (quality.get("consistency_score", 0.0) * 100)
	bbcode += "• Completeness: [color=teal]%.0f%%[/color]\n\n" % (quality.get("completeness_score", 0.0) * 100)
	
	# Structure
	var structure = analysis.get("structure", {})
	bbcode += "[b]🏗️ Document Structure[/b]\n"
	bbcode += "• Sections: %d\n" % structure.get("node_count", 0)
	bbcode += "• Clear Sections: %s\n" % ("Yes" if structure.get("has_clear_sections", false) else "No")
	bbcode += "• Section Balance: %.0f%%\n" % (structure.get("section_balance", 0.0) * 100)
	bbcode += "• Logical Flow: %.0f%%\n\n" % (structure.get("logical_flow", 0.0) * 100)
	
	# Suggestions
	var suggestions = get_document_editing_suggestions()
	if not suggestions.is_empty():
		bbcode += "[b]💡 Editing Suggestions[/b]\n"
		for suggestion in suggestions:
			bbcode += "• %s\n" % suggestion
	
	return bbcode
