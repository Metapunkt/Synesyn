@tool
extends Node
class_name TaskProcessor

signal task_started(task_id: String)
signal task_completed(task_id: String, result: Dictionary)
signal task_failed(task_id: String, error: String)
signal task_progress(task_id: String, progress: float)

# Task queue and processing
var _task_queue: Array = []
var _active_tasks: Dictionary = {}
var _task_results: Dictionary = {}

# Task priorities
enum Priority { LOW = 0, NORMAL = 1, HIGH = 2, CRITICAL = 3 }

# Task structure
class Task:
    var id: String
    var type: String
    var data: Dictionary
    var priority: int
    var component: String
    var dependencies: Array
    var timeout: float
    var start_time: float
    
    func _init(p_id: String, p_type: String, p_data: Dictionary) -> void:
        id = p_id
        type = p_type
        data = p_data
        priority = Priority.NORMAL
        component = ""
        dependencies = []
        timeout = 30.0  # Default timeout in seconds
        start_time = 0.0
    
    func to_dict() -> Dictionary:
        return {
            "id": id,
            "type": type,
            "data": data.duplicate(),
            "priority": priority,
            "component": component,
            "dependencies": dependencies.duplicate(),
            "timeout": timeout,
            "start_time": start_time
        }

# Process a new task
func process_task(task_data: Dictionary) -> void:
    if not _validate_task_data(task_data):
        push_error("Invalid task data format")
        return
    
    var task_id = _generate_task_id()
    var task = Task.new(task_id, task_data.type, task_data.data)
    
    # Set optional parameters if provided
    if task_data.has("priority"):
        task.priority = task_data.priority
    if task_data.has("component"):
        task.component = task_data.component
    if task_data.has("dependencies"):
        task.dependencies = task_data.dependencies
    if task_data.has("timeout"):
        task.timeout = task_data.timeout
    
    _add_task_to_queue(task)
    _process_queue()

# Add task to queue
func _add_task_to_queue(task: Task) -> void:
    # Insert task in priority order
    var inserted = false
    for i in range(_task_queue.size()):
        if _task_queue[i].priority < task.priority:
            _task_queue.insert(i, task)
            inserted = true
            break
    
    if not inserted:
        _task_queue.append(task)

# Process the task queue
func _process_queue() -> void:
    if _task_queue.is_empty():
        return
    
    var tasks_to_remove = []
    
    # Check for tasks that can be started
    for task in _task_queue:
        if _can_start_task(task):
            _start_task(task)
            tasks_to_remove.append(task)
    
    # Remove started tasks from queue
    for task in tasks_to_remove:
        _task_queue.erase(task)

# Check if a task can be started
func _can_start_task(task: Task) -> bool:
    # Check dependencies
    for dep_id in task.dependencies:
        if not _task_results.has(dep_id):
            return false
    return true

# Start a task
func _start_task(task: Task) -> void:
    task.start_time = Time.get_unix_time_from_system()
    _active_tasks[task.id] = task
    
    emit_signal("task_started", task.id)
    
    # Start timeout monitoring
    _start_timeout_monitoring(task)
    
    # Execute task based on type
    match task.type:
        "semantic_analysis":
            _execute_semantic_task(task)
        "visual_processing":
            _execute_visual_task(task)
        "pattern_integration":
            _execute_integration_task(task)
        _:
            _execute_generic_task(task)

# Task execution methods
func _execute_semantic_task(task: Task) -> void:
    # Implementation will delegate to SynTree
    pass

func _execute_visual_task(task: Task) -> void:
    # Implementation will delegate to Synpunkt
    pass

func _execute_integration_task(task: Task) -> void:
    # Delegate to SynAxes via the orchestrator's component interface.
    var tree := Engine.get_main_loop() as SceneTree
    if not tree:
        _fail_task(task.id, "No scene tree available")
        return

    # Walk up to find the Orchestrator (our sibling under the same parent).
    var orchestrator_node: Node = null
    if get_parent():
        orchestrator_node = get_parent()

    if orchestrator_node and orchestrator_node is Orchestrator:
        var synaxes_iface = orchestrator_node._components.get("synaxes")
        if synaxes_iface:
            synaxes_iface.send_command({
                "type": "discover_patterns",
                "data": task.data,
            })
            # The interface emits task_completed / task_failed — we bridge to ours.
            if synaxes_iface.has_signal("task_completed"):
                var on_done := func(_tid: String, result: Dictionary) -> void:
                    _complete_task(task.id, result)
                synaxes_iface.task_completed.connect(on_done, CONNECT_ONE_SHOT)
            if synaxes_iface.has_signal("task_failed"):
                var on_fail := func(_tid: String, error: String) -> void:
                    _fail_task(task.id, error)
                synaxes_iface.task_failed.connect(on_fail, CONNECT_ONE_SHOT)
        else:
            _fail_task(task.id, "SynAxes interface not registered in orchestrator")
    else:
        _fail_task(task.id, "Orchestrator not available for SynAxes delegation")

func _execute_generic_task(task: Task) -> void:
    # Handle unknown task types
    _complete_task(task.id, {"status": "unknown_task_type"})

# Task completion handling
func _complete_task(task_id: String, result: Dictionary) -> void:
    if _active_tasks.has(task_id):
        var task = _active_tasks[task_id]
        _task_results[task_id] = result
        _active_tasks.erase(task_id)
        
        emit_signal("task_completed", task_id, result)
        
        # Process queue in case tasks are waiting on this one
        _process_queue()

# Task failure handling
func _fail_task(task_id: String, error: String) -> void:
    if _active_tasks.has(task_id):
        _active_tasks.erase(task_id)
        emit_signal("task_failed", task_id, error)
        
        # Process queue in case we need to handle other tasks
        _process_queue()

# Timeout monitoring
func _start_timeout_monitoring(task: Task) -> void:
    var timer = Timer.new()
    add_child(timer)
    timer.wait_time = task.timeout
    timer.one_shot = true
    timer.timeout.connect(_on_task_timeout.bind(task.id))
    timer.start()

func _on_task_timeout(task_id: String) -> void:
    if _active_tasks.has(task_id):
        _fail_task(task_id, "Task timed out")

# Utility functions
func _generate_task_id() -> String:
    return str(randi()) + "_" + str(Time.get_unix_time_from_system())

func _validate_task_data(data: Dictionary) -> bool:
    return data.has("type") and data.has("data")

# Progress reporting
func report_progress(task_id: String, progress: float) -> void:
    if _active_tasks.has(task_id):
        emit_signal("task_progress", task_id, progress)

func get_task_status(task_id: String) -> Dictionary:
    if _active_tasks.has(task_id):
        return _active_tasks[task_id].to_dict()
    if _task_results.has(task_id):
        return _task_results[task_id]
    return {}

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # Clean up any active tasks
        for task_id in _active_tasks:
            _fail_task(task_id, "System shutdown")
        _task_queue.clear()
        _task_results.clear() 