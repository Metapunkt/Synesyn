## Purpose: Build versioned ui.prompt_chain payloads and provenance.
extends RefCounted


func build(
	chain: Dictionary,
	chain_id: String,
	scope_id: String,
	previous_artifact_id: String,
	created_at: float
) -> Dictionary:
	var binding: Dictionary = chain.get("context_binding", {})
	var previous_id_value: Variant = null
	if not previous_artifact_id.is_empty():
		previous_id_value = previous_artifact_id
	var source_artifacts: Array = []
	if not binding.is_empty():
		source_artifacts.append({
			"artifact_type": "ui.context_graph",
			"artifact_id": str(
				binding.get("context_graph_artifact_id", "")
			),
			"version_id": str(
				binding.get("context_graph_version_id", "")
			),
		})
	return {
		"inline_json": {
			"schema_version": 1,
			"chain_id": chain_id,
			"scope": scope_id,
			"name": str(chain.get("name", "")),
			"blocks": chain.get("blocks", []),
			"slots": chain.get("slots", []),
			"context_binding": binding,
			"created_at": created_at,
			"prev_artifact_id": previous_id_value,
		},
		"metadata": {
			"provenance": {
				"generated_by": "syntree.prompt_chain_editor",
				"source_artifacts": source_artifacts,
			},
			"refs": {"chain_id": chain_id, "scope": scope_id},
		},
	}
