@tool
extends Control
class_name EdgelessPreview
const CardUiFactoryScript = preload("res://addons/synpunkt/scripts/internal/edgeless_card_ui_factory.gd")
const EdgelessLayoutUtilsScript = preload("res://addons/synpunkt/scripts/internal/edgeless_layout_utils.gd")

# Minimal read-only preview of a SynDoc edgeless layout.
# Expects nodes as: [{ "pos": [x,y], "z": float (optional), "label": string (optional) }, ...]

var _nodes: Array = []
signal selection_changed(node_id: String, ref: Dictionary)
signal node_moved(node_id: String, new_pos: Array) # new_pos = [x,y] in layout space
signal label_changed(node_id: String, label: String)
signal drag_ended()

var _selected_node_id: String = ""
var _clusters: Array = [] # [{id,pos,z,label,ref,...}]
var _node_cluster: Dictionary = {} # node_id -> cluster_id
var _overlay_nodes: Array = [] # read-only overlay nodes (e.g. sensors), same node schema as _nodes
var _show_labels: bool = false
var _editable: bool = false
var _snap_enabled: bool = false
var _grid_size: float = 50.0

enum RenderStyle { CARDS, DOTS }
var _render_style: int = RenderStyle.CARDS

# Frame card sizing (in screen pixels).
# Important: cards must remain legible even when fit-to-view scale is very small (e.g. large projections),
# so we size in screen px rather than layout units.
var _frame_card_size_px: Vector2 = Vector2(240.0, 150.0)
const _FRAME_CARD_CORNER_PAD_PX := 10.0
const _FRAME_CARD_SEPARATION_PX := 14.0

var _avoid_overlap: bool = true

# Optional: render SynDoc frame nodes as real Control-based cards (text/images),
# instead of drawing placeholder rectangles.
var _render_frames_as_controls: bool = false
var _syndoc_frames_by_id: Dictionary = {} # frame_id -> frame Dictionary
var _frame_cards_by_node_id: Dictionary = {} # node_id -> Control
var _image_uri_map: Dictionary = {} # artifact_id -> uri (file://... or res://...)
var _presentation_style: bool = false
var is_dark_mode: bool = true

var _dragging: bool = false
var _drag_node_id: String = ""
var _drag_last_mouse: Vector2 = Vector2.ZERO

# View state (read-only inspector)
var _zoom: float = 1.0 # user zoom multiplier
var _pan: Vector2 = Vector2.ZERO # user pan in screen px
var _panning: bool = false
var _pan_anchor_mouse: Vector2 = Vector2.ZERO
var _pan_anchor_pan: Vector2 = Vector2.ZERO

# Cached bounds + fit transform (screen px)
var _has_bounds: bool = false
var _min_xy: Vector2 = Vector2.ZERO
var _max_xy: Vector2 = Vector2.ZERO
var _center_xy: Vector2 = Vector2.ZERO
var _fit_scale: float = 1.0
var _fit_offset: Vector2 = Vector2.ZERO
var _min_z: float = 0.0
var _max_z: float = 0.0
var _bounds_dirty: bool = true

# Initial camera snapshot (captured when content is loaded/set).
# Reset View should return to this, so it remains distinct from Fit to Layout.
var _initial_has_bounds: bool = false
var _initial_min_xy: Vector2 = Vector2.ZERO
var _initial_max_xy: Vector2 = Vector2.ZERO
var _initial_center_xy: Vector2 = Vector2.ZERO
var _initial_min_z: float = 0.0
var _initial_max_z: float = 0.0
var _initial_zoom: float = 1.0
var _initial_pan: Vector2 = Vector2.ZERO

# --- Camera helpers (v1)
func get_camera() -> Dictionary:
	# Camera is expressed in layout space:
	# - center: [x,y] layout coords that should be centered on screen
	# - zoom: user zoom multiplier
	if not _has_bounds:
		return {"center": [0.0, 0.0], "zoom": float(_zoom)}
	var center_layout: Vector2 = _screen_to_layout(size * 0.5, _zoom)
	return {"center": [center_layout.x, center_layout.y], "zoom": float(_zoom)}

func set_camera(center: Array, zoom_value: float) -> void:
	# Center the given layout-space point in the viewport and apply zoom.
	if not _has_bounds:
		_zoom = clamp(float(zoom_value), 0.15, 8.0)
		queue_redraw()
		return
	var cx := 0.0
	var cy := 0.0
	if center.size() >= 2:
		cx = float(center[0])
		cy = float(center[1])
	_zoom = clamp(float(zoom_value), 0.15, 8.0)
	var denom: float = max(_fit_scale * _zoom, 0.00001)
	# We want layout point (cx,cy) to map to screen center (= _fit_offset).
	# _layout_to_screen(L) = _fit_offset + _pan + (L - _center_xy) * (_fit_scale*_zoom)
	# => _pan = - (L - _center_xy) * (_fit_scale*_zoom)
	_pan = -(Vector2(cx, cy) - _center_xy) * denom
	queue_redraw()
	_update_frame_cards_transform()

func set_nodes(nodes: Array) -> void:
	_nodes = nodes
	if not _selected_node_id.is_empty() and _find_node_by_id(_selected_node_id) == null:
		_selected_node_id = ""
	# Treat this as a "new document/layout loaded" event; capture an initial camera snapshot.
	_bounds_dirty = true
	_recompute_bounds()
	_capture_initial_view_snapshot()
	reset_to_initial_view()
	queue_redraw()
	_rebuild_frame_cards()

