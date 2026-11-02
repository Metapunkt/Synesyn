## Purpose: Panel controller for publishing the active SynTree context graph to the Hub (async, non-blocking)
@tool
extends Node
class_name PublishContextGraphController

const RuntimeConfigScript = preload("res://addons/synesyn_core/scripts/runtime_config.gd")
const ContextGraphV1PayloadBuilderScript = preload(
	"res://addons/syntree/scripts/ui/panel/internal/context_graph_v1_payload_builder.gd"
)

var _content_state: ContentStateResource = null
var _show_warning_cb: Callable = Callable()
var _show_error_cb: Callable = Callable()
var _set_status_cb: Callable = Callable() # expects (text:String)
var _notify_info_cb: Callable = Callable() # expects (message:String, title:String)
var _notify_success_cb: Callable = Callable() # expects (message:String, title:String)

var _inflight: bool = false
var _payload_builder: RefCounted = null

func setup(
		content_state: ContentStateResource,
		show_warning_cb: Callable,
		show_error_cb: Callable,
		set_status_cb: Callable,
		notify_info_cb: Callable,
		notify_success_cb: Callable
	) -> void:
	_content_state = content_state
	_show_warning_cb = show_warning_cb
	_show_error_cb = show_error_cb
	_set_status_cb = set_status_cb
	_notify_info_cb = notify_info_cb
	_notify_success_cb = notify_success_cb

func start_publish() -> void:
	if _inflight:
		return
	_inflight = true
	if _notify_info_cb.is_valid():
		_notify_info_cb.call("Publishing…", "Hub Publish")
	if _set_status_cb.is_valid():
		_set_status_cb.call("Hub: publishing context graph…")
	call_deferred("_publish_async")

func _publish_async() -> void:
	if not is_instance_valid(_content_state):
		_inflight = false
		if _show_error_cb.is_valid():
			_show_error_cb.call("Publish Failed", "ContentStateResource not available.")
		return

	var active_ids: Array[String] = _content_state.get_active_sources() if _content_state.has_method("get_active_sources") else []
	if active_ids.is_empty():
		_inflight = false
		if _show_warning_cb.is_valid():
			_show_warning_cb.call("Nothing to Publish", "No active sources. Activate sources first, then publish.")
		return

	if _payload_builder == null:
		_payload_builder = ContextGraphV1PayloadBuilderScript.new()
	var source_ids: Array = _payload_builder.call(
		"collect_source_ids",
		_content_state,
		active_ids
	)
	var nodes: Array = []
	var edges: Array = []
	var i := 0
	for source_id_any in source_ids:
		i += 1
		_payload_builder.call(
			"append_source",
			_content_state,
			str(source_id_any),
			nodes,
			edges
		)
		# Yield occasionally to keep editor responsive.
		if i % 25 == 0:
			await get_tree().process_frame
	var graph: Dictionary = _payload_builder.call(
		"make_payload",
		active_ids,
		nodes,
		edges,
		Time.get_datetime_string_from_system(false, true)
	)

	var HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
	var client = HubSubstrateClientScript.new()
	add_child(client)
	client.configure_from_runtime_config()

	# Fast reachability check.
	if client and client.has_method("check_health"):
		var health: Dictionary = await client.check_health()
		if not bool(health.get("ok", false)):
			client.queue_free()
			_inflight = false
			if _set_status_cb.is_valid():
				_set_status_cb.call("Hub: not reachable (start Hub and try again)")
			if _show_error_cb.is_valid():
				_show_error_cb.call("Publish Failed", "Hub is not reachable.")
			return

	var metadata := {
		"provenance": {
			"generated_by": "syntree.publish_context_graph",
			"inputs": [{"type": "syntree.content_sources", "count": nodes.size()}],
		}
	}

	var res: Dictionary = await client.create_artifact_inline_json("ui.context_graph", graph, metadata)

	# Optional: emit a "bridge" artifact that only references the published context graph id.
	# This lets other apps (ReadyMade/Studio/ScenSyn) pass around references without direct injection.
	var publish_bridge := false
	var publish_to_store := false
	var cfg: Dictionary = RuntimeConfigScript.load_config() if RuntimeConfigScript else {}
	var apps_any: Variant = cfg.get("apps", {})
	if typeof(apps_any) == TYPE_DICTIONARY:
		var apps: Dictionary = apps_any
		var syntree_any: Variant = apps.get("syntree", {})
		if typeof(syntree_any) == TYPE_DICTIONARY:
			publish_bridge = bool((syntree_any as Dictionary).get("publish_context_graph_bridge", false))
			publish_to_store = bool((syntree_any as Dictionary).get("publish_context_graph_to_stfx_store", false))
	if publish_bridge and bool(res.get("ok", false)) and client and client.has_method("create_context_graph_bridge"):
		var ctx_id := str(res.get("id", "")).strip_edges()
		if not ctx_id.is_empty():
			var bmeta := {"provenance": {"generated_by": "syntree.publish_context_graph_bridge", "inputs": [{"artifact_type": "ui.context_graph", "artifact_id": ctx_id}]}}
			var bres: Dictionary = await client.create_context_graph_bridge(ctx_id, bmeta)
			if bool(bres.get("ok", false)) and _set_status_cb.is_valid():
				_set_status_cb.call("Hub: published context graph: %s (bridge: %s)" % [ctx_id, str(bres.get("id", ""))])
	if publish_to_store and bool(res.get("ok", false)) and client and client.has_method("stfx_store_commit_context_graph"):
		var store_prov := {
			"produced_by": "syntree.publish_context_graph",
			"inputs": [
				{"type": "syntree.content_sources", "count": nodes.size()},
				{"artifact_type": "ui.context_graph", "artifact_id": str(res.get("id", ""))}
			],
		}
		var store_res: Dictionary = await client.stfx_store_commit_context_graph(graph, store_prov)
		if bool(store_res.get("ok", false)) and _set_status_cb.is_valid():
			_set_status_cb.call("Hub: mirrored context graph to STFX Store: %s" % str(store_res.get("artifact_id", "")))
	client.queue_free()

	if bool(res.get("ok", false)):
		var art_id := str(res.get("id", ""))
		if _set_status_cb.is_valid():
			_set_status_cb.call("Hub: published context graph: %s" % art_id)
		if _notify_success_cb.is_valid():
			_notify_success_cb.call("Published: %s" % art_id, "Hub Publish")
	else:
		if _show_error_cb.is_valid():
			_show_error_cb.call("Publish Failed", str(res.get("error", res)))

	_inflight = false


