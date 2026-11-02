extends RefCounted
class_name ScenarioBundleAssets

## Collects and restores the binary side of a Scenario bundle.
##
## Today that means generated character sprites. They live outside the Scenario
## JSON, at
##   <workspace>/scensyn/sprites_generated/<collection>/<scenario>/<character>/<animation>/*.png
## so a Scenario shared as JSON alone renders with different portraits on the
## recipient's machine. When a Scenario has none, the bundle is a bare .json.
##
## Paths here are always relative to one Scenario's own sprite directory. How
## they are laid out inside an archive is ScenarioBundle's business.

const SpriteStoreScript = preload(
	"res://ScenSyn/scripts/services/scensyn_generated_sprite_store.gd"
)

const MAX_FILES: int = 400
const MAX_TOTAL_BYTES: int = 64 * 1024 * 1024


## Directory-friendly name. Must match Character._dir_slug, because the runtime
## sprite lookup resolves scenario and character folders with that convention.
static func dir_slug(source_text: String) -> String:
	var out: String = String(source_text).strip_edges().to_lower()
	out = out.replace(" ", "_")
	out = out.replace("/", "_").replace("\\", "_").replace(":", "_")
	return out


static func scenario_sprite_dir(scenario: Dictionary) -> String:
	var root: String = SpriteStoreScript.get_sprites_generated_root_abs()
	if root.strip_edges().is_empty():
		return ""
	var collection_slug: String = dir_slug(String(scenario.get("_collection_id", "default")))
	if collection_slug.is_empty():
		collection_slug = "default"
	var scenario_name: String = String(
		scenario.get("_scenario_name", scenario.get("name", ""))
	).strip_edges()
	if scenario_name.is_empty():
		return ""
	return root.path_join(collection_slug).path_join(dir_slug(scenario_name))


## Files to carry for this Scenario: {relative_path, source_abs, bytes}.
## Reports totals so the caller can tell the user what is being shared, and
## flags truncation rather than silently dropping a huge sprite set.
static func collect(scenario: Dictionary) -> Dictionary:
	var result: Dictionary = {"files": [], "total_bytes": 0, "truncated": false}
	var source_dir: String = scenario_sprite_dir(scenario)
	if source_dir.is_empty() or not DirAccess.dir_exists_absolute(source_dir):
		return result
	var files: Array[Dictionary] = []
	var total_bytes: int = 0
	var pending: Array[String] = [""]
	while not pending.is_empty():
		var relative_dir: String = pending.pop_back()
		var absolute_dir: String = source_dir
		if not relative_dir.is_empty():
			absolute_dir = source_dir.path_join(relative_dir)
		var dir: DirAccess = DirAccess.open(absolute_dir)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry_name: String = dir.get_next()
		while not entry_name.is_empty():
			var relative_entry: String = entry_name
			if not relative_dir.is_empty():
				relative_entry = relative_dir.path_join(entry_name)
			if dir.current_is_dir():
				pending.append(relative_entry)
			else:
				var absolute_entry: String = source_dir.path_join(relative_entry)
				var entry_bytes: int = _file_size(absolute_entry)
				if files.size() >= MAX_FILES or total_bytes + entry_bytes > MAX_TOTAL_BYTES:
					result["truncated"] = true
				else:
					files.append({
						"relative_path": relative_entry,
						"source_abs": absolute_entry,
						"bytes": entry_bytes,
					})
					total_bytes += entry_bytes
			entry_name = dir.get_next()
		dir.list_dir_end()
	result["files"] = files
	result["total_bytes"] = total_bytes
	return result


## True when an archive-declared path is safe to write. Bundles are untrusted
## input, so anything absolute, drive-qualified, or containing a parent-directory
## hop is refused rather than sanitized into something plausible.
static func is_safe_relative_path(relative_path: String) -> bool:
	var clean_path: String = relative_path.strip_edges().replace("\\", "/")
	if clean_path.is_empty() or clean_path.begins_with("/") or clean_path.ends_with("/"):
		return false
	if clean_path.contains(":") or clean_path.contains("//"):
		return false
	for segment: String in clean_path.split("/"):
		if segment == ".." or segment == "." or segment.strip_edges().is_empty():
			return false
	return true


## Writes one carried file into the importing machine's sprite root for this
## Scenario. The destination is derived from the imported Scenario, never from
## the archive, so a bundle cannot choose where its bytes land. Sprite folders
## are keyed by Scenario name, matching runtime lookup, so re-importing the same
## Scenario refreshes its own portraits.
static func restore_file(
	scenario: Dictionary,
	relative_path: String,
	bytes: PackedByteArray
) -> bool:
	if not is_safe_relative_path(relative_path):
		return false
	var dest_dir: String = scenario_sprite_dir(scenario)
	if dest_dir.is_empty():
		return false
	var dest_path: String = dest_dir.path_join(relative_path.strip_edges().replace("\\", "/"))
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(dest_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return false
	var file: FileAccess = FileAccess.open(dest_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


static func _file_size(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size: int = int(file.get_length())
	file.close()
	return size
