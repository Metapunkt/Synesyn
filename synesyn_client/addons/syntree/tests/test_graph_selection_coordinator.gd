extends SceneTree

const GraphSelectionCoordinatorScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_selection_coordinator.gd"
)

var _failures: int = 0


class FakeContentState:
	extends RefCounted
	var selected_nodes: Array[String] = []

	func select_node(node_id: String) -> void:
		selected_nodes.append(node_id)


class FakeViewState:
	extends RefCounted
	var selected_sources: Array[String] = []

	func select_source(source_id: String, is_selected: bool) -> void:
		if is_selected:
			selected_sources.append(source_id)


func _init() -> void:
	_test_ordinary_selection()
	_test_stack_selection_preserves_view_root()
	if _failures == 0:
		print("Graph selection coordinator tests: all passed")
		quit(0)
		return
	push_error("Graph selection coordinator tests: %d failure(s)" % _failures)
	quit(1)


func _test_ordinary_selection() -> void:
	var coordinator: RefCounted = GraphSelectionCoordinatorScript.new()
	var content_state := FakeContentState.new()
	var view_state := FakeViewState.new()
	coordinator.call("select_node", content_state, view_state, "node-a", "source-a", false)
	_expect(content_state.selected_nodes == ["node-a"], "ordinary node selection was not routed")
	_expect(view_state.selected_sources == ["source-a"], "ordinary source selection was not synchronized")


func _test_stack_selection_preserves_view_root() -> void:
	var coordinator: RefCounted = GraphSelectionCoordinatorScript.new()
	var content_state := FakeContentState.new()
	var view_state := FakeViewState.new()
	coordinator.call("select_node", content_state, view_state, "source-a::node-a", "source-a", true)
	_expect(content_state.selected_nodes == ["source-a::node-a"], "stack node selection was not routed")
	_expect(view_state.selected_sources.is_empty(), "stack selection changed the displayed source root")


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(failure_message)
