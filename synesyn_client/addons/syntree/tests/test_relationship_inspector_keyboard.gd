extends SceneTree

const RelationshipInspectorScene = preload(
	"res://addons/syntree/scenes/relationship_inspector.tscn"
)

var _created_endpoints: Array[String] = []


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var inspector: Control = RelationshipInspectorScene.instantiate()
	root.add_child(inspector)
	inspector.endpoints_create_requested.connect(_on_endpoints_created)
	var node_ids: Array[String] = ["node-a", "node-b"]
	inspector.call("set_node_ids", node_ids)
	var create_button: Button = inspector.get_node(
		"MarginContainer/VBoxContainer/CreateEndpointsButton"
	)
	create_button.pressed.emit()
	inspector.queue_free()
	if _created_endpoints == node_ids:
		print("Relationship inspector keyboard tests: all passed")
		quit(0)
		return
	push_error("Keyboard endpoint controls did not emit the selected nodes")
	quit(1)


func _on_endpoints_created(from_id: String, to_id: String) -> void:
	_created_endpoints = [from_id, to_id]
