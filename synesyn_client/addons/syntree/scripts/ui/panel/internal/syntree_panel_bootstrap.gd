## Purpose: Internal bootstrap helpers for SyntreePanel (setup, resource injection, view-manager instantiation).
@tool
extends RefCounted
class_name SyntreePanelBootstrap

const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")

static func initialize_notification_manager(panel: Object) -> bool:
	if not is_instance_valid(panel):
		return false

	# Idempotency guard: if the manager is already alive in the tree, just keep it and
	# re-register with ContentBus. Destroying and recreating it on every setup() call
	# (e.g. when the runtime bootstrap re-runs) is unnecessary and can cause subtle
	# reference-invalidation bugs when the old manager is queue_free()'d while still
	# referenced elsewhere.
	if is_instance_valid(panel._notification_manager) and panel._notification_manager.is_inside_tree():
		print("SyntreePanel: Notification manager already valid — skipping re-init.")
		var existing_bus := SynTreeAutoloads.content_bus()
		if is_instance_valid(existing_bus):
			existing_bus.register_notification_manager(panel._notification_manager)
		return true

	print("SyntreePanel: Initializing notification manager...")

	# Clean up any stale reference that is no longer in the tree.
	if panel._notification_manager:
		if panel._notification_manager.is_inside_tree():
			panel.remove_child(panel._notification_manager)
		panel._notification_manager.queue_free()
		panel._notification_manager = null

	panel._notification_manager = panel.NotificationManager.new()
	if not panel._notification_manager:
		push_error("SyntreePanel: Failed to create notification manager!")
		return false

	panel.add_child(panel._notification_manager)
	print("SyntreePanel: Notification manager added to scene tree")

	var notification_popup = panel.get_node_or_null("%NotificationPopup")
	if not notification_popup:
		notification_popup = panel.find_child("NotificationPopup", true, false)
	if not notification_popup:
		push_error("SyntreePanel: NotificationPopup not found in scene tree!")
		return false

	notification_popup.hide()
	var setup_result = panel._notification_manager.setup(notification_popup)
	if not setup_result:
		push_error("SyntreePanel: Failed to setup notification manager!")
		return false

	var bus := SynTreeAutoloads.content_bus()
	if is_instance_valid(bus):
		print("SyntreePanel: Registering notification manager with ContentBus")
		bus.register_notification_manager(panel._notification_manager)
		print("SyntreePanel: Notification manager registration complete")
	else:
		push_error("SyntreePanel: ContentBus not available for notification manager registration!")
		return false

	print("SyntreePanel: Notification manager setup complete")
	return true

