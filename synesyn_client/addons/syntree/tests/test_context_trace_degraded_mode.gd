extends SceneTree

const ConversationManagerScript = preload(
	"res://addons/syntree/scripts/services/chat/conversation_manager.gd"
)
const TraceCoordinatorScript = preload(
	"res://addons/syntree/scripts/services/chat/internal/context_execution_trace_coordinator.gd"
)


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var manager: Node = ConversationManagerScript.new()
	root.add_child(manager)
	var trace: Dictionary = {
		"schema_version": 1,
		"run_id": "ctxrun-degraded",
		"status": "completed",
	}
	var coordinator: RefCounted = TraceCoordinatorScript.new()
	coordinator.call(
		"complete",
		manager,
		null,
		trace,
		{"status": "completed"}
	)
	var was_available_immediately: bool = (
		manager.get_meta(
			"latest_context_execution_trace",
			{}
		).get("run_id", "") == "ctxrun-degraded"
	)
	await process_frame
	await process_frame
	var warning_text: String = str(manager.get_meta(
		"last_context_trace_persistence_warning",
		""
	))
	manager.queue_free()
	if (
		was_available_immediately
		and warning_text == "hub_client_unavailable"
	):
		print("Context trace degraded mode tests: all passed")
		quit(0)
		return
	push_error("Unavailable trace persistence blocked or hid the local trace")
	quit(1)
