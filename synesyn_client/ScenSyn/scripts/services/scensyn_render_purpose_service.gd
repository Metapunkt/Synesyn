extends Node
class_name ScenSynRenderPurposeService

# ScenSyn -> Synpunkt render pipeline (generic, scenario-aware).
# - Discovers Synpunkt workflow presets (json.workflow artifacts) by tags
# - Selects best preset using fallback: scenario+collection -> collection -> global
# - Submits a SynesynRenderRequestV1 via hub render jobs (render.comfyui)
# - Never blocks gameplay; call sites should be cache-first / enqueue-only.
#
# How presets are selected (tagging workflow presets in SynPunkt):
# - In SynPunkt Render tab, use "Preset Tags" and click "Save Workflow Preset".
# - Tags are stored on the Hub in the `json.workflow` artifact metadata at:
#   metadata.preset.tags : Array[String]
# - Required tag:
#   - scensyn:render_purpose=<purpose_id>
# - Optional scoping tags:
#   - scensyn:collection=<collection_id>
#   - scensyn:scenario=<scenario_key>
#   - scensyn:character=<character_slug>
#   - scensyn:variant=<variant_id>
#   - scensyn:phase=<phase_id>
# Selection fallback:
# - scenario+collection -> collection -> global (purpose-only)

const HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
const SynesynRenderServiceScript = preload("res://addons/synesyn_core/scripts/synesyn_render_service.gd")
const SynesynRenderRequestV1Script = preload("res://addons/synesyn_core/scripts/synesyn_render_request_v1.gd")
const VisStoryV2BatchAdapterScript = preload("res://ScenSyn/scripts/services/internal/vis_story_v2_batch_adapter.gd")
const RenderPurposeUtilsScript = preload("res://ScenSyn/scripts/services/internal/scensyn_render_purpose_utils.gd")

const RenderCommonParamsUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_common_params_utils.gd")
const RenderWorkflowUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_workflow_utils.gd")
const GeneratedSpriteStoreScript = preload("res://ScenSyn/scripts/services/scensyn_generated_sprite_store.gd")

const PORTRAIT_CHECKPOINT_NAME := "Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors"
const PORTRAIT_DEFAULT_FRAME_COUNT := 4

signal render_submitted(job_id: String, render_purpose: String, meta: Dictionary)
signal sprite_materialized(job_id: String, character_name: String, animation_frames: String, dst_abs: String, meta: Dictionary)
signal sprite_materialization_failed(job_id: String, error: String, meta: Dictionary)
signal vis_story_images_ready(job_id: String, turn_id: int, image_paths: Array, meta: Dictionary)

var _hub: HubSubstrateClient = null
var _render: SynesynRenderService = null
var _session_id: String = ""
var _ws_armed: bool = false
var _pending_sprite_jobs: Dictionary = {} # {job_id: {collection, scenario, character_name, character_slug, animation_frames, frame_count, transparent_background, meta}}
var _pending_vis_story_jobs: Dictionary = {} # {job_id: {cycle_id, collection, scenario, ...}}
var _job_poll_timers: Dictionary = {} # {job_id: Timer}
var _job_poll_started_ms: Dictionary = {} # {job_id: int}
var _portrait_preset_auto_installed: bool = false
var _vis_story_v2_turn_preset_auto_installed: bool = false


func _ensure_ready() -> void:
	if _hub == null or not is_instance_valid(_hub):
		_hub = HubSubstrateClientScript.new()
		add_child(_hub)
		_hub.configure_from_runtime_config()
	if _render == null or not is_instance_valid(_render):
		_render = SynesynRenderServiceScript.new()
		add_child(_render)
		_render.set_hub_client(_hub)
	if _session_id.is_empty():
		_session_id = SynesynSession.get_or_create_session_id("scensyn")
	if not _ws_armed and _hub != null and is_instance_valid(_hub):
		_ws_armed = true
		_hub.ensure_ws_connected()
		_hub.ws_subscribe(["job.completed", "job.failed"])
		_hub.ws_replay(8.0, ["job.completed", "job.failed"])
		if not _hub.job_done.is_connected(_on_hub_job_done):
			_hub.job_done.connect(_on_hub_job_done)


func _on_hub_job_done(job_id: String, status: String, payload: Dictionary) -> void:
	var jid_check: String = str(job_id).strip_edges()
	if _pending_vis_story_jobs.has(jid_check):
		await _handle_vis_story_job_done(jid_check, status, payload)
	else:
		await _handle_job_done_for_materialization(job_id, status, payload)


func _handle_job_done_for_materialization(job_id: String, status: String, payload: Dictionary) -> void:
	var jid: String = str(job_id).strip_edges()
	if jid.is_empty():
		return
	if not _pending_sprite_jobs.has(jid):
		return
	var pending_any: Variant = _pending_sprite_jobs.get(jid, {})
	_pending_sprite_jobs.erase(jid)
	var pending: Dictionary = pending_any if typeof(pending_any) == TYPE_DICTIONARY else {}
	var meta_any: Variant = pending.get("meta", {})
	var meta: Dictionary = meta_any if typeof(meta_any) == TYPE_DICTIONARY else {}

	var st: String = str(status).strip_edges().to_lower()
	if st != "completed":
		sprite_materialization_failed.emit(jid, "job_%s" % st, meta)
		return

	var image_ids: Array[String] = RenderPurposeUtilsScript.extract_image_artifact_ids(payload)
	if image_ids.is_empty():
		var job_res: Dictionary = await _hub.render_get_job(jid)
		if bool(job_res.get("ok", false)):
			image_ids = RenderPurposeUtilsScript.extract_image_artifact_ids(job_res)

	if image_ids.is_empty():
		sprite_materialization_failed.emit(jid, "no_image_artifact_id", meta)
		return

	var store: ScenSynGeneratedSpriteStore = GeneratedSpriteStoreScript.new()
	var frame_count: int = int(pending.get("frame_count", 1))
	var transparent_bg: bool = (pending.get("transparent_background", false) == true)
	if frame_count > 1 and image_ids.size() > frame_count:
		image_ids = image_ids.slice(0, frame_count)

	var mat: Dictionary = await store.materialize_image_artifact_ids(
		_hub,
		image_ids,
		str(pending.get("collection", "default")),
		str(pending.get("scenario", "default")),
		str(pending.get("character_slug", "unknown")),
		str(pending.get("animation_frames", "idle")),
		1,
		transparent_bg
	)
	if not (mat.get("ok", false) == true) or int(mat.get("count", 0)) <= 0:
		sprite_materialization_failed.emit(jid, str(mat.get("error", "materialize_failed")), meta)
		return
	var first_path: String = ""
	var paths_any: Variant = mat.get("paths", [])
	if typeof(paths_any) == TYPE_ARRAY and (paths_any as Array).size() > 0:
		first_path = str((paths_any as Array)[0]).strip_edges()
	sprite_materialized.emit(
		jid,
		str(pending.get("character_name", "")),
		str(pending.get("animation_frames", "idle")),
		first_path,
		meta
	)


