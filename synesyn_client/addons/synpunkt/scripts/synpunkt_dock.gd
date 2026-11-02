@tool
extends Control

# NOTE: Avoid shadowing `class_name` globals with same-named preload constants.
# Shadowing breaks GDScript member resolution (e.g. `_render.comfy`).
const HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
const SynesynRenderServiceScript = preload("res://addons/synesyn_core/scripts/synesyn_render_service.gd")
const SynesynSessionScript = preload("res://addons/synesyn_core/scripts/synesyn_session.gd")
const SynesynAutoloadAccessScript = preload("res://addons/synesyn_core/scripts/synesyn_autoload_access.gd")
const _SYNPUNKT_LOGO_DARK := preload("res://addons/synpunkt/icons/SynPunkt_logo.svg")
const _SYNPUNKT_LOGO_WHITE := preload("res://addons/synpunkt/icons/SynPunkt_logo_white.svg")
const EdgelessPreviewScript = preload("res://addons/synpunkt/scripts/edgeless_preview.gd")
const WorkflowUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_workflow_utils.gd")
const SyndocSlidesUtilsScript = preload("res://addons/synpunkt/scripts/internal/syndoc_slides_utils.gd")
const RenderActionsUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_actions_utils.gd")
const ArtifactBrowserUtilsScript = preload("res://addons/synpunkt/scripts/internal/artifact_browser_utils.gd")
const RenderResultsBrowserUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_results_browser_utils.gd")
const RenderResultsDetailsUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_results_details_utils.gd")
const SyndocActionsUtilsScript = preload("res://addons/synpunkt/scripts/internal/syndoc_actions_utils.gd")
const RenderResultsLinksUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_results_links_utils.gd")
const FrameBlockEditorUtilsScript = preload("res://addons/synpunkt/scripts/internal/frame_block_editor_utils.gd")
const PresentNavigationUtilsScript = preload("res://addons/synpunkt/scripts/internal/present_navigation_utils.gd")
const RenderCommonParamsUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_common_params_utils.gd")
const SyndocFrameSyncUtilsScript = preload("res://addons/synpunkt/scripts/internal/syndoc_frame_sync_utils.gd")
const UiConnectionsUtilsScript = preload("res://addons/synpunkt/scripts/internal/ui_connections_utils.gd")
const RenderSettingsUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_settings_utils.gd")
const SyndocRefsUtilsScript = preload("res://addons/synpunkt/scripts/internal/syndoc_refs_utils.gd")
const RenderSubmitUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_submit_utils.gd")
const EdgelessLayoutBuilderUtilsScript = preload("res://addons/synpunkt/scripts/internal/edgeless_layout_builder_utils.gd")
const RenderRecipeUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_recipe_utils.gd")
const RenderWorkflowSelectorUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_workflow_selector_utils.gd")
const StartupUtilsScript = preload("res://addons/synpunkt/scripts/internal/startup_utils.gd")
const RenderWorkflowOpsUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_workflow_ops_utils.gd")
const ArtifactDeleteUtilsScript = preload("res://addons/synpunkt/scripts/internal/artifact_delete_utils.gd")
const EdgelessInteractionUtilsScript = preload("res://addons/synpunkt/scripts/internal/edgeless_interaction_utils.gd")
const PresentCameraUtilsScript = preload("res://addons/synpunkt/scripts/internal/present_camera_utils.gd")
const UiHubUtilsScript = preload("res://addons/synpunkt/scripts/internal/ui_hub_utils.gd")
const RenderJobsUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_jobs_utils.gd")
const ARTIFACT_CLOSURE := "ui.closure"
const ARTIFACT_SYNDOC := "ui.syndoc"

@onready var _root: Node = %Root

@onready var _closures_list: Tree = %ClosuresList
@onready var _refresh_btn: Button = %RefreshClosures
@onready var _load_btn: Button = %LoadClosure
@onready var _refresh_store_closures_btn: Button = get_node_or_null("%RefreshStoreClosures") as Button
@onready var _refresh_store_context_packs_btn: Button = get_node_or_null("%RefreshStoreContextPacks") as Button
@onready var _create_demo_closure: Button = get_node_or_null("%CreateDemoClosure") as Button
@onready var _delete_closure_btn: Button = get_node_or_null("%DeleteClosure") as Button

@onready var _flowdocs_list: Tree = %SynDocsList
@onready var _refresh_flowdocs_btn: Button = %RefreshSynDocs
@onready var _load_flowdoc_btn: Button = %LoadSynDoc
@onready var _new_empty_flowdoc: Button = get_node_or_null("%NewEmptySynDoc") as Button
@onready var _delete_syndoc_btn: Button = get_node_or_null("%DeleteSynDoc") as Button
@onready var _closure_json: TextEdit = %ClosureJson

@onready var _hub_url: LineEdit = %HubUrl
@onready var _apply_hub_url: Button = %ApplyHubUrl
@onready var _toggle_artifacts: Button = get_node_or_null("%ToggleArtifacts") as Button

@onready var _flowdoc_title: LineEdit = %SynDocTitle
@onready var _generate_btn: Button = %GenerateSynDoc
@onready var _flowdoc_json: TextEdit = %SynDocJson
@onready var _flowdoc_json_resize_handle: Control = get_node_or_null("%SynDocJsonResizeHandle") as Control
@onready var _save_btn: Button = %SaveSynDoc
@onready var _save_version_btn: Button = %SaveAsNewVersion
@onready var _validate_btn: Button = %ValidateSynDoc
@onready var _slides_deck_artifact_id: LineEdit = get_node_or_null("%SlidesDeckArtifactId") as LineEdit
@onready var _import_slides_deck: Button = get_node_or_null("%ImportSlidesDeck") as Button
@onready var _export_slides_deck: Button = get_node_or_null("%ExportSlidesDeck") as Button

# SynDoc refs (v0)
@onready var _ref_closure: LineEdit = %ClosureRef
@onready var _ref_context_graph: LineEdit = %ContextGraphRef
@onready var _ref_prompt_chain: LineEdit = %PromptChainRef
@onready var _ref_projection: LineEdit = %ProjectionRef
@onready var _ref_cluster: LineEdit = %ClusterRef
@onready var _toggle_advanced_refs: Button = get_node_or_null("%ToggleAdvancedRefs") as Button
@onready var _prompt_chain_ref_row: Control = get_node_or_null("%PromptChainRefRow") as Control
@onready var _projection_ref_row: Control = get_node_or_null("%ProjectionRefRow") as Control
@onready var _cluster_ref_row: Control = get_node_or_null("%ClusterRefRow") as Control
@onready var _how_to_rich_text: RichTextLabel = get_node_or_null("%HowToRichText") as RichTextLabel
@onready var _build_edgeless_layout: Button = %BuildEdgelessLayout
@onready var _rebuild_edgeless_keep_edits: Button = %RebuildEdgelessKeepEdits
@onready var _reset_edgeless_view: Button = %ResetEdgelessView
@onready var _fit_edgeless_to_layout: Button = get_node_or_null("%FitEdgelessToLayout") as Button
@onready var _edgeless_preview: EdgelessPreview = %EdgelessPreview
@onready var _edgeless_show_labels: CheckBox = %ShowEdgelessLabels
@onready var _edgeless_edit_layout: CheckBox = %EditEdgelessLayout
@onready var _edgeless_snap: CheckBox = %SnapToGrid
@onready var _edgeless_avoid_overlap: CheckBox = get_node_or_null("%AvoidOverlap") as CheckBox
@onready var _edgeless_grid_size: SpinBox = %GridSize
@onready var _edgeless_view_style: OptionButton = get_node_or_null("%EdgelessViewStyle") as OptionButton
@onready var _edgeless_align_to_grid: Button = %AlignToGrid
@onready var _edgeless_center_x: Button = %CenterX
@onready var _edgeless_center_y: Button = %CenterY
@onready var _edgeless_label_edit: LineEdit = %EdgelessLabelEdit
@onready var _edgeless_apply_label: Button = %ApplyEdgelessLabel
@onready var _edgeless_resize_handle: Control = get_node_or_null("%EdgelessResizeHandle") as Control

# Block editor UI (v0)
@onready var _blocks_list: ItemList = %BlocksList
@onready var _blocks_label: Label = %BlocksLabel
@onready var _move_up_block: Button = %MoveUpBlock
@onready var _move_down_block: Button = %MoveDownBlock
@onready var _delete_block: Button = %DeleteBlock
@onready var _frames_list: ItemList = %FramesList
@onready var _add_frame: Button = %AddFrame
@onready var _delete_frame: Button = %DeleteFrame
@onready var _move_frame_up: Button = %MoveFrameUp
@onready var _move_frame_down: Button = %MoveFrameDown
@onready var _frame_id: LineEdit = %FrameId
@onready var _apply_frame_id: Button = %ApplyFrameId

@onready var _send_to_frame: OptionButton = %SendToFrame
@onready var _move_block_to_frame: Button = %MoveBlockToFrame

