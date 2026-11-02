class_name SynesynVisualProfileResolver
extends RefCounted

signal profile_changed(profile_id: String, profile_mode: String)

var _profiles_by_id: Dictionary = {}
var _default_profile_id: String = ""
var _active_profile_id: String = ""
var _active_profile_mode: String = "dark"


func register_profile(profile_definition: SynesynVisualProfileDefinition) -> Dictionary:
	if profile_definition == null:
		return {"ok": false, "errors": ["resolver:null_profile"]}
	var validation_result: Dictionary = _validate_profile(profile_definition)
	if not bool(validation_result.get("ok", false)):
		return validation_result
	_profiles_by_id[profile_definition.profile_id] = profile_definition
	if _default_profile_id.is_empty():
		_default_profile_id = profile_definition.profile_id
	if _active_profile_id.is_empty():
		_active_profile_id = profile_definition.profile_id
	return {"ok": true, "errors": []}


func set_default_profile(profile_id: String) -> bool:
	if not _profiles_by_id.has(profile_id):
		return false
	_default_profile_id = profile_id
	if _active_profile_id.is_empty():
		_active_profile_id = profile_id
	return true


func resolve_profile(
	requested_profile_id: String = "",
	requested_family: String = "",
	required_capabilities: PackedStringArray = PackedStringArray()
) -> SynesynVisualProfileDefinition:
	if _profiles_by_id.has(requested_profile_id):
		var requested_profile: SynesynVisualProfileDefinition = _profiles_by_id[
			requested_profile_id
		]
		if _supports_capabilities(requested_profile, required_capabilities):
			return requested_profile
	for profile_value in _profiles_by_id.values():
		var profile_definition: SynesynVisualProfileDefinition = profile_value
		if (
			(requested_family.is_empty() or profile_definition.profile_family == requested_family)
			and _supports_capabilities(profile_definition, required_capabilities)
		):
			return profile_definition
	if _profiles_by_id.has(_default_profile_id):
		return _profiles_by_id[_default_profile_id]
	return null


func activate_profile(profile_id: String, profile_mode: String) -> bool:
	if not _profiles_by_id.has(profile_id):
		return false
	var profile_definition: SynesynVisualProfileDefinition = _profiles_by_id[profile_id]
	var normalized_profile_mode: String = _normalize_profile_mode(
		profile_definition,
		profile_mode
	)
	_active_profile_id = profile_id
	_active_profile_mode = normalized_profile_mode
	profile_changed.emit(_active_profile_id, _active_profile_mode)
	return true


func get_active_profile() -> SynesynVisualProfileDefinition:
	return resolve_profile(_active_profile_id)


func get_active_profile_mode() -> String:
	return _active_profile_mode


func resolve_control_theme(
	profile_definition: SynesynVisualProfileDefinition,
	surface_id: String,
	profile_mode: String
) -> Theme:
	if profile_definition == null:
		return null
	return profile_definition.get_control_theme(surface_id, profile_mode)


func resolve_semantic_color(
	profile_definition: SynesynVisualProfileDefinition,
	semantic_role: String,
	profile_mode: String
) -> Color:
	var fallback_colors: Dictionary = _fallback_colors(profile_mode)
	if profile_definition == null:
		return fallback_colors.get(semantic_role, Color.MAGENTA)
	var semantic_colors: Dictionary = profile_definition.get_semantic_colors(profile_mode)
	var color_value: Variant = semantic_colors.get(
		semantic_role,
		fallback_colors.get(semantic_role, Color.MAGENTA)
	)
	if color_value is Color:
		return color_value
	return fallback_colors.get(semantic_role, Color.MAGENTA)


func resolve_metric(
	profile_definition: SynesynVisualProfileDefinition,
	metric_family: String,
	semantic_role: String,
	fallback_value: float = 0.0
) -> float:
	if profile_definition == null:
		return fallback_value
	var metric_values: Dictionary = {}
	match metric_family:
		"typography":
			metric_values = profile_definition.typography_roles
		"spacing":
			metric_values = profile_definition.spacing_roles
		"radius":
			metric_values = profile_definition.radius_roles
		"elevation":
			metric_values = profile_definition.elevation_roles
		"motion":
			metric_values = profile_definition.motion_durations_ms
		_:
			return fallback_value
	return float(metric_values.get(semantic_role, fallback_value))


func _validate_profile(
	profile_definition: SynesynVisualProfileDefinition
) -> Dictionary:
	var errors: Array[String] = []
	if profile_definition.schema_version != SynesynVisualProfileDefinition.SCHEMA_VERSION:
		errors.append("profile:unsupported_schema")
	if profile_definition.profile_id.strip_edges().is_empty():
		errors.append("profile:profile_id:required")
	if profile_definition.profile_family.strip_edges().is_empty():
		errors.append("profile:profile_family:required")
	if profile_definition.supported_profile_modes.is_empty():
		errors.append("profile:no_supported_modes")
	if profile_definition.required_semantic_roles.is_empty():
		errors.append("profile:no_semantic_roles")
	if not profile_definition.is_reduced_motion_supported:
		errors.append("profile:reduced_motion_required")
	return {"ok": errors.is_empty(), "errors": errors, "warnings": []}


func _supports_capabilities(
	profile_definition: SynesynVisualProfileDefinition,
	required_capabilities: PackedStringArray
) -> bool:
	for capability_id in required_capabilities:
		if not profile_definition.supported_capabilities.has(capability_id):
			return false
	return true


func _normalize_profile_mode(
	profile_definition: SynesynVisualProfileDefinition,
	requested_profile_mode: String
) -> String:
	if profile_definition.supported_profile_modes.has(requested_profile_mode):
		return requested_profile_mode
	if profile_definition.supported_profile_modes.has("dark"):
		return "dark"
	if not profile_definition.supported_profile_modes.is_empty():
		return profile_definition.supported_profile_modes[0]
	return "dark"


func _fallback_colors(profile_mode: String) -> Dictionary:
	if profile_mode == "light":
		return {
			"base": Color("f4f6fa"),
			"surface": Color("ffffff"),
			"raised": Color("e8edf5"),
			"accent": Color("245fbd"),
			"muted": Color("65738a"),
			"warning": Color("a15c00"),
			"danger": Color("b42318"),
			"success": Color("267a45"),
			"unavailable": Color("8b95a5"),
			"proposed": Color("6b5dd3"),
			"reviewed": Color("246b93"),
			"committed": Color("267a45"),
			"rejected": Color("b42318"),
			"deferred": Color("8a5a14"),
			"read_only": Color("65738a"),
			"degraded": Color("a15c00"),
		}
	return {
		"base": Color("10141d"),
		"surface": Color("171d29"),
		"raised": Color("202838"),
		"accent": Color("76a9ff"),
		"muted": Color("93a1b5"),
		"warning": Color("f0ad4e"),
		"danger": Color("ff6b6b"),
		"success": Color("5bc98c"),
		"unavailable": Color("6f7b8e"),
		"proposed": Color("a99bff"),
		"reviewed": Color("71c5e8"),
		"committed": Color("5bc98c"),
		"rejected": Color("ff6b6b"),
		"deferred": Color("d8a85d"),
		"read_only": Color("93a1b5"),
		"degraded": Color("f0ad4e"),
	}
