extends SceneTree

const ContextPreviewScene = preload(
	"res://addons/syntree/scenes/context_preview_panel.tscn"
)

var _refresh_options: Dictionary = {}


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var preview: Control = ContextPreviewScene.instantiate()
	root.add_child(preview)
	preview.refresh_requested.connect(_on_refresh_requested)
	preview.call("set_compile_result", {
		"included_nodes": [{
			"node_id": "node-a",
			"reason": "entry",
			"estimated_tokens": 3,
		}],
		"omitted_nodes": [{"node_id": "node-b", "reason": "token_budget"}],
		"estimated_tokens": 3,
		"token_budget": 8,
		"estimator_id": "test-estimator",
		"compiled_text": "Exact context",
	})
	preview.call("refresh_preview")
	var included_list: ItemList = preview.get_node(
		"MarginContainer/VBoxContainer/IncludedList"
	)
	var omitted_list: ItemList = preview.get_node(
		"MarginContainer/VBoxContainer/OmittedList"
	)
	var compiled_text: TextEdit = preview.get_node(
		"MarginContainer/VBoxContainer/CompiledText"
	)
	var is_valid: bool = (
		included_list.item_count == 1
		and omitted_list.item_count == 1
		and compiled_text.text == "Exact context"
		and _refresh_options.get("preset", "") == "balanced"
		and int(_refresh_options.get("max_tokens", 0)) == 8000
	)
	preview.queue_free()
	if is_valid:
		print("Context preview panel tests: all passed")
		quit(0)
		return
	push_error(
		"Context preview panel did not expose compiler output/options: "
		+ "included=%d omitted=%d text=%s options=%s"
		% [
			included_list.item_count,
			omitted_list.item_count,
			compiled_text.text,
			str(_refresh_options),
		]
	)
	quit(1)


func _on_refresh_requested(options: Dictionary) -> void:
	_refresh_options = options
