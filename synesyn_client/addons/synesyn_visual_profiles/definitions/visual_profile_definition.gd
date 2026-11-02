class_name SynesynVisualProfileDefinition
extends Resource

const SCHEMA_VERSION: int = 1

@export var schema_version: int = SCHEMA_VERSION
@export var profile_id: String = ""
@export var profile_family: String = ""
@export var supported_capabilities: PackedStringArray = PackedStringArray(
	["direct_navigation", "reduced_motion", "projector", "high_contrast"]
)
@export var supported_profile_modes: PackedStringArray = PackedStringArray(
	["light", "dark", "projector", "high_contrast"]
)
@export var required_semantic_roles: PackedStringArray = PackedStringArray(
	[
		"base",
		"surface",
		"raised",
		"accent",
		"muted",
		"warning",
		"danger",
		"success",
		"unavailable",
		"proposed",
		"reviewed",
		"committed",
		"rejected",
		"deferred",
		"read_only",
		"degraded",
	]
)
@export var is_reduced_motion_supported: bool = true

@export_group("Control Themes")
@export var base_light: Theme
@export var base_dark: Theme
@export var utility_light: Theme
@export var utility_dark: Theme
@export var console_light: Theme
@export var console_dark: Theme
@export var tools_light: Theme
@export var tools_dark: Theme

@export_group("Semantic Colors")
@export var semantic_colors_light: Dictionary = {}
@export var semantic_colors_dark: Dictionary = {}
@export var semantic_colors_projector: Dictionary = {}
@export var semantic_colors_high_contrast: Dictionary = {}

@export_group("Typography and Geometry")
@export var typography_roles: Dictionary = {
	"display": 30,
	"title": 24,
	"section": 18,
	"body": 16,
	"support": 14,
	"status": 13,
}
@export var spacing_roles: Dictionary = {
	"tight": 4,
	"default": 8,
	"relaxed": 12,
	"section": 16,
	"region": 24,
}
@export var radius_roles: Dictionary = {
	"control": 10,
	"card": 10,
	"dialog": 14,
}
@export var elevation_roles: Dictionary = {
	"base": 0,
	"raised": 1,
	"overlay": 2,
	"modal": 3,
}
@export var border_roles: Dictionary = {
	"none": 0,
	"subtle": 1,
	"emphasis": 2,
}
@export var focus_roles: Dictionary = {
	"width": 2,
	"offset": 2,
	"semantic_color": "accent",
}

@export_group("Motion")
@export var motion_durations_ms: Dictionary = {
	"instant": 0,
	"quick": 120,
	"standard": 220,
	"deliberate": 360,
}
@export var motion_easing_roles: Dictionary = {
	"enter": "ease_out",
	"exit": "ease_in",
	"move": "ease_in_out",
}
@export var reduced_motion_durations_ms: Dictionary = {
	"instant": 0,
	"quick": 0,
	"standard": 0,
	"deliberate": 80,
}


func to_dictionary() -> Dictionary:
	return {
		"schema_version": schema_version,
		"profile_id": profile_id,
		"profile_family": profile_family,
		"supported_capabilities": Array(supported_capabilities),
		"supported_profile_modes": Array(supported_profile_modes),
		"required_semantic_roles": Array(required_semantic_roles),
		"is_reduced_motion_supported": is_reduced_motion_supported,
		"typography_roles": typography_roles.duplicate(true),
		"spacing_roles": spacing_roles.duplicate(true),
		"radius_roles": radius_roles.duplicate(true),
		"elevation_roles": elevation_roles.duplicate(true),
		"border_roles": border_roles.duplicate(true),
		"focus_roles": focus_roles.duplicate(true),
		"motion_durations_ms": motion_durations_ms.duplicate(true),
		"motion_easing_roles": motion_easing_roles.duplicate(true),
		"reduced_motion_durations_ms": reduced_motion_durations_ms.duplicate(true),
	}


func get_control_theme(surface_id: String, profile_mode: String) -> Theme:
	var normalized_surface_id: String = surface_id
	if not normalized_surface_id in ["base", "utility", "console", "tools"]:
		normalized_surface_id = "base"
	var theme_mode_id: String = "light" if profile_mode == "light" else "dark"
	var property_id: String = "%s_%s" % [normalized_surface_id, theme_mode_id]
	var theme_value: Variant = get(property_id)
	if theme_value is Theme:
		return theme_value
	var fallback_value: Variant = get("base_%s" % theme_mode_id)
	if fallback_value is Theme:
		return fallback_value
	if base_dark != null:
		return base_dark
	return base_light


func get_semantic_colors(profile_mode: String) -> Dictionary:
	match profile_mode:
		"light":
			return semantic_colors_light
		"projector":
			return semantic_colors_projector
		"high_contrast":
			return semantic_colors_high_contrast
		_:
			return semantic_colors_dark