func set_edgeless(edgeless: Dictionary) -> void:
	var nodes_any: Variant = edgeless.get("nodes", [])
	_nodes = nodes_any if typeof(nodes_any) == TYPE_ARRAY else []
	var clusters_any: Variant = edgeless.get("clusters", [])
	_clusters = clusters_any if typeof(clusters_any) == TYPE_ARRAY else []
	var map_any: Variant = edgeless.get("node_cluster", {})
	_node_cluster = map_any if typeof(map_any) == TYPE_DICTIONARY else {}
	if not _selected_node_id.is_empty() and _find_any_by_id(_selected_node_id) == null:
		_selected_node_id = ""
	# Treat this as a "new document/layout loaded" event; capture an initial camera snapshot.
	_bounds_dirty = true
	_recompute_bounds()
	_capture_initial_view_snapshot()
	reset_to_initial_view()
	queue_redraw()
	_rebuild_frame_cards()

func set_overlay_nodes(nodes: Array) -> void:
	# Overlay nodes are never persisted; they are purely a view-layer concern.
	_overlay_nodes = nodes
	queue_redraw()

func select_node(node_id: String) -> void:
	if node_id.is_empty():
		_selected_node_id = ""
		queue_redraw()
		_update_frame_cards_selection_styles()
		selection_changed.emit("", {})
		return
	if _find_any_by_id(node_id) == null:
		return
	_selected_node_id = node_id
	queue_redraw()
	_update_frame_cards_selection_styles()
	var n_any: Variant = _find_any_by_id(_selected_node_id)
	var ref: Dictionary = {}
	if typeof(n_any) == TYPE_DICTIONARY:
		var n: Dictionary = n_any
		var ref_any: Variant = n.get("ref", {})
		if typeof(ref_any) == TYPE_DICTIONARY:
			ref = ref_any
	selection_changed.emit(_selected_node_id, ref)

func focus_node(node_id: String) -> void:
	if not _has_bounds:
		return
	var n_any: Variant = _find_any_by_id(node_id)
	if typeof(n_any) != TYPE_DICTIONARY:
		return
	var n: Dictionary = n_any
	var pos_any: Variant = n.get("pos", null)
	if typeof(pos_any) != TYPE_ARRAY:
		return
	var pos: Array = pos_any
	if pos.size() < 2:
		return
	var target_screen: Vector2 = _layout_to_screen(Vector2(float(pos[0]), float(pos[1])))
	var desired: Vector2 = size * 0.5
	_pan += (desired - target_screen)
	queue_redraw()

func set_show_labels(enabled: bool) -> void:
	_show_labels = enabled
	queue_redraw()

func set_render_style(style_id: int) -> void:
	_render_style = int(style_id)
	queue_redraw()

func get_render_style() -> int:
	return int(_render_style)

func set_frame_card_size_px(size_px: Vector2) -> void:
	_frame_card_size_px = Vector2(max(size_px.x, 80.0), max(size_px.y, 60.0))
	_rebuild_frame_cards()
	queue_redraw()

func set_avoid_overlap(enabled: bool) -> void:
	_avoid_overlap = bool(enabled)

func get_avoid_overlap() -> bool:
	return bool(_avoid_overlap)

func set_render_frames_as_controls(enabled: bool) -> void:
	_render_frames_as_controls = bool(enabled)
	set_process(_render_frames_as_controls)
	_rebuild_frame_cards()
	queue_redraw()

func set_presentation_style(enabled: bool) -> void:
	_presentation_style = bool(enabled)
	_rebuild_frame_cards()
	queue_redraw()

func set_dark_mode(enabled: bool) -> void:
	is_dark_mode = bool(enabled)
	_rebuild_frame_cards()
	queue_redraw()

func _is_light_cards() -> bool:
	return _presentation_style or not is_dark_mode

func _canvas_bg_fill() -> Color:
	return Color(0.08, 0.08, 0.09, 1.0) if is_dark_mode else Color(0.93, 0.93, 0.95, 1.0)

func _canvas_bg_border() -> Color:
	return Color(0.18, 0.18, 0.20, 1.0) if is_dark_mode else Color(0.78, 0.78, 0.80, 1.0)

func _card_fill_col() -> Color:
	return Color(0.10, 0.14, 0.22, 0.92) if is_dark_mode else Color(0.97, 0.97, 1.0, 0.94)

func _card_text_col() -> Color:
	return Color(0.92, 0.92, 0.96, 0.95) if is_dark_mode else Color(0.12, 0.12, 0.16, 0.95)

func _label_text_col() -> Color:
	return Color(0.9, 0.9, 0.95, 0.9) if is_dark_mode else Color(0.1, 0.1, 0.15, 0.9)

func _dot_label_text_col() -> Color:
	return Color(0.85, 0.85, 0.9, 0.9) if is_dark_mode else Color(0.15, 0.15, 0.2, 0.9)

func _center_text_col() -> Color:
	return Color(0.7, 0.7, 0.75, 1.0) if is_dark_mode else Color(0.45, 0.45, 0.50, 1.0)

func _overlay_text_col() -> Color:
	return Color(0.95, 0.9, 0.7, 1.0) if is_dark_mode else Color(0.35, 0.25, 0.05, 1.0)

func _overlay_outline_col() -> Color:
	return Color(0.10, 0.10, 0.10, 1.0) if is_dark_mode else Color(0.80, 0.80, 0.80, 1.0)

func set_syndoc_frames(frames: Array) -> void:
	# frames: [{id, blocks:[{type,text,...}], ...}]
	_syndoc_frames_by_id = {}
	for frame_any in frames:
		if typeof(frame_any) != TYPE_DICTIONARY:
			continue
		var frame_dict: Dictionary = frame_any
		var frame_id := str(frame_dict.get("id", "")).strip_edges()
		if frame_id.is_empty():
			continue
		_syndoc_frames_by_id[frame_id] = frame_dict
	_rebuild_frame_cards()

