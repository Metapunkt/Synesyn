extends Node

# Centralized, editor-only test hooks for DevAgent harness runs.
# Attach this as a child node named `DevHarnessHooks` in the scenes you want to test.
#
# This keeps test-only code out of core scene scripts: scenes expose small `test_*` forwarders,
# while the implementation lives here.

@export var hook_kind: String = "" # e.g. "game_session", "story_stage"

const SynesynAutoloadAccessScript = preload("res://addons/synesyn_core/scripts/synesyn_autoload_access.gd")
const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")

func _global() -> Node:
	return SynesynAutoloadAccessScript.global()

func _story_state() -> Node:
	return SynesynAutoloadAccessScript.story_state()

func _plugin_manager() -> Node:
	return SynTreeAutoloads.plugin_manager()

func _is_enabled() -> bool:
	# Editor builds (including CLI-run editor exe) only.
	return OS.has_feature("editor")

func _owner() -> Node:
	return get_parent()

func apply_state(state: Dictionary) -> void:
	if not _is_enabled() or state == null:
		return
	match hook_kind:
		"game_session":
			_apply_state_game_session(state)
		"story_stage":
			_apply_state_story_stage(state)
		"story_log_player":
			_apply_state_story_log_player(state)
		_:
			pass

func dump_logs(output_path: String, since_msec: int = 0) -> void:
	if not _is_enabled():
		return
	match hook_kind:
		"game_session":
			_dump_logs_game_session(output_path, since_msec)
		"story_stage":
			_dump_logs_story_stage(output_path, since_msec)
		"story_log_player":
			_dump_logs_story_log_player(output_path)
		_:
			_write_json(output_path, {"ok": false, "error": "Unknown hook_kind: %s" % hook_kind})

func send_user_message(message_text: String) -> void:
	if not _is_enabled():
		return
	match hook_kind:
		"game_session":
			_send_user_message_game_session(message_text)
		"story_stage":
			_send_user_message_story_stage(message_text)
		_:
			pass

func _apply_state_game_session(state: Dictionary) -> void:
	var owner_node := _owner()
	if not is_instance_valid(owner_node):
		return

	var scenario_name := String(state.get("scenario", "")).strip_edges()
	if not scenario_name.is_empty() and _global() and _global().has_method("switch_scenario"):
		_global().switch_scenario(scenario_name)

	var toggles_any: Variant = state.get("toggles", {})
	if typeof(toggles_any) == TYPE_DICTIONARY:
		var toggles: Dictionary = toggles_any
		if toggles.has("auto_player_input"):
			var desired := bool(toggles.get("auto_player_input"))
			var player_auto_input_any: Variant = owner_node.get("player_auto_input")
			if player_auto_input_any == null and _global() and _global().has_method("get_player_auto_input"):
				owner_node.set("player_auto_input", _global().get_player_auto_input())
				player_auto_input_any = owner_node.get("player_auto_input")
			if player_auto_input_any and (player_auto_input_any as Object).has_method("set_enabled"):
				(player_auto_input_any as Object).call("set_enabled", desired, true)
			if (owner_node as Object).has_method("_refresh_auto_player_input_toggle"):
				(owner_node as Object).call("_refresh_auto_player_input_toggle", desired)

		if toggles.has("tts_emitter") and _global() and _global().has_method("set_tts_emitter"):
			_global().set_tts_emitter(String(toggles.get("tts_emitter")).strip_edges())

	# Optional top-level tts_emitter (convenience).
	var emitter := String(state.get("tts_emitter", "")).strip_edges()
	if not emitter.is_empty() and _global() and _global().has_method("set_tts_emitter"):
		_global().set_tts_emitter(emitter)

