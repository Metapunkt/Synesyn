extends SceneTree

## Visible failure guidance for Hub voice when running ScenSyn from source.
##
## Run (from synesyn_client):
##   godot --headless --path . --script res://addons/synesyn_core/scripts/tests/test_hub_voice_visible_failures.gd

const HubLocatorScript = preload("res://addons/synesyn_core/scripts/hub_locator.gd")
const VoiceClientScript = preload("res://addons/syntree_voice/scripts/services/voice_client.gd")
const RuntimeConfigScript = preload("res://addons/synesyn_core/scripts/runtime_config.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_voice_unavailable_message()
	_test_format_host_port()
	_test_autostart_from_source_default_off()
	_test_source_run_gates_exported_templates()
	await _test_voice_queue_cap_and_unavailable_enqueue()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("Hub voice visible failures tests: all passed")
		quit(0)
		return
	for failure_message in _failures:
		print("FAIL: " + failure_message)
	quit(1)


func _expect(cond: bool, message: String) -> void:
	if not cond:
		_failures.append(message)


func _test_voice_unavailable_message() -> void:
	var msg: String = HubLocatorScript.voice_unavailable_message("http://127.0.0.1:17777")
	_expect(
		msg == "Voice unavailable: Synesyn Hub isn't running at 127.0.0.1:17777",
		"voice_unavailable_message should name host:port; got: %s" % msg
	)
	var msg2: String = HubLocatorScript.voice_unavailable_message("http://localhost:17777/extra")
	_expect(
		msg2.find("127.0.0.1:17777") != -1 or msg2.find("localhost:17777") != -1,
		"voice_unavailable_message should keep host:port from URL with path; got: %s" % msg2
	)


func _test_format_host_port() -> void:
	_expect(
		HubLocatorScript.format_host_port("http://127.0.0.1:17777") == "127.0.0.1:17777",
		"format_host_port should strip scheme"
	)
	_expect(
		HubLocatorScript.format_host_port("") == "127.0.0.1:17777",
		"format_host_port empty should fall back to default"
	)


func _test_autostart_from_source_default_off() -> void:
	var cfg: Dictionary = RuntimeConfigScript.default_config()
	var hub_any: Variant = cfg.get("hub", {})
	_expect(typeof(hub_any) == TYPE_DICTIONARY, "default_config hub section missing")
	if typeof(hub_any) != TYPE_DICTIONARY:
		return
	var hub_cfg: Dictionary = hub_any
	_expect(
		hub_cfg.has("autostart_from_source"),
		"default hub config must declare autostart_from_source"
	)
	_expect(
		bool(hub_cfg.get("autostart_from_source", true)) == false,
		"hub.autostart_from_source must default to false"
	)
	_expect(
		HubLocatorScript.is_autostart_from_source_enabled(cfg) == false,
		"is_autostart_from_source_enabled should be false by default"
	)
	var enabled_cfg := {"hub": {"autostart_from_source": true}}
	_expect(
		HubLocatorScript.is_autostart_from_source_enabled(enabled_cfg) == true,
		"is_autostart_from_source_enabled should honour true"
	)


func _test_source_run_gates_exported_templates() -> void:
	# Packaged builds set the "template" feature; source/editor runs do not.
	# We cannot flip OS features in-test, so only assert consistency for this process.
	var is_source: bool = HubLocatorScript.is_source_run()
	if OS.has_feature("template"):
		_expect(is_source == false, "template builds must not be treated as source runs")
	else:
		_expect(is_source == true, "non-template runs should be treated as source runs")


func _test_voice_queue_cap_and_unavailable_enqueue() -> void:
	var client: Node = VoiceClientScript.new()
	root.add_child(client)
	await process_frame
	client.is_service_available = false
	var max_q: int = int(VoiceClientScript.MAX_REQUEST_QUEUE)
	_expect(max_q == 32, "MAX_REQUEST_QUEUE should be 32, got %d" % max_q)
	for i in range(max_q + 5):
		var accepted: bool = bool(client.call("synthesize_speech", "line %d" % i, "Speaker%d" % i))
		_expect(accepted, "synthesize_speech should accept while unavailable")
	_expect(
		client.request_queue.size() == max_q,
		"queue should be capped at %d, got %d" % [max_q, client.request_queue.size()]
	)
	client.queue_free()
	await process_frame
