extends Node

## Dual Window Manager for ScenSyn
## Manages simultaneous Story Log and story_stage windows

signal window_mode_changed(new_mode: WindowMode)

enum WindowMode {
	SINGLE_STORY_LOG,      # Only Story Log window
	SINGLE_STORY_STAGE,    # Only story_stage window  
	DUAL_WINDOWS          # Both windows simultaneously
}

var current_mode: WindowMode = WindowMode.SINGLE_STORY_LOG
var story_log_window: Window = null
var story_stage_window: Window = null

# Window positioning
const WINDOW_OFFSET = Vector2i(50, 50)
const DEFAULT_WINDOW_SIZE = Vector2i(1200, 800)
const MIN_WINDOW_SIZE = Vector2i(800, 600)

## Initialize the dual window system
func _ready():
	print("DualWindowManager: Initializing...")
	# Connect to window close events
	if story_log_window:
		story_log_window.close_requested.connect(_on_story_log_window_close_requested)
	if story_stage_window:
		story_stage_window.close_requested.connect(_on_story_stage_window_close_requested)

func _is_window_valid(window: Window) -> bool:
	return window != null and is_instance_valid(window)

func focus_story_log_window() -> bool:
	# In dual window mode, Story Log might be the main window (no separate Window node)
	var current_scene := get_tree().current_scene
	if current_scene and current_scene.name == "GameSession":
		var main_window := get_window()
		if main_window:
			main_window.grab_focus()
			return true
	if _is_window_valid(story_log_window):
		story_log_window.show()
		story_log_window.grab_focus()
		return true
	return false

func focus_story_stage_window() -> bool:
	# In dual window mode, story_stage might be the main window (no separate Window node)
	var current_scene := get_tree().current_scene
	if current_scene and current_scene.name == "StoryStage":
		var main_window := get_window()
		if main_window:
			main_window.grab_focus()
			return true
	if _is_window_valid(story_stage_window):
		story_stage_window.show()
		story_stage_window.grab_focus()
		return true
	return false

## Toggle dual window mode on/off
func toggle_dual_window_mode():
	if current_mode == WindowMode.DUAL_WINDOWS:
		disable_dual_window_mode()
	else:
		enable_dual_window_mode()

## Enable dual window mode (both windows visible)
func enable_dual_window_mode():
	print("DualWindowManager: Enabling dual window mode...")
	
	var main_window = get_window()
	if not main_window:
		push_error("DualWindowManager: Could not get main window")
		return
	
	# CRITICAL FIX: Set main window to NOT embed subwindows (makes them truly independent)
	main_window.gui_embed_subwindows = false
	print("DualWindowManager: Set main window gui_embed_subwindows = false for independent windows")
	
	# Determine what's currently in the main window
	var current_scene = get_tree().current_scene
	var scene_name: String = current_scene.name if current_scene else ""
	var is_story_log = scene_name == "GameSession"
	var is_story_stage = scene_name == "StoryStage"
	var story_log_ready = _is_window_valid(story_log_window)
	var story_stage_ready = _is_window_valid(story_stage_window)
	var secondary_ready = (is_story_log and story_stage_ready) or (is_story_stage and story_log_ready)
	
	if current_mode == WindowMode.DUAL_WINDOWS and secondary_ready:
		print("DualWindowManager: Already in dual window mode")
		return
	
	if not secondary_ready:
		if is_story_log:
			_create_story_stage_window()
			story_stage_ready = _is_window_valid(story_stage_window)
			secondary_ready = story_stage_ready
		elif is_story_stage:
			_create_story_log_window()
			story_log_ready = _is_window_valid(story_log_window)
			secondary_ready = story_log_ready
		else:
			print("DualWindowManager: Unknown scene type - cannot create secondary window (", scene_name, ")")
	
	if not secondary_ready:
		push_error("DualWindowManager: Failed to create secondary window")
		return
	
	current_mode = WindowMode.DUAL_WINDOWS
	window_mode_changed.emit(current_mode)
	print("DualWindowManager: Dual window mode enabled")

## Disable dual window mode (close secondary window)
func disable_dual_window_mode():
	print("DualWindowManager: Disabling dual window mode...")
	
	# Restore main window embedding behavior
	var main_window = get_window()
	if main_window:
		main_window.gui_embed_subwindows = true
		print("DualWindowManager: Restored main window gui_embed_subwindows = true")
	
	# Close secondary windows
	if _is_window_valid(story_log_window) and story_log_window != get_window():
		story_log_window.queue_free()
	story_log_window = null
	
	if _is_window_valid(story_stage_window) and story_stage_window != get_window():
		story_stage_window.queue_free()
	story_stage_window = null
	
	# Determine new single window mode based on current main window
	var current_scene = get_tree().current_scene
	if current_scene.name == "GameSession":
		current_mode = WindowMode.SINGLE_STORY_LOG
	elif current_scene.name == "StoryStage":
		current_mode = WindowMode.SINGLE_STORY_STAGE
	else:
		current_mode = WindowMode.SINGLE_STORY_LOG
	
	window_mode_changed.emit(current_mode)
	print("DualWindowManager: Dual window mode disabled")

