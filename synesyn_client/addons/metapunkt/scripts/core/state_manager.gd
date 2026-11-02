@tool
extends Node
class_name StateManager

signal state_changed(component: String, new_state: Dictionary)
signal pattern_state_changed(pattern_id: String, new_state: Dictionary)
signal workflow_state_changed(workflow_id: String, new_state: Dictionary)

# State storage
var _component_states := {}
var _pattern_states := {}
var _workflow_states := {}

# Component state structure
class ComponentState:
    var status: String = "inactive"  # inactive, initializing, active, error
    var health: float = 100.0  # 0-100
    var resources: Dictionary = {}
    var last_update: int = 0
    var error: String = ""
    
    func to_dict() -> Dictionary:
        return {
            "status": status,
            "health": health,
            "resources": resources.duplicate(),
            "last_update": last_update,
            "error": error
        }
    
    func from_dict(data: Dictionary) -> void:
        if data.has("status"): status = data.status
        if data.has("health"): health = data.health
        if data.has("resources"): resources = data.resources.duplicate()
        if data.has("last_update"): last_update = data.last_update
        if data.has("error"): error = data.error

# Pattern state structure
class PatternState:
    var pattern_id: String
    var type: String
    var confidence: float
    var relationships: Array
    var metadata: Dictionary
    var last_update: int
    
    func _init(id: String) -> void:
        pattern_id = id
        type = "unknown"
        confidence = 0.0
        relationships = []
        metadata = {}
        last_update = Time.get_unix_time_from_system()
    
    func to_dict() -> Dictionary:
        return {
            "pattern_id": pattern_id,
            "type": type,
            "confidence": confidence,
            "relationships": relationships.duplicate(),
            "metadata": metadata.duplicate(),
            "last_update": last_update
        }
    
    func from_dict(data: Dictionary) -> void:
        if data.has("type"): type = data.type
        if data.has("confidence"): confidence = data.confidence
        if data.has("relationships"): relationships = data.relationships.duplicate()
        if data.has("metadata"): metadata = data.metadata.duplicate()
        if data.has("last_update"): last_update = data.last_update

# Workflow state structure
class WorkflowState:
    var workflow_id: String
    var status: String
    var progress: float
    var steps: Array
    var current_step: int
    var errors: Array
    
    func _init(id: String) -> void:
        workflow_id = id
        status = "pending"
        progress = 0.0
        steps = []
        current_step = -1
        errors = []
    
    func to_dict() -> Dictionary:
        return {
            "workflow_id": workflow_id,
            "status": status,
            "progress": progress,
            "steps": steps.duplicate(),
            "current_step": current_step,
            "errors": errors.duplicate()
        }
    
    func from_dict(data: Dictionary) -> void:
        if data.has("status"): status = data.status
        if data.has("progress"): progress = data.progress
        if data.has("steps"): steps = data.steps.duplicate()
        if data.has("current_step"): current_step = data.current_step
        if data.has("errors"): errors = errors.duplicate()

# Component state management
func update_component_state(component: String, state: Dictionary) -> void:
    if not _component_states.has(component):
        _component_states[component] = ComponentState.new()
    
    _component_states[component].from_dict(state)
    _component_states[component].last_update = Time.get_unix_time_from_system()
    
    emit_signal("state_changed", component, _component_states[component].to_dict())

func get_component_state(component: String) -> Dictionary:
    if not _component_states.has(component):
        return {}
    return _component_states[component].to_dict()

# Pattern state management
func update_pattern_state(pattern_id: String, state: Dictionary) -> void:
    if not _pattern_states.has(pattern_id):
        _pattern_states[pattern_id] = PatternState.new(pattern_id)
    
    _pattern_states[pattern_id].from_dict(state)
    emit_signal("pattern_state_changed", pattern_id, _pattern_states[pattern_id].to_dict())

func get_pattern_state(pattern_id: String) -> Dictionary:
    if not _pattern_states.has(pattern_id):
        return {}
    return _pattern_states[pattern_id].to_dict()

# Workflow state management
func update_workflow_state(workflow_id: String, state: Dictionary) -> void:
    if not _workflow_states.has(workflow_id):
        _workflow_states[workflow_id] = WorkflowState.new(workflow_id)
    
    _workflow_states[workflow_id].from_dict(state)
    emit_signal("workflow_state_changed", workflow_id, _workflow_states[workflow_id].to_dict())

func get_workflow_state(workflow_id: String) -> Dictionary:
    if not _workflow_states.has(workflow_id):
        return {}
    return _workflow_states[workflow_id].to_dict()

# State queries
func get_active_components() -> Array:
    var active := []
    for component in _component_states:
        if _component_states[component].status == "active":
            active.append(component)
    return active

func get_patterns_by_type(pattern_type: String) -> Array:
    var patterns := []
    for pattern in _pattern_states.values():
        if pattern.type == pattern_type:
            patterns.append(pattern.to_dict())
    return patterns

func get_active_workflows() -> Array:
    var active := []
    for workflow in _workflow_states.values():
        if workflow.status != "completed" and workflow.status != "failed":
            active.append(workflow.to_dict())
    return active

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # Clear all states
        _component_states.clear()
        _pattern_states.clear()
        _workflow_states.clear() 