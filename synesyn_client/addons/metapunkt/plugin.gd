## Metapunkt — Agent definition, orchestration, and workspace management for the Godot editor.
## Copyright © 2026 Ayodele Arigbabu | metapunkt.org | NTNU. All rights reserved.
## Licensed under [licence pending].
## Version: 0.0.3
## Enquiries: metapunkt@metapunkt.org
@tool
extends EditorPlugin

const PLUGIN_NAME = "Metapunkt"

var main_panel_instance = null
var _orchestrator = null
var _endpoint_handler = null
const _MAIN_SCENE: PackedScene = preload("res://addons/metapunkt/scenes/metapunkt_main.tscn")

func _enter_tree() -> void:
	# Intent: this EditorPlugin must always show *something* in the editor UI.
	# The runtime "Tools" UI in ScenSyn is separate; this editor plugin surfaces a dock/panel for inspection/debug.
	#
	# IMPORTANT: Metapunkt is installed under `synesyn/synesyn_client/`. Ensure you have opened that Godot
	# project (`synesyn/synesyn_client/project.godot`) and enabled the plugin in Project Settings → Plugins.

	# Prefer the full UI scene (anchors + layout are already set in the .tscn).
	if _MAIN_SCENE:
		var inst: Node = _MAIN_SCENE.instantiate()
		if inst is Control:
			main_panel_instance = inst
		else:
			push_warning("Metapunkt plugin: metapunkt_main.tscn did not instantiate a Control; falling back to minimal UI.")

	# Fallback: minimal but visible UI (avoid a zero-sized blank panel).
	if not (main_panel_instance is Control):
		var root := VBoxContainer.new()
		root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.custom_minimum_size = Vector2(400, 200)
		var title := Label.new()
		title.text = "Metapunkt (editor plugin)"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(title)
		var hint := Label.new()
		hint.text = "UI scene failed to load. Check console for warnings."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		root.add_child(hint)
		main_panel_instance = root

	# Cache the EndpointHandler node if present (metapunkt_main.tscn includes it).
	if main_panel_instance:
		_endpoint_handler = main_panel_instance.get_node_or_null("MetapunktEndpointHandler")

	add_control_to_bottom_panel(main_panel_instance, PLUGIN_NAME)

func _exit_tree() -> void:
	if main_panel_instance:
		remove_control_from_bottom_panel(main_panel_instance)
		main_panel_instance.queue_free()
	
	# EndpointHandler is owned by the panel scene; nothing else to clean up here.
	_endpoint_handler = null

func _has_main_screen() -> bool:
	return false

func _make_visible(visible: bool) -> void:
	if main_panel_instance:
		main_panel_instance.visible = visible

func _get_plugin_name() -> String:
	return PLUGIN_NAME

# Provide access to the endpoint handler for testing
func get_endpoint_handler():
	return _endpoint_handler 
