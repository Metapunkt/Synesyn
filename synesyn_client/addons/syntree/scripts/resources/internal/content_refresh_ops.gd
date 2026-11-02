## Purpose: Internal helpers for refreshing active sources and parsing source content updates (no signals, no ContentBus)
extends RefCounted

func parse_updated_content(source_data: Dictionary, new_content: String) -> Dictionary:
	# Returns: { success: bool, error: String, updated_content: Variant }
	var content_type := ""
	var meta_any: Variant = source_data.get("meta", {})
	if meta_any is Dictionary:
		var meta: Dictionary = meta_any
		if meta.has("content_type"):
			content_type = str(meta.get("content_type", ""))

	if content_type == "json":
		var json = JSON.new()
		var err = json.parse(new_content)
		if err != OK:
			return {"success": false, "error": "Cannot update JSON content - " + json.get_error_message(), "updated_content": null}
		return {"success": true, "error": "", "updated_content": json.get_data()}

	# For non-JSON content (text, markdown, etc.), store as raw text
	return {"success": true, "error": "", "updated_content": new_content}

func refresh_active_sources(active_sources: Array[String], get_source_data_cb: Callable, update_source_content_cb: Callable, trigger_remote_refresh_cb: Callable) -> Dictionary:
	# Mirrors the existing ContentStateResource.refresh_active_sources contract:
	# { success: bool, refreshed_count: int, errors: Array }
	var result = {
		"success": true,
		"refreshed_count": 0,
		"errors": []
	}

	for source_id in active_sources:
		var source_data: Dictionary = get_source_data_cb.call(source_id)
		if source_data.is_empty():
			result.errors.append("No data found for source: " + source_id)
			continue

		var meta_any: Variant = source_data.get("meta", {})
		var meta: Dictionary = meta_any if meta_any is Dictionary else {}
		var origin := str(meta.get("source_origin", "file")) # Default to file
		var path_or_url := str(meta.get("path", ""))

		if path_or_url.is_empty():
			result.errors.append("No path/URL found for source: " + source_id)
			continue

		if origin == "file":
			var p := str(path_or_url)
			p = p.replace("\\", "/")
			var file = FileAccess.open(p, FileAccess.READ)
			if not file:
				result.errors.append("Failed to open file: " + p)
				continue
			var content = file.get_as_text()
			file.close()

			if bool(update_source_content_cb.call(source_id, content)):
				result.refreshed_count += 1
			else:
				result.errors.append("Failed to update file content for: " + source_id)

		elif origin == "remote":
			# Remote refresh is async; this function only schedules it.
			if trigger_remote_refresh_cb.is_valid():
				trigger_remote_refresh_cb.call(source_id, path_or_url)
			# No increment here (async)
		else:
			result.errors.append("Unknown source origin '%s' for: %s" % [origin, source_id])

	result.success = result.errors.is_empty()
	return result


