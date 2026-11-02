## Purpose: Manages the graph view of content nodes and their relationships
@tool
class_name ContentGraphController
extends Node

## ContentGraphController - per-panel controller for managing graph view of content sources

const DEBUG: bool = false

const GraphDataBuilder = preload("res://addons/syntree/scripts/ui/content_graph/internal/graph_data_builder.gd")
const GraphRenderer = preload("res://addons/syntree/scripts/ui/content_graph/internal/graph_renderer.gd")
const GraphStackComposerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_stack_composer.gd"
)
const GraphSelectionCoordinatorScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_selection_coordinator.gd"
)
const ContextCompilerBridgeScript = preload(
	"res://addons/syntree/scripts/services/chat/internal/conversation_context_compiler_bridge.gd"
)
const ContextSetPanelControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/context_set_panel_controller.gd"
)
const ContextTraceOverlayScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/context_trace_overlay.gd"
)
const ContextProvenancePanelControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/context_provenance_panel_controller.gd"
)
const ContextProposalPanelControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/context_proposal_panel_controller.gd"
)
const ContextDiagnosticsPanelControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/context_diagnostics_panel_controller.gd"
)
const ContextFocusPanelControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/context_focus_panel_controller.gd"
)
const ContextLayoutPanelControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/context_layout_panel_controller.gd"
)
const LatestDeferredJobScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/latest_deferred_job.gd"
)
const GraphCanvasInteractionScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_canvas_interaction.gd"
)
const GraphNodeCommandsScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_node_commands.gd"
)
const GraphRelationshipWorkflowScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_relationship_workflow.gd"
)
const GraphNodeFactoryScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_node_factory.gd"
)
const GraphSourceRenderCoordinatorScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_source_render_coordinator.gd"
)
const HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")

func _dbg(msg: Variant) -> void:
	if DEBUG:
		print(msg)

## Content state resource reference
var content_state: ContentStateResource = null

## View state resource reference (optional, for selection propagation)
var view_state: ViewStateResource = null

## Graph view reference  
var graph_view: GraphEdit = null

var _data_builder: GraphDataBuilder = null
var _renderer: GraphRenderer = null
var _stack_composer: RefCounted = null
var _selection_coordinator: RefCounted = null
var _relationship_inspector: Control = null
var _context_preview: Control = null
var _context_set_panel: Control = null
var _context_trace_panel: Control = null
var _context_set_panel_controller: RefCounted = null
var _context_provenance_controller: RefCounted = null
var _context_proposal_controller: RefCounted = null
var _context_diagnostics_controller: RefCounted = null
var _context_focus_controller: RefCounted = null
var _context_layout_controller: RefCounted = null
var _canvas_interaction: RefCounted = null
var _node_commands: RefCounted = null
var _relationship_workflow: RefCounted = null
var _node_factory: RefCounted = GraphNodeFactoryScript.new()
var _source_renderer: Node = null
var _context_graph_hub_client: Node = null
var _conversation_manager: Object = null
var _compiler_bridge: RefCounted = ContextCompilerBridgeScript.new()
var _compile_job: RefCounted = LatestDeferredJobScript.new()
var _context_trace_overlay: RefCounted = ContextTraceOverlayScript.new()
var _current_source_id: String = ""
var _prompt_chain_preview_node_ids: Array[String] = []
var _render_generation: int = 0
var _pending_focus_node_id: String = ""

var _is_initialized: bool = false

# Stack graph mode (composed graph from multiple sources; edits persist to stack-root only)
var _stack_mode: bool = false
var _current_stack_id: String = ""

