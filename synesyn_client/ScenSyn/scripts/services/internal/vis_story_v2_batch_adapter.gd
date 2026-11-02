extends RefCounted
class_name VisStoryV2BatchAdapter

const RenderWorkflowUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_workflow_utils.gd")

const _NID_SPECTRE := 10
const _NID_CRACKLE := 20
const _NID_STFX := 33
const _NID_TERRACHROMA := 30
const _NID_NARRATIVE := 31
const _NID_SCHEDULE := 62
const _NID_CLIP_POS := 70
const _NID_MAIN_KSAMPLER := 80
const _NID_SKETCH_KSAMPLER := 101
const _NID_SAVE := 99
const _NID_SAVE_SK := 104
const _NID_EMPTY_LATENT := 100

const RENDER_WIDTH := 1024
const RENDER_HEIGHT := 768

const _SECTOR_HEX_TO_PALETTE := {
	"#8ad0ff": "Adire",
	"#ffd27a": "Aso Oke",
	"#a6f4a1": "Bogolan",
}

const _SECTOR_HEX_TO_STFX_PALETTE := {
	"#8ad0ff": "Adire (Indigo / Cream)",
	"#ffd27a": "Aso Oke (Crimson / Gold)",
	"#a6f4a1": "Bogolan (Charcoal / Terracotta)",
}

const _DEFAULT_CONTROL_PRESET := "landscape"

const _ARC_TAG_TO_ODUU := {
	"founding_gestures": "Primary (Ogbe / Oyeku / Iwori / Odi)",
	"civic_emergence": "Transitional (Irosun / Owonrin / Obara / Okanran)",
	"systemic_repair": "Rhythmic (Ogunda / Osa / Ika / Oturupon)",
	"transformation": "Alternating (Otura / Irete / Ose / Ofun)",
	"renewal": "Alternating (Otura / Irete / Ose / Ofun)",
	"deepening": "Rhythmic (Ogunda / Osa / Ika / Oturupon)",
}

# ── Prompt scaffolding — loaded from shared JSON config at runtime ────────────
# No hardcoded scaffolding data in this file.  Everything comes from
# prompt_scaffolding.json so that changes propagate to both the GDScript
# (batch_fanout) and Python (scheduler) code paths from a single source.


static func _load_scaffolding(scaffolding_path: String) -> Dictionary:
	if scaffolding_path.is_empty():
		push_warning("VisStoryV2BatchAdapter: scaffolding_path is empty — prompts will use degraded fallback.")
		return {}
	var file := FileAccess.open(scaffolding_path, FileAccess.READ)
	if file == null:
		push_warning("VisStoryV2BatchAdapter: could not open %s — prompts will use degraded fallback." % scaffolding_path)
		return {}
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("VisStoryV2BatchAdapter: %s did not parse as Dictionary." % scaffolding_path)
		return {}
	var data: Dictionary = parsed
	for required_key in ["register_to_booster", "default_booster", "context_anchors"]:
		if not data.has(required_key):
			push_warning("VisStoryV2BatchAdapter: scaffolding missing key '%s'." % required_key)
	return data


