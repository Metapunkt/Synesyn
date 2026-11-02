## Purpose: Minimal Ensembles UI for SynTree to view/edit Metapunkt slot assignments and run a simple multi-slot template.
## Policy: keep this popup self-contained and best-effort (it must not break SynTree when Metapunkt is absent).
@tool
extends PopupPanel

var _view_state: ViewStateResource = null
var _message_input: TextEdit = null
var _reload_thread_cb: Callable = Callable()

@onready var _slots_list: ItemList = get_node_or_null("%SlotsList") as ItemList
@onready var _agent_picker: OptionButton = get_node_or_null("%AgentPicker") as OptionButton
@onready var _paths_label: Label = get_node_or_null("%PathsLabel") as Label
@onready var _status_label: Label = get_node_or_null("%StatusLabel") as Label
@onready var _open_user_synterfaces_button: Button = get_node_or_null("%OpenUserSynterfacesButton") as Button

@onready var _plan_slot_picker: OptionButton = get_node_or_null("%PlanSlotPicker") as OptionButton
@onready var _draft_slot_picker: OptionButton = get_node_or_null("%DraftSlotPicker") as OptionButton
@onready var _review_slot_picker: OptionButton = get_node_or_null("%ReviewSlotPicker") as OptionButton
@onready var _context_synterface_picker: OptionButton = get_node_or_null("%ContextSynterfacePicker") as OptionButton

@onready var _task_input: TextEdit = get_node_or_null("%TaskInput") as TextEdit
@onready var _output: TextEdit = get_node_or_null("%Output") as TextEdit
@onready var _template_picker: OptionButton = get_node_or_null("%TemplatePicker") as OptionButton
@onready var _chat_slot_picker: OptionButton = get_node_or_null("%ChatSlotPicker") as OptionButton
@onready var _logs: TextEdit = get_node_or_null("%Logs") as TextEdit
@onready var _auth_mode_option: OptionButton = get_node_or_null("%AuthModeOption") as OptionButton
@onready var _auth_token_edit: LineEdit = get_node_or_null("%AuthTokenEdit") as LineEdit
@onready var _auth_verify_via_hub_toggle: CheckButton = get_node_or_null("%AuthVerifyViaHubToggle") as CheckButton

var _selected_slot_id: String = ""
var _slots_cache: Dictionary = {} # slot_id -> record
var _agents_cache: Dictionary = {} # agent_id -> status_name
var _log_lines: Array[String] = []
const _MAX_LOG_LINES := 200

func setup(view_state: ViewStateResource, message_input: TextEdit, reload_thread_cb: Callable) -> void:
	_view_state = view_state
	_message_input = message_input
	_reload_thread_cb = reload_thread_cb
	_refresh_all()

func open() -> void:
	_refresh_all()
	popup_centered()

func _get_router() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	var host := tree.root.get_node_or_null("MetapunktAppHost")
	var o: Object = host as Object
	if o and o.has_method("get_agent_slots_catalog") and o.has_method("set_slot_assignment") and o.has_method("clear_slot_assignment"):
		return o
	return null

func _find_endpoint() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	var n: Node = tree.root.find_child("MetapunktEndpointHandler", true, false)
	var o: Object = n as Object
	if o and o.has_method("get_agents") and o.has_method("call_tool"):
		return o
	return null

func _refresh_all() -> void:
	_refresh_slots()
	_refresh_agents()
	_refresh_slot_pickers_for_template()
	_refresh_user_synterfaces_ui()
	_refresh_chat_slot_picker()
	_wire_progress_logs_best_effort()
	_refresh_auth_ui()
	_refresh_paths_and_status()

func _refresh_auth_ui() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_cfg: Dictionary = cfg.get("apps", {})
	var mp_cfg: Dictionary = apps_cfg.get("metapunkt", {})
	var mode := str(mp_cfg.get("auth_mode", "no-auth")).strip_edges().to_lower()
	if _auth_mode_option:
		# Back-compat: accept "open"/"required"
		_auth_mode_option.select(1 if (mode == "auth-required" or mode == "required") else 0)
	if _auth_token_edit:
		_auth_token_edit.text = str(mp_cfg.get("auth_token", ""))
	if _auth_verify_via_hub_toggle:
		_auth_verify_via_hub_toggle.button_pressed = bool(mp_cfg.get("auth_verify_via_hub", false))