func _resolve_source_id_for_graph_node(node_id: String) -> String:
	# Prefer looking up the live node instance's metadata when available.
	# This avoids edge cases where node ids are not in node_to_source_map (or are ambiguous).
	if is_instance_valid(graph_view):
		var inst := graph_view.get_node_or_null(NodePath(String(node_id)))
		if inst is ContentSourceGraphNode:
			var nd: Dictionary = (inst as ContentSourceGraphNode).node_data
			if nd is Dictionary:
				var meta: Dictionary = nd.get("meta", {})
				var sid := str(meta.get("source_id", "")).strip_edges()
				if not sid.is_empty():
					return sid

	if not is_instance_valid(content_state):
		return ""
	if content_state.has_method("parse_composed_node_id"):
		var parsed := content_state.parse_composed_node_id(node_id)
		if parsed is Dictionary and parsed.get("is_composed", false) == true:
			return str(parsed.get("source_id", ""))
	if content_state.has_method("get_source_for_node"):
		return str(content_state.get_source_for_node(node_id))
	return ""

func _init() -> void:
	add_to_group("graph_controllers")

## Initializes the controller with required references
## Returns true if initialization was successful
func initialize(
	state_resource: ContentStateResource,
	view: GraphEdit,
	injected_view_state: ViewStateResource = null,
	conversation_manager: Object = null
) -> bool:
	_dbg("ContentGraphController: Initializing with ContentStateResource and view")
	
	content_state = state_resource
	graph_view = view
	view_state = injected_view_state
	_conversation_manager = conversation_manager
	if _data_builder == null:
		_data_builder = GraphDataBuilder.new(content_state)
	else:
		_data_builder.set_content_state(content_state)
	if _renderer == null:
		_renderer = GraphRenderer.new()
	if not is_instance_valid(_source_renderer):
		_source_renderer = GraphSourceRenderCoordinatorScript.new()
		add_child(_source_renderer)
		Signal(
			_source_renderer,
			&"render_completed"
		).connect(
			_on_source_render_completed
		)
	if _stack_composer == null:
		_stack_composer = GraphStackComposerScript.new()
	if _selection_coordinator == null:
		_selection_coordinator = GraphSelectionCoordinatorScript.new()
	if _canvas_interaction == null:
		_canvas_interaction = GraphCanvasInteractionScript.new()
		_canvas_interaction.call("setup", graph_view)
	if _node_commands == null:
		_node_commands = GraphNodeCommandsScript.new()
		_node_commands.call(
			"setup",
			content_state,
			graph_view,
			self,
			_resolve_source_id_for_graph_node,
			get_graph_nodes,
			initialize_with_source
		)
	_node_factory.call(
		"setup",
		content_state,
		_on_node_metaprompt_toggled,
		_on_node_active_source_toggled,
		_on_node_delete_requested
	)
	_bind_context_graph_sidebars()
	
	if not is_instance_valid(content_state):
		push_error("ContentGraphController: Invalid null content state resource")
		return false
		
	if not graph_view:
		push_error("ContentGraphController: Invalid null graph view")
		return false

	# Connect to content state signals (once)
	if content_state.has_signal("metaprompt_state_changed") and not content_state.metaprompt_state_changed.is_connected(_on_metaprompt_state_changed):
		content_state.metaprompt_state_changed.connect(_on_metaprompt_state_changed)
	if content_state.has_signal("active_state_changed") and not content_state.active_state_changed.is_connected(_on_active_state_changed):
		content_state.active_state_changed.connect(_on_active_state_changed)
	
	# Connect to view signals
	_connect_graph_signals()
	
	_is_initialized = true
	_dbg("ContentGraphController: Initialization successful")
	return true

