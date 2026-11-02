@tool
extends Node
class_name EndpointHandler

# Preload module scripts
# --- ARCHITECTURE-BOUNDARY: Module Preloads ---
const AgentRegistry = preload("res://addons/metapunkt/Core/AgentRegistry/AgentRegistry.gd")
# Restore SensorInterface preload
const SensorInterface = preload("res://addons/metapunkt/Core/SensorInterface/SensorInterface.gd")
const DecisionLogicManager = preload("res://addons/metapunkt/Core/DecisionLogicManager/DecisionLogicManager.gd")
const ActionDispatcher = preload("res://addons/metapunkt/Core/ActionDispatcher/ActionDispatcher.gd")
const ShortTermMemory = preload("res://addons/metapunkt/Memory/ShortTermMemory.gd")
const LongTermMemoryClient = preload("res://addons/metapunkt/Memory/LongTermMemoryClient.gd")
const ToolRegistry = preload("res://addons/metapunkt/Tools/ToolRegistry.gd")
# Restore TaskManager preloads
const TaskQueue = preload("res://addons/metapunkt/TaskManager/TaskQueue.gd")
const TaskRunner = preload("res://addons/metapunkt/TaskManager/TaskRunner.gd")
const AuditLogger = preload("res://addons/metapunkt/Audit/AuditLogger.gd")
const PaymentClient = preload("res://addons/metapunkt/Payments/PaymentClient.gd")
const AgentManager = preload("res://addons/metapunkt/Core/AgentManager.gd")
const HubEventsClient = preload("res://addons/metapunkt/Networking/HubEventsClient.gd")
const RolePolicy = preload("res://addons/metapunkt/Core/Security/RolePolicy.gd")

# Preload OUR custom server/response classes
const CustomHTTPServer = preload("res://addons/metapunkt/Networking/SLOPServer/HTTPServer.gd")
const CustomHTTPResponse = preload("res://addons/metapunkt/Networking/SLOPServer/HTTPResponse.gd")
# --- /ARCHITECTURE-BOUNDARY: Module Preloads ---


# Routes incoming SLOP requests to appropriate modules.
# MUST extract user context (ID, scopes) and perform authorization.

# References to other modules (will need to be set up)
# --- ARCHITECTURE-BOUNDARY: Module References ---
var agent_registry : AgentRegistry
# Restore SensorInterface variable and type hint
var sensor_interface : SensorInterface 
var decision_logic_manager : DecisionLogicManager
var action_dispatcher : ActionDispatcher
var short_term_memory : ShortTermMemory
var long_term_memory_client : LongTermMemoryClient
var tool_registry : ToolRegistry
# Restore TaskManager variables and type hints
var task_queue : TaskQueue
var task_runner : TaskRunner 
var audit_logger : AuditLogger
var payments_client : PaymentClient
var agent_manager : AgentManager
var hub_events_client : HubEventsClient
var role_policy : RolePolicy
# --- /ARCHITECTURE-BOUNDARY: Module References ---

# Server instance - Use our custom server class now
var server: CustomHTTPServer

# App-facing hooks + event stream
signal orchestration_event(event: Dictionary)

# Default configuration 
var listen_host: String = "127.0.0.1"
var listen_port: int = 8080

var last_listen_error: int = OK
var last_listen_error_message: String = ""

const METAPUNKT_API_VERSION := "v0"
const METAPUNKT_VERSION := "0.1.0"
const LOCALHOST_ONLY := true

# Optional auth (v0): local shared-secret bearer token.
# This is intentionally simple; future work can delegate verification to the Hub.
var auth_mode: String = "no-auth" # "no-auth" | "auth-required"
var auth_token: String = ""       # used when auth_mode == "auth-required"
var auth_verify_via_hub: bool = false


func _init():
	# Use custom server instantiation
	server = CustomHTTPServer.new()
	add_child(server) # Add server to tree so _process runs


