extends RefCounted
class_name WorkshopCatalystControllerUtils

## Small, mostly-pure helpers pulled out of workshop_catalyst_controller.gd
## (script size ratchet). Kept static/stateless so they stay easy to unit test
## without instantiating the controller or its many Node dependencies.

const AutoloadsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_autoloads.gd"
)
const WorkshopPresenceControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_presence_controller.gd"
)


## Mounts ADR 0013 presence UI and activates multiplayer or single-player mode.
## authority_changed_cb receives (has_claim: bool).
static func mount_presence_controller(
	workspace_shell_node: Control,
	authority_changed_cb: Callable
) -> RefCounted:
	var presence_controller: RefCounted = WorkshopPresenceControllerScript.new()
	var presence_sync: Node = AutoloadsScript.workshop_presence()
	if not presence_controller.mount(workspace_shell_node, presence_sync):
		return null
	if authority_changed_cb.is_valid():
		presence_controller.facilitator_authority_changed.connect(authority_changed_cb)
	if AutoloadsScript.is_enet_session():
		presence_controller.begin_multiplayer_session()
	else:
		presence_controller.begin_single_player_session()
	return presence_controller


static func has_local_facilitator_claim(presence_controller: RefCounted) -> bool:
	if presence_controller:
		return bool(presence_controller.call("has_local_facilitator_claim"))
	return true


## Host broadcasts full StoryState after a local workshop_catalyst mutation.
static func sync_workshop_state_to_peers_if_host() -> void:
	var story_state_node: Node = AutoloadsScript.story_state()
	if not story_state_node:
		return
	if not AutoloadsScript.is_enet_session():
		return
	var network_node: Node = AutoloadsScript.network()
	if not network_node.is_server():
		return
	if network_node.get_connected_peers().size() <= 0:
		return
	network_node.rpc("sync_story_state", story_state_node.get_state())


## Clients: when the workshop_catalyst fingerprint changes, return true so the
## controller can rehydrate panels. Hosts always return false.
static func client_workshop_fingerprint_changed(
	new_state: Dictionary,
	ws_key: String,
	previous_fingerprint: String
) -> Dictionary:
	if not AutoloadsScript.is_enet_session():
		return {"changed": false, "fingerprint": previous_fingerprint}
	if AutoloadsScript.network().is_server():
		return {"changed": false, "fingerprint": previous_fingerprint}
	var ws_any: Variant = new_state.get(ws_key, {})
	var fingerprint: String = JSON.stringify(ws_any)
	if fingerprint == previous_fingerprint:
		return {"changed": false, "fingerprint": previous_fingerprint}
	return {"changed": true, "fingerprint": fingerprint}


static func format_datetime_now() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]


static func export_decision_record_only(
	export_utils_script: GDScript,
	ws: Dictionary,
	session_id: String,
	scenario: Dictionary,
	record_store: RefCounted
) -> String:
	if ws.is_empty():
		return ""
	var committed_payload: Dictionary = (
		record_store.get_last_committed_payload() if record_store else {}
	)
	var committed_artifact_id: String = (
		record_store.get_last_committed_artifact_id() if record_store else ""
	)
	return export_utils_script.export_decision_record_only(
		ws,
		session_id,
		scenario,
		format_datetime_now(),
		committed_payload,
		committed_artifact_id
	)


## One completed stage, snapshotted for the workshop's stage history. Pure.
static func build_stage_history_entry(ws: Dictionary, stage_info: Dictionary) -> Dictionary:
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	return {
		"day_index": int(ws.get("day_index", 0)),
		"stage_index": int(ws.get("stage_index", 0)),
		"stage_name": String(stage_info.get("name", "")),
		"stage_status": String(ws.get("stage_status", "not_started")),
		"started_at_unix": int(ws.get("stage_started_at_unix", 0)),
		"completed_at_unix": int(ws.get("stage_completed_at_unix", 0)),
		"remaining_sec": int(ws.get("stage_remaining_sec", 0)),
		"buckets_snapshot": buckets.duplicate(true)
	}


## The sibling of export_decision_record_only, which had stayed inline in the controller
## while this one was already delegated. Same shape, same committed-payload handling.
static func export_workshop_summary(
	export_utils_script: GDScript,
	ws: Dictionary,
	session_id: String,
	scenario: Dictionary,
	stage_info: Dictionary,
	record_store: RefCounted
) -> String:
	if ws.is_empty():
		return ""
	var committed_payload: Dictionary = (
		record_store.get_last_committed_payload() if record_store else {}
	)
	var committed_artifact_id: String = (
		record_store.get_last_committed_artifact_id() if record_store else ""
	)
	return export_utils_script.export_workshop_summary(
		ws,
		session_id,
		scenario,
		stage_info,
		format_datetime_now(),
		committed_payload,
		committed_artifact_id
	)


