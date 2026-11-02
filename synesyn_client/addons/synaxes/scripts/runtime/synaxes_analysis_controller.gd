extends RefCounted
## Discovery / analysis orchestration for SynAxes.
##
## Runs local or hub-job discovery, persists analysis artifacts, updates optional
## PatternViewer UI, and builds the Dream Inbox when a closure controller is wired.
## Safe for headless use when UI refs are left null (Phase F seam).

signal analysis_status(msg: String)
signal discovery_completed(result: Dictionary)

const DiscoveryEngine = preload("res://addons/synaxes/scripts/integration/discovery_engine.gd")
const TextEmbedderScript = preload("res://addons/synaxes/scripts/data_processing/text_embedder.gd")
const EmbeddingCacheScript = preload("res://addons/synaxes/scripts/data_processing/embedding_cache.gd")

# Dependencies — set by the runtime controller after construction.
var engine: DiscoveryEngine
var pipeline  # HubPipelineScript (RefCounted)
var closure_ctrl  # ClosureControllerScript (optional)
var text_embedder: RefCounted  # TextEmbedderScript
var embed_cache: RefCounted  # EmbeddingCacheScript
var host_node: Node  # parents HTTPRequest nodes for Tier 3

# Optional UI (bound via bind_ui; null-safe for headless)
var discovery_method: OptionButton
var dim_method: OptionButton
var clusters_slider: HSlider
var pattern_viewer: Node
var bottom_tabs: TabContainer

# State fallbacks when UI is null (also mirrors last UI selection after discover)
var method_id: int = 0
var dim_id: int = 0
var clusters_k: int = 5
var use_hub_jobs: bool = false
## Preference to use model embeddings when consented for the active provider.
## Never auto-enable; Tier 3 also requires per-provider consent (REQ-NDP-006).
var use_hub_embeddings: bool = false
var embedding_tier: String = ""  # "tier2_tfidf", "tier3_model", "tier3_hub", …

# Last discovery result / provenance artifact ids
var last_patterns: Array = []
var last_projection_artifact_id: String = ""
var last_cluster_artifact_id: String = ""
var last_analysis_run_artifact_id: String = ""
var last_bridge_artifact_id: String = ""
var last_hub_artifact_id: String = ""
var last_discover_item_count: int = 0

const _CFG_APP_ID := "synaxes"
const _CFG_CONSENT_BY_PROVIDER := "embedding_consent_by_provider"


func ensure_engine() -> void:
	if engine == null:
		engine = DiscoveryEngine.new()
	if text_embedder == null:
		text_embedder = TextEmbedderScript.new()
	if embed_cache == null:
		embed_cache = EmbeddingCacheScript.new()


func bind_ui(refs: Dictionary) -> void:
	discovery_method = refs.get("discovery_method") as OptionButton
	dim_method = refs.get("dim_method") as OptionButton
	clusters_slider = refs.get("clusters_slider") as HSlider
	pattern_viewer = refs.get("pattern_viewer") as Node
	bottom_tabs = refs.get("bottom_tabs") as TabContainer


func clear_viewer() -> void:
	if pattern_viewer and pattern_viewer.has_method("clear_patterns"):
		pattern_viewer.clear_patterns()


func get_discovery_params() -> Dictionary:
	## Resolve method / dim / k from UI when present, else from cached state.
	var resolved_method: int = method_id
	var resolved_dim: int = dim_id
	var resolved_k: int = clusters_k
	if discovery_method:
		resolved_method = discovery_method.selected
	if dim_method:
		resolved_dim = dim_method.selected
	if clusters_slider:
		resolved_k = int(clusters_slider.value)
	method_id = resolved_method
	dim_id = resolved_dim
	clusters_k = resolved_k
	return {
		"method_id": resolved_method,
		"dim_id": resolved_dim,
		"clusters_k": resolved_k,
	}


