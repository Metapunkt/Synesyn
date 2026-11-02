extends SceneTree

const TraceCoordinatorScript = preload(
	"res://addons/syntree/scripts/services/chat/internal/context_execution_trace_coordinator.gd"
)


class FakeHubClient:
	extends RefCounted

	var committed_type: String = ""
	var committed_payload: Dictionary = {}

	func create_artifact_inline_json(
		artifact_type: String,
		payload: Dictionary,
		_metadata: Dictionary
	) -> Dictionary:
		committed_type = artifact_type
		committed_payload = payload.duplicate(true)
		return {"ok": true, "id": "trace-artifact-1"}


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var coordinator: RefCounted = TraceCoordinatorScript.new()
	var message_id: String = coordinator.call(
		"make_message_id",
		"syntree_editor",
		"thread-a",
		2,
		"user",
		"2026-07-10T20:00:00"
	)
	var compile_result: Dictionary = {
		"ok": true,
		"compiled_text": "private compiled context",
		"graph_artifact_id": "graph-a",
		"graph_version_id": "version-3",
		"context_set_id": "set-a",
		"prompt_chain_id": "chain-a",
		"estimator_id": "heuristic_unicode_chars_div_4_v1",
		"estimated_tokens": 40,
		"token_budget": 100,
		"policy": {"max_tokens": 100},
		"included_nodes": [{
			"node_id": "source-a::node-a",
			"reason": "entry",
		}],
		"omitted_nodes": [{
			"node_id": "source-a::node-b",
			"reason": "excluded",
		}],
	}
	var trace: Dictionary = coordinator.call("begin_run", compile_result, {
		"thread_scope": "syntree_editor",
		"thread_id": "thread-a",
		"user_message_id": message_id,
		"user_index": 2,
		"model_id": "model-a",
		"provider_id": "provider-a",
	})
	var finalized: Dictionary = coordinator.call("finalize_run", trace, {
		"assistant_message_id": "msg_assistant",
		"assistant_index": 3,
		"status": "completed",
	})
	var fake_hub := FakeHubClient.new()
	var persisted: Dictionary = await coordinator.call(
		"persist",
		fake_hub,
		finalized
	)
	var has_private_text: bool = finalized.has("compiled_text")
	var message_refs: Dictionary = finalized.get("message_refs", {})
	var did_pass: bool = (
		message_id.begins_with("msg_")
		and str(finalized.get("context_path", "")) == "prompt_chain_binding"
		and str(finalized.get("compiled_text_hash", "")).length() == 64
		and not has_private_text
		and str(message_refs.get("user_message_id", "")) == message_id
		and str(
			message_refs.get("assistant_message_id", "")
		) == "msg_assistant"
		and fake_hub.committed_type == "json.context_execution_trace"
		and fake_hub.committed_payload == finalized
		and bool(persisted.get("ok", false))
	)
	if did_pass:
		print("Context execution trace coordinator tests: all passed")
		quit(0)
		return
	push_error(
		"Context execution trace coordinator contract failed: %s"
		% JSON.stringify(finalized)
	)
	quit(1)
