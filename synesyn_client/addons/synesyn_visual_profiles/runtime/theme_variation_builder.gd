class_name SynesynThemeVariationBuilder
extends RefCounted

const ACTION_VARIATIONS: Dictionary = {
	"primary": "SynesynPrimaryAction",
	"secondary": "SynesynSecondaryAction",
	"quiet": "SynesynQuietAction",
	"destructive": "SynesynDestructiveAction",
}
const BADGE_VARIATIONS: Dictionary = {
	"proposed": "SynesynBadgeProposed",
	"reviewed": "SynesynBadgeReviewed",
	"committed": "SynesynBadgeCommitted",
	"rejected": "SynesynBadgeRejected",
	"deferred": "SynesynBadgeDeferred",
	"read_only": "SynesynBadgeReadOnly",
	"degraded": "SynesynBadgeDegraded",
}
const PANEL_VARIATIONS: Dictionary = {
	"surface": "SynesynSurfacePanel",
	"raised": "SynesynRaisedPanel",
	"dialog": "SynesynDialogPanel",
	"drawer": "SynesynDrawerPanel",
	"status": "SynesynStatusPanel",
}
const NAVIGATION_VARIATIONS: Dictionary = {
	"default": "SynesynNavigation",
	"selected": "SynesynNavigationSelected",
}


static func decorate_profile(
	profile_definition: SynesynVisualProfileDefinition
) -> void:
	if profile_definition == null:
		return
	for profile_mode in ["light", "dark"]:
		for surface_id in ["base", "utility", "console", "tools"]:
			var resolved_theme: Theme = profile_definition.get_control_theme(
				surface_id,
				profile_mode
			)
			_decorate_theme(resolved_theme, profile_definition, profile_mode)


static func action_variation(semantic_role: String) -> StringName:
	return StringName(ACTION_VARIATIONS.get(semantic_role, ACTION_VARIATIONS["secondary"]))


static func badge_variation(semantic_role: String) -> StringName:
	return StringName(BADGE_VARIATIONS.get(semantic_role, BADGE_VARIATIONS["read_only"]))


static func badge_label_variation(semantic_role: String) -> StringName:
	return StringName("%sLabel" % badge_variation(semantic_role))


static func panel_variation(semantic_role: String) -> StringName:
	return StringName(PANEL_VARIATIONS.get(semantic_role, PANEL_VARIATIONS["surface"]))


static func navigation_variation(is_selected: bool) -> StringName:
	return StringName(
		NAVIGATION_VARIATIONS["selected"]
		if is_selected
		else NAVIGATION_VARIATIONS["default"]
	)


