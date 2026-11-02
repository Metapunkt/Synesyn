extends SceneTree

const GraphRenderBatcherScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_render_batcher.gd"
)

const MEDIUM_NODE_COUNT: int = 240
const BATCH_SIZE: int = 20
const RENDER_TARGET_MS: float = 3000.0

var _did_complete: bool = false
var _completed_result: Dictionary = {}


class FakeBuilder:
	extends RefCounted

	func build_node_payload(
		_node_id: String,
		_source_id: String,
		_source_data: Dictionary,
		node_data: Dictionary,
		_include_source: bool,
		_is_stack: bool
	) -> Dictionary:
		return {
			"complete_node_data": node_data,
			"is_active": true,
			"is_metaprompt": false,
		}


class FakeRenderer:
	extends RefCounted

	func add_node_to_graph(
		graph_view: GraphEdit,
		graph_node: Node,
		canvas_point: Vector2,
		_is_active: bool,
		_is_metaprompt: bool
	) -> void:
		graph_view.add_child(graph_node)
		(graph_node as GraphNode).position_offset = canvas_point

	func connect_children_edges(
		_graph_view: GraphEdit,
		_created_nodes: Dictionary,
		_nodes: Array
	) -> void:
		pass

	func connect_typed_edges(
		_graph_view: GraphEdit,
		_created_nodes: Dictionary,
		_edges: Array
	) -> void:
		pass


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var graph_view: GraphEdit = GraphEdit.new()
	root.add_child(graph_view)
	var batcher: Node = GraphRenderBatcherScript.new()
	root.add_child(batcher)
	Signal(batcher, &"source_render_completed").connect(
		_on_render_completed
	)
	var nodes: Array = []
	for node_index in range(MEDIUM_NODE_COUNT):
		nodes.append({
			"node_id": "node-%d" % node_index,
			"content": "Rendered fixture %d" % node_index,
		})
	var started_usec: int = Time.get_ticks_usec()
	batcher.call(
		"begin_source_render",
		graph_view,
		"source-a",
		{"content": {"nodes": nodes}},
		FakeBuilder.new(),
		FakeRenderer.new(),
		_create_node,
		1,
		BATCH_SIZE
	)
	var rendered_frames: int = 0
	var maximum_growth: int = 0
	var previous_count: int = 0
	while not _did_complete and rendered_frames < 100:
		await process_frame
		rendered_frames += 1
		var current_count: int = _graph_node_count(graph_view)
		maximum_growth = maxi(
			maximum_growth,
			current_count - previous_count
		)
		previous_count = current_count
	var elapsed_ms: float = (
		Time.get_ticks_usec() - started_usec
	) / 1000.0
	var did_pass: bool = (
		_did_complete
		and bool(_completed_result.get("ok", false))
		and _graph_node_count(graph_view) == MEDIUM_NODE_COUNT
		and rendered_frames > 1
		and maximum_growth <= BATCH_SIZE
		and elapsed_ms <= RENDER_TARGET_MS
	)
	batcher.queue_free()
	graph_view.queue_free()
	print(
		"Rendered canvas fixture: nodes=%d frames=%d max_batch=%d time=%.2fms"
		% [
			MEDIUM_NODE_COUNT,
			rendered_frames,
			maximum_growth,
			elapsed_ms,
		]
	)
	if did_pass:
		print("Graph render batcher tests: all passed")
		quit(0)
		return
	push_error("Rendered graph construction was blocking or exceeded target")
	quit(1)


func _create_node(node_data: Dictionary) -> GraphNode:
	var graph_node := GraphNode.new()
	graph_node.name = str(node_data.get("node_id", ""))
	return graph_node


func _graph_node_count(graph_view: GraphEdit) -> int:
	var graph_node_count: int = 0
	for child_node in graph_view.get_children():
		if child_node is GraphNode:
			graph_node_count += 1
	return graph_node_count


func _on_render_completed(
	_generation: int,
	result: Dictionary
) -> void:
	_did_complete = true
	_completed_result = result
