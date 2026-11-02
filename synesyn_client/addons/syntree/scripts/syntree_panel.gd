## Purpose: Main container and coordination
"""
COMPONENT: SyntreePanel
RESPONSIBILITY: Main container and coordination
PUBLIC API:
  - _ready(): Initialize panel
  - _setup_content_view_manager(): Setup view manager with references
  - get_content_list_view(): Get reference to content list
  - get_content_model(): Get reference to content model
DEPENDENCIES:
  - ContentBus: For signals
  - ContentModel: For data management
  - ContentViewManager: For view management
"""
@tool
extends Control

signal operation_failed(operation: String, error: String, details: String)
signal detach_plugin_window_toggled(detached: bool)
signal show_error_requested(title: String, message: String, details: String)

# Scene References
const ContentGraphNodeScene = preload("res://addons/syntree/scenes/content_source_graph_node.tscn")
const MessageContainerScene = preload("res://addons/syntree/scenes/message_container.tscn")
const ContentSourceItemScene = preload("res://addons/syntree/scenes/content_source_item.tscn")
const ContentViewManagerScene = preload("res://addons/syntree/scenes/content_view_manager.tscn")

# Script References
const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")
const ContentGraphScript = preload("res://addons/syntree/scripts/ui/content_graph/content_graph.gd")
const ContentSourceEditor = preload("res://addons/syntree/scripts/ui/content_source_editor/content_source_editor.gd")
const MessageContainerScript = preload("res://addons/syntree/scripts/ui/chat/message_container.gd")
const ResizeHandle = preload("res://addons/syntree/scripts/utils/ui/resize_handle.gd")
const NotificationManager = preload("res://addons/syntree/scripts/utils/notification_manager.gd")
const ContentSourceDialog = preload("res://addons/syntree/scripts/ui/dialogs/content_source_dialog.gd")
const ContentHierarchyViewScript = preload("res://addons/syntree/scripts/ui/content_source_list/content_hierarchy_view.gd")
const ConversationManager = preload("res://addons/syntree/scripts/services/chat/conversation_manager.gd")
const ContentSourceItem = preload("res://addons/syntree/scripts/ui/content_source_list/content_source_item.gd")
const ContentViewManagerScript = preload("res://addons/syntree/scripts/ui/content_view_manager.gd")
const ToolbarControls = preload("res://addons/syntree/scripts/utils/ui/toolbar_controls.gd") # UPDATED Path
const UnifiedDiffApplier = preload("res://addons/syntree/scripts/utils/unified_diff_applier.gd")
const DevAgentOrchestratorScript = preload("res://addons/syntree/scripts/dev_agent/dev_agent_orchestrator.gd")
const ContentSourcesPanelControllerScript = preload("res://addons/syntree/scripts/ui/panel/content_sources_panel_controller.gd")
const ModelSettingsControllerScript = preload("res://addons/syntree/scripts/ui/panel/model_settings_controller.gd")
const ChatPanelControllerScript = preload("res://addons/syntree/scripts/ui/panel/chat_panel_controller.gd")
const StatusHubControllerScript = preload("res://addons/syntree/scripts/ui/panel/status_hub_controller.gd")
const PublishContextGraphControllerScript = preload("res://addons/syntree/scripts/ui/panel/publish_context_graph_controller.gd")
const SyntreePanelDevAgentUtilsScript = preload("res://addons/syntree/scripts/ui/panel/internal/syntree_panel_dev_agent_utils.gd")
const SyntreePanelStoreActionsScript = preload("res://addons/syntree/scripts/ui/panel/internal/syntree_panel_store_actions.gd")
const HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
const SynesynAutoloadAccessScript = preload("res://addons/synesyn_core/scripts/synesyn_autoload_access.gd")
const EnsemblesPopupScene: PackedScene = preload("res://addons/syntree/scenes/ensembles_popup.tscn")

# Services
var _plugin_manager = null
var _ai_model_manager = null
var _content_graph = null
var _message_container = null
var _conversation_manager = null
var _notification_manager = null
var _is_setup_complete = false
var _content_source_dialog = null
var _content_sources_panel_controller: ContentSourcesPanelController = null
var _model_settings_controller: ModelSettingsController = null
var _chat_panel_controller: ChatPanelController = null
var _status_hub_controller: StatusHubController = null
var _publish_context_graph_controller: PublishContextGraphController = null
var _ensembles_popup: PopupPanel = null
var _runtime_model_services_retry_count: int = 0
var _runtime_model_services_retry_scheduled: bool = false
var _is_store_repair_running: bool = false

# Internal helpers:
# Implemented as `class_name` + `static func` helpers (avoid `.new()` instantiation).

# --- Latent Reality / Hub integration (v0) ---
const MENU_ID_PUBLISH_CONTEXT_GRAPH := 100
const _MAX_RUNTIME_MODEL_SERVICE_RETRIES := 40

## (Publish state moved into PublishContextGraphController)

# State tracking
var _ui_state = {
	# Remove current_thread (handled by ViewStateResource)
	# "current_thread": "", 
	"is_processing": false,
	# Remove current_source (handled by ViewStateResource)
	# "current_source": "" 
}

# Constants
const DEFAULT_CONTENT_SOURCES_DIR = "res://addons/syntree/content_source_lists/"
const SUPPORTED_CONTENT_EXTENSIONS = [
	# Documentation formats
	"txt", "md", "rst", "adoc",
	# Code files
	"gd", "gdscript", "cs", "cpp", "c", "h", "hpp", "py", "js", "ts", "html", "css", "sh",
	# Config files
	"json", "cfg", "ini", "toml", "yaml", "yml",
	# Project files
	"xml", "csv", "env"
]

