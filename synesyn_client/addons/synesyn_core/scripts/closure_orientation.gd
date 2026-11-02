extends RefCounted
class_name ClosureOrientation

## Purpose: the Closure Map quadrant vocabulary — one definition, for every surface
## that orients anything on it.
##
## Lives in `synesyn_core` because it is not any one surface's property. The Closure
## Map is a concept defined upstream in the Improved Exposition and the Operational
## Manual; ScenSyn's Workshop Catalyst Closure Audit and the SynAxes Closure Editor
## are both *consumers* of it, auditing different things at different scales — SynAxes
## orients committed closures across a corpus, the Workshop orients live claims inside
## one session — while having to read as one instrument.
##
## It was briefly held under `ScenSyn/session_types/workshop_catalyst/` with a comment
## asking the two surfaces to stay in lockstep by hand. That failed on its first test:
## a revision to the plain glosses landed in the ScenSyn copy while four other
## transcriptions of the same table — the SynAxes controller and three places in
## `synaxes_main.tscn` — kept the superseded wording, so the same quadrant was
## described two different ways depending on which panel you opened. The placement was
## also what made the duplication unavoidable, since an addon cannot depend on host
## ScenSyn code (ADR 0017). Moving the definition here removes the cause rather than
## the symptom. See ADR 0020 as amended.
##
## What belongs here is the *definition*: what a quadrant is, what it is called, what
## it means, and the shape written onto a node. What does not belong here is any
## surface's *use* of it — the Workshop's audit rules, its suggestion prompt and card
## presentation, and SynAxes' corpus coverage counting all stay with their owners.

## Stored with every tag so a later revision of the Closure Map can be told apart
## from this one rather than silently reinterpreting old sessions and old closures.
const MAP_VERSION: String = "closure-map-2026-08"

const QUADRANTS: Array[String] = ["A", "B", "C", "D"]

## Machine labels. Persisted in artifacts, so changing one is a migration.
const LABEL_BY_QUADRANT: Dictionary = {
	"A": "distal_past",
	"B": "distal_future",
	"C": "deep_past",
	"D": "deep_future",
}

## Canonical terms. These stay canonical because position on the map and the six
## tetrahedral edges are derivable from them, which is not true of the plain glosses.
const DISPLAY_BY_QUADRANT: Dictionary = {
	"A": "Distal Past",
	"B": "Distal Future",
	"C": "Deep Past",
	"D": "Deep Future",
}

## The plain glosses, from the Improved Exposition's "Terminology: Canonical Terms and
## Plain Glosses" table. Not this project's invention and not free text: they are
## defined upstream, so they are transcribed rather than paraphrased.
##
## The upstream rule is that a gloss never replaces a canonical term in the map itself,
## in a closure profile, or in any reference to a tetrahedral edge. Surfaces honour
## that by scoping the gloss to pickers and inbox rows — controls used repeatedly under
## time pressure, where "Distal Past" means nothing to someone who has not read the
## manual — while every reading that names a quadrant *as a coordinate* leads with the
## canonical term and brackets the gloss. `get_canonical_with_gloss` is that form.
##
## "Emergent", not "emerging": the Exposition notes that "emerging" reads outward at
## external trends and would pull D toward Distal Future, which is the precise
## confusion this vertex exists to prevent.
const PLAIN_BY_QUADRANT: Dictionary = {
	"A": "Inherited History",
	"B": "Projected Future",
	"C": "Embedded Culture",
	"D": "Emergent Potential",
}

## The "Temporal role" column. Distinguishes the two pairs: received and projected
## are the distal pair, operating and forming the deep pair.
const TEMPORAL_ROLE_BY_QUADRANT: Dictionary = {
	"A": "Past received",
	"B": "Future projected",
	"C": "Past still operating",
	"D": "Future forming",
}

## The "What it means" column, verbatim. Each states the quadrant's own coordinates,
## which is how a dropdown can convey a 2x2 it cannot draw: the first clause is the
## distal/deep axis, the second the past/future axis.
const AXIS_HINT_BY_QUADRANT: Dictionary = {
	"A": "Out there, already happened",
	"B": "Out there, might happen",
	"C": "In here, already at work",
	"D": "In here, already taking shape",
}

## The whole set in plain speech, from the same section. Useful where one line has to
## introduce all four at once.
const PLAIN_SET_SUMMARY: String = (
	"What we received, what we project, what we repeat, and what we are becoming."
)

