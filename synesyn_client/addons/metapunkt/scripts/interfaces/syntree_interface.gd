@tool
extends "base_interface.gd"

var _plugin_instance = null
var _conversation_manager = null

func _init() -> void:
    super._init("syntree")

func setup(plugin_script: GDScript) -> void:
    _plugin_instance = plugin_script.new()
    
    # Wait for plugin to initialize
    await Engine.get_main_loop().process_frame
    
    # Get conversation manager
    if _plugin_instance.has_method("get_conversation_manager"):
        _conversation_manager = _plugin_instance.get_conversation_manager()
        if _conversation_manager:
            _connect_signals()
            _update_status("status", "active")
        else:
            push_error("SynTree: Failed to get conversation manager")
            _update_status("status", "error")
            _update_status("error", "Failed to get conversation manager")
    else:
        push_error("SynTree: Plugin missing required method")
        _update_status("status", "error")
        _update_status("error", "Plugin missing required method")

func send_command(command: Dictionary) -> void:
    if not _validate_command(command):
        push_error("SynTree: Invalid command format")
        return
    
    match command.type:
        "semantic_analysis":
            _handle_semantic_analysis(command.data)
        "pattern_extraction":
            _handle_pattern_extraction(command.data)
        "tool_operation":
            _handle_tool_operation(command.data)
        _:
            push_error("SynTree: Unknown command type: " + command.type)

func _connect_signals() -> void:
    if _conversation_manager:
        if _conversation_manager.has_signal("conversation_updated"):
            _conversation_manager.conversation_updated.connect(_on_conversation_updated)
        if _conversation_manager.has_signal("operation_failed"):
            _conversation_manager.operation_failed.connect(_on_operation_failed)

func _handle_semantic_analysis(data: Dictionary) -> void:
    if not _conversation_manager:
        push_error("SynTree: Conversation manager not available")
        return
    
    if not data.has("prompt"):
        push_error("SynTree: Semantic analysis requires prompt")
        return
    
    var thread_name = data.get("thread", "")
    var result = await _conversation_manager.chat(data.prompt, thread_name)
    
    if result.success:
        emit_signal("task_completed", data.get("task_id", ""), {
            "type": "semantic_analysis",
            "result": result.response
        })
    else:
        emit_signal("task_failed", data.get("task_id", ""), result.error)

func _handle_pattern_extraction(data: Dictionary) -> void:
    # Implementation pending SynTree pattern extraction capability
    push_error("SynTree: Pattern extraction not implemented yet")
    emit_signal("task_failed", data.get("task_id", ""), "Pattern extraction not implemented")

func _handle_tool_operation(data: Dictionary) -> void:
    # Implementation pending SynTree tool management capability
    push_error("SynTree: Tool operations not implemented yet")
    emit_signal("task_failed", data.get("task_id", ""), "Tool operations not implemented")

func _on_conversation_updated(thread_name: String) -> void:
    _update_status("last_conversation", thread_name)
    _update_status("last_activity", Time.get_unix_time_from_system())

func _on_operation_failed(operation: String, error: String, details: String) -> void:
    _update_status("last_error", {
        "operation": operation,
        "error": error,
        "details": details,
        "timestamp": Time.get_unix_time_from_system()
    })
    
    emit_signal("task_failed", "", error) 