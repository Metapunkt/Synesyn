extends RefCounted
class_name SynpunktSyndocActionsUtils

static func on_generate_flowdoc(owner: Control) -> void:
	var active_closure_json_any: Variant = owner.get("_active_closure_json")
	var active_closure_json: Dictionary = active_closure_json_any if typeof(active_closure_json_any) == TYPE_DICTIONARY else {}
	if active_closure_json.is_empty():
		owner.call("_set_status", "Load a closure first.")
		return
	var flowdoc_title: LineEdit = owner.get("_flowdoc_title")
	var title := flowdoc_title.text.strip_edges() if flowdoc_title else ""
	var active_closure_id := str(owner.get("_active_closure_id")).strip_edges()
	if title.is_empty():
		title = "SynDoc from closure %s" % active_closure_id.left(8)
		if flowdoc_title:
			flowdoc_title.text = title
	var flowdoc: Dictionary = owner.call("_generate_flowdoc_from_closure", active_closure_id, active_closure_json, title)
	owner.call("_apply_refs_fields_to_flowdoc", flowdoc)
	owner.set("_flowdoc_model", flowdoc)
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	if flowdoc_json:
		flowdoc_json.text = JSON.stringify(flowdoc, "\t")
	owner.call("_sync_from_raw_json")
	owner.call("_set_status", "Generated SynDoc (editable).")


static func save_flowdoc(owner: Control, as_new_version: bool = false) -> void:
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	var raw := flowdoc_json.text.strip_edges() if flowdoc_json else ""
	if raw.is_empty():
		owner.call("_set_status", "No SynDoc JSON to save.")
		return
	var parsed_any: Variant = JSON.parse_string(raw)
	if typeof(parsed_any) != TYPE_DICTIONARY:
		owner.call("_set_status", "SynDoc JSON is not a dictionary.")
		return
	var flowdoc: Dictionary = parsed_any
	owner.call("_apply_refs_fields_to_flowdoc", flowdoc)
	var validation: Dictionary = owner.call("_validate_flowdoc", flowdoc)
	if not bool(validation.get("ok", false)):
		owner.call("_set_status_err", "SynDoc invalid: %s" % str(validation.get("error", "unknown")))
		return
	var active_closure_id := str(owner.get("_active_closure_id")).strip_edges()
	var active_flowdoc_id := str(owner.get("_active_flowdoc_id")).strip_edges()
	var meta := {
		"provenance": {
			"generated_by": "synpunkt.v0",
			"source_artifacts": ([] if active_closure_id.is_empty() else [active_closure_id]),
		}
	}
	if as_new_version and not active_flowdoc_id.is_empty():
		meta["provenance"]["previous_version"] = active_flowdoc_id
	var hub: Object = owner.get("_hub")
	var artifact_syndoc := str(owner.get("ARTIFACT_SYNDOC"))
	var res: Dictionary = await hub.call("create_artifact_inline_json", artifact_syndoc, flowdoc, meta)
	if not bool(res.get("ok", false)):
		owner.call("_set_status_err", "Save failed: %s" % str(res.get("error", res)))
		return
	var new_id := str(res.get("id", "")).strip_edges()
	var new_uri := str(res.get("uri", "")).strip_edges()
	owner.set("_active_flowdoc_id", new_id)
	owner.set("_active_flowdoc_uri", new_uri)
	if flowdoc_json:
		flowdoc_json.text = JSON.stringify(flowdoc, "\t")
	owner.call("_set_status_ok", "Saved SynDoc to hub: %s" % (new_id.left(12) if not new_id.is_empty() else "ok"))
	await owner.call("_refresh_flowdocs")
	tree_select_by_id(owner.get("_flowdocs_list"), new_id)


static func tree_select_by_id(tree_node: Tree, artifact_id: String) -> void:
	if not tree_node:
		return
	var target := String(artifact_id).strip_edges()
	if target.is_empty():
		return
	var root := tree_node.get_root()
	if root == null:
		return
	var item := root.get_first_child()
	while item != null:
		var aid := str(item.get_metadata(1)).strip_edges()
		if aid == target:
			tree_node.set_selected(item, 1)
			return
		item = item.get_next()


static func on_validate_flowdoc(owner: Control) -> void:
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	var raw := flowdoc_json.text.strip_edges() if flowdoc_json else ""
	if raw.is_empty():
		owner.call("_set_status", "No SynDoc JSON to validate.")
		return
	var parsed_any: Variant = JSON.parse_string(raw)
	if typeof(parsed_any) != TYPE_DICTIONARY:
		owner.call("_set_status", "SynDoc JSON is not a dictionary.")
		return
	owner.call("_apply_refs_fields_to_flowdoc", parsed_any)
	var res: Dictionary = owner.call("_validate_flowdoc", parsed_any)
	if bool(res.get("ok", false)):
		owner.call("_set_status_ok", "SynDoc valid.")
	else:
		owner.call("_set_status_err", "SynDoc invalid: %s" % str(res.get("error", "unknown")))


