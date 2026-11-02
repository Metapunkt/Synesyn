extends Node
class_name HubProcessManager

# Minimal v0 process manager for Synesyn Hub (local-only).
# Responsibilities:
# - Start/stop hub process (no CLI for end users)
# - Poll /health + /status for UI
# - Call /workspace/select on demand

signal hub_started(pid: int)
signal hub_stopped()
signal hub_health_updated(ok: bool, payload: Dictionary)
signal hub_status_updated(payload: Dictionary)
signal hub_error(message: String)

@export var hub_base_url: String = "http://127.0.0.1:17777"
@export var poll_interval_sec: float = 1.0

# A hub that answered /health this recently is treated as still serving.
# Polling runs once a second, so this tolerates one missed tick.
const _SERVING_STALE_MS := 4000

var _pid: int = -1
var _poll_timer: Timer
var _http_poll: HTTPRequest
var _http_api: HTTPRequest
var _poll_inflight: bool = false
var _is_serving: bool = false
var _serving_known_ms: int = 0

func _disable_proxy_for_local(http: HTTPRequest, url: String) -> void:
	# On some Windows setups, system proxies can interfere even with localhost calls.
	# Disable proxies for local hub requests.
	if not is_instance_valid(http):
		return
	var u := String(url).strip_edges().to_lower()
	var is_local := (u.find("127.0.0.1") != -1) or (u.find("localhost") != -1) or (u.find("[::1]") != -1)
	if not is_local:
		return
	http.set_http_proxy("", -1)
	http.set_https_proxy("", -1)

func _ready() -> void:
	# Prefer runtime config (Documents/Synesyn/.../synesyn_client.json) over project defaults.
	# This keeps exports configurable without editing project.godot.
	var cfg: Dictionary = RuntimeConfig.load_config()
	# Use the global class_name ProviderModePolicy; do not shadow it with a preload var.
	hub_base_url = str(ProviderModePolicy.get_hub_base_url(cfg)).strip_edges()

	# Use two HTTPRequest nodes:
	# - _http_poll for the periodic /health + /status polling
	# - _http_api for ad-hoc UI calls (e.g. /workspace, /workspace/select)
	# This avoids ERR_BUSY races where polling blocks UI requests.
	_http_poll = HTTPRequest.new()
	add_child(_http_poll)
	_disable_proxy_for_local(_http_poll, hub_base_url)

	_http_api = HTTPRequest.new()
	add_child(_http_api)
	_disable_proxy_for_local(_http_api, hub_base_url)

	_poll_timer = Timer.new()
	_poll_timer.wait_time = poll_interval_sec
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_poll)
	add_child(_poll_timer)
	# Always poll health/status, even if this manager didn't spawn the hub process.
	# This makes UI panels (e.g. Services) reflect externally started hubs.
	_poll_timer.start()
	# Kick an immediate poll so the UI doesn't sit at "unknown".
	call_deferred("_poll")

func is_running() -> bool:
	if _pid <= 0:
		return false
	# If the child process died (common after reboot/crash), don't report "running".
	# This prevents false-positive UI states like "Hub: running" while the port is closed.
	if OS.has_method("is_process_running"):
		return OS.is_process_running(_pid)
	return true

func get_pid() -> int:
	return _pid

func is_reachable() -> bool:
	# True when a hub answered /health recently, whether or not this client
	# spawned it. An orphan left behind by an abnormal exit still answers and
	# still holds the port, so this is what Start and Stop must key on rather
	# than a PID this client happens to remember.
	if _serving_known_ms <= 0:
		return false
	if (int(Time.get_ticks_msec()) - _serving_known_ms) > _SERVING_STALE_MS:
		return false
	return _is_serving

