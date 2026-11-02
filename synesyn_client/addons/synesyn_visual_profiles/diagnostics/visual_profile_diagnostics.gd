class_name SynesynVisualProfileDiagnostics
extends RefCounted


static func inspect_profile(
	profile_definition: SynesynVisualProfileDefinition
) -> Dictionary:
	var unresolved_roles: Dictionary = {}
	if profile_definition == null:
		return {
			"ok": false,
			"errors": ["diagnostics:null_profile"],
			"unresolved_roles": unresolved_roles,
		}
	for profile_mode in profile_definition.supported_profile_modes:
		var semantic_colors: Dictionary = profile_definition.get_semantic_colors(profile_mode)
		var missing_roles: PackedStringArray = PackedStringArray()
		for semantic_role in profile_definition.required_semantic_roles:
			if not semantic_colors.has(semantic_role):
				missing_roles.append(semantic_role)
		if not missing_roles.is_empty():
			unresolved_roles[profile_mode] = Array(missing_roles)
	return {
		"ok": unresolved_roles.is_empty(),
		"errors": [],
		"unresolved_roles": unresolved_roles,
	}


static func inspect_tree(root_node: Node) -> Dictionary:
	var local_overrides: Array[Dictionary] = []
	var unregistered_isolated_roots: Array[String] = []
	if root_node == null:
		return {
			"ok": false,
			"errors": ["diagnostics:null_root"],
			"local_overrides": local_overrides,
			"unregistered_isolated_roots": unregistered_isolated_roots,
		}
	_collect_tree_findings(root_node, local_overrides, unregistered_isolated_roots)
	return {
		"ok": local_overrides.is_empty() and unregistered_isolated_roots.is_empty(),
		"errors": [],
		"local_overrides": local_overrides,
		"unregistered_isolated_roots": unregistered_isolated_roots,
	}


static func _collect_tree_findings(
	parent_node: Node,
	local_overrides: Array[Dictionary],
	unregistered_isolated_roots: Array[String]
) -> void:
	if parent_node is Control:
		for property_record in parent_node.get_property_list():
			var property_id: String = String((property_record as Dictionary).get("name", ""))
			if _is_active_override(parent_node, property_id):
				local_overrides.append(
					{
						"node_path": _node_identifier(parent_node),
						"property": property_id,
					}
				)
	if parent_node is CanvasLayer or parent_node is SubViewport:
		for isolated_root_node in parent_node.get_children():
			if (
				isolated_root_node is Control
				and not isolated_root_node.has_meta("synesyn_visual_profile_family")
				and not isolated_root_node.is_in_group("synesyn_themed")
			):
				unregistered_isolated_roots.append(_node_identifier(isolated_root_node))
	for child_node in parent_node.get_children():
		_collect_tree_findings(child_node, local_overrides, unregistered_isolated_roots)


static func _is_active_override(control_node: Control, property_id: String) -> bool:
	var property_parts: PackedStringArray = property_id.split("/")
	if property_parts.size() != 2:
		return false
	var override_family: String = property_parts[0]
	var item_id: StringName = StringName(property_parts[1])
	match override_family:
		"theme_override_colors":
			return control_node.has_theme_color_override(item_id)
		"theme_override_constants":
			return control_node.has_theme_constant_override(item_id)
		"theme_override_font_sizes":
			return control_node.has_theme_font_size_override(item_id)
		"theme_override_fonts":
			return control_node.has_theme_font_override(item_id)
		"theme_override_icons":
			return control_node.has_theme_icon_override(item_id)
		"theme_override_styles":
			return control_node.has_theme_stylebox_override(item_id)
	return false


static func _node_identifier(target_node: Node) -> String:
	if target_node.is_inside_tree():
		return String(target_node.get_path())
	return "%s#%d" % [target_node.get_class(), target_node.get_instance_id()]
