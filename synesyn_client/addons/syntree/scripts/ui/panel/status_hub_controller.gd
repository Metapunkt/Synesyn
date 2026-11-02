## Purpose: Panel controller for Hub status strip + thread hub versions popup (one cohesive domain)
@tool
extends Node
class_name StatusHubController

const HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")

var _ai_model_manager: Object = null
var _conversation_manager: Object = null
var _view_state: ViewStateResource = null

var _api_provider_selector: OptionButton = null
var _ai_model_selector: OptionButton = null
var _status_strip_label: Label = null
var _system_info_label: Label = null

var _thread_hub_versions_popup: PopupPanel = null
var _thread_hub_versions_list: ItemList = null

var _refresh_thread_view_cb: Callable = Callable() # expects (thread_id:String)
var _emit_operation_failed_cb: Callable = Callable() # expects (op:String, error:String, details:String)

var _hub_client: Node = null
var _timer: Timer = null
var _inflight: bool = false

func setup(
		ai_model_manager: Object,
		conversation_manager: Object,
		view_state: ViewStateResource,
		api_provider_selector: OptionButton,
		ai_model_selector: OptionButton,
		status_strip_label: Label,
		system_info_label: Label,
		thread_hub_versions_popup: PopupPanel,
		thread_hub_versions_list: ItemList,
		refresh_thread_view_cb: Callable,
		emit_operation_failed_cb: Callable
	) -> void:
	_ai_model_manager = ai_model_manager
	_conversation_manager = conversation_manager
	_view_state = view_state
	_api_provider_selector = api_provider_selector
	_ai_model_selector = ai_model_selector
	_status_strip_label = status_strip_label
	_system_info_label = system_info_label
	_thread_hub_versions_popup = thread_hub_versions_popup
	_thread_hub_versions_list = thread_hub_versions_list
	_refresh_thread_view_cb = refresh_thread_view_cb
	_emit_operation_failed_cb = emit_operation_failed_cb

func start() -> void:
	# Safe to call multiple times.
	if not is_instance_valid(_hub_client):
		_hub_client = HubSubstrateClientScript.new()
		add_child(_hub_client)
		if _hub_client.has_method("configure_from_runtime_config"):
			_hub_client.configure_from_runtime_config()

	if not is_instance_valid(_timer):
		_timer = Timer.new()
		_timer.wait_time = 1.0
		_timer.one_shot = false
		_timer.timeout.connect(_on_timer_timeout)
		add_child(_timer)
		_timer.start()

func stop() -> void:
	if is_instance_valid(_timer):
		_timer.stop()

func _on_timer_timeout() -> void:
	await _update_status_async()

func _update_status_async() -> void:
	if _inflight:
		return
	_inflight = true

	var hub_text := "Hub: ?"
	var voice_text := "Voice: ?"
	if is_instance_valid(_hub_client) and _hub_client.has_method("check_health"):
		var res: Dictionary = await _hub_client.check_health()
		hub_text = "Hub: up" if bool(res.get("ok", false)) else "Hub: down"
		voice_text = _format_voice_status_from_health(res)

	var model := ""
	var provider := ""
	if is_instance_valid(_ai_model_manager) and _ai_model_manager.has_method("get_current_model"):
		model = str(_ai_model_manager.get_current_model())
		if _ai_model_manager.has_method("get_provider_for_model"):
			provider = str(_ai_model_manager.get_provider_for_model(model))

	if provider.is_empty() and is_instance_valid(_api_provider_selector):
		var meta := _api_provider_selector.get_item_metadata(_api_provider_selector.selected)
		provider = str(meta) if meta != null else ""

	# Fallback: the model selector UI is often initialized before the model manager is fully synced.
	if model.is_empty() and is_instance_valid(_ai_model_selector):
		var idx := int(_ai_model_selector.selected)
		if idx >= 0 and idx < _ai_model_selector.item_count:
			var txt := String(_ai_model_selector.get_item_text(idx)).strip_edges()
			if not txt.is_empty():
				model = txt

	if provider.is_empty():
		provider = "?"
	if model.is_empty():
		model = "?"

	# Check embedding capability for the active model's provider
	var embed_text := ""
	if is_instance_valid(_ai_model_manager) and _ai_model_manager.has_method("get_provider_loader"):
		var loader: Variant = _ai_model_manager.get_provider_loader(provider)
		if loader and loader.has_method("supports_embeddings") and loader.supports_embeddings():
			embed_text = " | Embeddings: yes"
		else:
			embed_text = " | Embeddings: no"

	var status_text := "%s | %s | Provider: %s | Model: %s%s" % [hub_text, voice_text, provider, model, embed_text]
	if is_instance_valid(_status_strip_label):
		_status_strip_label.text = status_text
	if is_instance_valid(_system_info_label):
		_system_info_label.text = status_text

	_inflight = false

