extends SceneTree

const TracePanelScene = preload(
	"res://addons/syntree/scenes/context_trace_panel.tscn"
)


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var panel: Control = TracePanelScene.instantiate()
	root.add_child(panel)
	panel.call("set_trace", {
		"run_id": "ctxrun-a",
		"status": "completed",
		"context_path": "context_compiler",
		"estimated_tokens": 30,
		"token_budget": 100,
		"compiled_text_hash": "hash-a",
		"runtime_compiled_text": "compiled context body",
		"included_nodes": [{
			"node_id": "source-a::node-a",
			"reason": "entry",
		}],
		"omitted_nodes": [{
			"node_id": "source-a::node-b",
			"reason": "excluded",
		}],
	})
	var included_list: ItemList = panel.get_node(
		"MarginContainer/VBoxContainer/IncludedNodes"
	)
	var omitted_list: ItemList = panel.get_node(
		"MarginContainer/VBoxContainer/OmittedNodes"
	)
	var status_label: Label = panel.get_node(
		"MarginContainer/VBoxContainer/TraceStatus"
	)
	var details_text: TextEdit = panel.get_node(
		"MarginContainer/VBoxContainer/TraceDetails"
	)
	var compiled_context: TextEdit = panel.get_node(
		"MarginContainer/VBoxContainer/CompiledContext"
	)
	var did_pass: bool = (
		included_list.item_count == 1
		and omitted_list.item_count == 1
		and status_label.text.contains("30/100")
		and details_text.text.contains("ctxrun-a")
		and not details_text.text.contains("private compiled context")
		and compiled_context.text == "compiled context body"
	)
	panel.queue_free()
	if did_pass:
		print("Context trace panel tests: all passed")
		quit(0)
		return
	push_error("Context trace panel did not explain the recorded run")
	quit(1)
