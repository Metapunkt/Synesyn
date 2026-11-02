## Purpose: ui/chat/message_container.gd
@tool
extends Control

const VERSION = "1.0.0"
const ResizeHandle = preload("res://addons/syntree/scripts/utils/ui/resize_handle.gd")
const CodeBlockScene = preload("res://addons/syntree/scenes/code_block.tscn")
const NotoSansBold = preload("res://tools/fonts/Noto_Sans/static/NotoSans-Bold.ttf")

signal message_edited(message_id: String, new_text: String)
signal message_deleted(message_id: String)
signal message_resend_requested(message_id: String)
signal show_edit_history_requested(formatted_text: String)
signal edit_history_saved(messages: Array)
signal assistant_message_added(content: String) # emitted when an assistant message is added (used by SynTree voice popup)

const _USER_MESSAGE_VARIATION := &"ChatMessageUser"
const _ASSISTANT_MESSAGE_VARIATION := &"ChatMessageAssistant"
const _CHAT_ROLE_VARIATION := &"LabelChatRole"
const _CHAT_TIMESTAMP_VARIATION := &"LabelChatTimestamp"
const _ASSISTANT_TEXT_COLOR := Color(0.16, 0.14, 0.22, 1)
const _ASSISTANT_TEXT_BG := Color(0.985, 0.982, 0.998, 0.96)
const _ASSISTANT_TEXT_BORDER := Color(0.67, 0.59, 0.93, 0.2)
const _CHAT_BODY_FONT_SIZE := 18
const _CHAT_ROLE_FONT_SIZE := 18
const _CHAT_TIMESTAMP_COLOR := Color(0.42, 0.39, 0.56, 0.78)
const _CHAT_ROLE_USER_COLOR := Color(0.29, 0.22, 0.49, 1)
const _CHAT_ROLE_ASSISTANT_COLOR := Color(0.2, 0.16, 0.38, 1)

# Message counter for generating unique IDs
var message_counter: int = 0

# UI References
@onready var messages_container: VBoxContainer = %MessagesContainer
@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var message_container_label: Label = %MessageContainerLabel

# --- ADDED FLAG --- 
var _is_empty: bool = true
# --- END FLAG --- 

func _ready() -> void:
	custom_minimum_size.y = 100
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL

func clear_messages() -> void:
	if not messages_container:
		push_error("Messages container not found")
		return
		
	for child in messages_container.get_children():
		child.queue_free()
	message_counter = 0
	
	# Show the initial label when cleared and set flag
	_is_empty = true # Set flag
	if is_instance_valid(message_container_label):
		message_container_label.visible = true

func _create_code_block(code: String, language: String = "") -> Control:
	var inst: Control = CodeBlockScene.instantiate()
	# Set language label if present in scene (HBoxContainer/Label)
	if inst and inst.has_node("HBoxContainer/Label"):
		var lbl := inst.get_node("HBoxContainer/Label")
		if lbl is Label:
			(lbl as Label).text = String(language).strip_edges()
			(lbl as Label).visible = not String(language).strip_edges().is_empty()
	if inst and inst.has_method("set_code"):
		# Defer until the node is in the tree so @onready vars in `code_block.gd` are initialized.
		inst.call_deferred("set_code", code.strip_edges())
	return inst

func _split_markdown_fences(text: String) -> Array[Dictionary]:
	# Returns segments in order:
	# [{kind:"text", text:String}, {kind:"code", lang:String, code:String}, ...]
	var s := String(text)
	var out: Array[Dictionary] = []
	var i := 0
	while true:
		var start := s.find("```", i)
		if start == -1:
			var tail := s.substr(i, s.length() - i)
			if not tail.is_empty():
				out.append({"kind": "text", "text": tail})
			break
		if start > i:
			var before := s.substr(i, start - i)
			if not before.is_empty():
				out.append({"kind": "text", "text": before})
		var lang_line_end := s.find("\n", start + 3)
		if lang_line_end == -1:
			# No newline after fence; treat remainder as text
			out.append({"kind": "text", "text": s.substr(start, s.length() - start)})
			break
		var lang := s.substr(start + 3, lang_line_end - (start + 3)).strip_edges()
		var end := s.find("```", lang_line_end + 1)
		if end == -1:
			# Unterminated fence; treat remainder as text
			out.append({"kind": "text", "text": s.substr(start, s.length() - start)})
			break
		var code := s.substr(lang_line_end + 1, end - (lang_line_end + 1))
		out.append({"kind": "code", "lang": lang, "code": code})
		i = end + 3
	return out

