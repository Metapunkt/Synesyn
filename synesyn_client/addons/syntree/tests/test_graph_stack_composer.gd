extends SceneTree

const ContentStateResourceScript = preload(
	"res://addons/syntree/scripts/resources/content_state_resource.gd"
)
const GraphDataBuilderScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_data_builder.gd"
)
const GraphRendererScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_renderer.gd"
)
const GraphStackComposerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_stack_composer.gd"
)


class NoSaveContentSource:
	extends ContentSourceResource

	func save_source(_source_id: String) -> bool:
		return true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state: ContentStateResource = ContentStateResourceScript.new()
	var source := NoSaveContentSource.new()
	state.content_source = source
	source.add_or_update_source_data(_member_source())
	source.add_or_update_source_data(_stack_source())

	var graph_view := GraphEdit.new()
	get_root().add_child(graph_view)
	var builder: GraphDataBuilder = GraphDataBuilderScript.new(state)
	var renderer: GraphRenderer = GraphRendererScript.new()
	var composer: RefCounted = GraphStackComposerScript.new()
	var created_nodes: Dictionary = composer.call(
		"build_stack_graph",
		state,
		graph_view,
		"stack_a",
		builder,
		renderer,
		_create_test_node
	)
	var failures: int = _expect(
		created_nodes.has("source_a__node_a"),
		"stack member node was not composed"
	)
	var graph_node: GraphNode = created_nodes.get("source_a__node_a")
	failures += _expect(
		is_instance_valid(graph_node)
		and graph_node.position_offset == Vector2(120.0, 240.0),
		"persisted stack layout position was not applied"
	)
	failures += _expect(
		graph_node.get_parent() == graph_view,
		"composed node was not added to GraphEdit"
	)
	graph_view.queue_free()
	if failures == 0:
		print("Graph stack composer tests: PASS")
		quit(0)
		return
	push_error("Graph stack composer tests: %d failure(s)" % failures)
	quit(1)


func _create_test_node(node_data: Dictionary) -> GraphNode:
	var graph_node := GraphNode.new()
	graph_node.name = str(node_data.get("node_id", ""))
	return graph_node


func _member_source() -> Dictionary:
	return {
		"meta": {
			"source_id": "source_a",
			"name": "Source A",
			"path": "user://syntree_regression/source_a.json",
			"ai_context": {
				"is_active": true,
				"metaprompt": false,
				"is_stack": false,
			},
		},
		"content": {
			"nodes": [
				{
					"node_id": "node_a",
					"content": "Node A",
					"relationships": {
						"parents": [],
						"children": [],
						"dependencies": [],
						"associations": [],
					},
				},
			],
		},
	}


func _stack_source() -> Dictionary:
	return {
		"meta": {
			"source_id": "stack_a",
			"name": "Stack A",
			"path": "user://syntree_regression/stack_a.json",
			"ai_context": {
				"is_active": true,
				"metaprompt": false,
				"is_stack": true,
				"stack_sources": ["source_a"],
				"stack_edges": [],
				"stack_layout": {
					"node_positions": {
						"source_a__node_a": {"x": 120.0, "y": 240.0},
					},
				},
			},
		},
		"content": {"nodes": []},
	}


func _expect(condition: bool, failure_message: String) -> int:
	if condition:
		return 0
	push_error(failure_message)
	return 1
