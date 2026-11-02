extends RefCounted
## Hub-substrate job orchestration for SynAxes.
##
## Handles: embed_text, project, cluster, bridges, hubs jobs,
## artifact persistence, entity/relation alignment, and analysis-run records.

signal status_message(msg: String)

const DimReductionScript = preload("res://addons/synaxes/scripts/pattern_space/dimensionality_reduction.gd")

const ARTIFACT_PROJECTION_3D := "coords.projection_3d"
const ARTIFACT_CLUSTER_RESULT := "graph.cluster_result"
const ARTIFACT_ANALYSIS_RUN := "json.analysis_run"
const ENTITY_CONTEXT_NODE := "context_graph_node"
const ENTITY_CLUSTER := "synaxes.cluster"
const REL_MEMBER_OF_CLUSTER := "member_of_cluster"

## Set these after construction, before calling any methods.
var hub  # HubSubstrateClient
var seq_fn: Callable  # () -> int – returns next sequence number

var active_job_ids: Dictionary = {}

# ── Embedding artifact persistence ────────────────────────────────────────

func persist_embedding_artifact(
	data: Array,
	context_graph_artifact_id: String,
	embedding_tier: String,
	model_provider: String,
	model_name: String,
) -> String:
	## Persists the embedding vectors currently attached to data as a Hub artifact.
	## Returns the artifact ID on success, empty string on failure.
	if data.is_empty():
		return ""
	var vectors_map: Dictionary = {}
	var contents_map: Dictionary = {}
	var item_ids: Array = []
	for it_any in data:
		if typeof(it_any) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_any
		var iid := str(it.get("id", ""))
		item_ids.append(iid)
		vectors_map[iid] = it.get("vector", [])
		contents_map[iid] = str(it.get("content", ""))

	var payload := {
		"schema": "synaxes.embeddings",
		"schema_version": 2,
		"item_ids": item_ids,
		"vectors": vectors_map,
		"contents": contents_map,
		"dim": vectors_map.values()[0].size() if not vectors_map.is_empty() else 0,
	}
	var meta := {
		"provenance": {
			"generated_by": "synaxes.embed",
			"embedding_tier": embedding_tier,
			"model_provider": model_provider,
			"model_name": model_name,
			"item_count": item_ids.size(),
			"inputs": [],
		}
	}
	if not context_graph_artifact_id.is_empty():
		meta["provenance"]["inputs"].append({"type": "artifact", "id": context_graph_artifact_id})

	var res: Dictionary = await hub.create_artifact_inline_json("synaxes.embeddings", payload, meta)
	if bool(res.get("ok", false)):
		var art_id := str(res.get("id", ""))
		_status("Persisted embeddings artifact: %s (%s/%s, %d items)" % [art_id.left(12), model_provider, model_name, item_ids.size()])
		return art_id
	return ""

# ── Hub-job discovery pipeline ────────────────────────────────────────────

const DIM_METHOD_NAMES := ["pca", "tsne", "umap"]

