extends SceneTree

const GraphWorkspaceDocumentScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_document.gd"
)


func _init() -> void:
	var failures: int = 0
	failures += _test_valid_document()
	failures += _test_dangling_edge()
	failures += _test_semantic_snapshot_ignores_layout_state()
	failures += _test_semantic_diff()
	if failures == 0:
		print("GraphWorkspaceDocument tests: PASS")
		quit(0)
		return
	push_error("GraphWorkspaceDocument tests: %d failure(s)" % failures)
	quit(1)


func _test_valid_document() -> int:
	var document: Dictionary = GraphWorkspaceDocumentScript.create_empty(
		"context_graph",
		"Test graph"
	)
	document["nodes"] = [
		{
			"id": "node_a",
			"kind": "content_source",
			"label": "A",
			"status": "committed",
			"provenance_refs": ["source:a"],
		},
		{
			"id": "node_b",
			"kind": "content_source",
			"label": "B",
			"status": "committed",
			"provenance_refs": ["source:b"],
		},
	]
	document["edges"] = [
		{
			"id": "edge_a_b",
			"from": "node_a",
			"to": "node_b",
			"relation": "supports",
			"status": "committed",
			"confidence": 0.8,
			"provenance_refs": ["source:a", "source:b"],
		},
	]
	var result: Dictionary = GraphWorkspaceDocumentScript.validate(
		document,
		"context_graph"
	)
	return _expect(bool(result.get("ok", false)), "valid document rejected")


func _test_dangling_edge() -> int:
	var document: Dictionary = GraphWorkspaceDocumentScript.create_empty(
		"context_graph"
	)
	document["nodes"] = [
		{
			"id": "node_a",
			"kind": "content_source",
			"label": "A",
			"status": "committed",
			"provenance_refs": [],
		},
	]
	document["edges"] = [
		{
			"id": "edge_missing",
			"from": "node_a",
			"to": "node_missing",
			"relation": "related_to",
			"status": "committed",
			"provenance_refs": [],
		},
	]
	var result: Dictionary = GraphWorkspaceDocumentScript.validate(document)
	var errors: Array = result.get("errors", [])
	return _expect(
		not bool(result.get("ok", true))
		and errors.has("dangling_edge_to:edge_missing:node_missing"),
		"dangling edge was not reported"
	)


func _test_semantic_snapshot_ignores_layout_state() -> int:
	var document: Dictionary = GraphWorkspaceDocumentScript.create_empty(
		"workshop_thinking_map"
	)
	document["layout_ref"] = "artifact_layout_1"
	document["viewport"] = {"zoom": 1.25}
	document["selection"] = ["node_a"]
	document["focus"] = {"node_id": "node_a"}
	var snapshot: Dictionary = GraphWorkspaceDocumentScript.semantic_snapshot(
		document
	)
	return _expect(
		not snapshot.has("layout_ref")
		and not snapshot.has("viewport")
		and not snapshot.has("selection")
		and not snapshot.has("focus"),
		"layout state leaked into semantic snapshot"
	)


func _test_semantic_diff() -> int:
	var before: Dictionary = GraphWorkspaceDocumentScript.create_empty("context_graph")
	before["nodes"] = [
		{"id": "removed", "kind": "content_source", "status": "committed", "provenance_refs": []},
		{"id": "changed", "kind": "content_source", "label": "Before", "status": "committed", "provenance_refs": []},
	]
	var after: Dictionary = before.duplicate(true)
	after["nodes"] = [
		{"id": "changed", "kind": "content_source", "label": "After", "status": "committed", "provenance_refs": []},
		{"id": "added", "kind": "content_source", "status": "committed", "provenance_refs": []},
	]
	before["viewport"] = {"zoom": 1.0}
	after["viewport"] = {"zoom": 2.0}
	var diff: Dictionary = GraphWorkspaceDocumentScript.semantic_diff(before, after)
	var node_diff: Dictionary = diff.get("nodes", {})
	return _expect(
		node_diff.get("added", []) == ["added"]
		and node_diff.get("removed", []) == ["removed"]
		and node_diff.get("changed", []) == ["changed"],
		"semantic diff did not classify node changes"
	)


func _expect(condition: bool, failure_message: String) -> int:
	if condition:
		return 0
	push_error(failure_message)
	return 1
