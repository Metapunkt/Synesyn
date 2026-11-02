extends RefCounted
## Dream Inbox + Closure commitment logic for SynAxes.
##
## Builds candidate closures from discovered patterns, handles accept/defer/reject
## decisions, and commits finalized closures to the hub substrate.

signal closure_status(msg: String)
signal closure_committed(closure_artifact_id: String)
signal candidate_editing(idx: int)
## Host shell wires this (e.g. Tools TabContainer). Addon must not reach host tree.
signal navigate_requested(target: String)

## The Closure Map vocabulary is defined once, in synesyn_core, and read by every
## surface that orients anything on it — here and in the ScenSyn Workshop Catalyst
## Closure Audit. This file previously carried its own transcription of the quadrant
## names, labels, map version and legend; a revision upstream reached one copy and not
## the others, so the same quadrant was described two different ways depending on which
## panel you opened. Nothing about the map may be restated here (ADR 0020, ADR 0017).
const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)

## OptionButton index 0 is untagged; 1..4 follow `ClosureOrientation.QUADRANTS` order,
## so the rows and this mapping cannot disagree.
const UNTAGGED_OPTION_IDX: int = 0
const NAV_TARGET_SYNPUNKT_CLOSURES := "synpunkt_closures"

var hub  # HubSubstrateClient
var seq_fn: Callable  # () -> int

# State
var dream_candidates: Array = []
var active_candidate_idx: int = -1
var _original_name: String = ""  # Track original values to detect unsaved edits
var _original_intent: String = ""
var _original_orientation_idx: int = 0
var _has_unsaved_edits: bool = false
var store_index_datasets: Dictionary = {}

# UI nodes (set via bind_ui)
var dream_inbox_list: ItemList
var saved_closures_list: ItemList
var work_on_this_button: Button
var defer_button: Button
var reject_button: Button
var closure_name_edit: LineEdit
var closure_intent_edit: LineEdit
var orientation_option: OptionButton
var coverage_label: Label
var time_start_edit: LineEdit
var time_end_edit: LineEdit
var selected_label: Label
var commit_button: Button
var closure_status_label: Label
var candidate_items_list: ItemList
var remove_item_button: Button
var commit_another_button: Button
var open_synpunkt_button: Button
var post_commit_actions: Control

func bind_ui(refs: Dictionary) -> void:
	dream_inbox_list = refs.get("dream_inbox_list") as ItemList
	saved_closures_list = refs.get("saved_closures_list") as ItemList
	work_on_this_button = refs.get("work_on_this_button") as Button
	defer_button = refs.get("defer_button") as Button
	reject_button = refs.get("reject_button") as Button
	closure_name_edit = refs.get("closure_name_edit") as LineEdit
	if work_on_this_button and not work_on_this_button.pressed.is_connected(work_on_this):
		work_on_this_button.pressed.connect(work_on_this)
	closure_intent_edit = refs.get("closure_intent_edit") as LineEdit
	orientation_option = refs.get("orientation_option") as OptionButton
	coverage_label = refs.get("coverage_label") as Label
	time_start_edit = refs.get("time_start_edit") as LineEdit
	time_end_edit = refs.get("time_end_edit") as LineEdit
	selected_label = refs.get("selected_label") as Label
	commit_button = refs.get("commit_button") as Button
	closure_status_label = refs.get("closure_status_label") as Label
	commit_another_button = refs.get("commit_another_button") as Button
	open_synpunkt_button = refs.get("open_synpunkt_button") as Button
	post_commit_actions = refs.get("post_commit_actions") as Control
	if closure_name_edit:
		closure_name_edit.text_changed.connect(func(_t: String): _mark_edited())
	if closure_intent_edit:
		closure_intent_edit.text_changed.connect(func(_t: String): _mark_edited())
	if orientation_option:
		_apply_orientation_option_labels()
		orientation_option.item_selected.connect(_on_orientation_selected)
	if coverage_label:
		coverage_label.tooltip_text = (
			"Closure Map coverage across Saved Closures. "
			+ ClosureOrientationScript.get_axes_legend()
			+ ". Untagged means no orientation was set at commit."
		)
	if commit_another_button and not commit_another_button.pressed.is_connected(prepare_commit_another):
		commit_another_button.pressed.connect(prepare_commit_another)
	if open_synpunkt_button and not open_synpunkt_button.pressed.is_connected(request_open_synpunkt_closures):
		open_synpunkt_button.pressed.connect(request_open_synpunkt_closures)
	_set_post_commit_actions_visible(false)
	candidate_items_list = refs.get("candidate_items_list") as ItemList
	remove_item_button = refs.get("remove_item_button") as Button
	if remove_item_button:
		remove_item_button.pressed.connect(_on_remove_item_pressed)
	available_items_list = refs.get("available_items_list") as ItemList
	add_item_button = refs.get("add_item_button") as Button
	if add_item_button:
		add_item_button.pressed.connect(_on_add_item_pressed)

func _mark_edited() -> void:
	## Called when name, intent, or orientation fields change.
	var cur_name := closure_name_edit.text if closure_name_edit else ""
	var cur_intent := closure_intent_edit.text if closure_intent_edit else ""
	var cur_orient_idx: int = orientation_option.selected if orientation_option else 0
	_has_unsaved_edits = (
		cur_name != _original_name
		or cur_intent != _original_intent
		or cur_orient_idx != _original_orientation_idx
	)