func _is_pending_job(jid: String) -> bool:
	return _pending_sprite_jobs.has(jid) or _pending_vis_story_jobs.has(jid)


func _start_job_poll_for_materialization(job_id: String) -> void:
	var jid: String = str(job_id).strip_edges()
	if jid.is_empty():
		return
	if _hub == null or not is_instance_valid(_hub):
		return
	if not _is_pending_job(jid):
		return
	if _job_poll_timers.has(jid):
		return

	var t := Timer.new()
	t.one_shot = false
	t.wait_time = 2.0
	add_child(t)
	_job_poll_timers[jid] = t
	_job_poll_started_ms[jid] = int(Time.get_ticks_msec())
	t.timeout.connect(func() -> void:
		await _poll_job_once_for_materialization(jid)
	)
	t.start()


func _stop_job_poll(jid: String) -> void:
	if _job_poll_timers.has(jid):
		var t_any: Variant = _job_poll_timers.get(jid, null)
		_job_poll_timers.erase(jid)
		_job_poll_started_ms.erase(jid)
		if is_instance_valid(t_any):
			var t: Timer = t_any
			t.stop()
			t.queue_free()


func _poll_job_once_for_materialization(jid: String) -> void:
	if jid.is_empty():
		return
	if _hub == null or not is_instance_valid(_hub):
		return
	if not _is_pending_job(jid):
		_stop_job_poll(jid)
		return

	var started_ms: int = int(_job_poll_started_ms.get(jid, int(Time.get_ticks_msec())))
	if (int(Time.get_ticks_msec()) - started_ms) > (600 * 1000):
		_stop_job_poll(jid)
		if _pending_sprite_jobs.has(jid):
			var pending_any: Variant = _pending_sprite_jobs.get(jid, {})
			_pending_sprite_jobs.erase(jid)
			var pending: Dictionary = pending_any if typeof(pending_any) == TYPE_DICTIONARY else {}
			var meta_any: Variant = pending.get("meta", {})
			var meta: Dictionary = meta_any if typeof(meta_any) == TYPE_DICTIONARY else {}
			sprite_materialization_failed.emit(jid, "job_poll_timeout", meta)
		elif _pending_vis_story_jobs.has(jid):
			_pending_vis_story_jobs.erase(jid)
			print("[RenderPurpose] vis_story child job %s poll timeout" % jid.left(12))
		return

	var job_res: Dictionary = await _hub.get_job(jid)
	if not (job_res.get("ok", false) == true):
		return
	var job_any: Variant = job_res.get("job", null)
	if typeof(job_any) != TYPE_DICTIONARY:
		return
	var job: Dictionary = job_any
	var status: String = str(job.get("status", "")).strip_edges().to_lower()
	if not (status in ["completed", "failed"]):
		return
	_stop_job_poll(jid)
	# Route through the unified handler so vis_story jobs are recognized
	await _on_hub_job_done(jid, status, {"job": job})


static func _slug_token(raw: String) -> String:
	var out: String = String(raw).strip_edges().to_lower()
	out = out.replace(" ", "_")
	out = out.replace("/", "_").replace("\\", "_").replace(":", "_")
	return out


func _character_profile_from_current_scenario(character_slug: String) -> Dictionary:
	var scen: Dictionary = Global.get_current_scenario() if (typeof(Global) != TYPE_NIL and Global and Global.has_method("get_current_scenario")) else {}
	var chars_any: Variant = scen.get("characters", [])
	if typeof(chars_any) != TYPE_ARRAY:
		return {}
	var chars: Array = chars_any
	var target: String = _slug_token(character_slug)
	if target.is_empty():
		return {}
	for c_any in chars:
		if typeof(c_any) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_any
		var c_name: String = str(c.get("name", "")).strip_edges()
		if _slug_token(c_name) == target:
			return c
	return {}


func _portrait_prompt_for_character(ctx: Dictionary, scen: Dictionary) -> String:
	var ch_raw: String = str(ctx.get("character_slug", "")).strip_edges()
	var ch_slug: String = _slug_token(ch_raw)
	var anim_frames: String = _slug_token(str(ctx.get("animation_frames", "")).strip_edges())
	if anim_frames.is_empty():
		anim_frames = "idle"

	var prof: Dictionary = _character_profile_from_current_scenario(ch_slug)
	var c_name: String = str(prof.get("name", ch_raw)).strip_edges()
	if c_name.is_empty():
		c_name = ch_raw if not ch_raw.is_empty() else "Narrator"
	var c_role: String = str(prof.get("role", "")).strip_edges()
	var c_desc: String = str(prof.get("description", "")).strip_edges()
	var c_instr: String = str(prof.get("behavioral_instructions", "")).strip_edges()
	if c_instr.length() > 320:
		c_instr = c_instr.substr(0, 320)

	var parts: Array[String] = []
	parts.append("2D game character sprite portrait, single subject, centered")
	parts.append("close-up portrait / head-and-shoulders, character occupies most of the frame")
	parts.append("character name: %s" % c_name)
	if not c_role.is_empty():
		parts.append("role: %s" % c_role)
	if not c_desc.is_empty():
		parts.append("character description: %s" % c_desc)
	if not c_instr.is_empty():
		parts.append("behavioral notes: %s" % c_instr)

	if anim_frames == "talking":
		parts.append("speaking, mouth open, subtle expressive face")
	else:
		parts.append("neutral mouth closed, calm pose")

	# IMPORTANT: do not include scenario location/setting in portraits; it causes "cityscape takeover".
	parts.append("solid pure white background (#ffffff), no environment, no buildings, no cityscape")
	parts.append("no text, no watermark, no logo, no UI")
	return "\n".join(parts)


