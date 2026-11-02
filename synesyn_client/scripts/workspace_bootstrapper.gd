extends Node

## Purpose:
## - Make "last applied workspace" deterministic across restarts.
## - Do NOT rely on UI scenes (which can be freed mid-async when changing scenes).
## - Broadcast global hub health transitions so every scene can react without
##   each wiring its own HubSubstrateClient instance.
##
## Data sources:
## - Documents/Synesyn/synesyn/config/workspace_state.json (preferred)
## - user://workspace_state.json (fallback)
##
## Behavior:
## - Wait for Hub health OK (local hubs only).
## - POST /workspace/select with persisted name/slug/root.
## - Verify via GET /workspace until it matches (or timeout).
## - Poll /health every few seconds; emit hub_connection_changed on transitions.
## - On app exit, best-effort stop the local hub if hub.stop_on_exit==true.

## Emitted when hub reachability transitions (true = just came online, false = just went offline).
signal hub_connection_changed(is_connected: bool)

const _STATE_FILENAME := "workspace_state.json"
const _DEFAULT_WORKSPACES_DIRNAME := "Workspaces"
const _LOG_FILENAME := "workspace_bootstrapper.log"
const _HEALTH_POLL_INTERVAL_SEC := 5.0

var _http: HTTPRequest
var _http_shutdown: HTTPRequest
var _http_health: HTTPRequest
var _health_poll_timer: Timer
var _hub_health_ok: bool = false
var _hub_health_known: bool = false
var _health_poll_inflight: bool = false
var _inflight: bool = false

# Hub lifecycle (local-only).
# A list, not a single pid: the Launcher and VoiceService both autostart a hub
# and both check reachability first, but on a cold start neither sees the other's
# process yet and they can spawn within a few seconds of each other. When this
# held one pid, the second registration overwrote the first and that hub could
# never be stopped by the app again — it survived as an orphan holding port
# 17777 and its share of memory until the user found it in Task Manager or
# rebooted.
var _hub_pids_started_by_client: Array[int] = []
var _hub_exec_path_started_by_client: String = ""

# --- Global hub-status notification banner ---
# Rendered above every scene via a CanvasLayer so no per-scene TSCN changes needed.
var _banner_canvas: CanvasLayer
var _banner_panel: PanelContainer
var _banner_label: Label
var _banner_dismiss_timer: Timer
var _banner_visible: bool = false

func register_hub_process(pid: int, exec_path: String = "") -> void:
	# Called by Launcher/VoiceService when they spawn a local hub process.
	# This lets the autoload enforce hub.stop_on_exit deterministically even if
	# HTTP shutdown cannot run during teardown.
	var hub_pid := int(pid)
	if hub_pid <= 0:
		return
	_hub_exec_path_started_by_client = String(exec_path).strip_edges()
	if _hub_pids_started_by_client.has(hub_pid):
		return
	_hub_pids_started_by_client.append(hub_pid)
	_log("hub_pid_registered pid=%s tracked=%d exec_path='%s'" % [
		str(hub_pid),
		_hub_pids_started_by_client.size(),
		_hub_exec_path_started_by_client,
	])

func clear_hub_process_registration() -> void:
	_hub_pids_started_by_client.clear()
	_hub_exec_path_started_by_client = ""

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	# Use threads to avoid blocking the main thread.
	_http.use_threads = true

	# Dedicated channel for best-effort hub shutdown on app exit.
	# Keep separate from workspace bootstrap traffic to avoid "busy" conflicts.
	_http_shutdown = HTTPRequest.new()
	add_child(_http_shutdown)
	# Keep shutdown request non-threaded so it can fire during teardown.
	_http_shutdown.use_threads = false

	# Dedicated channel for ongoing health polling (never blocks workspace HTTP).
	_http_health = HTTPRequest.new()
	_http_health.use_threads = true
	add_child(_http_health)

	_health_poll_timer = Timer.new()
	_health_poll_timer.wait_time = _HEALTH_POLL_INTERVAL_SEC
	_health_poll_timer.one_shot = false
	_health_poll_timer.timeout.connect(_poll_hub_health)
	add_child(_health_poll_timer)
	_health_poll_timer.start()

	_setup_hub_banner()

	# Prefer the window close signal (fires before node teardown).
	var root := get_tree().root
	if is_instance_valid(root) and root.has_signal("close_requested"):
		# Avoid duplicate connections across hot reloads.
		if not root.close_requested.is_connected(_on_close_requested):
			root.close_requested.connect(_on_close_requested)
	call_deferred("_run")