static func build_render_batch_request(story_json_path: String, cycle_id: int, opts: Dictionary = {}) -> Dictionary:
	var json_path := String(story_json_path).strip_edges()
	if json_path.is_empty():
		return {"ok": false, "error": "story_json_path_required"}

	var workflow_path := String(opts.get("workflow_path", "")).strip_edges()
	if workflow_path.is_empty():
		return {"ok": false, "error": "workflow_path_required"}

	var story_res := _read_json_dict(json_path)
	if not bool(story_res.get("ok", false)):
		return story_res
	var story: Dictionary = story_res.get("json", {})

	var workflow_res := _read_json_dict(workflow_path)
	if not bool(workflow_res.get("ok", false)):
		return workflow_res
	var base_graph: Dictionary = workflow_res.get("json", {})

	var scaffolding_path := String(opts.get("scaffolding_path", "")).strip_edges()
	var scaffolding: Dictionary = _load_scaffolding(scaffolding_path)

	var cycle := _find_cycle(story, cycle_id)
	if cycle.is_empty():
		return {"ok": false, "error": "cycle_not_found", "cycle_id": int(cycle_id), "story_json_path": json_path}

	var override_panels_to_render := int(opts.get("override_panels_to_render", 0))
	var override_selection_mode := str(opts.get("override_selection_mode", "use_json")).strip_edges().to_lower()
	var override_panel_indices: Array[int] = []
	var override_any: Variant = opts.get("override_panel_indices", [])
	if typeof(override_any) == TYPE_ARRAY:
		for idx_any in override_any:
			override_panel_indices.append(int(idx_any))

	var selected_indices := _select_panel_indices(
		cycle,
		override_panels_to_render,
		override_selection_mode,
		override_panel_indices
	)
	if selected_indices.is_empty():
		return {"ok": false, "error": "no_selected_panels", "cycle_id": int(cycle_id)}

	var comfy_url := String(opts.get("comfy_url", "")).strip_edges()
	if comfy_url.is_empty():
		return {"ok": false, "error": "comfy_url_required"}
	var session_id := String(opts.get("session_id", "")).strip_edges()
	var turn_id := String(opts.get("turn_id", "")).strip_edges()
	var collection_id := String(opts.get("collection_id", "default")).strip_edges()
	var scenario_key := String(opts.get("scenario_key", "default")).strip_edges()
	var output_root := String(opts.get("output_root", "scensyn/vis_story_v2")).strip_edges()
	var batch_request_id := String(opts.get("batch_request_id", "")).strip_edges()
	if batch_request_id.is_empty():
		batch_request_id = "scensyn_vis_story_batch_%d" % int(Time.get_unix_time_from_system())

	var items: Array = []
	for panel_index in selected_indices:
		var panel := _find_panel(cycle, panel_index)
		if panel.is_empty():
			continue
		var params := _translate_panel(cycle, panel, scaffolding)
		var prompt_candidate: Dictionary = {}
		if _looks_like_api_prompt_graph(base_graph):
			prompt_candidate = _extract_api_prompt_graph(base_graph).duplicate(true)
			_patch_api_prompt_graph(prompt_candidate, params, output_root)
		else:
			var graph: Dictionary = base_graph.duplicate(true)
			_patch_graph(graph, params, output_root)
			prompt_candidate = _ui_graph_to_api_prompt(graph)
		var prompt_res: Dictionary = RenderWorkflowUtilsScript.extract_comfy_prompt_graph(prompt_candidate)
		if not bool(prompt_res.get("ok", false)):
			return {
				"ok": false,
				"error": "workflow_prompt_extract_failed",
				"details": prompt_res,
				"panel_index": int(panel_index),
			}
		var prompt_graph: Dictionary = prompt_res.get("prompt", {})
		var child_request_id := "%s_%s" % [batch_request_id, str(params.get("base_name", "panel")).strip_edges()]
		var child_request := {
			"schema_version": 1,
			"kind": "synesyn.render_request",
			"routing": {"mode": "hub", "provider": "comfyui", "comfy_base_url": comfy_url},
			"output_routing": {
				"mode": "substrate",
				"render_request_artifact_type": "json.render_request",
				"images": {"artifact_type": "image.scensyn.vis_story_panel"},
			},
			"workflow": {"inline": prompt_graph},
			"patches": [],
			"client": {
				"app_id": "scensyn",
				"session_id": session_id,
				"request_id": child_request_id,
				"turn_id": turn_id,
				"client_id": "scensyn_%s" % str(params.get("base_name", "panel")).strip_edges(),
			},
			"refs": {
				"scensyn": {
					"render_purpose": "vis_story_panel",
					"collection": collection_id,
					"scenario": scenario_key,
					"vis_story_cycle_version": "v2_batch_fanout",
					"cycle_id": int(cycle.get("cycle_id", cycle_id)),
					"panel_index": int(panel_index),
				},
				"story_json_path": json_path,
				"vis_story": {
					"adapter_version": "batch_fanout_v1",
					"base_name": str(params.get("base_name", "")),
					"panel_role": str(panel.get("panel_role", "")),
					"register": str(params.get("register", "")),
					"sector_name": str(params.get("sector_name", "")),
					"sector_hex": str(params.get("sector_hex", "")),
				},
			},
		}
		items.append(
			{
				"item_id": str(params.get("base_name", "panel_%02d" % int(panel_index))).strip_edges(),
				"request": child_request,
				"metadata": {
					"cycle_id": int(cycle.get("cycle_id", cycle_id)),
					"panel_index": int(panel_index),
					"base_name": str(params.get("base_name", "")),
				},
			}
		)

	return {
		"ok": true,
		"batch_request": {
			"schema_version": 1,
			"kind": "synesyn.render_batch_request",
			"client": {
				"app_id": "scensyn",
				"session_id": session_id,
				"request_id": batch_request_id,
				"turn_id": turn_id,
			},
			"metadata": {
				"adapter": "vis_story_v2_batch_fanout",
				"collection": collection_id,
				"scenario": scenario_key,
				"cycle_id": int(cycle.get("cycle_id", cycle_id)),
				"selected_panels": selected_indices,
			},
			"items": items,
		},
		"selected_panels": selected_indices,
	}