func setup_modules(modules: Dictionary):
	"""Receives and stores references to all necessary modules."""
	print("EndpointHandler: Setting up modules from external source...")
	agent_registry = modules.get("agent_registry")
	sensor_interface = modules.get("sensor_interface")
	decision_logic_manager = modules.get("decision_logic_manager")
	action_dispatcher = modules.get("action_dispatcher")
	short_term_memory = modules.get("short_term_memory")
	long_term_memory_client = modules.get("long_term_memory_client")
	tool_registry = modules.get("tool_registry")
	task_queue = modules.get("task_queue")
	task_runner = modules.get("task_runner")
	audit_logger = modules.get("audit_logger")
	payments_client = modules.get("payments_client")
	agent_manager = modules.get("agent_manager")
	hub_events_client = modules.get("hub_events_client")
	role_policy = modules.get("role_policy")
	print("EndpointHandler: All modules assigned.")
	if audit_logger and audit_logger.has_signal("event_emitted"):
		if not audit_logger.event_emitted.is_connected(_on_audit_event_emitted):
			audit_logger.event_emitted.connect(_on_audit_event_emitted)
	if hub_events_client and hub_events_client.has_signal("hub_event"):
		if not hub_events_client.hub_event.is_connected(_on_hub_event_received):
			hub_events_client.hub_event.connect(_on_hub_event_received)
	if action_dispatcher and agent_registry and action_dispatcher.has_method("set_agent_registry"):
		action_dispatcher.set_agent_registry(agent_registry)
	if action_dispatcher and role_policy and action_dispatcher.has_method("set_role_policy"):
		action_dispatcher.set_role_policy(role_policy)

func _on_audit_event_emitted(evt: Dictionary) -> void:
	orchestration_event.emit(evt)

func _on_hub_event_received(evt: Dictionary) -> void:
	# Forward hub events to host apps through the same event stream.
	orchestration_event.emit(evt)

# --- Minimal app-facing hooks (in-process; avoids HTTP) ---
func spawn_agent(definition_path: String, owner_user_id: String = "") -> Dictionary:
	if not agent_registry:
		return {"ok": false, "error": "AgentRegistry not initialized"}
	if definition_path.strip_edges().is_empty():
		return {"ok": false, "error": "definition_path is required"}
	if not ResourceLoader.exists(definition_path):
		return {"ok": false, "error": "definition_path not found"}
	var def = load(definition_path)
	if not def:
		return {"ok": false, "error": "Failed to load AgentDefinition"}
	# Guard: users sometimes paste a behavior tree path here; give a precise error.
	if not (def is AgentDefinition):
		return {"ok": false, "error": "definition_path must point to an AgentDefinition resource (.tres); got %s" % def.get_class()}

	var agent = await agent_registry.create_agent_from_definition(def, owner_user_id)
	if not agent:
		var reason := ""
		# Godot 4: Object has no has_variable(); just read and treat missing as empty.
		if agent_registry:
			reason = str(agent_registry.get("last_creation_error")).strip_edges()
		return {"ok": false, "error": ("Agent creation failed" + (": %s" % reason if not reason.is_empty() else ""))}
	return {"ok": true, "agent_id": agent.agent_id}

func stop_agent(agent_id: String, owner_user_id: String = "") -> Dictionary:
	if not agent_registry:
		return {"ok": false, "error": "AgentRegistry not initialized"}
	var ok := agent_registry.delete_agent(agent_id, owner_user_id) if agent_registry.has_method("delete_agent") else false
	if not ok:
		return {"ok": false, "error": "Agent not found"}
	return {"ok": true}

func get_agents() -> Array:
	if not agent_registry:
		return []
	return agent_registry.get_all_agent_instances()

func get_agent_status(agent_id: String) -> Dictionary:
	if not agent_registry:
		return {"ok": false, "error": "AgentRegistry not initialized"}
	var a = agent_registry.get_agent_instance(agent_id)
	if not a:
		return {"ok": false, "error": "Agent not found"}
	return {"ok": true, "status": a.get_status_info()}

func call_tool(agent_id: String, tool_name: String, args: Dictionary, user_id: String = "", scopes: Array = []) -> Dictionary:
	if not action_dispatcher:
		return {"ok": false, "error": "ActionDispatcher not initialized"}
	return await action_dispatcher.dispatch_action(agent_id, tool_name, args, user_id, scopes)


