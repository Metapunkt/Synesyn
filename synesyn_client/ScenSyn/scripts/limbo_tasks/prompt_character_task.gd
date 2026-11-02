@tool
extends BTAction
class_name PromptCharacterTask

@export var challenge: String = "What will you do next?"

func _tick(_delta: float) -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var story_state_node: Variant = tree.root.get_node_or_null("StoryState") if tree else null
	if not story_state_node or not story_state_node.has_method("get_state"):
		return BT.Status.FAILURE
	var state: Dictionary = story_state_node.get_state()
	var chars: Dictionary = state.get("characters", {})
	var candidates: Array = []
	for k in chars.keys():
		if chars[k].get("is_active", true):
			candidates.append(k)
	if candidates.size() == 0:
		return BT.Status.FAILURE
	var idx = randi() % candidates.size()
	var char_name = candidates[idx]
	if story_state_node.has_method("trigger_event"):
		story_state_node.trigger_event("PROMPT_CHARACTER", {"character_name": char_name, "challenge": challenge})
	return BT.Status.SUCCESS 