static func _read_json_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "failed_to_open_json", "path": path}
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "json_root_not_object", "path": path}
	return {"ok": true, "json": parsed}


static func _looks_like_api_prompt_graph(graph: Dictionary) -> bool:
	var prompt_any: Variant = graph.get("prompt", null)
	if typeof(prompt_any) == TYPE_DICTIONARY:
		return _looks_like_api_prompt_graph(prompt_any)
	if graph.has("nodes"):
		return false
	for key_any in graph.keys():
		var node_any: Variant = graph.get(key_any, null)
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = node_any
		if not str(node.get("class_type", "")).strip_edges().is_empty():
			return true
	return false


static func _extract_api_prompt_graph(graph: Dictionary) -> Dictionary:
	var prompt_any: Variant = graph.get("prompt", null)
	if typeof(prompt_any) == TYPE_DICTIONARY:
		return prompt_any
	return graph


static func _find_cycle(story: Dictionary, cycle_id: int) -> Dictionary:
	var cycles_any: Variant = story.get("cycles", [])
	if typeof(cycles_any) != TYPE_ARRAY:
		return {}
	for cycle_any in cycles_any:
		if typeof(cycle_any) != TYPE_DICTIONARY:
			continue
		var cycle: Dictionary = cycle_any
		if int(cycle.get("cycle_id", -1)) == int(cycle_id):
			return cycle
	return {}


static func _find_panel(cycle: Dictionary, panel_index: int) -> Dictionary:
	var panels_any: Variant = cycle.get("panels", [])
	if typeof(panels_any) != TYPE_ARRAY:
		return {}
	for panel_any in panels_any:
		if typeof(panel_any) != TYPE_DICTIONARY:
			continue
		var panel: Dictionary = panel_any
		if int(panel.get("panel_index", -1)) == int(panel_index):
			return panel
	return {}


static func _sorted_panels(cycle: Dictionary) -> Array:
	var panels_any: Variant = cycle.get("panels", [])
	var panels: Array = panels_any if typeof(panels_any) == TYPE_ARRAY else []
	var copy := panels.duplicate(true)
	copy.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int((a as Dictionary).get("panel_index", 0)) < int((b as Dictionary).get("panel_index", 0))
	)
	return copy


static func _resolve_render_plan(
	cycle: Dictionary,
	override_panels_to_render: int = 0,
	override_selection_mode: String = "use_json",
	override_panel_indices: Array[int] = []
) -> Dictionary:
	var panels := _sorted_panels(cycle)
	var available: Array[int] = []
	for panel_any in panels:
		var panel: Dictionary = panel_any
		var idx := int(panel.get("panel_index", 0))
		if idx > 0:
			available.append(idx)

	var render_plan: Dictionary = cycle.get("render_plan", {}) if typeof(cycle.get("render_plan", {})) == TYPE_DICTIONARY else {}
	var max_panels := int(render_plan.get("max_panels_per_turn", available.size()))
	var requested_count := int(render_plan.get("panels_to_render", available.size()))
	if int(override_panels_to_render) > 0:
		requested_count = int(override_panels_to_render)

	var selection_mode := str(render_plan.get("selection_mode", "spread")).strip_edges().to_lower()
	if not override_selection_mode.is_empty() and override_selection_mode != "use_json":
		selection_mode = override_selection_mode

	var custom_indices: Array[int] = []
	var custom_any: Variant = render_plan.get("panel_indices", [])
	if typeof(custom_any) == TYPE_ARRAY:
		for idx_any in custom_any:
			custom_indices.append(int(idx_any))
	if not override_panel_indices.is_empty():
		custom_indices = override_panel_indices.duplicate()

	var effective_count := 0
	if not available.is_empty():
		effective_count = maxi(1, mini(requested_count, mini(max_panels, mini(available.size(), 24))))

	return {
		"available": available,
		"selection_mode": selection_mode,
		"panel_indices": custom_indices,
		"effective_panels_to_render": effective_count,
	}


