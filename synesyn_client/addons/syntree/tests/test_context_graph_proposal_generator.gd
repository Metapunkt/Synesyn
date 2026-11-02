extends SceneTree

const ProposalGeneratorScript = preload(
	"res://addons/syntree/scripts/services/prompting/context_graph_proposal_generator.gd"
)


class FakeApiService:
	extends RefCounted

	var received_context: String = ""

	func process_message_with_history(
		_messages: Array,
		context_text: String,
		_model_id: String
	) -> Dictionary:
		received_context = context_text
		return {
			"success": true,
			"response": """```json
[{
  "proposal_type": "relationship",
  "operation": "add_edge",
  "payload": {
    "id": "edge-a",
    "from": "node-a",
    "to": "node-b",
    "relation": "supports",
    "status": "suggested",
    "provenance_refs": ["trace:a"]
  },
  "rationale": "Evidence supports the claim",
  "evidence_refs": ["artifact:a"],
  "affected_record_ids": ["node-a", "node-b"],
  "confidence": 0.8
}]
```""",
		}


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var generator: RefCounted = ProposalGeneratorScript.new()
	var api := FakeApiService.new()
	var result: Dictionary = await generator.call(
		"generate",
		api,
		{
			"graph_schema_version": 1,
			"graph_kind": "context_graph",
			"nodes": [],
			"edges": [],
		},
		"Find evidence links",
		"model-a"
	)
	var proposals: Array = result.get("proposals", [])
	var proposal: Dictionary = {}
	if not proposals.is_empty():
		proposal = proposals[0]
	var did_pass: bool = (
		bool(result.get("ok", false))
		and proposals.size() == 1
		and proposal.get("status", "") == "suggested"
		and proposal.get("model_id", "") == "model-a"
		and api.received_context.contains("Never claim to commit")
		and not generator.has_method("commit")
	)
	if did_pass:
		print("Context graph proposal generator tests: all passed")
		quit(0)
		return
	push_error("Proposal generator parsed invalid data or gained commit access")
	quit(1)
