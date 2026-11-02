extends SceneTree

const PromptChainArtifactPayloadBuilderScript = preload(
	"res://addons/syntree/scripts/services/prompting/prompt_chain_artifact_payload_builder.gd"
)


func _init() -> void:
	var builder: RefCounted = PromptChainArtifactPayloadBuilderScript.new()
	var binding: Dictionary = {
		"context_graph_artifact_id": "graph-a",
		"context_graph_version_id": "graph-v2",
		"context_set_id": "source-a::research",
	}
	var payload: Dictionary = builder.call(
		"build",
		{
			"name": "Chain",
			"blocks": [{"id": "block-a", "text": "A"}],
			"slots": [{"name": "phase", "default": "review"}],
			"context_binding": binding,
		},
		"chain-a",
		"syntree_editor",
		"chain-v1",
		1.0
	)
	var inline_json: Dictionary = payload.get("inline_json", {})
	var metadata: Dictionary = payload.get("metadata", {})
	var provenance: Dictionary = metadata.get("provenance", {})
	var source_artifacts: Array = provenance.get("source_artifacts", [])
	if (
		inline_json.get("context_binding", {}) == binding
		and (inline_json.get("slots", []) as Array).size() == 1
		and inline_json.get("prev_artifact_id", "") == "chain-v1"
		and source_artifacts.size() == 1
		and (
			source_artifacts[0] as Dictionary
		).get("version_id", "") == "graph-v2"
	):
		print("Prompt chain artifact payload builder tests: all passed")
		quit(0)
		return
	push_error("Prompt Chain Hub payload omitted binding provenance")
	quit(1)