func is_hub_reachable() -> bool:
	return _hub_health_known and _hub_health_ok

func is_hub_health_known() -> bool:
	return _hub_health_known

# --- Hub notification banner ---

func _setup_hub_banner() -> void:
	_banner_canvas = CanvasLayer.new()
	_banner_canvas.layer = 64  # above all game UI
	add_child(_banner_canvas)

	_banner_panel = PanelContainer.new()
	_banner_panel.visible = false
	_banner_panel.anchors_preset = Control.PRESET_TOP_WIDE
	_banner_panel.anchor_left = 0.0
	_banner_panel.anchor_top = 0.0
	_banner_panel.anchor_right = 1.0
	_banner_panel.anchor_bottom = 0.0
	_banner_panel.offset_bottom = 52.0
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_canvas.add_child(_banner_panel)

	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_panel.add_child(_banner_label)

	_banner_dismiss_timer = Timer.new()
	_banner_dismiss_timer.one_shot = true
	_banner_dismiss_timer.timeout.connect(_hide_hub_banner)
	add_child(_banner_dismiss_timer)

## Show a banner across the top of the screen.
## color: Color for the panel background.
## auto_dismiss_sec: > 0 → auto-hide after this many seconds; <= 0 → persistent until next call.
func show_hub_notification(message: String, banner_color: Color, auto_dismiss_sec: float = 0.0) -> void:
	if not is_instance_valid(_banner_label):
		return
	var style := StyleBoxFlat.new()
	style.bg_color = banner_color
	_banner_panel.add_theme_stylebox_override("panel", style)
	_banner_label.text = message
	# Pick readable text colour (white on dark, black on light).
	var luminance: float = 0.299 * banner_color.r + 0.587 * banner_color.g + 0.114 * banner_color.b
	_banner_label.add_theme_color_override("font_color", Color.WHITE if luminance < 0.5 else Color.BLACK)
	_banner_panel.visible = true
	_banner_visible = true
	_banner_dismiss_timer.stop()
	if auto_dismiss_sec > 0.0:
		_banner_dismiss_timer.wait_time = auto_dismiss_sec
		_banner_dismiss_timer.start()

func _hide_hub_banner() -> void:
	if is_instance_valid(_banner_panel):
		_banner_panel.visible = false
	_banner_visible = false

func _on_close_requested() -> void:
	_shutdown_hub_best_effort()

func _notification(what: int) -> void:
	# Autoload persists across scene changes, so this is the right place to
	# implement "stop hub on app exit" when the Launcher scene isn't active.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown_hub_best_effort()

func _exit_tree() -> void:
	# Fallback for editor stop / teardown paths that may not emit WM_CLOSE_REQUEST.
	_shutdown_hub_best_effort()

func _shutdown_hub_best_effort() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var hub_cfg_any: Variant = cfg.get("hub", {})
	var hub_cfg: Dictionary = hub_cfg_any as Dictionary if typeof(hub_cfg_any) == TYPE_DICTIONARY else {}
	if not bool(hub_cfg.get("stop_on_exit", true)):
		return

	# PID kill is more reliable than HTTP during teardown: do it first.
	# Only kill processes THIS client spawned (not an externally running hub).
	# Kill every one we spawned: a hub that lost the port race still holds its
	# memory, so leaving any behind is what strands the machine.
	if not _hub_pids_started_by_client.is_empty():
		for hub_pid in _hub_pids_started_by_client:
			if hub_pid <= 0:
				continue
			if OS.has_method("is_process_running") and OS.is_process_running(hub_pid):
				_log("hub_shutdown killing_pid=%s" % str(hub_pid))
				OS.kill(hub_pid)
		# Always clear so a reused PID isn't mistakenly killed on a future run.
		clear_hub_process_registration()

	# HTTP /admin/shutdown: best-effort, only if the node is still usable.
	# During NOTIFICATION_WM_CLOSE_REQUEST the tree is alive; during _exit_tree
	# children may already be detached, making request() return ERR_UNCONFIGURED.
	var base_url := str(ProviderModePolicy.get_hub_base_url(cfg)).strip_edges()
	if base_url.is_empty() or (not _is_local_url(base_url)):
		return
	if not is_instance_valid(_http_shutdown):
		return
	if not _http_shutdown.is_inside_tree():
		return
	if _http_shutdown.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return

	_disable_proxy_for_local(base_url)
	_http_shutdown.set_http_proxy("", -1)
	_http_shutdown.set_https_proxy("", -1)
	_http_shutdown.timeout = 1.5
	var url := base_url.rstrip("/") + "/admin/shutdown"
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _http_shutdown.request(url, headers, HTTPClient.METHOD_POST, "{}")
	if err != OK:
		_log("hub_shutdown request_failed: %s" % error_string(err))