func _on_auth_save_pressed() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_cfg: Dictionary = cfg.get("apps", {})
	var mp_cfg: Dictionary = apps_cfg.get("metapunkt", {})
	var auth_mode := "no-auth"
	if _auth_mode_option:
		auth_mode = "auth-required" if _auth_mode_option.selected == 1 else "no-auth"
	mp_cfg["auth_mode"] = auth_mode
	if _auth_token_edit:
		mp_cfg["auth_token"] = _auth_token_edit.text.strip_edges()
	if _auth_verify_via_hub_toggle:
		mp_cfg["auth_verify_via_hub"] = bool(_auth_verify_via_hub_toggle.button_pressed)
	apps_cfg["metapunkt"] = mp_cfg
	cfg["apps"] = apps_cfg
	if not RuntimeConfig.save_config(cfg):
		_append_log("Auth save failed: could not write Documents/Synesyn config (synesyn_client.json)")
		return
	_append_log("Saved Metapunkt auth: mode=%s, verify_via_hub=%s" % [auth_mode, str(mp_cfg.get("auth_verify_via_hub", false))])

func _refresh_chat_slot_picker() -> void:
	if not _chat_slot_picker:
		return
	_chat_slot_picker.clear()
	_chat_slot_picker.add_item("(select slot)")
	_chat_slot_picker.set_item_metadata(0, "")
	var ids: Array = _slots_cache.keys()
	ids.sort()
	for sid_any in ids:
		var sid := str(sid_any).strip_edges()
		if sid.is_empty():
			continue
		var idx := _chat_slot_picker.item_count
		_chat_slot_picker.add_item(sid)
		_chat_slot_picker.set_item_metadata(idx, sid)

func _wire_progress_logs_best_effort() -> void:
	# Best-effort: attach to Metapunkt endpoint orchestration_event stream if present.
	var ep := _find_endpoint()
	if not ep:
		_append_log("Metapunkt endpoint not found (no logs).")
		return
	if not ep.has_signal("orchestration_event"):
		_append_log("Metapunkt endpoint has no orchestration_event signal (no logs).")
		return
	var sig_any: Variant = ep.get("orchestration_event")
	if typeof(sig_any) != TYPE_SIGNAL:
		_append_log("Metapunkt orchestration_event is not a Signal (no logs).")
		return
	var sig: Signal = sig_any
	if not sig.is_connected(_on_metapunkt_orchestration_event):
		sig.connect(_on_metapunkt_orchestration_event)
		_append_log("Connected to Metapunkt orchestration_event (best-effort).")

func _on_metapunkt_orchestration_event(evt: Dictionary) -> void:
	var et := str(evt.get("event_type", "")).strip_edges()
	# Filter: keep higher-signal events only.
	if et.find("tool.") != -1 or et.find("job.") != -1 or et.find("sensor.warning") != -1 or et.find("metapunkt.") != -1:
		_append_log("%s %s" % [et, JSON.stringify(evt.get("payload", {}))])

func _append_log(line: String) -> void:
	if line.strip_edges().is_empty():
		return
	_log_lines.append("[%s] %s" % [Time.get_time_string_from_system(), line])
	while _log_lines.size() > _MAX_LOG_LINES:
		_log_lines.pop_front()
	if _logs:
		_logs.text = "\n".join(_log_lines)

func _refresh_slots() -> void:
	if not _slots_list:
		return
	var router := _get_router()
	_slots_list.clear()
	_slots_cache.clear()
	_selected_slot_id = ""
	if not router:
		_slots_list.add_item("MetapunktAppHost router not available.")
		return
	var cat_any: Variant = router.call("get_agent_slots_catalog")
	if typeof(cat_any) != TYPE_DICTIONARY:
		_slots_list.add_item("Slot catalog unavailable.")
		return
	var cat: Dictionary = cat_any
	var slots_any: Variant = cat.get("slots")
	var slots: Dictionary = slots_any if typeof(slots_any) == TYPE_DICTIONARY else {}
	var ids: Array = slots.keys()
	ids.sort()
	for sid_any in ids:
		var sid := str(sid_any).strip_edges()
		if sid.is_empty():
			continue
		var rec_any: Variant = slots.get(sid_any)
		if typeof(rec_any) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_any
		_slots_cache[sid] = rec
		var label := str(rec.get("label", "")).strip_edges()
		var assigned := str(rec.get("assigned_agent_id", "")).strip_edges()
		var conflict := bool(rec.get("conflict", false))
		var line := sid
		if not label.is_empty():
			line += " — " + label
		if conflict:
			line += " [CONFLICT]"
		elif not assigned.is_empty():
			line += " (assigned: %s)" % assigned
		var i := _slots_list.item_count
		_slots_list.add_item(line)
		_slots_list.set_item_metadata(i, sid)
	if _slots_list.item_count > 0:
		_slots_list.select(0)
		_on_slot_selected(0)