## Operational Manual §2.3. Held here because a facilitator prompt, a card tooltip and
## an editor's help text must all describe a quadrant the same way.
##
## C and D carry the Exposition's two explicit warnings against narrow readings:
## Embedded Culture covers norms, incentives, power relations and institutional memory
## rather than stated values, and "past still operating" does not mean finished or
## sealed — deep closure is closure made available for further opening.
const CHARACTER_BY_QUADRANT: Dictionary = {
	"A": "Remote inheritance, public history, archive, canon, precedent — what happened out there.",
	"B": "Projection, speculation, forecast, horizon — what we imagine happening out there.",
	"C": "Norms, habits, incentives, power relations, institutional memory, structures operating beneath awareness — what that past has become within us. Read widely, not narrowly as stated values. Still operating does not mean sealed.",
	"D": "Latent potential, intention, tendency, formation already under way without being explicit — what is already forming within the present.",
}

## The four session prompts, verbatim in substance from Operational Manual §3.3.
const PROMPT_BY_QUADRANT: Dictionary = {
	"A": "What inherited facts, precedents, histories, constraints, or external conditions are shaping this situation?",
	"B": "What external future are we projecting, forecasting, fearing, or promising?",
	"C": "What assumptions, habits, memories, incentives, or incorporated patterns are already operating inside the situation?",
	"D": "What latent capability, unintended possibility, emerging tendency, or formation is already present without being explicit?",
}

## Tetrahedral edges (Exposition §14, Manual §6). Six transitions over four vertices,
## each naming a transformation rather than a location. Read as bidirectional: the
## operational sense given here is the forward reading.
const EDGE_TRANSFORMATIONS: Dictionary = {
	"A-B": "Convert precedent into an explicit projected scenario",
	"A-C": "Convert public history into incorporated understanding",
	"A-D": "Convert inherited resources into new capability",
	"B-C": "Test the projected future against habits, resistance, and capacity",
	"B-D": "Turn an open horizon into deliberate, resourced intention",
	"C-D": "Transform incorporated habit into emerging capability",
}


static func is_valid_quadrant(quadrant_id: String) -> bool:
	return quadrant_id.strip_edges().to_upper() in QUADRANTS


## Normalises loose input to a canonical quadrant, or "" for untagged. Callers
## treat "" as "clear the tag" rather than as an error.
static func normalize_quadrant(quadrant_id: String) -> String:
	var candidate: String = quadrant_id.strip_edges().to_upper()
	return candidate if candidate in QUADRANTS else ""


static func get_label(quadrant_id: String) -> String:
	return String(LABEL_BY_QUADRANT.get(normalize_quadrant(quadrant_id), ""))


static func get_display_name(quadrant_id: String) -> String:
	var quadrant: String = normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return "Untagged"
	return "%s %s" % [quadrant, String(DISPLAY_BY_QUADRANT.get(quadrant, ""))]


## The canonical term alone, without the letter `get_display_name()` prepends. For compact
## readings that name several quadrants at once — a coverage summary, a list of empty
## quadrants — where the letters are noise once the term is spelled out, and where four
## bracketed glosses would not fit. The gloss is not dropped, only moved: callers put the full
## `get_canonical_with_gloss()` mapping in the surrounding tooltip.
static func get_canonical_term(quadrant_id: String) -> String:
	var quadrant: String = normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return "Untagged"
	return String(DISPLAY_BY_QUADRANT.get(quadrant, ""))


## Several quadrants named in one compact reading, e.g. "Deep Past and Deep Future".
static func join_canonical_terms(quadrant_ids: Array, separator: String = ", ") -> String:
	var terms: Array[String] = []
	for quadrant_any: Variant in quadrant_ids:
		var term: String = get_canonical_term(String(quadrant_any))
		if not term.is_empty():
			terms.append(term)
	return separator.join(terms)


static func get_plain_name(quadrant_id: String) -> String:
	var quadrant: String = normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return "Untagged"
	return String(PLAIN_BY_QUADRANT.get(quadrant, ""))


## Canonical term with the gloss bracketed, which is the upstream convention for
## naming a quadrant in prose. Use this anywhere a quadrant is named as a coordinate:
## coverage readings, edge transitions, exports.
static func get_canonical_with_gloss(quadrant_id: String) -> String:
	var quadrant: String = normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return "Untagged"
	return "%s (%s)" % [get_display_name(quadrant), get_plain_name(quadrant)]


## One picker row: the letter, then the gloss to recognise it by, then the canonical
## term it stands for. Shared so a picker in one surface cannot come to read
## differently from a picker in another.
static func get_option_text(quadrant_id: String) -> String:
	var quadrant: String = normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return "Untagged"
	return "%s — %s (%s)" % [
		quadrant,
		get_plain_name(quadrant),
		String(DISPLAY_BY_QUADRANT.get(quadrant, "")),
	]


