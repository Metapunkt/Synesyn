class_name StoryStageCharacter
extends Node

## Per-stage character registry and sprite discovery. Not process-wide.

const NARRATOR_ID := 0

static var _live: Array[StoryStageCharacter] = []
static var _pending: Dictionary = {}
static var _pending_next := 1

var stage: Node
var _by_name: Dictionary = {}
var _by_id: Dictionary = {}
var _next_id := 1
var _normal: Texture2D


static func dir_slug(s: String) -> String:
	var source := s.strip_edges().to_lower()
	var out := ""
	for i in source.length():
		var c := source.substr(i, 1)
		if c == " " or c == "/" or c == "\\" or c == ":":
			out += "_"
		else:
			out += c
	return out


static func _dir_slug(s: String) -> String:
	return dir_slug(s)


static func _get_sprite_roots_for_current_scenario() -> Array[String]:
	return StoryStageHost.resolve_default().get_sprite_roots()


static func _load_texture_any(texture_path: String) -> Texture2D:
	var path := texture_path.strip_edges()
	if path == "":
		return null
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			var loaded: Variant = load(path)
			if loaded is Texture2D:
				return loaded
		return null
	var absolute := path.replace("\\", "/")
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.new()
	if image.load(absolute) != OK:
		return null
	return ImageTexture.create_from_image(image)


func setup(p_stage: Node) -> void:
	stage = p_stage
	_ensure_narrator()


func _enter_tree() -> void:
	if not _live.has(self):
		_live.append(self)
	for cname in _pending.keys():
		if _by_name.has(cname):
			continue
		var id := int(_pending[cname])
		_store(id, str(cname), {"name": cname})
		_next_id = maxi(_next_id, id + 1)


func _exit_tree() -> void:
	_live.erase(self)


static func clear_all_characters() -> void:
	_pending.clear()
	_pending_next = 1
	for reg in _live:
		if is_instance_valid(reg):
			reg.reset()


static func register_scensyn_character(char_data: Dictionary) -> int:
	var cname := str(char_data.get("name", "")).strip_edges()
	if cname == "":
		return -1
	if _live.is_empty():
		if _pending.has(cname):
			return int(_pending[cname])
		var id := _pending_next
		_pending_next += 1
		_pending[cname] = id
		return id
	var id := -1
	for reg in _live:
		if is_instance_valid(reg):
			id = reg.register_character(char_data)
	return id


static func get_enum_from_string(cname: String) -> int:
	if not _live.is_empty() and is_instance_valid(_live[0]):
		return _live[0].id_for_name(cname)
	if _pending.has(cname):
		return int(_pending[cname])
	return -1


func register_character(char_data: Dictionary) -> int:
	var cname := str(char_data.get("name", "")).strip_edges()
	if cname == "":
		return NARRATOR_ID
	if _by_name.has(cname):
		return int(_by_name[cname])
	var id := _next_id
	_next_id += 1
	_store(id, cname, char_data)
	return id


func _is_narrator_name(name: String) -> bool:
	var bare := name.trim_prefix("The ").strip_edges() if name.begins_with("The ") else name
	return bare == "Narrator"


func id_for_name(cname: String) -> int:
	var name := cname.strip_edges()
	if name == "":
		return NARRATOR_ID
	if _is_narrator_name(name) and not _folder_exists(name):
		_by_name[name] = NARRATOR_ID
		return NARRATOR_ID
	if _by_name.has(name):
		return int(_by_name[name])
	return register_character({"name": name})


func get_character_details(id: int) -> Dictionary:
	_ensure_narrator()
	if not _by_id.has(id):
		return {}
	var stored: Dictionary = _by_id[id]
	if stored.get("sprite_frames") == null:
		_load_art(int(stored["id"]), str(stored["name"]))
	return _public_details(stored)


func get_character_details_by_name(cname: String) -> Dictionary:
	return get_character_details(id_for_name(cname))


func refresh_character_sprite_frames(cname: String) -> void:
	var id := id_for_name(cname)
	if not _by_id.has(id):
		return
	var stored: Dictionary = _by_id[id]
	stored["sprite_frames"] = null
	stored["mouth"] = {}
	stored["loaded"] = false
	_load_art(id, str(stored["name"]))


func reset() -> void:
	_by_name.clear()
	_by_id.clear()
	_next_id = 1
	_ensure_narrator()


func _ensure_narrator() -> void:
	if _by_id.has(NARRATOR_ID):
		return
	_store(NARRATOR_ID, "Narrator", {"name": "Narrator"})


func _store(id: int, cname: String, char_data: Dictionary) -> void:
	var profile := StoryStageCharacterProfile.new()
	profile.id = str(char_data.get("id", cname))
	profile.display_name = str(char_data.get("display_name", cname))
	profile.sprite_slug = dir_slug(cname)
	profile.voice_name = str(char_data.get("voice_name", cname))
	if char_data.get("expressions") is PackedStringArray:
		profile.expressions = char_data["expressions"]
	elif char_data.get("expressions") is Array:
		var names := PackedStringArray()
		for item in char_data["expressions"]:
			names.append(str(item))
		profile.expressions = names
	if char_data.get("gestures") is Array:
		var gestures := PackedStringArray()
		for item in char_data["gestures"]:
			gestures.append(str(item))
		profile.gestures = gestures
	_by_name[cname] = id
	_by_id[id] = {
		"id": id,
		"name": cname,
		"sprite_frames": null,
		"mouth": {},
		"profile": profile,
		"loaded": false,
	}


