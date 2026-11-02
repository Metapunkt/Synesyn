extends SceneTree

const ContentStateResourceScript = preload(
	"res://addons/syntree/scripts/resources/content_state_resource.gd"
)


class NoSaveContentSource:
	extends ContentSourceResource

	var save_calls: int = 0

	func save_source(_source_id: String) -> bool:
		save_calls += 1
		return true


func _init() -> void:
	var failures: int = _test_delete_unlinks_and_clears_mapping()
	if failures == 0:
		print("Content state node deletion tests: PASS")
		quit(0)
		return
	push_error("Content state node deletion tests: %d failure(s)" % failures)
	quit(1)


func _test_delete_unlinks_and_clears_mapping() -> int:
	var state: ContentStateResource = ContentStateResourceScript.new()
	var source := NoSaveContentSource.new()
	source.sources_directory = "user://syntree_regression"
	state.content_source = source
	var source_data: Dictionary = {
		"format_version": "1.0.0",
		"meta": {
			"source_id": "source_a",
			"name": "Source A",
			"path": "user://syntree_regression/source_a.json",
			"ai_context": {
				"is_active": false,
				"metaprompt": false,
				"is_stack": false,
			},
		},
		"content": {
			"nodes": [
				{
					"node_id": "node_a",
					"relationships": {
						"parents": [],
						"children": ["node_b"],
						"dependencies": ["node_b"],
						"associations": ["node_b"],
					},
				},
				{
					"node_id": "node_b",
					"relationships": {
						"parents": ["node_a"],
						"children": [],
						"dependencies": [],
						"associations": [],
					},
				},
			],
			"context_graph_edges": [{
				"id": "edge-a-b",
				"from": "node_a",
				"to": "node_b",
				"relation": "supports",
				"status": "committed",
				"provenance_refs": [],
			}],
		},
	}
	source.add_or_update_source_data(source_data)
	var failures: int = _expect(
		state.get_source_for_node("node_b") == "source_a",
		"fixture node mapping was not registered"
	)
	var removed: bool = state.remove_node_from_source("source_a", "node_b")
	var updated_source: Dictionary = state.get_source_data("source_a")
	var nodes: Array = updated_source.get("content", {}).get("nodes", [])
	var remaining_node: Dictionary = nodes[0] if not nodes.is_empty() else {}
	var relationships: Dictionary = remaining_node.get("relationships", {})
	var rich_edges: Array = updated_source.get("content", {}).get(
		"context_graph_edges",
		[]
	)
	failures += _expect(removed, "resource-layer node removal failed")
	failures += _expect(
		nodes.size() == 1
		and str(remaining_node.get("node_id", "")) == "node_a",
		"deleted node remained in source data"
	)
	failures += _expect(
		(relationships.get("children", []) as Array).is_empty()
		and (relationships.get("dependencies", []) as Array).is_empty()
		and (relationships.get("associations", []) as Array).is_empty(),
		"normalization left stale relationship references"
	)
	failures += _expect(
		rich_edges.is_empty(),
		"node deletion left an incident rich edge"
	)
	failures += _expect(
		state.get_source_for_node("node_b").is_empty(),
		"deleted node left a stale node-to-source mapping"
	)
	failures += _expect(
		source.save_calls >= 1,
		"node removal was not persisted through the resource API"
	)
	return failures


func _expect(condition: bool, failure_message: String) -> int:
	if condition:
		return 0
	push_error(failure_message)
	return 1
