## Purpose: Panel controller for the Conversation domain (threads, send/resend, edit history UI)
@tool
extends Node
class_name ChatPanelController

var _conversation_manager: Object = null
var _view_state: ViewStateResource = null
var _message_container: Node = null
var _notification_manager: Object = null

var _message_input: TextEdit = null
var _send_button: Button = null
var _stop_request_button: Button = null
var _thread_dropdown: OptionButton = null
var _new_thread_button: Button = null
var _new_thread_name_input: LineEdit = null

var _edit_history_popup: PopupPanel = null
var _history_text_edit: TextEdit = null

var _top_toolbar: Node = null
var _bottom_toolbar: Node = null

var _show_error_cb: Callable = Callable() # expects (title:String, message:String)
var _emit_operation_failed_cb: Callable = Callable() # expects (op:String, error:String, details:String)

var _is_processing: bool = false
var _was_cancelled: bool = false
var _stream_message_id: String = ""

func setup(
		conversation_manager: Object,
		view_state: ViewStateResource,
		message_container: Node,
		notification_manager: Object,
		message_input: TextEdit,
		send_button: Button,
		stop_request_button: Button,
		thread_dropdown: OptionButton,
		new_thread_button: Button,
		new_thread_name_input: LineEdit,
		edit_history_popup: PopupPanel,
		history_text_edit: TextEdit,
		top_toolbar_controls: Node,
		bottom_toolbar_controls: Node,
		show_error_cb: Callable,
		emit_operation_failed_cb: Callable
	) -> void:
	_conversation_manager = conversation_manager
	_view_state = view_state
	_message_container = message_container
	_notification_manager = notification_manager

	_message_input = message_input
	_send_button = send_button
	_stop_request_button = stop_request_button
	if is_instance_valid(_stop_request_button):
		_stop_request_button.visible = false
	_thread_dropdown = thread_dropdown
	_new_thread_button = new_thread_button
	_new_thread_name_input = new_thread_name_input

	_edit_history_popup = edit_history_popup
	_history_text_edit = history_text_edit

	_top_toolbar = top_toolbar_controls
	_bottom_toolbar = bottom_toolbar_controls

	_show_error_cb = show_error_cb
	_emit_operation_failed_cb = emit_operation_failed_cb
	var api_service: Object = _get_api_service()
	if (
		is_instance_valid(api_service)
		and api_service.has_signal("stream_chunk_received")
	):
		var stream_signal := Signal(
			api_service,
			"stream_chunk_received"
		)
		if not stream_signal.is_connected(_on_stream_chunk_received):
			stream_signal.connect(_on_stream_chunk_received)

func update_thread_options() -> void:
	if not is_instance_valid(_thread_dropdown) or not is_instance_valid(_conversation_manager):
		return

	# Disk is the source of truth: refresh thread list from JSON on each update.
	if _conversation_manager.has_method("reload_threads_from_disk"):
		_conversation_manager.reload_threads_from_disk()

	var current_thread_id := _get_current_thread_id_safe()

	_thread_dropdown.clear()
	_thread_dropdown.add_item("Select Thread")
	_thread_dropdown.set_item_metadata(0, "")
	_thread_dropdown.add_item("default")
	_thread_dropdown.set_item_metadata(1, "default")

	var selected_index := 1 if current_thread_id == "default" else -1
	if _conversation_manager.has_method("get_thread_list"):
		var threads: Array = _conversation_manager.get_thread_list()
		for thread_id_any in threads:
			var thread_id := str(thread_id_any).strip_edges()
			if thread_id.is_empty() or thread_id == "default":
				continue
			_thread_dropdown.add_item(thread_id)
			var idx := _thread_dropdown.item_count - 1
			_thread_dropdown.set_item_metadata(idx, thread_id)
			if thread_id == current_thread_id:
				selected_index = idx

	if selected_index < 0:
		selected_index = 1
	_thread_dropdown.select(selected_index)