func _apply_state_story_stage(state: Dictionary) -> void:
	var owner_node := _owner()
	if not is_instance_valid(owner_node):
		return

	var scenario_name := String(state.get("scenario", "")).strip_edges()
	if not scenario_name.is_empty() and _global() and _global().has_method("switch_scenario"):
		_global().switch_scenario(scenario_name)

	var toggles_any: Variant = state.get("toggles", {})
	if typeof(toggles_any) == TYPE_DICTIONARY:
		var toggles: Dictionary = toggles_any
		if toggles.has("auto_player_input"):
			var desired := bool(toggles.get("auto_player_input"))
			var player_auto_input_any: Variant = owner_node.get("player_auto_input")
			if player_auto_input_any == null and _global() and _global().has_method("get_player_auto_input"):
				owner_node.set("player_auto_input", _global().get_player_auto_input())
				player_auto_input_any = owner_node.get("player_auto_input")
			if player_auto_input_any and (player_auto_input_any as Object).has_method("set_enabled"):
				(player_auto_input_any as Object).call("set_enabled", desired, true)
			if (owner_node as Object).has_method("_update_stage_input_field_state"):
				(owner_node as Object).call("_update_stage_input_field_state")

	# Optional: set TTS emitter if present.
	var emitter := String(state.get("tts_emitter", "")).strip_edges()
	if not emitter.is_empty() and _global() and _global().has_method("set_tts_emitter"):
		_global().set_tts_emitter(emitter)

func _send_user_message_game_session(message_text: String) -> void:
	var owner_node := _owner()
	if not is_instance_valid(owner_node):
		return
	var msg_text := String(message_text).strip_edges()
	if msg_text.is_empty():
		return
	if (owner_node as Object).has_method("_on_character_input_text_submitted"):
		(owner_node as Object).call("_on_character_input_text_submitted", msg_text)
		return
	var input_field_any: Variant = owner_node.get("input_field")
	if input_field_any and input_field_any is LineEdit:
		(input_field_any as LineEdit).text = msg_text
	if (owner_node as Object).has_method("_on_send_pressed"):
		(owner_node as Object).call("_on_send_pressed")

func _send_user_message_story_stage(message_text: String) -> void:
	var owner_node := _owner()
	if not is_instance_valid(owner_node):
		return
	var msg_text := String(message_text).strip_edges()
	if msg_text.is_empty():
		return
	var input_field_any: Variant = owner_node.get("input_field")
	if input_field_any and input_field_any is LineEdit:
		(input_field_any as LineEdit).text = msg_text
	if (owner_node as Object).has_method("_on_send_pressed"):
		(owner_node as Object).call("_on_send_pressed")

