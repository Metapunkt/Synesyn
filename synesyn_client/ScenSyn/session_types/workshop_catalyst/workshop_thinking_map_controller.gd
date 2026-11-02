extends RefCounted
class_name WorkshopThinkingMapController

signal state_changed(map_state: Dictionary)
signal specialist_context_changed(context_payload: Dictionary, trace: Dictionary)
signal closure_route_requested(outcome: Dictionary)
## Carries the claims to orient. Answered by `apply_orientation_suggestions`.
signal orientation_suggestions_requested(claims: Array)
## Asks for model-drafted answers to the Closure Audit's steps (REQ-CA-021). Like the
## orientation pass, this controller has no model access and only relays.
signal audit_suggestions_requested(request: Dictionary)

const AdapterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/thinking_map_adapter.gd"
)
const PersistenceScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/thinking_map_persistence_coordinator.gd"
)
const CardScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map_card.tscn"
)
const GraphProjectionScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map_graph_projection.gd"
)
const ConversationLayoutStabilizerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_conversation_layout_stabilizer.gd"
)
const SymbolicRulesScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map_symbolic_rules.gd"
)
const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)
const ClosureAuditRulesScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_rules.gd"
)
const OrientationSuggesterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_orientation_suggester.gd"
)
const OrientationPresenterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_orientation_presenter.gd"
)
const ViewsReviewPresenterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_views_review_presenter.gd"
)
const AuditHostScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_host.gd"
)
const MapLayoutUtilsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_map_layout_utils.gd"
)
const MapPanelTogglesScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_map_panel_toggles.gd"
)
const AutoloadsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_autoloads.gd"
)

var _panel_node: Control = null
var _adapter: RefCounted = null
var _persistence: Node = null
var _record_store: RefCounted = null
var _graph_projection: RefCounted = null
var _facilitator_ref: String = "Facilitator"
var _preview_hash: String = ""
var _preview_payload: Dictionary = {}
var _last_ingested_log_index: int = -1
var _map_column_mode_connected: bool = false
var _last_symbolic_insights: Dictionary = {}
## Orientation is solicited only during an audit, so the per-card pickers and the
## coverage reading stay out of ordinary Talk / Map / Review facilitation.
var _is_closure_audit_active: bool = false
var _last_closure_findings: Dictionary = {}
var _audit_host: RefCounted = null
## Held here only so it can ride along in the persisted map state; the host owns the truth.
var _audit_state: Dictionary = {}
## Model proposals awaiting a human decision, by record id. Transient by design.
var _orientation_suggestions: Dictionary = {}
## Claims the model said no quadrant fits. Kept apart from the suggestions so
## "none applies" cannot be read as a tag.
var _declined_orientation_ids: Array = []
var _is_awaiting_orientation_suggestions: bool = false


func mount(
	panel_node: Control,
	hub_client: Object,
	record_store: RefCounted,
	session_id: String,
	scenario_id: String,
	saved_state: Dictionary = {}
) -> bool:
	_panel_node = panel_node
	_record_store = record_store
	if not is_instance_valid(_panel_node):
		return false
	_adapter = AdapterScript.new()
	_adapter.initialize(session_id, scenario_id, "decision_triage", saved_state)
	_persistence = PersistenceScript.new()
	_persistence.name = "ThinkingMapPersistenceCoordinator"
	_panel_node.add_child(_persistence)
	_persistence.configure(hub_client, _adapter)
	var preview_button_node: Button = _panel_node.get_node_or_null("%PreviewMapButton")
	var commit_button_node: Button = _panel_node.get_node_or_null("%CommitMapButton")
	var retry_button_node: Button = _panel_node.get_node_or_null("%RetryMapCommitButton")
	var context_toggle_node: CheckButton = _panel_node.get_node_or_null("%MapContextToggle")
	if not preview_button_node or not commit_button_node or not retry_button_node or not context_toggle_node:
		return false
	preview_button_node.pressed.connect(_on_preview_button_pressed)
	commit_button_node.pressed.connect(_request_commit)
	retry_button_node.pressed.connect(_persistence.retry)
	context_toggle_node.toggled.connect(_on_context_toggled)
	context_toggle_node.set_pressed_no_signal(
		saved_state.get("specialist_context_enabled", false) == true
	)
	preview_button_node.visible = true
	commit_button_node.visible = true
	context_toggle_node.visible = true
	var toolbar_node: Control = _panel_node.get_node_or_null("MapToolbar") as Control
	if toolbar_node:
		ConversationLayoutStabilizerScript.compact_input_actions(toolbar_node)
	_connect_add_item_row()
	_connect_closure_audit_toggle()
	_graph_projection = GraphProjectionScript.new()
	if not _graph_projection.mount(
		_panel_node,
		Callable(self, "review_item")
	):
		return false
	_graph_projection.configure_layout_owner(session_id)
	_graph_projection.manual_edge_requested.connect(_on_manual_edge_requested)
	_persistence.commit_started.connect(_on_commit_started)
	_persistence.commit_succeeded.connect(_on_commit_succeeded)
	_persistence.commit_failed.connect(_on_commit_failed)
	_connect_map_column_theme()
	_apply_map_column_styles()
	# The audit surface keeps its own controller and state. All this file owes it is a mount
	# point, the findings on each refresh, and a relay of its state to whoever persists ours.
	_audit_host = AuditHostScript.new()
	if _audit_host.mount(_panel_node, record_store, saved_state.get("closure_audit", {})):
		_audit_host.state_changed.connect(_on_audit_state_changed)
		_audit_host.hide_requested.connect(
			func() -> void: set_closure_audit_active(false)
		)
		# The claims travel with the request because only this controller holds the document.
		_audit_host.suggestions_requested.connect(
			func(request: Dictionary) -> void:
				request["claims"] = ClosureAuditRulesScript.collect_claims_for_audit(
					_adapter.get_document()
				)
				audit_suggestions_requested.emit(request)
		)
	_panel_node.visible = true
	MapPanelTogglesScript.connect_sub_toggles(
		_panel_node,
		Callable(self, "set_closure_audit_active")
	)
	_connect_candidate_source()
	refresh()
	return true