func _bind_context_graph_sidebars() -> void:
	if not is_instance_valid(graph_view) or not is_instance_valid(graph_view.get_parent()):
		return
	var inspector_node: Node = graph_view.get_parent().get_node_or_null(
		"ContextGraphSidebar/RelationshipInspector"
	)
	if inspector_node is Control:
		_relationship_inspector = inspector_node
		if _relationship_workflow == null:
			_relationship_workflow = GraphRelationshipWorkflowScript.new()
			_relationship_workflow.call(
				"setup",
				content_state,
				graph_view,
				_relationship_inspector,
				initialize_with_source,
				_graph_node_ids
			)
		_connect_inspector_event("save_requested", _on_relationship_save_requested)
		_connect_inspector_event("cancel_new_requested", _on_relationship_cancel_requested)
		_connect_inspector_event("reverse_requested", _on_relationship_reverse_requested)
		_connect_inspector_event("disconnect_requested", _on_relationship_disconnect_requested)
		_connect_inspector_event(
			"endpoints_create_requested",
			_on_relationship_endpoints_create_requested
		)
	var preview_node: Node = graph_view.get_parent().get_node_or_null(
		"ContextGraphSidebar/ContextPreview"
	)
	if preview_node is Control:
		_context_preview = preview_node
		_connect_preview_event("refresh_requested", _on_context_preview_requested)
		_connect_preview_event(
			"compiler_enabled_changed",
			_on_context_compiler_enabled_changed
		)
		if is_instance_valid(_conversation_manager):
			_context_preview.call(
				"set_compiler_enabled",
				bool(_conversation_manager.get_meta("use_context_compiler", false))
			)
	var context_set_node: Node = graph_view.get_parent().get_node_or_null(
		"ContextGraphSidebar/ContextSets"
	)
	if context_set_node is Control:
		_context_set_panel = context_set_node
		if not is_instance_valid(_context_graph_hub_client):
			_context_graph_hub_client = HubSubstrateClientScript.new()
			add_child(_context_graph_hub_client)
			_context_graph_hub_client.configure_from_runtime_config()
		_context_set_panel_controller = ContextSetPanelControllerScript.new()
		_context_set_panel_controller.call(
			"setup",
			_context_set_panel,
			content_state,
			_context_preview,
			_conversation_manager,
			_compiler_bridge,
			_context_graph_hub_client
		)
	var trace_node: Node = graph_view.get_parent().get_node_or_null(
		"ContextGraphSidebar/ContextTrace"
	)
	if trace_node is Control:
		_context_trace_panel = trace_node
		var refresh_trace: Callable = _on_context_trace_requested
		var refresh_trace_signal: Signal = Signal(
			trace_node,
			&"refresh_requested"
		)
		if not refresh_trace_signal.is_connected(refresh_trace):
			refresh_trace_signal.connect(refresh_trace)
	var provenance_node: Node = graph_view.get_parent().get_node_or_null(
		"ContextGraphSidebar/ContextProvenance"
	)
	if provenance_node is Control:
		_context_provenance_controller = (
			ContextProvenancePanelControllerScript.new()
		)
		_context_provenance_controller.call(
			"setup",
			provenance_node,
			content_state
		)
	var proposal_node: Node = graph_view.get_parent().get_node_or_null(
		"ContextGraphSidebar/ContextProposals"
	)
	if proposal_node is Control:
		_context_proposal_controller = (
			ContextProposalPanelControllerScript.new()
		)
		_context_proposal_controller.call(
			"setup",
			proposal_node,
			content_state,
			_conversation_manager,
			_context_graph_hub_client
		)
	var diagnostics_node: Node = graph_view.get_parent().get_node_or_null(
		"ContextGraphSidebar/ContextDiagnostics"
	)
	if diagnostics_node is Control:
		_context_diagnostics_controller = (
			ContextDiagnosticsPanelControllerScript.new()
		)
		_context_diagnostics_controller.call(
			"setup",
			diagnostics_node,
			content_state,
			_conversation_manager,
			_context_graph_hub_client,
			self
		)
	var focus_node: Node = graph_view.get_parent().get_node_or_null(
		"ContextGraphSidebar/ContextFocus"
	)
	if focus_node is Control:
		_context_focus_controller = ContextFocusPanelControllerScript.new()
		_context_focus_controller.call(
			"setup",
			focus_node,
			content_state,
			self
		)
	var layout_node: Node = graph_view.get_parent().get_node_or_null(
		"ContextGraphSidebar/ContextLayouts"
	)
	if layout_node is Control:
		_context_layout_controller = ContextLayoutPanelControllerScript.new()
		_context_layout_controller.call("setup", layout_node, self)

