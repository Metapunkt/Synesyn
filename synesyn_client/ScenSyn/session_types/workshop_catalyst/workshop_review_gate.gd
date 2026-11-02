extends RefCounted
class_name WorkshopReviewGate

## Purpose: decide whether the Review workspace is usable yet, and say why when it
## is not.
##
## Review is a terminal surface rather than an exploratory one. Compare Paths builds
## its cards only from Session Record entries in `decisions` — see
## `workshop_path_proposal_engine.gd::candidates_from_reviewed_record`, where
## `risks` and `next_steps` only fill fields of a decision-derived path and can
## never create one. So a facilitator who opens Review early gets the seeded
## do-nothing card, a row of buttons, and no route forward, and the one button that
## would populate the surface answers by doing nothing and saying nothing.
##
## Stating the precondition is cheaper than teaching the dependency. This module
## holds the rule and its wording in one place so the gated button and the empty
## import cannot explain the same condition two different ways.

## The only Session Record category that can produce a path.
const REQUIRED_CATEGORY: String = "decisions"


## Counts reviewed decisions that would actually yield a path. Mirrors the proposal
## engine's own skip rule: an item present but blank produces nothing, so it must
## not be counted as satisfying the precondition.
static func decision_count(reviewed_record: Dictionary) -> int:
	var items_any: Variant = reviewed_record.get(REQUIRED_CATEGORY, [])
	if typeof(items_any) != TYPE_ARRAY:
		return 0
	var usable_count: int = 0
	for item_any: Variant in (items_any as Array):
		if typeof(item_any) != TYPE_DICTIONARY:
			continue
		var item_text: String = str((item_any as Dictionary).get("text", "")).strip_edges()
		if not item_text.is_empty():
			usable_count += 1
	return usable_count


static func is_available(reviewed_record: Dictionary) -> bool:
	return decision_count(reviewed_record) > 0


## Names the missing precondition and the one action that clears it.
static func unavailable_tooltip() -> String:
	return (
		"Review weighs one decision path against another, so it needs a decision"
		+ " first.\nCapture one with /decide, or use Add under Decisions in the"
		+ " Session Record, and this opens."
	)


## Deliberately does not repeat the old tooltip's "decisions, risks, and options":
## risks and open questions cannot become paths, and promising that they can is
## what sends facilitators looking for a feature that is not there.
static func available_tooltip() -> String:
	return (
		"Weigh one decision path against another, including doing nothing."
		+ " Moves the Session Record into the centre beside Compare Paths."
	)


## Shown inside Compare Paths when an import yields nothing, so that a no-op is
## never silent. The two cases need different answers: one is a missing
## precondition, the other means the work is already done.
static func empty_import_status(reviewed_record: Dictionary) -> String:
	if decision_count(reviewed_record) > 0:
		return (
			"No new paths proposed — every reviewed decision already has one."
			+ " Add a decision to the Session Record to propose another."
		)
	return (
		"No paths proposed: the Session Record holds no reviewed decision yet."
		+ " Capture one with /decide, then propose again. Risks and open questions"
		+ " do not become paths on their own."
	)
