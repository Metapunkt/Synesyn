extends Node

## Universal light/dark theme switcher (autoload: ThemeManager).
##
## Usage in a scene — no script required:
##   1. Add the scene's root Control (or any Control/Window) to the group
##      "synesyn_themed".
##   2. Set a node metadata "theme_surface" to one of:
##      "base" (default), "utility", "console", "tools".
##   The manager applies the correct theme on load and re-applies on every
##   mode switch. CanvasLayer children don't inherit Control themes, so put
##   such roots in the group individually.
##
## Switching at runtime (routine):
##   ThemeManager.toggle_mode()            # flip light <-> dark
##   ThemeManager.set_mode("light")        # explicit
##   ThemeManager.mode_changed.connect(...) # react (e.g. update toggle label)
##
## Theme packs:
##   res://addons/synesyn_core/themes/theme_config.tres  (bundled drop-in default)
##   res://ScenSyn/themes/theme_config.tres              (optional host override)
##
## Visual profile bridge (addons/synesyn_visual_profiles) decorates those Themes
## with shared type variations (SynesynPrimaryAction, SynesynSurfacePanel, …).

signal mode_changed(mode: String)

## Bundled drop-in pack first; optional fuller host pack (ScenSyn) overrides when present.
const CORE_CONFIG_PATH := "res://addons/synesyn_core/themes/theme_config.tres"
const HOST_CONFIG_PATH := "res://ScenSyn/themes/theme_config.tres"
const GROUP := "synesyn_themed"
const META_SURFACE := "theme_surface"
const SYNESYN_PROFILE_PATH := (
	"res://ScenSyn/themes/profiles/synesyn_compatibility.tres"
)
const READYMADE_PROFILE_PATH := (
	"res://readymade/ui/readymade_compatibility.tres"
)
const VISUAL_PROFILE_BRIDGE_PATH := (
	"res://addons/synesyn_visual_profiles/runtime/visual_profile_bridge.gd"
)

var config: ThemeConfig
var mode: String = "dark"
var visual_profile_bridge: RefCounted

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Prefer host pack when present so ScenSyn keeps its full surface set;
	# otherwise use the bundled synesyn_core pack for drop-in addon docks.
	if ResourceLoader.exists(HOST_CONFIG_PATH):
		config = load(HOST_CONFIG_PATH) as ThemeConfig
	elif ResourceLoader.exists(CORE_CONFIG_PATH):
		config = load(CORE_CONFIG_PATH) as ThemeConfig
	if config == null:
		config = ThemeConfig.new()
	_init_visual_profile_bridge()
	mode = _load_saved_mode()
	get_tree().node_added.connect(_on_node_added)
	# Apply to anything already present (e.g. the boot scene's root).
	call_deferred("_apply_all")
	call_deferred("_apply_stored_ui_scale")

func _init_visual_profile_bridge() -> void:
	## Optional: synesyn_visual_profiles + host profile .tres. Never hard-preload.
	if not ResourceLoader.exists(VISUAL_PROFILE_BRIDGE_PATH):
		return
	var bridge_script: Variant = load(VISUAL_PROFILE_BRIDGE_PATH)
	if bridge_script == null:
		return
	visual_profile_bridge = bridge_script.new() as RefCounted
	if visual_profile_bridge == null or not visual_profile_bridge.has_method("initialize"):
		visual_profile_bridge = null
		return
	var bridge_result: Dictionary = visual_profile_bridge.call(
		"initialize",
		_load_visual_profiles(),
		"synesyn_compatibility"
	)
	if not bool(bridge_result.get("ok", false)):
		push_warning(
			"ThemeManager: visual profile bridge unavailable: %s"
			% bridge_result.get("errors", [])
		)

func _load_visual_profiles() -> Array:
	## Untyped Array so this script parses without synesyn_visual_profiles types.
	var profile_definitions: Array = []
	for profile_path in [SYNESYN_PROFILE_PATH, READYMADE_PROFILE_PATH]:
		if not ResourceLoader.exists(profile_path):
			continue
		var profile_definition: Resource = load(profile_path)
		if profile_definition != null:
			profile_definitions.append(profile_definition)
	return profile_definitions

func get_theme_for(surface: String) -> Theme:
	if (
		visual_profile_bridge != null
		and visual_profile_bridge.has_method("is_initialized")
		and visual_profile_bridge.call("is_initialized")
		and visual_profile_bridge.has_method("get_theme")
	):
		var resolved_theme: Theme = visual_profile_bridge.call("get_theme", surface, mode) as Theme
		if resolved_theme != null:
			return resolved_theme
	return config.get_theme(surface, mode)

func get_visual_profile(profile_family: String = "synesyn") -> Variant:
	if (
		visual_profile_bridge == null
		or not visual_profile_bridge.has_method("is_initialized")
		or not visual_profile_bridge.call("is_initialized")
		or not visual_profile_bridge.has_method("get_profile")
	):
		return null
	return visual_profile_bridge.call("get_profile", profile_family)

func get_semantic_color(
	semantic_role: String,
	profile_family: String = "synesyn"
) -> Color:
	if (
		visual_profile_bridge == null
		or not visual_profile_bridge.has_method("is_initialized")
		or not visual_profile_bridge.call("is_initialized")
		or not visual_profile_bridge.has_method("get_semantic_color")
	):
		return Color.MAGENTA
	return visual_profile_bridge.call(
		"get_semantic_color",
		semantic_role,
		mode,
		profile_family
	) as Color

func is_dark() -> bool:
	return mode == "dark"

func set_mode(new_mode: String) -> void:
	if new_mode != "light" and new_mode != "dark":
		return
	if new_mode == mode:
		return
	mode = new_mode
	_save_mode()
	_apply_all()
	mode_changed.emit(mode)

func toggle_mode() -> void:
	set_mode("light" if mode == "dark" else "dark")

func _apply_all() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(GROUP):
		_apply_to(node)


func _apply_stored_ui_scale() -> void:
	if not is_inside_tree() or get_tree().root == null:
		return
	RuntimeConfig.apply_stored_ui_scale(get_tree().root)

func _apply_to(node: Node) -> void:
	if node is Control or node is Window:
		var surface: String = "base"
		if node.has_meta(META_SURFACE):
			surface = str(node.get_meta(META_SURFACE))
		if (
			visual_profile_bridge != null
			and visual_profile_bridge.has_method("apply_to_root")
			and bool(visual_profile_bridge.call("apply_to_root", node, surface, mode))
		):
			return
		var t: Theme = get_theme_for(surface)
		if t != null:
			node.set("theme", t)

func _on_node_added(node: Node) -> void:
	if node.is_in_group(GROUP):
		_apply_to(node)

func _ui_save_path() -> String:
	var dest: String = RuntimeConfig.get_ui_config_path()
	RuntimeConfig.migrate_file_if_needed(dest, ["user://synesyn_ui.cfg"])
	return dest

func _load_saved_mode() -> String:
	var save_path: String = _ui_save_path()
	var cf := ConfigFile.new()
	if cf.load(save_path) == OK:
		return str(cf.get_value("ui", "mode", config.default_mode))
	return config.default_mode

func _save_mode() -> void:
	var save_path: String = _ui_save_path()
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var cf := ConfigFile.new()
	cf.load(save_path)
	cf.set_value("ui", "mode", mode)
	cf.save(save_path)
