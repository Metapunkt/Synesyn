extends RefCounted
class_name WorkshopResumeHydrate

## Restores Scenario packet, Session Record text, and Thinking Map lines from a
## saved Workshop Catalyst story log so resume is a continuation, not a blank
## session keyed only by filename.

const ScenarioContractScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_scenario_contract.gd"
)

const SNAPSHOT_KEYS: Array[String] = [
	"id",
	"name",
	"objective",
	"description",
	"workshop_packet",
	"workshop_packet_text",
	"workshop_agenda_text",
	"time_model",
	"stage_guidance",
	"about_text",
	"how_to_text",
	"system_config",
]


static func compact_scenario_snapshot(scenario: Dictionary) -> Dictionary:
	var snapshot: Dictionary = {}
	for key_name: String in SNAPSHOT_KEYS:
		if scenario.has(key_name):
			snapshot[key_name] = scenario[key_name]
	if snapshot.is_empty():
		return {}
	snapshot["schema_version"] = int(scenario.get("schema_version", 1))
	snapshot["_session_type_id"] = "workshop_catalyst"
	snapshot["persistence_state"] = "resumed_snapshot"
	return snapshot


static func scenario_from_resume_path(json_path: String) -> Dictionary:
	var sidecar: Dictionary = read_json_dictionary(_workshop_path(json_path))
	var snapshot_any: Variant = sidecar.get("scenario_snapshot", {})
	if typeof(snapshot_any) == TYPE_DICTIONARY and not (snapshot_any as Dictionary).is_empty():
		var snapshot: Dictionary = snapshot_any
		if not String(snapshot.get("name", "")).strip_edges().is_empty():
			return ScenarioContractScript.normalize(snapshot)
	return _scenario_from_legacy_files(json_path, sidecar)


static func session_record_prompt_text(workshop_state: Dictionary, char_limit: int) -> String:
	var sections: Array[String] = []
	var resume_summary: String = String(
		workshop_state.get("resume_summary", "")
	).strip_edges()
	if not resume_summary.is_empty():
		sections.append("Resume: " + resume_summary)
	var latest_text: String = String(
		workshop_state.get("session_record_latest_text", "")
	).strip_edges()
	if not latest_text.is_empty():
		sections.append("Latest Session Record:\n" + latest_text)
	var reviewed_text: String = _reviewed_items_text(workshop_state)
	if not reviewed_text.is_empty():
		sections.append("Reviewed Session Record items:\n" + reviewed_text)
	var buckets_text: String = _buckets_text(workshop_state)
	if not buckets_text.is_empty():
		sections.append("Buckets:\n" + buckets_text)
	return "\n\n".join(sections).left(char_limit)


static func thinking_map_resume_lines(workshop_state: Dictionary, max_items: int) -> Array[String]:
	var map_any: Variant = workshop_state.get("thinking_map", {})
	if typeof(map_any) != TYPE_DICTIONARY:
		return []
	var map_state: Dictionary = map_any
	var nodes: Array = _map_nodes(map_state)
	var lines: Array[String] = []
	for node_any: Variant in nodes:
		if lines.size() >= max_items:
			break
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		var label_text: String = String(
			node_data.get("label", node_data.get("proposition", ""))
		).strip_edges()
		if label_text.is_empty():
			continue
		var category_text: String = String(
			node_data.get("kind", node_data.get("category", "item"))
		).strip_edges()
		if category_text.is_empty():
			category_text = "item"
		lines.append("- [%s] %s" % [category_text, label_text.left(300)])
	return lines


static func read_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func read_json_array(path: String) -> Array:
	if path.is_empty() or not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_ARRAY:
		return []
	return parsed