func _ready():
	# v1: if no external composition root provided modules, create a safe default set.
	if not audit_logger:
		audit_logger = AuditLogger.new()
		add_child(audit_logger)
	# Load optional auth config (best-effort; default is open).
	if ResourceLoader.exists("res://addons/synesyn_core/scripts/runtime_config.gd"):
		var cfg: Dictionary = RuntimeConfig.load_config()
		var apps_any: Variant = cfg.get("apps", {})
		if typeof(apps_any) == TYPE_DICTIONARY:
			var apps: Dictionary = apps_any
			var mp_any: Variant = apps.get("metapunkt", {})
			if typeof(mp_any) == TYPE_DICTIONARY:
				var mp: Dictionary = mp_any
				var m := str(mp.get("auth_mode", "no-auth")).strip_edges().to_lower()
				# Back-compat: accept old values ("open"/"required") as aliases.
				if m == "auth-required" or m == "required":
					auth_mode = "auth-required"
				else:
					auth_mode = "no-auth"
				auth_token = str(mp.get("auth_token", "")).strip_edges()
				auth_verify_via_hub = bool(mp.get("auth_verify_via_hub", false))
	if not role_policy:
		role_policy = RolePolicy.new()
		role_policy.load_override_from_user()
	if not task_queue:
		task_queue = TaskQueue.new(audit_logger)
	if not task_runner:
		task_runner = TaskRunner.new(task_queue, audit_logger)
		add_child(task_runner)
	if not tool_registry:
		tool_registry = ToolRegistry.new(audit_logger)
	if not action_dispatcher:
		action_dispatcher = ActionDispatcher.new(tool_registry, audit_logger, task_queue)
	if not sensor_interface:
		sensor_interface = SensorInterface.new(audit_logger)
	if not agent_manager:
		agent_manager = AgentManager.new()
		add_child(agent_manager)
	if not decision_logic_manager:
		# Use this EndpointHandler as runner parent so runner Nodes are attached safely.
		decision_logic_manager = DecisionLogicManager.new(action_dispatcher, audit_logger, sensor_interface, self)
	if not short_term_memory:
		short_term_memory = ShortTermMemory.new(audit_logger)
	if not long_term_memory_client:
		long_term_memory_client = LongTermMemoryClient.new(audit_logger)
	if not agent_registry:
		agent_registry = AgentRegistry.new(audit_logger, action_dispatcher, sensor_interface, short_term_memory, decision_logic_manager)
	if agent_manager and agent_manager.has_method("setup"):
		agent_manager.setup(agent_registry, audit_logger)
	if action_dispatcher and action_dispatcher.has_method("set_agent_registry"):
		action_dispatcher.set_agent_registry(agent_registry)
	if action_dispatcher and action_dispatcher.has_method("set_role_policy"):
		action_dispatcher.set_role_policy(role_policy)

	# Optional: hub WS subscription for cross-app reactivity (best-effort).
	if not hub_events_client:
		hub_events_client = HubEventsClient.new()
		add_child(hub_events_client)
		hub_events_client.hub_event.connect(_on_hub_event_received)
		# Default subscription: warnings + job lifecycle (keeps noise low).
		hub_events_client.subscribe(["sensor.warning", "job.progress", "job.completed", "job.failed"])
		if audit_logger:
			hub_events_client.connect_to_hub(audit_logger.hub_base_url)

	# Module instantiation is now handled externally.
	# The server can be started immediately.
	# --- START THE SERVER ---
	start_server() # Call with default host/port

	# Best-effort: if a host app has already established a Synesyn session id, attach it
	# so Metapunkt-internal audit events also carry a session id (even without inbound HTTP calls).
	if audit_logger and ResourceLoader.exists("res://addons/synesyn_core/scripts/synesyn_session.gd"):
		# Prefer explicit host identity if provided, otherwise keep existing default.
		var sid := SynesynSession.get_or_create_session_id("metapunkt")
		if not sid.is_empty():
			audit_logger.default_session_id = sid


