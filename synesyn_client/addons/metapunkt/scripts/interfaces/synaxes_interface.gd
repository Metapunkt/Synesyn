@tool
extends "base_interface.gd"

## Metapunkt ↔ SynAxes orchestrator interface.
##
## Provides three command types that map to DiscoveryEngine capabilities:
##   discover_patterns  – run clustering / bridge / hub discovery on supplied data
##   get_patterns       – retrieve previously discovered patterns
##   clear_patterns     – reset the engine state
##
## The interface creates its own DiscoveryEngine instance (RefCounted, no scene
## tree required) and does NOT attempt to instantiate the editor-only plugin.gd.

const DiscoveryEngineScript = preload("res://addons/synaxes/scripts/integration/discovery_engine.gd")

var _discovery_engine: RefCounted = null


func _init() -> void:
	super._init("synaxes")


func setup(_plugin_script: GDScript) -> void:
	# We intentionally ignore plugin_script — plugin.gd is an EditorPlugin and
	# cannot be instantiated at runtime.  Instead we create a lightweight
	# DiscoveryEngine that provides the same local analytics.
	_discovery_engine = DiscoveryEngineScript.new()
	if _discovery_engine:
		_update_status("status", "active")
	else:
		push_error("SynAxes interface: failed to create DiscoveryEngine")
		_update_status("status", "error")
		_update_status("error", "Failed to create DiscoveryEngine")


func send_command(command: Dictionary) -> void:
	if not _validate_command(command):
		push_error("SynAxes interface: invalid command format")
		return

	match command.type:
		"discover_patterns":
			_handle_pattern_discovery(command.data)
		"get_patterns":
			_handle_get_patterns(command.data)
		"clear_patterns":
			_handle_clear_patterns(command.data)
		_:
			push_error("SynAxes interface: unknown command type: " + str(command.type))


# ── discover_patterns ────────────────────────────────────────────────────────
# Expected data keys:
#   source_data  : Array[Dictionary]   – items with "vector"/"embedding" + metadata
#   method       : int (optional, 0)   – DiscoveryEngine.DiscoveryMethod enum value
#   dim_method   : int (optional, 0)   – DimReduction method (0=PCA,1=tSNE,2=UMAP)
#   num_clusters : int (optional, 5)   – k for clustering
func _handle_pattern_discovery(data: Dictionary) -> void:
	if not _discovery_engine:
		push_error("SynAxes interface: DiscoveryEngine not available")
		emit_signal("task_failed", data.get("task_id", ""), "DiscoveryEngine not available")
		return

	if not data.has("source_data") or not data.source_data is Array:
		push_error("SynAxes interface: discover_patterns requires 'source_data' Array")
		emit_signal("task_failed", data.get("task_id", ""), "Missing or invalid source_data")
		return

	_discovery_engine.set_data(data.source_data)

	var method: int       = data.get("method", 0)        # CLUSTERING
	var dim_method: int   = data.get("dim_method", 0)     # PCA
	var num_clusters: int = data.get("num_clusters", 5)

	var patterns: Array = _discovery_engine.discover_patterns(method, dim_method, num_clusters)

	_update_status("last_discovery", {
		"pattern_count": patterns.size(),
		"timestamp": Time.get_unix_time_from_system(),
	})

	emit_signal("task_completed", data.get("task_id", ""), {
		"type": "pattern_discovery",
		"patterns": patterns,
	})


# ── get_patterns ─────────────────────────────────────────────────────────────
# Optional data key:
#   pattern_id : int – return a single pattern; omit to get all stored patterns
func _handle_get_patterns(data: Dictionary) -> void:
	if not _discovery_engine:
		emit_signal("task_failed", data.get("task_id", ""), "DiscoveryEngine not available")
		return

	if data.has("pattern_id"):
		var pattern: Dictionary = _discovery_engine.get_pattern(data.pattern_id)
		emit_signal("task_completed", data.get("task_id", ""), {
			"type": "get_patterns",
			"pattern": pattern,
		})
	else:
		# Return all stored patterns via the engine's internal dict
		var all_patterns: Dictionary = _discovery_engine._patterns.duplicate()
		emit_signal("task_completed", data.get("task_id", ""), {
			"type": "get_patterns",
			"patterns": all_patterns,
		})


# ── clear_patterns ───────────────────────────────────────────────────────────
func _handle_clear_patterns(data: Dictionary) -> void:
	if _discovery_engine:
		_discovery_engine._data.clear()
		_discovery_engine._patterns.clear()

	_update_status("last_discovery", {})
	emit_signal("task_completed", data.get("task_id", ""), {
		"type": "clear_patterns",
		"status": "cleared",
	})