# ── Dream Inbox ───────────────────────────────────────────────────────────

func build_dream_inbox_from_patterns(patterns: Array) -> void:
	dream_candidates.clear()
	if dream_inbox_list:
		dream_inbox_list.clear()

	for p_any in patterns:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_any
		var ptype := str(p.get("type", "pattern")).to_lower()
		if ptype != "cluster":
			continue
		var pid := int(p.get("id", -1))
		if pid < 0:
			continue
		var conf := float(p.get("confidence", 0.5))
		var items: Array = p.get("items", [])
		var item_count := items.size()

		# Build a short content preview from the first few items
		var preview_parts: Array[String] = []
		for it_any in items:
			if preview_parts.size() >= 3:
				break
			if typeof(it_any) == TYPE_DICTIONARY:
				var content := str((it_any as Dictionary).get("content", ""))
				if content.length() > 40:
					content = content.left(37) + "..."
				if not content.is_empty():
					preview_parts.append(content)

		var preview_str := ", ".join(preview_parts) if not preview_parts.is_empty() else "(no content preview)"
		var cand_name := "Cluster #%d (%d items)" % [pid, item_count]
		var intent := "Grouped %d items by similarity (confidence %.0f%%). Samples: %s" % [item_count, conf * 100.0, preview_str]

		var item_ids: Array[String] = []
		for it_any in items:
			if typeof(it_any) == TYPE_DICTIONARY:
				item_ids.append(str((it_any as Dictionary).get("id", "")))

		var related_pattern_ids: Array[int] = []
		var rels: Array = p.get("relations", [])
		for r_any in rels:
			if typeof(r_any) != TYPE_DICTIONARY:
				continue
			var r: Dictionary = r_any
			var rid := int(r.get("id", -1))
			if rid >= 0 and rid != pid:
				related_pattern_ids.append(rid)
		related_pattern_ids = related_pattern_ids.slice(0, 5)

		var pids: Array[int] = [pid]
		for rid in related_pattern_ids:
			pids.append(rid)

		dream_candidates.append({
			"candidate_id": "cluster_%d_%d" % [pid, Time.get_ticks_msec()],
			"name": cand_name,
			"intent": intent,
			"orientation_quadrant": "",
			"pattern_ids": pids,
			"item_ids": item_ids,
			"items": items,
			"confidence": conf,
		})

	if dream_inbox_list:
		for i in range(dream_candidates.size()):
			var c_row: Dictionary = dream_candidates[i]
			dream_inbox_list.add_item(_dream_inbox_row_text(c_row))
			dream_inbox_list.set_item_tooltip(i, str(c_row.get("intent", "")).strip_edges())

	_cstatus("Dream Inbox: %d pattern candidates. Select one, then Work on this — or Defer / Reject." % dream_candidates.size())
	update_decision_buttons()

func get_dream_candidates() -> Array:
	## Headless accessor for Metapunkt / application callers (REQ-NDP-015).
	return dream_candidates.duplicate(true)


func select_candidate(idx: int) -> bool:
	## Select a Dream Inbox candidate by index without requiring ItemList UI.
	if idx < 0 or idx >= dream_candidates.size():
		_cstatus("select_candidate: index out of range.")
		update_decision_buttons()
		return false
	if dream_inbox_list:
		dream_inbox_list.select(idx)
	on_dream_candidate_selected(idx)
	return true


func work_on_this() -> void:
	## Primary Dream Inbox action: select active/selected candidate and populate Closure Editor.
	var idx: int = active_candidate_idx
	if dream_inbox_list:
		var selected_items: PackedInt32Array = dream_inbox_list.get_selected_items()
		if not selected_items.is_empty():
			idx = int(selected_items[0])
	if idx < 0 and not dream_candidates.is_empty():
		idx = 0
	if idx < 0 or idx >= dream_candidates.size():
		_cstatus("Select a Dream Inbox candidate first.")
		update_decision_buttons()
		return
	if dream_inbox_list:
		dream_inbox_list.select(idx)
	on_dream_candidate_selected(idx)


func on_dream_candidate_selected(idx: int) -> void:
	if idx < 0 or idx >= dream_candidates.size():
		active_candidate_idx = idx
		update_decision_buttons()
		return

	# Warn if switching away from unsaved edits
	if _has_unsaved_edits and active_candidate_idx >= 0 and active_candidate_idx != idx:
		_cstatus("Unsaved edits on previous candidate were discarded. Now editing candidate #%d." % idx)
	_has_unsaved_edits = false

	active_candidate_idx = idx
	var c: Dictionary = dream_candidates[idx]

	# Set editor fields and remember originals for change detection
	var cand_name := str(c.get("name", ""))
	var cand_intent := str(c.get("intent", ""))
	var orient_idx: int = _orientation_idx_from_quadrant(str(c.get("orientation_quadrant", "")))
	_original_name = cand_name
	_original_intent = cand_intent
	_original_orientation_idx = orient_idx
	if closure_name_edit:
		closure_name_edit.text = cand_name
	if closure_intent_edit:
		closure_intent_edit.text = cand_intent
	if orientation_option:
		orientation_option.select(orient_idx)
	var items_arr: Array = c.get("items", [])
	var conf := float(c.get("confidence", 0.0))
	var conf_label := "low"
	if conf >= 0.7:
		conf_label = "high"
	elif conf >= 0.4:
		conf_label = "medium"
	if selected_label:
		selected_label.text = "Editing: %s | %d items | %s confidence (%.0f%%)" % [cand_name, items_arr.size(), conf_label, conf * 100.0]

	# Populate items in the candidate and available items for adding
	_refresh_candidate_items_list(c)
	_refresh_available_items_list(c)

	_cstatus("Review items and optional Orientation (A–D). Remove/add items, then Commit.")
	update_decision_buttons()
	candidate_editing.emit(idx)

