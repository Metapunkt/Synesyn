extends VBoxContainer

const BRAINSTORMING_THREAD_ID = "BRAINSTORMING_THREAD"
const BrainstormingTabDebugUtilsScript = preload("res://readymade/ui/brainstorming_tab_debug_utils.gd")

var conversation_manager

# Hub substrate (session.turn events)
var _hub = null
var _session_id: String = ""

# Context-aware brainstorming variables
var current_workflow: String = ""
var document_context_enabled: bool = false
var context_indicator_text: String = ""

# Add to group for easy finding
func _enter_tree():
	add_to_group("brainstorming_tab")
	print("Brainstorming Tab: Added to group 'brainstorming_tab'")

func _on_tree_exited():
	remove_from_group("brainstorming_tab")

@onready var chat_history: TextEdit = $MarginContainer/VBoxContainer/ChatHistory
@onready var prompt_input = $MarginContainer/VBoxContainer/HBoxContainer/PromptInput
@onready var generate_button = $MarginContainer/VBoxContainer/HBoxContainer/GenerateButton
@onready var import_dialog = $ImportDialog
@onready var export_dialog = $ExportDialog
@onready var new_session_button = $MarginContainer/VBoxContainer/PanelContainer/HBoxContainer/NewSessionButton
@onready var import_button = $MarginContainer/VBoxContainer/PanelContainer/HBoxContainer/ImportButton
@onready var export_button = $MarginContainer/VBoxContainer/PanelContainer/HBoxContainer/ExportButton
@onready var paste_button = $MarginContainer/VBoxContainer/PanelContainer/HBoxContainer/PasteButton

# Context awareness UI components - will be created dynamically
var context_indicator_label: Label
var context_toggle_button: Button
var context_info_button: Button

# Emergency debug system
var context_button_click_count: int = 0
var last_context_click_time: float = 0.0
var debug_timer: Timer

func _ready():
	print("Brainstorming Tab: _ready() called")

	# Ensure a stable session id for this run (used for hub + metapunkt alignment).
	_session_id = SynesynSession.get_or_create_session_id("readymade")
	_hub = HubSubstrateClient.new()
	add_child(_hub)
	_hub.configure_from_runtime_config()
	
	# Debug: Check if we're in the scene tree and visible
	call_deferred("_debug_chat_history_visibility")
	
	# Configure chat_history as an editable paste target
	if chat_history:
		_configure_chat_history_for_editing()
		print("Brainstorming Tab: ✅ Chat history configured for editing")
		print("Brainstorming Tab: Chat history size: ", chat_history.size)
		print("Brainstorming Tab: Chat history visible: ", chat_history.visible)
		print("Brainstorming Tab: Chat history global position: ", chat_history.global_position)
	else:
		print("Brainstorming Tab: ❌ chat_history not found in _ready!")
		print("Brainstorming Tab: Attempting manual node path resolution...")
		
		# Try different possible paths
		var possible_paths = [
			"MarginContainer/VBoxContainer/ChatHistory",
			"./MarginContainer/VBoxContainer/ChatHistory",
			"MarginContainer/VBoxContainer/ScrollContainer/ChatHistory",
			"ChatHistory"
		]
		
		for path in possible_paths:
			var found_node = get_node_or_null(path)
			if found_node and found_node is TextEdit:
				print("Brainstorming Tab: ✅ Found ChatHistory at path: ", path)
				chat_history = found_node as TextEdit
				_configure_chat_history_for_editing()
				break
			else:
				print("Brainstorming Tab: ❌ No TextEdit at path: ", path)
		
		if not chat_history:
			call_deferred("_debug_node_structure")

	# Connect button signals
	new_session_button.pressed.connect(self._on_new_session_pressed)
	import_button.pressed.connect(self._on_import_button_pressed)
	export_button.pressed.connect(self._on_export_button_pressed)
	if paste_button and not paste_button.pressed.is_connected(_on_paste_button_pressed):
		paste_button.pressed.connect(_on_paste_button_pressed)
	generate_button.pressed.connect(self._on_generate_pressed)
	prompt_input.text_submitted.connect(self._on_generate_pressed)

	# Connect dialog signals
	import_dialog.file_selected.connect(self._on_import_dialog_file_selected)
	export_dialog.file_selected.connect(self._on_export_dialog_file_selected)

	# Setup context-aware UI components
	_setup_context_ui()
	
	# Connect to workflow and document managers
	call_deferred("_connect_to_managers")

	# Use deferred call to connect to orchestrator
	call_deferred("_connect_to_orchestrator")
	
	# Setup emergency debug system
	_setup_emergency_debug()
	
	# Apply initial layout fixes on startup
	call_deferred("_apply_initial_layout_fixes")
	
	# Apply immediate cursor fix
	call_deferred("_immediate_cursor_fix")
	
	# Connect visibility change signal to fix input focus when tab becomes visible
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	
	# Connect to input text changes to maintain cursor visibility
	if prompt_input and not prompt_input.text_changed.is_connected(_on_input_text_changed):
		prompt_input.text_changed.connect(_on_input_text_changed)