func _run() -> void:
	if _inflight:
		return
	_inflight = true
	_log("start")
	await _ensure_workspace_selected()
	_log("done")
	_inflight = false

func _poll_hub_health() -> void:
	if _health_poll_inflight:
		return
	if not is_instance_valid(_http_health):
		return
	var cfg: Dictionary = RuntimeConfig.load_config()
	var base_url := str(ProviderModePolicy.get_hub_base_url(cfg)).strip_edges()
	if base_url.is_empty():
		return
	_health_poll_inflight = true
	var result: Dictionary = await _get_json_health(base_url.rstrip("/") + "/health", 3.0)
	_health_poll_inflight = false
	var is_ok: bool = bool(result.get("ok", false)) and bool(result.get("data", {}).get("ok", false))
	if _hub_health_known and is_ok != _hub_health_ok:
		hub_connection_changed.emit(is_ok)
		if is_ok:
			show_hub_notification(
				"Hub back online — Voice and workspace features restored.",
				Color(0.18, 0.62, 0.35),  # green
				4.0
			)
		else:
			show_hub_notification(
				"Hub offline — Voice and workspace sync paused.  AI chat continues normally.",
				Color(0.82, 0.57, 0.05),  # amber
				0.0  # persistent until reconnect
			)
	_hub_health_ok = is_ok
	_hub_health_known = true

func _get_json_health(url: String, timeout_sec: float) -> Dictionary:
	if not is_instance_valid(_http_health):
		return {"ok": false, "error": "http_missing"}
	if _http_health.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return {"ok": false, "error": "busy"}
	_disable_proxy_for_local(url)
	_http_health.set_http_proxy("", -1)
	_http_health.set_https_proxy("", -1)
	_http_health.timeout = float(timeout_sec)
	var err := _http_health.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "")
	if err != OK:
		return {"ok": false, "error": "request_failed: %s" % error_string(err)}
	var completed: Array = await _http_health.request_completed
	var result_code: int = completed[0]
	var response_code: int = completed[1]
	var resp_body: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": {"result": result_code}}
	var data: Variant = _parse_json_body(resp_body)
	if response_code < 200 or response_code >= 300:
		return {"ok": false, "error": {"status": response_code, "body": data}}
	return {"ok": true, "data": data, "status": response_code}

