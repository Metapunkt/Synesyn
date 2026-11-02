## Purpose: Helpers for ContentSourceResource.initialize_content_sources() (directory scan + sync plan)
extends RefCounted

func scan_json_source_ids(dir_to_scan: String) -> Dictionary:
	# Returns: { success: bool, error: String, ids: PackedStringArray }
	var dir_access := DirAccess.open(dir_to_scan)
	if not dir_access:
		var error_msg = "Failed to open directory: %s (Error code: %d)" % [dir_to_scan, DirAccess.get_open_error()]
		return {"success": false, "error": error_msg, "ids": PackedStringArray([])}

	var file_source_ids := PackedStringArray([])
	dir_access.list_dir_begin()
	var file_name = dir_access.get_next()
	while not file_name.is_empty():
		if not dir_access.current_is_dir() and file_name.ends_with(".json"):
			file_source_ids.append(file_name.get_basename())
		file_name = dir_access.get_next()
	dir_access.list_dir_end()
	return {"success": true, "error": "", "ids": file_source_ids}

func compute_sync_plan(file_source_ids: PackedStringArray, memory_source_ids: Array) -> Dictionary:
	# Returns: { to_add: Array, to_remove: Array }
	var sources_to_remove := []
	var sources_to_add := []

	var memory_set := {}
	for id in memory_source_ids:
		memory_set[id] = true

	for file_id in file_source_ids:
		if not memory_set.has(file_id):
			sources_to_add.append(file_id)

	var file_set := {}
	for id in file_source_ids:
		file_set[id] = true
	for mem_id in memory_source_ids:
		if not file_set.has(mem_id):
			sources_to_remove.append(mem_id)

	return {"to_add": sources_to_add, "to_remove": sources_to_remove}