func create_message(content: String, role: String) -> Control:
	message_counter += 1
	var message_id = "message_%d" % message_counter
	
	var message_container = PanelContainer.new()
	message_container.name = message_id
	message_container.set_meta("role", role)
	message_container.set_meta("raw_content", content)
	message_container.size_flags_horizontal = SIZE_EXPAND_FILL
	message_container.theme_type_variation = _USER_MESSAGE_VARIATION if role.to_lower() in ["user", "user:"] else _ASSISTANT_MESSAGE_VARIATION
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	message_container.add_child(vbox)
	
	# Create header with role and timestamp
	var header = HBoxContainer.new()
	header.name = "HeaderRow"
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)
	header.size_flags_horizontal = SIZE_EXPAND_FILL
	
	var timestamp = Time.get_datetime_string_from_system() + " | "
	var role_display = ""
	if role.to_lower() == "user":
		role_display = "User"
	elif role.to_lower() == "assistant":
		role_display = "Assistant"
	var timestamp_label := Label.new()
	timestamp_label.name = "TimestampLabel"
	timestamp_label.theme_type_variation = _CHAT_TIMESTAMP_VARIATION
	timestamp_label.add_theme_color_override("font_color", _CHAT_TIMESTAMP_COLOR)
	timestamp_label.text = timestamp
	header.add_child(timestamp_label)
	
	var role_label := Label.new()
	role_label.name = "RoleLabel"
	role_label.theme_type_variation = _CHAT_ROLE_VARIATION
	role_label.add_theme_font_override("font", NotoSansBold)
	role_label.add_theme_font_size_override("font_size", _CHAT_ROLE_FONT_SIZE)
	if role.to_lower() in ["user", "user:"]:
		role_label.add_theme_color_override("font_color", _CHAT_ROLE_USER_COLOR)
	else:
		role_label.add_theme_color_override("font_color", _CHAT_ROLE_ASSISTANT_COLOR)
	role_label.text = role_display
	header.add_child(role_label)
	
	# Handle message content based on role
	if role.to_lower() in ["user", "user:"]:
		var content_edit = TextEdit.new()
		content_edit.name = "MessageText"
		vbox.add_child(content_edit)
		content_edit.unique_name_in_owner = true
		content_edit.text = content
		content_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		content_edit.editable = false
		content_edit.custom_minimum_size.y = 50
		content_edit.size_flags_horizontal = SIZE_EXPAND_FILL
		content_edit.size_flags_vertical = SIZE_EXPAND_FILL
		content_edit.add_theme_font_size_override("font_size", _CHAT_BODY_FONT_SIZE)
		content_edit.add_theme_constant_override("line_spacing", 6)
		
		# Add resize handle
		var resize_handle = ResizeHandle.new()
		resize_handle.parent_container = content_edit
		resize_handle.min_size = 50
		vbox.add_child(resize_handle)
	else:
		# Assistant: split markdown code fences into CodeBlock controls + normal text blocks.
		var body = VBoxContainer.new()
		body.name = "MessageText"
		body.unique_name_in_owner = true
		body.size_flags_horizontal = SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 8)
		vbox.add_child(body)
		
		var segments := _split_markdown_fences(content)
		for seg in segments:
			var kind := str(seg.get("kind", "text"))
			if kind == "code":
				body.add_child(_create_code_block(str(seg.get("code", "")), str(seg.get("lang", ""))))
			else:
				var t := str(seg.get("text", ""))
				if t.strip_edges().is_empty():
					continue
				body.add_child(_create_text_label(t))
		
		# Add resize handle
		var resize_handle = ResizeHandle.new()
		resize_handle.parent_container = body
		resize_handle.min_size = 50
		vbox.add_child(resize_handle)
	
	# Add message buttons
	var message_buttons = _create_message_buttons(message_id, role)
	vbox.add_child(message_buttons)
	
	# Add separator
	var separator = HSeparator.new()
	vbox.add_child(separator)
	
	messages_container.add_child(message_container)
	return message_container

func _create_text_label(text: String) -> RichTextLabel:
	var content_label = RichTextLabel.new()
	# Keep this plain-text to avoid markdown conversion bugs hiding content.
	content_label.bbcode_enabled = false
	content_label.selection_enabled = true
	content_label.fit_content = true
	content_label.scroll_active = false
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_label.size_flags_horizontal = SIZE_EXPAND_FILL
	content_label.add_theme_font_size_override("normal_font_size", _CHAT_BODY_FONT_SIZE)
	var text_style := StyleBoxFlat.new()
	text_style.content_margin_left = 10.0
	text_style.content_margin_top = 8.0
	text_style.content_margin_right = 10.0
	text_style.content_margin_bottom = 8.0
	text_style.bg_color = _ASSISTANT_TEXT_BG
	text_style.border_width_left = 1
	text_style.border_width_top = 1
	text_style.border_width_right = 1
	text_style.border_width_bottom = 1
	text_style.border_color = _ASSISTANT_TEXT_BORDER
	text_style.corner_radius_top_left = 8
	text_style.corner_radius_top_right = 8
	text_style.corner_radius_bottom_right = 8
	text_style.corner_radius_bottom_left = 8
	content_label.add_theme_stylebox_override("normal", text_style)
	content_label.add_theme_color_override("default_color", _ASSISTANT_TEXT_COLOR)

	content_label.text = text
	return content_label