static func _decorate_theme(
	resolved_theme: Theme,
	profile_definition: SynesynVisualProfileDefinition,
	profile_mode: String
) -> void:
	if resolved_theme == null:
		return
	var decoration_key: String = "synesyn_variations_%s" % profile_mode
	if bool(resolved_theme.get_meta(decoration_key, false)):
		return
	var semantic_colors: Dictionary = profile_definition.get_semantic_colors(profile_mode)
	var radius_value: int = int(profile_definition.radius_roles.get("control", 10))
	var accent_color: Color = _color(semantic_colors, "accent", Color("1e73e8"))
	var muted_color: Color = _color(semantic_colors, "muted", Color("93a1b5"))
	var raised_color: Color = _color(semantic_colors, "raised", Color("1a2433"))
	var surface_color: Color = _color(semantic_colors, "surface", Color("121a25"))
	var base_color: Color = _color(semantic_colors, "base", Color("0a0e14"))
	# Dark mode: keep accent for selected/primary fills only. Outline chrome uses
	# muted borders so the shell does not read as a bright blue wireframe.
	var is_dark_profile: bool = profile_mode == "dark" or profile_mode == "projector"
	# No idle outline stroke — soft AA borders wash out fills in both modes.
	var outline_border: Color = Color.TRANSPARENT
	var selected_fill: Color = accent_color
	if is_dark_profile:
		selected_fill = accent_color.darkened(0.12)
	_add_action_variation(
		resolved_theme,
		action_variation("primary"),
		selected_fill,
		radius_value,
		false
	)
	_add_action_variation(
		resolved_theme,
		action_variation("secondary"),
		raised_color,
		radius_value,
		false,
		outline_border
	)
	_add_action_variation(
		resolved_theme,
		action_variation("quiet"),
		surface_color,
		radius_value,
		false
	)
	_add_action_variation(
		resolved_theme,
		action_variation("destructive"),
		_color(semantic_colors, "danger", Color("ff6b6b")),
		radius_value,
		true
	)
	for semantic_role in BADGE_VARIATIONS:
		_add_badge_variation(
			resolved_theme,
			badge_variation(semantic_role),
			_color(semantic_colors, semantic_role, Color("93a1b5")),
			radius_value
		)
	_add_panel_variation(
		resolved_theme,
		panel_variation("surface"),
		surface_color,
		int(profile_definition.radius_roles.get("card", 10))
	)
	_add_panel_variation(
		resolved_theme,
		panel_variation("raised"),
		raised_color,
		int(profile_definition.radius_roles.get("card", 10))
	)
	_add_panel_variation(
		resolved_theme,
		panel_variation("dialog"),
		raised_color,
		int(profile_definition.radius_roles.get("dialog", 14)),
		outline_border
	)
	_add_panel_variation(
		resolved_theme,
		panel_variation("drawer"),
		surface_color,
		0,
		Color.TRANSPARENT
	)
	_add_panel_variation(
		resolved_theme,
		panel_variation("status"),
		base_color,
		0
	)
	_add_action_variation(
		resolved_theme,
		navigation_variation(false),
		raised_color,
		radius_value,
		false,
		outline_border
	)
	_add_action_variation(
		resolved_theme,
		navigation_variation(true),
		selected_fill,
		radius_value,
		false
	)
	_add_field_variation(
		resolved_theme,
		surface_color,
		selected_fill if not is_dark_profile else muted_color,
		muted_color,
		radius_value
	)
	_add_muted_label_variation(
		resolved_theme,
		_color(semantic_colors, "muted", Color("93a1b5"))
	)
	resolved_theme.set_meta(decoration_key, true)


static func _add_action_variation(
	resolved_theme: Theme,
	variation_id: StringName,
	background_color: Color,
	radius_value: int,
	is_danger: bool,
	border_color: Color = Color.TRANSPARENT
) -> void:
	resolved_theme.set_type_variation(variation_id, &"Button")
	resolved_theme.set_stylebox(
		&"normal",
		variation_id,
		_make_stylebox(background_color, radius_value, border_color)
	)
	resolved_theme.set_stylebox(
		&"hover",
		variation_id,
		_make_stylebox(background_color.lightened(0.08), radius_value, border_color)
	)
	resolved_theme.set_stylebox(
		&"pressed",
		variation_id,
		_make_stylebox(background_color.darkened(0.1), radius_value, border_color)
	)
	resolved_theme.set_stylebox(
		&"focus",
		variation_id,
		_make_stylebox(
			background_color,
			radius_value,
			_contrast_color(background_color)
		)
	)
	var disabled_bg: Color = background_color
	disabled_bg.a = minf(disabled_bg.a, 1.0) * 0.45
	resolved_theme.set_stylebox(
		&"disabled",
		variation_id,
		_make_stylebox(disabled_bg, radius_value, border_color)
	)
	var font_color: Color = _contrast_color(background_color)
	if is_danger:
		font_color = Color.WHITE
	resolved_theme.set_color(&"font_color", variation_id, font_color)
	resolved_theme.set_color(&"font_hover_color", variation_id, font_color)
	resolved_theme.set_color(&"font_pressed_color", variation_id, font_color)
	var disabled_font: Color = font_color
	disabled_font.a = 0.45
	resolved_theme.set_color(&"font_disabled_color", variation_id, disabled_font)


