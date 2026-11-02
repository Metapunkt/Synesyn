## Purpose: register_resources.gd
@tool
extends Node

# This script registers all the custom resource types for the SynTree plugin

func _enter_tree():
	# Register all resource types with type hints
	register_resource_types()

func register_resource_types():
	# Ensure all resources are recognized by Godot
	var script_paths = {
		"ContentSourceResource": "res://addons/syntree/scripts/resources/content_source_resource.gd",
		"ContentStateResource": "res://addons/syntree/scripts/resources/content_state_resource.gd",
		"ViewStateResource": "res://addons/syntree/scripts/resources/view_state_resource.gd",
		"GraphStateResource": "res://addons/syntree/scripts/resources/graph_state_resource.gd",
		"SyntreeResources": "res://addons/syntree/scripts/resources/syntree_resources.gd"
	}
	
	if not ProjectSettings.has_setting("_global_script_classes"):
		return
		
	var script_classes = ProjectSettings.get_setting("_global_script_classes")
	
	for class_name_key in script_paths.keys():
		var found = false
		var path = script_paths[class_name_key]
		
		for script_class in script_classes:
			if script_class.get("class") == class_name_key:
				found = true
				break
				
		if not found:
			# Add to global script classes
			var script = load(path)
			if script:
				script_classes.append({
					"base": "Resource",
					"class": class_name_key,
					"language": "GDScript",
					"path": path
				})
				
	# Update project settings
	ProjectSettings.set_setting("_global_script_classes", script_classes)
	ProjectSettings.save() 