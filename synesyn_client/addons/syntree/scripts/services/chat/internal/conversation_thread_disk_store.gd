## Purpose: Internal disk storage helper for ConversationManager (threads dir + load/save thread JSON).
extends RefCounted

const RuntimeConfigScript = preload("res://addons/synesyn_core/scripts/runtime_config.gd")
const ThreadScopeUtils = preload("res://addons/synesyn_core/scripts/thread_scope_utils.gd")
const _MAX_THREAD_FILE_STEM_LEN := 96

func apply_runtime_storage_root_override() -> String:
	# Returns absolute Documents/Synesyn root (or "" only if Documents is unavailable).
	var root_dir := String(RuntimeConfigScript.get_storage_root_dir()).strip_edges()
	if root_dir.is_empty():
		return ""
	return root_dir.replace("\\", "/")

func compute_threads_dir(thread_scope: String, storage_root_override: String) -> String:
	var scope := ThreadScopeUtils.sanitize_scope(String(thread_scope))
	var root := String(storage_root_override).strip_edges()
	if not root.is_empty():
		# Example: C:/Users/<you>/Documents/Synesyn/synesyn/conversation_threads/<scope>/
		return root.path_join("synesyn").path_join("conversation_threads").path_join(scope)
	return RuntimeConfigScript.get_conversation_threads_dir().path_join(scope)

func has_any_thread_files(threads_dir: String) -> bool:
	var base_dir := String(threads_dir).strip_edges()
	if base_dir.is_empty():
		return false

	# Ensure directory exists.
	var abs_dir := _to_abs_path(base_dir)
	if abs_dir.is_empty():
		return false
	var mkerr := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mkerr != OK:
		return false

	var dir := DirAccess.open(base_dir)
	if not dir:
		return false

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			dir.list_dir_end()
			return true
		file_name = dir.get_next()
	dir.list_dir_end()
	return false

func _to_abs_path(p: String) -> String:
	var s := String(p).strip_edges().replace("\\", "/")
	if s.is_empty():
		return ""
	if s.begins_with("res://") or s.begins_with("user://"):
		return ProjectSettings.globalize_path(s)
	return s

func _safe_thread_file_stem(thread_id: String) -> String:
	var tid := String(thread_id).strip_edges()
	if tid.is_empty():
		return "thread"
	var cleaned := ""
	for ch in tid:
		var code := ch.unicode_at(0)
		var is_alpha := (code >= 97 and code <= 122) or (code >= 65 and code <= 90)
		var is_num := (code >= 48 and code <= 57)
		if is_alpha or is_num:
			cleaned += ch.to_lower()
		elif ch in ["-", "_", "."]:
			cleaned += ch
		else:
			cleaned += "_"
	while cleaned.contains("__"):
		cleaned = cleaned.replace("__", "_")
	cleaned = cleaned.strip_edges().trim_prefix("_").trim_suffix("_")
	if cleaned.is_empty():
		cleaned = "thread"
	var digest := tid.sha256_text().substr(0, 16)
	var max_prefix_len := max(8, _MAX_THREAD_FILE_STEM_LEN - digest.length() - 2)
	if cleaned.length() > max_prefix_len:
		cleaned = cleaned.substr(0, max_prefix_len)
	while cleaned.ends_with("_") or cleaned.ends_with("-") or cleaned.ends_with("."):
		cleaned = cleaned.substr(0, cleaned.length() - 1)
	if cleaned.is_empty():
		cleaned = "thread"
	return "%s__%s" % [cleaned, digest]

func _thread_path_for_id(threads_dir: String, thread_id: String) -> String:
	var base_dir := String(threads_dir).strip_edges()
	var tid := String(thread_id).strip_edges()
	if base_dir.is_empty() or tid.is_empty():
		return ""
	return base_dir.path_join(_safe_thread_file_stem(tid) + ".json")

func _legacy_thread_path_for_id(threads_dir: String, thread_id: String) -> String:
	var base_dir := String(threads_dir).strip_edges()
	var tid := String(thread_id).strip_edges()
	if base_dir.is_empty() or tid.is_empty():
		return ""
	return base_dir.path_join(tid + ".json")

func _ensure_dir_for_file_path(file_path: String) -> Dictionary:
	var p := String(file_path).strip_edges().replace("\\", "/")
	if p.is_empty():
		return {"success": false, "error": "Empty file_path"}
	var parts := p.rsplit("/", true, 1)
	if parts.size() < 2:
		return {"success": true, "error": ""}
	var dir_path := String(parts[0]).strip_edges()
	if dir_path.is_empty():
		return {"success": true, "error": ""}

	var abs_dir := _to_abs_path(dir_path)
	if abs_dir.is_empty():
		return {"success": false, "error": "Failed to resolve directory path: %s" % dir_path}
	var err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if err != OK:
		return {"success": false, "error": "Failed to create directory: %s (err=%s)" % [dir_path, err]}
	return {"success": true, "error": ""}

