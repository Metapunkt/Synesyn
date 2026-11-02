extends "res://readymade/ui/internal/mission_control_workplan_syntree_base.gd"
class_name MissionControlPerformanceBase

func _create_phase_5_2_ui():
	"""Create Phase 5.2 performance optimization UI"""
	var phase_5_2_container = VBoxContainer.new()
	phase_5_2_container.name = "Phase52Container"
	
	var phase_label = Label.new()
	phase_label.text = "=== Performance Optimization ==="
	phase_label.add_theme_stylebox_override("normal", _create_section_style())
	phase_5_2_container.add_child(phase_label)
	
	# Performance monitor button
	performance_monitor_button = Button.new()
	performance_monitor_button.text = "Performance Monitor"
	performance_monitor_button.tooltip_text = "View detailed performance metrics and optimization suggestions"
	phase_5_2_container.add_child(performance_monitor_button)
	
	# Performance controls
	var controls_container = HBoxContainer.new()
	
	auto_optimize_toggle = CheckBox.new()
	auto_optimize_toggle.text = "Auto Optimize"
	auto_optimize_toggle.button_pressed = false
	auto_optimize_toggle.tooltip_text = "Automatically optimize memory usage"
	controls_container.add_child(auto_optimize_toggle)
	
	phase_5_2_container.add_child(controls_container)
	
	# Quick memory info
	memory_usage_label = Label.new()
	memory_usage_label.text = "Memory: Calculating..."
	memory_usage_label.add_theme_color_override("font_color", Color.GRAY)
	phase_5_2_container.add_child(memory_usage_label)
	
	# Add to main container
	edit_session_container.add_child(phase_5_2_container)
	
	# Create performance monitor dialog
	_create_performance_monitor_dialog()

func _create_performance_monitor_dialog():
	"""Create the detailed performance monitoring dialog"""
	performance_monitor_dialog = AcceptDialog.new()
	performance_monitor_dialog.title = "Performance Monitor"
	performance_monitor_dialog.size = Vector2i(800, 600)
	add_child(performance_monitor_dialog)
	
	var main_container = VBoxContainer.new()
	performance_monitor_dialog.add_child(main_container)
	
	# Tabs for different performance views
	var tab_container_local = TabContainer.new()
	main_container.add_child(tab_container_local)
	
	# Memory Usage Tab
	var memory_tab = VBoxContainer.new()
	memory_tab.name = "Memory Usage"
	tab_container_local.add_child(memory_tab)
	
	performance_stats_container = VBoxContainer.new()
	memory_tab.add_child(performance_stats_container)
	
	# Optimization Suggestions Tab
	var suggestions_tab = VBoxContainer.new()
	suggestions_tab.name = "Optimization"
	tab_container_local.add_child(suggestions_tab)
	
	optimization_suggestions_list = ItemList.new()
	optimization_suggestions_list.custom_minimum_size = Vector2(750, 400)
	suggestions_tab.add_child(optimization_suggestions_list)
	
	# Action buttons
	var action_container = HBoxContainer.new()
	suggestions_tab.add_child(action_container)
	
	var optimize_button = Button.new()
	optimize_button.text = "Optimize Now"
	optimize_button.pressed.connect(_on_optimize_performance_pressed)
	action_container.add_child(optimize_button)
	
	var clear_cache_button = Button.new()
	clear_cache_button.text = "Clear Cache"
	clear_cache_button.pressed.connect(_on_clear_cache_pressed)
	action_container.add_child(clear_cache_button)

func _connect_phase_5_2_signals():
	"""Connect Phase 5.2 performance optimization signals"""
	if performance_monitor_button:
		performance_monitor_button.pressed.connect(_on_performance_monitor_pressed)
	
	if auto_optimize_toggle:
		auto_optimize_toggle.toggled.connect(_on_auto_optimize_toggled)
	
	# Setup performance update timer
	performance_update_timer = Timer.new()
	performance_update_timer.wait_time = 5.0  # Update every 5 seconds
	performance_update_timer.timeout.connect(_update_performance_display)
	performance_update_timer.autostart = true
	add_child(performance_update_timer)

