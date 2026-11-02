extends Object
class_name ShortTermMemory

const CustomHTTPResponse = preload("res://addons/metapunkt/Networking/SLOPServer/HTTPResponse.gd") # Added

# In-engine dictionaries/resources for fast-access state.
# Implements parts of SLOP /memory/short_term endpoint logic.

# --- Dependencies ---
var audit_logger # : AuditLogger

# --- Internal State ---
# Structure: { "agent_id_or_global": { "key": value } }
# Using "global" for non-agent-specific memory for now.
var _memory_store: Dictionary = {}

# --- Initialization ---
func _init(p_audit_logger = null):
	audit_logger = p_audit_logger
	if not audit_logger:
		push_warning("ShortTermMemory initialized without AuditLogger.")

# --- Public API (called by AgentInstance, DecisionLogic, or SLOP handler) ---

func set_memory(key: String, value: Variant, scope_id: String = "global"):
	if not _memory_store.has(scope_id):
		_memory_store[scope_id] = {}
	_memory_store[scope_id][key] = value
	# Log audit only if called via SLOP? Or always?
	# _log_audit("stm_set", {"scope": scope_id, "key": key}, "system") # Assuming internal calls are system

func get_memory(key: String, scope_id: String = "global") -> Variant:
	if not _memory_store.has(scope_id):
		return null
	return _memory_store[scope_id].get(key) # Returns null if key doesn't exist

func delete_memory(key: String, scope_id: String = "global") -> bool:
	if not _memory_store.has(scope_id):
		return false
	if not _memory_store[scope_id].has(key):
		return false
	_memory_store[scope_id].erase(key)
	# Clean up scope if empty?
	# if _memory_store[scope_id].is_empty():
	#     _memory_store.erase(scope_id)
	return true

func list_memory_keys(scope_id: String = "global") -> Array:
	if not _memory_store.has(scope_id):
		return []
	return _memory_store[scope_id].keys()

func list_scopes() -> Array:
	return _memory_store.keys()

# --- ARCHITECTURE-BOUNDARY: SLOP Endpoint Handler ---
# Handles requests routed from EndpointHandler for the /memory/short_term path
func handle_slop_request(method: String, path_segments: Array, request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array):
	# Expected path: /{scope_id}/{key} or /{scope_id}
	var endpoint_path = "/memory/short_term" + ("/" + "/".join(path_segments) if not path_segments.is_empty() else "")
	print("ShortTermMemory handling request: %s %s" % [method, endpoint_path])

	var scope_id: String = "global" # Default scope
	var key: String = ""

	if path_segments.size() >= 1:
		scope_id = path_segments[0]
	if path_segments.size() >= 2:
		key = path_segments[1]
	# Ignore extra path segments for now

	# TODO: Authorization - Can user_id/scopes access this scope_id?
	# For now, assume yes.

	match method:
		"GET":
			if key.is_empty(): # GET /memory/short_term/{scope_id}
				_handle_get_scope_keys(request_data, response, user_id, scopes, scope_id)
			else: # GET /memory/short_term/{scope_id}/{key}
				_handle_get_key_value(request_data, response, user_id, scopes, scope_id, key)
		"PUT", "POST": # Treat PUT and POST as setting the value
			if key.is_empty():
				response.send_error(400, "Key must be specified for PUT/POST.")
				return
			_handle_set_key_value(request_data, response, user_id, scopes, scope_id, key)
		"DELETE":
			if key.is_empty():
				response.send_error(400, "Key must be specified for DELETE.")
				return
			_handle_delete_key_value(request_data, response, user_id, scopes, scope_id, key)
		_:
			_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Method Not Allowed"}, user_id)
			response.send_error(405)

# --- Private SLOP Handler Methods ---

func _handle_get_scope_keys(request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array, scope_id: String):
	var keys = list_memory_keys(scope_id)
	_log_audit("stm_list_keys", {"scope": scope_id, "count": keys.size()}, user_id)
	response.send_ok({"scope": scope_id, "keys": keys, "count": keys.size()})

func _handle_get_key_value(request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array, scope_id: String, key: String):
	var value = get_memory(key, scope_id)
	if value == null and not (_memory_store.has(scope_id) and _memory_store[scope_id].has(key)):
		_log_audit("stm_get_error", {"scope": scope_id, "key": key, "error": "Not Found"}, user_id)
		response.send_error(404)
		return
	
	_log_audit("stm_get", {"scope": scope_id, "key": key}, user_id)
	# TODO: Better serialization for complex types?
	var response_data = {"value": value}
	response.send_ok(response_data)

func _handle_set_key_value(request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array, scope_id: String, key: String):
	# Assume JSON body contains the value
	var value
	var body_bytes: PackedByteArray = request_data.get("body", PackedByteArray())
	var body_str = body_bytes.get_string_from_utf8()

	var json_parser = JSON.new()
	var parse_err_code = json_parser.parse(body_str)
	var parsed_value # To store the successfully parsed value

	if parse_err_code == OK:
		parsed_value = json_parser.get_data()
		if typeof(parsed_value) == TYPE_DICTIONARY and parsed_value.has("value"):
			value = parsed_value["value"]
		else:
			value = parsed_value # Assume raw JSON value
	else:
		# Parsing failed
		var err_line = json_parser.get_error_line()
		var err_msg = json_parser.get_error_message()
		_log_audit("stm_set_error", {"scope": scope_id, "key": key, "error": "Invalid JSON body", "details": "Line %s: %s" % [err_line, err_msg]}, user_id)
		response.send_error(400, "Invalid JSON body (at line %s: %s). Expecting {'value': ...} or raw JSON value." % [err_line, err_msg])
		return

	set_memory(key, value, scope_id)
	_log_audit("stm_set", {"scope": scope_id, "key": key}, user_id)
	response.send_empty(204) # 204 No Content for successful PUT/POST update

func _handle_delete_key_value(request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array, scope_id: String, key: String):
	var deleted = delete_memory(key, scope_id)
	if deleted:
		_log_audit("stm_delete", {"scope": scope_id, "key": key}, user_id)
		response.send_empty(204)
	else:
		_log_audit("stm_delete_error", {"scope": scope_id, "key": key, "error": "Not Found"}, user_id)
		response.send_error(404)

# --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 