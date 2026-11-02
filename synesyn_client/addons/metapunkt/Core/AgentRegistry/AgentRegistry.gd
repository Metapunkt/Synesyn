extends Object # Or Node, TBD
class_name AgentRegistry

const _SynterfaceCatalog = preload("res://addons/metapunkt/Core/Ports/synterface_catalog.gd")
const _JsonSchemaValidator = preload("res://addons/metapunkt/Core/Ports/json_schema_validator.gd")
const _AppHostBase = preload("res://addons/metapunkt/Core/Ports/metapunkt_app_host_base.gd")

# Preloads
const AgentInstance = preload("res://addons/metapunkt/Core/AgentRegistry/AgentInstance.gd")
const AgentDefinition = preload("res://addons/metapunkt/Core/AgentRegistry/AgentDefinition.gd")
const CustomHTTPResponse = preload("res://addons/metapunkt/Networking/SLOPServer/HTTPResponse.gd")

# AgentDefinition schema version allowlist
const _AGENTDEF_SCHEMA_V1: String = "metapunkt.agentdef.v1"

# Manages Synesyn agent lifecycle, status, discovery.
# Implements SLOP /agents endpoint logic.

# --- Dependencies ---
var audit_logger # : AuditLogger
var action_dispatcher # : ActionDispatcher
var sensor_interface # : SensorInterface
var short_term_memory # : ShortTermMemory
var decision_logic_manager # : DecisionLogicManager

# --- Internal State ---
var _agents: Dictionary = {} # agent_id -> AgentInstance
var _next_agent_id: int = 1

# If create_agent_from_definition() returns null, this is populated with the latest failure reason
# (used by UI to surface actionable errors).
var last_creation_error: String = ""

# --- Initialization ---
func _init(p_audit_logger = null, p_action_dispatcher = null, p_sensor_interface = null, p_stm = null, p_dlm = null):
	audit_logger = p_audit_logger
	action_dispatcher = p_action_dispatcher
	sensor_interface = p_sensor_interface
	short_term_memory = p_stm
	decision_logic_manager = p_dlm
	# Validate dependencies
	if not audit_logger: push_warning("AgentRegistry initialized without AuditLogger.")
	if not action_dispatcher: push_error("AgentRegistry initialized without ActionDispatcher!")
	if not sensor_interface: push_error("AgentRegistry initialized without SensorInterface!")
	if not short_term_memory: push_error("AgentRegistry initialized without ShortTermMemory!")
	if not decision_logic_manager: push_error("AgentRegistry initialized without DecisionLogicManager!")

# --- Public API ---

# Called by other modules potentially?
func get_agent_instance(agent_id: String) -> AgentInstance:
	return _agents.get(agent_id)

# Called by AgentManager to iterate for ticking
func get_all_agent_instances() -> Array[AgentInstance]:
	var instances: Array[AgentInstance] = []
	for agent_instance in _agents.values():
		if agent_instance is AgentInstance: # Ensure type safety
			instances.append(agent_instance)
	return instances

func delete_agent(agent_id: String, user_id: String = "") -> bool:
	var agent_instance: AgentInstance = _agents.get(agent_id)
	if not agent_instance:
		return false

	agent_instance.shutdown()
	# Release decision logic runner if possible (avoids runner leakage)
	if decision_logic_manager and decision_logic_manager.has_method("release_agent"):
		decision_logic_manager.release_agent(agent_id)

	_agents.erase(agent_id)
	_log_audit("agent_deleted", {"agent_id": agent_id}, user_id)
	if audit_logger and audit_logger.has_method("emit_event"):
		var turn_id := str(audit_logger.default_turn_id).strip_edges() if audit_logger else ""
		audit_logger.emit_event(
			"agent.stopped",
			{"agent_id": agent_id, "turn_id": turn_id},
			user_id,
			{"component": "metapunkt"}
		)
	return true

