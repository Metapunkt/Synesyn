extends "res://readymade/ui/internal/mission_control_task_reporting_base.gd"
class_name MissionControlWorkplanSyntreeBase

func _show_workplan_manager_dialog():
	"""Create and show the workplan manager dialog"""
	if has_method("_dismiss_blocking_dialogs"):
		await _dismiss_blocking_dialogs()
	var dialog = _create_workplan_manager_dialog()
	dialog.close_requested.connect(func():
		if has_method("_release_exclusive_window"):
			await _release_exclusive_window(dialog)
		else:
			dialog.hide()
			dialog.queue_free()
	)
	dialog.canceled.connect(func():
		if has_method("_release_exclusive_window"):
			await _release_exclusive_window(dialog)
		else:
			dialog.hide()
			dialog.queue_free()
	)
	dialog.confirmed.connect(func():
		if has_method("_release_exclusive_window"):
			await _release_exclusive_window(dialog)
		else:
			dialog.hide()
			dialog.queue_free()
	)
	add_child(dialog)
	var ok_btn: Button = dialog.get_ok_button()
	if ok_btn != null:
		ok_btn.visible = false
	dialog.popup_centered(Vector2(600, 400))

func _create_workplan_manager_dialog() -> AcceptDialog:
	"""Create the workplan manager dialog with grouped action sections."""
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
	workplan_list.custom_minimum_size = Vector2(0, 180)
	workplan_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var available_workplans = workplan_manager.get_available_workplans()
	for workplan_name in available_workplans:
		workplan_list.add_item(workplan_name)
	vbox.add_child(workplan_list)

	# --- Workplan ---
	var workplan_section = Label.new()
	workplan_section.text = "Workplan"
	workplan_section.theme_type_variation = "HeaderSmall"
	vbox.add_child(workplan_section)

	var button_container = HBoxContainer.new()
	vbox.add_child(button_container)
	
	var new_button = Button.new()
	new_button.text = "New Workplan"
	new_button.tooltip_text = "Create a new empty workplan and switch to it"
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

	var workplan_io = HBoxContainer.new()
	vbox.add_child(workplan_io)
	var import_button = Button.new()
	import_button.text = "Import Workplan"
	import_button.pressed.connect(_on_import_workplan_pressed.bind(dialog))
	workplan_io.add_child(import_button)
	var export_button = Button.new()
	export_button.text = "Export Workplan"
	export_button.pressed.connect(_on_export_workplan_pressed.bind(dialog, workplan_list))
	workplan_io.add_child(export_button)

	vbox.add_child(HSeparator.new())

	# --- Tasks import-export ---
	var tasks_section = Label.new()
	tasks_section.text = "Tasks import / export"
	tasks_section.theme_type_variation = "HeaderSmall"
	vbox.add_child(tasks_section)

	var task_io_container = HBoxContainer.new()
	vbox.add_child(task_io_container)
	var import_tasks_button = Button.new()
	import_tasks_button.text = "Import Tasks (CSV/JSON)"
	import_tasks_button.tooltip_text = "Bulk create/update tasks from CSV or JSON with preview"
	import_tasks_button.pressed.connect(_on_import_tasks_pressed.bind(dialog))
	task_io_container.add_child(import_tasks_button)
	var export_tasks_button = Button.new()
	export_tasks_button.text = "Export Tasks (CSV/JSON)"
	export_tasks_button.tooltip_text = "Export current workplan tasks for spreadsheet review"
	export_tasks_button.pressed.connect(_on_export_tasks_pressed.bind(dialog))
	task_io_container.add_child(export_tasks_button)

	vbox.add_child(HSeparator.new())

	# --- Channels & caps ---
	var channels_section = Label.new()
	channels_section.text = "Channels & caps"
	channels_section.theme_type_variation = "HeaderSmall"
	vbox.add_child(channels_section)

	var channels_row = HBoxContainer.new()
	vbox.add_child(channels_row)
	var channels_button = Button.new()
	channels_button.text = "Manage Channels"
	channels_button.tooltip_text = "Add, rename, remove, or reorder custom destinations"
	channels_button.pressed.connect(_on_manage_channels_pressed.bind(dialog))
	channels_row.add_child(channels_button)
	var cadence_button = Button.new()
	cadence_button.text = "Cadence Caps"
	cadence_button.tooltip_text = "Set per-channel weekly caps and view non-blocking warnings"
	cadence_button.pressed.connect(_on_cadence_caps_pressed.bind(dialog))
	channels_row.add_child(cadence_button)
	var people_button = Button.new()
	people_button.text = "Manage People"
	people_button.tooltip_text = "People and agents who can be assigned to tasks"
	people_button.pressed.connect(_on_manage_people_pressed.bind(dialog))
	channels_row.add_child(people_button)

	vbox.add_child(HSeparator.new())

	# --- Time zones ---
	var tz_section = Label.new()
	tz_section.text = "Time zones"
	tz_section.theme_type_variation = "HeaderSmall"
	vbox.add_child(tz_section)

	var tz_row = HBoxContainer.new()
	vbox.add_child(tz_row)
	var default_tz_button = Button.new()
	default_tz_button.text = "Default Timezone"
	default_tz_button.tooltip_text = "IANA zone stored on tasks when publish timezone is left empty"
	default_tz_button.pressed.connect(_on_default_timezone_pressed.bind(dialog))
	tz_row.add_child(default_tz_button)
	var tz_button = Button.new()
	tz_button.text = "Viewer Timezone"
	tz_button.tooltip_text = "IANA zone used when converting publish times in calendar/lists"
	tz_button.pressed.connect(_on_viewer_timezone_pressed.bind(dialog))
	tz_row.add_child(tz_button)

	var cadence_warn_label = Label.new()
	cadence_warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cadence_warn_label.modulate = Color(0.95, 0.75, 0.35)
	if workplan_manager != null and workplan_manager.has_method("get_cadence_warnings"):
		var warns: Array = workplan_manager.get_cadence_warnings()
		if warns.is_empty():
			cadence_warn_label.text = ""
		else:
			cadence_warn_label.text = "⚠ %d cadence warning(s) — open Cadence Caps for details" % warns.size()
	vbox.add_child(cadence_warn_label)

	# Close is available via window X; hide the redundant AcceptDialog OK in _show_*.
	dialog.dialog_hide_on_ok = false
	
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
	
	_popup_nested_dialog(name_dialog)

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
	
	_popup_nested_dialog(name_dialog)

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
	
	_popup_nested_dialog(name_dialog)

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
	_popup_nested_dialog(confirmation)

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

