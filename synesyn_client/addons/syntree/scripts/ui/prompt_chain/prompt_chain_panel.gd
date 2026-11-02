## Purpose: ui/prompt_chain/prompt_chain_panel.gd
@tool
extends VBoxContainer

const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")
const PromptChainStore = preload("res://addons/syntree/scripts/services/prompting/prompt_chain_store.gd")
const HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
const PromptChainHubVersionControllerScript = preload(
	"res://addons/syntree/scripts/ui/prompt_chain/internal/prompt_chain_hub_version_controller.gd"
)

var _scope: String = "syntree_editor"

var _thread_id: String = "default"
var _state: Dictionary = {}
var _hub = null
var _hub_version_controller: RefCounted = (
	PromptChainHubVersionControllerScript.new()
)

# UI
var _mode_option: OptionButton
var _apply_toggle: CheckButton
var _chains_list: ItemList
var _add_chain_btn: Button
var _delete_chain_btn: Button
var _save_hub_btn: Button
var _promote_and_save_btn: Button
var _commit_btn: Button
var _revert_btn: Button
var _proposal_label: Label
var _diff_label: Label
var _hub_info_label: Label
var _hub_versions_list: ItemList
var _name_edit: LineEdit
var _blocks_list: ItemList
var _block_enabled: CheckButton
var _block_text: TextEdit
var _add_block_btn: Button
var _delete_block_btn: Button
var _move_up_btn: Button
var _move_down_btn: Button
var _preview: TextEdit
var _binding_panel: Control

# Slots UI (v1)
var _slots_list: ItemList
var _add_slot_btn: Button
var _delete_slot_btn: Button
var _slot_name: LineEdit
var _slot_default: LineEdit
var _slot_desc: TextEdit
var _slot_value: LineEdit
var _export_slot_values_btn: Button
var _import_slot_values_btn: Button

var _suppress: bool = false

func _ready() -> void:
	_build_ui()
	_binding_panel = get_node_or_null("PromptChainBindingPanel")
	if is_instance_valid(_binding_panel):
		move_child(_binding_panel, get_child_count() - 1)
	_hub = HubSubstrateClientScript.new()
	add_child(_hub)
	if _hub and _hub.has_method("configure_from_runtime_config"):
		_hub.configure_from_runtime_config()
	_refresh_thread_id()
	_reload()
	# Keep in sync if the user switches threads in the Conversation Manager.
	var sync_bus := SynTreeAutoloads.content_bus()
	if is_instance_valid(sync_bus) and sync_bus.has_method("get_view_state_resource"):
		var vs = sync_bus.get_view_state_resource()
		if is_instance_valid(vs) and vs.has_signal("view_state_changed"):
			vs.view_state_changed.connect(func():
				var prev := _thread_id
				_refresh_thread_id()
				if _thread_id != prev:
					_reload()
			)

