extends SceneTree

const ProposalStoreScript = preload(
	"res://addons/syntree/scripts/resources/internal/context_graph_proposal_store.gd"
)


class FakeContentState:
	extends RefCounted

	var source_data: Dictionary = {
		"meta": {"ai_context": {}},
		"content": {"nodes": []},
	}

	func get_source_data(_source_id: String) -> Dictionary:
		return source_data.duplicate(true)

	func update_source(
		_source_id: String,
		updated_source: Dictionary
	) -> bool:
		source_data = updated_source.duplicate(true)
		return true


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var store: RefCounted = ProposalStoreScript.new()
	var state := FakeContentState.new()
	var suggestion: Dictionary = {
		"id": "proposal-a",
		"proposal_type": "relationship",
		"operation": "add_edge",
		"payload": {
			"id": "edge-a",
			"from": "node-a",
			"to": "node-b",
			"relation": "supports",
			"provenance_refs": ["trace:a"],
		},
		"evidence_refs": ["artifact:a"],
	}
	var saved: Dictionary = store.call(
		"upsert_suggestion",
		state,
		"source-a",
		suggestion
	)
	var reviewed: Dictionary = store.call(
		"review",
		state,
		"source-a",
		"proposal-a",
		"rejected",
		{},
		"Insufficient evidence"
	)
	var suppressed: Dictionary = store.call(
		"upsert_suggestion",
		state,
		"source-a",
		suggestion
	)
	var proposals: Array = store.call(
		"get_proposals",
		state,
		"source-a"
	)
	var did_pass: bool = (
		bool(saved.get("ok", false))
		and bool(reviewed.get("ok", false))
		and (
			reviewed.get("event", {}) as Dictionary
		).get("decision", "") == "rejected"
		and bool(suppressed.get("suppressed", false))
		and proposals.size() == 1
		and (
			proposals[0] as Dictionary
		).get("status", "") == "rejected"
	)
	if did_pass:
		print("Context graph proposal store tests: all passed")
		quit(0)
		return
	push_error("Proposal review decisions were lost or resurfaced")
	quit(1)
