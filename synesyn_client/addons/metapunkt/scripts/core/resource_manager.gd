@tool
extends Node
class_name ResourceManager

signal resource_allocated(component: String, resource_type: String, amount: float)
signal resource_depleted(resource_type: String)
signal resource_released(component: String, resource_type: String, amount: float)

# Resource pool structure
class ResourcePool:
    var total_capacity: float
    var allocated: float
    var reservations: Dictionary  # component -> amount
    
    func _init(capacity: float = 100.0) -> void:
        total_capacity = capacity
        allocated = 0.0
        reservations = {}
    
    func can_allocate(amount: float) -> bool:
        return (allocated + amount) <= total_capacity
    
    func allocate(component: String, amount: float) -> bool:
        if can_allocate(amount):
            if not reservations.has(component):
                reservations[component] = 0.0
            reservations[component] += amount
            allocated += amount
            return true
        return false
    
    func release(component: String) -> float:
        var amount = reservations.get(component, 0.0)
        if amount > 0:
            reservations.erase(component)
            allocated -= amount
        return amount

# Resource pools
var _resource_pools := {
    "cpu": ResourcePool.new(100.0),
    "memory": ResourcePool.new(1024.0),  # MB
    "gpu": ResourcePool.new(100.0)
}

# Component resource tracking
var _component_resources := {}

func allocate_resources(component: String, requirements: Dictionary) -> bool:
    # Validate requirements
    if not _validate_requirements(requirements):
        push_error("Invalid resource requirements format")
        return false
    
    # Check if we can allocate all required resources
    for resource_type in requirements:
        if not _resource_pools.has(resource_type):
            push_error("Unknown resource type: " + resource_type)
            return false
        
        var amount = requirements[resource_type]
        if not _resource_pools[resource_type].can_allocate(amount):
            emit_signal("resource_depleted", resource_type)
            return false
    
    # If we can allocate all, do so
    for resource_type in requirements:
        var amount = requirements[resource_type]
        if _resource_pools[resource_type].allocate(component, amount):
            emit_signal("resource_allocated", component, resource_type, amount)
        else:
            # This shouldn't happen since we checked earlier
            push_error("Failed to allocate " + resource_type + " for " + component)
            return false
    
    # Track allocations for the component
    if not _component_resources.has(component):
        _component_resources[component] = {}
    for resource_type in requirements:
        _component_resources[component][resource_type] = requirements[resource_type]
    
    return true

func release_resources(component: String) -> void:
    if not _component_resources.has(component):
        return
    
    for resource_type in _component_resources[component]:
        var pool = _resource_pools.get(resource_type)
        if pool:
            var amount = pool.release(component)
            if amount > 0:
                emit_signal("resource_released", component, resource_type, amount)
    
    _component_resources.erase(component)

func get_available_resources() -> Dictionary:
    var available := {}
    for type in _resource_pools:
        var pool = _resource_pools[type]
        available[type] = pool.total_capacity - pool.allocated
    return available

func _validate_requirements(requirements: Dictionary) -> bool:
    if requirements.is_empty():
        return false
    
    for resource_type in requirements:
        if not (requirements[resource_type] is float or requirements[resource_type] is int):
            return false
        if requirements[resource_type] <= 0:
            return false
    
    return true

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # Release all resources
        var components = _component_resources.keys()
        for component in components:
            release_resources(component) 