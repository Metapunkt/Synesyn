extends Object
class_name ActionDispatcher

# Dispatches agent action requests to components/game world (via ToolRegistry).
# Implements SLOP /actions endpoint logic.

# --- Dependencies ---
var tool_registry # : ToolRegistry - Injected via constructor
var audit_logger # : AuditLogger - Injected via constructor
var task_queue # : TaskQueue - Injected via constructor
var agent_registry = null # : AgentRegistry (optional; used for role/tool enforcement)
var role_policy = null # : RolePolicy (optional)
const CustomHTTPResponse = preload("res://addons/metapunkt/Networking/SLOPServer/HTTPResponse.gd") # Added
const ToolCallSchema = preload("res://addons/synesyn_core/scripts/tool_call_schema.gd")

# --- Initialization ---
func _init(p_tool_registry = null, p_audit_logger = null, p_task_queue = null):
	tool_registry = p_tool_registry
	audit_logger = p_audit_logger
	task_queue = p_task_queue
	if not tool_registry:
		push_error("ActionDispatcher initialized without a ToolRegistry!")
	if not task_queue:
		push_error("ActionDispatcher initialized without a TaskQueue!") # Need task queue now
	if not audit_logger:
		push_warning("ActionDispatcher initialized without an AuditLogger.")

func set_agent_registry(p_agent_registry) -> void:
	agent_registry = p_agent_registry

func set_role_policy(p_role_policy) -> void:
	role_policy = p_role_policy

# --- Public API ---