func import_embed_discover(
	source_data: Array,
	context_graph_artifact_id: String = "",
	opts: Dictionary = {},
) -> Dictionary:
	## Headless Import → embed → discover (REQ-NDP-024). No UI required.
	## Tier 3 only when preference + recorded per-provider consent; else Tier 2.
	ensure_engine()
	if source_data.is_empty():
		_status("No source_data for headless discover.")
		return _empty_result()
	if opts.has("method"):
		method_id = int(opts.get("method", method_id))
	if opts.has("dim_method"):
		dim_id = int(opts.get("dim_method", dim_id))
	if opts.has("num_clusters"):
		clusters_k = int(opts.get("num_clusters", clusters_k))
	if opts.has("use_hub_jobs"):
		use_hub_jobs = bool(opts.get("use_hub_jobs", false))
	# Preference may be requested, but apply_embeddings still gates on consent.
	use_hub_embeddings = bool(opts.get("use_hub_embeddings", use_hub_embeddings))
	var data: Array = source_data.duplicate(true)
	data = await apply_embeddings(data, context_graph_artifact_id)
	return await discover(data, context_graph_artifact_id, data)


func reload_last_analysis(
	context_graph_artifact_id: String = "",
	existing_data: Array = [],
) -> Dictionary:
	## REQ-NDP-017: hydrate Pattern Space from Hub analysis artifacts (no re-discover).
	if pipeline == null:
		_status("Hub pipeline unavailable — cannot reload last analysis.")
		return _empty_result()
	var hub_result: Dictionary = await pipeline.reload_last_analysis(
		context_graph_artifact_id, existing_data
	)
	var patterns: Array = hub_result.get("patterns", [])
	if patterns.is_empty():
		return _empty_result()
	_apply_artifact_ids(hub_result)
	if hub_result.has("method_id"):
		method_id = int(hub_result.get("method_id", method_id))
	if hub_result.has("dim_id"):
		dim_id = int(hub_result.get("dim_id", dim_id))
	if hub_result.has("clusters_k"):
		clusters_k = int(hub_result.get("clusters_k", clusters_k))
	_populate_pattern_viewer(patterns)
	var hydrated: Array = hub_result.get("hydrated_data", [])
	last_discover_item_count = hydrated.size() if not hydrated.is_empty() else existing_data.size()
	var theme_count: int = _count_theme_patterns(patterns)
	_status(human_discover_summary(theme_count, last_discover_item_count))
	if bottom_tabs and bottom_tabs.get_tab_count() > 0:
		bottom_tabs.current_tab = 0
	if closure_ctrl:
		var dream_source: Array = hydrated if not hydrated.is_empty() else existing_data
		closure_ctrl.all_data = dream_source
		closure_ctrl.build_dream_inbox_from_patterns(patterns)
	var result: Dictionary = {
		"patterns": patterns,
		"projection_artifact_id": last_projection_artifact_id,
		"cluster_artifact_id": last_cluster_artifact_id,
		"analysis_run_artifact_id": last_analysis_run_artifact_id,
		"bridge_artifact_id": last_bridge_artifact_id,
		"hub_artifact_id": last_hub_artifact_id,
		"method_id": method_id,
		"dim_id": dim_id,
		"clusters_k": clusters_k,
		"theme_count": theme_count,
		"item_count": last_discover_item_count,
		"themes_source": themes_source_plain(),
		"hydrated_data": hydrated,
		"context_graph_artifact_id": str(hub_result.get("context_graph_artifact_id", "")),
		"reloaded": true,
	}
	discovery_completed.emit(result)
	return result