func ingest_story_entry(entry: Dictionary, log_index: int) -> Dictionary:
	if log_index <= _last_ingested_log_index:
		return {"ok": true, "duplicate": true, "applied": 0}
	# Raw transcript and Session Record prose are intentionally not semantic map
	# candidates. Only the validated specialist candidate event is accepted.
	_last_ingested_log_index = log_index
	return {
		"ok": true,
		"ignored": true,
		"applied": 0,
		"reason": "structured_candidates_required",
	}


func ingest_specialist_candidate_batch(batch_payload: Dictionary) -> Dictionary:
	var has_locally_validated_candidates: bool = (
		String(batch_payload.get("candidate_delivery_status", ""))
		== "local_validated"
	)
	if (
		String(batch_payload.get("status", "")) != "complete"
		and not has_locally_validated_candidates
	):
		return {"ok": true, "ignored": true, "applied": 0}
	var candidates_any: Variant = batch_payload.get("map_candidates", [])
	if typeof(candidates_any) != TYPE_ARRAY:
		return {"ok": false, "error": "map_candidates_required"}
	var trace_ref: String = String(batch_payload.get("trace_ref", "")).strip_edges()
	var timestamp_text: String = String(
		batch_payload.get("created_at", Time.get_datetime_string_from_system(true))
	)
	var stage_name: String = String(batch_payload.get("stage_name", "")).strip_edges()
	var commands: Array = _adapter.specialist_candidate_commands(
		candidates_any,
		trace_ref,
		timestamp_text,
		stage_name
	)
	if commands.is_empty():
		return {"ok": true, "applied": 0}
	var turn_id: String = String(batch_payload.get("turn_id", "")).strip_edges()
	var result: Dictionary = _adapter.apply_command_batch(
		"specialist-map-" + turn_id,
		commands,
		"specialist_candidates",
		_turn_sequence(turn_id)
	)
	if bool(result.get("ok", false)) and int(result.get("applied", 0)) > 0:
		_after_local_change()
	return result


func _on_manual_edge_requested(from_id: String, to_id: String, relation_id: String) -> void:
	var command: Dictionary = _adapter.manual_edge_command(
		from_id,
		to_id,
		relation_id,
		_facilitator_ref
	)
	var result: Dictionary = _adapter.apply_command_batch(
		"manual-edge-" + String(command.get("id", "")),
		[command]
	)
	if bool(result.get("ok", false)):
		if int(result.get("applied", 0)) > 0:
			_after_local_change()
	else:
		_set_status(
			"Could not connect those two items: %s" % String(result.get("error", "unknown_error"))
		)


## Wires the manual add row. The row is optional so an older embedding scene
## without it still mounts; the map just loses the add affordance.
func _connect_add_item_row() -> void:
	var text_node: LineEdit = _panel_node.get_node_or_null("%AddItemText") as LineEdit
	var add_button_node: Button = _panel_node.get_node_or_null("%AddItemButton") as Button
	if not text_node or not add_button_node:
		return
	add_button_node.pressed.connect(_on_add_item_submitted)
	text_node.text_submitted.connect(func(_submitted_text: String) -> void: _on_add_item_submitted())


func _on_add_item_submitted() -> void:
	var text_node: LineEdit = _panel_node.get_node_or_null("%AddItemText") as LineEdit
	if not text_node:
		return
	var category_node: OptionButton = _panel_node.get_node_or_null("%AddItemCategory") as OptionButton
	var category_id: String = "opportunity"
	if category_node and category_node.selected >= 0:
		category_id = category_node.get_item_text(category_node.selected).to_lower()
	var result: Dictionary = add_manual_item(category_id, text_node.text)
	# Keep the text on failure so a rejected entry is not lost mid-workshop.
	if bool(result.get("ok", false)) and int(result.get("applied", 0)) > 0:
		text_node.clear()


## Wires the Closure Audit toggle. Optional like the add row, so an older
## embedding scene without it still mounts — the map just loses the audit.
func _connect_closure_audit_toggle() -> void:
	var toggle_node: CheckButton = (
		_panel_node.get_node_or_null("%ClosureAuditToggle") as CheckButton
	)
	if not toggle_node:
		return
	toggle_node.toggled.connect(set_closure_audit_active)
	toggle_node.set_pressed_no_signal(_is_closure_audit_active)
	var suggest_button_node: Button = (
		_panel_node.get_node_or_null("%SuggestOrientationsButton") as Button
	)
	if suggest_button_node:
		suggest_button_node.pressed.connect(_on_suggest_orientations_pressed)
	var review_button_node: Button = (
		_panel_node.get_node_or_null("%ViewsReviewButton") as Button
	)
	if review_button_node:
		review_button_node.pressed.connect(toggle_views_review)
	var reveal_button_node: Button = (
		_panel_node.get_node_or_null("%RevealViewsButton") as Button
	)
	if reveal_button_node:
		reveal_button_node.pressed.connect(reveal_views)


