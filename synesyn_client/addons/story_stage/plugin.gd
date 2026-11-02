@tool
extends EditorPlugin

## Registers the default-host project setting. Registers no autoload.


func _enter_tree() -> void:
	var key := "story_stage/default_host_script"
	if not ProjectSettings.has_setting(key):
		ProjectSettings.set_setting(key, "")
	ProjectSettings.set_initial_value(key, "")
	ProjectSettings.add_property_info({
		"name": key,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.gd",
	})