func _ensure_workspace_selected() -> void:
	var state: Dictionary = _load_workspace_state()
	if state.is_empty():
		_log("no_state — attempting to bootstrap a default workspace")
		await _bootstrap_default_workspace()
		return
	var name := str(state.get("name", "")).strip_edges()
	var slug := str(state.get("slug", "")).strip_edges()
	var root_base := str(state.get("root_base", "")).strip_edges()
	if name.is_empty() or slug.is_empty():
		_log("invalid_state name='%s' slug='%s'" % [name, slug])
		return
	_log("state name='%s' slug='%s' root_base='%s'" % [name, slug, root_base])

	if root_base.is_empty():
		root_base = str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).path_join("Synesyn").path_join(_DEFAULT_WORKSPACES_DIRNAME)

	var cfg: Dictionary = RuntimeConfig.load_config()
	var base_url := str(ProviderModePolicy.get_hub_base_url(cfg)).strip_edges()
	if base_url.is_empty():
		_log("no_base_url")
		return
	if not _is_local_url(base_url):
		# Never try to control a remote hub's workspace.
		_log("remote_base_url '%s' (skip)" % base_url)
		return
	_log("base_url '%s'" % base_url)

	_disable_proxy_for_local(base_url)

	# Wait for hub health.
	for _i in range(60):
		var health: Dictionary = await _get_json(base_url.rstrip("/") + "/health", 1.0)
		if bool(health.get("ok", false)) and bool(health.get("data", {}).get("ok", false)):
			_log("health_ok")
			break
		await get_tree().create_timer(0.2).timeout

	# If already matches, no-op.
	for _i in range(30):
		var ws_res: Dictionary = await _get_json(base_url.rstrip("/") + "/workspace", 2.0)
		if bool(ws_res.get("ok", false)):
			var data_any: Variant = ws_res.get("data", null)
			if typeof(data_any) == TYPE_DICTIONARY:
				var data: Dictionary = data_any
				var ws_any: Variant = data.get("workspace", null)
				if typeof(ws_any) == TYPE_DICTIONARY:
					var ws: Dictionary = ws_any
					var cur_name := str(ws.get("name", "") if ws.get("name") != null else "").strip_edges()
					var cur_slug := str(ws.get("slug", "") if ws.get("slug") != null else "").strip_edges()
					if cur_name == name and cur_slug == slug:
						_log("already_matches")
						return

		# Back-compat: send workspace-root path (base_root/slug) as "root"
		var workspace_root := root_base.path_join(slug)
		var payload := {"name": name, "slug": slug, "root": workspace_root}
		var sel := await _post_json(base_url.rstrip("/") + "/workspace/select", payload, 4.0)
		if bool(sel.get("ok", false)):
			_log("select attempt=%d ok=true" % _i)
		else:
			var err_any: Variant = sel.get("error", null)
			if err_any == null:
				err_any = sel
			var err_s: String = JSON.stringify(err_any) if typeof(err_any) in [TYPE_DICTIONARY, TYPE_ARRAY] else str(err_any)
			_log("select attempt=%d ok=false err=%s" % [_i, err_s])
		await get_tree().create_timer(0.2).timeout

func _bootstrap_default_workspace() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var base_url := str(ProviderModePolicy.get_hub_base_url(cfg)).strip_edges()
	if base_url.is_empty() or not _is_local_url(base_url):
		_log("bootstrap_default_workspace: no local hub url, skipping")
		return

	# Wait for hub health (up to ~6 s).
	var hub_ok := false
	for _i in range(30):
		var health: Dictionary = await _get_json(base_url.rstrip("/") + "/health", 1.0)
		if bool(health.get("ok", false)) and bool(health.get("data", {}).get("ok", false)):
			hub_ok = true
			break
		await get_tree().create_timer(0.2).timeout
	if not hub_ok:
		_log("bootstrap_default_workspace: hub not reachable, skipping")
		return

	var default_name := "My Workspace"
	var default_slug := "my-workspace"
	var root_base := str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).path_join("Synesyn").path_join(_DEFAULT_WORKSPACES_DIRNAME)
	var workspace_root := root_base.path_join(default_slug)
	_log("bootstrap_default_workspace: name='%s' slug='%s' root='%s'" % [default_name, default_slug, workspace_root])

	var payload := {"name": default_name, "slug": default_slug, "root": workspace_root}
	var sel: Dictionary = await _post_json(base_url.rstrip("/") + "/workspace/select", payload, 4.0)
	if bool(sel.get("ok", false)):
		_log("bootstrap_default_workspace: created OK — persisting state")
		_persist_workspace_state(default_name, default_slug, root_base)
	else:
		var err_any: Variant = sel.get("error", null)
		var err_s: String = JSON.stringify(err_any) if typeof(err_any) in [TYPE_DICTIONARY, TYPE_ARRAY] else str(err_any)
		_log("bootstrap_default_workspace: failed err=%s" % err_s)

func _persist_workspace_state(ws_name: String, slug: String, root_base: String) -> void:
	var obj := {
		"name": ws_name,
		"slug": slug,
		"root_base": root_base,
		"updated_utc": Time.get_datetime_string_from_system(true),
	}
	# Write only under Documents/Synesyn (ADR 0014). Legacy user:// is read-only.
	var cfg_path := RuntimeConfig.get_config_path_abs()
	if cfg_path.strip_edges().is_empty():
		return
	var p: String = cfg_path.get_base_dir().path_join(_STATE_FILENAME)
	var dir := p.get_base_dir()
	if not dir.strip_edges().is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(obj, "\t"))
		f.close()
		_log("persist_workspace_state: wrote %s" % p)

