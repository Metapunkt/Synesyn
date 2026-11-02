extends RefCounted

const RenderCommonParamsUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_common_params_utils.gd")

const INTERMEDIATE_MARKERS: Array[String] = [
	"seam_edge_map", "micro_line_map", "height_map", "surface_image",
	"byte_luma_map", "semantic_field_map", "semantic_edge_map",
	"graded_surface_image", "region_id_map", "region_map",
	"stfx_region", "spectre_region", "sketch",
]

static func is_nonempty_string(value: Variant) -> bool:
	return (typeof(value) == TYPE_STRING) and (str(value).strip_edges() != "")

static func extract_first_image_artifact_id(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return ""
	var data: Dictionary = value

	if is_nonempty_string(data.get("image_artifact_id", null)):
		return str(data.get("image_artifact_id", "")).strip_edges()

	var ids_any: Variant = data.get("image_artifact_ids", null)
	if typeof(ids_any) == TYPE_ARRAY:
		var ids: Array = ids_any
		if ids.size() > 0 and is_nonempty_string(ids[0]):
			return str(ids[0]).strip_edges()

	var images_any: Variant = data.get("images", null)
	if typeof(images_any) == TYPE_ARRAY:
		var images: Array = images_any
		for image_any in images:
			if is_nonempty_string(image_any):
				return str(image_any).strip_edges()
			if typeof(image_any) == TYPE_DICTIONARY:
				var image_record: Dictionary = image_any
				if is_nonempty_string(image_record.get("artifact_id", null)):
					return str(image_record.get("artifact_id", "")).strip_edges()
				if is_nonempty_string(image_record.get("id", null)):
					return str(image_record.get("id", "")).strip_edges()

	var artifacts_any: Variant = data.get("artifacts", null)
	if typeof(artifacts_any) == TYPE_ARRAY:
		var artifacts: Array = artifacts_any
		for artifact_any in artifacts:
			if typeof(artifact_any) != TYPE_DICTIONARY:
				continue
			var artifact_record: Dictionary = artifact_any
			var artifact_type: String = str(artifact_record.get("artifact_type", "")).strip_edges()
			if artifact_type == "image.generated" or artifact_type.begins_with("image."):
				if is_nonempty_string(artifact_record.get("artifact_id", null)):
					return str(artifact_record.get("artifact_id", "")).strip_edges()
				if is_nonempty_string(artifact_record.get("id", null)):
					return str(artifact_record.get("id", "")).strip_edges()

	for key_id in ["payload", "output", "result", "job", "data"]:
		var nested_any: Variant = data.get(key_id, null)
		if typeof(nested_any) == TYPE_DICTIONARY:
			var found: String = extract_first_image_artifact_id(nested_any)
			if not found.is_empty():
				return found
	return ""

static func extract_image_artifact_ids(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		return out
	var data: Dictionary = value

	var ids_any: Variant = data.get("image_artifact_ids", null)
	if typeof(ids_any) == TYPE_ARRAY:
		for artifact_id_any in (ids_any as Array):
			var artifact_id: String = str(artifact_id_any).strip_edges()
			if not artifact_id.is_empty() and not out.has(artifact_id):
				out.append(artifact_id)

	var artifacts_any: Variant = data.get("artifacts", null)
	if typeof(artifacts_any) == TYPE_ARRAY:
		for artifact_any in (artifacts_any as Array):
			if typeof(artifact_any) != TYPE_DICTIONARY:
				continue
			var artifact_record: Dictionary = artifact_any
			var artifact_type: String = str(artifact_record.get("artifact_type", "")).strip_edges()
			if artifact_type == "image.generated" or artifact_type.begins_with("image."):
				var artifact_id2: String = str(artifact_record.get("artifact_id", artifact_record.get("id", ""))).strip_edges()
				if not artifact_id2.is_empty() and not out.has(artifact_id2):
					out.append(artifact_id2)

	var output_any: Variant = data.get("output", null)
	if typeof(output_any) == TYPE_DICTIONARY:
		var output_ids: Array[String] = extract_image_artifact_ids(output_any)
		for artifact_id3 in output_ids:
			if not out.has(artifact_id3):
				out.append(artifact_id3)

	for key_id in ["payload", "result", "job", "data"]:
		var nested_any: Variant = data.get(key_id, null)
		if typeof(nested_any) == TYPE_DICTIONARY:
			var nested_ids: Array[String] = extract_image_artifact_ids(nested_any)
			for artifact_id4 in nested_ids:
				if not out.has(artifact_id4):
					out.append(artifact_id4)
	return out

static func extract_child_job_ids(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		return out
	var data: Dictionary = value
	var child_ids_any: Variant = data.get("child_job_ids", null)
	if typeof(child_ids_any) == TYPE_ARRAY:
		for child_id_any in (child_ids_any as Array):
			var child_id: String = str(child_id_any).strip_edges()
			if not child_id.is_empty() and not out.has(child_id):
				out.append(child_id)
	for key_id in ["output", "payload", "result", "job", "data"]:
		var nested_any: Variant = data.get(key_id, null)
		if typeof(nested_any) == TYPE_DICTIONARY:
			var nested_child_ids: Array[String] = extract_child_job_ids(nested_any)
			for child_id2 in nested_child_ids:
				if not out.has(child_id2):
					out.append(child_id2)
	return out

static func extract_final_image_artifact_ids(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_DICTIONARY:
		return out
	var data: Dictionary = value
	var final_ids_any: Variant = data.get("final_image_artifact_ids", null)
	if typeof(final_ids_any) == TYPE_ARRAY:
		for artifact_id_any in (final_ids_any as Array):
			var artifact_id: String = str(artifact_id_any).strip_edges()
			if not artifact_id.is_empty() and not out.has(artifact_id):
				out.append(artifact_id)
	for key_id in ["output", "payload", "result", "job", "data"]:
		var nested_any: Variant = data.get(key_id, null)
		if typeof(nested_any) == TYPE_DICTIONARY:
			var nested_ids: Array[String] = extract_final_image_artifact_ids(nested_any)
			for artifact_id2 in nested_ids:
				if not out.has(artifact_id2):
					out.append(artifact_id2)
	return out

static func metadata_dict_from_text(text_value: String) -> Dictionary:
	var raw: String = String(text_value).strip_edges()
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

static func row_get(cols: Array, row: Array, col_name: String) -> Variant:
	var idx := cols.find(col_name)
	if idx == -1 or idx >= row.size():
		return null
	return row[idx]

static func preset_tags(preset: Dictionary) -> Array[String]:
	var tags_any: Variant = preset.get("tags", [])
	var out: Array[String] = []
	if typeof(tags_any) == TYPE_ARRAY:
		for tag_any in (tags_any as Array):
			var tag_id: String = str(tag_any).strip_edges().to_lower()
			if tag_id.is_empty():
				continue
			if not out.has(tag_id):
				out.append(tag_id)
	return out

static func has_tag(tags: Array[String], tag_id: String) -> bool:
	var target: String = String(tag_id).strip_edges().to_lower()
	if target.is_empty():
		return false
	for tag_item in tags:
		if String(tag_item).strip_edges().to_lower() == target:
			return true
	return false

static func first_tag_with_prefix(tags: Array[String], prefix: String) -> String:
	var prefix_text: String = String(prefix).strip_edges().to_lower()
	if prefix_text.is_empty():
		return ""
	for tag_item in tags:
		var tag_text: String = String(tag_item).strip_edges().to_lower()
		if tag_text.begins_with(prefix_text):
			return tag_text
	return ""

static func is_intermediate_uri(uri: String, rec: Dictionary) -> bool:
	var uri_lower: String = uri.to_lower()
	for marker in INTERMEDIATE_MARKERS:
		if uri_lower.contains(marker):
			return true

	var meta: Dictionary = {}
	var meta_raw: Variant = rec.get("metadata_json", rec.get("metadata", null))
	if typeof(meta_raw) == TYPE_STRING and not str(meta_raw).is_empty():
		var parsed: Variant = JSON.parse_string(str(meta_raw))
		if typeof(parsed) == TYPE_DICTIONARY:
			meta = parsed
	elif typeof(meta_raw) == TYPE_DICTIONARY:
		meta = meta_raw

	if meta.is_empty():
		return false
	var prov_any: Variant = meta.get("provenance", null)
	if typeof(prov_any) != TYPE_DICTIONARY:
		return false
	var provenance: Dictionary = prov_any as Dictionary
	if provenance.get("is_final_output", true) == false:
		return true
	var filename_lower: String = str(provenance.get("filename", "")).to_lower()
	var subfolder_lower: String = str(provenance.get("subfolder", "")).to_lower()
	for marker in INTERMEDIATE_MARKERS:
		if filename_lower.contains(marker) or subfolder_lower.contains(marker):
			return true
	return false

static func load_bg_manifest(path_value: String) -> Array:
	if not FileAccess.file_exists(path_value):
		return []
	var file := FileAccess.open(path_value, FileAccess.READ)
	if not file:
		return []
	var raw: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	return []

static func save_bg_manifest(path_value: String, manifest: Array) -> void:
	var file := FileAccess.open(path_value, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify(manifest, "  "))
	file.close()

static func detect_checkpoint_target(workflow: Dictionary) -> Dictionary:
	for node_id_any in workflow.keys():
		var node_id: String = str(node_id_any).strip_edges()
		var node_any: Variant = workflow.get(node_id_any)
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_record: Dictionary = node_any
		var class_type: String = str(node_record.get("class_type", "")).strip_edges()
		if class_type.findn("CheckpointLoader") == -1:
			continue
		var inputs_any: Variant = node_record.get("inputs", {})
		if typeof(inputs_any) != TYPE_DICTIONARY:
			continue
		var inputs: Dictionary = inputs_any
		if inputs.has("ckpt_name"):
			return {"node_id": node_id, "input": "ckpt_name"}
	return {}

static func detect_latent_batch_size_target(workflow: Dictionary) -> Dictionary:
	for node_id_any in workflow.keys():
		var node_id: String = str(node_id_any).strip_edges()
		var node_any: Variant = workflow.get(node_id_any)
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_record: Dictionary = node_any
		var class_type: String = str(node_record.get("class_type", "")).strip_edges()
		if class_type.findn("EmptyLatentImage") == -1:
			continue
		var inputs_any: Variant = node_record.get("inputs", {})
		if typeof(inputs_any) != TYPE_DICTIONARY:
			continue
		var inputs: Dictionary = inputs_any
		if inputs.has("batch_size"):
			return {"node_id": node_id, "input": "batch_size"}
	return {}

static func default_comfy_url_from_runtime_config() -> String:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var render_any: Variant = cfg.get("render", {})
	if typeof(render_any) == TYPE_DICTIONARY:
		var render_cfg: Dictionary = render_any
		var url: String = str(render_cfg.get("comfy_url", "")).strip_edges()
		if not url.is_empty():
			return url
	return "http://127.0.0.1:8188"

static func default_routing_mode_from_runtime_config() -> String:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var render_any: Variant = cfg.get("render", {})
	if typeof(render_any) == TYPE_DICTIONARY:
		var render_cfg: Dictionary = render_any
		var routing_mode: String = str(render_cfg.get("routing_mode", "hub")).strip_edges().to_lower()
		return "hub" if routing_mode == "hub" else "direct"
	return "hub"

## Resolves a visual system asset against the configured visual system directory.
## Previously this reached outside the project root via `res://../`, which cannot
## resolve in a cloned checkout; the location now comes from RuntimeConfig.
static func default_visualsystem_path(rel_path: String) -> String:
	var clean_rel: String = String(rel_path).strip_edges()
	if clean_rel.is_empty():
		return ""
	return RuntimeConfig.get_visualsystem_dir().path_join(clean_rel)

static func render_profile_entry_node_id(selection: Dictionary, fallback: String = "1") -> String:
	var meta_any: Variant = selection.get("metadata", {})
	var meta: Dictionary = meta_any if typeof(meta_any) == TYPE_DICTIONARY else {}
	var render_profile_any: Variant = meta.get("render_profile", {})
	var render_profile: Dictionary = render_profile_any if typeof(render_profile_any) == TYPE_DICTIONARY else {}
	var entry_id: String = str(render_profile.get("entry_node_id", fallback)).strip_edges()
	return entry_id if not entry_id.is_empty() else fallback

static func build_vis_story_v2_scheduler_prompt_graph() -> Dictionary:
	return {
		"1": {
			"class_type": "ForEachPanelRangeV2",
			"inputs": {
				"workflow_path": default_visualsystem_path("vis_story/aratitun_option_c_sdxl_autosketch.json"),
				"comfy_base_url": "http://127.0.0.1:8188",
				"json_path": default_visualsystem_path("vis_story_v2/story_data/Sample_StoryCycle_v2.json"),
				"presets_path": default_visualsystem_path("vis_story_v2/config/presets.yaml"),
				"cycle_start": 1,
				"cycle_end": 1,
				"override_panels_to_render": 0,
				"override_selection_mode": "use_json",
				"override_panel_indices_csv": "",
				"throttle_ms": 300,
				"output_root": "vis_story_v2"
			}
		}
	}

static func patches_with_common_params(workflow_prompt: Dictionary, base_patches: Array, values: Dictionary) -> Array:
	var patches: Array = base_patches.duplicate()
	var detected: Dictionary = RenderCommonParamsUtilsScript.detect_common_param_targets(workflow_prompt)
	if not (detected.get("ok", false) == true):
		return patches
	var targets_any: Variant = detected.get("targets", {})
	if typeof(targets_any) != TYPE_DICTIONARY:
		return patches
	var targets: Dictionary = targets_any
	for key_any in values.keys():
		var key_id: String = str(key_any)
		if not targets.has(key_id):
			continue
		var target_any: Variant = targets.get(key_id, {})
		if typeof(target_any) != TYPE_DICTIONARY:
			continue
		var target: Dictionary = target_any
		var node_id: String = str(target.get("node_id", "")).strip_edges()
		var input_key: String = str(target.get("input", "")).strip_edges()
		if node_id.is_empty() or input_key.is_empty():
			continue
		RenderCommonParamsUtilsScript.upsert_patch(patches, node_id, input_key, values.get(key_id))
	return patches