func load_thread(thread_name: String) -> void:
	if not is_instance_valid(_message_container) or not is_instance_valid(_conversation_manager):
		return
	var tid := String(thread_name).strip_edges()
	if tid.is_empty():
		tid = "default"

	if _message_container.has_method("clear_messages"):
		_message_container.clear_messages()
	if _conversation_manager.has_method("get_thread_messages"):
		var messages: Array = _conversation_manager.get_thread_messages(tid)
		for message in messages:
			if message is Dictionary and (message as Dictionary).has("role") and (message as Dictionary).has("content"):
				_message_container.add_message(message.content, message.role)

	if is_instance_valid(_view_state) and _view_state.has_method("set_current_thread_id"):
		_view_state.set_current_thread_id(tid)

func on_message_input_changed() -> void:
	if not is_instance_valid(_send_button) or not is_instance_valid(_message_input):
		return
	_send_button.disabled = (
		_is_processing
		or _message_input.text.strip_edges().is_empty()
	)

func on_send_message() -> void:
	if _is_processing:
		return
	if not is_instance_valid(_message_input):
		return
	var user_message_text := _message_input.text.strip_edges()
	if user_message_text.is_empty():
		_emit_failed("send_message", "Message cannot be empty", "")
		return

	_is_processing = true
	_was_cancelled = false
	_stream_message_id = ""
	_set_request_controls(true)
	_animate_progress_start()

	if is_instance_valid(_message_container) and _message_container.has_method("add_message"):
		_message_container.add_message(user_message_text, "user")
	_message_input.text = ""

	var current_thread_id := _get_current_thread_id_safe()
	if not is_instance_valid(_conversation_manager) or not _conversation_manager.has_method("chat"):
		_animate_progress_complete(false)
		_emit_failed("send_message", "Conversation manager not available", "")
		_is_processing = false
		_set_request_controls(false)
		return

	var response: Dictionary = await _conversation_manager.chat(user_message_text, current_thread_id)
	if bool(response.get("success", false)):
		_animate_progress_complete(true)
		if is_instance_valid(_message_container):
			var response_text: String = str(
				response.get("response", "")
			)
			if (
				not _stream_message_id.is_empty()
				and _message_container.has_method(
					"finish_streamed_assistant_message"
				)
			):
				_message_container.call(
					"finish_streamed_assistant_message",
					_stream_message_id,
					response_text
				)
			elif _message_container.has_method("add_message"):
				_message_container.add_message(
					response_text,
					"assistant"
				)
	else:
		_animate_progress_complete(false)
		if not _was_cancelled:
			_emit_failed(
				"send_message",
				str(response.get("error", "Unknown error")),
				str(response.get("details", ""))
			)

	_is_processing = false
	_set_request_controls(false)


func on_stop_request() -> void:
	if not _is_processing or not is_instance_valid(_conversation_manager):
		return
	_was_cancelled = true
	var api_service: Object = _get_api_service()
	if (
		is_instance_valid(api_service)
		and api_service.has_method("cancel_current_request")
	):
		api_service.call("cancel_current_request")
	if (
		not _stream_message_id.is_empty()
		and is_instance_valid(_message_container)
		and _message_container.has_method("remove_last_message")
	):
		_message_container.call("remove_last_message")
		_stream_message_id = ""
	if is_instance_valid(_stop_request_button):
		_stop_request_button.disabled = true


func _set_request_controls(is_processing_request: bool) -> void:
	if is_instance_valid(_stop_request_button):
		_stop_request_button.visible = is_processing_request
		_stop_request_button.disabled = false
	if is_instance_valid(_send_button):
		_send_button.disabled = (
			is_processing_request
			or not is_instance_valid(_message_input)
			or _message_input.text.strip_edges().is_empty()
		)


func _on_stream_chunk_received(
	_request_id: String,
	content_delta: String
) -> void:
	if not _is_processing or not is_instance_valid(_message_container):
		return
	if _stream_message_id.is_empty():
		if not _message_container.has_method(
			"begin_streamed_assistant_message"
		):
			return
		_stream_message_id = String(
			_message_container.call(
				"begin_streamed_assistant_message"
			)
		)
	if (
		not _stream_message_id.is_empty()
		and _message_container.has_method(
			"append_streamed_assistant_delta"
		)
	):
		_message_container.call(
			"append_streamed_assistant_delta",
			_stream_message_id,
			content_delta
		)


