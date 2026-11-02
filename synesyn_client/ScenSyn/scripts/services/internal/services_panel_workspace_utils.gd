extends RefCounted

const WORKSPACE_STATE_FILENAME := "workspace_state.json"
const WORKSPACE_META_FILENAME := "workspace.json"
const DEFAULT_WORKSPACES_DIRNAME := "Workspaces"
const META_BROWSE_ROOT := "__browse_root__"
const META_PLACEHOLDER := "__placeholder__"

static func workspace_state_path_docs() -> String:
	var cfg_path: String = RuntimeConfig.get_config_path_abs()
	if cfg_path.strip_edges().is_empty():
		return ""
	return cfg_path.get_base_dir().path_join(WORKSPACE_STATE_FILENAME)

static func workspace_state_path_user() -> String:
	return ProjectSettings.globalize_path("user://%s" % WORKSPACE_STATE_FILENAME)

static func load_workspace_state() -> Dictionary:
	var candidates: Array[String] = []
	var docs_path: String = workspace_state_path_docs()
	if not docs_path.strip_edges().is_empty():
		candidates.append(docs_path)
	var user_path: String = workspace_state_path_user()
	if not user_path.strip_edges().is_empty():
		candidates.append(user_path)

	for candidate_path in candidates:
		if not FileAccess.file_exists(candidate_path):
			continue
		var file := FileAccess.open(candidate_path, FileAccess.READ)
		if not file:
			continue
		var raw: String = file.get_as_text()
		file.close()
		var parsed_any: Variant = JSON.parse_string(raw)
		if typeof(parsed_any) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = parsed_any
		if str(data.get("name", "")).strip_edges().is_empty():
			continue
		return data
	return {}

static func workspace_base_root_default() -> String:
	return str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).path_join("Synesyn").path_join(DEFAULT_WORKSPACES_DIRNAME)

static func legacy_workspace_root() -> String:
	return to_native_path(str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).path_join("Synesyn"))

static func save_workspace_state(ws_name: String, slug: String, root_base: String) -> Dictionary:
	var obj := {
		"name": ws_name,
		"slug": slug,
		"root_base": root_base,
		"updated_utc": Time.get_datetime_string_from_system(true),
	}

	# Write only Documents/Synesyn (ADR 0014). Legacy user:// remains a read candidate.
	var docs_path: String = workspace_state_path_docs()
	if not docs_path.strip_edges().is_empty():
		var target_dir: String = docs_path.get_base_dir()
		if not target_dir.strip_edges().is_empty():
			DirAccess.make_dir_recursive_absolute(target_dir)
		var file := FileAccess.open(docs_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(obj, "\t"))
			file.close()

	var boot_write: Dictionary = write_hub_boot_workspace_state(ws_name, slug, root_base)

	var base_root: String = root_base
	if base_root.strip_edges().is_empty():
		base_root = workspace_base_root_default()
	var ws_root: String = base_root.path_join(slug)
	DirAccess.make_dir_recursive_absolute(ws_root)
	var meta_path: String = ws_root.path_join(WORKSPACE_META_FILENAME)
	var meta_file := FileAccess.open(meta_path, FileAccess.WRITE)
	if meta_file:
		meta_file.store_string(JSON.stringify(obj, "\t"))
		meta_file.close()

	return boot_write

static func write_hub_boot_workspace_state(ws_name: String, slug: String, root_base: String) -> Dictionary:
	# Hub loads persisted workspace from Documents/Synesyn/_current_workspace.json.
	# Hub config logic treats "root" as a BASE ROOT and appends slug on startup.
	var docs_root: String = str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).path_join("Synesyn")
	var state_path: String = docs_root.path_join("_current_workspace.json")
	DirAccess.make_dir_recursive_absolute(docs_root)

	var base_root: String = root_base.strip_edges()
	if base_root.is_empty():
		base_root = docs_root.path_join(DEFAULT_WORKSPACES_DIRNAME)

	var obj := {
		"name": ws_name,
		"slug": slug,
		"root": base_root,
		"updated_utc": Time.get_datetime_string_from_system(true),
	}
	var file := FileAccess.open(state_path, FileAccess.WRITE)
	if not file:
		var open_error := FileAccess.get_open_error()
		return {"ok": false, "path": state_path, "error": error_string(open_error)}
	file.store_string(JSON.stringify(obj, "  "))
	file.close()
	return {"ok": true, "path": state_path}

static func extract_workspace_dict(payload: Variant) -> Dictionary:
	if typeof(payload) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = payload as Dictionary
	var workspace_any: Variant = data.get("workspace", null)
	if typeof(workspace_any) == TYPE_DICTIONARY:
		return workspace_any as Dictionary
	var inner_any: Variant = data.get("data", null)
	if typeof(inner_any) == TYPE_DICTIONARY:
		var inner: Dictionary = inner_any as Dictionary
		var workspace2_any: Variant = inner.get("workspace", null)
		if typeof(workspace2_any) == TYPE_DICTIONARY:
			return workspace2_any as Dictionary
	return {}