func _connect_to_orchestrator():
	print("Brainstorming Tab: Attempting to connect to ReadyMadeOrchestrator...")
	print("Brainstorming Tab: ReadyMadeOrchestrator exists: ", ReadyMadeOrchestrator != null)
	
	# The ReadyMadeOrchestrator singleton is responsible for ensuring the
	# PluginManager exists. We must wait for it to finish its setup.
	if ReadyMadeOrchestrator:
		ReadyMadeOrchestrator.workplan_loaded.connect(_on_orchestrator_ready)
		print("Brainstorming Tab: ✅ Connected to ReadyMadeOrchestrator")
		print("Brainstorming Tab: Workplan exists: ", ReadyMadeOrchestrator.workplan != null)
		# If orchestrator is already ready, trigger the event
		if ReadyMadeOrchestrator.workplan:
			print("Brainstorming Tab: Workplan ready, calling _on_orchestrator_ready()")
			_on_orchestrator_ready()
		else:
			print("Brainstorming Tab: Waiting for workplan_loaded signal...")
	else:
		# This is a fallback in case the orchestrator is missing.
		push_error("Brainstorming Tab: ReadyMadeOrchestrator singleton not found! Cannot initialize.")
		generate_button.disabled = true
		# Try again after a short delay
		print("Brainstorming Tab: Retrying connection in 0.1 seconds...")
		await get_tree().create_timer(0.1).timeout
		_connect_to_orchestrator()

func _on_orchestrator_ready():
	print("Brainstorming Tab: Orchestrator ready, checking PluginManager...")
	print("Brainstorming Tab: Engine.has_singleton('PluginManager'): ", Engine.has_singleton("PluginManager"))
	print("Brainstorming Tab: PluginManager direct access: ", PluginManager != null)
	
	# Try direct access first (since we know it's an autoload)
	if PluginManager:
		print("Brainstorming Tab: PluginManager found via direct access")
		print("Brainstorming Tab: PluginManager.is_ready(): ", PluginManager.is_ready())
		if PluginManager.is_ready():
			print("Brainstorming Tab: PluginManager is ready, calling _on_plugin_manager_ready()")
			_on_plugin_manager_ready()
		else:
			print("Brainstorming Tab: PluginManager not ready, connecting to initialization_completed signal")
			if PluginManager.has_signal("initialization_completed"):
				PluginManager.initialization_completed.connect(_on_plugin_manager_ready)
				print("Brainstorming Tab: Connected to initialization_completed signal")
			else:
				print("Brainstorming Tab: ⚠️ PluginManager missing initialization_completed signal!")
				generate_button.disabled = true
	# Fallback to Engine.has_singleton check
	elif Engine.has_singleton("PluginManager"):
		print("Brainstorming Tab: PluginManager singleton found via Engine")
		if PluginManager.is_ready():
			print("Brainstorming Tab: PluginManager is ready")
			_on_plugin_manager_ready()
		else:
			print("Brainstorming Tab: PluginManager not ready, connecting to initialization_completed signal")
			PluginManager.initialization_completed.connect(_on_plugin_manager_ready)
	else:
		push_error("Brainstorming Tab: PluginManager not found even after orchestrator setup!")
		generate_button.disabled = true

func _on_plugin_manager_ready():
	print("Brainstorming Tab: PluginManager ready, getting ConversationManager...")
	print("Brainstorming Tab: PluginManager exists: ", PluginManager != null)
	print("Brainstorming Tab: PluginManager is_ready: ", str(PluginManager.is_ready()) if PluginManager else "N/A")
	
	if not PluginManager:
		print("Brainstorming Tab: ⚠️ PluginManager is null!")
		generate_button.disabled = true
		return
		
	if not PluginManager.has_method("get_available_services"):
		print("Brainstorming Tab: ⚠️ PluginManager missing get_available_services method!")
		generate_button.disabled = true
		return
		
	var available_services = PluginManager.get_available_services()
	print("Brainstorming Tab: Available services: ", available_services)
	
	# Try both naming conventions
	conversation_manager = PluginManager.get_service("ConversationManager")
	if not conversation_manager:
		print("Brainstorming Tab: ConversationManager not found, trying conversation_manager...")
		conversation_manager = PluginManager.get_service("conversation_manager")
	
	if conversation_manager:
		print("Brainstorming Tab: ✅ ConversationManager obtained successfully: ", conversation_manager)
		generate_button.disabled = false
	else:
		print("Brainstorming Tab: ⚠️ ConversationManager not found with either name!")
		print("Brainstorming Tab: Available services: ", available_services)
		generate_button.disabled = true
	_load_chat_history()

