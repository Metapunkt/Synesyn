extends SceneTree

const ContextSetStoreScript = preload(
	"res://addons/syntree/scripts/resources/internal/context_set_store.gd"
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
		"content": {"nodes": []},
	}
	var store: RefCounted = ContextSetStoreScript.new()
	var save_result: Dictionary = store.call(
		"upsert_set",
		content_state,
		"source-a",
		{
			"id": "research",
			"label": "Research",
			"entry_node_ids": ["node-b", "node-b", "node-a"],
			"allowed_relationship_types": ["supports"],
			"traversal_depth": 2,
			"activation_rules": {"mode": "manual_only"},
			"budget_policy": {"max_tokens": 4000},
		}
	)
	var stored_sets: Array = store.call("get_sets", content_state, "source-a")
	var stored_set: Dictionary = {}
	if not stored_sets.is_empty():
		stored_set = stored_sets[0]
	var remove_result: Dictionary = store.call(
		"remove_set",
		content_state,
		"source-a",
		"research"
	)
	var remaining_sets: Array = store.call(
		"get_sets",
		content_state,
		"source-a"
	)
	if (
		bool(save_result.get("ok", false))
		and stored_set.get("entry_node_ids", []) == ["node-b", "node-a"]
		and stored_set.get("status", "") == "draft"
		and bool(remove_result.get("ok", false))
		and remaining_sets.is_empty()
	):
		print("Context set store tests: all passed")
		quit(0)
		return
	push_error("Context set store did not round-trip normalized named sets")
	quit(1)
