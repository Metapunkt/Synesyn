@tool
extends BTAction
class_name CheckEventTask

@export var event_id: String = ""
@export var narrator_intent: String = "EVENT_NARRATION"

var _event_lines_res = null

func _ready():
	_event_lines_res = load("res://ScenSyn/scripts/utils/event_narration_lines.gd").new()

func _tick(_delta: float) -> int:
	if event_id == "":
		return BT.Status.FAILURE
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var story_state_node: Variant = tree.root.get_node_or_null("StoryState") if tree else null
	if not story_state_node or not story_state_node.has_method("consume_event"):
		return BT.Status.FAILURE
	var payload: Dictionary = story_state_node.consume_event(event_id)
	if payload != {}:
		if _event_lines_res == null:
			_event_lines_res = load("res://ScenSyn/scripts/utils/event_narration_lines.gd").new()
		var line: String = _event_lines_res.get_random_line(event_id)
		if line != "":
			payload["line"] = line
		var narrator = blackboard.get_var("narrator_node")
		if narrator and narrator.has_method("_maybe_generate_narration") and story_state_node.has_method("get_state"):
			narrator._maybe_generate_narration(narrator_intent, story_state_node.get_state(), 0, payload)
		return BT.Status.SUCCESS
	return BT.Status.FAILURE 