static func _select_panel_indices(
	cycle: Dictionary,
	override_panels_to_render: int = 0,
	override_selection_mode: String = "use_json",
	override_panel_indices: Array[int] = []
) -> Array[int]:
	var plan := _resolve_render_plan(cycle, override_panels_to_render, override_selection_mode, override_panel_indices)
	var available: Array = plan.get("available", [])
	if available.is_empty():
		return []
	var count := int(plan.get("effective_panels_to_render", available.size()))
	var selection_mode := str(plan.get("selection_mode", "first_n")).strip_edges().to_lower()
	var cycle_id := int(cycle.get("cycle_id", 1))

	if selection_mode == "custom":
		var explicit: Array[int] = []
		for idx in plan.get("panel_indices", []):
			var val := int(idx)
			if available.has(val):
				explicit.append(val)
		return explicit.slice(0, count)

	if selection_mode == "hero_only":
		for panel_any in _sorted_panels(cycle):
			var panel: Dictionary = panel_any
			if str(panel.get("panel_role", "")).strip_edges().to_lower() == "hero":
				return [int(panel.get("panel_index", 1))]
		return [available[0]]

	if selection_mode == "spread":
		return _spread_select(available, count, cycle_id)

	return available.slice(0, count)


static func _spread_select(indices: Array[int], count: int, p_cycle_id: int = 0) -> Array[int]:
	if count <= 0 or indices.is_empty():
		return []
	if count >= indices.size():
		return indices.duplicate()
	var n := indices.size()
	var offset := (p_cycle_id * 3) % n
	var rotated: Array[int] = []
	for i in range(n):
		rotated.append(indices[(i + offset) % n])
	if count == 1:
		return [rotated[0]]
	var chosen: Array[int] = []
	var last := rotated.size() - 1
	for i in range(count):
		var pos := int(round(float(i * last) / float(count - 1)))
		var idx := rotated[pos]
		if not chosen.has(idx):
			chosen.append(idx)
	for idx in rotated:
		if chosen.size() >= count:
			break
		if not chosen.has(idx):
			chosen.append(idx)
	chosen.sort()
	return chosen


static func _sector_hex_to_palette(hex_color: String) -> String:
	return str(_SECTOR_HEX_TO_PALETTE.get(hex_color.to_lower(), "Terrachroma Classic"))


static func _sector_hex_to_stfx_palette(hex_color: String) -> String:
	return str(_SECTOR_HEX_TO_STFX_PALETTE.get(hex_color.to_lower(), "Adire (Indigo / Cream)"))


static func _register_to_preset(register: String) -> String:
	return _DEFAULT_CONTROL_PRESET


static func _arc_tag_to_oduu_group(arc_tag: String) -> String:
	return str(_ARC_TAG_TO_ODUU.get(arc_tag, "Primary (Ogbe / Oyeku / Iwori / Odi)"))


