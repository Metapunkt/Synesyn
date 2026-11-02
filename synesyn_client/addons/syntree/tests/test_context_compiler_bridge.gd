extends SceneTree

const ContextCompilerBridgeScript = preload(
	"res://addons/syntree/scripts/services/chat/internal/conversation_context_compiler_bridge.gd"
)


class FakeContentState:
	extends RefCounted
	var sources: Dictionary = {}

	func get_source_data(source_id: String) -> Dictionary:
		return sources.get(source_id, {})


func _init() -> void:
	var content_state := FakeContentState.new()
	content_state.sources["source-a"] = {
		"meta": {
			"name": "Source A",
			"source_type": "test",
			"ai_context": {"is_active": true, "metaprompt": false, "is_stack": false},
		},
		"content": {
			"nodes": [{
				"node_id": "node-a",
				"content": "The exact compiled passage.",
				"relationships": {
					"parents": [],
					"children": [],
					"dependencies": [],
					"associations": [],
				},
			}],
		},
	}
	var bridge: RefCounted = ContextCompilerBridgeScript.new()
	var source_ids: Array[String] = ["source-a"]
	var result: Dictionary = bridge.call(
		"compile_sources",
		content_state,
		source_ids,
		{"preset": "minimal", "max_tokens": 100}
	)
	var wrapped: String = bridge.call("wrap_for_chat", result)
	var override_result: Dictionary = bridge.call(
		"compile_sources",
		content_state,
		source_ids,
		{
			"preset": "minimal",
			"max_tokens": 100,
			"context_set_override": {
				"id": "preview-override",
				"entry_node_ids": ["source-a::node-a"],
				"traversal_depth": 0,
				"allowed_relationship_types": [],
				"budget_policy": {},
			},
		}
	)
	var expected_wrapped: String = (
		"[SYNESYN_CONTEXT v2]\n"
		+ str(result.get("compiled_text", "")).strip_edges()
		+ "\n[/SYNESYN_CONTEXT]\n"
	)
	if (
		bool(result.get("ok", false))
		and result.get("compiled_text", "").contains("The exact compiled passage.")
		and wrapped == expected_wrapped
		and override_result.get("context_set_id", "") == "preview-override"
		and override_result.get("compiled_text", "").contains(
			"The exact compiled passage."
		)
	):
		print("Context compiler bridge tests: all passed")
		quit(0)
		return
	push_error(
		"Context compiler preview/submission bridge diverged: %s | %s"
		% [str(result), wrapped]
	)
	quit(1)
