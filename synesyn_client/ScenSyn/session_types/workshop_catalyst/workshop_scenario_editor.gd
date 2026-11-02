extends PanelContainer
class_name WorkshopScenarioEditor

signal scenario_saved(scenario: Dictionary)
signal editor_cancelled

const WorkshopScenarioContractScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_scenario_contract.gd"
)
const ScenarioBundleScript = preload("res://ScenSyn/scripts/core/scenario_bundle.gd")
const ScenarioShareUiScript = preload("res://ScenSyn/scripts/core/scenario_share_ui.gd")

const SOURCE_EMPTY := "empty"
const SOURCE_LOCAL_DRAFT := "local_draft"
const SOURCE_SESSION := "session"
const SOURCE_HOST_SYNCED := "host_synced"

@onready var _heading_label: Label = %Heading
@onready var _source_banner_node: PanelContainer = %SourceBanner
@onready var _source_banner_label: Label = %SourceBannerLabel
@onready var _join_hint_label: Label = %JoinHintLabel
@onready var _title_input: LineEdit = %WorkshopScenarioTitle
@onready var _objective_input: TextEdit = %WorkshopScenarioObjective
@onready var _context_input: TextEdit = %WorkshopScenarioContext
@onready var _outcomes_input: TextEdit = %WorkshopScenarioOutcomes
@onready var _constraints_input: TextEdit = %WorkshopScenarioConstraints
@onready var _time_horizon_input: LineEdit = %WorkshopScenarioTimeHorizon
@onready var _perspectives_input: TextEdit = %WorkshopScenarioPerspectives
@onready var _evidence_input: TextEdit = %WorkshopScenarioEvidence
@onready var _status_label: Label = %WorkshopScenarioDraftStatus
@onready var _save_button: Button = %SaveWorkshopScenarioButton
@onready var _fresh_button: Button = %FreshWorkshopScenarioButton
@onready var _cancel_button: Button = %CancelWorkshopScenarioButton
@onready var _share_button: Button = %ShareWorkshopScenarioButton
@onready var _import_button: Button = %ImportWorkshopScenarioButton

var _source_kind: String = SOURCE_EMPTY
var _import_dialog: FileDialog = null


func _ready() -> void:
	_save_button.pressed.connect(_save)
	_fresh_button.pressed.connect(_start_fresh_draft)
	_cancel_button.pressed.connect(_cancel)
	_share_button.pressed.connect(_share)
	_import_button.pressed.connect(_open_import_dialog)
	visible = false


## Open the editor. `source_kind` may be empty (auto-detect), or one of:
## empty | local_draft | session | host_synced.
func open_editor(
	source: Dictionary = {},
	source_kind: String = "",
	show_join_hint: bool = false
) -> void:
	var scenario: Dictionary = source.duplicate(true) if not source.is_empty() else {}
	var resolved_kind: String = source_kind.strip_edges()
	if scenario.is_empty():
		scenario = WorkshopScenarioContractScript.load_local_draft()
		if scenario.is_empty():
			scenario = WorkshopScenarioContractScript.create_custom({})
			resolved_kind = SOURCE_EMPTY if resolved_kind.is_empty() else resolved_kind
		elif resolved_kind.is_empty():
			resolved_kind = SOURCE_LOCAL_DRAFT
	elif resolved_kind.is_empty():
		if String(scenario.get("persistence_state", "")) == "local_draft":
			resolved_kind = SOURCE_LOCAL_DRAFT
		else:
			resolved_kind = SOURCE_SESSION
	_source_kind = resolved_kind
	_populate_fields(scenario)
	_apply_source_copy(show_join_hint)
	visible = true


func get_reviewed_fields() -> Dictionary:
	return {
		"title": _title_input.text.strip_edges(),
		"objective": _objective_input.text.strip_edges(),
		"context": _context_input.text.strip_edges(),
		"desired_outcomes": _nonempty_lines(_outcomes_input.text),
		"constraints": _nonempty_lines(_constraints_input.text),
		"time_horizon": _time_horizon_input.text.strip_edges(),
		"relevant_perspectives": _nonempty_lines(_perspectives_input.text),
		"evidence_notes": _evidence_input.text.strip_edges(),
	}


func get_source_kind() -> String:
	return _source_kind


func has_populated_draft() -> bool:
	var fields: Dictionary = get_reviewed_fields()
	return (
		not String(fields.get("title", "")).is_empty()
		or not String(fields.get("objective", "")).is_empty()
		or not String(fields.get("context", "")).is_empty()
	)


func _populate_fields(scenario: Dictionary) -> void:
	var packet_any: Variant = scenario.get("workshop_packet", {})
	var packet: Dictionary = (
		packet_any as Dictionary if typeof(packet_any) == TYPE_DICTIONARY else {}
	)
	_title_input.text = String(packet.get("title", scenario.get("name", "")))
	_objective_input.text = String(packet.get("objective", scenario.get("objective", "")))
	_context_input.text = String(packet.get("context", scenario.get("description", "")))
	_outcomes_input.text = _lines(packet.get("desired_outcomes", []))
	_constraints_input.text = _lines(packet.get("constraints", []))
	_time_horizon_input.text = String(packet.get("time_horizon", ""))
	_perspectives_input.text = _lines(packet.get("relevant_perspectives", []))
	_evidence_input.text = String(packet.get("evidence_notes", ""))


