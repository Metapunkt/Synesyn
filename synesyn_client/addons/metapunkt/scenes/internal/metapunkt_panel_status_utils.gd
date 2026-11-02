extends RefCounted
class_name MetapunktPanelStatusUtils

static func _coerce_int(v: Variant, default_value: int) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return floori(v)
		TYPE_STRING:
			var s := str(v).strip_edges()
			return s.to_int() if not s.is_empty() else default_value
		_:
			return default_value


static func get_endpoint_obj(endpoint: Node) -> Object:
	return endpoint as Object


static func get_hub_events_obj(ep_obj: Object) -> Object:
	if not ep_obj:
		return null
	var hub_any: Variant = ep_obj.get("hub_events_client")
	return hub_any as Object


static func get_audit_logger_obj(ep_obj: Object) -> Object:
	if not ep_obj:
		return null
	var a_any: Variant = ep_obj.get("audit_logger")
	return a_any as Object


static func hub_preset_event_types(idx: int) -> Array[String]:
	match idx:
		0:
			return ["sensor.warning", "job.progress", "job.completed", "job.failed"]
		1:
			return ["job.progress", "job.completed", "job.failed"]
		2:
			return ["tool.call", "tool.result", "tool.error", "tool.denied"]
		3:
			return []
		_:
			return ["sensor.warning", "job.progress", "job.completed", "job.failed"]


static func get_agent_registry(ep_obj: Object) -> Object:
	if not ep_obj:
		return null
	var ar_any: Variant = ep_obj.get("agent_registry")
	return ar_any as Object


static func update_agent_list_into(endpoint: Node, ob: OptionButton, include_none: bool) -> void:
	if not endpoint or not ob:
		return
	var ep_obj: Object = endpoint as Object
	if not ep_obj:
		return
	var ar := get_agent_registry(ep_obj)
	var prev_selected_id := ""
	if ob.item_count > 0:
		prev_selected_id = str(ob.get_item_metadata(ob.selected)).strip_edges()
	ob.clear()
	if include_none:
		ob.add_item("(no agent)")
		ob.set_item_metadata(0, "")
	if not ar or not ar.has_method("get_all_agent_instances"):
		var idx := ob.item_count
		ob.add_item("(agent registry unavailable)")
		ob.set_item_metadata(idx, "")
		ob.select(0)
		return
	var agents_any: Variant = ar.call("get_all_agent_instances")
	if typeof(agents_any) != TYPE_ARRAY:
		ob.add_item("(unexpected agent list)")
		ob.select(0)
		return
	var agents: Array = agents_any
	for a_any in agents:
		var a: Object = a_any as Object
		if not a:
			continue
		var aid := str(a.get("agent_id")).strip_edges()
		if aid.is_empty():
			continue
		var status_name := ""
		if a.has_method("get_status_info"):
			var info: Dictionary = a.call("get_status_info")
			status_name = str(info.get("status_name", "")).strip_edges()
		var label := aid
		if not status_name.is_empty():
			label += " [%s]" % status_name
		var i := ob.item_count
		ob.add_item(label)
		ob.set_item_metadata(i, aid)
	if ob.item_count == 0:
		ob.add_item("(no agents)")
		ob.set_item_metadata(0, "")
		ob.select(0)
		return
	if not prev_selected_id.is_empty():
		for i in range(ob.item_count):
			if str(ob.get_item_metadata(i)).strip_edges() == prev_selected_id:
				ob.select(i)
				return
	ob.select(0)


static func refresh_controls_strip(endpoint: Node, slop_bound: Label, hub_state: Label, hub_url: LineEdit) -> void:
	if not endpoint:
		return
	var ep_obj: Object = endpoint as Object
	if not ep_obj:
		return
	if slop_bound:
		var server_any: Variant = ep_obj.get("server")
		var listening := false
		if server_any and typeof(server_any) == TYPE_OBJECT and (server_any as Object).has_method("is_listening"):
			listening = bool((server_any as Object).call("is_listening"))
		var host := str(ep_obj.get("listen_host")).strip_edges()
		var port := _coerce_int(ep_obj.get("listen_port"), 8080)
		if host.is_empty():
			host = "127.0.0.1"
		slop_bound.text = ("SLOP active at %s:%d" % [host, port]) if listening else ("SLOP offline — port %d unavailable?" % port)
		slop_bound.tooltip_text = "SLOP (Simple Language-to-Object Protocol) server. Agents communicate with Metapunkt through this local endpoint." if listening else "Server could not bind to the requested port. Try a different port number below."
	if hub_state:
		var hub_any: Variant = ep_obj.get("hub_events_client")
		if hub_any and typeof(hub_any) == TYPE_OBJECT and (hub_any as Object).has_method("is_hub_connected"):
			var is_conn := bool((hub_any as Object).call("is_hub_connected"))
			hub_state.text = ("Hub: online" if is_conn else "Hub: offline")
			hub_state.tooltip_text = "Connected to the Synesyn Hub for event streaming and artifact publishing." if is_conn else "Not connected to Hub. Embeddings, voice, and artifact publishing won't be available."
		else:
			hub_state.text = "Hub: not configured"
			hub_state.tooltip_text = "Hub events client not initialised. Enter a Hub URL and click Connect."
	if hub_url:
		var audit_any: Variant = ep_obj.get("audit_logger")
		if audit_any and typeof(audit_any) == TYPE_OBJECT:
			var base := str((audit_any as Object).get("hub_base_url")).strip_edges()
			if not base.is_empty() and hub_url.text.strip_edges().is_empty():
				hub_url.text = base