func set_image_uri_map(uri_map: Dictionary) -> void:
	# uri_map: {artifact_id: "file://.../image.png"}
	_image_uri_map = uri_map if typeof(uri_map) == TYPE_DICTIONARY else {}
	_rebuild_frame_cards()

func set_editable(enabled: bool) -> void:
	_editable = enabled

func is_editable() -> bool:
	return _editable

func set_snap_enabled(enabled: bool) -> void:
	_snap_enabled = enabled

func set_grid_size(size_value: float) -> void:
	_grid_size = max(size_value, 1.0)

func get_selected_node_id() -> String:
	return _selected_node_id

func get_node_label(node_id: String) -> String:
	var n_any: Variant = _find_any_by_id(node_id)
	if typeof(n_any) != TYPE_DICTIONARY:
		return ""
	return str((n_any as Dictionary).get("label", "")).strip_edges()

func set_node_label(node_id: String, label: String) -> void:
	if node_id.is_empty():
		return
	var n_any: Variant = _find_any_by_id(node_id)
	if typeof(n_any) != TYPE_DICTIONARY:
		return
	# Update the backing array entry.
	if node_id.begins_with("cluster:"):
		for i in range(_clusters.size()):
			if typeof(_clusters[i]) != TYPE_DICTIONARY:
				continue
			var c: Dictionary = _clusters[i]
			if str(c.get("id", "")).strip_edges() == node_id:
				c["label"] = label
				_clusters[i] = c
				break
	else:
		for i in range(_nodes.size()):
			if typeof(_nodes[i]) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = _nodes[i]
			if str(n.get("id", "")).strip_edges() == node_id:
				n["label"] = label
				_nodes[i] = n
				break
	queue_redraw()
	label_changed.emit(node_id, label)

func clear() -> void:
	_nodes = []
	_clusters = []
	_node_cluster = {}
	_overlay_nodes = []
	_syndoc_frames_by_id = {}
	_clear_frame_cards()
	_selected_node_id = ""
	_initial_has_bounds = false
	_initial_zoom = 1.0
	_initial_pan = Vector2.ZERO
	reset_view()
	_bounds_dirty = true
	queue_redraw()

func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	queue_redraw()
	_update_frame_cards_transform()

func reset_to_initial_view() -> void:
	# Reset camera/bounds to the initial snapshot captured when content was loaded.
	if _initial_has_bounds:
		_has_bounds = true
		_min_xy = _initial_min_xy
		_max_xy = _initial_max_xy
		_center_xy = _initial_center_xy
		_min_z = _initial_min_z
		_max_z = _initial_max_z
		_bounds_dirty = false
	_zoom = float(_initial_zoom)
	_pan = _initial_pan
	queue_redraw()
	_update_frame_cards_transform()

func fit_to_layout() -> void:
	# Recompute bounds and reset camera so content is visible.
	# This is distinct from reset_view() because bounds are not recomputed on every draw.
	_bounds_dirty = true
	_recompute_bounds()
	_zoom = 1.0
	_pan = Vector2.ZERO
	queue_redraw()
	_update_frame_cards_transform()