func _get_api_service() -> Object:
	if (
		is_instance_valid(_conversation_manager)
		and "api_service" in _conversation_manager
	):
		return _conversation_manager.get("api_service") as Object
	return null

func on_thread_selected(index: int) -> void:
	if not is_instance_valid(_thread_dropdown) or not is_instance_valid(_conversation_manager):
		return
	var meta: Variant = _thread_dropdown.get_item_metadata(index)
	var thread_name := str(meta).strip_edges() if meta != null else ""
	if thread_name.is_empty():
		thread_name = _thread_dropdown.get_item_text(index).strip_edges()
	if thread_name.is_empty() or thread_name.to_lower() == "select thread":
		return

	if _conversation_manager.has_method("set_current_thread"):
		var result: Dictionary = _conversation_manager.set_current_thread(thread_name)
		if bool(result.get("success", true)):
			if is_instance_valid(_view_state) and _view_state.has_method("set_current_thread_id"):
				_view_state.set_current_thread_id(thread_name)
			load_thread(thread_name)
		else:
			_emit_failed("select_thread", str(result.get("error", "Failed to select thread")), "")

func on_new_thread() -> void:
	if not is_instance_valid(_new_thread_name_input):
		return
	var thread_name := _new_thread_name_input.text.strip_edges()
	if thread_name.is_empty():
		if is_instance_valid(_new_thread_name_input):
			_new_thread_name_input.tooltip_text = "Please type a thread name here before clicking “Create New Thread”."
			_new_thread_name_input.grab_focus()
		if is_instance_valid(_new_thread_button):
			_new_thread_button.tooltip_text = "Enter a thread name in the field, then click to create the thread."
		if is_instance_valid(_notification_manager) and _notification_manager.has_method("warning"):
			_notification_manager.warning("Please enter a thread name in the input field before creating a new thread.", "Thread name required")
		else:
			_emit_failed("new_thread", "Thread name cannot be empty", "")
		return

	if not is_instance_valid(_conversation_manager) or not _conversation_manager.has_method("set_current_thread"):
		_emit_failed("new_thread", "ConversationManager not available", "")
		return

	# Explicit create: disk is the source of truth; don't rely on set_current_thread to create.
	if _conversation_manager.has_method("ensure_thread_saved"):
		var save_res: Dictionary = _conversation_manager.ensure_thread_saved(thread_name)
		if not bool(save_res.get("success", false)):
			_emit_failed("new_thread_save", str(save_res.get("error", "Failed to save thread")), str(save_res.get("details", "")))
			return
	if _conversation_manager.has_method("set_current_thread"):
		var result: Dictionary = _conversation_manager.set_current_thread(thread_name)
		if not bool(result.get("success", true)):
			_emit_failed("new_thread", str(result.get("error", "Failed to select thread after create")), "")
			return

	_new_thread_name_input.text = ""
	update_thread_options()
	load_thread(thread_name)

func on_edit_history_pressed() -> void:
	if is_instance_valid(_message_container) and _message_container.has_method("show_edit_history"):
		_message_container.show_edit_history()
	else:
		_emit_failed("edit_history", "Message container not available", "")

func on_show_edit_history(formatted_text: String) -> void:
	if not is_instance_valid(_edit_history_popup) or not is_instance_valid(_history_text_edit):
		_emit_failed("edit_history", "Edit history popup not found", "")
		return
	_history_text_edit.text = formatted_text
	_edit_history_popup.popup_centered()

func on_save_history_pressed() -> void:
	if not is_instance_valid(_message_container):
		_emit_failed("save_history", "Message container not available", "")
		return
	if is_instance_valid(_history_text_edit) and _message_container.has_method("update_from_edited_text"):
		_message_container.update_from_edited_text(_history_text_edit.text.strip_edges())
	if is_instance_valid(_edit_history_popup):
		_edit_history_popup.hide()

func on_cancel_edit_pressed() -> void:
	if is_instance_valid(_edit_history_popup):
		_edit_history_popup.hide()

