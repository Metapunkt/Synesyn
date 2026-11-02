extends Object
class_name SensorInterface

# Routes/queries sensor data for agents.
# Implements SLOP /sensors endpoint logic.

# --- Dependencies ---
var audit_logger # : AuditLogger

# --- Internal State (Sensor Definitions) ---
# In a real implementation, this might load SensorDefinition resources
# or discover sensor nodes in the scene tree.
var _sensors: Dictionary = {
	"player_position": {
		"description": "The current X, Y, Z position of the player character.",
		"value_type": "Vector3",
		"update_frequency": "on_demand", # or "periodic"
		"getter_method": "_get_player_position" # Name of internal method to get value
	},
	"game_time": {
		"description": "The current time elapsed since the game started (in seconds).",
		"value_type": "float",
		"update_frequency": "on_demand",
		"getter_method": "_get_game_time"
	},
	"nearby_enemies": {
		"description": "A list of enemy IDs within a certain radius of the player.",
		"value_type": "Array[String]",
		"update_frequency": "on_demand",
		"getter_method": "_get_nearby_enemies"
	}
}

# --- Initialization ---
func _init(p_audit_logger = null):
	audit_logger = p_audit_logger
	if not audit_logger:
		push_warning("SensorInterface initialized without AuditLogger.")

# --- Public API (called by AgentInstance or DecisionLogic) ---

# Gets the current value of a specific sensor
func read_sensor(sensor_id: String, agent_id: String = "", user_id: String = "") -> Variant:
	if not _sensors.has(sensor_id):
		_log_audit("sensor_read_error", {"sensor_id": sensor_id, "agent_id": agent_id, "error": "Not Found"}, user_id)
		push_error("Sensor not found: %s" % sensor_id)
		return null
	
	var sensor_config = _sensors[sensor_id]
	var getter_method_name = sensor_config.get("getter_method")

	if not getter_method_name or not has_method(getter_method_name):
		_log_audit("sensor_read_error", {"sensor_id": sensor_id, "agent_id": agent_id, "error": "Getter method not found"}, user_id)
		push_error("Getter method '%s' not found for sensor '%s'" % [getter_method_name, sensor_id])
		return null
	
	# Call the internal getter method
	var value = call(getter_method_name, agent_id) # Pass agent_id for context if needed
	
	# Check if the call potentially failed (conventionally returns null on failure)
	if value == null:
		# It's hard to know the exact error without try/except. 
		# Log a generic error or rely on the getter method to log specifics.
		var err_msg = "Error or null value reading sensor %s using method %s" % [sensor_id, getter_method_name]
		_log_audit("sensor_read_error", {"sensor_id": sensor_id, "agent_id": agent_id, "error": err_msg}, user_id)
		# printerr(err_msg) # Optional: print error here too
		return null
	
	# If we got here, assume the call succeeded
	_log_audit("sensor_read", {"sensor_id": sensor_id, "agent_id": agent_id, "value_retrieved": true}, user_id) # Log success
	return value

# Lists available sensors
func list_available_sensors(user_id: String = "", scopes: Array = []) -> Array:
	# TODO: Filter sensors based on user/scopes/agent capabilities?
	var sensor_list = []
	for sensor_id in _sensors:
		var config = _sensors[sensor_id].duplicate()
		config.erase("getter_method") # Don't expose internal method name
		config["id"] = sensor_id
		sensor_list.append(config)
	return sensor_list

# --- ARCHITECTURE-BOUNDARY: SLOP Endpoint Handler ---
# Removed HTTPRequest/Response type hints due to persistent parse errors
func handle_request(method: String, path_segments: Array, request, response, user_id: String, scopes: Array):
	var endpoint_path = "/sensors" + ("/" + "/".join(path_segments) if not path_segments.is_empty() else "")
	print("SensorInterface handling request: %s %s" % [method, endpoint_path])

	if method == "GET" and path_segments.is_empty():
		_handle_get_sensors_list(request, response, user_id, scopes)
	elif method == "GET" and path_segments.size() == 1:
		# Get sensor definition/metadata
		var sensor_id = path_segments[0]
		_handle_get_sensor_details(request, response, user_id, scopes, sensor_id)
	elif method == "GET" and path_segments.size() == 2 and path_segments[1] == "value":
		# Get current sensor value
		var sensor_id = path_segments[0]
		_handle_get_sensor_value(request, response, user_id, scopes, sensor_id)
	else:
		_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Not Implemented"}, user_id)
		# Use the passed response object directly, even without type hint
		response.send_error(501, "Endpoint not implemented: %s %s" % [method, endpoint_path]) # 501 Not Implemented


# --- Private Handler Methods ---

# Removed HTTPRequest/Response type hints
func _handle_get_sensors_list(request, response, user_id: String, scopes: Array):
	var sensors_data = list_available_sensors(user_id, scopes)
	_log_audit("list_sensors", {"count": sensors_data.size()}, user_id)
	response.send_ok({"sensors": sensors_data, "count": sensors_data.size()})

# Removed HTTPRequest/Response type hints
func _handle_get_sensor_details(request, response, user_id: String, scopes: Array, sensor_id: String):
	if not _sensors.has(sensor_id):
		_log_audit("get_sensor_details_error", {"sensor_id": sensor_id, "error": "Not Found"}, user_id)
		response.send_error(404) # 404 Not Found
		return

	# TODO: Authorization check?
	var sensor_config = _sensors[sensor_id].duplicate()
	sensor_config.erase("getter_method") # Don't expose internal details
	sensor_config["id"] = sensor_id

	_log_audit("get_sensor_details", {"sensor_id": sensor_id}, user_id)
	response.send_ok(sensor_config)

# Removed HTTPRequest/Response type hints
func _handle_get_sensor_value(request, response, user_id: String, scopes: Array, sensor_id: String):
	# TODO: Authorization check?
	var value = read_sensor(sensor_id, "SLOP_request", user_id) # Pass context

	if value == null and not _sensors.has(sensor_id): # Check if error was due to not found
		response.send_error(404) # 404 Not Found
		return
	elif value == null: # Assume other error during read
		response.send_error(500, "Error reading sensor value.") # 500 Internal Server Error
		return

	# Package the value in a standard way
	var response_data = {
		"sensor_id": sensor_id,
		"value": value,
		"timestamp": Time.get_unix_time_from_system()
	}
	# Note: JSON stringify might fail on complex Godot types (Vector3, etc.)
	# We might need custom serialization for certain value types.
	response.send_ok(response_data)


# --- Internal Sensor Getter Methods (Placeholders) ---

func _get_player_position(agent_id: String = "") -> Vector3:
	# TODO: Get actual player position from SceneTree or game state manager
	return Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))

func _get_game_time(agent_id: String = "") -> float:
	# TODO: Get actual game time
	return Time.get_ticks_msec() / 1000.0

func _get_nearby_enemies(agent_id: String = "") -> Array[String]:
	# TODO: Implement logic to find nearby enemies
	return ["enemy_01", "enemy_03"] if randi() % 2 == 0 else ["enemy_02"]

# --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 
