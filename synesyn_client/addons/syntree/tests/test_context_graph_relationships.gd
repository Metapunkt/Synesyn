extends SceneTree

const RelationshipRegistryScript = preload(
	"res://addons/syntree/scripts/core/context_graph_relationship_registry.gd"
)
const ContextGraphEdgeStoreScript = preload(
	"res://addons/syntree/scripts/resources/internal/context_graph_edge_store.gd"
)

var _failures: int = 0


func _init() -> void:
	_test_vocabulary_and_inverse()
	_test_validation_and_cycles()
	_test_store_round_trip_and_reverse()
	_test_all_relationship_round_trips()
	_test_legacy_migration()
	if _failures == 0:
		print("Context graph relationship tests: all passed")
		quit(0)
		return
	push_error("Context graph relationship tests: %d failure(s)" % _failures)
	quit(1)


func _test_vocabulary_and_inverse() -> void:
	var ids: Array[String] = RelationshipRegistryScript.relation_ids()
	_expect(ids.size() == 10, "controlled relationship vocabulary changed unexpectedly")
	var canonical: Dictionary = RelationshipRegistryScript.canonicalize(
		"part_of",
		"child",
		"parent"
	)
	_expect(
		canonical == {"relation": "contains", "from": "parent", "to": "child"},
		"part_of was not canonicalized as reversed contains"
	)


func _test_validation_and_cycles() -> void:
	var node_ids: Array[String] = ["a", "b", "c"]
	var edge_ab: Dictionary = RelationshipRegistryScript.make_edge("contains", "a", "b")
	var edge_bc: Dictionary = RelationshipRegistryScript.make_edge("contains", "b", "c")
	var existing: Array = [edge_ab, edge_bc]
	var cycle_edge: Dictionary = RelationshipRegistryScript.make_edge("contains", "c", "a")
	var cycle_result: Dictionary = RelationshipRegistryScript.validate_edge(
		cycle_edge,
		node_ids,
		existing
	)
	_expect(
		cycle_result.get("errors", []).has("structural_cycle"),
		"structural cycle was accepted"
	)
	var semantic_cycle: Dictionary = RelationshipRegistryScript.make_edge(
		"related_to",
		"c",
		"a"
	)
	var semantic_result: Dictionary = RelationshipRegistryScript.validate_edge(
		semantic_cycle,
		node_ids,
		existing
	)
	_expect(bool(semantic_result.get("ok", false)), "semantic cycle was rejected")
	var self_edge: Dictionary = RelationshipRegistryScript.make_edge("supports", "a", "a")
	var self_result: Dictionary = RelationshipRegistryScript.validate_edge(
		self_edge,
		node_ids,
		[]
	)
	_expect(
		self_result.get("errors", []).has("self_edge_not_allowed"),
		"self edge was accepted"
	)


func _test_store_round_trip_and_reverse() -> void:
	var store: RefCounted = ContextGraphEdgeStoreScript.new()
	var node_ids: Array[String] = ["a", "b"]
	var edge_data: Dictionary = RelationshipRegistryScript.make_edge(
		"supports",
		"a",
		"b",
		"Evidence note",
		0.75,
		["source:a"]
	)
	var inserted: Dictionary = store.call("upsert", [], edge_data, node_ids)
	var edges: Array = inserted.get("edges", [])
	_expect(bool(inserted.get("success", false)), "rich edge insert failed")
	_expect(edges.size() == 1, "rich edge did not round trip")
	var duplicate: Dictionary = RelationshipRegistryScript.make_edge(
		"supports",
		"a",
		"b",
		"",
		null,
		[],
		"different-id"
	)
	var duplicate_result: Dictionary = store.call("upsert", edges, duplicate, node_ids)
	_expect(
		duplicate_result.get("errors", []).has("duplicate_edge"),
		"semantic duplicate edge was accepted"
	)
	var reversed: Dictionary = store.call("reverse", edges, edge_data.get("id", ""), node_ids)
	var reversed_edges: Array = reversed.get("edges", [])
	_expect(
		bool(reversed.get("success", false))
		and reversed_edges[0].get("from", "") == "b"
		and reversed_edges[0].get("to", "") == "a",
		"edge reversal failed"
	)


func _test_all_relationship_round_trips() -> void:
	var store: RefCounted = ContextGraphEdgeStoreScript.new()
	var node_ids: Array[String] = ["a", "b"]
	for relation_id in RelationshipRegistryScript.relation_ids():
		var edge_data: Dictionary = RelationshipRegistryScript.make_edge(
			relation_id,
			"a",
			"b",
			"Round-trip note",
			0.5,
			["source:test"]
		)
		var inserted: Dictionary = store.call("upsert", [], edge_data, node_ids)
		var edges: Array = inserted.get("edges", [])
		_expect(
			bool(inserted.get("success", false))
			and edges.size() == 1
			and not str(edges[0].get("created_at", "")).is_empty()
			and not str(edges[0].get("updated_at", "")).is_empty(),
			"relationship did not round trip: %s" % relation_id
		)


func _test_legacy_migration() -> void:
	var store: RefCounted = ContextGraphEdgeStoreScript.new()
	var nodes: Array = [
		_node("a", ["b"], ["b"], ["b"]),
		_node("b", [], [], []),
	]
	var migrated: Dictionary = store.call("migrate_legacy", nodes, [])
	var edges: Array = migrated.get("edges", [])
	_expect(edges.size() == 3, "legacy relationship arrays did not migrate deterministically")
	_expect(_has_relation(edges, "contains"), "legacy child edge did not become contains")
	_expect(_has_relation(edges, "depends_on"), "legacy dependency did not migrate")
	_expect(_has_relation(edges, "related_to"), "legacy association did not migrate")


func _node(
	node_id: String,
	children: Array,
	dependencies: Array,
	associations: Array
) -> Dictionary:
	return {
		"node_id": node_id,
		"relationships": {
			"parents": [],
			"children": children,
			"dependencies": dependencies,
			"associations": associations,
		},
	}


func _has_relation(edges: Array, relation_id: String) -> bool:
	for edge_any in edges:
		if str((edge_any as Dictionary).get("relation", "")) == relation_id:
			return true
	return false


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(failure_message)
