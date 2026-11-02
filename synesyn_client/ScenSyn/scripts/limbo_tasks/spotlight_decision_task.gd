extends BTAction
class_name SpotlightDecisionTask

func _tick(_delta: float) -> int:
	var narrator_node = blackboard.get_var("narrator_node")
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var story_state_node: Variant = tree.root.get_node_or_null("StoryState") if tree else null
	if narrator_node and story_state_node and story_state_node.has_method("get_state"):
		narrator_node._maybe_generate_narration("SPOTLIGHT", story_state_node.get_state())
	return BT.Status.SUCCESS 