func update_decision_buttons() -> void:
	var has_sel := (active_candidate_idx >= 0 and active_candidate_idx < dream_candidates.size())
	var has_candidates := not dream_candidates.is_empty()
	if work_on_this_button:
		# Enable when inbox has candidates; work_on_this falls back to first if none selected.
		work_on_this_button.disabled = not has_candidates
	if defer_button:
		defer_button.disabled = not has_sel
	if reject_button:
		reject_button.disabled = not has_sel

# ── Item curation ─────────────────────────────────────────────────────────

func _on_remove_item_pressed() -> void:
	## Remove the selected item from the active candidate's items list.
	if active_candidate_idx < 0 or active_candidate_idx >= dream_candidates.size():
		_cstatus("Select a candidate first.")
		return
	if not candidate_items_list:
		return
	var sel_items := candidate_items_list.get_selected_items()
	if sel_items.is_empty():
		_cstatus("Select an item in the list above, then click Remove.")
		return

	# Remove from back to front so indices stay valid
	var sorted_sel: Array = Array(sel_items)
	sorted_sel.sort()
	sorted_sel.reverse()

	var c: Dictionary = dream_candidates[active_candidate_idx]
	var items: Array = c.get("items", [])
	var item_ids: Array = c.get("item_ids", [])
	for sel_idx in sorted_sel:
		if sel_idx < items.size():
			items.remove_at(sel_idx)
		if sel_idx < item_ids.size():
			item_ids.remove_at(sel_idx)
		candidate_items_list.remove_item(sel_idx)

	# Update the stored candidate
	c["items"] = items
	c["item_ids"] = item_ids
	dream_candidates[active_candidate_idx] = c

	# Refresh both lists
	_refresh_candidate_items_list(c)
	_refresh_available_items_list(c)
	_has_unsaved_edits = true
	_cstatus("Removed item. %d items remaining." % items.size())

# ── Decisions ─────────────────────────────────────────────────────────────

func decision_candidate(decision: String, remove_from_inbox: bool) -> void:
	if active_candidate_idx < 0 or active_candidate_idx >= dream_candidates.size():
		_cstatus("Select a Dream Inbox candidate first.")
		return

	var c: Dictionary = dream_candidates[active_candidate_idx]
	var cand_id := str(c.get("candidate_id", ""))
	var payload := {
		"decision": decision,
		"candidate_id": cand_id,
		"candidate_name": str(c.get("name", "")),
		"pattern_ids": c.get("pattern_ids", []),
	}
	var prov := {"generated_by": "synaxes.dream_inbox"}
	await hub.create_event("synaxes.dream_inbox.decision", payload, prov, "synaxes", seq_fn.call())

	if remove_from_inbox:
		dream_candidates.remove_at(active_candidate_idx)
		if dream_inbox_list:
			dream_inbox_list.remove_item(active_candidate_idx)
		active_candidate_idx = -1
		update_decision_buttons()
		_cstatus("%s recorded." % decision.capitalize())
	else:
		_cstatus("Accepted. Edit and commit the closure when ready.")

# ── Closure commit ────────────────────────────────────────────────────────

