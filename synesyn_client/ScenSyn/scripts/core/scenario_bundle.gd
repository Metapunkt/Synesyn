extends RefCounted
class_name ScenarioBundle

## Shareable Scenario bundles: export to a file, import from a file.
##
## The payload is the normalized Scenario contract dictionary — the same value
## Network already ships whole to joining peers — wrapped in a versioned
## envelope holding an array, so sharing a set of Scenarios later needs no new
## format. A bundle with no carried assets is written as a single .json; one with
## generated sprites is written as a .zip holding that same JSON at its root.
##
## Import never trusts the file: every Scenario goes back through its owning
## contract's normalize(), and every carried path through
## ScenarioBundleAssets.is_safe_relative_path().

const SCHEMA_PREFIX: String = "synesyn.scensyn.scenario_bundle.v"
const SCHEMA_MAJOR: int = 1
const SCHEMA: String = SCHEMA_PREFIX + "1"
const BUNDLE_JSON_NAME: String = "scenario.json"
const SESSION_TYPE_WORKSHOP: String = "workshop_catalyst"
const SESSION_TYPE_STORY: String = "story_catalyst"

## Fields that direct the app rather than describe the subject, so an imported
## bundle must not apply them unreviewed.
##
## stage_guidance is the specialists' per-stage operating contract, and authored
## guidance beats WorkshopScenarioContract.default_stage_guidance(), so a bundle
## could replace the facilitation method of ADR 0012 outright. system_config
## selects the specialist / synthesizer / director / actor model and the output
## word limits; model ids are validated against AIModelManager's registered list,
## so this cannot reach an arbitrary endpoint, but it can still redirect calls to
## another of the user's own models.
##
## Only Workshop Catalyst declares either field. Open Play carries neither.
const QUARANTINED_ON_IMPORT: Array[String] = ["stage_guidance", "system_config"]

const WorkshopScenarioContractScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_scenario_contract.gd"
)
const StoryScenarioContractScript = preload(
	"res://ScenSyn/session_types/story_catalyst/open_play/story_scenario_contract.gd"
)
const ScenarioBundleAssetsScript = preload(
	"res://ScenSyn/scripts/core/scenario_bundle_assets.gd"
)
const ScenarioLibraryStoreScript = preload(
	"res://ScenSyn/scripts/core/scenario_library_store.gd"
)


static func session_type_of(scenario: Dictionary) -> String:
	return String(scenario.get("_session_type_id", "")).strip_edges()


static func is_supported_session_type(session_type: String) -> bool:
	return session_type == SESSION_TYPE_WORKSHOP or session_type == SESSION_TYPE_STORY


static func normalize_for(session_type: String, scenario: Dictionary) -> Dictionary:
	if session_type == SESSION_TYPE_WORKSHOP:
		return WorkshopScenarioContractScript.normalize(scenario)
	if session_type == SESSION_TYPE_STORY:
		return StoryScenarioContractScript.normalize(scenario)
	return {}


static func app_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "")).strip_edges()


# --- Export ------------------------------------------------------------------

## Writes one bundle holding every given Scenario. Chooses .zip over .json only
## when a Scenario actually carries files, so the common case stays a plain JSON
## a recipient can read in a text editor.
static func export_scenarios(scenarios: Array, dest_dir: String = "") -> Dictionary:
	if scenarios.is_empty():
		return {"ok": false, "error": "no_scenarios"}
	var target_dir: String = dest_dir.strip_edges()
	if target_dir.is_empty():
		target_dir = RuntimeConfig.get_scenario_exports_dir()
	var entries: Array[Dictionary] = []
	var carried: Array[Dictionary] = []
	var asset_count: int = 0
	var asset_bytes: int = 0
	var truncated: bool = false
	for scenario_any: Variant in scenarios:
		if typeof(scenario_any) != TYPE_DICTIONARY:
			continue
		var session_type: String = session_type_of(scenario_any)
		if not is_supported_session_type(session_type):
			continue
		var normalized: Dictionary = normalize_for(session_type, scenario_any)
		if normalized.is_empty():
			continue
		var collected: Dictionary = ScenarioBundleAssetsScript.collect(normalized)
		var files_any: Variant = collected.get("files", [])
		var files: Array = files_any if typeof(files_any) == TYPE_ARRAY else []
		var entry_index: int = entries.size()
		var asset_paths: Array[String] = []
		for file_any: Variant in files:
			if typeof(file_any) != TYPE_DICTIONARY:
				continue
			var file_entry: Dictionary = file_any
			var relative_path: String = String(file_entry.get("relative_path", ""))
			asset_paths.append(relative_path)
			carried.append({
				"archive_path": archive_path(entry_index, relative_path),
				"source_abs": String(file_entry.get("source_abs", "")),
			})
			asset_count += 1
			asset_bytes += int(file_entry.get("bytes", 0))
		if bool(collected.get("truncated", false)):
			truncated = true
		entries.append({
			"session_type": session_type,
			"scenario": normalized,
			"assets": asset_paths,
		})
	if entries.is_empty():
		return {"ok": false, "error": "no_supported_scenarios"}
	var envelope: Dictionary = build_envelope(entries)
	var file_stem: String = _file_stem(entries)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(target_dir)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "export_directory_unavailable"}
	var result: Dictionary = {}
	if carried.is_empty():
		result = write_json_bundle(target_dir.path_join(file_stem + ".json"), envelope)
	else:
		result = write_zip_bundle(target_dir.path_join(file_stem + ".zip"), envelope, carried)
	if not bool(result.get("ok", false)):
		return result
	result["scenario_count"] = entries.size()
	result["asset_count"] = asset_count
	result["asset_bytes"] = asset_bytes
	result["assets_truncated"] = truncated
	return result


