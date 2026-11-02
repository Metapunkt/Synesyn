extends RefCounted
class_name MetapunktSynterfaceSlotsUtils

static func refresh_synterface_issues_ui(owner: Control) -> void:
	var list_node: ItemList = owner.get("_synterface_issues_list")
	if not list_node:
		return
	var host: Object = owner.call("_get_app_host_router")
	if not host:
		list_node.clear()
		owner.set("_selected_issue_sid", "")
		owner.call("_update_synterface_impl_picker", [])
		var overrides_path: Label = owner.get("_synterface_overrides_path")
		if overrides_path:
			overrides_path.text = "MetapunktAppHost router not available."
		return
	var issues_any: Variant = host.call("get_synterface_issues")
	if typeof(issues_any) != TYPE_ARRAY:
		return
	var issues: Array = issues_any
	var sig_parts: Array = []
	for it_any in issues:
		if typeof(it_any) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_any
		sig_parts.append("%s:%s:%s" % [str(it.get("synterface_id", "")), str(it.get("status", "")), str(it.get("override", ""))])
	var sig := "|".join(sig_parts)
	var old_sig := str(owner.get("_synterface_issues_signature"))
	if sig == old_sig:
		var ov_path: Label = owner.get("_synterface_overrides_path")
		if ov_path and host.has_method("get_overrides_path_abs"):
			ov_path.text = "Overrides: %s" % str(host.call("get_overrides_path_abs"))
		var user_path: Label = owner.get("_user_synterfaces_path")
		if user_path and host.has_method("get_user_synterfaces_path_abs"):
			user_path.text = "User synterfaces: %s" % str(host.call("get_user_synterfaces_path_abs"))
		# Keep user synterfaces issues fresh even when the issues list itself is unchanged.
		_refresh_user_synterfaces_issues_label(owner, host)
		return
	owner.set("_synterface_issues_signature", sig)
	var prev_sid := str(owner.get("_selected_issue_sid"))
	list_node.clear()
	for it_any in issues:
		var it: Dictionary = it_any
		var sid := str(it.get("synterface_id", "")).strip_edges()
		var status := str(it.get("status", "")).strip_edges()
		var override := str(it.get("override", "")).strip_edges()
		var label := "%s [%s]" % [sid, status.to_upper()]
		if not override.is_empty():
			label += " (override set)"
		var i := list_node.item_count
		list_node.add_item(label)
		list_node.set_item_metadata(i, it)
	if not prev_sid.is_empty():
		for i2 in range(list_node.item_count):
			var md_any: Variant = list_node.get_item_metadata(i2)
			if typeof(md_any) != TYPE_DICTIONARY:
				continue
			if str((md_any as Dictionary).get("synterface_id", "")).strip_edges() == prev_sid:
				list_node.select(i2)
				owner.call("_on_synterface_issue_selected", i2)
				break
	elif list_node.item_count > 0:
		list_node.select(0)
		owner.call("_on_synterface_issue_selected", 0)
	else:
		owner.set("_selected_issue_sid", "")
		owner.call("_update_synterface_impl_picker", [])
	var ov_path2: Label = owner.get("_synterface_overrides_path")
	if ov_path2 and host.has_method("get_overrides_path_abs"):
		ov_path2.text = "Overrides: %s" % str(host.call("get_overrides_path_abs"))
	var user_path2: Label = owner.get("_user_synterfaces_path")
	if user_path2 and host.has_method("get_user_synterfaces_path_abs"):
		user_path2.text = "User synterfaces: %s" % str(host.call("get_user_synterfaces_path_abs"))
	# Always refresh the issues label so fixes to user_synterfaces.json are reflected promptly.
	_refresh_user_synterfaces_issues_label(owner, host)


static func _refresh_user_synterfaces_issues_label(owner: Control, host: Object) -> void:
	var issues_lbl: Label = owner.get("_user_synterfaces_issues_label")
	if issues_lbl:
		issues_lbl.text = format_user_synterfaces_issues(host)


static func format_user_synterfaces_issues(host: Object) -> String:
	if not host or not host.has_method("get_user_synterfaces_issues"):
		return ""
	var iss_any: Variant = host.call("get_user_synterfaces_issues")
	if typeof(iss_any) != TYPE_ARRAY:
		return ""
	var iss: Array = iss_any
	if iss.is_empty():
		return "User synterfaces: OK"
	var lines: Array[String] = []
	lines.append("User synterfaces: %d issue(s)" % iss.size())
	var n := min(iss.size(), 6)
	for i in range(n):
		var it_any: Variant = iss[i]
		if typeof(it_any) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_any
		lines.append("- %s: %s" % [str(it.get("synterface_id", "")), str(it.get("error", ""))])
	if iss.size() > n:
		lines.append("…")
	return "\n".join(lines)


