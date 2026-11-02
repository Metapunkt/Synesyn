extends SceneTree

const PromptChainContextResolverScript = preload(
	"res://addons/syntree/scripts/services/prompting/prompt_chain_context_resolver.gd"
)


class FakeHubClient:
	extends RefCounted
	var document: Dictionary = {}

	func get_artifact_json(artifact_id: String) -> Dictionary:
		if artifact_id == "missing":
			return {"ok": false, "error": "not_found"}
		return {
			"ok": true,
			"json": document.duplicate(true),
			"record": {"id": artifact_id},
		}

	func create_artifact_inline_json(
		_artifact_type: String,
		_inline_json: Dictionary,
		_metadata: Dictionary = {}
	) -> Dictionary:
		return {"ok": true, "artifact_id": "unused"}


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var hub_client: FakeHubClient = FakeHubClient.new()
	hub_client.document = _document()
	var resolver: RefCounted = PromptChainContextResolverScript.new()
	resolver.call("setup", hub_client)
	var chain: Dictionary = _chain()
	var resolved: Dictionary = await resolver.call(
		"resolve",
		chain,
		"source-a",
		{
			"app_scope": "syntree_editor",
			"prompt_chain_id": "chain-a",
			"slots": {"phase": "review"},
		},
		"block-a"
	)
	var compile_result: Dictionary = resolved.get("compile_result", {})
	var included: Array = compile_result.get("included_nodes", [])
	var wrong_scope: Dictionary = await resolver.call(
		"resolve",
		chain,
		"source-b"
	)
	var missing_set_chain: Dictionary = chain.duplicate(true)
	var missing_binding: Dictionary = missing_set_chain.get(
		"context_binding",
		{}
	)
	missing_binding["context_set_id"] = "source-a::missing"
	missing_set_chain["context_binding"] = missing_binding
	var missing_set: Dictionary = await resolver.call(
		"resolve",
		missing_set_chain,
		"source-a"
	)
	var unpinned_chain: Dictionary = chain.duplicate(true)
	var unpinned_binding: Dictionary = unpinned_chain.get(
		"context_binding",
		{}
	)
	unpinned_binding["context_graph_version_id"] = ""
	unpinned_chain["context_binding"] = unpinned_binding
	var unpinned: Dictionary = await resolver.call(
		"resolve",
		unpinned_chain,
		"source-a"
	)
	var missing_artifact_chain: Dictionary = chain.duplicate(true)
	var missing_artifact_binding: Dictionary = missing_artifact_chain.get(
		"context_binding",
		{}
	)
	missing_artifact_binding["context_graph_version_id"] = "missing"
	missing_artifact_chain["context_binding"] = missing_artifact_binding
	var missing_artifact: Dictionary = await resolver.call(
		"resolve",
		missing_artifact_chain,
		"source-a"
	)
	var is_valid: bool = (
		bool(resolved.get("ok", false))
		and included.size() == 1
		and (
			included[0] as Dictionary
		).get("node_id", "") == "source-a"
		and compile_result.get("graph_version_id", "") == "version-a"
		and compile_result.get("prompt_chain_id", "") == "chain-a"
		and wrong_scope.get("error", "") == "context_owner_scope_mismatch"
		and missing_set.get("error", "") == "context_set_not_found"
		and (unpinned.get("warnings", []) as Array).has(
			"context_graph_version_not_pinned"
		)
		and missing_artifact.get("error", "") == "context_graph_unavailable"
	)
	if is_valid:
		print("Prompt chain context resolver tests: all passed")
		quit(0)
		return
	push_error("Prompt chain context binding did not resolve safely")
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
		"blocks": [{
			"id": "block-a",
			"enabled": true,
			"text": "Review",
			"context_override": {
				"traversal_depth": 0,
				"allowed_relationship_types": [],
				"pinned_node_ids": [],
			},
		}],
	}


func _document() -> Dictionary:
	return {
		"graph_schema_version": 1,
		"graph_kind": "context_graph",
		"name": "Bound graph",
		"nodes": [
			{
				"id": "source-a",
				"kind": "content_source",
				"label": "Source A",
				"status": "committed",
				"provenance_refs": [],
			},
			{
				"id": "source-a::node-a",
				"kind": "chunk",
				"label": "Node A",
				"status": "committed",
				"provenance_refs": [],
			},
		],
		"edges": [{
			"id": "contains-a",
			"from": "source-a",
			"to": "source-a::node-a",
			"relation": "contains",
			"status": "committed",
			"provenance_refs": [],
		}],
		"context_sets": [{
			"id": "source-a::research",
			"owner_source_id": "source-a",
			"entry_node_ids": ["source-a"],
			"allowed_relationship_types": ["contains"],
			"traversal_depth": 1,
			"budget_policy": {"max_tokens": 100},
			"status": "committed",
		}],
	}
