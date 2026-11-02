extends SceneTree

## Open Play · StoryScenarioContract + registry smoke tests.

const StoryScenarioContractScript = preload(
	"res://ScenSyn/session_types/story_catalyst/open_play/story_scenario_contract.gd"
)
const ScenarioLoaderScript = preload("res://ScenSyn/scripts/core/scenario_loader.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_contract_normalize_and_tags()
	_test_contract_round_trip()
	_test_library_save_list_load()
	_test_loader_story_dictionary()
	_test_global_registry()
	_finish()


func _test_contract_normalize_and_tags() -> void:
	var custom: Dictionary = StoryScenarioContractScript.create_custom({
		"name": "Lantern Coast",
		"setting": "A fogbound harbour town.",
		"objective": "Find who snuffed the lighthouse.",
		"characters": [
			{"name": "Mira", "description": "A cartographer with wet boots."},
			{"name": "Orrin", "role": "Smuggler", "description": "Knows every cove."},
		],
		"plot_twists": ["The lighthouse keeps its own counsel."],
		"tags": ["Mystery", "fantasy", "NotARealTag", "Adventure"],
	})
	_expect(String(custom.get("id", "")) == "custom_open_play_scenario", "Custom id mismatch")
	_expect(String(custom.get("_collection_id", "")) == "open_play", "Collection id mismatch")
	_expect(String(custom.get("_session_type_id", "")) == "story_catalyst", "Session type mismatch")
	var tags: Array = custom.get("tags", [])
	_expect(tags.has("Mystery") and tags.has("Fantasy") and tags.has("Adventure"), "Tag normalize failed")
	_expect(not tags.has("NotARealTag"), "Unknown tag should be dropped")
	var characters: Array = custom.get("characters", [])
	_expect(characters.size() == 2, "Expected two characters")
	if characters.size() >= 1:
		_expect(
			String((characters[0] as Dictionary).get("role", "")) == "Character",
			"Missing role should default to Character"
		)
	if characters.size() >= 2:
		_expect(
			String((characters[1] as Dictionary).get("role", "")) == "Smuggler",
			"Authored role should be kept"
		)
	_expect(StoryScenarioContractScript.looks_like_custom(custom), "looks_like_custom should match")


func _test_contract_round_trip() -> void:
	var custom: Dictionary = StoryScenarioContractScript.create_custom({
		"name": "Round Trip Isle",
		"objective": "Escape before dawn.",
		"setting": "Volcanic beaches.",
		"characters": [{"name": "Kit", "role": "Runner", "description": "Fast."}],
		"tags": ["Thriller"],
	})
	var save_result: Dictionary = StoryScenarioContractScript.save_local_draft(custom)
	_expect(bool(save_result.get("ok", false)), "save_local_draft failed")
	var reloaded: Dictionary = StoryScenarioContractScript.load_local_draft()
	_expect(reloaded.get("name") == custom.get("name"), "Draft title did not reload")
	_expect(reloaded.get("persistence_state") == "local_draft", "Draft persistence_state wrong")


func _test_library_save_list_load() -> void:
	var library_dir: String = StoryScenarioContractScript.library_dir()
	_expect(
		library_dir.find("Synesyn") >= 0 and library_dir.find("app_userdata") < 0,
		"Open Play library must live under Documents/Synesyn, not app_userdata: " + library_dir
	)
	var custom: Dictionary = StoryScenarioContractScript.create_custom({
		"name": "Library Harbour",
		"objective": "Catalog the tide charts.",
		"setting": "A quiet cartographers' quay.",
		"characters": [{"name": "Nell", "role": "Archivist", "description": "Ink-stained."}],
		"tags": ["Mystery"],
	})
	var save_result: Dictionary = StoryScenarioContractScript.save_to_library(custom)
	_expect(bool(save_result.get("ok", false)), "save_to_library failed")
	var saved: Dictionary = save_result.get("scenario", {}) as Dictionary
	var saved_id: String = String(saved.get("id", ""))
	_expect(StoryScenarioContractScript.is_library_id(saved_id), "Expected open_play_ library id")
	_expect(String(saved.get("persistence_state", "")) == "saved", "Library persistence_state wrong")
	var saved_path: String = String(save_result.get("path", ""))
	_expect(saved_path.begins_with(library_dir), "Saved path not under Documents library dir")
	var listed: Array[Dictionary] = StoryScenarioContractScript.list_saved_scenarios()
	var found: bool = false
	for entry: Dictionary in listed:
		if String(entry.get("id", "")) == saved_id:
			found = true
			_expect(String(entry.get("name", "")) == "Library Harbour", "List name mismatch")
			break
	_expect(found, "Saved scenario missing from list_saved_scenarios")
	var loaded: Dictionary = StoryScenarioContractScript.load_saved_scenario(saved_id)
	_expect(String(loaded.get("name", "")) == "Library Harbour", "load_saved_scenario name mismatch")
	_expect(StoryScenarioContractScript.looks_like_custom(loaded), "Library scenario should look custom")


func _test_loader_story_dictionary() -> void:
	var loader: RefCounted = ScenarioLoaderScript.new()
	var custom: Dictionary = StoryScenarioContractScript.create_custom({
		"name": "Loader Cove",
		"objective": "Bargain for passage.",
		"setting": "Crowded docks.",
		"characters": [
			{"name": "Ash", "role": "Broker", "description": "Speaks softly."},
			{"name": "Rye", "role": "Sailor", "description": "Keeps watch."},
		],
		"tags": ["Adventure"],
	})
	_expect(loader.load_story_dictionary(custom), "load_story_dictionary failed")
	var loaded: Dictionary = loader.get_current_scenario()
	_expect(String(loaded.get("name", "")) == "Loader Cove", "Loader name mismatch")
	var characters: Array = loaded.get("characters", [])
	_expect(characters.size() == 2, "Loader did not expose cast")


func _test_global_registry() -> void:
	var root_global: Node = root.get_node_or_null("Global")
	_expect(root_global != null, "Global autoload missing in headless tree")
	if root_global == null:
		return
	var collection_ids: Array = root_global.call("get_collection_ids", "story_catalyst")
	_expect(collection_ids.has("open_play"), "open_play not registered under story_catalyst")
	_expect(
		String(root_global.call("get_collection_display_name", "open_play")) == "Open Play",
		"Open Play display name mismatch"
	)
	var manager: Node = root_global.call(
		"get_metaprompt_manager_for_collection", "story_catalyst", "open_play"
	)
	_expect(manager != null, "Open Play metaprompt manager failed to resolve")
	if manager:
		manager.queue_free()


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Open Play story scenario tests: all passed")
		quit(0)
	for failure_message: String in _failures:
		print("FAIL: " + failure_message)
	quit(1)
