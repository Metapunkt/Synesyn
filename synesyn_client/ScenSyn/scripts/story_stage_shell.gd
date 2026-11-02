extends Control

@onready var back_button: Button = %BackButton

func _ready() -> void:
	if back_button:
		back_button.pressed.connect(_go_back)

func _go_back() -> void:
	get_tree().change_scene_to_file("res://ScenSyn/scenes/synesyn_tools.tscn")


