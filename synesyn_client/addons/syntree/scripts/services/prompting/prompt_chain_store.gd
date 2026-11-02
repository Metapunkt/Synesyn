## Purpose: PromptChainStore (script)
extends RefCounted
class_name PromptChainStore

const SCHEMA_VERSION := 1
const RuntimeConfigScript = preload("res://addons/synesyn_core/scripts/runtime_config.gd")
const SLOT_VALUES_DIR := "slot_values"

static func _get_root_dir() -> String:
	# Documents/Synesyn/synesyn/prompt_chains (ADR 0014).
	return RuntimeConfigScript.get_prompt_chains_dir().replace("\\", "/")

static func _ensure_root_dir() -> void:
	var root := _get_root_dir()
	# user:// case (must use DirAccess.open("user://") for relative directory operations)
	if root.begins_with("user://"):
		var dir := DirAccess.open("user://")
		if not dir:
			return
		var rel := root.replace("user://", "")
		if not dir.dir_exists(rel):
			dir.make_dir_recursive(rel)
		return
	# Absolute path case
	if not DirAccess.dir_exists_absolute(root):
		DirAccess.make_dir_recursive_absolute(root)

static func _ensure_dir(path: String) -> void:
	var p := String(path).strip_edges()
	if p.is_empty():
		return
	if p.begins_with("user://"):
		var dir := DirAccess.open("user://")
		if not dir:
			return
		var rel := p.replace("user://", "")
		if not dir.dir_exists(rel):
			dir.make_dir_recursive(rel)
		return
	var abs := ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p
	if not abs.is_empty() and not DirAccess.dir_exists_absolute(abs):
		DirAccess.make_dir_recursive_absolute(abs)

static func _state_path(scope: String) -> String:
	var safe_scope := String(scope).strip_edges()
	if safe_scope.is_empty():
		safe_scope = "shared"
	_ensure_root_dir()
	return _get_root_dir().path_join("%s.json" % safe_scope)

static func _slot_values_path(scope: String, thread_id: String) -> String:
	var safe_scope := String(scope).strip_edges()
	if safe_scope.is_empty():
		safe_scope = "shared"
	var tid := String(thread_id).strip_edges()
	if tid.is_empty():
		tid = "default"
	_ensure_root_dir()
	var dir_path := _get_root_dir().path_join(SLOT_VALUES_DIR).path_join(safe_scope)
	_ensure_dir(dir_path)
	return dir_path.path_join("%s.json" % tid)

static func default_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"chains": {},   # chain_id -> chain dict
		"threads": {},  # thread_id -> {mode, asset_id, draft, apply_to_chat}
		"hub": {        # best-effort system-of-record pointers (v1)
			"chains": {}, # chain_id -> {latest_artifact_id, versions:[artifact_id,...]}
		},
	}

static func load_state(scope: String) -> Dictionary:
	var path := _state_path(scope)
	if not FileAccess.file_exists(path):
		return default_state()
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return default_state()
	var raw := f.get_as_text()
	f.close()
	if raw.strip_edges().is_empty():
		return default_state()
	var parsed_any: Variant = JSON.parse_string(raw)
	if typeof(parsed_any) != TYPE_DICTIONARY:
		return default_state()
	var parsed: Dictionary = parsed_any
	var st := default_state()
	st.merge(parsed, true)
	return st

static func save_state(scope: String, state: Dictionary) -> bool:
	var path := _state_path(scope)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return false
	f.store_string(JSON.stringify(state, "\t"))
	f.close()
	return true

static func get_thread_settings(scope: String, thread_id: String) -> Dictionary:
	var st := load_state(scope)
	var threads_any: Variant = st.get("threads", {})
	if typeof(threads_any) != TYPE_DICTIONARY:
		return {}
	var threads: Dictionary = threads_any
	return threads.get(thread_id, {})

static func get_thread_slot_values(scope: String, thread_id: String) -> Dictionary:
	var t: Dictionary = get_thread_settings(scope, thread_id)
	var sv_any: Variant = t.get("slot_values", {})
	return sv_any if typeof(sv_any) == TYPE_DICTIONARY else {}

static func set_thread_slot_values(scope: String, thread_id: String, slot_values: Dictionary) -> bool:
	var t: Dictionary = get_thread_settings(scope, thread_id)
	t["slot_values"] = slot_values if slot_values != null else {}
	return set_thread_settings(scope, thread_id, t)

static func export_thread_slot_values(scope: String, thread_id: String) -> Dictionary:
	var path := _slot_values_path(scope, thread_id)
	var data: Dictionary = get_thread_slot_values(scope, thread_id)
	var payload := {"schema_version": 1, "scope": scope, "thread_id": thread_id, "slot_values": data}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return {"success": false, "error": "Failed to open for write: %s" % path}
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return {"success": true, "path": path}

