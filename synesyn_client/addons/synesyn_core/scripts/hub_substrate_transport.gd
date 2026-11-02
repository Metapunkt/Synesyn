extends Node
class_name HubSubstrateTransport

# Transport / plumbing layer for the Synesyn hub client.
#
# This base class owns everything that is NOT a domain endpoint: connection
# state, auth, the HTTP verb helpers (_post_json/_get_json/_delete_json/_patch_json),
# the WebSocket event loop, and the stateless request-policy helpers.
#
# `HubSubstrateClient` extends this class and adds the typed endpoint wrappers,
# so callers keep a single object with the full API (methods and signals are
# inherited). The dependency is one-directional: this base never calls into the
# client subclass.

signal request_failed(message: String)
signal ws_connected()
signal ws_disconnected()
signal hub_event_received(event: Dictionary)
signal job_progress(job_id: String, payload: Dictionary)
signal job_done(job_id: String, status: String, payload: Dictionary)

var base_url: String = "http://127.0.0.1:17777"
var auth_enabled: bool = false
var auth_token: String = ""
var _ws: WebSocketPeer
var _ws_url: String = ""
var _ws_ready: bool = false
var _ws_subscribed_event_types: Array[String] = []
var _ws_replay_pending: Dictionary = {} # {window_sec, event_types}
var _workspace_root_cache: String = ""

static func _is_local_url(url: String) -> bool:
	var u := String(url).strip_edges().to_lower()
	return (u.find("127.0.0.1") != -1) or (u.find("localhost") != -1) or (u.find("[::1]") != -1)

static func _disable_proxy_for_local(http: HTTPRequest, url: String) -> void:
	# On some Windows setups, system proxies can interfere even with localhost calls.
	# We disable proxies for local hub URLs only.
	if not is_instance_valid(http):
		return
	if not _is_local_url(url):
		return
	http.set_http_proxy("", -1)
	http.set_https_proxy("", -1)

static func _default_timeout_sec_for_url(url: String) -> float:
	# Give local calls a generous budget to tolerate cold starts, AV scans, and sqlite warmups.
	# (We still avoid "infinite" timeouts to prevent editor hangs.)
	if url.ends_with("/substrate/query"):
		return 60.0
	if url.ends_with("/health") or url.ends_with("/status") or url.ends_with("/workspace"):
		return 10.0
	return 20.0

static func _should_retry_timeout(url: String, result_code: int) -> bool:
	if result_code != HTTPRequest.RESULT_TIMEOUT:
		return false
	# Only retry local hub calls.
	if not _is_local_url(url):
		return false
	# Only retry the heavier endpoints where timeouts are most common.
	return url.ends_with("/substrate/query")

static func _should_retry_connect(url: String, result_code: int) -> bool:
	# Retrying cant_connect helps when Godot starts before the hub binds its port.
	if result_code != HTTPRequest.RESULT_CANT_CONNECT:
		return false
	return _is_local_url(url)

static func _retry_delay_sec_for_attempt(attempt: int) -> float:
	# Short backoff: 0.15s, 0.35s, 0.75s.
	if attempt <= 0:
		return 0.15
	if attempt == 1:
		return 0.35
	return 0.75

static func _http_result_to_string(result_code: int) -> String:
	# Human-readable name for HTTPRequest.RESULT_* codes.
	match result_code:
		HTTPRequest.RESULT_SUCCESS:
			return "success"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "chunked_body_size_mismatch"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "cant_connect"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "cant_resolve"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "connection_error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "tls_handshake_error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "no_response"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "body_size_limit_exceeded"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "body_decompress_failed"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "request_failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "download_file_cant_open"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "download_file_write_error"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "redirect_limit_reached"
		HTTPRequest.RESULT_TIMEOUT:
			return "timeout"
		_:
			return str(result_code)

func _ready() -> void:
	set_process(true)
	_ws = WebSocketPeer.new()