static func on_open_user_synterfaces_pressed(owner: Control) -> void:
	var host: Object = owner.call("_get_app_host_router")
	if not host or not host.has_method("get_user_synterfaces_path_abs"):
		owner.call("_agentdef_set_status", "Cannot open user_synterfaces.json (router unavailable).")
		return
	var path_abs := str(host.call("get_user_synterfaces_path_abs")).strip_edges()
	if path_abs.is_empty():
		owner.call("_agentdef_set_status", "Cannot open user_synterfaces.json (path unavailable).")
		return
	open_in_file_manager(owner, path_abs)


static func open_in_file_manager(owner: Control, path_abs: String) -> void:
	var p := path_abs
	if OS.get_name() == "Windows":
		var win := p.replace("/", "\\")
		var err := OS.create_process("explorer.exe", ["/select,", win])
		if err != OK:
			OS.create_process("explorer.exe", [win])
		owner.call("_agentdef_set_status", "Opened: %s" % win)
		return
	var url := "file://" + p
	OS.shell_open(url)
	owner.call("_agentdef_set_status", "Opened: %s" % p)


static func update_synterface_impl_picker(owner: Control, impls: Array) -> void:
	var picker: OptionButton = owner.get("_synterface_impl_picker")
	if not picker:
		return
	picker.clear()
	for impl_any in impls:
		if typeof(impl_any) != TYPE_DICTIONARY:
			continue
		var impl: Dictionary = impl_any
		var impl_id := str(impl.get("impl_id", "")).strip_edges()
		var provider_id := str(impl.get("provider_id", "")).strip_edges()
		var provider_class := str(impl.get("provider_class", "")).strip_edges()
		var txt := "%s (%s)" % [provider_id, provider_class]
		var idx := picker.item_count
		picker.add_item(txt)
		picker.set_item_metadata(idx, impl_id)
	if picker.item_count > 0:
		picker.select(0)


static func on_synterface_issue_selected(owner: Control, index: int) -> void:
	var list_node: ItemList = owner.get("_synterface_issues_list")
	if not list_node or index < 0 or index >= list_node.item_count:
		owner.set("_selected_issue_sid", "")
		update_synterface_impl_picker(owner, [])
		return
	var md_any: Variant = list_node.get_item_metadata(index)
	if typeof(md_any) != TYPE_DICTIONARY:
		return
	var md: Dictionary = md_any
	owner.set("_selected_issue_sid", str(md.get("synterface_id", "")).strip_edges())
	var impls_any: Variant = md.get("impls")
	var impls: Array = impls_any if typeof(impls_any) == TYPE_ARRAY else []
	update_synterface_impl_picker(owner, impls)


static func on_synterface_set_override_pressed(owner: Control) -> void:
	var host: Object = owner.call("_get_app_host_router")
	var selected_sid := str(owner.get("_selected_issue_sid")).strip_edges()
	if not host or selected_sid.is_empty():
		return
	var picker: OptionButton = owner.get("_synterface_impl_picker")
	if not picker or picker.item_count <= 0:
		return
	var idx := picker.get_selected()
	if idx < 0:
		return
	var impl_id := str(picker.get_item_metadata(idx)).strip_edges()
	var res_any: Variant = host.call("set_override", selected_sid, impl_id)
	if typeof(res_any) == TYPE_DICTIONARY and bool((res_any as Dictionary).get("ok", false)):
		owner.call("_agentdef_set_status", "Override set for %s" % selected_sid)
	else:
		var msg := "unknown error"
		if typeof(res_any) == TYPE_DICTIONARY:
			msg = str((res_any as Dictionary).get("error", ""))
		owner.call("_agentdef_set_status", "Override set failed: %s" % msg)
	owner.set("_synterface_issues_signature", "")
	refresh_synterface_issues_ui(owner)


