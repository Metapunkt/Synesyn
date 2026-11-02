extends RefCounted
class_name HTTPResponse

## Custom HTTPResponse class to work around potential parser issues
## and provide a similar interface for server-side responses.

var status_code: int = 200
var headers: Dictionary = {}
var body_bytes: PackedByteArray = PackedByteArray()

# Basic API metadata (for clients/tools)
const API_VERSION := "v0"

# Internal: Holds the actual TCP connection to send the response
var _peer: StreamPeerTCP = null 

func _init(peer: StreamPeerTCP):
	_peer = peer

func set_status_code(code: int):
	status_code = code

func add_header(header_line: String):
	var parts = header_line.split(": ", true, 1)
	if parts.size() == 2:
		headers[parts[0].strip_edges()] = parts[1].strip_edges()
	else:
		printerr("Invalid header format: ", header_line)

func send_text(text: String):
	body_bytes = text.to_utf8_buffer()
	_send_response()

func send_json(payload: Variant, code: int = 200):
	status_code = code
	add_header("Content-Type: application/json")
	add_header("X-Metapunkt-API: %s" % API_VERSION)
	body_bytes = JSON.stringify(payload).to_utf8_buffer()
	_send_response()

func send_ok(data: Variant = null, meta: Dictionary = {}, code: int = 200):
	var payload = {
		"ok": true,
		"data": data,
		"meta": meta,
	}
	send_json(payload, code)

func send_fail(code: int, error_code: String, message: String, details: Dictionary = {}):
	status_code = code
	var payload = {
		"ok": false,
		"error": {
			"code": error_code,
			"message": message,
			"details": details,
		}
	}
	send_json(payload, code)

func send_error(code: int, message: String = ""):
	# Back-compat: keep this method but emit a stable envelope.
	var msg = message if not message.is_empty() else _get_status_message(code)
	send_fail(code, "http_%d" % code, msg)

func send_empty(code: int):
	status_code = code
	body_bytes = PackedByteArray()
	_send_response()
	
# --- Private ---

func _send_response():
	if not _peer or not _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		printerr("HTTPResponse cannot send, peer is not connected or invalid.")
		return

	var status_text = _get_status_message(status_code)
	var response_line = "HTTP/1.1 %d %s\r\n" % [status_code, status_text]
	_peer.put_data(response_line.to_utf8_buffer())

	# Add default headers if missing
	if not headers.has("Content-Type"):
		headers["Content-Type"] = "text/plain" # Default, might be overridden
	if not headers.has("Content-Length"):
		headers["Content-Length"] = str(body_bytes.size())
	if not headers.has("Connection"):
		headers["Connection"] = "close" # Close connection after response

	# Send headers
	for key in headers:
		var header_line = "%s: %s\r\n" % [key, headers[key]]
		_peer.put_data(header_line.to_utf8_buffer())
		
	# Send separator
	_peer.put_data("\r\n".to_utf8_buffer())

	# Send body
	if body_bytes.size() > 0:
		_peer.put_data(body_bytes)

	print("Sent HTTP Response: ", status_code)
	# Close the connection after sending
	_peer.disconnect_from_host()


# Basic status messages - can be expanded
func _get_status_message(code: int) -> String:
	match code:
		200: return "OK"
		201: return "Created"
		204: return "No Content"
		400: return "Bad Request"
		401: return "Unauthorized"
		403: return "Forbidden"
		404: return "Not Found"
		405: return "Method Not Allowed"
		500: return "Internal Server Error"
		501: return "Not Implemented"
		_:   return "Status Unknown" 