func _apply_source_copy(show_join_hint: bool) -> void:
	_join_hint_label.visible = show_join_hint
	_source_banner_node.visible = true
	match _source_kind:
		SOURCE_HOST_SYNCED:
			_heading_label.text = "Host Scenario available"
			_source_banner_label.text = (
				"This Scenario was synced from the host instance. "
				+ "Use it as-is, edit then use, or start a new draft if you intend to host instead."
			)
			_status_label.text = "Host Scenario loaded into the form."
			_save_button.text = "Use host Scenario"
		SOURCE_LOCAL_DRAFT:
			_heading_label.text = "Existing draft on this device"
			_source_banner_label.text = (
				"A Scenario draft is already saved on this device — often from another "
				+ "local instance or an earlier session. Review it and use it, or start a new draft."
			)
			_status_label.text = "Local draft loaded. Review every field before starting."
			_save_button.text = "Use this Scenario"
		SOURCE_SESSION:
			_heading_label.text = "Current session Scenario"
			_source_banner_label.text = (
				"Fields show the Scenario already selected for this session. "
				+ "Confirm to keep it, edit then use, or start a new draft."
			)
			_status_label.text = "Session Scenario loaded into the form."
			_save_button.text = "Use this Scenario"
		_:
			_heading_label.text = "Describe your Scenario"
			_source_banner_label.text = (
				"New local draft. Nothing is published or committed. "
				+ "Fill the required fields, then use this Scenario for the session you host."
			)
			_status_label.text = "New local draft. Nothing is published or committed."
			_save_button.text = "Use this Scenario"


func _start_fresh_draft() -> void:
	_source_kind = SOURCE_EMPTY
	_populate_fields(WorkshopScenarioContractScript.create_custom({}))
	_apply_source_copy(_join_hint_label.visible)
	_status_label.text = "Cleared. Enter a new Scenario draft."
	_title_input.grab_focus()


func _save() -> void:
	var fields: Dictionary = get_reviewed_fields()
	if (
		String(fields.get("title", "")).is_empty()
		or String(fields.get("objective", "")).is_empty()
		or String(fields.get("context", "")).is_empty()
	):
		_status_label.text = "Title, central question/objective, and context are required."
		return
	var scenario: Dictionary = WorkshopScenarioContractScript.create_custom(fields)
	var save_result: Dictionary = WorkshopScenarioContractScript.save_local_draft(scenario)
	if not bool(save_result.get("ok", false)):
		_status_label.text = "Local draft could not be saved: " + String(
			save_result.get("error", "unknown_error")
		)
		return
	_source_kind = SOURCE_LOCAL_DRAFT
	_status_label.text = "Saved locally as a draft and ready to use. Not committed or published."
	scenario_saved.emit(save_result.get("scenario", scenario))


## Shares whatever is in the form right now, without touching the library or the
## draft: the facilitator is publishing a copy, not committing to anything.
func _share() -> void:
	var fields: Dictionary = get_reviewed_fields()
	if String(fields.get("title", "")).is_empty():
		_status_label.text = "Give the Scenario a title before sharing it."
		return
	var scenario: Dictionary = WorkshopScenarioContractScript.create_custom(fields)
	var export_result: Dictionary = ScenarioBundleScript.export_scenarios([scenario])
	_status_label.text = ScenarioShareUiScript.export_message(export_result)
	if bool(export_result.get("ok", false)):
		ScenarioShareUiScript.reveal_exports_dir()


func _open_import_dialog() -> void:
	if _import_dialog == null:
		_import_dialog = ScenarioShareUiScript.make_import_dialog(self)
		_import_dialog.file_selected.connect(_import_selected_bundle)
	_import_dialog.popup_centered()


func _import_selected_bundle(path: String) -> void:
	var import_result: Dictionary = ScenarioBundleScript.import_bundle(
		path,
		[ScenarioBundleScript.SESSION_TYPE_WORKSHOP]
	)
	if bool(import_result.get("ok", false)):
		_show_first_imported(import_result)
	_status_label.text = ScenarioShareUiScript.import_message(import_result)


## Loads the import into the form so the facilitator can read it before deciding
## to use it. The form is a view here; the Scenario is already in the library.
func _show_first_imported(import_result: Dictionary) -> void:
	var imported_any: Variant = import_result.get("imported", [])
	var imported: Array = imported_any if typeof(imported_any) == TYPE_ARRAY else []
	if imported.is_empty():
		return
	var first: Dictionary = imported[0]
	var loaded: Dictionary = WorkshopScenarioContractScript.load_saved_scenario(
		String(first.get("id", ""))
	)
	if loaded.is_empty():
		return
	_source_kind = SOURCE_SESSION
	_populate_fields(loaded)
	_apply_source_copy(_join_hint_label.visible)


func _cancel() -> void:
	visible = false
	editor_cancelled.emit()


func _nonempty_lines(source_text: String) -> Array[String]:
	var values: Array[String] = []
	for line_text: String in source_text.split("\n"):
		var clean_text: String = line_text.strip_edges().trim_prefix("-").strip_edges()
		if not clean_text.is_empty():
			values.append(clean_text)
	return values


func _lines(values_any: Variant) -> String:
	if typeof(values_any) != TYPE_ARRAY:
		return ""
	var lines: Array[String] = []
	for value_any: Variant in values_any:
		var value_text: String = String(value_any).strip_edges()
		if not value_text.is_empty():
			lines.append(value_text)
	return "\n".join(lines)
