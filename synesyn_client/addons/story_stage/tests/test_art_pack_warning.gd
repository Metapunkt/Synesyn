extends SceneTree

## Story Stage emits a single art-pack warning instead of per-file load spam.
##
## Run (from synesyn_client):
##   godot --headless --path . --script res://addons/story_stage/tests/test_art_pack_warning.gd

const StoryStageCharacterScript = preload("res://addons/story_stage/scripts/story_stage_character.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_warning_constant()
	_test_warn_once()
	_test_missing_res_texture_does_not_load()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("Story Stage art pack warning tests: all passed")
		quit(0)
		return
	for failure_message in _failures:
		print("FAIL: " + failure_message)
	quit(1)


func _expect(cond: bool, message: String) -> void:
	if not cond:
		_failures.append(message)


func _test_warning_constant() -> void:
	var text: String = str(StoryStageCharacterScript.ART_PACK_WARNING)
	_expect(
		text.find("Story Stage art pack not installed") != -1,
		"ART_PACK_WARNING must include the user-facing title"
	)
	_expect(
		text.find("utilities/assets/story_stage_sprites.py") != -1,
		"ART_PACK_WARNING must point at story_stage_sprites.py"
	)
	_expect(
		text.find("docs/user-guide/story-stage-sprites.md") != -1,
		"ART_PACK_WARNING must point at the user-guide docs"
	)


func _test_warn_once() -> void:
	StoryStageCharacterScript.reset_art_pack_warning_for_tests()
	_expect(
		StoryStageCharacterScript._art_pack_warning_emitted == false,
		"warning flag should reset for tests"
	)
	StoryStageCharacterScript.warn_art_pack_missing_once()
	StoryStageCharacterScript.warn_art_pack_missing_once()
	StoryStageCharacterScript.warn_art_pack_missing_once()
	_expect(
		StoryStageCharacterScript._art_pack_warning_emitted == true,
		"warning flag should stay true after the first emit"
	)


func _test_missing_res_texture_does_not_load() -> void:
	StoryStageCharacterScript.reset_art_pack_warning_for_tests()
	var missing := "res://ScenSyn/story_stage/sprites/__missing_pack__/idle/0.png"
	var tex: Texture2D = StoryStageCharacterScript._load_texture_any(missing)
	_expect(tex == null, "missing pack texture must return null")
	_expect(
		StoryStageCharacterScript._art_pack_warning_emitted == true,
		"missing pack texture should emit the single art-pack warning"
	)
	# Second miss must not clear or require a second distinct warning path.
	var tex2: Texture2D = StoryStageCharacterScript._load_texture_any(missing)
	_expect(tex2 == null, "second missing load must still return null")
	_expect(
		StoryStageCharacterScript._art_pack_warning_emitted == true,
		"warning remains one-shot after repeated misses"
	)
