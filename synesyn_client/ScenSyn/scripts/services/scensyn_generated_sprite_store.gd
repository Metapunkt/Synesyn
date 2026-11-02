extends RefCounted
class_name ScenSynGeneratedSpriteStore

# Materializes (copies) generated image artifacts into a stable, runtime-friendly
# sprite directory under the active workspace:
#   <workspace_root>/scensyn/sprites_generated/<collection>/<scenario>/<character>/<animation_frames>/0001.png
#
# This is intentionally separate from the Hub artifact store (`artifacts/`), which
# remains the immutable provenance/history source of truth.

const RuntimeConfigScript = preload("res://addons/synesyn_core/scripts/runtime_config.gd")


static func _workspace_state_candidates_abs() -> Array[String]:
	var candidates: Array[String] = []
	var cfg_path_abs: String = str(RuntimeConfigScript.get_config_path_abs()).strip_edges()
	if not cfg_path_abs.is_empty():
		candidates.append(cfg_path_abs.get_base_dir().path_join("workspace_state.json"))
	candidates.append(ProjectSettings.globalize_path("user://workspace_state.json"))
	return candidates


static func _load_workspace_state() -> Dictionary:
	for p in _workspace_state_candidates_abs():
		if p.strip_edges().is_empty() or (not FileAccess.file_exists(p)):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if not f:
			continue
		var raw: String = f.get_as_text()
		f.close()
		var parsed_any: Variant = JSON.parse_string(raw)
		if typeof(parsed_any) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = parsed_any
		# Expected shape: {name, slug, root_base, ...}
		if str(d.get("slug", "")).strip_edges().is_empty():
			continue
		return d
	return {}


static func get_workspace_root_abs() -> String:
	var st: Dictionary = _load_workspace_state()
	if st.is_empty():
		return ""
	var base_root: String = str(st.get("root_base", "")).strip_edges()
	var slug: String = str(st.get("slug", "")).strip_edges()
	if base_root.is_empty() or slug.is_empty():
		return ""
	var ws_root: String = base_root.path_join(slug)
	return ws_root.replace("\\", "/")


static func get_sprites_generated_root_abs() -> String:
	var ws_root: String = get_workspace_root_abs()
	if ws_root.is_empty():
		return ""
	return ws_root.path_join("scensyn").path_join("sprites_generated").replace("\\", "/")


static func uri_to_abs_path(uri: String) -> String:
	var u: String = String(uri).strip_edges()
	if u.is_empty():
		return ""
	if not u.begins_with("file:"):
		return ""
	var path := u
	# Replace file:/// with "/" so Linux absolute paths keep their leading slash.
	# file:///home/user/path → /home/user/path  (Linux)
	# file:///C:/path       → /C:/path          (Windows, normalized below)
	path = path.replace("file:///", "/")
	path = path.replace("file://", "")
	# Normalize Windows drive letter: /C:/path → C:/path
	if path.length() > 2 and path[0] == "/" and path[2] == ":":
		path = path.substr(1)
	return path.replace("\\", "/")


static func _ensure_dir_abs(dir_abs: String) -> void:
	var d: String = String(dir_abs).strip_edges()
	if d.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(d)


static func _copy_file_abs(src_abs: String, dst_abs: String) -> bool:
	var src: String = String(src_abs).strip_edges().replace("\\", "/")
	var dst: String = String(dst_abs).strip_edges().replace("\\", "/")
	if src.is_empty() or dst.is_empty():
		return false
	if not FileAccess.file_exists(src):
		return false
	_ensure_dir_abs(dst.get_base_dir())
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(src)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if not f:
		return false
	f.store_buffer(bytes)
	f.close()
	return true


