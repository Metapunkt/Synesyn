extends RefCounted
class_name WorkshopClosureAuditController

## Mounts and drives the closure audit surface.
##
## A `RefCounted` controller over a scene, like the other Workshop Catalyst panel
## controllers, so the audit's own logic stays in `WorkshopClosureAuditRecord` and this file
## does nothing but move values between the record and the widgets. The Thinking Map
## controller is already at the soft line limit, and the audit is a distinct surface with its
## own lifecycle, so it gets its own controller rather than a sixth responsibility there.
##
## Reads the map's geometry from `WorkshopClosureAuditRules` on every refresh rather than
## caching it: which quadrants are thin changes as the room tags claims, and a completion
## gate computed against a stale reading would let an audit close over a quadrant that had
## since emptied.

signal state_changed(audit_state: Dictionary)
## Carries proposals to whoever owns the Session Record store.
signal route_requested()
## The panel cannot close itself: the map's own toggle owns whether the audit is open, and a
## panel that hid its own host would leave that toggle showing "on".
signal hide_requested()
## Asks for model-drafted answers to the steps below (REQ-CA-021).
signal suggestions_requested()

const RecordScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_record.gd"
)
const DiagnosticsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_diagnostics.gd"
)
const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)
const RulesScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_rules.gd"
)
const SuggestionPresenterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_suggestion_presenter.gd"
)

var _panel_node: Control = null
var _record: RefCounted = null
var _findings: Dictionary = {}
var _debt_conditions: Dictionary = {}
## Once the room has chosen an edge itself, the reading stops moving the pickers under it.
var _transition_pickers_touched: bool = false
## Model drafts awaiting a decision, keyed as the suggester returns them. Held here rather than
## on the record so nothing drafted can satisfy the completion gate, and cleared when the audit
## closes: a draft read against a map that has since moved on is worse than no draft.
var _suggestions: Dictionary = {}


func mount(panel_node: Control, saved_state: Dictionary = {}) -> bool:
	if not panel_node:
		return false
	_panel_node = panel_node
	_record = RecordScript.new()
	_record.initialize(saved_state)
	_populate_pickers()
	_connect_controls()
	refresh({})
	return true


func get_record() -> RefCounted:
	return _record


func get_state() -> Dictionary:
	return _record.get_state() if _record else {}


## `findings` is the rules module's output for the current map.
func refresh(findings: Dictionary) -> void:
	if not _panel_node or not _record:
		return
	_findings = findings
	_sync_orient_step()
	_sync_decision_input()
	_rebuild_absence_list()
	_sync_concentration()
	_sync_debt()
	_sync_transition()
	# After the step it belongs to, because `_sync_transition` returns early in several cases
	# and a draft rendered inside it would be skipped in exactly those cases.
	_render_transition_suggestion()
	_rebuild_action_list()
	_render_action_suggestions()
	_sync_gate_status()


## The quadrants the audit must account for: empty ones and weak ones together. Weak counts
## because a quadrant holding one claim against a dominant quadrant's twelve is not covered
## in any sense the manual would accept — it only looks covered.
func get_thin_quadrants() -> Array[String]:
	var thin: Array[String] = []
	for quadrant_any: Variant in _findings.get("empty_quadrants", []):
		var quadrant: String = String(quadrant_any)
		if quadrant not in thin:
			thin.append(quadrant)
	for quadrant_any: Variant in _findings.get("weak_quadrants", []):
		var quadrant: String = String(quadrant_any)
		if quadrant not in thin:
			thin.append(quadrant)
	return thin