func _build_ui() -> void:
	# Header row
	var header := HBoxContainer.new()
	add_child(header)

	var title := Label.new()
	title.text = "Prompt Chains"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_apply_toggle = CheckButton.new()
	_apply_toggle.text = "Apply to chat (this thread)"
	_apply_toggle.toggled.connect(_on_apply_toggled)
	header.add_child(_apply_toggle)

	_mode_option = OptionButton.new()
	_mode_option.add_item("Asset (persist-to-hub)")
	_mode_option.add_item("Draft (thread-local)")
	_mode_option.tooltip_text = "Asset: reusable prompt chain intended to become a versioned hub artifact (ui.prompt_chain).\n(v0: stored locally; v1: persisted to hub)\nDraft: stored only inside this thread; promote to Asset when you want reuse/versioning."
	_mode_option.item_selected.connect(_on_mode_changed)
	header.add_child(_mode_option)

	_save_hub_btn = Button.new()
	_save_hub_btn.text = "Save version to Hub"
	_save_hub_btn.tooltip_text = "Persist the selected Asset prompt chain as a new versioned ui.prompt_chain artifact in the Hub."
	_save_hub_btn.pressed.connect(_on_save_version_to_hub)
	header.add_child(_save_hub_btn)

	_promote_and_save_btn = Button.new()
	_promote_and_save_btn.text = "Promote draft → Asset + Save"
	_promote_and_save_btn.tooltip_text = "If in Draft mode, creates a new Asset from the draft, links it to this thread, then saves a new version to Hub."
	_promote_and_save_btn.pressed.connect(_on_promote_draft_and_save_to_hub)
	header.add_child(_promote_and_save_btn)

	_commit_btn = Button.new()
	_commit_btn.text = "Commit"
	_commit_btn.tooltip_text = "Apply proposed edits. Draft: commits to the thread draft. Asset: writes to the asset store."
	_commit_btn.pressed.connect(_on_commit_pressed)
	header.add_child(_commit_btn)

	_revert_btn = Button.new()
	_revert_btn.text = "Revert"
	_revert_btn.tooltip_text = "Discard proposed edits and reload last committed state."
	_revert_btn.pressed.connect(_on_revert_pressed)
	header.add_child(_revert_btn)

	_proposal_label = Label.new()
	_proposal_label.text = ""
	_proposal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_proposal_label)

	_diff_label = Label.new()
	_diff_label.text = ""
	_diff_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_diff_label)

	# Main split: chains list + editor
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	split.add_child(left)

	var left_row := HBoxContainer.new()
	left.add_child(left_row)
	_add_chain_btn = Button.new()
	_add_chain_btn.text = "+ Chain"
	_add_chain_btn.pressed.connect(_on_add_chain)
	left_row.add_child(_add_chain_btn)
	_delete_chain_btn = Button.new()
	_delete_chain_btn.text = "Delete"
	_delete_chain_btn.pressed.connect(_on_delete_chain)
	left_row.add_child(_delete_chain_btn)

	_chains_list = ItemList.new()
	_chains_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chains_list.item_selected.connect(_on_chain_selected)
	left.add_child(_chains_list)

	_hub_info_label = Label.new()
	_hub_info_label.text = "Hub: (select a chain)"
	_hub_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_hub_info_label)

	_hub_versions_list = ItemList.new()
	_hub_versions_list.custom_minimum_size = Vector2(0, 120)
	_hub_versions_list.size_flags_vertical = Control.SIZE_SHRINK_END
	_hub_versions_list.item_activated.connect(_on_hub_version_activated)
	left.add_child(_hub_versions_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	var name_row := HBoxContainer.new()
	right.add_child(name_row)
	name_row.add_child(Label.new())
	name_row.get_child(0).text = "Name:"
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_edit)

	# Slots editor (v1)
	var slots_header := HBoxContainer.new()
	right.add_child(slots_header)
	var slots_title := Label.new()
	slots_title.text = "Slots:"
	slots_header.add_child(slots_title)
	_add_slot_btn = Button.new()
	_add_slot_btn.text = "+ Slot"
	_add_slot_btn.pressed.connect(_on_add_slot)
	slots_header.add_child(_add_slot_btn)
	_delete_slot_btn = Button.new()
	_delete_slot_btn.text = "Delete"
	_delete_slot_btn.pressed.connect(_on_delete_slot)
	slots_header.add_child(_delete_slot_btn)

	_export_slot_values_btn = Button.new()
	_export_slot_values_btn.text = "Export values"
	_export_slot_values_btn.tooltip_text = "Write per-thread slot values to a stable JSON file under the Synesyn prompt_chains folder."
	_export_slot_values_btn.pressed.connect(_on_export_slot_values)
	slots_header.add_child(_export_slot_values_btn)

	_import_slot_values_btn = Button.new()
	_import_slot_values_btn.text = "Import values"
	_import_slot_values_btn.tooltip_text = "Read per-thread slot values from the stable JSON file and merge into the current thread."
	_import_slot_values_btn.pressed.connect(_on_import_slot_values)
	slots_header.add_child(_import_slot_values_btn)

	var slots_split := HSplitContainer.new()
	slots_split.custom_minimum_size = Vector2(0, 160)
	right.add_child(slots_split)
	_slots_list = ItemList.new()
	_slots_list.custom_minimum_size = Vector2(220, 0)
	_slots_list.item_selected.connect(_on_slot_selected)
	slots_split.add_child(_slots_list)
	var slots_editor := VBoxContainer.new()
	slots_split.add_child(slots_editor)
	var sn_row := HBoxContainer.new()
	slots_editor.add_child(sn_row)
	var sn_l := Label.new()
	sn_l.text = "Name:"
	sn_row.add_child(sn_l)
	_slot_name = LineEdit.new()
	_slot_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_name.text_changed.connect(_on_slot_def_changed)
	sn_row.add_child(_slot_name)

	var sd_row := HBoxContainer.new()
	slots_editor.add_child(sd_row)
	var sd_l := Label.new()
	sd_l.text = "Default:"
	sd_row.add_child(sd_l)
	_slot_default = LineEdit.new()
	_slot_default.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_default.text_changed.connect(_on_slot_def_changed)
	sd_row.add_child(_slot_default)

	var sv_row := HBoxContainer.new()
	slots_editor.add_child(sv_row)
	var sv_l := Label.new()
	sv_l.text = "Value (this thread):"
	sv_row.add_child(sv_l)
	_slot_value = LineEdit.new()
	_slot_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_value.text_changed.connect(_on_slot_value_changed)
	sv_row.add_child(_slot_value)

	_slot_desc = TextEdit.new()
	_slot_desc.custom_minimum_size = Vector2(0, 80)
	_slot_desc.placeholder_text = "Description"
	_slot_desc.text_changed.connect(_on_slot_def_changed)
	slots_editor.add_child(_slot_desc)

	var blocks_header := HBoxContainer.new()
	right.add_child(blocks_header)
	_add_block_btn = Button.new()
	_add_block_btn.text = "+ Block"
	_add_block_btn.pressed.connect(_on_add_block)
	blocks_header.add_child(_add_block_btn)
	_delete_block_btn = Button.new()
	_delete_block_btn.text = "Delete"
	_delete_block_btn.pressed.connect(_on_delete_block)
	blocks_header.add_child(_delete_block_btn)
	_move_up_btn = Button.new()
	_move_up_btn.text = "↑"
	_move_up_btn.pressed.connect(func(): _move_block(-1))
	blocks_header.add_child(_move_up_btn)
	_move_down_btn = Button.new()
	_move_down_btn.text = "↓"
	_move_down_btn.pressed.connect(func(): _move_block(1))
	blocks_header.add_child(_move_down_btn)

	var blocks_split := VSplitContainer.new()
	blocks_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(blocks_split)

	_blocks_list = ItemList.new()
	_blocks_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_blocks_list.item_selected.connect(_on_block_selected)
	blocks_split.add_child(_blocks_list)

	var editor := VBoxContainer.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blocks_split.add_child(editor)

	var enabled_row := HBoxContainer.new()
	editor.add_child(enabled_row)
	var enabled_label := Label.new()
	enabled_label.text = "Enabled:"
	enabled_row.add_child(enabled_label)
	_block_enabled = CheckButton.new()
	_block_enabled.text = ""
	_block_enabled.toggled.connect(_on_block_enabled_toggled)
	enabled_row.add_child(_block_enabled)

	_block_text = TextEdit.new()
	_block_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_block_text.text_changed.connect(_on_block_text_changed)
	editor.add_child(_block_text)

	_preview = TextEdit.new()
	_preview.editable = false
	_preview.custom_minimum_size = Vector2(0, 120)
	_preview.placeholder_text = "Compiled preview (what will be prepended as system prompt when Apply is enabled)"
	add_child(_preview)