func _configure_filesystem_file_dialog(file_dialog_local: FileDialog) -> void:
	"""Workplan import/export must browse the real filesystem (Documents), not res://."""
	file_dialog_local.access = FileDialog.ACCESS_FILESYSTEM
	var docs_dir: String = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var preferred: String = RuntimeConfig.get_readymade_data_dir() if RuntimeConfig else ""
	if not preferred.is_empty() and DirAccess.dir_exists_absolute(preferred):
		file_dialog_local.current_dir = preferred
	elif not docs_dir.is_empty():
		file_dialog_local.current_dir = docs_dir
	_wire_file_dialog_line_confirm(file_dialog_local)


func _wire_file_dialog_line_confirm(file_dialog_local: FileDialog) -> void:
	"""Enable Open/Save when File: names an existing file (open) or valid save path; Enter confirms."""
	if file_dialog_local == null:
		return
	if file_dialog_local.get_meta("_line_confirm_wired", false):
		_sync_file_dialog_ok_from_line(file_dialog_local)
		return
	var line: LineEdit = file_dialog_local.get_line_edit()
	if line == null:
		return
	file_dialog_local.set_meta("_line_confirm_wired", true)
	line.text_changed.connect(func(_text: String) -> void:
		_sync_file_dialog_ok_from_line(file_dialog_local)
	)
	line.text_submitted.connect(func(submitted: String) -> void:
		_sync_file_dialog_ok_from_line(file_dialog_local)
		var ok_btn: Button = file_dialog_local.get_ok_button()
		if ok_btn == null or ok_btn.disabled:
			return
		var path: String = _resolve_file_dialog_line_path(file_dialog_local, submitted)
		if path.is_empty():
			return
		file_dialog_local.file_selected.emit(path)
		file_dialog_local.hide()
	)


