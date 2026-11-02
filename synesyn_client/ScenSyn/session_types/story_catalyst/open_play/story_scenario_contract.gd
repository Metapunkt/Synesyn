extends RefCounted
class_name StoryScenarioContract

## Story Catalyst · Open Play draft contract. Normalizes custom story scenarios
## (setting, cast, plot twists, genre tags) for local draft persistence and
## host sync. Parallel to WorkshopScenarioContract; does not touch Workshop data.

const SCHEMA_VERSION: int = 1
const CUSTOM_SCENARIO_ID: String = "custom_open_play_scenario"
const COLLECTION_ID: String = "open_play"
const SESSION_TYPE_ID: String = "story_catalyst"
## Legacy Godot app_userdata locations (migrated into Documents/Synesyn on read).
const _LEGACY_DRAFT_PATHS: Array[String] = [
	"user://scensyn/story_catalyst/open_play/scenario_draft_v1.json",
	"user://ScenSyn/story_catalyst/open_play/scenario_draft_v1.json",
]
const _LEGACY_LIBRARY_DIRS: Array[String] = [
	"user://scensyn/story_catalyst/open_play/scenarios/",
	"user://ScenSyn/story_catalyst/open_play/scenarios/",
]
const ScenarioLibraryStoreScript = preload(
	"res://ScenSyn/scripts/core/scenario_library_store.gd"
)
const _LIBRARY_ID_PREFIX: String = "open_play"


static func local_draft_path() -> String:
	return RuntimeConfig.get_open_play_draft_path()


static func library_dir() -> String:
	return RuntimeConfig.get_open_play_scenarios_dir()

## Curated genre tags for discovery and creation-prompt seeding. Multi-select.
const CURATED_TAGS: Array[String] = [
	"Fantasy",
	"Sci-Fi",
	"Horror",
	"Mystery",
	"Thriller",
	"Adventure",
	"Historical",
	"Cyberpunk",
	"Solarpunk",
	"Espionage",
]


static func looks_like_custom(scenario: Dictionary) -> bool:
	if scenario.is_empty():
		return false
	var scenario_id: String = String(scenario.get("id", "")).strip_edges()
	if scenario_id == CUSTOM_SCENARIO_ID or is_library_id(scenario_id):
		return true
	if String(scenario.get("_collection_id", "")) == COLLECTION_ID:
		return true
	if String(scenario.get("_session_type_id", "")) == SESSION_TYPE_ID:
		var persistence: String = String(scenario.get("persistence_state", ""))
		if (
			persistence == "local_draft"
			or persistence == "saved"
			or persistence == "imported"
			or persistence == "host_synced"
			or persistence == "session"
		):
			return scenario.has("plot_twists") or scenario.has("tags")
	return false


static func is_library_id(scenario_id: String) -> bool:
	var clean_id: String = scenario_id.strip_edges()
	return clean_id.begins_with("open_play_") and clean_id != CUSTOM_SCENARIO_ID


static func normalize(source: Dictionary) -> Dictionary:
	var setting_text: String = String(
		source.get("setting", source.get("description", ""))
	).strip_edges()
	var objective_text: String = String(source.get("objective", "")).strip_edges()
	var name_text: String = String(source.get("name", "Untitled Story")).strip_edges()
	if name_text.is_empty():
		name_text = "Untitled Story"
	var scenario_id: String = String(
		source.get("id", source.get("_scenario_name", CUSTOM_SCENARIO_ID))
	).strip_edges()
	if scenario_id.is_empty():
		scenario_id = CUSTOM_SCENARIO_ID
	var characters: Array[Dictionary] = _normalize_characters(source.get("characters", []))
	var plot_twists: Array[String] = _string_array(source.get("plot_twists", []))
	var tags: Array[String] = _normalize_tags(source.get("tags", []))
	var about_parts: Array[String] = []
	if not setting_text.is_empty():
		about_parts.append(setting_text)
	if not tags.is_empty():
		about_parts.append("Tags: " + ", ".join(tags))
	var how_parts: Array[String] = []
	if not plot_twists.is_empty():
		how_parts.append("Possible plot twists:")
		for twist_text: String in plot_twists:
			how_parts.append("- " + twist_text)
	how_parts.append(
		"Open Play is for narrative fun and roleplay — no teaching meters or curriculum overlays."
	)
	return {
		"schema_version": SCHEMA_VERSION,
		"id": scenario_id,
		"name": name_text,
		"objective": objective_text,
		"description": setting_text,
		"setting": setting_text,
		"characters": characters,
		"plot_twists": plot_twists,
		"tags": tags,
		"about_text": String(source.get("about_text", "\n\n".join(about_parts))).strip_edges(),
		"how_to_text": String(source.get("how_to_text", "\n".join(how_parts))).strip_edges(),
		"_session_type_id": SESSION_TYPE_ID,
		"_collection_id": COLLECTION_ID,
		"persistence_state": String(source.get("persistence_state", "template")),
	}


