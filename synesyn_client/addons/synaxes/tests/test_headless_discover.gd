extends SceneTree
## REQ-NDP-024 acceptance: analysis controller runs import→embed→discover with no dock UI.
## Asserts Dream Inbox candidates are non-empty on demo fixture data (Tier 2, no consent).
##
## Run (from synesyn_client, using Godot 4 path from Cursor settings):
##   godot --headless --path . --script res://addons/synaxes/tests/test_headless_discover.gd

const AnalysisControllerScript = preload(
	"res://addons/synaxes/scripts/runtime/synaxes_analysis_controller.gd"
)
const ClosureControllerScript = preload(
	"res://addons/synaxes/scripts/runtime/synaxes_closure_controller.gd"
)
const TestDataGeneratorScript = preload(
	"res://addons/synaxes/scripts/integration/test_data_generator.gd"
)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: int = 0
	failures += await _test_headless_discover_candidates()
	failures += await _test_no_consent_stays_tier2()
	if failures == 0:
		print("SynAxes headless discover: all passed")
		quit(0)
	else:
		push_error("SynAxes headless discover failures: %d" % failures)
		quit(1)


func _test_headless_discover_candidates() -> int:
	var closure_ctrl: RefCounted = ClosureControllerScript.new()
	var analysis: RefCounted = AnalysisControllerScript.new()
	analysis.closure_ctrl = closure_ctrl
	analysis.use_hub_embeddings = false
	analysis.ensure_engine()

	var gen: RefCounted = TestDataGeneratorScript.new()
	gen.set_data_type("text")
	gen.set_item_count(12)
	var source_data: Array = gen.generate_test_data()
	if source_data.is_empty():
		push_error("FAIL: demo fixture empty")
		return 1
	# Strip pre-baked demo vectors so embed→discover exercises Tier 2 (not imported-embedding short-circuit).
	for i in range(source_data.size()):
		if typeof(source_data[i]) != TYPE_DICTIONARY:
			continue
		var item_dict: Dictionary = (source_data[i] as Dictionary).duplicate()
		item_dict["vector"] = []
		source_data[i] = item_dict

	var result: Dictionary = await analysis.import_embed_discover(
		source_data,
		"",
		{"method": 0, "dim_method": 0, "num_clusters": 4, "use_hub_embeddings": false},
	)
	var patterns: Array = result.get("patterns", [])
	var candidates: Array = closure_ctrl.get_dream_candidates()
	if patterns.is_empty():
		push_error("FAIL: patterns empty after headless discover")
		return 1
	if candidates.is_empty():
		push_error("FAIL: dream candidates empty after headless discover")
		return 1
	var themes_source: String = str(result.get("themes_source", ""))
	if themes_source != "local":
		push_error("FAIL: expected themes_source local, got %s" % themes_source)
		return 1
	print(
		"OK headless discover: %d patterns, %d candidates, themes=%s"
		% [patterns.size(), candidates.size(), themes_source]
	)
	return 0


func _test_no_consent_stays_tier2() -> int:
	## Preference on + no recorded consent → Tier 2 local themes (REQ-NDP-006/024).
	var analysis: RefCounted = AnalysisControllerScript.new()
	analysis.use_hub_embeddings = true
	analysis.ensure_engine()
	var gen: RefCounted = TestDataGeneratorScript.new()
	gen.set_data_type("text")
	gen.set_item_count(6)
	var data: Array = gen.generate_test_data()
	for i in range(data.size()):
		if typeof(data[i]) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = (data[i] as Dictionary).duplicate()
		it["vector"] = []
		data[i] = it
	data = await analysis.apply_embeddings(data, "")
	var tier_label: String = analysis.embedding_tier_label()
	if analysis.themes_source_plain() != "local":
		push_error("FAIL: no-consent path claimed model themes (%s)" % tier_label)
		return 1
	if analysis.embedding_tier != "tier2_tfidf":
		push_error("FAIL: expected tier2_tfidf, got %s" % analysis.embedding_tier)
		return 1
	print("OK no-consent embed: %s" % tier_label)
	return 0