# UI Elements
@onready var content_hierarchy: Control = %ContentHierarchy
@onready var graph_view: GraphEdit = %ContentGraph
@onready var detach_panel_button: CheckButton = %DetachPanelButton
@onready var scroll_top_button: Button = %ScrollTopButton
@onready var scroll_bottom_button: Button = %ScrollBottomButton
@onready var chat_history_container: Control = %OutputContainer
@onready var message_input: TextEdit = %MessageInput
@onready var send_button: Button = %SendButton
@onready var stop_request_button: Button = %StopRequestButton
@onready var thread_dropdown: OptionButton = %ThreadDropdown
@onready var new_thread_button: Button = %NewThreadButton
@onready var new_thread_name_input: LineEdit = %NewThreadNameInput
@onready var thread_hub_versions_button: Button = get_node_or_null("%ThreadHubVersionsButton")
@onready var open_threads_folder_button: Button = get_node_or_null("%OpenThreadsFolderButton")
@onready var open_store_trace_button: Button = get_node_or_null("%OpenStoreTraceButton")
@onready var view_store_trace_button: Button = get_node_or_null("%ViewStoreTraceButton")
@onready var open_store_chunk_button: Button = get_node_or_null("%OpenStoreChunkButton")
@onready var repair_store_symbolic_button: Button = get_node_or_null("%RepairStoreSymbolicButton")
@onready var store_repair_button: Button = get_node_or_null("%StoreRepairButton")
@onready var thread_hub_versions_popup: PopupPanel = get_node_or_null("%ThreadHubVersionsPopup")
@onready var thread_hub_versions_list: ItemList = get_node_or_null("%ThreadHubVersionsList")
@onready var ai_model_selector: OptionButton = %AIModelSelector
@onready var ollama_status_label: Label = %OllamaStatusLabel
@onready var ollama_endpoint_input: LineEdit = %OllamaEndpointInput
@onready var apply_ollama_endpoint_button: Button = %ApplyOllamaEndpointButton
@onready var refresh_ollama_models_button: Button = %RefreshOllamaModelsButton
@onready var api_key_input: LineEdit = %APIKeyInput
@onready var save_api_key_button: Button = get_node_or_null("%SaveApiKeyButton")
#@onready var chat_menu_toggle: CheckButton = %ToggleChatMenu
#@onready var main_menu_toggle: CheckButton = %ToggleMainMenu
@onready var chat_menu_container: Control = %Chat_Menu_Container
@onready var main_menu_container: Control = %Main_Menu_Container
@onready var content_sources_container: VBoxContainer = %ContentSourcesContainer
@onready var create_source_menu_button: MenuButton = %CreateSourcesMenu
@onready var manage_sources_menu_button: MenuButton = %ManageSourcesMenu
@onready var content_source_list_options: OptionButton = %ContentSourceListOptions
@onready var content_source_menu_button: Button = %ContentSourceMenuButton
@onready var save_content_sources_button: Button = %SaveContentSourcesList
@onready var edit_history_button: Button = %EditHistoryButton
@onready var edit_history_popup: PopupPanel = %EditHistoryPopup
@onready var history_text_edit: TextEdit = %HistoryTextEdit
@onready var save_history_button: Button = %SaveHistoryButton
@onready var cancel_edit_button: Button = %CancelEditButton
@onready var change_content_dir_button: Button = %ChangeContentDirButton
@onready var content_dir_path_label: Label = %ContentDirPathLabel
@onready var save_custom_sources_popup = %SaveCustomSourcesPopUp
@onready var content_list_view: VBoxContainer = %ContentList
@onready var view_manager_placeholder: Control = %ContentViewManager
@onready var debug_data_button: Button = %DebugDataButton
@onready var sources_tab_container: TabContainer = %SourcesTabContainer
@onready var conversation_tabs: TabContainer = %ConversationTabs
@onready var add_source_button: Button = %AddSourceBtn
@onready var delete_source_button: Button = get_node_or_null("%DeleteSourceBtn")
@onready var filter_button: Button = get_node_or_null("%FilterButton")
@onready var stats_button: Button = get_node_or_null("%StatsButton")
@onready var search_box: LineEdit = get_node_or_null("%SearchBox")
@onready var voice_popup: PopupPanel = get_node_or_null("%VoicePopup")
@onready var dev_agent_popup: PopupPanel = get_node_or_null("%DevAgentPopup")
@onready var dev_agent_patch_input: TextEdit = get_node_or_null("%PatchInput")
@onready var dev_agent_patch_result: TextEdit = get_node_or_null("%PatchResult")
@onready var dev_agent_patch_dry_run_button: Button = get_node_or_null("%PatchDryRunButton")
@onready var dev_agent_patch_apply_button: Button = get_node_or_null("%PatchApplyButton")
@onready var dev_agent_patch_revert_button: Button = get_node_or_null("%PatchRevertButton")
@onready var dev_agent_patch_close_button: Button = get_node_or_null("%PatchCloseButton")
@onready var dev_agent_open_backups_folder_button: Button = get_node_or_null("%OpenBackupsFolderButton")
@onready var dev_agent_open_artifacts_folder_button: Button = get_node_or_null("%OpenArtifactsFolderButton")
@onready var dev_agent_run_spec_input: TextEdit = get_node_or_null("%RunSpecInput")
@onready var dev_agent_run_spec_result: TextEdit = get_node_or_null("%RunSpecResult")
@onready var dev_agent_run_spec_load_button: Button = get_node_or_null("%RunSpecLoadButton")
@onready var dev_agent_run_spec_save_button: Button = get_node_or_null("%RunSpecSaveButton")
@onready var dev_agent_run_spec_run_button: Button = get_node_or_null("%RunSpecRunButton")
@onready var dev_agent_run_spec_scene_path: LineEdit = get_node_or_null("%RunSpecScenePath")
@onready var dev_agent_run_spec_browse_scene_button: Button = get_node_or_null("%RunSpecBrowseSceneButton")
@onready var dev_agent_run_spec_schema_status_label: Label = get_node_or_null("%RunSpecSchemaStatusLabel")
@onready var dev_agent_run_spec_schema_fields_container: VBoxContainer = get_node_or_null("%RunSpecSchemaFields")
@onready var dev_agent_run_spec_sync_to_json_button: Button = get_node_or_null("%RunSpecSyncToJsonButton")
@onready var dev_agent_run_spec_fill_from_json_button: Button = get_node_or_null("%RunSpecFillFromJsonButton")
@onready var dev_agent_run_spec_last_run_text: TextEdit = get_node_or_null("%RunSpecLastRunText")
@onready var dev_agent_run_spec_refresh_last_run_button: Button = get_node_or_null("%RunSpecRefreshLastRunButton")
@onready var dev_agent_run_spec_open_last_run_dir_button: Button = get_node_or_null("%RunSpecOpenLastRunDirButton")
@onready var dev_agent_run_spec_open_last_run_manifest_button: Button = get_node_or_null("%RunSpecOpenLastRunManifestButton")
@onready var dev_agent_run_spec_scene_picker_dialog: FileDialog = get_node_or_null("%RunSpecScenePickerDialog")

# Dev Agent Loop tab
@onready var dev_agent_loop_goal_input: TextEdit = get_node_or_null("%LoopGoalInput")
@onready var dev_agent_loop_where_input: LineEdit = get_node_or_null("%LoopWhereInput")
@onready var dev_agent_loop_verify_input: TextEdit = get_node_or_null("%LoopVerifyInput")
@onready var dev_agent_loop_constraints_input: TextEdit = get_node_or_null("%LoopConstraintsInput")
@onready var dev_agent_loop_max_iters: SpinBox = get_node_or_null("%LoopMaxIters")
@onready var dev_agent_loop_start_button: Button = get_node_or_null("%LoopStartButton")
@onready var dev_agent_loop_stop_button: Button = get_node_or_null("%LoopStopButton")
@onready var dev_agent_loop_log: TextEdit = get_node_or_null("%LoopLog")
@onready var refresh_menu_button: MenuButton = get_node_or_null("%RefreshButton")
@onready var active_filters_label: Label = %ActiveFiltersLabel_2 # Corrected unique name
@onready var api_provider_selector: OptionButton = %APIProviderSelector # ADDED
@onready var system_info_label: Label = %SystemInfoLabel_2
@onready var top_toolbar_controls: ToolbarControls = %TopToolbarControls
@onready var bottom_toolbar_controls: ToolbarControls = %BottomToolbarControls
@onready var status_strip_label: Label = get_node_or_null("%StatusStripLabel")

# Add current_source_id tracking
var current_source_id: String = ""

# Add near the top after extends
var _debug_name = "SyntreePanel"

# Harness / Run Spec UI state
var _dev_agent_last_run_pointer: Dictionary = {}
var _run_spec_ui_schema: Dictionary = {}
var _run_spec_ui_schema_fields: Array[Dictionary] = [] # each: {id, json_path, type, control, clear_on_empty, default}

# Dev Agent Orchestrator
var _dev_agent_orchestrator: DevAgentOrchestrator = null

# Add a variable to hold the actual ContentViewManager INSTANCE
var content_view_manager_instance: Node = null 

# Add vars to hold resource references
var _content_state_resource: ContentStateResource = null
var _view_state_resource: ViewStateResource = null

# Resource bootstrap guards (when panel is instanced without calling setup())
var _resource_bootstrap_inflight: bool = false
var _resource_bootstrap_retry_count: int = 0

# Add var for plugin reference
var _plugin_ref = null

# ... Other consts ...

const _SYNTREE_LOGO_DARK := preload("res://addons/syntree/syntree_icons/SynTree_logo_mini_04-2025.png")
const _SYNTREE_LOGO_WHITE := preload("res://addons/syntree/syntree_icons/SynTree_logo_mini_white.png")
const _SYNTREE_GLYPH_DARK := preload("res://addons/syntree/syntree_icons/SynTree-glyph_.png")
const _SYNTREE_GLYPH_WHITE := preload("res://addons/syntree/syntree_icons/SynTree-glyph_white.png")

func _update_syntree_logos(_mode: String = "") -> void:
	var is_dark_mode := true
	var theme_mgr: Node = SynesynAutoloadAccessScript.theme_manager()
	if theme_mgr != null and theme_mgr.has_method("is_dark"):
		is_dark_mode = bool(theme_mgr.call("is_dark"))
	var logo_tex: Texture2D = _SYNTREE_LOGO_WHITE if is_dark_mode else _SYNTREE_LOGO_DARK
	var glyph_tex: Texture2D = _SYNTREE_GLYPH_WHITE if is_dark_mode else _SYNTREE_GLYPH_DARK
	var logo_node: TextureRect = get_node_or_null("%SyntreeLogo") as TextureRect
	if logo_node:
		logo_node.texture = logo_tex
	for g_name in ["%SyntreeGlyph", "%SyntreeGlyph2"]:
		var glyph_node: TextureRect = get_node_or_null(g_name) as TextureRect
		if glyph_node:
			glyph_node.texture = glyph_tex