func _resolve_file_dialog_line_path(file_dialog_local: FileDialog, raw_text: String = "") -> String:
	var name_text: String = raw_text.strip_edges()
	if name_text.is_empty():
		var line: LineEdit = file_dialog_local.get_line_edit()
		name_text = line.text.strip_edges() if line else ""
	if name_text.is_empty():
		return ""
	var is_absolute: bool = name_text.begins_with("/") or (name_text.length() > 2 and name_text[1] == ":")
	if is_absolute:
		return name_text
	return String(file_dialog_local.current_dir).path_join(name_text)


func _sync_file_dialog_ok_from_line(file_dialog_local: FileDialog) -> void:
	var ok_btn: Button = file_dialog_local.get_ok_button()
	if ok_btn == null:
		return
	var path: String = _resolve_file_dialog_line_path(file_dialog_local)
	if path.is_empty():
		ok_btn.disabled = true
		return
	var file_part: String = path.get_file()
	var dir_part: String = path.get_base_dir()
	var is_open: bool = (
		file_dialog_local.file_mode == FileDialog.FILE_MODE_OPEN_FILE
		or file_dialog_local.file_mode == FileDialog.FILE_MODE_OPEN_FILES
	)
	if is_open:
		var exists: bool = FileAccess.file_exists(path)
		if exists:
			file_dialog_local.current_dir = dir_part
			file_dialog_local.current_file = file_part
		ok_btn.disabled = not exists
	else:
		var dir_ok: bool = DirAccess.dir_exists_absolute(dir_part) and not file_part.is_empty()
		if dir_ok:
			file_dialog_local.current_dir = dir_part
			file_dialog_local.current_file = file_part
		ok_btn.disabled = not dir_ok


func _popup_nested_dialog(dialog_window: Window, size: Vector2 = Vector2.ZERO) -> void:
	"""Pop nested AcceptDialog without stealing exclusive from Workplan Manager."""
	dialog_window.exclusive = false
	if size == Vector2.ZERO:
		dialog_window.popup_centered()
	else:
		dialog_window.popup_centered(size)
	# Non-exclusive windows often need a focus grab so the first OK click applies.
	if dialog_window is AcceptDialog:
		var accept_dialog: AcceptDialog = dialog_window as AcceptDialog
		accept_dialog.call_deferred("grab_focus")
		var ok_btn: Button = accept_dialog.get_ok_button()
		if ok_btn != null:
			ok_btn.call_deferred("grab_focus")


func _popup_file_dialog_over_manager(parent_dialog: AcceptDialog, file_dialog_local: FileDialog, size: Vector2 = Vector2(800, 600)) -> void:
	"""Hide Workplan Manager while FileDialog is exclusive so Open/Save receives input cleanly."""
	var parent_was_visible: bool = false
	if parent_dialog != null and is_instance_valid(parent_dialog):
		parent_was_visible = parent_dialog.visible
		parent_dialog.hide()
	var restore := func(_arg = null):
		if parent_dialog != null and is_instance_valid(parent_dialog) and parent_was_visible:
			parent_dialog.show()
	# file_selected emits the path; canceled emits nothing — accept optional arg.
	file_dialog_local.file_selected.connect(restore, CONNECT_ONE_SHOT)
	file_dialog_local.canceled.connect(restore, CONNECT_ONE_SHOT)
	file_dialog_local.exclusive = true
	file_dialog_local.popup_centered(size)
	# LineEdit exists after popup; re-sync OK state for any prefilled current_file.
	_wire_file_dialog_line_confirm(file_dialog_local)
	_sync_file_dialog_ok_from_line(file_dialog_local)


func _on_import_workplan_pressed(_dialog: AcceptDialog):
	"""Handle workplan import"""
	var file_dialog_local = FileDialog.new()
	file_dialog_local.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_configure_filesystem_file_dialog(file_dialog_local)
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
	
	_popup_file_dialog_over_manager(_dialog, file_dialog_local)

func _on_export_workplan_pressed(_dialog: AcceptDialog, workplan_list: ItemList):
	"""Handle workplan export"""
	var selected_items = workplan_list.get_selected_items()
	if selected_items.is_empty():
		_show_error_dialog("Please select a workplan to export.")
		return
	
	var workplan_name = workplan_list.get_item_text(selected_items[0])
	var file_dialog_local = FileDialog.new()
	file_dialog_local.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_configure_filesystem_file_dialog(file_dialog_local)
	file_dialog_local.add_filter("*.md", "Markdown (content plan handoff)")
	file_dialog_local.add_filter("*.csv", "Tasks CSV (bulk edit)")
	file_dialog_local.add_filter("*.json", "Tasks JSON (bulk edit)")
	file_dialog_local.add_filter("*.tres", "Godot Resource Files")
	file_dialog_local.current_file = workplan_name + ".md"
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
	
	_popup_file_dialog_over_manager(_dialog, file_dialog_local)