func _capture_initial_view_snapshot() -> void:
	_initial_has_bounds = bool(_has_bounds)
	if _initial_has_bounds:
		_initial_min_xy = _min_xy
		_initial_max_xy = _max_xy
		_initial_center_xy = _center_xy
		_initial_min_z = float(_min_z)
		_initial_max_z = float(_max_z)
	_initial_zoom = 1.0
	_initial_pan = Vector2.ZERO

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, _canvas_bg_fill(), true)
	draw_rect(r, _canvas_bg_border(), false, 1.0)

	if _nodes.is_empty() and _clusters.is_empty():
		_draw_center_text("(no edgeless layout)")
		return

	# Important UX: do NOT auto-refit the view every draw.
	# If we recompute bounds+fit continuously, moving one node makes the entire view shift/scale,
	# which feels like other cards are moving. We only recompute when content is set/cleared.
	if _bounds_dirty or not _has_bounds:
		_recompute_bounds()
	_bounds_dirty = false
	if not _has_bounds:
		_draw_center_text("(no valid points)")
		return

	var pad: float = 14.0
	var w: float = max(r.size.x - pad * 2.0, 10.0)
	var h: float = max(r.size.y - pad * 2.0, 10.0)
	var range_x: float = max(_max_xy.x - _min_xy.x, 0.00001)
	var range_y: float = max(_max_xy.y - _min_xy.y, 0.00001)
	var range_z: float = max(_max_z - _min_z, 0.00001)

	# Fit-to-view transform
	_fit_scale = min(w / range_x, h / range_y)
	_fit_offset = Vector2(pad + w * 0.5, pad + h * 0.5)

	# Draw points
	var font: Font = get_theme_default_font()
	var font_size: int = get_theme_default_font_size()
	var denom: float = max(_fit_scale * _zoom, 0.00001)
	var zoom_ui: float = clamp(_zoom, 0.75, 2.0)

	# Draw clusters first (island markers)
	for c_any in _clusters:
		if typeof(c_any) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_any
		var pos_any: Variant = c.get("pos", null)
		if typeof(pos_any) != TYPE_ARRAY:
			continue
		var pos: Array = pos_any
		if pos.size() < 2:
			continue
		var p: Vector2 = _layout_to_screen(Vector2(float(pos[0]), float(pos[1])))
		var cid := int(c.get("cluster_id", -1))
		var col: Color = _cluster_color(cid)
		var r_big: float = 14.0 * clamp(_zoom, 0.75, 2.0)
		var node_id := str(c.get("id", "")).strip_edges()
		var is_sel := (not _selected_node_id.is_empty() and node_id == _selected_node_id)
		draw_circle(p, r_big, Color(col.r, col.g, col.b, 0.15))
		draw_circle(p, r_big * 0.65, Color(col.r, col.g, col.b, 0.25))
		if is_sel:
			draw_circle(p, r_big + 4.0, Color(1.0, 0.9, 0.3, 0.25))
			draw_circle(p, r_big + 2.0, Color(1.0, 0.9, 0.3, 0.9))
		draw_circle(p, r_big * 0.45, Color(col.r, col.g, col.b, 0.9))

		if _show_labels and font:
			var label := str(c.get("label", "Cluster")).strip_edges()
			if not label.is_empty():
				draw_string(font, p + Vector2(10, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _label_text_col())

	for n_any in _nodes:
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		var pos_any: Variant = n.get("pos", null)
		if typeof(pos_any) != TYPE_ARRAY:
			continue
		var pos: Array = pos_any
		if pos.size() < 2:
			continue

		var x: float = float(pos[0])
		var y: float = float(pos[1])
		var p: Vector2 = _layout_to_screen(Vector2(x, y))

		var z: float = float(n.get("z", 0.0))
		var zn: float = (z - _min_z) / range_z

		# Color by cluster membership if present; otherwise use z-based default.
		var node_id := str(n.get("id", "")).strip_edges()
		var base: Color = Color(0.35 + 0.35 * zn, 0.55 + 0.25 * zn, 0.95, 1.0)
		if _node_cluster.has(node_id):
			base = _cluster_color(int(_node_cluster.get(node_id, -1)))
		var is_sel := (not _selected_node_id.is_empty() and node_id == _selected_node_id)

		# Render SynDoc frames as cards (default), and keep other nodes as dots.
		if _render_style == RenderStyle.CARDS and _node_is_syndoc_frame(n):
			# If we're rendering full frame Controls, skip placeholder card drawing.
			if _render_frames_as_controls:
				continue
			var size_screen: Vector2 = _frame_card_size_px * zoom_ui
			var rect := Rect2(p - size_screen * 0.5, size_screen)
			# Background + border
			var fill := _card_fill_col()
			var border := Color(base.r, base.g, base.b, 0.85)
			draw_rect(rect, fill, true)
			draw_rect(rect, border, false, 2.0)
			if is_sel:
				draw_rect(rect.grow(2.0), Color(1.0, 0.9, 0.3, 0.35), false, 4.0)

			# Title/label (top-left)
			if font:
				var label := str(n.get("label", "")).strip_edges()
				if label.is_empty():
					label = node_id
				var sz := int(clamp(float(font_size) * clamp(_zoom, 0.85, 1.35), 11.0, 20.0))
				var pad_px := Vector2(_FRAME_CARD_CORNER_PAD_PX, _FRAME_CARD_CORNER_PAD_PX)
				var text_pos := rect.position + pad_px + Vector2(0.0, float(sz))
				draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - pad_px.x * 2.0, sz, _card_text_col())
		else:
			var c: Color = base
			var radius: float = (4.0 + 2.0 * zn) * zoom_ui
			if is_sel:
				draw_circle(p, radius + 3.0, Color(1.0, 0.9, 0.3, 0.35))
				draw_circle(p, radius + 1.5, Color(1.0, 0.9, 0.3, 0.9))
			draw_circle(p, radius, c)

			if _show_labels and font:
				var label2 := str(n.get("label", "")).strip_edges()
				if not label2.is_empty():
					draw_string(font, p + Vector2(8, 4), label2, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _dot_label_text_col())

	# Draw overlay nodes last (so they sit on top)
	for n_any in _overlay_nodes:
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		var pos_any: Variant = n.get("pos", null)
		if typeof(pos_any) != TYPE_ARRAY:
			continue
		var pos: Array = pos_any
		if pos.size() < 2:
			continue
		var x: float = float(pos[0])
		var y: float = float(pos[1])
		var p: Vector2 = _layout_to_screen(Vector2(x, y))
		var radius: float = 7.0 * clamp(_zoom, 0.75, 2.0)
		var col := Color(0.95, 0.75, 0.15, 1.0)
		draw_circle(p, radius, col)
		draw_circle(p, radius + 1.5, _overlay_outline_col(), false, 2.0)
		if font:
			var label := str(n.get("label", "")).strip_edges()
			if not label.is_empty():
				draw_string(font, p + Vector2(10, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _overlay_text_col())

func _draw_center_text(text: String) -> void:
	var font: Font = get_theme_default_font()
	var font_size: int = get_theme_default_font_size()
	if not font:
		return
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var p := (size - text_size) * 0.5
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, _center_text_col())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.keycode == KEY_R:
			reset_to_initial_view()
			accept_event()
			return

	# Pan: middle or right drag. Zoom: wheel. Select: left click.
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom_at(e.position, 1.15)
			accept_event()
			return
		if e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom_at(e.position, 1.0 / 1.15)
			accept_event()
			return
		if e.button_index == MOUSE_BUTTON_MIDDLE or e.button_index == MOUSE_BUTTON_RIGHT:
			if e.pressed:
				_panning = true
				_pan_anchor_mouse = e.position
				_pan_anchor_pan = _pan
			else:
				_panning = false
			accept_event()
			return
		if e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			grab_focus()
			_select_at(e.position)
			if _editable and not _selected_node_id.is_empty():
				_dragging = true
				_drag_node_id = _selected_node_id
				_drag_last_mouse = e.position
			accept_event()
			return
		if e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			if _dragging:
				# Resolve overlaps at drop time (stable UX; avoids jitter during drag).
				var last_drag_id := _drag_node_id
				_dragging = false
				_drag_node_id = ""
				if _avoid_overlap and _render_style == RenderStyle.CARDS and not last_drag_id.is_empty():
					_resolve_frame_card_overlaps(last_drag_id)
				drag_ended.emit()
				accept_event()
				return

	if event is InputEventMouseMotion:
		var m: InputEventMouseMotion = event
		if _panning:
			_pan = _pan_anchor_pan + (m.position - _pan_anchor_mouse)
			queue_redraw()
			accept_event()
			return
		if _dragging and _editable and not _drag_node_id.is_empty():
			var delta_screen: Vector2 = m.position - _drag_last_mouse
			_drag_last_mouse = m.position
			var denom: float = max(_fit_scale * _zoom, 0.00001)
			var delta_layout: Vector2 = delta_screen / denom
			_move_node_layout_delta(_drag_node_id, delta_layout)
			accept_event()
			return

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var old_zoom: float = _zoom
	_zoom = clamp(_zoom * factor, 0.15, 8.0)
	if is_equal_approx(old_zoom, _zoom):
		return
	if not _has_bounds:
		queue_redraw()
		return

	# Keep the layout point under cursor stable.
	var world_before: Vector2 = _screen_to_layout(screen_pos, old_zoom)
	var world_after: Vector2 = _screen_to_layout(screen_pos, _zoom)
	var delta_world: Vector2 = world_after - world_before
	_pan -= delta_world * (_fit_scale * _zoom)
	queue_redraw()