func create_agent_from_definition(p_definition: AgentDefinition, p_owner_id: String) -> AgentInstance:
	"""
	Creates, initializes, and registers an agent from a definition resource.
	This is the primary method for internal, in-process agent creation.
	Returns the new AgentInstance or null on failure.
	"""
	if not p_definition or not p_definition is AgentDefinition:
		last_creation_error = "Invalid AgentDefinition object provided."
		_log_audit("creation_failed", {"definition_path": "in-memory", "reason": "Invalid definition object provided."}, p_owner_id)
		push_error("Agent creation failed: Invalid AgentDefinition object provided.")
		return null

	# --- Schema version validation (fail-fast) ---
	var sv_any: Variant = p_definition.get("schema_version")
	var sv := str(sv_any).strip_edges() if typeof(sv_any) == TYPE_STRING or typeof(sv_any) == TYPE_NIL else str(sv_any).strip_edges()
	if sv.is_empty():
		# Treat empty as "use default" for safety when resources are hand-authored.
		sv = _AGENTDEF_SCHEMA_V1
		p_definition.schema_version = sv
	if sv != _AGENTDEF_SCHEMA_V1:
		last_creation_error = "Unsupported AgentDefinition.schema_version: '%s' (expected '%s')" % [sv, _AGENTDEF_SCHEMA_V1]
		_log_audit("agent_creation_error", {"definition_path": p_definition.resource_path, "error": "Unsupported schema_version", "schema_version": sv}, p_owner_id)
		return null
		
	# --- Create Instance ---
	var new_agent_id = "agent_%s" % p_definition.agent_id if not p_definition.agent_id.is_empty() else "agent_%03d" % _next_agent_id
	_next_agent_id += 1

	var new_agent = AgentInstance.new(new_agent_id, p_owner_id, p_definition)
	
	# Setup dependencies for the new agent instance
	if not new_agent.setup_dependencies(action_dispatcher, sensor_interface, short_term_memory, decision_logic_manager):
		last_creation_error = "Dependency setup failed"
		_log_audit("agent_creation_error", {"agent_id": new_agent_id, "error": "Dependency setup failed"}, p_owner_id)
		return null

	# Synterfaces/Bindings v1 (fail-fast only when required synterfaces is non-empty)
	var syn_result := _bind_synterfaces_for_definition(p_definition)
	if not syn_result.get("ok", false):
		last_creation_error = str(syn_result.get("error", "Synterface binding failed")).strip_edges()
		_log_audit("agent_creation_error", {"agent_id": new_agent_id, "error": "Synterface binding failed", "reason": last_creation_error}, p_owner_id)
		return null
	new_agent.bound_ports = syn_result.get("synterfaces", {})
	
	# Trigger initialization which includes assigning logic
	await new_agent.initialize_state()
	
	# Check if initialization resulted in an ERROR state
	if new_agent.current_status == AgentInstance.Status.ERROR:
		last_creation_error = "Initialization failed: %s" % new_agent.status_message
		_log_audit("agent_creation_error", {"agent_id": new_agent_id, "error": "Initialization failed", "reason": new_agent.status_message}, p_owner_id)
		return null

	# Add to registry ONLY on full success
	_agents[new_agent_id] = new_agent
	last_creation_error = ""
	_log_audit("agent_created", {"agent_id": new_agent_id, "definition_path": p_definition.resource_path}, p_owner_id)
	if audit_logger and audit_logger.has_method("emit_event"):
		var turn_id := str(audit_logger.default_turn_id).strip_edges() if audit_logger else ""
		audit_logger.emit_event(
			"agent.spawned",
			{"agent_id": new_agent_id, "definition_path": p_definition.resource_path, "turn_id": turn_id},
			p_owner_id,
			{"component": "metapunkt"}
		)
	
	return new_agent

