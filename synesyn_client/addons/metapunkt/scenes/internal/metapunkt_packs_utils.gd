## Metapunkt Packs tab UI builder + logic (v0).
##
## Builds the Packs tab programmatically and handles user interactions.
## Follows the same utility-script pattern as metapunkt_synterface_slots_utils.gd.
extends RefCounted

const CapabilityPackStoreScript = preload("res://addons/metapunkt/Packs/capability_pack_store.gd")
const CapabilityPackManifestScript = preload("res://addons/metapunkt/Packs/capability_pack_manifest.gd")
const CapabilityPackRegistryScript = preload("res://addons/metapunkt/Packs/capability_pack_registry.gd")


# --- Tab creation ---

static func build_packs_tab(tabs_container: TabContainer) -> Dictionary:
	## Creates and returns the Packs tab UI nodes.
	## Root is a ScrollContainer so the whole tab scrolls when the panel is small.

	# Outer scroll (becomes the tab page; TabContainer uses node name as tab title)
	var scroll_root := ScrollContainer.new()
	scroll_root.name = "Packs"
	scroll_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_root.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	# Margin for inner padding
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 4)
	scroll_root.add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)

	# Button bar
	var btn_bar := HBoxContainer.new()
	btn_bar.name = "PackButtonBar"
	btn_bar.add_theme_constant_override("separation", 6)

	var install_btn := Button.new()
	install_btn.name = "PackInstallButton"
	install_btn.text = "Install from folder..."
	install_btn.tooltip_text = "Install a Capability Pack from a folder on your filesystem.\nThe folder must contain a valid pack.json manifest."
	btn_bar.add_child(install_btn)

	var reinstall_bundled_btn := Button.new()
	reinstall_bundled_btn.name = "PackReinstallBundledButton"
	reinstall_bundled_btn.text = "Reinstall bundled..."
	reinstall_bundled_btn.tooltip_text = "Reinstall any bundled Capability Packs that were previously uninstalled.\nBundled packs (e.g. Demo Echo, DevAgent) ship with Synesyn and can always be restored."
	btn_bar.add_child(reinstall_bundled_btn)

	var refresh_btn := Button.new()
	refresh_btn.name = "PackRefreshButton"
	refresh_btn.text = "Refresh"
	btn_bar.add_child(refresh_btn)

	var uninstall_btn := Button.new()
	uninstall_btn.name = "PackUninstallButton"
	uninstall_btn.text = "Uninstall selected"
	uninstall_btn.tooltip_text = "Remove the selected pack from Documents/Synesyn/synesyn/packs/.\nYou can reinstall bundled packs at any time via 'Reinstall bundled…'."
	btn_bar.add_child(uninstall_btn)

	root.add_child(btn_bar)

	# Status
	var status_label := Label.new()
	status_label.name = "PackStatus"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(status_label)

	var top_sep := HSeparator.new()
	root.add_child(top_sep)

	# Split: pack list (left) + details/panels (right)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Pack list
	var pack_list := ItemList.new()
	pack_list.name = "PackList"
	pack_list.custom_minimum_size = Vector2(200, 100)
	pack_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(pack_list)

	# Right side: details + capability toggles + panels mount area
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 4)

	var details_label := Label.new()
	details_label.name = "PackDetailsLabel"
	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	details_label.custom_minimum_size = Vector2(0, 48)
	right_vbox.add_child(details_label)

	# Capability toggles (populated dynamically)
	var caps_sep := HSeparator.new()
	right_vbox.add_child(caps_sep)

	var caps_header := Label.new()
	caps_header.text = "Capabilities:"
	right_vbox.add_child(caps_header)

	var caps_container := VBoxContainer.new()
	caps_container.name = "PackCapsContainer"
	caps_container.add_theme_constant_override("separation", 2)
	right_vbox.add_child(caps_container)

	# Panels mount area
	var panels_sep := HSeparator.new()
	right_vbox.add_child(panels_sep)

	var panels_header := Label.new()
	panels_header.text = "Pack Panels:"
	right_vbox.add_child(panels_header)

	var panels_container := TabContainer.new()
	panels_container.name = "PackPanelsContainer"
	panels_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panels_container.custom_minimum_size = Vector2(0, 100)
	right_vbox.add_child(panels_container)

	right_scroll.add_child(right_vbox)
	split.add_child(right_scroll)
	root.add_child(split)

	# File dialog for install
	var install_dialog := FileDialog.new()
	install_dialog.name = "PackInstallDialog"
	install_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	install_dialog.title = "Select Pack Directory"
	install_dialog.access = FileDialog.ACCESS_FILESYSTEM
	root.add_child(install_dialog)

	tabs_container.add_child(scroll_root)
	return {
		"root": scroll_root,
		"list": pack_list,
		"status": status_label,
		"details": details_label,
		"caps_container": caps_container,
		"panels_container": panels_container,
		"install_dialog": install_dialog,
		"install_btn": install_btn,
		"reinstall_bundled_btn": reinstall_bundled_btn,
		"refresh_btn": refresh_btn,
		"uninstall_btn": uninstall_btn,
	}