func _load_chat_history():
	print("Brainstorming Tab: Loading chat history...")
	
	if not chat_history:
		print("Brainstorming Tab: ⚠️ chat_history component not found!")
		return
	
	chat_history.clear()
	print("Brainstorming Tab: Chat history cleared")
	
	if conversation_manager:
		print("Brainstorming Tab: ConversationManager available, getting messages for thread: ", BRAINSTORMING_THREAD_ID)
		var messages = conversation_manager.get_messages_for_thread(BRAINSTORMING_THREAD_ID)
		print("Brainstorming Tab: Retrieved ", messages.size(), " messages")
		
		if messages.size() == 0:
			_append_to_chat("system", "Welcome to context-aware brainstorming! 🧠✨")
			call_deferred("_check_initial_context_message")
		else:
			for message in messages:
				_append_to_chat(message.role, message.content)
	else:
		print("Brainstorming Tab: ⚠️ ConversationManager not available for loading chat history")
		_append_to_chat("system", "ConversationManager not available. Please check your setup.")

func _configure_chat_history_for_editing() -> void:
	if chat_history == null:
		return
	chat_history.editable = true
	chat_history.shortcut_keys_enabled = true
	chat_history.context_menu_enabled = true
	chat_history.selecting_enabled = true
	chat_history.focus_mode = Control.FOCUS_ALL
	chat_history.mouse_filter = Control.MOUSE_FILTER_STOP
	chat_history.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY

func _on_paste_button_pressed() -> void:
	var clipboard_text: String = DisplayServer.clipboard_get()
	if clipboard_text.is_empty() or chat_history == null:
		return
	chat_history.grab_focus()
	chat_history.insert_text_at_caret(clipboard_text)

func _plain_chat_content(raw_content: String) -> String:
	var bbcode_regex := RegEx.new()
	bbcode_regex.compile("\\[/?[^\\]]+\\]")
	return bbcode_regex.sub(raw_content, "", true)

func _scroll_chat_to_end() -> void:
	if chat_history == null:
		return
	var last_line: int = maxi(chat_history.get_line_count() - 1, 0)
	chat_history.set_caret_line(last_line)
	var scroll_bar: VScrollBar = chat_history.get_v_scroll_bar()
	if scroll_bar:
		scroll_bar.value = scroll_bar.max_value

func _append_to_chat(role, content):
	if not chat_history:
		print("Brainstorming Tab: ⚠️ chat_history not available for _append_to_chat!")
		print("Brainstorming Tab: Attempting to find ChatHistory...")
		_attempt_chat_history_fix()
		if not chat_history:
			print("Brainstorming Tab: ❌ Could not recover ChatHistory, message lost")
			return
	
	# Ensure content is not empty
	if content.strip_edges().is_empty():
		print("Brainstorming Tab: ⚠️ Attempting to append empty content for role: ", role)
		content = "[Empty response]"
	
	# Ensure chat_history is visible and configured
	if not chat_history.visible:
		print("Brainstorming Tab: ⚠️ chat_history is not visible, making it visible!")
		chat_history.visible = true
	_configure_chat_history_for_editing()
	
	var formatted_text: String = "%s:\n%s\n\n" % [role.capitalize(), _plain_chat_content(str(content))]
	print("Brainstorming Tab: Appending to chat - role: ", role, ", length: ", content.length())
	print("Brainstorming Tab: Formatted text (first 150 chars): ", formatted_text.substr(0, 150))
	
	var length_before: int = chat_history.text.length()
	chat_history.text += formatted_text
	_scroll_chat_to_end()
	
	await get_tree().process_frame
	var length_after: int = chat_history.text.length()
	
	print("Brainstorming Tab: Text length before: ", length_before, ", after: ", length_after)
	if length_after <= length_before:
		print("Brainstorming Tab: ⚠️ Text may not have been added properly!")
		print("Brainstorming Tab: Visible: ", chat_history.visible)
	
	print("Brainstorming Tab: Chat history text length: ", chat_history.text.length())

