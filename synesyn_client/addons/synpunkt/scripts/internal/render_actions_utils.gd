extends RefCounted
class_name SynpunktRenderActionsUtils

static func on_render_details_copy_all_links(owner: Control) -> void:
	var ctx: Dictionary = owner.call("_current_render_artifact_context")
	if ctx.is_empty():
		owner.call("_set_status", "Render details: select one artifact first.")
		return
	var refs_any: Variant = ctx.get("refs", {})
	var refs: Dictionary = refs_any if typeof(refs_any) == TYPE_DICTIONARY else {}
	var prov_any: Variant = ctx.get("provenance", {})
	var prov: Dictionary = prov_any if typeof(prov_any) == TYPE_DICTIONARY else {}
	var aid := str(ctx.get("artifact_id", "")).strip_edges()
	var lines: Array[String] = []
	lines.append("artifact_id=%s" % aid)
	lines.append("render_request_artifact_id=%s" % str(refs.get("render_request_artifact_id", "")).strip_edges())
	lines.append("workflow_artifact_id=%s" % str(refs.get("workflow_artifact_id", "")).strip_edges())
	lines.append("prompt_artifact_id=%s" % str(refs.get("prompt_artifact_id", "")).strip_edges())
	lines.append("route=%s/%s" % [str(prov.get("route_mode", "direct")).strip_edges(), str(prov.get("route_provider", "comfyui")).strip_edges()])
	lines.append("seed_info=%s" % str(prov.get("seed_info", {})))
	DisplayServer.clipboard_set("\n".join(lines))
	owner.call("_set_status", "Render details: copied link ids for %s." % aid.left(12))


static func delete_selected_render_image_artifacts(owner: Control) -> void:
	owner.call("_ensure_render_results_bound")
	var hub: Object = owner.get("_hub")
	if not hub:
		owner.call("_set_status", "Render: hub client not initialized.")
		return
	var aids: Array = owner.call("_get_selected_render_artifact_ids")
	if aids.is_empty():
		owner.call("_set_status", "Render: select one or more artifacts in Render results first.")
		return
	var ok_count := 0
	var fail_count := 0
	for aid in aids:
		var del_res: Dictionary = await hub.call("delete_artifact", aid, true)
		if bool(del_res.get("ok", false)):
			ok_count += 1
		else:
			fail_count += 1
	await owner.call("_refresh_render_results_from_hub")
	owner.call("_set_status", "Render: deleted %d artifact(s), failed %d." % [ok_count, fail_count])


static func insert_selected_render_artifacts_into_current_frame(owner: Control) -> void:
	var frames: Array = owner.call("_get_frames")
	if frames.is_empty():
		owner.call("_set_status", "Insert to frame: load or create a SynDoc first.")
		return
	var aids: Array = owner.call("_get_selected_render_artifact_ids")
	if aids.is_empty():
		owner.call("_set_status", "Insert to frame: select one or more render artifacts first.")
		return
	var blocks: Array = owner.call("_get_blocks")
	for aid in aids:
		blocks.append({"type": "image", "artifact_id": aid})
	owner.call("_set_blocks", blocks)
	owner.call("_write_model_to_raw_json")
	owner.call("_refresh_blocks_ui")
	owner.call("_refresh_performer_ui")
	owner.call("_refresh_present_edgeless")
	owner.call("_set_status", "Inserted %d render artifact(s) into frame %s." % [aids.size(), str(owner.call("_get_active_frame_id"))])