func save_thread(threads_dir: String, thread_id: String, thread_data: Dictionary) -> Dictionary:
	var tid := String(thread_id).strip_edges()
	if tid.is_empty():
		return {"success": false, "error": "Thread id is empty"}
	var base_dir := String(threads_dir).strip_edges()
	if base_dir.is_empty():
		return {"success": false, "error": "threads_dir is empty"}

	var thread_path := _thread_path_for_id(base_dir, tid)
	var mkdir_res: Dictionary = _ensure_dir_for_file_path(thread_path)
	if not bool(mkdir_res.get("success", false)):
		return {"success": false, "error": str(mkdir_res.get("error", "mkdir failed"))}

	var messages_to_save_any: Variant = thread_data.get("messages", [])
	var messages_to_save: Array = messages_to_save_any if typeof(messages_to_save_any) == TYPE_ARRAY else []
	var payload := {
		"name": tid,
		"messages": messages_to_save,
		"last_updated": Time.get_unix_time_from_system(),
		"_file_stem": _safe_thread_file_stem(tid),
	}
	var f := FileAccess.open(thread_path, FileAccess.WRITE)
	if not f:
		return {"success": false, "error": "Failed to open file for writing: %s (open_err=%s)" % [thread_path, FileAccess.get_open_error()]}
	f.store_string(JSON.stringify(payload, "", true))
	f.close()
	return {"success": true, "error": "", "thread_path": thread_path}

func load_threads(threads_dir: String) -> Dictionary:
	var base_dir := String(threads_dir).strip_edges()
	if base_dir.is_empty():
		return {"success": false, "error": "threads_dir is empty", "threads": {}}

	# Ensure directory exists.
	var abs_dir := _to_abs_path(base_dir)
	if abs_dir.is_empty():
		return {"success": false, "error": "Failed to resolve threads_dir: %s" % base_dir, "threads": {}}
	var mkerr := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mkerr != OK:
		return {"success": false, "error": "Failed to create threads directory (err=%s)" % mkerr, "threads": {}}

	var dir := DirAccess.open(base_dir)
	if not dir:
		return {"success": false, "error": "Failed to open threads directory: %s" % base_dir, "threads": {}}

	var out: Dictionary = {}
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var file_tid := file_name.get_basename()
			var thread_path := base_dir.path_join(file_name)
			var raw := FileAccess.get_file_as_string(thread_path)
			if raw.strip_edges().is_empty():
				file_name = dir.get_next()
				continue
			var any: Variant = JSON.parse_string(raw)
			if typeof(any) == TYPE_DICTIONARY:
				var d: Dictionary = any
				var logical_id := str(d.get("name", file_tid)).strip_edges()
				if logical_id.is_empty():
					logical_id = file_tid
				if not d.has("name"):
					d["name"] = logical_id
				d["_thread_id"] = logical_id
				# Normalize messages.
				var msgs_any: Variant = d.get("messages", [])
				if typeof(msgs_any) != TYPE_ARRAY:
					d["messages"] = []
				out[logical_id] = d
		file_name = dir.get_next()
	dir.list_dir_end()

	return {"success": true, "error": "", "threads": out}

func load_thread(threads_dir: String, thread_id: String) -> Dictionary:
	var base_dir := String(threads_dir).strip_edges()
	var tid := String(thread_id).strip_edges()
	if base_dir.is_empty():
		return {"success": false, "error": "threads_dir is empty", "thread": {}}
	if tid.is_empty():
		return {"success": false, "error": "thread_id is empty", "thread": {}}

	# Ensure directory exists (so callers can rely on it).
	var abs_dir := _to_abs_path(base_dir)
	if abs_dir.is_empty():
		return {"success": false, "error": "Failed to resolve threads_dir: %s" % base_dir, "thread": {}}
	var mkerr := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mkerr != OK:
		return {"success": false, "error": "Failed to create threads directory (err=%s)" % mkerr, "thread": {}}

	var thread_path := _thread_path_for_id(base_dir, tid)
	if not FileAccess.file_exists(thread_path):
		var legacy_thread_path := _legacy_thread_path_for_id(base_dir, tid)
		if FileAccess.file_exists(legacy_thread_path):
			thread_path = legacy_thread_path
		else:
			return {"success": false, "error": "Thread file not found: %s" % thread_path, "thread": {}}
	var raw := FileAccess.get_file_as_string(thread_path)
	if raw.strip_edges().is_empty():
		return {"success": false, "error": "Thread file is empty: %s" % thread_path, "thread": {}}
	var any: Variant = JSON.parse_string(raw)
	if typeof(any) != TYPE_DICTIONARY:
		return {"success": false, "error": "Thread JSON is not a dictionary: %s" % thread_path, "thread": {}}
	var d: Dictionary = any
	if not d.has("name"):
		d["name"] = tid
	d["_thread_id"] = tid
	var msgs_any: Variant = d.get("messages", [])
	if typeof(msgs_any) != TYPE_ARRAY:
		d["messages"] = []
	return {"success": true, "error": "", "thread": d, "thread_path": thread_path}