static func _scenario_from_legacy_files(json_path: String, sidecar: Dictionary) -> Dictionary:
	var provenance: Dictionary = read_json_dictionary(_provenance_path(json_path))
	var scenario_title: String = String(provenance.get("scenario", "")).strip_edges()
	if scenario_title.is_empty() or scenario_title.to_lower() == "resumed session":
		scenario_title = "Resumed workshop"
	var objective_text: String = _objective_from_story_log(read_json_array(json_path))
	var agenda_any: Variant = sidecar.get("agenda", [])
	var source: Dictionary = {
		"id": ScenarioContractScript.CUSTOM_SCENARIO_ID,
		"name": scenario_title if not scenario_title.is_empty() else "Resumed workshop",
		"objective": objective_text,
		"description": String(sidecar.get("resume_summary", "")).strip_edges(),
		"persistence_state": "resumed_snapshot",
	}
	if typeof(agenda_any) == TYPE_ARRAY and not (agenda_any as Array).is_empty():
		source["workshop_agenda_text"] = JSON.stringify(agenda_any)
	return ScenarioContractScript.normalize(source)


static func _objective_from_story_log(entries: Array) -> String:
	for entry_any: Variant in entries:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		if String(entry.get("sender", "")).strip_edges() != "Workshop Catalyst":
			continue
		var cleaned: String = _strip_bbcode(String(entry.get("message", "")))
		var first_line: String = cleaned.split("\n")[0].strip_edges()
		if not first_line.is_empty():
			return first_line
	return ""


static func _strip_bbcode(raw_text: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[/?[^\\]]+\\]")
	return regex.sub(raw_text, "", true).strip_edges()


static func _reviewed_items_text(workshop_state: Dictionary) -> String:
	var review_any: Variant = workshop_state.get("session_record_review", {})
	if typeof(review_any) != TYPE_DICTIONARY:
		return ""
	var reviewed_any: Variant = (review_any as Dictionary).get("reviewed", {})
	if typeof(reviewed_any) != TYPE_DICTIONARY:
		return ""
	var lines: Array[String] = []
	var reviewed: Dictionary = reviewed_any
	for category_id: String in reviewed.keys():
		var items_any: Variant = reviewed.get(category_id, [])
		if typeof(items_any) != TYPE_ARRAY:
			continue
		for item_any: Variant in items_any:
			var item_text: String = ""
			if typeof(item_any) == TYPE_DICTIONARY:
				item_text = String((item_any as Dictionary).get("text", "")).strip_edges()
			else:
				item_text = String(item_any).strip_edges()
			if not item_text.is_empty():
				lines.append("- [%s] %s" % [String(category_id), item_text.left(240)])
			if lines.size() >= 12:
				break
		if lines.size() >= 12:
			break
	return "\n".join(lines)


static func _buckets_text(workshop_state: Dictionary) -> String:
	var buckets_any: Variant = workshop_state.get("buckets", {})
	if typeof(buckets_any) != TYPE_DICTIONARY:
		return ""
	var buckets: Dictionary = buckets_any
	var has_item: bool = false
	for bucket_key: Variant in buckets.keys():
		var items_any: Variant = buckets.get(bucket_key, [])
		if typeof(items_any) == TYPE_ARRAY:
			for item_any: Variant in items_any:
				if not String(item_any).strip_edges().is_empty():
					has_item = true
					break
		if has_item:
			break
	if not has_item:
		return ""
	return JSON.stringify(buckets)


static func _map_nodes(map_state: Dictionary) -> Array:
	var document_any: Variant = map_state.get("document", {})
	if typeof(document_any) == TYPE_DICTIONARY:
		var nodes_any: Variant = (document_any as Dictionary).get("nodes", [])
		if typeof(nodes_any) == TYPE_ARRAY and not (nodes_any as Array).is_empty():
			return nodes_any
	var committed_any: Variant = map_state.get("last_committed_document", {})
	if typeof(committed_any) == TYPE_DICTIONARY:
		var committed_nodes_any: Variant = (committed_any as Dictionary).get("nodes", [])
		if typeof(committed_nodes_any) == TYPE_ARRAY:
			return committed_nodes_any
	var top_nodes_any: Variant = map_state.get("nodes", [])
	if typeof(top_nodes_any) == TYPE_ARRAY:
		return top_nodes_any
	return []


static func _workshop_path(json_path: String) -> String:
	if json_path.ends_with(".json"):
		return json_path.substr(0, json_path.length() - 5) + ".workshop.json"
	return json_path + ".workshop.json"


static func _provenance_path(json_path: String) -> String:
	if json_path.ends_with(".json"):
		return json_path.substr(0, json_path.length() - 5) + ".provenance.json"
	return json_path + ".provenance.json"
