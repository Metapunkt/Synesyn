# character_manager.gd
extends Node

class_name CharacterManager

signal character_switched(character_name)

var characters = {}
var current_character = ""


func _ready():
	load_characters()


func _metaprompts_dir() -> String:
	var dest_dir: String = RuntimeConfig.get_character_metaprompts_dir()
	DirAccess.make_dir_recursive_absolute(dest_dir)
	_migrate_legacy_metaprompts(dest_dir)
	return dest_dir


func _migrate_legacy_metaprompts(dest_dir: String) -> void:
	for legacy_dir: String in [
		"user://ScenSyn/character_metaprompts/",
		"user://scensyn/character_metaprompts/",
	]:
		var abs_legacy: String = ProjectSettings.globalize_path(legacy_dir)
		if not DirAccess.dir_exists_absolute(abs_legacy):
			continue
		var dir: DirAccess = DirAccess.open(legacy_dir)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.ends_with(".txt"):
				var dest_path: String = dest_dir.path_join(file_name)
				if not FileAccess.file_exists(dest_path):
					RuntimeConfig.migrate_file_if_needed(
						dest_path,
						[legacy_dir.path_join(file_name)]
					)
			file_name = dir.get_next()
		dir.list_dir_end()


func load_characters():
	var dir_path: String = _metaprompts_dir()
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".txt"):
				var character_name = file_name.replace(".txt", "")
				characters[character_name] = load_character_metaprompt(character_name)
			file_name = dir.get_next()
		dir.list_dir_end()

func load_character_metaprompt(character_name: String) -> String:
	var file = FileAccess.open(
		_metaprompts_dir().path_join(character_name + ".txt"),
		FileAccess.READ
	)
	if file:
		var metaprompt = file.get_as_text()
		file.close()
		return metaprompt
	return ""

func switch_character(character_name: String):
	if characters.has(character_name):
		current_character = character_name
		# UPDATED: Character switching now handled through Global character system
		# instead of direct godot_syntree metaprompt setting
		Global.set_current_character({"name": character_name, "metaprompt": characters[character_name]})
		emit_signal("character_switched", character_name)
	else:
		print("Character not found: " + character_name)

func get_current_character() -> String:
	return current_character

func get_available_characters() -> Array:
	return characters.keys()
