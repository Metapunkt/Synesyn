extends "res://readymade/ui/internal/mission_control_task_reporting_base.gd"
class_name MissionControlWorkplanSyntreeBase

func _show_workplan_manager_dialog():
	"""Create and show the workplan manager dialog"""
	var dialog = _create_workplan_manager_dialog()
	add_child(dialog)
	dialog.popup_centered(Vector2(600, 400))

func _create_workplan_manager_dialog() -> AcceptDialog:
	"""Create the workplan manager dialog"""
	var dialog = AcceptDialog.new()
	dialog.title = "Workplan Manager"
	dialog.set_flag(Window.FLAG_RESIZE_DISABLED, false)
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	# Current workplan info
	var current_info = Label.new()
	current_info.text = "Current Workplan: " + workplan_manager.get_current_workplan_name()
	current_info.theme_type_variation = "HeaderMedium"
	vbox.add_child(current_info)
	
	vbox.add_child(HSeparator.new())
	
	# Workplan list
	var list_label = Label.new()
	list_label.text = "Available Workplans:"
	vbox.add_child(list_label)
	
	var workplan_list = ItemList.new()
	workplan_list.custom_minimum_size = Vector2(0, 200)
	workplan_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var available_workplans = workplan_manager.get_available_workplans()
	for workplan_name in available_workplans:
		workplan_list.add_item(workplan_name)
	vbox.add_child(workplan_list)
	
	# Action buttons
	var button_container = HBoxContainer.new()
	vbox.add_child(button_container)
	
	var new_button = Button.new()
	new_button.text = "New Workplan"
	new_button.pressed.connect(_on_new_workplan_pressed.bind(dialog))
	button_container.add_child(new_button)
	
	var duplicate_button = Button.new()
	duplicate_button.text = "Duplicate"
	duplicate_button.pressed.connect(_on_duplicate_workplan_pressed.bind(dialog, workplan_list))
	button_container.add_child(duplicate_button)
	
	var rename_button = Button.new()
	rename_button.text = "Rename"
	rename_button.pressed.connect(_on_rename_workplan_pressed.bind(dialog, workplan_list))
	button_container.add_child(rename_button)
	
	var delete_button = Button.new()
	delete_button.text = "Delete"
	delete_button.modulate = Color.RED
	delete_button.pressed.connect(_on_delete_workplan_pressed.bind(dialog, workplan_list))
	button_container.add_child(delete_button)
	
	# Import/Export buttons
	var io_container = HBoxContainer.new()
	vbox.add_child(io_container)
	
	var import_button = Button.new()
	import_button.text = "Import Workplan"
	import_button.pressed.connect(_on_import_workplan_pressed.bind(dialog))
	io_container.add_child(import_button)
	
	var export_button = Button.new()
	export_button.text = "Export Workplan"
	export_button.pressed.connect(_on_export_workplan_pressed.bind(dialog, workplan_list))
	io_container.add_child(export_button)
	
	return dialog

# Workplan Manager Dialog Handlers
func _on_new_workplan_pressed(dialog: AcceptDialog):
	"""Handle new workplan creation"""
	var name_dialog = _create_text_input_dialog("New Workplan", "Enter workplan name:")
	add_child(name_dialog)
	
	# Connect signals with direct handling
	name_dialog.confirmed.connect(func(): 
		var workplan_name = name_dialog.get_meta("line_edit").text
		print("MissionControl: New workplan dialog confirmed with name: '", workplan_name, "'")
		name_dialog.queue_free()
		
		if not workplan_name.is_empty():
			if workplan_manager.create_new_workplan(workplan_name):
				print("MissionControl: ✅ Created new workplan: ", workplan_name)
				dialog.queue_free()
			else:
				_show_error_dialog("Failed to create workplan. Name may already exist.")
		else:
			_show_error_dialog("Please enter a workplan name.")
	)
	
	name_dialog.canceled.connect(func(): 
		print("MissionControl: New workplan dialog canceled")
		name_dialog.queue_free()
	)
	
	name_dialog.popup_centered()

