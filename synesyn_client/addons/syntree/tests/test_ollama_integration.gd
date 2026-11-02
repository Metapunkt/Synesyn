extends SceneTree

const OllamaModelScript = preload(
	"res://addons/syntree/scripts/services/ai/ai_model_loaders/ollama_model.gd"
)
const OllamaStreamingClientScript = preload(
	"res://addons/syntree/scripts/services/api/internal/ollama_streaming_client.gd"
)
const ContextPolicyScript = preload(
	"res://addons/syntree/scripts/services/chat/internal/conversation_model_context_policy.gd"
)
const RuntimeConfigScript = preload("res://addons/synesyn_core/scripts/runtime_config.gd")

var _streamed_text: String = ""


class FakeModelManager:
	extends RefCounted

	func get_current_model() -> String:
		return "custom:8b"

	func get_model_metadata(_model_id: String) -> Dictionary:
		return {"context_length": 8192}


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var loader: RefCounted = OllamaModelScript.new()
	var metadata: Dictionary = {
		"custom:8b": {
			"parameter_size": "8.0B",
			"quantization_level": "Q4_K_M",
			"context_length": 32768,
			"capabilities": ["completion", "tools", "vision"],
		},
	}
	var discovered_models: Array[String] = ["custom:8b"]
	loader.call(
		"set_discovered_models",
		discovered_models,
		metadata
	)
	loader.call("set_model", "custom:8b")
	var endpoint_was_set: bool = bool(
		loader.call(
			"set_base_origin",
			"http://192.168.1.20:11434/api/chat"
		)
	)
	var models: Array = loader.call("get_available_models")
	var capabilities: Dictionary = loader.call("get_capabilities")
	var parsed_metrics: Dictionary = loader.call("parse_metrics", {
		"total_duration": 2000000000,
		"load_duration": 250000000,
		"prompt_eval_count": 20,
		"prompt_eval_duration": 1000000000,
		"eval_count": 30,
		"eval_duration": 1500000000,
		"done_reason": "stop",
	})
	var stream_client: Node = OllamaStreamingClientScript.new()
	root.add_child(stream_client)
	var stream_endpoint_was_set: bool = bool(
		stream_client.call(
			"configure",
			"http://192.168.1.20:11434"
		)
	)
	Signal(
		stream_client,
		"chunk_received"
	).connect(_on_chunk_received)
	var parsed_stream: Dictionary = stream_client.call(
		"parse_ndjson_lines",
		(
			"{\"message\":{\"content\":\"Hello \"},\"done\":false}\n"
			+ "{\"message\":{\"content\":\"world\"},\"done\":true,"
			+ "\"eval_count\":2}\npartial"
		),
		"test-request"
	)
	var chunks: Array = parsed_stream.get("chunks", [])
	var final_payload: Dictionary = parsed_stream.get("final", {})
	var message_scene: PackedScene = load(
		"res://addons/syntree/scenes/message_container.tscn"
	)
	var message_container_node: Control = message_scene.instantiate()
	root.add_child(message_container_node)
	await process_frame
	var streamed_message_id: String = String(
		message_container_node.call(
			"begin_streamed_assistant_message"
		)
	)
	message_container_node.call(
		"append_streamed_assistant_delta",
		streamed_message_id,
		"Visible "
	)
	message_container_node.call(
		"append_streamed_assistant_delta",
		streamed_message_id,
		"stream"
	)
	message_container_node.call(
		"finish_streamed_assistant_message",
		streamed_message_id,
		"Visible stream"
	)
	var displayed_messages: Array = message_container_node.call(
		"get_messages"
	)
	var context_policy: RefCounted = ContextPolicyScript.new()
	var adaptive_policy: Dictionary = context_policy.call(
		"resolve",
		FakeModelManager.new(),
		true
	)
	var default_runtime_config: Dictionary = (
		RuntimeConfigScript.default_config()
	)
	var syntree_defaults: Dictionary = (
		(default_runtime_config.get("apps", {}) as Dictionary).get(
			"syntree",
			{}
		)
	)
	var scene: PackedScene = load(
		"res://addons/syntree/scenes/syntree_panel.tscn"
	)
	var scene_state: SceneState = scene.get_state()
	var has_status_label: bool = false
	var has_stop_button: bool = false
	var has_endpoint_input: bool = false
	for node_index: int in range(scene_state.get_node_count()):
		var node_id: String = String(
			scene_state.get_node_name(node_index)
		)
		if node_id == "OllamaStatusLabel":
			has_status_label = true
		elif node_id == "StopRequestButton":
			has_stop_button = true
		elif node_id == "OllamaEndpointInput":
			has_endpoint_input = true
	var did_pass: bool = (
		models == ["custom:8b"]
		and endpoint_was_set
		and loader.get("base_url") == (
			"http://192.168.1.20:11434/api/chat"
		)
		and stream_endpoint_was_set
		and int(capabilities.get("context_length", 0)) == 32768
		and bool(capabilities.get("supports_functions", false))
		and bool(capabilities.get("supports_vision", false))
		and int(parsed_metrics.get("prompt_tokens", 0)) == 20
		and is_equal_approx(
			float(
				parsed_metrics.get(
					"completion_tokens_per_second",
					0.0
				)
			),
			20.0
		)
		and chunks == ["Hello ", "world"]
		and _streamed_text == "Hello world"
		and bool(final_payload.get("done", false))
		and parsed_stream.get("remaining", "") == "partial"
		and displayed_messages.size() == 1
		and (
			displayed_messages[0] as Dictionary
		).get("content", "") == "Visible stream"
		and int(
			adaptive_policy.get("per_source_char_limit", 0)
		) == 12288
		and syntree_defaults.get("ollama_base_url", "") == (
			"http://127.0.0.1:11434"
		)
		and has_status_label
		and has_stop_button
		and has_endpoint_input
	)
	stream_client.queue_free()
	message_container_node.queue_free()
	if did_pass:
		print("Ollama integration tests: all passed")
		quit(0)
		return
	push_error(
		"Ollama discovery, capabilities, metrics, streaming, or UI regressed"
	)
	quit(1)


func _on_chunk_received(
	_request_id: String,
	content_delta: String
) -> void:
	_streamed_text += content_delta