static func base_root_from_hub_workspace_root(hub_root: String, slug: String) -> String:
	var root_text: String = hub_root.strip_edges()
	if root_text.is_empty():
		return ""
	var slug_text: String = slug.strip_edges()
	var normalized_root: String = root_text.replace("\\", "/").trim_suffix("/")
	var normalized_slug: String = slug_text.replace("\\", "/").trim_suffix("/")
	if not normalized_slug.is_empty():
		var double_suffix: String = "/" + normalized_slug + "/" + normalized_slug
		var single_suffix: String = "/" + normalized_slug
		if normalized_root.ends_with(double_suffix):
			normalized_root = normalized_root.substr(0, normalized_root.length() - double_suffix.length())
		elif normalized_root.ends_with(single_suffix):
			normalized_root = normalized_root.substr(0, normalized_root.length() - single_suffix.length())
	return to_native_path(normalized_root)

static func to_native_path(path_text: String) -> String:
	if OS.has_feature("windows"):
		return path_text.replace("/", "\\")
	return path_text

static func fs_path(path_text: String) -> String:
	return path_text.replace("\\", "/")

static func norm_picker_value(text_value: String) -> String:
	var value: String = text_value.strip_edges()
	value = value.replace("\\", "/").trim_suffix("/")
	if OS.has_feature("windows"):
		value = value.to_lower()
	return value

static func slugify(text_value: String) -> String:
	var result: String = text_value.to_lower().strip_edges()
	var cleaned: String = ""
	var prev_hyphen: bool = true
	for char_text in result:
		if (char_text >= "a" and char_text <= "z") or (char_text >= "0" and char_text <= "9"):
			cleaned += char_text
			prev_hyphen = false
		elif char_text == " " or char_text == "-" or char_text == "_":
			if not prev_hyphen:
				cleaned += "-"
			prev_hyphen = true
	while cleaned.ends_with("-"):
		cleaned = cleaned.substr(0, cleaned.length() - 1)
	return cleaned

static func scan_workspace_slugs(base_root: String) -> Array[String]:
	var out: Array[String] = []
	var root: String = fs_path(base_root.strip_edges())
	if root.is_empty():
		return out
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var all_dirs: Array[String] = []
	while true:
		var dir_name: String = dir.get_next()
		if dir_name.is_empty():
			break
		if not dir.current_is_dir():
			continue
		if dir_name.begins_with("."):
			continue
		all_dirs.append(dir_name)
		var sub: String = root.path_join(dir_name).path_join("substrate")
		var art: String = root.path_join(dir_name).path_join("artifacts")
		var sub2: String = root.path_join(dir_name).path_join(dir_name).path_join("substrate")
		var art2: String = root.path_join(dir_name).path_join(dir_name).path_join("artifacts")
		var meta: String = root.path_join(dir_name).path_join(WORKSPACE_META_FILENAME)
		var meta2: String = root.path_join(dir_name).path_join(dir_name).path_join(WORKSPACE_META_FILENAME)
		if DirAccess.dir_exists_absolute(sub) or DirAccess.dir_exists_absolute(art) or DirAccess.dir_exists_absolute(sub2) or DirAccess.dir_exists_absolute(art2) or FileAccess.file_exists(meta) or FileAccess.file_exists(meta2):
			out.append(dir_name)
	dir.list_dir_end()

	if out.is_empty():
		out = all_dirs
	out.sort()
	return out

static func scan_workspace_records(base_root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root: String = fs_path(base_root.strip_edges())
	if root.is_empty():
		return out
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var dir_name: String = dir.get_next()
		if dir_name.is_empty():
			break
		if not dir.current_is_dir():
			continue
		if dir_name.begins_with("."):
			continue
		var slug: String = dir_name
		var meta_paths: Array[String] = [
			root.path_join(slug).path_join(WORKSPACE_META_FILENAME),
			root.path_join(slug).path_join(slug).path_join(WORKSPACE_META_FILENAME),
		]
		var display_name: String = ""
		for meta_path in meta_paths:
			if FileAccess.file_exists(meta_path):
				var file := FileAccess.open(meta_path, FileAccess.READ)
				if file:
					var raw: String = file.get_as_text()
					file.close()
					var parsed_any: Variant = JSON.parse_string(raw)
					if typeof(parsed_any) == TYPE_DICTIONARY:
						var meta_data: Dictionary = parsed_any
						display_name = str(meta_data.get("name", "")).strip_edges()
						break
		out.append({"slug": slug, "name": display_name})
	dir.list_dir_end()
	return out