func commit_closure(provenance_ctx: Dictionary, overrides: Dictionary = {}) -> Dictionary:
	## provenance_ctx keys: context_graph_artifact_id, projection_artifact_id,
	## cluster_artifact_id, analysis_run_artifact_id, discovery_method, dim_method, clusters_count
	## Optional overrides (headless / Metapunkt): name, intent, orientation/orientation_quadrant,
	## time_start, time_end, item_ids, candidate_idx.
	if overrides.has("candidate_idx"):
		var override_idx: int = int(overrides.get("candidate_idx", -1))
		if not select_candidate(override_idx):
			return {"ok": false, "error": "candidate_idx out of range"}
	if active_candidate_idx < 0 or active_candidate_idx >= dream_candidates.size():
		_cstatus("Select a Dream Inbox candidate first.")
		return {"ok": false, "error": "No Dream Inbox candidate selected"}

	var c: Dictionary = dream_candidates[active_candidate_idx]
	if overrides.has("item_ids") and typeof(overrides.get("item_ids")) == TYPE_ARRAY:
		var override_ids: Array = overrides.get("item_ids", [])
		var id_strings: Array[String] = []
		for id_any in override_ids:
			id_strings.append(str(id_any))
		c["item_ids"] = id_strings
		dream_candidates[active_candidate_idx] = c

	var cname: String = (
		str(overrides.get("name", "")).strip_edges()
		if overrides.has("name")
		else (closure_name_edit.text.strip_edges() if closure_name_edit else str(c.get("name", "")))
	)
	if cname.is_empty():
		_cstatus("Closure name is required.")
		return {"ok": false, "error": "Closure name is required"}
	var intent: String = (
		str(overrides.get("intent", "")).strip_edges()
		if overrides.has("intent")
		else (closure_intent_edit.text.strip_edges() if closure_intent_edit else str(c.get("intent", "")))
	)
	var t_start: String = (
		str(overrides.get("time_start", "")).strip_edges()
		if overrides.has("time_start")
		else (time_start_edit.text.strip_edges() if time_start_edit else "")
	)
	var t_end: String = (
		str(overrides.get("time_end", "")).strip_edges()
		if overrides.has("time_end")
		else (time_end_edit.text.strip_edges() if time_end_edit else "")
	)

	# Validate date format if provided (YYYY-MM-DD)
	if not t_start.is_empty() and not _is_valid_date(t_start):
		_cstatus("'From' date must be in YYYY-MM-DD format (e.g. 2025-12-20), or leave blank.")
		return {"ok": false, "error": "Invalid time_start format"}
	if not t_end.is_empty() and not _is_valid_date(t_end):
		_cstatus("'Until' date must be in YYYY-MM-DD format (e.g. 2026-01-15), or leave blank.")
		return {"ok": false, "error": "Invalid time_end format"}

	var ctx_id := str(provenance_ctx.get("context_graph_artifact_id", ""))
	var proj_id := str(provenance_ctx.get("projection_artifact_id", ""))
	var clust_id := str(provenance_ctx.get("cluster_artifact_id", ""))
	var run_id := str(provenance_ctx.get("analysis_run_artifact_id", ""))

	var orient_quadrant: String = ""
	if overrides.has("orientation") or overrides.has("orientation_quadrant"):
		orient_quadrant = ClosureOrientationScript.normalize_quadrant(
			str(overrides.get("orientation", overrides.get("orientation_quadrant", "")))
		)
	else:
		orient_quadrant = _current_orientation_quadrant()
	# Keep candidate in sync if the OptionButton was set without a prior signal.
	c["orientation_quadrant"] = orient_quadrant
	dream_candidates[active_candidate_idx] = c

	var schema_version: int = 1 if orient_quadrant.is_empty() else 2
	var closure := {
		"schema_version": schema_version,
		"name": cname,
		"intent": intent,
		"selection": {
			"pattern_ids": c.get("pattern_ids", []),
			"item_ids": c.get("item_ids", []),
			"context_graph_artifact_id": ctx_id,
			"projection_artifact_id": proj_id,
			"cluster_artifact_id": clust_id,
			"analysis_run_artifact_id": run_id,
		},
		"time_window": {"start": t_start, "end": t_end},
	}
	if not orient_quadrant.is_empty():
		closure["orientation"] = ClosureOrientationScript.build_annotation(orient_quadrant)

	var metadata := {
		"provenance": {
			"generated_by": "synaxes.commit_closure",
			"inputs": [
				{"type": "artifact", "id": ctx_id},
				{"type": "artifact", "id": run_id},
			],
			"parameters": {
				"discovery_method": int(provenance_ctx.get("discovery_method", 0)),
				"dim_method": int(provenance_ctx.get("dim_method", 0)),
				"clusters": int(provenance_ctx.get("clusters_count", 0)),
				"orientation_quadrant": orient_quadrant,
			},
		}
	}

	if hub == null:
		_cstatus("Commit failed: Hub client unavailable.")
		return {"ok": false, "error": "Hub client unavailable"}

	_cstatus("Committing closure to hub…")
	var res: Dictionary = await hub.create_artifact_inline_json("ui.closure", closure, metadata)
	if bool(res.get("ok", false)):
		var new_id := str(res.get("id", ""))
		var extra := ""
		if not clust_id.is_empty() or not proj_id.is_empty():
			extra = " (analysis: proj=%s, cluster=%s)" % [proj_id.left(8), clust_id.left(8)]
		if not orient_quadrant.is_empty():
			extra += " orient=%s" % orient_quadrant
		_has_unsaved_edits = false
		_cstatus(
			"Committed: %s%s. Next: commit another theme, or open SynPunkt Closures."
			% [cname if not cname.is_empty() else new_id.left(12), extra]
		)
		await hub.create_event(
			"synaxes.closure.committed",
			{
				"closure_artifact_id": new_id,
				"candidate_id": str(c.get("candidate_id", "")),
				"name": cname,
				"context_graph_artifact_id": ctx_id,
				"orientation_quadrant": orient_quadrant,
			},
			{"generated_by": "synaxes.commit_closure"},
			"synaxes",
			seq_fn.call()
		)
		await _commit_stfx_store_closure(closure, metadata, new_id)
		await reload_saved_closures()
		_set_post_commit_actions_visible(true)
		closure_committed.emit(new_id)
		return {"ok": true, "closure_artifact_id": new_id, "name": cname}
	var err_text: String = str(res.get("error", res))
	_cstatus("Commit failed: %s" % err_text)
	return {"ok": false, "error": err_text}