func _on_generate_pressed(text = ""):
	print("Brainstorming Tab: Generate button pressed")
	var prompt = prompt_input.text
	if prompt.strip_edges().is_empty():
		print("Brainstorming Tab: ⚠️ Empty prompt, ignoring")
		return

	# Handle debug commands
	if prompt.strip_edges().to_lower() == "/debug":
		show_debug_info()
		prompt_input.clear()
		return
	elif prompt.strip_edges().to_lower() == "/test":
		test_context_integration()
		_append_to_chat("system", "[color=green]✅ Context integration test completed. Check console for details.[/color]")
		prompt_input.clear()
		return
	elif prompt.strip_edges().to_lower() == "/testfix":
		test_fixes()
		prompt_input.clear()
		return
	elif prompt.strip_edges().to_lower() == "/visibility":
		_debug_chat_history_visibility()
		prompt_input.clear()
		return
	elif prompt.strip_edges().to_lower() == "/structure":
		_debug_node_structure()
		prompt_input.clear()
		return
	elif prompt.strip_edges().to_lower() == "/fixchat":
		_attempt_chat_history_fix()
		prompt_input.clear()
		return
	elif prompt.strip_edges().to_lower() == "/layout":
		_debug_layout_issues()
		prompt_input.clear()
		return
	elif prompt.strip_edges().to_lower() == "/forcefix":
		_force_visibility_fix()
		prompt_input.clear()
		return
	elif prompt.strip_edges().to_lower() == "/help":
		var help_text = "Available commands:\n"
		help_text += "/debug - Show debug information\n"
		help_text += "/test - Test context integration\n"
		help_text += "/testfix - Test the recent fixes\n"
		help_text += "/visibility - Debug chat history visibility\n"
		help_text += "/structure - Debug node structure\n"
		help_text += "/fixchat - Attempt to fix chat history\n"
		help_text += "/layout - Debug layout and sizing issues\n"
		help_text += "/forcefix - Force visibility and layout fixes\n"
		help_text += "/help - Show this help\n"
		help_text += "/context - Show current context info"
		_append_to_chat("system", "[color=cyan]%s[/color]" % help_text)
		prompt_input.clear()
		return
	elif prompt.strip_edges().to_lower() == "/context":
		var context_info = get_current_context_info()
		_append_to_chat("system", "[color=cyan]%s[/color]" % context_info)
		prompt_input.clear()
		return

	print("Brainstorming Tab: Processing prompt: ", prompt)
	
	# Build context-enhanced prompt
	var enhanced_prompt = _build_context_enhanced_prompt(prompt)
	var prompt_to_send = enhanced_prompt
	
	# Show user prompt in chat (original, not enhanced)
	_append_to_chat("user", prompt)
	var turn_id := _emit_session_turn_async(prompt, BRAINSTORMING_THREAD_ID)
	
	# Show context indicator if context was added
	if enhanced_prompt != prompt:
		_append_to_chat("system", "[color=cyan]💡 Added document context to prompt[/color]")
	
	prompt_input.clear()
	generate_button.disabled = true

	if conversation_manager:
		print("Brainstorming Tab: Sending prompt to ConversationManager...")
		print("Brainstorming Tab: Enhanced prompt length: ", enhanced_prompt.length())
		
		var response_dict = await conversation_manager.chat(prompt_to_send, BRAINSTORMING_THREAD_ID)
		
		print("Brainstorming Tab: Response received: ", response_dict)
		
		if response_dict and response_dict.get("success", false):
			var response_content = response_dict.get("response", "")
			print("Brainstorming Tab: Received response: ", response_content.substr(0, 100), "...")
			
			if response_content.strip_edges().is_empty():
				print("Brainstorming Tab: ⚠️ Empty response content")
				_append_to_chat("system", "[color=yellow]Warning: Received empty response[/color]")
			else:
				_append_to_chat("assistant", response_content)
				_emit_session_turn_completed_async(turn_id, true, "")
		else:
			var error_msg = response_dict.get("error", "Unknown error") if response_dict else "No response received"
			print("Brainstorming Tab: ⚠️ Error from ConversationManager: ", error_msg)
			_append_to_chat("system", "[color=red]Error: %s[/color]" % error_msg)
			_emit_session_turn_completed_async(turn_id, false, str(error_msg))
	else:
		print("Brainstorming Tab: ⚠️ ConversationManager not available")
		_append_to_chat("system", "[color=red]Error: ConversationManager not available.[/color]")
		_emit_session_turn_completed_async(turn_id, false, "conversation_manager_not_available")
	
	generate_button.disabled = false

func _emit_session_turn_async(user_input: String, thread_id: String) -> String:
	# Fire-and-forget best-effort substrate event for deterministic correlation.
	if not _hub:
		return ""
	var app_id := "readymade"
	var turn_id := "turn_%s_%d" % [app_id, int(Time.get_ticks_usec())]
	SynesynSession.set_current_turn_id(app_id, turn_id)
	SynesynSession.set_current_turn_id(app_id, turn_id)
	var payload := {
		"turn_id": turn_id,
		"role": "user",
		"text": user_input,
		"thread_id": thread_id,
		"t_client": float(Time.get_unix_time_from_system()),
	}
	var prov := {
		"component": "readymade",
		"app_id": app_id,
	}
	_hub.create_event_fire_and_forget("session.turn", payload, prov, app_id, 0, _session_id)
	return turn_id

func _emit_session_turn_completed_async(turn_id: String, ok: bool, error_message: String) -> void:
	if not _hub:
		return
	if turn_id.strip_edges().is_empty():
		return
	var app_id := "readymade"
	var error_val: Variant = null
	if not error_message.strip_edges().is_empty():
		error_val = error_message
	var payload := {
		"turn_id": turn_id,
		"ok": ok,
		"error": error_val,
		"t_client": float(Time.get_unix_time_from_system()),
	}
	var prov := {
		"component": "readymade",
		"app_id": app_id,
	}
	_hub.create_event_fire_and_forget("session.turn.completed", payload, prov, app_id, 0, _session_id)

