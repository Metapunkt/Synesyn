extends SceneTree

const PromptChainStoreScript = preload(
	"res://addons/syntree/scripts/services/prompting/prompt_chain_store.gd"
)


func _init() -> void:
	var chain: Dictionary = {
		"id": "chain-a",
		"name": "Chain A",
		"blocks": [
			{"label": "First", "enabled": true, "text": "A"},
			{
				"id": "block-001",
				"label": "Second",
				"enabled": true,
				"text": "B",
				"context_override": {
					"traversal_depth": 1,
					"allowed_relationship_types": ["supports", "supports"],
					"pinned_node_ids": ["node-a"],
				},
			},
		],
		"context_binding": {
			"context_graph_artifact_id": "artifact-a",
			"context_graph_version_id": "version-a",
			"context_set_id": "source-a::research",
			"owner_source_id": "source-a",
			"compiler_preset": "BALANCED",
			"max_tokens": 4000,
		},
	}
	var normalized: Dictionary = PromptChainStoreScript.normalize_chain(chain)
	var blocks: Array = normalized.get("blocks", [])
	var binding: Dictionary = normalized.get("context_binding", {})
	var round_trip_any: Variant = JSON.parse_string(JSON.stringify(normalized))
	var round_trip_binding: Dictionary = {}
	if typeof(round_trip_any) == TYPE_DICTIONARY:
		round_trip_binding = (
			round_trip_any as Dictionary
		).get("context_binding", {})
	var is_valid: bool = (
		blocks.size() == 2
		and (blocks[0] as Dictionary).get("id", "") == "block-001"
		and (blocks[1] as Dictionary).get("id", "") == "block-001-2"
		and (
			(blocks[1] as Dictionary).get(
				"context_override",
				{}
			) as Dictionary
		).get("allowed_relationship_types", []) == ["supports"]
		and binding.get("compiler_preset", "") == "balanced"
		and typeof(round_trip_any) == TYPE_DICTIONARY
		and round_trip_binding.get("context_set_id", "")
		== binding.get("context_set_id", "")
		and int(round_trip_binding.get("max_tokens", 0))
		== int(binding.get("max_tokens", 0))
	)
	if is_valid:
		print("Prompt chain store binding tests: all passed")
		quit(0)
		return
	push_error(
		"Prompt chain binding normalization was not stable: %s"
		% str(normalized)
	)
	quit(1)
