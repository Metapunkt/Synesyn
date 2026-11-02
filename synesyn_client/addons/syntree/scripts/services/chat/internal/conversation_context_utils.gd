## Purpose: Internal helpers for ConversationManager context building (source matching + text extraction).
extends RefCounted

func normalize_source_ref(s: String) -> String:
	var t := String(s).strip_edges().to_lower()
	if t.is_empty():
		return ""
	t = t.replace("\\", "/")
	# Keep it simple: collapse spaces and common separators.
	t = t.replace(" ", "_").replace("-", "_")
	while t.find("__") != -1:
		t = t.replace("__", "_")
	return t

func extract_source_aliases(source_id: String, meta: Dictionary) -> Array[String]:
	var aliases: Array[String] = []
	var sid_norm := normalize_source_ref(source_id)
	if not sid_norm.is_empty():
		aliases.append(sid_norm)
	var name_norm := normalize_source_ref(str(meta.get("name", "")))
	if not name_norm.is_empty() and not aliases.has(name_norm):
		aliases.append(name_norm)

	var path_raw := str(meta.get("path", "")).strip_edges()
	if path_raw.is_empty():
		return aliases
	var path_norm := normalize_source_ref(path_raw)
	if not path_norm.is_empty() and not aliases.has(path_norm):
		aliases.append(path_norm)

	# Basename tokens: README.md -> readme, readme_md
	var last_slash := path_norm.rfind("/")
	var tail := path_norm.substr(last_slash + 1) if last_slash >= 0 else path_norm
	if not tail.is_empty():
		var tail_no_ext := tail.get_basename()
		if not tail_no_ext.is_empty() and not aliases.has(tail_no_ext):
			aliases.append(tail_no_ext)
		if not aliases.has(tail):
			aliases.append(tail)

	# Repo-ish token: for GitHub/raw URLs, capture "<owner>_<repo>" and "<repo>"
	# Example: raw.githubusercontent.com/bi-ds/dre7053/... -> dre7053
	var parts := path_norm.split("/")
	for i in range(parts.size()):
		if parts[i] == "github.com" or parts[i] == "raw.githubusercontent.com":
			if i + 2 < parts.size():
				var owner := parts[i + 1]
				var repo := parts[i + 2]
				var owner_repo := "%s_%s" % [owner, repo]
				if not aliases.has(owner_repo):
					aliases.append(owner_repo)
				if not aliases.has(repo):
					aliases.append(repo)
			break

	return aliases

func find_referenced_active_sources(user_prompt: String, content_state, active_sources: Array) -> Array[String]:
	var p := normalize_source_ref(user_prompt)
	if p.is_empty():
		return []
	var hits: Array[String] = []
	for sid_any in active_sources:
		var sid := str(sid_any)
		var sd: Dictionary = content_state.get_source_data(sid)
		var meta: Dictionary = sd.get("meta", {})
		var aliases := extract_source_aliases(sid, meta)
		for a in aliases:
			if not a.is_empty() and p.find(a) != -1:
				hits.append(sid)
				break
	return hits

func expand_active_sources_for_reference_matching(content_state, active_sources: Array) -> Array[String]:
	# Include stack member ids so user prompts can reference them even if only the stack root is active.
	var out: Array[String] = []
	var seen := {}
	for sid_any in active_sources:
		var sid := str(sid_any)
		if sid.is_empty() or seen.has(sid):
			continue
		out.append(sid)
		seen[sid] = true
		var sd0: Dictionary = content_state.get_source_data(sid)
		var ai0: Dictionary = sd0.get("meta", {}).get("ai_context", {})
		if bool(ai0.get("is_stack", false)) and content_state.has_method("get_stack_member_source_ids"):
			var members: Array[String] = content_state.get_stack_member_source_ids(sid)
			for mid in members:
				if not mid.is_empty() and not seen.has(mid):
					out.append(mid)
					seen[mid] = true
	return out

func expand_sources_for_context(content_state, sources: Array) -> Array[String]:
	# Expand stack sources into ordered member sources (by stack wiring) and preserve stable order.
	var out: Array[String] = []
	var seen := {}
	for sid_any in sources:
		var sid := str(sid_any)
		if sid.is_empty():
			continue
		var sd: Dictionary = content_state.get_source_data(sid)
		var ai: Dictionary = sd.get("meta", {}).get("ai_context", {})
		var is_stack := bool(ai.get("is_stack", false))
		if is_stack and content_state.has_method("get_stack_ordered_member_source_ids"):
			var ordered: Array[String] = content_state.get_stack_ordered_member_source_ids(sid)
			for mid in ordered:
				if not mid.is_empty() and not seen.has(mid):
					out.append(mid)
					seen[mid] = true
		else:
			if not seen.has(sid):
				out.append(sid)
				seen[sid] = true
	return out

func make_source_digest(text: String, max_chars: int) -> String:
	var raw := String(text)
	if raw.strip_edges().is_empty():
		return ""
	var lines := raw.split("\n")
	var out: Array[String] = []
	var seen := {}

	# Prefer markdown headings + first few non-empty lines.
	for ln in lines:
		var s := String(ln).strip_edges()
		if s.is_empty():
			continue
		if s.begins_with("#"):
			if not seen.has(s):
				out.append(s)
				seen[s] = true
		if out.size() >= 12:
			break

	# If no headings, include first non-empty lines.
	if out.is_empty():
		for ln2 in lines:
			var s2 := String(ln2).strip_edges()
			if s2.is_empty():
				continue
			out.append(s2)
			if out.size() >= 12:
				break

	var joined := "\n".join(out)
	if joined.length() > max_chars:
		return joined.substr(0, max_chars) + "…"
	return joined

func looks_like_html(text: String) -> bool:
	var t := String(text).strip_edges()
	if t.is_empty():
		return false
	var low := t.to_lower()
	return low.begins_with("<!doctype html") or low.begins_with("<html") or low.find("<head") != -1 or low.find("<meta") != -1

func extract_text_from_source_data(sd: Dictionary) -> String:
	# - Prefer in-memory node content (remote sources, structured sources)
	# - Treat whitespace-only string "content" as empty (common placeholder for file sources)
	# - Fallback to reading meta.path for res://, user://, and absolute filesystem paths
	var content_any: Variant = sd.get("content", null)
	if typeof(content_any) == TYPE_STRING:
		var s := str(content_any)
		if not s.strip_edges().is_empty():
			return s

	if typeof(content_any) == TYPE_DICTIONARY:
		var cdict: Dictionary = content_any
		var nodes_any: Variant = cdict.get("nodes", null)
		if typeof(nodes_any) == TYPE_ARRAY:
			var nodes: Array = nodes_any
			var parts: Array[String] = []
			for n_any in nodes:
				if typeof(n_any) == TYPE_DICTIONARY:
					var nd: Dictionary = n_any
					var txt := str(nd.get("content", "")).strip_edges()
					if not txt.is_empty():
						parts.append(txt)
			if not parts.is_empty():
				return "\n\n".join(parts)

	# Fallback: read underlying file content from meta.path.
	var meta: Dictionary = sd.get("meta", {})
	var p := str(meta.get("path", "")).strip_edges()
	if p.is_empty():
		return ""

	# Skip URL paths (remote sources should have content in nodes).
	if p.begins_with("http://") or p.begins_with("https://"):
		return ""

	# Normalize Windows paths (C:\...) to Godot-friendly form.
	p = p.replace("\\", "/")

	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		if f:
			var t := f.get_as_text()
			f.close()
			return t
	return ""


