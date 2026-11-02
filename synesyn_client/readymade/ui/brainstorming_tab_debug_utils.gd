extends RefCounted
class_name BrainstormingTabDebugUtils

static func chat_history_text(chat_node) -> String:
	if chat_node == null:
		return ""
	if chat_node is TextEdit:
		return chat_node.text
	if chat_node.has_method("get_parsed_text"):
		return chat_node.get_parsed_text()
	var raw_text: String = str(chat_node.get("text"))
	return raw_text

static func test_context_integration(owner) -> void:
	print("Brainstorming Tab: Testing context integration...")
	print("- Current workflow: ", owner.current_workflow)
	print("- Document context enabled: ", owner.document_context_enabled)
	print("- Context indicator label: ", owner.context_indicator_label.text if owner.context_indicator_label else "Missing")
	print("- Context toggle button: ", owner.context_toggle_button.text if owner.context_toggle_button else "Missing")
	if owner.current_workflow == "edit_session" and DocumentSessionManager:
		var session_summary = DocumentSessionManager.get_session_summary()
		print("- Documents loaded: ", session_summary.document_count)
		print("- Primary document: ", session_summary.primary_document)
		if owner.document_context_enabled:
			var context: Dictionary = owner.get_edit_session_context()
			print("- Context keys: ", context.keys())
			var test_prompt := "Help me improve this text"
			var enhanced: String = owner._build_context_enhanced_prompt(test_prompt)
			print("- Enhanced prompt length: ", enhanced.length())
			print("- Context added: ", enhanced != test_prompt)
	print("Brainstorming Tab: Context integration test complete")

static func show_debug_info(owner) -> void:
	var debug_info := "Brainstorming Tab Debug Info:\n\n"
	debug_info += "UI Components:\n"
	debug_info += "- chat_history: %s\n" % ("OK" if owner.chat_history else "MISSING")
	debug_info += "- context_indicator_label: %s\n" % ("OK" if owner.context_indicator_label else "MISSING")
	debug_info += "- context_toggle_button: %s\n" % ("OK" if owner.context_toggle_button else "MISSING")
	debug_info += "\nState:\n"
	debug_info += "- current_workflow: %s\n" % owner.current_workflow
	debug_info += "- document_context_enabled: %s\n" % owner.document_context_enabled
	debug_info += "- conversation_manager: %s\n" % ("OK" if owner.conversation_manager else "MISSING")
	if owner.chat_history:
		debug_info += "\nChat History:\n"
		debug_info += "- visible: %s\n" % owner.chat_history.visible
		debug_info += "- editable: %s\n" % owner.chat_history.editable
		debug_info += "- text_length: %d\n" % chat_history_text(owner.chat_history).length()
	if owner.context_toggle_button:
		debug_info += "\nContext Button:\n"
		debug_info += "- text: %s\n" % owner.context_toggle_button.text
		debug_info += "- disabled: %s\n" % owner.context_toggle_button.disabled
		debug_info += "- visible: %s\n" % owner.context_toggle_button.visible
	if DocumentSessionManager:
		var session_summary = DocumentSessionManager.get_session_summary()
		debug_info += "\nDocument Session:\n"
		debug_info += "- document_count: %d\n" % session_summary.document_count
		debug_info += "- primary_document: %s\n" % session_summary.primary_document
	owner._append_to_chat("system", "[color=cyan]%s[/color]" % debug_info)
	print("Brainstorming Tab: Debug info displayed")

