extends RefCounted
class_name WorkshopClosureAuditRules

## Purpose: derive the *shape* of the Thinking Map's closure, for the Closure Audit
## (ADR 0020).
##
## `workshop_thinking_map_symbolic_rules.gd` reads what is present — contradictions,
## causal chains, weakly evidenced premises. Closure Mapping's two primary
## diagnostics instead read what is absent or over-represented: the empty quadrant
## and the concentrated quadrant. This module supplies those two readings.
##
## Same contract as the symbolic rules: static, deterministic, explainable,
## read-only. It derives findings and never mutates the document, never writes a
## finding back as a node or edge, and has no opinion on review actions. It also
## has no opinion on what an absence *means* — classifying an empty quadrant as
## not applicable, deliberately excluded, unknown, suppressed, or not-yet-formed is
## a human judgement the audit surface collects, because the manual's whole point
## is that geometry must not be diagnosed before how the geometry was produced.

const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)

## Rejected claims are dead weight, as in the symbolic rules; everything still
## under consideration counts.
const _INACTIVE_STATUSES: Array[String] = ["rejected"]

## Below this many oriented claims, "dominant" and "empty" describe the sample
## rather than the room's thinking, so no reading is offered at all. Four is the
## smallest count that can distribute across the quadrants at all unevenly.
const MIN_TAGGED_FOR_READING: int = 4

## A populated quadrant counts as weak when it holds no more than this share of
## the dominant quadrant's material. Relative rather than an absolute floor, so
## the reading scales with session size instead of calling everything weak in a
## long session and nothing weak in a short one.
const WEAK_SHARE_OF_DOMINANT: float = 0.25


static func evaluate(document: Dictionary) -> Dictionary:
	var coverage: Dictionary = _count_by_quadrant(document)
	var tagged_count: int = 0
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		tagged_count += int(coverage.get(quadrant_id, 0))
	var untagged_count: int = int(coverage.get("untagged", 0))
	var has_reading: bool = tagged_count >= MIN_TAGGED_FOR_READING
	var dominant_quadrants: Array[String] = []
	var empty_quadrants: Array[String] = []
	var weak_quadrants: Array[String] = []
	if has_reading:
		dominant_quadrants = _dominant_quadrants(coverage)
		empty_quadrants = _empty_quadrants(coverage)
		weak_quadrants = _weak_quadrants(coverage, dominant_quadrants)
	# A tie is not a dominant closure. Reporting one anyway would invent a
	# concentration the material does not show; §8.3's "two opposite quadrants
	# dominate" is a separate reading over `dominant_quadrants`.
	var dominant_quadrant: String = ""
	if dominant_quadrants.size() == 1:
		dominant_quadrant = dominant_quadrants[0]
	var findings: Dictionary = {
		"coverage": coverage,
		"tagged_count": tagged_count,
		"untagged_count": untagged_count,
		"axis_totals": _axis_totals(coverage),
		"has_reading": has_reading,
		"min_tagged_for_reading": MIN_TAGGED_FOR_READING,
		"dominant_quadrant": dominant_quadrant,
		"dominant_quadrants": dominant_quadrants,
		"empty_quadrants": empty_quadrants,
		"weak_quadrants": weak_quadrants,
		"single_source_quadrants": _single_source_quadrants(document),
	}
	findings.merge(_contestation_counts(document))
	return findings


