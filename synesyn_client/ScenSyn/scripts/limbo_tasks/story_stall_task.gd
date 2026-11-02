@tool
extends BTAction
class_name StoryStallTask

@export var stall_threshold: int = 3

func _tick(_delta: float) -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var story_state_node: Variant = tree.root.get_node_or_null("StoryState") if tree else null
	if not story_state_node or not story_state_node.has_method("get_inactive_turns"):
		return BT.Status.FAILURE
	if story_state_node.get_inactive_turns() >= stall_threshold:
		if story_state_node.has_method("trigger_event"):
			story_state_node.trigger_event("STORY_STALL")
		return BT.Status.SUCCESS
	return BT.Status.FAILURE 