func _on_performance_monitor_pressed():
	"""Show the performance monitor dialog"""
	_update_performance_monitor_data()
	performance_monitor_dialog.popup_centered()

func _on_auto_optimize_toggled(enabled: bool):
	"""Toggle automatic optimization"""
	if enabled:
		performance_update_timer.wait_time = 10.0  # Check every 10 seconds for optimization
	else:
		performance_update_timer.wait_time = 5.0   # Normal monitoring interval
	print("MissionControl: Auto optimization %s" % ("enabled" if enabled else "disabled"))

func _on_optimize_performance_pressed():
	"""Manually trigger performance optimization"""
	var start_time = Time.get_unix_time_from_system()
	
	# Optimize document session
	if DocumentSessionManager:
		DocumentSessionManager.optimize_session_performance()
	
	# Optimize UI components
	_optimize_ui_performance()
	
	var optimization_time = Time.get_unix_time_from_system() - start_time
	ui_performance_metrics.last_optimization = Time.get_unix_time_from_system()
	
	print("MissionControl: Performance optimization completed in %.3f seconds" % optimization_time)
	
	# Refresh performance display
	_update_performance_monitor_data()

func _on_clear_cache_pressed():
	"""Clear UI component cache"""
	ui_component_cache.clear()
	task_card_pool.clear()
	ui_performance_metrics.components_in_pool = 0
	
	print("MissionControl: UI cache cleared")
	_update_performance_monitor_data()

func _optimize_ui_performance():
	"""Optimize UI component performance"""
	var start_time = Time.get_unix_time_from_system()
	var optimized_count = 0
	
	# Clean up unused task cards
	_cleanup_task_card_pool()
	
	# Clear excessive cached components
	if ui_component_cache.size() > max_cached_components:
		var keys_to_remove = []
		var removal_count = ui_component_cache.size() - max_cached_components
		
		for key in ui_component_cache.keys():
			if removal_count <= 0:
				break
			keys_to_remove.append(key)
			removal_count -= 1
		
		for key in keys_to_remove:
			if ui_component_cache[key] is Node:
				ui_component_cache[key].queue_free()
			ui_component_cache.erase(key)
			optimized_count += 1
	
	# Update metrics
	var optimization_time = Time.get_unix_time_from_system() - start_time
	ui_performance_metrics.last_optimization = Time.get_unix_time_from_system()
	
	print("MissionControl: UI optimization completed, removed %d cached components in %.3f seconds" % [optimized_count, optimization_time])

func _cleanup_task_card_pool():
	"""Clean up the task card object pool"""
	var cleaned_count = 0
	var active_cards: Array[Control] = []
	
	# Check which cards are still in use
	for card in task_card_pool:
		if is_instance_valid(card) and card.get_parent() != null:
			active_cards.append(card)
		else:
			if is_instance_valid(card):
				card.queue_free()
			cleaned_count += 1
	
	task_card_pool = active_cards
	ui_performance_metrics.components_in_pool = task_card_pool.size()
	
	if cleaned_count > 0:
		print("MissionControl: Cleaned up %d unused task cards" % cleaned_count)

func create_optimized_task_card(task: WorkplanTask) -> Control:
	"""Create or reuse task card with performance optimization"""
	var start_time = Time.get_unix_time_from_system()
	var task_card: Control
	
	# Try to reuse from pool first
	if task_card_pool.size() > 0:
		task_card = task_card_pool.pop_back()
		ui_performance_metrics.components_in_pool -= 1
	else:
		# Create new card
		task_card = task_card_scene.instantiate()
		ui_performance_metrics.total_components_created += 1
	
	# Configure the card
	if task_card.has_method("configure_for_task"):
		task_card.configure_for_task(task)
	
	# Track creation time
	var creation_time = Time.get_unix_time_from_system() - start_time
	ui_performance_metrics.component_creation_times[task.title] = creation_time
	
	return task_card