func discover(active_data: Array, context_graph_artifact_id: String = "", all_data: Array = []) -> Dictionary:
	## Run discovery on active_data, persist, update optional UI, build dream inbox.
	## Returns a result Dictionary (same shape as discovery_completed).
	ensure_engine()
	if active_data.is_empty():
		_status("No items selected. Check the Imported Data tab and select items to analyse.")
		return _empty_result()

	engine.set_data(active_data)
	var params: Dictionary = get_discovery_params()
	var resolved_method: int = int(params.get("method_id", 0))
	var resolved_dim: int = int(params.get("dim_id", 0))
	var resolved_k: int = int(params.get("clusters_k", 5))

	var patterns: Array = []
	if use_hub_jobs and pipeline:
		var hub_result: Dictionary = await pipeline.discover_via_hub_jobs(
			active_data, context_graph_artifact_id, resolved_method, resolved_dim, resolved_k
		)
		patterns = hub_result.get("patterns", [])
		_apply_artifact_ids(hub_result)
	else:
		_status("Discovering patterns on %d selected items…" % active_data.size())
		patterns = engine.discover_patterns(resolved_method, resolved_dim, resolved_k)
		last_patterns = patterns
		if pipeline:
			var persist_result: Dictionary = await pipeline.persist_analysis_results_to_hub(
				patterns, active_data, context_graph_artifact_id,
				resolved_method, resolved_dim, resolved_k
			)
			last_projection_artifact_id = str(persist_result.get("projection_artifact_id", ""))
			last_cluster_artifact_id = str(persist_result.get("cluster_artifact_id", ""))
			last_analysis_run_artifact_id = str(persist_result.get("analysis_run_artifact_id", ""))

	_populate_pattern_viewer(patterns)
	last_discover_item_count = active_data.size()
	var theme_count: int = _count_theme_patterns(patterns)
	_status(human_discover_summary(theme_count, active_data.size()))

	if bottom_tabs and bottom_tabs.get_tab_count() > 0:
		bottom_tabs.current_tab = 0

	if closure_ctrl:
		var dream_source: Array = all_data if not all_data.is_empty() else active_data
		closure_ctrl.all_data = dream_source
		closure_ctrl.build_dream_inbox_from_patterns(patterns)

	var result: Dictionary = {
		"patterns": patterns,
		"projection_artifact_id": last_projection_artifact_id,
		"cluster_artifact_id": last_cluster_artifact_id,
		"analysis_run_artifact_id": last_analysis_run_artifact_id,
		"bridge_artifact_id": last_bridge_artifact_id,
		"hub_artifact_id": last_hub_artifact_id,
		"method_id": resolved_method,
		"dim_id": resolved_dim,
		"clusters_k": resolved_k,
		"theme_count": theme_count,
		"item_count": active_data.size(),
		"themes_source": themes_source_plain(),
	}
	discovery_completed.emit(result)
	return result


func provenance_snapshot(context_graph_artifact_id: String = "") -> Dictionary:
	## Compact provenance fields for commit / display consumers.
	return {
		"context_graph_artifact_id": context_graph_artifact_id,
		"projection_artifact_id": last_projection_artifact_id,
		"cluster_artifact_id": last_cluster_artifact_id,
		"analysis_run_artifact_id": last_analysis_run_artifact_id,
		"bridge_artifact_id": last_bridge_artifact_id,
		"hub_artifact_id": last_hub_artifact_id,
		"discovery_method": method_id if discovery_method == null else discovery_method.selected,
		"dim_method": dim_id if dim_method == null else dim_method.selected,
		"clusters_count": clusters_k if clusters_slider == null else int(clusters_slider.value),
		"embedding_tier_label": embedding_tier_label(),
		"via_hub_jobs": use_hub_jobs,
	}


# ── Embedding tiers ───────────────────────────────────────────────────────

func apply_embeddings(data: Array, context_graph_artifact_id: String = "") -> Array:
	## Applies the best available embedding tier; returns the (possibly mutated) data.
	## Tier 3 (model): only when preference is on AND per-provider consent exists.
	## Headless / no consent → Tier 2 (REQ-NDP-006 / REQ-NDP-024).
	ensure_engine()
	if data.is_empty():
		return data

	if (not use_hub_embeddings) and _data_has_vectors(data):
		embedding_tier = "tier3_hub"
		_status("Using imported embeddings (model themes).")
		return data

	if use_hub_embeddings and can_use_model_embeddings():
		var did_tier3: bool = await _try_tier3_model_embeddings(data, context_graph_artifact_id)
		if did_tier3:
			return data
		_status("Model themes unavailable — using local themes.")
	elif use_hub_embeddings:
		_status("Model themes need disclosed consent for the active provider — using local themes.")

	_apply_tier2_tfidf(data)
	return data


