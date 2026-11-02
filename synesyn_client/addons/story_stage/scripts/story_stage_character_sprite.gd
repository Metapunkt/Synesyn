class_name StoryStageCharacterSprite
extends Node2D

## One 2D portrait: authored loops, mouth sheet, bob, and optional deformation.

var allow_big := false
var motion_blend := 0.0

var _registry: StoryStageCharacter
var _anim: AnimatedSprite2D
var _mouth: Sprite2D
var _spectrum: Node2D
var _light: PointLight2D
var _player: AnimationPlayer
var _tree: AnimationTree
var _skeleton: Skeleton2D
var _bone: Bone2D
var _poly: Polygon2D
var _base := Vector2.ZERO
var _intensity := 0.0
var _bob_t := 0.0
var _expression := "neutral"
var _talking := false
var _deform := false
var _has_art := false
var _generated: SpriteFrames
var _authored: SpriteFrames
var _character_id := -1
var _normal: Texture2D


func _ready() -> void:
	_anim = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _anim == null:
		_anim = AnimatedSprite2D.new()
		_anim.name = "AnimatedSprite2D"
		add_child(_anim)
	_anim.centered = true
	_mouth = get_node_or_null("Mouth") as Sprite2D
	if _mouth == null:
		_mouth = Sprite2D.new()
		_mouth.name = "Mouth"
		_mouth.visible = false
		add_child(_mouth)
	_spectrum = get_node_or_null("Spectrum") as Node2D
	if _spectrum == null:
		_spectrum = StoryStageSpectrum.new()
		_spectrum.name = "Spectrum"
		add_child(_spectrum)
	_light = PointLight2D.new()
	_light.name = "CueLight"
	_light.energy = 0.6
	_light.texture = _light_texture()
	_light.texture_scale = 4.0
	add_child(_light)
	_base = position


func bind_registry(registry: StoryStageCharacter) -> void:
	_registry = registry


func change_character(id: int, talking: bool, expression: String) -> void:
	_character_id = id
	_expression = expression if expression != "" else "neutral"
	_talking = talking
	_apply_details()


func change_character_scensyn(cname: String, talking: bool, expression: String = "neutral") -> void:
	if _registry == null:
		return
	change_character(_registry.id_for_name(cname), talking, expression)


func set_talking_intensity(intensity: float) -> void:
	_intensity = clampf(intensity, 0.0, 1.0)
	if _intensity <= 0.05:
		_talking = false
		_intensity = 0.0
		if _anim:
			_anim.speed_scale = 1.0
		_apply_anim()
		_blend_to(0.0)
		return
	_talking = true
	if _anim:
		_anim.speed_scale = 1.0
	_apply_anim()
	_blend_to(_intensity)


## Keeps the talking loop running for the whole utterance. The spectrum level only
## opens the mouth and nods the portrait; it must not restart the clip or change its speed.
func set_speech_level(level: float) -> void:
	var was_talking := _talking
	_talking = true
	_intensity = clampf(level, 0.0, 1.0)
	if _anim:
		_anim.speed_scale = 1.0
	if not was_talking:
		_apply_anim()
	_blend_to(_intensity)


func set_mouth(viseme: String, intensity: float) -> void:
	if _mouth == null:
		return
	var details := _details()
	var mouth: Dictionary = details.get("mouth", {})
	var key := StoryStageViseme.canonical(viseme)
	if details.get("profile") is StoryStageCharacterProfile:
		var custom: Dictionary = (details["profile"] as StoryStageCharacterProfile).viseme_map
		if custom.has(key) and custom[key] is String and mouth.has(custom[key]):
			key = str(custom[key])
	if not mouth.has(key):
		_mouth.visible = false
		return
	_mouth.texture = mouth[key]
	_mouth.visible = true
	_mouth.scale = Vector2.ONE * lerpf(0.9, 1.15, clampf(intensity, 0.0, 1.0))