## The controller has no model access of its own, so it asks. The session controller
## owns the conversation manager and hands the result back through
## `apply_orientation_suggestions`.
func _on_suggest_orientations_pressed() -> void:
	if _is_awaiting_orientation_suggestions:
		return
	if not _local_facilitator_may_act("Requesting orientation suggestions"):
		return
	var claims: Array[Dictionary] = collect_claims_for_orientation()
	if claims.is_empty():
		_set_status(
			OrientationPresenterScript.format_nothing_to_suggest(_orientable_claim_count())
		)
		return
	_is_awaiting_orientation_suggestions = true
	_set_status("Asking the model to suggest orientations for %d claim(s)…" % claims.size())
	_refresh_suggest_button()
	orientation_suggestions_requested.emit(claims)


func _refresh_suggest_button() -> void:
	OrientationPresenterScript.apply_suggest_button(
		_panel_node,
		_is_closure_audit_active,
		_is_awaiting_orientation_suggestions
	)


## Opens or closes the audit. Purely a view concern: it reveals the per-card
## orientation pickers and the coverage reading. Closing it hides them again and
## keeps every tag already recorded.
func set_closure_audit_active(is_active: bool) -> void:
	if _is_closure_audit_active == is_active:
		return
	_is_closure_audit_active = is_active
	if not is_active:
		# Undecided suggestions expire with the audit. Holding them across a closed
		# audit would let a stale proposal be accepted in a later stage, against a map
		# that has moved on since.
		_orientation_suggestions.clear()
		_declined_orientation_ids.clear()
	if _audit_host:
		_audit_host.set_audit_active(is_active)
	MapLayoutUtilsScript.apply_audit_split(_panel_node, is_active)
	var toggle_node: CheckButton = (
		_panel_node.get_node_or_null("%ClosureAuditToggle") as CheckButton
	)
	if toggle_node and toggle_node.button_pressed != is_active:
		# The audit's own Hide button routes through here, so the toggle has to be brought back
		# into line or it would keep reading "on" over a closed panel. The Custom drawer's
		# Closure switch is a third route into the same state and needs the same treatment.
		toggle_node.set_pressed_no_signal(is_active)
	MapPanelTogglesScript.sync_sub_toggles(_panel_node, is_active)
	refresh()


func is_closure_audit_active() -> bool:
	return _is_closure_audit_active


## Read-only coverage and concentration reading over the last refreshed document.
func get_closure_findings() -> Dictionary:
	return _last_closure_findings.duplicate(true)


## Holds what a model proposed, so the facilitator can accept or change it. Kept in
## memory only and never persisted: a suggestion is not a tag (REQ-CA-004), so it
## must not survive into saved state where it could be mistaken for one.
func apply_orientation_suggestions(result: Dictionary) -> void:
	_is_awaiting_orientation_suggestions = false
	if not bool(result.get("ok", false)):
		_orientation_suggestions.clear()
		_declined_orientation_ids.clear()
	else:
		_orientation_suggestions = (result.get("suggestions", {}) as Dictionary).duplicate()
		_declined_orientation_ids = (result.get("declined", []) as Array).duplicate()
	_set_status(OrientationSuggesterScript.format_summary(result))
	refresh()


func is_awaiting_orientation_suggestions() -> bool:
	return _is_awaiting_orientation_suggestions


## Hands drafted audit answers to the audit surface, which holds them for review.
func apply_audit_suggestions(result: Dictionary) -> void:
	if _audit_host:
		_audit_host.apply_suggestions(result)


## Claims that could carry an orientation at all, tagged or not. Distinguishes "nothing to
## suggest because the room has already oriented everything" from "nothing to suggest because
## there is nothing here" — opposite situations that `collect_claims_for_orientation()`
## reports identically, as an empty array.
func _orientable_claim_count() -> int:
	var total: int = 0
	for node_any: Variant in _adapter.get_document().get("nodes", []):
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		if String(node_data.get("status", "")) == "rejected":
			continue
		total += 1
	return total


## The claims a suggestion pass should cover: untagged and not already rejected.
## Already-oriented claims are excluded because re-suggesting over a human judgement
## is how assistance turns into pressure.
func collect_claims_for_orientation() -> Array[Dictionary]:
	var claims: Array[Dictionary] = []
	for node_any: Variant in _adapter.get_document().get("nodes", []):
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		if String(node_data.get("status", "")) == "rejected":
			continue
		if not ClosureOrientationScript.get_node_quadrant(node_data).is_empty():
			continue
		claims.append({
			"id": str(node_data.get("id", "")),
			"kind": str(node_data.get("kind", "")),
			"label": str(node_data.get("label", "")),
		})
	return claims