static func import_thread_slot_values(scope: String, thread_id: String, merge: bool = true) -> Dictionary:
	var path := _slot_values_path(scope, thread_id)
	if not FileAccess.file_exists(path):
		return {"success": false, "error": "Slot values file not found: %s" % path}
	var raw := FileAccess.get_file_as_string(path)
	if raw.strip_edges().is_empty():
		return {"success": false, "error": "Slot values file is empty: %s" % path}
	var any: Variant = JSON.parse_string(raw)
	if typeof(any) != TYPE_DICTIONARY:
		return {"success": false, "error": "Slot values JSON invalid: %s" % path}
	var d: Dictionary = any
	var sv_any: Variant = d.get("slot_values", {})
	if typeof(sv_any) != TYPE_DICTIONARY:
		return {"success": false, "error": "Slot values JSON missing slot_values object"}
	var incoming: Dictionary = sv_any

	var current: Dictionary = get_thread_slot_values(scope, thread_id)
	var next := current.duplicate(true) if merge else {}
	next.merge(incoming, true)
	var ok := set_thread_slot_values(scope, thread_id, next)
	return {"success": ok, "path": path, "merged": merge}

static func set_thread_settings(scope: String, thread_id: String, settings: Dictionary) -> bool:
	var st := load_state(scope)
	var threads_any: Variant = st.get("threads", {})
	var threads: Dictionary = threads_any if typeof(threads_any) == TYPE_DICTIONARY else {}
	threads[thread_id] = settings
	st["threads"] = threads
	return save_state(scope, st)

static func get_chain(scope: String, chain_id: String) -> Dictionary:
	var st := load_state(scope)
	var chains_any: Variant = st.get("chains", {})
	if typeof(chains_any) != TYPE_DICTIONARY:
		return {}
	var chains: Dictionary = chains_any
	var chain_any: Variant = chains.get(chain_id, {})
	if typeof(chain_any) != TYPE_DICTIONARY:
		return {}
	return normalize_chain(chain_any)

static func set_chain(scope: String, chain_id: String, chain: Dictionary) -> bool:
	var st := load_state(scope)
	var chains_any: Variant = st.get("chains", {})
	var chains: Dictionary = chains_any if typeof(chains_any) == TYPE_DICTIONARY else {}
	chains[chain_id] = normalize_chain(chain)
	st["chains"] = chains
	return save_state(scope, st)


static func normalize_chain(chain: Dictionary) -> Dictionary:
	var normalized: Dictionary = chain.duplicate(true)
	var blocks_any: Variant = normalized.get("blocks", [])
	var normalized_blocks: Array = []
	var used_ids: Dictionary = {}
	if typeof(blocks_any) == TYPE_ARRAY:
		var block_index: int = 0
		for block_any in (blocks_any as Array):
			if typeof(block_any) != TYPE_DICTIONARY:
				continue
			var block_data: Dictionary = (
				block_any as Dictionary
			).duplicate(true)
			var block_id: String = str(
				block_data.get("id", "")
			).strip_edges()
			if block_id.is_empty():
				block_id = "block-%03d" % (block_index + 1)
			var base_id: String = block_id
			var duplicate_index: int = 1
			while used_ids.has(block_id):
				duplicate_index += 1
				block_id = "%s-%d" % [base_id, duplicate_index]
			used_ids[block_id] = true
			block_data["id"] = block_id
			var override_any: Variant = block_data.get(
				"context_override",
				null
			)
			if typeof(override_any) == TYPE_DICTIONARY:
				block_data["context_override"] = _normalize_context_override(
					override_any
				)
			normalized_blocks.append(block_data)
			block_index += 1
	normalized["blocks"] = normalized_blocks
	var binding_any: Variant = normalized.get("context_binding", null)
	if typeof(binding_any) == TYPE_DICTIONARY:
		normalized["context_binding"] = _normalize_context_binding(binding_any)
	return normalized


static func _normalize_context_binding(binding_any: Variant) -> Dictionary:
	var binding: Dictionary = (binding_any as Dictionary).duplicate(true)
	return {
		"context_graph_artifact_id": str(
			binding.get("context_graph_artifact_id", "")
		).strip_edges(),
		"context_graph_version_id": str(
			binding.get("context_graph_version_id", "")
		).strip_edges(),
		"context_set_id": str(
			binding.get("context_set_id", "")
		).strip_edges(),
		"owner_source_id": str(
			binding.get("owner_source_id", "")
		).strip_edges(),
		"compiler_preset": str(
			binding.get("compiler_preset", "balanced")
		).to_lower(),
		"max_tokens": maxi(0, int(binding.get("max_tokens", 8000))),
	}


