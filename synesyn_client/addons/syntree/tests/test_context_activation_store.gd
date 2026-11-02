extends SceneTree

const ContextActivationStoreScript = preload(
	"res://addons/syntree/scripts/resources/internal/context_activation_store.gd"
)


class FakeContentState:
	extends RefCounted
	var sources: Dictionary = {}

	func get_source_data(source_id: String) -> Dictionary:
		return (sources.get(source_id, {}) as Dictionary).duplicate(true)

	func update_source(source_id: String, source_data: Dictionary) -> bool:
		if not sources.has(source_id):
			return false
		sources[source_id] = source_data.duplicate(true)
		return true


func _init() -> void:
	var content_state: FakeContentState = FakeContentState.new()
	content_state.sources["source-a"] = {
		"meta": {"ai_context": {}},
		"content": {"nodes": [{"node_id": "node-a", "content": "A"}]},
	}
	var store: RefCounted = ContextActivationStoreScript.new()
	var activation: Dictionary = {
		"mode": "conditional",
		"conditions": {"app_scope": "syntree"},
		"priority": 4,
	}
	var save_result: Dictionary = store.call(
		"set_activation",
		content_state,
		"source-a",
		"source-a::node-a",
		activation
	)
	var loaded: Dictionary = store.call(
		"get_activation",
		content_state,
		"source-a",
		"source-a::node-a"
	)
	var source_save: Dictionary = store.call(
		"set_activation",
		content_state,
		"source-a",
		"source-a",
		{"mode": "always"}
	)
	var source_loaded: Dictionary = store.call(
		"get_activation",
		content_state,
		"source-a",
		"source-a"
	)
	if (
		bool(save_result.get("ok", false))
		and loaded == activation
		and bool(source_save.get("ok", false))
		and source_loaded.get("mode", "") == "always"
	):
		print("Context activation store tests: all passed")
		quit(0)
		return
	push_error("Context activation store did not round-trip node/source policy")
	quit(1)