func _ensure_portrait_workflow_preset_installed() -> void:
	# Goal: ensure at least one Hub workflow preset exists with tag:
	#   scensyn:render_purpose=portrait
	# We create it by cloning the most recent existing json.workflow (so it will work on the user's setup).
	if _portrait_preset_auto_installed:
		return
	_ensure_ready()

	var purpose_tag: String = _tag_render_purpose("portrait")
	var listing: Dictionary = await _list_workflow_presets(200)
	if listing.get("ok", false) == true:
		var presets_any: Variant = listing.get("presets", [])
		var presets: Array = presets_any if typeof(presets_any) == TYPE_ARRAY else []
		for p_any in presets:
			if typeof(p_any) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_any
			var preset_any: Variant = p.get("preset", {})
			var preset: Dictionary = preset_any if typeof(preset_any) == TYPE_DICTIONARY else {}
			var tags: Array[String] = RenderPurposeUtilsScript.preset_tags(preset)
			if RenderPurposeUtilsScript.has_tag(tags, purpose_tag):
				_portrait_preset_auto_installed = true
				return

	# Pick the newest non-archived workflow as a clone source.
	var best_aid: String = ""
	var best_created: String = ""
	if listing.get("ok", false) == true:
		var presets2_any: Variant = listing.get("presets", [])
		var presets2: Array = presets2_any if typeof(presets2_any) == TYPE_ARRAY else []
		for p_any in presets2:
			if typeof(p_any) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_any
			var preset_any: Variant = p.get("preset", {})
			var preset: Dictionary = preset_any if typeof(preset_any) == TYPE_DICTIONARY else {}
			if preset.get("archived", false) == true:
				continue
			var created := str(p.get("created_at", "")).strip_edges()
			var aid := str(p.get("artifact_id", "")).strip_edges()
			if aid.is_empty():
				continue
			if best_aid.is_empty() or (not created.is_empty() and created > best_created):
				best_aid = aid
				best_created = created

	var workflow_prompt: Dictionary = {}
	var source_aid: String = ""
	if not best_aid.is_empty():
		source_aid = best_aid
		var wf_res: Dictionary = await _hub.get_artifact_json(best_aid)
		if wf_res.get("ok", false) == true:
			var wf_any: Variant = wf_res.get("json", {})
			if typeof(wf_any) == TYPE_DICTIONARY:
				var wf_norm: Dictionary = RenderWorkflowUtilsScript.extract_comfy_prompt_graph(wf_any)
				if wf_norm.get("ok", false) == true:
					workflow_prompt = wf_norm.get("prompt", {})

	# If no existing workflow to clone, fall back to SynPunkt default (may not match installed models).
	if workflow_prompt.is_empty():
		var wf_txt: String = str(RenderWorkflowUtilsScript.default_workflow_json()).strip_edges()
		var parsed_any: Variant = JSON.parse_string(wf_txt)
		if typeof(parsed_any) == TYPE_DICTIONARY:
			var wf_norm2: Dictionary = RenderWorkflowUtilsScript.extract_comfy_prompt_graph(parsed_any)
			if wf_norm2.get("ok", false) == true:
				workflow_prompt = wf_norm2.get("prompt", {})

	if workflow_prompt.is_empty():
		return

	var preset_meta := {
		"name": "ScenSyn portrait preset (auto)",
		"tags": [purpose_tag],
		"model_family": "",
		"lineage_id": source_aid,
		"version": 1,
		"last_used_at": int(Time.get_unix_time_from_system()),
		"archived": false,
	}
	var meta := {
		"provenance": {
			"generated_by": "scensyn.auto_install.preset",
			"purpose": "portrait",
			"source_workflow_artifact_id": source_aid,
		},
		"preset": preset_meta,
	}
	var created: Dictionary = await _hub.create_artifact_inline_json("json.workflow", workflow_prompt, meta)
	if created.get("ok", false) == true:
		_portrait_preset_auto_installed = true


func _current_collection_and_scenario_key() -> Dictionary:
	var collection_id: String = "default"
	var scenario_key: String = "default"
	if typeof(Global) != TYPE_NIL and Global:
		collection_id = _slug_token(String(Global.current_collection_id))
		if Global.has_method("get_current_scenario"):
			var scen: Dictionary = Global.get_current_scenario()
			if typeof(scen) == TYPE_DICTIONARY:
				var key := String(scen.get("_scenario_name", "")).strip_edges()
				if key.is_empty():
					key = String(scen.get("name", "")).strip_edges()
				if not key.is_empty():
					scenario_key = _slug_token(key)
	return {"collection_id": collection_id, "scenario_key": scenario_key}


static func _tag_render_purpose(render_purpose: String) -> String:
	return "scensyn:render_purpose=%s" % _slug_token(render_purpose)


static func _tag_collection(collection_id: String) -> String:
	return "scensyn:collection=%s" % _slug_token(collection_id)


static func _tag_scenario(scenario_key: String) -> String:
	return "scensyn:scenario=%s" % _slug_token(scenario_key)


static func _tag_character(character_slug: String) -> String:
	return "scensyn:character=%s" % _slug_token(character_slug)


static func _tag_variant(variant_id: String) -> String:
	return "scensyn:variant=%s" % _slug_token(variant_id)


static func _tag_phase(phase_id: String) -> String:
	return "scensyn:phase=%s" % _slug_token(phase_id)


func _list_workflow_presets(limit: int = 200) -> Dictionary:
	# Returns {ok, presets:[{artifact_id, created_at, metadata, preset}]}
	_ensure_ready()
	var res: Dictionary = await _hub.query_artifacts_by_type("json.workflow", limit)
	if not (res.get("ok", false) == true):
		return {"ok": false, "error": res.get("error", res)}
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows_any: Variant = result.get("rows", [])
	var rows: Array = rows_any if typeof(rows_any) == TYPE_ARRAY else []
	var presets: Array = []
	for r_any in rows:
		if typeof(r_any) != TYPE_ARRAY:
			continue
		var row: Array = r_any
		var aid := str(RenderPurposeUtilsScript.row_get(cols, row, "id")).strip_edges()
		if aid.is_empty():
			continue
		var created := str(RenderPurposeUtilsScript.row_get(cols, row, "created_at")).strip_edges()
		var meta_txt := str(RenderPurposeUtilsScript.row_get(cols, row, "metadata_json")).strip_edges()
		if meta_txt.is_empty():
			meta_txt = str(RenderPurposeUtilsScript.row_get(cols, row, "metadata")).strip_edges()
		var md := RenderPurposeUtilsScript.metadata_dict_from_text(meta_txt)
		var preset_any: Variant = md.get("preset", {})
		var preset: Dictionary = preset_any if typeof(preset_any) == TYPE_DICTIONARY else {}
		presets.append({"artifact_id": aid, "created_at": created, "metadata": md, "preset": preset})
	return {"ok": true, "presets": presets}


