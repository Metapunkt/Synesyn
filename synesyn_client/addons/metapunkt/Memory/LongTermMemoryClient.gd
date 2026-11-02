extends Node # Needs to be Node for HTTPRequest child
class_name LongTermMemoryClient

# Client for accessing external Vector DBs via SLOP HTTP client.
# Handles user-specific data scoping based on provided context.
# Implements parts of SLOP /memory/long_term endpoint logic.

# --- Dependencies ---
var audit_logger # : AuditLogger
const CustomHTTPResponse = preload("res://addons/metapunkt/Networking/SLOPServer/HTTPResponse.gd") # Added

# --- Configuration ---
@export var ltm_service_url: String = "http://127.0.0.1:8000/api/v1" # Example URL for external LTM
@export var request_timeout: int = 10 # Seconds

# --- Internal State ---
# We create a fresh HTTPRequest per outbound call to support concurrency safely.
# Dictionary: request_instance_id -> {response: HTTPResponse, user_id: String, action: String, http: HTTPRequest}
var _pending_requests: Dictionary = {}

# --- Initialization ---
func _init(p_audit_logger = null):
	audit_logger = p_audit_logger
	if not audit_logger:
		push_warning("LongTermMemoryClient initialized without AuditLogger.")

func _ready():
	pass


func _create_outbound_request() -> HTTPRequest:
	var req = HTTPRequest.new()
	add_child(req)
	req.timeout = request_timeout
	# Godot 4: there is no get_signal_sender() in GDScript.
	# Bind the request instance id into the callback so we can correlate safely.
	req.request_completed.connect(_on_outbound_request_completed.bind(req.get_instance_id()))
	return req


# --- Public API (called by SLOP handler or potentially other modules) ---

# Adds a memory chunk to the external LTM
func add_memory(memory_data: Dictionary, user_id: String, scopes: Array, response: HTTPResponse):
	# TODO: Validate memory_data structure (e.g., requires 'text', optional 'metadata')
	var url = ltm_service_url.path_join("memories")
	var headers = ["Content-Type: application/json"]
	# TODO: Pass user_id/scopes in headers if required by LTM service
	# headers.append("X-User-Id: %s" % user_id)
	
	var body = JSON.stringify(memory_data)
	
	_log_audit("ltm_add_request", {"url": url, "data": memory_data.keys()}, user_id)
	var req = _create_outbound_request()
	var error = req.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		_handle_request_error("ltm_add_failed", "Failed to initiate add request: %s" % error_string(error), response, user_id)
	else:
		# Store response object to reply later
		_pending_requests[req.get_instance_id()] = { "response": response, "user_id": user_id, "action": "add", "http": req }


# Searches the external LTM
func search_memory(query: String, filters: Dictionary, top_k: int, user_id: String, scopes: Array, response: HTTPResponse):
	var url = ltm_service_url.path_join("memories/search")
	var headers = ["Content-Type: application/json"]
	# TODO: Pass user_id/scopes in headers if required by LTM service
	
	var search_payload = {
		"query": query,
		"filters": filters,
		"top_k": top_k
	}
	var body = JSON.stringify(search_payload)

	_log_audit("ltm_search_request", {"url": url, "query_len": query.length(), "filters": filters.keys(), "top_k": top_k}, user_id)
	var req = _create_outbound_request()
	var error = req.request(url, headers, HTTPClient.METHOD_POST, body)

	if error != OK:
		_handle_request_error("ltm_search_failed", "Failed to initiate search request: %s" % error_string(error), response, user_id)
	else:
		# Store response object to reply later
		_pending_requests[req.get_instance_id()] = { "response": response, "user_id": user_id, "action": "search", "http": req }