static func refresh_components(endpoint: Node, components: ItemList) -> void:
	if not components:
		return
	components.clear()
	if not endpoint:
		components.add_item("EndpointHandler: (missing)")
		return
	var ep_obj: Object = endpoint as Object
	if not ep_obj:
		components.add_item("EndpointHandler: (wrong type)")
		return
	var server_any: Variant = ep_obj.get("server")
	var listening := false
	var host := str(ep_obj.get("listen_host")).strip_edges()
	if host.is_empty():
		host = "127.0.0.1"
	var port := _coerce_int(ep_obj.get("listen_port"), 8080)
	if port <= 0:
		port = 8080
	if server_any and typeof(server_any) == TYPE_OBJECT and (server_any as Object).has_method("is_listening"):
		listening = bool((server_any as Object).call("is_listening"))
	components.add_item("SLOP server: %s %s:%d" % ["LISTENING" if listening else "NOT LISTENING", host, port])
	var agent_registry: Variant = ep_obj.get("agent_registry")
	var tool_registry: Variant = ep_obj.get("tool_registry")
	var task_queue: Variant = ep_obj.get("task_queue")
	var hub_events: Variant = ep_obj.get("hub_events_client")
	var agents := 0
	if agent_registry and typeof(agent_registry) == TYPE_OBJECT and (agent_registry as Object).has_method("get_all_agent_instances"):
		agents = ((agent_registry as Object).call("get_all_agent_instances") as Array).size()
	components.add_item("Agents: %d" % agents)
	var tools := 0
	if tool_registry and typeof(tool_registry) == TYPE_OBJECT and (tool_registry as Object).has_method("get_tools"):
		tools = ((tool_registry as Object).call("get_tools") as Array).size()
	components.add_item("Tools: %d" % tools)
	var pending := 0
	var active := 0
	var completed := 0
	if task_queue:
		var p_any: Variant = (task_queue as Object).get("_pending_tasks") if typeof(task_queue) == TYPE_OBJECT else null
		var a_any: Variant = (task_queue as Object).get("_active_tasks") if typeof(task_queue) == TYPE_OBJECT else null
		var c_any: Variant = (task_queue as Object).get("_completed_tasks") if typeof(task_queue) == TYPE_OBJECT else null
		if typeof(p_any) == TYPE_ARRAY:
			pending = (p_any as Array).size()
		if typeof(a_any) == TYPE_DICTIONARY:
			active = (a_any as Dictionary).size()
		if typeof(c_any) == TYPE_DICTIONARY:
			completed = (c_any as Dictionary).size()
	components.add_item("Tasks: pending=%d active=%d completed=%d" % [pending, active, completed])
	if hub_events and typeof(hub_events) == TYPE_OBJECT and (hub_events as Object).has_method("is_hub_connected"):
		components.add_item("Hub events: connected=%s" % str((hub_events as Object).call("is_hub_connected")))
	else:
		components.add_item("Hub events: (status unavailable)")


