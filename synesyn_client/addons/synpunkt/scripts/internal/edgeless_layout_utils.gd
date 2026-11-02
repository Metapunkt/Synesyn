extends RefCounted
class_name EdgelessLayoutUtils

static func resolve_image_uri(block: Dictionary, image_uri_map: Dictionary) -> String:
	var direct_uri := str(block.get("uri", block.get("src", ""))).strip_edges()
	if not direct_uri.is_empty():
		return direct_uri
	var aid := str(block.get("artifact_id", block.get("image_artifact_id", block.get("id", "")))).strip_edges()
	if aid.is_empty():
		aid = str(block.get("image_id", "")).strip_edges()
	if not aid.is_empty() and image_uri_map.has(aid):
		return str(image_uri_map.get(aid, "")).strip_edges()
	if image_uri_map.has(direct_uri):
		return str(image_uri_map.get(direct_uri, "")).strip_edges()
	return ""


static func load_texture_from_uri(uri: String) -> Texture2D:
	var u := String(uri).strip_edges()
	if u.is_empty():
		return null
	if u.begins_with("res://"):
		var tex_any: Variant = load(u)
		return tex_any as Texture2D if tex_any is Texture2D else null
	if u.begins_with("file://"):
		var path := u
		path = path.replace("file:///", "/")
		path = path.replace("file://", "")
		if path.length() > 2 and path[0] == "/" and path[2] == ":":
			path = path.substr(1)
		path = path.uri_decode()
		if not FileAccess.file_exists(path):
			var win_path := path.replace("/", "\\")
			if FileAccess.file_exists(win_path):
				path = win_path
			else:
				return null
		var img := Image.new()
		var err := img.load(path)
		if err != OK:
			return null
		return ImageTexture.create_from_image(img)
	return null


static func find_node_by_id(nodes: Array, node_id: String) -> Variant:
	for n_any in nodes:
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		if str(n.get("id", "")).strip_edges() == node_id:
			return n
	return null


static func find_any_by_id(nodes: Array, clusters: Array, node_id: String) -> Variant:
	var n := find_node_by_id(nodes, node_id)
	if n != null:
		return n
	for c_any in clusters:
		if typeof(c_any) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_any
		if str(c.get("id", "")).strip_edges() == node_id:
			return c
	return null


static func compute_bounds(nodes: Array, clusters: Array) -> Dictionary:
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for n_any in nodes:
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
		min_x = min(min_x, x)
		max_x = max(max_x, x)
		min_y = min(min_y, y)
		max_y = max(max_y, y)
		var z: float = float(n.get("z", 0.0))
		min_z = min(min_z, z)
		max_z = max(max_z, z)
	for c_any in clusters:
		if typeof(c_any) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_any
		var pos_any2: Variant = c.get("pos", null)
		if typeof(pos_any2) != TYPE_ARRAY:
			continue
		var pos2: Array = pos_any2
		if pos2.size() < 2:
			continue
		var x2: float = float(pos2[0])
		var y2: float = float(pos2[1])
		min_x = min(min_x, x2)
		max_x = max(max_x, x2)
		min_y = min(min_y, y2)
		max_y = max(max_y, y2)
		var z2: float = float(c.get("z", 0.0))
		min_z = min(min_z, z2)
		max_z = max(max_z, z2)
	if min_x == INF or min_y == INF:
		return {"has_bounds": false}
	var min_xy := Vector2(min_x, min_y)
	var max_xy := Vector2(max_x, max_y)
	return {
		"has_bounds": true,
		"min_xy": min_xy,
		"max_xy": max_xy,
		"center_xy": (min_xy + max_xy) * 0.5,
		"min_z": min_z if min_z != INF else 0.0,
		"max_z": max_z if max_z != -INF else 0.0,
	}


static func cluster_color(cluster_id: int) -> Color:
	var palette: Array = [
		Color(0.30, 0.80, 0.90, 1.0),
		Color(0.85, 0.45, 0.95, 1.0),
		Color(0.95, 0.65, 0.30, 1.0),
		Color(0.35, 0.90, 0.55, 1.0),
		Color(0.95, 0.35, 0.40, 1.0),
		Color(0.55, 0.70, 0.95, 1.0),
		Color(0.95, 0.90, 0.35, 1.0),
	]
	if cluster_id < 0:
		return Color(0.75, 0.75, 0.8, 1.0)
	return palette[cluster_id % palette.size()]