func _dump_logs_game_session(output_path: String, since_msec: int = 0) -> void:
	var owner_node := _owner()
	var now_ms: int = int(Time.get_ticks_msec())
	if since_msec > now_ms:
		since_msec = 0

	var ai_diag: Dictionary = {}
	if _plugin_manager() and _plugin_manager().has_method("get_ai_model_manager"):
		var aim_any: Variant = _plugin_manager().get_ai_model_manager()
		if aim_any:
			var aim_obj := aim_any as Object
			if aim_obj and aim_obj.has_method("get_current_model"):
				var current_model: String = String(aim_obj.call("get_current_model")).strip_edges()
				ai_diag["current_model"] = current_model
				var provider_name: String = ""
				if current_model != "" and aim_obj.has_method("get_provider_for_model"):
					provider_name = String(aim_obj.call("get_provider_for_model", current_model)).strip_edges()
				ai_diag["provider"] = provider_name
				var avail_any: Variant = aim_obj.call("get_available_models") if aim_obj.has_method("get_available_models") else []
				if typeof(avail_any) == TYPE_ARRAY:
					ai_diag["available_models_count"] = int((avail_any as Array).size())
				var loader_any: Variant = null
				if provider_name != "" and aim_obj.has_method("get_provider_loader"):
					loader_any = aim_obj.call("get_provider_loader", provider_name)
				if loader_any:
					var loader_obj := loader_any as Object
					if loader_obj:
						var base_any: Variant = loader_obj.get("base_url")
						ai_diag["base_url"] = String(base_any).strip_edges()
						var key_any: Variant = loader_obj.get("api_key")
						var key_s: String = String(key_any).strip_edges()
						ai_diag["api_key_present"] = (provider_name != "ollama" and not key_s.is_empty())

	var gfm: Object = _global().get_game_flow_manager() if _global() and _global().has_method("get_game_flow_manager") else null
	var scenario_name := ""
	if gfm and gfm.has_method("get_current_scenario_name"):
		scenario_name = String(gfm.get_current_scenario_name()).strip_edges()
	elif gfm and gfm.has_method("get_current_scenario"):
		var scen_any: Variant = gfm.get_current_scenario()
		if typeof(scen_any) == TYPE_DICTIONARY:
			scenario_name = String((scen_any as Dictionary).get("name", "")).strip_edges()

	var player_auto_input_any: Variant = owner_node.get("player_auto_input") if owner_node else null
	var pai_available: bool = false
	var pai_enabled: bool = false
	if player_auto_input_any:
		if (player_auto_input_any as Object).has_method("is_available"):
			pai_available = bool((player_auto_input_any as Object).call("is_available"))
		if (player_auto_input_any as Object).has_method("is_enabled"):
			pai_enabled = bool((player_auto_input_any as Object).call("is_enabled"))

	var story_log_entries: Array = _story_state().get_state().get("story_log", []) if _story_state() else []
	var last_story_sender := ""
	var last_story_message := ""
	var last_story_entries: Array = []
	if story_log_entries.size() > 0:
		var last_any: Variant = story_log_entries.back()
		if typeof(last_any) == TYPE_DICTIONARY:
			var last_entry: Dictionary = last_any
			last_story_sender = String(last_entry.get("sender", "")).strip_edges()
			last_story_message = String(last_entry.get("message", "")).strip_edges()
		var start_idx: int = maxi(0, story_log_entries.size() - 5)
		for i in range(start_idx, story_log_entries.size()):
			var e_any: Variant = story_log_entries[i]
			if typeof(e_any) != TYPE_DICTIONARY:
				continue
			var e: Dictionary = e_any
			last_story_entries.append({
				"sender": String(e.get("sender", "")).strip_edges(),
				"message": String(e.get("message", "")).strip_edges(),
			})

	var session_id := String(owner_node.get("_session_id") if owner_node else "").strip_edges()
	var turn_any: Variant = owner_node.get("current_turn") if owner_node else 0
	var turn_idx := int(turn_any) if typeof(turn_any) in [TYPE_INT, TYPE_FLOAT] else 0

	var input_field_any: Variant = owner_node.get("input_field") if owner_node else null
	var hamburger_panel_any: Variant = owner_node.get("hamburger_settings_panel") if owner_node else null

	var payload := {
		"kind": "game_session_snapshot",
		"captured_at_ms": now_ms,
		"since_msec_requested": since_msec,
		"ai": ai_diag,
		"scenario": scenario_name,
		"tts_emitter": (_global().get_tts_emitter() if _global() and _global().has_method("get_tts_emitter") else ""),
		"auto_player_input": {"available": bool(pai_available), "enabled": bool(pai_enabled)},
		"thread": {"session_id": session_id, "turn": turn_idx},
		"story_log": {
			"count": int(story_log_entries.size()),
			"last_entry": {"sender": last_story_sender, "message": last_story_message},
			"tail": last_story_entries,
		},
		"ui": {
			"input_editable": ((input_field_any as LineEdit).editable if input_field_any is LineEdit else null),
			"hamburger_visible": ((hamburger_panel_any as Control).visible if hamburger_panel_any is Control else null),
		},
		"filter_stats": owner_node.get("filter_stats") if owner_node else {},
		"workshop_catalyst": _workshop_snapshot(),
	}
	_write_json(output_path, payload)

