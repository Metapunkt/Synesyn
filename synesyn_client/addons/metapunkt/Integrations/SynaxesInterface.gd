extends ToolInterfaceBase
class_name SynaxesInterface

## SLOP /tools adapter for SynAxes pattern-discovery + closure formation.
##
## Operations:
##   discover_patterns    - headless embed → discover → Dream Inbox candidates
##   get_dream_candidates - list Dream Inbox candidates from last discovery
##   select_candidate     - select candidate by index (no dock ItemList required)
##   commit_closure       - commit selected/overridden candidate to Hub
##   get_status           - return current engine state (pattern/candidate counts)
##   clear                - reset engine + candidate state

const DiscoveryEngineScript = preload("res://addons/synaxes/scripts/integration/discovery_engine.gd")
const ClosureControllerScript = preload("res://addons/synaxes/scripts/runtime/synaxes_closure_controller.gd")
const AnalysisControllerScript = preload("res://addons/synaxes/scripts/runtime/synaxes_analysis_controller.gd")
const HubPipelineScript = preload("res://addons/synaxes/scripts/runtime/synaxes_hub_pipeline.gd")
const HubSubstrateClient = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")

var _engine: RefCounted = null
var _closure_ctrl: RefCounted = null
var _analysis_ctrl: RefCounted = null
var _pipeline: RefCounted = null
var _hub: HubSubstrateClient = null
var _seq: int = 1
var _last_patterns: Array = []


func _init():
	_engine = DiscoveryEngineScript.new()
	_closure_ctrl = ClosureControllerScript.new()
	_closure_ctrl.seq_fn = Callable(self, "_next_seq")
	_analysis_ctrl = AnalysisControllerScript.new()
	_analysis_ctrl.closure_ctrl = _closure_ctrl
	_analysis_ctrl.ensure_engine()
	# Keep legacy engine pointer aligned for get_status / clear.
	_analysis_ctrl.engine = _engine


func get_tool_name() -> String:
	return "Synaxes"


func get_description() -> String:
	return "SynAxes pattern discovery and closure formation tool. Supports local clustering, bridge analysis, hub identification, Dream Inbox candidates, and Hub closure commit."


func get_operations() -> Array[String]:
	return [
		"discover_patterns",
		"get_dream_candidates",
		"select_candidate",
		"commit_closure",
		"get_status",
		"clear",
	]


func get_input_schema() -> Dictionary:
	return {
		"schema_version": 1,
		"type": "object",
		"properties": {
			"operation": {
				"type": "string",
				"description": "Operation name (discover_patterns / get_dream_candidates / select_candidate / commit_closure / get_status / clear).",
			},
			"source_data": {
				"type": "array",
				"description": "Array of item dicts with optional 'vector'/'embedding' and 'content'/'metadata'. Required for discover_patterns.",
			},
			"method": {
				"type": "integer",
				"description": "Discovery method: 0=Clustering, 1=BridgeAnalysis, 2=HubIdentification. Default 0.",
			},
			"dim_method": {
				"type": "integer",
				"description": "Dimensionality reduction: 0=PCA, 1=tSNE, 2=UMAP. Default 0.",
			},
			"num_clusters": {
				"type": "integer",
				"description": "Number of clusters (for Clustering method). Default 5.",
			},
			"use_hub_embeddings": {
				"type": "boolean",
				"description": "Request model embeddings. Still requires recorded per-provider consent; otherwise Tier 2 local themes (REQ-NDP-006/024).",
			},
			"use_hub_jobs": {
				"type": "boolean",
				"description": "Run discovery via Hub jobs when a context_graph_artifact_id is supplied. Default false.",
			},
			"context_graph_artifact_id": {
				"type": "string",
				"description": "Optional Hub context graph id for provenance / Hub jobs.",
			},
			"candidate_idx": {
				"type": "integer",
				"description": "Dream Inbox candidate index for select_candidate / commit_closure.",
			},
			"name": {
				"type": "string",
				"description": "Optional closure name override for commit_closure.",
			},
			"intent": {
				"type": "string",
				"description": "Optional closure intent override for commit_closure.",
			},
			"orientation": {
				"type": "string",
				"description": "Optional Closure Map quadrant A–D for commit_closure.",
			},
			"item_ids": {
				"type": "array",
				"description": "Optional item id list override for commit_closure.",
			},
			"provenance": {
				"type": "object",
				"description": "Optional provenance_ctx for commit_closure (context_graph / analysis artifact ids).",
			},
			"overrides": {
				"type": "object",
				"description": "Optional overrides dictionary passed through to commit_closure.",
			},
		},
		"required": ["operation"],
	}


