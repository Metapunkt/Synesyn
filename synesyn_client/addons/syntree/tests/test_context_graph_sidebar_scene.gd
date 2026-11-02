extends SceneTree

const SynTreePanelScene = preload("res://addons/syntree/scenes/syntree_panel.tscn")


func _init() -> void:
	var panel: Control = SynTreePanelScene.instantiate()
	var graph_view: GraphEdit = panel.get_node(
		"MarginContainer/ScrollContainer/Main_VBoxContainer/"
		+ "ContentSourcesContainer/ContentSourcesScroll/SourcesDisplay/"
		+ "SourcesTabContainer/ContextGraphWorkspace/ContentGraph"
	)
	var sidebar: TabContainer = graph_view.get_parent().get_node(
		"ContextGraphSidebar"
	)
	var relationship_inspector: Control = sidebar.get_node(
		"RelationshipInspector"
	)
	var context_preview: Control = sidebar.get_node("ContextPreview")
	var context_sets: Control = sidebar.get_node("ContextSets")
	var context_trace: Control = sidebar.get_node("ContextTrace")
	var context_provenance: Control = sidebar.get_node("ContextProvenance")
	var context_proposals: Control = sidebar.get_node("ContextProposals")
	var context_diagnostics: Control = sidebar.get_node("ContextDiagnostics")
	var context_focus: Control = sidebar.get_node("ContextFocus")
	var context_layouts: Control = sidebar.get_node("ContextLayouts")
	var is_valid: bool = (
		sidebar.get_tab_count() == 9
		and is_instance_valid(relationship_inspector)
		and is_instance_valid(context_preview)
		and is_instance_valid(context_sets)
		and is_instance_valid(context_trace)
		and is_instance_valid(context_provenance)
		and is_instance_valid(context_proposals)
		and is_instance_valid(context_diagnostics)
		and is_instance_valid(context_focus)
		and is_instance_valid(context_layouts)
		and is_instance_valid(context_focus.get_node("%FitRelevantButton"))
		and is_instance_valid(context_layouts.get_node("%SaveLayoutButton"))
	)
	panel.free()
	if is_valid:
		print("Context graph sidebar scene tests: all passed")
		quit(0)
		return
	push_error("Context Graph sidebar scene contract is incomplete")
	quit(1)