## Workshop Catalyst evidence that a specialist turn ran. Needed because the
## synthesized narrative is cached for `/synthesis` rather than posted to the
## story log (ADR 0009, 2026-08-03), so story-log assertions alone cannot tell a
## working Workshop session from a silent one.
##
## Reports the narrative's length rather than its text: length is enough to prove
## analysis produced prose, without copying session content into CI artifacts.
func _workshop_snapshot() -> Dictionary:
	var state: Dictionary = _story_state().get_state() if _story_state() else {}
	var ws_any: Variant = state.get("workshop_catalyst", {})
	if typeof(ws_any) != TYPE_DICTIONARY:
		return {}
	var ws: Dictionary = ws_any
	var map_any: Variant = ws.get("thinking_map", {})
	var map_state: Dictionary = map_any if typeof(map_any) == TYPE_DICTIONARY else {}
	var document_any: Variant = map_state.get("document", {})
	var document: Dictionary = document_any if typeof(document_any) == TYPE_DICTIONARY else {}
	var nodes_any: Variant = document.get("nodes", [])
	var nodes: Array = nodes_any if typeof(nodes_any) == TYPE_ARRAY else []
	var nodes_by_kind: Dictionary = {}
	var orientation_counts: Dictionary = {}
	var oriented_count: int = 0
	var contested_count: int = 0
	var view_position_count: int = 0
	var claims_with_views: int = 0
	for node_any: Variant in nodes:
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		var node_kind: String = String(node_data.get("kind", "")).strip_edges()
		if not node_kind.is_empty():
			nodes_by_kind[node_kind] = int(nodes_by_kind.get(node_kind, 0)) + 1
		var quadrant_id: String = _node_orientation_quadrant(node_data)
		if not quadrant_id.is_empty():
			orientation_counts[quadrant_id] = int(orientation_counts.get(quadrant_id, 0)) + 1
			oriented_count += 1
		if _node_orientation_contested(node_data):
			contested_count += 1
		var view_holders: int = _node_view_holder_count(node_data)
		if view_holders > 0:
			view_position_count += view_holders
			claims_with_views += 1
	var edges_any: Variant = document.get("edges", [])
	var edges: Array = edges_any if typeof(edges_any) == TYPE_ARRAY else []
	return {
		"session_type": (
			String(_global().current_session_type)
			if _global() and "current_session_type" in _global()
			else ""
		),
		"current_stage_name": String(ws.get("current_stage_name", "")).strip_edges(),
		"session_record_pulse": String(ws.get("session_record_pulse", "")).strip_edges(),
		"session_record_text_length": String(ws.get("session_record_latest_text", "")).length(),
		"thinking_map": {
			"node_count": nodes.size(),
			"edge_count": edges.size(),
			"nodes_by_kind": nodes_by_kind,
			# Closure Audit coverage (ADR 0020). Raw document totals with no
			# status filter, unlike the product's own reading, which drops
			# rejected claims. `orientation_counts` holds only the quadrants
			# actually present, so assert on `oriented_count` for the guarantee
			# that an unaudited session records no orientation at all.
			"oriented_count": oriented_count,
			"unoriented_count": nodes.size() - oriented_count,
			"orientation_counts": orientation_counts,
			"contested_count": contested_count,
			"view_position_count": view_position_count,
			"claims_with_views": claims_with_views,
		},
	}

## Reads a claim's Closure Map quadrant straight out of the document. Structural on
## purpose: the harness needs counts, not vocabulary, and reading the stored shape
## directly is also what lets it verify that shape rather than agreeing with whatever
## the product currently writes. (`ClosureOrientation` now lives in `synesyn_core`, so
## importing it would be permitted under ADR 0017 — it is simply not wanted here.)
func _node_orientation_quadrant(node_data: Dictionary) -> String:
	var annotations_any: Variant = node_data.get("annotations", {})
	if typeof(annotations_any) != TYPE_DICTIONARY:
		return ""
	var orientation_any: Variant = (annotations_any as Dictionary).get("orientation", {})
	if typeof(orientation_any) != TYPE_DICTIONARY:
		return ""
	return String((orientation_any as Dictionary).get("quadrant", "")).strip_edges()

## A sibling of `orientation`, not a field inside it, so that marking a claim contested
## cannot alter the persisted orientation shape. Reports the asserted flag *or* divergent
## recorded views, matching what the product treats as contested.
func _node_orientation_contested(node_data: Dictionary) -> bool:
	var annotations_any: Variant = node_data.get("annotations", {})
	if typeof(annotations_any) != TYPE_DICTIONARY:
		return false
	if bool((annotations_any as Dictionary).get("orientation_contested", false)):
		return true
	var distinct_views: Array[String] = []
	for position_any: Variant in _node_view_positions(node_data):
		var view_text: String = String((position_any as Dictionary).get("view", "")).strip_edges()
		if not view_text.is_empty() and view_text not in distinct_views:
			distinct_views.append(view_text)
	return distinct_views.size() > 1


func _node_view_holder_count(node_data: Dictionary) -> int:
	return _node_view_positions(node_data).size()


## Participant orientation views, which are stored as positions on the register's
## `placement` dimension rather than in a store of their own — a view and a placement
## position are the same fact.
func _node_view_positions(node_data: Dictionary) -> Array:
	var annotations_any: Variant = node_data.get("annotations", {})
	if typeof(annotations_any) != TYPE_DICTIONARY:
		return []
	var register_any: Variant = (annotations_any as Dictionary).get("contestation", {})
	if typeof(register_any) != TYPE_DICTIONARY:
		return []
	var placement_any: Variant = (register_any as Dictionary).get("placement", {})
	if typeof(placement_any) != TYPE_DICTIONARY:
		return []
	var positions_any: Variant = (placement_any as Dictionary).get("positions", [])
	return positions_any if typeof(positions_any) == TYPE_ARRAY else []

