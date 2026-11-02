extends RefCounted
class_name WorkshopOrientationPresenter

## Purpose: how a claim's Closure Map orientation appears on its card, and how a
## model's suggestion appears beside it.
##
## Split out of `workshop_thinking_map_controller.gd`, which owns the map's domain
## actions — proposing, reviewing, committing, routing to the Session Record.
## Orientation display carries no such authority: every path through here ends in the
## controller's own `orient_item`, passed in as a Callable. Keeping it separate also
## keeps the wording of the audit's four quadrants in one place, next to the
## vocabulary it renders, rather than inside a 1000-line controller.

const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)


## `suggestions` maps record ids to a suggested quadrant; `declined_ids` lists the
## claims a model said no quadrant fits. Both are absent outside an audit.
static func bind_card(
	card_node: Control,
	node_data: Dictionary,
	record_id: String,
	is_audit_active: bool,
	suggestions: Dictionary,
	declined_ids: Array,
	orient_callable: Callable,
	contest_callable: Callable,
	are_views_revealed: bool
) -> void:
	var row_node: Control = card_node.get_node_or_null("%OrientationRow") as Control
	var option_node: OptionButton = (
		card_node.get_node_or_null("%OrientationOption") as OptionButton
	)
	if not row_node or not option_node:
		return
	row_node.visible = is_audit_active
	if not is_audit_active:
		return
	option_node.clear()
	option_node.add_item("Untagged", 0)
	option_node.set_item_tooltip(
		0,
		"No quadrant recorded. This is always a valid answer. An empty quadrant only"
		+ " counts as a gap once the audit says why it is empty."
	)
	for quadrant_index: int in range(ClosureOrientationScript.QUADRANTS.size()):
		var quadrant_id: String = ClosureOrientationScript.QUADRANTS[quadrant_index]
		# Plain name in the list, canonical term in the tooltip: the picker is used
		# on every card under time pressure, so it must not require the manual.
		option_node.add_item(
			ClosureOrientationScript.get_plain_name(quadrant_id),
			quadrant_index + 1
		)
		option_node.set_item_tooltip(
			quadrant_index + 1,
			ClosureOrientationScript.get_quadrant_help(quadrant_id)
		)
	# An untagged node finds nothing, giving -1 + 1 = 0, the Untagged row.
	var current_quadrant: String = ClosureOrientationScript.get_node_quadrant(node_data)
	# Assigning `selected` does not emit item_selected, so rebuilding a card
	# cannot loop back into a write.
	option_node.selected = ClosureOrientationScript.QUADRANTS.find(current_quadrant) + 1
	option_node.item_selected.connect(
		func(selected_index: int) -> void:
			var selected_quadrant: String = ""
			if selected_index > 0:
				selected_quadrant = ClosureOrientationScript.QUADRANTS[selected_index - 1]
			orient_callable.call(record_id, selected_quadrant)
	)
	_bind_suggestion(
		card_node,
		record_id,
		current_quadrant,
		suggestions,
		declined_ids,
		orient_callable
	)
	_bind_contested(card_node, node_data, record_id, contest_callable)
	bind_view_spread(card_node, node_data, are_views_revealed)


## The card's answer to "is this one disputed", in as little space as a card can spare.
## The session-level question — which claims did the room turn out not to share — is not
## answerable here and belongs to the review panel.
##
## Before reveal it shows only how many people have entered a view, never which. Showing
## the spread early would destroy what private entry buys: a participant who can see that
## three others said C is no longer recording an independent reading, and a facilitator who
## can see it is no longer tagging independently either.
static func bind_view_spread(
	card_node: Control,
	node_data: Dictionary,
	are_views_revealed: bool
) -> void:
	var spread_label_node: Label = card_node.get_node_or_null("%ViewSpreadLabel") as Label
	if not spread_label_node:
		return
	var positions: Array = ClosureOrientationScript.get_positions(
		node_data, ClosureOrientationScript.DIMENSION_PLACEMENT
	)
	if positions.is_empty():
		spread_label_node.visible = false
		return
	spread_label_node.visible = true
	if not are_views_revealed:
		spread_label_node.text = "%d view(s) entered" % positions.size()
		spread_label_node.tooltip_text = (
			"Views stay closed until you reveal them, so each is recorded independently."
		)
		return
	spread_label_node.text = format_spread(node_data)
	spread_label_node.tooltip_text = format_positions_detail(node_data)


## Counts per quadrant in canonical order, e.g. "views A·2 C·3". Reads as a distribution
## rather than a verdict, which is deliberate: there is no winner here, and a claim where
## three say C and two say A is contested rather than "mostly C".
static func format_spread(node_data: Dictionary) -> String:
	var counts: Dictionary = {}
	for position_any: Variant in ClosureOrientationScript.get_positions(
		node_data, ClosureOrientationScript.DIMENSION_PLACEMENT
	):
		var view_text: String = String((position_any as Dictionary).get("view", "")).strip_edges()
		if not view_text.is_empty():
			counts[view_text] = int(counts.get(view_text, 0)) + 1
	var parts: Array[String] = []
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		if counts.has(quadrant_id):
			parts.append("%s·%d" % [quadrant_id, int(counts[quadrant_id])])
	if parts.is_empty():
		return ""
	var prefix: String = "split" if parts.size() > 1 else "agreed"
	return "%s %s" % [prefix, " ".join(parts)]


