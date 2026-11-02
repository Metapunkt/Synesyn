## Purpose: ToolbarControls (script)
@tool
extends HBoxContainer # Or Control if you prefer
class_name ToolbarControls

# Define signals for each button's action
signal chat_menu_toggled(button_pressed: bool)
signal main_menu_toggled(button_pressed: bool)
signal output_container_toggled(button_pressed: bool)
signal user_input_toggled(button_pressed: bool)
signal content_sources_toggled(button_pressed: bool)
signal dev_agent_toggled(button_pressed: bool)

# Node references (use % unique names)
@onready var chat_menu_toggle_button: CheckButton = %ToggleChatMenu
@onready var main_menu_toggle_button: CheckButton = %ToggleMainMenu
@onready var output_container_toggle_button: CheckButton = %ToggleOutputContainer
@onready var user_input_toggle_button: CheckButton = %ToggleUserInput
@onready var content_sources_toggle_button: CheckButton = %ToggleContentSources
@onready var dev_agent_toggle_button: CheckButton = %ToggleDevAgent
@onready var progress_bar: TextureProgressBar = %ProgressBar

# Flag to prevent signal loops when setting state programmatically
var _is_updating_internally := false
var _progress_tween: Tween = null
var _completion_tween: Tween = null

func _ready() -> void:
	# Connect internal button signals to handlers
	if not is_instance_valid(chat_menu_toggle_button):
		push_error("ToolbarControls: Missing %ToggleChatMenu node")
		return
	chat_menu_toggle_button.toggled.connect(_on_chat_menu_toggled)
	
	if not is_instance_valid(main_menu_toggle_button):
		push_error("ToolbarControls: Missing %ToggleMainMenu node")
		return
	main_menu_toggle_button.toggled.connect(_on_main_menu_toggled)
	
	if not is_instance_valid(output_container_toggle_button):
		push_error("ToolbarControls: Missing %ToggleOutputContainer node")
		return
	output_container_toggle_button.toggled.connect(_on_output_container_toggled)
	
	if not is_instance_valid(user_input_toggle_button):
		push_error("ToolbarControls: Missing %ToggleUserInput node")
		return
	user_input_toggle_button.toggled.connect(_on_user_input_toggled)
	
	if not is_instance_valid(content_sources_toggle_button):
		push_error("ToolbarControls: Missing %ToggleContentSources node")
		return
	content_sources_toggle_button.toggled.connect(_on_content_sources_toggled)

	if not is_instance_valid(dev_agent_toggle_button):
		push_error("ToolbarControls: Missing %ToggleDevAgent node")
		return
	dev_agent_toggle_button.toggled.connect(_on_dev_agent_toggled)

	# Ensure progress bar is initially hidden
	if is_instance_valid(progress_bar):
		progress_bar.visible = false
		progress_bar.value = 0
	else:
		push_error("ToolbarControls: Missing %ProgressBar node")

# --- Internal Signal Handlers --- 
func _on_chat_menu_toggled(button_pressed: bool) -> void:
	if not _is_updating_internally:
		emit_signal("chat_menu_toggled", button_pressed)

func _on_main_menu_toggled(button_pressed: bool) -> void:
	if not _is_updating_internally:
		emit_signal("main_menu_toggled", button_pressed)

func _on_output_container_toggled(button_pressed: bool) -> void:
	if not _is_updating_internally:
		emit_signal("output_container_toggled", button_pressed)

func _on_user_input_toggled(button_pressed: bool) -> void:
	if not _is_updating_internally:
		emit_signal("user_input_toggled", button_pressed)

func _on_content_sources_toggled(button_pressed: bool) -> void:
	if not _is_updating_internally:
		emit_signal("content_sources_toggled", button_pressed)

func _on_dev_agent_toggled(button_pressed: bool) -> void:
	if not _is_updating_internally:
		emit_signal("dev_agent_toggled", button_pressed)

# --- Public Methods to Control Progress Bar --- 

func show_bar() -> void:
	if is_instance_valid(progress_bar):
		progress_bar.value = 0.0
		progress_bar.modulate.a = 1.0 # Ensure fully opaque
		progress_bar.visible = true
	else:
		push_warning("ToolbarControls: ProgressBar node not valid in show_bar")