func embedding_tier_label() -> String:
	## Plain-language status for UI (REQ-NDP-006). Advanced still shows method detail.
	match embedding_tier:
		"tier3_hub":
			return "Model themes (imported)"
		"tier3_model":
			return "Model themes"
		"tier2_tfidf":
			return "Local themes"
		_:
			return "Local themes (pending)"


func themes_source_plain() -> String:
	## "local" | "model" for discover summary (REQ-NDP-010).
	if embedding_tier == "tier3_model" or embedding_tier == "tier3_hub":
		return "model"
	return "local"


func human_discover_summary(theme_count: int, item_count: int) -> String:
	## REQ-NDP-010: "N themes from M items · themes: local|model"
	return "%d themes from %d items · themes: %s" % [
		theme_count, item_count, themes_source_plain()
	]


func probe_embed_capability() -> Dictionary:
	## Returns {capable, provider, model} for the active SynTree model. No network.
	var empty: Dictionary = {"capable": false, "provider": "", "model": ""}
	var pm_node: Node = _get_plugin_manager()
	if not pm_node or not pm_node.has_method("get_ai_model_manager"):
		return empty
	var ai_manager = pm_node.get_ai_model_manager()
	if not ai_manager:
		return empty
	var current_model: String = str(ai_manager.get_current_model()) if ai_manager.has_method("get_current_model") else ""
	if current_model.is_empty():
		return empty
	var provider_name: String = ""
	if ai_manager.has_method("get_provider_for_model"):
		provider_name = str(ai_manager.get_provider_for_model(current_model))
	if provider_name.is_empty():
		return empty
	var loader = ai_manager.get_provider_loader(provider_name) if ai_manager.has_method("get_provider_loader") else null
	if not loader or not loader.has_method("supports_embeddings") or not loader.supports_embeddings():
		return empty
	return {"capable": true, "provider": provider_name, "model": current_model}


func has_provider_consent(provider_name: String) -> bool:
	var key: String = provider_name.strip_edges().to_lower()
	if key.is_empty():
		return false
	var consents: Dictionary = _load_consent_map()
	return bool(consents.get(key, false))


func set_provider_consent(provider_name: String, is_accepted: bool) -> void:
	var key: String = provider_name.strip_edges().to_lower()
	if key.is_empty():
		return
	var consents: Dictionary = _load_consent_map()
	consents[key] = is_accepted
	_save_consent_map(consents)


func can_use_model_embeddings() -> bool:
	## Preference + capability + remembered consent for the active provider.
	if not use_hub_embeddings:
		return false
	var cap: Dictionary = probe_embed_capability()
	if not bool(cap.get("capable", false)):
		return false
	return has_provider_consent(str(cap.get("provider", "")))


func opt_in_model_themes_for_active_provider() -> Dictionary:
	## One-click disclosed consent path. Returns capability dict (may be empty).
	var cap: Dictionary = probe_embed_capability()
	if not bool(cap.get("capable", false)):
		return cap
	var provider_name: String = str(cap.get("provider", ""))
	set_provider_consent(provider_name, true)
	use_hub_embeddings = true
	return cap


func disclosed_opt_in_label() -> String:
	## Button / dialog text naming the destination provider (REQ-NDP-006).
	var cap: Dictionary = probe_embed_capability()
	if not bool(cap.get("capable", false)):
		return ""
	var provider_name: String = str(cap.get("provider", ""))
	return "Use model themes — sends item text to %s" % provider_name


func cache_entry_count() -> int:
	ensure_engine()
	return int(embed_cache.entry_count())


func _apply_tier2_tfidf(data: Array) -> void:
	var texts: Array = []
	for it_any in data:
		if typeof(it_any) == TYPE_DICTIONARY:
			texts.append(str((it_any as Dictionary).get("content", "")))
		else:
			texts.append("")
	var vectors: Array = text_embedder.embed_batch(texts, 64)
	for i in range(mini(data.size(), vectors.size())):
		if typeof(data[i]) == TYPE_DICTIONARY:
			var it: Dictionary = (data[i] as Dictionary).duplicate()
			it["vector"] = vectors[i]
			data[i] = it
	embedding_tier = "tier2_tfidf"


