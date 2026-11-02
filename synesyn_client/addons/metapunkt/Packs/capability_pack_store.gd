## Capability Pack store: install/uninstall/list + per-pack config + secrets (v0).
##
## Installed packs live at: Documents/Synesyn/synesyn/packs/<pack_id>/<version>/
## Pack config (enabled state, secrets) lives at: .../packs/_config.json
extends RefCounted
class_name CapabilityPackStore

const CONFIG_FILENAME := "_config.json"
const CONFIG_SCHEMA_VERSION := 1


static func packs_root() -> String:
	return RuntimeConfig.get_packs_dir()


# --- Public API ---

static func ensure_packs_dir() -> void:
	DirAccess.make_dir_recursive_absolute(packs_root())


static func list_installed() -> Array[Dictionary]:
	## Returns [{id, version, dir_path, manifest: CapabilityPackManifest}] for each installed pack.
	ensure_packs_dir()
	var results: Array[Dictionary] = []
	var root_path: String = packs_root()
	var root_dir := DirAccess.open(root_path)
	if not root_dir:
		return results
	root_dir.list_dir_begin()
	var pack_id_dir := root_dir.get_next()
	while not pack_id_dir.is_empty():
		if root_dir.current_is_dir() and not pack_id_dir.begins_with("_"):
			var pack_dir_path := root_path.path_join(pack_id_dir)
			var inner := DirAccess.open(pack_dir_path)
			if inner:
				inner.list_dir_begin()
				var ver_dir := inner.get_next()
				while not ver_dir.is_empty():
					if inner.current_is_dir():
						var full_path := pack_dir_path.path_join(ver_dir)
						var manifest := CapabilityPackManifest.load_from_directory(full_path)
						results.append({
							"id": pack_id_dir,
							"version": ver_dir,
							"dir_path": full_path,
							"manifest": manifest,
						})
					ver_dir = inner.get_next()
				inner.list_dir_end()
		pack_id_dir = root_dir.get_next()
	root_dir.list_dir_end()
	return results


static func install_from_directory(source_dir: String) -> Dictionary:
	## Copies a pack directory into Documents/Synesyn/synesyn/packs/<id>/<version>/.
	## Returns {ok, id, version, error}.
	var manifest := CapabilityPackManifest.load_from_directory(source_dir)
	if not manifest.is_valid:
		return {"ok": false, "error": "Invalid manifest: %s" % str(manifest.validation_errors)}

	var dest := packs_root().path_join(manifest.id).path_join(manifest.version)
	DirAccess.make_dir_recursive_absolute(dest)

	var copy_ok := _copy_dir_recursive(source_dir, dest)
	if not copy_ok:
		return {"ok": false, "error": "Failed to copy pack files to %s" % dest}

	# Re-validate from installed location
	var installed := CapabilityPackManifest.load_from_directory(dest)
	if not installed.is_valid:
		return {"ok": false, "error": "Installed pack validation failed: %s" % str(installed.validation_errors)}

	print("[PackStore] Installed: %s v%s -> %s" % [manifest.id, manifest.version, dest])
	return {"ok": true, "id": manifest.id, "version": manifest.version}


static func uninstall(pack_id: String, pack_version: String) -> Dictionary:
	## Removes an installed pack version. Returns {ok, error}.
	var pack_path := packs_root().path_join(pack_id).path_join(pack_version)
	if not DirAccess.dir_exists_absolute(pack_path):
		return {"ok": false, "error": "Pack not found: %s/%s" % [pack_id, pack_version]}

	var removed := _remove_dir_recursive(pack_path)
	if not removed:
		return {"ok": false, "error": "Failed to remove pack directory"}

	# Clean up parent if empty
	var parent_path := packs_root().path_join(pack_id)
	var parent := DirAccess.open(parent_path)
	if parent:
		parent.list_dir_begin()
		var has_children := false
		var child_name := parent.get_next()
		while not child_name.is_empty():
			has_children = true
			break
		parent.list_dir_end()
		if not has_children:
			DirAccess.remove_absolute(parent_path)

	# Remove config entry
	var cfg := _load_config()
	var packs_cfg_any: Variant = cfg.get("packs", {})
	if typeof(packs_cfg_any) == TYPE_DICTIONARY:
		var key := "%s/%s" % [pack_id, pack_version]
		if (packs_cfg_any as Dictionary).has(key):
			(packs_cfg_any as Dictionary).erase(key)
			cfg["packs"] = packs_cfg_any
			_save_config(cfg)

	print("[PackStore] Uninstalled: %s v%s" % [pack_id, pack_version])
	return {"ok": true}


static func mark_bundled_dismissed(pack_id: String) -> void:
	## Record that the user explicitly uninstalled a bundled pack so it won't auto-reinstall.
	var cfg := _load_config()
	var dismissed_any: Variant = cfg.get("dismissed_bundled", [])
	if typeof(dismissed_any) != TYPE_ARRAY:
		dismissed_any = []
	var dismissed: Array = dismissed_any
	if pack_id not in dismissed:
		dismissed.append(pack_id)
	cfg["dismissed_bundled"] = dismissed
	_save_config(cfg)