static func create_custom(fields: Dictionary) -> Dictionary:
	var scenario_id: String = String(fields.get("id", CUSTOM_SCENARIO_ID)).strip_edges()
	if scenario_id.is_empty():
		scenario_id = CUSTOM_SCENARIO_ID
	return normalize({
		"id": scenario_id,
		"name": String(fields.get("name", fields.get("title", "Untitled Story"))),
		"objective": String(fields.get("objective", "")),
		"setting": String(fields.get("setting", fields.get("context", fields.get("description", "")))),
		"description": String(fields.get("setting", fields.get("context", fields.get("description", "")))),
		"characters": fields.get("characters", []),
		"plot_twists": fields.get("plot_twists", []),
		"tags": fields.get("tags", []),
		"persistence_state": "local_draft",
	})


static func save_local_draft(scenario: Dictionary) -> Dictionary:
	var normalized: Dictionary = normalize(scenario)
	normalized["id"] = CUSTOM_SCENARIO_ID
	normalized["persistence_state"] = "local_draft"
	return ScenarioLibraryStoreScript.save_draft(normalized, local_draft_path())


static func load_local_draft() -> Dictionary:
	var raw: Dictionary = ScenarioLibraryStoreScript.load_draft_raw(
		local_draft_path(),
		_LEGACY_DRAFT_PATHS
	)
	if raw.is_empty():
		return {}
	var normalized: Dictionary = normalize(raw)
	normalized["id"] = CUSTOM_SCENARIO_ID
	normalized["persistence_state"] = "local_draft"
	return normalized


## Persist a finished Open Play scenario into the selectable library.
## Assigns a unique id when the source still uses the draft sentinel.
##
## `sync_draft` keeps the working draft pointing at the latest finish so
## "Review draft" still opens it. Imports pass false: a shared Scenario must
## never overwrite what the user was authoring.
static func save_to_library(scenario: Dictionary, sync_draft: bool = true) -> Dictionary:
	var normalized: Dictionary = normalize(scenario)
	ScenarioLibraryStoreScript.carry_metadata(normalized, scenario)
	var scenario_id: String = String(normalized.get("id", "")).strip_edges()
	if scenario_id.is_empty() or scenario_id == CUSTOM_SCENARIO_ID:
		scenario_id = make_unique_id(String(normalized.get("name", "Untitled Story")))
	normalized["id"] = scenario_id
	var persistence: String = String(normalized.get("persistence_state", ""))
	normalized["persistence_state"] = persistence if persistence == "imported" else "saved"
	normalized["saved_at"] = ScenarioLibraryStoreScript.saved_at_stamp()
	var result: Dictionary = ScenarioLibraryStoreScript.save_entry(
		normalized,
		library_dir(),
		scenario_id
	)
	if bool(result.get("ok", false)) and sync_draft:
		save_local_draft(normalized)
	return result