func _on_duplicate_workplan_pressed(dialog: AcceptDialog, workplan_list: ItemList):
	"""Handle workplan duplication"""
	var selected_items = workplan_list.get_selected_items()
	if selected_items.is_empty():
		_show_error_dialog("Please select a workplan to duplicate.")
		return
	
	var source_name = workplan_list.get_item_text(selected_items[0])
	var name_dialog = _create_text_input_dialog("Duplicate Workplan", "Enter new name:", source_name + " Copy")
	add_child(name_dialog)
	
	# Connect signals with direct handling
	name_dialog.confirmed.connect(func(): 
		var new_name = name_dialog.get_meta("line_edit").text
		print("MissionControl: Duplicate workplan dialog confirmed with name: '", new_name, "'")
		name_dialog.queue_free()
		
		if not new_name.is_empty():
			if workplan_manager.duplicate_workplan(source_name, new_name):
				print("MissionControl: ✅ Duplicated workplan: ", source_name, " → ", new_name)
				dialog.queue_free()
			else:
				_show_error_dialog("Failed to duplicate workplan.")
		else:
			_show_error_dialog("Please enter a name for the duplicated workplan.")
	)
	
	name_dialog.canceled.connect(func(): 
		print("MissionControl: Duplicate workplan dialog canceled")
		name_dialog.queue_free()
	)
	
	name_dialog.popup_centered()

func _on_rename_workplan_pressed(dialog: AcceptDialog, workplan_list: ItemList):
	"""Handle workplan renaming"""
	var selected_items = workplan_list.get_selected_items()
	if selected_items.is_empty():
		_show_error_dialog("Please select a workplan to rename.")
		return
	
	var old_name = workplan_list.get_item_text(selected_items[0])
	var name_dialog = _create_text_input_dialog("Rename Workplan", "Enter new name:", old_name)
	add_child(name_dialog)
	
	# Connect signals with direct handling
	name_dialog.confirmed.connect(func(): 
		var new_name = name_dialog.get_meta("line_edit").text
		print("MissionControl: Rename workplan dialog confirmed with name: '", new_name, "'")
		name_dialog.queue_free()
		
		if not new_name.is_empty() and new_name != old_name:
			if workplan_manager.rename_workplan(old_name, new_name):
				print("MissionControl: ✅ Renamed workplan: ", old_name, " → ", new_name)
				dialog.queue_free()
			else:
				_show_error_dialog("Failed to rename workplan.")
		elif new_name == old_name:
			_show_error_dialog("New name must be different from the current name.")
		else:
			_show_error_dialog("Please enter a new name for the workplan.")
	)
	
	name_dialog.canceled.connect(func(): 
		print("MissionControl: Rename workplan dialog canceled")
		name_dialog.queue_free()
	)
	
	name_dialog.popup_centered()

func _on_delete_workplan_pressed(dialog: AcceptDialog, workplan_list: ItemList):
	"""Handle workplan deletion"""
	var selected_items = workplan_list.get_selected_items()
	if selected_items.is_empty():
		_show_error_dialog("Please select a workplan to delete.")
		return
	
	var workplan_name = workplan_list.get_item_text(selected_items[0])
	var confirmation = ConfirmationDialog.new()
	confirmation.dialog_text = "Are you sure you want to delete workplan '" + workplan_name + "'?\n\nThis action cannot be undone."
	confirmation.title = "Delete Workplan"
	add_child(confirmation)
	confirmation.popup_centered()

	# Avoid "confusable capture reassignment" by mutating a container, not reassigning a local.
	var confirmed_box: Array = [false]
	var decision_done_box: Array = [false]

	confirmation.confirmed.connect(func():
		confirmed_box[0] = true
		decision_done_box[0] = true
		if is_instance_valid(confirmation):
			confirmation.queue_free()
	)
	confirmation.canceled.connect(func():
		confirmed_box[0] = false
		decision_done_box[0] = true
		if is_instance_valid(confirmation):
			confirmation.queue_free()
	)

	while not bool(decision_done_box[0]):
		await get_tree().process_frame

	var confirmed_flag := bool(confirmed_box[0])

	if confirmed_flag:
		if workplan_manager.delete_workplan(workplan_name):
			print("MissionControl: ✅ Deleted workplan: ", workplan_name)
			dialog.queue_free()
		else:
			_show_error_dialog("Failed to delete workplan.")