func _post_json(url: String, obj: Dictionary) -> Dictionary:
	var headers := ["Content-Type: application/json"]
	if auth_enabled and not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)
	var body := JSON.stringify(obj)
	var http := HTTPRequest.new()
	# Editor/runtime safety: don't allow requests to hang indefinitely.
	# (Hangs inside @tool code can appear as editor freezes/crashes.)
	# Note: /substrate/query can be slow on cold start (sqlite cache warmup, file locks, antivirus scans),
	# so give it a longer budget than typical control-plane calls.
	http.timeout = _default_timeout_sec_for_url(url)
	http.use_threads = true
	add_child(http)
	_disable_proxy_for_local(http, url)
	var err = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "HTTPRequest.request failed: %s" % error_string(err), "url": url}

	var completed: Array = await http.request_completed
	http.queue_free()
	var result_code: int = completed[0]
	var response_code: int = completed[1]
	var resp_body: PackedByteArray = completed[3]

	# Short retries for local "can't connect" (hub still starting/binding).
	if _should_retry_connect(url, result_code):
		for attempt in range(3):
			await get_tree().create_timer(_retry_delay_sec_for_attempt(attempt)).timeout
			var httpc := HTTPRequest.new()
			httpc.timeout = _default_timeout_sec_for_url(url)
			httpc.use_threads = true
			add_child(httpc)
			_disable_proxy_for_local(httpc, url)
			var errc := httpc.request(url, headers, HTTPClient.METHOD_POST, body)
			if errc == OK:
				var donec: Array = await httpc.request_completed
				httpc.queue_free()
				result_code = donec[0]
				response_code = donec[1]
				resp_body = donec[3]
				if result_code != HTTPRequest.RESULT_CANT_CONNECT:
					break
			else:
				httpc.queue_free()

	# One-shot retry for local slow cold-start queries.
	if _should_retry_timeout(url, result_code):
		var http2 := HTTPRequest.new()
		http2.timeout = max(_default_timeout_sec_for_url(url) * 1.5, 90.0)
		http2.use_threads = true
		add_child(http2)
		_disable_proxy_for_local(http2, url)
		var err2 := http2.request(url, headers, HTTPClient.METHOD_POST, body)
		if err2 == OK:
			var completed2: Array = await http2.request_completed
			http2.queue_free()
			result_code = completed2[0]
			response_code = completed2[1]
			resp_body = completed2[3]
		else:
			http2.queue_free()

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"error": "HTTP request failed: %s (%s)" % [result_code, _http_result_to_string(result_code)],
			"url": url,
			"http_status": response_code,
		}

	var parsed: Variant = {}
	var s := resp_body.get_string_from_utf8()
	if not s.is_empty():
		# Avoid JSON parse errors for plain-text error bodies like "Internal Server Error".
		var t0 := s.strip_edges()
		if t0.begins_with("{") or t0.begins_with("["):
			parsed = JSON.parse_string(t0)
		else:
			parsed = t0

	if response_code < 200 or response_code >= 300:
		return {
			"ok": false,
			"error": {"status": response_code, "body": parsed, "body_raw": s},
			"url": url,
			"http_status": response_code
		}

	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {"ok": true, "data": parsed}