func enable_deform(on: bool) -> void:
	_deform = on
	if on:
		_ensure_deform()
	if _skeleton:
		_skeleton.visible = on
	if _poly:
		_poly.visible = on and _has_art
	if _anim:
		_anim.visible = _has_art and not on


func set_light_energy(energy: float) -> void:
	if _light:
		_light.energy = energy


func use_generated(frames: SpriteFrames) -> void:
	_generated = frames
	_apply_anim()


func play_authored_talking() -> void:
	_talking = true
	_intensity = 0.0
	if _anim:
		_anim.speed_scale = 1.0
	_apply_anim()


func current_animation() -> String:
	if _anim == null:
		return ""
	return str(_anim.animation)


func current_texture() -> Texture2D:
	if _anim == null or _anim.sprite_frames == null:
		return null
	if not _anim.sprite_frames.has_animation(_anim.animation):
		return null
	if _anim.sprite_frames.get_frame_count(_anim.animation) <= 0:
		return null
	return _anim.sprite_frames.get_frame_texture(_anim.animation, _anim.frame)


func _process(delta: float) -> void:
	if _talking:
		_bob_t += delta
		position = _base + Vector2(0.0, sin(_bob_t * 3.2) * 2.5 * _intensity)
	else:
		position = _base
	if _deform:
		_tick_deform()
	if _spectrum is StoryStageSpectrum:
		(_spectrum as StoryStageSpectrum).set_active(not _has_art)


func set_base_position(pos: Vector2) -> void:
	_base = pos
	if _intensity <= 0.05:
		position = pos


func portrait_size() -> Vector2:
	var tex := current_texture()
	if tex:
		var sz := tex.get_size()
		if sz.x > 1.0 and sz.y > 1.0:
			return sz
	return Vector2(1024, 768)


func fit_portrait(frame: Vector2) -> Vector2:
	var native := portrait_size()
	var s := maxf(frame.x / native.x, frame.y / native.y)
	s = clampf(s, 0.4, 3.0)
	scale = Vector2(s, s)
	return native * s


func _apply_details() -> void:
	var details := _details()
	var frames: Variant = details.get("sprite_frames")
	_has_art = frames is SpriteFrames
	_authored = frames if _has_art else null
	var speaker_name := str(details.get("name", ""))
	if _spectrum:
		_spectrum.visible = not _has_art and speaker_name != "Narrator"
	if not _has_art:
		if _anim:
			_anim.visible = false
		if _mouth:
			_mouth.visible = false
		return
	_anim.visible = not _deform
	_anim.sprite_frames = _authored
	_ensure_blend_tree()
	_apply_anim()


func _apply_anim() -> void:
	if _anim == null or (_authored == null and _generated == null):
		return
	var name := _animation_name(_authored if _authored else _generated)
	if _generated and _expression != "" and _expression != "neutral":
		var sided := "%s-%s" % [_expression, "talking" if _talking else "idle"]
		if _generated.has_animation(sided):
			name = sided
	var source: SpriteFrames = null
	if _generated and _generated.has_animation(name):
		source = _generated
	elif _authored and _authored.has_animation(name):
		source = _authored
	if source == null:
		return
	if _anim.sprite_frames != source:
		_anim.sprite_frames = source
	if _anim.animation != name or not _anim.is_playing():
		_anim.play(name)


func _animation_name(frames: SpriteFrames) -> String:
	var expr := "" if _expression == "" or _expression == "neutral" else _expression
	if _talking and allow_big and _intensity >= 0.7 and frames.has_animation("talking_big"):
		return "talking_big"
	if expr != "":
		var sided := "%s-%s" % [expr, "talking" if _talking else "idle"]
		if frames.has_animation(sided):
			return sided
	if _talking and frames.has_animation("talking"):
		return "talking"
	return "idle"


func _details() -> Dictionary:
	if _registry == null or _character_id < 0:
		return {}
	return _registry.get_character_details(_character_id)