## Records which Closure Map quadrant a claim belongs to; an empty quadrant
## untags it. Not a review decision — see `set_node_orientation` in the adapter.
func orient_item(record_id: String, quadrant_id: String) -> bool:
	if not _local_facilitator_may_act("Orienting a map item"):
		return false
	var was_suggested: bool = (
		_orientation_suggestions.has(record_id)
		or _declined_orientation_ids.has(record_id)
	)
	var result: Dictionary = _adapter.set_node_orientation(
		record_id,
		quadrant_id,
		_facilitator_ref,
		str(_orientation_suggestions.get(record_id, "")),
		was_suggested
	)
	if not bool(result.get("ok", false)):
		_set_status(
			"Could not orient that item: %s" % String(result.get("error", "unknown_error"))
		)
		return false
	if not bool(result.get("changed", false)):
		return true
	_after_local_change()
	return true


## Opens the divergence review. Read-only apart from Reveal, so it is not gated on the
## facilitator claim: everyone should be able to see where the room stands once the views
## are open, which is the whole reason the surface exists.
func toggle_views_review() -> void:
	var panel_node: Control = _panel_node.get_node_or_null("%ViewsReviewPanel") as Control
	if not panel_node:
		return
	panel_node.visible = not panel_node.visible
	if panel_node.visible:
		_refresh_views_review()


func _refresh_views_review() -> void:
	var panel_node: Control = _panel_node.get_node_or_null("%ViewsReviewPanel") as Control
	var review_button_node: Button = _panel_node.get_node_or_null("%ViewsReviewButton") as Button
	if review_button_node:
		review_button_node.visible = _is_closure_audit_active
	if not panel_node or not panel_node.visible or not _adapter:
		return
	ViewsReviewPresenterScript.populate(
		panel_node,
		_adapter.get_document(),
		_adapter.are_views_revealed(),
		_is_local_facilitator()
	)


## Opens the recorded views to the room. One-way: re-hiding views the room has already
## discussed would record a retraction that did not happen.
func reveal_views() -> void:
	if not _local_facilitator_may_act("Revealing recorded views"):
		return
	if not _adapter.reveal_views():
		return
	_set_status("Recorded views are now open to everyone.")
	_after_local_change()


## Records one participant's reading of where a claim sits (REQ-CA-018). Not a vote and
## not a tag: it never changes the facilitator's orientation, which stays canonical.
func record_orientation_view(
	record_id: String,
	held_by: String,
	quadrant_id: String,
	evidence: String
) -> bool:
	var result: Dictionary = _adapter.record_contestation_position(
		record_id,
		ClosureOrientationScript.DIMENSION_PLACEMENT,
		held_by,
		quadrant_id,
		evidence,
		_is_local_facilitator()
	)
	if not bool(result.get("ok", false)):
		_set_status("Could not record that view: %s" % String(result.get("error", "unknown")))
		return false
	if bool(result.get("changed", false)):
		_after_local_change()
	return true


## Records that the room did not converge on this claim's orientation. Not a review
## decision and not a tag — see `set_node_orientation_contested` in the adapter.
func contest_item_orientation(record_id: String, is_contested: bool) -> bool:
	if not _local_facilitator_may_act("Marking an orientation contested"):
		return false
	var result: Dictionary = _adapter.set_node_orientation_contested(
		record_id,
		is_contested,
		_facilitator_ref
	)
	if not bool(result.get("ok", false)):
		_set_status(
			"Could not mark that item: %s" % String(result.get("error", "unknown_error"))
		)
		return false
	if not bool(result.get("changed", false)):
		return true
	_after_local_change()
	return true


func _connect_candidate_source() -> void:
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not scene_tree:
		return
	var trace_store_node: Node = scene_tree.get_first_node_in_group(
		"workshop_specialist_trace_store"
	)
	if not trace_store_node or not trace_store_node.has_signal("candidate_batch_ready"):
		return
	var candidate_callable := Callable(self, "ingest_specialist_candidate_batch")
	if not trace_store_node.is_connected("candidate_batch_ready", candidate_callable):
		trace_store_node.connect("candidate_batch_ready", candidate_callable)


func _turn_sequence(turn_id: String) -> int:
	var suffix: String = turn_id.trim_prefix("turn_")
	return int(suffix) if suffix.is_valid_int() else 0


func apply_live_batch(
	batch_id: String,
	commands: Array,
	stream_id: String,
	sequence: int
) -> Dictionary:
	var result: Dictionary = _adapter.apply_command_batch(
		batch_id,
		commands,
		stream_id,
		sequence
	)
	if bool(result.get("ok", false)) and int(result.get("applied", 0)) > 0:
		_after_local_change()
	return result


func review_item(record_id: String, action_id: String, edited_text: String = "") -> bool:
	if not _adapter.review_proposal(record_id, action_id, edited_text, _facilitator_ref):
		return false
	_after_local_change()
	return true


## Adds a claim the facilitator typed rather than one the specialists proposed.
## The category comes from an explicit picker, so this bypasses the keyword
## classifier that has to guess a column when parsing chat messages.
func add_manual_item(category_id: String, label_text: String) -> Dictionary:
	var normalized_label: String = label_text.strip_edges()
	if normalized_label.is_empty():
		_set_status("Type the claim first, then press Add.")
		return {"ok": false, "error": "empty_label"}
	if not _local_facilitator_may_act("Adding a map item"):
		return {"ok": false, "error": "facilitator_claim_required"}
	var command: Dictionary = _adapter.manual_node_command(
		category_id,
		normalized_label,
		_facilitator_ref
	)
	# The node id is content-derived so duplicate wording collapses, but the batch
	# id must be per-action: reusing it would make re-adding something previously
	# withdrawn look like an already-applied batch.
	var result: Dictionary = _adapter.apply_command_batch(
		"manual-node-%s-%d" % [String(command.get("id", "")), Time.get_ticks_msec()],
		[command]
	)
	if not bool(result.get("ok", false)):
		_set_status(
			"Could not add that item: %s" % String(result.get("error", "unknown_error"))
		)
		return result
	if int(result.get("applied", 0)) == 0:
		_set_status("That wording is already on the map in this column.")
		return result
	_after_local_change()
	return result


