class_name StoryStageBackgroundController
extends Node

## Backdrop, scenario frame cycle, and the slideshow queue.

var host: StoryStageHost
var slideshow_enabled := false

var _bg: TextureRect
var _incoming: TextureRect
var _frames: Array[Texture2D] = []
var _frame_i := 0
var _frame_timer: Timer
var _by_turn: Dictionary = {}
var _paths: Array = []
var _path_i := 0
var _speaker := ""
var _last_advance_msec := -100000
var _lull_cycling := false
var _lull_timer: Timer
var _fade: Tween


func initialize_with_background(bg: TextureRect, preferred_default: String = "") -> void:
	_bg = bg
	_incoming = bg.get_node_or_null("BackgroundIncoming") as TextureRect
	_frame_timer = Timer.new()
	_frame_timer.wait_time = 0.2
	_frame_timer.timeout.connect(_cycle_frame)
	add_child(_frame_timer)
	_lull_timer = Timer.new()
	_lull_timer.wait_time = 6.0
	_lull_timer.timeout.connect(_advance_slide)
	add_child(_lull_timer)
	_apply_resolved(preferred_default)


func restage_scenario_background() -> void:
	_apply_resolved("")


func enable_slideshow() -> void:
	slideshow_enabled = true


func disable_slideshow() -> void:
	slideshow_enabled = false
	_lull_cycling = false
	if _lull_timer:
		_lull_timer.stop()


func is_slideshow_enabled() -> bool:
	return slideshow_enabled


func enqueue_images(image_paths: Array, turn_id: int) -> void:
	_by_turn[turn_id] = image_paths.duplicate()


func notify_turn_started(turn_id: int) -> void:
	if not slideshow_enabled:
		return
	var paths: Variant = _by_turn.get(turn_id, [])
	if not (paths is Array) or (paths as Array).is_empty():
		return
	_paths = paths
	_path_i = 0
	_show_path(str(_paths[0]), true)
	_last_advance_msec = Time.get_ticks_msec()


func notify_lull_ended() -> void:
	_lull_cycling = false
	if _lull_timer:
		_lull_timer.stop()


func start_lull_cycle() -> void:
	if not slideshow_enabled or _paths.is_empty():
		return
	_lull_cycling = true
	if _lull_timer and _lull_timer.is_stopped():
		_lull_timer.start()


func note_speaker(speaker: String) -> void:
	if not slideshow_enabled:
		_speaker = speaker
		return
	if speaker == _speaker:
		return
	_speaker = speaker
	if Time.get_ticks_msec() - _last_advance_msec < 3000:
		return
	_advance_slide()


func preload_replay_dir() -> void:
	if host == null:
		return
	var folder := host.get_replay_backgrounds_dir()
	if folder == "":
		return
	var paths: Array = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for name in dir.get_files():
		if str(name).to_lower().ends_with(".png"):
			paths.append(folder.path_join(str(name)))
	paths.sort()
	if not paths.is_empty():
		enqueue_images(paths, -1)
		if slideshow_enabled:
			notify_turn_started(-1)


func show_texture(texture: Texture2D, crossfade: bool) -> void:
	if _bg == null or texture == null:
		return
	if not crossfade or _incoming == null or _bg.texture == null:
		_bg.texture = texture
		if _incoming:
			_incoming.modulate.a = 0.0
		_sync_surface(texture)
		return
	_incoming.texture = texture
	_incoming.modulate.a = 0.0
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_incoming, "modulate:a", 1.0, 1.8)
	_fade.finished.connect(func() -> void:
		_bg.texture = texture
		_incoming.modulate.a = 0.0
		_sync_surface(texture)
	)


func _apply_resolved(preferred: String) -> void:
	var resolved := _resolve(preferred)
	if resolved:
		_bg.texture = resolved
		_sync_surface(resolved)