func _connect_inspector_event(event_id: String, callback: Callable) -> void:
	if (
		not is_instance_valid(_relationship_inspector)
		or not _relationship_inspector.has_signal(event_id)
	):
		return
	var inspector_event: Signal = Signal(
		_relationship_inspector,
		StringName(event_id)
	)
	if not inspector_event.is_connected(callback):
		inspector_event.connect(callback)

func _connect_preview_event(event_id: String, callback: Callable) -> void:
	if (
		not is_instance_valid(_context_preview)
		or not _context_preview.has_signal(event_id)
	):
		return
	var preview_event: Signal = Signal(_context_preview, StringName(event_id))
	if not preview_event.is_connected(callback):
		preview_event.connect(callback)

## Connects signals from the graph view
func _connect_graph_signals() -> void:
	if not graph_view:
		push_error("Cannot connect signals to null graph view")
		return
		
	_dbg("ContentGraphController: Connecting signals to graph view")
	
	# IMPORTANT: Connect to the graph's custom signals for selected/deselected 
	# (content_node_selected/deselected), NOT the built-in GraphEdit signals
	
	# First disconnect any existing connections to avoid duplicates
	if graph_view.has_signal("content_node_selected") and graph_view.content_node_selected.is_connected(_on_graph_node_selected):
		graph_view.content_node_selected.disconnect(_on_graph_node_selected)
		
	if graph_view.has_signal("content_node_deselected") and graph_view.content_node_deselected.is_connected(_on_graph_node_deselected):
		graph_view.content_node_deselected.disconnect(_on_graph_node_deselected)
	
	# Now connect our custom signals
	if graph_view.has_signal("content_node_selected"):
		graph_view.content_node_selected.connect(_on_graph_node_selected)
		_dbg("ContentGraphController: Connected to content_node_selected signal")
	else:
		push_error("ContentGraphController: Missing expected content_node_selected signal on graph view")
	
	if graph_view.has_signal("content_node_deselected"):
		graph_view.content_node_deselected.connect(_on_graph_node_deselected)
		_dbg("ContentGraphController: Connected to content_node_deselected signal")  
	else:
		push_error("ContentGraphController: Missing expected content_node_deselected signal on graph view")
		
	# Connect movement and connection signals
	if graph_view.has_signal("node_moved") and not graph_view.node_moved.is_connected(_on_graph_node_moved):
		graph_view.node_moved.connect(_on_graph_node_moved)
		_dbg("ContentGraphController: Connected node_moved signal")
		
	if graph_view.has_signal("node_connected") and not graph_view.node_connected.is_connected(_on_graph_nodes_connected):
		graph_view.node_connected.connect(_on_graph_nodes_connected)
		_dbg("ContentGraphController: Connected node_connected signal")
		
	if graph_view.has_signal("node_disconnected") and not graph_view.node_disconnected.is_connected(_on_graph_nodes_disconnected):
		graph_view.node_disconnected.connect(_on_graph_nodes_disconnected)
		_dbg("ContentGraphController: Connected node_disconnected signal")

## Disconnects all signals from the graph view to prevent callbacks on removed nodes
func _disconnect_graph_signals() -> void:
	if not graph_view:
		return
		
	_dbg("ContentGraphController: Disconnecting signals from graph view")
	
	# Disconnect custom signals
	if graph_view.has_signal("content_node_selected") and graph_view.content_node_selected.is_connected(_on_graph_node_selected):
		graph_view.content_node_selected.disconnect(_on_graph_node_selected)
		_dbg("ContentGraphController: Disconnected content_node_selected signal")
		
	if graph_view.has_signal("content_node_deselected") and graph_view.content_node_deselected.is_connected(_on_graph_node_deselected):
		graph_view.content_node_deselected.disconnect(_on_graph_node_deselected)
		_dbg("ContentGraphController: Disconnected content_node_deselected signal")
	
	# Disconnect movement and connection signals
	if graph_view.has_signal("node_moved") and graph_view.node_moved.is_connected(_on_graph_node_moved):
		graph_view.node_moved.disconnect(_on_graph_node_moved)
		_dbg("ContentGraphController: Disconnected node_moved signal")
		
	if graph_view.has_signal("node_connected") and graph_view.node_connected.is_connected(_on_graph_nodes_connected):
		graph_view.node_connected.disconnect(_on_graph_nodes_connected)
		_dbg("ContentGraphController: Disconnected node_connected signal")
		
	if graph_view.has_signal("node_disconnected") and graph_view.node_disconnected.is_connected(_on_graph_nodes_disconnected):
		graph_view.node_disconnected.disconnect(_on_graph_nodes_disconnected)
		_dbg("ContentGraphController: Disconnected node_disconnected signal")