func _refresh_agents() -> void:
	if not _agent_picker:
		return
	_agent_picker.clear()
	_agent_picker.add_item("(no agent)")
	_agent_picker.set_item_metadata(0, "")
	_agents_cache.clear()
	var ep := _find_endpoint()
	if not ep:
		return
	var agents_any: Variant = ep.call("get_agents")
	if typeof(agents_any) != TYPE_ARRAY:
		return
	for a_any in (agents_any as Array):
		var a: Object = a_any as Object
		if not a:
			continue
		var aid := str(a.get("agent_id")).strip_edges()
		if aid.is_empty():
			continue
		var st := ""
		if a.has_method("get_status_info"):
			var info: Dictionary = a.call("get_status_info")
			st = str(info.get("status_name", "")).strip_edges()
		_agents_cache[aid] = st
		var line := aid
		if not st.is_empty():
			line += " [%s]" % st
		var idx := _agent_picker.item_count
		_agent_picker.add_item(line)
		_agent_picker.set_item_metadata(idx, aid)

func _refresh_slot_pickers_for_template() -> void:
	# Template uses slots; populate with all known slot ids.
	var pickers: Array = [_plan_slot_picker, _draft_slot_picker, _review_slot_picker]
	for p_any in pickers:
		var p: OptionButton = p_any as OptionButton
		if not p:
			continue
		p.clear()
		p.add_item("(select slot)")
		p.set_item_metadata(0, "")
		var ids: Array = _slots_cache.keys()
		ids.sort()
		for sid_any in ids:
			var sid := str(sid_any).strip_edges()
			if sid.is_empty():
				continue
			var idx := p.item_count
			p.add_item(sid)
			p.set_item_metadata(idx, sid)

	# Best-effort default selection for known apps
	_select_slot_if_present(_plan_slot_picker, "scensyn.narrator")
	_select_slot_if_present(_draft_slot_picker, "readymade.a1")

func _select_slot_if_present(p: OptionButton, sid: String) -> void:
	if not p:
		return
	for i in range(p.item_count):
		if str(p.get_item_metadata(i)).strip_edges() == sid:
			p.select(i)
			return

func _refresh_user_synterfaces_ui() -> void:
	if not _context_synterface_picker:
		return
	_context_synterface_picker.clear()
	_context_synterface_picker.add_item("(no context synterface)")
	_context_synterface_picker.set_item_metadata(0, "")
	var router := _get_router()
	if not router or not router.has_method("get_user_synterfaces_catalog"):
		return
	var cat_any: Variant = router.call("get_user_synterfaces_catalog")
	if typeof(cat_any) != TYPE_DICTIONARY:
		return
	var cat: Dictionary = cat_any
	var syn_any: Variant = cat.get("synterfaces")
	if typeof(syn_any) != TYPE_DICTIONARY:
		return
	var syn: Dictionary = syn_any
	var ids: Array = syn.keys()
	ids.sort()
	for sid_any in ids:
		var sid := str(sid_any).strip_edges()
		if sid.is_empty():
			continue
		var rec_any: Variant = syn.get(sid_any)
		var rec: Dictionary = rec_any if typeof(rec_any) == TYPE_DICTIONARY else {}
		var desc := str(rec.get("description", "")).strip_edges()
		var line := sid
		if not desc.is_empty():
			line += " — " + desc
		var idx := _context_synterface_picker.item_count
		_context_synterface_picker.add_item(line)
		_context_synterface_picker.set_item_metadata(idx, sid)

func _on_open_user_synterfaces_pressed() -> void:
	var router := _get_router()
	if not router or not router.has_method("get_user_synterfaces_path_abs"):
		if _status_label:
			_status_label.text = "Cannot open user_synterfaces.json (router unavailable)."
		return
	var path_abs := str(router.call("get_user_synterfaces_path_abs")).strip_edges()
	if path_abs.is_empty():
		return
	_open_in_file_manager(path_abs)