static func on_hub_event_received(owner: Control, evt: Dictionary) -> void:
	var et := str(evt.get("event_type", "")).strip_edges()
	if et.begins_with("render."):
		var payload_any: Variant = evt.get("payload", {})
		var payload: Dictionary = payload_any if typeof(payload_any) == TYPE_DICTIONARY else {}
		var job_id := str(payload.get("job_id", "")).strip_edges()
		var prompt_id := str(payload.get("prompt_id", "")).strip_edges()
		if et == "render.completed":
			owner.call("_set_status", "Render event: completed job=%s prompt=%s" % [job_id.left(12), prompt_id.left(12)])
			owner.call_deferred("_refresh_render_results_from_hub", 200, "event")
		elif et == "render.failed":
			owner.call("_set_status", "Render event: failed job=%s (%s)" % [job_id.left(12), str(payload.get("error", "unknown"))])
		elif et == "render.started":
			owner.call("_set_status", "Render event: started job=%s" % job_id.left(12))
		elif et == "render.queued":
			owner.call("_set_status", "Render event: queued job=%s" % job_id.left(12))
	var sensor_enabled := bool(owner.get("_sensor_enabled"))
	if not sensor_enabled:
		return
	if not et.begins_with("sensor."):
		return
	var source_id := str(evt.get("source_id", "")).strip_edges()
	if source_id.is_empty():
		source_id = "unknown"
	var latest_by_source_any: Variant = owner.get("_sensor_latest_by_source")
	var latest_by_source: Dictionary = latest_by_source_any if typeof(latest_by_source_any) == TYPE_DICTIONARY else {}
	latest_by_source[source_id] = evt
	owner.set("_sensor_latest_by_source", latest_by_source)
	var sensor_recent_any: Variant = owner.get("_sensor_recent")
	var sensor_recent: Array = sensor_recent_any if typeof(sensor_recent_any) == TYPE_ARRAY else []
	sensor_recent.append(evt)
	if sensor_recent.size() > 50:
		sensor_recent.pop_front()
	owner.set("_sensor_recent", sensor_recent)
	var sensor_events: ItemList = owner.get("_sensor_events")
	if sensor_events:
		sensor_events.clear()
		for sid in latest_by_source.keys():
			var e: Dictionary = latest_by_source[sid]
			var payload_any: Variant = e.get("payload", {})
			var p: Dictionary = payload_any if typeof(payload_any) == TYPE_DICTIONARY else {}
			sensor_events.add_item("%s: %s" % [str(sid), str(p)])
	owner.call("_update_sensor_overlay_nodes")


static func update_sensor_overlay_nodes(owner: Control) -> void:
	var latest_by_source_any: Variant = owner.get("_sensor_latest_by_source")
	var latest_by_source: Dictionary = latest_by_source_any if typeof(latest_by_source_any) == TYPE_DICTIONARY else {}
	var nodes: Array = []
	var i := 0
	for sid in latest_by_source.keys():
		var evt: Dictionary = latest_by_source[sid]
		var payload_any: Variant = evt.get("payload", {})
		var p: Dictionary = payload_any if typeof(payload_any) == TYPE_DICTIONARY else {}
		nodes.append(
			{
				"id": "sensor:%s" % str(sid),
				"pos": [float(i) * 120.0, -120.0],
				"label": "%s\n%s" % [str(sid), str(p)],
				"ref": {"kind": "sensor_overlay", "source_id": str(sid)},
			}
		)
		i += 1
	var edgeless_preview: Object = owner.get("_edgeless_preview")
	if edgeless_preview and edgeless_preview.has_method("set_overlay_nodes"):
		edgeless_preview.call("set_overlay_nodes", nodes)
	var present_edgeless_preview: Object = owner.get("_present_edgeless_preview")
	if present_edgeless_preview and present_edgeless_preview.has_method("set_overlay_nodes"):
		present_edgeless_preview.call("set_overlay_nodes", nodes)


static func snapshot_sensors_to_hub(owner: Control) -> void:
	var latest_by_source_any: Variant = owner.get("_sensor_latest_by_source")
	var latest_by_source: Dictionary = latest_by_source_any if typeof(latest_by_source_any) == TYPE_DICTIONARY else {}
	if latest_by_source.is_empty():
		owner.call("_set_status", "No sensor data to snapshot yet.")
		return
	var sensor_recent_any: Variant = owner.get("_sensor_recent")
	var sensor_recent: Array = sensor_recent_any if typeof(sensor_recent_any) == TYPE_ARRAY else []
	var snap := {
		"schema_version": 1,
		"kind": "sensor.snapshot",
		"latest_by_source": latest_by_source,
		"recent": sensor_recent,
		"created_at": Time.get_unix_time_from_system(),
	}
	var meta := {"provenance": {"generated_by": "synpunkt.sensor_snapshot"}}
	var hub: Object = owner.get("_hub")
	if not hub:
		owner.call("_set_status", "Snapshot failed: hub unavailable.")
		return
	var res: Dictionary = await hub.call("create_artifact_inline_json", "json.sensor_snapshot", snap, meta)
	if bool(res.get("ok", false)):
		owner.set("_last_sensor_snapshot_artifact_id", str(res.get("id", "")).strip_edges())
		owner.call("_set_status", "Snapshot saved: %s" % str(owner.get("_last_sensor_snapshot_artifact_id")))
	else:
		owner.call("_set_status", "Snapshot failed: %s" % str(res.get("error", res)))