static func refresh_tasks(endpoint: Node, tasks: ItemList) -> void:
	if not tasks:
		return
	tasks.clear()
	if not endpoint:
		tasks.add_item("(no EndpointHandler)")
		return
	var ep_obj: Object = endpoint as Object
	if not ep_obj:
		tasks.add_item("(EndpointHandler wrong type)")
		return
	var task_queue: Variant = ep_obj.get("task_queue")
	if not task_queue:
		tasks.add_item("(task queue not initialized)")
		return
	var p_any: Variant = (task_queue as Object).get("_pending_tasks") if typeof(task_queue) == TYPE_OBJECT else null
	var a_any: Variant = (task_queue as Object).get("_active_tasks") if typeof(task_queue) == TYPE_OBJECT else null
	if typeof(p_any) == TYPE_ARRAY:
		for t_any in (p_any as Array):
			if typeof(t_any) == TYPE_OBJECT and (t_any as Object).has_method("get_status_dict"):
				var d: Dictionary = (t_any as Object).call("get_status_dict")
				tasks.add_item("[pending] %s" % str(d.get("task_id", "")))
	if typeof(a_any) == TYPE_DICTIONARY:
		for k in (a_any as Dictionary).keys():
			tasks.add_item("[active] %s" % str(k))
	if tasks.item_count == 0:
		tasks.add_item("(no tasks yet)")


static func refresh_resources(endpoint: Node, resources: ItemList) -> void:
	if not resources:
		return
	resources.clear()
	if not endpoint:
		resources.add_item("(no EndpointHandler)")
		return
	var ep_obj: Object = endpoint as Object
	if not ep_obj:
		resources.add_item("(EndpointHandler wrong type)")
		return
	var agent_registry: Variant = ep_obj.get("agent_registry")
	if not agent_registry or not (agent_registry as Object).has_method("get_all_agent_instances"):
		resources.add_item("(agent registry not initialized)")
		return
	var agents: Array = (agent_registry as Object).call("get_all_agent_instances")
	for a_any in agents:
		if typeof(a_any) != TYPE_OBJECT:
			continue
		var a: Object = a_any as Object
		var aid := str(a.get("agent_id")).strip_edges()
		var st := ""
		if a.has_method("get_status_info"):
			var info: Dictionary = a.call("get_status_info")
			st = str(info.get("status", "")).strip_edges()
		resources.add_item("%s %s" % [aid, ("(%s)" % st if not st.is_empty() else "")])
	if resources.item_count == 0:
		resources.add_item("(no agents spawned yet)")


static func refresh_patterns(patterns: ItemList) -> void:
	if not patterns:
		return
	patterns.clear()
	patterns.add_item("(patterns not surfaced yet)")


static func refresh_status(endpoint: Node, status_text: TextEdit) -> void:
	if not status_text:
		return
	var lines: Array[String] = []
	lines.append("=== Metapunkt status ===")
	lines.append("")
	if not endpoint:
		lines.append("[!] EndpointHandler node is missing.")
		lines.append("    Add MetapunktEndpointHandler as a child of this panel.")
		status_text.text = "\n".join(lines)
		return
	var ep_obj: Object = endpoint as Object
	if not ep_obj:
		lines.append("[!] EndpointHandler is the wrong type.")
		status_text.text = "\n".join(lines)
		return
	var server_any: Variant = ep_obj.get("server")
	var listening := false
	if server_any and typeof(server_any) == TYPE_OBJECT and (server_any as Object).has_method("is_listening"):
		listening = bool((server_any as Object).call("is_listening"))
	var host2 := str(ep_obj.get("listen_host")).strip_edges()
	if host2.is_empty():
		host2 = "127.0.0.1"
	var port2 := _coerce_int(ep_obj.get("listen_port"), 8080)
	if port2 <= 0:
		port2 = 8080
	if listening:
		lines.append("[OK] SLOP server active at %s:%d" % [host2, port2])
		lines.append("     Agents can send requests to this local endpoint.")
	else:
		lines.append("[!!] SLOP server offline (tried %s:%d)" % [host2, port2])
		var le := _coerce_int(ep_obj.get("last_listen_error"), 0)
		var lem := str(ep_obj.get("last_listen_error_message")).strip_edges()
		if le != 0 or not lem.is_empty():
			lines.append("     Error: %s (%s)" % [str(le), (lem if not lem.is_empty() else "unknown")])
		lines.append("     Try a different port, or check that nothing else is using port %d." % port2)
	var audit_logger: Variant = ep_obj.get("audit_logger")
	if audit_logger and typeof(audit_logger) == TYPE_OBJECT:
		var hub_url := str((audit_logger as Object).get("hub_base_url")).strip_edges()
		if not hub_url.is_empty():
			lines.append("[  ] Hub URL: %s" % hub_url)
		else:
			lines.append("[  ] Hub URL: not set (voice, embeddings, and artifact publishing require Hub)")
	lines.append("")
	lines.append("Note: the Agents / Tasks lists are empty until you spawn an agent")
	lines.append("(use the Agents tab, or spawn via the /agents SLOP endpoint).")
	status_text.text = "\n".join(lines)