func prepare_commit_another() -> void:
	## Clear editor for the next Dream Inbox candidate (REQ-NDP-008).
	_set_post_commit_actions_visible(false)
	active_candidate_idx = -1
	_has_unsaved_edits = false
	_original_name = ""
	_original_intent = ""
	_original_orientation_idx = 0
	if closure_name_edit:
		closure_name_edit.text = ""
	if closure_intent_edit:
		closure_intent_edit.text = ""
	if orientation_option:
		orientation_option.select(0)
	if time_start_edit:
		time_start_edit.text = ""
	if time_end_edit:
		time_end_edit.text = ""
	if selected_label:
		selected_label.text = "Selected patterns: (none)"
	if candidate_items_list:
		candidate_items_list.clear()
	if available_items_list:
		available_items_list.clear()
	if dream_inbox_list:
		dream_inbox_list.deselect_all()
	update_decision_buttons()
	_cstatus("Ready for another. Select a Dream Inbox candidate, then Work on this.")


func request_open_synpunkt_closures() -> void:
	## Host shell should switch to SynPunkt (Closures). Addon does not touch host tree.
	navigate_requested.emit(NAV_TARGET_SYNPUNKT_CLOSURES)
	_cstatus("Opening SynPunkt Closures…")

func _commit_stfx_store_closure(closure: Dictionary, metadata: Dictionary, ui_closure_artifact_id: String) -> void:
	if hub == null or not hub.has_method("stfx_store_commit_closure"):
		return
	await load_stfx_store_index_datasets()
	var title: String = str(closure.get("name", "SynAxes Closure")).strip_edges()
	if title.is_empty():
		title = "SynAxes Closure"
	var intent: String = str(closure.get("intent", "")).strip_edges()
	var rationale: String = intent
	if rationale.is_empty():
		rationale = "Human-committed SynAxes closure mirrored from ui.closure."
	var selection_any: Variant = closure.get("selection", {})
	var selection: Dictionary = selection_any if typeof(selection_any) == TYPE_DICTIONARY else {}
	var artifact_ids: Array[String] = []
	_append_nonempty(artifact_ids, ui_closure_artifact_id)
	_append_nonempty(artifact_ids, str(selection.get("context_graph_artifact_id", "")))
	_append_nonempty(artifact_ids, str(selection.get("projection_artifact_id", "")))
	_append_nonempty(artifact_ids, str(selection.get("cluster_artifact_id", "")))
	_append_nonempty(artifact_ids, str(selection.get("analysis_run_artifact_id", "")))
	var item_ids: Array = selection.get("item_ids", []) if typeof(selection.get("item_ids", [])) == TYPE_ARRAY else []
	var pattern_ids: Array = selection.get("pattern_ids", []) if typeof(selection.get("pattern_ids", [])) == TYPE_ARRAY else []
	var time_window_any: Variant = closure.get("time_window", {})
	var time_window: Dictionary = time_window_any if typeof(time_window_any) == TYPE_DICTIONARY else {}
	var payload := {
		"title": title,
		"selected": {
			"artifact_ids": artifact_ids,
			"source_ids": [],
			"chunk_ids": [],
			"memory_ids": [],
			"item_ids": item_ids,
			"pattern_ids": pattern_ids,
		},
		"symbolic_constraints": {
			"primary_seed": "closure",
			"source_app": "synaxes",
			"time_window": time_window,
		},
		"human_commit": {
			"committed_by": "synaxes",
			"decision": "commit",
			"ui_closure_artifact_id": ui_closure_artifact_id,
		},
		"rationale": rationale,
		"relations": [
			{
				"type": "mirrors",
				"target": ui_closure_artifact_id,
				"rationale": "Store closure mirrors the committed LatentSubstrate ui.closure artifact.",
			}
		],
	}
	var metadata_prov_any: Variant = metadata.get("provenance", {})
	var metadata_prov: Dictionary = metadata_prov_any if typeof(metadata_prov_any) == TYPE_DICTIONARY else {}
	var provenance := {
		"produced_by": "synaxes.ui_closure_to_stfx_store",
		"inputs": [
			{"type": "substrate.artifact", "artifact_type": "ui.closure", "artifact_id": ui_closure_artifact_id}
		],
		"source_provenance": metadata_prov,
	}
	var store_res: Dictionary = await hub.stfx_store_commit_closure(payload, provenance)
	if bool(store_res.get("ok", false)):
		_cstatus("Committed ui.closure and Store closure: %s" % str(store_res.get("closure_id", "")))
	else:
		_cstatus("Committed ui.closure; Store closure mirror failed: %s" % str(store_res.get("error", store_res)))

