extends RefCounted
class_name WorkshopViewsReviewPresenter

## The session-level reading of recorded orientation views: not "is this claim disputed",
## which a card can answer, but *which claims the room turned out not to share*, which no
## single card can. A room that agrees on nineteen claims and splits on one has a different
## problem from a room that splits on twelve, and only the ordered list shows which it is.
##
## Ordering, not filtering. Claims where views agree stay in the list below the divided
## ones, because "we all read this the same way" is also a finding — and a list that showed
## only disagreements would make a well-aligned room look like it had done no work.

const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)
const OrientationPresenterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_orientation_presenter.gd"
)
const ContestationRegisterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_contestation_register.gd"
)

const _INACTIVE_STATUSES: Array[String] = ["rejected"]


## Builds the ordered reading. Pure, so it can be asserted headlessly where the controller
## cannot be instantiated at all (ADR 0017 rule 6).
##
## Most divided first, by distinct views and then by how many people weighed in: a
## three-way split matters more than a two-way one, and a two-way split among six people
## matters more than the same split among two. Claims marked contested by the facilitator
## but carrying no views sort with the divided ones, since they are contested on the
## facilitator's word and the absence of views is not evidence of agreement.
static func build_rows(document: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var nodes_any: Variant = document.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		return rows
	for node_any: Variant in (nodes_any as Array):
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		if String(node_data.get("status", "")) in _INACTIVE_STATUSES:
			continue
		var positions: Array = ClosureOrientationScript.get_positions(
			node_data, ClosureOrientationScript.DIMENSION_PLACEMENT
		)
		var is_asserted: bool = ClosureOrientationScript.has_asserted_contested(node_data)
		if positions.is_empty() and not is_asserted:
			continue
		var distinct_views: int = ClosureOrientationScript.get_distinct_views(
			node_data, ClosureOrientationScript.DIMENSION_PLACEMENT
		).size()
		rows.append({
			"record_id": String(node_data.get("id", "")),
			"label": String(node_data.get("label", "")),
			"quadrant": ClosureOrientationScript.get_node_quadrant(node_data),
			"distinct_views": distinct_views,
			"holder_count": positions.size(),
			"is_contested": ClosureOrientationScript.is_orientation_contested(node_data),
			"is_asserted": is_asserted,
			"spread": OrientationPresenterScript.format_spread(node_data),
			"detail": OrientationPresenterScript.format_positions_detail(node_data),
			"gaps": ContestationRegisterScript.describe_gaps(
				node_data, ClosureOrientationScript.DIMENSION_PLACEMENT
			),
		})
	rows.sort_custom(_more_divided_first)
	return rows


static func _more_divided_first(left: Dictionary, right: Dictionary) -> bool:
	var left_views: int = int(left.get("distinct_views", 0))
	var right_views: int = int(right.get("distinct_views", 0))
	# An asserted mark with no views still ranks as a split, so it is not sorted below
	# claims whose recorded views happen to agree.
	if left_views <= 1 and bool(left.get("is_asserted", false)):
		left_views = 2
	if right_views <= 1 and bool(right.get("is_asserted", false)):
		right_views = 2
	if left_views != right_views:
		return left_views > right_views
	return int(left.get("holder_count", 0)) > int(right.get("holder_count", 0))


## Fills the list and the reveal row. Rows are built in code because their number and
## content are only known at runtime; the panel's own structure lives in the scene.
static func populate(
	panel_node: Control,
	document: Dictionary,
	are_views_revealed: bool,
	may_reveal: bool
) -> void:
	var list_node: Node = panel_node.get_node_or_null("%ViewsReviewList")
	if not list_node:
		return
	for child_node: Node in list_node.get_children():
		child_node.queue_free()
	var rows: Array[Dictionary] = build_rows(document)
	_update_reveal_row(panel_node, rows, are_views_revealed, may_reveal)
	if rows.is_empty():
		# Without the leading repetition: the status label beside the Reveal button already
		# says "No views recorded yet", and the two sat one line apart.
		list_node.add_child(_body_label(
			"Participants can record where they think each claim sits; nobody sees anyone"
			+ " else's until you reveal them."
		))
		return
	if not are_views_revealed:
		list_node.add_child(_body_label(
			"%d claim(s) have views recorded. They stay closed until you reveal them, so"
			% rows.size()
			+ " nobody's reading is swayed by seeing someone else's first."
		))
		return
	for row: Dictionary in rows:
		list_node.add_child(_row_control(row))


static func _update_reveal_row(
	panel_node: Control,
	rows: Array[Dictionary],
	are_views_revealed: bool,
	may_reveal: bool
) -> void:
	var reveal_button_node: Button = panel_node.get_node_or_null("%RevealViewsButton") as Button
	var status_label_node: Label = panel_node.get_node_or_null("%ViewsRevealStatus") as Label
	var holder_total: int = 0
	var divided_total: int = 0
	for row: Dictionary in rows:
		holder_total += int(row.get("holder_count", 0))
		if bool(row.get("is_contested", false)):
			divided_total += 1
	if reveal_button_node:
		reveal_button_node.visible = not are_views_revealed
		reveal_button_node.disabled = not may_reveal or rows.is_empty()
	if not status_label_node:
		return
	if rows.is_empty():
		status_label_node.text = "No views recorded yet."
	elif not are_views_revealed:
		status_label_node.text = (
			"%d view(s) across %d claim(s), still closed." % [holder_total, rows.size()]
		)
	elif divided_total == 0:
		status_label_node.text = (
			"%d claim(s) with views, and everyone read them the same way."
			% rows.size()
		)
	else:
		status_label_node.text = (
			"%d of %d claim(s) with views are read differently." % [divided_total, rows.size()]
		)


static func _row_control(row: Dictionary) -> Control:
	var row_box := VBoxContainer.new()
	var heading := Label.new()
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tag_text: String = String(row.get("quadrant", ""))
	var tagged_as: String = (
		"tagged %s" % tag_text if not tag_text.is_empty() else "not yet tagged"
	)
	heading.text = "%s — %s, %s" % [
		String(row.get("label", "")),
		String(row.get("spread", "no views")),
		tagged_as,
	]
	heading.tooltip_text = String(row.get("detail", ""))
	row_box.add_child(heading)
	var detail_text: String = String(row.get("detail", ""))
	if not detail_text.is_empty():
		row_box.add_child(_body_label(detail_text))
	if bool(row.get("is_asserted", false)) and int(row.get("distinct_views", 0)) <= 1:
		row_box.add_child(_body_label(
			"Marked contested in discussion; no views recorded to show the split."
		))
	var gaps: Array = row.get("gaps", [])
	if not gaps.is_empty():
		row_box.add_child(_body_label(
			"Still needed: %s." % ", ".join(PackedStringArray(gaps))
		))
	return row_box


static func _body_label(text_value: String) -> Label:
	var body_label := Label.new()
	body_label.text = text_value
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 11)
	return body_label