static func build_envelope(entries: Array[Dictionary]) -> Dictionary:
	return {
		"schema": SCHEMA,
		"exported_at": Time.get_datetime_string_from_system(true, true),
		"exported_by_app_version": app_version(),
		"scenarios": entries,
	}


static func archive_path(entry_index: int, relative_path: String) -> String:
	return "assets/%d/sprites/%s" % [entry_index, relative_path]


## Inverse of archive_path. Returns {} when the entry is not a carried asset,
## which also filters the directory entries a zip writer inserts implicitly.
static func parse_archive_path(archive_entry: String) -> Dictionary:
	var clean_entry: String = archive_entry.strip_edges().replace("\\", "/")
	if not clean_entry.begins_with("assets/") or clean_entry.ends_with("/"):
		return {}
	var segments: PackedStringArray = clean_entry.split("/")
	if segments.size() < 4:
		return {}
	if segments[2] != "sprites":
		return {}
	var index_text: String = segments[1]
	if not index_text.is_valid_int():
		return {}
	var relative_segments: Array[String] = []
	for segment_index: int in range(3, segments.size()):
		relative_segments.append(segments[segment_index])
	return {
		"entry_index": int(index_text),
		"relative_path": "/".join(relative_segments),
	}


static func write_json_bundle(path: String, envelope: Dictionary) -> Dictionary:
	var result: Dictionary = ScenarioLibraryStoreScript.write_json_dictionary(
		path,
		envelope,
		"export"
	)
	if not bool(result.get("ok", false)):
		return result
	return {"ok": true, "path": String(result.get("path", "")), "format": "json"}


## `carried` entries are {archive_path, source_abs}, as composed by archive_path().
static func write_zip_bundle(
	path: String,
	envelope: Dictionary,
	carried: Array[Dictionary]
) -> Dictionary:
	var packer := ZIPPacker.new()
	var open_error: Error = packer.open(path)
	if open_error != OK:
		return {"ok": false, "error": "export_zip_unavailable"}
	packer.start_file(BUNDLE_JSON_NAME)
	packer.write_file(JSON.stringify(envelope, "\t").to_utf8_buffer())
	packer.close_file()
	var written: int = 0
	for carried_entry: Dictionary in carried:
		var source_abs: String = String(carried_entry.get("source_abs", ""))
		if source_abs.is_empty() or not FileAccess.file_exists(source_abs):
			continue
		packer.start_file(String(carried_entry.get("archive_path", "")))
		packer.write_file(FileAccess.get_file_as_bytes(source_abs))
		packer.close_file()
		written += 1
	packer.close()
	return {"ok": true, "path": path, "format": "zip", "files_written": written}


static func _file_stem(entries: Array[Dictionary]) -> String:
	var first: Dictionary = ScenarioLibraryStoreScript.to_dictionary(
		entries[0].get("scenario", {})
	)
	var slug: String = ScenarioLibraryStoreScript.slugify(
		String(first.get("name", "scenario")),
		"scenario",
		ScenarioLibraryStoreScript.ID_MAX_LENGTH
	)
	if entries.size() > 1:
		slug += "_and_%d_more" % [entries.size() - 1]
	return "%s_%s" % [slug, str(Time.get_unix_time_from_system()).replace(".", "")]


# --- Import ------------------------------------------------------------------