func _format_voice_status_from_health(health: Dictionary) -> String:
	# Hub API spec (normative): /health returns {"ok":bool, "capabilities": {"voice_tts":bool, "voice_stt":bool, ...}}
	# Be robust to older/newer shapes.
	if not bool(health.get("ok", false)):
		return "Voice: down"

	var caps_any: Variant = health.get("capabilities", null)
	var caps: Dictionary = caps_any if typeof(caps_any) == TYPE_DICTIONARY else {}

	var tts := false
	var stt := false
	if not caps.is_empty():
		tts = bool(caps.get("voice_tts", false))
		stt = bool(caps.get("voice_stt", false))
	else:
		# Fallback shapes (defensive): {"voice": {"tts": {...}, "stt": {...}}} or {"voice_tts": true, ...}
		tts = bool(health.get("voice_tts", false))
		stt = bool(health.get("voice_stt", false))
		var voice_any: Variant = health.get("voice", null)
		if typeof(voice_any) == TYPE_DICTIONARY:
			var voice: Dictionary = voice_any
			tts = tts or bool(voice.get("tts", false))
			stt = stt or bool(voice.get("stt", false))

	if tts and stt:
		return "Voice: TTS+STT"
	if tts:
		return "Voice: TTS"
	if stt:
		return "Voice: STT"
	return "Voice: unavailable"

func on_open_thread_hub_versions_pressed() -> void:
	if not is_instance_valid(_thread_hub_versions_popup) or not is_instance_valid(_thread_hub_versions_list):
		return
	_thread_hub_versions_list.clear()

	var tid := _get_current_thread_id_safe()
	if not is_instance_valid(_conversation_manager) or not _conversation_manager.has_method("get_thread_hub_info"):
		_thread_hub_versions_list.add_item("(ConversationManager has no hub mapping)")
		_thread_hub_versions_popup.popup_centered()
		return

	var info: Dictionary = _conversation_manager.get_thread_hub_info(tid)
	var versions_any: Variant = info.get("versions", [])
	if typeof(versions_any) != TYPE_ARRAY:
		_thread_hub_versions_list.add_item("(no hub versions recorded yet)")
		_thread_hub_versions_popup.popup_centered()
		return

	var versions: Array = versions_any
	if versions.is_empty():
		_thread_hub_versions_list.add_item("(no hub versions recorded yet)")
	else:
		for v in versions:
			_thread_hub_versions_list.add_item(str(v))
	_thread_hub_versions_popup.popup_centered()

func on_thread_hub_version_activated(idx: int) -> void:
	if not is_instance_valid(_thread_hub_versions_list):
		return
	if idx < 0 or idx >= _thread_hub_versions_list.item_count:
		return
	var artifact_id := _thread_hub_versions_list.get_item_text(idx).strip_edges()
	if artifact_id.is_empty() or artifact_id.begins_with("("):
		return

	var tid := _get_current_thread_id_safe()
	if not is_instance_valid(_conversation_manager) or not _conversation_manager.has_method("load_thread_from_hub_version"):
		return
	var res: Dictionary = await _conversation_manager.load_thread_from_hub_version(tid, artifact_id)
	if not bool(res.get("success", false)):
		_emit_failed("thread_hub_load", str(res.get("error", "failed")), str(res.get("details", "")))
		return
	# Refresh current thread view
	if _refresh_thread_view_cb.is_valid():
		_refresh_thread_view_cb.call(tid)

