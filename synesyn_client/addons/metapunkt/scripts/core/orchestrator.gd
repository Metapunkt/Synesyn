@tool
extends Node
class_name Orchestrator

signal component_registered(component_name: String)
signal component_unregistered(component_name: String)
signal state_changed(component: String, new_state: Dictionary)

# Component references
var _components := {}
var _resource_manager = null
var _state_manager = null
var _task_processor = null

# Component paths
const COMPONENT_PATHS := {
    "syntree": "res://addons/syntree/plugin.gd",
    "synpunkt": "res://addons/synpunkt/plugin.gd",
    "synaxes": "res://addons/synaxes/plugin.gd"
}

func _init() -> void:
    _resource_manager = preload("res://addons/metapunkt/scripts/core/resource_manager.gd").new()
    _state_manager = preload("res://addons/metapunkt/scripts/core/state_manager.gd").new()
    _task_processor = preload("res://addons/metapunkt/scripts/task/task_processor.gd").new()

func _ready() -> void:
    # @tool safety: defer child attachment until we're inside the tree.
    if _resource_manager and not _resource_manager.get_parent():
        add_child.call_deferred(_resource_manager)
    if _state_manager and not _state_manager.get_parent():
        add_child.call_deferred(_state_manager)
    if _task_processor and not _task_processor.get_parent():
        add_child.call_deferred(_task_processor)

func initialize_interfaces() -> void:
    for component_name in COMPONENT_PATHS:
        var plugin_path = COMPONENT_PATHS[component_name]
        if FileAccess.file_exists(plugin_path):
            _connect_to_component(component_name, plugin_path)

func _connect_to_component(component_name: String, plugin_path: String) -> void:
    var plugin_script = load(plugin_path)
    if plugin_script:
        var interface_script = load("res://addons/metapunkt/scripts/interfaces/" + component_name + "_interface.gd")
        if interface_script:
            var interface = interface_script.new()
            interface.setup(plugin_script)
            _components[component_name] = interface
            emit_signal("component_registered", component_name)

func submit_task(task: Dictionary) -> void:
    if not task.has("type") or not task.has("data"):
        push_error("Invalid task format")
        return
    
    _task_processor.process_task(task)

func get_component_state(component_name: String) -> Dictionary:
    return _state_manager.get_component_state(component_name)

func update_component_state(component_name: String, state: Dictionary) -> void:
    _state_manager.update_component_state(component_name, state)
    emit_signal("state_changed", component_name, state)

func allocate_resources(component: String, requirements: Dictionary) -> bool:
    return _resource_manager.allocate_resources(component, requirements)

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # Clean up
        for component in _components.values():
            if is_instance_valid(component):
                component.queue_free()
        
        if _resource_manager:
            _resource_manager.queue_free()
        if _state_manager:
            _state_manager.queue_free()
        if _task_processor:
            _task_processor.queue_free() 