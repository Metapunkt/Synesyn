extends SceneTree

const GraphNodeScene = preload(
	"res://addons/syntree/scenes/content_source_graph_node.tscn"
)
const RelationshipInspectorScene = preload(
	"res://addons/syntree/scenes/relationship_inspector.tscn"
)
const LightTheme = preload(
	"res://addons/synesyn_core/themes/SynesynUtility_light.tres"
)
const DarkTheme = preload(
	"res://addons/synesyn_core/themes/SynesynUtility_contemporary_dark.tres"
)


func _init() -> void:
	var graph_node: GraphNode = GraphNodeScene.instantiate()
	root.add_child(graph_node)
	var state_badge: Label = graph_node.get_node("%StateBadge")
	var port_labels: Array[String] = []
	for label_id in [
		"StructuralPort",
		"DependencyPort",
		"EvidentialPort",
		"SemanticPort",
	]:
		port_labels.append(str(graph_node.get_node(label_id).text))
	var inspector: Control = RelationshipInspectorScene.instantiate()
	root.add_child(inspector)
	var legend: RichTextLabel = inspector.get_node(
		"MarginContainer/VBoxContainer/Legend"
	)
	var themes_are_valid: bool = true
	for checked_theme in [LightTheme, DarkTheme]:
		graph_node.theme = checked_theme
		var panel_style: StyleBox = graph_node.get_theme_stylebox(
			"panel",
			"GraphNode"
		)
		var font_color: Color = graph_node.get_theme_color(
			"font_color",
			"Label"
		)
		themes_are_valid = (
			themes_are_valid
			and panel_style != null
			and font_color.a > 0.5
		)
	var is_valid: bool = (
		state_badge.text.begins_with("State:")
		and port_labels == [
			"Structural",
			"Dependency",
			"Evidential",
			"Semantic",
		]
		and legend.text.contains("containment")
		and legend.text.contains("ordering")
		and not graph_node.has_theme_color_override("font_color")
		and themes_are_valid
	)
	graph_node.queue_free()
	inspector.queue_free()
	if is_valid:
		print("Context Graph accessibility tests: all passed")
		quit(0)
		return
	push_error("Context Graph non-color accessibility contract failed")
	quit(1)