func _dump_logs_story_stage(output_path: String, since_msec: int = 0) -> void:
	var owner_node := _owner()
	var now_ms: int = int(Time.get_ticks_msec())
	if since_msec > now_ms:
		since_msec = 0

	var gfm: Object = _global().get_game_flow_manager() if _global() and _global().has_method("get_game_flow_manager") else null
	var scenario_name := ""
	if gfm and gfm.has_method("get_current_scenario_name"):
		scenario_name = String(gfm.get_current_scenario_name()).strip_edges()
	elif gfm and gfm.has_method("get_current_scenario"):
		var scen_any: Variant = gfm.get_current_scenario()
		if typeof(scen_any) == TYPE_DICTIONARY:
			scenario_name = String((scen_any as Dictionary).get("name", "")).strip_edges()

	var player_auto_input_any: Variant = owner_node.get("player_auto_input") if owner_node else null
	var pai_available: bool = false
	var pai_enabled: bool = false
	if player_auto_input_any:
		if (player_auto_input_any as Object).has_method("is_available"):
			pai_available = bool((player_auto_input_any as Object).call("is_available"))
		if (player_auto_input_any as Object).has_method("is_enabled"):
			pai_enabled = bool((player_auto_input_any as Object).call("is_enabled"))

	var input_field_any: Variant = owner_node.get("input_field") if owner_node else null
	var send_button_any: Variant = owner_node.get("send_button") if owner_node else null
	var settings_panel_any: Variant = owner_node.get("settings_panel") if owner_node else null

	var payload := {
		"kind": "story_stage_snapshot",
		"captured_at_ms": now_ms,
		"since_msec_requested": since_msec,
		"scenario": scenario_name,
		"tts_emitter": (_global().get_tts_emitter() if _global() and _global().has_method("get_tts_emitter") else ""),
		"auto_player_input": {"available": bool(pai_available), "enabled": bool(pai_enabled)},
		"ui": {
			"input_editable": ((input_field_any as LineEdit).editable if input_field_any is LineEdit else null),
			"send_disabled": ((send_button_any as BaseButton).disabled if send_button_any is BaseButton else null),
			"hamburger_visible": ((settings_panel_any as Control).visible if settings_panel_any is Control else null),
		},
	}
	_write_json(output_path, payload)

## State keys: log_path, pace ("reading" | "original" | "manual"), speed, loop, voice.
## Voice is set first so the opening line is already paced without it.
func _apply_state_story_log_player(state: Dictionary) -> void:
	var player = _owner()
	if not is_instance_valid(player) or not player.has_method("open_log"):
		return
	if state.has("voice"):
		player.host.set_voice_enabled(bool(state.get("voice")))
	var pace_name := String(state.get("pace", "")).strip_edges().to_lower()
	for pace_id in player.PACE_NAMES:
		if player.PACE_NAMES[pace_id] == pace_name:
			player.set_pace(pace_id)
	if state.has("speed"):
		player.set_speed(float(state.get("speed")))
	if state.has("loop"):
		player.set_loop(bool(state.get("loop")))
	var log_path := String(state.get("log_path", "")).strip_edges()
	if not log_path.is_empty():
		player.open_log(log_path)

## Lines displayed come from the player; whether the stage reached for a hub is read off
## the tree, where ScenSyn's session services would have attached themselves.
func _dump_logs_story_log_player(output_path: String) -> void:
	var player = _owner()
	if not is_instance_valid(player) or not player.has_method("get_playback_report"):
		_write_json(output_path, {"ok": false, "error": "story_log_player hook has no player"})
		return
	var stage: Node = player.get("stage")
	var session_attached: bool = stage != null and stage.find_child("ScenSynStageSession", true, false) != null
	_write_json(output_path, {
		"kind": "story_log_player_snapshot",
		"captured_at_ms": int(Time.get_ticks_msec()),
		"playback": player.get_playback_report(),
		"hub": {"stage_session_attached": session_attached},
	})

func _write_json(path: String, data: Dictionary) -> void:
	var p := String(path).strip_edges()
	if p.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify(data if data != null else {}, "  "))
	f.close()
