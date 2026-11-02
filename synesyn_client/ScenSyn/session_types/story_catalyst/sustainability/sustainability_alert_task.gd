extends BTAction
class_name SustainabilityAlertTask

@export var energy_threshold: int = 30
@export var resource_statuses: Array[String] = ["critical", "low"]

func _tick(_delta: float) -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var story_state_node: Variant = tree.root.get_node_or_null("StoryState") if tree else null
	if not story_state_node or not story_state_node.has_method("get_state"):
		return BT.Status.FAILURE
	var state: Dictionary = story_state_node.get_state()
	var energy = state.get("energy", 100)
	var resource_status = state.get("resource_status", "normal")
	if energy <= energy_threshold or resource_status in resource_statuses:
		var narrator_node = blackboard.get_var("narrator_node")
		if narrator_node:
			narrator_node._maybe_generate_narration("SUSTAINABILITY_ALERT", state)
	return BT.Status.SUCCESS 