func _on_export_tasks_pressed(_dialog: AcceptDialog) -> void:
	"""Export current workplan tasks as CSV or JSON."""
	if workplan_manager == null or workplan_manager.get_current_workplan() == null:
		_show_error_dialog("No current workplan to export tasks from.")
		return
	var plan_name: String = workplan_manager.get_current_workplan_name()
	var file_dialog_local = FileDialog.new()
	file_dialog_local.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_configure_filesystem_file_dialog(file_dialog_local)
	file_dialog_local.add_filter("*.csv", "CSV tasks")
	file_dialog_local.add_filter("*.json", "JSON tasks")
	file_dialog_local.current_file = plan_name + "_tasks.csv"
	add_child(file_dialog_local)
	file_dialog_local.file_selected.connect(func(selected_path: String):
		file_dialog_local.queue_free()
		var ok: bool = false
		if selected_path.to_lower().ends_with(".json"):
			ok = workplan_manager.export_current_tasks_json(selected_path)
		else:
			ok = workplan_manager.export_current_tasks_csv(selected_path)
		if ok:
			print("MissionControl: ✅ Exported tasks to: ", selected_path)
		else:
			_show_error_dialog("Failed to export tasks.")
	)
	file_dialog_local.canceled.connect(func():
		file_dialog_local.queue_free()
	)
	_popup_file_dialog_over_manager(_dialog, file_dialog_local)


func _on_import_tasks_pressed(_dialog: AcceptDialog) -> void:
	"""Import CSV/JSON tasks into the current workplan with preview."""
	if workplan_manager == null or workplan_manager.get_current_workplan() == null:
		_show_error_dialog("No current workplan to import tasks into.")
		return
	var file_dialog_local = FileDialog.new()
	file_dialog_local.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_configure_filesystem_file_dialog(file_dialog_local)
	file_dialog_local.add_filter("*.csv", "CSV tasks")
	file_dialog_local.add_filter("*.json", "JSON tasks")
	add_child(file_dialog_local)
	file_dialog_local.file_selected.connect(func(selected_path: String):
		file_dialog_local.queue_free()
		var preview: Dictionary = workplan_manager.import_tasks_from_path(selected_path, false)
		_show_task_import_preview(preview, selected_path)
	)
	file_dialog_local.canceled.connect(func():
		file_dialog_local.queue_free()
	)
	_popup_file_dialog_over_manager(_dialog, file_dialog_local)


