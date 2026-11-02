## Purpose: Minimal unified diff parser + applier (editor-time writeback).
##
## Supports:
## - multi-file unified diffs (---/+++ headers)
## - @@ -old_start,old_count +new_start,new_count @@ hunks
## - lines prefixed with ' ', '+', '-'
##
## Notes:
## - This is intentionally strict (fails fast on mismatch) to keep writeback safe.
## - Designed for editor-only use: writing to `res://` is not valid in exported builds.
@tool
extends RefCounted
class_name UnifiedDiffApplier

static func _parse_range(r: String, prefix: String) -> Dictionary:
	var rr := String(r)
	if not rr.begins_with(prefix):
		return {"ok": false, "error": "Invalid range '%s' (expected %s…)" % [rr, prefix]}
	rr = rr.substr(1)
	var start := 0
	var count := 1
	if rr.find(",") != -1:
		var sp := rr.split(",", false)
		if sp.size() != 2:
			return {"ok": false, "error": "Invalid range: %s" % r}
		start = int(sp[0])
		count = int(sp[1])
	else:
		start = int(rr)
		count = 1
	return {"ok": true, "start": start, "count": count}

static func parse_unified_diff(diff_text: String) -> Dictionary:
	var text := String(diff_text).replace("\r\n", "\n")
	var lines := text.split("\n", false)
	var files: Array = []
	var cur: Dictionary = {}
	var cur_hunk: Dictionary = {}

	for raw in lines:
		var line := String(raw)
		if line.begins_with("--- "):
			# flush current hunk
			if not cur_hunk.is_empty():
				if not cur.has("hunks"):
					cur["hunks"] = []
				cur["hunks"].append(cur_hunk)
				cur_hunk = {}
			# flush current file
			if not cur.is_empty():
				files.append(cur)
			cur = {"old_header": line, "hunks": []}
			continue
		if line.begins_with("+++ "):
			if cur.is_empty():
				# Diff starts with +++ without ---; still accept.
				cur = {"hunks": []}
			cur["new_header"] = line
			var p := line.substr(4).strip_edges()
			# Trim leading a/ or b/ when present.
			if p.begins_with("a/") or p.begins_with("b/"):
				p = p.substr(2)
			cur["path"] = p
			continue
		if line.begins_with("@@ "):
			# flush previous hunk for this file
			if not cur_hunk.is_empty():
				if not cur.has("hunks"):
					cur["hunks"] = []
				cur["hunks"].append(cur_hunk)
				cur_hunk = {}
			# Parse hunk header like: @@ -l,s +l,s @@
			var parts := line.split(" ")
			if parts.size() < 3:
				return {"ok": false, "error": "Invalid hunk header: %s" % line}
			var old_part := parts[1] # -start,count
			var new_part := parts[2] # +start,count
			var o := _parse_range(old_part, "-")
			if not bool(o.get("ok", false)):
				return {"ok": false, "error": o.get("error", "Invalid old range")}
			var n := _parse_range(new_part, "+")
			if not bool(n.get("ok", false)):
				return {"ok": false, "error": n.get("error", "Invalid new range")}

			cur_hunk = {
				"header": line,
				"old_start": int(o.get("start", 1)),
				"old_count": int(o.get("count", 1)),
				"new_start": int(n.get("start", 1)),
				"new_count": int(n.get("count", 1)),
				"lines": []
			}
			continue

		# Hunk lines
		if not cur_hunk.is_empty():
			if line == "\\ No newline at end of file":
				continue
			# Unified diff hunk lines always have a prefix. If we encounter an empty raw line,
			# treat it as a context empty line.
			if line.length() == 0:
				(cur_hunk["lines"] as Array).append({"op": " ", "text": ""})
				continue
			var op := line.left(1)
			if op == " " or op == "+" or op == "-":
				(cur_hunk["lines"] as Array).append({"op": op, "text": line.substr(1)})
				continue
			# Otherwise ignore (could be diff metadata)
			continue

	# End
	if not cur_hunk.is_empty():
		if not cur.has("hunks"):
			cur["hunks"] = []
		cur["hunks"].append(cur_hunk)
		cur_hunk = {}
	if not cur.is_empty():
		files.append(cur)

	if files.is_empty():
		return {"ok": false, "error": "No file sections found in diff."}
	for f in files:
		if not (f is Dictionary) or str((f as Dictionary).get("path", "")).strip_edges().is_empty():
			return {"ok": false, "error": "Diff is missing file path (need +++ header)."}
	return {"ok": true, "files": files}