func _on_import_workplan_pressed(_dialog: AcceptDialog):
	"""Handle workplan import"""
	var file_dialog_local = FileDialog.new()
	file_dialog_local.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog_local.add_filter("*.tres", "Godot Resource Files")
	add_child(file_dialog_local)
	
	# Connect signals with direct handling
	file_dialog_local.file_selected.connect(func(selected_path: String): 
		print("MissionControl: Import workplan file selected: ", selected_path)
		file_dialog_local.queue_free()
		
		if workplan_manager.import_workplan(selected_path):
			print("MissionControl: ✅ Imported workplan from: ", selected_path)
			_dialog.queue_free()
		else:
			_show_error_dialog("Failed to import workplan.")
	)
	
	file_dialog_local.canceled.connect(func(): 
		print("MissionControl: Import workplan dialog canceled")
		file_dialog_local.queue_free()
	)
	
	file_dialog_local.popup_centered(Vector2(800, 600))

func _on_export_workplan_pressed(_dialog: AcceptDialog, workplan_list: ItemList):
	"""Handle workplan export"""
	var selected_items = workplan_list.get_selected_items()
	if selected_items.is_empty():
		_show_error_dialog("Please select a workplan to export.")
		return
	
	var workplan_name = workplan_list.get_item_text(selected_items[0])
	var file_dialog_local = FileDialog.new()
	file_dialog_local.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog_local.add_filter("*.tres", "Godot Resource Files")
	file_dialog_local.current_file = workplan_name + ".tres"
	add_child(file_dialog_local)
	
	# Connect signals with direct handling
	file_dialog_local.file_selected.connect(func(selected_path: String): 
		print("MissionControl: Export workplan file selected: ", selected_path)
		file_dialog_local.queue_free()
		
		if workplan_manager.export_workplan(workplan_name, selected_path):
			print("MissionControl: ✅ Exported workplan to: ", selected_path)
		else:
			_show_error_dialog("Failed to export workplan.")
	)
	
	file_dialog_local.canceled.connect(func(): 
		print("MissionControl: Export workplan dialog canceled")
		file_dialog_local.queue_free()
	)
	
	file_dialog_local.popup_centered(Vector2(800, 600))

# Helper functions for dialogs
func _create_text_input_dialog(title: String, prompt: String, default_text: String = "") -> AcceptDialog:
	"""Create a text input dialog"""
	var dialog = AcceptDialog.new()
	dialog.title = title
	dialog.wrap_controls = true
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var label = Label.new()
	label.text = prompt
	vbox.add_child(label)
	
	var line_edit = LineEdit.new()
	line_edit.text = default_text
	line_edit.custom_minimum_size.x = 300
	vbox.add_child(line_edit)
	
	# Store line edit reference for retrieval
	dialog.set_meta("line_edit", line_edit)
	
	# Focus the line edit when dialog is shown
	dialog.about_to_popup.connect(func():
		await get_tree().process_frame
		line_edit.grab_focus()
		if not default_text.is_empty():
			line_edit.select_all()
	)
	
	# Allow Enter key to confirm dialog
	line_edit.text_submitted.connect(func(_text: String):
		dialog.confirmed.emit()
		dialog.hide()
	)
	
	return dialog