func _connect_controls() -> void:
	var decision_button: Button = _node("%DecisionSaveButton") as Button
	if decision_button:
		decision_button.pressed.connect(_on_decision_set)
	var concentration_picker: OptionButton = _node("%ConcentrationPicker") as OptionButton
	if concentration_picker:
		concentration_picker.item_selected.connect(_on_concentration_selected)
	var debt_button: Button = _node("%DebtRecordButton") as Button
	if debt_button:
		debt_button.pressed.connect(_on_debt_recorded)
	var debt_picker: OptionButton = _node("%DebtQuadrantPicker") as OptionButton
	if debt_picker:
		# The four answers are about one quadrant's absence. Carrying them to the next quadrant
		# would record that one as debt on evidence gathered about a different absence.
		debt_picker.item_selected.connect(
			func(_item_index: int) -> void:
				_reset_debt_conditions()
		)
	var transition_button: Button = _node("%TransitionSaveButton") as Button
	if transition_button:
		transition_button.pressed.connect(_on_transition_set)
	for picker_name: String in ["%TransitionFromPicker", "%TransitionToPicker"]:
		var transition_picker: OptionButton = _node(picker_name) as OptionButton
		if transition_picker:
			transition_picker.item_selected.connect(
				func(_item_index: int) -> void:
					_transition_pickers_touched = true
					_sync_transition()
			)
	var action_button: Button = _node("%ActionAddButton") as Button
	if action_button:
		action_button.pressed.connect(_on_action_added)
	var route_button: Button = _node("%RouteButton") as Button
	if route_button:
		route_button.pressed.connect(func() -> void: route_requested.emit())
	var hide_button: Button = _node("%AuditHideButton") as Button
	if hide_button:
		hide_button.pressed.connect(func() -> void: hide_requested.emit())
	var suggest_button: Button = _node("%AuditSuggestButton") as Button
	if suggest_button:
		suggest_button.pressed.connect(func() -> void: suggestions_requested.emit())


## Every picker's contents come from the vocabularies, never from the scene, so a
## classification cannot be renamed in one place and left stale in another.
func _populate_pickers() -> void:
	var concentration_picker: OptionButton = _node("%ConcentrationPicker") as OptionButton
	if concentration_picker:
		concentration_picker.clear()
		concentration_picker.add_item("What it means…", -1)
		concentration_picker.set_item_disabled(0, true)
		for classification_id: String in DiagnosticsScript.CONCENTRATION_CLASSIFICATIONS:
			concentration_picker.add_item(
				String(DiagnosticsScript.CONCENTRATION_LABELS.get(classification_id, classification_id))
			)
			concentration_picker.set_item_tooltip(
				concentration_picker.item_count - 1,
				String(DiagnosticsScript.CONCENTRATION_HELP.get(classification_id, ""))
			)
	for picker_name: String in ["%DebtQuadrantPicker", "%TransitionFromPicker", "%TransitionToPicker"]:
		var picker_node: OptionButton = _node(picker_name) as OptionButton
		if not picker_node:
			continue
		picker_node.clear()
		for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
			# Compact text because an OptionButton's minimum width is set by its longest item
			# regardless of `clip_text`, and the full option text made these three pickers
			# demand 335px inside a map column. The full reading stays in the tooltip.
			picker_node.add_item(
				ClosureOrientationScript.get_compact_option_text(quadrant_id)
			)
			picker_node.set_item_tooltip(
				picker_node.item_count - 1,
				ClosureOrientationScript.get_quadrant_help(quadrant_id)
			)
	var transition_to: OptionButton = _node("%TransitionToPicker") as OptionButton
	if transition_to and transition_to.item_count > 1:
		# Defaulting both pickers to A would make the commonest first press an invalid
		# same-quadrant transition.
		transition_to.select(1)
	_rebuild_debt_conditions()


## One checkbox per condition, labelled with the question a facilitator has to put to the
## room rather than the field name.
func _rebuild_debt_conditions() -> void:
	var conditions_box: Node = _node("%DebtConditions")
	if not conditions_box:
		return
	_clear_children(conditions_box)
	for condition_id: String in DiagnosticsScript.DEBT_CONDITIONS:
		var condition_check := CheckBox.new()
		condition_check.text = String(
			DiagnosticsScript.DEBT_CONDITION_PROMPTS.get(condition_id, condition_id)
		)
		# Each prompt is a full question, and four of them unwrapped would push the panel
		# wider than the column it sits in.
		condition_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		condition_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		condition_check.add_theme_font_size_override("font_size", 11)
		condition_check.set_pressed_no_signal(bool(_debt_conditions.get(condition_id, false)))
		condition_check.toggled.connect(
			func(is_pressed: bool) -> void:
				_debt_conditions[condition_id] = is_pressed
		)
		conditions_box.add_child(condition_check)


## Hands the panel a set of model drafts. Nothing is applied: each lands beside the step it
## answers, with the model's reason, and waits.
func set_suggestions(suggestions: Dictionary) -> void:
	_suggestions = suggestions.duplicate(true)
	refresh(_findings)


func clear_suggestions() -> void:
	_suggestions = {}
	refresh(_findings)