static func load_saved_scenario(scenario_id: String) -> Dictionary:
	ScenarioLibraryStoreScript.migrate_dir_if_needed(library_dir(), _LEGACY_LIBRARY_DIRS)
	var clean_id: String = scenario_id.strip_edges()
	if clean_id.is_empty():
		return {}
	if clean_id == CUSTOM_SCENARIO_ID:
		return load_local_draft()
	var raw: Dictionary = ScenarioLibraryStoreScript.load_entry_raw(library_dir(), clean_id)
	if raw.is_empty():
		return {}
	var normalized: Dictionary = normalize(raw)
	ScenarioLibraryStoreScript.carry_metadata(normalized, raw)
	normalized["id"] = clean_id
	if String(normalized.get("persistence_state", "")).is_empty():
		normalized["persistence_state"] = "saved"
	return normalized


## Returns entries newest-first: {id, name, objective, saved_at, path}.
static func list_saved_scenarios() -> Array[Dictionary]:
	ScenarioLibraryStoreScript.migrate_dir_if_needed(library_dir(), _LEGACY_LIBRARY_DIRS)
	var entries: Array[Dictionary] = []
	var lib_dir: String = library_dir()
	for scenario_id: String in ScenarioLibraryStoreScript.list_entry_ids(lib_dir):
		var loaded: Dictionary = load_saved_scenario(scenario_id)
		if loaded.is_empty():
			continue
		entries.append({
			"id": scenario_id,
			"name": String(loaded.get("name", "Untitled Story")),
			"objective": String(loaded.get("objective", "")),
			"saved_at": String(loaded.get("saved_at", "")),
			"path": lib_dir.path_join(scenario_id + ".json"),
		})
	ScenarioLibraryStoreScript.sort_entries_newest_first(entries)
	if entries.is_empty():
		_maybe_promote_legacy_draft(entries)
	return entries


static func make_unique_id(display_name: String) -> String:
	return ScenarioLibraryStoreScript.make_unique_id(_LIBRARY_ID_PREFIX, display_name, "story")


static func _maybe_promote_legacy_draft(entries: Array[Dictionary]) -> void:
	## One-time bridge: a pre-library local draft becomes the first selectable entry.
	if not entries.is_empty():
		return
	var draft: Dictionary = load_local_draft()
	if draft.is_empty():
		return
	var promoted: Dictionary = save_to_library(draft)
	if not bool(promoted.get("ok", false)):
		return
	var scenario: Dictionary = promoted.get("scenario", {}) as Dictionary
	entries.append({
		"id": String(scenario.get("id", "")),
		"name": String(scenario.get("name", "Untitled Story")),
		"objective": String(scenario.get("objective", "")),
		"saved_at": String(scenario.get("saved_at", "")),
		"path": String(promoted.get("path", "")),
	})


static func tags_prompt_fragment(tags: Array[String]) -> String:
	if tags.is_empty():
		return ""
	return "Genre tags for this story: " + ", ".join(tags) + "."


static func _normalize_characters(characters_any: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(characters_any) != TYPE_ARRAY:
		return result
	var next_id: int = 1
	for character_any: Variant in characters_any:
		if typeof(character_any) != TYPE_DICTIONARY:
			continue
		var character: Dictionary = character_any
		var char_name: String = String(character.get("name", "")).strip_edges()
		if char_name.is_empty():
			continue
		var role_text: String = String(character.get("role", "")).strip_edges()
		if role_text.is_empty():
			role_text = "Character"
		var char_id: int = int(character.get("id", next_id))
		result.append({
			"id": char_id,
			"name": char_name,
			"role": role_text,
			"description": String(character.get("description", "")).strip_edges(),
			"is_ai": bool(character.get("is_ai", true)),
		})
		next_id = maxi(next_id, char_id + 1)
	return result


static func _normalize_tags(tags_any: Variant) -> Array[String]:
	var requested: Array[String] = _string_array(tags_any)
	var result: Array[String] = []
	for tag_text: String in requested:
		for curated_tag: String in CURATED_TAGS:
			if tag_text.to_lower() == curated_tag.to_lower() and not result.has(curated_tag):
				result.append(curated_tag)
				break
	return result


static func _string_array(value_any: Variant) -> Array[String]:
	return ScenarioLibraryStoreScript.string_array(value_any)
