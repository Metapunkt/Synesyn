extends Node
class_name OllamaStreamingClient

signal chunk_received(request_id: String, content_delta: String)

const CHAT_PATH: String = "/api/chat"

var _clients: Dictionary = {}
var _cancelled_ids: Dictionary = {}
var _host: String = "127.0.0.1"
var _port: int = 11434
var _use_tls: bool = false


func configure(origin_url: String) -> bool:
	var normalized: String = origin_url.strip_edges().trim_suffix("/")
	normalized = normalized.trim_suffix("/api/chat")
	_use_tls = normalized.begins_with("https://")
	if not (_use_tls or normalized.begins_with("http://")):
		return false
	var authority: String = normalized.get_slice("://", 1)
	if authority.contains("/"):
		authority = authority.get_slice("/", 0)
	if authority.is_empty():
		return false
	_host = authority
	_port = 443 if _use_tls else 80
	if authority.contains(":"):
		_host = authority.get_slice(":", 0)
		var port_text: String = authority.get_slice(":", 1)
		if not port_text.is_valid_int():
			return false
		_port = port_text.to_int()
	return not _host.is_empty() and _port > 0


func run(
	request_id: String,
	request_body: Dictionary,
	timeout_seconds: float
) -> Dictionary:
	if _clients.has(request_id):
		return {"success": false, "error": "duplicate_request_id"}
	var client := HTTPClient.new()
	_clients[request_id] = client
	var started_msec: int = Time.get_ticks_msec()
	var tls_options: TLSOptions = null
	if _use_tls:
		tls_options = TLSOptions.client()
	var connection_error: Error = client.connect_to_host(
		_host,
		_port,
		tls_options
	)
	if connection_error != OK:
		_release(request_id)
		return {"success": false, "error": "ollama_connect_failed"}
	var ready_result: Dictionary = await _wait_for_connection(
		client,
		request_id,
		started_msec,
		timeout_seconds
	)
	if not bool(ready_result.get("success", false)):
		_release(request_id)
		return ready_result
	var streaming_body: Dictionary = request_body.duplicate(true)
	streaming_body["stream"] = true
	var request_error: Error = client.request(
		HTTPClient.METHOD_POST,
		CHAT_PATH,
		PackedStringArray(["Content-Type: application/json"]),
		JSON.stringify(streaming_body)
	)
	if request_error != OK:
		_release(request_id)
		return {"success": false, "error": "ollama_stream_start_failed"}
	var response_result: Dictionary = await _read_response(
		client,
		request_id,
		started_msec,
		timeout_seconds
	)
	_release(request_id)
	return response_result


func cancel(request_id: String) -> bool:
	_cancelled_ids[request_id] = true
	var client_any: Variant = _clients.get(request_id)
	if client_any is HTTPClient:
		(client_any as HTTPClient).close()
		return true
	return false


func cancel_all() -> bool:
	var did_cancel: bool = false
	for request_id_any: Variant in _clients.keys():
		did_cancel = cancel(String(request_id_any)) or did_cancel
	return did_cancel


func is_busy() -> bool:
	return not _clients.is_empty()


func parse_ndjson_lines(
	buffer: String,
	request_id: String = ""
) -> Dictionary:
	var remaining: String = buffer
	var chunks: Array[String] = []
	var final_payload: Dictionary = {}
	while remaining.contains("\n"):
		var newline_index: int = remaining.find("\n")
		var line_text: String = remaining.left(newline_index).strip_edges()
		remaining = remaining.substr(newline_index + 1)
		if line_text.is_empty():
			continue
		var parsed_any: Variant = JSON.parse_string(line_text)
		if typeof(parsed_any) != TYPE_DICTIONARY:
			continue
		var payload: Dictionary = parsed_any
		var message_any: Variant = payload.get("message", {})
		if typeof(message_any) == TYPE_DICTIONARY:
			var content_delta: String = String(
				(message_any as Dictionary).get("content", "")
			)
			if not content_delta.is_empty():
				chunks.append(content_delta)
				if not request_id.is_empty():
					chunk_received.emit(request_id, content_delta)
		if bool(payload.get("done", false)):
			final_payload = payload.duplicate(true)
	return {
		"remaining": remaining,
		"chunks": chunks,
		"final": final_payload,
	}


func _wait_for_connection(
	client: HTTPClient,
	request_id: String,
	started_msec: int,
	timeout_seconds: float
) -> Dictionary:
	while client.get_status() in [
		HTTPClient.STATUS_RESOLVING,
		HTTPClient.STATUS_CONNECTING,
	]:
		if _is_cancelled(request_id):
			return {"success": false, "error": "cancelled"}
		if _has_timed_out(started_msec, timeout_seconds):
			return {"success": false, "error": "timeout"}
		client.poll()
		await get_tree().process_frame
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"success": false, "error": "ollama_unreachable"}
	return {"success": true}


func _read_response(
	client: HTTPClient,
	request_id: String,
	started_msec: int,
	timeout_seconds: float
) -> Dictionary:
	var buffer: String = ""
	var content: String = ""
	var final_payload: Dictionary = {}
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		if _is_cancelled(request_id):
			return {"success": false, "error": "cancelled"}
		if _has_timed_out(started_msec, timeout_seconds):
			return {"success": false, "error": "timeout"}
		client.poll()
		await get_tree().process_frame
	if client.get_response_code() != 200:
		return {
			"success": false,
			"error": "ollama_http_%d" % client.get_response_code(),
		}
	while client.get_status() == HTTPClient.STATUS_BODY:
		if _is_cancelled(request_id):
			return {"success": false, "error": "cancelled"}
		if _has_timed_out(started_msec, timeout_seconds):
			return {"success": false, "error": "timeout"}
		client.poll()
		var body_chunk: PackedByteArray = client.read_response_body_chunk()
		if not body_chunk.is_empty():
			buffer += body_chunk.get_string_from_utf8()
			var parsed: Dictionary = parse_ndjson_lines(
				buffer,
				request_id
			)
			buffer = String(parsed.get("remaining", ""))
			for delta_any: Variant in parsed.get("chunks", []):
				content += String(delta_any)
			var final_any: Variant = parsed.get("final", {})
			if typeof(final_any) == TYPE_DICTIONARY:
				var resolved_final: Dictionary = final_any
				if not resolved_final.is_empty():
					final_payload = resolved_final
		await get_tree().process_frame
	if not buffer.strip_edges().is_empty():
		var trailing: Dictionary = parse_ndjson_lines(
			buffer + "\n",
			request_id
		)
		for delta_any: Variant in trailing.get("chunks", []):
			content += String(delta_any)
		var trailing_final_any: Variant = trailing.get("final", {})
		if typeof(trailing_final_any) == TYPE_DICTIONARY:
			var trailing_final: Dictionary = trailing_final_any
			if not trailing_final.is_empty():
				final_payload = trailing_final
	return {
		"success": true,
		"response": content.strip_edges(),
		"raw_final": final_payload,
		"request_id": request_id,
	}


func _is_cancelled(request_id: String) -> bool:
	return bool(_cancelled_ids.get(request_id, false))


func _has_timed_out(started_msec: int, timeout_seconds: float) -> bool:
	return (
		Time.get_ticks_msec() - started_msec
		> int(timeout_seconds * 1000.0)
	)


func _release(request_id: String) -> void:
	var client_any: Variant = _clients.get(request_id)
	if client_any is HTTPClient:
		(client_any as HTTPClient).close()
	_clients.erase(request_id)
	_cancelled_ids.erase(request_id)
