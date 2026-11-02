extends Node
class_name ClosureBus

## ClosureBus
##
## Cross-cutting event bus for closure formation. Session-type records (currently
## WorkshopCatalystSessionRecord; future session types that adopt vote-based or
## other explicit-closure mechanisms) emit to this bus when a closure is captured
## or discarded. Listeners include the substrate emitter (which persists captures
## as ui.workshop_closure artifacts to the Hub when available) and any future
## consumers — analytics, SynPunkt staging cues, ReadyMade carry-forward, etc.
##
## Captures are NOT stored as `ui.closure`; that type is a SynAxes slice with a
## different payload. See ADR 0026.
##
## The bus is session-type-agnostic. Payload entries carry session_type_id and
## scenario_id so downstream consumers can filter or interpret them.
##
## Wired in by Global._ready() as a child node, accessible via `Global.closure_bus`.
##
## Payload schema (for both signals):
## {
##   "schema_version":  "1.0",           # signal version; the stored artifact
##                                       # carries its own integer version
##   "session_type_id": String,            # e.g. "workshop_catalyst"
##   "scenario_id":     String,            # internal scenario name (filename stem)
##   "scenario_name":   String,            # human-readable scenario name
##   "kind":            String,            # session-type-defined: "decision" | "risk" | "open_question" | ...
##   "statement":       String,            # the closure text as captured
##   "owner":           String,            # role/owner if applicable
##   "confidence":      String,            # "High" | "Medium" | "Low" | ""
##   "voters_yes":      Array[String],
##   "voters_no":       Array[String],
##   "outcome":         String,            # "yes" | "no"
##   "reason":          String,            # "Yes" | "No" | "Plurality (Yes)" | ...
##   "trigger":         String,            # what initiated this closure round
##   "stage_name":      String,            # current workshop stage / scene name
##   "stage_turn":      int,               # turns into current stage
##   "session_turn":    int,               # turns into the whole session (or -1 if unknown)
##   "captured_at_unix": float,
##   "source_log_index_open":  int,        # log index when proposal was opened (or -1)
##   "source_log_index_close": int,        # log index at moment of capture
## }

signal closure_captured(payload: Dictionary)
signal closure_discarded(payload: Dictionary)

const SCHEMA_VERSION: String = "1.0"

var _emitter: Node = null

func _ready() -> void:
	# Compose the substrate emitter. It listens to our own signals and posts to
	# the Hub when available; if not, it silently no-ops. We do this in _ready
	# rather than _init so the autoload Global has finished its own setup and
	# RuntimeConfig / ProviderModePolicy classes are available.
	var emitter_script: GDScript = preload("res://ScenSyn/scripts/closure/closure_substrate_emitter.gd")
	if emitter_script:
		_emitter = emitter_script.new()
		add_child(_emitter)
		if _emitter.has_method("attach_to_bus"):
			_emitter.attach_to_bus(self)

## Convenience: emit a captured closure event with sensible default fields filled in.
##
## Session-type records build the payload they care about and pass it here; this
## helper stamps schema_version and captured_at_unix if missing so all
## listeners see a uniformly-shaped event.
func emit_captured(payload: Dictionary) -> void:
	var p: Dictionary = payload.duplicate(true)
	if not p.has("schema_version") or String(p.get("schema_version", "")).is_empty():
		p["schema_version"] = SCHEMA_VERSION
	if not p.has("captured_at_unix") or float(p.get("captured_at_unix", 0.0)) <= 0.0:
		p["captured_at_unix"] = Time.get_unix_time_from_system()
	emit_signal("closure_captured", p)

## Mirror of emit_captured for the discard path.
func emit_discarded(payload: Dictionary) -> void:
	var p: Dictionary = payload.duplicate(true)
	if not p.has("schema_version") or String(p.get("schema_version", "")).is_empty():
		p["schema_version"] = SCHEMA_VERSION
	if not p.has("captured_at_unix") or float(p.get("captured_at_unix", 0.0)) <= 0.0:
		p["captured_at_unix"] = Time.get_unix_time_from_system()
	emit_signal("closure_discarded", p)