func select_workflow_preset_for_render_purpose(render_purpose: String, ctx: Dictionary = {}) -> Dictionary:
	# ctx may include:
	# - character_slug, variant_id, phase_id
	# Returns {ok, artifact_id, preset, tags, created_at}
	var purpose_tag: String = _tag_render_purpose(render_purpose)
	var collection_scen: Dictionary = _current_collection_and_scenario_key()
	var collection_id: String = str(collection_scen.get("collection_id", "default"))
	var scenario_key: String = str(collection_scen.get("scenario_key", "default"))
	var collection_tag: String = _tag_collection(collection_id)
	var scenario_tag: String = _tag_scenario(scenario_key)

	var character_slug: String = _slug_token(str(ctx.get("character_slug", "")).strip_edges())
	var variant_id: String = _slug_token(str(ctx.get("variant_id", "")).strip_edges())
	var phase_id: String = _slug_token(str(ctx.get("phase_id", "")).strip_edges())

	var desired_tags: Array[String] = []
	if not character_slug.is_empty():
		desired_tags.append(_tag_character(character_slug))
	if not variant_id.is_empty():
		desired_tags.append(_tag_variant(variant_id))
	if not phase_id.is_empty():
		desired_tags.append(_tag_phase(phase_id))

	var listing: Dictionary = await _list_workflow_presets(200)
	if not (listing.get("ok", false) == true):
		return {"ok": false, "error": listing.get("error", "workflow_list_failed")}
	var presets_any: Variant = listing.get("presets", [])
	var presets: Array = presets_any if typeof(presets_any) == TYPE_ARRAY else []

	var best: Dictionary = {}
	var best_score := -999999
	var best_version := -1
	var best_created := ""

	# First pass: prefer non-archived; second pass: allow archived if nothing else matches.
	for pass_idx in [0, 1]:
		for p_any in presets:
			if typeof(p_any) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_any
			var preset_any: Variant = p.get("preset", {})
			var preset: Dictionary = preset_any if typeof(preset_any) == TYPE_DICTIONARY else {}
			var archived: bool = (preset.get("archived", false) == true)
			if pass_idx == 0 and archived:
				continue

			var tags: Array[String] = RenderPurposeUtilsScript.preset_tags(preset)
			if not RenderPurposeUtilsScript.has_tag(tags, purpose_tag):
				continue

			var score := 0
			var has_collection := RenderPurposeUtilsScript.has_tag(tags, collection_tag)
			var has_scenario := RenderPurposeUtilsScript.has_tag(tags, scenario_tag)
			if has_collection:
				score += 10
			if has_scenario:
				score += 100
			for dt in desired_tags:
				if RenderPurposeUtilsScript.has_tag(tags, dt):
					score += 3

			# If a preset declares scenario/collection, it must match the current scenario/collection.
			var declared_scenario_tag := RenderPurposeUtilsScript.first_tag_with_prefix(tags, "scensyn:scenario=")
			if not declared_scenario_tag.is_empty() and declared_scenario_tag != scenario_tag:
				continue
			var declared_collection_tag := RenderPurposeUtilsScript.first_tag_with_prefix(tags, "scensyn:collection=")
			if not declared_collection_tag.is_empty() and declared_collection_tag != collection_tag:
				continue
			var declared_character_tag := RenderPurposeUtilsScript.first_tag_with_prefix(tags, "scensyn:character=")
			if not declared_character_tag.is_empty():
				# If workflow is character-specific, only use it when the caller provided a character and it matches.
				if character_slug.is_empty() or declared_character_tag != _tag_character(character_slug):
					continue
			var declared_variant_tag := RenderPurposeUtilsScript.first_tag_with_prefix(tags, "scensyn:variant=")
			if not declared_variant_tag.is_empty():
				if variant_id.is_empty() or declared_variant_tag != _tag_variant(variant_id):
					continue
			var declared_phase_tag := RenderPurposeUtilsScript.first_tag_with_prefix(tags, "scensyn:phase=")
			if not declared_phase_tag.is_empty():
				if phase_id.is_empty() or declared_phase_tag != _tag_phase(phase_id):
					continue

			var version := int(preset.get("version", 0))
			var created := str(p.get("created_at", "")).strip_edges()

			if score > best_score:
				best = p
				best_score = score
				best_version = version
				best_created = created
			elif score == best_score:
				if version > best_version:
					best = p
					best_version = version
					best_created = created
				elif version == best_version and (not created.is_empty()) and created > best_created:
					best = p
					best_created = created

		if not best.is_empty():
			break

	if best.is_empty():
		return {"ok": false, "error": "no_matching_workflow_preset", "render_purpose": render_purpose, "purpose_tag": purpose_tag}

	var preset_best_any: Variant = best.get("preset", {})
	var preset_best: Dictionary = preset_best_any if typeof(preset_best_any) == TYPE_DICTIONARY else {}
	var metadata_best_any: Variant = best.get("metadata", {})
	var metadata_best: Dictionary = metadata_best_any if typeof(metadata_best_any) == TYPE_DICTIONARY else {}
	return {
		"ok": true,
		"artifact_id": str(best.get("artifact_id", "")).strip_edges(),
		"preset": preset_best,
		"metadata": metadata_best,
		"tags": RenderPurposeUtilsScript.preset_tags(preset_best),
		"created_at": str(best.get("created_at", "")).strip_edges(),
		"score": best_score,
	}


func _ensure_vis_story_v2_turn_workflow_preset_installed() -> void:
	if _vis_story_v2_turn_preset_auto_installed:
		return
	_ensure_ready()

	var purpose_tag: String = _tag_render_purpose("vis_story_v2_turn")
	var listing: Dictionary = await _list_workflow_presets(200)
	if listing.get("ok", false) == true:
		var presets_any: Variant = listing.get("presets", [])
		var presets: Array = presets_any if typeof(presets_any) == TYPE_ARRAY else []
		for p_any in presets:
			if typeof(p_any) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_any
			var preset_any: Variant = p.get("preset", {})
			var preset: Dictionary = preset_any if typeof(preset_any) == TYPE_DICTIONARY else {}
			var tags: Array[String] = RenderPurposeUtilsScript.preset_tags(preset)
			if RenderPurposeUtilsScript.has_tag(tags, purpose_tag):
				_vis_story_v2_turn_preset_auto_installed = true
				return

	var workflow_prompt: Dictionary = RenderPurposeUtilsScript.build_vis_story_v2_scheduler_prompt_graph()
	if workflow_prompt.is_empty():
		return

	var preset_meta := {
		"name": "ScenSyn vis_story_v2 turn scheduler (auto)",
		"tags": [purpose_tag],
		"model_family": "sdxl",
		"lineage_id": "vis_story_v2_aratitun_sdxl_scheduler",
		"version": 1,
		"last_used_at": int(Time.get_unix_time_from_system()),
		"archived": false,
	}
	var meta := {
		"provenance": {
			"generated_by": "scensyn.auto_install.preset",
			"purpose": "vis_story_v2_turn",
		},
		"preset": preset_meta,
		"render_profile": {
			"profile_id": "vis_story_v2_aratitun_sdxl_scheduler",
			"profile_kind": "scensyn_turn_scheduler",
			"entry_node_id": "1",
		},
	}
	var created: Dictionary = await _hub.create_artifact_inline_json("json.workflow", workflow_prompt, meta)
	if created.get("ok", false) == true:
		_vis_story_v2_turn_preset_auto_installed = true