static func _normalize_context_override(override_any: Variant) -> Dictionary:
	var context_override: Dictionary = (
		override_any as Dictionary
	).duplicate(true)
	return {
		"traversal_depth": maxi(
			0,
			int(context_override.get("traversal_depth", 0))
		),
		"allowed_relationship_types": _unique_strings(
			context_override.get("allowed_relationship_types", [])
		),
		"pinned_node_ids": _unique_strings(
			context_override.get("pinned_node_ids", [])
		),
	}


static func _unique_strings(values_any: Variant) -> Array[String]:
	var values: Array[String] = []
	if typeof(values_any) != TYPE_ARRAY:
		return values
	for value_any in (values_any as Array):
		var value_id: String = str(value_any).strip_edges()
		if not value_id.is_empty() and not values.has(value_id):
			values.append(value_id)
	return values

static func delete_chain(scope: String, chain_id: String) -> bool:
	var st := load_state(scope)
	var chains_any: Variant = st.get("chains", {})
	if typeof(chains_any) != TYPE_DICTIONARY:
		return save_state(scope, st)
	var chains: Dictionary = chains_any
	if chains.has(chain_id):
		chains.erase(chain_id)
	st["chains"] = chains
	# Clean thread references
	var threads_any: Variant = st.get("threads", {})
	if typeof(threads_any) == TYPE_DICTIONARY:
		var threads: Dictionary = threads_any
		for tid in threads.keys():
			var t: Dictionary = threads.get(tid, {})
			if str(t.get("asset_id", "")) == chain_id:
				t["asset_id"] = ""
				threads[tid] = t
		st["threads"] = threads
	# Clean hub pointers
	var hub_any: Variant = st.get("hub", {})
	if typeof(hub_any) == TYPE_DICTIONARY:
		var hub: Dictionary = hub_any
		var hc_any: Variant = hub.get("chains", {})
		if typeof(hc_any) == TYPE_DICTIONARY:
			var hc: Dictionary = hc_any
			if hc.has(chain_id):
				hc.erase(chain_id)
			hub["chains"] = hc
			st["hub"] = hub
	return save_state(scope, st)

static func get_chain_hub_info(scope: String, chain_id: String) -> Dictionary:
	var st := load_state(scope)
	var hub_any: Variant = st.get("hub", {})
	if typeof(hub_any) != TYPE_DICTIONARY:
		return {}
	var hub: Dictionary = hub_any
	var hc_any: Variant = hub.get("chains", {})
	if typeof(hc_any) != TYPE_DICTIONARY:
		return {}
	var hc: Dictionary = hc_any
	var info_any: Variant = hc.get(chain_id, {})
	return info_any if typeof(info_any) == TYPE_DICTIONARY else {}

static func record_chain_hub_version(scope: String, chain_id: String, artifact_id: String) -> bool:
	var aid := String(artifact_id).strip_edges()
	if aid.is_empty():
		return false
	var st := load_state(scope)
	var hub_any: Variant = st.get("hub", {})
	var hub: Dictionary = hub_any if typeof(hub_any) == TYPE_DICTIONARY else {}
	var hc_any: Variant = hub.get("chains", {})
	var hc: Dictionary = hc_any if typeof(hc_any) == TYPE_DICTIONARY else {}
	var info_any: Variant = hc.get(chain_id, {})
	var info: Dictionary = info_any if typeof(info_any) == TYPE_DICTIONARY else {}
	var versions_any: Variant = info.get("versions", [])
	var versions: Array = versions_any if typeof(versions_any) == TYPE_ARRAY else []
	if not versions.has(aid):
		versions.append(aid)
	info["versions"] = versions
	info["latest_artifact_id"] = aid
	hc[chain_id] = info
	hub["chains"] = hc
	st["hub"] = hub
	return save_state(scope, st)

static func compile_chain_text(chain: Dictionary) -> String:
	var blocks_any: Variant = chain.get("blocks", [])
	if typeof(blocks_any) != TYPE_ARRAY:
		return ""
	var blocks: Array = blocks_any
	var parts: Array[String] = []
	for b_any in blocks:
		if typeof(b_any) != TYPE_DICTIONARY:
			continue
		var b: Dictionary = b_any
		if not bool(b.get("enabled", true)):
			continue
		var t := str(b.get("text", "")).strip_edges()
		if t.is_empty():
			continue
		parts.append(t)
	return "\n\n".join(parts)

