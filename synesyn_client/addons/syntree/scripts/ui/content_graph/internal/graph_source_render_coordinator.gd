## Purpose: Choose synchronous or incremental ordinary-source canvas rendering.
extends Node

signal render_completed(generation: int, result: Dictionary)

const GraphSourceComposerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_source_composer.gd"
)
const GraphRenderBatcherScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_render_batcher.gd"
)

var _composer: RefCounted = GraphSourceComposerScript.new()
var _batcher: Node = null
var _generation: int = 0


func _ready() -> void:
	_batcher = GraphRenderBatcherScript.new()
	add_child(_batcher)
	Signal(_batcher, &"source_render_completed").connect(
		_on_batch_completed
	)


func render(
	graph_view: GraphEdit,
	source_id: String,
	source_data: Dictionary,
	data_builder: RefCounted,
	renderer: RefCounted,
	create_node: Callable
) -> int:
	_generation += 1
	_batcher.call("cancel")
	var nodes: Array = source_data.get("content", {}).get("nodes", [])
	if nodes.size() > 144:
		_batcher.call(
			"begin_source_render",
			graph_view,
			source_id,
			source_data,
			data_builder,
			renderer,
			create_node,
			_generation
		)
		return _generation
	var result: Dictionary = _composer.call(
		"build",
		graph_view,
		source_id,
		source_data,
		data_builder,
		renderer,
		create_node
	)
	call_deferred(
		"_emit_completion",
		_generation,
		result
	)
	return _generation


func cancel() -> int:
	_generation += 1
	if is_instance_valid(_batcher):
		_batcher.call("cancel")
	return _generation


func _on_batch_completed(
	generation: int,
	result: Dictionary
) -> void:
	if generation == _generation:
		render_completed.emit(generation, result)


func _emit_completion(
	generation: int,
	result: Dictionary
) -> void:
	if generation == _generation:
		render_completed.emit(generation, result)