func _create_message_buttons(message_id: String, role: String) -> HBoxContainer:
	var container = HBoxContainer.new()
	container.name = "MessageButtonsContainer"
	
	if role.to_lower() in ["user", "user:"]:
		var edit_button = Button.new()
		edit_button.name = "EditButton"
		edit_button.text = "Edit"
		edit_button.pressed.connect(_on_edit_pressed.bind(message_id))
		container.add_child(edit_button)
		
		var resend_button = Button.new()
		resend_button.name = "ResendButton"
		resend_button.text = "Resend"
		resend_button.pressed.connect(_on_resend_pressed.bind(message_id))
		resend_button.visible = false
		container.add_child(resend_button)
	
	var delete_button = Button.new()
	delete_button.name = "DeleteButton"
	delete_button.text = "Delete"
	delete_button.pressed.connect(_on_delete_pressed.bind(message_id))
	container.add_child(delete_button)
	
	return container

func _on_edit_pressed(message_id: String) -> void:
	var message_container = messages_container.get_node(message_id)
	if not message_container:
		push_error("Message container not found: " + message_id)
		return
	
	var vbox = message_container.get_child(0)  # Get VBox
	if not vbox:
		push_error("VBox not found in message container")
		return
		
	var content_edit = vbox.get_node("MessageText")  # Get TextEdit by name
	if not content_edit is TextEdit:
		push_error("MessageText not found or not TextEdit")
		return
		
	content_edit.editable = not content_edit.editable
	content_edit.custom_minimum_size.y = 100 if content_edit.editable else 50
	
	var button_container = vbox.get_node("MessageButtonsContainer")
	if button_container:
		var edit_button = button_container.get_node("EditButton")
		var resend_button = button_container.get_node("ResendButton")
		if edit_button and resend_button:
			if content_edit.editable:
				# Starting edit mode
				edit_button.text = "Done"
				resend_button.visible = true
			else:
				# Ending edit mode
				edit_button.text = "Edit"
				resend_button.visible = false
				message_container.set_meta("raw_content", content_edit.text)
				message_edited.emit(message_id, content_edit.text)

func _on_resend_pressed(message_id: String) -> void:
	var message_container = messages_container.get_node(message_id)
	if not message_container:
		return
		
	var vbox = message_container.get_child(0)
	if not vbox:
		return
		
	# Reset edit state
	var content_edit = vbox.get_node("MessageText")
	if content_edit is TextEdit:
		content_edit.editable = false
		content_edit.custom_minimum_size.y = 50
		
	var button_container = vbox.get_node("MessageButtonsContainer")
	if button_container:
		var edit_button = button_container.get_node("EditButton")
		var resend_button = button_container.get_node("ResendButton")
		if edit_button and resend_button:
			edit_button.text = "Edit"
			resend_button.visible = false
	
	message_resend_requested.emit(message_id)

func _on_delete_pressed(message_id: String) -> void:
	message_deleted.emit(message_id)

func scroll_to_top() -> void:
	if scroll_container:
		scroll_container.scroll_vertical = 0

func scroll_to_bottom() -> void:
	if scroll_container:
		scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value

func add_message(content: String, role: String) -> void:
	# --- Check flag and hide label directly --- 
	if _is_empty:
		_is_empty = false # Clear flag
		if is_instance_valid(message_container_label):
			message_container_label.visible = false
	# --- End Check --- 
		
	var message = create_message(content, role)
	if message:
		if String(role).strip_edges() == "assistant":
			assistant_message_added.emit(String(content))
		# Wait for the message to be added to the tree and sized
		await get_tree().process_frame
		# Scroll to the new message
		scroll_to_bottom()

func begin_streamed_assistant_message() -> String:
	if _is_empty:
		_is_empty = false
		if is_instance_valid(message_container_label):
			message_container_label.visible = false
	var message_node: Control = create_message("", "assistant")
	if not is_instance_valid(message_node):
		return ""
	var body_node: VBoxContainer = message_node.find_child(
		"MessageText",
		true,
		false
	) as VBoxContainer
	if body_node:
		var text_node: RichTextLabel = _create_text_label("")
		text_node.name = "StreamingText"
		body_node.add_child(text_node)
		body_node.move_child(text_node, 0)
	call_deferred("scroll_to_bottom")
	return String(message_node.name)