## The pass's own progress and outcome, which is not the audit's state and must not be written
## into the completion gate.
func set_suggest_status(status_text: String, is_busy: bool = false) -> void:
	var status_label: Label = _node("%AuditSuggestStatus") as Label
	if status_label:
		status_label.text = status_text
		status_label.visible = not status_text.is_empty()
	var suggest_button: Button = _node("%AuditSuggestButton") as Button
	if suggest_button:
		suggest_button.disabled = is_busy
		suggest_button.text = "Drafting…" if is_busy else "Suggest answers"


## Puts one draft into the container reserved for its step, or empties that container when
## there is nothing to offer. Accepting or dismissing drops the draft, so the strip disappears
## and the step's ordinary widgets show what the record now holds.
func _render_suggestion(
	host_name: String,
	suggestion_key: String,
	body_text: String,
	accept_text: String,
	on_accept: Callable
) -> void:
	var host_node: Node = _node(host_name)
	if not host_node:
		return
	_clear_children(host_node)
	if not _suggestions.has(suggestion_key):
		return
	host_node.add_child(SuggestionPresenterScript.build_strip(
		body_text,
		accept_text,
		on_accept,
		func() -> void:
			_suggestions.erase(suggestion_key)
			refresh(_findings)
	))


func _sync_decision_input() -> void:
	var decision_input: LineEdit = _node("%DecisionInput") as LineEdit
	if decision_input and not decision_input.has_focus():
		decision_input.text = _record.get_decision_under_audit()
	_render_suggestion(
		"%DecisionSuggestion",
		"decision",
		String(_suggestions.get("decision", "")),
		"Use this",
		func() -> void:
			var suggested_text: String = String(_suggestions.get("decision", ""))
			_suggestions.erase("decision")
			# Written to the record and left in the field, so accepting settles the step while
			# still leaving the wording open to edit and Set again.
			_record.set_decision_under_audit(suggested_text)
			_emit_and_refresh()
	)


func _on_decision_set() -> void:
	var decision_input: LineEdit = _node("%DecisionInput") as LineEdit
	if not decision_input:
		return
	if _record.set_decision_under_audit(decision_input.text):
		_emit_and_refresh()


## One row per thin quadrant: what kind of absence, then its triage. Built in code because
## which quadrants are thin is only known at runtime.
func _rebuild_absence_list() -> void:
	var list_node: Node = _node("%AbsenceList")
	if not list_node:
		return
	_clear_children(list_node)
	var thin_quadrants: Array[String] = get_thin_quadrants()
	if thin_quadrants.is_empty():
		# Two very different situations produce no thin quadrants, and telling the room
		# "nothing to classify" for both is how an unexamined map reads as a clean one.
		var note_text: String = (
			"Every quadrant has claims in it, so there is nothing to explain here. Check that"
			+ " against your own sense of what the group skipped."
		)
		if not _is_map_readable():
			# The how-to lives in step 0 now; repeating it here read as two instructions.
			note_text = (
				"Not enough claims are tagged to tell which quadrants are empty. See step 0"
				+ " above. Run the audit now and it will report a clean map that it cannot"
				+ " actually see."
			)
		list_node.add_child(SuggestionPresenterScript.build_body_note(note_text))
		return
	for quadrant_id: String in thin_quadrants:
		list_node.add_child(_absence_row(quadrant_id))