## Spells the reading out in facilitator language, for the coverage tooltip.
##
## Text generation sits here rather than in the controller for two reasons: it is a pure
## function of the findings, so it can be asserted headlessly where the controller cannot
## be instantiated at all (ADR 0017 rule 6); and the controller is near the soft line
## limit, where the formatting would keep pushing it.
##
## It names an empty quadrant but deliberately does not tell the room to fill it: an
## absence has to be classified as irrelevant, chosen, unknown, suppressed, or emergent
## before it counts as a gap, and filling one for the sake of symmetry is the failure this
## instrument exists to prevent.
static func format_reading(findings: Dictionary) -> String:
	var lines: Array[String] = []
	var coverage: Dictionary = findings.get("coverage", {})
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		lines.append("%s: %d claim(s). %s" % [
			ClosureOrientationScript.get_canonical_with_gloss(quadrant_id),
			int(coverage.get(quadrant_id, 0)),
			String(ClosureOrientationScript.CHARACTER_BY_QUADRANT.get(quadrant_id, "")),
		])
	var axis_totals: Dictionary = findings.get("axis_totals", {})
	var distal_count: int = int(axis_totals.get("distal", 0))
	var deep_count: int = int(axis_totals.get("deep", 0))
	lines.append("Distal %d against Deep %d." % [distal_count, deep_count])
	if distal_count > 0 and deep_count == 0:
		lines.append(
			"Nothing tagged in the Deep half. The group looked outward at the wider"
			+ " world without looking at its own habits and structures."
		)
	var empty_quadrants: Array = findings.get("empty_quadrants", [])
	if not empty_quadrants.is_empty():
		lines.append(
			"Empty: %s. Say why each one is empty before you treat it as a gap."
			% ClosureOrientationScript.join_canonical_terms(empty_quadrants)
		)
	lines.append_array(_format_contestation_lines(findings))
	var single_source: Dictionary = findings.get("single_source_quadrants", {})
	for quadrant_id: String in single_source.keys():
		var entry: Dictionary = single_source[quadrant_id]
		lines.append(
			"%s comes entirely from %s (%d claim(s)). It looks covered, but only one"
			% [
				ClosureOrientationScript.get_canonical_term(quadrant_id),
				String(entry.get("author", "")),
				int(entry.get("claim_count", 0)),
			]
			+ " person put anything there."
		)
	return "\n".join(lines)