## Saves a wording change to your own uncommitted item.
func revise_item(record_id: String, new_label: String) -> bool:
	if not _local_facilitator_may_act("Editing a map item"):
		return false
	var result: Dictionary = _adapter.revise_own_node(record_id, new_label, _facilitator_ref)
	if not bool(result.get("ok", false)):
		_set_status(
			"Could not save that edit: %s" % String(result.get("error", "unknown_error"))
		)
		return false
	if not bool(result.get("changed", false)):
		_set_status("No change to save.")
		return true
	_after_local_change()
	return true


## Removes a human-authored item that has not been committed yet. AI proposals
## are rejected rather than withdrawn, so they stay on the record.
func withdraw_item(record_id: String) -> bool:
	if not _local_facilitator_may_act("Withdrawing a map item"):
		return false
	var result: Dictionary = _adapter.withdraw_node(record_id, _facilitator_ref)
	if not bool(result.get("ok", false)):
		_set_status(
			"Could not withdraw that item: %s" % String(result.get("error", "unknown_error"))
		)
		return false
	_after_local_change()
	# Losing typed connections silently would be surprising, so say so — after
	# _after_local_change has written its own generic draft-changed line.
	var removed_edge_count: int = int(result.get("removed_edges", 0))
	if removed_edge_count > 0:
		_set_status(
			"Withdrew the item and %d connection(s) that depended on it." % removed_edge_count
		)
	return true


## Preview button handler: toggles the Semantic impact preview panel closed if
## it is already open (no need to recompute the diff just to hide it), and
## otherwise builds a fresh preview and opens it. Kept separate from
## show_preview() so other callers (e.g. tests) can still force a preview open
## without depending on the button's open/closed state.
func _on_preview_button_pressed() -> void:
	var preview_panel_node: Control = _panel_node.get_node_or_null("%MapPreviewPanel")
	if preview_panel_node and preview_panel_node.visible:
		preview_panel_node.visible = false
		return
	show_preview()


func show_preview() -> Dictionary:
	var preview: Dictionary = _adapter.build_preview(_facilitator_ref)
	var preview_panel_node: Control = _panel_node.get_node_or_null("%MapPreviewPanel")
	var preview_text_node: TextEdit = _panel_node.get_node_or_null("%MapPreviewText")
	var commit_button_node: Button = _panel_node.get_node_or_null("%CommitMapButton")
	if preview_panel_node:
		preview_panel_node.visible = true
	if preview_text_node:
		preview_text_node.text = JSON.stringify(preview, "\t")
	_preview_hash = JSON.stringify(preview.get("resulting_map", {})).sha256_text()
	_preview_payload = preview.get("resulting_map", {}).duplicate(true)
	if commit_button_node:
		commit_button_node.disabled = not bool(preview.get("valid", false))
	return preview


func route_outcome_to_session_record(record_id: String) -> bool:
	var outcome: Dictionary = _adapter.get_routable_outcome(record_id)
	if outcome.is_empty() or not _record_store:
		return false
	var item: Dictionary = _record_store.add_facilitator_item(
		String(outcome.get("record_category", "")),
		String(outcome.get("text", "")),
		_facilitator_ref,
		{
			"provenance_refs": [
				String(outcome.get("map_item_id", "")),
				String(outcome.get("map_artifact_id", "")),
			],
			"provenance": {
				"authorship_kind": "facilitator_routed",
				"origin_ref": String(outcome.get("map_item_id", "")),
				"thinking_map_artifact_id": String(outcome.get("map_artifact_id", "")),
				"review_status": "reviewed",
			},
		}
	)
	if item.is_empty():
		return false
	return true


func request_closure_route(record_id: String) -> bool:
	var outcome: Dictionary = _adapter.get_routable_outcome(record_id)
	if outcome.is_empty():
		return false
	closure_route_requested.emit(outcome)
	return true


func get_adapter() -> RefCounted:
	return _adapter


func get_state() -> Dictionary:
	return _map_state() if _adapter else {}