static func test_fixes(owner) -> void:
	print("=== TESTING RECENT FIXES ===")
	owner._append_to_chat("system", "[color=yellow]🔧 Testing recent fixes...[/color]")
	owner._append_to_chat("system", "[color=green]✅ Test 1: If you can see this GREEN text, BBCode is working![/color]")
	owner._append_to_chat("user", "[color=lightgreen]This should be light green user text[/color]")
	owner._append_to_chat("assistant", "[color=lightblue]This should be light blue assistant text[/color]")
	var context_status := "UNKNOWN"
	if owner.context_toggle_button:
		if DocumentSessionManager:
			var session_summary = DocumentSessionManager.get_session_summary()
			var has_documents: bool = session_summary.document_count > 0
			if owner.context_toggle_button.disabled:
				context_status = "❌ DISABLED but should be ENABLED (documents available)" if has_documents else "✅ CORRECTLY DISABLED (no documents available)"
			else:
				context_status = "✅ CORRECTLY ENABLED (documents available)" if has_documents else "❌ ENABLED but should be DISABLED (no documents available)"
		else:
			context_status = "❌ DocumentSessionManager not available"
	else:
		context_status = "❌ CONTEXT BUTTON NOT FOUND"
	owner._append_to_chat("system", "[color=cyan]Test 2 - Context Button: %s[/color]" % context_status)
	var workflow_status: String = "Current workflow: %s" % owner.current_workflow
	if WorkflowManager:
		var actual_workflow: String = WorkflowManager.get_current_workflow_name()
		workflow_status += " ✅ (matches WorkflowManager)" if actual_workflow == owner.current_workflow else " ❌ (WorkflowManager says: %s)" % actual_workflow
	else:
		workflow_status += " ❌ (WorkflowManager not available)"
	owner._append_to_chat("system", "[color=cyan]Test 3 - Workflow: %s[/color]" % workflow_status)
	var doc_status := ""
	if DocumentSessionManager:
		var session_summary2 = DocumentSessionManager.get_session_summary()
		doc_status = "Documents: %d, Primary: %s" % [session_summary2.document_count, session_summary2.primary_document]
	else:
		doc_status = "DocumentSessionManager not available"
	owner._append_to_chat("system", "[color=cyan]Test 4 - Documents: %s[/color]" % doc_status)
	owner._append_to_chat("system", "[color=yellow]🔧 Fix testing complete! Check results above.[/color]")
	print("=== FIX TESTING COMPLETE ===")

static func debug_chat_history_visibility(owner) -> void:
	print("\n=== CHAT HISTORY VISIBILITY DEBUG ===")
	print("Brainstorming Tab Self:")
	print("  - Name: ", owner.name)
	print("  - Visible: ", owner.visible)
	print("  - Modulate: ", owner.modulate)
	print("  - Size: ", owner.size)
	print("  - Position: ", owner.position)
	print("  - In tree: ", owner.is_inside_tree())
	var current_node = owner
	var depth := 0
	while current_node and depth < 5:
		print("  Parent level ", depth, ": ", current_node.name)
		print("    - Type: ", current_node.get_class())
		print("    - Visible: ", current_node.visible)
		print("    - Size: ", current_node.size)
		current_node = current_node.get_parent()
		depth += 1
	if owner.chat_history:
		print("\nChatHistory Node:")
		print("  - Name: ", owner.chat_history.name)
		print("  - Type: ", owner.chat_history.get_class())
		print("  - Visible: ", owner.chat_history.visible)
		print("  - Size: ", owner.chat_history.size)
		print("  - Position: ", owner.chat_history.position)
		print("  - Modulate: ", owner.chat_history.modulate)
		print("  - Clip contents: ", owner.chat_history.clip_contents)
		print("  - Text length: ", chat_history_text(owner.chat_history).length())
		var scroll_container = owner.chat_history.get_parent()
		if scroll_container:
			print("\nScrollContainer Parent:")
			print("  - Name: ", scroll_container.name)
			print("  - Type: ", scroll_container.get_class())
			print("  - Visible: ", scroll_container.visible)
			print("  - Size: ", scroll_container.size)
			print("  - Position: ", scroll_container.position)
			if scroll_container.has_method("get_rect"):
				var rect = scroll_container.get_rect()
				print("  - Rect: ", rect)
				if rect.size.x <= 0 or rect.size.y <= 0:
					print("  - ⚠️ ScrollContainer has zero size!")
		if owner.chat_history.has_method("get_rect"):
			var chat_rect = owner.chat_history.get_rect()
			print("  - ChatHistory rect: ", chat_rect)
			if chat_rect.size.x <= 0 or chat_rect.size.y <= 0:
				print("  - ⚠️ ChatHistory has zero size!")
	else:
		print("\n❌ ChatHistory node is NULL!")
	print("=== END VISIBILITY DEBUG ===\n")