func _get_json(url: String) -> Dictionary:
	var headers := ["Accept: application/json"]
	if auth_enabled and not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)
	var http := HTTPRequest.new()
	http.timeout = _default_timeout_sec_for_url(url)
	http.use_threads = true
	add_child(http)
	_disable_proxy_for_local(http, url)
	var err = http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "HTTPRequest.request failed: %s" % error_string(err), "url": url}
	var completed: Array = await http.request_completed
	http.queue_free()
	var result_code: int = completed[0]
	var response_code: int = completed[1]
	var resp_body: PackedByteArray = completed[3]
	# Short retries for local "can't connect" (hub still starting/binding).
	if _should_retry_connect(url, result_code):
		for attempt in range(3):
			await get_tree().create_timer(_retry_delay_sec_for_attempt(attempt)).timeout
			var httpc := HTTPRequest.new()
			httpc.timeout = _default_timeout_sec_for_url(url)
			httpc.use_threads = true
			add_child(httpc)
			_disable_proxy_for_local(httpc, url)
			var errc := httpc.request(url, headers, HTTPClient.METHOD_GET)
			if errc == OK:
				var donec: Array = await httpc.request_completed
				httpc.queue_free()
				result_code = donec[0]
				response_code = donec[1]
				resp_body = donec[3]
				if result_code != HTTPRequest.RESULT_CANT_CONNECT:
					break
			else:
				httpc.queue_free()
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"error": "HTTP request failed: %s (%s)" % [result_code, _http_result_to_string(result_code)],
			"url": url,
			"http_status": response_code,
		}
	if response_code < 200 or response_code >= 300:
		var error_body: String = resp_body.get_string_from_utf8()
		var error_payload: Variant = error_body
		if error_body.strip_edges().begins_with("{") or error_body.strip_edges().begins_with("["):
			var error_json := JSON.new()
			if error_json.parse(error_body) == OK:
				error_payload = error_json.data
		return {"ok": false, "error": {"status": response_code, "body": error_payload}, "url": url, "http_status": response_code}
	var parsed: Variant = {}
	var s: String = resp_body.get_string_from_utf8()
	if not s.is_empty():
		var json := JSON.new()
		if json.parse(s) == OK:
			parsed = json.data
		else:
			return {"ok": false, "error": "Response was not valid JSON", "body": s, "url": url, "http_status": response_code}
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {"ok": true, "data": parsed}

func _delete_json(url: String) -> Dictionary:
	var headers := ["Accept: application/json"]
	if auth_enabled and not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	_disable_proxy_for_local(http, url)
	var err = http.request(url, headers, HTTPClient.METHOD_DELETE)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "HTTPRequest.request failed: %s" % error_string(err), "url": url}
	var completed: Array = await http.request_completed
	http.queue_free()

	var result_code: int = completed[0]
	var response_code: int = completed[1]
	var resp_body: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"error": "HTTP request failed: %s (%s)" % [result_code, _http_result_to_string(result_code)],
			"url": url,
			"http_status": response_code,
		}

	var parsed: Variant = {}
	var s := resp_body.get_string_from_utf8()
	if not s.is_empty():
		parsed = JSON.parse_string(s)

	if response_code < 200 or response_code >= 300:
		return {"ok": false, "error": {"status": response_code, "body": parsed}, "url": url, "http_status": response_code}

	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {"ok": true, "data": parsed}

func _patch_json(url: String, obj: Dictionary) -> Dictionary:
	var headers := ["Content-Type: application/json"]
	if auth_enabled and not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)
	var body := JSON.stringify(obj)
	var http := HTTPRequest.new()
	http.timeout = _default_timeout_sec_for_url(url)
	http.use_threads = true
	add_child(http)
	_disable_proxy_for_local(http, url)
	var err = http.request(url, headers, HTTPClient.METHOD_PATCH, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "HTTPRequest.request failed: %s" % error_string(err), "url": url}
	var completed: Array = await http.request_completed
	http.queue_free()
	var result_code: int = completed[0]
	var response_code: int = completed[1]
	var resp_body: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"error": "HTTP request failed: %s (%s)" % [result_code, _http_result_to_string(result_code)],
			"url": url,
			"http_status": response_code,
		}
	var parsed: Variant = {}
	var s := resp_body.get_string_from_utf8()
	if not s.is_empty():
		var t0 := s.strip_edges()
		if t0.begins_with("{") or t0.begins_with("["):
			parsed = JSON.parse_string(t0)
		else:
			parsed = t0
	if response_code < 200 or response_code >= 300:
		return {
			"ok": false,
			"error": {"status": response_code, "body": parsed, "body_raw": s},
			"url": url,
			"http_status": response_code
		}
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {"ok": true, "data": parsed}