static func _resolve_to_os_path(path: String) -> String:
	var p := String(path).strip_edges()
	if p.is_empty():
		return ""
	if p.begins_with("res://"):
		return ProjectSettings.globalize_path(p)
	return p

static func dry_run_apply(diff_text: String) -> Dictionary:
	return _apply_internal(diff_text, false, "")

static func apply_with_backups(diff_text: String, backup_root_dir: String) -> Dictionary:
	return _apply_internal(diff_text, true, backup_root_dir)

static func _apply_internal(diff_text: String, do_write: bool, backup_root_dir: String) -> Dictionary:
	var parsed := parse_unified_diff(diff_text)
	if not bool(parsed.ok):
		return parsed
	var files: Array = parsed.files
	var results: Array = []
	var backups: Array = []

	for f_any in files:
		var f: Dictionary = f_any
		var logical_path := str(f.get("path", "")).strip_edges()
		var os_path := _resolve_to_os_path(logical_path)
		if os_path.is_empty():
			return {"ok": false, "error": "Could not resolve path: %s" % logical_path}
		if not FileAccess.file_exists(os_path):
			return {"ok": false, "error": "Target file not found: %s" % os_path}
		var original_text := ""
		var fin := FileAccess.open(os_path, FileAccess.READ)
		if not fin:
			return {"ok": false, "error": "Failed to open for read: %s" % os_path}
		original_text = fin.get_as_text()
		fin.close()
		var had_trailing_newline := original_text.ends_with("\n")
		var current_lines := original_text.replace("\r\n", "\n").split("\n", false)

		# Backup first (if writing)
		var backup_path := ""
		if do_write:
			var backup_base := String(backup_root_dir).strip_edges()
			if backup_base.is_empty():
				return {"ok": false, "error": "backup_root_dir is required when do_write=true"}
			var safe_name := logical_path.replace("res://", "res__/").replace(":", "_").replace("\\", "/")
			backup_path = backup_base.path_join(safe_name)
			var backup_dir := backup_path.get_base_dir()
			DirAccess.make_dir_recursive_absolute(backup_dir)
			var fb := FileAccess.open(backup_path, FileAccess.WRITE)
			if not fb:
				return {"ok": false, "error": "Failed to write backup: %s" % backup_path}
			fb.store_string(original_text)
			fb.close()
			backups.append({"target": logical_path, "target_os": os_path, "backup_os": backup_path})

		var line_offset := 0
		for h_any in (f.get("hunks", []) as Array):
			var h: Dictionary = h_any
			var old_start := int(h.get("old_start", 1))
			var idx := (old_start - 1) + line_offset
			if idx < 0:
				idx = 0
			var h_lines: Array = h.get("lines", [])
			for hl_any in h_lines:
				var hl: Dictionary = hl_any
				var op := str(hl.get("op", " "))
				var t := str(hl.get("text", ""))
				match op:
					" ":
						if idx >= current_lines.size():
							return {"ok": false, "error": "Context line out of range in %s" % logical_path}
						if String(current_lines[idx]) != t:
							return {"ok": false, "error": "Context mismatch in %s at line %d.\nExpected: %s\nGot: %s" % [logical_path, idx + 1, t, current_lines[idx]]}
						idx += 1
					"-":
						if idx >= current_lines.size():
							return {"ok": false, "error": "Removal out of range in %s" % logical_path}
						if String(current_lines[idx]) != t:
							return {"ok": false, "error": "Removal mismatch in %s at line %d.\nExpected: %s\nGot: %s" % [logical_path, idx + 1, t, current_lines[idx]]}
						current_lines.remove_at(idx)
						line_offset -= 1
					"+":
						current_lines.insert(idx, t)
						idx += 1
						line_offset += 1
					_:
						# ignore
						pass

		var new_text := "\n".join(current_lines)
		if had_trailing_newline:
			new_text += "\n"

		if do_write:
			var fout := FileAccess.open(os_path, FileAccess.WRITE)
			if not fout:
				return {"ok": false, "error": "Failed to open for write: %s" % os_path}
			fout.store_string(new_text)
			fout.close()

		results.append({"path": logical_path, "changed": true, "backup_os": backup_path})

	return {"ok": true, "results": results, "backups": backups}

