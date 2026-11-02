## SynTree — AI conversation and reasoning interface for the Godot editor.
## Copyright © 2026 Ayodele Arigbabu | metapunkt.org | NTNU. All rights reserved.
## Licensed under [licence pending].
## Version: 0.0.3
## Enquiries: metapunkt@metapunkt.org
@tool
extends EditorPlugin

const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")

var syntree_panel
var window: Window
var is_detached: bool = false
var initialization_complete = false

const TOOLMENU_ADD_SELECTED := "SynTree/Add selected file(s) to Active Sources"
const TOOLMENU_ADD_CURRENT_SCRIPT := "SynTree/Add current script to Active Sources"

## Autoloads SynTree owns and requires. Declared here so the addon is drop-in:
## a host project does not have to hand-write these into project.godot.
## Insertion order is the autoload initialisation order.
##
## NotificationManager is deliberately absent: it declares `class_name
## NotificationManager`, and Godot rejects an autoload whose name collides with a
## global script class. It is instantiated directly by SyntreePanel and registered
## with ContentBus at runtime, so it never needed to be an autoload.
const REQUIRED_AUTOLOADS := {
	"PluginManager": "res://addons/syntree/scripts/plugin_manager.gd",
	"ContentBus": "res://addons/syntree/scripts/autoload/content_bus.gd",
}

## Only the autoloads this plugin actually added, so disabling the plugin never
## strips entries a host project registered itself.
var _autoloads_added: PackedStringArray = PackedStringArray()

func _enter_tree():
	print("=== GodotSynTreePlugin _enter_tree START ===")

	_register_required_autoloads()
	
	# Setup directories first
	print("Creating required directories...")
	var dir = DirAccess.open("res://addons/syntree")
	if dir:
		# Create required directories
		var required_dirs = [
			"ai_model_loaders",
			"conversation_threads",
			"config"
		]
		for directory in required_dirs:
			if not dir.dir_exists(directory):
				print("Creating directory: ", directory)
				dir.make_dir(directory)
	else:
		push_error("Failed to access plugin directory")
		return
	
	# Add to project settings with default empty values
	if not ProjectSettings.has_setting("syntree/openai_api_key"):
		ProjectSettings.set_setting("syntree/openai_api_key", "")
	if not ProjectSettings.has_setting("syntree/anthropic_api_key"):
		ProjectSettings.set_setting("syntree/anthropic_api_key", "")

	# Session data root (local disk) for artifacts/backups/run specs.
	# Default to Documents/Synesyn to match agreed local workflow.
	if not ProjectSettings.has_setting("synesyn/session_data_dir"):
		var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		var default_root := docs.path_join("Synesyn") if not String(docs).strip_edges().is_empty() else ""
		ProjectSettings.set_setting("synesyn/session_data_dir", default_root)

	# Per-project Run Spec UI schema path (optional).
	# If empty, SynTree will look for `res://syntree_run_spec_ui_schema.json`.
	if not ProjectSettings.has_setting("syntree/dev_agent/run_spec_ui_schema_path"):
		# If this project contains a ScenSyn module schema, prefer it by default.
		var default_schema := ""
		if FileAccess.file_exists("res://ScenSyn/syntree_run_spec_ui_schema.json"):
			default_schema = "res://ScenSyn/syntree_run_spec_ui_schema.json"
		ProjectSettings.set_setting("syntree/dev_agent/run_spec_ui_schema_path", default_schema)
				
	# Make sure the settings are saved
	ProjectSettings.save()
	
	# Create and add the panel immediately
	print("Instantiating SynTreePanel...")
	syntree_panel = preload("res://addons/syntree/scenes/syntree_panel.tscn").instantiate()
	
	print("Adding custom type...")
	add_custom_type("GodotSynTree", "Node", preload("res://addons/syntree/scripts/syntree.gd"), null)
	
	print("Setting up window...")
	window = Window.new()
	window.title = "SynTree (Detached)"
	window.size = Vector2(1600, 960)
	window.visible = false
	window.close_requested.connect(_on_window_close_requested)
	EditorInterface.get_base_control().add_child(window)
	
	print("Connecting signals...")
	# Godot 4: use the Signal API for robust connect/is_connected checks.
	if not syntree_panel.detach_plugin_window_toggled.is_connected(_toggle_detached_window):
		syntree_panel.detach_plugin_window_toggled.connect(_toggle_detached_window)
		print("Signal connected successfully (detach_plugin_window_toggled → _toggle_detached_window)")
	
	print("Adding panel to bottom panel...")
	add_control_to_bottom_panel(syntree_panel, "SynTree")

	# Minimal editor affordances: quickly add files/scripts to Active Sources.
	# These are tool menu items (avoid custom dock/context-menu complexity).
	if not Engine.is_editor_hint():
		pass
	else:
		remove_tool_menu_item(TOOLMENU_ADD_SELECTED)
		remove_tool_menu_item(TOOLMENU_ADD_CURRENT_SCRIPT)
		add_tool_menu_item(TOOLMENU_ADD_SELECTED, Callable(self, "_syntree_add_selected_files_to_active_sources"))
		add_tool_menu_item(TOOLMENU_ADD_CURRENT_SCRIPT, Callable(self, "_syntree_add_current_script_to_active_sources"))
	
	# Start the async initialization
	_continue_initialization.call_deferred()

