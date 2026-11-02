## Purpose: Internal helper for ContentBus editor-only debounced persistence scheduling.
@tool
extends Node

const DEFAULT_DELAY_SEC := 0.25

var _delay_sec: float = DEFAULT_DELAY_SEC
var _inflight: bool = false
var _persist_cb: Callable = Callable()

func setup(persist_cb: Callable, delay_sec: float = DEFAULT_DELAY_SEC) -> void:
	_persist_cb = persist_cb
	_delay_sec = max(0.0, delay_sec)

func request_persist() -> void:
	# Only persist automatically in the editor; in exported builds `res://` is not writable.
	if not Engine.is_editor_hint():
		return
	if _inflight:
		return
	_inflight = true

	var ml: Variant = Engine.get_main_loop()
	if ml is SceneTree:
		var t := (ml as SceneTree).create_timer(_delay_sec)
		t.timeout.connect(_on_timeout)
		return

	# Fallback (unexpected): no SceneTree, persist immediately.
	_on_timeout()

func _on_timeout() -> void:
	_inflight = false
	if _persist_cb.is_valid():
		_persist_cb.call()

