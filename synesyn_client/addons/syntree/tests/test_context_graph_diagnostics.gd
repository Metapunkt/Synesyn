extends SceneTree

const DiagnosticsScript = preload(
	"res://addons/syntree/scripts/core/context_graph_diagnostics.gd"
)


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var diagnostics_engine: RefCounted = DiagnosticsScript.new()
	var document: Dictionary = {
		"graph_schema_version": 1,
		"graph_kind": "context_graph",
		"name": "Diagnostic fixture",
		"nodes": [
			_node("a", "Duplicate", true),
			_node("b", "duplicate", true),
			_node("orphan", "Orphan", false),
		],
		"edges": [
			_edge("ab", "a", "b"),
			_edge("ba", "b", "a"),
		],
	}
	var diagnostics: Array = diagnostics_engine.call(
		"analyze",
		document,
		{
			"is_over_budget": true,
			"estimated_tokens": 120,
			"token_budget": 100,
			"included_nodes": [{"node_id": "a"}],
		}
	)
	var diagnostic_types: Array[String] = []
	for diagnostic_any in diagnostics:
		diagnostic_types.append(str(
			(diagnostic_any as Dictionary).get("type", "")
		))
	var after_document: Dictionary = document.duplicate(true)
	(after_document.get("nodes", []) as Array).append(
		_node("new", "New", false)
	)
	var comparison: Dictionary = diagnostics_engine.call(
		"compare_versions",
		document,
		after_document,
		{
			"included_nodes": [{"node_id": "a"}],
			"estimated_tokens": 10,
			"compiled_text": "A",
		},
		{
			"included_nodes": [
				{"node_id": "a"},
				{"node_id": "new"},
			],
			"estimated_tokens": 20,
			"compiled_text": "A\nNew",
		}
	)
	var semantic_diff: Dictionary = comparison.get("semantic_diff", {})
	var node_diff: Dictionary = semantic_diff.get("nodes", {})
	var compiled_diff: Dictionary = comparison.get(
		"compiled_context_diff",
		{}
	)
	var did_pass: bool = (
		diagnostic_types.has("orphaned_node")
		and diagnostic_types.has("duplicate_node_label")
		and diagnostic_types.has("structural_cycle")
		and diagnostic_types.has("unreviewed_ai_record")
		and diagnostic_types.has("conflicting_active_instructions")
		and diagnostic_types.has("token_budget_overflow")
		and node_diff.get("added", []) == ["new"]
		and compiled_diff.get("included_added", []) == ["new"]
		and bool(compiled_diff.get("compiled_text_changed", false))
		and not bool(comparison.get("causation_claimed", true))
	)
	if did_pass:
		print("Context graph diagnostics tests: all passed")
		quit(0)
		return
	push_error(
		"Context Graph diagnostics were unstable or claimed causation: %s"
		% JSON.stringify({
			"diagnostics": diagnostics,
			"comparison": comparison,
		})
	)
	quit(1)


func _node(
	node_id: String,
	label_text: String,
	is_metaprompt: bool
) -> Dictionary:
	return {
		"id": node_id,
		"kind": "chunk",
		"label": label_text,
		"status": "committed",
		"annotations": {
			"is_metaprompt": is_metaprompt,
			"is_active": is_metaprompt,
		},
		"provenance": {
			"authorship_kind": "ai_inference",
			"origin_ref": "source:test",
			"review_status": "unreviewed",
			"source_artifact_id": "artifact-a",
			"source_version_id": "",
		},
		"provenance_refs": ["source:test"],
	}


func _edge(
	edge_id: String,
	from_id: String,
	to_id: String
) -> Dictionary:
	return {
		"id": edge_id,
		"from": from_id,
		"to": to_id,
		"relation": "contains",
		"status": "committed",
		"provenance": {
			"origin_ref": "source:test",
			"authorship_kind": "user_authored",
			"review_status": "reviewed",
		},
		"provenance_refs": ["source:test"],
	}
