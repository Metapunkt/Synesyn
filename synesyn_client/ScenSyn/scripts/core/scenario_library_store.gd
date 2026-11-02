extends RefCounted
class_name ScenarioLibraryStore

## Shared draft and library persistence for session-type scenario contracts.
##
## Each contract keeps its own normalize(): that is the trust boundary for
## incoming data, and it stays session-type-owned. File layout, id minting and
## value coercion live here so Workshop Catalyst and Open Play cannot drift.
## Loaders deliberately return raw parsed dictionaries — the calling contract
## must normalize before the value reaches the rest of the app.

const ID_MAX_LENGTH: int = 40


static func read_json_dictionary(path: String) -> Dictionary:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty() or not FileAccess.file_exists(clean_path):
		return {}
	var file: FileAccess = FileAccess.open(clean_path, FileAccess.READ)
	if file == null:
		return {}
	var source_text: String = file.get_as_text()
	file.close()
	var parsed_any: Variant = JSON.parse_string(source_text)
	if typeof(parsed_any) != TYPE_DICTIONARY:
		return {}
	return parsed_any


static func write_json_dictionary(
	path: String,
	data: Dictionary,
	error_prefix: String
) -> Dictionary:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty():
		return {"ok": false, "error": error_prefix + "_path_unavailable"}
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(clean_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": error_prefix + "_directory_unavailable"}
	var file: FileAccess = FileAccess.open(clean_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": error_prefix + "_file_unavailable"}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return {"ok": true, "path": clean_path}


static func save_draft(normalized: Dictionary, draft_path: String) -> Dictionary:
	var result: Dictionary = write_json_dictionary(draft_path, normalized, "draft")
	if not bool(result.get("ok", false)):
		return result
	return {"ok": true, "scenario": normalized, "path": String(result.get("path", ""))}


static func load_draft_raw(draft_path: String, legacy_paths: Array) -> Dictionary:
	RuntimeConfig.migrate_file_if_needed(draft_path, legacy_paths)
	return read_json_dictionary(draft_path)


static func save_entry(
	normalized: Dictionary,
	library_dir: String,
	entry_id: String
) -> Dictionary:
	var clean_dir: String = library_dir.strip_edges()
	var clean_id: String = entry_id.strip_edges()
	if clean_dir.is_empty() or clean_id.is_empty():
		return {"ok": false, "error": "library_target_unavailable"}
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(clean_dir)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "library_directory_unavailable"}
	var result: Dictionary = write_json_dictionary(
		clean_dir.path_join(clean_id + ".json"),
		normalized,
		"library"
	)
	if not bool(result.get("ok", false)):
		return result
	return {"ok": true, "scenario": normalized, "path": String(result.get("path", ""))}


static func load_entry_raw(library_dir: String, entry_id: String) -> Dictionary:
	var clean_id: String = entry_id.strip_edges()
	if clean_id.is_empty():
		return {}
	return read_json_dictionary(library_dir.strip_edges().path_join(clean_id + ".json"))


static func entry_exists(library_dir: String, entry_id: String) -> bool:
	var clean_id: String = entry_id.strip_edges()
	if clean_id.is_empty():
		return false
	return FileAccess.file_exists(library_dir.strip_edges().path_join(clean_id + ".json"))


## Ids of every .json in the library, unsorted. Callers load and sort.
static func list_entry_ids(library_dir: String) -> Array[String]:
	var ids: Array[String] = []
	var clean_dir: String = library_dir.strip_edges()
	if clean_dir.is_empty() or not DirAccess.dir_exists_absolute(clean_dir):
		return ids
	var dir: DirAccess = DirAccess.open(clean_dir)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			ids.append(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	return ids


static func sort_entries_newest_first(entries: Array[Dictionary]) -> void:
	entries.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return String(first.get("saved_at", "")) > String(second.get("saved_at", ""))
	)


static func saved_at_stamp() -> String:
	return Time.get_datetime_string_from_system(true, true)


## Persistence metadata that no contract's normalize() models, because it
## describes the file rather than the Scenario. Carried across normalize so
## newest-first ordering and import provenance survive a load or a re-save.
const METADATA_KEYS: Array[String] = ["saved_at", "imported_from"]


static func carry_metadata(normalized: Dictionary, source: Dictionary) -> Dictionary:
	for key_name: String in METADATA_KEYS:
		if source.has(key_name) and not normalized.has(key_name):
			normalized[key_name] = source[key_name]
	return normalized


static func slugify(source_text: String, fallback: String, max_length: int) -> String:
	var lowered: String = source_text.strip_edges().to_lower().replace(" ", "_")
	var cleaned: String = ""
	for index: int in range(lowered.length()):
		var character: String = lowered[index]
		var code: int = character.unicode_at(0)
		var is_allowed: bool = (
			(code >= 97 and code <= 122)
			or (code >= 48 and code <= 57)
			or character == "_"
		)
		if is_allowed:
			cleaned += character
	if cleaned.is_empty():
		cleaned = fallback
	if max_length > 0 and cleaned.length() > max_length:
		cleaned = cleaned.substr(0, max_length)
	return cleaned


static func make_unique_id(prefix: String, display_name: String, fallback_slug: String) -> String:
	var stamp: String = str(Time.get_unix_time_from_system()).replace(".", "")
	return "%s_%s_%s" % [prefix, slugify(display_name, fallback_slug, ID_MAX_LENGTH), stamp]


static func string_array(value_any: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value_any) == TYPE_STRING:
		for line_text: String in String(value_any).split("\n"):
			var clean_line: String = line_text.strip_edges().trim_prefix("-").strip_edges()
			if not clean_line.is_empty():
				result.append(clean_line)
	elif typeof(value_any) == TYPE_ARRAY:
		for item_any: Variant in value_any:
			var item_text: String = String(item_any).strip_edges()
			if not item_text.is_empty():
				result.append(item_text)
	return result


static func to_dictionary(value_any: Variant) -> Dictionary:
	if typeof(value_any) != TYPE_DICTIONARY:
		return {}
	return (value_any as Dictionary).duplicate(true)


## Copy a legacy library directory's entries into the Documents library once.
## Per-file migration no-ops when the destination already exists, so a user who
## has edited a migrated entry never has it overwritten by the stale original.
static func migrate_dir_if_needed(dest_dir: String, legacy_dirs: Array) -> void:
	var clean_dest: String = dest_dir.strip_edges()
	if clean_dest.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(clean_dest)
	for legacy_any: Variant in legacy_dirs:
		var legacy_dir: String = String(legacy_any).strip_edges()
		if legacy_dir.is_empty():
			continue
		var dir: DirAccess = DirAccess.open(legacy_dir)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				RuntimeConfig.migrate_file_if_needed(
					clean_dest.path_join(file_name),
					[legacy_dir.path_join(file_name)]
				)
			file_name = dir.get_next()
		dir.list_dir_end()