func _layout_to_screen(layout_pos: Vector2) -> Vector2:
	var v: Vector2 = (layout_pos - _center_xy) * (_fit_scale * _zoom)
	return _fit_offset + _pan + v

func _screen_to_layout(screen_pos: Vector2, zoom_value: float) -> Vector2:
	var denom: float = max(_fit_scale * zoom_value, 0.00001)
	var v: Vector2 = (screen_pos - _fit_offset - _pan) / denom
	return _center_xy + v

func _select_at(screen_pos: Vector2) -> void:
	if _nodes.is_empty() and _clusters.is_empty():
		return
	var best_id: String = ""
	var best_d2: float = INF
	var hit_r: float = 10.0 * clamp(_zoom, 0.75, 2.0)
	var hit_r2: float = hit_r * hit_r

	# Hit test clusters (slightly larger)
	var hit_rc: float = 18.0 * clamp(_zoom, 0.75, 2.0)
	var hit_rc2: float = hit_rc * hit_rc
	for c_any in _clusters:
		if typeof(c_any) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_any
		var pos_any: Variant = c.get("pos", null)
		if typeof(pos_any) != TYPE_ARRAY:
			continue
		var pos: Array = pos_any
		if pos.size() < 2:
			continue
		var p: Vector2 = _layout_to_screen(Vector2(float(pos[0]), float(pos[1])))
		var d2: float = p.distance_squared_to(screen_pos)
		if d2 <= hit_rc2 and d2 < best_d2:
			best_d2 = d2
			best_id = str(c.get("id", "")).strip_edges()

	# Prefer card hit-test for SynDoc frames when in card mode.
	if _render_style == RenderStyle.CARDS:
		var scale_factor: float = clamp(_zoom, 0.15, 8.0) if _render_frames_as_controls else clamp(_zoom, 0.75, 2.0)
		var size_screen: Vector2 = _frame_card_size_px * scale_factor
		for n_any_card in _nodes:
			if typeof(n_any_card) != TYPE_DICTIONARY:
				continue
			var n_card: Dictionary = n_any_card
			if not _node_is_syndoc_frame(n_card):
				continue
			var pos_any_card: Variant = n_card.get("pos", null)
			if typeof(pos_any_card) != TYPE_ARRAY:
				continue
			var pos_card: Array = pos_any_card
			if pos_card.size() < 2:
				continue
			var p_card: Vector2 = _layout_to_screen(Vector2(float(pos_card[0]), float(pos_card[1])))
			var rect := Rect2(p_card - size_screen * 0.5, size_screen)
			if rect.has_point(screen_pos):
				best_id = str(n_card.get("id", "")).strip_edges()
				best_d2 = 0.0
				break

	for n_any in _nodes:
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		# If we already hit a card, don't override with dots.
		if best_d2 <= 0.0:
			break
		var pos_any: Variant = n.get("pos", null)
		if typeof(pos_any) != TYPE_ARRAY:
			continue
		var pos: Array = pos_any
		if pos.size() < 2:
			continue
		var p: Vector2 = _layout_to_screen(Vector2(float(pos[0]), float(pos[1])))
		var d2: float = p.distance_squared_to(screen_pos)
		if d2 <= hit_r2 and d2 < best_d2:
			best_d2 = d2
			best_id = str(n.get("id", "")).strip_edges()

	if best_id == _selected_node_id:
		return
	_selected_node_id = best_id
	queue_redraw()
	_update_frame_cards_selection_styles()

	if not _selected_node_id.is_empty():
		var n_any: Variant = _find_any_by_id(_selected_node_id)
		var ref: Dictionary = {}
		if typeof(n_any) == TYPE_DICTIONARY:
			var n: Dictionary = n_any
			var ref_any: Variant = n.get("ref", {})
			if typeof(ref_any) == TYPE_DICTIONARY:
				ref = ref_any
		selection_changed.emit(_selected_node_id, ref)