## The same picker row without the bracketed canonical term, for pickers that sit in a
## column's width rather than a dialog's. It drops nothing the room needs to identify the
## quadrant — the letter and the gloss both survive — and callers pair it with
## `get_option_text()` as the tooltip so the full reading stays one hover away.
##
## This lives here rather than being shortened at each call site for the reason on
## `get_option_text()`: a narrow surface that invented its own abbreviation is how two
## pickers start naming the same quadrant differently.
static func get_compact_option_text(quadrant_id: String) -> String:
	var quadrant: String = normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return "Untagged"
	return "%s — %s" % [quadrant, get_plain_name(quadrant)]


## Everything needed to choose this quadrant. Leads with the canonical term and
## brackets the gloss, then gives the temporal role and both axis coordinates, then
## the characterisation.
static func get_quadrant_help(quadrant_id: String) -> String:
	var quadrant: String = normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return ""
	return "%s\n%s \u00b7 %s\n%s" % [
		get_canonical_with_gloss(quadrant),
		String(TEMPORAL_ROLE_BY_QUADRANT.get(quadrant, "")),
		String(AXIS_HINT_BY_QUADRANT.get(quadrant, "")),
		String(CHARACTER_BY_QUADRANT.get(quadrant, "")),
	]


## The four quadrants on one line, for a legend or a tooltip that has to introduce the
## whole map at once.
static func get_axes_legend() -> String:
	var parts: Array[String] = []
	for quadrant_id: String in QUADRANTS:
		parts.append("%s %s (%s)" % [
			quadrant_id,
			String(DISPLAY_BY_QUADRANT[quadrant_id]),
			get_plain_name(quadrant_id),
		])
	return "; ".join(parts)


## The annotation written onto a graph node's `annotations.orientation`, and the same
## shape SynAxes stores as a closure's `orientation`. Kept beside
## `graph_workspace_document.gd`, which owns the document this goes into.
static func build_annotation(quadrant_id: String) -> Dictionary:
	var quadrant: String = normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return {}
	return {
		"quadrant": quadrant,
		"label": get_label(quadrant),
		"map_version": MAP_VERSION,
	}


## Marks that a room did not converge on where a claim sits. Deliberately a *sibling*
## of `orientation` rather than a field inside it: the orientation dictionary is the
## persisted `ui.closure` schema v2 shape, and contestedness is a fact about the
## deliberation that produced a tag, not a coordinate on the map. Keeping it outside
## means marking a claim contested cannot change how any stored closure reads.
##
## It applies with or without a quadrant. A room that argued and settled on C, and a
## room that could not agree at all, are both contested; the second is simply contested
## and untagged.
const CONTESTED_ANNOTATION_KEY: String = "orientation_contested"


## The contestation register (REQ-CA-010). Two dimensions, one shape, because the four
## elements the requirement asks for — who holds each view, the supporting evidence,
## which decision would differ, what test discriminates — describe either kind of
## disagreement without modification:
##
##   placement — the room agrees the claim holds but splits on which quadrant it is in.
##   substance — the room agrees where it sits but splits on whether it holds.
##
## Neither subsumes the other. A room can be unanimous that a claim is true and split on
## whether it is inherited or embedded, or agree on placement and split on the evidence.
##
## `positions` doubles as the source labelling REQ-CA-011 needs: a position is a named
## participant's view, so a placement register *is* the set of participant orientation
## views, and divergence across them is what makes a claim contested without anyone
## having to assert it.
##
## `view` is read against the dimension: a quadrant id for placement, free text for
## substance. `decision_at_stake` and `discriminating_test` sit at dimension level rather
## than per position, because they describe what hangs on the disagreement and what would
## settle it — properties of the split, not of one side of it.
const CONTESTATION_ANNOTATION_KEY: String = "contestation"
const DIMENSION_PLACEMENT: String = "placement"
const DIMENSION_SUBSTANCE: String = "substance"
const DIMENSIONS: Array[String] = [DIMENSION_PLACEMENT, DIMENSION_SUBSTANCE]


static func is_valid_dimension(dimension: String) -> bool:
	return dimension.strip_edges().to_lower() in DIMENSIONS


static func get_contestation(node_data: Dictionary) -> Dictionary:
	var annotations_any: Variant = node_data.get("annotations", {})
	if typeof(annotations_any) != TYPE_DICTIONARY:
		return {}
	var register_any: Variant = (annotations_any as Dictionary).get(
		CONTESTATION_ANNOTATION_KEY, {}
	)
	return register_any if typeof(register_any) == TYPE_DICTIONARY else {}


