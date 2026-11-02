## Purpose: Internal wiring helpers for SyntreePanel (UI + manager signal hookups, initial UI sizing).
@tool
extends RefCounted
class_name SyntreePanelWiring

const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")

static func normalize_manage_sources_menu_popup(panel: Object) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel.manage_sources_menu_button):
		return
	var mb: MenuButton = panel.manage_sources_menu_button as MenuButton
	if not is_instance_valid(mb):
		return
	var popup: PopupMenu = mb.get_popup()
	if not is_instance_valid(popup):
		return
	for i in range(popup.item_count):
		if popup.get_item_id(i) == int(panel.MENU_ID_PUBLISH_CONTEXT_GRAPH):
			popup.set_item_text(i, "Publish Context Graph")
			popup.set_item_tooltip(i, "Publish the current SynTree context graph to the Hub as a ui.context_graph artifact.")
			break

static func install_latent_reality_menu_items(panel: Object) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel.manage_sources_menu_button):
		return
	var mb: MenuButton = panel.manage_sources_menu_button as MenuButton
	if not is_instance_valid(mb):
		return
	var popup: PopupMenu = mb.get_popup()
	if not is_instance_valid(popup):
		return
	for i in range(popup.item_count):
		if popup.get_item_id(i) == int(panel.MENU_ID_PUBLISH_CONTEXT_GRAPH):
			popup.set_item_text(i, "Publish Context Graph")
			popup.set_item_tooltip(i, "Publish the current SynTree context graph to the Hub as a ui.context_graph artifact.")
			return
	popup.add_separator()
	popup.add_item("Publish Context Graph", int(panel.MENU_ID_PUBLISH_CONTEXT_GRAPH))
	var idx: int = popup.item_count - 1
	popup.set_item_tooltip(idx, "Publish the current SynTree context graph to the Hub as a ui.context_graph artifact.")

static func clamp_manage_sources_popup_width_only(panel: Object) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel.manage_sources_menu_button):
		return
	var pctrl: Control = panel as Control
	if not is_instance_valid(pctrl):
		return
	var mb: MenuButton = panel.manage_sources_menu_button as MenuButton
	if not is_instance_valid(mb):
		return
	var popup: PopupMenu = mb.get_popup()
	if not is_instance_valid(popup):
		return
	var vp: Vector2 = pctrl.get_viewport_rect().size
	var max_w: int = int(min(520.0, max(300.0, vp.x - 60.0)))
	var cur_w: int = int(popup.size.x)
	if cur_w <= max_w:
		return
	var center_x := float(popup.position.x) + float(cur_w) * 0.5
	popup.size = Vector2i(max_w, popup.size.y)
	var new_x := int(round(center_x - float(max_w) * 0.5))
	new_x = clamp(new_x, 10, int(vp.x) - max_w - 10)
	popup.position = Vector2i(new_x, popup.position.y)

