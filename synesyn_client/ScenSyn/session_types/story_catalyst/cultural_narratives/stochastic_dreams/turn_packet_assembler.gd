extends RefCounted
class_name SDTurnPacketAssembler
## Loads the narrative Odu ontology and the Option B three-lattice ontology
## (uwp_bindings × ifa_odu + binding_x_odu overrides), builds board beads
## from coin detections, selects a UWP binding from pendulum dominant sector
## + secondary bead, selects an Odu mode from pendulum (stability, 1-entropy)
## quantization, composes the merged preset, and assembles the full
## ScenSyn-compatible turn packet dictionary.
##
## Option-B-only (post task 11). See
## ScenSyn/session_types/story_catalyst/cultural_narratives/stochastic_dreams/
## docs_for_update_on_bindings_odu_matrix_refinement/uwp_ifa_coherence_design.md
## §8.6 for selection rules and §14.2(c) for the end-state contract.


const CLASS_TO_BEAD: Dictionary = {
	"will": "Will", "fount": "Fount", "ethos": "Ethos",
	"cycle": "Cycle", "seed": "Seed",
}

# UWP quadrant offsets into the 16-binding canonical order (§3.2).
const QUADRANT_OFFSETS: Dictionary = {
	"Fount": 0, "Ethos": 4, "Cycle": 8, "Will": 12,
}

# Canonical within-quadrant order used by _select_binding. A design decision
# owned by the assembler (post task 11, no longer stored in JSON).
const BEAD_SUB_INDEX: Dictionary = {
	"Fount": 0, "Ethos": 1, "Cycle": 2, "Will": 3, "Seed": 0,
}

var _board_w: int = 760
var _board_h: int = 760
var _sector_anchors: Dictionary = {}

# Narrative Odu ontology (odu_ontology.json).
var _odu_list: Array = []
var _odu_by_name: Dictionary = {}

# Option B three-lattice ontology (uwp_16x16_ontology.json).
var _uwp_bindings: Array = []
var _ifa_odu: Array = []
var _binding_x_odu: Dictionary = {}
var _binding_by_id: Dictionary = {}
var _odu_by_canonical_index: Dictionary = {}
var _uwp_16x16_loaded: bool = false

var _seq: int = 0


func _init(config: Dictionary) -> void:
	_board_w = maxi(1, int(config.get("board_warped_size", [760, 760])[0]))
	_board_h = maxi(1, int(config.get("board_warped_size", [760, 760])[1]))
	_sector_anchors = config.get("sector_anchors", {
		"Fount": [0.78, 0.24], "Ethos": [0.50, 0.78],
		"Will": [0.50, 0.18], "Cycle": [0.22, 0.78],
	})
	_load_ontology()
	_load_uwp_16x16_ontology()


