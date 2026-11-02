## Purpose: NotificationManager (script)
@tool
extends Node
class_name NotificationManager

signal notification_shown(type: String, message: String)
signal notification_closed(type: String)

enum NotificationType {
	INFO,
	WARNING,
	ERROR,
	SUCCESS
}

var _notification_popup: PopupPanel = null
var _title_label: Label = null
var _message_label: Label = null
var _details_label: Label = null
var _close_button: Button = null
var _auto_dismiss_timer: Timer = null
var _body_scroll: ScrollContainer = null
var _body_vbox: VBoxContainer = null

# Notification sizing defaults (editor-safe). These are MINIMUMS; we still clamp to window MAX.
const NOTIF_MIN_W := 520
const NOTIF_MIN_H := 220

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup()

func _cleanup() -> void:
	if _auto_dismiss_timer:
		if _auto_dismiss_timer.is_inside_tree():
			_auto_dismiss_timer.get_parent().remove_child(_auto_dismiss_timer)
		_auto_dismiss_timer.queue_free()
		_auto_dismiss_timer = null
	
	if _close_button and _close_button.is_connected("pressed", _on_close_button_pressed):
		_close_button.pressed.disconnect(_on_close_button_pressed)
	
	_notification_popup = null
	_title_label = null
	_message_label = null
	_details_label = null
	_close_button = null
	_body_scroll = null
	_body_vbox = null

func setup(popup: PopupPanel) -> bool:
	print("NotificationManager: Setting up with popup reference")
	print("DEBUG: Popup parameter: ", popup)
	print("DEBUG: Popup is inside tree: ", popup.is_inside_tree() if popup else "N/A")
	
	# Clean up any existing setup
	_cleanup()
	
	if not popup:
		push_error("NotificationManager: Received null popup reference!")
		return false
		
	_notification_popup = popup
	
	print("DEBUG: Popup reference set, getting UI elements...")
	print("DEBUG: Looking for labels in: ", _notification_popup.get_path())
	
	_title_label = _notification_popup.get_node_or_null("%Notification_Title_Label")
	print("DEBUG: Title label found: ", _title_label != null)
	
	_message_label = _notification_popup.get_node_or_null("%Notification_Msg_Label")
	print("DEBUG: Message label found: ", _message_label != null)
	
	_details_label = _notification_popup.get_node_or_null("%Error_Details_Label")
	print("DEBUG: Details label found: ", _details_label != null)
	
	_close_button = _notification_popup.get_node_or_null("%Close_Notification_Btn")
	print("DEBUG: Close button found: ", _close_button != null)

	# Robust fallback: if unique-name lookup fails (can happen if the popup's node tree was modified at runtime),
	# fall back to a name-based recursive search.
	if not _message_label:
		_message_label = _notification_popup.find_child("Notification_Msg_Label", true, false) as Label
		print("DEBUG: Message label found via find_child: ", _message_label != null)
	if not _details_label:
		_details_label = _notification_popup.find_child("Error_Details_Label", true, false) as Label
		print("DEBUG: Details label found via find_child: ", _details_label != null)
	if not _title_label:
		_title_label = _notification_popup.find_child("Notification_Title_Label", true, false) as Label
		print("DEBUG: Title label found via find_child: ", _title_label != null)
	if not _close_button:
		_close_button = _notification_popup.find_child("Close_Notification_Btn", true, false) as Button
		print("DEBUG: Close button found via find_child: ", _close_button != null)
	
	if not _title_label or not _message_label or not _details_label or not _close_button:
		push_error("NotificationManager: Failed to find all required UI elements!")
		_cleanup()
		return false

	_ensure_scroll_body()
	
	print("DEBUG: Popup initial state - visible: ", _notification_popup.visible)
	print("DEBUG: Popup size: ", _notification_popup.size)
	print("DEBUG: Popup position: ", _notification_popup.position)
	
	if _close_button:
		if _close_button.is_connected("pressed", _on_close_button_pressed):
			_close_button.pressed.disconnect(_on_close_button_pressed)
		_close_button.pressed.connect(_on_close_button_pressed)
		
	_auto_dismiss_timer = Timer.new()
	_auto_dismiss_timer.name = "AutoDismissTimer"
	_auto_dismiss_timer.one_shot = true
	if not _notification_popup.has_node("AutoDismissTimer"):
		_notification_popup.add_child(_auto_dismiss_timer)
	if _auto_dismiss_timer.is_connected("timeout", _on_auto_dismiss_timeout):
		_auto_dismiss_timer.timeout.disconnect(_on_auto_dismiss_timeout)
	_auto_dismiss_timer.timeout.connect(_on_auto_dismiss_timeout)
	
	print("NotificationManager: Setup complete with UI references")
	return true

