@tool
extends RefCounted
class_name ComponentInterface

signal status_changed(status: Dictionary)
signal task_completed(task_id: String, result: Dictionary)
signal task_failed(task_id: String, error: String)

var _component_name: String
var _component_status: Dictionary = {
    "status": "inactive",
    "health": 100.0,
    "last_update": 0
}

func _init(component_name: String) -> void:
    _component_name = component_name

func setup(plugin_script: GDScript) -> void:
    push_error("ComponentInterface.setup() must be implemented by child classes")

func send_command(command: Dictionary) -> void:
    push_error("ComponentInterface.send_command() must be implemented by child classes")

func receive_status(status: Dictionary) -> void:
    _component_status = status
    emit_signal("status_changed", status)

func get_status() -> Dictionary:
    return _component_status.duplicate()

func get_name() -> String:
    return _component_name

func _validate_command(command: Dictionary) -> bool:
    return command.has("type") and command.has("data")

func _update_status(key: String, value: Variant) -> void:
    _component_status[key] = value
    _component_status["last_update"] = Time.get_unix_time_from_system()
    emit_signal("status_changed", _component_status.duplicate()) 