func _bind_synterfaces_for_definition(definition: AgentDefinition) -> Dictionary:
	if not definition:
		return {"ok": true, "synterfaces": {}}

	# Prefer synterface fields; fall back to legacy port fields for backward compatibility.
	var required_any: Variant = definition.get("required_synterfaces")
	var required: Array = required_any if typeof(required_any) == TYPE_ARRAY else []
	if required == null or required.is_empty():
		return {"ok": true, "synterfaces": {}}

	# Find autoload host by agreed deterministic name.
	var host = _get_app_host()
	if not host:
		return {"ok": false, "error": "MetapunktAppHost autoload not found at /root/MetapunktAppHost (required synterfaces: %s)" % str(required)}

	# Merge catalogs (core + host custom).
	var catalog := _SynterfaceCatalog.get_core_synterface_catalog_v1()
	var host_catalog: Dictionary = {}
	if host.has_method("get_synterface_catalog"):
		var hc = host.call("get_synterface_catalog")
		if typeof(hc) == TYPE_DICTIONARY:
			host_catalog = hc
	for k in host_catalog.keys():
		catalog[k] = host_catalog[k]

	# Validate required port IDs exist in catalog.
	var missing_defs: Array = []
	for p in required:
		var pid := str(p).strip_edges()
		if pid.is_empty():
			continue
		if not catalog.has(pid):
			missing_defs.append(pid)
	if not missing_defs.is_empty():
		return {"ok": false, "error": "Unknown required_synterfaces (not in catalog): %s" % str(missing_defs)}

	# Ask host to bind synterfaces.
	var hints_any: Variant = definition.get("binding_hints")
	var hints: Dictionary = hints_any if typeof(hints_any) == TYPE_DICTIONARY else {}
	var bind_res = host.call("bind_synterfaces", required, hints)
	if typeof(bind_res) != TYPE_DICTIONARY:
		return {"ok": false, "error": "MetapunktAppHost.bind_synterfaces returned non-dictionary result"}
	var bind_d: Dictionary = bind_res
	if not bool(bind_d.get("ok", false)):
		var err := str(bind_d.get("error", "")).strip_edges()
		var miss_any: Variant = bind_d.get("missing")
		if err.is_empty() and typeof(miss_any) == TYPE_ARRAY and not (miss_any as Array).is_empty():
			err = "Missing synterfaces: %s" % str(miss_any)
		if err.is_empty():
			err = "MetapunktAppHost.bind_synterfaces failed"
		return {"ok": false, "error": err}

	var syn_val: Variant = bind_d.get("synterfaces")
	if typeof(syn_val) != TYPE_DICTIONARY:
		return {"ok": false, "error": "MetapunktAppHost.bind_synterfaces missing 'synterfaces' dictionary"}
	var synterfaces: Dictionary = syn_val

	# Validate each port binding against its schema (actionable errors).
	for p2 in required:
		var pid2 := str(p2).strip_edges()
		if pid2.is_empty():
			continue
		if not synterfaces.has(pid2):
			return {"ok": false, "error": "Host did not bind required synterface '%s'" % pid2}
		var binding = synterfaces.get(pid2)
		if typeof(binding) != TYPE_DICTIONARY:
			return {"ok": false, "error": "Synterface '%s' binding must be a Dictionary (JSON-friendly), got %s" % [pid2, str(typeof(binding))]}
		var entry: Dictionary = catalog.get(pid2, {})
		var schema: Dictionary = entry.get("schema", {})
		if typeof(schema) == TYPE_DICTIONARY and not schema.is_empty():
			var vr = _JsonSchemaValidator.validate(binding, schema, "$.%s" % pid2)
			if not bool(vr.get("ok", false)):
				return {"ok": false, "error": "Synterface '%s' binding invalid: %s" % [pid2, str(vr.get("error", "schema validation failed"))]}

	return {"ok": true, "synterfaces": synterfaces}

func _get_app_host() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	var host := tree.root.get_node_or_null("MetapunktAppHost")
	if not host:
		return null
	# Optional: if the script derives from our base, great; otherwise allow but validate methods.
	if host is _AppHostBase:
		return host
	if host.has_method("bind_synterfaces"):
		return host
	return null

# --- ARCHITECTURE-BOUNDARY: SLOP Endpoint Handler ---
# Handles requests routed from EndpointHandler for the /agents path
func handle_request(method: String, path_segments: Array, request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array):
	var endpoint_path = "/agents" + ("/" + "/".join(path_segments) if not path_segments.is_empty() else "")
	print("AgentRegistry handling request: %s %s" % [method, endpoint_path])

	# Route based on method and path segments
	if method == "GET" and path_segments.is_empty():
		_handle_get_agents_list(request_data, response, user_id, scopes)
	elif method == "POST" and path_segments.is_empty():
		await _handle_create_agent(request_data, response, user_id, scopes)
	elif method == "GET" and path_segments.size() == 1:
		var agent_id = path_segments[0]
		_handle_get_agent_details(request_data, response, user_id, scopes, agent_id)
	elif method == "DELETE" and path_segments.size() == 1:
		var agent_id = path_segments[0]
		_handle_delete_agent(request_data, response, user_id, scopes, agent_id)
	# TODO: Implement PUT /agents/{id} for updates
	else:
		# Method/Path not implemented for /agents
		_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Not Implemented"}, user_id)
		response.send_error(501, "Endpoint not implemented: %s %s" % [method, endpoint_path])

# --- Private Handler Methods ---

func _handle_get_agents_list(request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array):
	var agent_list_data = []
	for agent_id in _agents:
		var agent_instance: AgentInstance = _agents[agent_id]
		# TODO: Add authorization check based on agent_instance.owner_user_id / scopes
		var status_info = agent_instance.get_status_info()
		agent_list_data.append({
			"id": agent_id,
			"status": status_info["status_name"],
			"definition_path": agent_instance.definition.resource_path if agent_instance.definition else "N/A"
		})

	_log_audit("list_agents", {"count": agent_list_data.size()}, user_id)
	response.send_ok({"agents": agent_list_data, "count": agent_list_data.size()})


