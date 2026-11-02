extends SceneTree

const ProvenanceScript = preload(
	"res://addons/syntree/scripts/core/context_graph_provenance.gd"
)
const ProvenanceStoreScript = preload(
	"res://addons/syntree/scripts/resources/internal/context_provenance_store.gd"
)


class FakeContentState:
	extends RefCounted

	var source_data: Dictionary = {
		"meta": {
			"name": "Source A",
			"path": "res://fixtures/source-a.md",
		},
		"content": {
			"nodes": [{
				"node_id": "node-a",
				"content": "Evidence",
			}],
		},
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
	var provenance: RefCounted = ProvenanceScript.new()
	var normalized: Dictionary = provenance.call("normalize", {
		"authorship_kind": "AI_INFERENCE",
		"evidence_status": "supported",
		"review_status": "reviewed",
		"derivation_refs": ["artifact:a", "artifact:a"],
	}, "source:source-a")
	var state := FakeContentState.new()
	var store: RefCounted = ProvenanceStoreScript.new()
	var source_provenance: Dictionary = store.call(
		"get_provenance",
		state,
		"source-a",
		"source-a"
	)
	var saved: Dictionary = store.call(
		"set_provenance",
		state,
		"source-a",
		"node-a",
		normalized
	)
	var stored_provenance: Dictionary = store.call(
		"get_provenance",
		state,
		"source-a",
		"node-a"
	)
	var source_location: Dictionary = source_provenance.get(
		"source_location",
		{}
	)
	var did_pass: bool = (
		normalized.get("authorship_kind", "") == "ai_inference"
		and normalized.get("origin_ref", "") == "source:source-a"
		and (
			normalized.get("derivation_refs", []) as Array
		).size() == 1
		and source_location.get("uri", "") == (
			"res://fixtures/source-a.md"
		)
		and bool(saved.get("ok", false))
		and stored_provenance.get("evidence_status", "") == "supported"
		and stored_provenance.get("review_status", "") == "reviewed"
	)
	if did_pass:
		print("Context graph provenance tests: all passed")
		quit(0)
		return
	push_error("Context Graph provenance was inferred, lost, or not persisted")
	quit(1)
