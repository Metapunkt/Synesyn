## Purpose: Defer pure work and discard results superseded by newer requests.
extends RefCounted

var _generation: int = 0


func schedule(work: Callable, completion: Callable) -> int:
	_generation += 1
	var request_id: int = _generation
	_run.call_deferred(request_id, work, completion)
	return request_id


func cancel() -> void:
	_generation += 1


func current_generation() -> int:
	return _generation


func _run(
	request_id: int,
	work: Callable,
	completion: Callable
) -> void:
	if request_id != _generation:
		return
	var result: Variant = work.call()
	if request_id != _generation:
		return
	completion.call(result)
