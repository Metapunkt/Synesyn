extends Object
class_name ToolRegistry

# Preloads
const ToolInterfaceBase = preload("res://addons/metapunkt/Tools/ToolInterfaceBase.gd")
# --- Known Tool Integration Scripts (Hardcoded for now) ---
const SynTreeInterface = preload("res://addons/metapunkt/Integrations/SynTreeInterface.gd")
const SynaxesInterface = preload("res://addons/metapunkt/Integrations/SynaxesInterface.gd")
const SynpunktInterface = preload("res://addons/metapunkt/Integrations/SynpunktInterface.gd")
const GodotUtilsInterface = preload("res://addons/metapunkt/Integrations/GodotUtilsInterface.gd")
# const ExternalLLMClient = preload("res://addons/metapunkt/Integrations/ExternalLLMClient.gd") # Optional
# const RLPolicyClient = preload("res://addons/metapunkt/Integrations/RLPolicyClient.gd") # Optional
const CustomHTTPResponse = preload("res://addons/metapunkt/Networking/SLOPServer/HTTPResponse.gd")

# Discovers & lists available tools (Synesyn components, Godot utils, external APIs).
# Implements SLOP /tools endpoint logic.

# --- Dependencies ---
var audit_logger # : AuditLogger - Injected via constructor
const ToolCallSchema = preload("res://addons/synesyn_core/scripts/tool_call_schema.gd")

# --- Internal State ---
var _tools: Dictionary = {} # tool_name -> ToolInterfaceBase instance

# --- Initialization ---
func _init(logger = null):
	audit_logger = logger
	if not audit_logger:
		push_warning("ToolRegistry initialized without an AuditLogger.")
	_discover_tools()

# --- Public API ---

# Called by ActionDispatcher to execute a tool
func execute_tool(tool_name: String, args: Dictionary, user_id: String, scopes: Array, ctx: Dictionary = {}) -> Dictionary:
	var tool_instance: ToolInterfaceBase = _tools.get(tool_name)
	if not tool_instance:
		var call_nf := ToolCallSchema.make_call(tool_name, args, {"user_id": user_id, "scopes": scopes, "agent_id": str(ctx.get("agent_id", "")), "call_id": str(ctx.get("call_id", "")), "turn_id": str(ctx.get("turn_id", "")), "session_id": str(ctx.get("session_id", ""))})
		_emit_tool_event("tool.error", call_nf, {"code": "not_found", "message": "Tool not found", "details": tool_name}, user_id)
		return ToolCallSchema.fail(call_nf, "not_found", "Tool not found: %s" % tool_name, {"tool_name": tool_name})

	# TODO: Add authorization check - Can this user/scope use this tool?
	# if not _can_use_tool(tool_name, user_id, scopes):
	#     _log_audit("auth_error", {"tool_name": tool_name, "reason": "Unauthorized"}, user_id)
	#     return {"error": "Unauthorized to use tool: %s" % tool_name}

	var call := ToolCallSchema.make_call(tool_name, args, {
		"user_id": user_id,
		"scopes": scopes,
		"agent_id": str(ctx.get("agent_id", "")),
		"call_id": str(ctx.get("call_id", "")),
		"turn_id": str(ctx.get("turn_id", "")),
		"session_id": str(ctx.get("session_id", "")),
		"workflow_id": str(ctx.get("workflow_id", "")),
		"model_id": str(ctx.get("model_id", "")),
	})
	_emit_tool_event("tool.call", call, {}, user_id)

	var result_any: Variant = null
	# Tool execution (may await internally)
	result_any = await tool_instance.execute_tool(args)

	# Normalize tool result into schema envelope.
	if typeof(result_any) == TYPE_DICTIONARY and (result_any as Dictionary).has("error"):
		var d: Dictionary = result_any
		var msg := str(d.get("error", "Tool error"))
		var env := ToolCallSchema.fail(call, "tool_error", msg, d)
		_emit_tool_event("tool.error", call, {"error_obj": env.get("error_obj", {}), "input_refs": _input_refs_from_call(call)}, user_id)
		return env

	var ok_env := ToolCallSchema.ok(call, result_any)
	_emit_tool_event(
		"tool.result",
		call,
		{
			"result_keys": (result_any as Dictionary).keys() if typeof(result_any) == TYPE_DICTIONARY else [],
			"artifact_refs": _extract_artifact_refs(result_any),
			"input_refs": _input_refs_from_call(call),
			"model_id": str(ctx.get("model_id", "")),
			"workflow_id": str(ctx.get("workflow_id", "")),
		},
		user_id
	)
	return ok_env