func _absence_row(quadrant_id: String) -> Control:
	var row_box := VBoxContainer.new()
	row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var entry: Dictionary = _record.get_absence(quadrant_id)
	var heading: Label = SuggestionPresenterScript.build_body_note(
		ClosureOrientationScript.get_canonical_with_gloss(quadrant_id)
	)
	heading.tooltip_text = ClosureOrientationScript.get_quadrant_help(quadrant_id)
	row_box.add_child(heading)
	var picker := OptionButton.new()
	picker.clip_text = true
	picker.add_theme_font_size_override("font_size", 11)
	picker.add_item("Why is it missing?", -1)
	picker.set_item_disabled(0, true)
	var selected_index: int = 0
	for index: int in DiagnosticsScript.ABSENCE_CLASSIFICATIONS.size():
		var classification_id: String = DiagnosticsScript.ABSENCE_CLASSIFICATIONS[index]
		picker.add_item(String(DiagnosticsScript.ABSENCE_LABELS.get(classification_id, classification_id)))
		picker.set_item_tooltip(
			picker.item_count - 1,
			String(DiagnosticsScript.ABSENCE_HELP.get(classification_id, ""))
		)
		if String(entry.get("classification", "")) == classification_id:
			selected_index = index + 1
	picker.select(selected_index)
	picker.item_selected.connect(
		func(item_index: int) -> void:
			_on_absence_selected(quadrant_id, item_index)
	)
	row_box.add_child(picker)
	if entry.has("classification"):
		row_box.add_child(_triage_row(quadrant_id, entry))
	var suggested: Dictionary = _absence_suggestion(quadrant_id)
	if not suggested.is_empty():
		# Offered even when the row is already answered: a draft that disagreed with the room
		# is worth seeing, and hiding it would make the pass look like it had skipped the
		# quadrant. Accepting overwrites; dismissing leaves the room's answer standing.
		row_box.add_child(SuggestionPresenterScript.build_strip(
			SuggestionPresenterScript.describe_absence(suggested),
			"Accept",
			func() -> void: _accept_absence_suggestion(quadrant_id),
			func() -> void: _dismiss_absence_suggestion(quadrant_id)
		))
	return row_box


func _absence_suggestion(quadrant_id: String) -> Dictionary:
	var absences: Dictionary = _suggestions.get("absences", {})
	var entry_any: Variant = absences.get(quadrant_id, {})
	return entry_any if typeof(entry_any) == TYPE_DICTIONARY else {}


## Applies the classification, then the bands if the draft carried both. Order matters:
## `classify_absence` clears any existing verdict, so triaging first would lose it.
func _accept_absence_suggestion(quadrant_id: String) -> void:
	var suggested: Dictionary = _absence_suggestion(quadrant_id)
	if suggested.is_empty():
		return
	_dismiss_absence_suggestion(quadrant_id, false)
	_record.classify_absence(quadrant_id, String(suggested.get("classification", "")))
	var consequence: String = String(suggested.get("consequence", ""))
	var confidence: String = String(suggested.get("confidence", ""))
	if not consequence.is_empty() or not confidence.is_empty():
		_record.triage_absence(quadrant_id, consequence, confidence)
	_emit_and_refresh()


func _dismiss_absence_suggestion(quadrant_id: String, should_refresh: bool = true) -> void:
	var absences: Dictionary = _suggestions.get("absences", {})
	absences.erase(quadrant_id)
	if absences.is_empty():
		_suggestions.erase("absences")
	if should_refresh:
		refresh(_findings)


## Triage appears only once the absence is classified, which mirrors the record's own refusal
## to accept a verdict before then — the surface should not offer a control that the model
## behind it will reject.
func _triage_row(quadrant_id: String, entry: Dictionary) -> Control:
	# Flow rather than a fixed row: two pickers and a verdict do not fit the width of a map
	# column, and an HBoxContainer answers that by crushing whichever child has no size flags
	# down to a single character per line.
	var triage_box := HFlowContainer.new()
	triage_box.add_theme_constant_override("h_separation", 6)
	triage_box.add_child(SuggestionPresenterScript.build_band_picker(
		"Cost if it matters…",
		"How bad it would be if this gap turns out to matter after all.",
		String(entry.get("consequence", "")),
		func(band_id: String) -> void:
			_on_triage_band(quadrant_id, band_id, "")
	))
	triage_box.add_child(SuggestionPresenterScript.build_band_picker(
		"Sure it doesn't…",
		"How sure you are that it does not matter.",
		String(entry.get("confidence", "")),
		func(band_id: String) -> void:
			_on_triage_band(quadrant_id, "", band_id)
	))
	var verdict: String = String(entry.get("verdict", ""))
	var verdict_text: String = "Answer both to see what to do."
	if not verdict.is_empty():
		verdict_text = String(DiagnosticsScript.TRIAGE_LABELS.get(verdict, ""))
	triage_box.add_child(SuggestionPresenterScript.build_body_note(verdict_text))
	return triage_box


func _on_absence_selected(quadrant_id: String, item_index: int) -> void:
	if item_index <= 0:
		return
	var classification_id: String = DiagnosticsScript.ABSENCE_CLASSIFICATIONS[item_index - 1]
	if bool(_record.classify_absence(quadrant_id, classification_id).get("changed", false)):
		_emit_and_refresh()


