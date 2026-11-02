extends RefCounted
class_name VoteTally

## VoteTally
##
## Pure-logic helpers for closure-formation voting. Theme-generic and stateless:
## the caller owns the votes_yes / votes_no arrays (they typically live inside the
## theme's pending_vote dictionary in StoryState). VoteTally encodes the
## resolution rules — simple majority, tie-broken-by-yes — so each theme that
## adopts vote-based closure does not reinvent them.
##
## Theme records (e.g. WorkshopCatalystSessionRecord) call these as static
## helpers; nothing here knows what a "decision" or "risk" or "Workshop chair"
## is — those remain theme concerns.

## Resolution outcome constants emitted from resolve().
const OUTCOME_YES: String = "yes"
const OUTCOME_NO: String = "no"
const OUTCOME_PENDING: String = "pending"

## Records or changes a vote in-place on the supplied votes_yes / votes_no arrays.
##
## Idempotent: a voter cannot double-vote, and switching from yes to no (or vice
## versa) is supported and produces the expected single-vote result. Returns
## true if anything changed (so callers can short-circuit a state write when a
## stale duplicate vote arrives).
static func record(votes_yes: Array, votes_no: Array, voter: String, choice: String) -> bool:
	var v: String = voter.strip_edges()
	if v.is_empty():
		return false
	var c: String = choice.strip_edges().to_lower()
	if c != "yes" and c != "no":
		return false
	var prev_yes: bool = v in votes_yes
	var prev_no: bool = v in votes_no
	if (c == "yes" and prev_yes and not prev_no) or (c == "no" and prev_no and not prev_yes):
		return false
	if prev_yes:
		votes_yes.erase(v)
	if prev_no:
		votes_no.erase(v)
	if c == "yes":
		votes_yes.append(v)
	else:
		votes_no.append(v)
	return true

## Threshold for a simple majority given a known cast size.
## Returns 1 when cast_size <= 0 (degenerate single-voter case).
static func threshold(cast_size: int) -> int:
	if cast_size <= 0:
		return 1
	# +0.001 protects against ceil(2.0/2.0)==2 vs 3.0/2.0==1.5->2 ambiguity.
	return int(ceil(float(cast_size) / 2.0 + 0.001))

## Resolves the current tally and returns one of:
##   { "outcome": "yes",     "reason": "Yes" }
##   { "outcome": "yes",     "reason": "Plurality (Yes)" }     # all-voted, tie or yes-plurality
##   { "outcome": "no",      "reason": "No" }
##   { "outcome": "no",      "reason": "Plurality (No)" }      # all-voted, no-plurality
##   { "outcome": "pending", "reason": "" }                    # not enough votes yet
##
## Tie-break rule: when every participant has voted and there is no majority,
## Yes wins on a tie (this is the conservative pro-closure default already used
## by Workshop Catalyst).
static func resolve(votes_yes: Array, votes_no: Array, cast_size: int) -> Dictionary:
	var t: int = threshold(cast_size)
	var n_yes: int = votes_yes.size()
	var n_no: int = votes_no.size()
	if n_yes >= t:
		return {"outcome": OUTCOME_YES, "reason": "Yes"}
	if n_no >= t:
		return {"outcome": OUTCOME_NO, "reason": "No"}
	if (n_yes + n_no) >= cast_size and cast_size > 0:
		if n_yes >= n_no:
			return {"outcome": OUTCOME_YES, "reason": "Plurality (Yes)"}
		return {"outcome": OUTCOME_NO, "reason": "Plurality (No)"}
	return {"outcome": OUTCOME_PENDING, "reason": ""}