## Register an external tool (e.g. from a Capability Pack). Returns true on success.
func register_tool(tool_name: String, tool_instance: ToolInterfaceBase) -> bool:
	if _tools.has(tool_name):
		push_warning("ToolRegistry: tool '%s' already registered; skipping." % tool_name)
		return false
	_tools[tool_name] = tool_instance
	print("ToolRegistry: registered external tool: %s" % tool_name)
	return true

## Unregister a previously registered tool. Returns true if it was present.
func unregister_tool(tool_name: String) -> bool:
	if not _tools.has(tool_name):
		return false
	_tools.erase(tool_name)
	print("ToolRegistry: unregistered tool: %s" % tool_name)
	return true

func list_tool_names() -> Array[String]:
	var out: Array[String] = []
	for k in _tools.keys():
		out.append(str(k))
	return out

# Check if a tool should be run asynchronously
func is_tool_async(tool_name: String) -> bool:
	# TODO: Implement actual logic. Maybe based on tool metadata?
	# 
	# IMPORTANT: SynTree is marked as sync here even though it uses await internally.
	# This allows ActionDispatcher to await the result directly and return it to agents
	# instead of going through the TaskQueue. The tool itself handles async properly
	# via its execute_tool() method which the ActionDispatcher awaits.
	return false  # All tools are synchronous for now

# Called by AgentRegistry or DecisionLogicManager to get tool info?
func get_tool_details(tool_name: String) -> Dictionary:
	var tool_instance: ToolInterfaceBase = _tools.get(tool_name)
	if not tool_instance:
		return {}
	# TODO: Enhance ToolInterfaceBase to provide more details (description, schema)
	return {
		"name": tool_instance.get_tool_name(),
		"description": (tool_instance.get_description() if tool_instance.has_method("get_description") else ""),
		"operations": (tool_instance.get_operations() if tool_instance.has_method("get_operations") else []),
		"input_schema": (tool_instance.get_input_schema() if tool_instance.has_method("get_input_schema") else {}),
		"output_schema": (tool_instance.get_output_schema() if tool_instance.has_method("get_output_schema") else {}),
	}

# --- ARCHITECTURE-BOUNDARY: SLOP Endpoint Handler ---
func handle_request(method: String, path_segments: Array, request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array):
	var endpoint_path = "/tools" + ("/" + "/".join(path_segments) if not path_segments.is_empty() else "")
	print("ToolRegistry handling request: %s %s" % [method, endpoint_path])

	if method == "GET" and path_segments.is_empty():
		_handle_get_tools_list(request_data, response, user_id, scopes)
	elif method == "GET" and path_segments.size() == 1:
		var tool_name = path_segments[0]
		_handle_get_tool_details(request_data, response, user_id, scopes, tool_name)
	else:
		_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Not Implemented"}, user_id)
		response.send_error(501, "Endpoint not implemented: %s %s" % [method, endpoint_path])

# --- Private Handler Methods ---

func _handle_get_tools_list(request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array):
	# TODO: Filter tools based on user_id/scopes if necessary
	var tools_list_data = []
	for tool_name in _tools:
		# if _can_use_tool(tool_name, user_id, scopes):
		var tool_details = get_tool_details(tool_name)
		tools_list_data.append(tool_details)

	_log_audit("list_tools", {"count": tools_list_data.size()}, user_id)
	response.send_ok({"tools": tools_list_data, "count": tools_list_data.size()})


