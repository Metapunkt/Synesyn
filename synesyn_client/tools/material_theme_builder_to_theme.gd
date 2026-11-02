@tool
extends EditorScript

# One-off converter: Material Theme Builder (Material 3) JSON -> Godot Theme (.tres)
#
# Run (from project root):
#   godot4 --headless --path . --script res://tools/material_theme_builder_to_theme.gd -- \
#     --input res://path/to/material-theme.json \
#     --output res://ScenSyn/themes/MaterialTheme_Light.tres \
#     --scheme light \
#     --corner_radius 10 \
#     --font res://ScenSyn/themes/fonts/noto/NotoSansUI_Regular.ttf
#
# Notes:
# - Material Theme Builder JSON shape varies by export target/version; this script tries several common layouts.
# - This maps the core M3 "scheme" tokens (primary/onPrimary/surface/onSurface/outline/etc.) into a practical
#   set of Godot Control theme items (Button/Panel/Label/LineEdit/PopupMenu/OptionButton/TabContainer/Tree).

const _KNOWN_M3_KEYS: PackedStringArray = [
	"primary",
	"onPrimary",
	"primaryContainer",
	"onPrimaryContainer",
	"secondary",
	"onSecondary",
	"secondaryContainer",
	"onSecondaryContainer",
	"tertiary",
	"onTertiary",
	"tertiaryContainer",
	"onTertiaryContainer",
	"error",
	"onError",
	"errorContainer",
	"onErrorContainer",
	"background",
	"onBackground",
	"surface",
	"onSurface",
	"surfaceVariant",
	"onSurfaceVariant",
	"outline",
	"outlineVariant",
	"shadow",
	"scrim",
	"inverseSurface",
	"inverseOnSurface",
	"inversePrimary",
	"surfaceTint",
	# Newer exports sometimes include these:
	"surfaceContainerLowest",
	"surfaceContainerLow",
	"surfaceContainer",
	"surfaceContainerHigh",
	"surfaceContainerHighest",
]

func _run() -> void:
	var args := _parse_args(OS.get_cmdline_args())
	var input_path: String = args.get("input", "")
	var output_path: String = args.get("output", "")
	var scheme: String = String(args.get("scheme", "light")).to_lower()
	var corner_radius: int = int(args.get("corner_radius", 10))
	var font_path: String = args.get("font", "")

	if input_path.is_empty() or output_path.is_empty():
		push_error("Missing args. Required: --input <json> --output <tres>. Optional: --scheme light|dark --corner_radius 10 --font <ttf/otf>")
		return

	var json_text := _read_text_any_path(input_path)
	if json_text.is_empty():
		push_error("Failed to read JSON from: %s" % input_path)
		return

	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON root is not an object/dictionary: %s" % input_path)
		return

	var scheme_dict := _find_scheme_dict(parsed, scheme)
	if scheme_dict.is_empty():
		push_error("Couldn't find a '%s' scheme in JSON. Known keys tried: schemes.{light|dark}, sys.color.{light|dark}, etc." % scheme)
		return

	var tokens := _extract_color_tokens(scheme_dict)
	if tokens.is_empty():
		push_error("Found scheme object, but couldn't extract any color tokens (hex strings) from it.")
		return

	var theme := _build_theme_from_tokens(tokens, corner_radius, font_path)
	var err := ResourceSaver.save(theme, output_path)
	if err != OK:
		push_error("Failed to save Theme to %s (err=%s)" % [output_path, err])
		return

	print("Saved Theme: %s" % output_path)