@onready var _prev_frame: Button = %PrevFrame
@onready var _next_frame: Button = %NextFrame

# Performer mode
@onready var _perform_prev: Button = %PresentPrev
@onready var _perform_next: Button = %PresentNext
@onready var _perform_frame_label: Label = %PresentFrameLabel
@onready var _perform_preview: RichTextLabel = %PresentPreview
@onready var _present_view_tabs: TabContainer = %PresentViewTabs
@onready var _present_edgeless_preview: EdgelessPreview = %PresentEdgelessPreview
@onready var _present_edgeless_selection: Label = %PresentEdgelessSelection
@onready var _present_prev_cluster: Button = %PresentPrevCluster
@onready var _present_next_cluster: Button = %PresentNextCluster
@onready var _present_make_frame: Button = %PresentMakeFrameFromCluster
@onready var _present_reset_view: Button = %PresentResetEdgelessView
@onready var _present_show_labels: CheckBox = %PresentShowLabels
@onready var _present_capture_camera: Button = get_node_or_null("%PresentCaptureCamera") as Button
@onready var _present_deck_capture: CheckBox = get_node_or_null("%PresentDeckCapture") as CheckBox
@onready var _present_clear_deck: Button = get_node_or_null("%PresentClearDeck") as Button
@onready var _present_apply_camera: Button = get_node_or_null("%PresentApplyCamera") as Button
@onready var _block_type: OptionButton = %BlockType
@onready var _insert_after_block: Button = %InsertAfterBlock
@onready var _block_text: TextEdit = %BlockText

@onready var _status: Label = %Status
@onready var _delete_confirm_dialog: ConfirmationDialog = %DeleteConfirmDialog

var _pending_delete_artifact_ids: Array[String] = []
var _pending_delete_kind: String = "" # "closure" | "syndoc"

# Checkbox selection (Tree checkbox cell; no prefix hacks)
var _checked_closure_ids: Dictionary = {} # artifact_id -> true
var _checked_syndoc_ids: Dictionary = {} # artifact_id -> true

# Settings (Host/Join)
@onready var _host_ip: OptionButton = get_node_or_null("%HostIp") as OptionButton
@onready var _host_port: SpinBox = get_node_or_null("%HostPort") as SpinBox
@onready var _host_copy_url: Button = get_node_or_null("%HostCopyUrl") as Button
@onready var _join_hub_url: LineEdit = get_node_or_null("%JoinHubUrl") as LineEdit
@onready var _join_test: Button = get_node_or_null("%JoinTest") as Button
@onready var _join_save: Button = get_node_or_null("%JoinSave") as Button
@onready var _join_use_auth: CheckBox = get_node_or_null("%JoinUseAuth") as CheckBox
@onready var _join_auth_token: LineEdit = get_node_or_null("%JoinAuthToken") as LineEdit

# Render mode (v1)
@onready var _comfy_url: LineEdit = get_node_or_null("%ComfyUrl") as LineEdit
@onready var _comfy_url_history: OptionButton = get_node_or_null("%ComfyUrlHistory") as OptionButton
@onready var _test_comfy: Button = get_node_or_null("%TestComfy") as Button
@onready var _render_route_mode_picker: OptionButton = get_node_or_null("%RenderRouteMode") as OptionButton
@onready var _workflow_select: OptionButton = get_node_or_null("%Workflow") as OptionButton
@onready var _submit_render: Button = get_node_or_null("%SubmitRender") as Button
@onready var _load_workflow_from_flowdoc: Button = get_node_or_null("%LoadWorkflowFromSynDoc") as Button
@onready var _auto_save_workflows: CheckBox = get_node_or_null("%RenderAutoSaveWorkflows") as CheckBox
@onready var _save_workflow_preset: Button = get_node_or_null("%SaveWorkflowPreset") as Button
@onready var _preset_tags: LineEdit = get_node_or_null("%PresetTags") as LineEdit
@onready var _preset_model_family: LineEdit = get_node_or_null("%PresetModelFamily") as LineEdit
@onready var _save_preset_version_btn: Button = get_node_or_null("%SavePresetVersion") as Button
@onready var _diff_selected_preset_btn: Button = get_node_or_null("%DiffSelectedPreset") as Button
@onready var _archive_selected_preset_btn: Button = get_node_or_null("%ArchiveSelectedPreset") as Button
@onready var _prune_archived_preset_btn: Button = get_node_or_null("%PruneArchivedPreset") as Button
@onready var _load_default_workflow: Button = get_node_or_null("%LoadDefaultWorkflow") as Button
@onready var _clear_workflow_inputs: Button = get_node_or_null("%ClearWorkflowInputs") as Button
@onready var _workflow_health_label: Label = get_node_or_null("%WorkflowHealthLabel") as Label
@onready var _common_detect_from_workflow: Button = get_node_or_null("%CommonDetectFromWorkflow") as Button
@onready var _common_apply_to_patch: Button = get_node_or_null("%CommonApplyToPatch") as Button
@onready var _common_prompt: LineEdit = get_node_or_null("%CommonPrompt") as LineEdit
@onready var _common_negative: LineEdit = get_node_or_null("%CommonNegative") as LineEdit
@onready var _common_seed: SpinBox = get_node_or_null("%CommonSeed") as SpinBox
@onready var _common_seed_randomize: CheckBox = get_node_or_null("%CommonSeedRandomize") as CheckBox
@onready var _common_steps: SpinBox = get_node_or_null("%CommonSteps") as SpinBox
@onready var _common_cfg: SpinBox = get_node_or_null("%CommonCfg") as SpinBox
@onready var _common_denoise: SpinBox = get_node_or_null("%CommonDenoise") as SpinBox
@onready var _common_width: SpinBox = get_node_or_null("%CommonWidth") as SpinBox
@onready var _common_height: SpinBox = get_node_or_null("%CommonHeight") as SpinBox
@onready var _workflow_json: TextEdit = get_node_or_null("%WorkflowJson") as TextEdit
@onready var _patch_json: TextEdit = get_node_or_null("%PatchJson") as TextEdit
@onready var _render_results: ItemList = get_node_or_null("%RenderResults") as ItemList
@onready var _render_results_filter: LineEdit = get_node_or_null("%RenderResultsFilter") as LineEdit
@onready var _render_results_sort: OptionButton = get_node_or_null("%RenderResultsSort") as OptionButton
@onready var _render_insert_into_frame: Button = get_node_or_null("%RenderInsertIntoFrame") as Button
@onready var _render_copy_artifact_id: Button = get_node_or_null("%RenderCopyArtifactId") as Button
@onready var _render_open_artifact_folder: Button = get_node_or_null("%RenderOpenArtifactFolder") as Button
@onready var _render_clear_results: Button = get_node_or_null("%RenderClearResults") as Button
@onready var _render_refresh_results: Button = get_node_or_null("%RenderRefreshResults") as Button
@onready var _render_delete_render_request: Button = get_node_or_null("%RenderDeleteRenderRequest") as Button
@onready var _render_delete_selected_artifacts: Button = get_node_or_null("%RenderDeleteSelectedArtifacts") as Button
@onready var _render_artifact_name_default: LineEdit = get_node_or_null("%RenderArtifactNameDefault") as LineEdit
@onready var _save_render_artifact_name_default: Button = get_node_or_null("%SaveRenderArtifactNameDefault") as Button
@onready var _render_artifact_name_edit: LineEdit = get_node_or_null("%RenderArtifactNameEdit") as LineEdit
@onready var _rename_selected_render_artifact_btn: Button = get_node_or_null("%RenameSelectedRenderArtifact") as Button
@onready var _reset_selected_render_artifact_name_btn: Button = get_node_or_null("%ResetSelectedRenderArtifactName") as Button
@onready var _render_artifact_details: RichTextLabel = get_node_or_null("%RenderArtifactDetails") as RichTextLabel
@onready var _render_details_load_workflow_btn: Button = get_node_or_null("%RenderDetailsLoadWorkflow") as Button
@onready var _render_details_load_render_request_btn: Button = get_node_or_null("%RenderDetailsLoadRenderRequest") as Button
@onready var _render_details_copy_links_btn: Button = get_node_or_null("%RenderDetailsCopyLinks") as Button
@onready var _enable_sensor_overlay: CheckBox = get_node_or_null("%EnableSensorOverlay") as CheckBox
@onready var _snapshot_sensors: Button = get_node_or_null("%SnapshotSensors") as Button
@onready var _sensor_events: ItemList = get_node_or_null("%SensorEventsList") as ItemList
@onready var _render_jobs_label: Label = get_node_or_null("%RenderJobsLabel") as Label
@onready var _refresh_render_jobs_btn: Button = get_node_or_null("%RefreshRenderJobs") as Button
@onready var _cancel_render_job_btn: Button = get_node_or_null("%CancelRenderJob") as Button
@onready var _retry_render_job_btn: Button = get_node_or_null("%RetryRenderJob") as Button
@onready var _resume_render_job_btn: Button = get_node_or_null("%ResumeRenderJob") as Button
@onready var _render_jobs_list: ItemList = get_node_or_null("%RenderJobsList") as ItemList
@onready var _render_recipe_name: LineEdit = get_node_or_null("%RenderRecipeName") as LineEdit
@onready var _save_render_recipe: Button = get_node_or_null("%SaveRenderRecipe") as Button
@onready var _render_results_label: Label = get_node_or_null("%RenderResultsLabel") as Label