func _log(msg: String) -> void:
	var line := "[%s] %s\n" % [Time.get_datetime_string_from_system(true), msg]
	_write_log(line, _log_path_docs())

func _log_path_docs() -> String:
	var cfg_path := RuntimeConfig.get_config_path_abs()
	if cfg_path.strip_edges().is_empty():
		return ""
	return cfg_path.get_base_dir().path_join(_LOG_FILENAME)

func _write_log(line: String, path: String) -> void:
	if path.strip_edges().is_empty():
		return
	var dir := path.get_base_dir()
	if not dir.strip_edges().is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var prev := ""
	if FileAccess.file_exists(path):
		var fr := FileAccess.open(path, FileAccess.READ)
		if fr:
			prev = fr.get_as_text()
			fr.close()
	# keep last ~8KB
	if prev.length() > 8192:
		prev = prev.substr(prev.length() - 8192, 8192)
	var fw := FileAccess.open(path, FileAccess.WRITE)
	if fw:
		fw.store_string(prev + line)
		fw.close()

func _load_workspace_state() -> Dictionary:
	var candidates: Array[String] = []
	var cfg_path := RuntimeConfig.get_config_path_abs()
	if not cfg_path.strip_edges().is_empty():
		candidates.append(cfg_path.get_base_dir().path_join(_STATE_FILENAME))
	candidates.append(ProjectSettings.globalize_path("user://%s" % _STATE_FILENAME))

	for p in candidates:
		if p.strip_edges().is_empty() or (not FileAccess.file_exists(p)):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if not f:
			continue
		var raw := f.get_as_text()
		f.close()
		var parsed_any: Variant = JSON.parse_string(raw)
		if typeof(parsed_any) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = parsed_any
		if str(d.get("name", "")).strip_edges().is_empty():
			continue
		return d
	return {}

func _is_local_url(url: String) -> bool:
	var u := String(url).strip_edges().to_lower()
	return (u.find("127.0.0.1") != -1) or (u.find("localhost") != -1) or (u.find("[::1]") != -1)

func _disable_proxy_for_local(url: String) -> void:
	if not is_instance_valid(_http):
		return
	if not _is_local_url(url):
		return
	_http.set_http_proxy("", -1)
	_http.set_https_proxy("", -1)

func _parse_json_body(body: PackedByteArray) -> Variant:
	var s := body.get_string_from_utf8()
	if s.is_empty():
		return {}
	return JSON.parse_string(s)

func _get_json(url: String, timeout_sec: float) -> Dictionary:
	if not is_instance_valid(_http):
		return {"ok": false, "error": "http_missing"}
	_http.timeout = float(timeout_sec)
	var err := _http.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "")
	if err != OK:
		return {"ok": false, "error": "HTTPRequest.request failed: %s" % error_string(err)}
	var completed = await _http.request_completed
	var result_code: int = completed[0]
	var response_code: int = completed[1]
	var resp_body: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": {"result": result_code}}
	var data = _parse_json_body(resp_body)
	if response_code < 200 or response_code >= 300:
		return {"ok": false, "error": {"status": response_code, "body": data}}
	return {"ok": true, "data": data, "status": response_code}

func _post_json(url: String, payload: Dictionary, timeout_sec: float) -> Dictionary:
	if not is_instance_valid(_http):
		return {"ok": false, "error": "http_missing"}
	_http.timeout = float(timeout_sec)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify(payload)
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		return {"ok": false, "error": "HTTPRequest.request failed: %s" % error_string(err)}
	var completed = await _http.request_completed
	var result_code: int = completed[0]
	var response_code: int = completed[1]
	var resp_body: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": {"result": result_code}}
	var data = _parse_json_body(resp_body)
	if response_code < 200 or response_code >= 300:
		return {"ok": false, "error": {"status": response_code, "body": data}}
	return {"ok": true, "data": data, "status": response_code}
