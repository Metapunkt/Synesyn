extends RefCounted
class_name ScenarioShareUi

## Turns ScenarioBundle results into sentences a user can act on, and builds the
## import file picker. Kept apart from the screens that call it so both the
## Workshop editor and Open Play can share one wording.

const ScenarioBundleScript = preload("res://ScenSyn/scripts/core/scenario_bundle.gd")

const IMPORT_FILTERS: Array[String] = [
	"*.json, *.zip ; Synesyn Scenario bundles",
	"*.json ; Scenario bundle (JSON)",
	"*.zip ; Scenario bundle with assets (ZIP)",
]


static func export_message(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return "Could not share this Scenario: " + _explain(String(result.get("error", "")))
	var path: String = String(result.get("path", ""))
	var scenario_count: int = int(result.get("scenario_count", 1))
	var asset_count: int = int(result.get("asset_count", 0))
	var noun: String = "Scenario" if scenario_count == 1 else "Scenarios"
	var message: String = "Shared %d %s to %s." % [scenario_count, noun, path.get_file()]
	if asset_count > 0:
		message += " %d image %s included (%s)." % [
			asset_count,
			"file" if asset_count == 1 else "files",
			_readable_size(int(result.get("asset_bytes", 0))),
		]
	if bool(result.get("assets_truncated", false)):
		message += " Some images were left out because the bundle would be too large."
	return message + " Send the file to anyone running Synesyn."


static func import_message(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return "Nothing imported: " + _explain(_first_reason(result))
	var imported_any: Variant = result.get("imported", [])
	var imported: Array = imported_any if typeof(imported_any) == TYPE_ARRAY else []
	var names: Array[String] = []
	var renamed: int = 0
	for entry_any: Variant in imported:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		names.append(String(entry.get("name", "Untitled")))
		if bool(entry.get("renamed_id", false)):
			renamed += 1
	var message: String = "Imported into your library: " + ", ".join(names) + "."
	if renamed > 0:
		message += " Saved as a copy, because you already had a Scenario with the same id."
	var restored: int = int(result.get("assets_restored", 0))
	if restored > 0:
		message += " %d image %s restored." % [restored, "file" if restored == 1 else "files"]
	var skipped_any: Variant = result.get("skipped", [])
	var skipped: Array = skipped_any if typeof(skipped_any) == TYPE_ARRAY else []
	if not skipped.is_empty():
		message += " %d entry %s skipped: %s" % [
			skipped.size(),
			"was" if skipped.size() == 1 else "were",
			_explain(String(skipped[0])),
		]
	return message


## Import picker. Created in code because it is a transient OS dialog rather
## than part of any screen's layout.
static func make_import_dialog(parent: Node) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = "Import a Scenario bundle"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(IMPORT_FILTERS)
	dialog.current_dir = RuntimeConfig.get_scenario_exports_dir()
	dialog.size = Vector2i(900, 620)
	parent.add_child(dialog)
	return dialog


static func reveal_exports_dir() -> void:
	var dir_path: String = RuntimeConfig.get_scenario_exports_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	OS.shell_open(dir_path)


static func _first_reason(result: Dictionary) -> String:
	var error_text: String = String(result.get("error", "")).strip_edges()
	if error_text != "nothing_imported" and not error_text.is_empty():
		return error_text
	var skipped_any: Variant = result.get("skipped", [])
	if typeof(skipped_any) == TYPE_ARRAY and not (skipped_any as Array).is_empty():
		return String((skipped_any as Array)[0])
	return error_text


static func _explain(error_code: String) -> String:
	match error_code:
		"bundle_not_found":
			return "that file no longer exists."
		"bundle_unreadable":
			return "that file could not be opened."
		"bundle_not_json":
			return "that file is not a Scenario bundle."
		"not_a_scenario_bundle":
			return "that file is not a Scenario bundle."
		"looks_like_story_log":
			return "that looks like a saved session log, not a Scenario bundle."
		"bundle_missing_scenario_json":
			return "that archive has no Scenario in it."
		"bundle_schema_unreadable":
			return "that bundle's version could not be read."
		"bundle_needs_newer_version":
			return "that bundle was made by a newer version of Synesyn."
		"bundle_has_no_scenarios":
			return "that bundle is empty."
		"wrong_session_type":
			return "that bundle holds a Scenario for the other session type."
		"unsupported_session_type":
			return "that Scenario's session type is not supported."
		"no_scenarios", "no_supported_scenarios":
			return "there was nothing to share."
		"export_directory_unavailable", "export_path_unavailable":
			return "the export folder could not be created."
		"export_zip_unavailable":
			return "the archive could not be written."
		"library_directory_unavailable", "library_file_unavailable":
			return "the library folder could not be written to."
		"normalize_failed", "entry_missing_scenario", "malformed_entry":
			return "that Scenario could not be read."
	return error_code


static func _readable_size(byte_count: int) -> String:
	if byte_count < 1024:
		return "%d bytes" % byte_count
	if byte_count < 1024 * 1024:
		return "%.1f KB" % (float(byte_count) / 1024.0)
	return "%.1f MB" % (float(byte_count) / (1024.0 * 1024.0))