func refresh() -> void:
	if not is_instance_valid(_panel_node) or not _adapter:
		return
	# REQ-CA-012. The adapter has always accepted `decision`, `risk`, `owner`, and
	# `next_step`, but the map had only three columns, so every one of them landed in
	# Opportunities — the column for things the room *could* do, holding things it had
	# already settled. Outcomes gives them somewhere true to sit.
	var outcomes_column_node: Node = _panel_node.get_node_or_null("%OutcomesItems")
	var columns: Dictionary = {
		"cause": _panel_node.get_node_or_null("%CausesItems"),
		"effect": _panel_node.get_node_or_null("%EffectsItems"),
		"opportunity": _panel_node.get_node_or_null("%OpportunitiesItems"),
		"decision": outcomes_column_node,
		"risk": outcomes_column_node,
		"owner": outcomes_column_node,
		"next_step": outcomes_column_node,
	}
	# Several kinds share the Outcomes node, so clearing per key would clear it repeatedly
	# and, worse, would clear it *after* cards had been added if the order ever changed.
	var cleared_nodes: Array[Node] = []
	for category_id: String in columns:
		var column_node: Node = columns[category_id] as Node
		if column_node and column_node not in cleared_nodes:
			_clear_children(column_node)
			cleared_nodes.append(column_node)
	var document: Dictionary = _adapter.get_document()
	for node_any: Variant in document.get("nodes", []):
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		var category_id: String = String(node_data.get("kind", ""))
		var target_column: VBoxContainer = columns.get(category_id) as VBoxContainer
		if not target_column:
			target_column = columns["opportunity"] as VBoxContainer
		_add_card(target_column, node_data)
	var relationship_label_node: Label = _panel_node.get_node_or_null("%RelationshipStatus")
	if relationship_label_node:
		relationship_label_node.text = "Typed connections: %d causal/evidential proposal(s)" % (
			document.get("edges", []) as Array
		).size()
	_last_symbolic_insights = SymbolicRulesScript.evaluate(document)
	_apply_symbolic_insights(_last_symbolic_insights)
	_last_closure_findings = ClosureAuditRulesScript.evaluate(document)
	_apply_closure_findings(_last_closure_findings)
	if _graph_projection:
		_graph_projection.refresh_document(document)


## Read-only findings from the symbolic rules layer (contradictions, derived
## multi-hop causal chains, evidence gaps) for the last refreshed document.
func get_symbolic_insights() -> Dictionary:
	return _last_symbolic_insights.duplicate(true)


func get_map_view_mode() -> String:
	if _graph_projection:
		return String(_graph_projection.get_view_mode())
	return "columns"


func set_map_view_mode(view_mode: String) -> void:
	if _graph_projection:
		_graph_projection.set_view_mode(view_mode)
		refresh()


func _add_card(parent_node: VBoxContainer, node_data: Dictionary) -> void:
	var card_node: Control = CardScene.instantiate() as Control
	parent_node.add_child(card_node)
	var item_text_node: TextEdit = card_node.get_node_or_null("%ItemText")
	var provenance_label_node: Label = card_node.get_node_or_null("%ProvenanceLabel")
	var state_label_node: Label = card_node.get_node_or_null("%StateLabel")
	var annotations_any: Variant = node_data.get("annotations", {})
	var annotations: Dictionary = (
		annotations_any if typeof(annotations_any) == TYPE_DICTIONARY else {}
	)
	var item_text: String = String(node_data.get("label", ""))
	item_text_node.text = item_text
	var estimated_line_count: int = maxi(
		3,
		int(ceil(float(item_text.length()) / 38.0))
	)
	item_text_node.custom_minimum_size.y = clampf(
		float(estimated_line_count * 22 + 16),
		96.0,
		176.0
	)
	# Fixed chrome below the text: provenance, status, and the review actions row.
	# The orientation row only exists while auditing, so it is only paid for then.
	var card_chrome_height: float = 102.0
	if _is_closure_audit_active:
		card_chrome_height += 30.0
	card_node.custom_minimum_size.y = (
		item_text_node.custom_minimum_size.y + card_chrome_height
	)
	var source_class: String = String(annotations.get("source_class", ""))
	var source_label: String = String(annotations.get("source_label", "Provenance unavailable"))
	provenance_label_node.text = "Source: " + source_label
	provenance_label_node.tooltip_text = _source_class_tooltip(
		source_class,
		String(annotations.get("authorship_kind", ""))
	)
	var display_state: String = String(
		annotations.get("proposal_state", node_data.get("status", "suggested"))
	)
	state_label_node.text = "Status: " + display_state.capitalize()
	state_label_node.tooltip_text = _proposal_state_tooltip(display_state)
	state_label_node.add_theme_color_override("font_color", _proposal_state_color(display_state))
	var record_id: String = String(node_data.get("id", ""))
	var is_suggested: bool = String(node_data.get("status", "")) == "suggested"
	var is_own_draft: bool = _adapter.is_own_uncommitted(record_id)
	for button_id: String in ["AcceptButton", "EditButton", "RejectButton", "DeferButton"]:
		var action_button_node: Button = card_node.get_node_or_null("%" + button_id)
		action_button_node.disabled = not is_suggested
	var accept_button_node: Button = card_node.get_node_or_null("%AcceptButton")
	var edit_button_node: Button = card_node.get_node_or_null("%EditButton")
	var reject_button_node: Button = card_node.get_node_or_null("%RejectButton")
	var defer_button_node: Button = card_node.get_node_or_null("%DeferButton")
	accept_button_node.pressed.connect(func() -> void: review_item(record_id, "accepted"))
	# Your own item is already accepted, so the review Edit action cannot apply to
	# it. Reuse the same button to save a wording correction instead, which is
	# what a facilitator fixing their own typo actually means.
	if is_own_draft:
		edit_button_node.disabled = false
		edit_button_node.text = "Save edit"
		edit_button_node.tooltip_text = (
			"Save your changes to this item's wording. Available until it is committed."
		)
		edit_button_node.pressed.connect(
			func() -> void: revise_item(record_id, item_text_node.text)
		)
	else:
		edit_button_node.pressed.connect(
			func() -> void: review_item(record_id, "edited", item_text_node.text)
		)
	reject_button_node.pressed.connect(func() -> void: review_item(record_id, "rejected"))
	defer_button_node.pressed.connect(func() -> void: review_item(record_id, "deferred"))
	var withdraw_button_node: Button = card_node.get_node_or_null("%WithdrawButton")
	withdraw_button_node.visible = is_own_draft
	if is_own_draft:
		withdraw_button_node.pressed.connect(func() -> void: withdraw_item(record_id))
	var route_button_node: Button = card_node.get_node_or_null("%RouteButton")
	var is_routable: bool = not _adapter.get_routable_outcome(record_id).is_empty()
	route_button_node.visible = is_routable
	if is_routable:
		route_button_node.pressed.connect(
			func() -> void: route_outcome_to_session_record(record_id)
		)
	var closure_button_node: Button = card_node.get_node_or_null("%ClosureButton")
	closure_button_node.visible = is_routable
	if is_routable:
		closure_button_node.pressed.connect(
			func() -> void: request_closure_route(record_id)
		)
	_bind_orientation_control(card_node, node_data, record_id)