var _hub: HubSubstrateClient

# Present → Edgeless: resolve image artifact ids to file:// URIs (so frame cards can render images).
var _present_image_uri_map: Dictionary = {} # artifact_id -> uri
var _present_image_resolve_queue: Array[String] = []
var _present_image_resolve_inflight: bool = false
var _present_image_resolve_http: HTTPRequest
# NOTE: Keep `_render` untyped to avoid editor-time parse failures when GDScript
# cannot introspect external class members (e.g. `_render.comfy`) during load.
var _render
var _sensor_enabled: bool = false
var _sensor_latest_by_source: Dictionary = {} # source_id -> evt
var _sensor_recent: Array = [] # ring of recent events (for snapshot)
var _last_sensor_snapshot_artifact_id: String = ""
var _render_workflow_options: Array = [] # [{artifact_id, created_at}]
var _render_request_options: Array = [] # [{artifact_id, created_at}]
var _last_saved_workflow_artifact_id: String = ""
var _last_saved_render_request_artifact_id: String = ""
var _render_auto_save_workflows_enabled: bool = false
var _render_seen_workflow_hash_to_workflow_id: Dictionary = {} # workflow_hash_sha256 -> artifact_id
var _render_seen_workflow_hash_skipped: Dictionary = {} # workflow_hash_sha256 -> true (unused; kept for back-compat)
var _common_param_targets: Dictionary = {} # key -> {node_id, input}
var _last_workflow_select_meta: Dictionary = {}
var _render_artifact_name_prefix: String = "Render"
var _render_artifact_name_next_index: int = 1
var _comfy_url_recent: Array[String] = []
var _comfy_url_history_refreshing: bool = false
var _render_route_mode: String = "direct"
var _render_results_cache: Array = [] # [{artifact_id, created_at, metadata_json, uri, hash, artifact_type}]
var _last_render_selected_artifact_id: String = ""
var _render_details_update_seq: int = 0
var _render_jobs_cache: Array = [] # [{id,status,output_json,...}]
var _last_selected_render_job_id: String = ""
var _render_results_last_refresh_source: String = ""
var _render_results_last_refresh_unix: int = 0
var _render_results_last_refresh_count: int = 0
var _render_results_last_refresh_ok: bool = false
var _render_results_last_refresh_error: String = ""
var _session_id: String = ""
var _current_turn_id: String = ""
var _closure_rows: Array = [] # array of row arrays, aligned to _closure_cols
var _closure_cols: Array = []
var _closure_browser_mode: String = "substrate_closure"
var _store_closure_records: Array = []
var _store_context_pack_records: Array = []
var _active_closure_id: String = ""
var _active_closure_uri: String = ""
var _active_closure_json: Dictionary = {}

var _flowdoc_rows: Array = []
var _flowdoc_cols: Array = []
var _active_flowdoc_id: String = ""
var _active_flowdoc_uri: String = ""

var _flowdoc_model: Dictionary = {}
var _active_block_idx: int = -1
var _active_frame_idx: int = 0
var _updating_ui: bool = false
var _present_cluster_ids: Array[String] = []
var _present_cluster_idx: int = -1
var _present_selected_node_id: String = ""
var _present_selected_ref: Dictionary = {}
var _present_deck_step_idx: int = -1
var _design_selected_node_id: String = ""

var _artifacts_visible: bool = true
var _artifacts_last_split_offset: int = 280

var _edgeless_resizing: bool = false
var _edgeless_resize_start_y: float = 0.0
var _edgeless_resize_start_h: float = 0.0

var _flowdoc_json_resizing: bool = false
var _flowdoc_json_resize_start_y: float = 0.0
var _flowdoc_json_resize_start_h: float = 0.0
var _startup_refresh_attempts: int = 0
func _ready() -> void:
	StartupUtilsScript.ready(self)
	_init_proxistant_atlas_tab()
	_init_present_tab_tooltips()
	_apply_canvas_dark_mode_from_theme_manager()
	var theme_mgr: Node = SynesynAutoloadAccessScript.theme_manager()
	if theme_mgr != null and theme_mgr.has_signal("mode_changed"):
		if not theme_mgr.is_connected("mode_changed", Callable(self, "_on_global_theme_mode_changed")):
			theme_mgr.connect("mode_changed", Callable(self, "_on_global_theme_mode_changed"))
func _on_global_theme_mode_changed(_new_mode: String) -> void:
	_apply_canvas_dark_mode_from_theme_manager()
func _apply_canvas_dark_mode_from_theme_manager() -> void:
	var is_dark := true
	var theme_mgr: Node = SynesynAutoloadAccessScript.theme_manager()
	if theme_mgr != null and theme_mgr.has_method("is_dark"):
		is_dark = bool(theme_mgr.call("is_dark"))
	_propagate_dark_mode_to_canvas(is_dark)
	var logo_node: TextureRect = get_node_or_null("%SynpunktLogo_TextureRect") as TextureRect
	if logo_node:
		logo_node.texture = _SYNPUNKT_LOGO_WHITE if is_dark else _SYNPUNKT_LOGO_DARK
## [EXPERIMENTAL — PENDING DEPRECATION]
## Adds the proxistant-atlas as a tab. This panel has no confirmed workflow use
## case and is retained only for temporary experimentation with stfx_core.
## Remove this call (and SynpunktProxistantAtlas) once the experiment concludes.
## See proxistant_atlas.gd for the full design rationale and removal criteria.
func _init_proxistant_atlas_tab() -> void:
	if _root == null:
		return
	var mode_tabs := _root.get_node_or_null("Body/Right/ModeTabs") as TabContainer
	if mode_tabs == null:
		return
	if mode_tabs.has_node("Atlas [exp]"):
		return
	var atlas := SynpunktProxistantAtlas.new()
	atlas.name = "Atlas [exp]"
	var hub: HubSubstrateClient = get("_hub") as HubSubstrateClient
	if hub != null:
		atlas.set_hub(hub)
	mode_tabs.add_child(atlas)
func _perform_store_record_on_atlas(record: Dictionary, record_kind: String) -> void:
	if _root == null:
		return
	var mode_tabs := _root.get_node_or_null("Body/Right/ModeTabs") as TabContainer
	if mode_tabs == null:
		return
	var atlas_node := mode_tabs.get_node_or_null("Atlas [exp]")
	if atlas_node == null or not atlas_node.has_method("apply_store_record"):
		return
	mode_tabs.current_tab = mode_tabs.get_tab_idx_from_control(atlas_node as Control)
	await atlas_node.call("apply_store_record", record, record_kind)
func _init_present_tab_tooltips() -> void:
	if not _present_view_tabs:
		return
	_present_view_tabs.set_tab_tooltip(0, "Outline — sequential slide-by-slide view of the loaded SynDoc's frames.")
	_present_view_tabs.set_tab_tooltip(1, "Edgeless — spatial map view: frames as cards, clusters as colour-coded regions.\nUse 'Build Edgeless Layout' in the Design tab first to populate this view.")
func _propagate_dark_mode_to_canvas(is_dark: bool) -> void:
	if _edgeless_preview:
		_edgeless_preview.set_dark_mode(is_dark)
	if _present_edgeless_preview:
		_present_edgeless_preview.set_dark_mode(is_dark)
func _init_render_settings_ui() -> void:
	RenderSettingsUtilsScript.init_render_settings_ui(self)
func _load_comfy_url_settings(cfg: Dictionary) -> void:
	RenderSettingsUtilsScript.load_comfy_url_settings(self, cfg)
func _save_comfy_url_settings() -> bool:
	return RenderSettingsUtilsScript.save_comfy_url_settings(self)
func _refresh_comfy_url_history_picker() -> void:
	RenderSettingsUtilsScript.refresh_comfy_url_history_picker(self)
func _on_comfy_url_history_selected(idx: int) -> void:
	RenderSettingsUtilsScript.on_comfy_url_history_selected(self, idx)
func _remember_comfy_url(url: String) -> void:
	RenderSettingsUtilsScript.remember_comfy_url(self, url)
func _on_auto_save_workflows_toggled(enabled: bool) -> void:
	RenderSettingsUtilsScript.on_auto_save_workflows_toggled(self, enabled)
func _on_render_route_mode_selected(idx: int) -> void:
	RenderSettingsUtilsScript.on_render_route_mode_selected(self, idx)
func _current_render_route_mode() -> String:
	return str(_render_route_mode).strip_edges().to_lower()