func _ready() -> void:
	# Add to syntree_panel group for easy access
	add_to_group("syntree_panel")
	_update_syntree_logos()
	var theme_mgr: Node = SynesynAutoloadAccessScript.theme_manager()
	if theme_mgr != null and theme_mgr.has_signal("mode_changed"):
		if not theme_mgr.is_connected("mode_changed", Callable(self, "_update_syntree_logos")):
			theme_mgr.connect("mode_changed", Callable(self, "_update_syntree_logos"))
	
	# Initialize notification manager FIRST before any other operations
	if not _initialize_notification_manager():
		push_error("SyntreePanel: Failed to initialize notification manager!")
		return

	var ready_bus := SynTreeAutoloads.content_bus()
	if is_instance_valid(ready_bus):
		ready_bus.panel_ready.emit(self)
	else:
		push_warning("SyntreePanel: ContentBus autoload unavailable; skipping panel_ready.")

	# IMPORTANT: In the editor dock flow, `setup(...)` is not always called.
	# Bootstrap resources from ContentBus so downstream systems can initialize.
	_ensure_resources_from_content_bus()
	# Runtime (play mode) needs an explicit bootstrap: the EditorPlugin does this in-editor,
	# but in play mode the EditorPlugin never runs. Without this, the panel can appear
	# but remain empty (no spawned content source items, graph nodes, or message container).
	call_deferred("_runtime_bootstrap_if_needed")

	# Initialize core components
	_setup_conversation_manager()
	
	# Initialize UI components
	_setup_content_view_manager()
	_setup_content_sources_panel_controller()
	_setup_model_settings_controller()
	_setup_publish_context_graph_controller()
	
	# Connect signals after everything is initialized
	_connect_manager_signals()
	_connect_ui_signals()
	var bootstrapper := SynesynAutoloadAccessScript.workspace_bootstrapper()
	if is_instance_valid(bootstrapper) and bootstrapper.has_signal("hub_connection_changed"):
		var hub_changed_cb := Callable(self, "_on_hub_connection_changed")
		if not bootstrapper.is_connected("hub_connection_changed", hub_changed_cb):
			bootstrapper.connect("hub_connection_changed", hub_changed_cb)
	_sync_dev_agent_toggle_from_bus()
	_wire_dev_agent_bus_signal()
	_wire_dev_agent_patch_ui()
	_wire_dev_agent_run_spec_ui()
	_wire_dev_agent_artifacts_ui()
	_wire_dev_agent_loop_ui()

	# Belt-and-suspenders: ensure the threads folder button is always wired.
	if is_instance_valid(open_threads_folder_button) and not open_threads_folder_button.pressed.is_connected(_on_open_threads_folder_pressed):
		open_threads_folder_button.pressed.connect(_on_open_threads_folder_pressed)
	if is_instance_valid(open_store_trace_button) and not open_store_trace_button.pressed.is_connected(_on_open_store_trace_button_pressed):
		open_store_trace_button.pressed.connect(_on_open_store_trace_button_pressed)
	if is_instance_valid(view_store_trace_button) and not view_store_trace_button.pressed.is_connected(_on_view_store_trace_button_pressed):
		view_store_trace_button.pressed.connect(_on_view_store_trace_button_pressed)
	if is_instance_valid(open_store_chunk_button) and not open_store_chunk_button.pressed.is_connected(_on_open_store_chunk_button_pressed):
		open_store_chunk_button.pressed.connect(_on_open_store_chunk_button_pressed)
	if is_instance_valid(repair_store_symbolic_button) and not repair_store_symbolic_button.pressed.is_connected(_on_repair_store_symbolic_button_pressed):
		repair_store_symbolic_button.pressed.connect(_on_repair_store_symbolic_button_pressed)
	if is_instance_valid(store_repair_button) and not store_repair_button.pressed.is_connected(_on_store_repair_button_pressed):
		store_repair_button.pressed.connect(_on_store_repair_button_pressed)
	
	# Set initial view state
	var view_bus := SynTreeAutoloads.content_bus()
	if is_instance_valid(view_bus):
		# Using call_deferred for initial state to avoid await in _ready
		# This ensures the panel completes initialization before view change
		view_bus.call_deferred("request_view_change", SynTreeAutoloads.ContentBusScript.ViewMode.LIST)

	# Add error handling for content source items
	for item in content_list_view.get_children():
		if item is ContentSourceItem and not item.show_error_requested.is_connected(_on_show_error_requested):
			item.show_error_requested.connect(_on_show_error_requested)

	# Setup content sources menu
	#var content_sources_menu = get_node_or_null("%ContentSourcesMenu")
	#if content_sources_menu:
		#content_sources_menu.clear()
		#content_sources_menu.add_item("Save Custom Sources...", 0)
		#content_sources_menu.add_item("Create Source Stack from Active", 1)
		#content_sources_menu.id_pressed.connect(_on_create_sources_menu_pressed)

	# Model/provider UI is owned by ModelSettingsController; keep panel as composition root.
	_setup_model_settings_controller()
	if is_instance_valid(_model_settings_controller):
		_model_settings_controller.populate_provider_selector()
	_install_latent_reality_menu_items()
	# Ensure Manage Sources menu labels/tooltips are sane even if authored in .tscn.
	_normalize_manage_sources_menu_popup()
	_setup_status_hub_controller()
	if is_instance_valid(_status_hub_controller):
		_status_hub_controller.start()

func _runtime_bootstrap_if_needed() -> void:
	# Only relevant in play mode (runtime).
	if Engine.is_editor_hint():
		return
	# Model/provider controls are used in the embedded runtime panel even when the
	# rest of the panel has already bootstrapped, so refresh them before any early
	# return below.
	_ensure_runtime_model_services()
	# If already fully configured, do nothing.
	if is_instance_valid(_plugin_manager) and is_instance_valid(_ai_model_manager) and is_instance_valid(_content_state_resource) and is_instance_valid(_view_state_resource) and is_instance_valid(_message_container):
		return

	# Prefer the project's autoload if present.
	if not is_instance_valid(_plugin_manager):
		var pm_autoload := SynTreeAutoloads.plugin_manager()
		if is_instance_valid(pm_autoload):
			_plugin_manager = pm_autoload

	# If PluginManager isn't ready yet, wait briefly for its init.
	if is_instance_valid(_plugin_manager) and _plugin_manager.has_method("is_ready") and not bool(_plugin_manager.is_ready()):
		if _plugin_manager.has_signal("initialization_completed"):
			await _plugin_manager.initialization_completed
		else:
			# Fallback: give it a moment.
			await get_tree().create_timer(0.25).timeout

	# Ensure we have resources from ContentBus.
	_ensure_resources_from_content_bus()
	if not (is_instance_valid(_content_state_resource) and is_instance_valid(_view_state_resource)):
		return

	# Ensure content sources are initialized (EditorPlugin does this step in-editor).
	if _content_state_resource.has_method("get_source_ids") and (_content_state_resource.get_source_ids() as Array).is_empty():
		if _content_state_resource.has_method("initialize_content_sources"):
			var init_res: Dictionary = _content_state_resource.initialize_content_sources(DEFAULT_CONTENT_SOURCES_DIR)
			if not bool(init_res.get("success", false)):
				push_warning("SyntreePanel: initialize_content_sources failed in runtime: %s" % str(init_res.get("error", "unknown error")))

	# Sync view selections against available ids.
	if _view_state_resource and _view_state_resource.has_method("sync_selections_with_available") and _content_state_resource.has_method("get_source_ids"):
		_view_state_resource.sync_selections_with_available(_content_state_resource.get_source_ids())

	# Finally, run the full setup path (spawns MessageContainer, wires services, etc).
	if is_instance_valid(_plugin_manager):
		var res: Dictionary = setup(null, _plugin_manager, _content_state_resource, _view_state_resource)
		if not bool(res.get("success", false)):
			push_warning("SyntreePanel: runtime setup() failed: %s" % str(res.get("error", "unknown error")))
		_ensure_runtime_model_services()

