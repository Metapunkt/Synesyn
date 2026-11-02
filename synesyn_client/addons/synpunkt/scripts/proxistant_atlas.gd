@tool
extends Control
class_name SynpunktProxistantAtlas

## [EXPERIMENTAL]
##
## This panel is the first SynPunkt performance surface for canonical
## STFX Store records. Store closures can bind symbolic constraints
## into the same field/collapse/twin operators used by the standalone explorer.
##
## It still remains experimental: `primary_seed` values from app closures do not
## always map directly onto a Hub lexicon family, so the Atlas falls back to the
## current/default family while preserving the record binding in the status text.

signal field_loaded(payload: Dictionary)
signal row_collapsed(provenance: Dictionary)

const FALLBACK_FAMILIES: Array[String] = ["primary", "transitional", "rhythmic", "alternating"]
const MIN_DEPTH: int = 0
const MAX_DEPTH: int = 4

var _hub: HubSubstrateClient
var _lexicon: String = "ifa_odu"
var _family: String = "primary"
var _depth: int = 3
var _busy: bool = false
var _available_families: Array[String] = []
var _bound_store_record_id: String = ""
var _bound_store_record_kind: String = ""
var _bound_symbolic_seed: String = ""

var _last_matrix: Array = []
var _selected_row: int = -1
var _twin_row: int = -1

var _atlas_view_node: TextureRect
var _family_option_node: OptionButton
var _depth_label_node: Label
var _status_label_node: RichTextLabel
var _zoom_in_button_node: Button
var _zoom_out_button_node: Button
var _decenter_button_node: Button
var _reload_button_node: Button


func set_hub(hub: HubSubstrateClient) -> void:
	_hub = hub


func apply_store_record(record: Dictionary, record_kind: String = "Store record") -> void:
	var constraints_any: Variant = record.get("symbolic_constraints", {})
	var constraints: Dictionary = constraints_any if typeof(constraints_any) == TYPE_DICTIONARY else {}
	var retrieval_plan_any: Variant = record.get("retrieval_plan", {})
	var retrieval_plan: Dictionary = retrieval_plan_any if typeof(retrieval_plan_any) == TYPE_DICTIONARY else {}
	var scope_any: Variant = record.get("scope", {})
	var scope: Dictionary = scope_any if typeof(scope_any) == TYPE_DICTIONARY else {}
	var family_hint: String = str(constraints.get("seed_family", "")).strip_edges()
	if family_hint.is_empty():
		family_hint = str(constraints.get("primary_seed", "")).strip_edges()
	if family_hint.is_empty():
		family_hint = str(retrieval_plan.get("symbolic_seed", "")).strip_edges()
	if family_hint.is_empty():
		family_hint = str(scope.get("seed_family", "")).strip_edges()
	var lexicon_hint: String = str(constraints.get("lexicon", "")).strip_edges()
	if not lexicon_hint.is_empty():
		_lexicon = lexicon_hint
	var depth_hint: int = _depth
	if constraints.has("expansion_depth"):
		depth_hint = int(constraints.get("expansion_depth", _depth))
	elif retrieval_plan.has("expansion_depth"):
		depth_hint = int(retrieval_plan.get("expansion_depth", _depth))
	_depth = clampi(depth_hint, MIN_DEPTH, MAX_DEPTH)
	_bound_store_record_id = _record_id(record)
	_bound_store_record_kind = record_kind
	_bound_symbolic_seed = family_hint
	await _populate_families()
	if not family_hint.is_empty() and _available_families.has(family_hint):
		_family = family_hint
		_select_family_option(_family)
	await _refresh_field()