func _open_in_file_manager(path_abs: String) -> void:
	if OS.get_name() == "Windows":
		var win := path_abs.replace("/", "\\")
		var err := OS.create_process("explorer.exe", ["/select,", win])
		if err != OK:
			OS.create_process("explorer.exe", [win])
		return
	OS.shell_open("file://" + path_abs)

func _refresh_paths_and_status() -> void:
	if _paths_label:
		var router := _get_router()
		if router and router.has_method("get_slot_assignments_path_abs"):
			_paths_label.text = "Slot assignments: %s" % str(router.call("get_slot_assignments_path_abs"))
		else:
			_paths_label.text = ""
	if _status_label:
		var ep := _find_endpoint()
		var s := ""
		if not _get_router():
			s = "Router not available."
		elif not ep:
			s = "MetapunktEndpointHandler not found (templates will be disabled)."
		_status_label.text = s

func _on_slot_selected(index: int) -> void:
	if not _slots_list or index < 0 or index >= _slots_list.item_count:
		_selected_slot_id = ""
		return
	var md_any: Variant = _slots_list.get_item_metadata(index)
	_selected_slot_id = str(md_any).strip_edges() if md_any != null else ""
	# Align agent picker selection to current assignment
	if not _agent_picker:
		return
	var rec: Dictionary = _slots_cache.get(_selected_slot_id, {})
	var assigned := str(rec.get("assigned_agent_id", "")).strip_edges()
	if assigned.is_empty():
		_agent_picker.select(0)
		return
	for i in range(_agent_picker.item_count):
		if str(_agent_picker.get_item_metadata(i)).strip_edges() == assigned:
			_agent_picker.select(i)
			return
	_agent_picker.select(0)

func _on_assign_pressed() -> void:
	var router := _get_router()
	if not router or _selected_slot_id.is_empty() or not _agent_picker:
		return
	var aid := str(_agent_picker.get_item_metadata(_agent_picker.selected)).strip_edges()
	if aid.is_empty():
		router.call("clear_slot_assignment", _selected_slot_id)
	else:
		router.call("set_slot_assignment", _selected_slot_id, aid)
	_refresh_slots()
	_refresh_paths_and_status()

func _on_clear_pressed() -> void:
	var router := _get_router()
	if not router or _selected_slot_id.is_empty():
		return
	router.call("clear_slot_assignment", _selected_slot_id)
	_refresh_slots()
	_refresh_paths_and_status()

func _on_use_current_input_pressed() -> void:
	if not _task_input:
		return
	if is_instance_valid(_message_input):
		_task_input.text = _message_input.text

func _on_run_pressed() -> void:
	if not _task_input or not _output:
		return
	_output.text = ""
	_append_log("Workflow run requested.")
	var base := _task_input.text.strip_edges()
	if base.is_empty():
		_output.text = "Task is empty."
		_append_log("Workflow run aborted: task empty.")
		return
	var ep := _find_endpoint()
	if not ep:
		_output.text = "MetapunktEndpointHandler not available. Open Tools → Metapunkt first."
		_append_log("Workflow run aborted: Metapunkt endpoint missing.")
		return

	var plan_slot := _get_picker_slot_id(_plan_slot_picker)
	var draft_slot := _get_picker_slot_id(_draft_slot_picker)
	var review_slot := _get_picker_slot_id(_review_slot_picker)
	if plan_slot.is_empty() or draft_slot.is_empty() or review_slot.is_empty():
		_output.text = "Select plan/draft/review slots first."
		_append_log("Workflow run aborted: slots not selected.")
		return

	var thread_id := "default"
	if is_instance_valid(_view_state) and _view_state.has_method("get_current_thread_id"):
		thread_id = str(_view_state.get_current_thread_id()).strip_edges()
		if thread_id.is_empty():
			thread_id = "default"

	# Optional: inject a user synterface binding (data-driven context) into all prompts.
	var ctx_sid := _get_picker_synterface_id(_context_synterface_picker)
	var ctx_block := ""
	if not ctx_sid.is_empty():
		var ctx_res := _resolve_synterface_binding(ctx_sid)
		if bool(ctx_res.get("ok", false)):
			ctx_block = "\n\nUSER SYNTERFACE CONTEXT (%s):\n%s" % [ctx_sid, str(ctx_res.get("binding", {}))]
		else:
			_output.text = "Context synterface bind failed: %s" % str(ctx_res.get("error", "unknown"))
			return

	var template_id := 0
	if _template_picker:
		template_id = int(_template_picker.get_item_id(_template_picker.selected))

	match template_id:
		1:
			await _run_template_outline_expand_summarize(ep, plan_slot, draft_slot, review_slot, base, ctx_block, thread_id)
		_:
			await _run_template_plan_draft_review(ep, plan_slot, draft_slot, review_slot, base, ctx_block, thread_id)

	# Refresh chat UI to reflect any thread changes (best-effort).
	if _reload_thread_cb.is_valid():
		_reload_thread_cb.call()
	_append_log("Workflow run complete.")

