## Purpose: ErrorDialog (script)
@tool
extends "res://addons/syntree/scripts/base/base_component.gd"

class_name ErrorDialog

signal dialog_closed

@onready var dialog: AcceptDialog = %ErrorDialog
@onready var error_label: Label = %ErrorLabel

func _init() -> void:
	super._init()

func _ready() -> void:
	await super._ready()
	
	if dialog:
		dialog.close_requested.connect(_on_dialog_closed)
		dialog.hide()

func get_component_name() -> String:
	return "error_dialog"

func show_error(message: String) -> void:
	if error_label:
		error_label.text = message
	if dialog:
		dialog.popup_centered()

func _on_dialog_closed() -> void:
	dialog_closed.emit()
