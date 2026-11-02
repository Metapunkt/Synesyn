class_name StoryStageCharacterProfile
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var sprite_slug: String = ""
@export var scene_3d: PackedScene
@export var expressions: PackedStringArray = PackedStringArray()
@export var gestures: PackedStringArray = PackedStringArray()
@export var viseme_map: Dictionary = {}
@export var voice_name: String = ""