## Create a new Story Log window
func _create_story_log_window():
	print("DualWindowManager: Creating Story Log window...")
	
	# ALTERNATIVE APPROACH: Use scene switching instead of dual windows
	# This might be more reliable than trying to create independent windows
	print("DualWindowManager: Creating new OS window for Story Log...")
	
	# Create new window with explicit OS window creation
	story_log_window = Window.new()
	story_log_window.title = "ScenSyn - Story Log"
	story_log_window.size = DEFAULT_WINDOW_SIZE
	story_log_window.min_size = MIN_WINDOW_SIZE
	
	# Try to make it as independent as possible
	story_log_window.mode = Window.MODE_WINDOWED
	story_log_window.unresizable = false
	story_log_window.transient = false
	story_log_window.wrap_controls = true
	story_log_window.always_on_top = false
	
	# Load Story Log scene FIRST
	var story_log_scene = load("res://ScenSyn/scenes/game_session.tscn")
	if not story_log_scene:
		push_error("DualWindowManager: Could not load Story Log scene")
		story_log_window.queue_free()
		story_log_window = null
		return
	
	var story_log_instance = story_log_scene.instantiate()
	story_log_window.add_child(story_log_instance)
	
	# CRITICAL: Add to scene tree root
	get_tree().root.add_child(story_log_window)
	
	# Position after adding to tree
	var main_window_pos = get_window().position
	story_log_window.position = main_window_pos + WINDOW_OFFSET
	
	# Show and bring to front
	story_log_window.show()
	story_log_window.grab_focus()
	
	# Connect close event
	story_log_window.close_requested.connect(_on_story_log_window_close_requested)
	
	print("DualWindowManager: Story Log window created at position: ", story_log_window.position)
	print("DualWindowManager: Main window position: ", main_window_pos)
	print("DualWindowManager: Story Log window should be movable anywhere on screen")

## Create a new story_stage window
func _create_story_stage_window():
	print("DualWindowManager: Creating story_stage window...")
	print("DualWindowManager: Creating new OS window for story_stage...")
	
	# Create new window with explicit OS window creation
	story_stage_window = Window.new()
	story_stage_window.title = "ScenSyn - Visual Stage"
	story_stage_window.size = DEFAULT_WINDOW_SIZE
	story_stage_window.min_size = MIN_WINDOW_SIZE
	
	# Try to make it as independent as possible
	story_stage_window.mode = Window.MODE_WINDOWED
	story_stage_window.unresizable = false
	story_stage_window.transient = false
	story_stage_window.wrap_controls = true
	story_stage_window.always_on_top = false
	
	# Load story_stage scene FIRST
	var story_stage_scene = load("res://ScenSyn/scenes/scensyn_story_stage.tscn")
	if not story_stage_scene:
		push_error("DualWindowManager: Could not load story_stage scene")
		story_stage_window.queue_free()
		story_stage_window = null
		return
	
	var story_stage_instance = story_stage_scene.instantiate()
	story_stage_window.add_child(story_stage_instance)
	
	# CRITICAL: Add to scene tree root
	get_tree().root.add_child(story_stage_window)
	
	# Position after adding to tree
	var main_window_pos = get_window().position
	story_stage_window.position = main_window_pos + WINDOW_OFFSET
	
	# Show and bring to front
	story_stage_window.show()
	story_stage_window.grab_focus()
	
	# Connect close event
	story_stage_window.close_requested.connect(_on_story_stage_window_close_requested)
	
	print("DualWindowManager: story_stage window created at position: ", story_stage_window.position)
	print("DualWindowManager: Main window position: ", main_window_pos)
	print("DualWindowManager: story_stage window should be movable anywhere on screen")

## Switch to single Story Log mode
func switch_to_single_story_log():
	if current_mode == WindowMode.SINGLE_STORY_LOG:
		return # Already in Story Log mode
	
	print("DualWindowManager: Switching to single Story Log mode...")
	
	# Close story_stage window if it exists
	if story_stage_window:
		story_stage_window.queue_free()
		story_stage_window = null
	
	# Switch main window to Story Log if needed
	var current_scene = get_tree().current_scene
	if current_scene.name != "GameSession":
		get_tree().change_scene_to_file("res://ScenSyn/scenes/game_session.tscn")
	
	current_mode = WindowMode.SINGLE_STORY_LOG
	window_mode_changed.emit(current_mode)

## Switch to single story_stage mode
func switch_to_single_story_stage():
	if current_mode == WindowMode.SINGLE_STORY_STAGE:
		return # Already in story_stage mode
	
	print("DualWindowManager: Switching to single story_stage mode...")
	
	# Close Story Log window if it exists
	if story_log_window:
		story_log_window.queue_free()
		story_log_window = null
	
	# Switch main window to story_stage if needed
	var current_scene = get_tree().current_scene
	if current_scene.name != "StoryStage":
		get_tree().change_scene_to_file("res://ScenSyn/scenes/scensyn_story_stage.tscn")
	
	current_mode = WindowMode.SINGLE_STORY_STAGE
	window_mode_changed.emit(current_mode)

## Get current window mode
func get_current_mode() -> WindowMode:
	return current_mode

## Check if dual window mode is active
func is_dual_window_mode() -> bool:
	return current_mode == WindowMode.DUAL_WINDOWS

## Handle Story Log window close request
func _on_story_log_window_close_requested():
	print("DualWindowManager: Story Log window close requested")
	if current_mode == WindowMode.DUAL_WINDOWS:
		disable_dual_window_mode()

## Handle story_stage window close request
func _on_story_stage_window_close_requested():
	print("DualWindowManager: story_stage window close requested")
	if current_mode == WindowMode.DUAL_WINDOWS:
		disable_dual_window_mode()

## Get window reference for a specific mode
func get_window_for_mode(mode: WindowMode) -> Window:
	match mode:
		WindowMode.SINGLE_STORY_LOG, WindowMode.DUAL_WINDOWS:
			return story_log_window if _is_window_valid(story_log_window) else get_window()
		WindowMode.SINGLE_STORY_STAGE:
			return story_stage_window if _is_window_valid(story_stage_window) else get_window()
		_:
			return get_window()