# --- ARCHITECTURE-BOUNDARY: SLOP Endpoint Handler ---
# Handles requests routed from EndpointHandler for the /memory/long_term path
func handle_slop_request(method: String, path_segments: Array, request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array):
	var endpoint_path = "/memory/long_term" + ("/" + "/".join(path_segments) if not path_segments.is_empty() else "")
	print("LongTermMemoryClient handling request: %s %s" % [method, endpoint_path])

	# Only POST is supported for add/search
	if method != "POST":
		_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Method Not Allowed"}, user_id)
		response.send_error(405)
		return

	if path_segments.size() != 1:
		_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Invalid path structure"}, user_id)
		response.send_error(400, "Expected path like /memory/long_term/add or /memory/long_term/search")
		return

	var action = path_segments[0]

	# Parse request body (used for both add and search)
	var body_bytes: PackedByteArray = request_data.get("body", PackedByteArray())
	var body_str = body_bytes.get_string_from_utf8()
	
	var json_parser = JSON.new()
	var parse_err_code = json_parser.parse(body_str)
	
	if parse_err_code != OK:
		var err_line = json_parser.get_error_line()
		var err_msg = json_parser.get_error_message()
		_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Invalid JSON body", "details": "Line %s: %s" % [err_line, err_msg]}, user_id)
		response.send_error(400, "Invalid JSON body at line %s: %s" % [err_line, err_msg])
		return
	
	var parsed_body_data: Dictionary = json_parser.get_data()
	
	match action:
		"add":
			# Body itself is the memory data to add
			add_memory(parsed_body_data, user_id, scopes, response)
		"search":
			# Extract search parameters from body
			var query = parsed_body_data.get("query", "")
			var filters = parsed_body_data.get("filters", {})
			var top_k = parsed_body_data.get("top_k", 5)
			if query.is_empty():
				response.send_error(400, "Missing 'query' in search request body")
				return
			search_memory(query, filters, top_k, user_id, scopes, response)
		_:
			_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Unknown LTM action"}, user_id)
			response.send_error(404, "Unknown long_term memory action: %s" % action)


# --- Internal Callbacks / Helpers ---

# Callback for completed outbound HTTP requests
func _on_outbound_request_completed(result: int, response_code: int, headers_packed_array: PackedStringArray, body: PackedByteArray, request_id: int):
	
	if not _pending_requests.has(request_id):
		printerr("Received completed HTTP request, but no pending data found for ID: %s" % request_id)
		# Best-effort cleanup: try to find and free the HTTPRequest node by instance id.
		for child in get_children():
			if child is HTTPRequest and child.get_instance_id() == request_id:
				child.queue_free()
				break
		return

	var pending_data_value = _pending_requests[request_id] 
	_pending_requests.erase(request_id) 
	# Cleanup the request node
	if pending_data_value.has("http") and pending_data_value["http"]:
		var req: HTTPRequest = pending_data_value["http"]
		req.queue_free()
	
	var slop_response: CustomHTTPResponse = pending_data_value["response"]
	var user_id: String = pending_data_value["user_id"]
	var action_str: String = pending_data_value["action"] # Renamed to avoid conflict with path variable

	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_request_error("ltm_%s_failed" % action_str, "Outbound LTM request failed: %s" % _result_to_string(result), slop_response, user_id)
		return

	_log_audit("ltm_%s_response" % action_str, {"status_code": response_code}, user_id)

	slop_response.set_status_code(response_code)
	for header_str_item in headers_packed_array:
		slop_response.add_header(header_str_item)
	
	slop_response.body_bytes = body
	slop_response._send_response()


# Helper to handle errors consistently and respond to the SLOP client
func _handle_request_error(audit_event: String, error_message: String, slop_response: CustomHTTPResponse, user_id: String):
	printerr(error_message)
	_log_audit(audit_event, {"error": error_message}, user_id)
	if slop_response and is_instance_valid(slop_response._peer) and slop_response._peer.is_connected_to_host():
		slop_response.send_error(500, "LTM request failed. Check server logs.")


# Helper to convert HTTPRequest result enum to string
func _result_to_string(result_code: int) -> String:
	match result_code:
		HTTPRequest.RESULT_SUCCESS: return "RESULT_SUCCESS"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: return "RESULT_CHUNKED_BODY_SIZE_MISMATCH"
		HTTPRequest.RESULT_CANT_CONNECT: return "RESULT_CANT_CONNECT"
		HTTPRequest.RESULT_CANT_RESOLVE: return "RESULT_CANT_RESOLVE"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "RESULT_CONNECTION_ERROR"
		# HTTPRequest.RESULT_SSL_HANDSHAKE_ERROR: return "RESULT_SSL_HANDSHAKE_ERROR" # Commented out
		HTTPRequest.RESULT_NO_RESPONSE: return "RESULT_NO_RESPONSE"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: return "RESULT_BODY_SIZE_LIMIT_EXCEEDED"
		HTTPRequest.RESULT_REQUEST_FAILED: return "RESULT_REQUEST_FAILED"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: return "RESULT_DOWNLOAD_FILE_CANT_OPEN"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: return "RESULT_DOWNLOAD_FILE_WRITE_ERROR"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: return "RESULT_REDIRECT_LIMIT_REACHED"
		HTTPRequest.RESULT_TIMEOUT: return "RESULT_TIMEOUT"
		_: return "Unknown HTTPRequest Result (%d)" % result_code


# --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 