func _ensure_scroll_body() -> void:
	# Install a scrollable body region so long notifications do not force the popup to grow beyond the viewport.
	# This is done once on setup to avoid per-notification overhead.
	if not _notification_popup or not _message_label or not _details_label:
		return
	# If already installed, reuse.
	var existing_scroll := _notification_popup.get_node_or_null("NotificationBodyScroll")
	if is_instance_valid(existing_scroll) and existing_scroll is ScrollContainer:
		_body_scroll = existing_scroll
		var existing_vbox := _body_scroll.get_node_or_null("NotificationBodyVBox")
		if is_instance_valid(existing_vbox) and existing_vbox is VBoxContainer:
			_body_vbox = existing_vbox
	if is_instance_valid(_body_scroll) and is_instance_valid(_body_vbox):
		# Ensure labels are inside the body vbox (in case of partial prior setup).
		if _message_label and _message_label.get_parent() != _body_vbox:
			if is_instance_valid(_message_label.get_parent()):
				_message_label.get_parent().remove_child(_message_label)
			_body_vbox.add_child(_message_label)
		if _details_label and _details_label.get_parent() != _body_vbox:
			if is_instance_valid(_details_label.get_parent()):
				_details_label.get_parent().remove_child(_details_label)
			_body_vbox.add_child(_details_label)
		return

	# The authored NotificationPopup has a VBoxContainer as its direct child.
	var root_vbox: VBoxContainer = _notification_popup.get_node_or_null("VBoxContainer")
	if not is_instance_valid(root_vbox):
		return

	_body_scroll = ScrollContainer.new()
	_body_scroll.name = "NotificationBodyScroll"
	_body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Give the body a reasonable minimum so short popups still show some content without scrolling.
	_body_scroll.custom_minimum_size = Vector2(0, 120)

	_body_vbox = VBoxContainer.new()
	_body_vbox.name = "NotificationBodyVBox"
	_body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Insert the scroll container after the title label (index 1 in the authored layout).
	# Current authored order: Title, Message, Details, CloseButton.
	root_vbox.add_child(_body_scroll)
	root_vbox.move_child(_body_scroll, 1)
	_body_scroll.add_child(_body_vbox)

	# Preserve ownership so unique-name lookups continue to work across multiple setup() calls.
	var scene_owner := _notification_popup.owner
	if scene_owner:
		_body_scroll.owner = scene_owner
		_body_vbox.owner = scene_owner

	# Move message + details into the scroll body.
	var msg_parent := _message_label.get_parent()
	if is_instance_valid(msg_parent):
		msg_parent.remove_child(_message_label)
	_body_vbox.add_child(_message_label)

	var det_parent := _details_label.get_parent()
	if is_instance_valid(det_parent):
		det_parent.remove_child(_details_label)
	_body_vbox.add_child(_details_label)

