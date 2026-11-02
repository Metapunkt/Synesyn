## Purpose: plugin.gd
@tool
extends EditorPlugin

const ContentBus = preload("res://addons/syntree/scripts/autoload/content_bus.gd")
const NotificationManager = preload("res://addons/syntree/scripts/utils/notification_manager.gd")
const ResourceRegistration = preload("res://addons/syntree/scripts/register_resources.gd")

func _enter_tree():
	# Register resources first before creating autoloads
	var resource_registration = ResourceRegistration.new()
	resource_registration.register_resource_types()
	
	# Add autoloads
	add_autoload_singleton("NotificationManager", "res://addons/syntree/scripts/utils/notification_manager.gd")
	add_autoload_singleton("ContentBus", "res://addons/syntree/scripts/autoload/content_bus.gd")
	
	# Initialize resources directory if it doesn't exist
	var resources_dir = "res://resources"
	if not DirAccess.dir_exists_absolute(resources_dir):
		DirAccess.make_dir_recursive_absolute(resources_dir)
	
	print("SynTree plugin initialized")

func _exit_tree():
	# Clean-up the autoloads
	remove_autoload_singleton("ContentBus")
	remove_autoload_singleton("NotificationManager")
	
	print("SynTree plugin cleaned up") 