func _handle_create_agent(request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array):
	# TODO: Add scope check (e.g., requires 'create_agent' scope?)
	# if not "create_agent" in scopes:
	#     _log_audit("auth_error", {"method": "POST", "path": "/agents", "reason": "Missing scope"}, user_id)
	#     response.send_error(403)
	#     return

	# Parse request body (assuming JSON)
	var body_bytes: PackedByteArray = request_data.get("body", PackedByteArray())
	var body_str = body_bytes.get_string_from_utf8()

	var json_parser = JSON.new()
	var parse_err_code = json_parser.parse(body_str)
	
	if parse_err_code != OK:
		var err_line = json_parser.get_error_line()
		var err_msg = json_parser.get_error_message()
		_log_audit("request_error", {"method": "POST", "path": "/agents", "error": "Invalid JSON body", "details": "Line %s: %s" % [err_line, err_msg]}, user_id)
		response.send_error(400, "Invalid JSON body at line %s: %s" % [err_line, err_msg])
		return

	var parsed_body_data: Dictionary = json_parser.get_data()

	# --- Validate Input: Get definition_path --- 
	var definition_path = parsed_body_data.get("definition_path")
	if not definition_path or not definition_path is String or definition_path.is_empty():
		_log_audit("request_error", {"method": "POST", "path": "/agents", "error": "Missing/invalid definition_path"}, user_id)
		response.send_error(400, "Missing, invalid, or empty 'definition_path' in request body")
		return

	# --- Load Definition --- 
	# Ensure the path is valid (basic check)
	if not ResourceLoader.exists(definition_path):
		_log_audit("creation_failed", {"definition_path": definition_path, "reason": "Definition resource file not found."}, user_id)
		response.send_error(400, "AgentDefinition resource not found at path: %s" % definition_path)
		return
		
	var agent_definition: AgentDefinition = load(definition_path)
	if not agent_definition or not agent_definition is AgentDefinition:
		_log_audit("creation_failed", {"definition_path": definition_path, "reason": "Failed to load or invalid type (not AgentDefinition)"}, user_id)
		response.send_error(400, "Failed to load or invalid AgentDefinition resource type at path: %s" % definition_path)
		return

	# --- Create Instance using the new centralized method ---
	var new_agent = await create_agent_from_definition(agent_definition, user_id)
	
	if not new_agent:
		response.send_error(500, "Agent created but failed during initialization.")
		return

	# --- Respond --- 
	var status_info = new_agent.get_status_info()
	var response_data = {
		"id": new_agent.agent_id, 
		"status": status_info["status_name"], 
		"message": status_info["message"]
	}
	response.add_header("Location: /agents/%s" % new_agent.agent_id)
	response.send_ok(response_data, {}, 201)


func _handle_get_agent_details(request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array, agent_id: String):
	var agent_instance: AgentInstance = _agents.get(agent_id)

	if not agent_instance:
		_log_audit("request_error", {"method": "GET", "path": "/agents/" + agent_id, "error": "Not Found"}, user_id)
		response.send_error(404)
		return

	# TODO: Add authorization check: Can this user_id/scopes view this agent?
	# if agent_instance.owner_user_id != user_id and not "admin_scope" in scopes:
	#     _log_audit("auth_error", {"method": "GET", "path": "/agents/" + agent_id, "reason": "Unauthorized"}, user_id)
	#     response.send_error(403)
	#     return

	var status_info = agent_instance.get_status_info()
	var details_data = {
		"id": agent_id,
		"status": status_info["status_name"],
		"status_message": status_info["message"],
		"owner_user_id": agent_instance.owner_user_id,
		"definition_path": agent_instance.definition.resource_path if agent_instance.definition else "N/A",
		"blackboard": agent_instance.blackboard, # Expose blackboard state
		"current_action_id": status_info["current_action_id"]
	}

	_log_audit("get_agent_details", {"agent_id": agent_id}, user_id)
	response.send_ok(details_data)


func _handle_delete_agent(request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array, agent_id: String):
	var agent_instance: AgentInstance = _agents.get(agent_id)

	if not agent_instance:
		_log_audit("request_error", {"method": "DELETE", "path": "/agents/" + agent_id, "error": "Not Found"}, user_id)
		response.send_error(404)
		return

	# TODO: Add authorization check: Can this user_id/scopes delete this agent?
	# if agent_instance.owner_user_id != user_id and not "admin_delete_scope" in scopes:
	#     _log_audit("auth_error", {"method": "DELETE", "path": "/agents/" + agent_id, "reason": "Unauthorized"}, user_id)
	#     response.send_error(403)
	#     return

	# Trigger agent shutdown
	delete_agent(agent_id, user_id)
	response.send_empty(204)


# --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 