func append_streamed_assistant_delta(
	message_id: String,
	content_delta: String
) -> void:
	var message_node: Control = messages_container.get_node_or_null(
		message_id
	) as Control
	if not message_node:
		return
	var accumulated: String = String(
		message_node.get_meta("raw_content", "")
	) + content_delta
	message_node.set_meta("raw_content", accumulated)
	var text_node: RichTextLabel = message_node.find_child(
		"StreamingText",
		true,
		false
	) as RichTextLabel
	if text_node:
		text_node.text = accumulated
	scroll_to_bottom()

func finish_streamed_assistant_message(
	message_id: String,
	final_content: String
) -> void:
	var message_node: Control = messages_container.get_node_or_null(
		message_id
	) as Control
	if message_node:
		message_node.set_meta("raw_content", final_content)
		var text_node: RichTextLabel = message_node.find_child(
			"StreamingText",
			true,
			false
		) as RichTextLabel
		if text_node:
			text_node.text = final_content
	assistant_message_added.emit(final_content)

func remove_last_message() -> void:
	if not messages_container or messages_container.get_child_count() == 0:
		return
		
	var last_message = messages_container.get_child(messages_container.get_child_count() - 1)
	last_message.queue_free()
	message_counter = max(0, message_counter - 1) 

func get_messages() -> Array:
	var messages = []
	if not messages_container:
		return messages
		
	for child in messages_container.get_children():
		if child is PanelContainer:
			var role_v: Variant = (child as PanelContainer).get_meta("role") if (child as PanelContainer).has_meta("role") else ""
			var raw_v: Variant = (child as PanelContainer).get_meta("raw_content") if (child as PanelContainer).has_meta("raw_content") else ""
			var role_meta := str(role_v).strip_edges()
			var content_meta := str(raw_v).strip_edges()
			if not role_meta.is_empty() and not content_meta.is_empty():
				messages.append({"role": role_meta, "content": content_meta})
				continue
			
			var vbox = child.get_child(0)  # First child is VBoxContainer
			
			# Find role label and message text in VBox children
			var role_label = vbox.find_child("RoleLabel", true, false)
			var message_text = vbox.find_child("MessageText", true, false)
			
			if role_label and message_text:
				var parsed_role := ""
				if role_label is Label:
					parsed_role = String((role_label as Label).text).strip_edges()
				
				# Get content based on node type
				var parsed_content := ""
				if message_text is TextEdit:
					parsed_content = message_text.text
				elif message_text is RichTextLabel:
					parsed_content = message_text.get_parsed_text()
				
				if not parsed_role.is_empty() and not parsed_content.is_empty():
					messages.append({
						"role": parsed_role,
						"content": parsed_content.strip_edges()
					})
				else:
					print("Skipping message - Empty role or content")
	
	return messages 

func show_edit_history() -> void:
	# Get all messages from the container
	var messages = get_messages()
	
	# Format messages into editable text
	var formatted_text = ""
	for message in messages:
		formatted_text += "[" + message.role + "]\n"
		formatted_text += message.content + "\n\n"
	
	# Emit signal for parent to show popup
	show_edit_history_requested.emit(formatted_text)

func update_from_edited_text(text: String) -> void:
	# Parse the edited text back into messages
	var lines = text.split("\n")
	var messages = []
	var current_role = ""
	var current_content = ""
	
	for line in lines:
		line = line.strip_edges()
		if line.is_empty():
			if not current_role.is_empty() and not current_content.is_empty():
				messages.append({
					"role": current_role,
					"content": current_content.strip_edges()
				})
				current_content = ""
			continue
			
		if line.begins_with("[") and line.ends_with("]"):
			# Save previous message if any
			if not current_role.is_empty() and not current_content.is_empty():
				messages.append({
					"role": current_role,
					"content": current_content.strip_edges()
				})
			# Start new message
			current_role = line.substr(1, line.length() - 2)  # Remove [ and ]
			current_content = ""
		else:
			current_content += line + "\n"
	
	# Add final message if any
	if not current_role.is_empty() and not current_content.is_empty():
		messages.append({
			"role": current_role,
			"content": current_content.strip_edges()
		})
	
	# Update message container
	clear_messages()
	for message in messages:
		add_message(message.content, message.role)
	
	# Emit signal for conversation manager to save
	edit_history_saved.emit(messages) 