## Handle node selection in the graph
func _on_graph_node_selected(node_id: String) -> void:
	_dbg("ContentGraphController: Node selected with ID: %s" % node_id)
	if _selection_coordinator == null:
		return
	
	var source_id: String = _resolve_source_id_for_graph_node(node_id)
	_dbg("ContentGraphController: Source ID for node %s: %s" % [node_id, source_id])
	_selection_coordinator.call(
		"select_node",
		content_state,
		view_state,
		node_id,
		source_id,
		_stack_mode
	)

## Handle node deselection in the graph
func _on_graph_node_deselected(node_id: String) -> void:
	# NOTE: Clicking empty graph space or deselecting a node should NOT:
	# - Deselect the SOURCE (we still want to view that source's graph)
	# - Call content_state.deselect_node() (which emits source_selected(false) and causes view switch)
	# 
	# Node deselection in GraphView is purely visual - it doesn't change which source we're viewing.
	# This prevents the unintended view switch to ListView when clicking on empty graph space.
	_dbg("ContentGraphController: Node deselected with ID: %s (no-op, keeping source view)" % node_id)

func _on_graph_node_moved(node_id: String, node_position: Vector2) -> void:
	# Positions are visual working state. They are persisted only when the user
	# explicitly saves a named layout, never into semantic source/artifact data.
	pass

func _on_graph_nodes_connected(
	from_id: String,
	from_port: int,
	to_id: String,
	to_port: int
) -> void:
	_relationship_workflow.call(
		"connection_requested",
		from_id,
		from_port,
		to_id,
		to_port
	)

func _on_graph_nodes_disconnected(
	from_id: String,
	from_port: int,
	to_id: String,
	to_port: int
) -> void:
	_relationship_workflow.call(
		"disconnection_requested",
		from_id,
		from_port,
		to_id,
		to_port
	)

func _on_relationship_save_requested(edge_data: Dictionary) -> void:
	_relationship_workflow.call("save", edge_data)

func _on_relationship_cancel_requested() -> void:
	_relationship_workflow.call("cancel_new")

func _on_relationship_endpoints_create_requested(
	from_id: String,
	to_id: String
) -> void:
	_relationship_workflow.call("create_endpoints", from_id, to_id)

func _on_relationship_reverse_requested(edge_id: String) -> void:
	_relationship_workflow.call("reverse", edge_id)

func _on_relationship_disconnect_requested(edge_id: String) -> void:
	_relationship_workflow.call("disconnect_edge", edge_id)

func _current_edges() -> Array:
	return _relationship_workflow.call("current_edges")

func _graph_node_ids() -> Array[String]:
	var node_ids: Array[String] = []
	if not is_instance_valid(graph_view):
		return node_ids
	for child in graph_view.get_children():
		if child is GraphNode:
			node_ids.append(str(child.name))
	return node_ids