static func find_current_session_id(scene_tree: SceneTree, ws: Dictionary) -> String:
	if scene_tree:
		var game_session_node: Node = scene_tree.get_first_node_in_group("game_session")
		if game_session_node and game_session_node.has_node("%StoryLogSystem"):
			var story_log_system_node: Node = game_session_node.get_node("%StoryLogSystem")
			if story_log_system_node:
				var story_log_session_id: String = str(
					story_log_system_node.get("session_id")
				).strip_edges()
				if not story_log_session_id.is_empty():
					return story_log_session_id
	return str(ws.get("session_id", "")).strip_edges()


## Extracts the stress-injection text authored for the given stage name (e.g.
## "Stress Injection A") from the scenario's stress_injections_text field.
## Returns {"post_text": String, "status": String}: post_text is empty when no
## matching section could be found, and status explains why.
static func build_stress_injection_post(scenario: Dictionary, stage_name: String) -> Dictionary:
	var injections_text: String = String(scenario.get("stress_injections_text", "")).strip_edges()
	if injections_text.is_empty():
		return {"post_text": "", "status": "No stress injection text found in this scenario."}
	var stage_lower: String = stage_name.to_lower()
	var lines: PackedStringArray = injections_text.split("\n")
	var in_section: bool = false
	var collected: Array[String] = []
	for raw_line: String in lines:
		var trimmed_line: String = raw_line.strip_edges()
		var lower_line: String = trimmed_line.to_lower()
		if (
			lower_line.begins_with(stage_lower + ":")
			or lower_line.begins_with(
				stage_lower.replace(" injection ", " injection\n") + ":"
			)
		):
			in_section = true
			collected.append(trimmed_line)
			continue
		if in_section:
			if lower_line.begins_with("stress injection") and not lower_line.begins_with(stage_lower):
				break
			collected.append(raw_line)
	var injection_content: String = "\n".join(collected).strip_edges()
	if injection_content.is_empty():
		return {
			"post_text": "",
			"status": "Could not locate text for '%s' in stress injections." % stage_name,
		}
	return {
		"post_text": "[STRESS INJECTION — %s]\n\n%s" % [stage_name, injection_content],
		"status": "",
	}


## Re-hydrates Session Record, Thinking Map, and Compare Paths from a freshly
## loaded workshop_catalyst state dict, without re-running mount() (which
## would double-wire button signals). Called by
## WorkshopCatalystController.reload_from_loaded_state() after "Load Story
## Log" / "My Sessions" loads a prior session's .workshop.json sidecar.
static func reload_workshop_panels_from_state(
	ws: Dictionary,
	session_id: String,
	scenario_id: String,
	record_store: RefCounted,
	record_panel_controller: RefCounted,
	thinking_map_controller: RefCounted,
	compare_paths_controller: RefCounted
) -> void:
	if record_store:
		var saved_record_any: Variant = ws.get("session_record_review", {})
		var saved_record: Dictionary = (
			saved_record_any if typeof(saved_record_any) == TYPE_DICTIONARY else {}
		)
		var buckets_any: Variant = ws.get("buckets", {})
		var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
		record_store.initialize(session_id, saved_record, buckets)
	if record_panel_controller:
		record_panel_controller.refresh()
	if thinking_map_controller:
		var adapter: RefCounted = thinking_map_controller.get_adapter()
		if adapter:
			var saved_map_any: Variant = ws.get("thinking_map", {})
			var saved_map: Dictionary = (
				saved_map_any if typeof(saved_map_any) == TYPE_DICTIONARY else {}
			)
			adapter.initialize(session_id, scenario_id, "decision_triage", saved_map)
		thinking_map_controller.refresh()
	if compare_paths_controller:
		var path_store: RefCounted = compare_paths_controller.get_path_store()
		if path_store:
			var saved_paths_any: Variant = ws.get("compare_paths", {})
			var saved_paths: Dictionary = (
				saved_paths_any if typeof(saved_paths_any) == TYPE_DICTIONARY else {}
			)
			path_store.initialize(session_id, scenario_id, saved_paths)
		compare_paths_controller.refresh()