## Parses and validates a bundle without writing anything.
static func read_envelope(path: String) -> Dictionary:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty() or not FileAccess.file_exists(clean_path):
		return {"ok": false, "error": "bundle_not_found"}
	if clean_path.to_lower().ends_with(".zip"):
		var reader := ZIPReader.new()
		var open_error: Error = reader.open(clean_path)
		if open_error != OK:
			return {"ok": false, "error": "bundle_unreadable"}
		if not reader.file_exists(BUNDLE_JSON_NAME):
			reader.close()
			return {"ok": false, "error": "bundle_missing_scenario_json"}
		var body: String = reader.read_file(BUNDLE_JSON_NAME).get_string_from_utf8()
		reader.close()
		return validate_envelope_text(body)
	var file: FileAccess = FileAccess.open(clean_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "bundle_unreadable"}
	var text: String = file.get_as_text()
	file.close()
	return validate_envelope_text(text)


static func validate_envelope_text(source_text: String) -> Dictionary:
	var parsed_any: Variant = JSON.parse_string(source_text)
	if typeof(parsed_any) == TYPE_ARRAY:
		# Story logs are top-level arrays. Users will try to import one.
		return {"ok": false, "error": "looks_like_story_log"}
	if typeof(parsed_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "bundle_not_json"}
	var envelope: Dictionary = parsed_any
	var schema_text: String = String(envelope.get("schema", "")).strip_edges()
	if not schema_text.begins_with(SCHEMA_PREFIX):
		return {"ok": false, "error": "not_a_scenario_bundle"}
	var major_text: String = schema_text.trim_prefix(SCHEMA_PREFIX)
	if not major_text.is_valid_int():
		return {"ok": false, "error": "bundle_schema_unreadable"}
	if int(major_text) > SCHEMA_MAJOR:
		return {"ok": false, "error": "bundle_needs_newer_version"}
	var scenarios_any: Variant = envelope.get("scenarios", [])
	if typeof(scenarios_any) != TYPE_ARRAY or (scenarios_any as Array).is_empty():
		return {"ok": false, "error": "bundle_has_no_scenarios"}
	return {"ok": true, "envelope": envelope, "scenarios": scenarios_any}


## Session types present in a validated envelope, so a caller can tell the user
## what a bundle holds before importing it.
static func session_types_in(scenarios: Array) -> Array[String]:
	var found: Array[String] = []
	for entry_any: Variant in scenarios:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var session_type: String = String(entry.get("session_type", "")).strip_edges()
		if session_type.is_empty():
			session_type = session_type_of(
				ScenarioLibraryStoreScript.to_dictionary(entry.get("scenario", {}))
			)
		if not session_type.is_empty() and not found.has(session_type):
			found.append(session_type)
	return found


## Validates, normalizes, and saves every Scenario in the bundle into its owning
## library. Existing library entries are never overwritten: a colliding id is
## re-minted so an import cannot replace work the user already has.
##
## `allowed_session_types`, when non-empty, scopes the import to one session
## type, so an entry point can refuse a bundle meant for the other mode instead
## of silently filing it somewhere the user is not looking.
static func import_bundle(path: String, allowed_session_types: Array = []) -> Dictionary:
	var read_result: Dictionary = read_envelope(path)
	if not bool(read_result.get("ok", false)):
		return read_result
	var envelope: Dictionary = read_result.get("envelope", {})
	var scenarios_any: Variant = read_result.get("scenarios", [])
	var scenarios: Array = scenarios_any if typeof(scenarios_any) == TYPE_ARRAY else []
	var provenance: Dictionary = {
		"exported_at": String(envelope.get("exported_at", "")),
		"exported_by_app_version": String(envelope.get("exported_by_app_version", "")),
		"source_file": path.get_file(),
	}
	var imported: Array[Dictionary] = []
	var skipped: Array[String] = []
	var saved_scenarios: Array[Dictionary] = []
	for entry_any: Variant in scenarios:
		if typeof(entry_any) != TYPE_DICTIONARY:
			skipped.append("malformed_entry")
			saved_scenarios.append({})
			continue
		var outcome: Dictionary = _import_entry(entry_any, provenance, allowed_session_types)
		if bool(outcome.get("ok", false)):
			var saved: Dictionary = outcome.get("scenario", {})
			saved_scenarios.append(saved)
			imported.append({
				"id": String(saved.get("id", "")),
				"name": String(saved.get("name", "")),
				"session_type": String(outcome.get("session_type", "")),
				"path": String(outcome.get("path", "")),
				"renamed_id": bool(outcome.get("renamed_id", false)),
			})
		else:
			saved_scenarios.append({})
			skipped.append(String(outcome.get("error", "import_failed")))
	if imported.is_empty():
		return {"ok": false, "error": "nothing_imported", "skipped": skipped}
	var restored: int = _restore_assets(path, saved_scenarios)
	return {
		"ok": true,
		"imported": imported,
		"skipped": skipped,
		"assets_restored": restored,
	}


