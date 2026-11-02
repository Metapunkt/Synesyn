## Purpose: SyntreeResources (script)
@tool
extends Resource
class_name SyntreeResources

# Load script references directly
const ContentStateResource = preload("res://addons/syntree/scripts/resources/content_state_resource.gd")
const ViewStateResource = preload("res://addons/syntree/scripts/resources/view_state_resource.gd")
const GraphStateResource = preload("res://addons/syntree/scripts/resources/graph_state_resource.gd")

# Resource references - use Resource as base type
@export var content_state: ContentStateResource
@export var view_state: ViewStateResource
@export var graph_state: GraphStateResource

# Initialization tracking
var _initialized: bool = false

func _init() -> void:
	print("SyntreeResources: Initializing...")
	
	# Create content state if needed
	if not is_instance_valid(content_state):
		content_state = ContentStateResource.new()
		
	# Ensure content source has correct directory
	if content_state and content_state.content_source:
		content_state.content_source.sources_directory = "res://addons/syntree/content_source_lists"
		
	# Create view state if needed
	if not is_instance_valid(view_state):
		view_state = ViewStateResource.new()
		
	# Create graph state if needed
	if not is_instance_valid(graph_state):
		graph_state = GraphStateResource.new()
		
	# Connect resources to each other
	_connect_resources()
	
	_initialized = true
	
	print("SyntreeResources: Initialization complete")

func _connect_resources() -> void:
	# Connect view_state to content_state signals if they exist
	if view_state and content_state:
		content_state.source_deleted.connect(
			func(source_id): _on_source_deleted(source_id)
		)

# Handler for when a source is deleted
func _on_source_deleted(source_id: String) -> void:
	# If this source is selected in the view state, clear it
	if view_state and view_state.get_current_source_id() == source_id:
		view_state.select_source(source_id, false)
		
	# If graph state has this source, clear its nodes
	if graph_state and graph_state.has_stored_positions(source_id):
		graph_state.clear_node_positions(source_id)

# Public API
func is_initialized() -> bool:
	return _initialized and content_state and view_state and graph_state

# Import data from ContentModel
func import_from_content_model(content_model: Node) -> void:
	if not content_model:
		return
		
	# Import content data
	if content_state:
		content_state.import_from_content_model(content_model)
		
	# Get current view state from ContentBus
	if view_state and content_model.get_parent() and content_model.get_parent().has_method("get_current_view_mode"):
		var content_bus = content_model.get_parent()
		view_state.current_mode = content_bus.get_current_view_mode()
		view_state.current_source_id = content_bus.get_current_source_id()
		
		# If ContentBus has a view history, import it
		if content_bus.has("_source_history_per_view"):
			var history = content_bus._source_history_per_view
			for mode in history:
				for source_id in history[mode]:
					view_state.add_to_history(mode, source_id)

# Save all modified resources
func save_all() -> void:
	# Mark all resources as changed to ensure they're saved
	if content_state:
		content_state.emit_changed()
	if view_state:
		view_state.emit_changed()
	if graph_state:
		graph_state.emit_changed() 
