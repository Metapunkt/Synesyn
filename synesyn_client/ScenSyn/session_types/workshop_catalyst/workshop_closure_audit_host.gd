extends RefCounted
class_name WorkshopClosureAuditHost

## Sites the closure audit inside the Thinking Map and connects it to the Session Record.
##
## Exists to keep this wiring out of `workshop_thinking_map_controller.gd`, which is well
## past its soft line limit and already carries five responsibilities. The map controller
## needs four lines to use this: construct, mount, forward findings on refresh, and forward
## the saved state.
##
## The audit belongs in the map panel rather than beside it because it audits *this* map: its
## thin quadrants, its concentration, its contested claims all come from the same findings
## the map's own coverage line reads, and a surface mounted elsewhere would need those
## findings pushed to it and could fall out of step.

signal state_changed(audit_state: Dictionary)
## Reaches the map's toggle, which is what actually owns whether the audit is open.
signal hide_requested()
## Carries a request for model-drafted answers outward. Nothing here has model access, the same
## way nothing in the map controller does: the session controller owns the conversation manager
## and hands the result back through `apply_suggestions` (REQ-CA-021).
signal suggestions_requested(request: Dictionary)

const AuditControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_controller.gd"
)
const RouterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_router.gd"
)
const AuditPanelScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_panel.tscn"
)
const SuggesterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_suggester.gd"
)

var _host_node: Control = null
var _audit_controller: RefCounted = null
var _record_store: RefCounted = null
var _findings: Dictionary = {}


func mount(
	map_panel_node: Control,
	record_store: RefCounted,
	saved_state: Dictionary = {}
) -> bool:
	if not map_panel_node:
		return false
	_host_node = map_panel_node.get_node_or_null("%ClosureAuditHost") as Control
	if not _host_node:
		return false
	_record_store = record_store
	var panel_node: Control = AuditPanelScene.instantiate() as Control
	# A ScrollContainer sizes an unflagged child to its minimum width, which leaves the audit
	# narrower than the space it has and squeezes its rows. The panel has to be told to fill.
	panel_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_node.add_child(panel_node)
	_audit_controller = AuditControllerScript.new()
	if not _audit_controller.mount(panel_node, saved_state):
		return false
	_audit_controller.state_changed.connect(
		func(audit_state: Dictionary) -> void: state_changed.emit(audit_state)
	)
	_audit_controller.route_requested.connect(_on_route_requested)
	_audit_controller.hide_requested.connect(func() -> void: hide_requested.emit())
	_audit_controller.suggestions_requested.connect(_on_suggestions_requested)
	return true


## The audit's own findings and decision travel with the request, so whoever runs the model does
## not have to reach back into the panel for them.
func _on_suggestions_requested() -> void:
	if not _audit_controller:
		return
	_audit_controller.set_suggest_status("Drafting answers from the map…", true)
	suggestions_requested.emit({
		"findings": _findings.duplicate(true),
		"thin_quadrants": _audit_controller.get_thin_quadrants(),
		"decision": _audit_controller.get_record().get_decision_under_audit(),
	})


## Drafts arrive here and stop. `set_suggestions` puts them beside the steps they answer; only a
## press moves one onto the record.
func apply_suggestions(result: Dictionary) -> void:
	if not _audit_controller:
		return
	_audit_controller.set_suggest_status(SuggesterScript.format_summary(result), false)
	if bool(result.get("ok", false)):
		_audit_controller.set_suggestions(result.get("suggestions", {}))


## Shown only while the audit is open. The audit's questions are about a map the room is
## actively reading; left visible outside the audit it would invite classifications made
## against a map nobody was looking at.
func set_audit_active(is_active: bool) -> void:
	if _host_node:
		_host_node.visible = is_active
	if not is_active and _audit_controller:
		# Undecided drafts expire with the audit, as orientation suggestions do. A draft accepted
		# in a later stage would be an answer about a map that had moved on since.
		_audit_controller.clear_suggestions()
		_audit_controller.set_suggest_status("", false)


func refresh(findings: Dictionary) -> void:
	_findings = findings
	if _audit_controller:
		_audit_controller.refresh(findings)


func get_state() -> Dictionary:
	return _audit_controller.get_state() if _audit_controller else {}


func _on_route_requested() -> void:
	if not _audit_controller:
		return
	if not _record_store:
		_audit_controller.set_route_status(
			"The Session Record is not available, so nothing was proposed."
		)
		return
	var result: Dictionary = RouterScript.route_audit(
		_record_store, _audit_controller.get_record(), _findings
	)
	if not bool(result.get("ok", false)):
		_audit_controller.set_route_status(
			"Could not propose: %s" % String(result.get("error", "unknown_error"))
		)
		return
	var proposed_count: int = (result.get("proposed", []) as Array).size()
	if proposed_count == 0:
		_audit_controller.set_route_status(
			"Nothing new to propose. Everything from this audit has already been sent for"
			+ " review."
		)
	else:
		_audit_controller.set_route_status(
			"%d entr%s proposed. Review them in the Session Record. Nothing is committed"
			% [proposed_count, "y" if proposed_count == 1 else "ies"]
			+ " until you accept it."
		)
	# The proposals live in the store, so its owner has to persist and repaint. Emitting the
	# audit's own state is what carries the routed refs that stop a second pass duplicating.
	state_changed.emit(_audit_controller.get_state())