static func _add_badge_variation(
	resolved_theme: Theme,
	variation_id: StringName,
	background_color: Color,
	radius_value: int
) -> void:
	resolved_theme.set_type_variation(variation_id, &"PanelContainer")
	# Compact margins so chips (e.g. 24px facilitator avatar) stay usable.
	resolved_theme.set_stylebox(
		&"panel",
		variation_id,
		_make_stylebox(background_color, radius_value, Color.TRANSPARENT, 4.0, 2.0)
	)
	var label_variation_id: StringName = StringName("%sLabel" % variation_id)
	resolved_theme.set_type_variation(label_variation_id, &"Label")
	resolved_theme.set_color(&"font_color", label_variation_id, _contrast_color(background_color))


static func _add_panel_variation(
	resolved_theme: Theme,
	variation_id: StringName,
	background_color: Color,
	radius_value: int,
	border_color: Color = Color.TRANSPARENT
) -> void:
	resolved_theme.set_type_variation(variation_id, &"PanelContainer")
	# Panels need lighter padding than action buttons (14/8) so headers/cards
	# do not grow tall enough to trip layout/fit edge cases.
	resolved_theme.set_stylebox(
		&"panel",
		variation_id,
		_make_stylebox(background_color, radius_value, border_color, 8.0, 6.0)
	)


static func _add_muted_label_variation(
	resolved_theme: Theme,
	muted_color: Color
) -> void:
	var variation_id: StringName = &"LabelMuted"
	resolved_theme.set_type_variation(variation_id, &"Label")
	resolved_theme.set_color(&"font_color", variation_id, muted_color)
	resolved_theme.set_font_size(&"font_size", variation_id, 12)


static func _add_field_variation(
	resolved_theme: Theme,
	background_color: Color,
	accent_color: Color,
	muted_color: Color,
	radius_value: int
) -> void:
	var variation_id: StringName = &"SynesynField"
	resolved_theme.set_type_variation(variation_id, &"LineEdit")
	resolved_theme.set_stylebox(
		&"normal",
		variation_id,
		_make_stylebox(background_color, radius_value, muted_color)
	)
	resolved_theme.set_stylebox(
		&"focus",
		variation_id,
		_make_stylebox(background_color, radius_value, accent_color)
	)
	resolved_theme.set_color(&"caret_color", variation_id, accent_color)
	resolved_theme.set_color(&"font_placeholder_color", variation_id, muted_color)


static func _make_stylebox(
	background_color: Color,
	radius_value: int,
	border_color: Color = Color.TRANSPARENT,
	margin_x: float = 14.0,
	margin_y: float = 8.0
) -> StyleBoxFlat:
	var stylebox: StyleBoxFlat = StyleBoxFlat.new()
	stylebox.bg_color = background_color
	stylebox.corner_radius_top_left = radius_value
	stylebox.corner_radius_top_right = radius_value
	stylebox.corner_radius_bottom_left = radius_value
	stylebox.corner_radius_bottom_right = radius_value
	stylebox.content_margin_left = margin_x
	stylebox.content_margin_right = margin_x
	stylebox.content_margin_top = margin_y
	stylebox.content_margin_bottom = margin_y
	if border_color.a > 0.0:
		stylebox.border_color = border_color
		stylebox.border_width_left = 1
		stylebox.border_width_top = 1
		stylebox.border_width_right = 1
		stylebox.border_width_bottom = 1
	return stylebox


static func _contrast_color(background_color: Color) -> Color:
	return Color("10141d") if background_color.get_luminance() > 0.52 else Color.WHITE


static func _color(
	semantic_colors: Dictionary,
	semantic_role: String,
	fallback_color: Color
) -> Color:
	var color_value: Variant = semantic_colors.get(semantic_role, fallback_color)
	if color_value is Color:
		return color_value
	return fallback_color