func _ensure_runtime_model_services() -> void:
	if Engine.is_editor_hint():
		return
	if not is_instance_valid(_plugin_manager):
		var pm_autoload := SynTreeAutoloads.plugin_manager()
		if is_instance_valid(pm_autoload):
			_plugin_manager = pm_autoload
	if not is_instance_valid(_plugin_manager):
		_schedule_runtime_model_services_retry()
		return
	if _plugin_manager.has_method("is_ready") and not bool(_plugin_manager.is_ready()):
		_schedule_runtime_model_services_retry()
		return
	if not is_instance_valid(_ai_model_manager) and _plugin_manager.has_method("get_ai_model_manager"):
		_ai_model_manager = _plugin_manager.get_ai_model_manager()
	if not is_instance_valid(_conversation_manager) and _plugin_manager.has_method("get_conversation_manager"):
		_conversation_manager = _plugin_manager.get_conversation_manager()
	if is_instance_valid(_conversation_manager) and is_instance_valid(_ai_model_manager) and _conversation_manager.has_method("set_ai_model_manager"):
		_conversation_manager.set_ai_model_manager(_ai_model_manager)
	_setup_model_settings_controller()
	if is_instance_valid(_model_settings_controller):
		_model_settings_controller.populate_provider_selector()
		_model_settings_controller.populate_model_selector()
	var needs_model_retry: bool = not is_instance_valid(_ai_model_manager)
	if not needs_model_retry:
		if not is_instance_valid(ai_model_selector):
			needs_model_retry = true
		elif ai_model_selector.item_count == 0:
			needs_model_retry = true
		elif ai_model_selector.item_count == 1 and ai_model_selector.get_item_text(0).begins_with("No Models"):
			needs_model_retry = true
	if needs_model_retry:
		_schedule_runtime_model_services_retry()
	else:
		_runtime_model_services_retry_count = 0
		_runtime_model_services_retry_scheduled = false

func _schedule_runtime_model_services_retry() -> void:
	if Engine.is_editor_hint():
		return
	if _runtime_model_services_retry_scheduled:
		return
	if _runtime_model_services_retry_count >= _MAX_RUNTIME_MODEL_SERVICE_RETRIES:
		push_warning("SyntreePanel: Model selector bootstrap retries exhausted; AIModelManager or model list was not available.")
		return
	_runtime_model_services_retry_scheduled = true
	_runtime_model_services_retry_count += 1
	var retry_timer: SceneTreeTimer = get_tree().create_timer(0.25)
	retry_timer.timeout.connect(func() -> void:
		_runtime_model_services_retry_scheduled = false
		_ensure_runtime_model_services()
	)

# Thread/store actions
func _on_open_threads_folder_pressed() -> void:
	SyntreePanelStoreActionsScript._on_open_threads_folder_pressed(self)
func _on_open_store_trace_button_pressed() -> void:
	await SyntreePanelStoreActionsScript._on_open_store_trace_button_pressed(self)
func _latest_store_context_paths_or_warn(action_title: String) -> Dictionary:
	return await SyntreePanelStoreActionsScript._latest_store_context_paths_or_warn(self, action_title)
func _on_view_store_trace_button_pressed() -> void:
	await SyntreePanelStoreActionsScript._on_view_store_trace_button_pressed(self)
func _on_open_store_chunk_button_pressed() -> void:
	await SyntreePanelStoreActionsScript._on_open_store_chunk_button_pressed(self)
func _on_repair_store_symbolic_button_pressed() -> void:
	await SyntreePanelStoreActionsScript._on_repair_store_symbolic_button_pressed(self)
func _latest_store_chunk_or_warn(action_title: String) -> Dictionary:
	return await SyntreePanelStoreActionsScript._latest_store_chunk_or_warn(self, action_title)
func _on_store_repair_button_pressed() -> void:
	await SyntreePanelStoreActionsScript._on_store_repair_button_pressed(self)
func _finish_store_repair_action(client: Node, is_success: bool, message: String) -> void:
	SyntreePanelStoreActionsScript._finish_store_repair_action(self, client, is_success, message)
func _format_store_repair_summary(validate_res: Dictionary, repair_res: Dictionary, rebuild_res: Dictionary) -> String:
	return SyntreePanelStoreActionsScript._format_store_repair_summary(self, validate_res, repair_res, rebuild_res)
func _store_result_error(result: Dictionary) -> String:
	return SyntreePanelStoreActionsScript._store_result_error(self, result)
func _normalize_manage_sources_menu_popup() -> void:
	SyntreePanelWiring.normalize_manage_sources_menu_popup(self)

## (Removed manage-menu popup clamping; it was changing behavior that previously worked.)

func _connect_ui_signals() -> void:
	SyntreePanelWiring.connect_ui_signals(self)
	if is_instance_valid(save_api_key_button) and not save_api_key_button.pressed.is_connected(_on_save_api_key_pressed):
		save_api_key_button.pressed.connect(_on_save_api_key_pressed)

func _on_save_api_key_pressed() -> void:
	if not is_instance_valid(_model_settings_controller):
		return
	var key_text: String = api_key_input.text if is_instance_valid(api_key_input) else ""
	_model_settings_controller.on_api_key_changed(key_text)

func _on_manage_sources_about_to_popup() -> void:
	# PopupMenu computes its size right before showing; clamp after that computation.
	call_deferred("_clamp_manage_sources_popup_width_only")

func _clamp_manage_sources_popup_width_only() -> void:
	SyntreePanelWiring.clamp_manage_sources_popup_width_only(self)

func _on_conversation_tab_selected(tab_idx: int) -> void:
	# Prefer title-based detection so future TabContainer reorders don't break behavior.
	var title := ""
	if is_instance_valid(conversation_tabs) and conversation_tabs.has_method("get_tab_title"):
		title = str(conversation_tabs.get_tab_title(tab_idx))
	var title_lc := title.to_lower()
	# Back-compat: fall back to index 0 if titles are unavailable / renamed.
	var is_chat := (title_lc == "chat") or (title_lc.find("chat") != -1) or (tab_idx == 0 and title_lc == "")
	if is_instance_valid(send_button):
		send_button.disabled = not is_chat
		send_button.tooltip_text = "" if is_chat else "Switch to the Chat tab to send a message."
	if is_instance_valid(edit_history_button):
		# Conservative: disable outside chat to avoid accidental edits while working on prompt chains.
		edit_history_button.disabled = not is_chat
		edit_history_button.tooltip_text = "" if is_chat else "Switch to the Chat tab to edit conversation history."

func _get_current_thread_id_safe() -> String:
	var tid := "default"
	if is_instance_valid(_view_state_resource) and _view_state_resource.has_method("get_current_thread_id"):
		tid = str(_view_state_resource.get_current_thread_id()).strip_edges()
	if tid.is_empty():
		tid = "default"
	return tid

func _refresh_thread_view_after_hub_load(thread_id: String) -> void:
	_setup_chat_panel_controller()
	if is_instance_valid(_chat_panel_controller):
		_chat_panel_controller.load_thread(String(thread_id).strip_edges())

func _install_latent_reality_menu_items() -> void:
	SyntreePanelWiring.install_latent_reality_menu_items(self)

