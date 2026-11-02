## Purpose: Internal helper for ContentBus remote URL loading (URL normalization + HTTPRequest + source upsert).
@tool
extends Node

var _http_request: HTTPRequest = null

var _get_content_state_cb: Callable = Callable()
var _handle_operation_failed_cb: Callable = Callable() # (op:String, err:String, details:String)
var _remote_source_processed_cb: Callable = Callable() # (source_id:String)

func setup(get_content_state_cb: Callable, handle_operation_failed_cb: Callable, remote_source_processed_cb: Callable) -> void:
	_get_content_state_cb = get_content_state_cb
	_handle_operation_failed_cb = handle_operation_failed_cb
	_remote_source_processed_cb = remote_source_processed_cb

func _rewrite_special_urls(url: String) -> String:
	var u := String(url).strip_edges()
	if u.is_empty():
		return ""
	# Strip query/fragments for predictable caching; callers can include stable raw URLs.
	var base := u.split("?", true, 1)[0]
	base = base.split("#", true, 1)[0]

	# Special cases live here. Add new cases over time without hardcoding in request logic.
	# Keep the default behavior "return base" so arbitrary URLs keep working.

	# **GitHub**: "blob" URLs return HTML; rewrite to raw for plain-text retrieval.
	if base.begins_with("https://github.com/"):
		var rest := base.substr("https://github.com/".length())
		var parts := rest.split("/")
		# Expected: owner/repo/blob/branch/path...
		if parts.size() >= 5 and parts[2] == "blob":
			var owner := parts[0]
			var repo := parts[1]
			var branch := parts[3]
			var path_parts := parts.slice(4, parts.size())
			var path := "/".join(path_parts)
			return "https://raw.githubusercontent.com/%s/%s/%s/%s" % [owner, repo, branch, path]

	return base

func request_load_source_from_url(url: String, user_name: String, source_id_override: String = "") -> void:
	var original_url := String(url).strip_edges()
	var request_url := _rewrite_special_urls(original_url)
	print("ContentBus: Requesting load from URL: %s (User Name: %s)" % [request_url, user_name])
	if request_url != original_url and not original_url.is_empty():
		print("ContentBus: Normalized remote URL:\n  from: %s\n  to:   %s" % [original_url, request_url])

	# Validate URL basic format (simple check)
	if not request_url.begins_with("http://") and not request_url.begins_with("https://"):
		_fail("load_remote_source", "Invalid URL format", url)
		return

	# Create HTTPRequest node if it doesn't exist
	if not is_instance_valid(_http_request):
		_http_request = HTTPRequest.new()
		add_child(_http_request)
		_http_request.request_completed.connect(_on_url_load_completed)
		print("ContentBus: Created and connected HTTPRequest node.")

	# Check if a request is already in progress
	if _http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_fail("load_remote_source", "Another request is already in progress.", url)
		return

	# --- Store metadata for callback ---
	_http_request.set_meta("request_url", request_url)
	_http_request.set_meta("original_url", original_url)
	_http_request.set_meta("user_name", user_name)
	_http_request.set_meta("source_id_override", String(source_id_override).strip_edges())
	# --- End metadata storage ---

	# Make the request
	var err := _http_request.request(request_url)
	if err != OK:
		_fail("load_remote_source", "Failed to initiate HTTP request. Error code: %s" % str(err), url)
	else:
		print("ContentBus: HTTP request initiated for URL: %s" % request_url)

func _fail(operation: String, error: String, details: String) -> void:
	if _handle_operation_failed_cb.is_valid():
		_handle_operation_failed_cb.call(operation, error, details)

func _get_content_state():
	if _get_content_state_cb.is_valid():
		return _get_content_state_cb.call()
	return null

func _emit_remote_source_processed(source_id: String) -> void:
	if _remote_source_processed_cb.is_valid():
		_remote_source_processed_cb.call(source_id)

