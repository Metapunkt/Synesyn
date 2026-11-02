extends SceneTree

const CanvasScene = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_canvas.tscn"
)
const DocumentScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_document.gd"
)
const LayoutStoreScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_layout_store.gd"
)

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_render_select_and_layout()
	_finish()


func _test_render_select_and_layout() -> void:
	var canvas_node: Control = CanvasScene.instantiate() as Control
	root.add_child(canvas_node)
	await process_frame
	_expect(
		canvas_node.has_method("configure_layout_owner")
		and canvas_node.has_method("set_document"),
		"Canvas scene script did not attach Graph Workspace canvas API"
	)
	# Unique per run: this suite's own persist_layout() call below writes a
	# real record to the shared user:// layout store, so a fixed owner id
	# would pick up a stale saved position from a prior run on the very next
	# load and silently defeat the "no saved layout" assertions below.
	var test_owner_id: String = "test_canvas_owner_%d" % Time.get_ticks_usec()
	canvas_node.configure_layout_owner(test_owner_id, "unit")
	var document: Dictionary = DocumentScript.create_empty("test_graph", "Canvas Test")
	document["nodes"] = [
		{
			"id": "n_cause",
			"kind": "cause",
			"label": "Budget pressure",
			"status": "suggested",
			"provenance_refs": [],
			"annotations": {},
		},
		{
			"id": "n_effect",
			"kind": "effect",
			"label": "Delayed delivery",
			"status": "accepted",
			"provenance_refs": [],
			"annotations": {},
		},
	]
	document["edges"] = [
		{
			"id": "e1",
			"from": "n_cause",
			"to": "n_effect",
			"relation": "causes",
			"status": "suggested",
			"provenance_refs": [],
			"annotations": {},
		},
	]
	canvas_node.set_document(document)
	await process_frame
	var graph_edit_node: GraphEdit = canvas_node.get_node_or_null("GraphEdit") as GraphEdit
	_expect(graph_edit_node != null, "GraphEdit host missing")
	var graph_nodes: Array[Node] = []
	for child_node: Node in graph_edit_node.get_children():
		if child_node is GraphNode:
			graph_nodes.append(child_node)
	_expect(graph_nodes.size() == 2, "Canvas did not render document nodes")
	_expect(
		graph_edit_node.get_connection_list().size() == 1,
		"Canvas did not render typed edge"
	)
	# Regression guard: nodes with no saved layout must fall through to their
	# staggered per-kind default position, not collapse onto the same point
	# (an empty-Dictionary "no saved position" sentinel used to satisfy the
	# TYPE_DICTIONARY check and stack every node at (0,0)).
	_expect(
		(graph_nodes[0] as GraphNode).position_offset
		!= (graph_nodes[1] as GraphNode).position_offset,
		"Nodes without a saved layout collapsed onto the same position"
	)
	var selected_ids: Array[String] = []
	canvas_node.node_selected.connect(
		func(node_id: String) -> void: selected_ids.append(node_id)
	)
	graph_edit_node.node_selected.emit(graph_nodes[0])
	_expect(
		selected_ids.size() == 1 and not selected_ids[0].is_empty(),
		"Canvas selection signal did not fire"
	)
	var persist_result: Dictionary = canvas_node.persist_layout()
	_expect(bool(persist_result.get("ok", false)), "Canvas layout persist failed")
	canvas_node.queue_free()
	await process_frame
	var saved_layout: Dictionary = persist_result.get("layout", {})
	LayoutStoreScript.new().delete_layout(
		test_owner_id,
		String(saved_layout.get("id", ""))
	)


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures.append(failure_message)
	push_error(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Graph Workspace Canvas tests: all passed")
		quit(0)
	else:
		push_error("Graph Workspace Canvas: %d failure(s)" % _failures.size())
		quit(1)