# Called directly by agent logic potentially, or via SLOP endpoint
# Returns either the direct result (sync) or a task info dict (async)
func dispatch_action(agent_id: String, tool_name: String, args: Dictionary, user_id: String, scopes: Array) -> Dictionary:
	# v1: role/tool allowlists (best-effort). If we cannot resolve an agent definition, allow.
	if role_policy and agent_registry and not agent_id.strip_edges().is_empty():
		var agent = agent_registry.get_agent_instance(agent_id)
		if agent and agent.definition:
			var all_tools: Array[String] = []
			if tool_registry and tool_registry.has_method("list_tool_names"):
				all_tools = tool_registry.list_tool_names()
			var decision = role_policy.is_tool_allowed(agent.definition, tool_name, all_tools)
			if not bool(decision.get("ok", true)):
				var turn_id_deny := _current_turn_id()
				var call_deny := ToolCallSchema.make_call(tool_name, args, {"agent_id": agent_id, "user_id": user_id, "turn_id": turn_id_deny, "scopes": scopes})
				_emit_orchestration(
					"tool.denied",
					{
						"call": call_deny,
						"agent_id": agent_id,
						"tool_name": tool_name,
						"reason": str(decision.get("reason", "denied")),
						"allowed_tools": decision.get("allowed_tools", []),
					},
					user_id
				)
				return {"error": "Tool denied by role policy", "status_code": 403}

	if not tool_registry:
		var err_msg = "ToolRegistry not available"
		_log_audit("dispatch_error", {"agent_id": agent_id, "tool_name": tool_name, "error": err_msg}, user_id)
		return {"error": err_msg, "status_code": 500}
	
	if not task_queue:
		var err_msg = "TaskQueue not available"
		_log_audit("dispatch_error", {"agent_id": agent_id, "tool_name": tool_name, "error": err_msg}, user_id)
		return {"error": err_msg, "status_code": 500}

	# Check if tool exists before checking async status
	var tool_instance = tool_registry.get_tool_details(tool_name)
	if not tool_instance:
		var err_msg = "Tool '%s' not found." % tool_name
		_log_audit("dispatch_error", {"agent_id": agent_id, "tool_name": tool_name, "error": err_msg}, user_id)
		return {"error": err_msg, "status_code": 404}

	# --- Handle Async vs Sync ---
	if tool_registry.is_tool_async(tool_name):
		var turn_id := _current_turn_id()
		var sid := str(audit_logger.default_session_id).strip_edges() if audit_logger else ""
		var call := ToolCallSchema.make_call(
			tool_name,
			args,
			{"agent_id": agent_id, "user_id": user_id, "turn_id": turn_id, "scopes": scopes, "session_id": sid}
		)
		_emit_orchestration("tool.call", {"call": call, "mode": "async"}, user_id)
		_emit_orchestration("agent.action", {"agent_id": agent_id, "tool_name": tool_name, "mode": "async", "turn_id": turn_id}, user_id)
		# Submit to Task Queue
		# Create callable for ActionDispatcher._execute_tool_task (captures agent_id for structured logging).
		var callable_target = Callable(self, "_execute_tool_task")
		var task_args = [
			agent_id,
			tool_name,
			args,
			user_id,
			scopes,
			turn_id,
			str(call.get("call_id", "")),
			sid,
			str(args.get("workflow_id", "")),
			str(args.get("model_id", "")),
		]
		
		var task_id = task_queue.submit_task(callable_target, task_args, user_id)
		
		_log_audit("action_submitted_async", {"agent_id": agent_id, "tool_name": tool_name, "task_id": task_id}, user_id)
		_emit_orchestration("tool.call", {"call": call, "task_id": task_id, "mode": "async"}, user_id)
		# Return task info and indicate acceptance (HTTP 202)
		return {
			"task_id": task_id,
			"status": "PENDING",
			"message": "Action submitted for asynchronous execution.",
			"status_code": 202 # Accepted
		}
	else:
		var turn_id := _current_turn_id()
		var call := ToolCallSchema.make_call(tool_name, args, {"agent_id": agent_id, "user_id": user_id, "turn_id": turn_id, "scopes": scopes})
		_emit_orchestration("tool.call", {"call": call, "mode": "sync"}, user_id)
		_emit_orchestration("agent.action", {"agent_id": agent_id, "tool_name": tool_name, "mode": "sync", "turn_id": turn_id}, user_id)
		# Execute Synchronously
		# CRITICAL: This await is essential for proper async tool execution
		# Tools like SynTree use async internally but should be treated as sync
		# at the ActionDispatcher level to return direct results
		var sid := str(audit_logger.default_session_id).strip_edges() if audit_logger else ""
		var result = await tool_registry.execute_tool(
			tool_name,
			args,
			user_id,
			scopes,
			{
				"agent_id": agent_id,
				"call_id": str(call.get("call_id", "")),
				"turn_id": turn_id,
				"session_id": sid,
				"workflow_id": str(args.get("workflow_id", "")),
				"model_id": str(args.get("model_id", "")),
			}
		)
		_log_audit("action_executed_sync", {"agent_id": agent_id, "tool_name": tool_name, "result_keys": result.keys() if result is Dictionary else []}, user_id)
		if ToolCallSchema.is_envelope(result) and not bool((result as Dictionary).get("ok", true)):
			_emit_orchestration("tool.error", {"call": call, "error": (result as Dictionary).get("error_obj", {}), "turn_id": turn_id}, user_id)
		elif result is Dictionary and (result as Dictionary).has("error"):
			_emit_orchestration("tool.error", {"call": call, "error": {"message": str((result as Dictionary).get("error"))}, "turn_id": turn_id}, user_id)
		else:
			var keys: Array = result.keys() if result is Dictionary else []
			_emit_orchestration("tool.result", {"call": call, "result_keys": keys, "turn_id": turn_id}, user_id)
		# Return result directly (HTTP 200)
		return {
			"result": result,
			"status_code": 200 # OK
		}

