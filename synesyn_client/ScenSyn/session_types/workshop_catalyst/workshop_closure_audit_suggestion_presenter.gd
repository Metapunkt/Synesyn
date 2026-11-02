extends RefCounted
class_name WorkshopClosureAuditSuggestionPresenter

## Renders a model-drafted answer as something to accept, edit or dismiss (REQ-CA-021).
##
## Separate from the audit controller because the controller is already at its useful size and
## this is presentation only: it reads a suggestion, returns a strip of widgets, and calls back.
## It never touches `WorkshopClosureAuditRecord`, so a suggestion cannot become an answer by
## being displayed.
##
## Every strip says "Suggested" and carries the model's reason. Both matter. Without the label
## an accepted draft becomes indistinguishable from a judgement the room reached, which is the
## failure the audit exists to prevent; without the reason there is nothing to review, and
## "accept" degrades into "dismiss the panel".

const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)
const DiagnosticsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_diagnostics.gd"
)

const SUGGESTION_FONT_SIZE: int = 11
## Grey-blue, distinct from the panel's own body text at a glance without relying on the
## wording alone.
const SUGGESTION_COLOR := Color(0.32, 0.36, 0.52)


## A wrapping body label. Every runtime label in the audit panel needs both the autowrap and
## the expand flag: the panel sits in a map column's width, and a label without them is what
## rendered the concentration prompt as a one-character-wide vertical stack.
static func build_body_note(note_text: String) -> Label:
	var note_label := Label.new()
	note_label.text = note_text
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_label.add_theme_font_size_override("font_size", SUGGESTION_FONT_SIZE)
	return note_label


## One of the two triage axes. The prompt is short enough to sit in a map column; the sentence
## saying which axis this is moves to the tooltip, because an OptionButton's minimum width is
## set by its longest item however `clip_text` is set.
static func build_band_picker(
	prompt_text: String,
	prompt_help: String,
	selected_band: String,
	on_band: Callable
) -> OptionButton:
	var picker := OptionButton.new()
	picker.clip_text = true
	picker.tooltip_text = prompt_help
	picker.add_theme_font_size_override("font_size", SUGGESTION_FONT_SIZE)
	picker.add_item(prompt_text, -1)
	picker.set_item_disabled(0, true)
	var selected_index: int = 0
	for index: int in DiagnosticsScript.TRIAGE_BANDS.size():
		var band_id: String = DiagnosticsScript.TRIAGE_BANDS[index]
		picker.add_item(band_id.capitalize())
		if band_id == selected_band:
			selected_index = index + 1
	picker.select(selected_index)
	picker.item_selected.connect(
		func(item_index: int) -> void:
			if item_index > 0:
				on_band.call(DiagnosticsScript.TRIAGE_BANDS[item_index - 1])
	)
	return picker


## A wrapping "Suggested: …" line with an accept button, and a dismiss button when the caller
## wants one. Returned as a VBox so the text is never squeezed to a column of single
## characters by a button beside it, which is what a row does at this panel's width.
static func build_strip(
	body_text: String,
	accept_text: String,
	on_accept: Callable,
	on_dismiss: Callable = Callable()
) -> Control:
	var strip_box := VBoxContainer.new()
	strip_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_box.add_theme_constant_override("separation", 2)
	var body_label := Label.new()
	body_label.text = "Suggested: %s" % body_text
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_label.add_theme_font_size_override("font_size", SUGGESTION_FONT_SIZE)
	body_label.add_theme_color_override("font_color", SUGGESTION_COLOR)
	strip_box.add_child(body_label)
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 6)
	var accept_button := Button.new()
	accept_button.text = accept_text
	accept_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	accept_button.add_theme_font_size_override("font_size", SUGGESTION_FONT_SIZE)
	accept_button.pressed.connect(on_accept)
	button_row.add_child(accept_button)
	if on_dismiss.is_valid():
		var dismiss_button := Button.new()
		dismiss_button.text = "Dismiss"
		dismiss_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dismiss_button.add_theme_font_size_override("font_size", SUGGESTION_FONT_SIZE)
		dismiss_button.tooltip_text = (
			"Drops this draft without answering the step. The step stays open."
		)
		dismiss_button.pressed.connect(on_dismiss)
		button_row.add_child(dismiss_button)
	strip_box.add_child(button_row)
	return strip_box


## "Unknown — nobody raised what the sector already knows. Cost if it matters: high;
## confidence it does not: low."
static func describe_absence(absence: Dictionary) -> String:
	var classification: String = String(absence.get("classification", ""))
	var described: String = String(
		DiagnosticsScript.ABSENCE_LABELS.get(classification, classification)
	)
	var reason: String = String(absence.get("reason", ""))
	if not reason.is_empty():
		described += " — %s" % reason
	var consequence: String = String(absence.get("consequence", ""))
	var confidence: String = String(absence.get("confidence", ""))
	if not consequence.is_empty() and not confidence.is_empty():
		described += " Cost if it matters: %s. Sure it doesn't: %s." % [
			consequence, confidence
		]
	return described


static func describe_concentration(concentration: Dictionary) -> String:
	var classification: String = String(concentration.get("classification", ""))
	var described: String = String(
		DiagnosticsScript.CONCENTRATION_LABELS.get(classification, classification)
	)
	var reason: String = String(concentration.get("reason", ""))
	if not reason.is_empty():
		described += " — %s" % reason
	return described


static func describe_transition(transition: Dictionary) -> String:
	return "%s → %s, by %s" % [
		ClosureOrientationScript.get_canonical_term(String(transition.get("from", ""))),
		ClosureOrientationScript.get_canonical_term(String(transition.get("to", ""))),
		String(transition.get("action", "")),
	]


## Actions arrive without an owner or a date, so the strip says so rather than leaving the
## facilitator to discover it when the record refuses the entry.
static func describe_action(action: Dictionary) -> String:
	return "%s Settled by: %s You add the owner and the date." % [
		String(action.get("action", "")),
		String(action.get("falsifier", "")),
	]