func _load_render_artifact_naming_settings(cfg: Dictionary) -> void:
	RenderSettingsUtilsScript.load_render_artifact_naming_settings(self, cfg)
func _save_render_artifact_naming_settings() -> bool:
	return RenderSettingsUtilsScript.save_render_artifact_naming_settings(self)
func _next_default_render_artifact_name() -> String:
	return RenderSettingsUtilsScript.next_default_render_artifact_name(self)
func _artifact_display_name_from_metadata_json(metadata_text: String) -> String:
	return RenderSettingsUtilsScript.artifact_display_name_from_metadata_json(metadata_text)
func _metadata_dict_from_text(metadata_text: String) -> Dictionary:
	return RenderSettingsUtilsScript.metadata_dict_from_text(metadata_text)
func _artifact_ext_from_uri(uri: String) -> String:
	return RenderSettingsUtilsScript.artifact_ext_from_uri(self, uri)
func _artifact_size_from_uri(uri: String) -> int:
	return RenderSettingsUtilsScript.artifact_size_from_uri(self, uri)
func _artifact_size_human(bytes_count: int) -> String:
	return RenderSettingsUtilsScript.artifact_size_human(bytes_count)
func _artifact_display_name_for_id(_artifact_id: String, metadata_text: String = "") -> String:
	return RenderSettingsUtilsScript.artifact_display_name_for_id(_artifact_id, metadata_text)
func _artifact_item_label(artifact_id: String, created_at: String = "", metadata_text: String = "") -> String:
	return RenderSettingsUtilsScript.artifact_item_label(artifact_id, created_at, metadata_text)
func _save_render_artifact_default_name_from_ui() -> void:
	RenderSettingsUtilsScript.save_render_artifact_default_name_from_ui(self)
func _rename_selected_render_artifact() -> void:
	await RenderResultsBrowserUtilsScript.rename_selected_render_artifact(self)
func _reset_selected_render_artifact_name() -> void:
	await RenderResultsBrowserUtilsScript.reset_selected_render_artifact_name(self)
func _refresh_render_results_labels() -> void:
	RenderResultsBrowserUtilsScript.refresh_render_results_labels(self)
func _on_render_results_item_selected(_idx: int) -> void:
	RenderResultsBrowserUtilsScript.on_render_results_item_selected(self, _idx)