func discover_via_hub_jobs(
	data: Array,
	context_graph_artifact_id: String,
	discovery_method_id: int,
	dim_method_id: int,
	k: int
) -> Dictionary:
	## Returns: {patterns, projection_artifact_id, cluster_artifact_id,
	##           analysis_run_artifact_id, bridge_artifact_id, hub_artifact_id}
	var empty := _empty_result()
	if context_graph_artifact_id.is_empty():
		_status("Use Hub Jobs requires importing a Hub context graph first.")
		return empty
	var ids_and_vectors: Dictionary = extract_ids_and_vectors(data)
	var item_ids: Array = ids_and_vectors.get("item_ids", [])
	var vectors: Array = ids_and_vectors.get("vectors", [])
	if item_ids.is_empty() or vectors.is_empty() or item_ids.size() != vectors.size():
		_status("No vectors available to submit to hub jobs.")
		return empty

	var dim_method_name: String = DIM_METHOD_NAMES[dim_method_id] if dim_method_id < DIM_METHOD_NAMES.size() else "pca"
	_status("Discovering via hub jobs (%s + kmeans)…" % dim_method_name)

	# ── Project ───────────────────────────────────────────────────────
	var proj_submit: Dictionary = await hub.submit_job(
		"synaxes.project",
		{"item_ids": item_ids, "vectors": vectors, "dim": 3, "method": dim_method_name},
		{},
		{"context_graph_artifact_id": context_graph_artifact_id}
	)
	if not bool(proj_submit.get("ok", false)):
		_status("Project job submit failed: %s" % str(proj_submit.get("error", proj_submit)))
		return empty
	var proj_job_id := str(proj_submit.get("id", "")).strip_edges()
	active_job_ids[proj_job_id] = "project"
	var proj_done: Dictionary = await hub.await_job_done(proj_job_id, 90.0)
	active_job_ids.erase(proj_job_id)
	if not bool(proj_done.get("ok", false)):
		_status("Project job failed: %s" % str(proj_done.get("error", proj_done)))
		return empty
	if str(proj_done.get("status", "")) != "completed":
		_status("Project job did not complete.")
		return empty
	var proj_payload: Dictionary = proj_done.get("payload", {})
	var artifacts_any: Variant = proj_payload.get("artifacts", [])
	var artifacts: Array = artifacts_any if typeof(artifacts_any) == TYPE_ARRAY else []
	var projection_artifact_id := ""
	for a_any in artifacts:
		if typeof(a_any) != TYPE_DICTIONARY:
			continue
		var a: Dictionary = a_any
		if str(a.get("artifact_type", "")) == ARTIFACT_PROJECTION_3D:
			projection_artifact_id = str(a.get("artifact_id", "")).strip_edges()
			break
	if projection_artifact_id.is_empty():
		_status("Project job missing projection_artifact_id.")
		return empty

	var proj_json_res: Dictionary = await hub.get_artifact_json(projection_artifact_id)
	if not bool(proj_json_res.get("ok", false)):
		_status("Failed to load projection artifact: %s" % str(proj_json_res.get("error", proj_json_res)))
		return empty
	var proj_json: Dictionary = proj_json_res.get("json", {})
	var coords_any: Variant = proj_json.get("coords", {})
	if typeof(coords_any) != TYPE_DICTIONARY:
		_status("Projection artifact missing coords map.")
		return empty
	var coords: Dictionary = coords_any

	# ── Cluster ───────────────────────────────────────────────────────
	var cluster_submit: Dictionary = await hub.submit_job(
		"synaxes.cluster",
		{"coords": coords, "k": k, "seed": 1337},
		{},
		{"projection_artifact_id": projection_artifact_id, "context_graph_artifact_id": context_graph_artifact_id}
	)
	if not bool(cluster_submit.get("ok", false)):
		_status("Cluster job submit failed: %s" % str(cluster_submit.get("error", cluster_submit)))
		return empty
	var cluster_job_id := str(cluster_submit.get("id", "")).strip_edges()
	active_job_ids[cluster_job_id] = "cluster"
	var cluster_done: Dictionary = await hub.await_job_done(cluster_job_id, 90.0)
	active_job_ids.erase(cluster_job_id)
	if not bool(cluster_done.get("ok", false)):
		_status("Cluster job failed: %s" % str(cluster_done.get("error", cluster_done)))
		return empty
	if str(cluster_done.get("status", "")) != "completed":
		_status("Cluster job did not complete.")
		return empty
	var cluster_payload: Dictionary = cluster_done.get("payload", {})
	var c_artifacts_any: Variant = cluster_payload.get("artifacts", [])
	var c_artifacts: Array = c_artifacts_any if typeof(c_artifacts_any) == TYPE_ARRAY else []
	var cluster_artifact_id := ""
	for a_any in c_artifacts:
		if typeof(a_any) != TYPE_DICTIONARY:
			continue
		var a: Dictionary = a_any
		if str(a.get("artifact_type", "")) == ARTIFACT_CLUSTER_RESULT:
			cluster_artifact_id = str(a.get("artifact_id", "")).strip_edges()
			break
	if cluster_artifact_id.is_empty():
		_status("Cluster job missing cluster_artifact_id.")
		return empty

	var cluster_json_res: Dictionary = await hub.get_artifact_json(cluster_artifact_id)
	if not bool(cluster_json_res.get("ok", false)):
		_status("Failed to load cluster artifact: %s" % str(cluster_json_res.get("error", cluster_json_res)))
		return empty
	var cluster_json: Dictionary = cluster_json_res.get("json", {})
	var clusters_any: Variant = cluster_json.get("clusters", [])
	if typeof(clusters_any) != TYPE_ARRAY:
		_status("Cluster artifact missing clusters array.")
		return empty
	var clusters_arr: Array = clusters_any

	# ── Optional bridge / hub jobs ────────────────────────────────────
	var bridge_artifact_id := ""
	var hub_artifact_id := ""
	var coords_for_jobs: Dictionary = coords
	var labels_for_jobs: Dictionary = _labels_map_from_clusters(clusters_arr)
	if discovery_method_id == 1:
		var br: Dictionary = await _run_bridges_job(coords_for_jobs, labels_for_jobs, projection_artifact_id, cluster_artifact_id)
		if bool(br.get("ok", false)):
			bridge_artifact_id = str(br.get("artifact_id", "")).strip_edges()
	elif discovery_method_id == 2:
		var hr: Dictionary = await _run_hubs_job(coords_for_jobs, projection_artifact_id)
		if bool(hr.get("ok", false)):
			hub_artifact_id = str(hr.get("artifact_id", "")).strip_edges()

	# ── Persist analysis run + entity/relation alignment ──────────────
	var analysis_run_artifact_id := ""
	analysis_run_artifact_id = await _persist_analysis_run_and_relations(
		item_ids, clusters_arr, discovery_method_id, dim_method_id, k,
		context_graph_artifact_id, projection_artifact_id, cluster_artifact_id,
		bridge_artifact_id, hub_artifact_id
	)

	# ── Build patterns ────────────────────────────────────────────────
	var item_by_id: Dictionary = {}
	for it_any in data:
		if typeof(it_any) == TYPE_DICTIONARY:
			var it: Dictionary = it_any
			item_by_id[str(it.get("id", ""))] = it

	var patterns: Array = _build_patterns_from_clusters(clusters_arr, item_by_id)

	if discovery_method_id == 1 and not bridge_artifact_id.is_empty():
		var bridges_any: Variant = await _load_bridges_from_artifact(bridge_artifact_id)
		if typeof(bridges_any) == TYPE_ARRAY:
			patterns.append_array(_bridge_patterns_from_items(bridges_any as Array, item_by_id, coords))
	if discovery_method_id == 2 and not hub_artifact_id.is_empty():
		var hubs_any: Variant = await _load_hubs_from_artifact(hub_artifact_id)
		if typeof(hubs_any) == TYPE_ARRAY:
			patterns.append_array(_hub_patterns_from_items(hubs_any as Array, item_by_id, coords))

	return {
		"patterns": patterns,
		"projection_artifact_id": projection_artifact_id,
		"cluster_artifact_id": cluster_artifact_id,
		"analysis_run_artifact_id": analysis_run_artifact_id,
		"bridge_artifact_id": bridge_artifact_id,
		"hub_artifact_id": hub_artifact_id,
	}