static func on_synterface_clear_override_pressed(owner: Control) -> void:
	var host: Object = owner.call("_get_app_host_router")
	var selected_sid := str(owner.get("_selected_issue_sid")).strip_edges()
	if not host or selected_sid.is_empty():
		return
	var res_any: Variant = host.call("clear_override", selected_sid)
	if typeof(res_any) == TYPE_DICTIONARY and bool((res_any as Dictionary).get("ok", false)):
		owner.call("_agentdef_set_status", "Override cleared for %s" % selected_sid)
	else:
		owner.call("_agentdef_set_status", "Override clear failed")
	owner.set("_synterface_issues_signature", "")
	refresh_synterface_issues_ui(owner)


static func refresh_agent_slots_ui(owner: Control) -> void:
	var list_node: ItemList = owner.get("_agent_slots_list")
	if not list_node:
		return
	var host: Object = owner.call("_get_router_obj_any")
	if not host or not host.has_method("get_agent_slots_catalog"):
		list_node.clear()
		owner.set("_selected_slot_id", "")
		var path_lbl: Label = owner.get("_agent_slot_assignments_path")
		if path_lbl:
			path_lbl.text = "MetapunktAppHost router not available."
		var status_lbl: Label = owner.get("_agent_slots_status")
		if status_lbl:
			status_lbl.text = ""
		return
	var picker: OptionButton = owner.get("_agent_slot_picker")
	if picker:
		owner.call("_update_agent_list_into", picker, true)
	var cat_any: Variant = host.call("get_agent_slots_catalog")
	if typeof(cat_any) != TYPE_DICTIONARY:
		return
	var cat: Dictionary = cat_any
	var slots_any: Variant = cat.get("slots")
	var slots: Dictionary = slots_any if typeof(slots_any) == TYPE_DICTIONARY else {}
	var ids: Array = slots.keys()
	ids.sort()
	var sig_parts: Array = []
	var ep_obj: Object = owner.call("_get_endpoint_obj")
	var ar: Object = owner.call("_get_agent_registry", ep_obj)
	var agents: Array = ar.call("get_all_agent_instances") if ar and ar.has_method("get_all_agent_instances") else []
	var agent_status_sig: Array = []
	for a_any in agents:
		var a: Object = a_any as Object
		if not a:
			continue
		var aid := str(a.get("agent_id")).strip_edges()
		var st := ""
		if a.has_method("get_status_info"):
			var info: Dictionary = a.call("get_status_info")
			st = str(info.get("status_name", "")).strip_edges()
		agent_status_sig.append("%s=%s" % [aid, st])
	agent_status_sig.sort()
	for sid_any in ids:
		var rec_any: Variant = slots.get(sid_any)
		if typeof(rec_any) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_any
		sig_parts.append("%s:%s" % [str(sid_any), str(rec.get("assigned_agent_id", ""))])
	var sig := ",".join(sig_parts) + "||" + ",".join(agent_status_sig)
	var old_sig := str(owner.get("_agent_slots_signature"))
	if sig != old_sig:
		owner.set("_agent_slots_signature", sig)
		list_node.clear()
		for sid_any in ids:
			var sid := str(sid_any).strip_edges()
			if sid.is_empty():
				continue
			var rec_any: Variant = slots.get(sid_any)
			if typeof(rec_any) != TYPE_DICTIONARY:
				continue
			var rec: Dictionary = rec_any
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
			var i := list_node.item_count
			list_node.add_item(line)
			list_node.set_item_metadata(i, rec)
	if list_node.item_count > 0:
		var idx_to_select := 0
		var selected_slot_id := str(owner.get("_selected_slot_id")).strip_edges()
		if not selected_slot_id.is_empty():
			for i2 in range(list_node.item_count):
				var md_any: Variant = list_node.get_item_metadata(i2)
				if typeof(md_any) == TYPE_DICTIONARY and str((md_any as Dictionary).get("slot_id", "")).strip_edges() == selected_slot_id:
					idx_to_select = i2
					break
		list_node.select(idx_to_select)
		on_agent_slot_selected(owner, idx_to_select)
	else:
		owner.set("_selected_slot_id", "")
	var path_lbl2: Label = owner.get("_agent_slot_assignments_path")
	if path_lbl2 and host.has_method("get_slot_assignments_path_abs"):
		path_lbl2.text = "Slot assignments: %s" % str(host.call("get_slot_assignments_path_abs"))
	validate_slot_assignments_ui(owner, host, slots, agents, ep_obj)


