extends SceneTree

const GraphWorkspaceArtifactClientScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_artifact_client.gd"
)
const GraphWorkspaceDocumentScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_document.gd"
)

var _failures: int = 0


class FakeHubClient:
	extends RefCounted
	var document: Dictionary = {}
	var last_commit: Dictionary = {}

	func get_artifact_json(_artifact_id: String) -> Dictionary:
		return {"ok": true, "json": document, "record": {"id": "artifact-1"}}

	func create_artifact_inline_json(
		artifact_type: String,
		inline_json: Dictionary,
		metadata: Dictionary = {}
	) -> Dictionary:
		last_commit = {
			"artifact_type": artifact_type,
			"document": inline_json,
			"metadata": metadata,
		}
		document = JSON.parse_string(JSON.stringify(inline_json))
		return {"ok": true, "artifact_id": "artifact-2"}

	func query_artifacts_by_type(
		_artifact_type: String,
		_limit: int = 50
	) -> Dictionary:
		return {
			"ok": true,
			"result": {
				"columns": ["id", "created_at", "metadata_json"],
				"rows": [
					[
						"artifact-1",
						"2026-01-01T00:00:00Z",
						JSON.stringify({"owner_source_id": "source-a"}),
					],
					[
						"artifact-2",
						"2026-02-01T00:00:00Z",
						JSON.stringify({"owner_source_id": "source-b"}),
					],
				],
			},
		}


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	var hub_client := FakeHubClient.new()
	hub_client.document = _valid_document()
	var client: RefCounted = GraphWorkspaceArtifactClientScript.new()
	_expect(bool(client.call("setup", hub_client)), "artifact client setup failed")
	var load_result: Dictionary = await client.call("load_graph", "artifact-1", "context_graph")
	_expect(bool(load_result.get("ok", false)), "valid graph artifact did not load")
	var commit_result: Dictionary = await client.call(
		"commit_graph",
		"ui.context_graph",
		hub_client.document,
		{"owner": "syntree"},
		"artifact-1",
		["trace-1"]
	)
	_expect(bool(commit_result.get("ok", false)), "valid graph artifact did not commit")
	_expect(
		hub_client.last_commit.get("document", {}).get("previous_version_id", "") == "artifact-1",
		"previous version id was not included"
	)
	_expect(
		hub_client.last_commit.get("metadata", {}).get("trace_refs", []) == ["trace-1"],
		"trace references were not included"
	)
	var reloaded: Dictionary = await client.call(
		"load_graph",
		"artifact-2",
		"context_graph"
	)
	_expect(
		bool(reloaded.get("ok", false))
		and (
			reloaded.get("document", {}).get("context_sets", []) as Array
		).size() == 1,
		"context sets did not survive committed JSON reload"
	)
	var versions_result: Dictionary = await client.call(
		"list_graph_versions",
		"ui.context_graph",
		{"owner_source_id": "source-a"}
	)
	var versions: Array = versions_result.get("versions", [])
	_expect(
		bool(versions_result.get("ok", false))
		and versions.size() == 1
		and (versions[0] as Dictionary).get("id", "") == "artifact-1",
		"artifact version filtering did not preserve owner scope"
	)
	if _failures == 0:
		print("Graph workspace artifact client tests: all passed")
		quit(0)
		return
	push_error("Graph workspace artifact client tests: %d failure(s)" % _failures)
	quit(1)


func _valid_document() -> Dictionary:
	var document: Dictionary = GraphWorkspaceDocumentScript.create_empty("context_graph")
	document["nodes"] = [{
		"id": "source-a",
		"kind": "content_source",
		"label": "Source A",
		"status": "committed",
		"provenance_refs": ["source:source-a"],
	}]
	document["context_sets"] = [{
		"id": "source-a::research",
		"label": "Research",
		"entry_node_ids": ["source-a"],
		"allowed_relationship_types": [],
		"traversal_depth": 1,
		"activation_rules": {"mode": "manual_only"},
		"budget_policy": {"max_tokens": 1000},
		"status": "committed",
	}]
	return document


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(failure_message)
