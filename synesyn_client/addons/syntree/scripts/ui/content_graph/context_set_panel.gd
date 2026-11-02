@tool
extends PanelContainer

signal save_set_requested(context_set: Dictionary)
signal delete_set_requested(context_set_id: String)
signal duplicate_set_requested(context_set_id: String)
signal preview_set_requested(context_set: Dictionary)
signal commit_set_requested(context_set: Dictionary)
signal history_requested
signal activation_selected(node_id: String)
signal activation_save_requested(node_id: String, activation: Dictionary)

const RELATION_IDS: Array[String] = [
	"contains",
	"depends_on",
	"precedes",
	"supports",
	"contradicts",
	"derived_from",
	"refines",
	"example_of",
	"related_to",
]
const ACTIVATION_MODES: Array[String] = [
	"always",
	"when_relevant",
	"conditional",
	"manual_only",
	"excluded",
]

@onready var set_selector: OptionButton = %SetSelector
@onready var set_id_edit: LineEdit = %SetIdEdit
@onready var set_label_edit: LineEdit = %SetLabelEdit
@onready var entry_list: ItemList = %EntryList
@onready var relation_list: ItemList = %RelationList
@onready var depth_spin: SpinBox = %DepthSpin
@onready var budget_spin: SpinBox = %SetBudgetSpin
@onready var prompt_chain_edit: LineEdit = %PromptChainEdit
@onready var save_set_button: Button = %SaveSetButton
@onready var duplicate_button: Button = %DuplicateButton
@onready var delete_button: Button = %DeleteSetButton
@onready var preview_button: Button = %PreviewSetButton
@onready var commit_button: Button = %CommitSetButton
@onready var history_button: Button = %HistoryButton
@onready var history_list: ItemList = %HistoryList
@onready var node_selector: OptionButton = %ActivationNodeSelector
@onready var activation_mode_selector: OptionButton = %ActivationModeSelector
@onready var priority_spin: SpinBox = %PrioritySpin
@onready var conditions_edit: TextEdit = %ConditionsEdit
@onready var save_activation_button: Button = %SaveActivationButton
@onready var status_label: Label = %StatusLabel

var _context_sets: Array = []


