extends Node
class_name HTTPServer

## Custom HTTPServer class using TCPServer internally.

# Preload the custom response class
const CustomHTTPResponse = preload("res://addons/metapunkt/Networking/SLOPServer/HTTPResponse.gd")

# Signal emitted when a request is received
# Passes a Dictionary representing the request and our custom HTTPResponse object
signal request_received(request_data: Dictionary, response: CustomHTTPResponse)

var tcp_server: TCPServer
var listening: bool = false
var listen_port: int = -1
var listen_host: String = ""

# Store active connections briefly while parsing
var active_connections: Array[StreamPeerTCP] = []

# --- Safety limits (v0 localhost-only control plane) ---
const MAX_HEADER_BYTES := 16 * 1024
const MAX_BODY_BYTES := 2 * 1024 * 1024
const MAX_BODY_WAIT_MS := 3000
const LOCALHOST_ONLY := true
const _LOCALHOST_ALLOW: Array[String] = ["127.0.0.1", "::1"]

func _init():
	tcp_server = TCPServer.new()
	
func listen(port: int, host: String = "*") -> Error:
	if listening:
		printerr("HTTPServer already listening.")
		return ERR_ALREADY_IN_USE

	# Guard invalid ports early.
	if port <= 0 or port > 65535:
		listening = false
		printerr("Custom HTTPServer invalid port: %s" % str(port))
		return ERR_INVALID_PARAMETER
		
	# Godot version compatibility:
	# Some builds support TCPServer.listen(port, bind_address), others only listen(port).
	var err: int = tcp_server.listen(port, host)
	if err == ERR_INVALID_PARAMETER and host != "*" and host.strip_edges() != "":
		# Retry 1-arg listen (binds to all interfaces or engine default).
		err = tcp_server.listen(port)
	if err == OK:
		listening = true
		listen_port = tcp_server.get_local_port()
		listen_host = host
		print("Custom HTTPServer started listening on %s:%d" % [host, listen_port])
		set_process(true) # Start polling
	else:
		listening = false
		printerr("Custom HTTPServer failed to listen on %s:%d - Error %s" % [host, port, err])
	return err

func stop():
	if listening:
		print("Stopping custom HTTPServer...")
		tcp_server.stop()
		listening = false
		listen_port = -1
		listen_host = ""
		set_process(false) # Stop polling
		# Close any connections that might still be open in our temp list
		for peer in active_connections:
			if is_instance_valid(peer) and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				peer.disconnect_from_host()
		active_connections.clear()

func is_listening() -> bool:
	return listening

func get_listen_port() -> int:
	return listen_port

func get_listen_host() -> String:
	return listen_host

func _process(delta): # Poll for connections
	if not listening:
		return
		
	# Check for new connections
	while tcp_server.is_connection_available():
		var peer: StreamPeerTCP = tcp_server.take_connection()
		if peer != null:
			if LOCALHOST_ONLY:
				var remote := String(peer.get_connected_host()).strip_edges()
				if remote not in _LOCALHOST_ALLOW:
					printerr("Custom HTTPServer rejected non-local connection from: %s:%s" % [remote, str(peer.get_connected_port())])
					peer.disconnect_from_host()
					continue
			print("Custom HTTPServer accepted connection from: ", peer.get_connected_host(), ":", peer.get_connected_port())
			active_connections.append(peer)
			
	# Check existing connections for data
	var connections_to_remove = []
	for i in range(active_connections.size() - 1, -1, -1): # Iterate backwards for safe removal
		var peer = active_connections[i]
		if not is_instance_valid(peer):
			connections_to_remove.append(i)
			continue

		if not peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			# This can happen if client closes connection before data is sent/fully received
			# Or if it was already handled and disconnected by HTTPResponse
			# print("Custom HTTPServer peer disconnected or already handled.") 
			connections_to_remove.append(i)
			continue

		var available_bytes = peer.get_available_bytes()
		if available_bytes > 0:
			# Attempt to read and parse the request
			var request_data_result = await _parse_http_request(peer, available_bytes)
			
			if typeof(request_data_result) == TYPE_DICTIONARY:
				# Successfully parsed, create response object and emit signal
				var response = CustomHTTPResponse.new(peer)
				request_received.emit(request_data_result, response)
				# Response object will handle closing the peer after sending
				connections_to_remove.append(i) # Remove from active polling list
				
			elif request_data_result == "incomplete":
				# Need more data, keep polling this connection
				pass 
			else: # Assume error
				printerr("Failed to parse HTTP request or error occurred: ", request_data_result)
				# Send a basic 400 Bad Request error and close
				var error_response = "HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
				peer.put_data(error_response.to_utf8_buffer())
				peer.disconnect_from_host()
				connections_to_remove.append(i)
				
	# Clean up handled/disconnected connections
	for i in connections_to_remove:
		if i < active_connections.size(): # Check index validity just in case
			active_connections.remove_at(i)

