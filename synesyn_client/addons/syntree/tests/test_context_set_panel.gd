extends SceneTree

const ContextSetPanelScene = preload(
	"res://addons/syntree/scenes/context_set_panel.tscn"
)

var _saved_set: Dictionary = {}
var _saved_activation: Dictionary = {}


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var panel: Control = ContextSetPanelScene.instantiate()
	root.add_child(panel)
	panel.save_set_requested.connect(_on_set_saved)
	panel.activation_save_requested.connect(_on_activation_saved)
	var node_ids: Array[String] = ["node-a", "node-b"]
	panel.call("set_node_ids", node_ids)
	var set_id_edit: LineEdit = panel.get_node("%SetIdEdit")
	var set_label_edit: LineEdit = panel.get_node("%SetLabelEdit")
	var entry_list: ItemList = panel.get_node("%EntryList")
	var save_set_button: Button = panel.get_node("%SaveSetButton")
	set_id_edit.text = "research"
	set_label_edit.text = "Research"
	entry_list.select(1)
	save_set_button.pressed.emit()
	var node_selector: OptionButton = panel.get_node("%ActivationNodeSelector")
	var activation_selector: OptionButton = panel.get_node(
		"%ActivationModeSelector"
	)
	var conditions_edit: TextEdit = panel.get_node("%ConditionsEdit")
	var save_activation_button: Button = panel.get_node(
		"%SaveActivationButton"
	)
	node_selector.select(1)
	activation_selector.select(2)
	conditions_edit.text = "{\"app_scope\":\"syntree\"}"
	save_activation_button.pressed.emit()
	var is_valid: bool = (
		_saved_set.get("id", "") == "research"
		and _saved_set.get("entry_node_ids", []) == ["node-b"]
		and _saved_activation.get("node_id", "") == "node-b"
		and (
			_saved_activation.get("activation", {}) as Dictionary
		).get("mode", "") == "conditional"
	)
	panel.queue_free()
	if is_valid:
		print("Context set panel tests: all passed")
		quit(0)
		return
	push_error("Context Set panel did not expose deterministic draft controls")
	quit(1)


func _on_set_saved(context_set: Dictionary) -> void:
	_saved_set = context_set


func _on_activation_saved(
	node_id: String,
	activation: Dictionary
) -> void:
	_saved_activation = {
		"node_id": node_id,
		"activation": activation,
	}