static func _story_state_to_narrative_text(panel: Dictionary, cycle_arc_tag: String = "") -> String:
	var parts: Array[String] = []
	var sector: Dictionary = panel.get("sector", {}) if typeof(panel.get("sector", {})) == TYPE_DICTIONARY else {}
	var theme: Dictionary = panel.get("theme", {}) if typeof(panel.get("theme", {})) == TYPE_DICTIONARY else {}
	var action: Dictionary = panel.get("action", {}) if typeof(panel.get("action", {})) == TYPE_DICTIONARY else {}
	var state_in: Dictionary = panel.get("story_state_in", {}) if typeof(panel.get("story_state_in", {})) == TYPE_DICTIONARY else {}
	var state_out: Dictionary = panel.get("story_state_out", {}) if typeof(panel.get("story_state_out", {})) == TYPE_DICTIONARY else {}
	var turn_context: Dictionary = panel.get("turn_context", {}) if typeof(panel.get("turn_context", {})) == TYPE_DICTIONARY else {}

	var sector_name := str(sector.get("name", "")).strip_edges()
	var register := str(panel.get("narrative_register", "")).strip_edges()
	var theme_name := str(theme.get("name", "")).strip_edges()
	var action_name := str(action.get("name", "")).strip_edges()
	var prompt := str(panel.get("prompt", "")).strip_edges()
	var caption := str(panel.get("caption", "")).strip_edges()
	var anchor := str(state_in.get("continuity_anchor", "")).strip_edges()
	var pressure := str(state_out.get("next_pressure", "")).strip_edges()
	var tension := str(state_out.get("latent_tension", "")).strip_edges()
	var focus_shift := str(state_out.get("focus_shift", "")).strip_edges()
	var site := str(turn_context.get("province_or_site", "")).strip_edges()
	var region := str(turn_context.get("tapestry_region_primary", "")).strip_edges()

	if not prompt.is_empty():
		parts.append(prompt)
	var motif_bits: Array[String] = []
	if not sector_name.is_empty():
		motif_bits.append(sector_name)
	if not theme_name.is_empty():
		motif_bits.append(theme_name)
	if not action_name.is_empty() and action_name != theme_name:
		motif_bits.append(action_name)
	if not motif_bits.is_empty():
		parts.append("Motifs: %s." % ", ".join(motif_bits))
	var locale_bits: Array[String] = []
	if not site.is_empty():
		locale_bits.append(site)
	if not region.is_empty() and region != site:
		locale_bits.append(region)
	if not locale_bits.is_empty():
		parts.append("Scene anchored in %s." % ", ".join(locale_bits))
	elif not anchor.is_empty():
		parts.append("Scene anchored in %s." % anchor)
	if not register.is_empty():
		parts.append("Narrative register: %s." % register)
	if not cycle_arc_tag.is_empty():
		parts.append("Arc mood: %s." % cycle_arc_tag)
	if not pressure.is_empty():
		parts.append("The immediate pressure is %s." % pressure)
	if not tension.is_empty():
		parts.append("The latent tension in the scene is %s." % tension)
	if not focus_shift.is_empty():
		parts.append("The scene leans toward %s." % focus_shift)
	if not caption.is_empty():
		parts.append(caption)
	return " ".join(parts)


static func _build_positive(
	scaffolding: Dictionary,
	raw_prompt: String, register: String, arc_tag: String,
	panel_role: String, hex_color: String, panel_index: int,
	p_cycle_id: int = 1,
) -> String:
	var reg_boosters: Dictionary = scaffolding.get("register_to_booster", {})
	var default_booster: String = str(scaffolding.get("default_booster", "detailed, high quality"))
	var compositions: Dictionary = scaffolding.get("arc_tag_to_composition", {})
	var framings: Dictionary = scaffolding.get("role_to_framing", {})
	var atmospheres: Dictionary = scaffolding.get("hex_to_atmosphere", {})
	var anchors: Array = scaffolding.get("context_anchors", [])

	var booster: String = str(reg_boosters.get(register, default_booster))
	var composition: String = str(compositions.get(arc_tag, ""))
	var framing: String = str(framings.get(panel_role, ""))
	var atmosphere: String = str(atmospheres.get(hex_color.to_lower(), ""))

	var parts: Array[String] = [raw_prompt, booster]
	if not composition.is_empty():
		parts.append(composition)
	if not framing.is_empty():
		parts.append(framing)
	if not atmosphere.is_empty():
		parts.append(atmosphere)
	if not anchors.is_empty():
		parts.append(str(anchors[(panel_index + p_cycle_id * 7) % anchors.size()]))
	return ", ".join(parts)


static func _translate_panel(cycle: Dictionary, panel: Dictionary, scaffolding: Dictionary = {}) -> Dictionary:
	var arc_tag := str(cycle.get("story_arc_tag", "")).strip_edges()
	var cycle_id := int(cycle.get("cycle_id", 1))
	var panel_index := int(panel.get("panel_index", 1))
	var register := str(panel.get("narrative_register", "")).strip_edges()
	var panel_role := str(panel.get("panel_role", "")).strip_edges().to_lower()
	var sector: Dictionary = panel.get("sector", {}) if typeof(panel.get("sector", {})) == TYPE_DICTIONARY else {}
	var hex_color := str(sector.get("color_hex", "")).strip_edges()
	var panel_seed := int(panel.get("seed", 1337))
	var cycle_seed := cycle_id * 10000
	var surface_seed := _derive_seed(cycle_seed, panel_index * 7919 + panel_seed)
	var raw_prompt := str(panel.get("prompt", "")).strip_edges()

	var positive := _build_positive(scaffolding, raw_prompt, register, arc_tag, panel_role, hex_color, panel_index, cycle_id)

	return {
		"positive": positive,
		"narrative_text": _story_state_to_narrative_text(panel, arc_tag),
		"palette_variant": _sector_hex_to_palette(hex_color),
		"stfx_palette": _sector_hex_to_stfx_palette(hex_color),
		"control_preset": _register_to_preset(register),
		"oduu_group": _arc_tag_to_oduu_group(arc_tag),
		"cycle_seed": cycle_seed,
		"surface_seed": surface_seed,
		"render_seed": panel_seed,
		"base_name": "c%03d_p%02d" % [cycle_id, panel_index],
		"arc_tag": arc_tag,
		"register": register,
		"sector_name": str(sector.get("name", "")).strip_edges(),
		"sector_hex": hex_color,
	}