func _refresh_thread_id() -> void:
	var thread_bus := SynTreeAutoloads.content_bus()
	var vs = thread_bus.get_view_state_resource() if is_instance_valid(thread_bus) and thread_bus.has_method("get_view_state_resource") else null
	if is_instance_valid(vs) and vs.has_method("get_current_thread_id"):
		_thread_id = str(vs.get_current_thread_id())
	if _thread_id.is_empty():
		_thread_id = "default"

func _reload() -> void:
	# Seed built-in chains (best-effort) so the panel isn't empty on fresh installs.
	PromptChainStore.ensure_builtin_chains(_scope)
	_state = PromptChainStore.load_state(_scope)
	_load_thread_settings_into_ui()
	_refresh_chains_list()
	_refresh_editor_from_current()

func _load_thread_settings_into_ui() -> void:
	_refresh_thread_id()
	var t: Dictionary = PromptChainStore.get_thread_settings(_scope, _thread_id)
	var mode := str(t.get("mode", "asset")).to_lower()
	var apply := bool(t.get("apply_to_chat", false))
	_suppress = true
	_mode_option.select(1 if mode == "draft" else 0)
	_apply_toggle.button_pressed = apply
	_suppress = false

func _save_thread_settings(settings: Dictionary) -> void:
	PromptChainStore.set_thread_settings(_scope, _thread_id, settings)

func _refresh_chains_list() -> void:
	_chains_list.clear()
	var chains_any: Variant = _state.get("chains", {})
	if typeof(chains_any) != TYPE_DICTIONARY:
		return
	var chains: Dictionary = chains_any
	for cid in chains.keys():
		var c: Dictionary = chains.get(cid, {})
		_chains_list.add_item("%s" % str(c.get("name", cid)))
		_chains_list.set_item_metadata(_chains_list.item_count - 1, cid)

func _get_selected_chain_id() -> String:
	if _chains_list.get_selected_items().is_empty():
		return ""
	var idx := int(_chains_list.get_selected_items()[0])
	return str(_chains_list.get_item_metadata(idx))

func _ensure_thread_defaults() -> Dictionary:
	var t := PromptChainStore.get_thread_settings(_scope, _thread_id)
	if t.is_empty():
		t = {"mode": "asset", "asset_id": "", "draft": {}, "draft_proposed": {}, "asset_proposed": {}, "slot_values": {}, "apply_to_chat": false}
	# Back-compat: ensure keys exist
	if not t.has("draft_proposed"):
		t["draft_proposed"] = {}
	if not t.has("asset_proposed"):
		t["asset_proposed"] = {}
	if not t.has("slot_values"):
		t["slot_values"] = {}
	return t

func _has_pending_proposal(t: Dictionary) -> bool:
	var mode := str(t.get("mode", "asset")).to_lower()
	if mode == "draft":
		var dp_any: Variant = t.get("draft_proposed", {})
		return typeof(dp_any) == TYPE_DICTIONARY and not (dp_any as Dictionary).is_empty()
	var ap_any: Variant = t.get("asset_proposed", {})
	return typeof(ap_any) == TYPE_DICTIONARY and not (ap_any as Dictionary).is_empty()