static func validate_slot_assignments_ui(owner: Control, host: Object, slots: Dictionary, agents: Array, ep_obj: Object) -> void:
	var status_lbl: Label = owner.get("_agent_slots_status")
	if not status_lbl:
		return
	var by_id: Dictionary = {}
	for a_any in agents:
		var a: Object = a_any as Object
		if not a:
			continue
		var aid := str(a.get("agent_id")).strip_edges()
		if not aid.is_empty():
			by_id[aid] = a
	var role_policy: Object = null
	var all_tools: Array[String] = []
	if ep_obj:
		var rp_any: Variant = ep_obj.get("role_policy")
		role_policy = rp_any as Object
		var tr_any: Variant = ep_obj.get("tool_registry")
		var tr: Object = tr_any as Object
		if tr and tr.has_method("get_tools"):
			var tools_any: Variant = tr.call("get_tools")
			if typeof(tools_any) == TYPE_ARRAY:
				for t in (tools_any as Array):
					var s := str(t).strip_edges()
					if not s.is_empty():
						all_tools.append(s)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if host.has_method("get_slot_assignment_issues"):
		var iss_any: Variant = host.call("get_slot_assignment_issues")
		if typeof(iss_any) == TYPE_DICTIONARY:
			var unknown_any: Variant = (iss_any as Dictionary).get("unknown_slots")
			if typeof(unknown_any) == TYPE_ARRAY and not (unknown_any as Array).is_empty():
				warnings.append("Unknown slot ids in saved assignments: %s" % str(unknown_any))
	for sid_any in slots.keys():
		var sid := str(sid_any).strip_edges()
		var rec_any: Variant = slots.get(sid_any)
		if typeof(rec_any) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_any
		if bool(rec.get("conflict", false)):
			errors.append("%s: slot id conflict (duplicate providers)" % sid)
			continue
		var assigned := str(rec.get("assigned_agent_id", "")).strip_edges()
		if assigned.is_empty():
			continue
		if not by_id.has(assigned):
			errors.append("%s: assigned agent not found (%s)" % [sid, assigned])
			continue
		var a: Object = by_id[assigned]
		if a.has_method("get_status_info"):
			var info: Dictionary = a.call("get_status_info")
			var st := str(info.get("status_name", "")).strip_edges()
			if st == "ERROR" or st == "COMPLETED":
				errors.append("%s: assigned agent '%s' status=%s" % [sid, assigned, st])
		var def_any: Variant = a.get("definition")
		var def: Object = def_any as Object
		if def:
			var req_any: Variant = rec.get("required_synterfaces")
			var req: Array = req_any if typeof(req_any) == TYPE_ARRAY else []
			var agent_req_any: Variant = def.get("required_synterfaces")
			var agent_req: Array = agent_req_any if typeof(agent_req_any) == TYPE_ARRAY else []
			var have: Dictionary = {}
			for x in agent_req:
				var s := str(x).strip_edges()
				if not s.is_empty():
					have[s] = true
			var missing_syn: Array = []
			for r in req:
				var rs := str(r).strip_edges()
				if rs.is_empty():
					continue
				if not have.has(rs):
					missing_syn.append(rs)
			if not missing_syn.is_empty():
				errors.append("%s: agent '%s' missing required_synterfaces: %s" % [sid, assigned, str(missing_syn)])
			if role_policy and role_policy.has_method("resolve_allowed_tools_for_agent") and all_tools.size() > 0:
				var resolved: Dictionary = role_policy.call("resolve_allowed_tools_for_agent", def, all_tools)
				var allow_all := bool(resolved.get("allow_all", false))
				var tools_arr: Array = resolved.get("tools", [])
				if not allow_all and tools_arr.is_empty():
					warnings.append("%s: agent '%s' role policy allows no tools (may be unable to act)" % [sid, assigned])
	var sig := "e=%d|w=%d" % [errors.size(), warnings.size()]
	var old_sig := str(owner.get("_agent_slots_last_validation_sig"))
	if sig != old_sig:
		owner.set("_agent_slots_last_validation_sig", sig)
		if errors.size() > 0:
			owner.call("_agentdef_set_status", "Slots invalid: %d error(s), %d warning(s)" % [errors.size(), warnings.size()])
	var lines: Array[String] = []
	if errors.is_empty() and warnings.is_empty():
		lines.append("Slots: OK")
	else:
		if errors.size() > 0:
			lines.append("Slots: %d error(s)" % errors.size())
		if warnings.size() > 0:
			lines.append("Slots: %d warning(s)" % warnings.size())
		for e in errors:
			lines.append("ERROR: " + str(e))
		for w in warnings:
			lines.append("WARN: " + str(w))
	status_lbl.text = "\n".join(lines)