func load_stfx_store_index_datasets() -> Dictionary:
	if hub == null or not hub.has_method("stfx_store_get_index"):
		return {"ok": false, "error": "Hub Store index API unavailable"}
	var symbolic_res: Dictionary = await hub.stfx_store_get_index("symbolic")
	var relation_res: Dictionary = await hub.stfx_store_get_index("relation")
	var vector_res: Dictionary = await hub.stfx_store_get_index("vector")
	store_index_datasets = {
		"symbolic": symbolic_res.get("index", {}) if bool(symbolic_res.get("ok", false)) else {},
		"relation": relation_res.get("index", {}) if bool(relation_res.get("ok", false)) else {},
		"vector": vector_res.get("index", {}) if bool(vector_res.get("ok", false)) else {},
	}
	var symbolic_count: int = int((store_index_datasets.get("symbolic", {}) as Dictionary).get("chunk_count", 0)) if typeof(store_index_datasets.get("symbolic", {})) == TYPE_DICTIONARY else 0
	var relation_edges: int = int(((store_index_datasets.get("relation", {}) as Dictionary).get("edges", []) as Array).size()) if typeof(store_index_datasets.get("relation", {})) == TYPE_DICTIONARY and typeof((store_index_datasets.get("relation", {}) as Dictionary).get("edges", [])) == TYPE_ARRAY else 0
	var vector_count: int = int(((store_index_datasets.get("vector", {}) as Dictionary).get("vectors", {}) as Dictionary).size()) if typeof(store_index_datasets.get("vector", {})) == TYPE_DICTIONARY and typeof((store_index_datasets.get("vector", {}) as Dictionary).get("vectors", {})) == TYPE_DICTIONARY else 0
	_cstatus("Loaded Store indexes: symbolic_chunks=%d relation_edges=%d vector_chunks=%d" % [symbolic_count, relation_edges, vector_count])
	return {"ok": true, "datasets": store_index_datasets}

func _append_nonempty(target: Array[String], value: String) -> void:
	var text: String = str(value).strip_edges()
	if not text.is_empty():
		target.append(text)

# ── Saved closures ────────────────────────────────────────────────────────

func reload_saved_closures() -> void:
	if not saved_closures_list:
		return
	saved_closures_list.clear()
	var count_a: int = 0
	var count_b: int = 0
	var count_c: int = 0
	var count_d: int = 0
	var count_untagged: int = 0
	var loaded_count: int = 0
	var skipped_count: int = 0
	var res: Dictionary = await hub.query_artifacts_by_type("ui.closure", 25)
	if not bool(res.get("ok", false)):
		_set_coverage_text(0, 0, 0, 0, 0)
		_cstatus("Load saved closures failed: %s" % str(res.get("error", res)))
		return
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	for row_any in rows:
		if typeof(row_any) != TYPE_ARRAY:
			continue
		var row: Array = row_any
		var art_id := _row_get(cols, row, "id")
		if art_id.is_empty():
			continue
		var display_name: String = art_id.left(12)
		var quadrant: String = ""
		# Prefer payload (schema v2 orientation + name); fall back to metadata params.
		if hub != null and hub.has_method("get_artifact_json"):
			var json_res: Dictionary = await hub.get_artifact_json(art_id)
			if bool(json_res.get("ok", false)):
				var doc_any: Variant = json_res.get("json", {})
				if typeof(doc_any) == TYPE_DICTIONARY:
					var doc: Dictionary = doc_any
					# Sessions once wrote captures under this type (pre ADR 0026).
					# They have no selection or orientation, so counting them
					# would inflate the untagged share of Closure Map coverage.
					if _is_legacy_session_capture(doc):
						skipped_count += 1
						continue
					var n: String = str(doc.get("name", "")).strip_edges()
					if not n.is_empty():
						display_name = n
					var orient_any: Variant = doc.get("orientation", {})
					if typeof(orient_any) == TYPE_DICTIONARY:
						quadrant = str((orient_any as Dictionary).get("quadrant", "")).strip_edges().to_upper()
		if quadrant.is_empty():
			var meta_json := _row_get(cols, row, "metadata_json")
			var meta_any: Variant = JSON.parse_string(meta_json) if not meta_json.is_empty() else null
			if typeof(meta_any) == TYPE_DICTIONARY:
				var prov_any: Variant = (meta_any as Dictionary).get("provenance", {})
				if typeof(prov_any) == TYPE_DICTIONARY:
					var params_any: Variant = (prov_any as Dictionary).get("parameters", {})
					if typeof(params_any) == TYPE_DICTIONARY:
						quadrant = str((params_any as Dictionary).get("orientation_quadrant", "")).strip_edges().to_upper()
		match quadrant:
			"A":
				count_a += 1
			"B":
				count_b += 1
			"C":
				count_c += 1
			"D":
				count_d += 1
			_:
				count_untagged += 1
				quadrant = ""
		var badge: String = "[%s]" % quadrant if not quadrant.is_empty() else "[·]"
		saved_closures_list.add_item("%s %s" % [badge, display_name])
		saved_closures_list.set_item_tooltip(loaded_count, "Artifact %s" % art_id)
		loaded_count += 1
	_set_coverage_text(count_a, count_b, count_c, count_d, count_untagged)
	if skipped_count > 0:
		_cstatus("Loaded %d saved closures (skipped %d session capture(s) stored under this type before ADR 0026)." % [
			loaded_count,
			skipped_count,
		])
	else:
		_cstatus("Loaded %d saved closures." % loaded_count)

