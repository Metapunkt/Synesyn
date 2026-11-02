## Visual-profile bridge: registers compatibility profiles and resolves Themes /
## semantic colors for ThemeManager.
class_name SynesynVisualProfileBridge
extends RefCounted

const ResolverScript = preload(
	"res://addons/synesyn_visual_profiles/runtime/visual_profile_resolver.gd"
)
const VariationBuilderScript = preload(
	"res://addons/synesyn_visual_profiles/runtime/theme_variation_builder.gd"
)

var _resolver: SynesynVisualProfileResolver
var _is_initialized: bool = false


func initialize(
	profile_definitions: Array,
	default_profile_id: String
) -> Dictionary:
	## Accepts untyped Array so ThemeManager (synesyn_core) can call without a
	## hard dependency on SynesynVisualProfileDefinition at parse time.
	_resolver = ResolverScript.new()
	var errors: Array[String] = []
	for profile_definition in profile_definitions:
		VariationBuilderScript.decorate_profile(profile_definition)
		var registration_result: Dictionary = _resolver.register_profile(profile_definition)
		if not bool(registration_result.get("ok", false)):
			for registration_error in registration_result.get("errors", []):
				errors.append(
					"%s:%s"
					% [
						profile_definition.profile_id if profile_definition != null else "null",
						String(registration_error),
					]
				)
	if not _resolver.set_default_profile(default_profile_id):
		errors.append("bridge:default_profile_unavailable")
	_is_initialized = errors.is_empty()
	return {
		"ok": _is_initialized,
		"errors": errors,
	}


func is_initialized() -> bool:
	return _is_initialized


func get_profile(
	profile_family: String = "synesyn"
) -> SynesynVisualProfileDefinition:
	if not _is_initialized:
		return null
	return _resolver.resolve_profile("", profile_family)


func get_theme(
	surface_id: String,
	profile_mode: String,
	profile_family: String = "synesyn"
) -> Theme:
	var profile_definition: SynesynVisualProfileDefinition = get_profile(profile_family)
	return _resolver.resolve_control_theme(profile_definition, surface_id, profile_mode)


func get_semantic_color(
	semantic_role: String,
	profile_mode: String,
	profile_family: String = "synesyn"
) -> Color:
	var profile_definition: SynesynVisualProfileDefinition = get_profile(profile_family)
	return _resolver.resolve_semantic_color(
		profile_definition,
		semantic_role,
		profile_mode
	)


func apply_to_root(
	root_node: Node,
	surface_id: String,
	profile_mode: String,
	profile_family: String = "synesyn"
) -> bool:
	if not _is_initialized or root_node == null:
		return false
	var resolved_theme: Theme = get_theme(surface_id, profile_mode, profile_family)
	if resolved_theme == null:
		return false
	_apply_theme(root_node, resolved_theme, profile_family, profile_mode)
	_apply_isolated_descendants(
		root_node,
		resolved_theme,
		profile_family,
		profile_mode
	)
	return true


func _apply_theme(
	target_node: Node,
	resolved_theme: Theme,
	profile_family: String,
	profile_mode: String
) -> void:
	if target_node is Control or target_node is Window:
		target_node.set("theme", resolved_theme)
		target_node.set_meta("synesyn_visual_profile_family", profile_family)
		target_node.set_meta("synesyn_visual_profile_mode", profile_mode)


func _apply_isolated_descendants(
	parent_node: Node,
	resolved_theme: Theme,
	profile_family: String,
	profile_mode: String
) -> void:
	for child_node in parent_node.get_children():
		if child_node is CanvasLayer or child_node is SubViewport:
			_apply_first_control_roots(
				child_node,
				resolved_theme,
				profile_family,
				profile_mode
			)
		else:
			_apply_isolated_descendants(
				child_node,
				resolved_theme,
				profile_family,
				profile_mode
			)


func _apply_first_control_roots(
	parent_node: Node,
	resolved_theme: Theme,
	profile_family: String,
	profile_mode: String
) -> void:
	for child_node in parent_node.get_children():
		if child_node is Control or child_node is Window:
			_apply_theme(child_node, resolved_theme, profile_family, profile_mode)
		else:
			_apply_first_control_roots(
				child_node,
				resolved_theme,
				profile_family,
				profile_mode
			)
