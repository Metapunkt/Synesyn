extends SceneTree

const ContextSetPanelScene = preload(
	"res://addons/syntree/scenes/context_set_panel.tscn"
)
const ContextPreviewScene = preload(
	"res://addons/syntree/scenes/context_preview_panel.tscn"
)
const ContextSetPanelControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/context_set_panel_controller.gd"
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


class FakeCompilerBridge:
	extends RefCounted

	func compile_sources(
		_content_state: Object,
		_source_ids: Array[String],
		options: Dictionary
	) -> Dictionary:
		var context_set: Dictionary = options.get("context_set_override", {})
		return {
			"ok": true,
			"context_set_id": context_set.get("id", ""),
			"included_nodes": [],
			"omitted_nodes": [],
			"compiled_text": "preview text",
			"estimated_tokens": 3,
			"token_budget": 100,
			"estimator_id": "test",
		}


class FakeHubClient:
	extends RefCounted
	var committed_document: Dictionary = {}

	func check_health() -> Dictionary:
		return {"ok": true}

	func get_artifact_json(_artifact_id: String) -> Dictionary:
		return {"ok": true, "json": committed_document, "record": {}}

	func create_artifact_inline_json(
		_artifact_type: String,
		inline_json: Dictionary,
		_metadata: Dictionary = {}
	) -> Dictionary:
		committed_document = inline_json.duplicate(true)
		return {"ok": true, "artifact_id": "version-1"}

	func query_artifacts_by_type(
		_artifact_type: String,
		_limit: int = 50
	) -> Dictionary:
		return {
			"ok": true,
			"result": {
				"columns": ["id", "created_at", "metadata_json"],
				"rows": [[
					"version-1",
					"2026-07-10T19:00:00Z",
					JSON.stringify({
						"owner_source_id": "source-a",
						"context_set_id": "research",
					}),
				]],
			},
		}


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var sidebar: TabContainer = TabContainer.new()
	root.add_child(sidebar)
	var panel: Control = ContextSetPanelScene.instantiate()
	var preview: Control = ContextPreviewScene.instantiate()
	sidebar.add_child(preview)
	sidebar.add_child(panel)
	var content_state: FakeContentState = FakeContentState.new()
	content_state.sources["source-a"] = {
		"meta": {"ai_context": {}},
		"content": {"nodes": [{"node_id": "node-a", "content": "A"}]},
	}
	var manager: RefCounted = RefCounted.new()
	manager.set_meta("use_context_compiler", true)
	var hub_client: FakeHubClient = FakeHubClient.new()
	var controller: RefCounted = ContextSetPanelControllerScript.new()
	controller.call(
		"setup",
		panel,
		content_state,
		preview,
		manager,
		FakeCompilerBridge.new(),
		hub_client
	)
	var node_ids: Array[String] = ["node-a"]
	controller.call("refresh_graph", "source-a", node_ids)
	panel.save_set_requested.emit({
		"id": "research",
		"label": "Research",
		"entry_node_ids": ["node-a"],
		"allowed_relationship_types": [],
		"traversal_depth": 1,
		"budget_policy": {"max_tokens": 100},
	})
	panel.activation_save_requested.emit(
		"node-a",
		{"mode": "always", "conditions": {}, "priority": 0}
	)
	panel.preview_set_requested.emit({
		"id": "research",
		"label": "Research",
		"entry_node_ids": ["node-a"],
		"allowed_relationship_types": [],
		"traversal_depth": 1,
		"activation_rules": {"mode": "manual_only"},
		"budget_policy": {"max_tokens": 100},
		"prompt_chain_ids": [],
		"status": "draft",
	})
	panel.commit_set_requested.emit({
		"id": "research",
		"label": "Research",
		"entry_node_ids": ["node-a"],
		"allowed_relationship_types": [],
		"traversal_depth": 1,
		"activation_rules": {"mode": "manual_only"},
		"budget_policy": {"max_tokens": 100},
		"prompt_chain_ids": [],
		"status": "draft",
	})
	await process_frame
	var saved_source: Dictionary = content_state.sources["source-a"]
	var source_meta: Dictionary = saved_source.get("meta", {})
	var ai_context: Dictionary = source_meta.get("ai_context", {})
	var saved_sets: Array = ai_context.get("context_sets", [])
	var content_data: Dictionary = saved_source.get("content", {})
	var saved_nodes: Array = content_data.get("nodes", [])
	var saved_node: Dictionary = saved_nodes[0]
	var frozen: Dictionary = manager.get_meta(
		"frozen_context_compile_result",
		{}
	)
	var committed_set: Dictionary = saved_sets[0]
	var history_list: ItemList = panel.get_node("%HistoryList")
	var is_valid: bool = (
		saved_sets.size() == 1
		and committed_set.get("status", "") == "committed"
		and (
			saved_node.get("activation", {}) as Dictionary
		).get("mode", "") == "always"
		and frozen.get("compiled_text", "") == "preview text"
		and frozen.get("context_set_id", "") == "research"
		and ai_context.get("context_graph_version_id", "") == "version-1"
		and history_list.item_count == 1
	)
	sidebar.queue_free()
	if is_valid:
		print("Context set panel controller tests: all passed")
		quit(0)
		return
	push_error("Context Set panel controller did not persist and preview drafts")
	quit(1)