func _ready() -> void:
	_populate_static_options()
	set_selector.item_selected.connect(_on_set_selected)
	node_selector.item_selected.connect(_on_activation_node_selected)
	save_set_button.pressed.connect(_on_save_set_pressed)
	duplicate_button.pressed.connect(_on_duplicate_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	preview_button.pressed.connect(_on_preview_pressed)
	commit_button.pressed.connect(_on_commit_pressed)
	history_button.pressed.connect(_on_history_pressed)
	save_activation_button.pressed.connect(_on_save_activation_pressed)
	clear_form()


func set_context_sets(context_sets: Array) -> void:
	_context_sets = context_sets.duplicate(true)
	set_selector.clear()
	set_selector.add_item("New context set…")
	set_selector.set_item_metadata(0, "")
	for context_set_any in _context_sets:
		var context_set: Dictionary = context_set_any
		set_selector.add_item(str(context_set.get("label", "Unnamed set")))
		set_selector.set_item_metadata(
			set_selector.item_count - 1,
			str(context_set.get("id", ""))
		)
	set_selector.select(0)
	clear_form()


func set_node_ids(node_ids: Array[String]) -> void:
	entry_list.clear()
	node_selector.clear()
	for node_id in node_ids:
		entry_list.add_item(node_id)
		entry_list.set_item_metadata(entry_list.item_count - 1, node_id)
		node_selector.add_item(node_id)
		node_selector.set_item_metadata(node_selector.item_count - 1, node_id)
	if node_selector.item_count > 0:
		node_selector.select(0)
		activation_selected.emit(str(node_selector.get_item_metadata(0)))


func show_activation(activation: Dictionary) -> void:
	var activation_mode: String = str(
		activation.get("mode", "when_relevant")
	)
	_select_metadata(activation_mode_selector, activation_mode)
	priority_spin.value = int(activation.get("priority", 0))
	conditions_edit.text = JSON.stringify(
		activation.get("conditions", {}),
		"\t"
	)
	status_label.text = ""


func show_status(status_text: String, is_error: bool = false) -> void:
	status_label.text = status_text
	status_label.modulate = Color("#d96c75") if is_error else Color.WHITE


func set_version_history(versions: Array) -> void:
	history_list.clear()
	for version_any in versions:
		var version_data: Dictionary = version_any
		var metadata: Dictionary = version_data.get("metadata", {})
		history_list.add_item("%s · %s · %s" % [
			str(version_data.get("created_at", "")),
			str(metadata.get("context_set_id", "graph")),
			str(version_data.get("id", "")),
		])


func clear_form() -> void:
	set_id_edit.text = ""
	set_label_edit.text = ""
	depth_spin.value = 2
	budget_spin.value = 8000
	prompt_chain_edit.text = ""
	for item_index in range(entry_list.item_count):
		entry_list.deselect(item_index)
	for item_index in range(relation_list.item_count):
		relation_list.select(item_index, false)
	duplicate_button.disabled = true
	delete_button.disabled = true


func _populate_static_options() -> void:
	relation_list.clear()
	for relation_id in RELATION_IDS:
		relation_list.add_item(relation_id.replace("_", " ").capitalize())
		relation_list.set_item_metadata(
			relation_list.item_count - 1,
			relation_id
		)
	activation_mode_selector.clear()
	for activation_mode in ACTIVATION_MODES:
		activation_mode_selector.add_item(
			activation_mode.replace("_", " ").capitalize()
		)
		activation_mode_selector.set_item_metadata(
			activation_mode_selector.item_count - 1,
			activation_mode
		)
	activation_mode_selector.select(1)


func _on_set_selected(item_index: int) -> void:
	var context_set_id: String = str(
		set_selector.get_item_metadata(item_index)
	)
	if context_set_id.is_empty():
		clear_form()
		return
	for context_set_any in _context_sets:
		var context_set: Dictionary = context_set_any
		if str(context_set.get("id", "")) == context_set_id:
			_load_set(context_set)
			return


func _load_set(context_set: Dictionary) -> void:
	set_id_edit.text = str(context_set.get("id", ""))
	set_label_edit.text = str(context_set.get("label", ""))
	depth_spin.value = int(context_set.get("traversal_depth", 0))
	var budget_policy: Dictionary = context_set.get("budget_policy", {})
	budget_spin.value = int(budget_policy.get("max_tokens", 8000))
	var prompt_chain_ids: Array = context_set.get("prompt_chain_ids", [])
	prompt_chain_edit.text = ", ".join(prompt_chain_ids)
	_select_list_metadata(
		entry_list,
		context_set.get("entry_node_ids", [])
	)
	_select_list_metadata(
		relation_list,
		context_set.get("allowed_relationship_types", [])
	)
	duplicate_button.disabled = false
	delete_button.disabled = false


func _current_set() -> Dictionary:
	return {
		"id": set_id_edit.text.strip_edges(),
		"label": set_label_edit.text.strip_edges(),
		"entry_node_ids": _selected_metadata(entry_list),
		"allowed_relationship_types": _selected_metadata(relation_list),
		"traversal_depth": int(depth_spin.value),
		"activation_rules": {"mode": "manual_only"},
		"budget_policy": {"max_tokens": int(budget_spin.value)},
		"prompt_chain_ids": _comma_values(prompt_chain_edit.text),
		"status": "draft",
	}


func _on_save_set_pressed() -> void:
	save_set_requested.emit(_current_set())


func _on_duplicate_pressed() -> void:
	duplicate_set_requested.emit(set_id_edit.text.strip_edges())


func _on_delete_pressed() -> void:
	delete_set_requested.emit(set_id_edit.text.strip_edges())


func _on_preview_pressed() -> void:
	preview_set_requested.emit(_current_set())


func _on_commit_pressed() -> void:
	commit_set_requested.emit(_current_set())


func _on_history_pressed() -> void:
	history_requested.emit()


func _on_activation_node_selected(item_index: int) -> void:
	activation_selected.emit(str(node_selector.get_item_metadata(item_index)))


func _on_save_activation_pressed() -> void:
	if node_selector.selected < 0:
		return
	var parsed_conditions: Variant = JSON.parse_string(conditions_edit.text)
	if typeof(parsed_conditions) != TYPE_DICTIONARY:
		show_status("Conditions must be a JSON object.", true)
		return
	activation_save_requested.emit(
		str(node_selector.get_item_metadata(node_selector.selected)),
		{
			"mode": str(activation_mode_selector.get_item_metadata(
				activation_mode_selector.selected
			)),
			"conditions": parsed_conditions,
			"priority": int(priority_spin.value),
		}
	)


func _selected_metadata(item_list: ItemList) -> Array[String]:
	var values: Array[String] = []
	for item_index in item_list.get_selected_items():
		values.append(str(item_list.get_item_metadata(item_index)))
	return values


func _select_list_metadata(item_list: ItemList, values_any: Variant) -> void:
	item_list.deselect_all()
	if typeof(values_any) != TYPE_ARRAY:
		return
	for item_index in range(item_list.item_count):
		if (values_any as Array).has(item_list.get_item_metadata(item_index)):
			item_list.select(item_index, false)


func _select_metadata(option_button: OptionButton, value_id: String) -> void:
	for item_index in range(option_button.item_count):
		if str(option_button.get_item_metadata(item_index)) == value_id:
			option_button.select(item_index)
			return


func _comma_values(values_text: String) -> Array[String]:
	var values: Array[String] = []
	for value_any in values_text.split(",", false):
		var value_id: String = str(value_any).strip_edges()
		if not value_id.is_empty() and not values.has(value_id):
			values.append(value_id)
	return values