func _ensure_blend_tree() -> void:
	if _tree or _anim == null or _anim.sprite_frames == null:
		return
	_player = AnimationPlayer.new()
	_player.name = "BlendPlayer"
	add_child(_player)
	var library := AnimationLibrary.new()
	library.add_animation("idle", _blend_animation(0.0))
	library.add_animation("talking", _blend_animation(1.0))
	_player.add_animation_library("", library)
	_tree = AnimationTree.new()
	_tree.name = "BlendTree"
	var blend := AnimationNodeBlendSpace1D.new()
	var idle := AnimationNodeAnimation.new()
	idle.animation = "idle"
	var talking := AnimationNodeAnimation.new()
	talking.animation = "talking"
	blend.add_blend_point(idle, 0.0, -1, &"idle")
	blend.add_blend_point(talking, 1.0, -1, &"talking")
	_tree.tree_root = blend
	add_child(_tree)
	_tree.anim_player = NodePath("../BlendPlayer")
	_tree.active = true
	_blend_to(0.0)


func _blend_animation(value: float) -> Animation:
	var anim := Animation.new()
	anim.length = 0.2
	var idx := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(idx, NodePath(".:motion_blend"))
	anim.track_insert_key(idx, 0.0, value)
	anim.track_insert_key(idx, 0.2, value)
	return anim


func _blend_to(value: float) -> void:
	if _tree:
		_tree.set("parameters/blend_position", clampf(value, 0.0, 1.0))


func _ensure_deform() -> void:
	if _skeleton:
		return
	_skeleton = Skeleton2D.new()
	_skeleton.name = "DeformSkeleton"
	_bone = Bone2D.new()
	_bone.name = "head"
	_bone.set_autocalculate_length_and_angle(false)
	_bone.length = 80.0
	_bone.rest = Transform2D(0.0, Vector2(0, -80))
	_bone.apply_rest()
	var tip := Bone2D.new()
	tip.name = "tip"
	tip.set_autocalculate_length_and_angle(false)
	tip.length = 16.0
	tip.rest = Transform2D(0.0, Vector2(0, -40))
	tip.apply_rest()
	_bone.add_child(tip)
	_skeleton.add_child(_bone)
	add_child(_skeleton)
	_poly = Polygon2D.new()
	_poly.name = "DeformMesh"
	_poly.polygon = PackedVector2Array([
		Vector2(-160, -220), Vector2(160, -220), Vector2(160, 220), Vector2(-160, 220),
	])
	_poly.uv = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
	])
	add_child(_poly)
	_poly.skeleton = _poly.get_path_to(_skeleton)
	_poly.add_bone(_poly.get_path_to(_bone), PackedFloat32Array([1.0, 1.0, 0.15, 0.15]))
	var material := ShaderMaterial.new()
	material.shader = load("res://addons/story_stage/shaders/portrait.gdshader")
	_poly.material = material


func _tick_deform() -> void:
	if _bone:
		_bone.rotation = sin(Time.get_ticks_msec() / 1000.0 * 0.6) * 0.08
	if _poly == null:
		return
	var texture := current_texture()
	if texture:
		_poly.texture = _canvas(texture)
	if _poly.material is ShaderMaterial:
		var phase := fmod(Time.get_ticks_msec() / 1000.0, 4.2)
		var blink := 1.0 if phase > 3.85 else 0.0
		(_poly.material as ShaderMaterial).set_shader_parameter("blink", blink)
		(_poly.material as ShaderMaterial).set_shader_parameter("breath", 1.0)


func _canvas(texture: Texture2D) -> Texture2D:
	var canvas := CanvasTexture.new()
	canvas.diffuse_texture = texture
	canvas.normal_texture = _flat_normal()
	return canvas


func _flat_normal() -> Texture2D:
	if _normal:
		return _normal
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color(0.5, 0.5, 1.0))
	_normal = ImageTexture.create_from_image(image)
	return _normal


func _light_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 0.96, 0.9, 0.9))
	gradient.set_color(1, Color(1, 0.96, 0.9, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