static func _find_ui_node(graph: Dictionary, node_id: int) -> Dictionary:
	var nodes_any: Variant = graph.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return {}
	for node_any in nodes_any:
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = node_any
		if int(node.get("id", -1)) == int(node_id):
			return node
	return {}


static func _derive_seed(base_seed: int, salt: int) -> int:
	var seed: int = abs(int(base_seed))
	var mixed: int = int((seed * 1664525) + (salt * 1013904223))
	var normalized: int = abs(mixed) % 2147483647
	return normalized if normalized > 0 else 1337


static func _resolve_link_source(node_by_id: Dictionary, raw_link: Dictionary, src_id: int, src_slot: int) -> Array:
	var node_any: Variant = node_by_id.get(src_id, null)
	if typeof(node_any) != TYPE_DICTIONARY:
		return [src_id, src_slot]
	var node: Dictionary = node_any
	if str(node.get("type", "")) != "Reroute":
		return [src_id, src_slot]
	var inputs_any: Variant = node.get("inputs", [])
	if typeof(inputs_any) != TYPE_ARRAY:
		return [src_id, src_slot]
	for inp_any in inputs_any:
		if typeof(inp_any) != TYPE_DICTIONARY:
			continue
		var inp: Dictionary = inp_any
		var link_id_any: Variant = inp.get("link", null)
		if link_id_any == null:
			continue
		var link_id := int(link_id_any)
		if raw_link.has(link_id):
			var link_src: Array = raw_link.get(link_id, [src_id, src_slot])
			return _resolve_link_source(node_by_id, raw_link, int(link_src[0]), int(link_src[1]))
	return [src_id, src_slot]


static func _ui_graph_to_api_prompt(graph: Dictionary, exclude_node_ids: Array = []) -> Dictionary:
	var exclude := {}
	for node_id_any in exclude_node_ids:
		exclude[int(node_id_any)] = true

	var raw_link := {}
	var links_any: Variant = graph.get("links", [])
	if typeof(links_any) == TYPE_ARRAY:
		for link_any in links_any:
			if typeof(link_any) != TYPE_ARRAY:
				continue
			var link: Array = link_any
			if link.size() < 3:
				continue
			raw_link[int(link[0])] = [int(link[1]), int(link[2])]

	var node_by_id := {}
	var nodes_any: Variant = graph.get("nodes", [])
	if typeof(nodes_any) == TYPE_ARRAY:
		for node_any in nodes_any:
			if typeof(node_any) != TYPE_DICTIONARY:
				continue
			var node: Dictionary = node_any
			node_by_id[int(node.get("id", -1))] = node

	var link_map := {}
	for lid_any in raw_link.keys():
		var lid := int(lid_any)
		var src: Array = raw_link.get(lid, [0, 0])
		link_map[lid] = _resolve_link_source(node_by_id, raw_link, int(src[0]), int(src[1]))

	var api: Dictionary = {}
	if typeof(nodes_any) != TYPE_ARRAY:
		return api
	for node_any in nodes_any:
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = node_any
		var class_type := str(node.get("type", "")).strip_edges()
		var nid_int := int(node.get("id", -1))
		if class_type.is_empty() or class_type in ["Note", "Reroute"] or exclude.has(nid_int):
			continue
		var widgets_any: Variant = node.get("widgets_values", [])
		var widgets: Array = widgets_any if typeof(widgets_any) == TYPE_ARRAY else []
		var widgets_i := 0
		var inputs: Dictionary = {}
		var node_inputs_any: Variant = node.get("inputs", [])
		var node_inputs: Array = node_inputs_any if typeof(node_inputs_any) == TYPE_ARRAY else []
		for inp_any in node_inputs:
			if typeof(inp_any) != TYPE_DICTIONARY:
				continue
			var inp: Dictionary = inp_any
			var name := str(inp.get("name", "")).strip_edges()
			var link_id_any: Variant = inp.get("link", null)
			var has_widget := inp.has("widget")
			if has_widget:
				var widget_val: Variant = widgets[widgets_i] if widgets_i < widgets.size() else null
				widgets_i += 1
				if str(inp.get("type", "")) == "INT" and name == "seed" and widgets_i < widgets.size() and typeof(widgets[widgets_i]) == TYPE_STRING:
					widgets_i += 1
				if link_id_any != null and link_map.has(int(link_id_any)):
					var sid_sslot: Array = link_map.get(int(link_id_any), [])
					if sid_sslot.size() >= 2:
						var sid := int(sid_sslot[0])
						var sslot := int(sid_sslot[1])
						if exclude.has(sid):
							if widget_val != null:
								inputs[name] = widget_val
						else:
							inputs[name] = [str(sid), sslot]
				elif widget_val != null:
					inputs[name] = widget_val
			elif link_id_any != null and link_map.has(int(link_id_any)):
				var sid_sslot: Array = link_map.get(int(link_id_any), [])
				if sid_sslot.size() >= 2 and not exclude.has(int(sid_sslot[0])):
					inputs[name] = [str(int(sid_sslot[0])), int(sid_sslot[1])]
		api[str(nid_int)] = {"class_type": class_type, "inputs": inputs}
	return api


