## Purpose: Resolve a committed Prompt Chain binding into compiled graph context.
extends RefCounted

const GraphWorkspaceArtifactClientScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_artifact_client.gd"
)
const ContextCompilerScript = preload(
	"res://addons/syntree/scripts/core/context_compiler.gd"
)

var _artifact_client: RefCounted = GraphWorkspaceArtifactClientScript.new()
var _compiler: RefCounted = ContextCompilerScript.new()


func setup(hub_client: Object) -> bool:
	return bool(_artifact_client.call("setup", hub_client))


func resolve(
	chain: Dictionary,
	expected_owner_source_id: String = "",
	activation_context: Dictionary = {},
	block_id: String = ""
) -> Dictionary:
	var binding_any: Variant = chain.get("context_binding", null)
	if typeof(binding_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "context_binding_missing"}
	var binding: Dictionary = binding_any
	var artifact_id: String = str(
		binding.get("context_graph_artifact_id", "")
	).strip_edges()
	var version_id: String = str(
		binding.get("context_graph_version_id", "")
	).strip_edges()
	var load_id: String = version_id if not version_id.is_empty() else artifact_id
	if load_id.is_empty():
		return {"ok": false, "error": "context_graph_artifact_required"}
	var loaded: Dictionary = await _artifact_client.call(
		"load_graph",
		load_id,
		"context_graph"
	)
	if not bool(loaded.get("ok", false)):
		return {
			"ok": false,
			"error": "context_graph_unavailable",
			"details": loaded,
		}
	var document: Dictionary = loaded.get("document", {})
	var context_set_id: String = str(
		binding.get("context_set_id", "")
	).strip_edges()
	if context_set_id.is_empty():
		context_set_id = "active-sources"
	var context_set: Dictionary = _find_context_set(
		document.get("context_sets", []),
		context_set_id
	)
	if context_set.is_empty():
		return {
			"ok": false,
			"error": "context_set_not_found",
			"context_set_id": context_set_id,
		}
	var binding_owner: String = str(
		binding.get("owner_source_id", "")
	).strip_edges()
	var set_owner: String = str(
		context_set.get("owner_source_id", binding_owner)
	).strip_edges()
	var expected_owner: String = expected_owner_source_id.strip_edges()
	if (
		not binding_owner.is_empty()
		and not set_owner.is_empty()
		and binding_owner != set_owner
	):
		return {
			"ok": false,
			"error": "binding_owner_scope_mismatch",
			"binding_owner_source_id": binding_owner,
			"set_owner_source_id": set_owner,
		}
	if (
		not expected_owner.is_empty()
		and set_owner != expected_owner
	):
		return {
			"ok": false,
			"error": "context_owner_scope_mismatch",
			"expected_owner_source_id": expected_owner,
			"actual_owner_source_id": set_owner,
		}
	var options: Dictionary = {
		"preset": str(binding.get("compiler_preset", "balanced")),
		"max_tokens": int(binding.get("max_tokens", 8000)),
		"graph_artifact_id": artifact_id,
		"graph_version_id": load_id,
		"activation_context": activation_context.duplicate(true),
	}
	var block_override: Dictionary = _block_override(chain, block_id)
	for option_key in block_override:
		options[option_key] = block_override[option_key]
	var compile_result: Dictionary = _compiler.call(
		"compile",
		document,
		context_set,
		options
	)
	var warnings: Array[String] = []
	if version_id.is_empty():
		warnings.append("context_graph_version_not_pinned")
	compile_result["prompt_chain_id"] = str(chain.get("id", ""))
	compile_result["prompt_chain_block_id"] = block_id
	return {
		"ok": bool(compile_result.get("ok", false)),
		"warnings": warnings,
		"compile_result": compile_result,
		"staleness": {
			"artifact_missing": false,
			"version_unpinned": version_id.is_empty(),
			"set_missing": false,
		},
	}


func _find_context_set(
	context_sets_any: Variant,
	context_set_id: String
) -> Dictionary:
	if typeof(context_sets_any) != TYPE_ARRAY:
		return {}
	for context_set_any in (context_sets_any as Array):
		if typeof(context_set_any) != TYPE_DICTIONARY:
			continue
		var context_set: Dictionary = context_set_any
		if str(context_set.get("id", "")) == context_set_id:
			return context_set
	return {}


func _block_override(chain: Dictionary, block_id: String) -> Dictionary:
	var normalized_block_id: String = block_id.strip_edges()
	if normalized_block_id.is_empty():
		return {}
	var blocks_any: Variant = chain.get("blocks", [])
	if typeof(blocks_any) != TYPE_ARRAY:
		return {}
	for block_any in (blocks_any as Array):
		if typeof(block_any) != TYPE_DICTIONARY:
			continue
		var block_data: Dictionary = block_any
		if str(block_data.get("id", "")) != normalized_block_id:
			continue
		var override_any: Variant = block_data.get("context_override", {})
		if typeof(override_any) == TYPE_DICTIONARY:
			return (override_any as Dictionary).duplicate(true)
	return {}