func _get_effective_chain() -> Dictionary:
	var t := _ensure_thread_defaults()
	var mode := str(t.get("mode", "asset")).to_lower()
	if mode == "draft":
		var dp_any: Variant = t.get("draft_proposed", {})
		if typeof(dp_any) == TYPE_DICTIONARY and not (dp_any as Dictionary).is_empty():
			return dp_any
		var d_any: Variant = t.get("draft", {})
		return d_any if typeof(d_any) == TYPE_DICTIONARY else {}
	var asset_id := str(t.get("asset_id", ""))
	if asset_id.is_empty():
		return {}
	var ap_any: Variant = t.get("asset_proposed", {})
	if typeof(ap_any) == TYPE_DICTIONARY and not (ap_any as Dictionary).is_empty():
		return ap_any
	return PromptChainStore.get_chain(_scope, asset_id)

func _refresh_editor_from_current() -> void:
	var chain := _get_effective_chain()
	_suppress = true
	_name_edit.text = str(chain.get("name", ""))
	_suppress = false
	_refresh_blocks_list(chain)
	_refresh_preview(chain)
	_refresh_slots_ui(chain)
	if is_instance_valid(_binding_panel):
		_binding_panel.call("set_binding", chain.get("context_binding", {}))
	_refresh_commit_ui()
	_refresh_hub_info()

func _refresh_hub_info() -> void:
	var cid := _get_selected_chain_id()
	if cid.is_empty():
		_hub_info_label.text = "Hub: (select a chain)"
		_hub_versions_list.clear()
		return
	var info: Dictionary = PromptChainStore.get_chain_hub_info(_scope, cid)
	var latest := str(info.get("latest_artifact_id", "")).strip_edges()
	_hub_info_label.text = ("Hub latest: %s" % latest) if not latest.is_empty() else "Hub: (no version saved yet)"
	_hub_versions_list.clear()
	var versions_any: Variant = info.get("versions", [])
	if typeof(versions_any) != TYPE_ARRAY:
		return
	var versions: Array = versions_any
	for v in versions:
		_hub_versions_list.add_item(str(v))

func _on_hub_version_activated(idx: int) -> void:
	# Double-click a version to load/import it into the current Asset.
	if idx < 0 or idx >= _hub_versions_list.item_count:
		return
	var artifact_id := _hub_versions_list.get_item_text(idx).strip_edges()
	if artifact_id.is_empty():
		return
	if not _hub or not _hub.has_method("get_artifact_json"):
		push_warning("PromptChainPanel: Hub client not available for version load.")
		return
	var res: Dictionary = await _hub.get_artifact_json(artifact_id)
	if not bool(res.get("ok", false)):
		push_warning("PromptChainPanel: Failed to load version %s: %s" % [artifact_id, str(res.get("error", ""))])
		return
	var any: Variant = res.get("json", {})
	if typeof(any) != TYPE_DICTIONARY:
		push_warning("PromptChainPanel: Hub version JSON is not a dictionary.")
		return
	var j: Dictionary = any
	# Minimal schema: {name, blocks}
	var blocks_any: Variant = j.get("blocks", [])
	var blocks: Array = blocks_any if typeof(blocks_any) == TYPE_ARRAY else []
	var cid := _get_selected_chain_id()
	if cid.is_empty():
		return
	var chain := PromptChainStore.get_chain(_scope, cid)
	if chain.is_empty():
		chain = {"id": cid, "name": "Imported Chain", "blocks": []}
	chain["name"] = str(j.get("name", chain.get("name", "")))
	chain["blocks"] = blocks
	if j.has("slots"):
		chain["slots"] = j.get("slots", [])
	if j.has("context_binding"):
		chain["context_binding"] = j.get("context_binding", {})
	PromptChainStore.set_chain(_scope, cid, chain)
	_refresh_editor_from_current()

func _refresh_blocks_list(chain: Dictionary) -> void:
	_blocks_list.clear()
	var blocks_any: Variant = chain.get("blocks", [])
	if typeof(blocks_any) != TYPE_ARRAY:
		return
	var blocks: Array = blocks_any
	for i in range(blocks.size()):
		var b_any = blocks[i]
		if typeof(b_any) != TYPE_DICTIONARY:
			continue
		var b: Dictionary = b_any
		var enabled := bool(b.get("enabled", true))
		var label := str(b.get("label", "Block %d" % (i + 1)))
		_blocks_list.add_item(("%s %s" % ["[x]" if enabled else "[ ]", label]))
		_blocks_list.set_item_metadata(_blocks_list.item_count - 1, i)

func _refresh_preview(chain: Dictionary) -> void:
	var t := _ensure_thread_defaults()
	var sv_any: Variant = t.get("slot_values", {})
	var sv: Dictionary = sv_any if typeof(sv_any) == TYPE_DICTIONARY else {}
	_preview.text = PromptChainStore.render_chain_text(chain, sv)

func _refresh_commit_ui() -> void:
	var t := _ensure_thread_defaults()
	var pending := _has_pending_proposal(t)
	if is_instance_valid(_commit_btn):
		_commit_btn.disabled = not pending
	if is_instance_valid(_revert_btn):
		_revert_btn.disabled = not pending
	if is_instance_valid(_proposal_label):
		_proposal_label.text = ("(Proposed changes pending)" if pending else "")
	_refresh_diff_summary()