static func debug_node_structure(owner) -> void:
	print("\n=== NODE STRUCTURE DEBUG ===")
	print("Brainstorming Tab children:")
	print_node_tree(owner, owner, 0, 3)
	print("\nSearching for ChatHistory manually...")
	var found_chat: Node = find_node_by_name(owner, owner, "ChatHistory")
	if found_chat:
		print("✅ Found ChatHistory at path: ", found_chat.get_path())
		owner.chat_history = found_chat as TextEdit
	else:
		print("❌ Could not find ChatHistory node anywhere in tree")
	print("=== END STRUCTURE DEBUG ===\n")

static func print_node_tree(_owner, node: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	var indent := "  ".repeat(depth)
	var is_visible_text := "N/A"
	if node is CanvasItem:
		is_visible_text = str((node as CanvasItem).visible)
	var size_text := "N/A"
	if node is Control:
		size_text = str((node as Control).size)
	print("%s- %s (%s) - visible: %s, size: %s" % [indent, node.name, node.get_class(), is_visible_text, size_text])
	for child in node.get_children():
		print_node_tree(_owner, child, depth + 1, max_depth)

static func find_node_by_name(_owner, node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found: Node = find_node_by_name(_owner, child, target_name)
		if found:
			return found
	return null

static func attempt_chat_history_fix(owner) -> void:
	print("\n=== ATTEMPTING CHAT HISTORY FIX ===")
	if not owner.chat_history:
		print("Attempting to find ChatHistory node...")
		var found_history: Node = find_node_by_name(owner, owner, "ChatHistory")
		owner.chat_history = found_history as TextEdit
		if owner.chat_history:
			print("✅ Found and reconnected ChatHistory")
		else:
			print("❌ Could not find ChatHistory node")
			return
	if owner.chat_history:
		print("Configuring ChatHistory...")
		owner.chat_history.visible = true
		if owner.chat_history is TextEdit:
			var history_edit: TextEdit = owner.chat_history
			history_edit.editable = true
			history_edit.shortcut_keys_enabled = true
			history_edit.context_menu_enabled = true
			history_edit.selecting_enabled = true
			history_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			history_edit.clear()
			history_edit.text = "Chat History Fix Applied!\n"
		if owner.chat_history.get_parent():
			owner.chat_history.get_parent().queue_sort()
		print("✅ ChatHistory configuration complete")
		print("  - Visible: ", owner.chat_history.visible)
		print("  - Size: ", owner.chat_history.size)
		print("  - Text length: ", chat_history_text(owner.chat_history).length())
	print("=== FIX ATTEMPT COMPLETE ===\n")

static func debug_layout_issues(owner) -> void:
	print("\n=== LAYOUT DEBUG ===")
	var mission_control = owner.get_tree().get_first_node_in_group("mission_control")
	if not mission_control:
		print("❌ Could not find mission control")
		return
	print("Mission Control found: ", mission_control.name)
	print("Mission Control size: ", mission_control.size)
	for node_path in [
		"HSplitContainer",
		"HSplitContainer/LeftPanelContainer",
		"HSplitContainer/LeftPanelContainer/MarginContainer/ScrollContainer",
		"HSplitContainer/LeftPanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BrainstormingContainer",
		"HSplitContainer/MainTabContainer",
	]:
		var node = mission_control.get_node_or_null(node_path)
		if node:
			print("\n", node.name, ":")
			print("  - Size: ", node.size)
			print("  - Position: ", node.position)
			print("  - Visible: ", node.visible)
			if node is SplitContainer:
				print("  - Split offset: ", node.split_offset)
			if node_path.ends_with("BrainstormingContainer"):
				print("  - Children count: ", node.get_child_count())
				for child in node.get_children():
					print("  - Child: ", child.name, " (", child.get_class(), ") - size: ", child.size, ", visible: ", child.visible)
	print("\nBrainstorming Tab Hierarchy:")
	print("Self:")
	print("  - Size: ", owner.size)
	print("  - Position: ", owner.position)
	print("  - Global position: ", owner.global_position)
	print("  - Visible: ", owner.visible)
	if owner.chat_history:
		print("ChatHistory:")
		print("  - Size: ", owner.chat_history.size)
		print("  - Position: ", owner.chat_history.position)
		print("  - Global position: ", owner.chat_history.global_position)
		print("  - Visible: ", owner.chat_history.visible)
		print("  - Get rect: ", owner.chat_history.get_rect())
	print("=== END LAYOUT DEBUG ===\n")

static func force_visibility_fix(owner) -> void:
	print("\n=== FORCING VISIBILITY FIX ===")
	var mission_control = owner.get_tree().get_first_node_in_group("mission_control")
	if not mission_control:
		print("❌ Could not find mission control")
		return
	var hsplit = mission_control.get_node_or_null("HSplitContainer")
	if hsplit:
		print("Adjusting HSplitContainer split...")
		hsplit.split_offset = 400
	var left_panel = mission_control.get_node_or_null("HSplitContainer/LeftPanelContainer")
	if left_panel:
		left_panel.visible = true
		left_panel.custom_minimum_size = Vector2(350, 600)
	var brainstorm_container = mission_control.get_node_or_null("HSplitContainer/LeftPanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BrainstormingContainer")
	if brainstorm_container:
		brainstorm_container.visible = true
		brainstorm_container.custom_minimum_size = Vector2(350, 400)
	var scroll_container = mission_control.get_node_or_null("HSplitContainer/LeftPanelContainer/MarginContainer/ScrollContainer")
	if scroll_container:
		scroll_container.custom_minimum_size = Vector2(350, 500)
	owner.visible = true
	owner.custom_minimum_size = Vector2(300, 400)
	if owner.chat_history:
		owner.chat_history.visible = true
		owner.chat_history.custom_minimum_size = Vector2(280, 300)
		var max_height := 300
		if owner.chat_history.size.y > max_height:
			print("ChatHistory is too tall (", owner.chat_history.size.y, "px)! Forcing to ", max_height, "px")
			owner.chat_history.size = Vector2(owner.chat_history.size.x, max_height)
		owner.chat_history.clip_contents = true
		var scroll_parent = owner.chat_history.get_parent()
		if scroll_parent:
			scroll_parent.visible = true
			scroll_parent.custom_minimum_size = Vector2(280, 300)
			if scroll_parent is HSplitContainer:
				scroll_parent.split_offset = -300
				scroll_parent.queue_redraw()
		owner.chat_history.queue_redraw()
		var chat_scroll_parent = owner.chat_history.get_parent()
		if chat_scroll_parent is ScrollContainer:
			chat_scroll_parent.scroll_vertical = chat_scroll_parent.get_v_scroll_bar().max_value
	else:
		print("Emergency: ChatHistory not found!")
	var root = owner.get_tree().current_scene
	if root:
		root.queue_redraw()
	if mission_control:
		mission_control.queue_redraw()
		mission_control.notification(Control.NOTIFICATION_RESIZED)
	if hsplit:
		hsplit.queue_redraw()
	owner.queue_redraw()
	owner.notification(Control.NOTIFICATION_RESIZED)
	await owner.get_tree().process_frame
	await owner.get_tree().process_frame
	print("Results after force fix:")
	if owner.chat_history:
		print("  - ChatHistory size: ", owner.chat_history.size)
		print("  - ChatHistory global position: ", owner.chat_history.global_position)
		print("  - ChatHistory visible: ", owner.chat_history.visible)
	if brainstorm_container:
		print("  - BrainstormingContainer size after fix: ", brainstorm_container.size)
	if scroll_container:
		print("  - ScrollContainer size after fix: ", scroll_container.size)
	print("  - Self size after fix: ", owner.size)
	print("=== FORCE FIX COMPLETE ===\n")

static func setup_emergency_debug(owner) -> void:
	print("Brainstorming Tab: Setting up emergency debug system...")
	owner.debug_timer = Timer.new()
	owner.debug_timer.wait_time = 10.0
	owner.debug_timer.timeout.connect(Callable(owner, "_monitor_input_state"))
	owner.add_child(owner.debug_timer)
	owner.debug_timer.start()
	print("Brainstorming Tab: Emergency debug system ready")
	print("Brainstorming Tab: 💡 Click context button 5 times quickly to trigger emergency debug")
	print("Brainstorming Tab: 💡 Click context button 3 times quickly to test cursor visibility")
	print("Brainstorming Tab: 💡 Click context button 7 times quickly to test mode integration")

static func monitor_input_state(owner) -> void:
	if owner.prompt_input and owner.prompt_input.editable == false:
		print("Brainstorming Tab: ⚠️ Input field is disabled! Auto-fixing...")
		fix_input_field_focus(owner)
		if owner.debug_timer.wait_time == 10.0:
			owner.debug_timer.wait_time = 60.0
		elif owner.debug_timer.wait_time == 60.0:
			print("Brainstorming Tab: Input still disabled after auto-fix, triggering full emergency debug")
			owner._emergency_debug_sequence()
			owner.debug_timer.wait_time = 300.0

static func emergency_debug_sequence(owner) -> void:
	print("\n🚨🚨🚨 EMERGENCY DEBUG SEQUENCE 🚨🚨🚨")
	owner._append_to_chat("system", "[color=red]🚨 EMERGENCY DEBUG ACTIVATED 🚨[/color]")
	if owner.prompt_input:
		owner._append_to_chat("system", "[color=yellow]Input Field Status:[/color]")
		owner._append_to_chat("system", "- Editable: %s" % owner.prompt_input.editable)
		owner._append_to_chat("system", "- Visible: %s" % owner.prompt_input.visible)
		owner._append_to_chat("system", "- Size: %s" % str(owner.prompt_input.size))
	if owner.generate_button:
		owner._append_to_chat("system", "[color=yellow]Generate Button Status:[/color]")
		owner._append_to_chat("system", "- Disabled: %s" % owner.generate_button.disabled)
		owner._append_to_chat("system", "- Text: %s" % owner.generate_button.text)
	owner._append_to_chat("system", "[color=yellow]ConversationManager Status:[/color]")
	owner._append_to_chat("system", "- Available: ✅ YES" if owner.conversation_manager else "- Available: ❌ NO - This is likely the problem!")
	owner._append_to_chat("system", "[color=cyan]Running layout diagnostics...[/color]")
	await owner.get_tree().process_frame
	debug_layout_issues(owner)
	owner._append_to_chat("system", "[color=green]Attempting automatic fixes...[/color]")
	await owner.get_tree().process_frame
	if owner.prompt_input:
		owner.prompt_input.editable = true
	if owner.generate_button:
		owner.generate_button.disabled = false
	fix_input_field_focus(owner)
	if owner.prompt_input:
		owner.prompt_input.add_theme_color_override("caret_color", get_optimal_cursor_color(owner))
		fix_placeholder_visibility(owner)
	await force_visibility_fix(owner)
	if not owner.conversation_manager:
		owner._append_to_chat("system", "[color=yellow]Attempting to reconnect ConversationManager...[/color]")
		owner._connect_to_orchestrator()
	owner._append_to_chat("system", "[color=green]🔧 Emergency debug sequence complete![/color]")
	owner._append_to_chat("system", "[color=cyan]Check console output for detailed diagnostics[/color]")
	print("🚨🚨🚨 EMERGENCY DEBUG SEQUENCE COMPLETE 🚨🚨🚨\n")

static func apply_initial_layout_fixes(owner) -> void:
	print("Brainstorming Tab: Applying initial layout fixes...")
	await owner.get_tree().process_frame
	await owner.get_tree().process_frame
	await force_visibility_fix(owner)
	fix_input_field_focus(owner)
	print("Brainstorming Tab: Initial layout fixes complete")

static func immediate_cursor_fix(owner) -> void:
	print("Brainstorming Tab: Applying immediate cursor fix...")
	if not owner.prompt_input:
		print("Brainstorming Tab: No prompt_input for immediate cursor fix")
		return
	var cursor_color: Color = get_optimal_cursor_color(owner)
	owner.prompt_input.add_theme_color_override("caret_color", cursor_color)
	owner.prompt_input.caret_blink = true
	owner.prompt_input.caret_blink_interval = 0.5
	fix_placeholder_visibility(owner)
	print("Brainstorming Tab: Immediate cursor fix applied - color: ", cursor_color)

static func fix_input_field_focus(owner) -> void:
	if not owner.prompt_input:
		print("Brainstorming Tab: No prompt_input found for focus fix")
		return
	print("Brainstorming Tab: Fixing input field focus...")
	owner.prompt_input.mouse_filter = Control.MOUSE_FILTER_STOP
	owner.prompt_input.focus_mode = Control.FOCUS_ALL
	owner.prompt_input.caret_blink = true
	owner.prompt_input.caret_blink_interval = 0.5
	fix_placeholder_visibility(owner)
	if not owner.prompt_input.focus_entered.is_connected(Callable(owner, "_on_input_focus_entered")):
		owner.prompt_input.focus_entered.connect(Callable(owner, "_on_input_focus_entered"))
	if not owner.prompt_input.focus_exited.is_connected(Callable(owner, "_on_input_focus_exited")):
		owner.prompt_input.focus_exited.connect(Callable(owner, "_on_input_focus_exited"))
	if owner.prompt_input.has_signal("gui_input"):
		if not owner.prompt_input.gui_input.is_connected(Callable(owner, "_on_input_clicked")):
			owner.prompt_input.gui_input.connect(Callable(owner, "_on_input_clicked"))
	owner.prompt_input.grab_focus()
	var optimal_cursor_color: Color = get_optimal_cursor_color(owner)
	owner.prompt_input.add_theme_color_override("caret_color", optimal_cursor_color)
	print("  - Set cursor color to: ", optimal_cursor_color)
	print("Brainstorming Tab: Input field focus fixed")
	print("  - Has focus: ", owner.prompt_input.has_focus())
	print("  - Caret blink: ", owner.prompt_input.caret_blink)

static func on_input_clicked(owner, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print("Brainstorming Tab: Input field clicked - grabbing focus")
		owner.prompt_input.grab_focus()
		owner.prompt_input.caret_blink = true
		owner.prompt_input.add_theme_color_override("caret_color", get_optimal_cursor_color(owner))

static func on_input_focus_entered(owner) -> void:
	print("Brainstorming Tab: Input field gained focus")
	owner.prompt_input.caret_blink = true
	owner.prompt_input.caret_blink_interval = 0.5
	owner.prompt_input.add_theme_color_override("caret_color", get_optimal_cursor_color(owner))
	if owner.prompt_input.text.is_empty():
		owner.prompt_input.add_theme_color_override("font_placeholder_color", Color(0.3, 0.3, 0.3, 1.0))
	print("  - Focus gained, cursor should now be visible")

static func on_input_focus_exited(owner) -> void:
	print("Brainstorming Tab: Input field lost focus")
	fix_placeholder_visibility(owner)

static func on_visibility_changed(owner) -> void:
	if owner.visible:
		print("Brainstorming Tab: Now visible - ensuring input focus")
		owner.call_deferred("_fix_input_field_focus")
	else:
		print("Brainstorming Tab: Now hidden")

static func test_cursor_visibility(owner) -> void:
	print("\n🔍🔍🔍 CURSOR VISIBILITY TEST 🔍🔍🔍")
	owner._append_to_chat("system", "[color=cyan]🔍 CURSOR VISIBILITY TEST ACTIVATED[/color]")
	if not owner.prompt_input:
		owner._append_to_chat("system", "[color=red]❌ No input field found![/color]")
		return
	owner._append_to_chat("system", "[color=yellow]Current Input Field State:[/color]")
	owner._append_to_chat("system", "- Text: '%s'" % owner.prompt_input.text)
	owner._append_to_chat("system", "- Placeholder: '%s'" % owner.prompt_input.placeholder_text)
	owner._append_to_chat("system", "- Has focus: %s" % owner.prompt_input.has_focus())
	owner._append_to_chat("system", "- Editable: %s" % owner.prompt_input.editable)
	owner._append_to_chat("system", "[color=green]Applying cursor fixes...[/color]")
	var original_placeholder: String = owner.prompt_input.placeholder_text
	owner.prompt_input.placeholder_text = ""
	owner.prompt_input.grab_focus()
	owner.prompt_input.caret_blink = true
	owner.prompt_input.caret_blink_interval = 0.3
	owner.prompt_input.caret_column = 0 if owner.prompt_input.text.is_empty() else owner.prompt_input.text.length()
	var optimal_color: Color = get_optimal_cursor_color(owner)
	owner.prompt_input.add_theme_color_override("caret_color", optimal_color)
	owner.prompt_input.add_theme_color_override("font_placeholder_color", Color(0.4, 0.4, 0.4, 1.0))
	await owner.get_tree().create_timer(3.0).timeout
	owner.prompt_input.placeholder_text = original_placeholder
	owner._append_to_chat("system", "[color=cyan]💡 Try typing now - cursor should be visible![/color]")
	print("🔍🔍🔍 CURSOR VISIBILITY TEST COMPLETE 🔍🔍🔍\n")

static func test_mode_integration(owner) -> void:
	print("\n🧪🧪🧪 MODE INTEGRATION TEST 🧪🧪🧪")
	owner._append_to_chat("system", "[color=cyan]🧪 MODE INTEGRATION TEST ACTIVATED[/color]")
	if not ModeManager or not EditMetaprompts:
		owner._append_to_chat("system", "[color=red]❌ Required systems not available[/color]")
		owner._append_to_chat("system", "- ModeManager: %s" % ("✅" if ModeManager else "❌"))
		owner._append_to_chat("system", "- EditMetaprompts: %s" % ("✅" if EditMetaprompts else "❌"))
		return
	owner._append_to_chat("system", "[color=green]✅ All required systems available[/color]")
	var current_work_mode: String = ModeManager.get_current_mode()
	var current_mode_config = ModeManager.get_current_config()
	owner._append_to_chat("system", "[color=yellow]Current Work Mode: %s[/color]" % current_mode_config.name)
	owner._append_to_chat("system", "Target Formats: %s" % ", ".join(current_mode_config.formats.slice(0, 3)))
	owner._append_to_chat("system", "Target Channels: %s" % ", ".join(current_mode_config.channels.slice(0, 3)))
	for edit_mode in ["developmental", "content", "line"]:
		owner._append_to_chat("system", "[color=cyan]Testing Edit Mode: %s[/color]" % edit_mode.capitalize())
		var test_context := {
			"document_name": "Mode Integration Test",
			"word_count": 450,
			"selected_text": "This is a sample text for testing how the editing system adapts to different work modes and provides specialized guidance.",
			"selection_context": "Previous context. [SELECTED TEXT] Following context.",
			"document_context": "Test document for mode integration verification"
		}
		var prompt: String = EditMetaprompts.get_edit_prompt(edit_mode, test_context, "Please provide editing suggestions.")
		var has_work_mode_section: bool = "WORK MODE:" in prompt
		var has_mode_guidance := false
		if current_work_mode == "social_media":
			has_mode_guidance = "platform" in prompt.to_lower() or "engagement" in prompt.to_lower()
		elif current_work_mode == "creative_writing":
			has_mode_guidance = "character" in prompt.to_lower() or "story" in prompt.to_lower()
		elif current_work_mode == "academic_writing":
			has_mode_guidance = "citation" in prompt.to_lower() or "scholarly" in prompt.to_lower()
		owner._append_to_chat("system", "- Work mode section: %s" % ("✅" if has_work_mode_section else "❌"))
		owner._append_to_chat("system", "- Mode guidance: %s" % ("✅" if has_mode_guidance else "❌"))
		owner._append_to_chat("system", "- Prompt length: %d chars" % prompt.length())
	owner._append_to_chat("system", "[color=yellow]Testing Mode Switching...[/color]")
	var different_prompts: Array = []
	for work_mode_id in ["social_media", "creative_writing", "academic_writing"]:
		ModeManager.set_mode(work_mode_id)
		await owner.get_tree().process_frame
		var context := {
			"document_name": "Mode Switch Test",
			"word_count": 300,
			"selected_text": "Testing mode switching effects on editing prompts.",
			"selection_context": "Context for mode switching test.",
			"document_context": "Document for testing mode switching"
		}
		var prompt_for_mode: String = EditMetaprompts.get_edit_prompt("content", context, "Test mode switching.")
		different_prompts.append(prompt_for_mode)
		owner._append_to_chat("system", "- %s: %d chars" % [work_mode_id.replace("_", " ").capitalize(), prompt_for_mode.length()])
	var prompts_are_different := true
	for prompt_index in range(different_prompts.size()):
		for compare_index in range(prompt_index + 1, different_prompts.size()):
			if different_prompts[prompt_index] == different_prompts[compare_index]:
				prompts_are_different = false
				break
		if not prompts_are_different:
			break
	owner._append_to_chat("system", "[color=green]✅ Mode switching generates different prompts[/color]" if prompts_are_different else "[color=red]❌ Mode switching not affecting prompts[/color]")
	ModeManager.set_mode(current_work_mode)
	await owner.get_tree().process_frame
	owner._append_to_chat("system", "[color=green]🎉 Mode integration test complete![/color]")
	owner._append_to_chat("system", "[color=cyan]Check console for detailed results[/color]")
	print("🧪🧪🧪 MODE INTEGRATION TEST COMPLETE 🧪🧪🧪\n")

static func get_optimal_cursor_color(owner) -> Color:
	if not owner.prompt_input:
		return Color.BLACK
	var bg_color := Color.WHITE
	var style_box = owner.prompt_input.get_theme_stylebox("normal", "LineEdit")
	if style_box and style_box.has_method("get_bg_color"):
		bg_color = style_box.get_bg_color()
	var theme_bg: Color = owner.prompt_input.get_theme_color("font_color", "LineEdit")
	if theme_bg != Color.TRANSPARENT:
		print("Theme font color: ", theme_bg)
	var cursor_color := Color(0.1, 0.1, 0.3, 1.0)
	print("Cursor color analysis:")
	print("  - Detected background: ", bg_color)
	print("  - Using cursor color: ", cursor_color)
	return cursor_color

static func fix_placeholder_visibility(owner) -> void:
	if not owner.prompt_input:
		return
	print("Brainstorming Tab: Fixing placeholder visibility...")
	var placeholder_color := Color(0.4, 0.4, 0.4, 1.0)
	owner.prompt_input.add_theme_color_override("font_placeholder_color", placeholder_color)
	if owner.prompt_input.has_method("set_placeholder_alpha"):
		owner.prompt_input.set_placeholder_alpha(1.0)
	print("  - Set placeholder color to: ", placeholder_color)
	print("  - Placeholder text: '", owner.prompt_input.placeholder_text, "'")

static func on_input_text_changed(owner, _new_text: String) -> void:
	if owner.prompt_input.has_focus():
		if owner.prompt_input.caret_blink == false:
			print("Brainstorming Tab: Text changed, re-enabling cursor blink")
			owner.prompt_input.caret_blink = true
		owner.prompt_input.add_theme_color_override("caret_color", get_optimal_cursor_color(owner))
