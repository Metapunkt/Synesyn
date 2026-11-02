## Purpose: SynTreeStateManager (script)
@tool
extends BaseService

class_name SynTreeStateManager

signal state_changed(key: String, value: Variant)
signal state_reset

var state: Dictionary = {
	"current_model": "",
	"current_thread": "",
	"content_sources": [],
	"is_processing": false
}

func _init() -> void:
	super._init()

func get_service_name() -> String:
	return "state_manager"

func _setup() -> bool:
	# Initialize default state
	state = {
		"current_model": "",
		"current_thread": "",
		"content_sources": [],
		"is_processing": false
	}
	return true

func set_state(key: String, value: Variant) -> void:
	state[key] = value
	state_changed.emit(key, value)

func get_state(key: String) -> Variant:
	return state.get(key, null)

func get_full_state() -> Dictionary:
	return state.duplicate()

func reset_state() -> void:
	state = {
		"current_model": "",
		"current_thread": "",
		"content_sources": [],
		"is_processing": false
	}
	state_reset.emit()
