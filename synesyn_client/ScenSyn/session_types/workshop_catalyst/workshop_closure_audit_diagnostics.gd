extends RefCounted
class_name WorkshopClosureAuditDiagnostics

## The manual's three diagnostics, as pure judgement-free machinery (REQ-CA-005 to 007).
##
## `workshop_closure_audit_rules.gd` reads the map's *geometry* — which quadrants are full,
## empty, dominant, single-sourced. This module holds the *classifications the room applies
## to that geometry*, which is a different job: geometry is computed, classification is
## chosen. Nothing here infers a classification from a document, and that is deliberate.
## The manual's central claim is that geometry must not be diagnosed before how the geometry
## was produced is understood, so an empty quadrant means nothing until a human says whether
## it is empty because the topic is irrelevant, because the room excluded it, because nobody
## knows, because something is being suppressed, or because it has not formed yet. A module
## that guessed would be committing precisely the error the instrument exists to catch.
##
## What it does supply: the vocabularies, the triage matrix, the four-condition debt gate,
## and the wording. Deterministic and explainable, like the rules module.

const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)

## REQ-CA-005. Why a quadrant is empty or weak. The order runs from benign to alarming,
## which is the order a facilitator should consider them in — and the last three are the
## reason the classification is mandatory rather than optional, since "unknown",
## "suppressed", and "not yet formed" are three completely different problems that an
## unclassified blank space hides equally well.
const ABSENCE_CLASSIFICATIONS: Array[String] = [
	"not_applicable",
	"deliberately_excluded",
	"unknown",
	"suppressed",
	"not_yet_formed",
]

const ABSENCE_LABELS: Dictionary = {
	"not_applicable": "Not applicable",
	"deliberately_excluded": "Deliberately excluded",
	"unknown": "Unknown",
	"suppressed": "Suppressed",
	"not_yet_formed": "Not yet formed",
}

const ABSENCE_HELP: Dictionary = {
	"not_applicable":
		"It has nothing to do with this decision. This is the easiest answer to pick, so"
		+ " make sure you can say why it does not apply.",
	"deliberately_excluded":
		"You looked at it and chose to leave it out. Write that down, or someone reading this"
		+ " later will think you missed it.",
	"unknown":
		"Nobody here knows. If the decision turns out to rest on it, this becomes debt.",
	"suppressed":
		"Something is keeping it off the table: politics, discomfort, or a person. Groups"
		+ " rarely pick this one about themselves.",
	"not_yet_formed":
		"It has not happened yet, so there is nothing to find. Different from Unknown, where"
		+ " there is something to find and nobody has looked.",
}

## REQ-CA-006. Consequence-if-omitted against confidence-it-is-irrelevant. Three bands
## rather than a continuous scale, because a facilitator asked to place something on a
## ten-point scale mid-session will pick the middle.
const TRIAGE_BANDS: Array[String] = ["low", "medium", "high"]

const TRIAGE_ACCEPT: String = "accept"
const TRIAGE_CHEAP_CHECK: String = "cheap_check"
const TRIAGE_MONITOR: String = "monitor"
const TRIAGE_REOPEN: String = "reopen"

const TRIAGE_LABELS: Dictionary = {
	TRIAGE_ACCEPT: "Accept the omission",
	TRIAGE_CHEAP_CHECK: "Run a cheap check",
	TRIAGE_MONITOR: "Monitor it",
	TRIAGE_REOPEN: "Reopen the decision",
}

## REQ-CA-007's third diagnostic. What a concentration *means*, which the geometry cannot
## say: the same lopsided map is either a room sensibly focused on what matters or a room
## that has stopped looking, and only the people in it can tell which.
const CONCENTRATION_CLASSIFICATIONS: Array[String] = [
	"legitimate_focus",
	"expertise_bias",
	"fixation",
	"suppression",
	"premature_closure",
]

const CONCENTRATION_LABELS: Dictionary = {
	"legitimate_focus": "Legitimate focus",
	"expertise_bias": "Expertise bias",
	"fixation": "Fixation",
	"suppression": "Suppression",
	"premature_closure": "Premature closure",
}

const CONCENTRATION_HELP: Dictionary = {
	"legitimate_focus":
		"The decision really does rest on this. Rule out the other four before you pick it.",
	"expertise_bias":
		"This is what the group knows about, so this is what it produced. Check whether one"
		+ " person supplied most of it.",
	"fixation":
		"The group keeps coming back to this out of worry, not because the decision needs it.",
	"suppression":
		"Talking about this is what keeps something else off the table.",
	"premature_closure":
		"The group made its mind up early and has been adding detail ever since instead of"
		+ " testing it.",
}