# ── Local (non-hub-job) persistence ──────────────────────────────────────

func persist_analysis_results_to_hub(
	patterns: Array,
	data: Array,
	context_graph_artifact_id: String,
	discovery_method_id: int,
	dim_method_id: int,
	k: int
) -> Dictionary:
	## Returns {projection_artifact_id, cluster_artifact_id, analysis_run_artifact_id}.
	var result := {"projection_artifact_id": "", "cluster_artifact_id": "", "analysis_run_artifact_id": ""}
	if context_graph_artifact_id.is_empty() or data.is_empty():
		return result

	var ids_and_vectors: Dictionary = extract_ids_and_vectors(data)
	var item_ids: Array = ids_and_vectors.get("item_ids", [])
	var vectors: Array = ids_and_vectors.get("vectors", [])
	if item_ids.is_empty() or vectors.is_empty() or item_ids.size() != vectors.size():
		return result

	# 1) Projection artifact (item_id -> [x,y,z])
	var positions: Array = DimReductionScript.reduce_dimensionality(vectors, dim_method_id)
	if positions.is_empty() or positions.size() != item_ids.size():
		return result

	var coords: Dictionary = {}
	for i in range(item_ids.size()):
		var vid := str(item_ids[i])
		var p_any: Variant = positions[i]
		if typeof(p_any) != TYPE_VECTOR3:
			continue
		var p: Vector3 = p_any
		coords[vid] = [p.x, p.y, p.z]

	var projection_payload := {
		"schema_version": 1,
		"method": dim_method_id,
		"dim": 3,
		"input_set": {"context_graph_artifact_id": context_graph_artifact_id, "item_ids": item_ids},
		"coords": coords,
	}
	var projection_meta := {
		"provenance": {
			"generated_by": "synaxes.discover_patterns",
			"inputs": [{"type": "artifact", "id": context_graph_artifact_id}],
			"parameters": {"dim_method": dim_method_id, "k": k, "discovery_method": discovery_method_id, "item_count": item_ids.size()},
		}
	}
	var proj_res: Dictionary = await hub.create_artifact_inline_json(ARTIFACT_PROJECTION_3D, projection_payload, projection_meta)
	if bool(proj_res.get("ok", false)):
		result["projection_artifact_id"] = str(proj_res.get("id", ""))

	# 2) Cluster artifact
	var clusters: Array = []
	for p_any in patterns:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_any
		if str(p.get("type", "")).to_lower() != "cluster":
			continue
		var cid := int(p.get("id", -1))
		if cid < 0:
			continue
		var items: Array = p.get("items", [])
		var cluster_item_ids: Array[String] = []
		for it_any in items:
			if typeof(it_any) == TYPE_DICTIONARY:
				cluster_item_ids.append(str((it_any as Dictionary).get("id", "")))
		var center_any: Variant = p.get("position", Vector3.ZERO)
		var center := center_any as Vector3
		clusters.append({
			"cluster_id": cid,
			"item_ids": cluster_item_ids,
			"center": [center.x, center.y, center.z],
			"confidence": float(p.get("confidence", 0.5)),
		})

	var cluster_payload := {
		"schema_version": 1,
		"method": discovery_method_id,
		"k": k,
		"input_set": {"context_graph_artifact_id": context_graph_artifact_id, "item_ids": item_ids},
		"projection_artifact_id": result["projection_artifact_id"],
		"clusters": clusters,
	}
	var cluster_meta := {
		"provenance": {
			"generated_by": "synaxes.discover_patterns",
			"inputs": [{"type": "artifact", "id": context_graph_artifact_id}],
			"parameters": {"dim_method": dim_method_id, "k": k, "discovery_method": discovery_method_id, "cluster_count": clusters.size()},
		}
	}
	var cluster_res: Dictionary = await hub.create_artifact_inline_json(ARTIFACT_CLUSTER_RESULT, cluster_payload, cluster_meta)
	if bool(cluster_res.get("ok", false)):
		result["cluster_artifact_id"] = str(cluster_res.get("id", ""))

	# 3) Analysis run (ties dataset+params+outputs together)
	if not result["projection_artifact_id"].is_empty() and not result["cluster_artifact_id"].is_empty():
		var analysis_run := {
			"schema": "synaxes.analysis_run",
			"schema_version": 1,
			"context_graph_artifact_id": context_graph_artifact_id,
			"item_ids": item_ids,
			"methods": {"discovery_method": discovery_method_id, "dim_method": dim_method_id, "k": k},
			"outputs": {
				"projection_artifact_id": result["projection_artifact_id"],
				"cluster_artifact_id": result["cluster_artifact_id"],
			}
		}
		var analysis_meta := {
			"provenance": {
				"generated_by": "synaxes.analysis_run",
				"inputs": [
					{"type": "artifact", "id": context_graph_artifact_id},
					{"type": "artifact", "id": result["projection_artifact_id"]},
					{"type": "artifact", "id": result["cluster_artifact_id"]},
				],
				"parameters": {"discovery_method": discovery_method_id, "dim_method": dim_method_id, "k": k},
			}
		}
		var ar_res: Dictionary = await hub.create_artifact_inline_json(ARTIFACT_ANALYSIS_RUN, analysis_run, analysis_meta)
		if bool(ar_res.get("ok", false)):
			result["analysis_run_artifact_id"] = str(ar_res.get("id", ""))

	# 4) Entity/Relation alignment (best-effort)
	if not result["cluster_artifact_id"].is_empty() and clusters.size() > 0:
		await _persist_cluster_membership(data, clusters, context_graph_artifact_id, result["cluster_artifact_id"])

	# Audit event
	await hub.create_event(
		"synaxes.analysis.persisted",
		{
			"context_graph_artifact_id": context_graph_artifact_id,
			"projection_artifact_id": result["projection_artifact_id"],
			"cluster_artifact_id": result["cluster_artifact_id"],
			"analysis_run_artifact_id": result["analysis_run_artifact_id"],
			"item_count": item_ids.size(),
			"cluster_count": clusters.size(),
		},
		{"generated_by": "synaxes.discover_patterns"},
		"synaxes",
		seq_fn.call()
	)
	return result