func _parse_args(argv: PackedStringArray) -> Dictionary:
	# Godot argv includes engine flags; we only care about args after "--" (common convention),
	# but also accept args without it.
	var args := {}
	var start_idx := 0
	for i in range(argv.size()):
		if argv[i] == "--":
			start_idx = i + 1
			break

	var i := start_idx
	while i < argv.size():
		var a := argv[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			var value := "true"
			if i + 1 < argv.size() and not String(argv[i + 1]).begins_with("--"):
				value = argv[i + 1]
				i += 1
			args[key] = value
		i += 1
	return args


func _read_text_any_path(p: String) -> String:
	var path := p
	if p.begins_with("res://"):
		path = ProjectSettings.globalize_path(p)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	return txt


func _find_scheme_dict(root: Dictionary, scheme: String) -> Dictionary:
	# Material Theme Builder exports differ. Common patterns:
	# - root.schemes.light (or root.schemes.dark)
	# - root.schemes is an array of objects with name/type
	# - root.sys.color.light / root.sys.color.dark
	# - root.colorSchemes.light (less common)
	var candidates: Array = [
		["schemes", scheme],
		["sys", "color", scheme],
		["colorSchemes", scheme],
		["theme", "schemes", scheme],
		["material", "schemes", scheme],
	]
	for path in candidates:
		var d: Variant = _dig_dict(root, path)
		if typeof(d) == TYPE_DICTIONARY and not d.is_empty():
			return d

	# If schemes is an array, find by "name"/"type"/"mode".
	var schemes_val = root.get("schemes")
	if typeof(schemes_val) == TYPE_ARRAY:
		for item in schemes_val:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var n := String(item.get("name", item.get("mode", item.get("type", "")))).to_lower()
			if n == scheme:
				# Sometimes the actual scheme is under item.colors or item.scheme.
				var inner = item.get("colors", item.get("scheme", item))
				if typeof(inner) == TYPE_DICTIONARY:
					return inner

	# Last resort: if root looks like it's already a scheme (contains primary/surface keys).
	for k in _KNOWN_M3_KEYS:
		if root.has(k):
			return root
	return {}


func _dig_dict(root: Dictionary, keys: Array) -> Variant:
	var cur: Variant = root
	for k in keys:
		if typeof(cur) != TYPE_DICTIONARY:
			return null
		cur = cur.get(k)
	return cur


func _extract_color_tokens(scheme_dict: Dictionary) -> Dictionary:
	# Return a { token_name: Color } map.
	var out := {}
	for k in _KNOWN_M3_KEYS:
		if not scheme_dict.has(k):
			continue
		var c: Variant = _color_from_unknown(scheme_dict[k])
		if c != null:
			out[k] = c

	# Some exports nest under "colors" / "color".
	for alt_key in ["colors", "color", "sys", "md", "m3"]:
		if not scheme_dict.has(alt_key):
			continue
		var inner: Variant = scheme_dict[alt_key]
		if typeof(inner) != TYPE_DICTIONARY:
			continue
		for k in _KNOWN_M3_KEYS:
			if not inner.has(k) or out.has(k):
				continue
			var c2: Variant = _color_from_unknown(inner[k])
			if c2 != null:
				out[k] = c2

	return out


func _color_from_unknown(v: Variant) -> Variant:
	# Accepts "#RRGGBB", "#AARRGGBB", or objects like { "value": "#..." }.
	if typeof(v) == TYPE_STRING:
		return _color_from_hex(String(v))
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		for key in ["value", "$value", "hex", "color"]:
			if d.has(key) and typeof(d[key]) == TYPE_STRING:
				return _color_from_hex(String(d[key]))
	return null


func _color_from_hex(s: String) -> Color:
	var t := s.strip_edges()
	if t.begins_with("#"):
		t = t.substr(1)
	if t.length() == 6:
		var r := int("0x" + t.substr(0, 2)) / 255.0
		var g := int("0x" + t.substr(2, 2)) / 255.0
		var b := int("0x" + t.substr(4, 2)) / 255.0
		return Color(r, g, b, 1.0)
	if t.length() == 8:
		# Assume AARRGGBB (common for token exports).
		var a := int("0x" + t.substr(0, 2)) / 255.0
		var r2 := int("0x" + t.substr(2, 2)) / 255.0
		var g2 := int("0x" + t.substr(4, 2)) / 255.0
		var b2 := int("0x" + t.substr(6, 2)) / 255.0
		return Color(r2, g2, b2, a)
	# Fallback: let Godot try parsing (supports named colors, etc.)
	return Color.html(s)


func _with_alpha(c: Color, a: float) -> Color:
	var cc := c
	cc.a = clampf(a, 0.0, 1.0)
	return cc


func _mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))