func _get_committed_chain() -> Dictionary:
	var t := _ensure_thread_defaults()
	var mode := str(t.get("mode", "asset")).to_lower()
	if mode == "draft":
		var d_any: Variant = t.get("draft", {})
		return d_any if typeof(d_any) == TYPE_DICTIONARY else {}
	var asset_id := str(t.get("asset_id", "")).strip_edges()
	if asset_id.is_empty():
		return {}
	return PromptChainStore.get_chain(_scope, asset_id)

func _refresh_diff_summary() -> void:
	if not is_instance_valid(_diff_label):
		return
	var t := _ensure_thread_defaults()
	if not _has_pending_proposal(t):
		_diff_label.text = ""
		return

	var committed := _get_committed_chain()
	var proposed := _get_effective_chain()

	var changes: Array[String] = []
	if str(committed.get("name", "")) != str(proposed.get("name", "")):
		changes.append("Name")

	# Blocks summary (count + text hash-ish)
	var cb_any: Variant = committed.get("blocks", [])
	var pb_any: Variant = proposed.get("blocks", [])
	var cb: Array = cb_any if typeof(cb_any) == TYPE_ARRAY else []
	var pb: Array = pb_any if typeof(pb_any) == TYPE_ARRAY else []
	if cb.size() != pb.size():
		changes.append("Blocks(count)")
	else:
		for i in range(pb.size()):
			var cbi: Variant = cb[i]
			var pbi: Variant = pb[i]
			if typeof(cbi) != TYPE_DICTIONARY or typeof(pbi) != TYPE_DICTIONARY:
				continue
			var cd: Dictionary = cbi
			var pd: Dictionary = pbi
			if bool(cd.get("enabled", true)) != bool(pd.get("enabled", true)) or str(cd.get("text", "")) != str(pd.get("text", "")) or str(cd.get("label", "")) != str(pd.get("label", "")):
				changes.append("Blocks(content)")
				break

	# Slots summary
	var cs_any: Variant = committed.get("slots", [])
	var ps_any: Variant = proposed.get("slots", [])
	var cs: Array = cs_any if typeof(cs_any) == TYPE_ARRAY else []
	var ps: Array = ps_any if typeof(ps_any) == TYPE_ARRAY else []
	if cs.size() != ps.size():
		changes.append("Slots(count)")
	else:
		for i in range(ps.size()):
			var csi: Variant = cs[i]
			var psi: Variant = ps[i]
			if typeof(csi) != TYPE_DICTIONARY or typeof(psi) != TYPE_DICTIONARY:
				continue
			var cd: Dictionary = csi
			var pd: Dictionary = psi
			if str(cd.get("name", "")) != str(pd.get("name", "")) or str(cd.get("default", "")) != str(pd.get("default", "")) or str(cd.get("description", "")) != str(pd.get("description", "")):
				changes.append("Slots(defs)")
				break
	if committed.get("context_binding", {}) != proposed.get(
		"context_binding",
		{}
	):
		changes.append("Context binding")

	_diff_label.text = "Proposed changes: %s" % (", ".join(changes) if not changes.is_empty() else "(unspecified)")

func _write_chain(chain: Dictionary) -> void:
	var t := _ensure_thread_defaults()
	var mode := str(t.get("mode", "asset")).to_lower()
	if mode == "draft":
		t["draft_proposed"] = chain
		_save_thread_settings(t)
		return
	# asset mode
	var asset_id := str(t.get("asset_id", ""))
	if asset_id.is_empty():
		return
	t["asset_proposed"] = chain
	_save_thread_settings(t)

func _commit_proposed() -> void:
	var t := _ensure_thread_defaults()
	var mode := str(t.get("mode", "asset")).to_lower()
	if mode == "draft":
		var dp_any: Variant = t.get("draft_proposed", {})
		if typeof(dp_any) != TYPE_DICTIONARY:
			return
		var dp: Dictionary = dp_any
		if dp.is_empty():
			return
		t["draft"] = dp
		t["draft_proposed"] = {}
		_save_thread_settings(t)
		_refresh_editor_from_current()
		return

	# asset mode
	var asset_id := str(t.get("asset_id", "")).strip_edges()
	if asset_id.is_empty():
		return
	var ap_any: Variant = t.get("asset_proposed", {})
	if typeof(ap_any) != TYPE_DICTIONARY:
		return
	var ap: Dictionary = ap_any
	if ap.is_empty():
		return
	PromptChainStore.set_chain(_scope, asset_id, ap)
	t["asset_proposed"] = {}
	_save_thread_settings(t)
	_reload()
	_select_chain_by_id(asset_id)

func _revert_proposed() -> void:
	var t := _ensure_thread_defaults()
	t["draft_proposed"] = {}
	t["asset_proposed"] = {}
	_save_thread_settings(t)
	_refresh_editor_from_current()

func _on_commit_pressed() -> void:
	if _suppress:
		return
	_commit_proposed()

func _on_revert_pressed() -> void:
	if _suppress:
		return
	_revert_proposed()

func _on_apply_toggled(enabled: bool) -> void:
	if _suppress:
		return
	var t := _ensure_thread_defaults()
	t["apply_to_chat"] = enabled
	_save_thread_settings(t)