static func generate_flowdoc_from_closure(owner: Control, closure_id: String, closure: Dictionary, title: String) -> Dictionary:
	var now := Time.get_datetime_string_from_system(false, true)
	var name := str(closure.get("name", "")).strip_edges()
	var intent := str(closure.get("intent", "")).strip_edges()
	var pattern_ids: Array = closure.get("pattern_ids", [])
	var context_graph_artifact_id := str(owner.call("_get_closure_context_graph_artifact_id", closure))
	var prompt_chain_asset_id := str(owner.call("_get_closure_prompt_chain_asset_id", closure))
	var projection_artifact_id := str(owner.call("_get_closure_projection_artifact_id", closure))
	var cluster_artifact_id := str(owner.call("_get_closure_cluster_artifact_id", closure))
	var overview_blocks: Array = []
	overview_blocks.append({"type": "h1", "text": "Overview"})
	if not name.is_empty():
		overview_blocks.append({"type": "p", "text": "Name: %s" % name})
	if not intent.is_empty():
		overview_blocks.append({"type": "p", "text": "Intent: %s" % intent})
	overview_blocks.append({"type": "p", "text": "Source closure: %s" % closure_id.left(12)})
	if not context_graph_artifact_id.is_empty():
		overview_blocks.append({"type": "p", "text": "Context graph: %s" % context_graph_artifact_id.left(12)})
	if not projection_artifact_id.is_empty():
		overview_blocks.append({"type": "p", "text": "Projection: %s" % projection_artifact_id.left(12)})
	if not cluster_artifact_id.is_empty():
		overview_blocks.append({"type": "p", "text": "Cluster result: %s" % cluster_artifact_id.left(12)})
	var patterns_blocks: Array = []
	patterns_blocks.append({"type": "h1", "text": "Patterns"})
	if pattern_ids.size() == 0:
		patterns_blocks.append({"type": "p", "text": "(none)"})
	else:
		patterns_blocks.append({"type": "p", "text": "Pattern ids referenced by this closure:"})
		for pid_any in pattern_ids:
			patterns_blocks.append({"type": "li", "text": str(pid_any)})
	var next_blocks: Array = []
	next_blocks.append({"type": "h1", "text": "Next"})
	next_blocks.append({"type": "p", "text": "Add a new frame, move blocks between frames, and arrange frames in the edgeless layout."})
	return {
		"schema": "ui.syndoc",
		"schema_version": "0.1.0",
		"title": title,
		"created_at": now,
		"refs": {
			"closure_artifact_id": closure_id,
			"context_graph_artifact_id": context_graph_artifact_id,
			"prompt_chain_asset_id": prompt_chain_asset_id,
			"projection_artifact_id": projection_artifact_id,
			"cluster_artifact_id": cluster_artifact_id,
		},
		"source": {"closure_artifact_id": closure_id},
		"frames": [
			{
				"id": "overview",
				"kind": "document",
				"transform": {"x": 0, "y": 0, "w": 960, "h": 540},
				"blocks": overview_blocks,
			},
			{
				"id": "patterns",
				"kind": "document",
				"transform": {"x": 0, "y": 0, "w": 960, "h": 540},
				"blocks": patterns_blocks,
			},
			{
				"id": "next",
				"kind": "document",
				"transform": {"x": 0, "y": 0, "w": 960, "h": 540},
				"blocks": next_blocks,
			}
		],
	}


static func on_new_empty_flowdoc(owner: Control) -> void:
	var title := ""
	var flowdoc_title: LineEdit = owner.get("_flowdoc_title")
	if flowdoc_title:
		title = flowdoc_title.text.strip_edges()
	if title.is_empty():
		title = "Untitled SynDoc"
	var flowdoc := generate_empty_flowdoc(title)
	owner.set("_flowdoc_model", flowdoc)
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	if flowdoc_json:
		flowdoc_json.text = JSON.stringify(flowdoc, "\t")
	owner.call("_sync_from_raw_json")
	owner.set("_active_flowdoc_id", "")
	owner.set("_active_flowdoc_uri", "")
	owner.call("_set_status", "New SynDoc created. Saving…")
	await owner.call("_save_flowdoc", false)


static func generate_empty_flowdoc(title: String) -> Dictionary:
	var now := Time.get_datetime_string_from_system(false, true)
	return {
		"schema": "ui.syndoc",
		"schema_version": "0.2.0",
		"title": title,
		"created_at": now,
		"refs": {},
		"frames": [
			{
				"id": "frame_1",
				"kind": "document",
				"transform": {"x": 0, "y": 0, "w": 960, "h": 540},
				"blocks": [
					{"type": "h1", "text": title},
				],
			}
		],
	}


static func on_create_demo_closure(owner: Control) -> void:
	var now := Time.get_datetime_string_from_system(false, true)
	var demo := {
		"schema_version": 1,
		"kind": "ui.closure",
		"name": "Demo closure (%s)" % now,
		"intent": "A minimal demo closure created by SynPunkt for testing.",
		"pattern_ids": [],
		"created_at": now,
		"refs": {},
	}
	var meta := {"provenance": {"generated_by": "synpunkt.demo_closure", "session_id": owner.get("_session_id")}}
	var hub: Node = owner.get("_hub")
	var artifact_closure := str(owner.get("ARTIFACT_CLOSURE"))
	var res: Dictionary = await hub.create_artifact_inline_json(artifact_closure, demo, meta)
	if bool(res.get("ok", false)):
		owner.call("_set_status", "Demo closure created: %s" % str(res.get("id", "")))
		await owner.call("_refresh_closures")
	else:
		owner.call("_set_status", "Create demo closure failed: %s" % str(res.get("error", res)))
