## Purpose: ui/dialogs/filter_popup.gd
# scripts/ui/dialogs/filter_popup.gd
@tool
extends PopupPanel

signal filters_applied(filters: Dictionary)

@onready var source_origin_options: OptionButton = %SourceOriginOptions
@onready var source_type_ext_options: OptionButton = %SourceTypeOptions
#@onready var metadata_tags_container: VBoxContainer = %MetadataTagsContainer
@onready var active_state_check: CheckBox = %ActiveStateCheck
@onready var metaprompt_check: CheckBox = %MetapromptCheck
@onready var apply_button: Button = %ApplyFilterButton
@onready var clear_button: Button = %ClearFilterButton

var _current_filters: Dictionary = {}
var _content_state: ContentStateResource = null

func set_resources(content_state: ContentStateResource) -> void:
	_content_state = content_state

func _ready() -> void:
	setup_source_origin_options()
	connect_signals()

func setup_source_origin_options() -> void:
	source_origin_options.clear()
	source_origin_options.add_item("All Origins", 0)
	source_origin_options.add_item("File", 1)
	source_origin_options.add_item("Remote", 2)

func setup_source_type_ext_options() -> void:
	source_type_ext_options.clear()
	source_type_ext_options.add_item("All Types", 0)
	
	if not is_instance_valid(_content_state):
		push_warning("FilterPopup: ContentStateResource not injected; cannot populate source types.")
		return
		
	var source_ids = _content_state.get_source_ids()
	var found_types := {}
	for source_id in source_ids:
		var source_data = _content_state.get_source_data(source_id)
		var meta = source_data.get("meta", {})
		var type = meta.get("source_type", "unknown")
		if type != "unknown" and not type.is_empty():
			found_types[type] = true
	
	var sorted_types = found_types.keys()
	sorted_types.sort()
	var index = 1
	for type in sorted_types:
		source_type_ext_options.add_item(type, index)
		index += 1

func connect_signals() -> void:
	apply_button.pressed.connect(_on_apply_pressed)
	clear_button.pressed.connect(_on_clear_pressed)
	source_origin_options.item_selected.connect(_on_source_origin_selected)
	source_type_ext_options.item_selected.connect(_on_source_type_by_ext_selected)
	active_state_check.toggled.connect(_on_active_state_toggled)
	metaprompt_check.toggled.connect(_on_metaprompt_toggled)

func _on_apply_pressed() -> void:
	filters_applied.emit(_current_filters)
	hide()

func _on_clear_pressed() -> void:
	_current_filters.clear()
	source_origin_options.selected = 0
	source_type_ext_options.selected = 0
	active_state_check.button_pressed = false
	metaprompt_check.button_pressed = false
	filters_applied.emit({})
	hide()

func _on_source_origin_selected(index: int) -> void:
	if index == 0:  # All Origins
		_current_filters.erase("source_origin")
	else:
		var type_map = {
			1: "file",
			2: "remote"
		}
		_current_filters["source_origin"] = type_map.get(index, "unknown")

func _on_source_type_by_ext_selected(index: int) -> void:
	if index == 0:  # All Types
		_current_filters.erase("source_type")
	else:
		var selected_type = source_type_ext_options.get_item_text(index).to_lower()
		_current_filters["source_type"] = selected_type

func _on_active_state_toggled(button_pressed: bool) -> void:
	if button_pressed:
		_current_filters["is_active"] = true
	else:
		_current_filters.erase("is_active")

func _on_metaprompt_toggled(button_pressed: bool) -> void:
	if button_pressed:
		_current_filters["is_metaprompt"] = true
	else:
		_current_filters.erase("is_metaprompt")

func show_dialog() -> void:
	setup_source_type_ext_options()
	
	_current_filters.clear()
	source_origin_options.selected = 0
	source_type_ext_options.selected = 0
	active_state_check.button_pressed = false
	metaprompt_check.button_pressed = false
	popup_centered()