func _build_default_prompt_for_purpose(render_purpose: String, ctx: Dictionary) -> String:
	var collection_scen: Dictionary = _current_collection_and_scenario_key()
	var scenario_key: String = str(collection_scen.get("scenario_key", "default"))
	var collection_id: String = str(collection_scen.get("collection_id", "default"))
	var scen: Dictionary = Global.get_current_scenario() if (typeof(Global) != TYPE_NIL and Global and Global.has_method("get_current_scenario")) else {}
	var scenario_title: String = String(scen.get("name", scenario_key)).strip_edges()
	var location_setting: String = String(scen.get("location and setting", scen.get("location_and_setting", ""))).strip_edges()
	var objective_text: String = String(scen.get("objective", "")).strip_edges()

	if _slug_token(render_purpose) == "portrait":
		return _portrait_prompt_for_character(ctx, scen)

	var parts: Array[String] = []
	parts.append("render purpose: %s" % _slug_token(render_purpose))
	parts.append("collection: %s" % collection_id)
	parts.append("scenario: %s" % (scenario_title if not scenario_title.is_empty() else scenario_key))
	if not location_setting.is_empty():
		parts.append("location: %s" % location_setting)
	if not objective_text.is_empty():
		parts.append("objective: %s" % objective_text)
	if ctx.has("character_slug"):
		var ch: String = str(ctx.get("character_slug", "")).strip_edges()
		if not ch.is_empty():
			parts.append("character: %s" % ch)
	if ctx.has("variant_id"):
		var v: String = str(ctx.get("variant_id", "")).strip_edges()
		if not v.is_empty():
			parts.append("variant: %s" % v)
	if ctx.has("phase_id"):
		var ph: String = str(ctx.get("phase_id", "")).strip_edges()
		if not ph.is_empty():
			parts.append("phase: %s" % ph)
	return "\n".join(parts)


func submit_render_purpose(render_purpose: String, opts: Dictionary = {}) -> Dictionary:
	# opts supports:
	# - prompt, negative, seed, steps, cfg, denoise, width, height
	# - character_slug, variant_id, phase_id (for preset selection and prompt defaults)
	# - patches: Array (additional explicit patches)
	# - materialize_to_sprites_generated: bool (portrait use-case)
	# - animation_frames: String (folder name under <character>/..., e.g. "idle", "talking")
	_ensure_ready()
	var ctx: Dictionary = {
		"character_slug": str(opts.get("character_slug", "")).strip_edges(),
		"variant_id": str(opts.get("variant_id", "")).strip_edges(),
		"phase_id": str(opts.get("phase_id", "")).strip_edges(),
		"animation_frames": str(opts.get("animation_frames", "")).strip_edges(),
	}

	if _slug_token(render_purpose) == "portrait":
		await _ensure_portrait_workflow_preset_installed()

	var sel: Dictionary = await select_workflow_preset_for_render_purpose(render_purpose, ctx)
	var workflow_artifact_id: String = ""
	var workflow_prompt: Dictionary = {}
	var used_default_workflow: bool = false
	var workflow_hash_sha256: String = ""

	if sel.get("ok", false) == true:
		workflow_artifact_id = str(sel.get("artifact_id", "")).strip_edges()
		if workflow_artifact_id.is_empty():
			return {"ok": false, "error": "selected_workflow_missing_artifact_id"}

		var wf_res: Dictionary = await _hub.get_artifact_json(workflow_artifact_id)
		if not (wf_res.get("ok", false) == true):
			return {"ok": false, "error": "failed_to_load_workflow", "details": wf_res}
		var wf_raw_any: Variant = wf_res.get("json", {})
		if typeof(wf_raw_any) != TYPE_DICTIONARY:
			return {"ok": false, "error": "workflow_json_invalid", "artifact_id": workflow_artifact_id}
		var wf_wrapped: Dictionary = wf_raw_any
		var wf_norm: Dictionary = RenderWorkflowUtilsScript.extract_comfy_prompt_graph(wf_wrapped)
		if not (wf_norm.get("ok", false) == true):
			return {"ok": false, "error": "workflow_invalid", "details": wf_norm}
		workflow_prompt = wf_norm.get("prompt", {})
		workflow_hash_sha256 = str(sel.get("hash_sha256", "")).strip_edges()
	else:
		# Fallback: if no preset matches, use SynPunkt's default workflow so ScenSyn can still render.
		if str(sel.get("error", "")).strip_edges() != "no_matching_workflow_preset":
			return sel
		used_default_workflow = true
		var wf_txt: String = str(RenderWorkflowUtilsScript.default_workflow_json()).strip_edges()
		var parsed_any: Variant = JSON.parse_string(wf_txt)
		if typeof(parsed_any) != TYPE_DICTIONARY:
			return {"ok": false, "error": "default_workflow_parse_failed"}
		var wf_norm2: Dictionary = RenderWorkflowUtilsScript.extract_comfy_prompt_graph(parsed_any)
		if not (wf_norm2.get("ok", false) == true):
			return {"ok": false, "error": "default_workflow_invalid", "details": wf_norm2}
		workflow_prompt = wf_norm2.get("prompt", {})
		workflow_hash_sha256 = RenderWorkflowUtilsScript.hash_sha256_hex(RenderWorkflowUtilsScript.canonical_json_bytes(workflow_prompt))

	var base_patches_any: Variant = opts.get("patches", [])
	var base_patches: Array = base_patches_any if typeof(base_patches_any) == TYPE_ARRAY else []

	var values: Dictionary = {}
	var prompt_text: String = str(opts.get("prompt", "")).strip_edges()
	if prompt_text.is_empty():
		prompt_text = _build_default_prompt_for_purpose(render_purpose, ctx)
	values["prompt"] = prompt_text
	var neg_text: String = str(opts.get("negative", "")).strip_edges()
	if neg_text.is_empty() and _slug_token(render_purpose) == "portrait":
		neg_text = "landscape, wide shot, panorama, aerial view, skyline, cityscape, buildings, streets, wind turbines, windmills, turbines, environment background, multiple people, crowd, text, watermark, logo, UI"
	if not neg_text.is_empty():
		values["negative"] = neg_text
	if opts.has("seed"):
		values["seed"] = int(opts.get("seed", 0))
	if opts.has("steps"):
		values["steps"] = int(opts.get("steps", 20))
	if opts.has("cfg"):
		values["cfg"] = float(opts.get("cfg", 7.0))
	if opts.has("denoise"):
		values["denoise"] = float(opts.get("denoise", 1.0))
	if opts.has("width"):
		values["width"] = int(opts.get("width", 1024))
	elif _slug_token(render_purpose) == "portrait":
		values["width"] = 768
	if opts.has("height"):
		values["height"] = int(opts.get("height", 1024))
	elif _slug_token(render_purpose) == "portrait":
		values["height"] = 1024

	var frame_count: int = int(opts.get("frame_count", 1))
	if frame_count <= 0:
		frame_count = 1
	if _slug_token(render_purpose) == "portrait" and frame_count == 1:
		frame_count = PORTRAIT_DEFAULT_FRAME_COUNT

	var patches: Array = RenderPurposeUtilsScript.patches_with_common_params(workflow_prompt, base_patches, values)

	# Portrait: force checkpoint + batch_size (frame sequences) when possible.
	if _slug_token(render_purpose) == "portrait":
		var ckpt_name: String = str(opts.get("checkpoint_name", PORTRAIT_CHECKPOINT_NAME)).strip_edges()
		if not ckpt_name.is_empty():
			var tgt_ckpt: Dictionary = RenderPurposeUtilsScript.detect_checkpoint_target(workflow_prompt)
			if not tgt_ckpt.is_empty():
				RenderCommonParamsUtilsScript.upsert_patch(patches, str(tgt_ckpt.get("node_id", "")), str(tgt_ckpt.get("input", "ckpt_name")), ckpt_name)
		if frame_count > 1:
			var tgt_bs: Dictionary = RenderPurposeUtilsScript.detect_latent_batch_size_target(workflow_prompt)
			if not tgt_bs.is_empty():
				RenderCommonParamsUtilsScript.upsert_patch(patches, str(tgt_bs.get("node_id", "")), str(tgt_bs.get("input", "batch_size")), int(frame_count))

	var comfy_url := RenderPurposeUtilsScript.default_comfy_url_from_runtime_config()
	var routing_mode := RenderPurposeUtilsScript.default_routing_mode_from_runtime_config()
	if routing_mode != "hub":
		# ScenSyn uses hub by default so renders are async and never block.
		routing_mode = "hub"

	var collection_scen: Dictionary = _current_collection_and_scenario_key()
	var render_meta := {
		"render_purpose": _slug_token(render_purpose),
		"collection": str(collection_scen.get("collection_id", "default")),
		"scenario": str(collection_scen.get("scenario_key", "default")),
		"character": _slug_token(str(ctx.get("character_slug", ""))),
		"variant": _slug_token(str(ctx.get("variant_id", ""))),
		"phase": _slug_token(str(ctx.get("phase_id", ""))),
	}

	var req := {
		"schema_version": 1,
		"kind": "synesyn.render_request",
		"routing": {"mode": routing_mode, "provider": "comfyui", "comfy_base_url": comfy_url},
		"output_routing": {
			"mode": "substrate",
			"render_request_artifact_type": "json.render_request",
			"images": {"artifact_type": "image.generated"},
		},
		"workflow": {"inline": workflow_prompt} if used_default_workflow else {"artifact_id": workflow_artifact_id},
		"patches": patches,
		"client": {
			"app_id": "scensyn",
			"session_id": _session_id,
			"request_id": "scensyn_%s_%d" % [_slug_token(render_purpose), int(Time.get_unix_time_from_system())],
			"turn_id": str(SynesynSession.get_current_turn_id("scensyn")).strip_edges(),
		},
		"refs": {
			"scensyn": render_meta,
			"workflow_artifact_id": workflow_artifact_id,
			"workflow_hash_sha256": workflow_hash_sha256,
			"used_default_workflow": used_default_workflow,
		},
	}

	var norm: Dictionary = SynesynRenderRequestV1Script.normalize(req, {"app_id": "scensyn"})
	if not (norm.get("ok", false) == true):
		return norm
	var submit: Dictionary = await _render.submit_render_request(norm.get("request", {}))
	if not (submit.get("ok", false) == true):
		return submit

	var job_id: String = str(submit.get("job_id", "")).strip_edges()
	if not job_id.is_empty():
		render_submitted.emit(job_id, _slug_token(render_purpose), render_meta)

		# Optional: materialize completed renders into workspace sprite folders.
		# NOTE: This only triggers on job completion and is best-effort (local workspaces).
		var do_mat: bool = (opts.get("materialize_to_sprites_generated", false) == true)
		if do_mat:
			var anim_frames: String = str(opts.get("animation_frames", "idle")).strip_edges()
			if anim_frames.is_empty():
				anim_frames = "idle"
			var char_name: String = str(opts.get("character_slug", "")).strip_edges()
			var char_slug: String = _slug_token(char_name)
			var transparent_bg: bool = (opts.get("transparent_background", false) == true)
			if _slug_token(render_purpose) == "portrait" and not opts.has("transparent_background"):
				transparent_bg = true
			_pending_sprite_jobs[job_id] = {
				"collection": str(render_meta.get("collection", "default")),
				"scenario": str(render_meta.get("scenario", "default")),
				"character_name": char_name,
				"character_slug": char_slug,
				"animation_frames": _slug_token(anim_frames),
				"frame_count": frame_count,
				"transparent_background": transparent_bg,
				"meta": render_meta,
			}
			# Deterministic fallback (poll) in case WS events are unavailable.
			_start_job_poll_for_materialization(job_id)
	return {
		"ok": true,
		"job_id": job_id,
		"workflow_artifact_id": workflow_artifact_id,
		"used_default_workflow": used_default_workflow,
		"render_purpose": _slug_token(render_purpose),
		"meta": render_meta,
		"submit": submit,
	}