func _on_send_as_slot_pressed() -> void:
	if not _chat_slot_picker:
		return
	var sid := str(_chat_slot_picker.get_item_metadata(_chat_slot_picker.selected)).strip_edges()
	if sid.is_empty():
		_append_log("Send-as-slot aborted: no slot selected.")
		return

	var msg := ""
	if is_instance_valid(_message_input):
		msg = _message_input.text.strip_edges()
	if msg.is_empty() and _task_input:
		msg = _task_input.text.strip_edges()
	if msg.is_empty():
		_append_log("Send-as-slot aborted: message empty.")
		return

	var thread_id := "default"
	if is_instance_valid(_view_state) and _view_state.has_method("get_current_thread_id"):
		thread_id = str(_view_state.get_current_thread_id()).strip_edges()
		if thread_id.is_empty():
			thread_id = "default"

	var ep := _find_endpoint()
	if not ep:
		_append_log("Send-as-slot failed: Metapunkt endpoint missing.")
		return
	var agent_id := _resolve_assigned_agent_id(sid)
	if agent_id.is_empty():
		_append_log("Send-as-slot failed: slot '%s' is unassigned." % sid)
		return

	_append_log("Send-as-slot: %s via %s" % [sid, agent_id])
	var args := {"operation": "chat", "message": msg, "thread_name": thread_id}
	var AuthContextUtils = preload("res://addons/synesyn_core/scripts/auth_context_utils.gd")
	var user_id := AuthContextUtils.get_user_id("syntree", "ui")
	var scopes: Array = AuthContextUtils.get_scopes("syntree")
	var env_any: Variant = await ep.call("call_tool", agent_id, "SynTree", args, user_id, scopes)
	if typeof(env_any) != TYPE_DICTIONARY:
		_append_log("Send-as-slot failed: invalid tool-call result.")
		return
	var env: Dictionary = env_any
	if not bool(env.get("ok", false)):
		_append_log("Send-as-slot failed: %s" % str(env.get("error", "Tool error")))
		return
	_append_log("Send-as-slot: ok")
	if _reload_thread_cb.is_valid():
		_reload_thread_cb.call()

func _run_template_plan_draft_review(ep: Object, plan_slot: String, draft_slot: String, review_slot: String, base: String, ctx_block: String, thread_id: String) -> void:
	# Step 1: plan
	var plan_out := await _run_step(ep, plan_slot, "PLAN", "Create a concise plan.\n\nTASK:\n%s%s" % [base, ctx_block], thread_id)
	if not plan_out.ok:
		_output.text = "PLAN failed: %s" % plan_out.error
		return
	_output.text += "PLAN:\n%s\n\n" % plan_out.text

	# Step 2: draft
	var draft_out := await _run_step(ep, draft_slot, "DRAFT", "Write the draft based on the plan.\n\nTASK:\n%s%s\n\nPLAN:\n%s" % [base, ctx_block, plan_out.text], thread_id)
	if not draft_out.ok:
		_output.text += "DRAFT failed: %s" % draft_out.error
		return
	_output.text += "DRAFT:\n%s\n\n" % draft_out.text

	# Step 3: review
	var review_out := await _run_step(ep, review_slot, "REVIEW", "Review the draft. Provide concrete improvements and a revised version if needed.\n\nTASK:\n%s%s\n\nDRAFT:\n%s" % [base, ctx_block, draft_out.text], thread_id)
	if not review_out.ok:
		_output.text += "REVIEW failed: %s" % review_out.error
		return
	_output.text += "REVIEW:\n%s\n" % review_out.text