## Populates and wires a card's orientation picker. The items are built from the
## vocabulary module rather than authored in the scene so the labels and per-item
## explanations cannot drift from the Closure Map definition, and so this surface
## and the SynAxes Closure Editor keep naming the quadrants identically.
func _bind_orientation_control(
	card_node: Control,
	node_data: Dictionary,
	record_id: String
) -> void:
	OrientationPresenterScript.bind_card(
		card_node,
		node_data,
		record_id,
		_is_closure_audit_active,
		_orientation_suggestions,
		_declined_orientation_ids,
		Callable(self, "orient_item"),
		Callable(self, "contest_item_orientation"),
		_adapter.are_views_revealed()
	)


## Explains a map item's provenance annotation (see thinking_map_adapter.gd's
## SOURCE_CLASSES) in the ProvenanceLabel tooltip — the "Source: ..." line
## alone reads as an unlabeled fragment without this context.
func _source_class_tooltip(source_class: String, authorship_kind: String = "") -> String:
	if authorship_kind == "facilitator_manual" or authorship_kind == "participant_manual":
		return "Typed directly onto the map by a person, not extracted from the conversation."
	match source_class:
		"participant_said":
			return "Directly attributed to something said in the transcript this turn."
		"external_evidence_supported":
			return "The specialists cited external evidence for this claim, not just the conversation."
		_:
			return "Synthesized or inferred by the AI specialists — not a direct quote."


## Explains a map item's review-state annotation in the StateLabel tooltip.
func _proposal_state_tooltip(proposal_state: String) -> String:
	match proposal_state:
		"suggested":
			return "Proposed by the specialists. Accept, Edit, Reject, or Defer below to review it."
		"accepted":
			return "Reviewed and accepted as-is. No further action needed unless you want to change it."
		"edited":
			return "Reviewed and accepted with facilitator edits to the wording."
		"rejected":
			return "Reviewed and rejected. Kept for the record but excluded from commits."
		"deferred":
			return "Review postponed. Still pending a decision."
		_:
			return "Review status for this map item."


## Color-codes the StateLabel so status is scannable at a glance across a
## column, on top of the "Status: " text prefix.
func _proposal_state_color(proposal_state: String) -> Color:
	match proposal_state:
		"suggested":
			return Color(0.7, 0.5, 0.05, 1)
		"accepted", "edited":
			return Color(0.16, 0.55, 0.25, 1)
		"rejected":
			return Color(0.7, 0.2, 0.2, 1)
		"deferred":
			return Color(0.4, 0.35, 0.6, 1)
		_:
			return Color(0.45, 0.45, 0.5, 1)


func _request_commit() -> void:
	if _preview_hash.is_empty() or _preview_payload.is_empty():
		return
	if not _local_facilitator_may_act("Map commit"):
		return
	_persistence.request_commit_payload(_preview_payload)


## Gate for actions that change or publish the shared map. In single-player the
## presence store is inactive and the local peer is always the facilitator, so
## this only restricts anything in a multi-instance session (ADR 0013).
## The silent counterpart of `_local_facilitator_may_act`, for deciding what a surface may
## offer rather than whether an action may proceed. It writes no status message, because
## disabling a button the user has not pressed should not explain itself in the status line.
##
## A solo session has no presence at all and is treated as the facilitator, matching the
## permissive default the acting check already uses.
func _is_local_facilitator() -> bool:
	var presence_node: Node = AutoloadsScript.workshop_presence()
	if not presence_node or not presence_node.has_method("is_active") or not presence_node.is_active():
		return true
	return bool(presence_node.call("has_local_facilitator_claim"))


func _local_facilitator_may_act(action_label: String) -> bool:
	var presence_node: Node = AutoloadsScript.workshop_presence()
	if not presence_node or not presence_node.has_method("is_active") or not presence_node.is_active():
		return true
	if bool(presence_node.call("has_local_facilitator_claim")):
		return true
	var status_node: Label = _panel_node.get_node_or_null("%MapCommitStatus") as Label
	if status_node:
		status_node.text = "%s requires a Facilitator claim." % action_label
	return false