func return_task_card_to_pool(task_card: Control):
	"""Return task card to pool for reuse"""
	if not is_instance_valid(task_card):
		return
	
	# Remove from parent without freeing
	if task_card.get_parent():
		task_card.get_parent().remove_child(task_card)
	
	# Reset card state
	if task_card.has_method("reset_state"):
		task_card.reset_state()
	
	# Add to pool if there's space
	if task_card_pool.size() < max_cached_components:
		task_card_pool.append(task_card)
		ui_performance_metrics.components_in_pool += 1
	else:
		task_card.queue_free()

func _update_performance_display():
	"""Update the performance display in the UI"""
	if not DocumentSessionManager:
		return
	
	# Update memory usage label
	var memory_summary = DocumentSessionManager.get_memory_usage_summary()
	var memory_text = "Memory: %.1f MB (%d docs)" % [
		memory_summary.total_memory / 1000000.0,
		memory_summary.document_count
	]
	
	if memory_usage_label:
		memory_usage_label.text = memory_text
		
		# Color code based on memory usage
		if memory_summary.total_memory > 10000000:  # 10MB
			memory_usage_label.add_theme_color_override("font_color", Color.RED)
		elif memory_summary.total_memory > 5000000:  # 5MB
			memory_usage_label.add_theme_color_override("font_color", Color.ORANGE)
		else:
			memory_usage_label.add_theme_color_override("font_color", Color.GREEN)
	
	# Auto-optimize if enabled
	if auto_optimize_toggle and auto_optimize_toggle.button_pressed:
		if memory_summary.total_memory > 15000000:  # 15MB threshold
			_on_optimize_performance_pressed()

func _update_performance_monitor_data():
	"""Update the detailed performance monitor data"""
	if not DocumentSessionManager or not performance_stats_container:
		return
	
	# Clear existing data
	for child in performance_stats_container.get_children():
		child.queue_free()
	
	if optimization_suggestions_list:
		optimization_suggestions_list.clear()
	
	# Get performance report
	var report = DocumentSessionManager.get_session_performance_report()
	
	# Display session info
	var session_info_label_local = Label.new()
	session_info_label_local.text = "=== Session Information ==="
	session_info_label_local.add_theme_stylebox_override("normal", _create_section_style())
	performance_stats_container.add_child(session_info_label_local)
	
	var info_text = """Documents: %d
Primary: %s
Duration: %.1f hours
Total Memory: %.1f MB
Memory Efficiency: %.1f%%""" % [
		report.session_info.total_documents,
		report.session_info.primary_document,
		report.session_info.session_duration / 3600.0,
		report.session_info.total_memory_usage / 1000000.0,
		report.performance_summary.memory_efficiency_score * 100
	]
	
	var info_label = Label.new()
	info_label.text = info_text
	performance_stats_container.add_child(info_label)
	
	# Display performance summary
	var perf_info_label = Label.new()
	perf_info_label.text = "=== Performance Summary ==="
	perf_info_label.add_theme_stylebox_override("normal", _create_section_style())
	performance_stats_container.add_child(perf_info_label)
	
	var perf_text = """Load Time: %.3f seconds
Processing Time: %.3f seconds
Context Efficiency: %.1f%%
UI Components: %d created, %d pooled""" % [
		report.performance_summary.total_load_time,
		report.performance_summary.total_processing_time,
		report.performance_summary.context_generation_efficiency * 100,
		ui_performance_metrics.total_components_created,
		ui_performance_metrics.components_in_pool
	]
	
	var perf_label = Label.new()
	perf_label.text = perf_text
	performance_stats_container.add_child(perf_label)
	
	# Display optimization suggestions
	if optimization_suggestions_list:
		for recommendation in report.optimization_recommendations:
			var item_text = "[%s] %s: %s" % [
				recommendation.priority.to_upper(),
				recommendation.title,
				recommendation.description
			]
			optimization_suggestions_list.add_item(item_text)