func _exit_tree():
	stop()
	
# --- Private --- 

# Very basic HTTP Request parser. Returns Dictionary on success, "incomplete" if 
# not enough data yet, or error string on failure.
# NOTE: This is extremely simplified and likely won't handle all edge cases,
# chunked encoding, large bodies correctly, etc.
func _parse_http_request(peer: StreamPeerTCP, available_bytes: int) -> Variant:
	# Read available data (limit to a reasonable amount for initial parse)
	# We might need more sophisticated buffering for large requests
	var read_limit = MAX_HEADER_BYTES
	var data_tuple = peer.get_partial_data(min(available_bytes, read_limit))
	var err = data_tuple[0]
	var data: PackedByteArray = data_tuple[1]
	
	if err != OK:
		return "Error reading from peer: %s" % err

	var request_str = data.get_string_from_utf8()
	
	# Check if headers are complete (double CRLF)
	var header_end_pos = request_str.find("\r\n\r\n")
	if header_end_pos == -1:
		# Headers not fully received yet? 
		# Could also be a very large request exceeding our read_limit.
		# For now, assume incomplete if we read the limit.
		if data.size() == read_limit: 
			return "Request headers too large or incomplete (read limit reached)" # Treat as error for now
		else:
			return "incomplete" 
		
	var header_part = request_str.substr(0, header_end_pos)
	var body_part_start = header_end_pos + 4
		
	var headers_arr = header_part.split("\r\n")
	if headers_arr.is_empty():
		return "Invalid request format (no request line)"
		
	# Parse Request Line (e.g., "GET /path HTTP/1.1")
	var request_line = headers_arr[0]
	var request_line_parts = request_line.split(" ", true, 2)
	if request_line_parts.size() != 3:
		return "Invalid request line format: %s" % request_line
		
	var method = request_line_parts[0]
	var uri = request_line_parts[1]
	var http_version = request_line_parts[2]
	
	# Parse Headers
	var headers_dict = {}
	for i in range(1, headers_arr.size()):
		var header_line = headers_arr[i]
		if header_line.is_empty(): continue # Should not happen before separator
		var parts = header_line.split(": ", true, 1)
		if parts.size() == 2:
			headers_dict[parts[0].strip_edges().to_lower()] = parts[1].strip_edges()
		else:
			print("Warning: Malformed header line ignored: ", header_line)
			
	# Basic Body Handling (Content-Length)
	var body_bytes = PackedByteArray()
	var content_length = 0
	if headers_dict.has("content-length"):
		if headers_dict["content-length"].is_valid_int():
			content_length = int(headers_dict["content-length"])
		else:
			return "Invalid Content-Length header"
	if content_length > MAX_BODY_BYTES:
		return "Request body too large (max %d bytes)" % MAX_BODY_BYTES
			
	# Check if we already read the entire body
	var initial_body_read = data.slice(body_part_start)
	body_bytes.append_array(initial_body_read)
	
	# Read remaining body if necessary
	var body_wait_start_ms = Time.get_ticks_msec()
	while body_bytes.size() < content_length:
		available_bytes = peer.get_available_bytes()
		if available_bytes == 0:
			# Need to wait for more data
			# Wait a frame (simple non-blocking wait)
			if Time.get_ticks_msec() - body_wait_start_ms > MAX_BODY_WAIT_MS:
				return "Incomplete request body (timeout)"
			await get_tree().process_frame 
			# Check again after waiting
			available_bytes = peer.get_available_bytes()
			if available_bytes == 0 and body_bytes.size() < content_length:
				return "Incomplete request body (timeout or disconnect)"
			continue # Re-check available bytes in next loop iteration
				
		var bytes_to_read = min(available_bytes, content_length - body_bytes.size())
		data_tuple = peer.get_partial_data(bytes_to_read)
		err = data_tuple[0]
		var chunk_data: PackedByteArray = data_tuple[1]
		
		if err != OK:
			return "Error reading request body: %s" % err
			
		body_bytes.append_array(chunk_data)

	# Construct request data dictionary (mimicking parts of HTTPRequest)
	# NOTE: This is NOT a real HTTPRequest object
	var request_data = {
		"request_method": method,
		"request_uri": uri,
		"http_version": http_version,
		"request_headers_as_dictionary": headers_dict,
		"body": body_bytes 
		# Add other fields as needed, e.g., parsed query params from URI
	}
	
	print("Parsed HTTP Request: %s %s" % [method, uri])
	return request_data 
