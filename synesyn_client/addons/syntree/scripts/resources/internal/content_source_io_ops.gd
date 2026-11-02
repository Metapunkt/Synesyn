## Purpose: Internal file IO helpers for ContentSourceResource (JSON read/write, mkdir, delete; no signals)
extends RefCounted

func _to_abs_path(p: String) -> String:
	# DirAccess.*_absolute APIs expect absolute filesystem paths.
	var s := String(p).strip_edges().replace("\\", "/")
	if s.begins_with("res://") or s.begins_with("user://"):
		return ProjectSettings.globalize_path(s)
	return s

func ensure_dir_for_file_path(file_path: String) -> Dictionary:
	# Returns: { success: bool, error: String, dir_path: String }
	var p := String(file_path).strip_edges().replace("\\", "/")
	if p.is_empty():
		return {"success": false, "error": "Empty file_path", "dir_path": ""}
	var parts := p.rsplit("/", true, 1)
	if parts.size() < 2:
		return {"success": true, "error": "", "dir_path": ""}
	var dir_path := String(parts[0]).strip_edges()
	if dir_path.is_empty():
		return {"success": true, "error": "", "dir_path": ""}

	# Godot 4: prefer absolute mkdir for stability.
	var abs_dir := _to_abs_path(dir_path)
	var err := DirAccess.make_dir_recursive_absolute(abs_dir)

	if err != OK:
		return {"success": false, "error": "Could not create directory %s (abs=%s, err=%s)" % [dir_path, abs_dir, err], "dir_path": dir_path}
	return {"success": true, "error": "", "dir_path": dir_path}

func write_text_file(file_path: String, text: String) -> Dictionary:
	# Returns: { success: bool, error: String }
	var p := String(file_path).strip_edges().replace("\\", "/")
	if p.is_empty():
		return {"success": false, "error": "Empty file_path"}
	var mkdir_res: Dictionary = ensure_dir_for_file_path(p)
	if not bool(mkdir_res.get("success", false)):
		return {"success": false, "error": str(mkdir_res.get("error", "mkdir failed"))}

	var f := FileAccess.open(p, FileAccess.WRITE)
	if not f:
		return {"success": false, "error": "Failed to open file for writing: %s (open_err=%s)" % [p, FileAccess.get_open_error()]}
	f.store_string(text)
	f.flush()
	var werr := f.get_error()
	f.close()
	if werr != OK:
		return {"success": false, "error": "Error writing file: %s (err=%s)" % [p, werr]}
	return {"success": true, "error": ""}

func write_json_file(file_path: String, data: Dictionary, indent: String = "  ") -> Dictionary:
	# Returns: { success: bool, error: String, json_text: String }
	var json_text := JSON.stringify(data, indent)
	if json_text.is_empty():
		return {"success": false, "error": "Failed to stringify JSON", "json_text": ""}
	var res: Dictionary = write_text_file(file_path, json_text)
	if not bool(res.get("success", false)):
		return {"success": false, "error": str(res.get("error", "write failed")), "json_text": json_text}
	return {"success": true, "error": "", "json_text": json_text}

func read_json_file(file_path: String) -> Dictionary:
	# Returns: { success: bool, error: String, data: Variant }
	var p := String(file_path).strip_edges().replace("\\", "/")
	if p.is_empty():
		return {"success": false, "error": "Empty file_path", "data": null}
	if not FileAccess.file_exists(p):
		return {"success": false, "error": "File does not exist: %s" % p, "data": null}
	var f := FileAccess.open(p, FileAccess.READ)
	if not f:
		return {"success": false, "error": "Failed to open file for read: %s (open_err=%s)" % [p, FileAccess.get_open_error()], "data": null}
	var content := f.get_as_text()
	f.close()
	var json := JSON.new()
	var perr := json.parse(content)
	if perr != OK:
		return {"success": false, "error": "Failed to parse JSON: %s" % json.get_error_message(), "data": null}
	return {"success": true, "error": "", "data": json.get_data()}

func remove_file(file_path: String) -> Dictionary:
	# Returns: { success: bool, error: String }
	var p := String(file_path).strip_edges().replace("\\", "/")
	if p.is_empty():
		return {"success": false, "error": "Empty file_path"}
	if not FileAccess.file_exists(p):
		return {"success": true, "error": ""} # treat as already removed

	# Prefer absolute remove if available.
	var abs_p := _to_abs_path(p)
	var err_abs := DirAccess.remove_absolute(abs_p)
	if err_abs != OK:
		return {"success": false, "error": "Failed to delete file: %s (abs=%s, err=%s)" % [p, abs_p, err_abs]}
	return {"success": true, "error": ""}

	var parts := p.rsplit("/", true, 1)
	if parts.size() < 2:
		return {"success": false, "error": "Cannot split dir/file from path: %s" % p}
	var dir_path := String(parts[0]).strip_edges()
	var file_name := String(parts[1]).strip_edges()
	var dir := DirAccess.open(dir_path)
	if not dir:
		return {"success": false, "error": "Failed to open directory for delete: %s (open_err=%s)" % [dir_path, DirAccess.get_open_error()]}
	var err := dir.remove(file_name)
	if err != OK:
		return {"success": false, "error": "Failed to delete file: %s (err=%s)" % [p, err]}
	return {"success": true, "error": ""}