static func render_chain_text(chain: Dictionary, slot_values: Dictionary = {}) -> String:
	# v1: slots are optional. Convention: placeholders in text are `{{slot_name}}`.
	var text := compile_chain_text(chain)
	var sv: Dictionary = slot_values if slot_values != null and typeof(slot_values) == TYPE_DICTIONARY else {}

	# Apply declared slots first (so defaults exist even if slot_values doesn't include them).
	var slots_any: Variant = chain.get("slots", [])
	if typeof(slots_any) == TYPE_ARRAY:
		for s_any in slots_any:
			if typeof(s_any) != TYPE_DICTIONARY:
				continue
			var s: Dictionary = s_any
			var name := str(s.get("name", "")).strip_edges()
			if name.is_empty():
				continue
			var val := str(sv.get(name, s.get("default", "")))
			text = text.replace("{{%s}}" % name, val)

	# Apply any remaining values (allows ad-hoc slots while keeping backwards compatibility).
	for k_any in sv.keys():
		var k := str(k_any).strip_edges()
		if k.is_empty():
			continue
		text = text.replace("{{%s}}" % k, str(sv.get(k_any, "")))

	return text


static func ensure_builtin_chains(scope: String) -> Dictionary:
	# Best-effort seeding: keeps SynTree usable out-of-the-box.
	# Only seeds into the SynTree editor scope (avoid surprising other consumers).
	var safe_scope := String(scope).strip_edges()
	if safe_scope.is_empty():
		safe_scope = "shared"
	if safe_scope != "syntree_editor":
		return load_state(safe_scope)

	var st := load_state(safe_scope)
	var chains_any: Variant = st.get("chains", {})
	var chains: Dictionary = chains_any if typeof(chains_any) == TYPE_DICTIONARY else {}

	var changed := false
	var cid := _builtin_godot_dev_agent_chain_id()
	if not chains.has(cid):
		chains[cid] = _builtin_godot_dev_agent_chain(cid)
		changed = true

	if changed:
		st["chains"] = chains
		save_state(safe_scope, st)

	return st

static func _builtin_godot_dev_agent_chain_id() -> String:
	return "godot_dev_agent.v1"

static func _builtin_godot_dev_agent_chain(chain_id: String) -> Dictionary:
	# A reusable “single-agent, multi-role” prompt chain.
	# This is intentionally tool-agnostic; SynTree UI provides the side-effect actions.
	return {
		"id": chain_id,
		"name": "Godot Dev Agent (v1)",
		"slots": [
			{"name": "project_name", "default": "Godot project", "description": "Human-readable project name."},
			{"name": "write_scope", "default": "Only modify files that are explicitly in Active Sources (or explicitly mentioned by path).", "description": "Safety scope for edits."},
			{"name": "run_spec", "default": "{\"scene_path\":\"res://path/to/scene.tscn\",\"state\":{},\"actions\":[]}", "description": "Run Spec JSON template (paste into Dev Agent → Run Spec tab)."},
			{"name": "session_data_dir_hint", "default": "Artifacts/backups are written under the configured Synesyn session data dir.", "description": "Where to look for artifacts/backups."},
		],
		"blocks": [
			{
				"label": "Role + objective",
				"enabled": true,
				"text": "You are the **Godot Dev Agent** operating inside **SynTree** for {{project_name}}.\n\nYour job is to iterate on a Godot project via a tight loop:\n1) understand the current behavior (from provided context + artifacts)\n2) propose minimal changes\n3) express those changes as a **unified diff patch**\n4) propose or update a **Run Spec** for deterministic verification\n5) interpret the next run’s artifacts and repeat.\n\nRespect scope: {{write_scope}}",
			},
			{
				"label": "Safety + side effects",
				"enabled": true,
				"text": "Safety rules:\n- Assume side-effect actions (apply patch / revert / run harness / publish) are **DISABLED unless explicitly stated enabled**.\n- When side effects are disabled, you may still produce: plans, analysis, proposed patches, and proposed run specs.\n- Never propose destructive actions (delete large directories, wipe data) unless explicitly requested.\n\nNote: {{session_data_dir_hint}}",
			},
			{
				"label": "Output contract",
				"enabled": true,
				"text": "When you recommend a change, output using this structure:\n\n## Plan\n- Bullet plan, small steps.\n\n## Patch (unified diff)\n- Provide a patch with `---` / `+++` / `@@` hunks.\n\n## Run Spec (JSON)\n- Provide a JSON object suitable for the Dev Agent Run Spec panel. Start from:\n{{run_spec}}\n\n## Verify\n- What artifacts to inspect (screenshot + ui metrics + last run JSON) and what success looks like.",
			},
			{
				"label": "Verification mindset",
				"enabled": true,
				"text": "Verification mindset:\n- Prefer deterministic setup via `test_apply_state(state)` on scene roots when available.\n- If state can’t be set deterministically yet, propose adding a small `test_apply_state` hook rather than hardcoding fragile node paths.\n- Keep fixes minimal and reversible.",
			},
		],
	}

