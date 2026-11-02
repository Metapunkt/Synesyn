extends Node
class_name ClosureSubstrateEmitter

## ClosureSubstrateEmitter
##
## Listens for ClosureBus.closure_captured and persists each captured closure
## to the Synesyn Hub LatentSubstrate as a `ui.workshop_closure` artifact (POST
## /substrate/artifacts with inline_json). Discards are NOT persisted by
## default — they are useful as live signal but typically not as substrate
## artifacts; if a future use case needs them, add a separate handler.
##
## Session captures are NOT `ui.closure`: that type is a SynAxes slice with a
## selection and an orientation quadrant. Writing captures there corrupted the
## Closure Map coverage figures and crowded genuine slices out of SynAxes'
## query window. See ADR 0026.
##
## Failures never degrade live workshop UX: the post is fire-and-forget and the
## session continues whether or not it lands. They are not, however, invisible.
## Transport failures and non-2xx responses are pushed as warnings so a broken
## contract or a misconfigured Hub surfaces in the Godot output panel, and the
## Hub URL failing to resolve warns once per process rather than per capture.
##
## All artifacts include provenance metadata (session type, scenario, session,
## stage, turn, trigger, log indices) so SynAxes / SynPunkt can later filter and
## stage them.

const _ARTIFACT_TYPE: String = "ui.workshop_closure"
## Artifact payload version, independent of the ClosureBus signal version.
const _SCHEMA_VERSION: int = 1
const _COMMITTED_BY: String = "scensyn.closure_bus"
const _SOURCE_APP: String = "scensyn"
const _ARTIFACTS_PATH: String = "/substrate/artifacts"
const _STORE_CLOSURE_PATH: String = "/stfx-store/closures/commit"

var _http: HTTPRequest = null
var _store_http: HTTPRequest = null
var _hub_base_url: String = ""
var _warned_about_missing_hub: bool = false
var _publish_to_store: bool = false

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_substrate_request_completed)
	_store_http = HTTPRequest.new()
	add_child(_store_http)
	_resolve_hub_url_once()
	_disable_proxy_for_local(_http, _hub_base_url)
	_disable_proxy_for_local(_store_http, _hub_base_url)

## Connects to a ClosureBus node (or any node exposing closure_captured signal).
## Called by ClosureBus._ready() after instantiating us as a child.
func attach_to_bus(bus: Node) -> void:
	if bus == null or not bus.has_signal("closure_captured"):
		return
	# String-based connect is safest here since `bus` is typed as base Node and
	# the parser does not statically know about ClosureBus signals.
	if not bus.is_connected("closure_captured", Callable(self, "_on_closure_captured")):
		bus.connect("closure_captured", Callable(self, "_on_closure_captured"))

func _resolve_hub_url_once() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	_hub_base_url = String(ProviderModePolicy.get_hub_base_url(cfg)).strip_edges()
	if _hub_base_url.is_empty():
		_hub_base_url = "http://127.0.0.1:17777"
	var apps_any: Variant = cfg.get("apps", {})
	if typeof(apps_any) == TYPE_DICTIONARY:
		var apps: Dictionary = apps_any
		var scensyn_any: Variant = apps.get("scensyn", {})
		if typeof(scensyn_any) == TYPE_DICTIONARY:
			var scensyn_cfg: Dictionary = scensyn_any
			_publish_to_store = bool(scensyn_cfg.get("publish_closures_to_stfx_store", false))

func _disable_proxy_for_local(http: HTTPRequest, url: String) -> void:
	# Mirror of the same workaround used by HubProcessManager: on Windows,
	# system proxies sometimes interfere with localhost calls. Disable proxies
	# for local hub requests.
	if not is_instance_valid(http):
		return
	var u: String = String(url).strip_edges().to_lower()
	var is_local: bool = (u.find("127.0.0.1") != -1) or (u.find("localhost") != -1) or (u.find("[::1]") != -1)
	if not is_local:
		return
	http.set_http_proxy("", -1)
	http.set_https_proxy("", -1)

func _on_closure_captured(payload: Dictionary) -> void:
	if _hub_base_url.is_empty():
		if not _warned_about_missing_hub:
			push_warning("[ClosureSubstrateEmitter] Hub base URL not resolved; closures will not be persisted to substrate this session.")
			_warned_about_missing_hub = true
		return
	if not is_instance_valid(_http):
		return
	# A capture with no statement carries no record of what the room committed,
	# and the Hub rejects it. Surface it here rather than as a silent 400.
	if String(payload.get("statement", "")).strip_edges().is_empty():
		push_warning("[ClosureSubstrateEmitter] Captured closure has an empty statement; not persisting.")
		return
	# Build the artifact body. inline_json carries the closure payload itself;
	# metadata carries the cross-cutting provenance the Hub indexes by.
	var body: Dictionary = {
		"artifact_type": _ARTIFACT_TYPE,
		"inline_json": _build_artifact_payload(payload),
		"metadata": _build_metadata(payload),
	}
	var url: String = _hub_base_url.rstrip("/") + _ARTIFACTS_PATH
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var json_body: String = JSON.stringify(body)
	# Fire-and-forget. We DO NOT await the response: the live workshop UX
	# must never block on a substrate write. If the Hub is down or slow,
	# the captured closure still surfaces in the Session Record post and
	# the bucket; the substrate copy is best-effort.
	var err: int = _http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		# Log once-ish; this is best-effort persistence.
		push_warning("[ClosureSubstrateEmitter] HTTPRequest.request() returned err=%d for %s" % [err, url])
	if _publish_to_store:
		_post_store_closure(payload)