func _resolve(preferred: String) -> Texture2D:
	_frame_timer.stop()
	_frames.clear()
	var art := ""
	if host:
		art = host.get_scenario_art_dir()
	var folder := art.path_join("background") if art != "" else ""
	var pngs := _pngs(folder)
	if pngs.size() >= 2:
		for png in pngs:
			var texture := _load_texture(png)
			if texture:
				_frames.append(texture)
		if _frames.size() >= 2:
			_frame_i = 0
			_frame_timer.start()
			return _frames[0]
	var name := preferred
	if name == "" and host:
		name = host.get_default_background_name()
	if name == "" or name == "title_screen":
		return null
	var path := _named_path(name)
	if path == "":
		return null
	return _load_texture(path)


func _named_path(image_name: String) -> String:
	if host == null:
		return ""
	var root := host.get_backgrounds_dir()
	if root == "":
		return ""
	var direct := root.path_join(image_name + ".png")
	if FileAccess.file_exists(direct):
		return direct
	return ""


func _cycle_frame() -> void:
	if _frames.size() < 2 or _bg == null:
		return
	_frame_i = (_frame_i + 1) % _frames.size()
	_bg.texture = _frames[_frame_i]
	_sync_surface(_frames[_frame_i])


func _advance_slide() -> void:
	if _paths.is_empty():
		return
	_path_i = (_path_i + 1) % _paths.size()
	_show_path(str(_paths[_path_i]), true)
	_last_advance_msec = Time.get_ticks_msec()


func _show_path(path: String, crossfade: bool) -> void:
	var texture := _load_texture(path)
	if texture:
		show_texture(texture, crossfade)


func _pngs(folder: String) -> Array[String]:
	var out: Array[String] = []
	if folder == "":
		return out
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	for name in dir.get_files():
		if str(name).to_lower().ends_with(".png"):
			out.append(folder.path_join(str(name)))
	out.sort()
	return out


func _load_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _sync_surface(texture: Texture2D) -> void:
	var surface := get_parent().get_node_or_null("StageViewport/StageWorld/Backdrop") if get_parent() else null
	if surface is Sprite2D:
		(surface as Sprite2D).texture = texture


static func get_location_context_for_ai() -> String:
	var dir_path := StoryStageHost.resolve_default().get_backgrounds_dir().strip_edges()
	if dir_path == "":
		return ""
	var found := _read_backgrounds(dir_path)
	if found.is_empty():
		return ""
	var lines: PackedStringArray = ["Available locations for the story:"]
	for bg_name in found:
		var meta: Dictionary = found[bg_name]
		lines.append("- %s: %s" % [bg_name.replace("_", " "), str(meta.get("description", ""))])
		var instructions := str(meta.get("ai_instructions", "")).strip_edges()
		if instructions != "":
			lines.append("  (Use for: %s)" % instructions)
	if found.size() > 1:
		lines.append("")
		lines.append("You may naturally transition between these locations as the story develops.")
	else:
		lines.append("")
		lines.append("Keep the story in the current location unless there's a compelling narrative reason to change.")
	return "\n".join(lines)


static func _read_backgrounds(dir_path: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file_name in dir.get_files():
		var name := str(file_name)
		if not name.to_lower().ends_with(".png") or name.ends_with(".import"):
			continue
		var bg_name := name.get_basename()
		out[bg_name] = _read_meta(dir_path.path_join(bg_name + ".json"), bg_name)
	return out


static func _read_meta(json_path: String, bg_name: String) -> Dictionary:
	var meta := {
		"description": "A location called " + bg_name.replace("_", " "),
		"ai_instructions": "",
	}
	var text := FileAccess.get_file_as_string(json_path)
	if text == "":
		return meta
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return meta
	var data: Dictionary = parsed
	if str(data.get("description", "")).strip_edges() != "":
		meta["description"] = str(data["description"])
	meta["ai_instructions"] = str(data.get("ai_instructions", ""))
	return meta
