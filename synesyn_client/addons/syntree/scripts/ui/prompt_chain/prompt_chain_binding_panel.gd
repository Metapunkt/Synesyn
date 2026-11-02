@tool
extends PanelContainer

const PromptChainStoreScript = preload(
	"res://addons/syntree/scripts/services/prompting/prompt_chain_store.gd"
)
const PromptChainContextResolverScript = preload(
	"res://addons/syntree/scripts/services/prompting/prompt_chain_context_resolver.gd"
)
const HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")

signal propose_binding_requested(binding: Dictionary)
signal preview_requested

@onready var artifact_edit: LineEdit = %BindingArtifactEdit
@onready var version_edit: LineEdit = %BindingVersionEdit
@onready var owner_edit: LineEdit = %BindingOwnerEdit
@onready var context_set_edit: LineEdit = %BindingContextSetEdit
@onready var preset_selector: OptionButton = %BindingPresetSelector
@onready var budget_spin: SpinBox = %BindingBudgetSpin
@onready var propose_button: Button = %ProposeBindingButton
@onready var preview_button: Button = %PreviewBindingButton
@onready var status_label: Label = %BindingStatusLabel
@onready var preview_text: TextEdit = %BindingPreviewText

var _hub_client: Node = null
var _resolver: RefCounted = PromptChainContextResolverScript.new()


func _ready() -> void:
	for preset_id in ["full", "balanced", "minimal"]:
		preset_selector.add_item(preset_id.capitalize())
		preset_selector.set_item_metadata(
			preset_selector.item_count - 1,
			preset_id
		)
	preset_selector.select(1)
	propose_button.pressed.connect(_on_propose_pressed)
	preview_button.pressed.connect(_on_preview_pressed)
	_hub_client = HubSubstrateClientScript.new()
	add_child(_hub_client)
	_hub_client.configure_from_runtime_config()
	_resolver.call("setup", _hub_client)
	propose_binding_requested.connect(_propose_to_parent)
	preview_requested.connect(_preview_from_parent)


func set_binding(binding: Dictionary) -> void:
	_show_graph_preview([])
	artifact_edit.text = str(binding.get("context_graph_artifact_id", ""))
	version_edit.text = str(binding.get("context_graph_version_id", ""))
	owner_edit.text = str(binding.get("owner_source_id", ""))
	context_set_edit.text = str(binding.get("context_set_id", ""))
	budget_spin.value = int(binding.get("max_tokens", 8000))
	_select_preset(str(binding.get("compiler_preset", "balanced")))
	status_label.text = "No binding." if binding.is_empty() else "Binding loaded."


func get_binding() -> Dictionary:
	return {
		"context_graph_artifact_id": artifact_edit.text.strip_edges(),
		"context_graph_version_id": version_edit.text.strip_edges(),
		"owner_source_id": owner_edit.text.strip_edges(),
		"context_set_id": context_set_edit.text.strip_edges(),
		"compiler_preset": str(
			preset_selector.get_item_metadata(preset_selector.selected)
		),
		"max_tokens": int(budget_spin.value),
	}


func set_preview_result(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_show_graph_preview([])
		status_label.text = "Binding warning: %s" % str(
			result.get("error", "resolution failed")
		)
		preview_text.text = str(result.get("details", ""))
		return
	var compile_result: Dictionary = result.get("compile_result", {})
	var included_node_ids: Array[String] = []
	for item_any in compile_result.get("included_nodes", []):
		included_node_ids.append(str(
			(item_any as Dictionary).get("node_id", "")
		))
	_show_graph_preview(included_node_ids)
	var warnings: Array = result.get("warnings", [])
	status_label.text = "~%d / %d tokens%s" % [
		int(compile_result.get("estimated_tokens", 0)),
		int(compile_result.get("token_budget", 0)),
		" · %s" % ", ".join(warnings) if not warnings.is_empty() else "",
	]
	preview_text.text = str(compile_result.get("compiled_text", ""))


func _on_propose_pressed() -> void:
	propose_binding_requested.emit(get_binding())


func _on_preview_pressed() -> void:
	preview_requested.emit()


func _propose_to_parent(binding: Dictionary) -> void:
	var panel: Node = get_parent()
	if not is_instance_valid(panel) or not panel.has_method(
		"_get_effective_chain"
	):
		return
	var chain: Dictionary = panel.call("_get_effective_chain")
	if chain.is_empty():
		set_preview_result({"ok": false, "error": "prompt_chain_missing"})
		return
	chain = chain.duplicate(true)
	chain["context_binding"] = binding
	chain = PromptChainStoreScript.normalize_chain(chain)
	panel.remove_meta("last_prompt_binding_preview")
	panel.call("_write_chain", chain)
	panel.call("_refresh_editor_from_current")


func _preview_from_parent() -> void:
	var panel: Node = get_parent()
	if not is_instance_valid(panel) or not panel.has_method(
		"_get_effective_chain"
	):
		return
	var chain: Dictionary = panel.call("_get_effective_chain")
	if chain.is_empty():
		set_preview_result({"ok": false, "error": "prompt_chain_missing"})
		return
	var binding: Dictionary = get_binding()
	chain = chain.duplicate(true)
	chain["context_binding"] = binding
	var thread_scope: String = str(panel.get("_scope"))
	var thread_id: String = str(panel.get("_thread_id"))
	var thread_settings: Dictionary = (
		PromptChainStoreScript.get_thread_settings(thread_scope, thread_id)
	)
	var slot_values: Dictionary = thread_settings.get("slot_values", {})
	var result: Dictionary = await _resolver.call(
		"resolve",
		chain,
		str(binding.get("owner_source_id", "")),
		{
			"thread_scope": thread_scope,
			"app_scope": "syntree_editor",
			"prompt_chain_id": str(chain.get("id", "")),
			"slots": slot_values,
		}
	)
	if bool(result.get("ok", false)):
		panel.set_meta("last_prompt_binding_preview", binding.duplicate(true))
	set_preview_result(result)


func _select_preset(preset_id: String) -> void:
	for item_index in range(preset_selector.item_count):
		if str(preset_selector.get_item_metadata(item_index)) == preset_id:
			preset_selector.select(item_index)
			return
	preset_selector.select(1)


func _show_graph_preview(node_ids: Array[String]) -> void:
	if is_inside_tree():
		get_tree().call_group(
			"graph_controllers",
			"show_prompt_chain_preview",
			node_ids
		)