func _continue_initialization():
	print("=== GodotSynTreePlugin continuing initialization ===")
	# Wait for tree if needed (though unlikely in deferred call)
	if not get_tree(): 
		await get_tree().ready

	# --- Wait for PluginManager (using direct reference instead of singleton) --- 
	await get_tree().process_frame
	
	var pm := SynTreeAutoloads.plugin_manager()
	if not is_instance_valid(pm):
		push_error("GodotSynTreePlugin: PluginManager node not found in the scene tree!")
		return
	
	if not pm.is_ready():
		print("GodotSynTreePlugin: Waiting for PluginManager initialization...")
		if pm.has_signal("initialization_completed"):
			await pm.initialization_completed
			print("GodotSynTreePlugin: PluginManager ready.")
		else:
			push_warning("GodotSynTreePlugin: PluginManager missing initialization_completed signal!")
			# Fallback delay
			await get_tree().create_timer(0.2).timeout

	# --- Wait for ContentBus Resources --- 
	await get_tree().process_frame
	
	var content_bus := SynTreeAutoloads.content_bus()
	if not is_instance_valid(content_bus):
		push_error("GodotSynTreePlugin: ContentBus node not found in the scene tree!")
		return
	
	# No need to check ContentBus.is_ready(), just await its resource signal
	print("GodotSynTreePlugin: Waiting for ContentBus resources...")
	
	# <<< USING TIMER DELAY instead of await resources_ready >>>
	print("GodotSynTreePlugin: Using simple timer delay instead of awaiting resources_ready signal.")
	await get_tree().create_timer(0.5).timeout # Simple delay
	print("GodotSynTreePlugin: Timer delay finished.")
	# if content_bus.has_signal("resources_ready"): 
	# 	await content_bus.resources_ready 
	# 	print("GodotSynTreePlugin: ContentBus resources_ready signal received.")
	# else:
	# 	push_warning("GodotSynTreePlugin: ContentBus missing resources_ready signal! Setup might fail.")
	# 	# Fallback delay
	# 	await get_tree().create_timer(0.1).timeout 
	# <<< END TIMER DELAY BLOCK >>>
		
	# --- Get Resources AFTER waiting --- 
	print("GodotSynTreePlugin: Attempting to get resources after delay...") # Use 'delay' in log
	var content_state = content_bus.get_content_state_resource()
	var view_state = content_bus.get_view_state_resource()
	
	# <<< Add Explicit Checks >>>
	var cs_valid = is_instance_valid(content_state)
	var vs_valid = is_instance_valid(view_state)
	print("GodotSynTreePlugin: Checking validity AFTER getting resources:")
	print("  - Content State valid: %s" % str(cs_valid))
	print("  - View State valid: %s" % str(vs_valid))
	# <<< End Explicit Checks >>>
	
	if not cs_valid or not vs_valid:
		push_error("GodotSynTreePlugin: Failed to get valid state resources from ContentBus after wait/delay.") # Use 'delay' in error
		return

	# <<< Restore Content Loading >>>
	if content_state.has_method("initialize_content_sources"): 
		print("GodotSynTreePlugin: Calling content_state.initialize_content_sources()...")
		var load_result = content_state.initialize_content_sources("res://addons/syntree/content_source_lists/")
		
		# --- ADD VIEW STATE SYNC HERE --- 
		print("GodotSynTreePlugin: Syncing ViewState selections with available sources...")
		var available_ids = content_state.get_source_ids() # Get IDs AFTER initialization
		if view_state.has_method("sync_selections_with_available"):
			view_state.sync_selections_with_available(available_ids)
			print("GodotSynTreePlugin: ViewState sync complete.")
		else:
			push_warning("GodotSynTreePlugin: ViewStateResource missing sync_selections_with_available method!")
		# --- END VIEW STATE SYNC --- 
			
		if load_result.get("success", false):
			# <<< Refresh List View AFTER successful load >>>
			print("GodotSynTreePlugin: Content sources loaded successfully. Refreshing ContentListView.")
			if is_instance_valid(syntree_panel) and syntree_panel.has_method("get_content_list_view"):
				var list_view = syntree_panel.get_content_list_view()
				if is_instance_valid(list_view) and list_view.has_method("refresh_sources"):
					list_view.refresh_sources()
					print("GodotSynTreePlugin: ContentListView refresh called.")
				else:
					push_warning("GodotSynTreePlugin: Could not get valid ContentListView or refresh_sources method.")
			else:
				push_warning("GodotSynTreePlugin: Could not get syntree_panel or get_content_list_view method.")
		else:
			# Loading failed
			push_error("GodotSynTreePlugin: Failed to initialize content sources: %s" % load_result.get("error", "Unknown error"))
	else:
		push_warning("GodotSynTreePlugin: ContentStateResource missing initialize_content_sources method.")

	# --- Call setup with ALL required arguments --- 
	
	# <<< Add Detailed Checks >>>
	var panel_valid = is_instance_valid(syntree_panel)
	var panel_has_setup = false
	if panel_valid:
		panel_has_setup = syntree_panel.has_method("setup")
		
	# <<< Moved Print Statement AFTER checks >>>
	print("GodotSynTreePlugin: Setting up SynTreePanel...") # Restored original log
	print("GodotSynTreePlugin: Checking panel validity and setup method...")
	print("  - is_instance_valid(syntree_panel): %s" % str(panel_valid))
	print("  - syntree_panel.has_method(\"setup\"): %s" % str(panel_has_setup))
	# <<< End Detailed Checks >>>
	
	if panel_valid and panel_has_setup:
		# <<< Log Before Await >>>
		print("GodotSynTreePlugin: About to await syntree_panel.setup()...")
		var setup_result = await syntree_panel.setup(self, pm, content_state, view_state)
		# <<< Log After Await >>>
		print("GodotSynTreePlugin: Awaited syntree_panel.setup(), result: %s" % str(setup_result))
		
		# Check result
		if not setup_result or not setup_result is Dictionary or not setup_result.has("success"):
			push_error("Invalid setup result from SynTreePanel")
			return
			
		if not setup_result.success:
			push_error("Failed to setup SynTreePanel: " + setup_result.error)
			return
	else:
		# <<< Log Else Reason >>>
		if not panel_valid:
			push_error("SyntreePanel instance invalid during delayed init.")
		elif not panel_has_setup:
			push_error("SyntreePanel instance valid but missing setup method during delayed init.")
		else:
			push_error("SyntreePanel setup check failed for unknown reason during delayed init.")
		return
	
	initialization_complete = true
	print("=== GodotSynTreePlugin initialization complete ===")