func _on_manage_channels_pressed(_parent_dialog: AcceptDialog) -> void:
	"""UI for add/rename/remove/reorder of workplan custom channels."""
	if workplan_manager == null or workplan_manager.get_current_workplan() == null:
		_show_error_dialog("No current workplan.")
		return
	var dialog = AcceptDialog.new()
	dialog.title = "Custom Channels"
	dialog.set_flag(Window.FLAG_RESIZE_DISABLED, false)
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	var list = ItemList.new()
	list.custom_minimum_size = Vector2(360, 200)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(list)
	var refresh := func():
		list.clear()
		for channel_label in workplan_manager.get_custom_channels():
			list.add_item(String(channel_label))
	refresh.call()
	var add_row = HBoxContainer.new()
	vbox.add_child(add_row)
	var add_edit = LineEdit.new()
	add_edit.placeholder_text = "#new-channel"
	add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(add_edit)
	var add_btn = Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(func():
		if workplan_manager.add_custom_channel(add_edit.text):
			add_edit.text = ""
			refresh.call()
	)
	add_row.add_child(add_btn)
	var actions = HBoxContainer.new()
	vbox.add_child(actions)
	var rename_btn = Button.new()
	rename_btn.text = "Rename"
	rename_btn.pressed.connect(func():
		var selected = list.get_selected_items()
		if selected.is_empty():
			return
		var old_label: String = list.get_item_text(selected[0])
		var name_dialog = _create_text_input_dialog("Rename Channel", "New name:", old_label)
		add_child(name_dialog)
		name_dialog.confirmed.connect(func():
			var new_label: String = name_dialog.get_meta("line_edit").text
			name_dialog.queue_free()
			workplan_manager.rename_custom_channel(old_label, new_label)
			refresh.call()
		)
		name_dialog.canceled.connect(func(): name_dialog.queue_free())
		_popup_nested_dialog(name_dialog)
	)
	actions.add_child(rename_btn)
	var remove_btn = Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(func():
		var selected2 = list.get_selected_items()
		if selected2.is_empty():
			return
		workplan_manager.remove_custom_channel(list.get_item_text(selected2[0]))
		refresh.call()
	)
	actions.add_child(remove_btn)
	var up_btn = Button.new()
	up_btn.text = "↑"
	up_btn.pressed.connect(func():
		var selected3 = list.get_selected_items()
		if selected3.is_empty() or selected3[0] <= 0:
			return
		var idx: int = selected3[0]
		if workplan_manager.move_custom_channel(idx, idx - 1):
			refresh.call()
			list.select(idx - 1)
	)
	actions.add_child(up_btn)
	var down_btn = Button.new()
	down_btn.text = "↓"
	down_btn.pressed.connect(func():
		var selected4 = list.get_selected_items()
		var channel_count: int = workplan_manager.get_custom_channels().size()
		if selected4.is_empty() or selected4[0] >= channel_count - 1:
			return
		var idx2: int = selected4[0]
		if workplan_manager.move_custom_channel(idx2, idx2 + 1):
			refresh.call()
			list.select(idx2 + 1)
	)
	actions.add_child(down_btn)
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	_popup_nested_dialog(dialog, Vector2(420, 360))


func _on_manage_people_pressed(_parent_dialog: AcceptDialog) -> void:
	"""UI for workplan people list: name, role label, timezone."""
	if workplan_manager == null or workplan_manager.get_current_workplan() == null:
		_show_error_dialog("No current workplan.")
		return
	var dialog = AcceptDialog.new()
	dialog.title = "People & Assignees"
	dialog.set_flag(Window.FLAG_RESIZE_DISABLED, false)
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	var list = ItemList.new()
	list.custom_minimum_size = Vector2(420, 200)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(list)
	var refresh := func():
		list.clear()
		if not workplan_manager.has_method("get_people"):
			return
		for person_any in workplan_manager.get_people():
			if typeof(person_any) != TYPE_DICTIONARY:
				continue
			var person: Dictionary = person_any
			var person_name: String = String(person.get("name", ""))
			var role_label: String = String(person.get("role", ""))
			var zone: String = String(person.get("timezone", ""))
			var line: String = person_name
			if not role_label.is_empty():
				line += " · %s" % role_label
			if not zone.is_empty():
				line += " · %s" % zone
			list.add_item(line)
			list.set_item_metadata(list.item_count - 1, person_name)
	refresh.call()
	var add_row = HBoxContainer.new()
	vbox.add_child(add_row)
	var name_edit = LineEdit.new()
	name_edit.placeholder_text = "Name or agent id"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(name_edit)
	var role_edit = LineEdit.new()
	role_edit.placeholder_text = "Role label"
	role_edit.custom_minimum_size = Vector2(200, 0)
	role_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(role_edit)
	var zone_edit = LineEdit.new()
	zone_edit.placeholder_text = "IANA timezone"
	zone_edit.custom_minimum_size = Vector2(160, 0)
	add_row.add_child(zone_edit)
	var add_btn = Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(func():
		if workplan_manager.add_person(name_edit.text, role_edit.text, zone_edit.text):
			name_edit.text = ""
			role_edit.text = ""
			zone_edit.text = ""
			refresh.call()
	)
	add_row.add_child(add_btn)
	var remove_btn = Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(func():
		var selected = list.get_selected_items()
		if selected.is_empty():
			return
		var person_name: String = String(list.get_item_metadata(selected[0]))
		workplan_manager.remove_person(person_name)
		refresh.call()
	)
	vbox.add_child(remove_btn)
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	_popup_nested_dialog(dialog, Vector2(640, 400))