# --- Refresh pack list ---

static func refresh_pack_list(pack_list: ItemList, status_label: Label) -> Array[Dictionary]:
	## Refreshes the ItemList with installed packs. Returns the installed packs array.
	var installed := CapabilityPackStoreScript.list_installed()
	pack_list.clear()
	for pack_info in installed:
		var manifest: CapabilityPackManifestScript = pack_info.get("manifest")
		if not manifest:
			continue
		var display_name := manifest.pack_name if not manifest.pack_name.is_empty() else manifest.id
		var label_text := "%s v%s" % [display_name, manifest.version]
		if not manifest.is_valid:
			label_text += " [INVALID]"
		var idx := pack_list.item_count
		pack_list.add_item(label_text)
		pack_list.set_item_metadata(idx, pack_info)
	if status_label:
		status_label.text = "%d pack(s) installed" % installed.size()
	return installed


# --- Show pack details ---

static func show_pack_details(pack_info: Dictionary, details_label: Label, caps_container: VBoxContainer, registry: CapabilityPackRegistryScript) -> void:
	# Clear caps container
	for child_node in caps_container.get_children():
		child_node.queue_free()

	var manifest: CapabilityPackManifestScript = pack_info.get("manifest")
	if not manifest:
		details_label.text = "(no manifest)"
		return

	var lines: Array[String] = []
	lines.append("ID: %s" % manifest.id)
	lines.append("Version: %s" % manifest.version)
	if not manifest.author.is_empty():
		lines.append("Author: %s" % manifest.author)
	if not manifest.description.is_empty():
		lines.append(manifest.description)
	lines.append("Permissions: %s" % manifest.get_permission_summary())
	if not manifest.is_valid:
		lines.append("ERRORS: %s" % str(manifest.validation_errors))
	details_label.text = "\n".join(lines)

	# Build capability toggles
	for cap in manifest.capabilities:
		var cap_id := str(cap.get("capability_id", "")).strip_edges()
		var cap_type := str(cap.get("type", "")).strip_edges()
		var is_enabled := CapabilityPackStoreScript.is_capability_enabled(manifest.id, manifest.version, cap_id)

		var hbox := HBoxContainer.new()
		var toggle := CheckButton.new()
		toggle.text = "%s [%s]" % [cap_id, cap_type]
		toggle.button_pressed = is_enabled
		toggle.toggled.connect(func(is_pressed: bool):
			CapabilityPackStoreScript.set_capability_enabled(manifest.id, manifest.version, cap_id, is_pressed)
			if registry:
				if is_pressed:
					registry.emit_pack_enabled(manifest, cap_id)
				else:
					registry.emit_pack_disabled(manifest, cap_id)
		)
		hbox.add_child(toggle)

		if cap_type == "tool":
			var ep: Dictionary = cap.get("entrypoints", {})
			var tool_label := Label.new()
			tool_label.text = "-> %s" % str(ep.get("tool_name", ""))
			hbox.add_child(tool_label)

		caps_container.add_child(hbox)


# --- Install pack ---

static func install_pack_from_path(source_path: String, status_label: Label, registry: CapabilityPackRegistryScript) -> bool:
	var result := CapabilityPackStoreScript.install_from_directory(source_path)
	if not bool(result.get("ok", false)):
		if status_label:
			status_label.text = "Install failed: %s" % str(result.get("error", "unknown"))
		return false
	# Clear dismissed flag so auto-install doesn't skip this pack in future
	var installed_id := str(result.get("id", ""))
	if not installed_id.is_empty():
		CapabilityPackStoreScript.clear_bundled_dismissed(installed_id)
	if status_label:
		status_label.text = "Installed: %s v%s" % [result.get("id", ""), result.get("version", "")]

	# Emit hub event + publish manifest snapshot
	if registry:
		var manifest := CapabilityPackManifestScript.load_from_directory(
			CapabilityPackStoreScript.packs_root().path_join(str(result.get("id", ""))).path_join(str(result.get("version", "")))
		)
		if manifest.is_valid:
			registry.emit_pack_installed(manifest)
			registry.publish_manifest_snapshot(manifest)
	return true


