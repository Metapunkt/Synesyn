## Purpose: NotificationPopup (script)
@tool
extends PanelContainer
class_name NotificationPopup

const MARGIN: int = 10
const AUTO_DISMISS_DELAY: float = 3.0

var type: int
var message: String
var title: String

@onready var title_label: Label = $VBox/TitleLabel
@onready var message_label: Label = $VBox/MessageLabel
@onready var close_button: Button = $VBox/CloseButton
@onready var auto_dismiss_timer: Timer = $AutoDismissTimer

signal dismissed()

func _ready() -> void:
	print("NotificationPopup: Initializing...")
	close_button.pressed.connect(_on_close_pressed)
	auto_dismiss_timer.timeout.connect(_on_auto_dismiss_timeout)
	print("NotificationPopup: Initialization complete")

func setup(p_message: String, p_type: int, p_title: String = "") -> void:
	print("NotificationPopup: Setting up with message: ", p_message)
	message = p_message
	type = p_type
	title = p_title if not p_title.is_empty() else _get_default_title(type)
	
	title_label.text = title
	message_label.text = message
	
	_apply_theme()
	show()  # Ensure popup is visible
	print("NotificationPopup: Setup complete")

func start_auto_dismiss() -> void:
	auto_dismiss_timer.start(AUTO_DISMISS_DELAY)

func _apply_theme() -> void:
	print("NotificationPopup: Applying theme")
	var style = StyleBoxFlat.new()
	style.bg_color = _get_type_color()
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	add_theme_stylebox_override("panel", style)
	print("NotificationPopup: Theme applied")

func _get_type_color() -> Color:
	match type:
		NotificationManager.NotificationType.ERROR:
			return Color(0.8, 0.2, 0.2, 0.9)
		NotificationManager.NotificationType.WARNING:
			return Color(0.8, 0.8, 0.2, 0.9)
		NotificationManager.NotificationType.SUCCESS:
			return Color(0.2, 0.8, 0.2, 0.9)
		_:  # INFO
			return Color(0.2, 0.2, 0.8, 0.9)

func _get_default_title(type: int) -> String:
	match type:
		NotificationManager.NotificationType.ERROR:
			return "Error"
		NotificationManager.NotificationType.WARNING:
			return "Warning"
		NotificationManager.NotificationType.SUCCESS:
			return "Success"
		_:
			return "Information"

func _on_close_pressed() -> void:
	dismissed.emit()
	queue_free()

func _on_auto_dismiss_timeout() -> void:
	dismissed.emit()
	queue_free() 
