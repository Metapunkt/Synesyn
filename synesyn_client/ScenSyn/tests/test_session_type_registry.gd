extends SceneTree

## Session Type / Collection registry tests.
##
## The registry is a hand-maintained set of parallel dictionaries in Global:
## SESSION_TYPE_COLLECTIONS, SESSION_TYPE_MANAGER_PATHS, COLLECTION_DISPLAY_NAMES.
## Nothing enforces that they agree, and a Collection registered without a
## manager path degrades silently to the neutral manager instead of failing, so
## these tests check the agreement rather than only the happy path.

const ScenarioLoaderScript = preload("res://ScenSyn/scripts/core/scenario_loader.gd")
const NEUTRAL_MANAGER_PATH: String = "res://ScenSyn/scripts/core/neutral_metaprompt_manager.gd"

## Registration order is load-bearing twice: it drives Collection dropdown order
## in the mode popup, and resolve_scenario returns the first Collection whose
## scenario list contains a name. Open Play sits last and registers no authored
## templates — its Scenarios come from the user's library under
## Documents/Synesyn — so it cannot shadow a curated Collection.
const EXPECTED_COLLECTIONS: Dictionary = {
	"workshop_catalyst": ["decision_triage"],
	"story_catalyst": ["sustainability", "cultural_narratives", "open_play"],
}

var _failures: Array[String] = []
var _global_node: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_global_node = root.get_node_or_null("Global")
	if _global_node == null:
		_failures.append("Global autoload was unavailable")
		_finish()
		return
	_test_registry_resolution()
	_test_every_collection_has_its_own_manager()
	_test_loader_paths()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("Session Type registry tests: all passed")
		quit(0)
		return
	for failure_message in _failures:
		print("FAIL: " + failure_message)
	quit(1)


func _test_registry_resolution() -> void:
	for session_type_id: String in EXPECTED_COLLECTIONS.keys():
		var expected: Array = EXPECTED_COLLECTIONS[session_type_id]
		var actual: Array = _global_node.call("get_collection_ids", session_type_id)
		_expect(
			actual == expected,
			(
				"%s Collections are %s but the registry declares %s. "
				+ "If this is intended, update EXPECTED_COLLECTIONS here and check "
				+ "the Collection dropdown order in the mode popup."
			) % [session_type_id, str(expected), str(actual)]
		)
	var workshop_resolution: Dictionary = _global_node.call(
		"resolve_scenario",
		"karlsruhe_library_future_design",
		"",
		""
	)
	_expect(
		workshop_resolution.get("session_type_id", "") == "workshop_catalyst"
		and workshop_resolution.get("collection_id", "") == "decision_triage",
		"Workshop scenario resolution failed"
	)
	var story_resolution: Dictionary = _global_node.call(
		"resolve_scenario",
		"stochastic_dreams",
		"",
		""
	)
	_expect(
		story_resolution.get("session_type_id", "") == "story_catalyst"
		and story_resolution.get("collection_id", "") == "cultural_narratives",
		"Cultural scenario resolution failed"
	)
	_expect(
		(_global_node.call("resolve_scenario", "not_registered", "", "") as Dictionary).is_empty(),
		"Unknown scenario resolved unexpectedly"
	)


## A Collection missing from SESSION_TYPE_MANAGER_PATHS still returns a manager:
## Global falls back to the neutral one and only pushes an error. That means the
## session runs with generic prompting instead of its own, which is easy to ship
## by accident, so assert each Collection resolves to a manager of its own.
func _test_every_collection_has_its_own_manager() -> void:
	for session_type_id: String in EXPECTED_COLLECTIONS.keys():
		for collection_id: String in _global_node.call("get_collection_ids", session_type_id):
			var manager: Node = _global_node.call(
				"get_metaprompt_manager_for_collection",
				session_type_id,
				collection_id
			)
			if manager == null:
				_failures.append(
					"No metaprompt manager returned for %s/%s" % [session_type_id, collection_id]
				)
				continue
			var manager_script: Script = manager.get_script()
			var script_path: String = "" if manager_script == null else manager_script.resource_path
			_expect(
				script_path != NEUTRAL_MANAGER_PATH,
				(
					"%s/%s fell back to the neutral metaprompt manager, so it would run "
					+ "with generic prompting. Add its script to SESSION_TYPE_MANAGER_PATHS."
				) % [session_type_id, collection_id]
			)
			manager.free()


## Every registered Scenario must have a file behind it, not just the sampled
## few: a typo in SESSION_TYPE_COLLECTIONS otherwise surfaces as an empty session
## at selection time.
func _test_loader_paths() -> void:
	var checked: int = 0
	for session_type_id: String in EXPECTED_COLLECTIONS.keys():
		for collection_id: String in _global_node.call("get_collection_ids", session_type_id):
			for scenario_id: String in _global_node.call(
				"get_scenario_names",
				session_type_id,
				collection_id
			):
				var scenario_path: String = ScenarioLoaderScript.get_scenario_path(
					scenario_id,
					session_type_id,
					collection_id
				)
				_expect(
					FileAccess.file_exists(scenario_path),
					"Registered Scenario %s/%s/%s has no file at: %s" % [
						session_type_id,
						collection_id,
						scenario_id,
						scenario_path,
					]
				)
				checked += 1
	_expect(checked > 0, "No registered Scenarios were checked")
	_expect(
		ScenarioLoaderScript.get_scenario_path(
			"unknown",
			"workshop_catalyst",
			"unknown"
		).is_empty(),
		"Unknown Collection produced a loader path"
	)


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)