func _on_new_session_pressed():
	if conversation_manager:
		# Clear the thread by updating it with empty messages
		conversation_manager.update_thread_messages(BRAINSTORMING_THREAD_ID, [])
		print("Brainstorming Tab: Cleared thread messages for new session")
	_load_chat_history()
	_append_to_chat("system", "New session started.")
	_append_to_chat("system", "[color=gray]💡 Tip: Type /help to see available commands, or /context to view current document context.[/color]")

func _on_export_button_pressed():
	export_dialog.popup_centered()

func _on_export_dialog_file_selected(path: String):
	if conversation_manager:
		var messages = conversation_manager.get_messages_for_thread(BRAINSTORMING_THREAD_ID)
		var file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(messages))
		file.close()

func _on_import_button_pressed():
	import_dialog.popup_centered()

func _on_import_dialog_file_selected(path: String):
	if FileAccess.file_exists(path) and conversation_manager:
		var file = FileAccess.open(path, FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(content) == OK:
			var messages = json.data
			if typeof(messages) == TYPE_ARRAY:
				# Use update_thread_messages to import the messages
				var result = conversation_manager.update_thread_messages(BRAINSTORMING_THREAD_ID, messages)
				if result.get("success", false):
					print("Brainstorming Tab: Successfully imported ", messages.size(), " messages")
					_load_chat_history()
					_append_to_chat("system", "Chat history imported successfully.")
				else:
					var error_msg = result.get("error", "Unknown error")
					print("Brainstorming Tab: Import failed: ", error_msg)
					_append_to_chat("system", "[color=red]Error importing chat: %s[/color]" % error_msg)
			else:
				_append_to_chat("system", "[color=red]Error: Invalid JSON format.[/color]")
		else:
			_append_to_chat("system", "[color=red]Error: Could not parse JSON file.[/color]")

# Context-Aware Brainstorming Functions
func _setup_context_ui():
	"""Setup UI components for context-aware brainstorming"""
	print("Brainstorming Tab: Setting up context UI...")
	
	# Check if we already have context UI
	var existing_container = get_node_or_null("ContextContainer")
	if existing_container:
		print("Brainstorming Tab: Context UI already exists, skipping setup")
		context_indicator_label = existing_container.get_node("Label")
		context_toggle_button = existing_container.get_node("ContextToggleButton")
		context_info_button = existing_container.get_node("ContextInfoButton")
		return
	
	# Wait for the node tree to be ready
	if not is_inside_tree():
		print("Brainstorming Tab: Not in tree yet, deferring context UI setup")
		call_deferred("_setup_context_ui")
		return
	
	# Find the panel container and add context info above it
	var panel_container = get_node_or_null("MarginContainer/VBoxContainer/PanelContainer")
	if not panel_container:
		print("Brainstorming Tab: ⚠️ Panel container not found, retrying...")
		call_deferred("_setup_context_ui")
		return
	
	# Create context indicator container
	var context_container = HBoxContainer.new()
	context_container.name = "ContextContainer"
	
	var parent = panel_container.get_parent()
	var index = panel_container.get_index()
	parent.add_child(context_container)
	parent.move_child(context_container, index)
	
	# Context indicator label
	context_indicator_label = Label.new()
	context_indicator_label.name = "Label"
	context_indicator_label.text = "💬 Brainstorming Mode"
	context_indicator_label.add_theme_font_size_override("font_size", 12)
	context_container.add_child(context_indicator_label)
	
	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_container.add_child(spacer)
	
	# Context toggle button
	context_toggle_button = Button.new()
	context_toggle_button.name = "ContextToggleButton"
	context_toggle_button.text = "📄 Include Document"
	context_toggle_button.disabled = true  # Will be enabled when in Edit Session
	context_toggle_button.pressed.connect(_on_context_toggle_pressed)
	context_container.add_child(context_toggle_button)
	
	# Context info button
	context_info_button = Button.new()
	context_info_button.name = "ContextInfoButton"
	context_info_button.text = "ℹ️"
	context_info_button.tooltip_text = "Show current context information"
	context_info_button.pressed.connect(_on_context_info_pressed)
	context_container.add_child(context_info_button)
	
	print("Brainstorming Tab: ✅ Context UI components created successfully")

func _connect_to_managers():
	"""Connect to WorkflowManager and DocumentSessionManager for context awareness"""
	# Connect to WorkflowManager
	if WorkflowManager:
		WorkflowManager.workflow_changed.connect(_on_workflow_changed)
		current_workflow = WorkflowManager.get_current_workflow_name()
		print("Brainstorming Tab: ✅ Connected to WorkflowManager, current workflow: ", current_workflow)
	else:
		print("Brainstorming Tab: ⚠️ WorkflowManager not available")
	
	# Connect to DocumentSessionManager
	if DocumentSessionManager:
		DocumentSessionManager.document_loaded.connect(_on_document_loaded)
		DocumentSessionManager.primary_document_changed.connect(_on_primary_document_changed)
		DocumentSessionManager.session_cleared.connect(_on_session_cleared)
		print("Brainstorming Tab: ✅ Connected to DocumentSessionManager")
	else:
		print("Brainstorming Tab: ⚠️ DocumentSessionManager not available")
	
	# Update context UI after connections are made
	call_deferred("_initial_context_update")
	
	# Set up periodic context update to catch missed events
	var timer = Timer.new()
	timer.wait_time = 1.0  # Check every second
	timer.timeout.connect(_periodic_context_update)
	add_child(timer)
	timer.start()

func _initial_context_update():
	"""Initial context update after all connections are made"""
	print("Brainstorming Tab: Performing initial context update")
	_update_context_ui()
	
	# Also update when chat history is loaded
	call_deferred("_update_context_ui")

func _check_initial_context_message():
	"""Check if we should show initial context message after chat history is loaded"""
	var session_summary: Variant = null
	if DocumentSessionManager:
		session_summary = DocumentSessionManager.get_session_summary()
	if session_summary != null and session_summary.document_count > 0:
		_append_to_chat("system", "[color=cyan]💡 You can enable document context to include your loaded documents in prompts.[/color]")
	else:
		_append_to_chat("system", "[color=yellow]💡 Load documents in Edit Session to enable context-aware brainstorming.[/color]")

func _periodic_context_update():
	"""Periodic update to catch any missed state changes"""
	# Only update if we detect a change
	var new_workflow = WorkflowManager.get_current_workflow_name() if WorkflowManager else ""
	var has_documents = false
	
	if DocumentSessionManager:
		var session_summary = DocumentSessionManager.get_session_summary()
		has_documents = session_summary.document_count > 0
	
	# Check if state has changed
	var state_changed = false
	if new_workflow != current_workflow:
		current_workflow = new_workflow
		state_changed = true
		print("Brainstorming Tab: Detected workflow change to: ", current_workflow)
	
	# Check if document state changed
	if (has_documents and context_toggle_button and context_toggle_button.disabled) or \
	   (not has_documents and context_toggle_button and not context_toggle_button.disabled):
		state_changed = true
		print("Brainstorming Tab: Detected document state change, has_documents: ", has_documents)
	
	if state_changed:
		_update_context_ui()

func _on_workflow_changed(new_workflow: String):
	"""Handle workflow changes"""
	current_workflow = new_workflow
	print("Brainstorming Tab: Workflow changed to: ", new_workflow)
	call_deferred("_update_context_ui")

func _on_document_loaded(document):
	"""Handle document loaded signal"""
	print("Brainstorming Tab: Document loaded: ", document.file_name if document else "unknown")
	call_deferred("_update_context_ui")

func _on_primary_document_changed(document):
	"""Handle primary document changed signal"""
	print("Brainstorming Tab: Primary document changed: ", document.file_name if document else "unknown")
	call_deferred("_update_context_ui")

func _on_session_cleared():
	"""Handle session cleared signal"""
	print("Brainstorming Tab: Document session cleared")
	call_deferred("_update_context_ui")

func _update_context_ui():
	"""Update context UI based on current workflow and document state"""
	if not context_indicator_label:
		print("Brainstorming Tab: ⚠️ context_indicator_label not available for update")
		return
	
	print("Brainstorming Tab: Updating context UI - workflow: ", current_workflow)
	
	# Check if documents are available regardless of current workflow
	var session_summary: Variant = null
	if DocumentSessionManager:
		session_summary = DocumentSessionManager.get_session_summary()
	var has_documents := false
	if session_summary != null:
		has_documents = session_summary.document_count > 0
	
	print("Brainstorming Tab: Documents available: ", has_documents)
	if has_documents:
		print("Brainstorming Tab: Document count: ", session_summary.document_count, ", Primary: ", session_summary.primary_document)
	
	if current_workflow == "edit_session":
		# In Edit Session workflow
		if has_documents:
			context_indicator_label.text = "📝 Edit Session | %d docs | %s" % [
				session_summary.document_count,
				session_summary.primary_document
			]
		else:
			context_indicator_label.text = "📝 Edit Session | No documents loaded"
	else:
		# Other workflows - show current workflow but indicate document availability
		var workflow_display = current_workflow.capitalize().replace("_", " ")
		if has_documents:
			context_indicator_label.text = "💬 %s | %d docs available" % [workflow_display, session_summary.document_count]
		else:
			context_indicator_label.text = "💬 %s Mode" % workflow_display
	
	# Enable context button if documents are available (regardless of workflow)
	# This allows cross-workflow document access - you can use document context
	# for brainstorming even when not currently in the Edit Session workflow
	if context_toggle_button:
		if has_documents:
			# Documents available - enable the button
			context_toggle_button.disabled = false
			if document_context_enabled:
				context_toggle_button.text = "📄 Document Context"
			else:
				context_toggle_button.text = "📄 Include Document"
			print("Brainstorming Tab: ✅ Enabled document context toggle button (documents available)")
		else:
			# No documents - disable the button
			context_toggle_button.disabled = true
			document_context_enabled = false
			context_toggle_button.text = "📄 No Documents"
			print("Brainstorming Tab: ❌ Disabled document context toggle button (no documents)")
	
	# Update button appearance based on context state
	if context_toggle_button:
		if document_context_enabled:
			context_toggle_button.modulate = Color.LIGHT_GREEN
		else:
			context_toggle_button.modulate = Color.WHITE
	
	print("Brainstorming Tab: Context UI updated - enabled: ", document_context_enabled, ", button disabled: ", str(context_toggle_button.disabled) if context_toggle_button else "N/A")

func _on_context_toggle_pressed():
	"""Toggle document context inclusion"""
	# Emergency debug system - detect rapid clicks
	var current_time = Time.get_time_dict_from_system()
	var time_stamp = current_time.hour * 3600 + current_time.minute * 60 + current_time.second
	
	if time_stamp - last_context_click_time < 3.0:  # Within 3 seconds
		context_button_click_count += 1
	else:
		context_button_click_count = 1
	
	last_context_click_time = time_stamp
	
	print("Brainstorming Tab: Context button click #", context_button_click_count)
	
	# Trigger cursor test on 3 rapid clicks
	if context_button_click_count == 3:
		print("Brainstorming Tab: 🔍 CURSOR TEST TRIGGERED! 🔍")
		_test_cursor_visibility()
		context_button_click_count = 0
		return
	
	# Trigger emergency debug on 5 rapid clicks
	if context_button_click_count >= 7:
		print("Brainstorming Tab: 🧪 MODE INTEGRATION TEST TRIGGERED! 🧪")
		_test_mode_integration()
		context_button_click_count = 0
		return
	elif context_button_click_count >= 5:
		print("Brainstorming Tab: 🚨 EMERGENCY DEBUG TRIGGERED! 🚨")
		_emergency_debug_sequence()
		context_button_click_count = 0
		return
	
	document_context_enabled = not document_context_enabled
	print("Brainstorming Tab: Document context enabled: ", document_context_enabled)
	_update_context_ui()
	
	# Show feedback
	if document_context_enabled:
		_append_to_chat("system", "[color=green]✅ Document context enabled. Your prompts will include information about the current document.[/color]")
	else:
		_append_to_chat("system", "[color=orange]📄 Document context disabled. Prompts will not include document information.[/color]")

func _on_context_info_pressed():
	"""Show current context information"""
	var context_info = get_current_context_info()
	var dialog = AcceptDialog.new()
	dialog.title = "Brainstorming Context Information"
	dialog.dialog_text = context_info
	get_tree().current_scene.add_child(dialog)
	dialog.popup_centered(Vector2(500, 400))
	dialog.confirmed.connect(func(): dialog.queue_free())

func get_current_context_info() -> String:
	"""Get formatted context information for display"""
	var info = "Current Brainstorming Context:\n\n"
	
	info += "Workflow: %s\n" % current_workflow.capitalize().replace("_", " ")
	info += "Document Context: %s\n\n" % ("Enabled" if document_context_enabled else "Disabled")
	
	if current_workflow == "edit_session" and DocumentSessionManager:
		var session_summary = DocumentSessionManager.get_session_summary()
		info += "Edit Session Information:\n"
		info += "- Documents loaded: %d\n" % session_summary.document_count
		info += "- Primary document: %s\n" % session_summary.primary_document
		info += "- Total words: %d\n" % session_summary.total_words
		
		if session_summary.unsaved_changes > 0:
			info += "- Unsaved changes: %d documents\n" % session_summary.unsaved_changes
		
		if document_context_enabled:
			info += "\nDocument context will be included in prompts."
		else:
			info += "\nDocument context is available but not included in prompts."
	else:
		info += "No document context available in current workflow."
	
	return info

func get_edit_session_context() -> Dictionary:
	"""Get document and selection context from DocumentSessionManager"""
	if not DocumentSessionManager:
		return {}
	
	var context = DocumentSessionManager.get_document_context_for_llm(true)
	
	# Try to get scratchpad selection context if available
	var scratchpad_context = _get_scratchpad_selection_context()
	if not scratchpad_context.is_empty():
		context.selection_context = scratchpad_context
	
	return context

func _get_scratchpad_selection_context() -> Dictionary:
	"""Get selection context from scratchpad if available"""
	# Try to find the scratchpad directly
	var scratchpad = get_tree().get_first_node_in_group("scratchpad")
	if scratchpad and scratchpad.has_method("get_selection_context"):
		return scratchpad.get_selection_context()
	
	# Fallback: find mission control or parent with selection context
	var mission_control = get_tree().get_first_node_in_group("mission_control")
	if not mission_control:
		# Try to find it by traversing up the tree
		var current = self
		while current and not mission_control:
			current = current.get_parent()
			if current and current.has_method("get_selection_context"):
				mission_control = current
				break
	
	if mission_control and mission_control.has_method("get_selection_context"):
		return mission_control.get_selection_context()
	
	return {}

func _build_context_enhanced_prompt(user_prompt: String) -> String:
	"""Build a prompt enhanced with document context"""
	if not document_context_enabled:
		return user_prompt
	
	# Get document context regardless of current workflow
	var context = get_edit_session_context()
	if context.is_empty():
		return user_prompt
	
	var enhanced_prompt = "Context: I'm working on a document editing session.\n\n"
	
	# Add primary document context
	if context.has("primary_document"):
		var primary = context.primary_document
		enhanced_prompt += "Primary Document: %s (%d words)\n" % [primary.name, primary.word_count]
		enhanced_prompt += "Content Preview:\n%s\n\n" % primary.content_preview
		
		if context.has("edit_mode"):
			enhanced_prompt += "Current Edit Mode: %s\n\n" % context.edit_mode
	
	# Add supporting documents if in multi-document context
	if context.get("context_type") == "multi_document" and context.has("supporting_documents"):
		enhanced_prompt += "Supporting Documents:\n"
		for doc in context.supporting_documents:
			enhanced_prompt += "- %s (%d words): %s\n" % [
				doc.name, 
				doc.word_count, 
				doc.get("relationship_to_primary", "related")
			]
		enhanced_prompt += "\n"
	
	# Add selection context if available
	if context.has("selection_context"):
		var selection = context.selection_context
		enhanced_prompt += "Current Selection: \"%s\"\n" % selection.get("selected_text", "")
		enhanced_prompt += "Context: %s\n\n" % selection.get("context_text", "")
	
	enhanced_prompt += "User Request: %s" % user_prompt
	
	return enhanced_prompt

# Testing and Debugging Functions
func test_context_integration():
	BrainstormingTabDebugUtilsScript.test_context_integration(self)

func show_debug_info():
	BrainstormingTabDebugUtilsScript.show_debug_info(self)

func test_fixes():
	BrainstormingTabDebugUtilsScript.test_fixes(self)

func _debug_chat_history_visibility():
	BrainstormingTabDebugUtilsScript.debug_chat_history_visibility(self)

func _debug_node_structure():
	BrainstormingTabDebugUtilsScript.debug_node_structure(self)

func _print_node_tree(node: Node, depth: int, max_depth: int):
	BrainstormingTabDebugUtilsScript.print_node_tree(self, node, depth, max_depth)

func _find_node_by_name(node: Node, target_name: String) -> Node:
	return BrainstormingTabDebugUtilsScript.find_node_by_name(self, node, target_name)

func _attempt_chat_history_fix():
	BrainstormingTabDebugUtilsScript.attempt_chat_history_fix(self)

func _debug_layout_issues():
	BrainstormingTabDebugUtilsScript.debug_layout_issues(self)

func _force_visibility_fix():
	await BrainstormingTabDebugUtilsScript.force_visibility_fix(self)

func _setup_emergency_debug():
	BrainstormingTabDebugUtilsScript.setup_emergency_debug(self)

func _monitor_input_state():
	BrainstormingTabDebugUtilsScript.monitor_input_state(self)

func _emergency_debug_sequence():
	await BrainstormingTabDebugUtilsScript.emergency_debug_sequence(self)

func _apply_initial_layout_fixes():
	await BrainstormingTabDebugUtilsScript.apply_initial_layout_fixes(self)

func _immediate_cursor_fix():
	BrainstormingTabDebugUtilsScript.immediate_cursor_fix(self)

func _fix_input_field_focus():
	BrainstormingTabDebugUtilsScript.fix_input_field_focus(self)

func _on_input_clicked(event: InputEvent):
	BrainstormingTabDebugUtilsScript.on_input_clicked(self, event)

func _on_input_focus_entered():
	BrainstormingTabDebugUtilsScript.on_input_focus_entered(self)

func _on_input_focus_exited():
	BrainstormingTabDebugUtilsScript.on_input_focus_exited(self)

func _on_visibility_changed():
	BrainstormingTabDebugUtilsScript.on_visibility_changed(self)

func _test_cursor_visibility():
	await BrainstormingTabDebugUtilsScript.test_cursor_visibility(self)

func _test_mode_integration():
	await BrainstormingTabDebugUtilsScript.test_mode_integration(self)

func _get_optimal_cursor_color() -> Color:
	return BrainstormingTabDebugUtilsScript.get_optimal_cursor_color(self)

func _fix_placeholder_visibility():
	BrainstormingTabDebugUtilsScript.fix_placeholder_visibility(self)

func _on_input_text_changed(_new_text: String):
	BrainstormingTabDebugUtilsScript.on_input_text_changed(self, _new_text)
