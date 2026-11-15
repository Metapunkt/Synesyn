extends VBoxContainer
## Drop target for a kanban column (wired from StageBoardView).


var column_id: String = ""
var on_task_dropped: Callable = Callable()


func configure(col_id: String, dropped: Callable) -> void:
	column_id = col_id
	on_task_dropped = dropped
	mouse_filter = Control.MOUSE_FILTER_STOP


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return _task_from_payload(data) != null


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var task: WorkplanTask = _task_from_payload(data)
	if task == null or column_id.is_empty():
		return
	if on_task_dropped.is_valid():
		on_task_dropped.call(column_id, task)


func _task_from_payload(data: Variant) -> WorkplanTask:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var payload: Dictionary = data
	return payload.get("task") as WorkplanTask