## Bands arrive one at a time, so the half that did not change is read back off the record and
## sent again. The record stores an incomplete pair and withholds the verdict until both are
## present, so nothing here has to hold a partial answer of its own.
func _on_triage_band(quadrant_id: String, consequence_band: String, confidence_band: String) -> void:
	var entry: Dictionary = _record.get_absence(quadrant_id)
	var consequence: String = (
		consequence_band if not consequence_band.is_empty()
		else String(entry.get("consequence", ""))
	)
	var confidence: String = (
		confidence_band if not confidence_band.is_empty()
		else String(entry.get("confidence", ""))
	)
	if bool(_record.triage_absence(quadrant_id, consequence, confidence).get("ok", false)):
		_emit_and_refresh()


## Step 0: how far the map is from having a readable distribution. Stays visible once the
## threshold is met rather than disappearing — a step that vanishes leaves a facilitator
## wondering whether they missed it, and the count is still worth seeing beside a reading
## drawn from it.
func _sync_orient_step() -> void:
	var status_label: Label = _node("%OrientStatus") as Label
	if not status_label:
		return
	var oriented_count: int = int(_findings.get("tagged_count", 0))
	var needed: int = int(_findings.get(
		"min_tagged_for_reading", RulesScript.MIN_TAGGED_FOR_READING
	))
	var untagged_count: int = int(_findings.get("untagged_count", 0))
	if oriented_count >= needed:
		var satisfied_text: String = (
			"%d claims tagged. That is enough to read the spread." % oriented_count
		)
		if untagged_count > 0:
			# Named because the reading is about the tagged claims only, and a facilitator
			# should know how much of the map it is silent about.
			satisfied_text += (
				" %d are still untagged, so everything below describes only the %d." % [
					untagged_count, oriented_count
				]
			)
		status_label.text = satisfied_text
		return
	status_label.text = (
		"%d of %d claims tagged. Pick a quadrant on each claim's card, or press Suggest in the"
		+ " row below to have the model propose them. You accept or change each one."
	) % [oriented_count, needed]


func _sync_concentration() -> void:
	var target_label: Label = _node("%ConcentrationTarget") as Label
	var picker_node: OptionButton = _node("%ConcentrationPicker") as OptionButton
	var dominant: String = String(_findings.get("dominant_quadrant", ""))
	var concentration: Dictionary = _record.get_concentration()
	if target_label:
		if dominant.is_empty() and not _is_map_readable():
			# The rules module reports no dominant quadrant both for a genuine tie and for a
			# map it cannot read yet. Saying "no quadrant dominates" for the second is a
			# finding of balance drawn from no material at all.
			target_label.text = (
				"Not enough claims are tagged to tell whether one quadrant holds most of them."
			)
		elif dominant.is_empty():
			# A tie is not a concentration, and the rules module reports no dominant quadrant
			# for one rather than picking a winner.
			target_label.text = (
				"The claims are spread evenly, so there is no pile-up to explain."
			)
		else:
			target_label.text = "Most of the claims are in %s." % (
				ClosureOrientationScript.get_canonical_with_gloss(dominant)
			)
	if not picker_node:
		return
	picker_node.disabled = dominant.is_empty()
	var stored_class: String = String(concentration.get("classification", ""))
	var selected_index: int = 0
	for index: int in DiagnosticsScript.CONCENTRATION_CLASSIFICATIONS.size():
		if DiagnosticsScript.CONCENTRATION_CLASSIFICATIONS[index] == stored_class:
			selected_index = index + 1
	picker_node.select(selected_index)
	var suggested: Dictionary = _suggestions.get("concentration", {})
	_render_suggestion(
		"%ConcentrationSuggestion",
		"concentration",
		SuggestionPresenterScript.describe_concentration(suggested),
		"Accept",
		func() -> void:
			var classification: String = String(suggested.get("classification", ""))
			var quadrant: String = String(suggested.get("quadrant", ""))
			_suggestions.erase("concentration")
			if not quadrant.is_empty() and not classification.is_empty():
				_record.classify_concentration(quadrant, classification)
			_emit_and_refresh()
	)


func _on_concentration_selected(item_index: int) -> void:
	if item_index <= 0:
		return
	var dominant: String = String(_findings.get("dominant_quadrant", ""))
	if dominant.is_empty():
		return
	var classification_id: String = DiagnosticsScript.CONCENTRATION_CLASSIFICATIONS[item_index - 1]
	if bool(_record.classify_concentration(dominant, classification_id).get("changed", false)):
		_emit_and_refresh()