func _on_context_toggled(is_enabled: bool) -> void:
	var trace: Dictionary = _adapter.set_specialist_context_enabled(
		is_enabled,
		_facilitator_ref
	)
	var context_payload: Dictionary = _adapter.get_specialist_prompt_context()
	specialist_context_changed.emit(context_payload, trace)
	state_changed.emit(_map_state())


func _on_commit_started() -> void:
	_set_status("Committing reviewed map without blocking the live session…")


func _on_commit_succeeded(artifact_id: String, _payload: Dictionary) -> void:
	_preview_hash = ""
	_preview_payload = {}
	var commit_button_node: Button = _panel_node.get_node_or_null("%CommitMapButton")
	var retry_button_node: Button = _panel_node.get_node_or_null("%RetryMapCommitButton")
	commit_button_node.disabled = true
	retry_button_node.visible = false
	_set_status("Committed map version: " + artifact_id)
	state_changed.emit(_map_state())


func _on_commit_failed(error_text: String) -> void:
	var retry_button_node: Button = _panel_node.get_node_or_null("%RetryMapCommitButton")
	retry_button_node.visible = _persistence.has_retryable_commit()
	_set_status(error_text)
	state_changed.emit(_map_state())


func _after_local_change() -> void:
	_preview_hash = ""
	_preview_payload = {}
	var commit_button_node: Button = _panel_node.get_node_or_null("%CommitMapButton")
	if commit_button_node:
		commit_button_node.disabled = true
	_set_status("Local reviewed draft changed — Preview required before Commit.")
	refresh()
	state_changed.emit(_map_state())


## The map's persisted state plus the audit's, so one save covers both. The audit rides in
## the map's state rather than the workshop's because it is only meaningful against this map:
## restoring an audit next to a different document would attach classifications to quadrants
## whose contents had changed underneath them.
func _map_state() -> Dictionary:
	var map_state: Dictionary = _adapter.get_state()
	if _audit_host:
		_audit_state = _audit_host.get_state()
	if not _audit_state.is_empty():
		map_state["closure_audit"] = _audit_state.duplicate(true)
	return map_state


func _on_audit_state_changed(audit_state: Dictionary) -> void:
	_audit_state = audit_state
	state_changed.emit(_map_state())


func _set_status(status_text: String) -> void:
	var status_label_node: Label = _panel_node.get_node_or_null("%MapCommitStatus")
	if status_label_node:
		status_label_node.text = status_text


func _apply_symbolic_insights(insights: Dictionary) -> void:
	var insights_label_node: Label = _panel_node.get_node_or_null("%SymbolicInsightsLabel")
	if not insights_label_node:
		return
	var contradictions: Array = insights.get("contradictions", [])
	var causal_chains: Array = insights.get("causal_chains", [])
	var evidence_gaps: Array = insights.get("evidence_gaps", [])
	if contradictions.is_empty() and causal_chains.is_empty() and evidence_gaps.is_empty():
		insights_label_node.text = "Symbolic checks: none flagged"
		insights_label_node.tooltip_text = (
			"No contradictions, causal chains, or evidence gaps detected yet."
		)
		return
	insights_label_node.text = (
		"Symbolic checks: %d contradiction(s) \u00b7 %d causal chain(s) \u00b7 %d evidence gap(s)"
		% [contradictions.size(), causal_chains.size(), evidence_gaps.size()]
	)
	var tooltip_lines: Array[String] = []
	for finding_any: Variant in contradictions + causal_chains + evidence_gaps:
		tooltip_lines.append("- " + String((finding_any as Dictionary).get("summary", "")))
	insights_label_node.tooltip_text = "\n".join(tooltip_lines.slice(0, mini(tooltip_lines.size(), 12)))


func _apply_closure_findings(findings: Dictionary) -> void:
	_refresh_suggest_button()
	var coverage_label_node: Label = (
		_panel_node.get_node_or_null("%ClosureCoverageLabel") as Label
	)
	if not coverage_label_node:
		return
	coverage_label_node.visible = _is_closure_audit_active
	if not _is_closure_audit_active:
		return
	coverage_label_node.text = ClosureAuditRulesScript.format_summary(findings)
	coverage_label_node.tooltip_text = ClosureAuditRulesScript.format_reading(findings)
	if _audit_host:
		_audit_host.refresh(findings)
	_refresh_views_review()


func _clear_children(parent_node: Node) -> void:
	if not parent_node:
		return
	for child_node: Node in parent_node.get_children():
		# Detached before freeing, not merely queued: `queue_free` runs at frame end, so a
		# column rebuilt during a refresh would hold the old cards and the new ones at once.
		parent_node.remove_child(child_node)
		child_node.queue_free()


func _connect_map_column_theme() -> void:
	var theme_manager_node: Node = AutoloadsScript.get_node_by_name("ThemeManager")
	if _map_column_mode_connected or theme_manager_node == null:
		return
	if not theme_manager_node.mode_changed.is_connected(_on_map_column_mode_changed):
		theme_manager_node.mode_changed.connect(_on_map_column_mode_changed)
	_map_column_mode_connected = true


func _on_map_column_mode_changed(_mode: String) -> void:
	_apply_map_column_styles()


func _apply_map_column_styles() -> void:
	var theme_manager_node: Node = AutoloadsScript.get_node_by_name("ThemeManager")
	MapLayoutUtilsScript.apply_column_styles(
		_panel_node,
		theme_manager_node != null and theme_manager_node.is_dark()
	)