func _on_mode_changed(_idx: int) -> void:
	if _suppress:
		return
	var t := _ensure_thread_defaults()
	t["mode"] = "draft" if _mode_option.selected == 1 else "asset"
	_save_thread_settings(t)
	_refresh_editor_from_current()

func _on_add_chain() -> void:
	var id := "pc_%s" % str(Time.get_unix_time_from_system())
	var chain := {"id": id, "name": "New Chain", "blocks": [{"label": "System", "enabled": true, "text": ""}]}
	PromptChainStore.set_chain(_scope, id, chain)
	var t := _ensure_thread_defaults()
	t["mode"] = "asset"
	t["asset_id"] = id
	_save_thread_settings(t)
	_reload()
	_select_chain_by_id(id)

func _select_chain_by_id(chain_id: String) -> void:
	for i in range(_chains_list.item_count):
		if str(_chains_list.get_item_metadata(i)) == chain_id:
			_chains_list.select(i)
			break

func _on_delete_chain() -> void:
	var cid := _get_selected_chain_id()
	if cid.is_empty():
		return
	PromptChainStore.delete_chain(_scope, cid)
	_reload()

func _on_chain_selected(_idx: int) -> void:
	var cid := _get_selected_chain_id()
	if cid.is_empty():
		return
	var t := _ensure_thread_defaults()
	t["mode"] = "asset"
	t["asset_id"] = cid
	_save_thread_settings(t)
	_refresh_editor_from_current()

func _on_save_version_to_hub() -> void:
	await _hub_version_controller.call("save_version", self)

func _on_promote_draft_and_save_to_hub() -> void:
	var t := _ensure_thread_defaults()
	var mode := str(t.get("mode", "asset")).to_lower()
	if mode == "asset":
		# Already an asset: just save a new version.
		_on_save_version_to_hub()
		return

	# Draft -> Asset
	var draft_any: Variant = t.get("draft_proposed", {})
	if typeof(draft_any) != TYPE_DICTIONARY or (draft_any as Dictionary).is_empty():
		draft_any = t.get("draft", {})
	if typeof(draft_any) != TYPE_DICTIONARY:
		push_warning("PromptChainPanel: No draft to promote.")
		return
	var draft: Dictionary = draft_any
	var blocks_any: Variant = draft.get("blocks", [])
	if typeof(blocks_any) != TYPE_ARRAY:
		push_warning("PromptChainPanel: Draft has no blocks.")
		return
	var new_id := "pc_%s" % str(Time.get_unix_time_from_system())
	var new_chain := {
		"id": new_id,
		"name": str(draft.get("name", "Promoted Draft")),
		"blocks": blocks_any,
	}
	# Carry over any slots from the draft.
	if draft.has("slots"):
		new_chain["slots"] = draft.get("slots", [])
	if draft.has("context_binding"):
		new_chain["context_binding"] = draft.get("context_binding", {})
	PromptChainStore.set_chain(_scope, new_id, new_chain)

	# Update thread settings to point to the new asset (and turn on asset mode).
	t["mode"] = "asset"
	t["asset_id"] = new_id
	# Keep draft for safety (user can clear later); but set apply_to_chat true by default.
	if not t.has("apply_to_chat"):
		t["apply_to_chat"] = true
	_save_thread_settings(t)

	# Refresh + select the new chain, then save to hub.
	_reload()
	_select_chain_by_id(new_id)
	await get_tree().process_frame
	# Ensure no pending proposals before versioning.
	var t2 := _ensure_thread_defaults()
	t2["asset_proposed"] = {}
	t2["draft_proposed"] = {}
	_save_thread_settings(t2)
	_on_save_version_to_hub()

# --- Slots (v1) ---
func _refresh_slots_ui(chain: Dictionary) -> void:
	_slots_list.clear()
	var slots_any: Variant = chain.get("slots", [])
	var slots: Array = slots_any if typeof(slots_any) == TYPE_ARRAY else []
	for i in range(slots.size()):
		var s_any: Variant = slots[i]
		if typeof(s_any) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = s_any
		var nm := str(s.get("name", "")).strip_edges()
		if nm.is_empty():
			nm = "(unnamed)"
		_slots_list.add_item(nm)
		_slots_list.set_item_metadata(_slots_list.item_count - 1, i)
	# Clear editor fields if nothing selected
	if _slots_list.get_selected_items().is_empty():
		_suppress = true
		_slot_name.text = ""
		_slot_default.text = ""
		_slot_desc.text = ""
		_slot_value.text = ""
		_suppress = false

func _get_selected_slot_index() -> int:
	if _slots_list.get_selected_items().is_empty():
		return -1
	var idx := int(_slots_list.get_selected_items()[0])
	return int(_slots_list.get_item_metadata(idx))