## Clears the four answers and the checkboxes showing them. Called when the quadrant changes
## and after a debt is recorded, so the next absence starts from unanswered.
func _reset_debt_conditions() -> void:
	_debt_conditions = {}
	_rebuild_debt_conditions()


func _sync_debt() -> void:
	var status_label: Label = _node("%DebtStatus") as Label
	if not status_label:
		return
	var debt_entries: Array = _record.get_debt()
	if debt_entries.is_empty():
		status_label.text = "No closure debt recorded."
		return
	var quadrants: Array[String] = []
	for entry_any: Variant in debt_entries:
		quadrants.append(String((entry_any as Dictionary).get("quadrant", "")))
	status_label.text = "Closure debt in %s." % ClosureOrientationScript.join_canonical_terms(
		quadrants, " and "
	)


func _on_debt_recorded() -> void:
	var picker_node: OptionButton = _node("%DebtQuadrantPicker") as OptionButton
	if not picker_node or picker_node.selected < 0:
		return
	var quadrant_id: String = ClosureOrientationScript.QUADRANTS[picker_node.selected]
	var result: Dictionary = _record.record_debt(quadrant_id, _debt_conditions)
	var status_label: Label = _node("%DebtStatus") as Label
	if not bool(result.get("recorded", false)):
		if status_label:
			# The unanswered questions are full sentences, so they need a separator that reads
			# as a list. Joined by spaces they ran together into one unreadable paragraph.
			var unmet: Array = result.get("unmet", [])
			status_label.text = (
				"Not debt yet. All four have to be true. Still unanswered: %s"
				% " / ".join(PackedStringArray(unmet))
			)
		return
	_reset_debt_conditions()
	_emit_and_refresh()


## The step asks for the move from the quadrant carrying the weight to one the room has
## neglected. Nothing enforced that direction, and nothing pointed at it either: both pickers
## opened on whatever they happened to be showing, so the commonest press named an edge the
## map gave no reason to name. The reading already knows which quadrant dominates and which
## are thin, so it can set the pickers there and let the room override it.
func _preselect_transition_from_reading() -> void:
	if _transition_pickers_touched or not _record.get_required_transition().is_empty():
		return
	var from_picker: OptionButton = _node("%TransitionFromPicker") as OptionButton
	var to_picker: OptionButton = _node("%TransitionToPicker") as OptionButton
	if not from_picker or not to_picker:
		return
	var dominant: String = String(_findings.get("dominant_quadrant", ""))
	var thin_quadrants: Array[String] = get_thin_quadrants()
	if dominant.is_empty() or thin_quadrants.is_empty():
		return
	var from_index: int = ClosureOrientationScript.QUADRANTS.find(dominant)
	var to_index: int = ClosureOrientationScript.QUADRANTS.find(thin_quadrants[0])
	if from_index < 0 or to_index < 0 or from_index == to_index:
		return
	from_picker.select(from_index)
	to_picker.select(to_index)


func _sync_transition() -> void:
	var status_label: Label = _node("%TransitionStatus") as Label
	if not status_label:
		return
	_preselect_transition_from_reading()
	var transition: Dictionary = _record.get_required_transition()
	if transition.is_empty():
		status_label.tooltip_text = ""
		var from_picker: OptionButton = _node("%TransitionFromPicker") as OptionButton
		var to_picker: OptionButton = _node("%TransitionToPicker") as OptionButton
		if from_picker and to_picker and from_picker.selected >= 0 and to_picker.selected >= 0:
			var from_quadrant: String = ClosureOrientationScript.QUADRANTS[from_picker.selected]
			var to_quadrant: String = ClosureOrientationScript.QUADRANTS[to_picker.selected]
			var transformation: String = DiagnosticsScript.describe_transition_edge(
				from_quadrant, to_quadrant
			)
			if transformation.is_empty():
				status_label.text = "Pick two different quadrants."
				return
			status_label.text = "That move means: %s" % transformation
			# A warning, not a refusal. The record stays permissive about order and choice; the
			# room may have a reason to name an edge the map did not point at, and it should be
			# told that is what it is doing rather than stopped.
			var unusual: String = _describe_unusual_transition(from_quadrant, to_quadrant)
			if not unusual.is_empty():
				status_label.text += "\n%s" % unusual
			return
		status_label.text = "No move named yet."
		return
	status_label.text = String(transition.get("summary", ""))
	status_label.tooltip_text = String(transition.get("transformation", ""))


