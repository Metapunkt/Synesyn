extends SceneTree

const RelationshipInspectorScene = preload(
	"res://addons/syntree/scenes/relationship_inspector.tscn"
)

var _failures: int = 0
var _saved_edge: Dictionary = {}
var _cancel_count: int = 0


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var inspector: Control = RelationshipInspectorScene.instantiate()
	root.add_child(inspector)
	inspector.save_requested.connect(_on_save_requested)
	inspector.cancel_new_requested.connect(_on_cancel_requested)
	var relation_selector: OptionButton = inspector.get_node(
		"MarginContainer/VBoxContainer/EditorContainer/RelationSelector"
	)
	_expect(relation_selector.item_count == 10, "relationship vocabulary was not loaded")
	inspector.call("show_new_connection", "node-a", "node-b")
	var save_button: Button = inspector.get_node(
		"MarginContainer/VBoxContainer/EditorContainer/PrimaryActions/SaveButton"
	)
	save_button.pressed.emit()
	_expect(
		_saved_edge.get("relation", "") == "contains"
		and _saved_edge.get("from", "") == "node-a"
		and _saved_edge.get("to", "") == "node-b",
		"new relationship draft was not emitted"
	)
	inspector.call("show_new_connection", "node-a", "node-b")
	var cancel_button: Button = inspector.get_node(
		"MarginContainer/VBoxContainer/EditorContainer/PrimaryActions/CancelButton"
	)
	cancel_button.pressed.emit()
	_expect(_cancel_count == 1, "new relationship cancellation was not emitted")
	inspector.queue_free()
	if _failures == 0:
		print("Relationship inspector tests: all passed")
		quit(0)
		return
	push_error("Relationship inspector tests: %d failure(s)" % _failures)
	quit(1)


func _on_save_requested(edge_data: Dictionary) -> void:
	_saved_edge = edge_data


func _on_cancel_requested() -> void:
	_cancel_count += 1


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(failure_message)