func _execute_tool_task(
	agent_id: String,
	tool_name: String,
	args: Dictionary,
	user_id: String,
	scopes: Array,
	turn_id: String = "",
	call_id: String = "",
	session_id: String = "",
	workflow_id: String = "",
	model_id: String = ""
):
	# Used only by TaskQueue/TaskRunner (async tools). Keep signature stable.
	return await tool_registry.execute_tool(
		tool_name,
		args,
		user_id,
		scopes,
		{
			"agent_id": agent_id,
			"call_id": call_id,
			"turn_id": turn_id,
			"session_id": session_id,
			"workflow_id": workflow_id,
			"model_id": model_id,
		}
	)

func _emit_orchestration(event_type: String, payload: Dictionary, user_id: String) -> void:
	if audit_logger and audit_logger.has_method("emit_event"):
		audit_logger.emit_event(event_type, payload, user_id, {"component": "metapunkt"})

func _current_turn_id() -> String:
	if audit_logger:
		return str(audit_logger.default_turn_id).strip_edges()
	return ""

# --- ARCHITECTURE-BOUNDARY: SLOP Endpoint Handler ---
func handle_request(method: String, path_segments: Array, request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array):
	var endpoint_path = "/actions" + ("/" + "/".join(path_segments) if not path_segments.is_empty() else "")
	print("ActionDispatcher handling request: %s %s" % [method, endpoint_path])

	# Only POST /actions is currently defined for dispatching actions
	if method == "POST" and path_segments.is_empty():
		_handle_dispatch_action_request(request_data, response, user_id, scopes)
	# TODO: Implement GET /actions/{action_id}/status ? (Requires TaskManager)
	else:
		_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Not Implemented"}, user_id)
		response.send_error(501, "Endpoint not implemented: %s %s" % [method, endpoint_path])


# --- Private Handler Methods ---

func _handle_dispatch_action_request(request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array):
	# Parse request body
	var body_bytes: PackedByteArray = request_data.get("body", PackedByteArray())
	var body_str = body_bytes.get_string_from_utf8()
	
	var json_parser = JSON.new()
	var parse_err_code = json_parser.parse(body_str)
	
	if parse_err_code != OK:
		# Parsing failed, get error details
		var err_line = json_parser.get_error_line()
		var err_msg = json_parser.get_error_message()
		_log_audit("request_error", {"method": "POST", "path": "/actions", "error": "Invalid JSON body", "details": "Line %s: %s" % [err_line, err_msg]}, user_id)
		response.send_error(400, "Invalid JSON body at line %s: %s" % [err_line, err_msg])
		return

	# If we are here, parsing was successful
	var parsed_body_data: Dictionary = json_parser.get_data()

	# Validate input
	var agent_id = parsed_body_data.get("agent_id", "") # Optional? Should agent be implicit?
	var tool_name = parsed_body_data.get("tool_name")
	if not tool_name or not tool_name is String:
		# v1 alias: accept "op" as tool name.
		tool_name = parsed_body_data.get("op")
	var args = parsed_body_data.get("args", {}) # Default to empty args if not provided

	if not tool_name or not tool_name is String:
		_log_audit("request_error", {"method": "POST", "path": "/actions", "error": "Missing/invalid tool_name"}, user_id)
		response.send_error(400, "Missing or invalid 'tool_name' (or 'op') in request body")
		return
	if not args is Dictionary:
		_log_audit("request_error", {"method": "POST", "path": "/actions", "error": "Invalid args format"}, user_id)
		response.send_error(400, "Invalid 'args' format in request body, must be a Dictionary")
		return

	# Dispatch the action (could be sync or async)
	var dispatch_result = await dispatch_action(agent_id, tool_name, args, user_id, scopes)

	# Determine HTTP status code from result
	var status_code = dispatch_result.get("status_code", 500) # Default to 500 if missing
	
	# Prepare response body (remove internal status code)
	var response_body = dispatch_result.duplicate()
	response_body.erase("status_code")

	# Respond with appropriate status and body
	if status_code == 202 and response_body.has("task_id"): # Add Location header for async tasks
		response.add_header("Location: /tasks/%s" % response_body["task_id"])
	response.send_ok(response_body, {}, status_code)


# --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 