static func _detach_input_link(graph: Dictionary, node_id: int, input_name: String) -> void:
	var nodes_any: Variant = graph.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return
	for node_any in nodes_any:
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = node_any
		if int(node.get("id", -1)) != int(node_id):
			continue
		var inputs_any: Variant = node.get("inputs", [])
		if typeof(inputs_any) != TYPE_ARRAY:
			return
		for inp_any in inputs_any:
			if typeof(inp_any) != TYPE_DICTIONARY:
				continue
			var inp: Dictionary = inp_any
			if str(inp.get("name", "")) == input_name:
				inp["link"] = null
				return
		return


static func _widget_values(graph: Dictionary, node_id: int) -> Array:
	var nodes_any: Variant = graph.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return []
	for node_any in nodes_any:
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = node_any
		if int(node.get("id", -1)) == int(node_id):
			var values_any: Variant = node.get("widgets_values", [])
			return values_any if typeof(values_any) == TYPE_ARRAY else []
	return []


static func _set_widget_value(graph: Dictionary, node_id: int, widget_index: int, value: Variant) -> void:
	var nodes_any: Variant = graph.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return
	for node_any in nodes_any:
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = node_any
		if int(node.get("id", -1)) != int(node_id):
			continue
		var values_any: Variant = node.get("widgets_values", [])
		var values: Array = values_any if typeof(values_any) == TYPE_ARRAY else []
		if widget_index < 0 or widget_index >= values.size():
			return
		values[widget_index] = value
		node["widgets_values"] = values
		return


static func _set_api_input(prompt_graph: Dictionary, node_id: int, input_name: String, value: Variant) -> void:
	var node_key := str(node_id)
	var node_any: Variant = prompt_graph.get(node_key, null)
	if typeof(node_any) != TYPE_DICTIONARY:
		return
	var node: Dictionary = node_any
	var inputs_any: Variant = node.get("inputs", {})
	var inputs: Dictionary = inputs_any if typeof(inputs_any) == TYPE_DICTIONARY else {}
	inputs[input_name] = value
	node["inputs"] = inputs
	prompt_graph[node_key] = node