func _public_details(stored: Dictionary) -> Dictionary:
	var profile: StoryStageCharacterProfile = stored.get("profile")
	var details := {
		"id": stored["id"],
		"name": stored["name"],
		"sprite_frames": stored.get("sprite_frames"),
		"mouth": stored.get("mouth", {}),
		"profile": profile,
	}
	if profile:
		details["display_name"] = profile.display_name
		details["sprite_slug"] = profile.sprite_slug
		details["expressions"] = profile.expressions
		details["gestures"] = profile.gestures
		details["voice_name"] = profile.voice_name
		details["viseme_map"] = profile.viseme_map
	return details


func _folder_exists(cname: String) -> bool:
	var slug := dir_slug(cname)
	for root in _roots():
		if _dir_exists(root.path_join(slug)):
			return true
	return false


func _load_art(id: int, cname: String) -> void:
	if not _by_id.has(id):
		return
	var stored: Dictionary = _by_id[id]
	if stored.get("loaded"):
		return
	stored["loaded"] = true
	var slug := dir_slug(cname)
	var folder := _first_folder(slug)
	if folder == "" and id == NARRATOR_ID:
		return
	if folder == "" and slug != "_fallback":
		folder = _first_folder("_fallback")
	if folder == "":
		return
	var built := _build_frames(folder)
	stored["sprite_frames"] = built.get("frames")
	stored["mouth"] = built.get("mouth", {})
	var profile: StoryStageCharacterProfile = stored.get("profile")
	if profile:
		profile.expressions = PackedStringArray(built.get("expressions", PackedStringArray()))
		profile.viseme_map = stored["mouth"]
	_maybe_save_tres(folder, slug, stored.get("sprite_frames"))


func _first_folder(slug: String) -> String:
	if slug == "":
		return ""
	for root in _roots():
		var path := root.path_join(slug)
		if _dir_exists(path):
			return path
	return ""


func _roots() -> Array[String]:
	if stage == null or stage.host == null:
		var empty: Array[String] = []
		return empty
	return stage.host.get_sprite_roots()


func _build_frames(folder: String) -> Dictionary:
	var frames := SpriteFrames.new()
	var expressions := PackedStringArray()
	var found := false
	var dir := DirAccess.open(folder)
	if dir == null:
		return {"frames": null, "mouth": {}, "expressions": expressions}
	var subdirs: Array[String] = []
	for entry in dir.get_directories():
		subdirs.append(str(entry))
	subdirs.sort()
	for sub in subdirs:
		if sub.begins_with("."):
			continue
		if sub == "mouth":
			continue
		var pngs := _pngs(folder.path_join(sub))
		if pngs.is_empty():
			continue
		if not frames.has_animation(sub):
			frames.add_animation(sub)
		frames.set_animation_speed(sub, 5.0)
		frames.set_animation_loop(sub, true)
		frames.set_animation_loop_mode(sub, SpriteFrames.LOOP_PINGPONG)
		for png in pngs:
			var texture := _texture(png)
			if texture:
				frames.add_frame(sub, texture)
				found = true
		if sub.ends_with("-idle") or sub.ends_with("-talking"):
			var expr := sub.trim_suffix("-idle").trim_suffix("-talking")
			if expr != "" and not expressions.has(expr):
				expressions.append(expr)
	var mouth := _load_mouth(folder.path_join("mouth"))
	if not found:
		return {"frames": null, "mouth": mouth, "expressions": expressions}
	if not frames.has_animation("idle") and frames.has_animation("talking"):
		frames.duplicate_animation("talking", "idle")
	return {"frames": frames, "mouth": mouth, "expressions": expressions}


func _load_mouth(folder: String) -> Dictionary:
	var mouth := {}
	if not _dir_exists(folder):
		return mouth
	for png in _pngs(folder):
		var base := png.get_file().get_basename()
		var texture := _texture(png)
		if texture:
			mouth[StoryStageViseme.canonical(base)] = texture
	return mouth


func _maybe_save_tres(folder: String, slug: String, frames: Variant) -> void:
	if frames == null or stage == null or stage.host == null:
		return
	var root := folder.get_base_dir()
	var dest := str(stage.host.get_generated_sprite_resource_path(root, slug))
	if dest == "" or not dest.begins_with("res://"):
		return
	ResourceSaver.save(frames, dest)


func _texture(path: String) -> Texture2D:
	return _load_texture_any(path)


func _pngs(folder: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	for entry in dir.get_files():
		var name := str(entry)
		if name.to_lower().ends_with(".png"):
			out.append(folder.path_join(name))
	out.sort()
	return out


func _dir_exists(path: String) -> bool:
	return path != "" and DirAccess.open(path) != null
