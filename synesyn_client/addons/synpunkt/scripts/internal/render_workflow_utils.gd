extends RefCounted
class_name SynpunktRenderWorkflowUtils

static func default_workflow_json() -> String:
	return """{
  "3": {
	"inputs": {
	  "seed": 516947011200724,
	  "steps": 20,
	  "cfg": 8,
	  "sampler_name": "euler",
	  "scheduler": "normal",
	  "denoise": 1,
	  "model": [
		"4",
		0
	  ],
	  "positive": [
		"6",
		0
	  ],
	  "negative": [
		"7",
		0
	  ],
	  "latent_image": [
		"5",
		0
	  ]
	},
	"class_type": "KSampler",
	"_meta": {
	  "title": "KSampler"
	}
  },
  "4": {
	"inputs": {
	  "ckpt_name": "v1-5-pruned-emaonly-fp16.safetensors"
	},
	"class_type": "CheckpointLoaderSimple",
	"_meta": {
	  "title": "Load Checkpoint"
	}
  },
  "5": {
	"inputs": {
	  "width": 512,
	  "height": 512,
	  "batch_size": 1
	},
	"class_type": "EmptyLatentImage",
	"_meta": {
	  "title": "Empty Latent Image"
	}
  },
  "6": {
	"inputs": {
	  "text": "beautiful scenery nature glass bottle landscape, purple galaxy bottle,",
	  "clip": [
		"4",
		1
	  ]
	},
	"class_type": "CLIPTextEncode",
	"_meta": {
	  "title": "CLIP Text Encode (Prompt)"
	}
  },
  "7": {
	"inputs": {
	  "text": "text, watermark",
	  "clip": [
		"4",
		1
	  ]
	},
	"class_type": "CLIPTextEncode",
	"_meta": {
	  "title": "CLIP Text Encode (Prompt)"
	}
  },
  "8": {
	"inputs": {
	  "samples": [
		"3",
		0
	  ],
	  "vae": [
		"4",
		2
	  ]
	},
	"class_type": "VAEDecode",
	"_meta": {
	  "title": "VAE Decode"
	}
  },
  "9": {
	"inputs": {
	  "filename_prefix": "SD1.5",
	  "images": [
		"8",
		0
	  ]
	},
	"class_type": "SaveImage",
	"_meta": {
	  "title": "Save Image"
	}
  }
}"""

static func hash_sha256_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	var out: PackedByteArray = ctx.finish()
	var s := ""
	for b in out:
		s += "%02x" % int(b)
	return s

static func canonicalize_json_value(v: Variant) -> Variant:
	var t := typeof(v)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		var keys: Array = d.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str(a) < str(b)
		)
		var out: Dictionary = {}
		for k in keys:
			out[k] = canonicalize_json_value(d.get(k))
		return out
	if t == TYPE_ARRAY:
		var a: Array = v
		var out_a: Array = []
		out_a.resize(a.size())
		for i in range(a.size()):
			out_a[i] = canonicalize_json_value(a[i])
		return out_a
	return v

static func canonical_json_bytes(v: Variant) -> PackedByteArray:
	var canon: Variant = canonicalize_json_value(v)
	var s := JSON.stringify(canon)
	return s.to_utf8_buffer()

static func _is_intlike(x: float) -> bool:
	var r := round(x)
	return abs(x - r) <= 0.000001

static func coerce_comfy_prompt_types(v: Variant, parent_key: String = "") -> Variant:
	var t := typeof(v)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		var out: Dictionary = {}
		for k_any in d.keys():
			var k := str(k_any)
			out[k_any] = coerce_comfy_prompt_types(d.get(k_any), k.to_lower())
		return out
	if t == TYPE_ARRAY:
		var a: Array = v
		if a.size() == 2 and typeof(a[0]) == TYPE_STRING and typeof(a[1]) == TYPE_FLOAT and _is_intlike(float(a[1])):
			return [str(a[0]), int(a[1])]
		var out_a: Array = []
		out_a.resize(a.size())
		for i in range(a.size()):
			out_a[i] = coerce_comfy_prompt_types(a[i], parent_key)
		return out_a
	if t == TYPE_FLOAT:
		var f := float(v)
		if parent_key in ["seed", "steps", "start_at_step", "end_at_step", "width", "height", "batch_size", "clip_skip"]:
			if _is_intlike(f):
				return int(f)
		return f
	return v

static func extract_comfy_prompt_graph(workflow_json: Dictionary) -> Dictionary:
	var prompt_any: Variant = workflow_json
	if workflow_json.has("prompt") and typeof(workflow_json.get("prompt")) == TYPE_DICTIONARY:
		prompt_any = workflow_json.get("prompt")
	if typeof(prompt_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "workflow_prompt_missing"}
	var prompt: Dictionary = prompt_any
	var has_node := false
	for k in prompt.keys():
		var n_any: Variant = prompt.get(k)
		if typeof(n_any) == TYPE_DICTIONARY and (n_any as Dictionary).has("class_type"):
			has_node = true
			break
	if not has_node:
		return {
			"ok": false,
			"error": "workflow_not_api_prompt_graph",
			"details": "Expected ComfyUI API prompt graph (dict keyed by node ids; node dicts contain class_type). If you exported from ComfyUI, use API format and paste the prompt graph (or JSON containing top-level 'prompt').",
		}
	var coerced_any: Variant = coerce_comfy_prompt_types(prompt, "")
	var coerced: Dictionary = coerced_any if typeof(coerced_any) == TYPE_DICTIONARY else prompt
	return {"ok": true, "prompt": coerced}

static func extract_seed_info_from_patches(patches: Array) -> Dictionary:
	var seeds: Array = []
	var offsets: Array = []
	for p_any in patches:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_any
		var key := str(p.get("input", "")).strip_edges().to_lower()
		if key.is_empty():
			continue
		if key == "seed" or key.ends_with(".seed") or key.contains("seed"):
			seeds.append(p.get("value", null))
		if key.contains("offset"):
			offsets.append({"input": key, "value": p.get("value", null)})
	return {"seeds": seeds, "offsets": offsets}

static func extract_model_identifiers_from_workflow(workflow: Dictionary) -> Array:
	var ids: Array = []
	for node_id in workflow.keys():
		var n_any: Variant = workflow.get(node_id)
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		var inputs_any: Variant = n.get("inputs", {})
		if typeof(inputs_any) != TYPE_DICTIONARY:
			continue
		var inputs: Dictionary = inputs_any
		for k in inputs.keys():
			var ks := str(k).strip_edges().to_lower()
			if not (ks in ["ckpt_name", "checkpoint", "model_name", "vae_name", "lora_name"]):
				continue
			var val := str(inputs.get(k, "")).strip_edges()
			if not val.is_empty() and not ids.has(val):
				ids.append(val)
	return ids

static func extract_prompt_text_from_patches(patches: Array) -> String:
	var lines: Array[String] = []
	for p_any in patches:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_any
		var key := str(p.get("input", "")).strip_edges().to_lower()
		if key.is_empty():
			continue
		if key in ["text", "prompt", "positive", "negative"]:
			var val := str(p.get("value", "")).strip_edges()
			if not val.is_empty():
				lines.append("%s: %s" % [key, val])
	return "\n".join(lines)