func _get_workspace_root() -> String:
	if not _workspace_root_cache.is_empty():
		return _workspace_root_cache
	# v0+ hubs expose /workspace and return {"ok": true, "workspace": {"root": "..."}}
	var url := base_url.rstrip("/") + "/workspace"
	var res: Dictionary = await _get_json(url)
	if not bool(res.get("ok", false)):
		return ""
	var ws_any: Variant = res.get("workspace", null)
	if typeof(ws_any) != TYPE_DICTIONARY:
		return ""
	var ws: Dictionary = ws_any
	var root := str(ws.get("root", "")).strip_edges()
	if root.is_empty():
		return ""
	_workspace_root_cache = root
	return root

func ensure_ws_connected() -> bool:
	# Hub WS endpoint is always /ws/events; newer hubs support subscribe/replay filtering.
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		return true
	if _ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		return false
	var http := base_url.strip_edges()
	if http.is_empty():
		return false
	var ws_url := http.replace("http://", "ws://").replace("https://", "wss://")
	ws_url = ws_url.rstrip("/") + "/ws/events"
	if _ws_url != ws_url:
		_ws_url = ws_url
	var err := _ws.connect_to_url(ws_url)
	if err != OK:
		return false
	return true

func ws_subscribe(event_types: Array[String]) -> void:
	# v1: server-side filtering via WS subscribe.
	_ws_subscribed_event_types = event_types.duplicate()
	_try_send_ws_subscribe()

func ws_replay(window_sec: float = 5.0, event_types: Array[String] = []) -> void:
	# v1: request ring-buffer replay within a time window.
	_ws_replay_pending = {"window_sec": float(window_sec), "event_types": event_types.duplicate()}
	_try_send_ws_replay()

func _try_send_ws_subscribe() -> void:
	if not _ws:
		return
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var msg := {"type": "subscribe", "event_types": _ws_subscribed_event_types}
	_ws.send_text(JSON.stringify(msg))

func _try_send_ws_replay() -> void:
	if not _ws:
		return
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if _ws_replay_pending.is_empty():
		return
	var msg := {
		"type": "replay",
		"window_sec": float(_ws_replay_pending.get("window_sec", 5.0)),
		"event_types": _ws_replay_pending.get("event_types", []),
	}
	_ws.send_text(JSON.stringify(msg))
	_ws_replay_pending = {}

func _process(_delta: float) -> void:
	if not _ws:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _ws_ready:
			_ws_ready = true
			ws_connected.emit()
			_try_send_ws_subscribe()
			_try_send_ws_replay()
		while _ws.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _ws.get_packet()
			var txt := pkt.get_string_from_utf8()
			if txt.is_empty():
				continue
			# Guard: avoid JSON parse errors in logs if a server ever sends a plaintext message.
			var t0 := txt.strip_edges()
			if not (t0.begins_with("{") or t0.begins_with("[")):
				continue
			var any: Variant = JSON.parse_string(t0)
			if typeof(any) != TYPE_DICTIONARY:
				continue
			var msg: Dictionary = any
			if str(msg.get("type", "")) != "event":
				continue
			var evt_any: Variant = msg.get("data", null)
			if typeof(evt_any) != TYPE_DICTIONARY:
				continue
			var evt: Dictionary = evt_any
			hub_event_received.emit(evt)

			var et := str(evt.get("event_type", ""))
			if et.begins_with("job."):
				var payload_any: Variant = evt.get("payload", {})
				var payload: Dictionary = payload_any if typeof(payload_any) == TYPE_DICTIONARY else {}
				var jid := str(payload.get("job_id", "")).strip_edges()
				if jid.is_empty():
					continue
				if et == "job.progress":
					job_progress.emit(jid, payload)
				elif et == "job.completed":
					job_done.emit(jid, "completed", payload)
				elif et == "job.failed":
					job_done.emit(jid, "failed", payload)
	elif state in [WebSocketPeer.STATE_CLOSED, WebSocketPeer.STATE_CLOSING]:
		if _ws_ready:
			_ws_ready = false
			ws_disconnected.emit()