## True when a `ui.closure` payload is actually a session capture written before
## captures moved to `ui.workshop_closure` (ADR 0026). Captures carry a
## statement and no selection; SynAxes closures always carry a selection.
func _is_legacy_session_capture(doc: Dictionary) -> bool:
	if typeof(doc.get("selection")) == TYPE_DICTIONARY:
		return false
	return not str(doc.get("statement", "")).strip_edges().is_empty()

# ── Add items to closure ──────────────────────────────────────────────────

## Reference to the full imported data array (set by runtime controller).
var all_data: Array = []

## UI nodes for the add-items section.
var available_items_list: ItemList
var add_item_button: Button
var _available_data_indices: Array = []  # Maps list row → index in all_data

func _on_add_item_pressed() -> void:
	## Add selected items from the available list into the active candidate.
	if active_candidate_idx < 0 or active_candidate_idx >= dream_candidates.size():
		_cstatus("Select a candidate first.")
		return
	if not available_items_list:
		return
	var sel_items := available_items_list.get_selected_items()
	if sel_items.is_empty():
		_cstatus("Select items from the 'Available' list, then click Add.")
		return

	var c: Dictionary = dream_candidates[active_candidate_idx]
	var items: Array = c.get("items", [])
	var item_ids: Array = c.get("item_ids", [])

	# Collect the data items to add
	for sel_idx in sel_items:
		if sel_idx >= _available_data_indices.size():
			continue
		var data_idx: int = _available_data_indices[sel_idx]
		if data_idx >= all_data.size():
			continue
		var data_item: Variant = all_data[data_idx]
		if typeof(data_item) == TYPE_DICTIONARY:
			items.append(data_item)
			item_ids.append(str((data_item as Dictionary).get("id", "")))

	c["items"] = items
	c["item_ids"] = item_ids
	dream_candidates[active_candidate_idx] = c

	# Refresh both lists
	_refresh_candidate_items_list(c)
	_refresh_available_items_list(c)

	_has_unsaved_edits = true
	_cstatus("Added %d item(s). %d items now in closure." % [sel_items.size(), items.size()])

func _refresh_candidate_items_list(c: Dictionary) -> void:
	if not candidate_items_list:
		return
	candidate_items_list.clear()
	var items: Array = c.get("items", [])
	for it_any in items:
		if typeof(it_any) == TYPE_DICTIONARY:
			var it: Dictionary = it_any
			var content := str(it.get("content", ""))
			var item_id := str(it.get("id", ""))
			if content.is_empty():
				content = item_id if not item_id.is_empty() else "(no content)"
			if content.length() > 120:
				content = content.left(117) + "..."
			candidate_items_list.add_item(content)
		else:
			candidate_items_list.add_item(str(it_any))
	# Update summary
	var conf := float(c.get("confidence", 0.0))
	var conf_label := "low"
	if conf >= 0.7:
		conf_label = "high"
	elif conf >= 0.4:
		conf_label = "medium"
	if selected_label:
		selected_label.text = "%d items | %s confidence (%.0f%%)" % [items.size(), conf_label, conf * 100.0]

func _refresh_available_items_list(c: Dictionary) -> void:
	if not available_items_list:
		return
	available_items_list.clear()
	_available_data_indices.clear()

	# Build set of item IDs already in the candidate for fast lookup
	var existing_ids: Dictionary = {}
	var items: Array = c.get("items", [])
	for it_any in items:
		if typeof(it_any) == TYPE_DICTIONARY:
			existing_ids[str((it_any as Dictionary).get("id", ""))] = true

	for i in range(all_data.size()):
		if typeof(all_data[i]) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = all_data[i] as Dictionary
		var d_id := str(d.get("id", ""))
		if existing_ids.has(d_id):
			continue
		var content := str(d.get("content", ""))
		if content.is_empty():
			content = d_id if not d_id.is_empty() else "(no content)"
		if content.length() > 100:
			content = content.left(97) + "..."
		available_items_list.add_item(content)
		_available_data_indices.append(i)

# ── Closure Map orientation ───────────────────────────────────────────────

func _on_orientation_selected(idx: int) -> void:
	if active_candidate_idx < 0 or active_candidate_idx >= dream_candidates.size():
		return
	var quadrant: String = _quadrant_from_orientation_idx(idx)
	var c: Dictionary = dream_candidates[active_candidate_idx]
	c["orientation_quadrant"] = quadrant
	dream_candidates[active_candidate_idx] = c
	_refresh_dream_inbox_row(active_candidate_idx)
	_mark_edited()

func _current_orientation_quadrant() -> String:
	if orientation_option != null:
		return _quadrant_from_orientation_idx(orientation_option.selected)
	# Headless / no UI: fall back to the active candidate dictionary.
	if active_candidate_idx >= 0 and active_candidate_idx < dream_candidates.size():
		return str(dream_candidates[active_candidate_idx].get("orientation_quadrant", "")).strip_edges().to_upper()
	return ""

func _quadrant_from_orientation_idx(idx: int) -> String:
	if idx <= UNTAGGED_OPTION_IDX or idx > ClosureOrientationScript.QUADRANTS.size():
		return ""
	return ClosureOrientationScript.QUADRANTS[idx - 1]

func _orientation_idx_from_quadrant(quadrant: String) -> int:
	# An unrecognised quadrant finds nothing, giving -1 + 1 = the Untagged row.
	return ClosureOrientationScript.QUADRANTS.find(
		ClosureOrientationScript.normalize_quadrant(quadrant)
	) + 1