## Empty when the chosen edge runs from the dominant quadrant into a thin one, which is what
## the step is for.
func _describe_unusual_transition(from_quadrant: String, to_quadrant: String) -> String:
	var dominant: String = String(_findings.get("dominant_quadrant", ""))
	var thin_quadrants: Array[String] = get_thin_quadrants()
	if dominant.is_empty() and thin_quadrants.is_empty():
		return ""
	if not dominant.is_empty() and from_quadrant != dominant:
		return "Most claims are in %s, not %s." % [
			ClosureOrientationScript.get_canonical_term(dominant),
			ClosureOrientationScript.get_canonical_term(from_quadrant),
		]
	if not thin_quadrants.is_empty() and to_quadrant not in thin_quadrants:
		return "%s is not one of the near-empty quadrants (%s)." % [
			ClosureOrientationScript.get_canonical_term(to_quadrant),
			ClosureOrientationScript.join_canonical_terms(thin_quadrants),
		]
	return ""


func _on_transition_set() -> void:
	var from_picker: OptionButton = _node("%TransitionFromPicker") as OptionButton
	var to_picker: OptionButton = _node("%TransitionToPicker") as OptionButton
	var action_input: LineEdit = _node("%TransitionActionInput") as LineEdit
	if not from_picker or not to_picker or not action_input:
		return
	var result: Dictionary = _record.set_required_transition(
		ClosureOrientationScript.QUADRANTS[from_picker.selected],
		ClosureOrientationScript.QUADRANTS[to_picker.selected],
		action_input.text
	)
	var status_label: Label = _node("%TransitionStatus") as Label
	if not bool(result.get("ok", false)):
		if status_label:
			status_label.text = (
				"Needs two different quadrants and something to do about it."
			)
		return
	_emit_and_refresh()


func _render_transition_suggestion() -> void:
	var suggested: Dictionary = _suggestions.get("transition", {})
	_render_suggestion(
		"%TransitionSuggestion",
		"transition",
		SuggestionPresenterScript.describe_transition(suggested),
		"Accept",
		func() -> void:
			var from_quadrant: String = String(suggested.get("from", ""))
			var to_quadrant: String = String(suggested.get("to", ""))
			var action_text: String = String(suggested.get("action", ""))
			_suggestions.erase("transition")
			# The pickers and the field are set as well as the record, so an accepted draft can
			# be adjusted and set again rather than only replaced from scratch.
			var from_picker: OptionButton = _node("%TransitionFromPicker") as OptionButton
			var to_picker: OptionButton = _node("%TransitionToPicker") as OptionButton
			var action_input: LineEdit = _node("%TransitionActionInput") as LineEdit
			if from_picker and to_picker:
				_transition_pickers_touched = true
				from_picker.select(ClosureOrientationScript.QUADRANTS.find(from_quadrant))
				to_picker.select(ClosureOrientationScript.QUADRANTS.find(to_quadrant))
			if action_input:
				action_input.text = action_text
			_record.set_required_transition(from_quadrant, to_quadrant, action_text)
			_emit_and_refresh()
	)


## Drafted actions fill the fields rather than the register: an action needs an owner and a
## date, which only the room can give, so accepting one has to end at a half-filled form the
## facilitator completes. Writing it straight to the record is not available — the record
## refuses an action without a commitment, and rightly.
func _render_action_suggestions() -> void:
	var host_node: Node = _node("%ActionSuggestion")
	if not host_node:
		return
	_clear_children(host_node)
	var suggested_actions: Array = _suggestions.get("reopening_actions", [])
	for index: int in suggested_actions.size():
		var action_any: Variant = suggested_actions[index]
		if typeof(action_any) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = action_any
		host_node.add_child(SuggestionPresenterScript.build_strip(
			SuggestionPresenterScript.describe_action(action),
			"Fill in",
			func() -> void: _fill_action_fields(action),
			func() -> void: _dismiss_action_suggestion(index)
		))


func _fill_action_fields(action: Dictionary) -> void:
	var action_input: LineEdit = _node("%ActionInput") as LineEdit
	var falsifier_input: LineEdit = _node("%ActionFalsifierInput") as LineEdit
	if action_input:
		action_input.text = String(action.get("action", ""))
	if falsifier_input:
		falsifier_input.text = String(action.get("falsifier", ""))
	var status_label: Label = _node("%ActionStatus") as Label
	if status_label:
		status_label.text = "Add an owner and a date, then press Add reopening action."