func _connect_manager_signals() -> void:
	SyntreePanelWiring.connect_manager_signals(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Clean up notification manager
		if _notification_manager:
			if _notification_manager.is_inside_tree():
				remove_child(_notification_manager)
			_notification_manager.queue_free()
			_notification_manager = null

func _initialize_notification_manager() -> bool:
	return bool(SyntreePanelBootstrap.initialize_notification_manager(self))

func setup(plugin_ref, plugin_manager, p_content_state_res: ContentStateResource, p_view_state_res: ViewStateResource) -> Dictionary:
	return SyntreePanelBootstrap.setup(self, plugin_ref, plugin_manager, p_content_state_res, p_view_state_res)

func _setup_initial_ui_state() -> void:
	SyntreePanelWiring.setup_initial_ui_state(self)

func _on_scroll_top_pressed() -> void:
	if _message_container and is_instance_valid(_message_container):
		# Defer to ensure the scroll bar values are valid after layout changes.
		_message_container.call_deferred("scroll_to_top")

func _on_scroll_bottom_pressed() -> void:
	if _message_container and is_instance_valid(_message_container):
		_message_container.call_deferred("scroll_to_bottom")

func _on_toggle_output_container(button_pressed: bool) -> void:
	chat_history_container.visible = button_pressed
	# Sync both toolbars
	if is_instance_valid(top_toolbar_controls):
		top_toolbar_controls.set_output_container_state(button_pressed)
	if is_instance_valid(bottom_toolbar_controls):
		bottom_toolbar_controls.set_output_container_state(button_pressed)

func _on_toggle_user_input(button_pressed: bool) -> void:
	message_input.visible = button_pressed
	send_button.visible = button_pressed
	# Sync both toolbars
	if is_instance_valid(top_toolbar_controls):
		top_toolbar_controls.set_user_input_state(button_pressed)
	if is_instance_valid(bottom_toolbar_controls):
		bottom_toolbar_controls.set_user_input_state(button_pressed)

func _on_toggle_content_sources(button_pressed: bool) -> void:
	content_sources_container.visible = button_pressed
	# Sync both toolbars
	if is_instance_valid(top_toolbar_controls):
		top_toolbar_controls.set_content_sources_state(button_pressed)
	if is_instance_valid(bottom_toolbar_controls):
		bottom_toolbar_controls.set_content_sources_state(button_pressed)

func _on_save_content_sources() -> void:
	var save_bus := SynTreeAutoloads.content_bus()
	var content_state = save_bus.get_content_state_resource() if is_instance_valid(save_bus) else null
	if is_instance_valid(content_state) and content_state.has_method("save_all_sources"):
		content_state.save_all_sources()
	else:
		push_warning("SyntreePanel: ContentStateResource missing save_all_sources method.")

func _on_detach_panel_toggled(button_pressed: bool) -> void:
	detach_plugin_window_toggled.emit(button_pressed)

func _on_operation_failed(operation: String, error: String, details: String = "") -> void:
	print("Operation failed - %s: %s" % [operation, error])
	var title = "Operation Failed: " + operation.capitalize()
	_notification_manager.error(error, title, details)
	# Re-emit for any other listeners
	operation_failed.emit(operation, error, details)

# --- Scene-wired critical UI hooks (policy: prefer .tscn connections for editor reliability) ---
func _on_send_button_pressed() -> void:
	if is_instance_valid(_chat_panel_controller):
		_chat_panel_controller.on_send_message()

func _on_stop_request_button_pressed() -> void:
	if is_instance_valid(_chat_panel_controller):
		_chat_panel_controller.on_stop_request()

func _on_voice_button_pressed() -> void:
	# Scene-wired wrapper (same policy/pattern as SendButton).
	if not is_instance_valid(voice_popup):
		push_warning("SyntreePanel: VoicePopup not found.")
		return
	# Provide explicit references so the popup never has to "find the panel".
	var mi: TextEdit = get_node_or_null("%MessageInput") as TextEdit
	var sb: Button = get_node_or_null("%SendButton") as Button
	if voice_popup.has_method("setup"):
		voice_popup.setup(mi, sb, _message_container)
	if voice_popup.has_method("on_voice_button_pressed"):
		voice_popup.on_voice_button_pressed()
	else:
		voice_popup.popup_centered()

func _on_ensembles_button_pressed() -> void:
	_ensure_ensembles_popup()
	if not is_instance_valid(_ensembles_popup):
		push_warning("SyntreePanel: EnsemblesPopup unavailable.")
		return
	# Provide explicit references so the popup never has to "find the panel".
	var mi: TextEdit = get_node_or_null("%MessageInput") as TextEdit
	var reload_cb := Callable(self, "_reload_current_thread")
	if _ensembles_popup.has_method("setup"):
		_ensembles_popup.setup(_view_state_resource, mi, reload_cb)
	if _ensembles_popup.has_method("open"):
		_ensembles_popup.open()
	else:
		_ensembles_popup.popup_centered()

# Dev Agent helpers
func _on_dev_agent_button_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_dev_agent_button_pressed(self)
func open_dev_agent_popup() -> void:
	SyntreePanelDevAgentUtilsScript.open_dev_agent_popup(self)
func open_dev_agent_artifacts_folder() -> void:
	SyntreePanelDevAgentUtilsScript.open_dev_agent_artifacts_folder(self)
func open_dev_agent_backups_folder() -> void:
	SyntreePanelDevAgentUtilsScript.open_dev_agent_backups_folder(self)
func _wire_dev_agent_patch_ui() -> void:
	SyntreePanelDevAgentUtilsScript._wire_dev_agent_patch_ui(self)
func _wire_dev_agent_artifacts_ui() -> void:
	SyntreePanelDevAgentUtilsScript._wire_dev_agent_artifacts_ui(self)
func _wire_dev_agent_run_spec_ui() -> void:
	SyntreePanelDevAgentUtilsScript._wire_dev_agent_run_spec_ui(self)
func _wire_dev_agent_loop_ui() -> void:
	SyntreePanelDevAgentUtilsScript._wire_dev_agent_loop_ui(self)
func _append_loop_log(line: String) -> void:
	SyntreePanelDevAgentUtilsScript._append_loop_log(self, line)
func _on_dev_agent_loop_log_line(line: String) -> void:
	SyntreePanelDevAgentUtilsScript._on_dev_agent_loop_log_line(self, line)
func _on_dev_agent_loop_finished(ok: bool, summary: String) -> void:
	SyntreePanelDevAgentUtilsScript._on_dev_agent_loop_finished(self, ok, summary)
func _on_dev_agent_loop_start_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_dev_agent_loop_start_pressed(self)
func _on_dev_agent_loop_stop_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_dev_agent_loop_stop_pressed(self)
func _dev_agent_apply_patch_text(patch_text: String) -> Dictionary:
	return SyntreePanelDevAgentUtilsScript._dev_agent_apply_patch_text(self, patch_text)
func _dev_agent_launch_harness_from_spec(spec: Dictionary) -> void:
	SyntreePanelDevAgentUtilsScript._dev_agent_launch_harness_from_spec(self, spec)
func _set_dev_agent_patch_result(text: String) -> void:
	SyntreePanelDevAgentUtilsScript._set_dev_agent_patch_result(self, text)
func _set_run_spec_result(text: String) -> void:
	SyntreePanelDevAgentUtilsScript._set_run_spec_result(self, text)
func _ensure_run_spec_ui_schema_loaded() -> void:
	SyntreePanelDevAgentUtilsScript._ensure_run_spec_ui_schema_loaded(self)
func _load_run_spec_ui_schema() -> Dictionary:
	return SyntreePanelDevAgentUtilsScript._load_run_spec_ui_schema(self)
func _apply_run_spec_ui_schema(schema: Dictionary) -> void:
	SyntreePanelDevAgentUtilsScript._apply_run_spec_ui_schema(self, schema)
func _dict_get_path(d: Dictionary, path: String, default_val: Variant = null) -> Variant:
	return SyntreePanelDevAgentUtilsScript._dict_get_path(self, d, path, default_val)
func _dict_set_path(d: Dictionary, path: String, value: Variant) -> void:
	SyntreePanelDevAgentUtilsScript._dict_set_path(self, d, path, value)
func _dict_erase_path(d: Dictionary, path: String) -> void:
	SyntreePanelDevAgentUtilsScript._dict_erase_path(self, d, path)
func _read_json_file_best_effort(path: String) -> Dictionary:
	return SyntreePanelDevAgentUtilsScript._read_json_file_best_effort(self, path)
func _get_harness_last_run_pointer_path() -> String:
	return SyntreePanelDevAgentUtilsScript._get_harness_last_run_pointer_path(self)
func _refresh_dev_agent_last_run_ui() -> void:
	SyntreePanelDevAgentUtilsScript._refresh_dev_agent_last_run_ui(self)
func _open_file_in_os(path_abs: String) -> void:
	SyntreePanelDevAgentUtilsScript._open_file_in_os(self, path_abs)
func _on_run_spec_refresh_last_run_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_run_spec_refresh_last_run_pressed(self)
func _on_run_spec_open_last_run_dir_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_run_spec_open_last_run_dir_pressed(self)
func _on_run_spec_open_last_run_manifest_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_run_spec_open_last_run_manifest_pressed(self)
func _on_run_spec_browse_scene_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_run_spec_browse_scene_pressed(self)
func _on_run_spec_scene_selected(res_path: String) -> void:
	SyntreePanelDevAgentUtilsScript._on_run_spec_scene_selected(self, res_path)
func _parse_run_spec_json_best_effort() -> Dictionary:
	return SyntreePanelDevAgentUtilsScript._parse_run_spec_json_best_effort(self)
func _write_run_spec_json(d: Dictionary) -> void:
	SyntreePanelDevAgentUtilsScript._write_run_spec_json(self, d)
func _on_run_spec_sync_to_json_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_run_spec_sync_to_json_pressed(self)
func _on_run_spec_fill_from_json_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_run_spec_fill_from_json_pressed(self)
func _dev_agent_guard_or_warn() -> bool:
	return SyntreePanelDevAgentUtilsScript._dev_agent_guard_or_warn(self)
func _get_current_thread_id_for_run_spec() -> String:
	return SyntreePanelDevAgentUtilsScript._get_current_thread_id_for_run_spec(self)
func _get_run_spec_dir() -> String:
	return SyntreePanelDevAgentUtilsScript._get_run_spec_dir(self)
func _get_run_spec_path_for_thread(thread_id: String) -> String:
	return SyntreePanelDevAgentUtilsScript._get_run_spec_path_for_thread(self, thread_id)
func _on_run_spec_load_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_run_spec_load_pressed(self)
func _on_run_spec_save_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_run_spec_save_pressed(self)
func _get_pending_run_spec_path() -> String:
	return SyntreePanelDevAgentUtilsScript._get_pending_run_spec_path(self)
func _on_run_spec_run_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_run_spec_run_pressed(self)
func _on_open_backups_folder_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_open_backups_folder_pressed(self)
func _on_open_artifacts_folder_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_open_artifacts_folder_pressed(self)
func _get_session_data_root_dir() -> String:
	return SyntreePanelDevAgentUtilsScript._get_session_data_root_dir(self)
func _open_folder_in_os(abs_dir: String) -> void:
	SyntreePanelDevAgentUtilsScript._open_folder_in_os(self, abs_dir)
func _get_dev_agent_backup_root_dir() -> String:
	return SyntreePanelDevAgentUtilsScript._get_dev_agent_backup_root_dir(self)
func _get_last_apply_manifest_path() -> String:
	return SyntreePanelDevAgentUtilsScript._get_last_apply_manifest_path(self)
func _write_last_apply_manifest(manifest: Dictionary) -> void:
	SyntreePanelDevAgentUtilsScript._write_last_apply_manifest(self, manifest)
func _read_last_apply_manifest() -> Dictionary:
	return SyntreePanelDevAgentUtilsScript._read_last_apply_manifest(self)
func _on_dev_agent_patch_dry_run_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_dev_agent_patch_dry_run_pressed(self)
func _on_dev_agent_patch_apply_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_dev_agent_patch_apply_pressed(self)
func _on_dev_agent_patch_revert_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_dev_agent_patch_revert_pressed(self)
func _on_dev_agent_patch_close_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_dev_agent_patch_close_pressed(self)
func _ensure_ensembles_popup() -> void:
	SyntreePanelDevAgentUtilsScript._ensure_ensembles_popup(self)
func _reload_current_thread() -> void:
	SyntreePanelDevAgentUtilsScript._reload_current_thread(self)
func _on_thread_dropdown_item_selected(index: int) -> void:
	SyntreePanelDevAgentUtilsScript._on_thread_dropdown_item_selected(self, index)
func _on_new_thread_button_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_new_thread_button_pressed(self)
func _on_thread_hub_versions_button_pressed() -> void:
	SyntreePanelDevAgentUtilsScript._on_thread_hub_versions_button_pressed(self)
func _on_chat_menu_toggled(button_pressed: bool) -> void:
	SyntreePanelDevAgentUtilsScript._on_chat_menu_toggled(self, button_pressed)
func _on_main_menu_toggled(button_pressed: bool) -> void:
	SyntreePanelDevAgentUtilsScript._on_main_menu_toggled(self, button_pressed)
func _on_dev_agent_toggled(button_pressed: bool) -> void:
	SyntreePanelDevAgentUtilsScript._on_dev_agent_toggled(self, button_pressed)
func _sync_dev_agent_toggle_from_bus() -> void:
	SyntreePanelDevAgentUtilsScript._sync_dev_agent_toggle_from_bus(self)
func _wire_dev_agent_bus_signal() -> void:
	SyntreePanelDevAgentUtilsScript._wire_dev_agent_bus_signal(self)
func _on_dev_agent_bus_changed(enabled: bool) -> void:
	SyntreePanelDevAgentUtilsScript._on_dev_agent_bus_changed(self, enabled)
func _update_layout_visibility() -> void:
	var layout_bus := SynTreeAutoloads.content_bus()
	if not is_instance_valid(layout_bus):
		return
	var current_view = layout_bus.get_current_view_mode()
	# Update container visibility based on view type
	if content_hierarchy and is_instance_valid(content_hierarchy):
		pass
	if content_list_view and is_instance_valid(content_list_view):
		pass
	# Graph view always stays visible regardless of the current view mode
	if graph_view and is_instance_valid(graph_view):
		pass
func _on_content_source_selected(index: int) -> void:
	await SyntreePanelContentSourcesGlue.on_content_source_selected(self, index)
func _load_all_content_sources() -> void:
	SyntreePanelContentSourcesGlue.load_all_content_sources(self)
# Handler functions for signals (May need review based on Resource architecture)
func _on_source_loaded(source_id: String) -> void:
	if is_instance_valid(content_list_view) and content_list_view.has_method("refresh_sources"):
		content_list_view.call_deferred("refresh_sources")
	call_deferred("update_content_source_options")
func _on_source_updated(source_id: String) -> void:
	if is_instance_valid(content_list_view) and content_list_view.has_method("refresh_sources"):
		content_list_view.call_deferred("refresh_sources")
	call_deferred("update_content_source_options")
func _on_source_deleted(source_id: String) -> void:
	if is_instance_valid(content_list_view) and content_list_view.has_method("refresh_sources"):
		content_list_view.call_deferred("refresh_sources")
	call_deferred("update_content_source_options")
func _on_sources_loaded() -> void:
	call_deferred("update_content_source_options")
func _on_thread_created(thread_id: String) -> void:
	_setup_chat_panel_controller()
	if is_instance_valid(_chat_panel_controller):
		_chat_panel_controller.call_deferred("update_thread_options")
func _on_thread_changed(thread_id: String) -> void:
	_setup_chat_panel_controller()
	if is_instance_valid(_chat_panel_controller):
		_chat_panel_controller.call_deferred("update_thread_options")
# Add this method to toggle detached mode
func toggle_detached_mode(detached: bool) -> void:
	print("SyntreePanel: Toggling detached mode: " + str(detached))
	detach_plugin_window_toggled.emit(detached)
## Updates the UI state based on current view and data
func _update_ui_state() -> void:
	print("SyntreePanel: Updating UI state")
	# NOTE: View switching is now resource-driven (ViewStateResource -> ContentViewManager).
	# Calling ContentViewManager internal handlers from here causes duplicate graph rebuilds/clears.
	# Keep this function as a lightweight hook for any future panel-level UI sync only.
	print("SyntreePanel: UI state updated")
# Add this getter method to provide access to the content list view
func get_content_list_view() -> Node:
	if content_list_view and is_instance_valid(content_list_view):
		return content_list_view
	# Try to find it by unique name
	content_list_view = get_node_or_null("%ContentList")
	return content_list_view
func _setup_content_view_manager() -> void:
	SyntreePanelBootstrap.setup_content_view_manager(self)
func _setup_content_sources_panel_controller() -> void:
	if is_instance_valid(_content_sources_panel_controller):
		return
	if not is_instance_valid(_content_state_resource) or not is_instance_valid(_view_state_resource):
		return
	if not is_instance_valid(save_custom_sources_popup):
		return
	_content_sources_panel_controller = ContentSourcesPanelControllerScript.new()
	_content_sources_panel_controller.name = "ContentSourcesPanelController"
	add_child(_content_sources_panel_controller)
	_content_sources_panel_controller.setup(
		_content_state_resource,
		_view_state_resource,
		content_hierarchy,
		graph_view,
		save_custom_sources_popup,
		_plugin_manager,
		_notification_manager,
		content_list_view,
		content_dir_path_label,
		Callable(self, "_get_action_source_id_for_menu"),
		Callable(self, "_get_source_display_name"),
		Callable(self, "_popup_menu_centered"),
		Callable(self, "_show_warning_dialog"),
		Callable(self, "_show_error_dialog"),
		Callable(self, "_get_selected_node_id_for_tree_actions"),
		Callable(self, "_raw_node_id"),
		Callable(self, "_refresh_hierarchy_view_deferred"),
		Callable(self, "_open_edit_content_source_dialog"),
		Callable(self, "_refresh_selected_source_content"),
		Callable(self, "_toggle_select_all_sources"),
		Callable(self, "_toggle_select_all_graph_nodes"),
		Callable(self, "_toggle_select_all_hierarchy_nodes"),
		Callable(self, "_request_delete_selected_node")
	)
func _setup_model_settings_controller() -> void:
	# Domain controller for model/provider settings.
	if not is_instance_valid(_model_settings_controller):
		_model_settings_controller = ModelSettingsControllerScript.new()
		_model_settings_controller.name = "ModelSettingsController"
		add_child(_model_settings_controller)
	if is_instance_valid(_model_settings_controller):
		_model_settings_controller.setup(
			_ai_model_manager,
			ai_model_selector,
			api_provider_selector,
			api_key_input,
			ollama_status_label,
			ollama_endpoint_input,
			Callable(self, "_show_error_dialog"),
			Callable(self, "_emit_operation_failed"),
			"gemma4:26b"
		)
		# Populate the model selector immediately whenever a valid manager is injected.
		# This provides a fallback if the bootstrap's explicit call is missed (build timing).
		if is_instance_valid(_ai_model_manager):
			_model_settings_controller.populate_model_selector()
func _setup_chat_panel_controller() -> void:
	# Domain controller for conversation UI behavior.
	if not is_instance_valid(_chat_panel_controller):
		_chat_panel_controller = ChatPanelControllerScript.new()
		_chat_panel_controller.name = "ChatPanelController"
		add_child(_chat_panel_controller)
	if is_instance_valid(_chat_panel_controller):
		_chat_panel_controller.setup(
			_conversation_manager,
			_view_state_resource,
			_message_container,
			_notification_manager,
			message_input,
			send_button,
			stop_request_button,
			thread_dropdown,
			new_thread_button,
			new_thread_name_input,
			edit_history_popup,
			history_text_edit,
			top_toolbar_controls,
			bottom_toolbar_controls,
			Callable(self, "_show_error_dialog"),
			Callable(self, "_emit_operation_failed")
		)
func _setup_status_hub_controller() -> void:
	if is_instance_valid(_status_hub_controller):
		return
	_status_hub_controller = StatusHubControllerScript.new()
	_status_hub_controller.name = "StatusHubController"
	add_child(_status_hub_controller)
	_status_hub_controller.setup(
		_ai_model_manager,
		_conversation_manager,
		_view_state_resource,
		api_provider_selector,
		ai_model_selector,
		status_strip_label,
		system_info_label,
		thread_hub_versions_popup,
		thread_hub_versions_list,
		Callable(self, "_refresh_thread_view_after_hub_load"),
		Callable(self, "_emit_operation_failed")
	)
func _setup_publish_context_graph_controller() -> void:
	if is_instance_valid(_publish_context_graph_controller):
		return
	if not is_instance_valid(_content_state_resource):
		return
	_publish_context_graph_controller = PublishContextGraphControllerScript.new()
	_publish_context_graph_controller.name = "PublishContextGraphController"
	add_child(_publish_context_graph_controller)
	_publish_context_graph_controller.setup(
		_content_state_resource,
		Callable(self, "_show_warning_dialog"),
		Callable(self, "_show_error_dialog"),
		Callable(self, "_set_status_strip_text"),
		Callable(self, "_notify_info"),
		Callable(self, "_notify_success")
	)
func update_content_source_options() -> void:
	print("SyntreePanel: Delegating content source update to ContentViewManager")
	# --- Use the INSTANCE reference --- 
	if not is_instance_valid(content_view_manager_instance):
		push_error("SyntreePanel: Cannot update content sources - ContentViewManager instance not valid!")
		# Try setting it up again?
		_setup_content_view_manager()
		if not is_instance_valid(content_view_manager_instance):
			return # Still not valid, give up
	# ContentViewManager no longer owns list population; List View refreshes itself.
	if is_instance_valid(content_list_view) and content_list_view.has_method("refresh_sources"):
		content_list_view.call_deferred("refresh_sources")
func setup_panels() -> void:
	SyntreePanelBootstrap.setup_panels(self)
## Graph controller initialization is owned by `ContentViewManager` (single coordinator).
## Keeping graph setup out of the panel avoids duplicate controllers and stale GraphEdit bindings.
func _ensure_resources_from_content_bus() -> void:
	SyntreePanelBootstrap.ensure_resources_from_content_bus(self)
func _on_show_error_requested(title: String, message: String, details: String = "") -> void:
	_show_error_dialog(title, message)
func _setup_conversation_manager():
	# Ensure we have a ConversationManager reference for chat UI and for disk-backed thread list.
	if is_instance_valid(_conversation_manager):
		return
	if is_instance_valid(_plugin_manager) and _plugin_manager.has_method("get_conversation_manager"):
		_conversation_manager = _plugin_manager.get_conversation_manager()
	# If we already have the chat panel controller instantiated, refresh it.
	_setup_chat_panel_controller()
	if is_instance_valid(_chat_panel_controller):
		_chat_panel_controller.update_thread_options()
# --- KEEP OTHER PLACEHOLDERS/HANDLERS --- 
func setup_content_source_manager():
	SyntreePanelContentSourcesGlue.setup_content_source_manager(self)
func _setup_content_list_view() -> void:
	SyntreePanelContentSourcesGlue.setup_content_list_view(self)
func _wire_content_source_dialog_signals() -> void:
	SyntreePanelContentSourcesGlue.wire_content_source_dialog_signals(self)
# --- END PLACEHOLDER FUNCTIONS --- 
func _on_add_source_btn_pressed() -> void:
	SyntreePanelContentSourcesGlue.on_add_source_btn_pressed(self)
func _on_delete_source_btn_pressed() -> void:
	SyntreePanelContentSourcesGlue.on_delete_source_btn_pressed(self)
func _on_footer_filter_pressed() -> void:
	SyntreePanelContentSourcesGlue.on_footer_filter_pressed(self)
func _on_footer_stats_pressed() -> void:
	SyntreePanelContentSourcesGlue.on_footer_stats_pressed(self)
func _setup_footer_refresh_menu() -> void:
	SyntreePanelContentSourcesGlue.setup_footer_refresh_menu(self)
func _on_footer_refresh_menu_id_pressed(id: int) -> void:
	SyntreePanelContentSourcesGlue.on_footer_refresh_menu_id_pressed(self, id)
func _on_footer_search_submitted(query: String) -> void:
	SyntreePanelContentSourcesGlue.on_footer_search_submitted(self, query)
var _last_selected_node_id: String = ""
var _last_action_source_id: String = "" # updated when a node is selected (graph/hierarchy) for SourceMenu context
var _content_source_editor_instance: Node = null
var _pending_state_overrides_by_source_id: Dictionary = {} # source_id -> {"is_active": bool, "is_metaprompt": bool}
# Pending: "Add Child…" flow from hierarchy context menu.
# We open the Create Source(s) dialog, then attach the newly created source as a linked child node.
# (moved into AddChildFlowController)
func _wire_content_state_signals() -> void:
	SyntreePanelContentSourcesGlue.wire_content_state_signals(self)
func _on_content_source_selected_from_state(source_id: String, selected: bool) -> void:
	SyntreePanelContentSourcesGlue.on_content_source_selected_from_state(self, source_id, selected)
func _on_content_node_selected(node_id: String) -> void:
	SyntreePanelContentSourcesGlue.on_content_node_selected(self, node_id)
func _get_action_source_id_for_menu() -> String:
	return str(SyntreePanelContentSourcesGlue.get_action_source_id_for_menu(self))
func _popup_menu_centered(pm: PopupMenu) -> void:
	SyntreePanelContentSourcesGlue.popup_menu_centered(self, pm)
func _get_selected_single_source_id_for_menu() -> String:
	return str(SyntreePanelContentSourcesGlue.get_selected_single_source_id_for_menu(self))
func _get_source_display_name(source_id: String) -> String:
	return str(SyntreePanelContentSourcesGlue.get_source_display_name(self, source_id))
func _on_content_source_menu_button_pressed() -> void:
	if not is_instance_valid(_content_sources_panel_controller):
		_setup_content_sources_panel_controller()
	if not is_instance_valid(_content_sources_panel_controller):
		return
	var tree_menu := get_node_or_null("%TreeContextMenu")
	var src_menu := get_node_or_null("%ContentSourceContextMenu")
	if not (is_instance_valid(tree_menu) and tree_menu is PopupMenu and is_instance_valid(src_menu) and src_menu is PopupMenu):
		return
	_content_sources_panel_controller.on_source_menu_button_pressed(tree_menu as PopupMenu, src_menu as PopupMenu)
func _are_all_sources_selected(all_ids: Array[String]) -> bool:
	return bool(SyntreePanelContentSourcesGlue.are_all_sources_selected(self, all_ids))
func _toggle_select_all_sources() -> void:
	SyntreePanelContentSourcesGlue.toggle_select_all_sources(self)
func _get_all_visible_graph_node_ids() -> Array[String]:
	var any: Variant = SyntreePanelContentSourcesGlue.get_all_visible_graph_node_ids(self)
	return any if typeof(any) == TYPE_ARRAY else []
func _are_all_graph_nodes_selected(node_ids: Array[String]) -> bool:
	return bool(SyntreePanelContentSourcesGlue.are_all_graph_nodes_selected(self, node_ids))
func _toggle_select_all_graph_nodes() -> void:
	SyntreePanelContentSourcesGlue.toggle_select_all_graph_nodes(self)
func _refresh_selected_source_content(source_id: String) -> void:
	SyntreePanelContentSourcesGlue.refresh_selected_source_content(self, source_id)
func _open_edit_content_source_dialog(source_id: String) -> void:
	SyntreePanelContentSourcesGlue.open_edit_content_source_dialog(self, source_id)
func _apply_edited_content_source(source_id: String, new_name: String, new_path: String) -> void:
	SyntreePanelContentSourcesGlue.apply_edited_content_source(self, source_id, new_name, new_path)
func _apply_source_ai_flags(source_id: String, is_active: bool, is_metaprompt: bool) -> void:
	SyntreePanelContentSourcesGlue.apply_source_ai_flags(self, source_id, is_active, is_metaprompt)
func _toggle_select_all_hierarchy_nodes() -> void:
	SyntreePanelContentSourcesGlue.toggle_select_all_hierarchy_nodes(self)
func _get_selected_node_id_for_tree_actions(source_id: String) -> String:
	return str(SyntreePanelContentSourcesGlue.get_selected_node_id_for_tree_actions(self, source_id))
func _raw_node_id(any_id: String) -> String:
	return str(SyntreePanelContentSourcesGlue.raw_node_id(self, any_id))
func _add_child_node_under_selection(fallback_source_id: String) -> void:
	if not is_instance_valid(_content_sources_panel_controller):
		_setup_content_sources_panel_controller()
	if is_instance_valid(_content_sources_panel_controller):
		_content_sources_panel_controller.begin_add_child(fallback_source_id)
		return
	_show_warning_dialog("Add Child Failed", "ContentSourcesPanelController not available.")
func _request_delete_selected_node() -> void:
	SyntreePanelContentSourcesGlue.request_delete_selected_node(self)
func _delete_selected_node() -> void:
	SyntreePanelContentSourcesGlue.delete_selected_node(self)
func _move_selected_node(delta: int) -> void:
	if not is_instance_valid(_content_sources_panel_controller):
		_setup_content_sources_panel_controller()
	if is_instance_valid(_content_sources_panel_controller):
		_content_sources_panel_controller.move_selected(delta)
		return
	# Fallback (should not happen): keep behavior safe.
	_show_warning_dialog("Move Failed", "ContentSourcesPanelController not available.")
func _refresh_hierarchy_view_deferred() -> void:
	# Rebuild hierarchy UI after mutations so the user sees the effect.
	if not is_instance_valid(_view_state_resource) or not is_instance_valid(content_hierarchy):
		return
	if int(_view_state_resource.current_mode) != 1:
		return
	if not content_hierarchy.has_method("display_hierarchy_with_id"):
		return
	var display_id := String(_view_state_resource.current_source_id).strip_edges()
	call_deferred("_refresh_hierarchy_view_now", display_id)
func _refresh_hierarchy_view_now(display_id: String) -> void:
	if not is_instance_valid(content_hierarchy) or not content_hierarchy.has_method("display_hierarchy_with_id"):
		return
	var sid := String(display_id).strip_edges()
	if sid.is_empty():
		return
	content_hierarchy.display_hierarchy_with_id(sid)
func _on_create_sources_menu_pressed(id: int) -> void:
	match id:
		0:  # Save Custom Sources
			save_custom_sources_popup.show_dialog()
		1:  # Create Source Stack
			_setup_content_sources_panel_controller()
			if is_instance_valid(_content_sources_panel_controller) and _content_sources_panel_controller.has_method("create_source_stack_from_active"):
				_content_sources_panel_controller.create_source_stack_from_active()
func _on_manage_sources_menu_pressed(id: int) -> void:
	SyntreePanelContentSourcesGlue.on_manage_sources_menu_pressed(self, id)
func _on_sources_refreshed(result: Dictionary) -> void:
	if not result.get("success", false):
		var error = result.get("error", "Unknown error")
		_show_error_dialog("Refresh Failed", "Failed to refresh sources: " + error)
		return
	var count = result.get("refreshed_count", 0)
	var errors = result.get("errors", [])
	if errors.size() > 0:
		# Show warning if some sources failed but overall operation succeeded
		var error_msg = "Some sources failed to refresh:\n" + "\n".join(errors)
		_show_warning_dialog("Partial Refresh", error_msg)
	# Update UI to reflect refreshed content
	if content_list_view and content_list_view.has_method("refresh_sources"):
		content_list_view.refresh_sources()
func _show_error_dialog(title: String, message: String) -> void:
	if _notification_manager:
		_notification_manager.error(message, title)
	else:
		push_error("[%s] %s: %s" % [_debug_name, title, message])
		show_error_requested.emit(title, message, "")
func _emit_operation_failed(operation: String, error: String, details: String = "") -> void:
	operation_failed.emit(operation, error, details)
func _show_warning_dialog(title: String, message: String) -> void:
		if _notification_manager:
			_notification_manager.warning(message, title)
		else:
			push_warning("[%s] %s: %s" % [_debug_name, title, message])
			show_error_requested.emit(title, message, "")
func _set_status_strip_text(text: String) -> void:
	if is_instance_valid(status_strip_label):
		status_strip_label.text = String(text)
func _on_hub_connection_changed(is_connected: bool) -> void:
	if is_connected:
		_set_status_strip_text("Hub back online \u2014 Voice and workspace features restored.")
	else:
		_set_status_strip_text("Hub offline \u2014 Voice and embedding paused. Direct AI chat may still work. Check Tools \u2192 Services.")
func _notify_info(message: String, title: String = "") -> void:
	if is_instance_valid(_notification_manager) and _notification_manager.has_method("info"):
		_notification_manager.info(String(message), String(title))
func _notify_success(message: String, title: String = "") -> void:
	if is_instance_valid(_notification_manager) and _notification_manager.has_method("success"):
		_notification_manager.success(String(message), String(title))
# Re-add handlers, now responsible for triggering UI refresh
func _on_source_created_confirmed(source_info: Dictionary) -> void: # Renamed param
	await SyntreePanelContentSourcesGlue.on_source_created_confirmed(self, source_info)
# Corrected handler name and signature
func _on_batched_sources_created_confirmed(sources_array: Array) -> void: # Renamed param for clarity
	SyntreePanelContentSourcesGlue.on_batched_sources_created_confirmed(self, sources_array)
func _on_content_source_cancelled() -> void:
	pass
func _on_remote_source_processed(source_id: String) -> void:
	SyntreePanelContentSourcesGlue.on_remote_source_processed(self, source_id)
func _update_active_filters_label(filters: Dictionary) -> void:
	SyntreePanelContentSourcesGlue.update_active_filters_label(self, filters)