static func is_bundled_dismissed(pack_id: String) -> bool:
	## Returns true if the user previously uninstalled this bundled pack.
	var cfg := _load_config()
	var dismissed_any: Variant = cfg.get("dismissed_bundled", [])
	if typeof(dismissed_any) != TYPE_ARRAY:
		return false
	return pack_id in (dismissed_any as Array)


static func clear_bundled_dismissed(pack_id: String) -> void:
	## Clears the dismissed flag (e.g. if user explicitly re-installs a bundled pack).
	var cfg := _load_config()
	var dismissed_any: Variant = cfg.get("dismissed_bundled", [])
	if typeof(dismissed_any) != TYPE_ARRAY:
		return
	(dismissed_any as Array).erase(pack_id)
	cfg["dismissed_bundled"] = dismissed_any
	_save_config(cfg)


# --- Config (enabled state + secrets) ---

static func is_capability_enabled(pack_id: String, pack_version: String, capability_id: String) -> bool:
	var cfg := _load_config()
	var key := "%s/%s" % [pack_id, pack_version]
	var packs_any: Variant = cfg.get("packs", {})
	if typeof(packs_any) != TYPE_DICTIONARY:
		return false
	var pack_cfg_any: Variant = (packs_any as Dictionary).get(key, {})
	if typeof(pack_cfg_any) != TYPE_DICTIONARY:
		return false
	var enabled_any: Variant = (pack_cfg_any as Dictionary).get("enabled_capabilities", [])
	if typeof(enabled_any) != TYPE_ARRAY:
		return false
	return capability_id in (enabled_any as Array)


static func set_capability_enabled(pack_id: String, pack_version: String, capability_id: String, is_enabled: bool) -> void:
	var cfg := _load_config()
	var key := "%s/%s" % [pack_id, pack_version]
	var packs_any: Variant = cfg.get("packs", {})
	if typeof(packs_any) != TYPE_DICTIONARY:
		packs_any = {}
	var packs: Dictionary = packs_any
	var pack_cfg_any: Variant = packs.get(key, {})
	if typeof(pack_cfg_any) != TYPE_DICTIONARY:
		pack_cfg_any = {}
	var pack_cfg: Dictionary = pack_cfg_any
	var enabled_any: Variant = pack_cfg.get("enabled_capabilities", [])
	if typeof(enabled_any) != TYPE_ARRAY:
		enabled_any = []
	var enabled_list: Array = enabled_any

	if is_enabled and capability_id not in enabled_list:
		enabled_list.append(capability_id)
	elif not is_enabled:
		enabled_list.erase(capability_id)

	pack_cfg["enabled_capabilities"] = enabled_list
	packs[key] = pack_cfg
	cfg["packs"] = packs
	_save_config(cfg)


static func get_secret(pack_id: String, secret_name: String) -> String:
	var cfg := _load_config()
	var secrets_any: Variant = cfg.get("secrets", {})
	if typeof(secrets_any) != TYPE_DICTIONARY:
		return ""
	var key := "%s.%s" % [pack_id, secret_name]
	return str((secrets_any as Dictionary).get(key, ""))


static func set_secret(pack_id: String, secret_name: String, secret_value: String) -> void:
	var cfg := _load_config()
	var secrets_any: Variant = cfg.get("secrets", {})
	if typeof(secrets_any) != TYPE_DICTIONARY:
		secrets_any = {}
	var secrets: Dictionary = secrets_any
	var key := "%s.%s" % [pack_id, secret_name]
	if secret_value.is_empty():
		secrets.erase(key)
	else:
		secrets[key] = secret_value
	cfg["secrets"] = secrets
	_save_config(cfg)


# --- Config file I/O ---

static func _load_config() -> Dictionary:
	var path := packs_root().path_join(CONFIG_FILENAME)
	if not FileAccess.file_exists(path):
		return {"schema_version": CONFIG_SCHEMA_VERSION, "packs": {}, "secrets": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {"schema_version": CONFIG_SCHEMA_VERSION, "packs": {}, "secrets": {}}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"schema_version": CONFIG_SCHEMA_VERSION, "packs": {}, "secrets": {}}
	return parsed


static func _save_config(cfg: Dictionary) -> void:
	ensure_packs_dir()
	var path := packs_root().path_join(CONFIG_FILENAME)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(cfg, "\t"))
		file.close()


# --- Directory utilities ---

static func _copy_dir_recursive(src: String, dest: String) -> bool:
	DirAccess.make_dir_recursive_absolute(dest)
	var dir := DirAccess.open(src)
	if not dir:
		return false
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while not entry_name.is_empty():
		var src_path := src.path_join(entry_name)
		var dest_path := dest.path_join(entry_name)
		if dir.current_is_dir():
			if not _copy_dir_recursive(src_path, dest_path):
				dir.list_dir_end()
				return false
		else:
			var err := dir.copy(src_path, dest_path)
			if err != OK:
				push_warning("[PackStore] Copy failed: %s -> %s (%s)" % [src_path, dest_path, error_string(err)])
				dir.list_dir_end()
				return false
		entry_name = dir.get_next()
	dir.list_dir_end()
	return true


static func _remove_dir_recursive(dir_path: String) -> bool:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return false
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while not entry_name.is_empty():
		var full := dir_path.path_join(entry_name)
		if dir.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		entry_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)
	return true
