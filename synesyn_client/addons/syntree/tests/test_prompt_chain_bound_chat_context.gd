extends SceneTree

const BoundPromptChainContextBuilderScript = preload(
	"res://addons/syntree/scripts/services/chat/internal/bound_prompt_chain_context_builder.gd"
)


class FakeHubClient:
	extends RefCounted
	var document: Dictionary = {}

	func get_artifact_json(artifact_id: String) -> Dictionary:
		return {
			"ok": true,
			"json": document,
			"record": {"id": artifact_id},
		}

	func create_artifact_inline_json(
		_artifact_type: String,
		_inline_json: Dictionary,
		_metadata: Dictionary = {}
	) -> Dictionary:
		return {"ok": true}


class FakeManager:
	extends RefCounted
	var _hub: RefCounted = null
	var thread_scope: String = "syntree_editor"


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var hub_client: FakeHubClient = FakeHubClient.new()
	hub_client.document = _document()
	var manager: FakeManager = FakeManager.new()
	manager._hub = hub_client
	var builder: RefCounted = BoundPromptChainContextBuilderScript.new()
	var resolved: Dictionary = await builder.call(
		"resolve",
		manager,
		_chain(),
		{"phase": "review"},
		"CHAIN PREFIX\n\n"
	)
	var context_text: String = str(resolved.get("text", ""))
	var compile_result: Dictionary = manager.get_meta(
		"last_context_compile_result",
		{}
	)
	var is_valid: bool = (
		bool(resolved.get("handled", false))
		and context_text.begins_with("CHAIN PREFIX")
		and context_text.count("[SYNESYN_CONTEXT v2]") == 1
		and context_text.contains("Bound source content")
		and compile_result.get("prompt_chain_id", "") == "chain-a"
		and not manager.has_meta("last_prompt_binding_warning")
	)
	if is_valid:
		print("Prompt chain bound chat context tests: all passed")
		quit(0)
		return
	push_error("Bound Prompt Chain context was not injected exactly once")
	quit(1)


func _chain() -> Dictionary:
	return {
		"id": "chain-a",
		"context_binding": {
			"context_graph_artifact_id": "artifact-a",
			"context_graph_version_id": "version-a",
			"context_set_id": "source-a::research",
			"owner_source_id": "source-a",
			"compiler_preset": "balanced",
			"max_tokens": 100,
		},
		"blocks": [],
	}


func _document() -> Dictionary:
	return {
		"graph_schema_version": 1,
		"graph_kind": "context_graph",
		"name": "Bound graph",
		"nodes": [{
			"id": "source-a",
			"kind": "content_source",
			"label": "Bound source content",
			"status": "committed",
			"provenance_refs": [],
		}],
		"edges": [],
		"context_sets": [{
			"id": "source-a::research",
			"owner_source_id": "source-a",
			"entry_node_ids": ["source-a"],
			"allowed_relationship_types": [],
			"traversal_depth": 0,
			"budget_policy": {"max_tokens": 100},
			"status": "committed",
		}],
	}