func start_hub(exec_path: String, args: Array[String] = []) -> bool:
	if is_running():
		return true
	# Something already serves this port. A second hub would fail to bind and
	# exit immediately, and because the build is --noconsole that failure is
	# invisible, so the UI would report a start that never happened. Adopt the
	# running hub instead. get_pid() stays -1 so callers do not register a
	# process this client does not own for kill-on-exit.
	if is_reachable():
		_poll_timer.start()
		return true
	if exec_path.is_empty():
		hub_error.emit("Hub exec path is empty")
		return false
	if not FileAccess.file_exists(exec_path):
		hub_error.emit("Hub exec not found: %s" % exec_path)
		return false

	# Non-blocking process.
	_pid = OS.create_process(exec_path, args, false)
	if _pid <= 0:
		hub_error.emit("Failed to start hub process")
		_pid = -1
		return false

	_poll_timer.start()
	hub_started.emit(_pid)
	return true

func stop_hub() -> void:
	if not is_running():
		return
	# Stop polling first to avoid overlapping requests while shutting down.
	_poll_timer.stop()
	# Best-effort: cancel any in-flight request to prevent ERR_BUSY spam.
	if is_instance_valid(_http_poll) and _http_poll.has_method("cancel_request"):
		_http_poll.cancel_request()
	if is_instance_valid(_http_api) and _http_api.has_method("cancel_request"):
		_http_api.cancel_request()
	OS.kill(_pid)
	_pid = -1
	# Resume polling so the UI follows the hub down instead of holding the last
	# state it saw before the kill.
	_poll_timer.start()
	hub_stopped.emit()

func stop_hub_async() -> bool:
	# Stop the local hub whether or not this client spawned it.
	#
	# When the client exits abnormally (crash, force-quit, or an OS kill under
	# memory pressure) the exit handlers never run and the hub survives as an
	# orphan holding port 17777. A PID-only stop cannot reach it, which left the
	# only remedies as Task Manager or a reboot. The hub's /admin/shutdown is
	# local-only, so ask it to exit itself.
	if is_running():
		stop_hub()
		return true
	if not is_reachable():
		return false
	var res: Dictionary = await _post_json(hub_base_url.rstrip("/") + "/admin/shutdown", {})
	if not bool(res.get("ok", false)):
		hub_error.emit("Could not stop the hub: %s" % str(res.get("error", "no response")))
		return false
	_is_serving = false
	_pid = -1
	hub_stopped.emit()
	return true

func _poll() -> void:
	# If the hub process died, stop polling and surface a clear status.
	if _pid > 0 and OS.has_method("is_process_running") and not OS.is_process_running(_pid):
		_poll_timer.stop()
		_pid = -1
		hub_stopped.emit()
		hub_health_updated.emit(false, {"ok": false, "reason": "hub_process_exited"})
		_poll_inflight = false
		return
	if _poll_inflight:
		return
	_poll_inflight = true
	# Health
	var health = await _get_json_poll(hub_base_url.rstrip("/") + "/health")
	# Track whether anything is serving the port, separately from whether the
	# payload reports a configured workspace. A "busy" result means this poll
	# overlapped an earlier one, which says nothing about the hub, so it must not
	# be recorded as the hub having gone away.
	var is_busy: bool = (not bool(health.get("ok", false))) and str(health.get("error", "")) == "busy"
	if not is_busy:
		_is_serving = bool(health.get("ok", false))
		_serving_known_ms = int(Time.get_ticks_msec())
	if health.ok:
		hub_health_updated.emit(health.data.get("ok", false) == true, health.data)
	else:
		hub_health_updated.emit(false, {"ok": false, "error": health.error})

	# Status (best-effort)
	var status = await _get_json_poll(hub_base_url.rstrip("/") + "/status")
	if status.ok:
		hub_status_updated.emit(status.data)
	_poll_inflight = false