static func ensure_resources_from_content_bus(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	var pnode: Node = panel as Node
	if not is_instance_valid(pnode):
		return
	# If already injected by setup(), do nothing.
	if is_instance_valid(panel._content_state_resource) and is_instance_valid(panel._view_state_resource):
		panel._wire_content_state_signals()
		return
	if panel._resource_bootstrap_inflight:
		return
	panel._resource_bootstrap_inflight = true
	panel._resource_bootstrap_retry_count += 1

	# Try immediately.
	var bus := SynTreeAutoloads.content_bus()
	if is_instance_valid(bus) and bus.has_method("get_content_state_resource"):
		var cs: Object = bus.get_content_state_resource()
		if is_instance_valid(cs):
			panel._content_state_resource = cs
	if is_instance_valid(bus) and bus.has_method("get_view_state_resource"):
		var vs: Object = bus.get_view_state_resource()
		if is_instance_valid(vs):
			panel._view_state_resource = vs
	panel._wire_content_state_signals()
	panel._resource_bootstrap_inflight = false

	# If still missing, retry a few times (ContentBus may still be initializing).
	if not is_instance_valid(panel._content_state_resource) or not is_instance_valid(panel._view_state_resource):
		if panel._resource_bootstrap_retry_count > 50:
			push_warning("SyntreePanel: Resource bootstrap retries exceeded; ContentBus resources not available.")
			return
		var t: SceneTreeTimer = pnode.get_tree().create_timer(0.10)
		t.timeout.connect(func():
			panel._ensure_resources_from_content_bus()
		)

static func setup_content_view_manager(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	print("SynTreePanel: Setting up content view manager")

	# If the instance was created earlier (e.g. during _ready before ContentBus resources
	# arrived), re-inject resources now that they are available, then return.
	if is_instance_valid(panel.content_view_manager_instance):
		if is_instance_valid(panel._content_state_resource) and is_instance_valid(panel._view_state_resource):
			var ui_references = {
				"sources_tab_container": panel.sources_tab_container,
				"content_list_container": panel.content_list_view,
				"content_hierarchy_node": panel.content_hierarchy,
				"graph_view_node": panel.graph_view,
				"content_state": panel._content_state_resource,
				"view_state": panel._view_state_resource,
				"conversation_manager": panel._conversation_manager
			}
			if panel.content_view_manager_instance.has_method("setup"):
				panel.content_view_manager_instance.setup(ui_references)
				print("SynTreePanel: Re-injected resources into existing ContentViewManager instance.")
		else:
			print("SynTreePanel: ContentViewManager already instantiated, resources still unavailable — skipping.")
		return

	if not is_instance_valid(panel.view_manager_placeholder):
		push_error("SynTreePanel: ContentViewManager placeholder node not found!")
		return
	for child in panel.view_manager_placeholder.get_children():
		panel.view_manager_placeholder.remove_child(child)
		child.queue_free()

	panel.content_view_manager_instance = panel.ContentViewManagerScene.instantiate()
	if not panel.content_view_manager_instance:
		push_error("SynTreePanel: Failed to instantiate ContentViewManagerScene!")
		return
	panel.view_manager_placeholder.add_child(panel.content_view_manager_instance)
	print("SynTreePanel: Instantiated and added ContentViewManager to placeholder.")

	var ui_references = {
		"sources_tab_container": panel.sources_tab_container,
		"content_list_container": panel.content_list_view,
		"content_hierarchy_node": panel.content_hierarchy,
		"graph_view_node": panel.graph_view,
		"content_state": panel._content_state_resource,
		"view_state": panel._view_state_resource,
		"conversation_manager": panel._conversation_manager
	}

	if panel.content_view_manager_instance.has_method("setup"):
		panel.content_view_manager_instance.setup(ui_references)
		print("SynTreePanel: ContentViewManager setup called on instance with TabContainer references")
	else:
		push_error("SynTreePanel: Instantiated ContentViewManager is missing the setup method!")
		panel.content_view_manager_instance.queue_free()
		panel.content_view_manager_instance = null

static func setup_panels(panel: Object) -> void:
	if not is_instance_valid(panel):
		return
	print("SyntreePanel: Setting up panels")

	# Always call setup_content_view_manager: it handles both first-time instantiation
	# and re-injection of resources into an instance created without them during _ready.
	setup_content_view_manager(panel)
	if not is_instance_valid(panel.content_view_manager_instance):
		push_error("SyntreePanel: Failed to setup ContentViewManager instance.")
		return

	if not is_instance_valid(panel._content_state_resource):
		push_error("SyntreePanel: ContentStateResource is invalid during setup_panels!")
		return

	if is_instance_valid(panel.content_hierarchy) and panel.content_hierarchy.has_method("setup_hierarchy"):
		panel.content_hierarchy.setup_hierarchy(panel._content_state_resource, panel._view_state_resource, panel._plugin_ref)
	else:
		push_warning("SyntreePanel: ContentHierarchy node invalid or missing setup_hierarchy method.")

static func setup(panel: Object, plugin_ref, plugin_manager, p_content_state_res, p_view_state_res) -> Dictionary:
	if not is_instance_valid(panel):
		return {"success": false, "error": "Panel not valid"}
	print("SyntreePanel: Starting setup (with injected resources)...")

	panel._plugin_ref = plugin_ref
	if not is_instance_valid(panel._plugin_ref):
		push_warning("SyntreePanel: Invalid plugin reference passed to setup!")
	else:
		print("SyntreePanel: Stored valid plugin reference.")

	if not plugin_manager:
		return {"success": false, "error": "Plugin manager not provided"}

	print("SyntreePanel (setup): Checking injected ContentStateResource...")
	if not is_instance_valid(p_content_state_res):
		push_error("SyntreePanel (setup): Injected ContentStateResource is NOT valid!")
		return {"success": false, "error": "Invalid ContentStateResource provided to setup"}
	else:
		print("  - Injected ContentStateResource is VALID (ID: %s)" % p_content_state_res.get_instance_id())

	print("SyntreePanel (setup): Checking injected ViewStateResource...")
	if not is_instance_valid(p_view_state_res):
		push_warning("SyntreePanel (setup): Injected ViewStateResource is NOT valid!")
	else:
		print("  - Injected ViewStateResource is VALID (ID: %s)" % p_view_state_res.get_instance_id())

	panel._plugin_manager = plugin_manager
	panel._content_state_resource = p_content_state_res
	panel._view_state_resource = p_view_state_res

	panel._wire_content_state_signals()

	print("SyntreePanel (setup): Checking stored _content_state_resource...")
	if not is_instance_valid(panel._content_state_resource):
		push_error("SyntreePanel (setup): Stored _content_state_resource is NOT valid after assignment!")
	else:
		print("  - Stored _content_state_resource is VALID (ID: %s)" % panel._content_state_resource.get_instance_id())

	print("SyntreePanel: Stored references to ContentState and ViewState resources.")

	if not initialize_notification_manager(panel):
		return {"success": false, "error": "Failed to initialize notification manager"}

	panel._ai_model_manager = panel._plugin_manager.get_ai_model_manager()
	panel._conversation_manager = panel._plugin_manager.get_conversation_manager()

	print("SyntreePanel: Preparing to set AI Model Manager on Conversation Manager...")
	print("  - _ai_model_manager Instance ID: %s" % str(panel._ai_model_manager.get_instance_id() if panel._ai_model_manager else "null"))
	print("  - _conversation_manager Instance ID: %s" % str(panel._conversation_manager.get_instance_id() if panel._conversation_manager else "null"))

	if is_instance_valid(panel._conversation_manager) and is_instance_valid(panel._ai_model_manager):
		if panel._conversation_manager.has_method("set_ai_model_manager"):
			panel._conversation_manager.set_ai_model_manager(panel._ai_model_manager)
			print("SyntreePanel: Explicitly set AI Model Manager on Conversation Manager.")
		else:
			push_error("SyntreePanel: ConversationManager is missing set_ai_model_manager method!")
	else:
		push_error("SyntreePanel: Could not set AI Model Manager on Conversation Manager - one or both managers are invalid.")

	print("SyntreePanel (setup): Preparing to call setup_content_source_manager...")
	panel.setup_content_source_manager()
	print("SyntreePanel (setup): Returned from setup_content_source_manager.")

	# Message container is an instance-only UI object; don't double-spawn it if setup() is called twice.
	if not is_instance_valid(panel._message_container):
		panel._message_container = panel.MessageContainerScene.instantiate()
		panel.chat_history_container.add_child(panel._message_container)

	panel._connect_manager_signals()
	panel._setup_initial_ui_state()

	panel._setup_chat_panel_controller()
	if is_instance_valid(panel._chat_panel_controller):
		panel._chat_panel_controller.update_thread_options()
	var tid: String = str(panel._get_current_thread_id_safe())
	if is_instance_valid(panel._chat_panel_controller):
		panel._chat_panel_controller.load_thread(tid)

	setup_panels(panel)

	# Re-run controller setup now that runtime dependencies have been injected.
	# In exported builds these controllers may have been instantiated earlier from
	# _ready() with null managers/resources, so they must be refreshed here.
	panel._setup_content_sources_panel_controller()
	panel._setup_publish_context_graph_controller()
	panel._setup_status_hub_controller()
	if is_instance_valid(panel._status_hub_controller):
		panel._status_hub_controller.start()

	panel._setup_model_settings_controller()
	if is_instance_valid(panel._model_settings_controller):
		panel._model_settings_controller.populate_provider_selector()
		panel._model_settings_controller.populate_model_selector()

	return {"success": true}