func _ready() -> void:
	_build_ui()
	if _hub == null:
		_hub = HubSubstrateClient.new()
		add_child(_hub)
		if _hub.has_method("configure_from_runtime_config"):
			_hub.configure_from_runtime_config()
	await _populate_families()
	await _refresh_field()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var root_node := VBoxContainer.new()
	root_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_node.add_theme_constant_override("separation", 6)
	add_child(root_node)

	var controls_node := HBoxContainer.new()
	controls_node.add_theme_constant_override("separation", 8)
	root_node.add_child(controls_node)

	var title_node := Label.new()
	title_node.text = "Proxistant Atlas"
	controls_node.add_child(title_node)

	_family_option_node = OptionButton.new()
	_family_option_node.item_selected.connect(_on_family_selected)
	controls_node.add_child(_family_option_node)

	_zoom_out_button_node = Button.new()
	_zoom_out_button_node.text = "Zoom out (−depth)"
	_zoom_out_button_node.pressed.connect(_on_zoom_out)
	controls_node.add_child(_zoom_out_button_node)

	_zoom_in_button_node = Button.new()
	_zoom_in_button_node.text = "Zoom in (+depth)"
	_zoom_in_button_node.pressed.connect(_on_zoom_in)
	controls_node.add_child(_zoom_in_button_node)

	_decenter_button_node = Button.new()
	_decenter_button_node.text = "Decenter (twin)"
	_decenter_button_node.pressed.connect(_on_decenter)
	controls_node.add_child(_decenter_button_node)

	_reload_button_node = Button.new()
	_reload_button_node.text = "Reload"
	_reload_button_node.pressed.connect(_on_reload)
	controls_node.add_child(_reload_button_node)

	_depth_label_node = Label.new()
	_depth_label_node.text = "depth %d" % _depth
	controls_node.add_child(_depth_label_node)

	_atlas_view_node = TextureRect.new()
	_atlas_view_node.custom_minimum_size = Vector2(384, 384)
	_atlas_view_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_atlas_view_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_atlas_view_node.stretch_mode = TextureRect.STRETCH_SCALE
	_atlas_view_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_atlas_view_node.mouse_filter = Control.MOUSE_FILTER_STOP
	_atlas_view_node.gui_input.connect(_on_view_gui_input)
	root_node.add_child(_atlas_view_node)

	_status_label_node = RichTextLabel.new()
	_status_label_node.fit_content = true
	_status_label_node.custom_minimum_size = Vector2(0, 84)
	_status_label_node.bbcode_enabled = true
	_status_label_node.text = "Initialising…"
	root_node.add_child(_status_label_node)

	_render_placeholder()


func _populate_families() -> void:
	var families: Array[String] = FALLBACK_FAMILIES.duplicate()
	if _hub != null and _hub.has_method("closure_lexicons"):
		var res: Dictionary = await _hub.closure_lexicons()
		if bool(res.get("ok", false)):
			var lexicons: Array = res.get("lexicons", [])
			for lex_any in lexicons:
				if typeof(lex_any) != TYPE_DICTIONARY:
					continue
				var lex: Dictionary = lex_any
				if str(lex.get("name", "")) == _lexicon:
					var fam_map: Dictionary = lex.get("families", {})
					if not fam_map.is_empty():
						families.assign(fam_map.keys())
	_family_option_node.clear()
	for fam in families:
		_family_option_node.add_item(str(fam))
	_available_families = families
	var sel_idx: int = maxi(0, families.find(_family))
	_family_option_node.select(sel_idx)
	_family = str(families[sel_idx])


func _select_family_option(family_id: String) -> void:
	if _family_option_node == null:
		return
	for item_index in range(_family_option_node.item_count):
		if _family_option_node.get_item_text(item_index) == family_id:
			_family_option_node.select(item_index)
			return


func _on_family_selected(item_index: int) -> void:
	_family = _family_option_node.get_item_text(item_index)
	_selected_row = -1
	_twin_row = -1
	await _refresh_field()


func _on_zoom_in() -> void:
	if _depth >= MAX_DEPTH:
		return
	_depth += 1
	await _refresh_field()


func _on_zoom_out() -> void:
	if _depth <= MIN_DEPTH:
		return
	_depth -= 1
	await _refresh_field()


func _on_decenter() -> void:
	if _twin_row < 0:
		_set_status("[i]Select a row first (click the atlas), then decenter to its twin.[/i]")
		return
	await _collapse_row(_twin_row)


func _on_reload() -> void:
	await _populate_families()
	await _refresh_field()


func _refresh_field() -> void:
	if _busy or _hub == null:
		return
	_busy = true
	_depth_label_node.text = "depth %d" % _depth
	_set_status("Loading field (family=%s, depth=%d)…" % [_family, _depth])
	var res: Dictionary = await _hub.closure_field(_lexicon, _family, _depth)
	_busy = false
	if not bool(res.get("ok", false)):
		_render_placeholder()
		var http_status: int = int(res.get("http_status", 0))
		if http_status == 404:
			_set_status("[color=#cc8866][b]Closure service not found on this Hub (404).[/b]\nThe running Hub is an older build without /closure/*. Start the updated Hub from source (port 17777), then press [b]Reload[/b].[/color]")
		elif http_status == 0:
			_set_status("[color=#cc8866][b]Hub unreachable.[/b] Start the Synesyn Hub (127.0.0.1:17777), then press [b]Reload[/b].\n[code]%s[/code][/color]" % str(res.get("error", "")))
		else:
			_set_status("[color=#cc6666]Field load failed (HTTP %d): %s[/color]" % [http_status, str(res.get("error", "?"))])
		return
	var matrix_any: Variant = res.get("matrix", [])
	_last_matrix = matrix_any if typeof(matrix_any) == TYPE_ARRAY else []
	_selected_row = -1
	_twin_row = -1
	_render()
	var meta: Dictionary = res.get("meta", {})
	var shape: Array = res.get("matrix_shape", [0, 0])
	var status_text: String = "Field %sx%s  unique_rows=%s  complementary_pairs=%s  (click a row to collapse)" % [
		str(shape[0]) if shape.size() > 0 else "?",
		str(shape[1]) if shape.size() > 1 else "?",
		str(meta.get("unique_rows", "?")),
		str(meta.get("complementary_pairs", "?")),
	]
	if not _bound_store_record_id.is_empty():
		status_text += "\nBound %s: %s" % [_bound_store_record_kind, _bound_store_record_id.left(12)]
		if not _bound_symbolic_seed.is_empty() and _bound_symbolic_seed != _family:
			status_text += "  seed=%s mapped_to_family=%s" % [_bound_symbolic_seed, _family]
	_set_status(status_text)
	field_loaded.emit(res)