func _exit_tree():
	# Restore stop_server call
	stop_server()


func start_server(host: String = "127.0.0.1", port: int = 8080):
	# Restore full start_server logic using custom server
	if server.is_listening():
		print("SLOP server already running on %s:%d" % [server.get_listen_host(), server.get_listen_port()])
		return

	last_listen_error = OK
	last_listen_error_message = ""

	# v0 stability: local control plane only
	if LOCALHOST_ONLY and host != "127.0.0.1":
		push_warning("Metapunkt SLOP server is localhost-only in v0; overriding host '%s' -> '127.0.0.1'" % host)
	listen_host = "127.0.0.1" if LOCALHOST_ONLY else host
	listen_port = port
	print("Starting SLOP server on %s:%d" % [listen_host, listen_port])
	
	if not server.is_connected("request_received", Callable(self, "_on_request_received")):
		server.connect("request_received", Callable(self, "_on_request_received"))

	# v0 stability: if the port is already taken (common when editor tool + runtime both run),
	# auto-fallback to the next free port in a small window.
	var start_port := port
	var max_tries := 11 # 8080..8090 inclusive
	var last_err: int = OK
	for i in range(max_tries):
		var p := start_port + i
		var err: int = server.listen(p, listen_host)
		if err == OK:
			listen_port = p
			if p != start_port:
				push_warning("Metapunkt SLOP port %d was busy; fell back to %d" % [start_port, p])
			return
		last_err = err
		# Retry only for "already in use"; otherwise break fast.
		if err != ERR_ALREADY_IN_USE:
			break

	last_listen_error = last_err
	last_listen_error_message = error_string(last_err)
	printerr("Error starting SLOP server: %s" % last_err)
	server.stop() # Ensure it's stopped if listen failed


func stop_server():
	# Restore full stop_server logic using custom server
	if server.is_listening():
		print("Stopping SLOP server")
		server.stop()