func _dismiss_action_suggestion(index: int) -> void:
	var suggested_actions: Array = _suggestions.get("reopening_actions", [])
	if index < 0 or index >= suggested_actions.size():
		return
	suggested_actions.remove_at(index)
	if suggested_actions.is_empty():
		_suggestions.erase("reopening_actions")
	refresh(_findings)


func _rebuild_action_list() -> void:
	var list_node: Node = _node("%ActionList")
	if not list_node:
		return
	_clear_children(list_node)
	for action_any: Variant in _record.get_reopening_actions():
		var action: Dictionary = action_any
		var action_label: Label = SuggestionPresenterScript.build_body_note("%s — %s, by %s" % [
			String(action.get("action", "")),
			String(action.get("owner", "")),
			String(action.get("due_date", "")),
		])
		action_label.tooltip_text = (
			"What would change the decision: %s" % String(action.get("falsifier", ""))
		)
		list_node.add_child(action_label)


func _on_action_added() -> void:
	var action_input: LineEdit = _node("%ActionInput") as LineEdit
	var owner_input: LineEdit = _node("%ActionOwnerInput") as LineEdit
	var date_input: LineEdit = _node("%ActionDateInput") as LineEdit
	var falsifier_input: LineEdit = _node("%ActionFalsifierInput") as LineEdit
	if not action_input or not owner_input or not date_input or not falsifier_input:
		return
	var result: Dictionary = _record.add_reopening_action(
		action_input.text, owner_input.text, date_input.text, falsifier_input.text
	)
	# Beside the fields it is about. This used to write into the completion gate at the top of
	# the panel, which both put the message where the facilitator was not looking and lost it
	# on the next refresh, since the gate rewrites itself from the record every time.
	var status_label: Label = _node("%ActionStatus") as Label
	if not bool(result.get("ok", false)):
		if status_label:
			var missing: Array = result.get("missing", [])
			status_label.text = (
				"Still needs %s." % " and ".join(PackedStringArray(missing))
				if not missing.is_empty()
				else "Say what has to be done."
			)
		return
	if status_label:
		status_label.text = ""
	action_input.text = ""
	owner_input.text = ""
	date_input.text = ""
	falsifier_input.text = ""
	_emit_and_refresh()


func _sync_gate_status() -> void:
	var gate_label: Label = _node("%AuditGateStatus") as Label
	if not gate_label:
		return
	# The threshold falls back to the rules module's own constant, not to 0. Defaulting a
	# missing key to 0 would make the gate permissive whenever findings arrived incomplete,
	# which is the same shape as the bug this gate exists to close.
	var gaps: Array[String] = _record.describe_completion_gaps(
		get_thin_quadrants(),
		int(_findings.get("tagged_count", 0)),
		int(_findings.get(
			"min_tagged_for_reading", RulesScript.MIN_TAGGED_FOR_READING
		)),
		String(_findings.get("dominant_quadrant", ""))
	)
	if gaps.is_empty():
		gate_label.text = "Done. Nothing on this map is left unexplained."
		return
	gate_label.text = "Still to do: %s." % "; ".join(gaps)


func set_route_status(status_text: String) -> void:
	var status_label: Label = _node("%RouteStatus") as Label
	if status_label:
		status_label.text = status_text


func _emit_and_refresh() -> void:
	state_changed.emit(_record.get_state())
	refresh(_findings)


## The rules module's `has_reading`: whether enough claims are oriented to say anything about
## coverage at all. Absent from the findings only before the first refresh, and treating that
## as readable would reintroduce the trivially-complete audit.
func _is_map_readable() -> bool:
	return bool(_findings.get("has_reading", false))


func _node(unique_path: String) -> Node:
	return _panel_node.get_node_or_null(unique_path) if _panel_node else null


## Detaches before freeing. `queue_free` alone runs at frame end, so a list rebuilt during a
## refresh would hold its old rows and its new ones simultaneously.
func _clear_children(parent_node: Node) -> void:
	if not parent_node:
		return
	for child_node: Node in parent_node.get_children():
		parent_node.remove_child(child_node)
		child_node.queue_free()