func _handle_get_tool_details(request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array, tool_name: String):
	var tool_instance: ToolInterfaceBase = _tools.get(tool_name)
	if not tool_instance:
		_log_audit("request_error", {"method": "GET", "path": "/tools/" + tool_name, "error": "Not Found"}, user_id)
		response.send_error(404)
		return

	# TODO: Check authorization for viewing tool details?
	# if not _can_use_tool(tool_name, user_id, scopes):
	#     _log_audit("auth_error", {"method": "GET", "path": "/tools/" + tool_name, "reason": "Unauthorized"}, user_id)
	#     response.send_error(403)
	#     return

	var details_data = get_tool_details(tool_name)
	_log_audit("get_tool_details", {"tool_name": tool_name}, user_id)
	response.send_ok(details_data)

# --- Tool Discovery --- 

func _discover_tools():
	print("Discovering Metapunkt tools...")
	_tools.clear()

	# --- Hardcoded Discovery (replace with dynamic later) ---
	var known_tool_scripts = [
		SynTreeInterface,
		SynaxesInterface,
		SynpunktInterface,
		GodotUtilsInterface,
		# ExternalLLMClient, # Uncomment if used
		# RLPolicyClient,     # Uncomment if used
	]

	for tool_script in known_tool_scripts:
		var tool_instance = tool_script.new()
		if tool_instance is ToolInterfaceBase:
			var tool_name = tool_instance.get_tool_name()
			if not tool_name.is_empty() and tool_name != "BaseTool":
				if _tools.has(tool_name):
					push_warning("Tool name collision during discovery: '%s' already exists. Overwriting." % tool_name)
				_tools[tool_name] = tool_instance
				print("- Discovered tool: %s" % tool_name)
			else:
				push_warning("Tool script %s returned invalid name: '%s'" % [tool_script, tool_name])
		else:
			push_warning("Tool script %s does not extend ToolInterfaceBase." % tool_script)

	# TODO: Implement dynamic discovery (e.g., scan `Integrations/` directory for scripts extending ToolInterfaceBase)

	print("Tool discovery complete. Found %d tools." % _tools.size())

# --- Authorization Stubs ---
func _can_use_tool(tool_name: String, user_id: String, scopes: Array) -> bool:
	# TODO: Implement actual authorization logic based on tool requirements, user, scopes
	return true # Placeholder

# --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 

func _emit_tool_event(event_type: String, call: Dictionary, payload: Dictionary, user_id: String) -> void:
	# Substrate logging path: AuditLogger.emit_event forwards to hub /substrate/events.
	if audit_logger and audit_logger.has_method("emit_event"):
		var p := payload.duplicate(true) if payload else {}
		p["call"] = call
		audit_logger.emit_event(event_type, p, user_id, {"component": "metapunkt"})
	else:
		_log_audit(event_type, {"call": call, "payload": payload}, user_id)

func _input_refs_from_call(call: Dictionary) -> Dictionary:
	var refs := {}
	var sid := str(call.get("session_id", "")).strip_edges()
	var tid := str(call.get("turn_id", "")).strip_edges()
	var cid := str(call.get("call_id", "")).strip_edges()
	var wid := str(call.get("workflow_id", "")).strip_edges()
	if not sid.is_empty():
		refs["session_id"] = sid
	if not tid.is_empty():
		refs["turn_id"] = tid
	if not cid.is_empty():
		refs["call_id"] = cid
	if not wid.is_empty():
		refs["workflow_id"] = wid
	return refs

func _extract_artifact_refs(result_any: Variant) -> Array:
	# Best-effort: extract common artifact reference shapes from tool results.
	var refs: Array = []
	if typeof(result_any) != TYPE_DICTIONARY:
		return refs
	var d: Dictionary = result_any
	# Common single artifact
	if d.has("artifact_id") or d.has("uri"):
		var r := {}
		if d.has("artifact_id"):
			r["artifact_id"] = d.get("artifact_id")
		if d.has("uri"):
			r["uri"] = d.get("uri")
		if r.size() > 0:
			refs.append(r)
	# Common list
	if d.has("artifacts") and typeof(d.get("artifacts")) == TYPE_ARRAY:
		for a in d.get("artifacts"):
			if typeof(a) == TYPE_DICTIONARY:
				refs.append(a)
	# Sometimes tools return {ok:true, id, uri, hash} shapes
	if d.has("id") and d.has("uri"):
		refs.append({"artifact_id": d.get("id"), "uri": d.get("uri")})
	return refs