func submit_vis_story_v2_turn_render(story_json_path: String, cycle_id: int, opts: Dictionary = {}) -> Dictionary:
	_ensure_ready()
	var json_path := String(story_json_path).strip_edges()
	if json_path.is_empty():
		return {"ok": false, "error": "story_json_path_required"}
	var submission_mode := str(opts.get("render_submission_mode", "scheduler")).strip_edges().to_lower()
	if submission_mode == "batch_fanout":
		return await _submit_vis_story_v2_turn_render_batch(json_path, cycle_id, opts)

	var render_purpose := _slug_token(str(opts.get("render_purpose", "vis_story_v2_turn")).strip_edges())
	if render_purpose.is_empty():
		render_purpose = "vis_story_v2_turn"
	if render_purpose == "vis_story_v2_turn":
		await _ensure_vis_story_v2_turn_workflow_preset_installed()

	var sel: Dictionary = await select_workflow_preset_for_render_purpose(render_purpose, {})
	if not bool(sel.get("ok", false)):
		return sel

	var workflow_artifact_id := str(sel.get("artifact_id", "")).strip_edges()
	if workflow_artifact_id.is_empty():
		return {"ok": false, "error": "selected_workflow_missing_artifact_id"}

	var entry_node_id := RenderPurposeUtilsScript.render_profile_entry_node_id(sel, "1")
	var scheduler_workflow_path := str(opts.get("scheduler_workflow_path", "")).strip_edges()
	if scheduler_workflow_path.is_empty():
		scheduler_workflow_path = RenderPurposeUtilsScript.default_visualsystem_path("vis_story/aratitun_option_c_sdxl_autosketch.json")
	var scheduler_presets_path := str(opts.get("scheduler_presets_path", "")).strip_edges()
	if scheduler_presets_path.is_empty():
		scheduler_presets_path = RenderPurposeUtilsScript.default_visualsystem_path("vis_story_v2/config/presets.yaml")
	var scheduler_output_root := str(opts.get("scheduler_output_root", "")).strip_edges()
	if scheduler_output_root.is_empty():
		var collection_scen: Dictionary = _current_collection_and_scenario_key()
		scheduler_output_root = "scensyn/vis_story_v2/%s" % str(collection_scen.get("scenario_key", "default"))
	var scheduler_throttle_ms := int(opts.get("scheduler_throttle_ms", 300))

	var comfy_url := RenderPurposeUtilsScript.default_comfy_url_from_runtime_config()
	var routing_mode := "hub"
	var request_id := "scensyn_vis_story_v2_%d" % int(Time.get_unix_time_from_system())
	var scenario_any: Variant = opts.get("scenario", {})
	var scenario: Dictionary = scenario_any if typeof(scenario_any) == TYPE_DICTIONARY else {}
	var translator_any: Variant = opts.get("translator_payload", {})
	var translator_payload: Dictionary = translator_any if typeof(translator_any) == TYPE_DICTIONARY else {}

	var patches: Array = [
		{"node_id": entry_node_id, "input": "workflow_path", "value": scheduler_workflow_path},
		{"node_id": entry_node_id, "input": "comfy_base_url", "value": comfy_url},
		{"node_id": entry_node_id, "input": "json_path", "value": json_path},
		{"node_id": entry_node_id, "input": "presets_path", "value": scheduler_presets_path},
		{"node_id": entry_node_id, "input": "cycle_start", "value": int(cycle_id)},
		{"node_id": entry_node_id, "input": "cycle_end", "value": int(cycle_id)},
		{"node_id": entry_node_id, "input": "override_panels_to_render", "value": 0},
		{"node_id": entry_node_id, "input": "override_selection_mode", "value": "use_json"},
		{"node_id": entry_node_id, "input": "override_panel_indices_csv", "value": ""},
		{"node_id": entry_node_id, "input": "throttle_ms", "value": int(scheduler_throttle_ms)},
		{"node_id": entry_node_id, "input": "output_root", "value": scheduler_output_root},
	]

	var collection_scen: Dictionary = _current_collection_and_scenario_key()
	var req := {
		"schema_version": 1,
		"kind": "synesyn.render_request",
		"routing": {"mode": routing_mode, "provider": "comfyui", "comfy_base_url": comfy_url},
		"output_routing": {
			"mode": "substrate",
			"render_request_artifact_type": "json.render_request",
			"images": {"artifact_type": "image.scensyn.vis_story_panel"},
		},
		"workflow": {"artifact_id": workflow_artifact_id},
		"patches": patches,
		"client": {
			"app_id": "scensyn",
			"session_id": _session_id,
			"request_id": request_id,
			"turn_id": str(SynesynSession.get_current_turn_id("scensyn")).strip_edges(),
		},
		"refs": {
			"scensyn": {
				"render_purpose": render_purpose,
				"collection": str(collection_scen.get("collection_id", "default")),
				"scenario": str(collection_scen.get("scenario_key", "default")),
				"vis_story_cycle_version": "v2",
				"cycle_id": int(cycle_id),
			},
			"workflow_artifact_id": workflow_artifact_id,
			"story_json_path": json_path,
			"translator_contract_type": str(translator_payload.get("contract_type", "")).strip_edges(),
			"scenario_name": str(scenario.get("name", "")).strip_edges(),
		},
	}

	var norm: Dictionary = SynesynRenderRequestV1Script.normalize(req, {"app_id": "scensyn"})
	if not bool(norm.get("ok", false)):
		return norm
	var submit: Dictionary = await _render.submit_render_request(norm.get("request", {}))
	if not bool(submit.get("ok", false)):
		return submit

	var job_id := str(submit.get("job_id", "")).strip_edges()
	var render_meta := {
		"render_purpose": render_purpose,
		"collection": str(collection_scen.get("collection_id", "default")),
		"scenario": str(collection_scen.get("scenario_key", "default")),
		"vis_story_cycle_version": "v2",
		"cycle_id": int(cycle_id),
	}
	if not job_id.is_empty():
		render_submitted.emit(job_id, render_purpose, render_meta)
	return {
		"ok": true,
		"job_id": job_id,
		"render_purpose": render_purpose,
		"workflow_artifact_id": workflow_artifact_id,
		"entry_node_id": entry_node_id,
		"story_json_path": json_path,
		"meta": render_meta,
		"submit": submit,
	}