func execute_tool(args: Dictionary) -> Dictionary:
	var operation: String = args.get("operation", "")

	match operation:
		"discover_patterns":
			return await _handle_discover(args)
		"get_dream_candidates":
			return _handle_get_dream_candidates()
		"select_candidate":
			return _handle_select_candidate(args)
		"commit_closure":
			return await _handle_commit_closure(args)
		"get_status":
			return _handle_get_status()
		"clear":
			return _handle_clear()
		_:
			return {"ok": false, "error": "Unknown operation: " + operation}


func _handle_discover(args: Dictionary) -> Dictionary:
	## Headless import → embed → discover via analysis controller (no dock UI).
	## No recorded Tier 3 consent → Tier 2 only (REQ-NDP-024).
	if not _analysis_ctrl:
		return {"ok": false, "error": "Analysis controller not initialised"}

	var source_data_any: Variant = args.get("source_data", [])
	if typeof(source_data_any) != TYPE_ARRAY or (source_data_any as Array).is_empty():
		return {"ok": false, "error": "source_data must be a non-empty Array of item dicts"}

	var source_data: Array = source_data_any
	var context_graph_artifact_id: String = str(args.get("context_graph_artifact_id", "")).strip_edges()
	var opts: Dictionary = {
		"method": int(args.get("method", 0)),
		"dim_method": int(args.get("dim_method", 0)),
		"num_clusters": int(args.get("num_clusters", 5)),
		"use_hub_embeddings": bool(args.get("use_hub_embeddings", false)),
		"use_hub_jobs": bool(args.get("use_hub_jobs", false)),
	}

	# Optional Hub pipeline for persistence / hub jobs (best-effort).
	if bool(opts.get("use_hub_jobs", false)) or not context_graph_artifact_id.is_empty():
		if _ensure_hub_ready():
			_ensure_pipeline()

	# Parent analysis HTTPRequest nodes under the hub (or scene root) when possible.
	if _analysis_ctrl.host_node == null and _hub != null:
		_analysis_ctrl.host_node = _hub

	var result: Dictionary = await _analysis_ctrl.import_embed_discover(
		source_data, context_graph_artifact_id, opts
	)
	var patterns: Array = result.get("patterns", [])
	_last_patterns = patterns
	if _engine:
		_engine.set_data(source_data)
		_engine._patterns.clear()
		for pattern_any in patterns:
			if typeof(pattern_any) != TYPE_DICTIONARY:
				continue
			var pattern: Dictionary = pattern_any
			_engine._patterns[pattern.get("id", -1)] = pattern

	var candidate_count: int = 0
	if _closure_ctrl:
		candidate_count = _closure_ctrl.get_dream_candidates().size()

	if patterns.is_empty():
		return {
			"ok": false,
			"error": "Discovery produced no patterns",
			"result": {
				"pattern_count": 0,
				"candidate_count": candidate_count,
				"embedding_tier": _analysis_ctrl.embedding_tier_label(),
				"themes_source": _analysis_ctrl.themes_source_plain(),
			},
		}

	return {
		"ok": true,
		"result": {
			"pattern_count": patterns.size(),
			"patterns": patterns,
			"candidate_count": candidate_count,
			"embedding_tier": _analysis_ctrl.embedding_tier_label(),
			"themes_source": _analysis_ctrl.themes_source_plain(),
			"analysis_run_artifact_id": str(result.get("analysis_run_artifact_id", "")),
			"projection_artifact_id": str(result.get("projection_artifact_id", "")),
			"cluster_artifact_id": str(result.get("cluster_artifact_id", "")),
		},
	}


func _handle_get_dream_candidates() -> Dictionary:
	if not _closure_ctrl:
		return {"ok": false, "error": "Closure controller not initialised"}
	var candidates: Array = _closure_ctrl.get_dream_candidates()
	return {
		"ok": true,
		"result": {
			"candidate_count": candidates.size(),
			"candidates": candidates,
			"active_candidate_idx": int(_closure_ctrl.active_candidate_idx),
		},
	}


