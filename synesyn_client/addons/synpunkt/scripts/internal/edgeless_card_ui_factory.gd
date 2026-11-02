extends RefCounted
class_name EdgelessCardUiFactory

static func make_frame_card_control(frame_card_size_px: Vector2, presentation_style: bool, is_dark_mode: bool = true) -> Control:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.focus_mode = Control.FOCUS_NONE
	card.clip_contents = true
	card.custom_minimum_size = frame_card_size_px
	card.size = frame_card_size_px

	var sb := StyleBoxFlat.new()
	if presentation_style:
		sb.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	elif is_dark_mode:
		sb.bg_color = Color(0.10, 0.14, 0.22, 0.94)
	else:
		sb.bg_color = Color(0.97, 0.97, 1.0, 0.94)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	if presentation_style:
		sb.border_color = Color(0.15, 0.15, 0.18, 0.95)
	elif is_dark_mode:
		sb.border_color = Color(0.25, 0.45, 0.95, 0.75)
	else:
		sb.border_color = Color(0.35, 0.45, 0.75, 0.55)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", sb)
	card.set_meta("frame_card_stylebox", sb)

	var margin_node := MarginContainer.new()
	margin_node.name = "Margin"
	margin_node.add_theme_constant_override("margin_left", 10)
	margin_node.add_theme_constant_override("margin_right", 10)
	margin_node.add_theme_constant_override("margin_top", 10)
	margin_node.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin_node)

	var vbox := VBoxContainer.new()
	vbox.name = "Content"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	margin_node.add_child(vbox)
	return card

static func make_frame_id_row(frame_id: String) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.82, 0.82, 0.86, 1.0)
	row.add_theme_stylebox_override("panel", sb)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	row.add_child(m)

	var lbl := Label.new()
	lbl.text = frame_id
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.clip_text = true
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 1.0))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(lbl)
	return row

static func make_text_row(text_value: String, font_size: int, font_col: Color, presentation_style: bool) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 1.0) if presentation_style else Color(0.88, 0.88, 0.92, 0.22)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.82, 0.82, 0.86, 1.0) if presentation_style else Color(0.30, 0.30, 0.34, 0.55)
	row.add_theme_stylebox_override("panel", sb)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	row.add_child(m)

	var lbl := Label.new()
	lbl.text = text_value
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", int(font_size))
	lbl.add_theme_color_override("font_color", font_col)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(lbl)
	return row