# Modified to accept request_data Dictionary and custom HTTPResponse
func _on_request_received(request_data: Dictionary, response: CustomHTTPResponse):
	# --- Request Parsing (Data already parsed by HTTPServer) ---
	var path: String = request_data.get("request_uri", "/")
	var method: String = request_data.get("request_method", "GET")
	var headers: Dictionary = request_data.get("request_headers_as_dictionary", {})
	var body: PackedByteArray = request_data.get("body", PackedByteArray())
	
	# --- User Context Extraction (Using parsed headers) ---
	var user_id: String = headers.get("x-user-id", "") # Header keys are lowercased by parser
	var auth_header: String = headers.get("authorization", "")
	var scope_header: String = headers.get("x-slop-scope", "")
	var session_id: String = headers.get("x-session-id", "")
	var turn_id: String = headers.get("x-turn-id", "")
	var scopes: Array = []
	if not scope_header.is_empty():
		scopes = scope_header.split(",")
	# Normalize scopes
	var scopes_norm: Array = []
	for s_any in scopes:
		var s := str(s_any).strip_edges()
		if not s.is_empty():
			scopes_norm.append(s)
	scopes = scopes_norm

	# --- Optional auth enforcement (v0) ---
	var auth_res := await _enforce_optional_auth_async(user_id, auth_header)
	if not bool(auth_res.get("ok", false)):
		var sc := int(auth_res.get("status", 403))
		var msg := str(auth_res.get("error", "forbidden"))
		response.send_error(sc, msg)
		return
	# Apply potentially-normalized user_id (e.g. guest in open mode)
	user_id = str(auth_res.get("user_id", user_id)).strip_edges()

	# Optional: allow callers to attach a session id for substrate alignment.
	# This is best-effort; if not set, AuditLogger will omit session_id.
	if audit_logger and not session_id.is_empty():
		audit_logger.default_session_id = session_id.strip_edges()
	if audit_logger and not turn_id.is_empty():
		audit_logger.default_turn_id = turn_id.strip_edges()
	
	print("Received SLOP request: %s %s (User: %s, Scopes: %s)" % [method, path, user_id if user_id else "N/A", scopes])

	# --- Authorization --- 
	# NOTE: Needs adjustment as we pass the custom response object now
	if not _is_authorized(path, method, scopes):
		response.send_error(403) # 403 Forbidden
		return

	# --- Routing ---
	var path_segments = path.lstrip("/").split("/")
	if path_segments.is_empty() or path_segments[0].is_empty():
		response.send_ok({"service": "metapunkt", "api": METAPUNKT_API_VERSION, "version": METAPUNKT_VERSION})
		return

	var base_route = path_segments[0]
	
	# NOTE: All handlers now need to work with the custom response object
	# and potentially just the request_data dictionary (if they were relying 
	# on specific HTTPRequest methods not present in the dictionary)
	match base_route:
		"version":
			response.send_ok({
				"service": "metapunkt",
				"api": METAPUNKT_API_VERSION,
				"version": METAPUNKT_VERSION,
				"endpoints": ["/agents", "/actions", "/tools", "/models", "/tasks", "/queue", "/sensors", "/roles", "/status", "/version"],
				"schemas": {"tool_call": 1, "event_envelope": 1},
			})
		"roles":
			_handle_roles_request(method, path_segments.slice(1), request_data, response, user_id, scopes)
		"agents":
			if agent_registry:
				# TODO: Update agent_registry.handle_request signature if needed
				agent_registry.handle_request(method, path_segments.slice(1), request_data, response, user_id, scopes)
			else:
				response.send_error(500, "AgentRegistry not initialized")
		"sensors":
			if sensor_interface:
				# SensorInterface already updated to remove type hints
				sensor_interface.handle_request(method, path_segments.slice(1), request_data, response, user_id, scopes)
			else:
				response.send_error(500, "SensorInterface not initialized")
		"models":
			if decision_logic_manager:
				# TODO: Update decision_logic_manager.handle_request signature if needed
				decision_logic_manager.handle_request(method, path_segments.slice(1), request_data, response, user_id, scopes)
			else:
				response.send_error(500, "DecisionLogicManager not initialized")
		"actions":
			if action_dispatcher:
				# TODO: Update action_dispatcher.handle_request signature if needed
				action_dispatcher.handle_request(method, path_segments.slice(1), request_data, response, user_id, scopes)
			else:
				response.send_error(500, "ActionDispatcher not initialized")
		"memory":
			_handle_memory_request(method, path_segments.slice(1), request_data, response, user_id, scopes)
		"tools":
			if tool_registry:
				# TODO: Update tool_registry.handle_request signature if needed
				tool_registry.handle_request(method, path_segments.slice(1), request_data, response, user_id, scopes)
			else:
				response.send_error(500, "ToolRegistry not initialized")
		"tasks":
			if task_runner:
				# Call TaskRunner handler, which returns a dictionary
				# NOTE: TaskRunner's handle_request was updated to remove HTTPRequest/Response hints
				# It expects the request_data dictionary and our custom response object now?
				# Let's review TaskRunner.handle_request signature... ok it just takes generic request/response
				var handler_result: Dictionary = task_runner.handle_request(method, path_segments.slice(1), request_data, response, user_id, scopes)
				
				# Extract status code and data/error from the result
				var status_code: int = handler_result.get("status_code", 500) # Default 500
				var response_data = handler_result.get("data")
				var error_message = handler_result.get("error")
				
				# Use the custom response object to send a stable envelope
				if error_message != null:
					var details = {}
					if handler_result.has("task_id"):
						details["task_id"] = handler_result["task_id"]
					response.send_fail(status_code, "task_error", str(error_message), details)
				elif response_data != null:
					response.send_ok(response_data, {}, status_code)
				else:
					response.send_empty(status_code)
			else:
				response.send_error(500, "TaskRunner not initialized")
		"queue":
			if task_queue:
				# TODO: Update task_queue.handle_request signature if needed
				task_queue.handle_request(method, path_segments.slice(1), request_data, response, user_id, scopes)
			else:
				response.send_error(500, "TaskQueue not initialized")
		"audit":
			if audit_logger:
				# TODO: Call audit_logger.handle_request(...) - needs signature update
				response.send_text("Placeholder for /audit endpoint - Handled by AuditLogger") # Placeholder
			else:
				response.send_error(500, "AuditLogger not initialized")
		"pay":
			if payments_client:
				# TODO: Call payments_client.handle_request(...) - needs signature update
				response.send_text("Placeholder for /pay endpoint - Handled by PaymentClient") # Placeholder
			else:
				response.send_error(500, "PaymentClient not initialized")
		"status": # Simple endpoint handled directly
			var modules_ok = {
				"agent_registry": agent_registry != null,
				"sensor_interface": sensor_interface != null,
				"decision_logic_manager": decision_logic_manager != null,
				"action_dispatcher": action_dispatcher != null,
				"short_term_memory": short_term_memory != null,
				"long_term_memory_client": long_term_memory_client != null,
				"tool_registry": tool_registry != null,
				"task_queue": task_queue != null,
				"task_runner": task_runner != null,
				"audit_logger": audit_logger != null,
			}
			response.send_ok({
				"service": "metapunkt",
				"api": METAPUNKT_API_VERSION,
				"version": METAPUNKT_VERSION,
				"listen": {"host": listen_host, "port": listen_port},
				"modules": modules_ok,
			})
		_:
			# Unknown route
			printerr("Unknown SLOP route: %s" % path)
			response.send_fail(404, "not_found", "Unknown route: %s" % path)