func _handle_select_candidate(args: Dictionary) -> Dictionary:
	if not _closure_ctrl:
		return {"ok": false, "error": "Closure controller not initialised"}
	if not args.has("candidate_idx"):
		return {"ok": false, "error": "candidate_idx is required"}
	var idx: int = int(args.get("candidate_idx", -1))
	var did_select: bool = bool(_closure_ctrl.select_candidate(idx))
	if not did_select:
		return {"ok": false, "error": "candidate_idx out of range"}
	return {
		"ok": true,
		"result": {
			"active_candidate_idx": idx,
			"candidate": _closure_ctrl.dream_candidates[idx] if idx < _closure_ctrl.dream_candidates.size() else {},
		},
	}


func _handle_commit_closure(args: Dictionary) -> Dictionary:
	if not _closure_ctrl:
		return {"ok": false, "error": "Closure controller not initialised"}
	if not _ensure_hub_ready():
		return {"ok": false, "error": "Hub client unavailable"}

	var provenance_any: Variant = args.get("provenance", {})
	var provenance_ctx: Dictionary = provenance_any if typeof(provenance_any) == TYPE_DICTIONARY else {}

	var overrides_any: Variant = args.get("overrides", {})
	var overrides: Dictionary = overrides_any if typeof(overrides_any) == TYPE_DICTIONARY else {}
	# Allow top-level shorthand args without nesting under overrides.
	for key_name in ["name", "intent", "orientation", "orientation_quadrant", "item_ids", "time_start", "time_end", "candidate_idx"]:
		if args.has(key_name) and not overrides.has(key_name):
			overrides[key_name] = args.get(key_name)

	var commit_res: Dictionary = await _closure_ctrl.commit_closure(provenance_ctx, overrides)
	if bool(commit_res.get("ok", false)):
		return {"ok": true, "result": commit_res}
	return {"ok": false, "error": str(commit_res.get("error", commit_res))}


func _ensure_hub_ready() -> bool:
	## HubSubstrateClient is a Node (HTTPRequest children). Parent it under the
	## scene tree when the ToolInterfaceBase host is not itself a Node.
	if _hub == null:
		_hub = HubSubstrateClient.new()
		_hub.configure_from_runtime_config()
		_closure_ctrl.hub = _hub
	if _hub.get_parent() != null:
		return true
	var tree_ref: SceneTree = Engine.get_main_loop() as SceneTree
	if tree_ref == null or tree_ref.root == null:
		return false
	tree_ref.root.add_child(_hub)
	return true


func _ensure_pipeline() -> void:
	if _pipeline != null or _hub == null or _analysis_ctrl == null:
		return
	_pipeline = HubPipelineScript.new()
	_pipeline.hub = _hub
	_pipeline.seq_fn = Callable(self, "_next_seq")
	_analysis_ctrl.pipeline = _pipeline


func _handle_get_status() -> Dictionary:
	if not _engine:
		return {"ok": false, "error": "DiscoveryEngine not initialised"}

	var candidate_count: int = 0
	var active_idx: int = -1
	if _closure_ctrl:
		candidate_count = _closure_ctrl.dream_candidates.size()
		active_idx = int(_closure_ctrl.active_candidate_idx)

	return {
		"ok": true,
		"result": {
			"data_count": _engine._data.size(),
			"pattern_count": _engine._patterns.size(),
			"candidate_count": candidate_count,
			"active_candidate_idx": active_idx,
			"last_pattern_count": _last_patterns.size(),
			"embedding_tier": _analysis_ctrl.embedding_tier_label() if _analysis_ctrl else "",
		},
	}


func _handle_clear() -> Dictionary:
	if _engine:
		_engine._data.clear()
		_engine._patterns.clear()
	_last_patterns.clear()
	if _analysis_ctrl:
		_analysis_ctrl.last_patterns = []
		_analysis_ctrl.clear_viewer()
	if _closure_ctrl:
		_closure_ctrl.dream_candidates.clear()
		_closure_ctrl.active_candidate_idx = -1

	return {
		"ok": true,
		"result": {"status": "cleared"},
	}


func _next_seq() -> int:
	var current: int = _seq
	_seq += 1
	return current
