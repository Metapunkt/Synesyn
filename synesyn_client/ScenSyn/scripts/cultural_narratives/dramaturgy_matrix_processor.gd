class_name DramaturgyMatrixProcessor
extends RefCounted

static var _matrix_cache: Dictionary = {}

static func get_character_behavioral_guidance(character_name: String, scenario: Dictionary = {}) -> String:
	var entry: Dictionary = _get_character_entry(character_name, scenario)
	if entry.is_empty():
		return ""
	var label: String = String(entry.get("_label", character_name)).strip_edges()
	var guidance: String = "\n--- " + label.to_upper() + " BEHAVIORAL MATRIX ---\n"
	guidance += "Core Identity: " + entry.get("primary_components", "") + "\n"
	guidance += "Symbolic Role: " + entry.get("symbolic_function", "") + "\n"
	guidance += "Relationship Dynamic: " + entry.get("character_relationship", "") + "\n"
	guidance += "Philosophical Stance: " + entry.get("philosophical_dimension", "") + "\n"
	return guidance

static func get_thematic_interaction_guidance(_scenario: Dictionary = {}) -> String:
	return ""

static func get_stage_manager_guidance(scenario: Dictionary = {}) -> String:
	var schema = scenario.get("dramaturgy_matrix", {})
	var stage_key = schema.get("stage_manager_key", "The Child")
	var entry = _get_character_entry(stage_key, scenario)
	if entry.is_empty():
		return ""
	var label: String = String(entry.get("_label", stage_key))
	var guidance: String = "=== %s BEHAVIORAL MATRIX ===\n\n" % label.to_upper()
	guidance += "Role: " + entry.get("primary_components", "") + "\n\n"
	guidance += "FUNCTION NOTES:\n"
	guidance += "- " + entry.get("symbolic_function", "") + "\n"
	guidance += "- " + entry.get("thematic_connection", "") + "\n"
	guidance += "- " + entry.get("character_relationship", "") + "\n"
	return guidance

static func _get_character_entry(character_name: String, scenario: Dictionary) -> Dictionary:
	var matrix = _get_character_matrix(scenario)
	var key = _normalize_name(character_name)
	return matrix.get(key, {})

static func _get_character_matrix(scenario: Dictionary) -> Dictionary:
	if scenario.is_empty() or not scenario.has("dramaturgy_matrix"):
		# No schema declared -> nothing to load (forces scenario authors to opt in).
		return {}
	var cache_key: String = String(scenario.get("_scenario_file", "")) + ":" + String(scenario.get("_scenario_name", ""))
	if _matrix_cache.has(cache_key):
		return _matrix_cache[cache_key]
	var parsed := _parse_matrix_for_scenario(scenario)
	_matrix_cache[cache_key] = parsed
	return parsed

static func _parse_matrix_for_scenario(scenario: Dictionary) -> Dictionary:
	var schema: Dictionary = scenario.get("dramaturgy_matrix", {})
	# Every scenario chooses its own CSV path/columns; this resolver keeps code generic.
	var csv_path := _resolve_matrix_path(schema, scenario)
	if csv_path == "":
		return {}
	var rows := _read_csv_rows(csv_path)
	if rows.is_empty():
		return {}
	var matrix_type: String = String(schema.get("type", "character_table")).to_lower()
	match matrix_type:
		"character_table":
			return _parse_character_table(rows, schema)
		_:
			print("DramaturgyMatrixProcessor: Unsupported matrix type '%s', skipping." % matrix_type)
			return {}

static func _resolve_matrix_path(schema: Dictionary, scenario: Dictionary) -> String:
	var raw_path: String = schema.get("file", "")
	if raw_path == "":
		return ""
	if raw_path.begins_with("res://"):
		return raw_path
	var base_dir: String = scenario.get("_base_dir", "")
	if base_dir == "":
		return raw_path
	return base_dir + raw_path

static func _read_csv_rows(path: String) -> Array:
	var rows: Array = []
	if not FileAccess.file_exists(path):
		push_warning("DramaturgyMatrixProcessor: CSV not found at %s" % path)
		return rows
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("DramaturgyMatrixProcessor: Failed to open %s" % path)
		return rows
	var headers: PackedStringArray
	while file.get_position() < file.get_length():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() == 0 or (line.size() == 1 and line[0].strip_edges() == ""):
			continue
		if headers.is_empty():
			headers = line
			continue
		var row: Dictionary = {}
		for i in range(headers.size()):
			var header = headers[i].strip_edges()
			if header == "":
				continue
			var value := ""
			if i < line.size():
				value = line[i].strip_edges()
			row[header] = value
		rows.append(row)
	file.close()
	return rows

static func _parse_character_table(rows: Array, schema: Dictionary) -> Dictionary:
	var key_column: String = schema.get("key_column", "Element")
	var field_columns: Array = _split_list(schema.get("field_columns", ""))
	var matrix: Dictionary = {}
	for row in rows:
		var label: String = row.get(key_column, "")
		if label.strip_edges() == "":
			continue
		var entry: Dictionary = {"_label": label.strip_edges()}
		if field_columns.is_empty():
			for k in row.keys():
				entry[k] = row[k]
		else:
			for field in field_columns:
				entry[field] = row.get(field, "")
		for alias_value in _generate_aliases(label):
			var key: String = _normalize_name(alias_value)
			if key == "":
				continue
			matrix[key] = entry
	return matrix

static func _split_list(value: String) -> Array:
	# Helper for comma-separated lists such as field_columns in the schema.
	if value == "":
		return []
	var parts := value.split(",")
	var result: Array = []
	for part in parts:
		var trimmed := String(part).strip_edges()
		if trimmed != "":
			result.append(trimmed)
	return result

static func _generate_aliases(raw_label: String) -> Array:
	var aliases: Array = []
	var base := raw_label.strip_edges()
	if base == "":
		return aliases
	aliases.append(base)
	var paren := base.find("(")
	if paren != -1:
		var without = base.substr(0, paren).strip_edges()
		if without != "" and not aliases.has(without):
			aliases.append(without)
	return aliases

static func _normalize_name(value: String) -> String:
	return String(value).strip_edges().to_lower()
