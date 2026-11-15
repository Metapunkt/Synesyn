extends PanelContainer
## Drag source for stage-board task cards (instanced in code by StageBoardView).


var board_task: WorkplanTask


func setup_drag(task: WorkplanTask) -> void:
	board_task = task
	mouse_filter = Control.MOUSE_FILTER_STOP


func _get_drag_data(_at_position: Vector2) -> Variant:
	if board_task == null:
		return null
	var preview: Label = Label.new()
	preview.text = board_task.title
	set_drag_preview(preview)
	return {"task": board_task}