func on_open_threads_folder_pressed() -> void:
	if not is_instance_valid(_conversation_manager) or not _conversation_manager.has_method("get_threads_dir_info"):
		if is_instance_valid(_status_strip_label):
			_status_strip_label.text = "Threads folder: (conversation manager unavailable)"
		_emit_failed("open_threads_folder", "ConversationManager not available", "")
		return
	var info: Dictionary = _conversation_manager.get_threads_dir_info()
	var abs_dir := str(info.get("threads_dir_abs", "")).strip_edges()
	if abs_dir.is_empty():
		if is_instance_valid(_status_strip_label):
			_status_strip_label.text = "Threads folder: (path unavailable)"
		_emit_failed("open_threads_folder", "Threads folder path not available", "")
		return
	abs_dir = abs_dir.replace("\\", "/")
	# Use push_warning so this is visible in the editor output even when normal prints are filtered.
	push_warning("StatusHubController: Open threads folder requested: %s" % abs_dir)
	if is_instance_valid(_status_strip_label):
		_status_strip_label.text = "Threads folder: opening…"
	if is_instance_valid(_system_info_label):
		_system_info_label.text = "Threads folder: opening…"

	# Ensure the directory exists (opening a non-existent folder is a no-op on some OSes).
	var mkerr := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mkerr != OK:
		if is_instance_valid(_status_strip_label):
			_status_strip_label.text = "Threads folder: mkdir failed"
		_emit_failed("open_threads_folder", "Threads folder could not be created", "path=%s (err=%s)" % [abs_dir, mkerr])
		return

	# Windows: Explorer fallback is the most reliable for folders.
	if OS.get_name() == "Windows":
		var pwin := abs_dir.replace("/", "\\")
		# Prefer create_process (non-blocking, more reliable in editor/tool context).
		var pid := OS.create_process("explorer.exe", PackedStringArray([pwin]), false)
		if pid > 0:
			if is_instance_valid(_status_strip_label):
				_status_strip_label.text = "Threads folder: opened"
			if is_instance_valid(_system_info_label):
				_system_info_label.text = "Threads folder: opened"
			return
		# Fall back to execute if create_process failed.
		var ex_err := OS.execute("explorer.exe", PackedStringArray([pwin]))
		if ex_err == 0:
			if is_instance_valid(_status_strip_label):
				_status_strip_label.text = "Threads folder: opened"
			if is_instance_valid(_system_info_label):
				_system_info_label.text = "Threads folder: opened"
			return
		# Last Windows fallback: `cmd /c start "" <path>`
		var pid2 := OS.create_process("cmd.exe", PackedStringArray(["/c", "start", "", pwin]), false)
		if pid2 > 0:
			if is_instance_valid(_status_strip_label):
				_status_strip_label.text = "Threads folder: opened"
			if is_instance_valid(_system_info_label):
				_system_info_label.text = "Threads folder: opened"
			return

	# Prefer opening the folder directly.
	var err := OS.shell_open(abs_dir)
	if err == OK:
		if is_instance_valid(_status_strip_label):
			_status_strip_label.text = "Threads folder: opened"
		if is_instance_valid(_system_info_label):
			_system_info_label.text = "Threads folder: opened"
		return

	# Next: show in file manager (works well for files, and some platforms accept folders).
	if OS.has_method("shell_show_in_file_manager"):
		OS.shell_show_in_file_manager(abs_dir, true)
		return

	# Last: OS.shell_open with a correctly formed file URI (URI-encoded).
	var uri := abs_dir
	if not uri.begins_with("file://"):
		# Windows drive letter paths need file:///C:/...
		if uri.length() >= 2 and uri[1] == ":":
			uri = "file:///" + uri
		else:
			uri = "file://" + uri
	# Godot 4.4: String has `uri_encode()` but does not support `has_method()`.
	if uri.find(" ") != -1:
		uri = uri.uri_encode()
	var err2 := OS.shell_open(uri)
	if err2 != OK:
		if is_instance_valid(_status_strip_label):
			_status_strip_label.text = "Threads folder: open failed"
		if is_instance_valid(_system_info_label):
			_system_info_label.text = "Threads folder: open failed"
		_emit_failed(
			"open_threads_folder",
			"Failed to open threads folder",
			"path=%s (mkerr=%s, shell_open_path_err=%s, uri=%s, shell_open_uri_err=%s)" % [abs_dir, mkerr, err, uri, err2]
		)
	else:
		if is_instance_valid(_status_strip_label):
			_status_strip_label.text = "Threads folder: opened"
		if is_instance_valid(_system_info_label):
			_system_info_label.text = "Threads folder: opened"

func _get_current_thread_id_safe() -> String:
	var tid := "default"
	if is_instance_valid(_view_state) and _view_state.has_method("get_current_thread_id"):
		tid = str(_view_state.get_current_thread_id()).strip_edges()
	if tid.is_empty():
		tid = "default"
	return tid

func _emit_failed(operation: String, error: String, details: String) -> void:
	if _emit_operation_failed_cb.is_valid():
		_emit_operation_failed_cb.call(operation, error, details)


