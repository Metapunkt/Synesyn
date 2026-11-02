extends SceneTree

const PromptChainBindingPanelScene = preload(
	"res://addons/syntree/scenes/prompt_chain_binding_panel.tscn"
)

var _proposed: Dictionary = {}


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var panel: Control = PromptChainBindingPanelScene.instantiate()
	root.add_child(panel)
	panel.propose_binding_requested.connect(_on_proposed)
	var binding: Dictionary = {
		"context_graph_artifact_id": "artifact-a",
		"context_graph_version_id": "version-a",
		"owner_source_id": "source-a",
		"context_set_id": "source-a::research",
		"compiler_preset": "minimal",
		"max_tokens": 1200,
	}
	panel.call("set_binding", binding)
	var propose_button: Button = panel.get_node("%ProposeBindingButton")
	propose_button.pressed.emit()
	panel.call("set_preview_result", {
		"ok": true,
		"warnings": [],
		"compile_result": {
			"estimated_tokens": 5,
			"token_budget": 1200,
			"compiled_text": "Bound preview",
		},
	})
	var preview_text: TextEdit = panel.get_node("%BindingPreviewText")
	var is_valid: bool = (
		_proposed == binding
		and preview_text.text == "Bound preview"
	)
	panel.queue_free()
	if is_valid:
		print("Prompt chain binding panel tests: all passed")
		quit(0)
		return
	push_error("Prompt Chain binding panel did not preserve proposal values")
	quit(1)


func _on_proposed(binding: Dictionary) -> void:
	_proposed = binding