func _handle_roles_request(method: String, path_segments: Array, request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array) -> void:
	if not role_policy:
		response.send_error(500, "RolePolicy not initialized")
		return

	if method == "GET" and path_segments.is_empty():
		response.send_ok({"ok": true, "policy": role_policy.get_policy_dict()})
		return

	if method == "POST" and path_segments.is_empty():
		var body_bytes: PackedByteArray = request_data.get("body", PackedByteArray())
		var body_str := body_bytes.get_string_from_utf8()
		var obj := JSON.parse_string(body_str) if not body_str.is_empty() else {}
		if typeof(obj) != TYPE_DICTIONARY:
			response.send_error(400, "Invalid JSON body")
			return
		var d: Dictionary = obj
		var override_any: Variant = d.get("override", {})
		if typeof(override_any) != TYPE_DICTIONARY:
			response.send_error(400, "override must be an object")
			return
		var publish := bool(d.get("publish_to_hub", false))

		var ok := role_policy.save_override_to_user(override_any)
		if not ok:
			response.send_error(500, "Failed to save role policy override")
			return
		role_policy.load_override_from_user()

		var published := {}
		if publish and audit_logger and audit_logger.has_method("hub_create_artifact_inline_json_async"):
			var meta := {
				"provenance": {
					"generated_by": "metapunkt.role_policy",
					"user_id": user_id,
				}
			}
			var res: Dictionary = await audit_logger.hub_create_artifact_inline_json_async("metapunkt.role_policy", role_policy.get_policy_dict(), meta)
			published = res
		response.send_ok({"ok": true, "policy": role_policy.get_policy_dict(), "published": published})
		return

	response.send_error(501, "Endpoint not implemented: %s /roles" % method)


func _is_authorized(path: String, method: String, scopes: Array) -> bool:
	# Restore placeholder logic
	return true

func _enforce_optional_auth_async(user_id_in: String, auth_header_in: String) -> Dictionary:
	var uid := user_id_in.strip_edges()
	var ah := auth_header_in.strip_edges()

	# OPEN: allow everything; ensure a stable user_id for auditing.
	if auth_mode != "auth-required":
		if uid.is_empty():
			uid = "guest"
		return {"ok": true, "user_id": uid}

	# AUTH-REQUIRED: enforce bearer token + explicit user id.
	if ah.is_empty() or not ah.begins_with("Bearer "):
		return {"ok": false, "status": 401, "error": "missing_bearer_token"}
	if uid.is_empty():
		return {"ok": false, "status": 400, "error": "missing_user_id"}

	# Prefer hub verification when enabled.
	if auth_verify_via_hub:
		var vr := await _verify_bearer_via_hub_async(ah, uid)
		if not bool(vr.get("ok", false)):
			return vr
		return {"ok": true, "user_id": uid}

	# Local shared-secret verification (default).
	if auth_token.strip_edges().is_empty():
		# Misconfiguration: auth required but no token configured, and hub verification disabled.
		return {"ok": false, "status": 500, "error": "auth_required_but_token_missing"}
	var token := ah.substr(len("Bearer ")).strip_edges()
	if token != auth_token.strip_edges():
		return {"ok": false, "status": 403, "error": "invalid_token"}
	return {"ok": true, "user_id": uid}

