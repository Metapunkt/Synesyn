extends RefCounted
class_name WorkshopCatalystBucketUtils

static func merge_bucket_sets(existing_buckets: Dictionary, incoming_buckets: Dictionary) -> Dictionary:
	var merged: Dictionary = existing_buckets.duplicate(true)
	for bucket_key_any in incoming_buckets.keys():
		var bucket_key: String = String(bucket_key_any)
		var existing_items_any: Variant = merged.get(bucket_key, [])
		var existing_items: Array = existing_items_any if typeof(existing_items_any) == TYPE_ARRAY else []
		var incoming_items_any: Variant = incoming_buckets.get(bucket_key, [])
		var incoming_items: Array = incoming_items_any if typeof(incoming_items_any) == TYPE_ARRAY else []
		var dedupe_map: Dictionary = {}
		var normalized_items: Array[String] = []
		var new_items: Array = []
		for existing_item_any in existing_items:
			var existing_text: String = bucket_item_to_string(existing_item_any)
			var normalized_existing: String = normalize_bucket_item_for_dedupe(existing_text)
			if existing_text != "" and not dedupe_map.has(normalized_existing):
				dedupe_map[normalized_existing] = true
				normalized_items.append(normalized_existing)
				new_items.append(existing_text)
		for incoming_item_any in incoming_items:
			var incoming_text: String = bucket_item_to_string(incoming_item_any)
			var normalized_incoming: String = normalize_bucket_item_for_dedupe(incoming_text)
			var near_duplicate_index: int = bucket_item_near_duplicate_index(normalized_incoming, normalized_items)
			if incoming_text != "" and not dedupe_map.has(normalized_incoming) and near_duplicate_index == -1:
				dedupe_map[normalized_incoming] = true
				normalized_items.append(normalized_incoming)
				new_items.append(incoming_text)
			elif bucket_key == "decisions" and near_duplicate_index >= 0 and bucket_item_is_richer_decision(incoming_text, String(new_items[near_duplicate_index])):
				new_items[near_duplicate_index] = incoming_text
				normalized_items[near_duplicate_index] = normalized_incoming
		merged[bucket_key] = new_items
	return merged

static func normalize_bucket_item_for_dedupe(text: String) -> String:
	var normalized: String = text.to_lower().strip_edges()
	for marker in [". owner:", ". confidence:", ". likelihood:", ". cost-bearer:", ". cost bearer:"]:
		var idx: int = normalized.find(marker)
		if idx >= 0:
			normalized = normalized.substr(0, idx).strip_edges()
	var keep := ""
	for i in range(normalized.length()):
		var char_text := normalized[i]
		if char_text.is_valid_identifier() or char_text == " " or char_text.is_valid_int():
			keep += char_text
		else:
			keep += " "
	while keep.find("  ") != -1:
		keep = keep.replace("  ", " ")
	return keep.strip_edges()

static func bucket_item_near_duplicate_index(normalized_incoming: String, normalized_items: Array[String]) -> int:
	if normalized_incoming.length() < 40:
		return -1
	for item_index in range(normalized_items.size()):
		var normalized_existing: String = normalized_items[item_index]
		if normalized_existing.length() < 40:
			continue
		if normalized_existing.find(normalized_incoming) != -1 or normalized_incoming.find(normalized_existing) != -1:
			return item_index
		var shared_terms := 0
		var incoming_terms: PackedStringArray = normalized_incoming.split(" ", false)
		for term in incoming_terms:
			if term.length() < 6:
				continue
			if normalized_existing.find(term) != -1:
				shared_terms += 1
		if shared_terms >= 8:
			return item_index
	return -1

static func bucket_item_is_richer_decision(incoming_text: String, existing_text: String) -> bool:
	var incoming_lower: String = incoming_text.to_lower()
	var existing_lower: String = existing_text.to_lower()
	var incoming_has_metadata: bool = incoming_lower.find("owner:") != -1 or incoming_lower.find("confidence:") != -1
	var existing_has_metadata: bool = existing_lower.find("owner:") != -1 or existing_lower.find("confidence:") != -1
	return incoming_has_metadata and not existing_has_metadata

static func bucket_item_to_string(item: Variant) -> String:
	var raw := ""
	if typeof(item) == TYPE_STRING:
		raw = String(item).strip_edges()
	elif typeof(item) == TYPE_DICTIONARY:
		var item_dict: Dictionary = item
		var parts: Array[String] = []
		for key_any in ["text", "statement", "decision", "risk", "question", "description", "content"]:
			var val: String = str(item_dict.get(key_any, "")).strip_edges()
			if not val.is_empty():
				parts.append(val)
				break
		for key_any in ["owner", "confidence", "likelihood", "cost_bearer", "cost-bearer"]:
			var val: String = str(item_dict.get(key_any, "")).strip_edges()
			if not val.is_empty():
				parts.append("%s: %s" % [str(key_any).replace("_", "-"), val])
		raw = ". ".join(parts).strip_edges()
	else:
		raw = str(item).strip_edges()
	while raw.find("..") != -1:
		raw = raw.replace("..", ".")
	return raw
