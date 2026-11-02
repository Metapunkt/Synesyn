@tool
extends PanelContainer

signal refresh_requested(options: Dictionary)
signal compiler_enabled_changed(is_enabled: bool)

@onready var enabled_check: CheckBox = %EnabledCheck
@onready var preset_selector: OptionButton = %PresetSelector
@onready var budget_spin: SpinBox = %BudgetSpin
@onready var refresh_button: Button = %RefreshButton
@onready var budget_label: Label = %BudgetLabel
@onready var included_list: ItemList = %IncludedList
@onready var omitted_list: ItemList = %OmittedList
@onready var compiled_text: TextEdit = %CompiledText


func _ready() -> void:
	preset_selector.clear()
	for preset_id in ["full", "balanced", "minimal"]:
		preset_selector.add_item(preset_id.capitalize())
		preset_selector.set_item_metadata(
			preset_selector.item_count - 1,
			preset_id
		)
	preset_selector.select(1)
	enabled_check.toggled.connect(_on_enabled_toggled)
	refresh_button.pressed.connect(_emit_refresh)
	preset_selector.item_selected.connect(_on_options_changed)
	budget_spin.value_changed.connect(_on_budget_changed)
	clear_preview()


func set_compile_result(result: Dictionary) -> void:
	included_list.clear()
	omitted_list.clear()
	var included: Array = result.get("included_nodes", [])
	for item_any in included:
		var item_data: Dictionary = item_any
		included_list.add_item("%s · %s · ~%d tokens" % [
			str(item_data.get("node_id", "")),
			str(item_data.get("reason", "")),
			int(item_data.get("estimated_tokens", 0)),
		])
	var omitted: Array = result.get("omitted_nodes", [])
	for item_any in omitted:
		var item_data: Dictionary = item_any
		omitted_list.add_item("%s · %s" % [
			str(item_data.get("node_id", "")),
			str(item_data.get("reason", "")),
		])
	var estimated_tokens: int = int(result.get("estimated_tokens", 0))
	var token_budget: int = int(result.get("token_budget", 0))
	budget_label.text = "~%d / %d tokens · %s" % [
		estimated_tokens,
		token_budget,
		str(result.get("estimator_id", "unknown estimator")),
	]
	compiled_text.text = str(result.get("compiled_text", ""))


func clear_preview() -> void:
	included_list.clear()
	omitted_list.clear()
	budget_label.text = "No compiled context preview."
	compiled_text.text = ""


func set_compiler_enabled(is_enabled: bool) -> void:
	enabled_check.set_pressed_no_signal(is_enabled)


func refresh_preview() -> void:
	_emit_refresh()


func get_options() -> Dictionary:
	var preset_id: String = str(
		preset_selector.get_item_metadata(preset_selector.selected)
	)
	return {
		"preset": preset_id,
		"max_tokens": int(budget_spin.value),
	}


func _emit_refresh() -> void:
	refresh_requested.emit(get_options())


func _on_enabled_toggled(is_enabled: bool) -> void:
	compiler_enabled_changed.emit(is_enabled)
	if is_enabled:
		_emit_refresh()


func _on_options_changed(_item_index: int) -> void:
	if enabled_check.button_pressed:
		_emit_refresh()


func _on_budget_changed(_budget_value: float) -> void:
	if enabled_check.button_pressed:
		_emit_refresh()