func _refresh_relationship_inspector() -> void:
	if is_instance_valid(_relationship_inspector):
		_relationship_inspector.call("set_edges", _current_edges())
		_relationship_inspector.call("set_node_ids", _graph_node_ids())
		_relationship_inspector.call("clear_editor")
	if _context_set_panel_controller != null:
		var owner_source_id: String = (
			_current_stack_id if _stack_mode else _current_source_id
		)
		_context_set_panel_controller.call(
			"refresh_graph",
			owner_source_id,
			_graph_node_ids()
		)
	if _context_provenance_controller != null:
		var provenance_owner_id: String = (
			_current_stack_id if _stack_mode else _current_source_id
		)
		_context_provenance_controller.call(
			"refresh_graph",
			provenance_owner_id,
			_graph_node_ids()
		)
	if _context_proposal_controller != null:
		var proposal_owner_id: String = (
			_current_stack_id if _stack_mode else _current_source_id
		)
		_context_proposal_controller.call(
			"refresh_graph",
			proposal_owner_id
		)
	if _context_diagnostics_controller != null:
		var diagnostics_owner_id: String = (
			_current_stack_id if _stack_mode else _current_source_id
		)
		_context_diagnostics_controller.call(
			"refresh_graph",
			diagnostics_owner_id
		)
	if _context_focus_controller != null:
		var focus_owner_id: String = (
			_current_stack_id if _stack_mode else _current_source_id
		)
		_context_focus_controller.call(
			"refresh_graph",
			focus_owner_id,
			_graph_node_ids()
		)
	if _context_layout_controller != null:
		var layout_owner_id: String = (
			_current_stack_id if _stack_mode else _current_source_id
		)
		_context_layout_controller.call("refresh_graph", layout_owner_id)
	_apply_prompt_chain_preview()
	if is_instance_valid(_conversation_manager):
		_apply_context_trace_overlay(
			_conversation_manager.get_meta(
				"latest_context_execution_trace",
				{}
			)
		)


func show_prompt_chain_preview(node_ids: Array[String]) -> void:
	_prompt_chain_preview_node_ids = node_ids.duplicate()
	_apply_prompt_chain_preview()


func show_diagnostic_overlay(record_ids: Array[String]) -> void:
	_context_trace_overlay.call(
		"apply_diagnostic_ids",
		graph_view,
		_current_source_id,
		_stack_mode,
		record_ids
	)


func apply_focus_filter(result: Dictionary) -> void:
	_canvas_interaction.call("apply_focus_filter", result)


func reset_focus_filter() -> void:
	_canvas_interaction.call("reset_focus_filter")


func fit_relevant_context() -> void:
	_canvas_interaction.call("fit_relevant_context")


func capture_canvas_layout() -> Dictionary:
	return _canvas_interaction.call("capture_layout")


func apply_canvas_layout(layout_data: Dictionary) -> void:
	_canvas_interaction.call("apply_layout", layout_data)


func _apply_prompt_chain_preview() -> void:
	if not is_instance_valid(graph_view):
		return
	for child in graph_view.get_children():
		if not child is ContentSourceGraphNode:
			continue
		var graph_node_id: String = str(child.name)
		var artifact_node_id: String = graph_node_id
		if (
			not _stack_mode
			and not graph_node_id.contains("::")
			and not _current_source_id.is_empty()
		):
			artifact_node_id = "%s::%s" % [
				_current_source_id,
				graph_node_id,
			]
		child.set_prompt_chain_highlight(
			_prompt_chain_preview_node_ids.has(graph_node_id)
			or _prompt_chain_preview_node_ids.has(artifact_node_id)
		)


func _on_context_trace_requested() -> void:
	if (
		not is_instance_valid(_context_trace_panel)
		or not is_instance_valid(_conversation_manager)
	):
		return
	var trace: Dictionary = _conversation_manager.get_meta(
		"latest_context_execution_trace",
		{}
	)
	_context_trace_panel.call("set_trace", trace)
	_apply_context_trace_overlay(trace)


func _apply_context_trace_overlay(trace: Dictionary) -> void:
	_context_trace_overlay.call(
		"apply",
		graph_view,
		_current_source_id,
		_stack_mode,
		trace
	)