# ── Reload last analysis (REQ-NDP-017) ────────────────────────────────────

func reload_last_analysis(
	context_graph_artifact_id: String = "",
	existing_data: Array = [],
) -> Dictionary:
	## Load latest json.analysis_run (+ projection/cluster) and rebuild patterns.
	## Prefer a run matching context_graph_artifact_id when provided.
	## Returns discover-shaped dict plus hydrated_data / context_graph_artifact_id.
	var empty: Dictionary = _empty_result()
	empty["hydrated_data"] = []
	empty["context_graph_artifact_id"] = ""
	if hub == null:
		_status("Hub unavailable — cannot reload last analysis.")
		return empty

	_status("Looking up last analysis run on Hub…")
	var res: Dictionary = await hub.query_artifacts_by_type(ARTIFACT_ANALYSIS_RUN, 50)
	if not bool(res.get("ok", false)):
		_status("Hub query failed: %s" % str(res.get("error", res)))
		return empty
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	if rows.is_empty():
		_status("No analysis runs found on Hub. Run Discover once first.")
		return empty

	var wanted_ctx: String = context_graph_artifact_id.strip_edges()
	var ranked: Array = _rank_analysis_run_rows(cols, rows)
	var chosen_run: Dictionary = {}
	var chosen_run_id: String = ""
	for entry_any in ranked:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var art_id: String = str(entry.get("id", ""))
		if art_id.is_empty():
			continue
		var json_res: Dictionary = await hub.get_artifact_json(art_id)
		if not bool(json_res.get("ok", false)):
			continue
		var run_json_any: Variant = json_res.get("json", {})
		if typeof(run_json_any) != TYPE_DICTIONARY:
			continue
		var run_json: Dictionary = run_json_any
		var run_ctx: String = str(run_json.get("context_graph_artifact_id", "")).strip_edges()
		if not wanted_ctx.is_empty() and run_ctx != wanted_ctx:
			continue
		chosen_run = run_json
		chosen_run_id = art_id
		break

	if chosen_run_id.is_empty() and not wanted_ctx.is_empty():
		# Fall back to latest run of any graph when current graph has none.
		for entry_any in ranked:
			if typeof(entry_any) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_any
			var art_id: String = str(entry.get("id", ""))
			if art_id.is_empty():
				continue
			var json_res: Dictionary = await hub.get_artifact_json(art_id)
			if not bool(json_res.get("ok", false)):
				continue
			var run_json_any: Variant = json_res.get("json", {})
			if typeof(run_json_any) != TYPE_DICTIONARY:
				continue
			chosen_run = run_json_any
			chosen_run_id = art_id
			break

	if chosen_run_id.is_empty():
		_status("Could not load any analysis run JSON from Hub.")
		return empty

	var outputs_any: Variant = chosen_run.get("outputs", {})
	var outputs: Dictionary = outputs_any if typeof(outputs_any) == TYPE_DICTIONARY else {}
	var projection_artifact_id: String = str(outputs.get("projection_artifact_id", "")).strip_edges()
	var cluster_artifact_id: String = str(outputs.get("cluster_artifact_id", "")).strip_edges()
	var bridge_artifact_id: String = str(outputs.get("bridge_artifact_id", "")).strip_edges()
	var hub_artifact_id: String = str(outputs.get("hub_artifact_id", "")).strip_edges()
	var run_ctx_id: String = str(chosen_run.get("context_graph_artifact_id", "")).strip_edges()
	if cluster_artifact_id.is_empty():
		_status("Analysis run %s missing cluster artifact." % chosen_run_id.left(12))
		return empty

	var cluster_json_res: Dictionary = await hub.get_artifact_json(cluster_artifact_id)
	if not bool(cluster_json_res.get("ok", false)):
		_status("Failed to load cluster artifact: %s" % str(cluster_json_res.get("error", cluster_json_res)))
		return empty
	var cluster_json: Dictionary = cluster_json_res.get("json", {})
	var clusters_any: Variant = cluster_json.get("clusters", [])
	if typeof(clusters_any) != TYPE_ARRAY:
		_status("Cluster artifact missing clusters array.")
		return empty
	var clusters_arr: Array = clusters_any

	var coords: Dictionary = {}
	if not projection_artifact_id.is_empty():
		var proj_json_res: Dictionary = await hub.get_artifact_json(projection_artifact_id)
		if bool(proj_json_res.get("ok", false)):
			var proj_json: Dictionary = proj_json_res.get("json", {})
			var coords_any: Variant = proj_json.get("coords", {})
			if typeof(coords_any) == TYPE_DICTIONARY:
				coords = coords_any

	var item_ids_any: Variant = chosen_run.get("item_ids", [])
	var item_ids: Array = item_ids_any if typeof(item_ids_any) == TYPE_ARRAY else []
	if item_ids.is_empty():
		item_ids = _item_ids_from_clusters(clusters_arr)

	var hydrated_data: Array = _hydrate_items_for_reload(item_ids, existing_data, coords)
	var item_by_id: Dictionary = {}
	for it_any in hydrated_data:
		if typeof(it_any) == TYPE_DICTIONARY:
			var it: Dictionary = it_any
			item_by_id[str(it.get("id", ""))] = it

	var patterns: Array = _build_patterns_from_clusters(clusters_arr, item_by_id)
	if not bridge_artifact_id.is_empty():
		var bridges_any: Variant = await _load_bridges_from_artifact(bridge_artifact_id)
		if typeof(bridges_any) == TYPE_ARRAY:
			patterns.append_array(_bridge_patterns_from_items(bridges_any as Array, item_by_id, coords))
	if not hub_artifact_id.is_empty():
		var hubs_any: Variant = await _load_hubs_from_artifact(hub_artifact_id)
		if typeof(hubs_any) == TYPE_ARRAY:
			patterns.append_array(_hub_patterns_from_items(hubs_any as Array, item_by_id, coords))

	var methods_any: Variant = chosen_run.get("methods", {})
	var methods: Dictionary = methods_any if typeof(methods_any) == TYPE_DICTIONARY else {}
	_status("Reloaded analysis %s (%d themes, no re-import)." % [chosen_run_id.left(12), patterns.size()])
	return {
		"patterns": patterns,
		"projection_artifact_id": projection_artifact_id,
		"cluster_artifact_id": cluster_artifact_id,
		"analysis_run_artifact_id": chosen_run_id,
		"bridge_artifact_id": bridge_artifact_id,
		"hub_artifact_id": hub_artifact_id,
		"hydrated_data": hydrated_data,
		"context_graph_artifact_id": run_ctx_id,
		"method_id": int(methods.get("discovery_method", 0)),
		"dim_id": int(methods.get("dim_method", 0)),
		"clusters_k": int(methods.get("k", 5)),
	}

