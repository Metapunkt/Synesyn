extends RefCounted
class_name CaptureCooldown

## CaptureCooldown
##
## Small stateful helper for the post-capture "riff window" used in vote-based
## closure formation. After any capture (yes or no), themes typically want a
## few turns of breathing room during which autonomous closure detectors
## (convergence checks, gap flags, closure-phrase detectors) are suppressed —
## otherwise the immediate post-vote rationale gets read as a new convergence
## point and the system loops on itself.
##
## Owned by the theme record (one per session). Theme-generic; the duration is
## configurable per call so each theme can tune its own riff length.

const DEFAULT_DURATION_TURNS: int = 4

var _expires_at_turn: int = -999

## Starts (or re-starts) the cooldown for `duration_turns` turns from
## `current_turn`. The cooldown is "active" for turns strictly less than
## current_turn + duration_turns.
func start(current_turn: int, duration_turns: int = DEFAULT_DURATION_TURNS) -> void:
	if duration_turns < 0:
		duration_turns = 0
	_expires_at_turn = current_turn + duration_turns

## Returns true while the cooldown is in effect at the supplied turn count.
func is_active(current_turn: int) -> bool:
	return current_turn < _expires_at_turn

## Returns the absolute turn at which the cooldown ends (or -999 if never started).
func expires_at() -> int:
	return _expires_at_turn

## Clears the cooldown so subsequent is_active() calls return false until
## start() is called again.
func clear() -> void:
	_expires_at_turn = -999