func _exit_tree():
	print("=== GodotSynTreePlugin _exit_tree START ===")
	if is_detached:
		_toggle_detached_window()
	remove_control_from_bottom_panel(syntree_panel)
	remove_custom_type("SynTree")
	remove_tool_menu_item(TOOLMENU_ADD_SELECTED)
	remove_tool_menu_item(TOOLMENU_ADD_CURRENT_SCRIPT)
	if window:
		window.queue_free()
	_unregister_required_autoloads()
	print("=== GodotSynTreePlugin _exit_tree END ===")

func _register_required_autoloads() -> void:
	for autoload_name in REQUIRED_AUTOLOADS:
		if ProjectSettings.has_setting("autoload/" + String(autoload_name)):
			continue
		var script_path := String(REQUIRED_AUTOLOADS[autoload_name])
		if not FileAccess.file_exists(script_path):
			push_warning("SynTree: cannot register autoload %s, missing %s" % [autoload_name, script_path])
			continue
		add_autoload_singleton(String(autoload_name), script_path)
		_autoloads_added.append(String(autoload_name))
	if not _autoloads_added.is_empty():
		push_warning("SynTree: registered autoloads %s. Reload the project to activate them." % String(", ").join(_autoloads_added))

func _unregister_required_autoloads() -> void:
	for autoload_name in _autoloads_added:
		remove_autoload_singleton(autoload_name)
	_autoloads_added.clear()