func _run_template_outline_expand_summarize(ep: Object, outline_slot: String, expand_slot: String, summarize_slot: String, base: String, ctx_block: String, thread_id: String) -> void:
	# Step 1: outline
	var outline_out := await _run_step(ep, outline_slot, "OUTLINE", "Produce a structured outline with headings and bullet points.\n\nTASK:\n%s%s" % [base, ctx_block], thread_id)
	if not outline_out.ok:
		_output.text = "OUTLINE failed: %s" % outline_out.error
		return
	_output.text += "OUTLINE:\n%s\n\n" % outline_out.text

	# Step 2: expand
	var expand_out := await _run_step(ep, expand_slot, "EXPAND", "Expand the outline into a full draft.\n\nTASK:\n%s%s\n\nOUTLINE:\n%s" % [base, ctx_block, outline_out.text], thread_id)
	if not expand_out.ok:
		_output.text += "EXPAND failed: %s" % expand_out.error
		return
	_output.text += "EXPANDED DRAFT:\n%s\n\n" % expand_out.text

	# Step 3: summarize
	var summ_out := await _run_step(ep, summarize_slot, "SUMMARY", "Summarize the draft into:\n- a 1-paragraph summary\n- 5 bullet key points\n- a one-line title\n\nTASK:\n%s%s\n\nDRAFT:\n%s" % [base, ctx_block, expand_out.text], thread_id)
	if not summ_out.ok:
		_output.text += "SUMMARY failed: %s" % summ_out.error
		return
	_output.text += "SUMMARY:\n%s\n" % summ_out.text

func _get_picker_slot_id(p: OptionButton) -> String:
	if not p:
		return ""
	return str(p.get_item_metadata(p.selected)).strip_edges()

func _get_picker_synterface_id(p: OptionButton) -> String:
	if not p:
		return ""
	return str(p.get_item_metadata(p.selected)).strip_edges()

func _resolve_synterface_binding(sid: String) -> Dictionary:
	var router := _get_router()
	if not router or not router.has_method("bind_synterfaces"):
		return {"ok": false, "error": "Router unavailable"}
	var res_any: Variant = router.call("bind_synterfaces", [sid], {})
	if typeof(res_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Invalid bind result"}
	var res: Dictionary = res_any
	if not bool(res.get("ok", false)):
		return {"ok": false, "error": str(res.get("error", "bind failed"))}
	var syn_any: Variant = res.get("synterfaces")
	if typeof(syn_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Missing synterfaces payload"}
	var syn: Dictionary = syn_any
	if not syn.has(sid):
		return {"ok": false, "error": "Binding missing for %s" % sid}
	return {"ok": true, "binding": syn.get(sid)}

func _resolve_assigned_agent_id(slot_id: String) -> String:
	var rec: Dictionary = _slots_cache.get(slot_id, {})
	return str(rec.get("assigned_agent_id", "")).strip_edges()

func _run_step(ep: Object, slot_id: String, label: String, prompt: String, thread_id: String) -> Dictionary:
	var agent_id := _resolve_assigned_agent_id(slot_id)
	if agent_id.is_empty():
		return {"ok": false, "error": "Slot '%s' is unassigned." % slot_id}
	var args := {
		"operation": "chat",
		"message": "[Ensemble/%s via %s]\n%s" % [label, slot_id, prompt],
		"thread_name": thread_id,
	}
	var AuthContextUtils = preload("res://addons/synesyn_core/scripts/auth_context_utils.gd")
	var user_id := AuthContextUtils.get_user_id("syntree", "ensemble")
	var scopes: Array = AuthContextUtils.get_scopes("syntree")
	var env_any: Variant = await ep.call("call_tool", agent_id, "SynTree", args, user_id, scopes)
	if typeof(env_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Invalid tool-call result"}
	var env: Dictionary = env_any
	if not bool(env.get("ok", false)):
		var err_obj: Variant = env.get("error_obj")
		if typeof(err_obj) == TYPE_DICTIONARY:
			return {"ok": false, "error": str((err_obj as Dictionary).get("message", env.get("error", "Tool error")))}
		return {"ok": false, "error": str(env.get("error", "Tool error"))}
	var res_any: Variant = env.get("result")
	if typeof(res_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "SynTree tool returned invalid payload"}
	var res: Dictionary = res_any
	if not bool(res.get("success", false)):
		return {"ok": false, "error": str(res.get("error", "SynTree chat failed"))}
	return {"ok": true, "text": str(res.get("response", ""))}


