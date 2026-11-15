extends RefCounted
## Month-view calendar day card helpers (merge same-task kinds, labels, tooltips).


static func merge_day_task_events(events: Array) -> Array:
	"""Collapse multiple date-kind events for the same task on one day into one entry."""
	var merged: Array = []
	var index_by_key: Dictionary = {}
	for event_any in events:
		if typeof(event_any) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_any
		var task: WorkplanTask = event.get("task") as WorkplanTask
		if task == null:
			continue
		task.ensure_task_id()
		var key: String = task.task_id if not task.task_id.is_empty() else task.title
		var kind: String = String(event.get("type", "deadline"))
		if index_by_key.has(key):
			var existing: Dictionary = merged[int(index_by_key[key])]
			var types: Array = existing.get("types", [])
			if not types.has(kind):
				types.append(kind)
			existing["types"] = types
			existing["type"] = preferred_calendar_date_type(types)
		else:
			index_by_key[key] = merged.size()
			merged.append({"task": task, "type": kind, "types": [kind]})
	return merged


static func preferred_calendar_date_type(kinds: Array) -> String:
	"""Drag primary: publish > deadline > start."""
	if kinds.has("publish"):
		return "publish"
	if kinds.has("deadline"):
		return "deadline"
	if kinds.has("start"):
		return "start"
	return "deadline"


static func format_calendar_kind_label(kinds: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for kind_any in kinds:
		parts.append(String(kind_any))
	return "+".join(parts)


static func calendar_kind_icons(kinds: Array) -> String:
	var icons: String = ""
	for kind_any in kinds:
		match String(kind_any):
			"start":
				icons += "🚀"
			"publish":
				icons += "📢"
			_:
				icons += "🎯"
	return icons if not icons.is_empty() else "🎯"


static func build_tooltip(
	task: WorkplanTask,
	kinds: Array,
	day_date: String,
	primary_type: String,
	is_blocked: bool,
	workplan: Resource = null
) -> String:
	var kind_label_text: String = format_calendar_kind_label(kinds)
	var block_note: String = "\nBlocked: predecessors not Done" if is_blocked else ""
	var tip: String = "%s\nKind: %s" % [task.title, kind_label_text]
	var has_concrete_date := false
	if kinds.has("start") and not task.start_date.is_empty():
		tip += "\nStart: %s" % task.start_date.substr(0, 10)
		has_concrete_date = true
	if kinds.has("deadline") and not task.deadline.is_empty():
		tip += "\nDeadline: %s" % task.deadline.substr(0, 10)
		has_concrete_date = true
	if kinds.has("publish"):
		const PublishTimeScript = preload("res://readymade/scripts/workplan_publish_time.gd")
		var publish_label: String = PublishTimeScript.format_publish_label(task, workplan)
		if publish_label.is_empty() and not task.publish_date.is_empty():
			publish_label = task.publish_date.substr(0, 10)
		if publish_label.is_empty() and not day_date.is_empty():
			publish_label = day_date
		if not publish_label.is_empty():
			tip += "\nPublish: %s" % publish_label
			has_concrete_date = true
	if not has_concrete_date and not day_date.is_empty():
		tip += "\nDate: %s" % day_date
	tip += "\nStatus: %s\nPriority: %d%s\n🎯 Drag moves %s\n🖱️ Right-click for Move / Undo / Copy\n📝 Double-click to edit" % [
		task.status, task.priority, block_note, primary_type
	]
	return tip


static func create_month_card(
	task: WorkplanTask,
	date_type: String,
	date_types: Array,
	day_date: String,
	is_blocked: bool,
	workplan: Resource = null
) -> PanelContainer:
	"""Compact month-cell card with kind icons/label and full-title tooltip."""
	var kinds: Array = date_types if not date_types.is_empty() else [date_type]
	var primary_type: String = preferred_calendar_date_type(kinds)
	if primary_type.is_empty():
		primary_type = date_type
	var kind_label_text: String = format_calendar_kind_label(kinds)
	var tip: String = build_tooltip(task, kinds, day_date, primary_type, is_blocked, workplan)

	var card := PanelContainer.new()
	card.name = "TaskCard_%s_%s" % [task.title.replace(" ", "_"), kind_label_text]
	card.custom_minimum_size = Vector2(0, 20)
	# STOP on the card; IGNORE on children so picking hits the card (not labels).
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("primary_type", primary_type)
	card.set_meta("tooltip_text_full", tip)

	var base_modulate: Color
	if task.status == "Done":
		base_modulate = Color(0.85, 0.95, 0.85)
	elif primary_type == "start":
		base_modulate = Color(0.8, 1.0, 0.8)
	elif primary_type == "publish":
		base_modulate = Color(0.8, 0.88, 1.0)
	else:
		base_modulate = Color(1.0, 0.8, 0.8)
	if is_blocked:
		base_modulate = Color(1.0, 0.72, 0.45)
	card.modulate = base_modulate
	card.set_meta("base_modulate", base_modulate)
	card.tooltip_text = tip

	var hbox := HBoxContainer.new()
	# IGNORE so the card owns right-click / double-click / hover (not child Labels).
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hbox)

	var icon_label := Label.new()
	icon_label.text = calendar_kind_icons(kinds)
	icon_label.add_theme_font_size_override("font_size", 10)
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_label.tooltip_text = tip
	hbox.add_child(icon_label)

	var kind_label := Label.new()
	kind_label.text = kind_label_text
	kind_label.add_theme_font_size_override("font_size", 8)
	kind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kind_label.tooltip_text = tip
	hbox.add_child(kind_label)

	var title_label := Label.new()
	var display_title: String = ("⛔ " if is_blocked else "") + task.title
	if display_title.length() > 12:
		display_title = display_title.substr(0, 12) + "..."
	title_label.text = display_title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 9)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.tooltip_text = tip
	hbox.add_child(title_label)

	var status_icon := Label.new()
	match task.status:
		"To Do":
			status_icon.text = "📝"
		"In Progress":
			status_icon.text = "🔄"
		"Review":
			status_icon.text = "👀"
		"Done":
			status_icon.text = "✅"
	status_icon.add_theme_font_size_override("font_size", 8)
	status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_icon.tooltip_text = tip
	hbox.add_child(status_icon)

	return card