func _node_is_syndoc_frame(node_dict: Dictionary) -> bool:
	# Identify frame-nodes created by SynPunkt's frame-grid builder.
	var ref_any: Variant = node_dict.get("ref", null)
	if typeof(ref_any) != TYPE_DICTIONARY:
		return false
	var ref: Dictionary = ref_any
	return str(ref.get("kind", "")).strip_edges() == "syndoc_frame"

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_frame_cards_transform()

func _process(_delta: float) -> void:
	# Keep frame cards synced to pan/zoom changes.
	if not _render_frames_as_controls:
		return
	if _frame_cards_by_node_id.is_empty():
		return
	_update_frame_cards_transform()

func _rebuild_frame_cards() -> void:
	if not _render_frames_as_controls:
		_clear_frame_cards()
		return
	# Only render for card-style + frame nodes.
	if _render_style != RenderStyle.CARDS:
		_clear_frame_cards()
		return
	if _nodes.is_empty():
		_clear_frame_cards()
		return

	# Ensure bounds/fit are available so transforms work.
	if _bounds_dirty or not _has_bounds:
		_recompute_bounds()
	_bounds_dirty = false

	var keep: Dictionary = {}
	for n_any in _nodes:
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		if not _node_is_syndoc_frame(n):
			continue
		var node_id := str(n.get("id", "")).strip_edges()
		if node_id.is_empty():
			continue
		var ref_any: Variant = n.get("ref", {})
		if typeof(ref_any) != TYPE_DICTIONARY:
			continue
		var ref: Dictionary = ref_any
		var frame_id := str(ref.get("frame_id", "")).strip_edges()
		if frame_id.is_empty():
			continue
		var frame_any: Variant = _syndoc_frames_by_id.get(frame_id, null)
		var frame: Dictionary = {}
		if typeof(frame_any) == TYPE_DICTIONARY:
			frame = frame_any
		else:
			# Keep the card visible even if the layout references a missing frame id
			# (common when raw JSON edits renamed/added frames without rebuilding layout).
			frame = {
				"id": frame_id,
				"kind": "document",
				"blocks": [
					{"type": "h1", "text": frame_id},
					{"type": "p", "text": "(Missing frame content for this frame_id. Rebuild the edgeless layout or add a node for this frame.)"},
				],
			}

		var card_any: Variant = _frame_cards_by_node_id.get(node_id, null)
		var card: Control
		if card_any != null and card_any is Control:
			card = card_any as Control
		else:
			card = CardUiFactoryScript.make_frame_card_control(_frame_card_size_px, _presentation_style, is_dark_mode)
			card.name = "FrameCard_%s" % node_id.replace(":", "_")
			add_child(card)
			_frame_cards_by_node_id[node_id] = card
		_update_frame_card_content(card, frame)
		keep[node_id] = true

	# Remove stale cards
	for k_any in _frame_cards_by_node_id.keys():
		var key := str(k_any)
		if not keep.has(key):
			var old_any: Variant = _frame_cards_by_node_id[key]
			if old_any is Node:
				(old_any as Node).queue_free()
			_frame_cards_by_node_id.erase(key)

	_update_frame_cards_transform()

func _clear_frame_cards() -> void:
	for k_any in _frame_cards_by_node_id.keys():
		var old_any: Variant = _frame_cards_by_node_id[k_any]
		if old_any is Node:
			(old_any as Node).queue_free()
	_frame_cards_by_node_id = {}

func _update_frame_cards_transform() -> void:
	if not _render_frames_as_controls:
		return
	if _frame_cards_by_node_id.is_empty():
		return
	# Bounds/fit must exist to compute screen positions.
	if _bounds_dirty or not _has_bounds:
		_recompute_bounds()
	_bounds_dirty = false

	var base_size: Vector2 = _frame_card_size_px
	var scale_factor: float = clamp(_zoom, 0.15, 8.0)
	for n_any in _nodes:
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		if not _node_is_syndoc_frame(n):
			continue
		var node_id := str(n.get("id", "")).strip_edges()
		if node_id.is_empty():
			continue
		var card_any: Variant = _frame_cards_by_node_id.get(node_id, null)
		if card_any == null or not (card_any is Control):
			continue
		var card: Control = card_any as Control
		var pos_any: Variant = n.get("pos", null)
		if typeof(pos_any) != TYPE_ARRAY:
			continue
		var pos_arr: Array = pos_any
		if pos_arr.size() < 2:
			continue
		var pos_screen: Vector2 = _layout_to_screen(Vector2(float(pos_arr[0]), float(pos_arr[1])))
		card.pivot_offset = base_size * 0.5
		# Position uses top-left; we set it so pivot lands at pos_screen.
		card.position = pos_screen - (card.pivot_offset * scale_factor)
		card.scale = Vector2(scale_factor, scale_factor)
		card.visible = true

	_update_frame_cards_selection_styles()

func _update_frame_cards_selection_styles() -> void:
	if _frame_cards_by_node_id.is_empty():
		return
	for k_any in _frame_cards_by_node_id.keys():
		var node_id := str(k_any)
		var card_any: Variant = _frame_cards_by_node_id.get(node_id, null)
		if card_any == null or not (card_any is Control):
			continue
		var card: Control = card_any as Control
		var sb_any: Variant = card.get_meta("frame_card_stylebox") if card.has_meta("frame_card_stylebox") else null
		if sb_any == null or not (sb_any is StyleBoxFlat):
			continue
		var sb: StyleBoxFlat = sb_any as StyleBoxFlat
		var is_sel := (not _selected_node_id.is_empty() and node_id == _selected_node_id)
		if is_sel:
			sb.border_color = Color(1.0, 0.9, 0.35, 0.95)
			sb.border_width_left = 4
			sb.border_width_top = 4
			sb.border_width_right = 4
			sb.border_width_bottom = 4
		else:
			sb.border_color = Color(0.15, 0.15, 0.18, 0.95) if _presentation_style else Color(0.25, 0.45, 0.95, 0.75)
			sb.border_width_left = 2
			sb.border_width_top = 2
			sb.border_width_right = 2
			sb.border_width_bottom = 2
		# Re-apply to force redraw in some themes/contexts.
		card.add_theme_stylebox_override("panel", sb)

