## Purpose: syntree.gd
@tool
extends EditorPlugin

const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")

# Remove variables related to manually managed PluginManager
# var plugin_manager = null 
# var persistence_service = null
# var conversation_manager = null
# var api_service = null
var panel_instance = null

# Define path to the main panel scene
const PANEL_SCENE = "res://addons/syntree/scenes/syntree_panel.tscn"

func _enter_tree():
	print("=== GodotSynTree Plugin Loading (Simplified - PluginManager is Autoload) ===")
	
	# REMOVE PluginManager instantiation - It's an Autoload now
	# plugin_manager = preload("res://addons/syntree/scripts/plugin_manager.gd").new()
	# add_child(plugin_manager)
	# print("GodotSynTree: PluginManager created.")

	# NOTE: Panel instantiation and setup is handled by syntree_plugin.gd
	
	print("=== GodotSynTree Plugin _enter_tree Complete (No PM setup here) ===")

# REMOVE Deferred Setup Function - Handled by syntree_plugin.gd
# func setup_panel_deferred(pm, p_content_state, p_view_state):

func _exit_tree():
	print("=== GodotSynTree Plugin Unloading ===")
	
	# Save content before unloading
	# Need persistence service - get from Autoload PluginManager                                                                                                                                                                                
	var pm = null
	if Engine.has_singleton("PluginManager"):
		pm = Engine.get_singleton("PluginManager")
	#	pm = PluginManager
	
	var persistence_service_local = null
	if is_instance_valid(pm) and pm.has_method("get_content_persistence"):
		persistence_service_local = pm.get_content_persistence()

	var bus := SynTreeAutoloads.content_bus()
	var content_state = bus.get_content_state_resource() if is_instance_valid(bus) else null
	var content_to_save = {}
	if is_instance_valid(content_state) and content_state.has_method("get_hierarchy"): 
		content_to_save = content_state.get_hierarchy()
	
	if is_instance_valid(persistence_service_local):
		print("GodotSynTree: Saving content...")
		if not content_to_save.is_empty(): 
			if persistence_service_local.save_content(content_to_save):
				print("GodotSynTree: Content saved successfully")
			else:
				push_error("GodotSynTree: Failed to save content using persistence service")
		else:
			print("GodotSynTree: No content data obtained from ContentStateResource to save.")
	else:
		push_warning("GodotSynTree: Persistence service not available during exit.")
	
	# Remove panel instance (Assume handled by syntree_plugin.gd _exit_tree)
	# if is_instance_valid(panel_instance): ...
		
	# REMOVE Clean up plugin manager - It's an Autoload
	# if is_instance_valid(plugin_manager): ...
	
	print("=== GodotSynTree Plugin Unloaded ===")