static func setup_initial_ui_state(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	# Set up content sources container with resize handle
	panel.content_sources_container.visible = true
	panel.content_sources_container.set_deferred("custom_minimum_size", Vector2(0, 400))
	panel.content_sources_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var sources_resize_handle = panel.ResizeHandle.new()
	sources_resize_handle.parent_container = panel.content_sources_container
	sources_resize_handle.min_size = 100
	panel.content_sources_container.get_parent().add_child(sources_resize_handle)
	panel.content_sources_container.get_parent().move_child(sources_resize_handle, panel.content_sources_container.get_index() + 1)

	# Set up chat history container
	panel.chat_history_container.set_deferred("custom_minimum_size", Vector2(0, 600))
	panel.chat_history_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.chat_history_container.size_flags_vertical = Control.SIZE_FILL

	var chat_resize_handle = panel.ResizeHandle.new()
	chat_resize_handle.parent_container = panel.chat_history_container
	chat_resize_handle.min_size = 200
	panel.chat_history_container.get_parent().add_child(chat_resize_handle)
	panel.chat_history_container.get_parent().move_child(chat_resize_handle, panel.chat_history_container.get_index() + 1)

	# Set up content source UI
	panel.content_source_list_options.clear()
	panel.content_source_list_options.add_item("All Sources", 0)

	# Set up thread dropdown
	panel.thread_dropdown.clear()
	panel.thread_dropdown.add_item("Select Thread")

	# Initialize content directory path
	var initial_dir := String(panel.DEFAULT_CONTENT_SOURCES_DIR)
	var wiring_bus := SynTreeAutoloads.content_bus()
	var cs_state = wiring_bus.get_content_state_resource() if is_instance_valid(wiring_bus) and wiring_bus.has_method("get_content_state_resource") else null
	if is_instance_valid(cs_state):
		var cs_any: Variant = cs_state.get("content_source")
		if is_instance_valid(cs_any) and (cs_any as Object).has_method("get"):
			var configured_any: Variant = (cs_any as Object).get("sources_directory")
			var configured := str(configured_any).strip_edges()
			if not configured.is_empty():
				initial_dir = configured
	if is_instance_valid(panel.content_dir_path_label):
		panel.content_dir_path_label.text = initial_dir

	# Ensure initial visibility states
	if panel.has_method("_update_layout_visibility"):
		panel._update_layout_visibility()

	# Set initial filter label state
	if is_instance_valid(panel.active_filters_label):
		panel.active_filters_label.text = "Filters: None"
		panel.active_filters_label.tooltip_text = "No filters currently active."

static func connect_manager_signals(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	print("SynTreePanel: Connecting manager signals...")
	if panel._conversation_manager:
		if not panel._conversation_manager.operation_failed.is_connected(panel._on_operation_failed):
			panel._conversation_manager.operation_failed.connect(panel._on_operation_failed)
	if panel._ai_model_manager:
		if not panel._ai_model_manager.operation_failed.is_connected(panel._on_operation_failed):
			panel._ai_model_manager.operation_failed.connect(panel._on_operation_failed)
		panel._setup_model_settings_controller()
		if is_instance_valid(panel._model_settings_controller):
			if not panel._ai_model_manager.model_changed.is_connected(panel._model_settings_controller.sync_ui_from_manager):
				panel._ai_model_manager.model_changed.connect(panel._model_settings_controller.sync_ui_from_manager)
			if (
				panel._ai_model_manager.has_signal("models_changed")
				and not Signal(
					panel._ai_model_manager,
					"models_changed"
				).is_connected(
					panel._model_settings_controller.populate_model_selector
				)
			):
				Signal(
					panel._ai_model_manager,
					"models_changed"
				).connect(
					panel._model_settings_controller.populate_model_selector
				)
			if (
				panel._ai_model_manager.has_signal(
					"provider_status_changed"
				)
				and not Signal(
					panel._ai_model_manager,
					"provider_status_changed"
				).is_connected(
					panel._model_settings_controller.update_ollama_status
				)
			):
				Signal(
					panel._ai_model_manager,
					"provider_status_changed"
				).connect(
					panel._model_settings_controller.update_ollama_status
				)
			if (
				panel._ai_model_manager.has_signal(
					"inference_metrics_updated"
				)
				and not Signal(
					panel._ai_model_manager,
					"inference_metrics_updated"
				).is_connected(
					panel._model_settings_controller.update_inference_metrics
				)
			):
				Signal(
					panel._ai_model_manager,
					"inference_metrics_updated"
				).connect(
					panel._model_settings_controller.update_inference_metrics
				)
	if panel._message_container:
		panel._setup_chat_panel_controller()
		if is_instance_valid(panel._chat_panel_controller):
			if not panel._message_container.edit_history_saved.is_connected(panel._chat_panel_controller.on_edit_history_saved):
				panel._message_container.edit_history_saved.connect(panel._chat_panel_controller.on_edit_history_saved)
			if not panel._message_container.show_edit_history_requested.is_connected(panel._chat_panel_controller.on_show_edit_history):
				panel._message_container.show_edit_history_requested.connect(panel._chat_panel_controller.on_show_edit_history)
			if not panel._message_container.message_resend_requested.is_connected(panel._chat_panel_controller.on_message_resend):
				panel._message_container.message_resend_requested.connect(panel._chat_panel_controller.on_message_resend)
			if not panel._message_container.message_deleted.is_connected(panel._chat_panel_controller.on_message_deleted):
				panel._message_container.message_deleted.connect(panel._chat_panel_controller.on_message_deleted)
	print("SynTreePanel: Manager signals connected")

static func connect_ui_signals(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	print("SynTreePanel: Connecting UI signals...")

	if is_instance_valid(panel.top_toolbar_controls):
		if not panel.top_toolbar_controls.chat_menu_toggled.is_connected(panel._on_chat_menu_toggled):
			panel.top_toolbar_controls.chat_menu_toggled.connect(panel._on_chat_menu_toggled)
		if not panel.top_toolbar_controls.main_menu_toggled.is_connected(panel._on_main_menu_toggled):
			panel.top_toolbar_controls.main_menu_toggled.connect(panel._on_main_menu_toggled)
		if not panel.top_toolbar_controls.output_container_toggled.is_connected(panel._on_toggle_output_container):
			panel.top_toolbar_controls.output_container_toggled.connect(panel._on_toggle_output_container)
		if not panel.top_toolbar_controls.user_input_toggled.is_connected(panel._on_toggle_user_input):
			panel.top_toolbar_controls.user_input_toggled.connect(panel._on_toggle_user_input)
		if not panel.top_toolbar_controls.content_sources_toggled.is_connected(panel._on_toggle_content_sources):
			panel.top_toolbar_controls.content_sources_toggled.connect(panel._on_toggle_content_sources)
		if panel.top_toolbar_controls.has_signal("dev_agent_toggled") and not panel.top_toolbar_controls.dev_agent_toggled.is_connected(panel._on_dev_agent_toggled):
			panel.top_toolbar_controls.dev_agent_toggled.connect(panel._on_dev_agent_toggled)
	else:
		push_warning("SyntreePanel: TopToolbarControls node not found or invalid.")

	if is_instance_valid(panel.bottom_toolbar_controls):
		if not panel.bottom_toolbar_controls.chat_menu_toggled.is_connected(panel._on_chat_menu_toggled):
			panel.bottom_toolbar_controls.chat_menu_toggled.connect(panel._on_chat_menu_toggled)
		if not panel.bottom_toolbar_controls.main_menu_toggled.is_connected(panel._on_main_menu_toggled):
			panel.bottom_toolbar_controls.main_menu_toggled.connect(panel._on_main_menu_toggled)
		if not panel.bottom_toolbar_controls.output_container_toggled.is_connected(panel._on_toggle_output_container):
			panel.bottom_toolbar_controls.output_container_toggled.connect(panel._on_toggle_output_container)
		if not panel.bottom_toolbar_controls.user_input_toggled.is_connected(panel._on_toggle_user_input):
			panel.bottom_toolbar_controls.user_input_toggled.connect(panel._on_toggle_user_input)
		if not panel.bottom_toolbar_controls.content_sources_toggled.is_connected(panel._on_toggle_content_sources):
			panel.bottom_toolbar_controls.content_sources_toggled.connect(panel._on_toggle_content_sources)
		if panel.bottom_toolbar_controls.has_signal("dev_agent_toggled") and not panel.bottom_toolbar_controls.dev_agent_toggled.is_connected(panel._on_dev_agent_toggled):
			panel.bottom_toolbar_controls.dev_agent_toggled.connect(panel._on_dev_agent_toggled)
	else:
		push_warning("SyntreePanel: BottomToolbarControls node not found or invalid.")

	# Conversation tab behavior: bottom bar should adapt to the active tab.
	if is_instance_valid(panel.conversation_tabs):
		if not panel.conversation_tabs.tab_selected.is_connected(panel._on_conversation_tab_selected):
			panel.conversation_tabs.tab_selected.connect(panel._on_conversation_tab_selected)
		panel._on_conversation_tab_selected(panel.conversation_tabs.current_tab)
	else:
		push_warning("SyntreePanel: ConversationTabs node not found or invalid.")

	# Scroll buttons
	if is_instance_valid(panel.scroll_top_button) and not panel.scroll_top_button.pressed.is_connected(panel._on_scroll_top_pressed):
		panel.scroll_top_button.pressed.connect(panel._on_scroll_top_pressed)
	if is_instance_valid(panel.scroll_bottom_button) and not panel.scroll_bottom_button.pressed.is_connected(panel._on_scroll_bottom_pressed):
		panel.scroll_bottom_button.pressed.connect(panel._on_scroll_bottom_pressed)

	# Message input
	panel._setup_chat_panel_controller()
	if is_instance_valid(panel.message_input) and is_instance_valid(panel._chat_panel_controller) and not panel.message_input.text_changed.is_connected(panel._chat_panel_controller.on_message_input_changed):
		panel.message_input.text_changed.connect(panel._chat_panel_controller.on_message_input_changed)
	# NOTE: SendButton is scene-wired to `SyntreePanel._on_send_button_pressed()` for editor reliability.

	# Thread management
	# NOTE: ThreadDropdown + NewThreadButton are scene-wired to SyntreePanel wrapper methods for editor reliability.
	if is_instance_valid(panel.new_thread_name_input):
		panel.new_thread_name_input.tooltip_text = "Type a thread name here, then click “Create New Thread”."
	if is_instance_valid(panel.new_thread_button):
		panel.new_thread_button.tooltip_text = "Enter a thread name in the field, then click to create/switch threads."

	if is_instance_valid(panel.thread_hub_versions_button):
		# NOTE: ThreadHubVersionsButton is scene-wired to `SyntreePanel._on_thread_hub_versions_button_pressed()`.
		pass
	if is_instance_valid(panel.thread_hub_versions_list):
		panel._setup_status_hub_controller()
		if is_instance_valid(panel._status_hub_controller) and not panel.thread_hub_versions_list.item_activated.is_connected(panel._status_hub_controller.on_thread_hub_version_activated):
			panel.thread_hub_versions_list.item_activated.connect(panel._status_hub_controller.on_thread_hub_version_activated)
	if is_instance_valid(panel.open_threads_folder_button):
		# Prefer panel-owned handler so opening uses the same directory logic and
		# works even if the status controller is not running.
		if not panel.open_threads_folder_button.pressed.is_connected(panel._on_open_threads_folder_pressed):
			panel.open_threads_folder_button.pressed.connect(panel._on_open_threads_folder_pressed)

	# AI model + provider selectors
	panel._setup_model_settings_controller()
	if is_instance_valid(panel.ai_model_selector) and is_instance_valid(panel._model_settings_controller) and not panel.ai_model_selector.item_selected.is_connected(panel._model_settings_controller.on_model_selected):
		panel.ai_model_selector.item_selected.connect(panel._model_settings_controller.on_model_selected)
	if is_instance_valid(panel.api_provider_selector) and is_instance_valid(panel._model_settings_controller) and not panel.api_provider_selector.item_selected.is_connected(panel._model_settings_controller.on_api_provider_selected):
		panel.api_provider_selector.item_selected.connect(panel._model_settings_controller.on_api_provider_selected)
	if is_instance_valid(panel.api_key_input) and is_instance_valid(panel._model_settings_controller) and not panel.api_key_input.text_changed.is_connected(panel._model_settings_controller.on_api_key_changed):
		panel.api_key_input.text_changed.connect(panel._model_settings_controller.on_api_key_changed)
	if (
		is_instance_valid(panel.apply_ollama_endpoint_button)
		and is_instance_valid(panel._model_settings_controller)
		and not panel.apply_ollama_endpoint_button.pressed.is_connected(
			panel._model_settings_controller.on_apply_ollama_endpoint
		)
	):
		panel.apply_ollama_endpoint_button.pressed.connect(
			panel._model_settings_controller.on_apply_ollama_endpoint
		)
	if (
		is_instance_valid(panel.refresh_ollama_models_button)
		and is_instance_valid(panel._model_settings_controller)
		and not panel.refresh_ollama_models_button.pressed.is_connected(
			panel._model_settings_controller.on_refresh_ollama_models
		)
	):
		panel.refresh_ollama_models_button.pressed.connect(
			panel._model_settings_controller.on_refresh_ollama_models
		)

	# Content source management
	if is_instance_valid(panel.create_source_menu_button):
		var mb1: MenuButton = panel.create_source_menu_button as MenuButton
		var p1: PopupMenu = (mb1.get_popup() if is_instance_valid(mb1) else null)
		if is_instance_valid(p1) and not p1.id_pressed.is_connected(panel._on_create_sources_menu_pressed):
			p1.id_pressed.connect(panel._on_create_sources_menu_pressed)
	if is_instance_valid(panel.manage_sources_menu_button):
		var mb2: MenuButton = panel.manage_sources_menu_button as MenuButton
		var p2: PopupMenu = (mb2.get_popup() if is_instance_valid(mb2) else null)
		if is_instance_valid(p2) and not p2.id_pressed.is_connected(panel._on_manage_sources_menu_pressed):
			p2.id_pressed.connect(panel._on_manage_sources_menu_pressed)
		if is_instance_valid(p2) and not p2.about_to_popup.is_connected(panel._on_manage_sources_about_to_popup):
			p2.about_to_popup.connect(panel._on_manage_sources_about_to_popup)
	if is_instance_valid(panel.save_content_sources_button) and not panel.save_content_sources_button.pressed.is_connected(panel._on_save_content_sources):
		panel.save_content_sources_button.pressed.connect(panel._on_save_content_sources)

	if is_instance_valid(panel.content_source_menu_button) and not panel.content_source_menu_button.pressed.is_connected(panel._on_content_source_menu_button_pressed):
		panel.content_source_menu_button.pressed.connect(panel._on_content_source_menu_button_pressed)

	# Footer wiring
	if is_instance_valid(panel.delete_source_button) and not panel.delete_source_button.pressed.is_connected(panel._on_delete_source_btn_pressed):
		panel.delete_source_button.pressed.connect(panel._on_delete_source_btn_pressed)
	if is_instance_valid(panel.filter_button) and not panel.filter_button.pressed.is_connected(panel._on_footer_filter_pressed):
		panel.filter_button.pressed.connect(panel._on_footer_filter_pressed)
	if is_instance_valid(panel.stats_button) and not panel.stats_button.pressed.is_connected(panel._on_footer_stats_pressed):
		panel.stats_button.pressed.connect(panel._on_footer_stats_pressed)
	if is_instance_valid(panel.search_box):
		panel.search_box.placeholder_text = "Search sources… (Enter to select)"
		panel.search_box.tooltip_text = "Type a source name/id/path keyword and press Enter to select the best match."
		if not panel.search_box.text_submitted.is_connected(panel._on_footer_search_submitted):
			panel.search_box.text_submitted.connect(panel._on_footer_search_submitted)
	panel._setup_footer_refresh_menu()

	# Filter popup wiring
	var filter_popup = panel.get_node_or_null("%FilterPopup")
	if is_instance_valid(filter_popup):
		if is_instance_valid(panel.content_list_view) and filter_popup.has_signal("filters_applied"):
			if not filter_popup.filters_applied.is_connected(panel.content_list_view._on_filters_applied):
				filter_popup.filters_applied.connect(panel.content_list_view._on_filters_applied)
		if filter_popup.has_signal("filters_applied") and not filter_popup.filters_applied.is_connected(panel._update_active_filters_label):
			filter_popup.filters_applied.connect(panel._update_active_filters_label)
	else:
		push_warning("SyntreePanel: FilterPopup node not found or invalid; filtering will not work.")

	if is_instance_valid(filter_popup) and filter_popup.has_method("set_resources") and is_instance_valid(panel._content_state_resource):
		filter_popup.set_resources(panel._content_state_resource)
	var stats_popup = panel.get_node_or_null("%StatsPopup")
	if is_instance_valid(stats_popup) and stats_popup.has_method("set_resources") and is_instance_valid(panel._content_state_resource):
		stats_popup.set_resources(panel._content_state_resource)

	# Window detachment
	if is_instance_valid(panel.detach_panel_button) and not panel.detach_panel_button.toggled.is_connected(panel._on_detach_panel_toggled):
		panel.detach_panel_button.toggled.connect(panel._on_detach_panel_toggled)

	# Edit history + content directory
	if is_instance_valid(panel.edit_history_button) and is_instance_valid(panel._chat_panel_controller) and not panel.edit_history_button.pressed.is_connected(panel._chat_panel_controller.on_edit_history_pressed):
		panel.edit_history_button.pressed.connect(panel._chat_panel_controller.on_edit_history_pressed)
	if is_instance_valid(panel.save_history_button) and is_instance_valid(panel._chat_panel_controller) and not panel.save_history_button.pressed.is_connected(panel._chat_panel_controller.on_save_history_pressed):
		panel.save_history_button.pressed.connect(panel._chat_panel_controller.on_save_history_pressed)
	if is_instance_valid(panel.cancel_edit_button) and is_instance_valid(panel._chat_panel_controller) and not panel.cancel_edit_button.pressed.is_connected(panel._chat_panel_controller.on_cancel_edit_pressed):
		panel.cancel_edit_button.pressed.connect(panel._chat_panel_controller.on_cancel_edit_pressed)
	if is_instance_valid(panel.change_content_dir_button):
		panel._setup_content_sources_panel_controller()
		if is_instance_valid(panel._content_sources_panel_controller) and not panel.change_content_dir_button.pressed.is_connected(panel._content_sources_panel_controller.begin_change_content_dir):
			panel.change_content_dir_button.pressed.connect(panel._content_sources_panel_controller.begin_change_content_dir)
	if is_instance_valid(panel.content_source_list_options) and not panel.content_source_list_options.item_selected.is_connected(panel._on_content_source_selected):
		panel.content_source_list_options.item_selected.connect(panel._on_content_source_selected)
