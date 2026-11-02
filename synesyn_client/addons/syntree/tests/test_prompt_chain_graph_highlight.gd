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
	var included_ids: Array[String] = ["source-a::node-a"]
	controller.call("show_prompt_chain_preview", included_ids)
	var highlighted_style: StyleBox = graph_node.get_theme_stylebox(
		"panel",
		"GraphNode"
	)
	var has_gold_border: bool = (
		highlighted_style is StyleBoxFlat
		and (highlighted_style as StyleBoxFlat).border_width_left == 4
		and (
			highlighted_style as StyleBoxFlat
		).border_color.is_equal_approx(
			Color(0.95, 0.72, 0.25, 0.95)
		)
	)
	var empty_ids: Array[String] = []
	controller.call("show_prompt_chain_preview", empty_ids)
	var did_clear: bool = not graph_node.has_theme_stylebox_override("panel")
	controller.queue_free()
	graph_view.queue_free()
	if has_gold_border and did_clear:
		print("Prompt chain graph highlight tests: all passed")
		quit(0)
		return
	push_error("Prompt Chain graph preview highlight was not transient")
	quit(1)