func hide_bar() -> void:
	if is_instance_valid(progress_bar):
		# Optionally fade out before hiding
		var fade_tween = create_tween()
		fade_tween.tween_property(progress_bar, "modulate:a", 0.0, 0.3)
		# Hide immediately after starting the fade
		progress_bar.visible = false 
		progress_bar.value = 0 # Reset value after hiding
	else:
		push_warning("ToolbarControls: ProgressBar node not valid in hide_bar")

func set_bar_value(value: float) -> void:
	if is_instance_valid(progress_bar):
		progress_bar.value = clampf(value, 0.0, 100.0)

func animate_progress_start() -> void:
	# Ensure progress_bar node is ready before proceeding
	if not is_instance_valid(progress_bar):
		push_warning("ToolbarControls: ProgressBar node instance is not valid when trying to start animation.")
		return
		
	# Explicitly wait if the node exists but isn't ready yet
	if not progress_bar.is_node_ready():
		await progress_bar.ready

	show_bar() # Restore call to show_bar()
	
	# Restore the progress tween logic
	if _progress_tween and _progress_tween.is_valid():
		_progress_tween.kill()
		
	_progress_tween = create_tween()
	_progress_tween.set_trans(Tween.TRANS_LINEAR) # Use linear for progress
	# SHORTENED ANIMATION: Animate quickly to 80%, then slower to 95%
	_progress_tween.tween_property(progress_bar, "value", 80.0, 1.5) # Faster initial jump
	_progress_tween.tween_property(progress_bar, "value", 95.0, 3.0) # Slower progress towards end
	_progress_tween.play()

func animate_progress_complete(success: bool) -> void:
	if not is_instance_valid(progress_bar):
		push_warning("ToolbarControls: ProgressBar node instance is not valid when trying to complete animation.")
		return

	# Kill the main progress tween if it's running
	if _progress_tween and _progress_tween.is_valid():
		_progress_tween.kill()
	
	# Kill any previous completion tween
	if _completion_tween and _completion_tween.is_valid():
		_completion_tween.kill()

	# Start the completion/hide animation
	_completion_tween = create_tween()
	_completion_tween.set_trans(Tween.TRANS_SINE) # Smoother transition for completion
	
	if success:
		# Animate quickly to 100% then fade out
		_completion_tween.tween_property(progress_bar, "value", 100.0, 0.2)
		_completion_tween.tween_callback(hide_bar).set_delay(0.1) # Start hide slightly after reaching 100
	else:
		# On failure, just hide immediately (or maybe a quick red flash? For now, just hide)
		_completion_tween.tween_callback(hide_bar)
	
	_completion_tween.play()

# --- Public Methods to Set State Externally --- 
# These methods prevent signals from being re-emitted when state is set programmatically

func set_chat_menu_state(is_visible: bool) -> void:
	if not is_instance_valid(chat_menu_toggle_button) or chat_menu_toggle_button.button_pressed == is_visible:
		return
	_is_updating_internally = true
	chat_menu_toggle_button.button_pressed = is_visible
	_is_updating_internally = false

func set_main_menu_state(is_visible: bool) -> void:
	if not is_instance_valid(main_menu_toggle_button) or main_menu_toggle_button.button_pressed == is_visible:
		return
	_is_updating_internally = true
	main_menu_toggle_button.button_pressed = is_visible
	_is_updating_internally = false

func set_output_container_state(is_visible: bool) -> void:
	if not is_instance_valid(output_container_toggle_button) or output_container_toggle_button.button_pressed == is_visible:
		return
	_is_updating_internally = true
	output_container_toggle_button.button_pressed = is_visible
	_is_updating_internally = false

func set_user_input_state(is_visible: bool) -> void:
	if not is_instance_valid(user_input_toggle_button) or user_input_toggle_button.button_pressed == is_visible:
		return
	_is_updating_internally = true
	user_input_toggle_button.button_pressed = is_visible
	_is_updating_internally = false

func set_content_sources_state(is_visible: bool) -> void:
	if not is_instance_valid(content_sources_toggle_button) or content_sources_toggle_button.button_pressed == is_visible:
		return
	_is_updating_internally = true
	content_sources_toggle_button.button_pressed = is_visible
	_is_updating_internally = false 

func set_dev_agent_state(enabled: bool) -> void:
	if not is_instance_valid(dev_agent_toggle_button) or dev_agent_toggle_button.button_pressed == enabled:
		return
	_is_updating_internally = true
	dev_agent_toggle_button.button_pressed = enabled
	_is_updating_internally = false