func _on_slot_selected(_idx: int) -> void:
	var chain := _get_effective_chain()
	var slots_any: Variant = chain.get("slots", [])
	var slots: Array = slots_any if typeof(slots_any) == TYPE_ARRAY else []
	var si := _get_selected_slot_index()
	if si < 0 or si >= slots.size():
		return
	var s_any: Variant = slots[si]
	if typeof(s_any) != TYPE_DICTIONARY:
		return
	var s: Dictionary = s_any
	var name := str(s.get("name", "")).strip_edges()
	var t := _ensure_thread_defaults()
	var sv_any: Variant = t.get("slot_values", {})
	var sv: Dictionary = sv_any if typeof(sv_any) == TYPE_DICTIONARY else {}
	_suppress = true
	_slot_name.text = name
	_slot_default.text = str(s.get("default", ""))
	_slot_desc.text = str(s.get("description", ""))
	_slot_value.text = str(sv.get(name, ""))
	_suppress = false

func _on_add_slot() -> void:
	var chain := _get_effective_chain()
	var slots_any: Variant = chain.get("slots", [])
	var slots: Array = slots_any if typeof(slots_any) == TYPE_ARRAY else []
	slots.append({"name": "slot_%d" % (slots.size() + 1), "default": "", "description": ""})
	chain["slots"] = slots
	_write_chain(chain)
	_refresh_slots_ui(chain)
	_refresh_preview(chain)
	_refresh_commit_ui()

func _on_delete_slot() -> void:
	var chain := _get_effective_chain()
	var slots_any: Variant = chain.get("slots", [])
	if typeof(slots_any) != TYPE_ARRAY:
		return
	var slots: Array = slots_any
	var si := _get_selected_slot_index()
	if si < 0 or si >= slots.size():
		return
	var s_any: Variant = slots[si]
	var name := ""
	if typeof(s_any) == TYPE_DICTIONARY:
		name = str((s_any as Dictionary).get("name", "")).strip_edges()
	slots.remove_at(si)
	chain["slots"] = slots
	_write_chain(chain)
	# Also clear per-thread value if it existed.
	if not name.is_empty():
		var t := _ensure_thread_defaults()
		var sv_any: Variant = t.get("slot_values", {})
		var sv: Dictionary = sv_any if typeof(sv_any) == TYPE_DICTIONARY else {}
		if sv.has(name):
			sv.erase(name)
			t["slot_values"] = sv
			_save_thread_settings(t)
	_refresh_editor_from_current()

func _on_slot_def_changed(_new_text: String = "") -> void:
	if _suppress:
		return
	var chain := _get_effective_chain()
	var slots_any: Variant = chain.get("slots", [])
	var slots: Array = slots_any if typeof(slots_any) == TYPE_ARRAY else []
	var si := _get_selected_slot_index()
	if si < 0 or si >= slots.size():
		return
	var s_any: Variant = slots[si]
	var s: Dictionary = s_any if typeof(s_any) == TYPE_DICTIONARY else {}
	var prev_name := str(s.get("name", "")).strip_edges()
	s["name"] = _slot_name.text.strip_edges()
	s["default"] = _slot_default.text
	s["description"] = _slot_desc.text
	slots[si] = s
	chain["slots"] = slots
	_write_chain(chain)
	# If the slot was renamed, also move the per-thread value mapping.
	var new_name := str(s.get("name", "")).strip_edges()
	if not prev_name.is_empty() and prev_name != new_name:
		var t := _ensure_thread_defaults()
		var sv_any: Variant = t.get("slot_values", {})
		var sv: Dictionary = sv_any if typeof(sv_any) == TYPE_DICTIONARY else {}
		if sv.has(prev_name) and not sv.has(new_name):
			sv[new_name] = sv.get(prev_name, "")
			sv.erase(prev_name)
			t["slot_values"] = sv
			_save_thread_settings(t)
	_refresh_slots_ui(chain)
	_refresh_preview(chain)
	_refresh_commit_ui()

func _on_slot_value_changed(new_text: String) -> void:
	if _suppress:
		return
	var chain := _get_effective_chain()
	var slots_any: Variant = chain.get("slots", [])
	var slots: Array = slots_any if typeof(slots_any) == TYPE_ARRAY else []
	var si := _get_selected_slot_index()
	if si < 0 or si >= slots.size():
		return
	var s_any: Variant = slots[si]
	if typeof(s_any) != TYPE_DICTIONARY:
		return
	var s: Dictionary = s_any
	var name := str(s.get("name", "")).strip_edges()
	if name.is_empty():
		return
	var t := _ensure_thread_defaults()
	var sv_any: Variant = t.get("slot_values", {})
	var sv: Dictionary = sv_any if typeof(sv_any) == TYPE_DICTIONARY else {}
	sv[name] = new_text
	t["slot_values"] = sv
	_save_thread_settings(t)
	_refresh_preview(chain)

func _on_export_slot_values() -> void:
	var res: Dictionary = PromptChainStore.export_thread_slot_values(_scope, _thread_id)
	if not bool(res.get("success", false)):
		push_warning("PromptChainPanel: Export slot values failed: %s" % str(res.get("error", "")))
		return
	# Best-effort user feedback via label
	if is_instance_valid(_diff_label):
		_diff_label.text = "Slot values exported to: %s" % str(res.get("path", ""))