# SynTree Analysis UI Functions
func _update_syntree_analysis_ui(document: DocumentSessionManager.DocumentContext, analysis: Dictionary, success: bool):
	"""Update the UI to show SynTree analysis results"""
	if not document or not session_info_label:
		return
	
	if success and not analysis.is_empty():
		var quality_score = analysis.get("quality_metrics", {}).get("overall_readability", 0.0)
		var structure_quality = analysis.get("quality_metrics", {}).get("structure_quality", 0.0)
		var _word_count = analysis.get("statistics", {}).get("total_words", 0)
		var node_count = analysis.get("structure", {}).get("node_count", 0)
		
		# Update session info with analysis results
		var current_text = session_info_label.text
		var analysis_text = " | Quality: %.1f | Structure: %.1f | %d sections" % [
			quality_score * 100,
			structure_quality * 100,
			node_count
		]
		
		# Replace or append analysis info
		if " | Quality:" in current_text:
			var parts = current_text.split(" | Quality:")
			session_info_label.text = parts[0] + analysis_text
		else:
			session_info_label.text = current_text + analysis_text
		
		print("MissionControl: Analysis UI updated - Quality: %.1f%%, Structure: %.1f%%" % [
			quality_score * 100,
			structure_quality * 100
		])
	else:
		print("MissionControl: Analysis failed or empty for: ", document.file_name)

func _show_syntree_processing_status(_document_name: String):
	"""Show processing status for SynTree analysis"""
	if session_info_label:
		var current_text = session_info_label.text
		if " | Analyzing..." not in current_text:
			session_info_label.text = current_text + " | Analyzing..."
		
		# Remove the analyzing status after a short delay
		await get_tree().create_timer(0.5).timeout
		if session_info_label:
			session_info_label.text = session_info_label.text.replace(" | Analyzing...", "")

func get_document_analysis_summary(document: DocumentSessionManager.DocumentContext) -> String:
	"""Get a formatted summary of document analysis"""
	if not document or not document.syntree_analysis:
		return "No analysis available"
	
	var analysis = document.syntree_analysis
	var summary = "Document Analysis for %s:\n\n" % document.file_name
	
	# Basic statistics
	var stats = analysis.get("statistics", {})
	summary += "Word Count: %d\n" % stats.get("total_words", 0)
	summary += "Character Count: %d\n" % stats.get("total_characters", 0)
	summary += "Sentences: %d\n" % stats.get("total_sentences", 0)
	summary += "Avg Words/Sentence: %.1f\n\n" % stats.get("average_words_per_sentence", 0.0)
	
	# Structure info
	var structure = analysis.get("structure", {})
	summary += "Structure:\n"
	summary += "  Sections: %d\n" % structure.get("node_count", 0)
	summary += "  Has Clear Sections: %s\n" % ("Yes" if structure.get("has_clear_sections", false) else "No")
	summary += "  Section Balance: %.1f%%\n" % (structure.get("section_balance", 0.0) * 100)
	summary += "  Logical Flow: %.1f%%\n\n" % (structure.get("logical_flow", 0.0) * 100)
	
	# Quality metrics
	var quality = analysis.get("quality_metrics", {})
	summary += "Quality Metrics:\n"
	summary += "  Overall Readability: %.1f%%\n" % (quality.get("overall_readability", 0.0) * 100)
	summary += "  Structure Quality: %.1f%%\n" % (quality.get("structure_quality", 0.0) * 100)
	summary += "  Content Density: %.1f%%\n" % (quality.get("content_density", 0.0) * 100)
	summary += "  Consistency: %.1f%%\n" % (quality.get("consistency_score", 0.0) * 100)
	summary += "  Completeness: %.1f%%\n\n" % (quality.get("completeness_score", 0.0) * 100)
	
	# Relationships
	var relationships = analysis.get("relationships", [])
	if relationships.size() > 0:
		summary += "Internal Relationships: %d found\n" % relationships.size()
		for rel in relationships.slice(0, 3):  # Show first 3
			summary += "  %s ↔ %s (%.1f%% similar)\n" % [
				rel.get("node1_id", ""),
				rel.get("node2_id", ""),
				rel.get("similarity", 0.0) * 100
			]
		if relationships.size() > 3:
			summary += "  ... and %d more\n" % (relationships.size() - 3)
	else:
		summary += "No internal relationships detected\n"
	
	return summary

func trigger_document_analysis(document: DocumentSessionManager.DocumentContext):
	"""Manually trigger analysis for a document"""
	if SynTreeDocumentProcessor and document:
		print("MissionControl: Manually triggering analysis for: ", document.file_name)
		SynTreeDocumentProcessor.process_document_with_syntree(document)