func _on_view_gui_input(event: InputEvent) -> void:
	if _last_matrix.is_empty():
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var rect_h: float = maxf(1.0, _atlas_view_node.size.y)
			var rows: int = _last_matrix.size()
			var local_pos: Vector2 = mb.position
			var row_index: int = int((local_pos.y / rect_h) * float(rows))
			row_index = clampi(row_index, 0, rows - 1)
			await _collapse_row(row_index)


func _collapse_row(row_index: int) -> void:
	if _busy or _hub == null:
		return
	_busy = true
	var collapse_res: Dictionary = await _hub.closure_collapse(row_index, _lexicon, _family, _depth)
	var twin_res: Dictionary = await _hub.closure_twin(row_index, _lexicon, _family, _depth)
	_busy = false
	if not bool(collapse_res.get("ok", false)):
		_set_status("[color=#cc6666]Collapse failed: %s[/color]" % str(collapse_res.get("error", "?")))
		return
	_selected_row = row_index
	var twin_any: Variant = twin_res.get("twin_index", null)
	_twin_row = int(twin_any) if (typeof(twin_any) == TYPE_INT or typeof(twin_any) == TYPE_FLOAT) else -1
	_render()
	var provenance: Dictionary = collapse_res.get("provenance", {})
	var recipe: String = str(collapse_res.get("recipe", ""))
	var twin_text: String = ("twin → row %d" % _twin_row) if _twin_row >= 0 else "no twin present"
	_set_status("[b]Collapsed[/b] row %d  ρ=%.3f  %s\n[code]%s[/code]" % [
		row_index,
		float(provenance.get("pattern_density", 0.0)),
		twin_text,
		recipe,
	])
	row_collapsed.emit(provenance)


func _render() -> void:
	var rows: int = _last_matrix.size()
	if rows <= 0:
		return
	var first_row: Array = _last_matrix[0]
	var cols: int = first_row.size()
	if cols <= 0:
		return
	var img := Image.create_empty(cols, rows, false, Image.FORMAT_RGB8)
	var dark_base := Color(0.07, 0.09, 0.17)
	var light_base := Color(0.95, 0.93, 0.91)
	var dark_sel := Color(0.35, 0.26, 0.05)
	var light_sel := Color(0.98, 0.78, 0.22)
	var dark_twin := Color(0.05, 0.24, 0.30)
	var light_twin := Color(0.34, 0.82, 0.96)
	for y in range(rows):
		var row: Array = _last_matrix[y]
		var is_sel: bool = (y == _selected_row)
		var is_twin: bool = (y == _twin_row)
		for x in range(cols):
			var bit: int = int(row[x])
			var col: Color
			if is_sel:
				col = light_sel if bit == 1 else dark_sel
			elif is_twin:
				col = light_twin if bit == 1 else dark_twin
			else:
				col = light_base if bit == 1 else dark_base
			img.set_pixel(x, y, col)
	_atlas_view_node.texture = ImageTexture.create_from_image(img)


func _render_placeholder() -> void:
	# A subtle checker so the atlas area reads as an (empty) surface rather than
	# invisible nothing. The status label below explains the current state.
	if _atlas_view_node == null:
		return
	var sz: int = 16
	var img := Image.create_empty(sz, sz, false, Image.FORMAT_RGB8)
	var tone_a := Color(0.10, 0.12, 0.20)
	var tone_b := Color(0.14, 0.16, 0.27)
	for y in range(sz):
		for x in range(sz):
			img.set_pixel(x, y, tone_a if ((x + y) % 2 == 0) else tone_b)
	_atlas_view_node.texture = ImageTexture.create_from_image(img)


func _set_status(text: String) -> void:
	if _status_label_node != null:
		_status_label_node.text = text


func _record_id(record: Dictionary) -> String:
	var keys: Array[String] = ["closure_id", "context_pack_id", "memory_id", "artifact_id", "trace_id"]
	for key in keys:
		var value := str(record.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return "store_record"
