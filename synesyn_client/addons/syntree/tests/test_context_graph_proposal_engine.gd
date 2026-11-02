extends SceneTree

const ProposalEngineScript = preload(
	"res://addons/syntree/scripts/core/context_graph_proposal_engine.gd"
)


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var engine: RefCounted = ProposalEngineScript.new()
	var document: Dictionary = {
		"graph_schema_version": 1,
		"graph_kind": "context_graph",
		"name": "Test",
		"nodes": [
			{
				"id": "node-a",
				"kind": "chunk",
				"status": "committed",
				"provenance_refs": [],
			},
			{
				"id": "node-b",
				"kind": "chunk",
				"status": "committed",
				"provenance_refs": [],
			},
		],
		"edges": [],
	}
	var suggested: Dictionary = engine.call("normalize", {
		"proposal_type": "relationship",
		"operation": "add_edge",
		"payload": {
			"id": "edge-a",
			"from": "node-a",
			"to": "node-b",
			"relation": "supports",
			"provenance_refs": ["trace:proposal-a"],
		},
		"rationale": "A supports B",
		"model_id": "model-a",
	})
	var rejected_review: Dictionary = engine.call(
		"review",
		suggested,
		"rejected",
		{},
		"Not supported"
	)
	var rejected_preview: Dictionary = engine.call(
		"preview",
		document,
		[rejected_review.get("proposal", {})]
	)
	var accepted_review: Dictionary = engine.call(
		"review",
		suggested,
		"accepted"
	)
	var accepted_preview: Dictionary = engine.call(
		"preview",
		document,
		[accepted_review.get("proposal", {})]
	)
	var preview_document: Dictionary = accepted_preview.get("document", {})
	var preview_edges: Array = preview_document.get("edges", [])
	var original_edges: Array = document.get("edges", [])
	var diff: Dictionary = accepted_preview.get("semantic_diff", {})
	var edge_diff: Dictionary = diff.get("edges", {})
	var did_pass: bool = (
		not engine.has_method("commit")
		and not engine.has_method("update_source")
		and original_edges.is_empty()
		and (
			rejected_preview.get("document", {}) as Dictionary
		).get("edges", []).is_empty()
		and bool(accepted_preview.get("ok", false))
		and preview_edges.size() == 1
		and (
			preview_edges[0] as Dictionary
		).get("status", "") == "accepted"
		and edge_diff.get("added", []) == ["edge-a"]
	)
	if did_pass:
		print("Context graph proposal engine tests: all passed")
		quit(0)
		return
	push_error("Proposal review mutated canonical graph or bypassed commit")
	quit(1)