func on_edit_history_saved(messages: Array) -> void:
	var current_thread_id := _get_current_thread_id_safe()
	if current_thread_id.is_empty():
		_emit_failed("save_history", "No current thread selected", "")
		return
	if not is_instance_valid(_conversation_manager):
		_emit_failed("save_history", "ConversationManager not available", "")
		return
	if not _conversation_manager.has_method("update_thread_messages"):
		_emit_failed("save_history", "ConversationManager missing update_thread_messages method", "")
		return
	var res: Dictionary = await _conversation_manager.update_thread_messages(current_thread_id, messages)
	if not bool(res.get("success", true)):
		if _show_error_cb.is_valid():
			_show_error_cb.call("Save Failed", "Failed to save edited history: " + str(res.get("error", "Unknown service error")))

func on_message_resend(message_id: String) -> void:
	if not is_instance_valid(_message_container) or not is_instance_valid(_conversation_manager):
		_emit_failed("resend_message", "Message container or conversation manager not available", "")
		return

	if not (_message_container.has("messages_container") and _message_container.messages_container):
		_emit_failed("resend_message", "Message container not ready", "")
		return

	var message_node = _message_container.messages_container.get_node(message_id)
	if not message_node:
		_emit_failed("resend_message", "Message not found", "")
		return

	var content_edit = message_node.get_child(0).get_child(1)
	if not (content_edit is TextEdit):
		_emit_failed("resend_message", "Invalid message content", "")
		return

	var msg := (content_edit as TextEdit).text.strip_edges()
	if msg.is_empty():
		_emit_failed("resend_message", "Message cannot be empty", "")
		return

	# Reset edit state
	(content_edit as TextEdit).editable = false
	(content_edit as TextEdit).custom_minimum_size.y = 50
	var button_container = message_node.get_node_or_null("MessageButtonsContainer")
	if button_container:
		var edit_button = button_container.get_node_or_null("EditButton")
		var resend_button = button_container.get_node_or_null("ResendButton")
		if edit_button and resend_button:
			edit_button.text = "Edit"
			resend_button.visible = false

	_is_processing = true
	_animate_progress_start()
	_message_container.add_message(msg, "user")

	var current_thread_id := _get_current_thread_id_safe()
	var response: Dictionary = await _conversation_manager.chat(msg, current_thread_id)
	if bool(response.get("success", false)):
		_animate_progress_complete(true)
		_message_container.add_message(str(response.get("response", "")), "assistant")
	else:
		_animate_progress_complete(false)
		_emit_failed("resend_message", str(response.get("error", "Unknown error")), "")

	_is_processing = false

func on_message_deleted(message_id: String) -> void:
	if not is_instance_valid(_message_container):
		_emit_failed("delete_message", "Message container not available", "")
		return
	if not (_message_container.has("messages_container") and _message_container.messages_container):
		return
	var message_node = _message_container.messages_container.get_node(message_id)
	if message_node:
		message_node.queue_free()

func _get_current_thread_id_safe() -> String:
	var tid := ""
	if is_instance_valid(_view_state) and _view_state.has_method("get_current_thread_id"):
		tid = str(_view_state.get_current_thread_id()).strip_edges()
	# Fallback: if ViewState is unavailable/unsynced, trust ConversationManager's current thread.
	if tid.is_empty() and is_instance_valid(_conversation_manager) and _conversation_manager.has_method("get_current_thread"):
		tid = str(_conversation_manager.get_current_thread()).strip_edges()
	if tid.is_empty():
		tid = "default"
	return tid

func _emit_failed(operation: String, error: String, details: String) -> void:
	if _emit_operation_failed_cb.is_valid():
		_emit_operation_failed_cb.call(operation, error, details)

func _animate_progress_start() -> void:
	if is_instance_valid(_top_toolbar) and _top_toolbar.has_method("animate_progress_start"):
		_top_toolbar.animate_progress_start()
	if is_instance_valid(_bottom_toolbar) and _bottom_toolbar.has_method("animate_progress_start"):
		_bottom_toolbar.animate_progress_start()

func _animate_progress_complete(success: bool) -> void:
	if is_instance_valid(_top_toolbar) and _top_toolbar.has_method("animate_progress_complete"):
		_top_toolbar.animate_progress_complete(success)
	if is_instance_valid(_bottom_toolbar) and _bottom_toolbar.has_method("animate_progress_complete"):
		_bottom_toolbar.animate_progress_complete(success)