static func get_contestation_dimension(node_data: Dictionary, dimension: String) -> Dictionary:
	var dimension_any: Variant = get_contestation(node_data).get(
		dimension.strip_edges().to_lower(), {}
	)
	return dimension_any if typeof(dimension_any) == TYPE_DICTIONARY else {}


## Named views on one dimension. Order is preserved as recorded: a register is read by
## people, and reordering positions between sessions would make it look edited.
static func get_positions(node_data: Dictionary, dimension: String) -> Array:
	var positions_any: Variant = get_contestation_dimension(node_data, dimension).get(
		"positions", []
	)
	if typeof(positions_any) != TYPE_ARRAY:
		return []
	var positions: Array = []
	for position_any: Variant in (positions_any as Array):
		if typeof(position_any) == TYPE_DICTIONARY:
			positions.append(position_any)
	return positions


## The distinct views held, which is what decides contestedness. Two people who
## independently say C are agreement, not a split, so the count that matters is of
## views rather than of positions.
static func get_distinct_views(node_data: Dictionary, dimension: String) -> Array[String]:
	var distinct_views: Array[String] = []
	for position_any: Variant in get_positions(node_data, dimension):
		var view_text: String = String((position_any as Dictionary).get("view", "")).strip_edges()
		if not view_text.is_empty() and view_text not in distinct_views:
			distinct_views.append(view_text)
	return distinct_views


static func is_dimension_contested(node_data: Dictionary, dimension: String) -> bool:
	return get_distinct_views(node_data, dimension).size() > 1


## Set by the facilitator when the room split out loud and no views were entered. Kept
## separate from the derived reading so the two can be reported apart: an asserted mark
## is a facilitator's judgement, a derived one is evidence.
static func has_asserted_contested(node_data: Dictionary) -> bool:
	var annotations_any: Variant = node_data.get("annotations", {})
	if typeof(annotations_any) != TYPE_DICTIONARY:
		return false
	return bool((annotations_any as Dictionary).get(CONTESTED_ANNOTATION_KEY, false))


## Contested by assertion or by divergent views. Callers that only need to know whether a
## claim's placement is disputed should use this and stay indifferent to which route
## established it.
static func is_orientation_contested(node_data: Dictionary) -> bool:
	if has_asserted_contested(node_data):
		return true
	return is_dimension_contested(node_data, DIMENSION_PLACEMENT)


## A register carries its full weight only once it says what hangs on the disagreement
## and what would settle it. Two positions with no discriminating test records that people
## disagree while leaving the disagreement exactly as unresolvable as before.
static func is_register_complete(node_data: Dictionary, dimension: String) -> bool:
	if not is_dimension_contested(node_data, dimension):
		return true
	var dimension_data: Dictionary = get_contestation_dimension(node_data, dimension)
	if String(dimension_data.get("discriminating_test", "")).strip_edges().is_empty():
		return false
	if String(dimension_data.get("decision_at_stake", "")).strip_edges().is_empty():
		return false
	for position_any: Variant in get_positions(node_data, dimension):
		var position: Dictionary = position_any
		if String(position.get("held_by", "")).strip_edges().is_empty():
			return false
		if String(position.get("evidence", "")).strip_edges().is_empty():
			return false
	return true


## Reads a node's quadrant, or "" when untagged. Tolerates a missing or malformed
## annotation rather than raising: an untagged node is normal.
static func get_node_quadrant(node_data: Dictionary) -> String:
	var annotations_any: Variant = node_data.get("annotations", {})
	if typeof(annotations_any) != TYPE_DICTIONARY:
		return ""
	var orientation_any: Variant = (annotations_any as Dictionary).get("orientation", {})
	if typeof(orientation_any) != TYPE_DICTIONARY:
		return ""
	return normalize_quadrant(String((orientation_any as Dictionary).get("quadrant", "")))


## Canonical edge key for an unordered vertex pair, e.g. ("C", "B") -> "B-C".
## Empty when either end is invalid or both name the same vertex.
static func get_edge_key(from_quadrant: String, to_quadrant: String) -> String:
	var from_id: String = normalize_quadrant(from_quadrant)
	var to_id: String = normalize_quadrant(to_quadrant)
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return ""
	var pair: Array[String] = [from_id, to_id]
	pair.sort()
	return "%s-%s" % [pair[0], pair[1]]


static func get_edge_transformation(from_quadrant: String, to_quadrant: String) -> String:
	return String(EDGE_TRANSFORMATIONS.get(get_edge_key(from_quadrant, to_quadrant), ""))