func _load_ontology() -> void:
	var path := "res://ScenSyn/session_types/story_catalyst/cultural_narratives/stochastic_dreams/odu_ontology.json"
	if not FileAccess.file_exists(path):
		push_error("SDTurnPacketAssembler: odu_ontology.json not found at %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("SDTurnPacketAssembler: failed to parse odu_ontology.json")
		return
	var data: Dictionary = json.data
	_odu_list = data.get("odu", [])
	for odu_entry in _odu_list:
		_odu_by_name[str(odu_entry["odu_name"])] = odu_entry
	print("SDTurnPacketAssembler: loaded %d narrative Odu entries" % _odu_list.size())


func _load_uwp_16x16_ontology() -> void:
	_uwp_16x16_loaded = false
	var path := "res://ScenSyn/session_types/story_catalyst/cultural_narratives/stochastic_dreams/uwp_16x16_ontology.json"
	if not FileAccess.file_exists(path):
		push_error("SDTurnPacketAssembler: uwp_16x16_ontology.json not found at %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("SDTurnPacketAssembler: failed to parse uwp_16x16_ontology.json")
		return
	var data: Dictionary = json.data
	_uwp_bindings = data.get("uwp_bindings", [])
	_ifa_odu = data.get("ifa_odu", [])
	_binding_x_odu = data.get("binding_x_odu", {})
	if _uwp_bindings.size() != 16:
		push_error("SDTurnPacketAssembler: uwp_bindings must have 16 entries (got %d)" % _uwp_bindings.size())
		return
	if _ifa_odu.size() != 16:
		push_error("SDTurnPacketAssembler: ifa_odu must have 16 entries (got %d)" % _ifa_odu.size())
		return
	for binding in _uwp_bindings:
		_binding_by_id[int(binding["id"])] = binding
	for odu_entry in _ifa_odu:
		_odu_by_canonical_index[int(odu_entry["canonical_index"])] = odu_entry
	_uwp_16x16_loaded = true
	print("SDTurnPacketAssembler: loaded three-lattice ontology — %d bindings, %d ifa_odu, %d cell overrides" % [
		_uwp_bindings.size(), _ifa_odu.size(), _binding_x_odu.size(),
	])


func assemble(board_detections: Dictionary, tracking_samples: Array) -> Dictionary:
	if not _uwp_16x16_loaded:
		push_warning("SDTurnPacketAssembler: uwp_16x16 ontology not loaded — skipping turn")
		return {}

	var beads: Array = _build_beads(board_detections)
	if beads.is_empty():
		push_warning("SDTurnPacketAssembler: no valid bead detections; skipping turn")
		return {}

	var traversal: Dictionary = SDUWPTraversalAnalyzer.analyze_traversal(tracking_samples, _sector_anchors)
	var pendulum_metrics: Dictionary = SDUWPTraversalAnalyzer.analyze_pendulum_motion(tracking_samples, traversal)

	var primary_bead: String = _pick_primary(beads)
	var secondary_bead: String = _pick_secondary(beads, primary_bead)
	var axis_x_bias: String = _summarize_axis_x(beads)
	var axis_y_bias: String = _summarize_axis_y(beads)
	var perturbation: float = _compute_perturbation(beads)

	var binding_id: int = _select_binding(str(traversal["dominant_sector"]), secondary_bead)
	var odu_id: int = _select_odu_mode(pendulum_metrics)
	var preset: Dictionary = _compose_preset(binding_id, odu_id)
	if preset.is_empty():
		push_warning("SDTurnPacketAssembler: preset composition failed (binding_id=%d odu_id=%d) — skipping turn" % [binding_id, odu_id])
		return {}

	var resonance: float = _compute_resonance(primary_bead, secondary_bead, traversal, pendulum_metrics)
	var quality: Dictionary = _build_quality(tracking_samples)

	var axis_y_short: String = "Centralized" if axis_y_bias == "Centralized Rule" else "Distributed"
	var axis_position: String = "%s & %s" % [axis_x_bias, axis_y_short]
	var bead_emphasis: String = "%s and %s dominate; Seed modulates the turn." % [primary_bead, secondary_bead]
	var pendulum_summary: String = "Dominant dwell in %s with %.2f stability and %d crossings." % [
		str(traversal["dominant_sector"]),
		float(pendulum_metrics["stability"]),
		int(traversal["crossings"]),
	]

	var shared: Dictionary = {
		"odu_name": preset["odu_name"],
		"predicament_family_id": preset["predicament_family_id"],
		"predicament_family": preset["predicament_family"],
		"tapestry_region_primary": preset["tapestry_region_primary"],
		"province_or_site": preset["province_or_site"],
		"world_domain_focus": preset["world_domain_focus"],
		"bead_emphasis_summary": bead_emphasis,
		"axis_emphasis_summary": "%s over %s; %s over %s." % [
			axis_x_bias.capitalize(),
			"Restoration" if axis_x_bias.to_lower() == "innovation" else "Innovation",
			"Centralized Rule" if axis_y_bias == "Centralized Rule" else "Distributed Commons",
			"Distributed Commons" if axis_y_bias == "Centralized Rule" else "Centralized Rule",
		],
		"pendulum_summary": pendulum_summary,
	}

	_seq += 1
	var clean_beads: Array = []
	for bead_entry in beads:
		var clean: Dictionary = {}
		for bead_key in bead_entry:
			if not str(bead_key).begins_with("_"):
				clean[bead_key] = bead_entry[bead_key]
		clean_beads.append(clean)

	var packet: Dictionary = {
		"event": "stochastic_dreams_turn",
		"schema_version": "1.0",
		"source_id": "lubi_board_bridge",
		"window_id": int(Time.get_unix_time_from_system() * 1000.0),
		"timestamp": Time.get_unix_time_from_system(),
		"board": {
			"beads": clean_beads,
			"perturbation_factor": perturbation,
			"primary_bead": primary_bead,
			"secondary_bead": secondary_bead,
			"axis_x_bias": axis_x_bias.to_lower(),
			"axis_y_bias": axis_y_short.to_lower(),
			"axis_position": axis_position,
			"bead_emphasis_summary": bead_emphasis,
		},
		"beads": {
			"primary_concept": primary_bead,
			"axis_position": axis_position,
		},
		"uwp_traversal": traversal,
		"pendulum": pendulum_metrics,
		"resonance": resonance,
		"quality": quality,
		"odu": str(preset["odu_name"]),
		"matrix_resolution": {
			"concept_id": preset["concept_id"],
			"concept_name": preset["concept_name"],
			"utopian_domain": preset["utopian_domain"],
			"odu_name": preset["odu_name"],
			"odu_bits": preset["odu_bits"],
			"predicament_family_id": preset["predicament_family_id"],
			"predicament_family": preset["predicament_family"],
			"complementary_odu": preset["complementary_odu"],
			"tapestry_region_primary": preset["tapestry_region_primary"],
			"tapestry_region_secondary": preset["tapestry_region_secondary"],
			"province_or_site": preset["province_or_site"],
			"world_domain_focus": preset["world_domain_focus"],
			"failure_state_risk": preset["failure_state_risk"],
			"flourishing_state_potential": preset["flourishing_state_potential"],
			"binding_id": int(preset["binding_id"]),
			"binding_name": str(preset["binding_name"]),
		},
		"turn_packet": {
			"shared": shared,
			"diviner": {
				"diviner_operation_cue": preset["diviner_operation_cue"],
				"operation_register": preset["operation_register"],
				"closure_tendency": preset["closure_tendency"],
				"shadow_tendency": preset["shadow_tendency"],
				"map_maker_move": preset["map_maker_move"],
				"path_finder_move": preset["path_finder_move"],
			},
			"echo": {
				"echo_omen_cue": preset["echo_omen_cue"],
				"complement_family_id": preset["predicament_family_id"],
				"complementary_odu": preset["complementary_odu"],
				"failure_state_risk": preset["failure_state_risk"],
			},
			"seeker": {
				"seeker_manifestation_cue": preset["seeker_manifestation_cue"],
				"visible_gain": preset["visible_gain"],
				"hidden_cost": preset["hidden_cost"],
				"visible_world_effect": preset["visible_world_effect"],
				"flourishing_state_potential": preset["flourishing_state_potential"],
			},
			"narrator": {
				"narrator_handoff_cue": preset["narrator_handoff_cue"],
				"next_question": preset["next_question"],
				"failure_state_risk": preset["failure_state_risk"],
				"flourishing_state_potential": preset["flourishing_state_potential"],
			},
		},
	}
	return packet


# ── Board helpers ─────────────────────────────────────────────────────────────

func _build_beads(board_detections: Dictionary) -> Array:
	var beads: Array = []
	for cls_name in board_detections:
		var bead_name: String = CLASS_TO_BEAD.get(str(cls_name).to_lower(), "")
		if bead_name == "":
			continue
		var point: Array = board_detections[cls_name]
		var x: float = clampf(float(point[0]) / float(_board_w), 0.0, 1.0)
		var y: float = clampf(float(point[1]) / float(_board_h), 0.0, 1.0)
		beads.append({
			"name": bead_name,
			"detected_class": str(cls_name),
			"grid_x": snappedf(x, 0.0001),
			"grid_y": snappedf(y, 0.0001),
			"axis_x_label": _axis_x_label(x),
			"axis_y_label": _axis_y_label(y),
			"_radius": sqrt(pow(x - 0.5, 2) + pow(y - 0.5, 2)),
		})
	beads.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return beads


func _pick_primary(beads: Array) -> String:
	var best: String = "Seed"
	var best_r: float = -1.0
	for bead_entry in beads:
		if float(bead_entry["_radius"]) > best_r:
			best_r = float(bead_entry["_radius"])
			best = str(bead_entry["name"])
	return best


func _pick_secondary(beads: Array, primary: String) -> String:
	var best: String = primary
	var best_r: float = -1.0
	for bead_entry in beads:
		if str(bead_entry["name"]) != primary and float(bead_entry["_radius"]) > best_r:
			best_r = float(bead_entry["_radius"])
			best = str(bead_entry["name"])
	return best


func _summarize_axis_x(beads: Array) -> String:
	if beads.is_empty():
		return "Balanced"
	var total: float = 0.0
	for bead_entry in beads:
		total += float(bead_entry["grid_x"])
	var x_mean: float = total / float(beads.size())
	return "Innovation" if x_mean >= 0.5 else "Restoration"


func _summarize_axis_y(beads: Array) -> String:
	if beads.is_empty():
		return "Balanced"
	var total: float = 0.0
	for bead_entry in beads:
		total += float(bead_entry["grid_y"])
	var y_mean: float = total / float(beads.size())
	return "Distributed Commons" if y_mean >= 0.5 else "Centralized Rule"


func _compute_perturbation(beads: Array) -> float:
	for bead_entry in beads:
		if str(bead_entry["name"]) == "Seed":
			return snappedf(minf(1.0, float(bead_entry["_radius"]) / 0.71), 0.001)
	return 0.25


func _compute_resonance(primary: String, secondary: String, traversal: Dictionary, pendulum: Dictionary) -> float:
	var score: float = 0.35
	var dominant: String = str(traversal.get("dominant_sector", ""))
	if dominant == primary:
		score += 0.25
	if dominant == secondary:
		score += 0.12
	score += float(pendulum.get("stability", 0.0)) * 0.18
	score += maxf(0.0, 1.0 - float(pendulum.get("entropy", 0.0))) * 0.1
	if dominant == "Seed":
		score -= 0.08
	return snappedf(clampf(score, 0.0, 1.0), 0.001)


func _build_quality(samples: Array) -> Dictionary:
	var valid_count: int = 0
	for sample in samples:
		if sample.get("x") != null:
			valid_count += 1
	var total: int = samples.size()
	var dropped: int = total - valid_count
	var avg_conf: float = 0.95
	if valid_count > 0:
		avg_conf = 1.0 - (float(dropped) / maxf(1.0, float(total)))
	var flags: Array = []
	if total == 0:
		flags.append("no_samples")
	elif dropped > total * 0.25:
		flags.append("tracking_soft")
	return {
		"tracking_confidence": snappedf(avg_conf, 0.001),
		"board_confidence": 0.95,
		"dropped_frames": dropped,
		"health_flags": flags,
	}


# ── Option B selection (§8.6) ─────────────────────────────────────────────────

## Quadrant offset + within-quadrant index. Falls back to Will when dominant
## sector is Seed or unrecognized (§8.6.1). Returns binding_id in [1, 16].
func _select_binding(dominant_sector: String, secondary_bead: String) -> int:
	var quadrant: String = dominant_sector
	if not QUADRANT_OFFSETS.has(quadrant):
		quadrant = "Will"
	var within: int = int(BEAD_SUB_INDEX.get(secondary_bead, 0))
	within = clampi(within, 0, 3)
	var offset: int = int(QUADRANT_OFFSETS[quadrant])
	return offset + within + 1


## 4×4 quantization of (stability, 1 − entropy). Returns odu_id in [1, 16],
## addressing ifa_odu by canonical_index (§8.6.2).
func _select_odu_mode(pendulum_metrics: Dictionary) -> int:
	var stability: float = clampf(float(pendulum_metrics.get("stability", 0.0)), 0.0, 1.0)
	var entropy: float = clampf(float(pendulum_metrics.get("entropy", 0.0)), 0.0, 1.0)
	var stability_bin: int = clampi(int(floor(stability * 4.0)), 0, 3)
	var inverse_entropy_bin: int = clampi(int(floor((1.0 - entropy) * 4.0)), 0, 3)
	return stability_bin * 4 + inverse_entropy_bin + 1


## Merge order (later overwrites earlier) per §8.6.3:
##   1. narrative legacy_odu (carries predicament/diviner/echo/seeker/narrator cues)
##   2. uwp_bindings[binding_id] (concept_id/name/domain + optional region/site/world)
##   3. ifa_odu[odu_id] (odu_name, odu_bits)
##   4. binding_x_odu["<bid>.<oid>"] sparse overrides
## Emits two extra keys: binding_id, binding_name.
func _compose_preset(binding_id: int, odu_id: int) -> Dictionary:
	var binding: Dictionary = _binding_by_id.get(binding_id, {})
	var ifa_entry: Dictionary = _odu_by_canonical_index.get(odu_id, {})
	if binding.is_empty() or ifa_entry.is_empty():
		return {}
	var legacy_odu_name: String = str(ifa_entry.get("odu_name", ""))
	var legacy_odu: Dictionary = _odu_by_name.get(legacy_odu_name, {})
	if legacy_odu.is_empty():
		return {}

	var preset: Dictionary = legacy_odu.duplicate(true)

	preset["concept_id"] = int(binding.get("id", preset.get("concept_id", 0)))
	preset["concept_name"] = str(binding.get("binding_name", preset.get("concept_name", "")))
	preset["utopian_domain"] = str(binding.get("domain", preset.get("utopian_domain", "")))

	var region_primary: String = str(binding.get("tapestry_region_primary", ""))
	if region_primary != "":
		preset["tapestry_region_primary"] = region_primary
	var province: String = str(binding.get("province_or_site", ""))
	if province != "":
		preset["province_or_site"] = province
	var world_focus: String = str(binding.get("world_domain_focus", ""))
	if world_focus != "":
		preset["world_domain_focus"] = world_focus

	preset["odu_name"] = str(ifa_entry.get("odu_name", preset.get("odu_name", "")))
	preset["odu_bits"] = str(ifa_entry.get("odu_bits", preset.get("odu_bits", "")))

	var cell_key: String = "%d.%d" % [binding_id, odu_id]
	var override: Variant = _binding_x_odu.get(cell_key, null)
	if typeof(override) == TYPE_DICTIONARY:
		for key in (override as Dictionary):
			preset[key] = override[key]

	preset["binding_id"] = binding_id
	preset["binding_name"] = str(binding.get("binding_name", ""))
	return preset


# ── Axis label helpers ────────────────────────────────────────────────────────

static func _axis_x_label(x: float) -> String:
	if x > 0.6:
		return "Innovation"
	if x < 0.4:
		return "Restoration"
	return "Balanced"


static func _axis_y_label(y: float) -> String:
	if y < 0.4:
		return "Centralized Rule"
	if y > 0.6:
		return "Distributed Commons"
	return "Balanced"
