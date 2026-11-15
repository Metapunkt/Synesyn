extends RefCounted
class_name WorkplanTaskMarkdown
## Format a single WorkplanTask as paste-ready Markdown for chat/community posts.


static func to_clipboard_markdown(task: WorkplanTask, workplan: Resource = null) -> String:
	if task == null:
		return ""
	const PublishTimeScript = preload("res://readymade/scripts/workplan_publish_time.gd")
	var lines: PackedStringArray = PackedStringArray()
	lines.append("## %s" % task.title)
	lines.append("")
	if not task.channel.is_empty():
		lines.append("**Channel:** `%s`" % task.channel)
	var publish_label: String = PublishTimeScript.format_publish_label(task, workplan)
	if not publish_label.is_empty():
		lines.append("**Publish:** %s" % publish_label)
	task.migrate_content_status_from_notes()
	lines.append("**Status:** %s" % task.get_content_status())
	if not task.campaign_tag.is_empty():
		lines.append("**Campaign:** %s" % task.campaign_tag)
	if not task.content_theme.is_empty():
		lines.append("**Theme:** %s" % task.content_theme)
	lines.append("")
	var body: String = task.generated_content.strip_edges()
	if body.is_empty():
		body = "_No draft yet._"
	lines.append(body)
	lines.append("")
	return "\n".join(lines)


static func copy_to_clipboard(task: WorkplanTask, workplan: Resource = null) -> String:
	var text: String = to_clipboard_markdown(task, workplan)
	DisplayServer.clipboard_set(text)
	return text
