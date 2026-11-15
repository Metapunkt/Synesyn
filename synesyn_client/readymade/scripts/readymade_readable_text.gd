extends RefCounted
class_name ReadyMadeReadableText
## Contrast helpers for read-only report/preview TextEdit controls on the light UI.


const FONT_COLOR := Color(0.1, 0.1, 0.1, 1.0)
const BG_COLOR := Color(0.98, 0.98, 0.98, 1.0)
const BORDER_COLOR := Color(0.7, 0.7, 0.7, 1.0)


static func make_report_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	return style


static func apply_report_text_edit(edit: TextEdit) -> void:
	"""Dark text on a light panel — works for editable=false (font_readonly_color)."""
	if edit == null:
		return
	edit.add_theme_color_override("font_color", FONT_COLOR)
	edit.add_theme_color_override("font_readonly_color", FONT_COLOR)
	edit.add_theme_color_override("font_placeholder_color", Color(0.35, 0.35, 0.35, 1.0))
	var style: StyleBoxFlat = make_report_stylebox()
	edit.add_theme_stylebox_override("normal", style)
	edit.add_theme_stylebox_override("focus", style)
	edit.add_theme_stylebox_override("read_only", style)


static func relative_luminance(color: Color) -> float:
	# WCAG relative luminance (sRGB).
	var channels: Array[float] = [color.r, color.g, color.b]
	for i in range(channels.size()):
		var channel: float = channels[i]
		if channel <= 0.03928:
			channels[i] = channel / 12.92
		else:
			channels[i] = pow((channel + 0.055) / 1.055, 2.4)
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


static func contrast_ratio(foreground: Color, background: Color) -> float:
	var lum_a: float = relative_luminance(foreground)
	var lum_b: float = relative_luminance(background)
	var lighter: float = maxf(lum_a, lum_b)
	var darker: float = minf(lum_a, lum_b)
	return (lighter + 0.05) / (darker + 0.05)


static func effective_report_font_color(edit: TextEdit) -> Color:
	if edit == null:
		return Color.BLACK
	if edit.has_theme_color_override("font_readonly_color"):
		return edit.get_theme_color("font_readonly_color")
	if not edit.editable:
		return edit.get_theme_color("font_readonly_color")
	return edit.get_theme_color("font_color")


static func effective_report_bg_color(edit: TextEdit) -> Color:
	if edit == null:
		return Color.WHITE
	var style_name: String = "read_only" if not edit.editable else "normal"
	if edit.has_theme_stylebox_override(style_name):
		var overridden: StyleBox = edit.get_theme_stylebox(style_name)
		if overridden is StyleBoxFlat:
			return (overridden as StyleBoxFlat).bg_color
	if edit.has_theme_stylebox_override("normal"):
		var normal_style: StyleBox = edit.get_theme_stylebox("normal")
		if normal_style is StyleBoxFlat:
			return (normal_style as StyleBoxFlat).bg_color
	var themed: StyleBox = edit.get_theme_stylebox(style_name)
	if themed is StyleBoxFlat:
		return (themed as StyleBoxFlat).bg_color
	return BG_COLOR