func _verify_bearer_via_hub_async(auth_header_in: String, user_id_in: String) -> Dictionary:
	# Verify the bearer token by calling the Hub (requires hub auth middleware enabled).
	if not audit_logger:
		return {"ok": false, "status": 500, "error": "hub_verify_requires_audit_logger"}
	var base := str(audit_logger.hub_base_url).strip_edges()
	if base.is_empty():
		base = "http://127.0.0.1:17777"
	var url := base.rstrip("/") + "/auth/whoami"
	var http := HTTPRequest.new()
	add_child(http)
	var result: Dictionary = {"ok": false, "status": 503, "error": "hub_verify_request_failed"}
	http.request_completed.connect(func(_rc: int, sc: int, _h: PackedStringArray, b: PackedByteArray):
		var txt := b.get_string_from_utf8()
		var body_any := JSON.parse_string(txt) if not txt.is_empty() else {}
		if sc >= 200 and sc < 300:
			if typeof(body_any) == TYPE_DICTIONARY and bool((body_any as Dictionary).get("ok", false)):
				result = {"ok": true}
			else:
				result = {"ok": false, "status": 403, "error": "hub_verify_denied"}
		elif sc == 400 and typeof(body_any) == TYPE_DICTIONARY and str((body_any as Dictionary).get("error", "")) == "auth_disabled":
			result = {"ok": false, "status": 500, "error": "hub_auth_disabled"}
		elif sc == 401:
			result = {"ok": false, "status": 401, "error": "missing_bearer_token"}
		elif sc == 403:
			result = {"ok": false, "status": 403, "error": "invalid_token"}
		else:
			result = {"ok": false, "status": sc, "error": "hub_verify_http_%d" % sc, "details": body_any}
		if is_instance_valid(http):
			http.queue_free()
	)
	var err := http.request(url, ["Content-Type: application/json", "Authorization: %s" % auth_header_in, "X-User-Id: %s" % user_id_in], HTTPClient.METHOD_GET, "")
	if err != OK:
		if is_instance_valid(http):
			http.queue_free()
		return {"ok": false, "status": 503, "error": "hub_verify_request_failed:%s" % error_string(err)}
	await http.request_completed
	return result


# --- Private Request Handlers --- 
# Modified to accept request_data Dictionary and custom HTTPResponse
func _handle_memory_request(method: String, path_segments: Array, request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array):
	var endpoint_path = "/memory" + ("/" + "/".join(path_segments) if not path_segments.is_empty() else "")
	print("Handling memory request: %s %s" % [method, endpoint_path])
	if path_segments.is_empty():
		response.send_error(400, "Memory type (e.g., /memory/short_term) must be specified.") # 400 Bad Request
		return
	var memory_type = path_segments[0]
	var remaining_path = path_segments.slice(1)
	match memory_type:
		"short_term":
			if short_term_memory:
				# TODO: Update short_term_memory.handle_slop_request signature if needed
				short_term_memory.handle_slop_request(method, remaining_path, request_data, response, user_id, scopes)
			else:
				response.send_error(500, "ShortTermMemory not initialized")
		"long_term":
			if long_term_memory_client:
				# TODO: Update long_term_memory_client.handle_slop_request signature if needed
				long_term_memory_client.handle_slop_request(method, remaining_path, request_data, response, user_id, scopes)
			else:
				response.send_error(500, "LongTermMemoryClient not initialized")
		_:
			_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Unknown memory type"}, user_id)
			response.send_error(404, "Unknown memory type: %s" % memory_type) # 404 Not Found


# --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	# Restore full logic
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 
