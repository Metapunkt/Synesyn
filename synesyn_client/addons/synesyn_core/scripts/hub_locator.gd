## Purpose: Single source of truth for locating the Synesyn Hub executable.
##
## Production contract (ADR 0018): the hub ships as the flattened contents of a
## PyInstaller one-dir bundle, placed beside the Godot executable:
##
##     Synesyn/
##       Synesyn.exe
##       services/synesyn_hub/synesyn_hub.exe
##       services/synesyn_hub/_internal/...
##
## Exactly one production location is probed. `dist/synesyn_hub/` is PyInstaller
## build output that packaging flattens away, so it is never shipped and is only
## consulted in editor runs, where the Godot project is a *sibling* of `services/`
## rather than living inside the packaged root.
extends RefCounted
class_name HubLocator

const SERVICES_DIR_NAME := "services"
const HUB_DIR_NAME := "synesyn_hub"

static func get_exe_name() -> String:
	return "synesyn_hub.exe" if OS.get_name() == "Windows" else "synesyn_hub"

## Path the hub occupies relative to the packaged application root.
static func get_canonical_relative_path() -> String:
	return SERVICES_DIR_NAME.path_join(HUB_DIR_NAME).path_join(get_exe_name())

## The only location a packaged install may keep the hub.
static func get_production_path() -> String:
	var app_dir := OS.get_executable_path().get_base_dir()
	if app_dir.is_empty():
		return ""
	return app_dir.path_join(get_canonical_relative_path())

## Editor-only locations. In the repo the Godot project sits beside `services/`,
## and a fresh build lands in `dist/synesyn_hub/` until packaging flattens it.
## Exported builds return nothing here so production never probes a build tree.
static func get_dev_paths() -> PackedStringArray:
	if not OS.has_feature("editor"):
		return PackedStringArray()
	var project_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	if project_dir.is_empty():
		return PackedStringArray()
	var hub_dir := project_dir.get_base_dir().path_join(SERVICES_DIR_NAME).path_join(HUB_DIR_NAME)
	return PackedStringArray([
		hub_dir.path_join("dist").path_join(HUB_DIR_NAME).path_join(get_exe_name()),
		hub_dir.path_join(get_exe_name()),
	])

## User override from `hub.exec_path`. Empty when unset.
static func get_configured_path(cfg: Dictionary) -> String:
	var hub_cfg_any: Variant = cfg.get("hub", {})
	var hub_cfg: Dictionary = hub_cfg_any as Dictionary if typeof(hub_cfg_any) == TYPE_DICTIONARY else {}
	return String(hub_cfg.get("exec_path", "")).strip_edges().replace("\\", "/")

## Full search order, highest precedence first. Useful for diagnostics.
static func get_searched_paths(cfg: Dictionary = {}) -> PackedStringArray:
	var paths := PackedStringArray()
	var configured := get_configured_path(cfg)
	if not configured.is_empty():
		paths.append(configured)
	var production := get_production_path()
	if not production.is_empty():
		paths.append(production)
	for dev_path in get_dev_paths():
		paths.append(dev_path)
	return paths

## Returns "" when the hub is absent. Callers must treat that as "cannot
## autostart" rather than passing a guessed path to a process launcher.
static func find_hub_exe(cfg: Dictionary = {}) -> String:
	for candidate in get_searched_paths(cfg):
		if FileAccess.file_exists(candidate):
			return candidate
	return ""

## For UI prefill only: where the hub *should* live, whether or not it exists.
static func get_suggested_path(cfg: Dictionary = {}) -> String:
	var found := find_hub_exe(cfg)
	if not found.is_empty():
		return found
	var production := get_production_path()
	if not production.is_empty():
		return production
	var dev_paths := get_dev_paths()
	return dev_paths[0] if dev_paths.size() > 0 else ""

## Operator-facing description of the expected install location.
static func describe_expected_location() -> String:
	return "%s (beside the Synesyn executable)" % get_canonical_relative_path()