func _submit_vis_story_v2_turn_render_batch(story_json_path: String, cycle_id: int, opts: Dictionary = {}) -> Dictionary:
	var workflow_path := str(opts.get("scheduler_workflow_path", "")).strip_edges()
	if workflow_path.is_empty():
		workflow_path = RenderPurposeUtilsScript.default_visualsystem_path("vis_story/aratitun_option_c_sdxl_autosketch.json")

	var scenario_any: Variant = opts.get("scenario", {})
	var scenario: Dictionary = scenario_any if typeof(scenario_any) == TYPE_DICTIONARY else {}
	var translator_any: Variant = opts.get("translator_payload", {})
	var translator_payload: Dictionary = translator_any if typeof(translator_any) == TYPE_DICTIONARY else {}
	var collection_scen: Dictionary = _current_collection_and_scenario_key()
	var comfy_url := RenderPurposeUtilsScript.default_comfy_url_from_runtime_config()
	var output_root := str(opts.get("scheduler_output_root", "")).strip_edges()
	if output_root.is_empty():
		output_root = "scensyn/vis_story_v2/%s" % str(collection_scen.get("scenario_key", "default"))
	var batch_request_id := "scensyn_vis_story_batch_%d" % int(Time.get_unix_time_from_system())

	var scaffolding_path := RenderPurposeUtilsScript.default_visualsystem_path("vis_story_v2/config/prompt_scaffolding.json")

	var build_res: Dictionary = VisStoryV2BatchAdapterScript.build_render_batch_request(
		story_json_path,
		cycle_id,
		{
			"workflow_path": workflow_path,
			"comfy_url": comfy_url,
			"session_id": _session_id,
			"turn_id": str(SynesynSession.get_current_turn_id("scensyn")).strip_edges(),
			"collection_id": str(collection_scen.get("collection_id", "default")),
			"scenario_key": str(collection_scen.get("scenario_key", "default")),
			"output_root": output_root,
			"batch_request_id": batch_request_id,
			"scaffolding_path": scaffolding_path,
		}
	)
	if not bool(build_res.get("ok", false)):
		return build_res

	var batch_request: Dictionary = build_res.get("batch_request", {})
	var items_any: Variant = batch_request.get("items", [])
	var items: Array = items_any if typeof(items_any) == TYPE_ARRAY else []
	for i in range(items.size()):
		var item_any: Variant = items[i]
		if typeof(item_any) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_any
		var child_request: Dictionary = item.get("request", {}) if typeof(item.get("request", {})) == TYPE_DICTIONARY else {}
		var norm: Dictionary = SynesynRenderRequestV1Script.normalize(child_request, {"app_id": "scensyn"})
		if not bool(norm.get("ok", false)):
			return {"ok": false, "error": "child_render_request_invalid", "index": i, "details": norm}
		item["request"] = norm.get("request", {})
		items[i] = item
	batch_request["items"] = items

	if _hub == null or not _hub.has_method("submit_render_batch"):
		return {"ok": false, "error": "hub_submit_render_batch_unavailable"}
	var submit: Dictionary = await _hub.submit_render_batch(batch_request)
	if not bool(submit.get("ok", false)):
		return submit

	var job_id := str(submit.get("job_id", "")).strip_edges()
	var render_meta := {
		"render_purpose": "vis_story_batch",
		"collection": str(collection_scen.get("collection_id", "default")),
		"scenario": str(collection_scen.get("scenario_key", "default")),
		"vis_story_cycle_version": "v2_batch_fanout",
		"cycle_id": int(cycle_id),
		"selected_panels": build_res.get("selected_panels", []),
	}
	if not job_id.is_empty():
		_pending_vis_story_jobs[job_id] = render_meta.duplicate()
		render_submitted.emit(job_id, "vis_story_batch", render_meta)
		_start_job_poll_for_materialization(job_id)
	return {
		"ok": true,
		"job_id": job_id,
		"render_purpose": "vis_story_batch",
		"story_json_path": story_json_path,
		"workflow_path": workflow_path,
		"meta": render_meta,
		"submit": submit,
		"selected_panels": build_res.get("selected_panels", []),
		"translator_contract_type": str(translator_payload.get("contract_type", "")).strip_edges(),
		"scenario_name": str(scenario.get("name", "")).strip_edges(),
	}