## Asserted and derived splits read differently to a facilitator, so they are worded
## differently: one is their own earlier judgement handed back to them, the other is
## evidence the room produced.
static func _format_contestation_lines(findings: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var derived_count: int = int(findings.get("contested_derived_count", 0))
	var asserted_count: int = int(findings.get("contested_asserted_count", 0))
	var substance_count: int = int(findings.get("contested_substance_count", 0))
	var incomplete_count: int = int(findings.get("incomplete_register_count", 0))
	if derived_count > 0:
		lines.append(
			"%d claim(s) where the recorded views disagree about placement. People do"
			% derived_count
			+ " not read these the same way."
		)
	if asserted_count > 0:
		lines.append(
			"%d claim(s) you marked contested in discussion." % asserted_count
		)
	if substance_count > 0:
		lines.append(
			"%d claim(s) contested on substance. People agree where these sit but not"
			% substance_count
			+ " whether they are true."
		)
	if incomplete_count > 0:
		lines.append(
			"%d register(s) still name no test that would settle the disagreement, so"
			% incomplete_count
			+ " it stays unresolved."
		)
	return lines


## Reported unconditionally, with no `has_reading` gate. The gated readings are
## statistical and need a sample before they mean anything; a contested claim is a
## recorded observation about one claim, so a single one is already true and already
## worth acting on.
##
## Asserted and derived are counted apart as well as together, because they are different
## kinds of evidence: a facilitator's mark is a judgement about a conversation, divergent
## recorded views are the disagreement itself. `incomplete_register_count` then tracks
## splits that name no discriminating test — recorded disagreements that nothing yet
## stands to resolve.
static func _contestation_counts(document: Dictionary) -> Dictionary:
	var contested_total: int = 0
	var asserted_total: int = 0
	var derived_total: int = 0
	var incomplete_total: int = 0
	var substance_total: int = 0
	for node_any: Variant in _active_nodes(document):
		var node_data: Dictionary = node_any
		var is_asserted: bool = ClosureOrientationScript.has_asserted_contested(node_data)
		var is_derived: bool = ClosureOrientationScript.is_dimension_contested(
			node_data, ClosureOrientationScript.DIMENSION_PLACEMENT
		)
		if is_asserted:
			asserted_total += 1
		if is_derived:
			derived_total += 1
		if is_asserted or is_derived:
			contested_total += 1
		if is_derived and not ClosureOrientationScript.is_register_complete(
			node_data, ClosureOrientationScript.DIMENSION_PLACEMENT
		):
			incomplete_total += 1
		if ClosureOrientationScript.is_dimension_contested(
			node_data, ClosureOrientationScript.DIMENSION_SUBSTANCE
		):
			substance_total += 1
			if not ClosureOrientationScript.is_register_complete(
				node_data, ClosureOrientationScript.DIMENSION_SUBSTANCE
			):
				incomplete_total += 1
	return {
		"contested_count": contested_total,
		"contested_asserted_count": asserted_total,
		"contested_derived_count": derived_total,
		"contested_substance_count": substance_total,
		"incomplete_register_count": incomplete_total,
	}


## REQ-CA-011: whether one participant supplied a whole quadrant. A quadrant filled by a
## single voice is the expertise-bias pathology in its plainest form — it looks like
## coverage on the map while resting entirely on one person's reading, and no amount of
## material in it makes the room's thinking any broader.
##
## Requires at least two claims: one claim from one author is not a concentration, it is
## simply a claim, and reporting it would fire on almost every quadrant early in a session.
static func _single_source_quadrants(document: Dictionary) -> Dictionary:
	var authors_by_quadrant: Dictionary = {}
	for node_any: Variant in _active_nodes(document):
		var node_data: Dictionary = node_any
		var quadrant_id: String = ClosureOrientationScript.get_node_quadrant(node_data)
		if quadrant_id.is_empty():
			continue
		var author_ref: String = _node_author(node_data)
		if author_ref.is_empty():
			continue
		var authors: Array = authors_by_quadrant.get(quadrant_id, [])
		authors.append(author_ref)
		authors_by_quadrant[quadrant_id] = authors
	var single_source: Dictionary = {}
	for quadrant_id: String in authors_by_quadrant.keys():
		var authors: Array = authors_by_quadrant[quadrant_id]
		if authors.size() < 2:
			continue
		var distinct_authors: Array[String] = []
		for author_any: Variant in authors:
			var author_ref: String = String(author_any)
			if author_ref not in distinct_authors:
				distinct_authors.append(author_ref)
		if distinct_authors.size() == 1:
			single_source[quadrant_id] = {
				"author": distinct_authors[0],
				"claim_count": authors.size(),
			}
	return single_source


## REQ-CA-011's source label. `authored_by` is what the map already records for both
## manual entries and accepted AI proposals, so the diagnostic reads the labelling that
## exists rather than requiring a parallel one.
static func _node_author(node_data: Dictionary) -> String:
	var provenance_any: Variant = node_data.get("provenance", {})
	if typeof(provenance_any) != TYPE_DICTIONARY:
		return ""
	return String((provenance_any as Dictionary).get("authored_by", "")).strip_edges()


## The claims an audit is about, each with the position it was tagged with, for a model asked
## to draft answers to the audit's steps (REQ-CA-021).
##
## Everything active, not just the untagged, which is the opposite of what orientation
## suggestion needs: the steps ask why a position is thin and what a pile-up means, and neither
## question can be answered without seeing which claims produced the shape.
static func collect_claims_for_audit(document: Dictionary) -> Array[Dictionary]:
	var claims: Array[Dictionary] = []
	for node_any: Variant in _active_nodes(document):
		var node_data: Dictionary = node_any
		var label: String = String(node_data.get("label", "")).strip_edges()
		if label.is_empty():
			continue
		claims.append({
			"id": String(node_data.get("id", "")),
			"kind": String(node_data.get("kind", "")),
			"label": label,
			"orientation": ClosureOrientationScript.get_node_quadrant(node_data),
		})
	return claims


static func _active_nodes(document: Dictionary) -> Array:
	var active_nodes: Array = []
	var nodes_any: Variant = document.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return active_nodes
	for node_any: Variant in (nodes_any as Array):
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		if String((node_any as Dictionary).get("status", "")) in _INACTIVE_STATUSES:
			continue
		active_nodes.append(node_any)
	return active_nodes


## Counts active nodes per quadrant, plus how many carry no orientation. Untagged
## is reported rather than hidden: a reading drawn from four tagged claims out of
## forty is a reading about the four.
static func _count_by_quadrant(document: Dictionary) -> Dictionary:
	var coverage: Dictionary = {"untagged": 0}
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		coverage[quadrant_id] = 0
	var nodes_any: Variant = document.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return coverage
	for node_any: Variant in (nodes_any as Array):
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		if String(node_data.get("status", "")) in _INACTIVE_STATUSES:
			continue
		var quadrant_id: String = ClosureOrientationScript.get_node_quadrant(node_data)
		var counter_key: String = quadrant_id if not quadrant_id.is_empty() else "untagged"
		coverage[counter_key] = int(coverage.get(counter_key, 0)) + 1
	return coverage


## Distal/deep and past/future totals. These make the pathology this instrument
## exists to catch directly readable: a map rich in A and B but thin in C and D is
## historically informed and strategically projected while never examining what the
## situation has already incorporated.
static func _axis_totals(coverage: Dictionary) -> Dictionary:
	return {
		"distal": int(coverage.get("A", 0)) + int(coverage.get("B", 0)),
		"deep": int(coverage.get("C", 0)) + int(coverage.get("D", 0)),
		"past": int(coverage.get("A", 0)) + int(coverage.get("C", 0)),
		"future": int(coverage.get("B", 0)) + int(coverage.get("D", 0)),
	}


static func _dominant_quadrants(coverage: Dictionary) -> Array[String]:
	var highest_count: int = 0
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		highest_count = maxi(highest_count, int(coverage.get(quadrant_id, 0)))
	var dominant: Array[String] = []
	if highest_count <= 0:
		return dominant
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		if int(coverage.get(quadrant_id, 0)) == highest_count:
			dominant.append(quadrant_id)
	# All four level is coverage, not concentration.
	if dominant.size() == ClosureOrientationScript.QUADRANTS.size():
		return [] as Array[String]
	return dominant


static func _empty_quadrants(coverage: Dictionary) -> Array[String]:
	var empty: Array[String] = []
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		if int(coverage.get(quadrant_id, 0)) == 0:
			empty.append(quadrant_id)
	return empty


## Populated but thin relative to the dominant quadrant. Excludes the dominant
## quadrants themselves, and yields nothing when there is no concentration to
## measure against.
static func _weak_quadrants(
	coverage: Dictionary,
	dominant_quadrants: Array[String]
) -> Array[String]:
	var weak: Array[String] = []
	if dominant_quadrants.is_empty():
		return weak
	var dominant_count: int = int(coverage.get(dominant_quadrants[0], 0))
	var weak_ceiling: float = float(dominant_count) * WEAK_SHARE_OF_DOMINANT
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		if quadrant_id in dominant_quadrants:
			continue
		var quadrant_count: int = int(coverage.get(quadrant_id, 0))
		if quadrant_count > 0 and float(quadrant_count) <= weak_ceiling:
			weak.append(quadrant_id)
	return weak


## One facilitator-facing line for the map status bar. States the rule it applied
## when it declines to read, so a blank reading is never mistaken for a balanced
## map.
##
## Quadrants are named by canonical term, not by letter. `A:3 B:0 C:1 D:2` asks a facilitator
## mid-session to hold a four-way mapping in their head to learn anything from the line, and
## the tooltip explained the distribution without ever giving the mapping. Canonical rather
## than the plain glosses because a coverage reading names quadrants *as coordinates*, and
## `closure_orientation.gd` records the upstream rule that a gloss never replaces the canonical
## term in that position — the glosses live in the label's tooltip instead.
static func format_summary(findings: Dictionary) -> String:
	var coverage: Dictionary = findings.get("coverage", {})
	var tagged_count: int = int(findings.get("tagged_count", 0))
	if tagged_count <= 0:
		return "Closure: no claims oriented yet."
	var counts: Array[String] = []
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		counts.append("%s %d" % [
			ClosureOrientationScript.get_canonical_term(quadrant_id),
			int(coverage.get(quadrant_id, 0)),
		])
	# Counts are comma-separated so the middle dots stay available to separate the readings.
	var parts: Array[String] = ["Closure: " + ", ".join(counts)]
	var untagged_count: int = int(findings.get("untagged_count", 0))
	if untagged_count > 0:
		parts.append("%d untagged" % untagged_count)
	if not bool(findings.get("has_reading", false)):
		parts.append("no reading below %d oriented" % int(
			findings.get("min_tagged_for_reading", MIN_TAGGED_FOR_READING)
		))
		return " \u00b7 ".join(parts)
	var dominant_quadrant: String = String(findings.get("dominant_quadrant", ""))
	if not dominant_quadrant.is_empty():
		parts.append(
			"dominant %s" % ClosureOrientationScript.get_canonical_term(dominant_quadrant)
		)
	var empty_quadrants: Array = findings.get("empty_quadrants", [])
	if not empty_quadrants.is_empty():
		parts.append(
			"empty %s" % ClosureOrientationScript.join_canonical_terms(empty_quadrants)
		)
	var weak_quadrants: Array = findings.get("weak_quadrants", [])
	if not weak_quadrants.is_empty():
		parts.append(
			"weak %s" % ClosureOrientationScript.join_canonical_terms(weak_quadrants)
		)
	return " \u00b7 ".join(parts)