func _on_context_preview_requested(options: Dictionary) -> void:
	if not is_instance_valid(content_state) or not is_instance_valid(_context_preview):
		return
	var active_source_ids: Array[String] = []
	for source_id_any in content_state.get_active_sources():
		active_source_ids.append(str(source_id_any))
	var frozen_options: Dictionary = options.duplicate(true)
	_compile_job.call(
		"schedule",
		func() -> Dictionary:
			return _compiler_bridge.call(
				"compile_sources",
				content_state,
				active_source_ids,
				frozen_options
			),
		func(result_any: Variant) -> void:
			_finish_context_preview(result_any, frozen_options)
	)


func _finish_context_preview(
	result_any: Variant,
	options: Dictionary
) -> void:
	var result: Dictionary = result_any
	_context_preview.call("set_compile_result", result)
	if is_instance_valid(_conversation_manager):
		_conversation_manager.set_meta("context_compiler_preset", options.get("preset", "balanced"))
		_conversation_manager.set_meta("context_compiler_max_tokens", options.get("max_tokens", 8000))
		if bool(_conversation_manager.get_meta("use_context_compiler", false)):
			_conversation_manager.set_meta("frozen_context_compile_result", result)

func _on_context_compiler_enabled_changed(is_enabled: bool) -> void:
	if not is_instance_valid(_conversation_manager):
		return
	_conversation_manager.set_meta("use_context_compiler", is_enabled)
	if not is_enabled and _conversation_manager.has_meta("frozen_context_compile_result"):
		_conversation_manager.remove_meta("frozen_context_compile_result")

## Add a method to clear all graph nodes
func clear_graph() -> void:
	_dbg("ContentGraphController: Clearing graph")
	if not graph_view:
		return
		
	# Disconnect signals temporarily to avoid callbacks during clear
	_disconnect_graph_signals()
	
	# Clear all connections first
	if graph_view.has_method("clear_connections"):
		graph_view.clear_connections()
	
	# Remove all GraphNode instances
	var nodes_to_remove = []
	for child in graph_view.get_children():
		if child is GraphNode:
			nodes_to_remove.append(child)
	
	# Remove nodes in a separate loop to avoid modifying collection during iteration
	for node in nodes_to_remove:
		if node.has_method("cleanup"):
			node.cleanup()
		graph_view.remove_child(node)
		node.queue_free()
	
	# Reconnect signals
	_connect_graph_signals()
	_dbg("ContentGraphController: Graph cleared successfully")

# Add handler for active source state changes FROM CONTENT BUS
func _on_active_state_changed(signal_source_id: String, is_active: bool) -> void:
	_node_commands.call("update_active_source", signal_source_id, is_active)
	if (
		is_instance_valid(_context_preview)
		and is_instance_valid(_conversation_manager)
		and bool(_conversation_manager.get_meta("use_context_compiler", false))
	):
		_context_preview.call("refresh_preview")

# Add handler for metaprompt state changes FROM CONTENT BUS
func _on_metaprompt_state_changed(signal_source_id: String, is_metaprompt: bool) -> void:
	_node_commands.call(
		"update_metaprompt_source",
		signal_source_id,
		is_metaprompt
	)

func get_graph_nodes() -> Array:
	if not graph_view:
		return []
	
	var nodes = []
	for child in graph_view.get_children():
		if child is GraphNode:  # This includes ContentSourceGraphNode since it inherits from GraphNode
			nodes.append(child)
	return nodes