func _rank_analysis_run_rows(cols: Array, rows: Array) -> Array:
	## Newest-first by created_at (string/ISO or numeric); stable fallback to reverse row order.
	var ranked: Array = []
	for row_any in rows:
		if typeof(row_any) != TYPE_ARRAY:
			continue
		var row: Array = row_any
		var art_id: String = _row_get(cols, row, "id")
		if art_id.is_empty():
			continue
		ranked.append({
			"id": art_id,
			"created_at": _row_get(cols, row, "created_at"),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("created_at", "")) > str(b.get("created_at", ""))
	)
	return ranked

func _item_ids_from_clusters(clusters_arr: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for c_any in clusters_arr:
		if typeof(c_any) != TYPE_DICTIONARY:
			continue
		var ids_any: Variant = (c_any as Dictionary).get("item_ids", [])
		if typeof(ids_any) != TYPE_ARRAY:
			continue
		for iid_any in (ids_any as Array):
			var iid: String = str(iid_any).strip_edges()
			if iid.is_empty() or seen.has(iid):
				continue
			seen[iid] = true
			out.append(iid)
	return out

func _hydrate_items_for_reload(item_ids: Array, existing_data: Array, coords: Dictionary) -> Array:
	var by_id: Dictionary = {}
	for it_any in existing_data:
		if typeof(it_any) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_any
		var iid: String = str(it.get("id", "")).strip_edges()
		if not iid.is_empty():
			by_id[iid] = it
	var out: Array = []
	for iid_any in item_ids:
		var iid: String = str(iid_any).strip_edges()
		if iid.is_empty():
			continue
		if by_id.has(iid):
			out.append(by_id[iid])
			continue
		var content_label: String = iid
		var pos_any: Variant = coords.get(iid, [])
		var meta: Dictionary = {"reloaded_from_analysis": true}
		if typeof(pos_any) == TYPE_ARRAY:
			meta["projection"] = pos_any
		out.append({
			"id": iid,
			"content": content_label,
			"vector": [],
			"metadata": meta,
		})
	return out

func _row_get(cols: Array, row: Array, col_name: String) -> String:
	var idx: int = cols.find(col_name)
	if idx == -1 or idx >= row.size():
		return ""
	return str(row[idx])

# ── Job signal handlers (connect from controller) ────────────────────────

func on_job_progress(job_id: String, payload: Dictionary) -> void:
	if not active_job_ids.has(job_id):
		return
	var stage := str(payload.get("stage", "")).strip_edges()
	var label := str(active_job_ids.get(job_id, "job"))
	if not stage.is_empty():
		_status("Hub job %s (%s): %s…" % [job_id.left(8), label, stage])
	else:
		_status("Hub job %s (%s)…" % [job_id.left(8), label])

func on_job_done(job_id: String, status: String, _payload: Dictionary) -> void:
	if not active_job_ids.has(job_id):
		return
	var label := str(active_job_ids.get(job_id, "job"))
	_status("Hub job %s (%s) %s." % [job_id.left(8), label, status])

# ── Utilities ─────────────────────────────────────────────────────────────

func extract_ids_and_vectors(items: Array) -> Dictionary:
	var item_ids: Array[String] = []
	var vectors: Array = []
	var labels: Dictionary = {}
	for it_any in items:
		if typeof(it_any) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_any
		var iid := str(it.get("id", ""))
		item_ids.append(iid)
		var label := str(it.get("content", "")).strip_edges()
		if not label.is_empty() and not iid.is_empty():
			labels[iid] = label
		if it.has("vector"):
			vectors.append(it.get("vector"))
		elif it.has("embedding"):
			vectors.append(it.get("embedding"))
		else:
			vectors.append(_random_vector(10))
	return {"item_ids": item_ids, "vectors": vectors, "labels": labels}

# ── Internals ─────────────────────────────────────────────────────────────

func _status(msg: String) -> void:
	status_message.emit(msg)

func _empty_result() -> Dictionary:
	return {
		"patterns": [] as Array,
		"projection_artifact_id": "",
		"cluster_artifact_id": "",
		"analysis_run_artifact_id": "",
		"bridge_artifact_id": "",
		"hub_artifact_id": "",
	}

func _random_vector(dim: int) -> Array:
	var v: Array = []
	for _i in range(dim):
		v.append(randf() * 2.0 - 1.0)
	return v

func _labels_map_from_clusters(clusters_arr: Array) -> Dictionary:
	var labels := {}
	for c_any in clusters_arr:
		if typeof(c_any) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_any
		var cid := int(c.get("cluster_id", -1))
		var item_ids_any: Variant = c.get("item_ids", [])
		if cid < 0 or typeof(item_ids_any) != TYPE_ARRAY:
			continue
		for iid_any in (item_ids_any as Array):
			labels[str(iid_any).strip_edges()] = cid
	return labels

func _run_bridges_job(coords: Dictionary, labels: Dictionary, projection_artifact_id: String, cluster_artifact_id: String) -> Dictionary:
	_status("Submitting synaxes.bridges job…")
	var submit: Dictionary = await hub.submit_job(
		"synaxes.bridges",
		{"coords": coords, "labels": labels},
		{},
		{"projection_artifact_id": projection_artifact_id, "cluster_artifact_id": cluster_artifact_id}
	)
	if not bool(submit.get("ok", false)):
		return {"ok": false, "error": submit.get("error", submit)}
	var jid := str(submit.get("id", "")).strip_edges()
	active_job_ids[jid] = "bridges"
	var done: Dictionary = await hub.await_job_done(jid, 60.0)
	active_job_ids.erase(jid)
	if not bool(done.get("ok", false)) or str(done.get("status", "")) != "completed":
		return {"ok": false, "error": done.get("error", done)}
	var payload: Dictionary = done.get("payload", {})
	var artifacts_any: Variant = payload.get("artifacts", [])
	var art_arr: Array = artifacts_any if typeof(artifacts_any) == TYPE_ARRAY else []
	for a_any in art_arr:
		if typeof(a_any) == TYPE_DICTIONARY and str((a_any as Dictionary).get("artifact_type", "")) == "graph.bridge_result":
			return {"ok": true, "artifact_id": str((a_any as Dictionary).get("artifact_id", ""))}
	return {"ok": false, "error": "bridge_result artifact missing"}

func _run_hubs_job(coords: Dictionary, projection_artifact_id: String) -> Dictionary:
	_status("Submitting synaxes.hubs job…")
	var submit: Dictionary = await hub.submit_job(
		"synaxes.hubs",
		{"coords": coords, "k": 8},
		{},
		{"projection_artifact_id": projection_artifact_id}
	)
	if not bool(submit.get("ok", false)):
		return {"ok": false, "error": submit.get("error", submit)}
	var jid := str(submit.get("id", "")).strip_edges()
	active_job_ids[jid] = "hubs"
	var done: Dictionary = await hub.await_job_done(jid, 60.0)
	active_job_ids.erase(jid)
	if not bool(done.get("ok", false)) or str(done.get("status", "")) != "completed":
		return {"ok": false, "error": done.get("error", done)}
	var payload: Dictionary = done.get("payload", {})
	var artifacts_any: Variant = payload.get("artifacts", [])
	var art_arr: Array = artifacts_any if typeof(artifacts_any) == TYPE_ARRAY else []
	for a_any in art_arr:
		if typeof(a_any) == TYPE_DICTIONARY and str((a_any as Dictionary).get("artifact_type", "")) == "graph.hub_result":
			return {"ok": true, "artifact_id": str((a_any as Dictionary).get("artifact_id", ""))}
	return {"ok": false, "error": "hub_result artifact missing"}

func _load_bridges_from_artifact(artifact_id: String) -> Variant:
	var res: Dictionary = await hub.get_artifact_json(artifact_id)
	if not bool(res.get("ok", false)):
		return []
	var json: Dictionary = res.get("json", {})
	return json.get("bridges", [])

func _load_hubs_from_artifact(artifact_id: String) -> Variant:
	var res: Dictionary = await hub.get_artifact_json(artifact_id)
	if not bool(res.get("ok", false)):
		return []
	var json: Dictionary = res.get("json", {})
	return json.get("hubs", [])

func _build_patterns_from_clusters(clusters_arr: Array, item_by_id: Dictionary) -> Array:
	var patterns: Array = []
	for c_any in clusters_arr:
		if typeof(c_any) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_any
		var cid := int(c.get("cluster_id", -1))
		if cid < 0:
			continue
		var center_any: Variant = c.get("center", [])
		var center: Array = center_any if typeof(center_any) == TYPE_ARRAY else []
		var vx := float(center[0]) if center.size() >= 1 else 0.0
		var vy := float(center[1]) if center.size() >= 2 else 0.0
		var vz := float(center[2]) if center.size() >= 3 else 0.0
		var items: Array = []
		var item_ids_any: Variant = c.get("item_ids", [])
		if typeof(item_ids_any) == TYPE_ARRAY:
			for iid_any in (item_ids_any as Array):
				var iid := str(iid_any).strip_edges()
				if item_by_id.has(iid):
					items.append(item_by_id[iid])
		patterns.append({
			"id": cid,
			"type": "cluster",
			"position": Vector3(vx, vy, vz),
			"confidence": float(c.get("confidence", 1.0)),
			"items": items,
			"relations": [],
		})
	return patterns

func _bridge_patterns_from_items(bridges: Array, item_by_id: Dictionary, coords: Dictionary) -> Array:
	var out: Array = []
	var idx := 100000
	for b_any in bridges:
		if typeof(b_any) != TYPE_DICTIONARY:
			continue
		var b: Dictionary = b_any
		var iid := str(b.get("item_id", "")).strip_edges()
		if iid.is_empty() or not item_by_id.has(iid):
			continue
		var pos_any: Variant = coords.get(iid, [])
		var pos_arr: Array = pos_any if typeof(pos_any) == TYPE_ARRAY else []
		var vx := float(pos_arr[0]) if pos_arr.size() >= 1 else 0.0
		var vy := float(pos_arr[1]) if pos_arr.size() >= 2 else 0.0
		var vz := float(pos_arr[2]) if pos_arr.size() >= 3 else 0.0
		out.append({
			"id": idx,
			"type": "bridge",
			"position": Vector3(vx, vy, vz),
			"confidence": float(b.get("score", 0.0)),
			"items": [item_by_id[iid]],
			"relations": [],
			"metadata": b,
		})
		idx += 1
	return out

func _hub_patterns_from_items(hubs_arr: Array, item_by_id: Dictionary, coords: Dictionary) -> Array:
	var out: Array = []
	var idx := 200000
	for h_any in hubs_arr:
		if typeof(h_any) != TYPE_DICTIONARY:
			continue
		var h: Dictionary = h_any
		var iid := str(h.get("item_id", "")).strip_edges()
		if iid.is_empty() or not item_by_id.has(iid):
			continue
		var pos_any: Variant = coords.get(iid, [])
		var pos_arr: Array = pos_any if typeof(pos_any) == TYPE_ARRAY else []
		var vx := float(pos_arr[0]) if pos_arr.size() >= 1 else 0.0
		var vy := float(pos_arr[1]) if pos_arr.size() >= 2 else 0.0
		var vz := float(pos_arr[2]) if pos_arr.size() >= 3 else 0.0
		out.append({
			"id": idx,
			"type": "hub",
			"position": Vector3(vx, vy, vz),
			"confidence": float(h.get("score", 0.0)),
			"items": [item_by_id[iid]],
			"relations": [],
			"metadata": h,
		})
		idx += 1
	return out

func _persist_analysis_run_and_relations(
	item_ids: Array,
	clusters: Array,
	discovery_method_id: int,
	dim_method_id: int,
	k: int,
	context_graph_artifact_id: String,
	projection_artifact_id: String,
	cluster_artifact_id: String,
	bridge_artifact_id: String,
	hub_artifact_id_val: String,
) -> String:
	## Returns analysis_run_artifact_id.
	if context_graph_artifact_id.is_empty() or projection_artifact_id.is_empty() or cluster_artifact_id.is_empty():
		return ""
	var analysis_run := {
		"schema": "synaxes.analysis_run",
		"schema_version": 1,
		"context_graph_artifact_id": context_graph_artifact_id,
		"item_ids": item_ids,
		"methods": {"discovery_method": discovery_method_id, "dim_method": dim_method_id, "k": k},
		"outputs": {
			"projection_artifact_id": projection_artifact_id,
			"cluster_artifact_id": cluster_artifact_id,
			"bridge_artifact_id": bridge_artifact_id,
			"hub_artifact_id": hub_artifact_id_val,
		},
	}
	var analysis_meta := {
		"provenance": {
			"generated_by": "synaxes.analysis_run",
			"inputs": [
				{"type": "artifact", "id": context_graph_artifact_id},
				{"type": "artifact", "id": projection_artifact_id},
				{"type": "artifact", "id": cluster_artifact_id},
			],
			"parameters": {"discovery_method": discovery_method_id, "dim_method": dim_method_id, "k": k, "via": "hub_jobs"},
		}
	}
	var ar_res: Dictionary = await hub.create_artifact_inline_json(ARTIFACT_ANALYSIS_RUN, analysis_run, analysis_meta)
	var analysis_run_artifact_id := ""
	if bool(ar_res.get("ok", false)):
		analysis_run_artifact_id = str(ar_res.get("id", ""))
	await _persist_cluster_membership([], clusters, context_graph_artifact_id, cluster_artifact_id)
	await hub.create_event(
		"synaxes.analysis.persisted",
		{
			"context_graph_artifact_id": context_graph_artifact_id,
			"projection_artifact_id": projection_artifact_id,
			"cluster_artifact_id": cluster_artifact_id,
			"analysis_run_artifact_id": analysis_run_artifact_id,
			"item_count": item_ids.size(),
			"cluster_count": clusters.size(),
			"via": "hub_jobs",
		},
		{"generated_by": "synaxes.hub_jobs"},
		"synaxes",
		seq_fn.call()
	)
	return analysis_run_artifact_id

func _persist_cluster_membership(
	data: Array,
	clusters: Array,
	context_graph_artifact_id: String,
	cluster_artifact_id: String,
) -> void:
	var ids_and_vectors: Dictionary = extract_ids_and_vectors(data) if not data.is_empty() else {"item_ids": [], "labels": {}}
	var labels_any: Variant = ids_and_vectors.get("labels", {})
	var labels: Dictionary = labels_any if typeof(labels_any) == TYPE_DICTIONARY else {}

	var item_ent_ids: Dictionary = {}
	for item_id_any in ids_and_vectors.get("item_ids", []):
		var item_id := str(item_id_any).strip_edges()
		if item_id.is_empty():
			continue
		var ent_name := item_id
		var summary := str(labels.get(item_id, "")).strip_edges()
		var ent_res: Dictionary = await hub.get_or_create_entity(
			ENTITY_CONTEXT_NODE, ent_name, summary, [],
			{"context_graph_artifact_id": context_graph_artifact_id}
		)
		if bool(ent_res.get("ok", false)):
			item_ent_ids[item_id] = str(ent_res.get("id", ""))

	for c_any in clusters:
		if typeof(c_any) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_any
		var cid := int(c.get("cluster_id", -1))
		if cid < 0:
			continue
		var cname := "%s::cluster_%d" % [context_graph_artifact_id, cid]
		var cent_res: Dictionary = await hub.get_or_create_entity(
			ENTITY_CLUSTER, cname, "SynAxes cluster %d" % cid, [],
			{
				"context_graph_artifact_id": context_graph_artifact_id,
				"cluster_result_artifact_id": cluster_artifact_id,
			}
		)
		if not bool(cent_res.get("ok", false)):
			continue
		var cluster_ent_id := str(cent_res.get("id", ""))

		var c_item_ids_any: Variant = c.get("item_ids", [])
		if typeof(c_item_ids_any) != TYPE_ARRAY:
			continue
		for it_any in (c_item_ids_any as Array):
			var item_id := str(it_any).strip_edges()
			if item_id.is_empty():
				continue
			var from_ent_id := str(item_ent_ids.get(item_id, ""))
			if from_ent_id.is_empty():
				continue
			await hub.create_relation(
				REL_MEMBER_OF_CLUSTER, from_ent_id, cluster_ent_id, 0.0,
				{
					"context_graph_artifact_id": context_graph_artifact_id,
					"cluster_result_artifact_id": cluster_artifact_id,
					"cluster_id": cid,
				}
			)
