extends SceneTree

const ContentGraphNodeScene = preload(
	"res://addons/syntree/scenes/content_source_graph_node.tscn"
)
const ContentGraphControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/content_graph_controller.gd"
)


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var graph_node: GraphNode = ContentGraphNodeScene.instantiate()
	graph_node.name = "node-a"
	var graph_view: GraphEdit = GraphEdit.new()
	root.add_child(graph_view)
	graph_view.add_child(graph_node)
	var controller: Node = ContentGraphControllerScript.new()
	root.add_child(controller)
	controller.set("graph_view", graph_view)
	controller.set("_current_source_id", "source-a")
	controller.call("_apply_context_trace_overlay", {
		"included_nodes": [{"node_id": "source-a::node-a"}],
		"omitted_nodes": [],
	})
	var included_style: StyleBox = graph_node.get_theme_stylebox(
		"panel",
		"GraphNode"
	)
	var is_included: bool = (
		included_style is StyleBoxFlat
		and (included_style as StyleBoxFlat).border_color.is_equal_approx(
			Color(0.2, 0.78, 0.92, 0.95)
		)
	)
	controller.call("_apply_context_trace_overlay", {
		"included_nodes": [],
		"omitted_nodes": [{"node_id": "source-a::node-a"}],
	})
	var omitted_style: StyleBox = graph_node.get_theme_stylebox(
		"panel",
		"GraphNode"
	)
	var is_omitted: bool = (
		omitted_style is StyleBoxFlat
		and (omitted_style as StyleBoxFlat).border_color.is_equal_approx(
			Color(0.48, 0.5, 0.55, 0.9)
		)
	)
	controller.call("_apply_context_trace_overlay", {})
	var did_clear_trace: bool = not graph_node.has_theme_stylebox_override(
		"panel"
	)
	var diagnostic_ids: Array[String] = ["source-a::node-a"]
	controller.call("show_diagnostic_overlay", diagnostic_ids)
	var diagnostic_style: StyleBox = graph_node.get_theme_stylebox(
		"panel",
		"GraphNode"
	)
	var is_diagnostic: bool = (
		diagnostic_style is StyleBoxFlat
		and (diagnostic_style as StyleBoxFlat).border_color.is_equal_approx(
			Color(1.0, 0.45, 0.18, 0.98)
		)
	)
	var empty_ids: Array[String] = []
	controller.call("show_diagnostic_overlay", empty_ids)
	var did_clear_diagnostic: bool = not (
		graph_node.has_theme_stylebox_override("panel")
	)
	controller.queue_free()
	graph_view.queue_free()
	if (
		is_included
		and is_omitted
		and did_clear_trace
		and is_diagnostic
		and did_clear_diagnostic
	):
		print("Context trace graph overlay tests: all passed")
		quit(0)
		return
	push_error("Context execution trace graph overlay states failed")
	quit(1)