func _try_tier3_model_embeddings(data: Array, context_graph_artifact_id: String) -> bool:
	## Attempts to embed data using SynTree's current AI model.
	## Caller must have verified preference + per-provider consent (no silent egress).
	var cap: Dictionary = probe_embed_capability()
	if not bool(cap.get("capable", false)):
		return false
	var provider_name: String = str(cap.get("provider", ""))
	var current_model: String = str(cap.get("model", ""))
	if not has_provider_consent(provider_name):
		return false
	var pm_node: Node = _get_plugin_manager()
	if not pm_node:
		return false
	var ai_manager = pm_node.get_ai_model_manager()
	if not ai_manager:
		return false
	var loader = ai_manager.get_provider_loader(provider_name)
	if not loader or not loader.has_method("supports_embeddings") or not loader.supports_embeddings():
		return false

	_status("Model themes: requesting embeddings from %s (%s)…" % [current_model, provider_name])

	var model_id: String = "%s/%s" % [provider_name, current_model]
	var texts: Array = []
	for it_any in data:
		if typeof(it_any) == TYPE_DICTIONARY:
			texts.append(str((it_any as Dictionary).get("content", "")))
		else:
			texts.append("")

	var cached: Dictionary = embed_cache.get_cached_batch(texts, model_id, 0)
	var uncached_indices: Array = []
	var uncached_texts: Array = []
	for i in range(texts.size()):
		if cached.has(i) and cached[i] != null:
			continue
		uncached_indices.append(i)
		uncached_texts.append(texts[i])

	var cache_hits: int = texts.size() - uncached_texts.size()
	if cache_hits > 0:
		_status("Model themes: %d/%d cached. Requesting %d from %s…" % [
			cache_hits, texts.size(), uncached_texts.size(), provider_name])

	var new_vectors: Array = []
	if not uncached_texts.is_empty():
		if host_node == null:
			return false
		var api_key: String = ai_manager.get_api_key(provider_name)
		var url: String = loader.get_embeddings_url(api_key)
		if url.is_empty():
			return false
		var req_headers: PackedStringArray = loader.get_embeddings_headers(api_key)
		var body: Dictionary = loader.prepare_embeddings_request(uncached_texts)
		var body_json: String = JSON.stringify(body)

		var http_req: HTTPRequest = HTTPRequest.new()
		host_node.add_child(http_req)
		var err: int = http_req.request(url, req_headers, HTTPClient.METHOD_POST, body_json)
		if err != OK:
			http_req.queue_free()
			_status("Model themes: HTTP request failed (err %d)." % err)
			return false
		var completed: Array = await http_req.request_completed
		http_req.queue_free()
		var response_code: int = int(completed[1])
		var response_body: PackedByteArray = completed[3]
		if response_code < 200 or response_code >= 300:
			_status("Model themes: provider returned HTTP %d." % response_code)
			return false

		var parsed: Variant = JSON.parse_string(response_body.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			_status("Model themes: could not parse provider response.")
			return false
		new_vectors = loader.parse_embeddings_response(parsed as Dictionary)
		if new_vectors.size() != uncached_texts.size():
			_status("Model themes: got %d vectors for %d items — mismatch." % [
				new_vectors.size(), uncached_texts.size()])
			return false

		var dim_size: int = 0
		if not new_vectors.is_empty():
			dim_size = int(new_vectors[0].size())
		embed_cache.put_cached_batch(uncached_texts, new_vectors, model_id, dim_size)
		embed_cache.save()

	var new_vec_idx: int = 0
	for i in range(data.size()):
		if typeof(data[i]) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = (data[i] as Dictionary).duplicate()
		if cached.has(i) and cached[i] != null:
			it["vector"] = cached[i]
		elif new_vec_idx < new_vectors.size():
			it["vector"] = new_vectors[new_vec_idx]
			new_vec_idx += 1
		data[i] = it
	embedding_tier = "tier3_model"
	_status("Model themes ready (%s, %d items, %d cached)." % [model_id, data.size(), cache_hits])

	if pipeline:
		await pipeline.persist_embedding_artifact(
			data, context_graph_artifact_id, embedding_tier, provider_name, current_model
		)
	return true


func _get_plugin_manager() -> Node:
	if Engine.has_singleton("PluginManager"):
		return Engine.get_singleton("PluginManager") as Node
	if host_node:
		var tree: SceneTree = host_node.get_tree()
		if tree:
			return tree.root.get_node_or_null("PluginManager")
	return null


func _data_has_vectors(data: Array) -> bool:
	for it_any in data:
		if typeof(it_any) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_any
		var vec_any: Variant = it.get("vector", null)
		if typeof(vec_any) == TYPE_ARRAY and (vec_any as Array).size() > 0:
			return true
	return false


func _populate_pattern_viewer(patterns: Array) -> void:
	var pv: Node = pattern_viewer
	if pv == null or not pv.has_method("display_patterns"):
		return
	var pg: Node = pv.get_node_or_null("PatternGraph")
	if pg:
		pg.clear()
		for p_any in patterns:
			if typeof(p_any) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_any
			var pnode = pg.PatternNode.new(p.get("id", -1))
			pnode.pattern_type = str(p.get("type", "Generic")).capitalize()
			pnode.position = p.get("position", Vector3.ZERO)
			pnode.items = p.get("items", [])
			pnode.confidence = float(p.get("confidence", 0.5))
			pnode.metadata = p
			pg.add_pattern(pnode)
	pv.display_patterns(patterns)


func _apply_artifact_ids(hub_result: Dictionary) -> void:
	last_projection_artifact_id = str(hub_result.get("projection_artifact_id", ""))
	last_cluster_artifact_id = str(hub_result.get("cluster_artifact_id", ""))
	last_analysis_run_artifact_id = str(hub_result.get("analysis_run_artifact_id", ""))
	last_bridge_artifact_id = str(hub_result.get("bridge_artifact_id", ""))
	last_hub_artifact_id = str(hub_result.get("hub_artifact_id", ""))
	last_patterns = hub_result.get("patterns", [])


func _empty_result() -> Dictionary:
	return {
		"patterns": [],
		"projection_artifact_id": "",
		"cluster_artifact_id": "",
		"analysis_run_artifact_id": "",
		"bridge_artifact_id": "",
		"hub_artifact_id": "",
		"method_id": method_id,
		"dim_id": dim_id,
		"clusters_k": clusters_k,
	}


func _count_theme_patterns(patterns: Array) -> int:
	var theme_count: int = 0
	for p_any in patterns:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var ptype: String = str((p_any as Dictionary).get("type", "")).to_lower()
		if ptype == "cluster" or ptype == "pattern" or ptype.is_empty():
			theme_count += 1
	if theme_count == 0:
		return patterns.size()
	return theme_count


func _load_consent_map() -> Dictionary:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	var apps: Dictionary = apps_any if typeof(apps_any) == TYPE_DICTIONARY else {}
	var syn_any: Variant = apps.get(_CFG_APP_ID, {})
	var syn_cfg: Dictionary = syn_any if typeof(syn_any) == TYPE_DICTIONARY else {}
	var consents_any: Variant = syn_cfg.get(_CFG_CONSENT_BY_PROVIDER, {})
	if typeof(consents_any) != TYPE_DICTIONARY:
		return {}
	return (consents_any as Dictionary).duplicate()


func _save_consent_map(consents: Dictionary) -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	var apps: Dictionary = apps_any if typeof(apps_any) == TYPE_DICTIONARY else {}
	var syn_any: Variant = apps.get(_CFG_APP_ID, {})
	var syn_cfg: Dictionary = syn_any if typeof(syn_any) == TYPE_DICTIONARY else {}
	syn_cfg[_CFG_CONSENT_BY_PROVIDER] = consents
	apps[_CFG_APP_ID] = syn_cfg
	cfg["apps"] = apps
	RuntimeConfig.save_config(cfg)


func _status(msg: String) -> void:
	analysis_status.emit(msg)