## REQ-CA-007. The four conditions, all of which must hold. Named as questions because that
## is how a facilitator has to put them to a room.
const DEBT_CONDITIONS: Array[String] = [
	"is_material",
	"is_unjustified",
	"is_outcome_changing",
	"is_unsafeguarded",
]

const DEBT_CONDITION_PROMPTS: Dictionary = {
	"is_material": "Does this absence bear on the decision at all?",
	"is_unjustified": "Is it unexplained, with no agreed reason for leaving it out?",
	"is_outcome_changing": "Would the decision differ if it were filled?",
	"is_unsafeguarded": "Is there nothing in place that would catch it if it mattered?",
}


static func is_valid_absence_classification(classification_id: String) -> bool:
	return classification_id.strip_edges().to_lower() in ABSENCE_CLASSIFICATIONS


static func is_valid_concentration_classification(classification_id: String) -> bool:
	return classification_id.strip_edges().to_lower() in CONCENTRATION_CLASSIFICATIONS


static func is_valid_band(band_id: String) -> bool:
	return band_id.strip_edges().to_lower() in TRIAGE_BANDS


## REQ-CA-006's matrix. Consequence is what happens if the absence turns out to matter;
## confidence is how sure the room is that it does *not*. High consequence with low
## confidence is the reopen corner, and low consequence with high confidence is the accept
## corner. The two middles are deliberately different: something cheap to check should be
## checked now rather than watched indefinitely, so a cheap check outranks monitoring
## wherever the room is unsure but the cost of finding out is small.
##
## Returns "" for an invalid band rather than guessing, so a caller's mistake cannot read
## as a verdict the room reached.
static func triage_verdict(consequence_band: String, confidence_band: String) -> String:
	if not is_valid_band(consequence_band) or not is_valid_band(confidence_band):
		return ""
	var consequence: String = consequence_band.strip_edges().to_lower()
	var confidence: String = confidence_band.strip_edges().to_lower()
	if consequence == "high":
		# Nothing about being confident it is irrelevant makes a high-consequence omission
		# safe, so confidence only decides how hard the room has to look, never whether.
		if confidence == "high":
			return TRIAGE_CHEAP_CHECK
		return TRIAGE_REOPEN
	if consequence == "medium":
		if confidence == "low":
			return TRIAGE_REOPEN
		if confidence == "medium":
			return TRIAGE_CHEAP_CHECK
		return TRIAGE_MONITOR
	if confidence == "low":
		return TRIAGE_CHEAP_CHECK
	if confidence == "medium":
		return TRIAGE_MONITOR
	return TRIAGE_ACCEPT


## True only when all four conditions hold (REQ-CA-007). Gating rather than scoring: the
## manual's point is that most absences are not debt, and a register that filled up with
## every gap would be ignored within one session.
static func qualifies_as_debt(conditions: Dictionary) -> bool:
	for condition_id: String in DEBT_CONDITIONS:
		if not bool(conditions.get(condition_id, false)):
			return false
	return true


## Names the conditions that failed, so a facilitator can see why something was not
## recorded as debt instead of wondering whether the tool ignored them.
static func describe_debt_shortfall(conditions: Dictionary) -> Array[String]:
	var unmet: Array[String] = []
	for condition_id: String in DEBT_CONDITIONS:
		if not bool(conditions.get(condition_id, false)):
			unmet.append(String(DEBT_CONDITION_PROMPTS.get(condition_id, condition_id)))
	return unmet


## REQ-CA-009. `dominant → neglected (edge XY) by <action>`.
##
## The displayed edge is the two quadrant letters, which is the manual's notation, not
## `ClosureOrientation.get_edge_key()` — that returns `A-C`, an internal lookup id for the
## `EDGE_TRANSFORMATIONS` table and not something to show a room. The *meaning* of the edge
## still comes from the shared vocabulary, via `describe_transition_edge`, so the audit names
## the transformation the Closure Map defines rather than inventing a second description of
## it.
static func format_required_transition(
	from_quadrant: String,
	to_quadrant: String,
	action_text: String
) -> String:
	var normalized_from: String = ClosureOrientationScript.normalize_quadrant(from_quadrant)
	var normalized_to: String = ClosureOrientationScript.normalize_quadrant(to_quadrant)
	if normalized_from.is_empty() or normalized_to.is_empty():
		return ""
	if normalized_from == normalized_to:
		return ""
	var clean_action: String = action_text.strip_edges()
	if clean_action.is_empty():
		return ""
	return "%s → %s (edge %s%s) by %s" % [
		normalized_from,
		normalized_to,
		normalized_from,
		normalized_to,
		clean_action,
	]


## The transformation the edge stands for, for the facilitator choosing an action to
## satisfy it.
static func describe_transition_edge(from_quadrant: String, to_quadrant: String) -> String:
	return ClosureOrientationScript.get_edge_transformation(from_quadrant, to_quadrant)
