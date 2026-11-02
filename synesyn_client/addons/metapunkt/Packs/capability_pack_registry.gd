## Capability Pack runtime registry (v0).
##
## Manages: tool registration into ToolRegistry, UI panel mounting,
## permission enforcement, and hub event emission for pack lifecycle.
extends RefCounted
class_name CapabilityPackRegistry

const PackToolProxyScript = preload("res://addons/metapunkt/Packs/pack_tool_proxy.gd")

var _tool_registry: Object  # ToolRegistry
var _audit_logger: Object   # AuditLogger
var _registered_tool_names: Array[String] = []
var _mounted_panels: Dictionary = {}  # capability_key -> Control node


func _init(tool_registry_ref: Object = null, audit_logger_ref: Object = null):
	_tool_registry = tool_registry_ref
	_audit_logger = audit_logger_ref


# --- Tool registration ---

func register_pack_tools(manifest: CapabilityPackManifest, pack_dir: String) -> Array[String]:
	## Register all enabled tool capabilities from a pack. Returns registered tool names.
	var registered: Array[String] = []
	if not _tool_registry or not _tool_registry.has_method("register_tool"):
		push_warning("[PackRegistry] ToolRegistry missing register_tool()")
		return registered

	for cap in manifest.get_tool_capabilities():
		var cap_id := str(cap.get("capability_id", "")).strip_edges()
		if not CapabilityPackStore.is_capability_enabled(manifest.id, manifest.version, cap_id):
			continue

		var ep: Dictionary = cap.get("entrypoints", {})
		var tool_name_val := str(ep.get("tool_name", "")).strip_edges()
		if tool_name_val.is_empty():
			continue

		var args_schema := _load_schema_file(pack_dir, str(ep.get("args_schema", "")))
		var result_schema := _load_schema_file(pack_dir, str(ep.get("result_schema", "")))
		var exec_mode := str(ep.get("execution_mode", "echo")).strip_edges()

		var proxy := PackToolProxyScript.new(
			tool_name_val,
			manifest.id,
			manifest.version,
			cap_id,
			manifest.description,
			args_schema,
			result_schema,
			exec_mode
		)

		var ok: bool = _tool_registry.call("register_tool", tool_name_val, proxy)
		if ok:
			registered.append(tool_name_val)
			_registered_tool_names.append(tool_name_val)
			_emit_event("capability.tool_registered", {
				"pack_id": manifest.id,
				"pack_version": manifest.version,
				"capability_id": cap_id,
				"tool_name": tool_name_val,
			})
		else:
			push_warning("[PackRegistry] Failed to register tool: %s (already exists?)" % tool_name_val)

	return registered


func unregister_all_pack_tools() -> void:
	if not _tool_registry or not _tool_registry.has_method("unregister_tool"):
		return
	for tool_name_val in _registered_tool_names:
		_tool_registry.call("unregister_tool", tool_name_val)
	_registered_tool_names.clear()


# --- UI panel mounting ---

func mount_ui_panel(manifest: CapabilityPackManifest, cap: Dictionary, pack_dir: String, mount_container: Control) -> bool:
	## Mount a UI panel capability into the given container. Returns true on success.
	var cap_id := str(cap.get("capability_id", "")).strip_edges()
	var ep: Dictionary = cap.get("entrypoints", {})
	var scene_rel := str(ep.get("scene_path", "")).strip_edges()
	if scene_rel.is_empty() or not mount_container:
		return false

	var scene_full := pack_dir.path_join(scene_rel)
	# Use FileAccess for user:// paths (ResourceLoader.exists may miss them).
	if not FileAccess.file_exists(scene_full) and not ResourceLoader.exists(scene_full):
		push_warning("[PackRegistry] UI panel scene not found: %s" % scene_full)
		var placeholder := Label.new()
		placeholder.text = "Panel not loadable: %s" % scene_rel
		placeholder.name = cap_id
		mount_container.add_child(placeholder)
		return false

	var scene_resource: PackedScene = ResourceLoader.load(scene_full) as PackedScene
	if not scene_resource:
		push_warning("[PackRegistry] Failed to load scene: %s" % scene_full)
		return false

	var panel_instance: Control = scene_resource.instantiate() as Control
	if not panel_instance:
		push_warning("[PackRegistry] Scene did not instantiate as Control: %s" % scene_full)
		return false

	var mount_info: Dictionary = ep.get("mount", {})
	var label_text := str(mount_info.get("label", cap_id)).strip_edges()
	panel_instance.name = label_text

	mount_container.add_child(panel_instance)
	var key := "%s/%s/%s" % [manifest.id, manifest.version, cap_id]
	_mounted_panels[key] = panel_instance

	_emit_event("capability.panel_mounted", {
		"pack_id": manifest.id,
		"pack_version": manifest.version,
		"capability_id": cap_id,
		"label": label_text,
	})
	return true


func unmount_all_panels() -> void:
	for key in _mounted_panels:
		var panel_node: Control = _mounted_panels[key]
		if is_instance_valid(panel_node):
			if panel_node.get_parent():
				panel_node.get_parent().remove_child(panel_node)
			panel_node.queue_free()
	_mounted_panels.clear()