func _on_render_results_item_clicked(idx: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	RenderResultsBrowserUtilsScript.on_render_results_item_clicked(self, idx)
func _on_render_results_multi_selected(idx: int, selected: bool) -> void:
	RenderResultsBrowserUtilsScript.on_render_results_multi_selected(self, idx, selected)
func _on_render_results_filter_changed(_t: String) -> void:
	_apply_render_results_view()
func _on_render_results_sort_changed(_idx: int) -> void:
	_apply_render_results_view()
func _on_sensor_overlay_toggled(v: bool) -> void:
	# Kept as a tiny helper in case anything still calls it directly.
	# The actual UI wiring uses an inline lambda in `_init_ui_connections_all()`.
			_sensor_enabled = v
			if v:
				_hub.ensure_ws_connected()
				_hub.ws_subscribe(["sensor.", "sensor.warning"])
				_hub.ws_replay(5.0, ["sensor.", "sensor.warning"])
				_set_status("Sensor overlay enabled.")
			else:
				_set_status("Sensor overlay disabled.")
func _on_save_workflow_preset_pressed() -> void:
	await _on_save_workflow_preset()
func _init_ui_connections_all() -> void:
	UiConnectionsUtilsScript.init_ui_connections_all(self)
func _init_edgeless_view_style() -> void:
	if not _edgeless_view_style:
		return
	# Populate only once.
	if _edgeless_view_style.item_count <= 0:
		_edgeless_view_style.add_item("Cards", 0)
		_edgeless_view_style.add_item("Dots", 1)
	# Default selection: cards.
	_edgeless_view_style.select(0)
	_apply_edgeless_view_style()
	# Avoid double-connecting if this method is called twice during startup.
	if not _edgeless_view_style.item_selected.is_connected(_on_edgeless_view_style_selected):
		_edgeless_view_style.item_selected.connect(_on_edgeless_view_style_selected)
func _on_edgeless_view_style_selected(_idx: int) -> void:
	_apply_edgeless_view_style()
func _apply_edgeless_view_style() -> void:
	if not _edgeless_view_style:
		return
	var style_id := int(_edgeless_view_style.get_selected_id())
	# Map to EdgelessPreview.RenderStyle {CARDS=0, DOTS=1}
	if _edgeless_preview:
		_edgeless_preview.set_render_style(style_id)
	if _present_edgeless_preview:
		_present_edgeless_preview.set_render_style(style_id)
	# UX: overlap resolution applies to cards; make this explicit to avoid confusion.
	if _edgeless_avoid_overlap:
		_edgeless_avoid_overlap.disabled = (style_id != 0)
func _on_closures_tree_item_edited() -> void:
	_sync_checked_from_edited_tree_item(_closures_list, _checked_closure_ids)
func _on_syndocs_tree_item_edited() -> void:
	_sync_checked_from_edited_tree_item(_flowdocs_list, _checked_syndoc_ids)
func _sync_checked_from_edited_tree_item(tree_node: Tree, checked_set: Dictionary) -> void:
	if not tree_node:
		return
	var item: TreeItem = tree_node.get_edited()
	if item == null:
		return
	var col := int(tree_node.get_edited_column())
	if col != 0:
		return
	# Store artifact id on the label column (1) so column 0 stays purely a checkbox.
	var meta_any: Variant = item.get_metadata(1)
	var artifact_id := str(meta_any).strip_edges()
	if artifact_id.is_empty():
		return
	if item.is_checked(0):
		checked_set[artifact_id] = true
	else:
		checked_set.erase(artifact_id)
func _on_delete_selected_closure_pressed() -> void:
	_request_delete_selected("closure")
func _on_delete_selected_syndoc_pressed() -> void:
	_request_delete_selected("syndoc")
func _request_delete_selected(kind: String) -> void:
	ArtifactDeleteUtilsScript.request_delete_selected(self, kind)
func _on_delete_confirmed() -> void:
	await _delete_pending_artifact_async()
func _delete_pending_artifact_async() -> void:
	await ArtifactDeleteUtilsScript.delete_pending_artifact_async(self)
func _tree_collect_checked_ids(tree_node: Tree) -> Array[String]:
	var out: Array[String] = []
	if not tree_node:
		return out
	var root := tree_node.get_root()
	if root == null:
		return out
	var item := root.get_first_child()
	while item != null:
		if item.get_cell_mode(0) == TreeItem.CELL_MODE_CHECK and item.is_checked(0):
			var aid := str(item.get_metadata(1)).strip_edges()
			if not aid.is_empty():
				out.append(aid)
		item = item.get_next()
	return out
func _post_ready_refresh() -> void:
	await ArtifactDeleteUtilsScript.post_ready_refresh(self)
func _await_hub_ready_for_startup_refresh(timeout_sec: float = 10.0) -> bool:
	return await ArtifactDeleteUtilsScript.await_hub_ready_for_startup_refresh(self, timeout_sec)
func _on_refresh_closures_pressed() -> void:
	await _refresh_closures()
func _on_refresh_store_closures_pressed() -> void:
	await _refresh_store_closures()
func _on_refresh_store_context_packs_pressed() -> void:
	await _refresh_store_context_packs()
func _on_load_selected_closure_pressed() -> void:
	await _load_selected_closure()
func _on_create_demo_closure_pressed() -> void:
	await _on_create_demo_closure()
func _on_refresh_flowdocs_pressed() -> void:
	await _refresh_flowdocs()
func _on_load_selected_flowdoc_pressed() -> void:
	await _load_selected_flowdoc()
func _on_save_flowdoc_pressed() -> void:
	await _save_flowdoc()
func _on_save_flowdoc_version_pressed() -> void:
	await _save_flowdoc(true)
func _on_test_comfy_pressed() -> void:
	await _on_test_comfy()
func _on_submit_render_pressed() -> void:
	await _on_submit_render()
func _on_save_render_recipe_pressed() -> void:
	await _on_save_render_recipe()
func _on_snapshot_sensors_pressed() -> void:
	await _snapshot_sensors_to_hub()
func _on_build_edgeless_layout_pressed() -> void:
	await _build_edgeless_layout_from_projection(false)
func _on_rebuild_edgeless_keep_edits_pressed() -> void:
	await _build_edgeless_layout_from_projection(true)
func _on_edgeless_preview_gui_input(event: InputEvent) -> void:
	await EdgelessInteractionUtilsScript.on_edgeless_preview_gui_input(self, event)
func _on_edgeless_selection_changed(node_id: String, ref: Dictionary) -> void:
	EdgelessInteractionUtilsScript.on_edgeless_selection_changed(self, node_id, ref)
func _on_reset_edgeless_view() -> void:
	if not _edgeless_preview:
		return
	_edgeless_preview.reset_to_initial_view()
	_edgeless_preview.queue_redraw()
	_set_status("Edgeless: view reset.")
func _on_fit_edgeless_to_layout() -> void:
	if _edgeless_preview:
		_edgeless_preview.fit_to_layout()
	if _present_edgeless_preview:
		_present_edgeless_preview.fit_to_layout()
	_set_status("Edgeless: fit to layout.")
func _on_apply_design_edgeless_label() -> void:
	if _design_selected_node_id.is_empty() or not _edgeless_preview or not _edgeless_label_edit:
		_set_status("Select a node/cluster first.")
		return
	var label := _edgeless_label_edit.text.strip_edges()
	_edgeless_preview.set_node_label(_design_selected_node_id, label)
	# model update happens via _on_design_edgeless_label_changed
	_set_status("Edgeless: label applied.")
func _on_edgeless_resize_gui_input(event: InputEvent) -> void:
	EdgelessInteractionUtilsScript.on_edgeless_resize_gui_input(self, event)
func _on_flowdoc_json_resize_gui_input(event: InputEvent) -> void:
	EdgelessInteractionUtilsScript.on_flowdoc_json_resize_gui_input(self, event)
func _on_design_edgeless_node_moved(node_id: String, new_pos: Array) -> void:
	_update_flowdoc_edgeless_node_pos(node_id, new_pos)
func _on_design_edgeless_drag_ended() -> void:
	# Persist current model into raw JSON without re-parsing (keeps the editing experience smooth).
	_write_model_to_raw_json()
func _on_design_edgeless_label_changed(node_id: String, label: String) -> void:
	_update_flowdoc_edgeless_node_label(node_id, label)
	_write_model_to_raw_json()
func _update_flowdoc_edgeless_node_pos(node_id: String, new_pos: Array) -> void:
	EdgelessInteractionUtilsScript.update_flowdoc_edgeless_node_pos(self, node_id, new_pos)
func _update_flowdoc_edgeless_node_label(node_id: String, label: String) -> void:
	EdgelessInteractionUtilsScript.update_flowdoc_edgeless_node_label(self, node_id, label)
func _build_edgeless_layout_from_projection(keep_edits: bool) -> void:
	await EdgelessLayoutBuilderUtilsScript.build_edgeless_layout_from_projection(self, keep_edits)
func _build_edgeless_layout_from_frames(keep_edits: bool) -> void:
	await EdgelessLayoutBuilderUtilsScript.build_edgeless_layout_from_frames(self, keep_edits)
func _merge_edgeless_keep_edits(old_ed: Dictionary, new_ed: Dictionary) -> void:
	EdgelessLayoutBuilderUtilsScript.merge_edgeless_keep_edits(old_ed, new_ed)
func _on_align_selected_to_grid() -> void:
	EdgelessInteractionUtilsScript.on_align_selected_to_grid(self)
func _center_selected_axis(is_x: bool) -> void:
	EdgelessInteractionUtilsScript.center_selected_axis(self, is_x)
func _get_flowdoc_edgeless_node_pos(node_id: String) -> Array:
	return EdgelessInteractionUtilsScript.get_flowdoc_edgeless_node_pos(self, node_id)
func _refresh_edgeless_preview() -> void:
	EdgelessInteractionUtilsScript.refresh_edgeless_preview(self)
func _refresh_present_edgeless() -> void:
	PresentNavigationUtilsScript.refresh_present_edgeless(self)
func _edgeless_with_all_frames(edgeless: Dictionary, frames: Array) -> Dictionary:
	return EdgelessLayoutBuilderUtilsScript.edgeless_with_all_frames(edgeless, frames)
func _start_present_image_uri_resolve() -> void:
	# Resolve image artifact ids referenced by frame blocks (best-effort, non-blocking).
	if not _present_edgeless_preview or not _hub:
		return
	if _flowdoc_model.is_empty():
		return
	var frames := _get_frames()
	var image_artifact_ids: Array[String] = _collect_image_artifact_ids_from_frames(frames)
	_present_image_resolve_queue = image_artifact_ids
	_present_image_resolve_inflight = false
	_present_image_uri_map = {}
	_present_edgeless_preview.set_image_uri_map(_present_image_uri_map)
	_resolve_next_present_image_uri()
func _collect_image_artifact_ids_from_frames(frames: Array) -> Array[String]:
	return EdgelessInteractionUtilsScript.collect_image_artifact_ids_from_frames(frames)
func _resolve_next_present_image_uri() -> void:
	EdgelessInteractionUtilsScript.resolve_next_present_image_uri(self)
func _on_present_image_resolve_completed(_result: int, _code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
	EdgelessInteractionUtilsScript.on_present_image_resolve_completed(self, body_bytes)
func _update_present_cluster_nav() -> void:
	var has := _present_cluster_ids.size() > 0
	if _present_prev_cluster:
		_present_prev_cluster.disabled = not has
	if _present_next_cluster:
		_present_next_cluster.disabled = not has
	if _present_make_frame:
		_present_make_frame.disabled = _present_selected_node_id.is_empty()
func _select_present_cluster_delta(delta: int) -> void:
	if _present_cluster_ids.is_empty() or not _present_edgeless_preview:
		return
	if _present_cluster_idx < 0:
		_present_cluster_idx = 0
	else:
		_present_cluster_idx = wrapi(_present_cluster_idx + delta, 0, _present_cluster_ids.size())
	var node_id := _present_cluster_ids[_present_cluster_idx]
	_present_edgeless_preview.select_node(node_id)
	_present_edgeless_preview.focus_node(node_id)
func _on_present_edgeless_selection_changed(node_id: String, ref: Dictionary) -> void:
	_present_selected_node_id = node_id
	_present_selected_ref = ref
	_update_present_cluster_nav()
	if _present_edgeless_selection:
		if node_id.is_empty():
			_present_edgeless_selection.text = "Selection: (none)"
		else:
			_present_edgeless_selection.text = "Selection: %s" % node_id
	# also show in status for clarity
	_on_edgeless_selection_changed(node_id, ref)
func _on_present_make_frame_from_cluster() -> void:
	EdgelessInteractionUtilsScript.on_present_make_frame_from_cluster(self)
func _get_edgeless_layout(flowdoc: Dictionary) -> Dictionary:
	var layout_any: Variant = flowdoc.get("layout", null)
	if typeof(layout_any) != TYPE_DICTIONARY:
		return {}
	var layout: Dictionary = layout_any
	var ed_any: Variant = layout.get("edgeless", null)
	if typeof(ed_any) != TYPE_DICTIONARY:
		return {}
	return ed_any
func _find_edgeless_cluster(edgeless: Dictionary, cluster_node_id: String) -> Dictionary:
	var clusters_any: Variant = edgeless.get("clusters", [])
	if typeof(clusters_any) != TYPE_ARRAY:
		return {}
	for c_any in (clusters_any as Array):
		if typeof(c_any) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_any
		if str(c.get("id", "")).strip_edges() == cluster_node_id:
			return c
	return {}
func _build_frame_from_cluster(cluster: Dictionary, edgeless: Dictionary) -> Dictionary:
	return EdgelessInteractionUtilsScript.build_frame_from_cluster(self, cluster, edgeless)
func _edgeless_item_label_map(edgeless: Dictionary) -> Dictionary:
	return EdgelessInteractionUtilsScript.edgeless_item_label_map(edgeless)
func _make_unique_frame_id(frames: Array, desired: String) -> String:
	return EdgelessInteractionUtilsScript.make_unique_frame_id(frames, desired)
func _on_apply_hub_url() -> void:
	var url := _hub_url.text.strip_edges()
	if url.is_empty():
		_set_status("Hub URL is empty.")
		return
	_hub.base_url = url
	_set_status("Hub URL applied: %s" % url)
func _init_advanced_refs_ui() -> void:
	# Progressive disclosure: keep high-salience refs visible, hide advanced knobs by default.
	_set_advanced_refs_visible(false)
	if _toggle_advanced_refs:
		_toggle_advanced_refs.button_pressed = false
		_toggle_advanced_refs.text = "Advanced ▸"
		_toggle_advanced_refs.toggled.connect(func(is_pressed: bool) -> void:
			_set_advanced_refs_visible(is_pressed)
			_toggle_advanced_refs.text = "Advanced ▾" if is_pressed else "Advanced ▸"
		)
func _set_advanced_refs_visible(is_visible_now: bool) -> void:
	if _prompt_chain_ref_row:
		_prompt_chain_ref_row.visible = is_visible_now
	if _projection_ref_row:
		_projection_ref_row.visible = is_visible_now
	if _cluster_ref_row:
		_cluster_ref_row.visible = is_visible_now
func _load_how_to_text() -> void:
	if not _how_to_rich_text:
		return
	var path := "res://addons/synpunkt/docs/how_to.bbcode"
	var raw := ""
	if FileAccess.file_exists(path):
		raw = FileAccess.get_file_as_string(path)
	if raw.strip_edges().is_empty():
		# Fall back to whatever the scene already contains (if any); otherwise show an explicit message.
		var existing := _how_to_rich_text.text.strip_edges()
		raw = existing if not existing.is_empty() else ("[b]SynPunkt — How To[/b]\n\nHelp file not found: %s" % path)
	# Godot 4: use .text (bbcode_enabled=true) instead of .bbcode_text.
	_how_to_rich_text.bbcode_enabled = true
	_how_to_rich_text.text = raw
func _autostart_hub_if_configured() -> void:
	await StartupUtilsScript.autostart_hub_if_configured(self)
func _on_new_empty_flowdoc() -> void:
	await SyndocActionsUtilsScript.on_new_empty_flowdoc(self)
func _generate_empty_flowdoc(title: String) -> Dictionary:
	return SyndocActionsUtilsScript.generate_empty_flowdoc(title)
func _on_create_demo_closure() -> void:
	await SyndocActionsUtilsScript.on_create_demo_closure(self)
func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg
		_status.remove_theme_color_override("font_color")
func _set_status_ok(msg: String) -> void:
	if _status:
		_status.text = msg
		var ok_col: Color = get_theme_color("font_color", "LabelStatusOk")
		_status.add_theme_color_override("font_color", ok_col)
func _set_status_err(msg: String) -> void:
	if _status:
		_status.text = msg
		var err_col: Color = get_theme_color("font_color", "LabelStatusError")
		_status.add_theme_color_override("font_color", err_col)
func _set_status_warn(msg: String) -> void:
	if _status:
		_status.text = msg
		var warn_col: Color = get_theme_color("font_color", "LabelStatusWarn")
		_status.add_theme_color_override("font_color", warn_col)
# ----------------------------
# Artifacts panel (left) toggle
# ----------------------------
func _init_artifacts_toggle() -> void:
	UiHubUtilsScript.init_artifacts_toggle(self)
func _on_toggle_artifacts(pressed: bool) -> void:
	UiHubUtilsScript.on_toggle_artifacts(self, pressed)
func _set_artifacts_visible(visible: bool, announce: bool) -> void:
	UiHubUtilsScript.set_artifacts_visible(self, visible, announce)
# ----------------------------
# Settings: Host/Join (Hub-first)
# ----------------------------
func _init_host_join_ui() -> void:
	UiHubUtilsScript.init_host_join_ui(self)
func _get_local_ipv4_candidates() -> Array[String]:
	return UiHubUtilsScript.get_local_ipv4_candidates()
func _get_host_share_url() -> String:
	return UiHubUtilsScript.get_host_share_url(self)
func _on_copy_host_url() -> void:
	UiHubUtilsScript.on_copy_host_url(self)
func _apply_hub_settings_in_memory(url: String, use_auth: bool, token: String) -> void:
	UiHubUtilsScript.apply_hub_settings_in_memory(self, url, use_auth, token)
func _on_join_test() -> void:
	await UiHubUtilsScript.on_join_test(self)
func _on_join_save() -> void:
	await UiHubUtilsScript.on_join_save(self)
func _on_export_slides_deck() -> void:
	await UiHubUtilsScript.on_export_slides_deck(self)
func _on_import_slides_deck() -> void:
	await UiHubUtilsScript.on_import_slides_deck(self)
# ----------------------------
# Render recipes (v1)
# ----------------------------
func _on_save_render_recipe() -> void:
	await RenderRecipeUtilsScript.on_save_render_recipe(self)
# ----------------------------
# Present camera path (v1)
# ----------------------------
func _frame_idx_by_id(frames: Array, frame_id: String) -> int:
	return PresentCameraUtilsScript.frame_idx_by_id(frames, frame_id)
func _present_target_frame_idx(frames: Array) -> int:
	return PresentCameraUtilsScript.present_target_frame_idx(self, frames)
func _on_present_capture_camera() -> void:
	PresentCameraUtilsScript.on_present_capture_camera(self)
func _get_presentation_dict() -> Dictionary:
	return PresentCameraUtilsScript.get_presentation_dict(self)
func _get_presentation_steps() -> Array:
	return PresentCameraUtilsScript.get_presentation_steps(self)
func _set_presentation_steps(steps: Array) -> void:
	PresentCameraUtilsScript.set_presentation_steps(self, steps)
func _capture_present_deck_step() -> void:
	PresentCameraUtilsScript.capture_present_deck_step(self)
func _on_present_clear_deck() -> void:
	PresentCameraUtilsScript.on_present_clear_deck(self)
func _apply_present_deck_step(idx: int, force: bool = false, sync_frame: bool = true) -> void:
	PresentCameraUtilsScript.apply_present_deck_step(self, idx, force, sync_frame)
func _apply_present_camera_for_frame_idx(idx: int, force: bool = false) -> void:
	PresentCameraUtilsScript.apply_present_camera_for_frame_idx(self, idx, force)
func _apply_present_camera_for_active_frame(force: bool = false, prefer_selection: bool = true) -> void:
	PresentCameraUtilsScript.apply_present_camera_for_active_frame(self, force, prefer_selection)
func _frame_has_saved_camera(frames: Array, idx: int) -> bool:
	return PresentCameraUtilsScript.frame_has_saved_camera(frames, idx)
func _find_deck_step_idx_for_frame_id(frame_id: String) -> int:
	return PresentCameraUtilsScript.find_deck_step_idx_for_frame_id(self, frame_id)
func _workflow_from_textbox() -> Dictionary:
	return RenderWorkflowOpsUtilsScript.workflow_from_textbox(self)
func _workflow_hash_from_metadata_json(metadata_text: String) -> String:
	var txt := String(metadata_text).strip_edges()
	if txt.is_empty():
		return ""
	var m_any: Variant = JSON.parse_string(txt)
	if typeof(m_any) != TYPE_DICTIONARY:
		return ""
	var m: Dictionary = m_any
	var prov_any: Variant = m.get("provenance", {})
	if typeof(prov_any) != TYPE_DICTIONARY:
		return ""
	var prov: Dictionary = prov_any
	return str(prov.get("workflow_hash_sha256", "")).strip_edges()
func _find_existing_workflow_artifact_id_by_hash(workflow_hash: String) -> String:
	return await RenderWorkflowOpsUtilsScript.find_existing_workflow_artifact_id_by_hash(self, workflow_hash)
func _workflow_health_message() -> String:
	return RenderWorkflowOpsUtilsScript.workflow_health_message(self)
func _refresh_workflow_health_indicator() -> void:
	RenderWorkflowOpsUtilsScript.refresh_workflow_health_indicator(self)
func _on_workflow_json_text_changed() -> void:
	RenderWorkflowOpsUtilsScript.on_workflow_json_text_changed(self)
func _error_details_text(err: Variant) -> String:
	return RenderWorkflowOpsUtilsScript.error_details_text(err)
func _render_error_status(stage: String, err: Variant) -> String:
	return RenderWorkflowOpsUtilsScript.render_error_status(self, stage, err)
func _render_route_label(payload: Variant = null) -> String:
	return RenderWorkflowOpsUtilsScript.render_route_label(self, payload)
func _workflow_node_by_id(workflow: Dictionary, node_id: String) -> Dictionary:
	return RenderCommonParamsUtilsScript.workflow_node_by_id(workflow, node_id)
func _link_node_id(link_any: Variant) -> String:
	return RenderCommonParamsUtilsScript.link_node_id(link_any)
func _resolve_text_target(workflow: Dictionary, node_id: String) -> Dictionary:
	return RenderCommonParamsUtilsScript.resolve_text_target(workflow, node_id)
func _detect_common_param_targets(workflow: Dictionary) -> Dictionary:
	return RenderCommonParamsUtilsScript.detect_common_param_targets(workflow)
func _sync_common_params_from_workflow_json(show_status: bool = false) -> void:
	RenderCommonParamsUtilsScript.sync_common_params_from_workflow_json(self, show_status)
func _upsert_patch(patches: Array, node_id: String, input_key: String, value: Variant) -> void:
	RenderCommonParamsUtilsScript.upsert_patch(patches, node_id, input_key, value)
func _on_common_detect_from_workflow_pressed() -> void:
	_sync_common_params_from_workflow_json(true)
func _on_common_apply_to_patch_pressed() -> void:
	RenderCommonParamsUtilsScript.on_common_apply_to_patch_pressed(self)
func _on_load_default_workflow_pressed() -> void:
	if not _workflow_json:
		_set_status("Render: no Workflow JSON field.")
		return
	var wf_any: Variant = JSON.parse_string(WorkflowUtilsScript.default_workflow_json())
	if typeof(wf_any) != TYPE_DICTIONARY:
		_set_status("Render: default workflow JSON is invalid.")
		return
	_workflow_json.text = JSON.stringify(wf_any, "\t")
	_sync_common_params_from_workflow_json(false)
	_refresh_workflow_health_indicator()
	_set_status("Render: loaded default workflow.")
func _on_clear_workflow_inputs_pressed() -> void:
	RenderWorkflowOpsUtilsScript.on_clear_workflow_inputs_pressed(self)
func _on_test_comfy() -> void:
	await RenderWorkflowOpsUtilsScript.on_test_comfy(self)
func _on_load_workflow_from_flowdoc() -> void:
	RenderWorkflowOpsUtilsScript.on_load_workflow_from_flowdoc(self)
func _on_submit_render() -> void:
	await RenderSubmitUtilsScript.on_submit_render(self)
func _select_workflow_in_selector(artifact_id: String) -> void:
	RenderWorkflowSelectorUtilsScript.select_workflow_in_selector(self, artifact_id)
func _select_render_result_by_artifact_id(artifact_id: String) -> void:
	RenderResultsBrowserUtilsScript.select_render_result_by_artifact_id(self, artifact_id)
func _on_save_workflow_preset() -> void:
	await RenderWorkflowSelectorUtilsScript.on_save_workflow_preset(self)
func _on_save_preset_version_pressed() -> void:
	await RenderWorkflowSelectorUtilsScript.on_save_preset_version(self)
func _on_diff_selected_preset_pressed() -> void:
	await RenderWorkflowSelectorUtilsScript.on_diff_selected_preset(self)
func _on_archive_selected_preset_pressed() -> void:
	await RenderWorkflowSelectorUtilsScript.on_archive_selected_preset(self)
func _on_prune_archived_preset_pressed() -> void:
	await RenderWorkflowSelectorUtilsScript.on_prune_archived_preset(self)
func _init_workflow_selector() -> void:
	RenderWorkflowSelectorUtilsScript.init_workflow_selector(self)
func _kick_refresh_render_workflow_selector() -> void:
	await RenderWorkflowSelectorUtilsScript.kick_refresh_render_workflow_selector(self)
func _kick_refresh_render_results() -> void:
	if Engine.is_editor_hint():
		return
	for attempt in range(4):
		if await _await_hub_ready_for_startup_refresh(8.0):
			await _refresh_render_results_from_hub(200, "startup")
			return
		if attempt < 3:
			await get_tree().create_timer(2.0).timeout
	_set_status("Render results: Hub not ready yet. Click Refresh list when Hub is up.")
func _on_mode_tabs_tab_changed(tab: int) -> void:
	if tab != 1:
		return
	_ensure_render_results_bound()
	var rr: ItemList = _render_results
	if not rr:
		return
	if rr.item_count <= 1:
		_refresh_render_results_from_hub(200, "tab")
func _refresh_render_workflow_selector() -> void:
	await RenderWorkflowSelectorUtilsScript.refresh_render_workflow_selector(self)
func _refresh_render_request_selector() -> void:
	await RenderWorkflowSelectorUtilsScript.refresh_render_request_selector(self)
func _on_render_workflow_selected(idx: int) -> void:
	await RenderWorkflowSelectorUtilsScript.on_render_workflow_selected(self, idx)
func _delete_selected_render_request_artifact() -> void:
	await RenderWorkflowSelectorUtilsScript.delete_selected_render_request_artifact(self)
func _parse_artifact_id_from_render_results_item(txt: String) -> String:
	return RenderResultsBrowserUtilsScript.parse_artifact_id_from_render_results_item(txt)
func _on_render_result_activated(idx: int) -> void:
	await RenderResultsBrowserUtilsScript.on_render_result_activated(self, idx)
func _ensure_render_results_bound() -> void:
	RenderResultsBrowserUtilsScript.ensure_render_results_bound(self)
func _get_selected_render_artifact_id() -> String:
	return RenderResultsBrowserUtilsScript.get_selected_render_artifact_id(self)
func _get_selected_render_artifact_ids() -> Array[String]:
	return RenderResultsBrowserUtilsScript.get_selected_render_artifact_ids(self)
func _artifact_uri_from_id(artifact_id: String) -> String:
	return await RenderResultsBrowserUtilsScript.artifact_uri_from_id(self, artifact_id)
func _path_from_file_uri(uri: String) -> String:
	return RenderResultsBrowserUtilsScript.path_from_file_uri(uri)
func _copy_selected_render_artifact_id() -> void:
	RenderResultsBrowserUtilsScript.copy_selected_render_artifact_id(self)
func _open_selected_render_artifact_folder() -> void:
	await RenderResultsBrowserUtilsScript.open_selected_render_artifact_folder(self)
func _clear_render_results_list() -> void:
	RenderResultsBrowserUtilsScript.clear_render_results_list(self)
func _refresh_render_results_from_hub(limit: int = 200, source: String = "auto") -> void:
	await RenderResultsDetailsUtilsScript.refresh_render_results_from_hub(self, limit, source)
func _set_render_results_refresh_meta(source: String, count: int, ok: bool, err: String = "") -> void:
	_render_results_last_refresh_source = source
	_render_results_last_refresh_unix = int(Time.get_unix_time_from_system())
	_render_results_last_refresh_count = maxi(0, count)
	_render_results_last_refresh_ok = ok
	_render_results_last_refresh_error = err
	_update_render_results_refresh_hint()
func _update_render_results_refresh_hint() -> void:
	if not _render_results_label:
		return
	var base := "Render results (hub artifacts):"
	if _render_results_last_refresh_unix <= 0:
		_render_results_label.text = base
		return
	var t := Time.get_datetime_dict_from_unix_time(_render_results_last_refresh_unix)
	var hh := str(int(t.get("hour", 0))).pad_zeros(2)
	var mm := str(int(t.get("minute", 0))).pad_zeros(2)
	var ss := str(int(t.get("second", 0))).pad_zeros(2)
	var stamp := "%s:%s:%s" % [hh, mm, ss]
	var src := _render_results_last_refresh_source if not _render_results_last_refresh_source.is_empty() else "auto"
	if _render_results_last_refresh_ok:
		_render_results_label.text = "%s  loaded=%d  last=%s @ %s" % [base, _render_results_last_refresh_count, src, stamp]
	else:
		var err := _render_results_last_refresh_error.strip_edges()
		if err.length() > 56:
			err = err.substr(0, 56) + "…"
		_render_results_label.text = "%s  last=%s @ %s (failed: %s)" % [base, src, stamp, err if not err.is_empty() else "unknown"]
func _parse_created_at_float(created_at: String) -> float:
	return RenderResultsDetailsUtilsScript.parse_created_at_float(created_at)
func _sort_render_results_rows(rows: Array) -> Array:
	return RenderResultsDetailsUtilsScript.sort_render_results_rows(self, rows)
func _row_matches_render_filter(row: Dictionary) -> bool:
	return RenderResultsDetailsUtilsScript.row_matches_render_filter(self, row)
func _apply_render_results_view() -> void:
	RenderResultsDetailsUtilsScript.apply_render_results_view(self)
func _update_render_artifact_details() -> void:
	RenderResultsLinksUtilsScript.update_render_artifact_details(self)
func _current_render_artifact_context() -> Dictionary:
	return RenderResultsLinksUtilsScript.current_render_artifact_context(self)
func _render_link_health_label(link_id: String, key: String, health: Dictionary) -> String:
	return RenderResultsLinksUtilsScript.render_link_health_label(link_id, key, health)
func _set_render_artifact_details_from_context(ctx: Dictionary, health: Dictionary = {}) -> void:
	RenderResultsLinksUtilsScript.set_render_artifact_details_from_context(self, ctx, health)
func _artifact_id_exists(artifact_id: String) -> bool:
	return await RenderResultsLinksUtilsScript.artifact_id_exists(self, artifact_id)
func _kick_render_artifact_link_health_check(ctx: Dictionary, seq: int) -> void:
	RenderResultsLinksUtilsScript.kick_render_artifact_link_health_check(self, ctx, seq)
func _render_artifact_link_health_check_async(ctx: Dictionary, seq: int) -> void:
	await RenderResultsLinksUtilsScript.render_artifact_link_health_check_async(self, ctx, seq)
func _load_workflow_from_render_request_artifact(rr_id: String) -> void:
	await RenderResultsLinksUtilsScript.load_workflow_from_render_request_artifact(self, rr_id)
func _on_render_details_load_linked_workflow() -> void:
	await RenderResultsLinksUtilsScript.on_render_details_load_linked_workflow(self)
func _on_render_details_load_linked_render_request() -> void:
	await RenderResultsLinksUtilsScript.on_render_details_load_linked_render_request(self)
func _on_render_details_copy_all_links() -> void:
	RenderActionsUtilsScript.on_render_details_copy_all_links(self)
func _delete_selected_render_image_artifacts() -> void:
	await RenderActionsUtilsScript.delete_selected_render_image_artifacts(self)
func _insert_selected_render_artifacts_into_current_frame() -> void:
	RenderActionsUtilsScript.insert_selected_render_artifacts_into_current_frame(self)
func _on_hub_event_received(evt: Dictionary) -> void:
	RenderActionsUtilsScript.on_hub_event_received(self, evt)
	RenderJobsUtilsScript.maybe_refresh_jobs_from_event(self, evt)
func _update_sensor_overlay_nodes() -> void:
	RenderActionsUtilsScript.update_sensor_overlay_nodes(self)
func _snapshot_sensors_to_hub() -> void:
	await RenderActionsUtilsScript.snapshot_sensors_to_hub(self)
func _refresh_closures() -> void:
	_closure_browser_mode = "substrate_closure"
	await ArtifactBrowserUtilsScript.refresh_closures(self, ARTIFACT_CLOSURE)
func _refresh_store_closures() -> void:
	await ArtifactBrowserUtilsScript.refresh_store_closures(self)
func _refresh_store_context_packs() -> void:
	await ArtifactBrowserUtilsScript.refresh_store_context_packs(self)
func _init_render_jobs_ui() -> void:
	RenderJobsUtilsScript.init_render_jobs_ui(self)
func _refresh_render_jobs(limit: int = 100, source: String = "manual") -> void:
	await RenderJobsUtilsScript.refresh_render_jobs(self, limit, source)
func _on_render_jobs_item_selected(idx: int) -> void:
	RenderJobsUtilsScript.on_render_jobs_item_selected(self, idx)
func _cancel_selected_render_job() -> void:
	await RenderJobsUtilsScript.cancel_selected_render_job(self)
func _retry_selected_render_job() -> void:
	await RenderJobsUtilsScript.retry_selected_render_job(self, "retry")
func _resume_selected_render_job() -> void:
	await RenderJobsUtilsScript.retry_selected_render_job(self, "resume")
func _refresh_flowdocs() -> void:
	await ArtifactBrowserUtilsScript.refresh_flowdocs(self, ARTIFACT_SYNDOC)
func _load_selected_closure() -> void:
	await ArtifactBrowserUtilsScript.load_selected_closure(self)
func _load_selected_flowdoc() -> void:
	ArtifactBrowserUtilsScript.load_selected_flowdoc(self)
func _focus_design_syndoc_tab() -> void:
	ArtifactBrowserUtilsScript.focus_design_syndoc_tab(self)
func _on_generate_flowdoc() -> void:
	SyndocActionsUtilsScript.on_generate_flowdoc(self)
func _save_flowdoc(as_new_version: bool = false) -> void:
	await SyndocActionsUtilsScript.save_flowdoc(self, as_new_version)
func _tree_select_by_id(tree_node: Tree, artifact_id: String) -> void:
	SyndocActionsUtilsScript.tree_select_by_id(tree_node, artifact_id)
func _on_validate_flowdoc() -> void:
	SyndocActionsUtilsScript.on_validate_flowdoc(self)
func _generate_flowdoc_from_closure(closure_id: String, closure: Dictionary, title: String) -> Dictionary:
	return SyndocActionsUtilsScript.generate_flowdoc_from_closure(self, closure_id, closure, title)
func _sync_from_raw_json() -> void:
	SyndocRefsUtilsScript.sync_from_raw_json(self)
func _refresh_refs_ui_from_flowdoc(flowdoc: Dictionary) -> void:
	SyndocRefsUtilsScript.refresh_refs_ui_from_flowdoc(self, flowdoc)
func _apply_refs_fields_to_flowdoc(flowdoc: Dictionary) -> void:
	SyndocRefsUtilsScript.apply_refs_fields_to_flowdoc(self, flowdoc)
func _read_flowdoc_refs(flowdoc: Dictionary) -> Dictionary:
	return SyndocRefsUtilsScript.read_flowdoc_refs(flowdoc)
func _get_closure_context_graph_artifact_id(closure: Dictionary) -> String:
	return SyndocRefsUtilsScript.get_closure_context_graph_artifact_id(closure)
func _get_closure_prompt_chain_asset_id(closure: Dictionary) -> String:
	return SyndocRefsUtilsScript.get_closure_prompt_chain_asset_id(closure)
func _get_closure_projection_artifact_id(closure: Dictionary) -> String:
	return SyndocRefsUtilsScript.get_closure_projection_artifact_id(closure)
func _get_closure_cluster_artifact_id(closure: Dictionary) -> String:
	return SyndocRefsUtilsScript.get_closure_cluster_artifact_id(closure)
func _refresh_frames_ui() -> void:
	FrameBlockEditorUtilsScript.refresh_frames_ui(self)
func _refresh_blocks_ui() -> void:
	FrameBlockEditorUtilsScript.refresh_blocks_ui(self)
func _block_type_display_name(code: String) -> String:
	return FrameBlockEditorUtilsScript.block_type_display_name(code)
func _refresh_send_targets() -> void:
	FrameBlockEditorUtilsScript.refresh_send_targets(self)
func _on_block_selected(idx: int) -> void:
	FrameBlockEditorUtilsScript.on_block_selected(self, idx)
func _select_block_type(t: String) -> void:
	FrameBlockEditorUtilsScript.select_block_type(self, t)
func _selected_block_type_code() -> String:
	return FrameBlockEditorUtilsScript.selected_block_type_code(self)
func _on_block_edited() -> void:
	FrameBlockEditorUtilsScript.on_block_edited(self)
func _insert_block_after() -> void:
	FrameBlockEditorUtilsScript.insert_block_after(self)
func _update_block_list_item(idx: int) -> void:
	FrameBlockEditorUtilsScript.update_block_list_item(self, idx)
func _delete_selected_block() -> void:
	FrameBlockEditorUtilsScript.delete_selected_block(self)
func _move_block(delta: int) -> void:
	FrameBlockEditorUtilsScript.move_block(self, delta)
func _write_model_to_raw_json() -> void:
	FrameBlockEditorUtilsScript.write_model_to_raw_json(self)
func _get_blocks() -> Array:
	return FrameBlockEditorUtilsScript.get_blocks(self)
func _set_blocks(blocks: Array) -> void:
	FrameBlockEditorUtilsScript.set_blocks(self, blocks)
func _get_frames() -> Array:
	return FrameBlockEditorUtilsScript.get_frames(self)
func _get_active_frame() -> Dictionary:
	return FrameBlockEditorUtilsScript.get_active_frame(self)
func _get_active_frame_id() -> String:
	return FrameBlockEditorUtilsScript.get_active_frame_id(self)
func _on_frame_selected(idx: int) -> void:
	FrameBlockEditorUtilsScript.on_frame_selected(self, idx)
func _jump_to_frame_id(frame_id: String) -> void:
	FrameBlockEditorUtilsScript.jump_to_frame_id(self, frame_id)
func _add_new_frame() -> void:
	FrameBlockEditorUtilsScript.add_new_frame(self)
func _delete_selected_frame() -> void:
	FrameBlockEditorUtilsScript.delete_selected_frame(self)
func _rename_selected_frame() -> void:
	SyndocFrameSyncUtilsScript.rename_selected_frame(self)
func _remap_edgeless_frame_node_id(old_frame_id: String, new_frame_id: String) -> void:
	SyndocFrameSyncUtilsScript.remap_edgeless_frame_node_id(self, old_frame_id, new_frame_id)
func _reconcile_edgeless_frame_nodes_with_frames() -> void:
	SyndocFrameSyncUtilsScript.reconcile_edgeless_frame_nodes_with_frames(self)
func _frame_id_for_index(i: int) -> String:
	return FrameBlockEditorUtilsScript.frame_id_for_index(self, i)
func _select_frame_delta(delta: int) -> void:
	PresentNavigationUtilsScript.select_frame_delta(self, delta)
func _on_present_prev_next(delta: int) -> void:
	PresentNavigationUtilsScript.on_present_prev_next(self, delta)
func _select_present_edgeless_delta(delta: int) -> void:
	PresentNavigationUtilsScript.select_present_edgeless_delta(self, delta)
func _select_present_step_delta(delta: int) -> void:
	PresentNavigationUtilsScript.select_present_step_delta(self, delta)
func _sync_present_edgeless_to_active_frame() -> void:
	PresentNavigationUtilsScript.sync_present_edgeless_to_active_frame(self)
func _move_frame(delta: int) -> void:
	FrameBlockEditorUtilsScript.move_frame(self, delta)
func _move_selected_block_to_target_frame() -> void:
	FrameBlockEditorUtilsScript.move_selected_block_to_target_frame(self)
func _refresh_performer_ui() -> void:
	PresentNavigationUtilsScript.refresh_performer_ui(self)
func _validate_flowdoc(flowdoc: Dictionary) -> Dictionary:
	return SyndocFrameSyncUtilsScript.validate_flowdoc(flowdoc)
func _row_get(columns: Array, row: Array, key: String) -> String:
	return SyndocFrameSyncUtilsScript.row_get(columns, row, key)
func _find_row_by_id(columns: Array, rows: Array, artifact_id: String) -> Array:
	return SyndocFrameSyncUtilsScript.find_row_by_id(columns, rows, artifact_id)
func _load_json_from_uri(uri: String) -> Variant:
	return SyndocFrameSyncUtilsScript.load_json_from_uri(uri)