func _orientation_badge(quadrant: String) -> String:
	var q: String = quadrant.strip_edges().to_upper()
	if q == "A" or q == "B" or q == "C" or q == "D":
		return "[%s]" % q
	return "[·]"

func _dream_inbox_row_text(c: Dictionary) -> String:
	var conf: float = float(c.get("confidence", 0.0))
	var conf_pct: String = "%.0f%%" % (conf * 100.0)
	var cand_name: String = str(c.get("name", "Candidate"))
	var sample: String = str(c.get("intent", "")).strip_edges()
	if sample.find("Samples:") != -1:
		sample = sample.get_slice("Samples:", 1).strip_edges()
	if sample.length() > 60:
		sample = sample.left(57) + "..."
	var badge: String = _orientation_badge(str(c.get("orientation_quadrant", "")))
	return "%s %s • %s • %s • %s" % [
		badge,
		cand_name,
		("%d items" % int(c.get("items", []).size())),
		conf_pct,
		sample,
	]

func _refresh_dream_inbox_row(idx: int) -> void:
	if dream_inbox_list == null or idx < 0 or idx >= dream_candidates.size():
		return
	if idx >= dream_inbox_list.item_count:
		return
	var c_row: Dictionary = dream_candidates[idx]
	dream_inbox_list.set_item_text(idx, _dream_inbox_row_text(c_row))
	dream_inbox_list.set_item_tooltip(idx, str(c_row.get("intent", "")).strip_edges())

## Coverage names each quadrant as a coordinate, so it leads with the canonical term
## and brackets the gloss — the upstream convention (REQ-NDP-009).
func _set_coverage_text(count_a: int, count_b: int, count_c: int, count_d: int, count_untagged: int) -> void:
	if coverage_label == null:
		return
	var counts_by_quadrant: Dictionary = {
		"A": count_a, "B": count_b, "C": count_c, "D": count_d,
	}
	var parts: Array[String] = []
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		parts.append("%s: %d" % [
			ClosureOrientationScript.get_canonical_with_gloss(quadrant_id),
			int(counts_by_quadrant[quadrant_id]),
		])
	parts.append("untagged: %d" % count_untagged)
	coverage_label.text = "Coverage — " + " \u00b7 ".join(parts)


## Rebuilds the picker from the shared vocabulary rather than from text authored in
## `synaxes_main.tscn`. The scene's baked rows are design-time placeholders only:
## anything typed there would be a second transcription and would drift.
func _apply_orientation_option_labels() -> void:
	if orientation_option == null:
		return
	var keep_idx: int = orientation_option.selected
	orientation_option.clear()
	orientation_option.add_item("Untagged", UNTAGGED_OPTION_IDX)
	orientation_option.set_item_tooltip(
		UNTAGGED_OPTION_IDX,
		"No orientation recorded. Commit still works — orientation is optional."
	)
	for quadrant_index in range(ClosureOrientationScript.QUADRANTS.size()):
		var quadrant_id: String = ClosureOrientationScript.QUADRANTS[quadrant_index]
		var option_idx: int = quadrant_index + 1
		orientation_option.add_item(
			ClosureOrientationScript.get_option_text(quadrant_id),
			option_idx
		)
		orientation_option.set_item_tooltip(
			option_idx,
			ClosureOrientationScript.get_quadrant_help(quadrant_id)
		)
	if keep_idx >= 0 and keep_idx < orientation_option.item_count:
		orientation_option.select(keep_idx)
	orientation_option.tooltip_text = (
		"Closure Map orientation — a human judgment, never inferred from embeddings.\n"
		+ "Distal is out there, beyond this group; Deep is in here, within how it"
		+ " already works. "
		+ ClosureOrientationScript.PLAIN_SET_SUMMARY
		+ "\nLeave Untagged if unsure."
	)


func _set_post_commit_actions_visible(is_shown: bool) -> void:
	if post_commit_actions:
		post_commit_actions.visible = is_shown
	if commit_another_button:
		commit_another_button.visible = is_shown
	if open_synpunkt_button:
		open_synpunkt_button.visible = is_shown

# ── Utilities ─────────────────────────────────────────────────────────────

static func _is_valid_date(date_str: String) -> bool:
	## Check if a string matches YYYY-MM-DD format with plausible values.
	if date_str.length() != 10:
		return false
	if date_str[4] != "-" or date_str[7] != "-":
		return false
	var parts := date_str.split("-")
	if parts.size() != 3:
		return false
	if not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return false
	var year := parts[0].to_int()
	var month := parts[1].to_int()
	var day := parts[2].to_int()
	if year < 1900 or year > 2100:
		return false
	if month < 1 or month > 12:
		return false
	if day < 1 or day > 31:
		return false
	return true

func _cstatus(msg: String) -> void:
	if closure_status_label:
		closure_status_label.text = msg
	print("[SynAxesClosure] ", msg)
	closure_status.emit(msg)

func _row_get(cols: Array, row: Array, col_name: String) -> String:
	var idx := cols.find(col_name)
	if idx == -1 or idx >= row.size():
		return ""
	return str(row[idx])