static func _patch_api_prompt_graph(prompt_graph: Dictionary, params: Dictionary, output_root: String) -> void:
	var surface_seed := int(params.get("surface_seed", 0))
	var base_name := str(params.get("base_name", "panel")).strip_edges()
	_set_api_input(prompt_graph, _NID_CLIP_POS, "text", str(params.get("positive", "")))
	_set_api_input(prompt_graph, _NID_NARRATIVE, "text", str(params.get("narrative_text", "")))
	_set_api_input(prompt_graph, _NID_STFX, "oduu_group", str(params.get("oduu_group", "")))
	_set_api_input(prompt_graph, _NID_STFX, "text", str(params.get("narrative_text", "")))
	_set_api_input(prompt_graph, _NID_STFX, "seed", surface_seed)
	_set_api_input(prompt_graph, _NID_STFX, "pattern_palette", str(params.get("stfx_palette", "")))
	_set_api_input(prompt_graph, _NID_TERRACHROMA, "seed", surface_seed)
	_set_api_input(prompt_graph, _NID_TERRACHROMA, "palette_variant", str(params.get("palette_variant", "")))
	_set_api_input(prompt_graph, _NID_SCHEDULE, "preset", str(params.get("control_preset", "")))
	_set_api_input(prompt_graph, _NID_SPECTRE, "tile_scale", 120)
	_set_api_input(prompt_graph, _NID_SPECTRE, "width", RENDER_WIDTH)
	_set_api_input(prompt_graph, _NID_SPECTRE, "height", RENDER_HEIGHT)
	_set_api_input(prompt_graph, _NID_NARRATIVE, "width", RENDER_WIDTH)
	_set_api_input(prompt_graph, _NID_NARRATIVE, "height", RENDER_HEIGHT)
	_set_api_input(prompt_graph, _NID_STFX, "width", RENDER_WIDTH)
	_set_api_input(prompt_graph, _NID_STFX, "height", RENDER_HEIGHT)
	_set_api_input(prompt_graph, _NID_EMPTY_LATENT, "width", RENDER_WIDTH)
	_set_api_input(prompt_graph, _NID_EMPTY_LATENT, "height", RENDER_HEIGHT)
	_set_api_input(prompt_graph, _NID_SAVE, "filename_prefix", "%s/%s" % [output_root, base_name])
	_set_api_input(prompt_graph, _NID_SAVE_SK, "filename_prefix", "%s/sketch/%s" % [output_root, base_name])


static func _patch_graph(graph: Dictionary, params: Dictionary, output_root: String) -> void:
	var surface_seed := int(params.get("surface_seed", 0))
	var base_name := str(params.get("base_name", "panel")).strip_edges()

	_detach_input_link(graph, _NID_CLIP_POS, "text")
	_detach_input_link(graph, _NID_NARRATIVE, "text")
	_detach_input_link(graph, _NID_STFX, "text")
	_detach_input_link(graph, _NID_STFX, "seed")
	_detach_input_link(graph, _NID_TERRACHROMA, "seed")

	var wv := _widget_values(graph, _NID_CLIP_POS)
	if not wv.is_empty():
		_set_widget_value(graph, _NID_CLIP_POS, 0, str(params.get("positive", "")))

	wv = _widget_values(graph, _NID_NARRATIVE)
	if not wv.is_empty():
		_set_widget_value(graph, _NID_NARRATIVE, 0, str(params.get("narrative_text", "")))

	wv = _widget_values(graph, _NID_STFX)
	if not wv.is_empty():
		_set_widget_value(graph, _NID_STFX, 0, str(params.get("oduu_group", "")))
		if wv.size() > 1:
			_set_widget_value(graph, _NID_STFX, 1, str(params.get("narrative_text", "")))
		if wv.size() > 2:
			_set_widget_value(graph, _NID_STFX, 2, surface_seed)
		if wv.size() > 7:
			_set_widget_value(graph, _NID_STFX, 7, str(params.get("stfx_palette", "")))

	wv = _widget_values(graph, _NID_TERRACHROMA)
	if not wv.is_empty():
		_set_widget_value(graph, _NID_TERRACHROMA, 0, surface_seed)
		if wv.size() > 2:
			_set_widget_value(graph, _NID_TERRACHROMA, 2, str(params.get("palette_variant", "")))

	wv = _widget_values(graph, _NID_SCHEDULE)
	if wv.size() > 1:
		_set_widget_value(graph, _NID_SCHEDULE, 1, str(params.get("control_preset", "")))

	wv = _widget_values(graph, _NID_SPECTRE)
	if wv.size() > 3:
		_set_widget_value(graph, _NID_SPECTRE, 3, 120)
	if wv.size() > 1:
		_set_widget_value(graph, _NID_SPECTRE, 0, RENDER_WIDTH)
		_set_widget_value(graph, _NID_SPECTRE, 1, RENDER_HEIGHT)

	wv = _widget_values(graph, _NID_EMPTY_LATENT)
	if wv.size() > 1:
		_set_widget_value(graph, _NID_EMPTY_LATENT, 0, RENDER_WIDTH)
		_set_widget_value(graph, _NID_EMPTY_LATENT, 1, RENDER_HEIGHT)

	wv = _widget_values(graph, _NID_SAVE)
	if not wv.is_empty():
		_set_widget_value(graph, _NID_SAVE, 0, "%s/%s" % [output_root, base_name])

	wv = _widget_values(graph, _NID_SAVE_SK)
	if not wv.is_empty():
		_set_widget_value(graph, _NID_SAVE_SK, 0, "%s/sketch/%s" % [output_root, base_name])