func get_ui_performance_metrics() -> Dictionary:
	"""Get UI-specific performance metrics"""
	return {
		"ui_metrics": ui_performance_metrics.duplicate(),
		"component_pool_size": task_card_pool.size(),
		"cached_components": ui_component_cache.size(),
		"auto_optimize_enabled": auto_optimize_toggle.button_pressed if auto_optimize_toggle else false
	}

func _create_section_style() -> StyleBox:
	"""Create consistent section styling"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.3, 0.8)
	style.border_width_left = 3
	style.border_color = Color(0.4, 0.6, 1.0)
	style.content_margin_left = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

# === END PHASE 5.2 UI OPTIMIZATION ===

func _create_export_dialogs():
	"""Create file dialogs for export operations"""
	# Report export dialog
	report_export_dialog = FileDialog.new()
	report_export_dialog.title = "Select Directory to Save Report"
	report_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	report_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	report_export_dialog.add_filter("*.html", "HTML Report")
	report_export_dialog.add_filter("*.md", "Markdown Report")
	report_export_dialog.add_filter("*.json", "JSON Report")
	report_export_dialog.add_filter("*.txt", "Text Report")
	add_child(report_export_dialog)
	report_export_dialog.file_selected.connect(_on_report_export_path_selected)
	
	# Documents export dialog
	documents_export_dialog = FileDialog.new()
	documents_export_dialog.title = "Select Directory to Export Documents"
	documents_export_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	documents_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	add_child(documents_export_dialog)
	documents_export_dialog.dir_selected.connect(_on_documents_export_dir_selected)
	
	# Session share dialog
	session_share_dialog = FileDialog.new()
	session_share_dialog.title = "Select Location to Save Session Package"
	session_share_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	session_share_dialog.access = FileDialog.ACCESS_FILESYSTEM
	session_share_dialog.add_filter("*.json", "Session Package")
	add_child(session_share_dialog)
	session_share_dialog.file_selected.connect(_on_session_share_path_selected)

# Export dialog callbacks
func _on_report_export_path_selected(path: String):
	"""Handle report export path selection"""
	print("MissionControl: Generating report in format: %s" % DocumentSessionManager.export_format_names[pending_export_format])
	print("MissionControl: Saving to: %s" % path)
	
	# Generate report with selected path
	var report_path = DocumentSessionManager.generate_edit_session_report(pending_export_format, path)
	if report_path.is_empty():
		_show_error_dialog("Failed to generate report.")
	# Success message will be shown via signal

func _on_documents_export_dir_selected(dir_path: String):
	"""Handle documents export directory selection"""
	print("MissionControl: Exporting all documents in format: %s" % DocumentSessionManager.export_format_names[pending_export_format])
	print("MissionControl: Saving to directory: %s" % dir_path)
	
	# Export all documents to selected directory
	var exported_files = DocumentSessionManager.export_all_documents(pending_export_format, dir_path)
	if exported_files.size() > 0:
		_show_info_dialog("Successfully exported %d documents.\n\nFiles saved to:\n%s" % [exported_files.size(), dir_path])
	else:
		_show_error_dialog("Failed to export documents.")

func _on_session_share_path_selected(path: String):
	"""Handle session share path selection"""
	print("MissionControl: Creating shareable session package")
	print("MissionControl: Saving to: %s" % path)
	
	# Create shareable package at selected path
	var share_path = DocumentSessionManager.export_session_for_sharing(path)
	if not share_path.is_empty():
		_show_info_dialog("Shareable session package created:\n%s\n\nThis package contains anonymized analytics and statistics (no document content)." % share_path)
	else:
		_show_error_dialog("Failed to create shareable session package.")