func _on_url_load_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	# --- Retrieve metadata ---
	var request_url := "Unknown"
	var original_url := ""
	var user_name := "Unknown"
	var source_id_override := ""
	if is_instance_valid(_http_request):
		if _http_request.has_meta("request_url"):
			request_url = str(_http_request.get_meta("request_url"))
		if _http_request.has_meta("original_url"):
			original_url = str(_http_request.get_meta("original_url"))
		if _http_request.has_meta("user_name"):
			user_name = str(_http_request.get_meta("user_name"))
		if _http_request.has_meta("source_id_override"):
			source_id_override = str(_http_request.get_meta("source_id_override"))
		# Clear metadata after use (optional)
		_http_request.remove_meta("request_url")
		_http_request.remove_meta("original_url")
		_http_request.remove_meta("user_name")
		_http_request.remove_meta("source_id_override")
	# --- End metadata retrieval ---

	print("ContentBus: URL load completed. Result: %d, Code: %d, URL: %s, User Name: %s" % [result, response_code, request_url, user_name])

	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("load_remote_source", "HTTP Request Failed. Result code: %s" % str(result), request_url)
		return

	if response_code < 200 or response_code >= 300:
		_fail("load_remote_source", "HTTP Error: %s" % str(response_code), request_url)
		return

	var raw_content_string: String = body.get_string_from_utf8()
	# Avoid dumping entire remote payloads to the console (can be huge + slow).
	# Keep a small preview for debugging.
	var preview_len: int = 600
	var preview: String = raw_content_string
	if preview.length() > preview_len:
		preview = preview.substr(0, preview_len) + "\n...[truncated preview]..."
	print("ContentBus: Remote content fetched (%d chars). Preview:\n%s" % [raw_content_string.length(), preview])

	if raw_content_string.is_empty():
		_fail("load_remote_source", "Received empty response body.", request_url)
		return

	# --- Create Basic Source Data (Bypass JSON Parse) ---
	var temp_source_id := String(source_id_override).strip_edges()
	if temp_source_id.is_empty():
		temp_source_id = user_name.to_lower().replace(" ", "_") + "_remote_" + str(randi() % 1000)
	var extension := "unknown"
	if request_url.find(".") > -1:
		extension = request_url.get_extension().to_lower()

	# Explicit typing avoids "cannot infer type" becoming a hard error when warnings are treated as errors.
	var orig: String = String(original_url).strip_edges()
	if orig.is_empty():
		orig = String(request_url)

	# Preserve user toggles if this is a refresh of an existing remote source.
	var ai_context: Dictionary = {"metaprompt": false, "is_active": false, "model_metadata": {}}
	var content_state_for_preserve = _get_content_state()
	if is_instance_valid(content_state_for_preserve):
		var existing: Dictionary = content_state_for_preserve.get_source_data(temp_source_id)
		if not existing.is_empty():
			var em: Dictionary = existing.get("meta", {})
			var eai_any: Variant = em.get("ai_context", {})
			if typeof(eai_any) == TYPE_DICTIONARY:
				var eai: Dictionary = eai_any
				ai_context["metaprompt"] = bool(eai.get("metaprompt", false))
				ai_context["is_active"] = bool(eai.get("is_active", false))
				ai_context["model_metadata"] = eai.get("model_metadata", {})

	var basic_source_data := {
		"format_version": "1.0.0",
		"meta": {
			"source_id": temp_source_id,
			"name": user_name,
			"author": "SynTree User (Remote Load)",
			"created": Time.get_datetime_string_from_system(),
			"modified": Time.get_datetime_string_from_system(),
			"path": request_url, # Store normalized/canonical URL
			"source_url_original": orig, # Store what the user entered (best-effort)
			"source_origin": "remote",
			"source_type": extension,
			"ai_context": ai_context
		},
		"content": {
			"nodes": [
				{
					"node_id": temp_source_id + "_node_0",
					"content": raw_content_string, # Store raw content
					"type": "raw_remote", # Indicate it's raw
					"title": user_name
				}
			]
		}
	}
	# --- End Basic Source Data Creation ---

	var content_state = _get_content_state()
	if not is_instance_valid(content_state) or not content_state.has_method("add_or_update_source_data"):
		_fail("load_remote_source", "ContentStateResource not available or missing required method (add_or_update_source_data).", request_url)
		return

	var added_or_updated_id: String = str(content_state.add_or_update_source_data(basic_source_data)).strip_edges()
	if added_or_updated_id.is_empty():
		_fail("load_remote_source", "Failed to add/update basic source data (check logs).", request_url)
		return

	print("ContentBus: Successfully added/updated basic remote source: %s" % added_or_updated_id)
	_emit_remote_source_processed(added_or_updated_id)