func _syntree_add_selected_files_to_active_sources() -> void:
	var dock := EditorInterface.get_file_system_dock()
	if not is_instance_valid(dock):
		push_warning("SynTree: FileSystem dock not available.")
		return

	var selected: Array = []
	if dock.has_method("get_selected_paths"):
		selected = dock.call("get_selected_paths")
	elif dock.has_method("get_selected_files"):
		selected = dock.call("get_selected_files")
	elif dock.has_method("get_selected_file_paths"):
		selected = dock.call("get_selected_file_paths")

	if selected.is_empty():
		push_warning("SynTree: No files selected in FileSystem dock.")
		return

	var added := 0
	for p_any in selected:
		var p := String(p_any).strip_edges()
		if p.is_empty():
			continue
		# Skip directories (best-effort check).
		if p.ends_with("/"):
			continue
		if _syntree_add_file_path_to_active_sources(p):
			added += 1

	if is_instance_valid(syntree_panel) and syntree_panel.has_method("get_content_list_view"):
		var lv: Node = syntree_panel.get_content_list_view()
		if is_instance_valid(lv) and lv.has_method("refresh_sources"):
			lv.refresh_sources()

	print("SynTree: Added %d file(s) to Active Sources." % added)

func _syntree_add_current_script_to_active_sources() -> void:
	var se := EditorInterface.get_script_editor()
	if not is_instance_valid(se):
		push_warning("SynTree: Script editor not available.")
		return
	var script: Script = null
	if se.has_method("get_current_script"):
		script = se.call("get_current_script")
	if not is_instance_valid(script):
		push_warning("SynTree: No current script.")
		return
	var p := String(script.resource_path).strip_edges()
	if p.is_empty():
		push_warning("SynTree: Current script has no resource_path.")
		return
	if _syntree_add_file_path_to_active_sources(p):
		if is_instance_valid(syntree_panel) and syntree_panel.has_method("get_content_list_view"):
			var lv: Node = syntree_panel.get_content_list_view()
			if is_instance_valid(lv) and lv.has_method("refresh_sources"):
				lv.refresh_sources()
		print("SynTree: Added current script to Active Sources: %s" % p)

func _syntree_add_file_path_to_active_sources(res_path: String) -> bool:
	if not Engine.is_editor_hint():
		return false
	var bus := SynTreeAutoloads.content_bus()
	if not is_instance_valid(bus):
		push_warning("SynTree: ContentBus autoload not available.")
		return false
	# Load (or update) a content source from file.
	var cs = bus.get_content_state_resource() if bus.has_method("get_content_state_resource") else null
	if not is_instance_valid(cs) or not cs.has_method("load_source_from_file"):
		push_warning("SynTree: ContentStateResource missing load_source_from_file.")
		return false
	var source_id := String(cs.load_source_from_file(String(res_path))).strip_edges()
	if source_id.is_empty():
		push_warning("SynTree: Failed to load source from file: %s" % res_path)
		return false
	# Mark active (persists).
	if bus.has_method("set_source_active_state"):
		bus.set_source_active_state(source_id, true)
	# Select it in the view state (helps discoverability).
	var vs = bus.get_view_state_resource() if bus.has_method("get_view_state_resource") else null
	if is_instance_valid(vs) and vs.has_method("select_source"):
		vs.select_source(source_id, true)
	return true

func _make_visible(visible):
	if visible:
		if is_detached:
			window.show()
		else:
			syntree_panel.show()
	else:
		if is_detached:
			window.hide()
		else:
			syntree_panel.hide()

func _toggle_detached_window(should_detach: bool = false) -> void:
	print("=== Toggle detached window called ===")
	print("Argument should_detach:", should_detach)
	print("Current state - is_detached:", is_detached)
	print("Panel parent:", syntree_panel.get_parent())
	
	if should_detach and not is_detached:
		print("Detaching panel")
		var current_parent = syntree_panel.get_parent()
		if current_parent != null:
			print("Removing from current parent:", current_parent)
			current_parent.remove_child(syntree_panel)
		print("Removing from bottom panel")
		remove_control_from_bottom_panel(syntree_panel)
		print("Adding to window")
		window.add_child(syntree_panel)
		syntree_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_center_window()
		window.show()
		is_detached = true
		print("Panel detached successfully")
	elif not should_detach and is_detached:
		print("Reattaching panel")
		window.hide()
		if syntree_panel.get_parent() == window:
			print("Removing from window")
			window.remove_child(syntree_panel)
		print("Adding to bottom panel")
		add_control_to_bottom_panel(syntree_panel, "SynTree")
		is_detached = false
		print("Panel reattached successfully")
	
	# Ensure the panel is visible and properly sized
	syntree_panel.visible = true
	syntree_panel.size = window.size if is_detached else Vector2(0, 0)
	print("Panel detach state updated - is_detached:", is_detached)
	print("Final panel parent:", syntree_panel.get_parent())
	print("=== Toggle detached window complete ===")

func _on_window_close_requested():
	_toggle_detached_window()

func _center_window():
	var screen_size = DisplayServer.screen_get_size()
	var window_size = window.size
	var new_position = (screen_size - window_size) / 2
	window.position = new_position