func show_notification(message: String, type: NotificationType = NotificationType.INFO, title: String = "", details: String = "") -> void:
	print("DEBUG: show_notification called with:")
	print("- message: ", message)
	print("- type: ", type)
	print("- title: ", title)
	print("- details: ", details)
	
	if not _notification_popup or not _title_label or not _message_label or not _details_label:
		push_error("NotificationManager: Cannot show notification - UI elements not initialized!")
		return
	
	# Update content
	_title_label.text = title if not title.is_empty() else _get_type_title(type)
	_message_label.text = message
	
	# Update details
	_details_label.visible = not details.is_empty()
	_details_label.text = details if not details.is_empty() else ""
	
	# Wrap aggressively: long IDs/JSON are often a single "word" and won't wrap with word-smart modes.
	# AUTOWRAP_ARBITRARY breaks anywhere to prevent horizontal stretching.
	_message_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	print("DEBUG: Notification content set:")
	print("- title: ", _title_label.text)
	print("- message: ", _message_label.text)
	print("- details: ", _details_label.text)
	print("- details visible: ", _details_label.visible)
	
	# Show popup.
	# IMPORTANT: In editor @tool context, an exclusive popup can make the editor feel "hung"
	# (nothing selectable) until the popup closes. Force non-exclusive behavior.
	_notification_popup.exclusive = false

	# Clamp popup size to the editor window so it can never extend beyond screen bounds.
	# NOTE: In the editor, get_viewport_rect() may not reflect the actual OS window size.
	var win_size_i: Vector2i = DisplayServer.window_get_size()
	var win_size := Vector2(float(win_size_i.x), float(win_size_i.y))
	if win_size.x <= 1.0 or win_size.y <= 1.0:
		win_size = _notification_popup.get_viewport_rect().size
	var max_w := int(min(720.0, max(float(NOTIF_MIN_W), win_size.x - 80.0)))
	var max_h := int(min(520.0, max(float(NOTIF_MIN_H), win_size.y - 120.0)))
	var sz: Vector2i = _notification_popup.size
	# Enforce minimum size (but never exceed max).
	sz.x = clamp(sz.x, NOTIF_MIN_W, max_w)
	sz.y = clamp(sz.y, NOTIF_MIN_H, max_h)
	if sz.x > max_w:
		sz.x = max_w
	if sz.y > max_h:
		sz.y = max_h
	_notification_popup.size = sz

	# Center within the OS window (more reliable than popup_centered() inside editor docks).
	var win_pos: Vector2i = DisplayServer.window_get_position()
	var x := win_pos.x + int((win_size.x - float(sz.x)) * 0.5)
	var y := win_pos.y + int((win_size.y - float(sz.y)) * 0.5)
	_notification_popup.position = Vector2i(x, y)
	_notification_popup.popup()
	_notification_popup.grab_focus()
	
	# Auto-dismiss non-error notifications
	if type != NotificationType.ERROR and _auto_dismiss_timer:
		_auto_dismiss_timer.start(3.0)  # 3 second auto-dismiss
	
	notification_shown.emit(str(type), message)

func _get_type_title(type: NotificationType) -> String:
	match type:
		NotificationType.INFO:
			return "Information"
		NotificationType.WARNING:
			return "Warning"
		NotificationType.ERROR:
			return "Error"
		NotificationType.SUCCESS:
			return "Success"
		_:
			return "Notification"

func _on_close_button_pressed() -> void:
	if _notification_popup:
		_notification_popup.hide()
		notification_closed.emit("closed")

func _on_auto_dismiss_timeout() -> void:
	if _notification_popup:
		_notification_popup.hide()
		notification_closed.emit("auto_dismissed")

# Convenience methods
func info(message: String, title: String = "", details: String = "") -> void:
	show_notification(message, NotificationType.INFO, title, details)

func warning(message: String, title: String = "", details: String = "") -> void:
	show_notification(message, NotificationType.WARNING, title, details)

func error(message: String, title: String = "Error", details: String = "") -> void:
	print("NotificationManager: Showing error notification")
	show_notification(message, NotificationType.ERROR, title, details)

func success(message: String, title: String = "", details: String = "") -> void:
	show_notification(message, NotificationType.SUCCESS, title, details)