# --- Permission enforcement ---

static func check_filesystem_permission(manifest: CapabilityPackManifest, requested_path: String, is_write: bool) -> bool:
	## Returns true if the pack's declared permissions allow the requested path.
	var fs_any: Variant = manifest.permissions.get("filesystem", {})
	if typeof(fs_any) != TYPE_DICTIONARY:
		return false
	var scope_key := "write" if is_write else "read"
	var allowed_any: Variant = (fs_any as Dictionary).get(scope_key, [])
	if typeof(allowed_any) != TYPE_ARRAY:
		return false
	for pattern_any in (allowed_any as Array):
		var pattern := str(pattern_any).strip_edges()
		if pattern.is_empty():
			continue
		if requested_path.match(pattern):
			return true
	return false


static func check_network_permission(manifest: CapabilityPackManifest, requested_domain: String) -> bool:
	## Returns true if the pack's declared permissions allow the requested domain.
	var net_any: Variant = manifest.permissions.get("network", {})
	if typeof(net_any) != TYPE_DICTIONARY:
		return false
	var allow_any: Variant = (net_any as Dictionary).get("allow", [])
	if typeof(allow_any) != TYPE_ARRAY:
		return false
	for domain_any in (allow_any as Array):
		var domain := str(domain_any).strip_edges()
		if domain.is_empty():
			continue
		if requested_domain.match(domain):
			return true
	return false


# --- Hub lifecycle events ---

func emit_pack_installed(manifest: CapabilityPackManifest) -> void:
	_emit_event("capability.pack_installed", {
		"pack_id": manifest.id,
		"pack_version": manifest.version,
		"pack_name": manifest.pack_name,
	})


func emit_pack_removed(pack_id: String, pack_version: String) -> void:
	_emit_event("capability.pack_removed", {"pack_id": pack_id, "pack_version": pack_version})


func emit_pack_enabled(manifest: CapabilityPackManifest, capability_id: String) -> void:
	_emit_event("capability.pack_enabled", {
		"pack_id": manifest.id,
		"pack_version": manifest.version,
		"capability_id": capability_id,
	})


func emit_pack_disabled(manifest: CapabilityPackManifest, capability_id: String) -> void:
	_emit_event("capability.pack_disabled", {
		"pack_id": manifest.id,
		"pack_version": manifest.version,
		"capability_id": capability_id,
	})


func publish_manifest_snapshot(manifest: CapabilityPackManifest) -> void:
	## Publish pack manifest as a hub artifact (best-effort, for traceability).
	if not _audit_logger or not _audit_logger.has_method("hub_create_artifact_inline_json"):
		return
	var inline := {
		"id": manifest.id,
		"version": manifest.version,
		"pack_name": manifest.pack_name,
		"permissions_summary": manifest.get_permission_summary(),
		"capabilities_count": manifest.capabilities.size(),
		"manifest_raw": manifest.raw,
	}
	var meta := {"provenance": {"generated_by": "metapunkt.capability_pack_registry"}}
	_audit_logger.call("hub_create_artifact_inline_json", "metapunkt.capability_pack_manifest.v1", inline, meta)


# --- Refresh all enabled packs ---

func refresh_all(mount_container: Control = null) -> Dictionary:
	## Scan installed packs, register enabled tools, mount enabled UI panels.
	## Returns {tools_registered: int, panels_mounted: int}.
	unregister_all_pack_tools()
	unmount_all_panels()
	# Also clear any orphaned children from the mount container
	if mount_container:
		for child_node in mount_container.get_children():
			mount_container.remove_child(child_node)
			child_node.queue_free()

	var tools_count := 0
	var panels_count := 0

	var installed := CapabilityPackStore.list_installed()
	for pack_info in installed:
		var manifest: CapabilityPackManifest = pack_info.get("manifest")
		if not manifest or not manifest.is_valid:
			continue
		var pack_dir: String = pack_info.get("dir_path", "")

		# Register tools
		var registered := register_pack_tools(manifest, pack_dir)
		tools_count += registered.size()

		# Mount UI panels
		if mount_container:
			for cap in manifest.get_ui_panel_capabilities():
				var cap_id := str(cap.get("capability_id", "")).strip_edges()
				if CapabilityPackStore.is_capability_enabled(manifest.id, manifest.version, cap_id):
					if mount_ui_panel(manifest, cap, pack_dir, mount_container):
						panels_count += 1

	return {"tools_registered": tools_count, "panels_mounted": panels_count}


# --- Internal ---

func _load_schema_file(pack_dir: String, rel_path: String) -> Dictionary:
	var path := rel_path.strip_edges()
	if path.is_empty():
		return {}
	var full := pack_dir.path_join(path)
	if not FileAccess.file_exists(full):
		return {}
	var file := FileAccess.open(full, FileAccess.READ)
	if not file:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}


func _emit_event(event_type: String, payload: Dictionary) -> void:
	if _audit_logger and _audit_logger.has_method("emit_event"):
		_audit_logger.call("emit_event", event_type, payload, "", {"component": "metapunkt.packs"})
	else:
		print("[PackRegistry] %s: %s" % [event_type, str(payload)])