static func on_agent_slot_selected(owner: Control, index: int) -> void:
	var list_node: ItemList = owner.get("_agent_slots_list")
	if not list_node or index < 0 or index >= list_node.item_count:
		owner.set("_selected_slot_id", "")
		return
	var md_any: Variant = list_node.get_item_metadata(index)
	if typeof(md_any) != TYPE_DICTIONARY:
		return
	var md: Dictionary = md_any
	var selected_slot_id := str(md.get("slot_id", "")).strip_edges()
	owner.set("_selected_slot_id", selected_slot_id)
	if selected_slot_id.is_empty():
		return
	var picker: OptionButton = owner.get("_agent_slot_picker")
	if not picker:
		return
	var assigned := str(md.get("assigned_agent_id", "")).strip_edges()
	if assigned.is_empty():
		picker.select(0)
		return
	for i in range(picker.item_count):
		if str(picker.get_item_metadata(i)).strip_edges() == assigned:
			picker.select(i)
			return
	picker.select(0)


static func on_agent_slot_assign_pressed(owner: Control) -> void:
	var host: Object = owner.call("_get_router_obj_any")
	if not host or not host.has_method("set_slot_assignment"):
		return
	var selected_slot_id := str(owner.get("_selected_slot_id")).strip_edges()
	var picker: OptionButton = owner.get("_agent_slot_picker")
	if selected_slot_id.is_empty() or not picker:
		return
	var idx := picker.selected
	var aid := str(picker.get_item_metadata(idx)).strip_edges()
	if aid.is_empty():
		host.call("clear_slot_assignment", selected_slot_id)
		owner.call("_agentdef_set_status", "Cleared slot assignment: %s" % selected_slot_id)
	else:
		host.call("set_slot_assignment", selected_slot_id, aid)
		owner.call("_agentdef_set_status", "Assigned %s → %s" % [selected_slot_id, aid])
	owner.set("_agent_slots_signature", "")
	refresh_agent_slots_ui(owner)


static func on_agent_slot_clear_pressed(owner: Control) -> void:
	var host: Object = owner.call("_get_router_obj_any")
	if not host or not host.has_method("clear_slot_assignment"):
		return
	var selected_slot_id := str(owner.get("_selected_slot_id")).strip_edges()
	if selected_slot_id.is_empty():
		return
	host.call("clear_slot_assignment", selected_slot_id)
	owner.call("_agentdef_set_status", "Cleared slot assignment: %s" % selected_slot_id)
	owner.set("_agent_slots_signature", "")
	refresh_agent_slots_ui(owner)


static func on_agent_slots_publish_pressed(owner: Control) -> void:
	var host: Object = owner.call("_get_router_obj_any")
	if not host or not host.has_method("get_slot_assignments") or not host.has_method("get_slot_assignments_path_abs"):
		owner.call("_agentdef_set_status", "Publish failed: MetapunktAppHost router not available.")
		return
	var ep_obj: Object = owner.call("_get_endpoint_obj")
	if not ep_obj:
		owner.call("_agentdef_set_status", "Publish failed: MetapunktEndpointHandler not available.")
		return
	var audit_any: Variant = ep_obj.get("audit_logger")
	var audit: Object = audit_any as Object
	if not audit or not audit.has_method("hub_create_artifact_inline_json_async"):
		owner.call("_agentdef_set_status", "Publish failed: AuditLogger hub forwarding not available.")
		return
	var assignments_any: Variant = host.call("get_slot_assignments")
	var assignments: Dictionary = assignments_any if typeof(assignments_any) == TYPE_DICTIONARY else {}
	var path_abs := str(host.call("get_slot_assignments_path_abs")).strip_edges()
	var payload := {
		"schema_version": "metapunkt.slot_assignments.v1",
		"assignments": assignments,
		"source_path": path_abs,
		"t_utc": Time.get_datetime_string_from_system(true),
	}
	var meta := {"provenance": {"generated_by": "metapunkt.slot_assignments"}}
	owner.call("_agentdef_set_status", "Publishing slot assignments to hub…")
	var res: Dictionary = await audit.hub_create_artifact_inline_json_async("metapunkt.slot_assignments", payload, meta)
	if bool(res.get("ok", false)):
		owner.call("_agentdef_set_status", "Published slot assignments to hub.")
	else:
		owner.call("_agentdef_set_status", "Publish failed: %s" % str(res.get("error", "unknown")))