func _on_import_slot_values() -> void:
	var res: Dictionary = PromptChainStore.import_thread_slot_values(_scope, _thread_id, true)
	if not bool(res.get("success", false)):
		push_warning("PromptChainPanel: Import slot values failed: %s" % str(res.get("error", "")))
		return
	_refresh_editor_from_current()
	if is_instance_valid(_diff_label):
		_diff_label.text = "Slot values imported from: %s" % str(res.get("path", ""))

func _on_name_changed(new_text: String) -> void:
	if _suppress:
		return
	var chain := _get_effective_chain()
	chain["name"] = new_text
	_write_chain(chain)
	_refresh_chains_list()
	_refresh_preview(chain)

func _on_add_block() -> void:
	var chain := _get_effective_chain()
	var blocks_any: Variant = chain.get("blocks", [])
	var blocks: Array = blocks_any if typeof(blocks_any) == TYPE_ARRAY else []
	blocks.append({"label": "Block %d" % (blocks.size() + 1), "enabled": true, "text": ""})
	chain["blocks"] = blocks
	_write_chain(chain)
	_refresh_editor_from_current()

func _on_delete_block() -> void:
	if _blocks_list.get_selected_items().is_empty():
		return
	var chain := _get_effective_chain()
	var blocks_any: Variant = chain.get("blocks", [])
	if typeof(blocks_any) != TYPE_ARRAY:
		return
	var blocks: Array = blocks_any
	var idx := int(_blocks_list.get_selected_items()[0])
	var block_index := int(_blocks_list.get_item_metadata(idx))
	if block_index < 0 or block_index >= blocks.size():
		return
	blocks.remove_at(block_index)
	chain["blocks"] = blocks
	_write_chain(chain)
	_refresh_editor_from_current()

func _move_block(delta: int) -> void:
	if _blocks_list.get_selected_items().is_empty():
		return
	var chain := _get_effective_chain()
	var blocks_any: Variant = chain.get("blocks", [])
	if typeof(blocks_any) != TYPE_ARRAY:
		return
	var blocks: Array = blocks_any
	var sel := int(_blocks_list.get_selected_items()[0])
	var i := int(_blocks_list.get_item_metadata(sel))
	var j := i + delta
	if j < 0 or j >= blocks.size():
		return
	var tmp = blocks[i]
	blocks[i] = blocks[j]
	blocks[j] = tmp
	chain["blocks"] = blocks
	_write_chain(chain)
	_refresh_editor_from_current()
	# reselect moved block
	for k in range(_blocks_list.item_count):
		if int(_blocks_list.get_item_metadata(k)) == j:
			_blocks_list.select(k)
			break

func _on_block_selected(_idx: int) -> void:
	_update_block_editor()

func _update_block_editor() -> void:
	var chain := _get_effective_chain()
	var blocks_any: Variant = chain.get("blocks", [])
	if typeof(blocks_any) != TYPE_ARRAY or _blocks_list.get_selected_items().is_empty():
		_suppress = true
		_block_enabled.button_pressed = false
		_block_text.text = ""
		_suppress = false
		return
	var blocks: Array = blocks_any
	var sel := int(_blocks_list.get_selected_items()[0])
	var i := int(_blocks_list.get_item_metadata(sel))
	if i < 0 or i >= blocks.size():
		return
	var b_any: Variant = blocks[i]
	if typeof(b_any) != TYPE_DICTIONARY:
		return
	var b: Dictionary = b_any
	_suppress = true
	_block_enabled.button_pressed = bool(b.get("enabled", true))
	_block_text.text = str(b.get("text", ""))
	_suppress = false

func _on_block_enabled_toggled(enabled: bool) -> void:
	if _suppress:
		return
	var chain := _get_effective_chain()
	var blocks_any: Variant = chain.get("blocks", [])
	if typeof(blocks_any) != TYPE_ARRAY or _blocks_list.get_selected_items().is_empty():
		return
	var blocks: Array = blocks_any
	var sel := int(_blocks_list.get_selected_items()[0])
	var i := int(_blocks_list.get_item_metadata(sel))
	if i < 0 or i >= blocks.size():
		return
	var b_any: Variant = blocks[i]
	if typeof(b_any) != TYPE_DICTIONARY:
		return
	var b: Dictionary = b_any
	b["enabled"] = enabled
	blocks[i] = b
	chain["blocks"] = blocks
	_write_chain(chain)
	_refresh_blocks_list(chain)
	_refresh_preview(chain)

func _on_block_text_changed() -> void:
	if _suppress:
		return
	var chain := _get_effective_chain()
	var blocks_any: Variant = chain.get("blocks", [])
	if typeof(blocks_any) != TYPE_ARRAY or _blocks_list.get_selected_items().is_empty():
		return
	var blocks: Array = blocks_any
	var sel := int(_blocks_list.get_selected_items()[0])
	var i := int(_blocks_list.get_item_metadata(sel))
	if i < 0 or i >= blocks.size():
		return
	var b_any: Variant = blocks[i]
	if typeof(b_any) != TYPE_DICTIONARY:
		return
	var b: Dictionary = b_any
	b["text"] = _block_text.text
	blocks[i] = b
	chain["blocks"] = blocks
	_write_chain(chain)
	_refresh_preview(chain)


