extends Node
## Configures the OS window when ReadyMade is entered via the Synesyn launcher.
## Disables canvas_items letterbox-scale so Mission Control lays out in real
## window pixels (toolbars can reflow), and sizes the window to a sensible
## fraction of the usable screen (HiDPI-aware via DisplayServer screen rect).

func _ready() -> void:
	call_deferred("_apply")


func _apply() -> void:
	var win: Window = get_window()
	if win == null:
		return
	# Real-pixel layout: project.godot uses canvas_items stretch which keeps
	# controls at the design size (~1152x648) and scales them — that letterboxes
	# or cramps toolbars when the OS window is larger. ReadyMade is a desktop UI.
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	win.content_scale_factor = 1.0

	if DisplayServer.get_name() == "headless" or OS.has_feature("headless"):
		return

	var screen_id: int = win.current_screen
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen_id)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return

	var target_w: int = clampi(int(float(usable.size.x) * 0.85), mini(1152, usable.size.x), usable.size.x)
	var target_h: int = clampi(int(float(usable.size.y) * 0.85), mini(648, usable.size.y), usable.size.y)
	# Avoid fighting an already-maximized window the user sized intentionally.
	if win.mode == Window.MODE_MAXIMIZED or win.mode == Window.MODE_FULLSCREEN:
		return
	win.size = Vector2i(target_w, target_h)
	var pos_x: int = usable.position.x + (usable.size.x - target_w) / 2
	var pos_y: int = usable.position.y + (usable.size.y - target_h) / 2
	win.position = Vector2i(pos_x, pos_y)