func _build_timezone_dialog(dialog_title: String, hint_text: String, placeholder: String, initial_zone: String) -> Dictionary:
	"""Compact timezone editor: avoids oversized AcceptDialogs from long autowrap labels."""
	var dialog = AcceptDialog.new()
	dialog.title = dialog_title
	dialog.wrap_controls = true
	dialog.unresizable = true
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	dialog.add_child(vbox)
	var hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(400, 0)
	hint.text = hint_text
	vbox.add_child(hint)
	var zone_edit = LineEdit.new()
	zone_edit.placeholder_text = placeholder
	zone_edit.text = initial_zone
	vbox.add_child(zone_edit)
	var known = Label.new()
	known.autowrap_mode = TextServer.AUTOWRAP_OFF
	known.clip_text = true
	known.text = "Examples: Africa/Lagos, America/New_York, Europe/Oslo"
	vbox.add_child(known)
	zone_edit.text_submitted.connect(func(_text: String):
		dialog.confirmed.emit()
		dialog.hide()
	)
	dialog.about_to_popup.connect(func():
		await get_tree().process_frame
		zone_edit.grab_focus()
		zone_edit.select_all()
	)
	return {"dialog": dialog, "zone_edit": zone_edit}


func _on_default_timezone_pressed(_parent_dialog: AcceptDialog) -> void:
	if workplan_manager == null or workplan_manager.get_current_workplan() == null:
		_show_error_dialog("No current workplan.")
		return
	var built: Dictionary = _build_timezone_dialog(
		"Default Timezone",
		"Used when a task leaves publish timezone empty. Prefer an IANA id.",
		"e.g. Europe/Oslo or Africa/Lagos",
		workplan_manager.get_default_timezone()
	)
	var dialog: AcceptDialog = built["dialog"]
	var zone_edit: LineEdit = built["zone_edit"]
	dialog.confirmed.connect(func():
		workplan_manager.set_default_timezone(zone_edit.text)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	_popup_nested_dialog(dialog, Vector2(480, 240))


func _on_viewer_timezone_pressed(_parent_dialog: AcceptDialog) -> void:
	if workplan_manager == null or workplan_manager.get_current_workplan() == null:
		_show_error_dialog("No current workplan.")
		return
	var built: Dictionary = _build_timezone_dialog(
		"Viewer Timezone",
		"Calendar and lists convert task publish times into this zone (DST-aware for known IANA ids).",
		"e.g. Europe/Oslo or America/New_York",
		workplan_manager.get_viewer_timezone()
	)
	var dialog: AcceptDialog = built["dialog"]
	var zone_edit: LineEdit = built["zone_edit"]
	dialog.confirmed.connect(func():
		workplan_manager.set_viewer_timezone(zone_edit.text)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	_popup_nested_dialog(dialog, Vector2(480, 240))


func _on_cadence_caps_pressed(_parent_dialog: AcceptDialog) -> void:
	"""Set per-channel weekly caps and show non-blocking validation report."""
	if workplan_manager == null or workplan_manager.get_current_workplan() == null:
		_show_error_dialog("No current workplan.")
		return
	var dialog = AcceptDialog.new()
	dialog.title = "Channel Cadence Caps"
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	var channel_edit = LineEdit.new()
	channel_edit.placeholder_text = "Channel (e.g. #general)"
	vbox.add_child(channel_edit)
	var cap_spin = SpinBox.new()
	cap_spin.min_value = 0
	cap_spin.max_value = 50
	cap_spin.value = 2
	cap_spin.prefix = "Max / week: "
	vbox.add_child(cap_spin)
	var report_label = Label.new()
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_label.text = workplan_manager.get_cadence_validation_report()
	var set_btn = Button.new()
	set_btn.text = "Set Cap"
	set_btn.pressed.connect(func():
		workplan_manager.set_channel_cadence_cap(channel_edit.text, int(cap_spin.value))
		report_label.text = workplan_manager.get_cadence_validation_report()
	)
	vbox.add_child(set_btn)
	vbox.add_child(report_label)
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	_popup_nested_dialog(dialog, Vector2(480, 320))


func _find_open_workplan_manager_dialog() -> AcceptDialog:
	"""Locate a visible Workplan Manager AcceptDialog owned by this dashboard."""
	for child in get_children():
		if child is AcceptDialog and is_instance_valid(child) and (child as AcceptDialog).visible:
			var dlg: AcceptDialog = child as AcceptDialog
			if dlg.title == "Workplan Manager":
				return dlg
	return null


func _close_import_preview_dialog(summary: Window) -> void:
	"""Hide and free the import preview so it cannot linger under a result dialog."""
	if summary == null or not is_instance_valid(summary):
		return
	summary.hide()
	summary.visible = false
	if summary.get_parent() != null:
		summary.get_parent().remove_child(summary)
	summary.queue_free()


func _show_import_complete_result(created_n: int, updated_n: int, manager_dialog: AcceptDialog = null) -> void:
	"""Show Import complete only after the preview Window is gone from the tree."""
	var result := AcceptDialog.new()
	result.title = "Import complete"
	result.dialog_text = "Created: %d\nUpdated: %d" % [created_n, updated_n]
	result.ok_button_text = "Close"
	result.exclusive = true
	result.wrap_controls = true
	# Floor size so the title is not truncated to "Import c…".
	result.min_size = Vector2(320, 140)
	add_child(result)
	var finish := func(_arg = null):
		if is_instance_valid(result):
			result.hide()
			result.queue_free()
		if manager_dialog != null and is_instance_valid(manager_dialog):
			manager_dialog.show()
	result.confirmed.connect(finish, CONNECT_ONE_SHOT)
	result.canceled.connect(finish, CONNECT_ONE_SHOT)
	result.close_requested.connect(finish, CONNECT_ONE_SHOT)
	result.popup_centered(Vector2i(320, 160))


func _show_task_import_preview(preview: Dictionary, source_path: String) -> void:
	"""Show created/updated/skipped/errors summary before applying bulk import."""
	var created_n: int = int(preview.get("created", 0))
	var updated_n: int = int(preview.get("updated", 0))
	var skipped_n: int = int(preview.get("skipped", 0))
	var errors: Array = preview.get("errors", [])
	var manager_dialog: AcceptDialog = _find_open_workplan_manager_dialog()
	# Hide Manager while preview is exclusive so Cancel cannot click-through to Export.
	if manager_dialog != null:
		manager_dialog.hide()
	var summary := ConfirmationDialog.new()
	summary.title = "Import Tasks Preview"
	summary.ok_button_text = "Apply"
	summary.cancel_button_text = "Cancel"
	# Exclusive (not nested non-exclusive) so Apply/Cancel cannot fall through to Manager.
	summary.exclusive = true
	var error_lines: String = ""
	if not errors.is_empty():
		var shown: PackedStringArray = PackedStringArray()
		for i in range(mini(5, errors.size())):
			shown.append(String(errors[i]))
		error_lines = "\nErrors:\n- " + "\n- ".join(shown)
		if errors.size() > 5:
			error_lines += "\n- …and %d more" % (errors.size() - 5)
	summary.dialog_text = (
		"Source: %s\n\nCreated: %d\nUpdated: %d\nSkipped: %d%s\n\nApply these changes to the current workplan?"
		% [source_path.get_file(), created_n, updated_n, skipped_n, error_lines]
	)
	add_child(summary)
	var restore_manager := func():
		if manager_dialog != null and is_instance_valid(manager_dialog):
			manager_dialog.show()
	summary.confirmed.connect(func():
		# Hide/free preview BEFORE showing the result so it cannot linger underneath.
		_close_import_preview_dialog(summary)
		var applied: Dictionary = workplan_manager.apply_import_tasks_preview(preview)
		var applied_created: int = int(applied.get("created", 0))
		var applied_updated: int = int(applied.get("updated", 0))
		print(
			"MissionControl: Import applied — created %d, updated %d"
			% [applied_created, applied_updated]
		)
		# Defer result one frame so the preview Window is gone from the tree first.
		call_deferred(
			"_show_import_complete_result",
			applied_created,
			applied_updated,
			manager_dialog
		)
	, CONNECT_ONE_SHOT)
	var on_cancel := func(_arg = null):
		_close_import_preview_dialog(summary)
		restore_manager.call()
		# Cancel must never open a save/export FileDialog.
	summary.canceled.connect(on_cancel, CONNECT_ONE_SHOT)
	summary.close_requested.connect(on_cancel, CONNECT_ONE_SHOT)
	summary.popup_centered()
	var ok_btn: Button = summary.get_ok_button()
	if ok_btn != null:
		ok_btn.call_deferred("grab_focus")

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

