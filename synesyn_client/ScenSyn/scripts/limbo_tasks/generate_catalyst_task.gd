# GenerateCatalystTask.gd
@tool
extends BTTask
class_name GenerateCatalystTask

const DynamicContextManager = preload("res://ScenSyn/scripts/core/dynamic_context_manager.gd")

@export var situation_description := "We need to keep this conversation on track."

var dynamic_context_manager: DynamicContextManager

func _setup():
	dynamic_context_manager = DynamicContextManager.new()

func _tick(_delta: float) -> int:
	# Only generate new dilemmas if there are none currently active
	if not StoryState.get_current_dilemmas().is_empty():
		return BT.Status.FAILURE

	print("GenerateCatalystTask: No active dilemmas. Generating new narrative catalyst...")
	var dilemmas = await dynamic_context_manager.generate_narrative_catalyst(situation_description)

	if not dilemmas.is_empty():
		print("GenerateCatalystTask: Successfully generated dilemmas. Storing in StoryState.")
		StoryState.set_current_dilemmas(dilemmas)
		return BT.Status.SUCCESS
	else:
		print("GenerateCatalystTask: Failed to generate dilemmas.")
		return BT.Status.FAILURE 