## Names who holds what, because the register's job is to make a disagreement actionable
## and "what test would discriminate?" cannot be asked of anonymous counts.
static func format_positions_detail(node_data: Dictionary) -> String:
	var lines: Array[String] = []
	for position_any: Variant in ClosureOrientationScript.get_positions(
		node_data, ClosureOrientationScript.DIMENSION_PLACEMENT
	):
		var position: Dictionary = position_any
		var holder: String = String(position.get("held_by", "")).strip_edges()
		var view_text: String = String(position.get("view", "")).strip_edges()
		var evidence: String = String(position.get("evidence", "")).strip_edges()
		var line: String = "%s: %s" % [holder, ClosureOrientationScript.get_canonical_with_gloss(view_text)]
		if evidence.is_empty():
			line += " — no evidence recorded"
		else:
			line += " — %s" % evidence
		if String(position.get("review_status", "")) != "reviewed":
			line += " (unreviewed)"
		lines.append(line)
	return "\n".join(lines)


## The contested marker records that the room split, which the facilitator's single
## closing tag cannot express on its own.
static func _bind_contested(
	card_node: Control,
	node_data: Dictionary,
	record_id: String,
	contest_callable: Callable
) -> void:
	var contested_check_node: CheckBox = (
		card_node.get_node_or_null("%OrientationContestedCheck") as CheckBox
	)
	if not contested_check_node:
		return
	contested_check_node.visible = true
	# Setting `button_pressed` would emit `toggled` and write straight back on every
	# card rebuild.
	contested_check_node.set_pressed_no_signal(
		ClosureOrientationScript.is_orientation_contested(node_data)
	)
	contested_check_node.toggled.connect(
		func(is_pressed: bool) -> void:
			contest_callable.call(record_id, is_pressed)
	)


## Shows what the model proposed for this claim, with one click to take it. The
## dropdown is deliberately left untouched: pre-selecting a suggestion would make the
## card look tagged when nothing has been recorded, and a facilitator scrolling past
## would leave behind orientations nobody decided.
static func _bind_suggestion(
	card_node: Control,
	record_id: String,
	current_quadrant: String,
	suggestions: Dictionary,
	declined_ids: Array,
	orient_callable: Callable
) -> void:
	var suggestion_label_node: Label = (
		card_node.get_node_or_null("%OrientationSuggestionLabel") as Label
	)
	var accept_button_node: Button = (
		card_node.get_node_or_null("%OrientationAcceptButton") as Button
	)
	if not suggestion_label_node or not accept_button_node:
		return
	var has_declined: bool = declined_ids.has(record_id)
	var suggested_quadrant: String = str(suggestions.get(record_id, ""))
	suggestion_label_node.visible = has_declined or not suggested_quadrant.is_empty()
	# Nothing to accept once the claim carries the suggested quadrant already, and
	# nothing to accept when the model declined: declining proposes no tag.
	accept_button_node.visible = (
		not suggested_quadrant.is_empty() and suggested_quadrant != current_quadrant
	)
	if has_declined:
		suggestion_label_node.text = "AI: none of these applies"
		suggestion_label_node.tooltip_text = (
			"The model found no quadrant that fits this claim. That is a complete"
			+ " answer rather than a gap, but it is only the model's reading and yours"
			+ " may differ. Nothing is recorded either way."
		)
		return
	if suggested_quadrant.is_empty():
		return
	suggestion_label_node.text = "AI: %s" % ClosureOrientationScript.get_plain_name(
		suggested_quadrant
	)
	suggestion_label_node.tooltip_text = (
		"This is a suggestion. The claim stays untagged until you accept it or pick a"
		+ " different quadrant.\n\n"
		+ ClosureOrientationScript.get_quadrant_help(suggested_quadrant)
	)
	accept_button_node.pressed.connect(
		func() -> void:
			orient_callable.call(record_id, suggested_quadrant)
	)


static func apply_suggest_button(
	panel_node: Control,
	is_audit_active: bool,
	is_awaiting: bool
) -> void:
	var suggest_button_node: Button = (
		panel_node.get_node_or_null("%SuggestOrientationsButton") as Button
	)
	if not suggest_button_node:
		return
	suggest_button_node.visible = is_audit_active
	suggest_button_node.disabled = is_awaiting


## Why a suggestion pass has nothing to do. Two opposite situations reach this point as the
## same empty candidate list, and only one of them is "the room has finished orienting" —
## reporting that for an empty map put "Every claim is already oriented" in the footer
## directly beside "Closure: no claims oriented yet".
##
## A separate function rather than a branch inside the button handler so the wording can be
## asserted without a mounted map and a facilitator claim.
static func format_nothing_to_suggest(orientable_claim_count: int) -> String:
	if orientable_claim_count <= 0:
		return "No claims on the map yet, so there is nothing to orient."
	return "Every claim is already oriented, so there is nothing to suggest."