func select_workspace(workspace_name: String, slug: String, root: String = "") -> Dictionary:
	var payload := {"name": workspace_name, "slug": slug}
	if not root.is_empty():
		# IMPORTANT (back-compat across hub builds):
		# The Services panel treats "Root" as a *base folder* that will contain the slug.
		# Some hub builds interpret `root` as the *workspace root* directly.
		# To make "set slug -> create new workspace folder" work reliably, always send a
		# workspace-root path when root is provided.
		var base_root := str(root).strip_edges()
		var s := str(slug).strip_edges()
		if s.is_empty():
			payload["root"] = base_root
		else:
			var br_norm := base_root.replace("\\", "/").trim_suffix("/")
			var s_norm := s.replace("\\", "/").trim_suffix("/")
			if br_norm.ends_with("/" + s_norm):
				# Already a workspace-root.
				payload["root"] = base_root
			else:
				# Base root -> workspace root.
				payload["root"] = base_root.path_join(s)
	var res = await _post_json(hub_base_url.rstrip("/") + "/workspace/select", payload)
	if not res.ok:
		hub_error.emit(str(res.error))
	return res

func export_workspace_zip() -> Dictionary:
	var res = await _post_json(hub_base_url.rstrip("/") + "/export/session", {"scope": "all"})
	if not res.ok:
		hub_error.emit(str(res.error))
	return res

func get_workspace() -> Dictionary:
	# Returns {ok, data} where data matches GET /workspace.
	return await _get_json(hub_base_url.rstrip("/") + "/workspace")

func test_voice(text: String = "Hello.", provider_preference: String = "auto") -> Dictionary:
	var payload: Dictionary = {"text": text, "character": "Narrator", "return_lipsync": false}
	var pref := String(provider_preference).strip_edges().to_lower()
	if pref in ["edge", "edge_tts", "edgetts"]:
		payload["provider_preference"] = "edge_tts"
	elif pref in ["sapi", "pyttsx3"]:
		payload["provider_preference"] = "sapi"
	elif pref in ["sidecar", "voice_sidecar"]:
		payload["provider_preference"] = "sidecar"
	# "auto" (or unknown) omitted so hub default behavior applies.
	var res = await _post_json(hub_base_url.rstrip("/") + "/voice/speak", payload)
	if not res.ok:
		hub_error.emit(str(res.error))
	return res

func set_session_consent_save_recordings(session_id: String, enabled: bool) -> Dictionary:
	var sid := String(session_id).strip_edges()
	if sid.is_empty():
		return {"ok": false, "error": "session_id is required"}
	var payload := {"save_recordings": (enabled == true)}
	var res = await _post_json(hub_base_url.rstrip("/") + ("/substrate/sessions/%s/consent" % sid), payload)
	if not res.ok:
		hub_error.emit(str(res.error))
	return res

func _parse_json_body(body: PackedByteArray) -> Variant:
	var s := body.get_string_from_utf8()
	if s.is_empty():
		return {}
	return JSON.parse_string(s)

func _get_json(url: String) -> Dictionary:
	var result = await _http_request(_http_api, url, HTTPClient.METHOD_GET, {})
	return result

func _post_json(url: String, obj: Dictionary) -> Dictionary:
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify(obj)
	return await _http_request(_http_api, url, HTTPClient.METHOD_POST, {"headers": headers, "body": body})

func _http_request(http: HTTPRequest, url: String, method: int, options: Dictionary) -> Dictionary:
	# Avoid ERR_BUSY spam from overlapping UI polls (e.g. Services panel label refresh).
	# If a request is already in-flight on this HTTPRequest node, skip this tick.
	if http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return {"ok": false, "error": "busy"}
	var headers: PackedStringArray = PackedStringArray(options.get("headers", PackedStringArray()))
	var body: String = str(options.get("body", ""))
	var err: int = http.request(url, headers, method, body)
	if err != OK:
		return {"ok": false, "error": "HTTPRequest.request failed: %s" % error_string(err)}

	var completed = await http.request_completed
	var result_code: int = completed[0]
	var response_code: int = completed[1]
	var _resp_headers: PackedStringArray = completed[2]
	var resp_body: PackedByteArray = completed[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "HTTP request failed: %s" % result_code}

	var data = _parse_json_body(resp_body)
	if response_code < 200 or response_code >= 300:
		return {"ok": false, "error": {"status": response_code, "body": data}}
	return {"ok": true, "data": data, "status": response_code}

func _get_json_poll(url: String) -> Dictionary:
	return await _http_request(_http_poll, url, HTTPClient.METHOD_GET, {})