## Maps a ClosureBus event onto the `ui.workshop_closure` artifact contract.
##
## The event and the artifact are versioned separately: the bus stamps a
## `schema_version` of "1.0" describing the signal, while the Hub requires an
## integer version describing the stored payload, as every other workshop
## artifact does.
func _build_artifact_payload(event: Dictionary) -> Dictionary:
	var artifact: Dictionary = event.duplicate(true)
	artifact["schema_version"] = _SCHEMA_VERSION
	artifact["session_type_id"] = String(event.get("session_type_id", "")).strip_edges()
	artifact["human_commit"] = {
		"committed_by": _COMMITTED_BY,
		"decision": String(event.get("outcome", "")).strip_edges(),
		"voters_yes": event.get("voters_yes", []),
		"voters_no": event.get("voters_no", []),
		"captured_at_unix": float(event.get("captured_at_unix", 0.0)),
	}
	return artifact

## Reports rejected or failed substrate writes. Persistence stays best-effort —
## we never block the session — but a silent drop would hide contract breaks.
func _on_substrate_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[ClosureSubstrateEmitter] Closure substrate write failed (result=%d)." % result)
		return
	if response_code < 200 or response_code >= 300:
		push_warning("[ClosureSubstrateEmitter] Hub rejected closure artifact (HTTP %d): %s" % [
			response_code,
			body.get_string_from_utf8().strip_edges(),
		])

func _build_metadata(payload: Dictionary) -> Dictionary:
	# Provenance the Hub will index. Keep keys short and stable; downstream
	# consumers (SynAxes, SynPunkt) will filter on these.
	return {
		"source_app": _SOURCE_APP,
		"session_type_id": String(payload.get("session_type_id", "")).strip_edges(),
		"scenario_id": String(payload.get("scenario_id", "")).strip_edges(),
		"scenario_name": String(payload.get("scenario_name", "")).strip_edges(),
		"kind": String(payload.get("kind", "")).strip_edges(),
		"outcome": String(payload.get("outcome", "")).strip_edges(),
		"trigger": String(payload.get("trigger", "")).strip_edges(),
		"stage_name": String(payload.get("stage_name", "")).strip_edges(),
		"captured_at_unix": float(payload.get("captured_at_unix", 0.0)),
	}

func _post_store_closure(payload: Dictionary) -> void:
	if not is_instance_valid(_store_http):
		return
	var title: String = String(payload.get("statement", "")).strip_edges()
	if title.is_empty():
		title = "ScenSyn Closure"
	var kind: String = String(payload.get("kind", "")).strip_edges()
	var primary_seed: String = kind.to_lower()
	if primary_seed.is_empty():
		primary_seed = "closure"
	var reason: String = String(payload.get("reason", "")).strip_edges()
	var trigger: String = String(payload.get("trigger", "")).strip_edges()
	var rationale: String = reason
	if not trigger.is_empty():
		rationale = "%s Trigger: %s" % [rationale, trigger] if not rationale.is_empty() else "Trigger: %s" % trigger
	if rationale.is_empty():
		rationale = "Captured ScenSyn closure mirrored from ClosureBus."
	var store_payload := {
		"title": title,
		"selected": {
			"source_ids": [],
			"chunk_ids": [],
			"memory_ids": [],
			"artifact_ids": [],
			"log_span": {
				"open": int(payload.get("source_log_index_open", -1)),
				"close": int(payload.get("source_log_index_close", -1)),
			},
		},
		"symbolic_constraints": {
			"primary_seed": primary_seed,
			"source_app": _SOURCE_APP,
			"session_type_id": String(payload.get("session_type_id", "")).strip_edges(),
			"scenario_id": String(payload.get("scenario_id", "")).strip_edges(),
			"stage_name": String(payload.get("stage_name", "")).strip_edges(),
		},
		"human_commit": {
			"committed_by": "scensyn.closure_bus",
			"decision": String(payload.get("outcome", "")).strip_edges(),
			"voters_yes": payload.get("voters_yes", []),
			"voters_no": payload.get("voters_no", []),
			"captured_at_unix": float(payload.get("captured_at_unix", 0.0)),
		},
		"rationale": rationale,
		"relations": [],
	}
	var provenance := {
		"produced_by": "scensyn.ui_closure_to_stfx_store",
		"inputs": [
			{
				"type": "scensyn.closure_bus_event",
				"session_type_id": String(payload.get("session_type_id", "")).strip_edges(),
				"scenario_id": String(payload.get("scenario_id", "")).strip_edges(),
				"kind": kind,
			}
		],
	}
	var body := {
		"payload": store_payload,
		"provenance": provenance,
	}
	var url: String = _hub_base_url.rstrip("/") + _STORE_CLOSURE_PATH
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var err: int = _store_http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		push_warning("[ClosureSubstrateEmitter] Store closure mirror request returned err=%d for %s" % [err, url])
