extends SceneTree

const FocusFilterScript = preload(
	"res://addons/syntree/scripts/core/context_graph_focus_filter.gd"
)
const CompilerScript = preload(
	"res://addons/syntree/scripts/core/context_compiler.gd"
)
const DiagnosticsScript = preload(
	"res://addons/syntree/scripts/core/context_graph_diagnostics.gd"
)
const LayoutStoreScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_layout_store.gd"
)
const GraphWorkspaceDocumentScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_document.gd"
)
const ContentGraphControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/content_graph_controller.gd"
)

const LARGE_NODE_COUNT: int = 1000
const FILTER_TARGET_MS: float = 300.0
const COMPILE_TARGET_MS: float = 500.0
const DIAGNOSTICS_TARGET_MS: float = 1000.0


func _init() -> void:
	var controller_parse_check: Node = ContentGraphControllerScript.new()
	controller_parse_check.free()
	var failures: int = 0
	failures += _test_layout_separation()
	failures += _test_large_fixture_targets()
	if failures == 0:
		print("Context Graph Stage I.11 tests: all passed")
		quit(0)
		return
	push_error("Context Graph Stage I.11 failures: %d" % failures)
	quit(1)


func _test_layout_separation() -> int:
	var store: RefCounted = LayoutStoreScript.new()
	var owner_id: String = "stage-i11-test-owner"
	var save_result: Dictionary = store.call(
		"save_layout",
		owner_id,
		"Deterministic fixture",
		{
			"node_positions": {"node-1": {"x": 12.0, "y": 34.0}},
			"viewport": {"scroll_x": 2.0, "scroll_y": 3.0, "zoom": 1.2},
		}
	)
	var layout_data: Dictionary = save_result.get("layout", {})
	var semantic_before: Dictionary = _fixture(2)
	var semantic_after: Dictionary = semantic_before.duplicate(true)
	semantic_after["layout_ref"] = str(layout_data.get("id", ""))
	semantic_after["viewport"] = layout_data.get("viewport", {})
	var diff: Dictionary = GraphWorkspaceDocumentScript.semantic_diff(
		semantic_before,
		semantic_after
	)
	store.call("delete_layout", owner_id, str(layout_data.get("id", "")))
	if (
		bool(save_result.get("ok", false))
		and (diff.get("nodes", {}).get("changed", []) as Array).is_empty()
		and (diff.get("edges", {}).get("changed", []) as Array).is_empty()
	):
		return 0
	push_error("Named layout leaked into semantic graph diff")
	return 1


func _test_large_fixture_targets() -> int:
	var document: Dictionary = _fixture(LARGE_NODE_COUNT)
	var started_usec: int = Time.get_ticks_usec()
	var filter_result: Dictionary = FocusFilterScript.new().call(
		"evaluate",
		document,
		{"search_text": "node", "show_rejected": true}
	)
	var filter_ms: float = (Time.get_ticks_usec() - started_usec) / 1000.0
	started_usec = Time.get_ticks_usec()
	var compile_result: Dictionary = CompilerScript.new().call(
		"compile",
		document,
		{"id": "large", "entry_node_ids": ["node-0"]},
		{"preset": "full", "max_tokens": 100000}
	)
	var compile_ms: float = (Time.get_ticks_usec() - started_usec) / 1000.0
	started_usec = Time.get_ticks_usec()
	var diagnostics: Array = DiagnosticsScript.new().call(
		"analyze",
		document,
		compile_result
	)
	var diagnostics_ms: float = (
		Time.get_ticks_usec() - started_usec
	) / 1000.0
	print(
		"Stage I.11 fixture: nodes=%d filter=%.2fms compile=%.2fms diagnostics=%.2fms"
		% [LARGE_NODE_COUNT, filter_ms, compile_ms, diagnostics_ms]
	)
	if (
		(filter_result.get("visible_node_ids", []) as Array).size()
			== LARGE_NODE_COUNT
		and not diagnostics.is_empty()
		and filter_ms <= FILTER_TARGET_MS
		and compile_ms <= COMPILE_TARGET_MS
		and diagnostics_ms <= DIAGNOSTICS_TARGET_MS
	):
		return 0
	push_error("Large Context Graph fixture exceeded deterministic targets")
	return 1


func _fixture(node_count: int) -> Dictionary:
	var nodes: Array = []
	var edges: Array = []
	for node_index in range(node_count):
		nodes.append({
			"id": "node-%d" % node_index,
			"kind": "content",
			"label": "Node %d" % node_index,
			"content": "Deterministic fixture content %d" % node_index,
			"status": "committed",
			"annotations": {"tags": ["fixture"], "is_active": true},
			"activation": {"mode": "always"},
			"provenance": {
				"origin_ref": "fixture",
				"authorship_kind": "user_authored",
				"review_status": "reviewed",
			},
		})
		if node_index > 0:
			edges.append({
				"id": "edge-%d" % node_index,
				"from": "node-%d" % (node_index - 1),
				"to": "node-%d" % node_index,
				"relation": "related_to",
				"confidence": 1.0,
				"provenance": {
					"origin_ref": "fixture",
					"authorship_kind": "user_authored",
					"review_status": "reviewed",
				},
			})
	return {
		"schema": "graph_workspace.v1",
		"graph_kind": "context_graph",
		"nodes": nodes,
		"edges": edges,
		"context_sets": [],
	}