func _update_frame_card_content(card: Control, frame: Dictionary) -> void:
	var vbox_any := card.find_child("Content", true, false)
	if vbox_any == null or not (vbox_any is VBoxContainer):
		return
	var vbox: VBoxContainer = vbox_any as VBoxContainer
	for child_node in vbox.get_children():
		(child_node as Node).queue_free()

	# Always show the frame id in presentation style so users can visually map canvas cards ↔ frame list.
	# (Frame titles can still live in the frame blocks, e.g. first h1.)
	if _presentation_style:
		var fid := str(frame.get("id", "")).strip_edges()
		if not fid.is_empty():
			vbox.add_child(CardUiFactoryScript.make_frame_id_row(fid))

	var blocks_any: Variant = frame.get("blocks", [])
	var blocks: Array = blocks_any if typeof(blocks_any) == TYPE_ARRAY else []
	for b_any in blocks:
		if typeof(b_any) != TYPE_DICTIONARY:
			continue
		var b: Dictionary = b_any
		var t := str(b.get("type", "p")).to_lower()
		var txt := str(b.get("text", ""))
		var font_col: Color = Color(0.07, 0.07, 0.08, 1.0) if _is_light_cards() else Color(0.86, 0.86, 0.92, 1.0)
		var head_col: Color = Color(0.0, 0.0, 0.0, 1.0) if _is_light_cards() else Color(0.95, 0.95, 0.98, 1.0)
		var sub_col: Color = Color(0.05, 0.05, 0.06, 1.0) if _is_light_cards() else Color(0.92, 0.92, 0.96, 1.0)
		if t == "h1":
			vbox.add_child(CardUiFactoryScript.make_text_row(txt, 24, head_col, _presentation_style))
		elif t == "h2":
			vbox.add_child(CardUiFactoryScript.make_text_row(txt, 18, sub_col, _presentation_style))
		elif t == "li":
			vbox.add_child(CardUiFactoryScript.make_text_row("• " + txt, 14, font_col, _presentation_style))
		elif t == "highlight":
			var c := Color(0.55, 0.35, 0.05, 1.0) if _is_light_cards() else Color(1.0, 0.9, 0.35, 1.0)
			vbox.add_child(CardUiFactoryScript.make_text_row(txt, 14, c, _presentation_style))
		elif t == "image" or t == "img":
			# Best-effort: support file:// or res:// URIs in `uri` or `src`.
			var img_uri := _resolve_image_uri(b)
			var tex := _load_texture_from_uri(img_uri)
			if tex != null:
				var tr := TextureRect.new()
				tr.texture = tex
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.custom_minimum_size = Vector2(_frame_card_size_px.x - 20.0, 140.0)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				vbox.add_child(tr)
			else:
				vbox.add_child(CardUiFactoryScript.make_text_row("(image missing)", 14, Color(0.65, 0.20, 0.20, 1.0) if _is_light_cards() else Color(0.85, 0.65, 0.65, 1.0), _presentation_style))
		else:
			vbox.add_child(CardUiFactoryScript.make_text_row(txt, 14, font_col, _presentation_style))

func _resolve_image_uri(block: Dictionary) -> String:
	return EdgelessLayoutUtilsScript.resolve_image_uri(block, _image_uri_map)

func _load_texture_from_uri(uri: String) -> Texture2D:
	return EdgelessLayoutUtilsScript.load_texture_from_uri(uri)

func _find_node_by_id(node_id: String) -> Variant:
	return EdgelessLayoutUtilsScript.find_node_by_id(_nodes, node_id)

func _find_any_by_id(node_id: String) -> Variant:
	return EdgelessLayoutUtilsScript.find_any_by_id(_nodes, _clusters, node_id)

func _move_node_layout_delta(node_id: String, delta_layout: Vector2) -> void:
	var n_any: Variant = _find_any_by_id(node_id)
	if typeof(n_any) != TYPE_DICTIONARY:
		return
	if node_id.begins_with("cluster:"):
		for i in range(_clusters.size()):
			if typeof(_clusters[i]) != TYPE_DICTIONARY:
				continue
			var c: Dictionary = _clusters[i]
			if str(c.get("id", "")).strip_edges() != node_id:
				continue
			var pos_any: Variant = c.get("pos", null)
			if typeof(pos_any) != TYPE_ARRAY:
				return
			var pos: Array = pos_any
			if pos.size() < 2:
				return
			var x: float = float(pos[0]) + delta_layout.x
			var y: float = float(pos[1]) + delta_layout.y
			if _snap_enabled:
				var gs: float = max(_grid_size, 1.0)
				x = snapped(x, gs)
				y = snapped(y, gs)
			c["pos"] = [x, y]
			_clusters[i] = c
			queue_redraw()
			node_moved.emit(node_id, [x, y])
			return
	else:
		for i in range(_nodes.size()):
			if typeof(_nodes[i]) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = _nodes[i]
			if str(n.get("id", "")).strip_edges() != node_id:
				continue
			var pos_any: Variant = n.get("pos", null)
			if typeof(pos_any) != TYPE_ARRAY:
				return
			var pos: Array = pos_any
			if pos.size() < 2:
				return
			var x: float = float(pos[0]) + delta_layout.x
			var y: float = float(pos[1]) + delta_layout.y
			if _snap_enabled:
				var gs: float = max(_grid_size, 1.0)
				x = snapped(x, gs)
				y = snapped(y, gs)
			n["pos"] = [x, y]
			_nodes[i] = n
			queue_redraw()
			node_moved.emit(node_id, [x, y])

