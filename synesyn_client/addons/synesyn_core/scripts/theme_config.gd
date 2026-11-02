extends Resource
class_name ThemeConfig

## Single source of truth for UI theming (owned by synesyn_core — ADR 0017).
## Maps each UI "surface" (base / utility / console / tools) to a light and a
## dark Theme. Host projects typically edit ScenSyn/themes/theme_config.tres.

@export_enum("light", "dark") var default_mode: String = "dark"

@export_group("Base")
@export var base_light: Theme
@export var base_dark: Theme

@export_group("Utility")
@export var utility_light: Theme
@export var utility_dark: Theme

@export_group("Console")
@export var console_light: Theme
@export var console_dark: Theme

@export_group("Tools")
@export var tools_light: Theme
@export var tools_dark: Theme

## Return the Theme for a given surface ("base"/"utility"/"console"/"tools")
## and mode ("light"/"dark"). Falls back to base of the same mode, then to any
## non-null theme, so a missing slot never leaves a node unthemed.
func get_theme(surface: String, mode: String) -> Theme:
	var t: Theme = get("%s_%s" % [surface, mode])
	if t == null:
		t = get("base_%s" % mode)
	return t