func materialize_image_artifact(
	hub: HubSubstrateClient,
	image_artifact_id: String,
	collection_id: String,
	scenario_key: String,
	character_slug: String,
	animation_frames: String,
	filename: String = "0001.png",
	transparent_background: bool = false
) -> Dictionary:
	if hub == null or (not is_instance_valid(hub)):
		return {"ok": false, "error": "hub_missing"}
	var aid: String = str(image_artifact_id).strip_edges()
	if aid.is_empty():
		return {"ok": false, "error": "image_artifact_id_missing"}

	var rec_res: Dictionary = await hub.get_artifact_record(aid)
	if not (rec_res.get("ok", false) == true):
		return {"ok": false, "error": "artifact_record_fetch_failed", "details": rec_res}
	var rec_any: Variant = rec_res.get("record", {})
	var rec: Dictionary = rec_any if typeof(rec_any) == TYPE_DICTIONARY else {}
	var uri: String = str(rec.get("uri", "")).strip_edges()
	var src_abs: String = uri_to_abs_path(uri)
	if src_abs.is_empty():
		return {"ok": false, "error": "artifact_uri_not_file", "uri": uri, "record": rec}
	if not FileAccess.file_exists(src_abs):
		return {"ok": false, "error": "artifact_file_missing", "src_abs": src_abs, "uri": uri}

	# Prefer hub-reported workspace root (authoritative for current selection).
	# Fall back to persisted workspace_state.json only if needed.
	var ws_root_abs: String = ""
	if hub.has_method("_get_workspace_root"):
		ws_root_abs = str(await hub.call("_get_workspace_root")).strip_edges()
	if ws_root_abs.is_empty():
		ws_root_abs = get_workspace_root_abs()
	if ws_root_abs.is_empty():
		return {"ok": false, "error": "workspace_root_unknown"}
	ws_root_abs = ws_root_abs.replace("\\", "/")

	var root_abs: String = ws_root_abs.path_join("scensyn").path_join("sprites_generated").replace("\\", "/")

	var col: String = str(collection_id).strip_edges()
	var s: String = str(scenario_key).strip_edges()
	var c: String = str(character_slug).strip_edges()
	var a: String = str(animation_frames).strip_edges()
	if col.is_empty():
		col = "default"
	if s.is_empty():
		s = "default"
	if c.is_empty():
		c = "unknown"
	if a.is_empty():
		a = "idle"

	var dst_dir_abs: String = root_abs.path_join(col).path_join(s).path_join(c).path_join(a)
	var dst_abs: String = dst_dir_abs.path_join(str(filename).strip_edges())

	var ok: bool = false
	if transparent_background:
		ok = _copy_with_white_key_to_alpha(src_abs, dst_abs)
	else:
		ok = _copy_file_abs(src_abs, dst_abs)
	if not ok:
		return {"ok": false, "error": "copy_failed", "src_abs": src_abs, "dst_abs": dst_abs, "transparent_background": transparent_background}
	return {"ok": true, "src_abs": src_abs, "dst_abs": dst_abs, "artifact_id": aid, "record": rec}


static func _copy_with_white_key_to_alpha(src_abs: String, dst_abs: String) -> bool:
	var src: String = String(src_abs).strip_edges().replace("\\", "/")
	var dst: String = String(dst_abs).strip_edges().replace("\\", "/")
	if src.is_empty() or dst.is_empty():
		return false
	if not FileAccess.file_exists(src):
		return false
	_ensure_dir_abs(dst.get_base_dir())

	var img: Image = Image.new()
	var err: int = img.load(src)
	if err != OK:
		# Fallback to raw copy if image can't be loaded.
		return _copy_file_abs(src, dst)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	# Simple "white background -> transparent" key.
	# Works best when the prompt enforces a plain white background.
	const HI := 0.97
	const LO := 0.88
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y in range(h):
		for x in range(w):
			var col: Color = img.get_pixel(x, y)
			var minc: float = minf(col.r, minf(col.g, col.b))
			var a: float = col.a
			if minc >= HI:
				a = 0.0
			elif minc >= LO:
				# Soft edge.
				var t: float = (minc - LO) / (HI - LO)
				a = (1.0 - t) * a
			# Preserve RGB; only change alpha.
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))

	var save_err: int = img.save_png(dst)
	if save_err != OK:
		# Fallback: at least copy the original.
		return _copy_file_abs(src, dst)
	return true


func materialize_image_artifact_ids(
	hub: HubSubstrateClient,
	image_artifact_ids: Array,
	collection_id: String,
	scenario_key: String,
	character_slug: String,
	animation_frames: String,
	start_index: int = 1,
	transparent_background: bool = false
) -> Dictionary:
	if typeof(image_artifact_ids) != TYPE_ARRAY or image_artifact_ids.is_empty():
		return {"ok": false, "error": "image_artifact_ids_required"}
	var out_paths: Array[String] = []
	var ok_all := true
	var idx: int = int(start_index)
	for aid_any in image_artifact_ids:
		var aid: String = str(aid_any).strip_edges()
		if aid.is_empty():
			continue
		var fname: String = "%04d.png" % idx
		var res: Dictionary = await materialize_image_artifact(hub, aid, collection_id, scenario_key, character_slug, animation_frames, fname, transparent_background)
		if bool(res.get("ok", false)):
			out_paths.append(str(res.get("dst_abs", "")).strip_edges())
		else:
			ok_all = false
		idx += 1
	return {"ok": ok_all, "paths": out_paths, "count": out_paths.size()}