func _handle_vis_story_job_done(job_id: String, status: String, payload: Dictionary) -> void:
	var meta_any: Variant = _pending_vis_story_jobs.get(job_id, {})
	_pending_vis_story_jobs.erase(job_id)
	var meta: Dictionary = meta_any if typeof(meta_any) == TYPE_DICTIONARY else {}
	_stop_job_poll(job_id)

	if str(status).strip_edges().to_lower() != "completed":
		print("[RenderPurpose] vis_story job %s status=%s — skipping materialization" % [job_id.left(12), status])
		return

	# Batch parent jobs complete with child_job_ids but no images.
	# Register each child so we catch their individual completions.
	var child_ids: Array[String] = RenderPurposeUtilsScript.extract_child_job_ids(payload)
	if not child_ids.is_empty():
		print("[RenderPurpose] vis_story batch parent %s completed — registering %d child jobs" % [job_id.left(12), child_ids.size()])
		for cid in child_ids:
			_pending_vis_story_jobs[cid] = meta.duplicate()
			_start_job_poll_for_materialization(cid)
		return

	# Child / single job with actual images.
	# Always re-fetch from render_get_job when final_ids are absent: the initial
	# payload (often a WS event) carries image_artifact_ids (all outputs) but
	# omits final_image_artifact_ids, which only the full job record contains.
	var final_ids: Array[String] = RenderPurposeUtilsScript.extract_final_image_artifact_ids(payload)
	if final_ids.is_empty():
		var job_res: Dictionary = await _hub.render_get_job(job_id)
		if bool(job_res.get("ok", false)):
			final_ids = RenderPurposeUtilsScript.extract_final_image_artifact_ids(job_res)
			if final_ids.is_empty():
				final_ids = RenderPurposeUtilsScript.extract_image_artifact_ids(job_res)
		if final_ids.is_empty():
			final_ids = RenderPurposeUtilsScript.extract_image_artifact_ids(payload)

	if final_ids.is_empty():
		print("[RenderPurpose] vis_story job %s completed but no image artifacts found" % job_id.left(12))
		return

	var cycle_id: int = int(meta.get("cycle_id", 0))
	var collection_str: String = str(meta.get("collection", "default")).strip_edges()
	var scenario_str: String = str(meta.get("scenario", "default")).strip_edges()
	var materialized_paths: Array = await _materialize_vis_story_finals(final_ids, collection_str, scenario_str, cycle_id)
	if materialized_paths.is_empty():
		print("[RenderPurpose] vis_story job %s: materialization produced 0 images" % job_id.left(12))
		return

	print("[RenderPurpose] vis_story job %s: %d final images materialized to backgrounds" % [job_id.left(12), materialized_paths.size()])
	vis_story_images_ready.emit(job_id, cycle_id, materialized_paths, meta)


func _materialize_vis_story_finals(artifact_ids: Array[String], collection_id: String, scenario_key: String, cycle_id: int) -> Array:
	var store: ScenSynGeneratedSpriteStore = GeneratedSpriteStoreScript.new()
	var ws_root: String = store.get_workspace_root_abs()
	if ws_root.is_empty():
		print("[RenderPurpose] vis_story materialize: workspace root unknown")
		return []
	ws_root = ws_root.replace("\\", "/")
	var bg_dir: String = ws_root.path_join("scensyn").path_join("vis_story_backgrounds").path_join(scenario_key)
	DirAccess.make_dir_recursive_absolute(bg_dir)

	var manifest_path: String = bg_dir.path_join("manifest.json")
	var manifest: Array = RenderPurposeUtilsScript.load_bg_manifest(manifest_path)
	var next_index: int = manifest.size() + 1

	var out_paths: Array = []
	for aid in artifact_ids:
		var rec_res: Dictionary = await _hub.get_artifact_record(aid)
		if not bool(rec_res.get("ok", false)):
			continue
		var rec_any: Variant = rec_res.get("record", {})
		var rec: Dictionary = rec_any if typeof(rec_any) == TYPE_DICTIONARY else {}
		var uri: String = str(rec.get("uri", "")).strip_edges()
		if RenderPurposeUtilsScript.is_intermediate_uri(uri, rec):
			continue
		var src_abs: String = store.uri_to_abs_path(uri)
		if src_abs.is_empty() or not FileAccess.file_exists(src_abs):
			continue
		var fname: String = "bg_%04d.png" % next_index
		var dst_abs: String = bg_dir.path_join(fname)
		var ok: bool = store._copy_file_abs(src_abs, dst_abs)
		if not ok:
			continue
		var entry: Dictionary = {
			"index": next_index,
			"filename": fname,
			"path": dst_abs,
			"artifact_id": aid,
			"cycle_id": cycle_id,
			"turn_id": cycle_id,
			"collection": collection_id,
			"scenario": scenario_key,
			"timestamp": Time.get_unix_time_from_system(),
		}
		manifest.append(entry)
		out_paths.append(dst_abs)
		next_index += 1

	RenderPurposeUtilsScript.save_bg_manifest(manifest_path, manifest)
	return out_paths


# Convenience entrypoints (recommended initial purposes)
func submit_background_render(opts: Dictionary = {}) -> Dictionary:
	return await submit_render_purpose("background", opts)


func submit_portrait_render(opts: Dictionary = {}) -> Dictionary:
	return await submit_render_purpose("portrait", opts)


func submit_prop_card_render(opts: Dictionary = {}) -> Dictionary:
	return await submit_render_purpose("prop_card", opts)