func _resolve_frame_card_overlaps(moved_node_id: String) -> void:
	# Only meaningful for card-mode SynDoc frames.
	var moved_id := String(moved_node_id).strip_edges()
	if moved_id.is_empty():
		return
	var moved_any: Variant = _find_node_by_id(moved_id)
	if typeof(moved_any) != TYPE_DICTIONARY:
		return
	var moved: Dictionary = moved_any
	if not _node_is_syndoc_frame(moved):
		return

	var denom: float = max(_fit_scale * _zoom, 0.00001)
	var zoom_ui: float = clamp(_zoom, 0.75, 2.0)
	var half_size_layout: Vector2 = (_frame_card_size_px * zoom_ui * 0.5) / denom
	var margin_layout: float = (_FRAME_CARD_SEPARATION_PX * zoom_ui) / denom

	var pos_any: Variant = moved.get("pos", null)
	if typeof(pos_any) != TYPE_ARRAY:
		return
	var pos_arr: Array = pos_any
	if pos_arr.size() < 2:
		return
	var moved_pos := Vector2(float(pos_arr[0]), float(pos_arr[1]))

	# If snapping is enabled, start from a snapped position and keep snapped after adjustments.
	if _snap_enabled:
		var gs0: float = max(_grid_size, 1.0)
		moved_pos.x = snappedf(moved_pos.x, gs0)
		moved_pos.y = snappedf(moved_pos.y, gs0)

	# Iterate a few times to resolve chain overlaps.
	var iter := 0
	while iter < 20:
		var moved_rect := Rect2(moved_pos - half_size_layout, half_size_layout * 2.0)
		var did_adjust := false

		for other_any in _nodes:
			if typeof(other_any) != TYPE_DICTIONARY:
				continue
			var other: Dictionary = other_any
			var other_id := str(other.get("id", "")).strip_edges()
			if other_id.is_empty() or other_id == moved_id:
				continue
			if not _node_is_syndoc_frame(other):
				continue
			var other_pos_any: Variant = other.get("pos", null)
			if typeof(other_pos_any) != TYPE_ARRAY:
				continue
			var other_pos_arr: Array = other_pos_any
			if other_pos_arr.size() < 2:
				continue
			var other_pos := Vector2(float(other_pos_arr[0]), float(other_pos_arr[1]))
			var other_rect := Rect2(other_pos - half_size_layout, half_size_layout * 2.0)
			if not moved_rect.intersects(other_rect):
				continue

			# Minimum translation vector (axis-aligned) to separate equal-size rects.
			var dx: float = moved_pos.x - other_pos.x
			var dy: float = moved_pos.y - other_pos.y
			# Explicit typing avoids Godot's "cannot infer type" analyzer warnings for numeric ops.
			# Include an explicit separation margin so "resolved" does not still visually overlap.
			var overlap_x: float = (half_size_layout.x * 2.0 + margin_layout) - absf(dx)
			var overlap_y: float = (half_size_layout.y * 2.0 + margin_layout) - absf(dy)
			if overlap_x <= 0.0 or overlap_y <= 0.0:
				continue

			if overlap_x < overlap_y:
				# Break ties deterministically when dx == 0 to avoid getting "stuck".
				var sx := 1.0 if dx > 0.00001 else (-1.0 if dx < -0.00001 else 1.0)
				moved_pos.x += sx * overlap_x
			else:
				var sy := 1.0 if dy > 0.00001 else (-1.0 if dy < -0.00001 else 1.0)
				moved_pos.y += sy * overlap_y
			if _snap_enabled:
				var gs1: float = max(_grid_size, 1.0)
				moved_pos.x = snappedf(moved_pos.x, gs1)
				moved_pos.y = snappedf(moved_pos.y, gs1)
			did_adjust = true
			# Recompute rect against remaining nodes.
			moved_rect = Rect2(moved_pos - half_size_layout, half_size_layout * 2.0)

		if not did_adjust:
			break
		iter += 1

	# Persist to backing node entry and emit update so SynPunkt can write it into the SynDoc model.
	for i in range(_nodes.size()):
		if typeof(_nodes[i]) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = _nodes[i]
		if str(n.get("id", "")).strip_edges() != moved_id:
			continue
		n["pos"] = [moved_pos.x, moved_pos.y]
		_nodes[i] = n
		queue_redraw()
		node_moved.emit(moved_id, [moved_pos.x, moved_pos.y])
		break
		return

func _recompute_bounds() -> void:
	var bounds: Dictionary = EdgelessLayoutUtilsScript.compute_bounds(_nodes, _clusters)
	_has_bounds = bool(bounds.get("has_bounds", false))
	if not _has_bounds:
		return
	_min_xy = bounds.get("min_xy", Vector2.ZERO)
	_max_xy = bounds.get("max_xy", Vector2.ZERO)
	_center_xy = bounds.get("center_xy", Vector2.ZERO)
	_min_z = float(bounds.get("min_z", 0.0))
	_max_z = float(bounds.get("max_z", 0.0))

func _cluster_color(cluster_id: int) -> Color:
	return EdgelessLayoutUtilsScript.cluster_color(cluster_id)