func _stylebox_flat(bg: Color, border: Color, border_w: int, radius: int, content_margin: Vector4 = Vector4(10, 6, 10, 6)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border_w > 0:
		sb.border_width_left = border_w
		sb.border_width_top = border_w
		sb.border_width_right = border_w
		sb.border_width_bottom = border_w
		sb.border_color = border
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = content_margin.x
	sb.content_margin_top = content_margin.y
	sb.content_margin_right = content_margin.z
	sb.content_margin_bottom = content_margin.w
	return sb


func _load_font_or_null(res_path: String) -> Font:
	if res_path.is_empty():
		return null
	var p := res_path
	if not p.begins_with("res://"):
		# Allow absolute paths, but prefer res://.
		# FontFile can load from absolute if accessible; if not, user should import into project.
		pass
	var f = load(p)
	if f is Font:
		return f
	if f is FontFile:
		return f
	return null


func _build_theme_from_tokens(tokens: Dictionary, corner_radius: int, font_path: String) -> Theme:
	# Required-ish tokens with sensible fallbacks.
	var primary: Color = tokens.get("primary", Color(0.26, 0.52, 0.96))
	var on_primary: Color = tokens.get("onPrimary", Color(1, 1, 1))
	var surface: Color = tokens.get("surface", tokens.get("background", Color(0.1, 0.1, 0.1)))
	var on_surface: Color = tokens.get("onSurface", tokens.get("onBackground", Color(1, 1, 1)))
	var surface_variant: Color = tokens.get("surfaceVariant", _mix(surface, on_surface, 0.12))
	var on_surface_variant: Color = tokens.get("onSurfaceVariant", _mix(on_surface, surface, 0.35))
	var outline: Color = tokens.get("outline", _with_alpha(on_surface, 0.30))
	var outline_variant: Color = tokens.get("outlineVariant", _with_alpha(on_surface, 0.18))
	var error: Color = tokens.get("error", Color(0.9, 0.2, 0.2))
	var on_error: Color = tokens.get("onError", Color(1, 1, 1))

	var theme := Theme.new()

	var font := _load_font_or_null(font_path)
	if font != null:
		theme.default_font = font

	# --- Label / RichTextLabel ---
	theme.set_color("font_color", "Label", on_surface)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0))
	theme.set_color("default_color", "RichTextLabel", on_surface)

	# --- Panel (background surface) ---
	var panel_sb := _stylebox_flat(surface, outline_variant, 1, corner_radius, Vector4(12, 12, 12, 12))
	theme.set_stylebox("panel", "Panel", panel_sb)

	# --- Button (filled primary by default) ---
	var btn_normal := _stylebox_flat(primary, outline_variant, 0, corner_radius, Vector4(14, 8, 14, 8))
	var btn_hover := _stylebox_flat(_mix(primary, on_primary, 0.08), outline_variant, 0, corner_radius, Vector4(14, 8, 14, 8))
	var btn_pressed := _stylebox_flat(_mix(primary, Color(0, 0, 0, 1), 0.12), outline_variant, 0, corner_radius, Vector4(14, 8, 14, 8))
	var btn_disabled := _stylebox_flat(_with_alpha(surface_variant, 0.75), outline_variant, 0, corner_radius, Vector4(14, 8, 14, 8))
	var btn_focus := _stylebox_flat(surface, primary, 2, corner_radius, Vector4(14, 8, 14, 8))

	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_stylebox("focus", "Button", btn_focus)

	theme.set_color("font_color", "Button", on_primary)
	theme.set_color("font_hover_color", "Button", on_primary)
	theme.set_color("font_pressed_color", "Button", on_primary)
	theme.set_color("font_disabled_color", "Button", _with_alpha(on_surface, 0.35))
	theme.set_color("font_focus_color", "Button", on_primary)

	# --- OptionButton uses many of the same keys as Button ---
	theme.set_stylebox("normal", "OptionButton", btn_normal)
	theme.set_stylebox("hover", "OptionButton", btn_hover)
	theme.set_stylebox("pressed", "OptionButton", btn_pressed)
	theme.set_stylebox("disabled", "OptionButton", btn_disabled)
	theme.set_stylebox("focus", "OptionButton", btn_focus)
	theme.set_color("font_color", "OptionButton", on_primary)
	theme.set_color("font_hover_color", "OptionButton", on_primary)
	theme.set_color("font_pressed_color", "OptionButton", on_primary)
	theme.set_color("font_disabled_color", "OptionButton", _with_alpha(on_surface, 0.35))

	# --- LineEdit ---
	var le_normal := _stylebox_flat(surface_variant, outline_variant, 1, corner_radius, Vector4(10, 8, 10, 8))
	var le_focus := _stylebox_flat(surface_variant, primary, 2, corner_radius, Vector4(10, 8, 10, 8))
	var le_readonly := _stylebox_flat(_mix(surface_variant, surface, 0.25), outline_variant, 1, corner_radius, Vector4(10, 8, 10, 8))
	theme.set_stylebox("normal", "LineEdit", le_normal)
	theme.set_stylebox("focus", "LineEdit", le_focus)
	theme.set_stylebox("read_only", "LineEdit", le_readonly)
	theme.set_color("font_color", "LineEdit", on_surface)
	theme.set_color("font_color_selected", "LineEdit", on_primary)
	theme.set_color("font_color_uneditable", "LineEdit", _with_alpha(on_surface, 0.55))
	theme.set_color("font_placeholder_color", "LineEdit", _with_alpha(on_surface_variant, 0.75))
	theme.set_color("cursor_color", "LineEdit", primary)
	theme.set_color("selection_color", "LineEdit", _with_alpha(primary, 0.35))

	# --- TextEdit (basic mapping; you may want a dedicated code theme separately) ---
	theme.set_stylebox("normal", "TextEdit", _stylebox_flat(_with_alpha(surface, 0.0), outline_variant, 1, corner_radius, Vector4(10, 10, 10, 10)))
	theme.set_stylebox("focus", "TextEdit", _stylebox_flat(_with_alpha(surface, 0.0), primary, 2, corner_radius, Vector4(10, 10, 10, 10)))
	theme.set_stylebox("read_only", "TextEdit", _stylebox_flat(_with_alpha(surface, 0.0), outline_variant, 1, corner_radius, Vector4(10, 10, 10, 10)))
	theme.set_color("font_color", "TextEdit", on_surface)
	theme.set_color("font_color_readonly", "TextEdit", _with_alpha(on_surface, 0.6))
	theme.set_color("selection_color", "TextEdit", _with_alpha(primary, 0.35))
	theme.set_color("caret_color", "TextEdit", primary)

	# --- PopupMenu ---
	theme.set_stylebox("panel", "PopupMenu", _stylebox_flat(surface, outline_variant, 1, corner_radius, Vector4(8, 8, 8, 8)))
	theme.set_stylebox("hover", "PopupMenu", _stylebox_flat(surface_variant, outline_variant, 0, 0, Vector4(8, 4, 8, 4)))
	theme.set_color("font_color", "PopupMenu", on_surface)
	theme.set_color("font_color_hover", "PopupMenu", on_surface)
	theme.set_color("font_color_disabled", "PopupMenu", _with_alpha(on_surface, 0.35))
	theme.set_color("font_color_accel", "PopupMenu", _with_alpha(on_surface_variant, 0.9))
	theme.set_color("font_color_separator", "PopupMenu", _with_alpha(on_surface_variant, 0.9))
	theme.set_constant("hseparation", "PopupMenu", 8)
	theme.set_constant("vseparation", "PopupMenu", 6)

	# --- TabContainer ---
	theme.set_stylebox("panel", "TabContainer", panel_sb)
	theme.set_stylebox("tab_fg", "TabContainer", _stylebox_flat(surface_variant, outline_variant, 1, corner_radius, Vector4(10, 6, 10, 6)))
	theme.set_stylebox("tab_bg", "TabContainer", _stylebox_flat(surface, outline_variant, 1, corner_radius, Vector4(10, 6, 10, 6)))
	theme.set_color("font_color_fg", "TabContainer", on_surface)
	theme.set_color("font_color_bg", "TabContainer", _with_alpha(on_surface_variant, 0.9))
	theme.set_color("font_color_disabled", "TabContainer", _with_alpha(on_surface, 0.35))

	# --- Tree (selection highlight) ---
	theme.set_stylebox("bg", "Tree", panel_sb)
	theme.set_stylebox("selected", "Tree", _stylebox_flat(_with_alpha(primary, 0.30), Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0)))
	theme.set_stylebox("selected_focus", "Tree", _stylebox_flat(_with_alpha(primary, 0.35), Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0)))
	theme.set_color("font_color", "Tree", on_surface)
	theme.set_color("font_color_selected", "Tree", on_surface)
	theme.set_color("guide_color", "Tree", _with_alpha(outline_variant, 0.5))

	# --- Error-ish colors for dialogs / warnings (basic) ---
	theme.set_color("error_color", "Editor", error) # harmless if unused
	theme.set_color("warning_color", "Editor", _mix(error, Color(1, 1, 0), 0.35))
	theme.set_color("success_color", "Editor", _mix(primary, Color(0, 1, 0), 0.25))
	theme.set_color("accent_color", "Editor", primary)
	theme.set_color("base_color", "Editor", surface)
	theme.set_color("font_color", "Editor", on_surface)
	theme.set_color("mono_color", "Editor", on_surface_variant)

	return theme


