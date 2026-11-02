## SynPunkt — Presentation and generative document surface for the Godot editor.
## Copyright © 2026 Ayodele Arigbabu | metapunkt.org | NTNU. All rights reserved.
## Licensed under [licence pending].
## Version: 0.0.3
## Enquiries: metapunkt@metapunkt.org
@tool
extends EditorPlugin

const DOCK_SCENE_PATH := "res://addons/synpunkt/scenes/synpunkt_dock.tscn"

var _dock: Control

func _enter_tree() -> void:
	_dock = load(DOCK_SCENE_PATH).instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	print("SynPunkt plugin enabled")

func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	print("SynPunkt plugin disabled")