func initialize_with_source(source_id: String) -> void:
	_dbg("ContentGraphController: Initializing graph with id: " + source_id)
	
	if not _is_initialized:
		push_error("ContentGraphController: Cannot initialize with source - controller not initialized")
		return
		
	if not graph_view:
		push_error("ContentGraphController: Cannot initialize with source - graph view not set")
		return
		
	if not content_state:
		push_error("ContentGraphController: Cannot initialize with source - content state not set")
		return

	# Resolve: callers may pass a node_id; normalize to its owning source_id.
	var resolved_source_id := String(source_id)
	if not resolved_source_id.is_empty() and content_state.has_method("get_source_data"):
		var direct = content_state.get_source_data(resolved_source_id)
		if direct.is_empty() and content_state.has_method("get_source_for_node"):
			var parent_src := String(content_state.get_source_for_node(resolved_source_id))
			if not parent_src.is_empty():
				_dbg("ContentGraphController: Resolved node_id -> source_id: %s -> %s" % [resolved_source_id, parent_src])
				resolved_source_id = parent_src

	# Get source data for resolved id
	var source_data = content_state.get_source_data(resolved_source_id)
	if source_data.is_empty():
		push_error("ContentGraphController: Failed to retrieve source data for id: " + resolved_source_id)
		return
	_compile_job.call("cancel")
	_current_source_id = resolved_source_id

	# Detect stack sources (stack-root-only orchestration)
	_stack_mode = false
	_current_stack_id = ""
	if content_state.has_method("is_stack_source") and content_state.is_stack_source(resolved_source_id):
		_stack_mode = true
		_current_stack_id = resolved_source_id
	_canvas_interaction.call("set_context", _current_source_id, _stack_mode)
	_node_commands.call("set_context", _stack_mode, _current_stack_id)
	_relationship_workflow.call(
		"set_context",
		_stack_mode,
		_current_source_id,
		_current_stack_id
	)
	
	_render_generation = int(_source_renderer.call("cancel"))
	clear_graph()
	_pending_focus_node_id = (
		String(source_id)
		if String(source_id) != resolved_source_id
		else ""
	)
	if _stack_mode:
		_build_graph_from_stack_data(resolved_source_id, source_data)
		_on_source_render_completed(_render_generation, {"ok": true})
	else:
		_render_generation = int(_source_renderer.call(
			"render",
			graph_view,
			resolved_source_id,
			source_data,
			_data_builder,
			_renderer,
			_create_graph_node
		))

func _build_graph_from_stack_data(stack_id: String, _stack_data: Dictionary) -> void:
	_dbg("ContentGraphController: Building stack graph from: " + stack_id)
	if not is_instance_valid(_stack_composer):
		return
	var created_nodes: Dictionary = _stack_composer.call(
		"build_stack_graph",
		content_state,
		graph_view,
		stack_id,
		_data_builder,
		_renderer,
		_create_graph_node
	)
	_dbg("ContentGraphController: Stack graph build complete with %d nodes" % created_nodes.size())

func _focus_node_if_present(node_id: String) -> void:
	if not is_instance_valid(graph_view):
		return
	for child in graph_view.get_children():
		if child is ContentSourceGraphNode and String(child.node_id) == node_id:
			# Move the view near the node (best-effort; GraphEdit has scroll_offset)
			if "scroll_offset" in graph_view:
				graph_view.scroll_offset = child.position_offset - (graph_view.size * 0.5)
			return

func _on_source_render_completed(
	generation: int,
	result: Dictionary
) -> void:
	if generation != _render_generation:
		return
	if not bool(result.get("ok", false)):
		push_error("ContentGraphController: Batched source render failed")
		return
	_refresh_relationship_inspector()
	if not _pending_focus_node_id.is_empty():
		call_deferred(
			"_focus_node_if_present",
			_pending_focus_node_id
		)
	_pending_focus_node_id = ""

# Add handler for active source toggle from nodes
func _on_node_active_source_toggled(node_id: String, is_active: bool) -> void:
	_node_commands.call("toggle_active", node_id, is_active)

# Update _create_graph_node to connect active source signal
func _create_graph_node(node_data: Dictionary) -> GraphNode:
	return _node_factory.call("create", node_data)

func _on_node_delete_requested(node_id: String) -> void:
	_node_commands.call("request_delete", node_id)

# Add handler for metaprompt toggle from nodes
func _on_node_metaprompt_toggled(node_id: String, is_metaprompt: bool) -> void:
	_node_commands.call("toggle_metaprompt", node_id, is_metaprompt)
