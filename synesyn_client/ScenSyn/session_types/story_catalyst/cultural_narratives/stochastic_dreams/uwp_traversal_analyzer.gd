extends RefCounted
class_name SDUWPTraversalAnalyzer
## Pure analysis functions for classifying pendulum tracking samples into
## UWP sectors and deriving traversal + motion metrics.
## No I/O, no scene tree dependency.


static func analyze_traversal(samples: Array, sector_anchors: Dictionary) -> Dictionary:
	var valid: Array = []
	for sample in samples:
		if sample.get("x") != null and sample.get("y") != null:
			valid.append(sample)

	if valid.is_empty():
		var dwell: Dictionary = {}
		for sector_name in sector_anchors:
			dwell[sector_name] = 0.0
		var first_sector: String = "Will"
		if not sector_anchors.is_empty():
			first_sector = sector_anchors.keys()[0]
		return {
			"dominant_sector": first_sector,
			"dwell_fractions": dwell,
			"path_sequence": [],
			"crossings": 0,
			"stability": 0.0,
		}

	var counts: Dictionary = {}
	for sector_name in sector_anchors:
		counts[sector_name] = 0
	var path_sequence: Array = []
	var previous_sector: String = ""
	var crossings: int = 0

	for sample in valid:
		var sector: String = _nearest_sector(float(sample["x"]), float(sample["y"]), sector_anchors)
		counts[sector] = counts.get(sector, 0) + 1
		if sector != previous_sector:
			path_sequence.append({"sector": sector, "t": snappedf(float(sample["t_s"]), 0.001)})
			if previous_sector != "":
				crossings += 1
			previous_sector = sector

	var total: float = float(valid.size())
	var dwell: Dictionary = {}
	for sector_name in counts:
		dwell[sector_name] = snappedf(float(counts[sector_name]) / total, 0.0001)

	var dominant: String = _max_key(dwell)
	var stability: float = snappedf(_estimate_stability(valid, crossings), 0.001)

	return {
		"dominant_sector": dominant,
		"dwell_fractions": dwell,
		"path_sequence": path_sequence.slice(0, 24),
		"crossings": crossings,
		"stability": stability,
	}


static func analyze_pendulum_motion(samples: Array, traversal: Dictionary) -> Dictionary:
	var valid: Array = []
	for sample in samples:
		if sample.get("x") != null and sample.get("y") != null:
			valid.append(sample)

	if valid.size() < 2:
		return {
			"bias": 0.0,
			"stability": float(traversal.get("stability", 0.0)),
			"period_s": 0.0,
			"amplitude": 0.0,
			"entropy": 0.0,
			"pattern_tag": "LINEAR_OSCILLATION",
		}

	var xs: Array = []
	var ys: Array = []
	var ts: Array = []
	for sample in valid:
		xs.append(float(sample["x"]))
		ys.append(float(sample["y"]))
		ts.append(float(sample["t_s"]))

	var x_centered_sum: float = 0.0
	var max_amp: float = 0.0
	for idx in range(xs.size()):
		x_centered_sum += (xs[idx] - 0.5) * 2.0
		var amp: float = sqrt(pow(xs[idx] - 0.5, 2) + pow(ys[idx] - 0.5, 2))
		if amp > max_amp:
			max_amp = amp

	var bias: float = clampf(x_centered_sum / float(xs.size()), -1.0, 1.0)
	var amplitude: float = minf(1.0, max_amp * 2.0)
	var cross_count: int = int(traversal.get("crossings", 0))
	var entropy: float = minf(1.0, float(cross_count) / maxf(1.0, float(valid.size()) / 3.0))

	var period: float = 0.0
	if cross_count > 0:
		period = ts[-1] / maxf(1.0, float(cross_count))
	elif ts[-1] > 0:
		period = ts[-1]

	var pattern_tag: String = _pattern_tag(xs, ys, entropy)

	return {
		"bias": snappedf(bias, 0.001),
		"stability": float(traversal.get("stability", 0.0)),
		"period_s": snappedf(period, 0.001),
		"amplitude": snappedf(amplitude, 0.001),
		"entropy": snappedf(entropy, 0.001),
		"pattern_tag": pattern_tag,
	}


# ── Helpers ───────────────────────────────────────────────────────────────────

static func _nearest_sector(x: float, y: float, sector_anchors: Dictionary) -> String:
	var best: String = "Will"
	if not sector_anchors.is_empty():
		best = sector_anchors.keys()[0]
	var best_dist: float = 999.0
	for sector_name in sector_anchors:
		var anchor: Array = sector_anchors[sector_name]
		var dist: float = sqrt(pow(x - float(anchor[0]), 2) + pow(y - float(anchor[1]), 2))
		if dist < best_dist:
			best = sector_name
			best_dist = dist
	return best


static func _estimate_stability(samples: Array, crossings: int) -> float:
	if samples.size() < 3:
		return 0.5
	var step_total: float = 0.0
	var step_count: int = 0
	for idx in range(1, samples.size()):
		var prev: Dictionary = samples[idx - 1]
		var cur: Dictionary = samples[idx]
		step_total += sqrt(pow(float(cur["x"]) - float(prev["x"]), 2) + pow(float(cur["y"]) - float(prev["y"]), 2))
		step_count += 1
	var avg_step: float = step_total / maxf(1.0, float(step_count))
	var crossing_penalty: float = minf(0.6, float(crossings) / maxf(3.0, float(samples.size())))
	var value: float = 1.0 - minf(0.7, avg_step * 8.0) - crossing_penalty
	return clampf(value, 0.0, 1.0)


static func _pattern_tag(xs: Array, ys: Array, entropy: float) -> String:
	var x_span: float = xs.max() - xs.min()
	var y_span: float = ys.max() - ys.min()
	if entropy > 0.75:
		return "CHAOTIC"
	if x_span > 0.35 and y_span > 0.22:
		return "LISSAJOUS_ELLIPTICAL"
	if x_span > 0.35 and y_span <= 0.22:
		return "LINEAR_OSCILLATION"
	if x_span < 0.18 and y_span < 0.18:
		return "SPIRAL_IN"
	return "LISSAJOUS_FIGURE8"


static func _max_key(dict: Dictionary) -> String:
	var best_key: String = ""
	var best_val: float = -1.0
	for dict_key in dict:
		var val: float = float(dict[dict_key])
		if val > best_val:
			best_val = val
			best_key = str(dict_key)
	return best_key