static func _import_entry(
	entry: Dictionary,
	provenance: Dictionary,
	allowed_session_types: Array
) -> Dictionary:
	var scenario_any: Variant = entry.get("scenario", {})
	if typeof(scenario_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "entry_missing_scenario"}
	var source: Dictionary = scenario_any
	var session_type: String = String(entry.get("session_type", "")).strip_edges()
	if session_type.is_empty():
		session_type = session_type_of(source)
	if not is_supported_session_type(session_type):
		return {"ok": false, "error": "unsupported_session_type"}
	if not allowed_session_types.is_empty() and not allowed_session_types.has(session_type):
		return {"ok": false, "error": "wrong_session_type"}
	var normalized: Dictionary = normalize_for(session_type, source)
	if normalized.is_empty():
		return {"ok": false, "error": "normalize_failed"}
	var original_id: String = String(normalized.get("id", "")).strip_edges()
	var library_dir: String = _library_dir_for(session_type)
	var renamed_id: bool = false
	if ScenarioLibraryStoreScript.entry_exists(library_dir, original_id):
		normalized["id"] = ""
		renamed_id = true
	normalized["persistence_state"] = "imported"
	var import_record: Dictionary = provenance.duplicate(true)
	import_record["original_id"] = original_id
	var quarantined: Dictionary = _quarantine_authority_fields(source, normalized)
	if not quarantined.is_empty():
		import_record["quarantined"] = quarantined
	normalized["imported_from"] = import_record
	var save_result: Dictionary = _save_to_library_for(session_type, normalized)
	if not bool(save_result.get("ok", false)):
		return {"ok": false, "error": String(save_result.get("error", "library_save_failed"))}
	return {
		"ok": true,
		"scenario": save_result.get("scenario", {}),
		"path": String(save_result.get("path", "")),
		"session_type": session_type,
		"renamed_id": renamed_id,
	}


## Sets the authority-carrying fields aside so an imported Scenario runs on this
## machine's defaults. The copy is kept under imported_from, which nothing reads,
## so the saved file still shows what arrived and a later review-and-accept step
## has something to restore from.
##
## Tested against `source` rather than `normalized`: normalize() substitutes
## default stage guidance when a Scenario carries none, so the normalized value is
## never empty and checking it would set aside our own defaults.
static func _quarantine_authority_fields(
	source: Dictionary,
	normalized: Dictionary
) -> Dictionary:
	var quarantined: Dictionary = {}
	for field_name: String in QUARANTINED_ON_IMPORT:
		var authored: Dictionary = ScenarioLibraryStoreScript.to_dictionary(
			source.get(field_name, {})
		)
		if authored.is_empty():
			continue
		quarantined[field_name] = authored
		# Emptied rather than erased, so the owning contract's normalize() refills
		# stage_guidance with its own defaults on the way to the library file.
		normalized[field_name] = {}
	return quarantined


static func _library_dir_for(session_type: String) -> String:
	if session_type == SESSION_TYPE_WORKSHOP:
		return WorkshopScenarioContractScript.library_dir()
	return StoryScenarioContractScript.library_dir()


static func _save_to_library_for(session_type: String, normalized: Dictionary) -> Dictionary:
	# sync_draft is false: an imported Scenario must not replace the draft the
	# user was authoring.
	if session_type == SESSION_TYPE_WORKSHOP:
		return WorkshopScenarioContractScript.save_to_library(normalized, false)
	return StoryScenarioContractScript.save_to_library(normalized, false)


## Copies carried sprites out of a zip bundle onto this machine. `saved_scenarios`
## is index-aligned with the envelope's scenarios array so archive paths resolve
## to the Scenario that was actually saved.
static func _restore_assets(path: String, saved_scenarios: Array[Dictionary]) -> int:
	if not path.strip_edges().to_lower().ends_with(".zip"):
		return 0
	var reader := ZIPReader.new()
	if reader.open(path.strip_edges()) != OK:
		return 0
	var restored: int = 0
	for archive_entry: String in reader.get_files():
		var parsed: Dictionary = parse_archive_path(archive_entry)
		if parsed.is_empty():
			continue
		var entry_index: int = int(parsed.get("entry_index", -1))
		if entry_index < 0 or entry_index >= saved_scenarios.size():
			continue
		var scenario: Dictionary = saved_scenarios[entry_index]
		if scenario.is_empty():
			continue
		var written: bool = ScenarioBundleAssetsScript.restore_file(
			scenario,
			String(parsed.get("relative_path", "")),
			reader.read_file(archive_entry)
		)
		if written:
			restored += 1
	reader.close()
	return restored