# --- Reinstall bundled packs ---

static func reinstall_bundled_packs(status_label: Label, registry: CapabilityPackRegistryScript) -> int:
	## Re-installs any bundled packs that have been previously uninstalled/dismissed.
	## Returns the count of packs reinstalled.
	var bundled_root := "res://addons/metapunkt/Packs"
	var dir := DirAccess.open(bundled_root)
	if not dir:
		if status_label:
			status_label.text = "Reinstall failed: could not open bundled packs directory."
		return 0

	var installed_before: Array[Dictionary] = CapabilityPackStoreScript.list_installed()
	var installed_ids: Array[String] = []
	for pack_entry in installed_before:
		installed_ids.append(str(pack_entry.get("id", "")))

	var reinstalled: Array[String] = []
	var skipped: Array[String] = []

	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while not entry_name.is_empty():
		if dir.current_is_dir() and not entry_name.begins_with(".") and not entry_name.begins_with("_"):
			var pack_dir := bundled_root.path_join(entry_name)
			if FileAccess.file_exists(pack_dir.path_join("pack.json")):
				var manifest := CapabilityPackManifestScript.load_from_directory(pack_dir)
				if not manifest.is_valid:
					skipped.append("%s (invalid manifest)" % entry_name)
				elif manifest.id in installed_ids:
					skipped.append("%s (already installed)" % manifest.id)
				else:
					# Clear the dismissed flag so auto-install will also recognise it.
					CapabilityPackStoreScript.clear_bundled_dismissed(manifest.id)
					var result: Dictionary = CapabilityPackStoreScript.install_from_directory(pack_dir)
					if bool(result.get("ok", false)):
						# Enable all capabilities by default for bundled packs.
						for cap_any in manifest.capabilities:
							if typeof(cap_any) == TYPE_DICTIONARY:
								var cap_id := str((cap_any as Dictionary).get("capability_id", ""))
								if not cap_id.is_empty():
									CapabilityPackStoreScript.set_capability_enabled(manifest.id, manifest.version, cap_id, true)
						reinstalled.append("%s v%s" % [manifest.id, manifest.version])
						if registry:
							registry.emit_pack_installed(manifest)
							registry.publish_manifest_snapshot(manifest)
					else:
						skipped.append("%s (%s)" % [manifest.id, str(result.get("error", "unknown"))])
		entry_name = dir.get_next()
	dir.list_dir_end()

	if status_label:
		if reinstalled.is_empty():
			if skipped.is_empty():
				status_label.text = "No bundled packs found."
			else:
				status_label.text = "Nothing to reinstall — all bundled packs already installed."
		else:
			status_label.text = "Reinstalled %d bundled pack(s): %s" % [reinstalled.size(), ", ".join(reinstalled)]

	return reinstalled.size()


# --- Uninstall pack ---

static func uninstall_selected(pack_list: ItemList, status_label: Label, registry: CapabilityPackRegistryScript) -> void:
	var selected := pack_list.get_selected_items()
	if selected.is_empty():
		if status_label:
			status_label.text = "Select a pack to uninstall"
		return
	var idx: int = int(selected[0])
	var pack_info: Dictionary = pack_list.get_item_metadata(idx)
	var pack_id := str(pack_info.get("id", ""))
	var pack_version := str(pack_info.get("version", ""))
	if pack_id.is_empty():
		return

	var result := CapabilityPackStoreScript.uninstall(pack_id, pack_version)
	if bool(result.get("ok", false)):
		# Mark as dismissed so auto-install doesn't re-install bundled packs
		CapabilityPackStoreScript.mark_bundled_dismissed(pack_id)
		if status_label:
			status_label.text = "Uninstalled: %s v%s" % [pack_id, pack_version]
		if registry:
			registry.emit_pack_removed(pack_id, pack_version)
	else:
		if status_label:
			status_label.text = "Uninstall failed: %s" % str(result.get("error", "unknown"))
