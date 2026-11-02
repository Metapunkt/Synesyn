extends Control
## SynAxes runtime controller — thin UI coordinator.
##
## Heavy logic lives in:
##   synaxes_hub_pipeline.gd         – hub job orchestration + artifact persistence
##   synaxes_closure_controller.gd   – dream inbox + closure commitment
##   synaxes_import_controller.gd    – data import + source picker
##   synaxes_analysis_controller.gd  – discovery / analysis orchestration
##   synaxes_ui_binder.gd            – shared main-scene UI node resolution

## Host shell (e.g. Synesyn Tools) wires this; addon does not reach into host tree.
## Known targets: "synpunkt_closures"
signal navigate_requested(target: String)

const _SYNAXES_LOGO_DARK := preload("res://addons/synaxes/icons/synaxes_logo_mini.svg")
const _SYNAXES_LOGO_WHITE := preload("res://addons/synaxes/icons/synaxes_logo_mini_white.svg")
const HubSubstrateClient = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
const SynesynAutoloadAccessScript = preload("res://addons/synesyn_core/scripts/synesyn_autoload_access.gd")
const HubPipelineScript = preload("res://addons/synaxes/scripts/runtime/synaxes_hub_pipeline.gd")
const ClosureControllerScript = preload("res://addons/synaxes/scripts/runtime/synaxes_closure_controller.gd")
const ImportControllerScript = preload("res://addons/synaxes/scripts/runtime/synaxes_import_controller.gd")
const AnalysisControllerScript = preload("res://addons/synaxes/scripts/runtime/synaxes_analysis_controller.gd")
const UiBinderScript = preload("res://addons/synaxes/scripts/runtime/synaxes_ui_binder.gd")

func _update_synaxes_logo(_mode: String = "") -> void:
	var is_dark_mode := true
	var theme_mgr: Node = SynesynAutoloadAccessScript.theme_manager()
	if theme_mgr != null and theme_mgr.has_method("is_dark"):
		is_dark_mode = bool(theme_mgr.call("is_dark"))
	var logo_node: TextureRect = find_child("TextureRect", true, false) as TextureRect
	if logo_node:
		logo_node.texture = _SYNAXES_LOGO_WHITE if is_dark_mode else _SYNAXES_LOGO_DARK

const SOURCE_LABEL_HUB_CONTEXT := "Hub: Context Graphs"
const SOURCE_LABEL_HUB_EMBEDDINGS := "Hub: Saved Embeddings"
const SOURCE_LABEL_SCENSYN_SESSIONS := "ScenSyn: Session Data"

var source_list: ItemList
var import_button: Button
var discover_button: Button
var clear_button: Button
var clusters_slider: HSlider
var clusters_value: Label
var discovery_method: OptionButton
var dim_method: OptionButton
var pattern_viewer: Node
var debug_info: Label
var persistent_status_label: Label
# Closure editor detail labels (moved from old Details tab)
var editor_position_label: Label
var editor_related_label: Label
var editor_provenance_label: Label
# Pattern Overview tab
var pattern_overview_list: ItemList
var overview_summary_label: Label
var use_hub_jobs_checkbox: CheckBox
var _use_hub_jobs: bool = false
var use_hub_embeddings_checkbox: CheckBox
var _use_hub_embeddings: bool = false
var embedding_tier_label: Label
var cache_stats_label: Label
var imported_data_list: ItemList
var imported_data_summary: Label
var bottom_tabs: TabContainer
var step_spine_label: Label
var advanced_toggle: CheckButton
var advanced_panel: Control
var import_latest_button: Button
var themes_status_label: Label
var use_model_themes_button: Button
var model_themes_consent_dialog: ConfirmationDialog

# RuntimeConfig keys (stored under apps.synaxes.*)
const _CFG_APP_ID := "synaxes"
const _CFG_USE_MODEL_EMBEDDINGS_TIER3 := "use_model_embeddings_tier3"
const _CFG_ADVANCED_OPEN := "advanced_open"
const _SELL_LINE := "Walk your material as a space and leave with a few closures you can stand behind."
const _EMPTY_CTA := "Import a demo source or a Hub context graph to begin."
const _SPINE_STEPS: Array[String] = ["Import", "Explore", "Choose", "Name", "Commit"]
## idle | imported | discovered | editing | committed
var _spine_state: String = "idle"
## When Advanced checkbox is toggled on without consent, confirm via dialog first.
var _pending_model_themes_from_checkbox: bool = false

# Panel toggle buttons (live in the toolbar row, always visible)
var _toggle_left_btn: Button
var _toggle_viewer_btn: Button
var _toggle_bottom_btn: Button
var _left_panel_node: Control
var _viewer_panel_node: Control
var _bottom_panel_node: Control

var _hub: HubSubstrateClient
var _pipeline: RefCounted  # HubPipelineScript
var _closure_ctrl: RefCounted  # ClosureControllerScript
var _import_ctrl: RefCounted  # ImportControllerScript
var _analysis_ctrl: RefCounted  # AnalysisControllerScript
var _ui_refs: Dictionary = {}

var _data: Array = []
var _current_context_graph_artifact_id: String = ""
var _seq: int = 1
## Application-layer propose-themes path (REQ-NDP-016): auto-discover after import;
## focus Closures tab after discover (overrides Overview-first for this path only).
var _auto_discover_after_import: bool = false
var _focus_closures_after_discover: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_ui_refs = UiBinderScript.resolve(self)
	source_list = _ui_refs.get("SourceList") as ItemList
	import_button = _ui_refs.get("ImportButton") as Button
	discover_button = _ui_refs.get("DiscoverButton") as Button
	clear_button = _ui_refs.get("ClearButton") as Button
	clusters_slider = _ui_refs.get("ClustersSlider") as HSlider
	clusters_value = _ui_refs.get("ClustersValue") as Label
	discovery_method = _ui_refs.get("DiscoveryMethod") as OptionButton
	dim_method = _ui_refs.get("DimReductionMethod") as OptionButton
	use_hub_jobs_checkbox = _ui_refs.get("UseHubJobs") as CheckBox
	use_hub_embeddings_checkbox = _ui_refs.get("UseHubEmbeddings") as CheckBox
	embedding_tier_label = _ui_refs.get("EmbeddingTierLabel") as Label
	cache_stats_label = _ui_refs.get("CacheStatsLabel") as Label
	pattern_viewer = _ui_refs.get("PatternViewer") as Node
	debug_info = _ui_refs.get("DebugInfo") as Label
	persistent_status_label = _ui_refs.get("PersistentStatusLabel") as Label
	step_spine_label = _ui_refs.get("StepSpineLabel") as Label
	if step_spine_label == null:
		step_spine_label = _find("StepSpineLabel") as Label
	advanced_toggle = _ui_refs.get("AdvancedToggle") as CheckButton
	if advanced_toggle == null:
		advanced_toggle = _find("AdvancedToggle") as CheckButton
	advanced_panel = _ui_refs.get("AdvancedPanel") as Control
	if advanced_panel == null:
		advanced_panel = _find("AdvancedPanel") as Control
	editor_position_label = _find("EditorPositionLabel") as Label
	editor_related_label = _find("EditorRelatedLabel") as Label
	editor_provenance_label = _find("EditorProvenanceLabel") as Label
	pattern_overview_list = _find("PatternOverviewList") as ItemList
	overview_summary_label = _find("OverviewSummary") as Label
	if pattern_overview_list:
		pattern_overview_list.item_selected.connect(_on_overview_pattern_selected)
	imported_data_list = _find("ImportedDataList") as ItemList
	imported_data_summary = _find("ImportedDataSummary") as Label
	bottom_tabs = _ui_refs.get("BottomTabs") as TabContainer
	import_latest_button = _ui_refs.get("ImportLatestContextGraphButton") as Button
	if import_latest_button == null:
		import_latest_button = _find("ImportLatestContextGraphButton") as Button
	themes_status_label = _ui_refs.get("ThemesStatusLabel") as Label
	if themes_status_label == null:
		themes_status_label = _find("ThemesStatusLabel") as Label
	use_model_themes_button = _ui_refs.get("UseModelThemesButton") as Button
	if use_model_themes_button == null:
		use_model_themes_button = _find("UseModelThemesButton") as Button
	model_themes_consent_dialog = _ui_refs.get("ModelThemesConsentDialog") as ConfirmationDialog
	if model_themes_consent_dialog == null:
		model_themes_consent_dialog = _find("ModelThemesConsentDialog") as ConfirmationDialog
	_hub = HubSubstrateClient.new()
	add_child(_hub)
	_hub.configure_from_runtime_config()
	_update_synaxes_logo()
	var theme_mgr: Node = SynesynAutoloadAccessScript.theme_manager()
	if theme_mgr != null and theme_mgr.has_signal("mode_changed"):
		if not theme_mgr.is_connected("mode_changed", Callable(self, "_update_synaxes_logo")):
			theme_mgr.connect("mode_changed", Callable(self, "_update_synaxes_logo"))
	var workspace_boot: Node = SynesynAutoloadAccessScript.workspace_bootstrapper()
	if workspace_boot != null and workspace_boot.has_signal("hub_connection_changed"):
		var hub_connection_cb := func(is_connected: bool) -> void:
			if is_connected:
				_set_status("Hub back online \u2014 Pattern analysis and embedding features restored.")
			else:
				_set_status("Hub offline \u2014 Pattern analysis and embedding paused. Check Tools \u2192 Services.")
		if not workspace_boot.is_connected("hub_connection_changed", hub_connection_cb):
			workspace_boot.connect("hub_connection_changed", hub_connection_cb)

	# Import controller (handles all sources + picker popup) — must be after _hub init
	_import_ctrl = ImportControllerScript.new()
	_import_ctrl.hub = _hub
	_import_ctrl.load_json_fn = Callable(self, "_load_json_from_uri")
	_import_ctrl.picker_popup = _find("SourcePickerPopup") as Window
	_import_ctrl.picker_list = _find("PickerList") as ItemList
	_import_ctrl.picker_hint = _find("PickerHint") as Label
	_import_ctrl.bind_picker_buttons(
		_find("PickerConfirmButton") as Button,
		_find("PickerCancelButton") as Button,
		_find("SelectAllPickerButton") as Button)
	_import_ctrl.import_completed.connect(_on_import_completed)
	_import_ctrl.status_changed.connect(_set_status)
	_import_ctrl.context_graphs_availability.connect(_on_context_graphs_availability)

	# Hub pipeline
	_pipeline = HubPipelineScript.new()
	_pipeline.hub = _hub
	_pipeline.seq_fn = Callable(self, "_next_seq")
	_pipeline.status_message.connect(_set_status)
	_hub.job_progress.connect(_pipeline.on_job_progress)
	_hub.job_done.connect(_pipeline.on_job_done)

	# Closure controller
	_closure_ctrl = ClosureControllerScript.new()
	_closure_ctrl.hub = _hub
	_closure_ctrl.seq_fn = Callable(self, "_next_seq")
	var work_on_this_btn: Button = _ui_refs.get("WorkOnThisButton") as Button
	if work_on_this_btn == null:
		work_on_this_btn = _find("WorkOnThisButton") as Button
	_closure_ctrl.bind_ui({
		"dream_inbox_list": _find("DreamInboxList"),
		"saved_closures_list": _find("SavedClosuresList"),
		"work_on_this_button": work_on_this_btn,
		"defer_button": _find("DeferCandidateButton"),
		"reject_button": _find("RejectCandidateButton"),
		"closure_name_edit": _find("ClosureNameEdit"),
		"closure_intent_edit": _find("ClosureIntentEdit"),
		"orientation_option": _find("OrientationOption"),
		"coverage_label": _find("CoverageLabel"),
		"time_start_edit": _find("TimeStartEdit"),
		"time_end_edit": _find("TimeEndEdit"),
		"selected_label": _find("SelectedLabel"),
		"commit_button": _find("CommitClosureButton"),
		"closure_status_label": _find("ClosureStatusLabel"),
		"candidate_items_list": _find("CandidateItemsList"),
		"remove_item_button": _find("RemoveItemButton"),
		"available_items_list": _find("AvailableItemsList"),
		"add_item_button": _find("AddItemButton"),
		"commit_another_button": _ui_refs.get("CommitAnotherButton", _find("CommitAnotherButton")),
		"open_synpunkt_button": _ui_refs.get("OpenSynPunktClosuresButton", _find("OpenSynPunktClosuresButton")),
		"post_commit_actions": _ui_refs.get("PostCommitActions", _find("PostCommitActions")),
	})
	if _closure_ctrl.has_signal("candidate_editing"):
		_closure_ctrl.candidate_editing.connect(_on_candidate_editing)
	if _closure_ctrl.has_signal("closure_committed"):
		_closure_ctrl.closure_committed.connect(_on_closure_committed)
	if _closure_ctrl.has_signal("navigate_requested"):
		_closure_ctrl.navigate_requested.connect(_on_closure_navigate_requested)

	# Analysis / discovery controller (Phase F headless seam)
	_analysis_ctrl = AnalysisControllerScript.new()
	_analysis_ctrl.host_node = self
	_analysis_ctrl.pipeline = _pipeline
	_analysis_ctrl.closure_ctrl = _closure_ctrl
	_analysis_ctrl.ensure_engine()
	_analysis_ctrl.bind_ui({
		"discovery_method": discovery_method,
		"dim_method": dim_method,
		"clusters_slider": clusters_slider,
		"pattern_viewer": pattern_viewer,
		"bottom_tabs": bottom_tabs,
	})
	_analysis_ctrl.analysis_status.connect(_set_status)
	_analysis_ctrl.discovery_completed.connect(_on_discovery_completed)

	_ensure_hub_source_present()

	# Auto-load saved closures from Hub on startup (best-effort, non-blocking)
	_closure_ctrl.reload_saved_closures()

	# Core buttons
	var refresh_btn: Button = _ui_refs.get("RefreshButton") as Button
	if refresh_btn == null:
		refresh_btn = _find("RefreshButton") as Button
	if refresh_btn:
		refresh_btn.pressed.connect(_on_refresh_sources_pressed)
	if import_button:
		import_button.pressed.connect(_on_import_pressed)
	if import_latest_button:
		import_latest_button.pressed.connect(_on_import_latest_pressed)
	if discover_button:
		discover_button.pressed.connect(_on_discover_pressed)
	var reload_btn: Button = _ui_refs.get("ReloadLastAnalysisButton") as Button
	if reload_btn:
		reload_btn.pressed.connect(func(): await _analysis_ctrl.reload_last_analysis(_current_context_graph_artifact_id, _data))
	if clear_button:
		clear_button.pressed.connect(_on_clear_pressed)
	if clusters_slider and clusters_value:
		clusters_slider.value_changed.connect(func(v: float): clusters_value.text = str(int(v)))
	if use_hub_jobs_checkbox:
		_use_hub_jobs = use_hub_jobs_checkbox.button_pressed
		_analysis_ctrl.use_hub_jobs = _use_hub_jobs
		use_hub_jobs_checkbox.toggled.connect(func(v: bool) -> void:
			_use_hub_jobs = v
			_analysis_ctrl.use_hub_jobs = v
		)
	# Embedding preference is persisted; Tier 3 still requires per-provider consent.
	# Advanced open/closed is also persisted under apps.synaxes.advanced_open.
	_load_synaxes_settings()
	if use_hub_embeddings_checkbox:
		use_hub_embeddings_checkbox.toggled.connect(_on_use_hub_embeddings_toggled)
	if use_model_themes_button:
		use_model_themes_button.pressed.connect(_on_use_model_themes_pressed)
	if model_themes_consent_dialog:
		model_themes_consent_dialog.confirmed.connect(_on_model_themes_consent_confirmed)
		model_themes_consent_dialog.canceled.connect(_on_model_themes_consent_canceled)
	if advanced_toggle:
		advanced_toggle.toggled.connect(_on_advanced_toggled)
	call_deferred("_refresh_phase_b_default_path_ui")

	# Closure buttons (delegate to closure controller)
	var dream_inbox_list_node: ItemList = _find("DreamInboxList") as ItemList
	if dream_inbox_list_node:
		dream_inbox_list_node.item_selected.connect(_closure_ctrl.on_dream_candidate_selected)
	var load_saved_btn: Button = _find("LoadSavedClosuresButton") as Button
	if load_saved_btn:
		load_saved_btn.pressed.connect(func(): await _closure_ctrl.reload_saved_closures())
	var commit_btn: Button = _find("CommitClosureButton") as Button
	if commit_btn:
		commit_btn.pressed.connect(func(): await _closure_ctrl.commit_closure(_provenance_ctx()))
	var defer_btn: Button = _find("DeferCandidateButton") as Button
	if defer_btn:
		defer_btn.pressed.connect(func(): await _closure_ctrl.decision_candidate("defer", true))
	var reject_btn: Button = _find("RejectCandidateButton") as Button
	if reject_btn:
		reject_btn.pressed.connect(func(): await _closure_ctrl.decision_candidate("reject", true))

	_closure_ctrl.update_decision_buttons()

	# Pattern viewer signals + viewer buttons
	if pattern_viewer:
		if pattern_viewer.has_signal("pattern_selected"):
			pattern_viewer.pattern_selected.connect(_on_viewer_pattern_selected)
		if pattern_viewer.has_signal("pattern_deselected"):
			pattern_viewer.pattern_deselected.connect(_on_viewer_pattern_deselected)
	var reset_btn: Button = _ui_refs.get("ResetViewButton") as Button
	if reset_btn and pattern_viewer:
		reset_btn.pressed.connect(func(): pattern_viewer._reset_camera())
	var focus_btn: Button = _ui_refs.get("FocusSelectionButton") as Button
	if focus_btn and pattern_viewer:
		focus_btn.pressed.connect(func(): pattern_viewer._focus_on_selection())
	var rot_left: Button = _ui_refs.get("RotateLeft") as Button
	if rot_left and pattern_viewer:
		rot_left.pressed.connect(func(): pattern_viewer._orbit_camera(Vector2(-20, 0)))
	var rot_right: Button = _ui_refs.get("RotateRight") as Button
	if rot_right and pattern_viewer:
		rot_right.pressed.connect(func(): pattern_viewer._orbit_camera(Vector2(20, 0)))
	var rot_up: Button = _ui_refs.get("RotateUp") as Button
	if rot_up and pattern_viewer:
		rot_up.pressed.connect(func(): pattern_viewer._orbit_camera(Vector2(0, -20)))
	var rot_down: Button = _ui_refs.get("RotateDown") as Button
	if rot_down and pattern_viewer:
		rot_down.pressed.connect(func(): pattern_viewer._orbit_camera(Vector2(0, 20)))
	var zoom_in: Button = _ui_refs.get("ZoomIn") as Button
	if zoom_in and pattern_viewer:
		zoom_in.pressed.connect(func(): pattern_viewer._zoom_camera(-1))
	var zoom_out: Button = _ui_refs.get("ZoomOut") as Button
	if zoom_out and pattern_viewer:
		zoom_out.pressed.connect(func(): pattern_viewer._zoom_camera(1))

	# Panel toggle buttons
	_toggle_left_btn = _find("ToggleLeftPanel") as Button
	_toggle_viewer_btn = _find("TogglePatternViewer") as Button
	_toggle_bottom_btn = _find("ToggleBottomPanel") as Button
	_left_panel_node = _find("LeftPanel") as Control
	_viewer_panel_node = _find("PatternViewerContainer") as Control
	_bottom_panel_node = _find("BottomPanel") as Control
	if _toggle_left_btn:
		_toggle_left_btn.toggled.connect(_on_toggle_left_panel)
	if _toggle_viewer_btn:
		_toggle_viewer_btn.toggled.connect(_on_toggle_viewer_panel)
	if _toggle_bottom_btn:
		_toggle_bottom_btn.toggled.connect(_on_toggle_bottom_panel)
	if not resized.is_connected(_on_synaxes_resized):
		resized.connect(_on_synaxes_resized)
	if not visibility_changed.is_connected(_on_synaxes_visibility_changed):
		visibility_changed.connect(_on_synaxes_visibility_changed)
	call_deferred("_apply_initial_panel_layout")

	# Imported data select/deselect all buttons
	var sel_all_btn := _find("SelectAllButton") as Button
	if sel_all_btn:
		sel_all_btn.pressed.connect(_on_select_all_imported)
	var desel_all_btn := _find("DeselectAllButton") as Button
	if desel_all_btn:
		desel_all_btn.pressed.connect(_on_deselect_all_imported)

	_set_spine_state("idle")
	_set_status("%s %s" % [_SELL_LINE, _EMPTY_CTA])

func _find(node_name: String) -> Node:
	return find_child(node_name, true, false)

# ── Import ────────────────────────────────────────────────────────────────

func _ensure_hub_source_present() -> void:
	## Rebuild the source list: real sources on top, separator, then demo sources below.
	if not source_list:
		return

	# Collect any existing demo items
	var demo_labels: Array[String] = []
	for i in range(source_list.item_count):
		var lbl := source_list.get_item_text(i)
		if lbl.begins_with("Demo:"):
			demo_labels.append(lbl)

	source_list.clear()

	# Real data sources first
	source_list.add_item(SOURCE_LABEL_HUB_CONTEXT)
	source_list.add_item(SOURCE_LABEL_HUB_EMBEDDINGS)
	source_list.add_item(SOURCE_LABEL_SCENSYN_SESSIONS)

	# Visual separator (disabled, non-selectable)
	var sep_idx := source_list.item_count
	source_list.add_item("── Demo / sample data ──")
	source_list.set_item_disabled(sep_idx, true)
	source_list.set_item_selectable(sep_idx, false)

	# Demo sources
	if demo_labels.is_empty():
		demo_labels = ["Demo: Text Samples", "Demo: Semantic Samples", "Demo: Image Samples"]
	for demo_lbl in demo_labels:
		source_list.add_item(demo_lbl)

func _on_refresh_sources_pressed() -> void:
	_ensure_hub_source_present()
	_refresh_themes_status_ui()
	if _import_ctrl:
		await _import_ctrl.refresh_context_graph_availability()
	_set_status("Sources refreshed.")


func _on_import_pressed() -> void:
	if not source_list:
		_set_status("Import failed: SourceList missing")
		return
	var selected := source_list.get_selected_items()
	if selected.is_empty():
		_set_status("Please select a source type first.")
		return
	var label := source_list.get_item_text(selected[0])
	await _import_ctrl.import_source(label)


func _on_import_latest_pressed() -> void:
	## REQ-NDP-007: one-click latest Hub context graph (picker if count > 1).
	await _import_ctrl.import_latest_context_graph()


func _on_context_graphs_availability(graph_count: int) -> void:
	if import_latest_button:
		import_latest_button.visible = graph_count > 0


func _on_import_completed(data: Array) -> void:
	## Called by the import controller when data is ready.
	_data = data
	_current_context_graph_artifact_id = str(_import_ctrl.last_context_graph_artifact_id)
	_analysis_ctrl.use_hub_embeddings = _use_hub_embeddings
	_data = await _analysis_ctrl.apply_embeddings(_data, _current_context_graph_artifact_id)
	_analysis_ctrl.ensure_engine()
	_analysis_ctrl.engine.set_data(_data)
	_populate_imported_data_preview()
	_set_spine_state("imported")
	_refresh_themes_status_ui()
	if _auto_discover_after_import:
		_auto_discover_after_import = false
		await _on_discover_pressed()


# ── SynAxes settings (RuntimeConfig) ───────────────────────────────────────

func _load_synaxes_settings() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	var apps: Dictionary = apps_any if typeof(apps_any) == TYPE_DICTIONARY else {}
	var syn_any: Variant = apps.get(_CFG_APP_ID, {})
	var syn_cfg: Dictionary = syn_any if typeof(syn_any) == TYPE_DICTIONARY else {}

	var use_tier3_any: Variant = syn_cfg.get(_CFG_USE_MODEL_EMBEDDINGS_TIER3, false)
	var use_tier3: bool = bool(use_tier3_any)
	_use_hub_embeddings = use_tier3
	_analysis_ctrl.use_hub_embeddings = use_tier3
	if use_hub_embeddings_checkbox:
		use_hub_embeddings_checkbox.button_pressed = use_tier3

	var advanced_open_any: Variant = syn_cfg.get(_CFG_ADVANCED_OPEN, false)
	var is_advanced_open: bool = bool(advanced_open_any)
	_apply_advanced_open(is_advanced_open, false)


func _save_synaxes_settings() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	var apps: Dictionary = apps_any if typeof(apps_any) == TYPE_DICTIONARY else {}
	var syn_any: Variant = apps.get(_CFG_APP_ID, {})
	var syn_cfg: Dictionary = syn_any if typeof(syn_any) == TYPE_DICTIONARY else {}

	syn_cfg[_CFG_USE_MODEL_EMBEDDINGS_TIER3] = bool(_use_hub_embeddings)
	var is_advanced_open: bool = false
	if advanced_toggle:
		is_advanced_open = advanced_toggle.button_pressed
	elif advanced_panel:
		is_advanced_open = advanced_panel.visible
	syn_cfg[_CFG_ADVANCED_OPEN] = is_advanced_open
	apps[_CFG_APP_ID] = syn_cfg
	cfg["apps"] = apps
	RuntimeConfig.save_config(cfg)


func _on_advanced_toggled(is_open: bool) -> void:
	_apply_advanced_open(is_open, true)


func _apply_advanced_open(is_open: bool, should_persist: bool) -> void:
	if advanced_panel:
		advanced_panel.visible = is_open
	if advanced_toggle and advanced_toggle.button_pressed != is_open:
		advanced_toggle.set_pressed_no_signal(is_open)
	if should_persist:
		_save_synaxes_settings()


func _set_spine_state(next_state: String) -> void:
	_spine_state = next_state
	_refresh_step_spine()


func _refresh_step_spine() -> void:
	if step_spine_label == null:
		return
	var active_idx: int = 0
	match _spine_state:
		"imported":
			active_idx = 1
		"discovered":
			active_idx = 2
		"editing":
			active_idx = 3
		"committed":
			active_idx = 4
		_:
			active_idx = 0
	var parts: Array[String] = []
	for i in range(_SPINE_STEPS.size()):
		var step_label: String = _SPINE_STEPS[i]
		if i == active_idx:
			parts.append("[%s]" % step_label)
		else:
			parts.append(step_label)
	step_spine_label.text = " → ".join(parts)


func _on_candidate_editing(_idx: int) -> void:
	_set_spine_state("editing")


func _on_closure_committed(_closure_artifact_id: String) -> void:
	_set_spine_state("committed")


func _on_closure_navigate_requested(target: String) -> void:
	navigate_requested.emit(target)


# ── Phase B: model themes consent + import CTA ─────────────────────────────

func _refresh_phase_b_default_path_ui() -> void:
	_refresh_themes_status_ui()
	if _import_ctrl:
		await _import_ctrl.refresh_context_graph_availability()


func _refresh_themes_status_ui() -> void:
	if not _analysis_ctrl:
		return
	var tier_text: String = _analysis_ctrl.embedding_tier_label()
	if themes_status_label:
		themes_status_label.text = "Themes: %s" % tier_text
	if embedding_tier_label:
		embedding_tier_label.text = "Themes: %s" % tier_text
	var cap: Dictionary = _analysis_ctrl.probe_embed_capability()
	var is_capable: bool = bool(cap.get("capable", false))
	var provider_name: String = str(cap.get("provider", ""))
	var has_consent: bool = is_capable and _analysis_ctrl.has_provider_consent(provider_name)
	if use_model_themes_button:
		var opt_label: String = _analysis_ctrl.disclosed_opt_in_label()
		if not opt_label.is_empty():
			use_model_themes_button.text = opt_label
		# Show when embed-capable and not yet using consented model themes.
		use_model_themes_button.visible = is_capable and not (has_consent and _use_hub_embeddings)


func _on_use_model_themes_pressed() -> void:
	_pending_model_themes_from_checkbox = false
	_show_model_themes_consent_dialog()


func _on_use_hub_embeddings_toggled(is_on: bool) -> void:
	if not is_on:
		_use_hub_embeddings = false
		_analysis_ctrl.use_hub_embeddings = false
		_save_synaxes_settings()
		_refresh_themes_status_ui()
		return
	var cap: Dictionary = _analysis_ctrl.probe_embed_capability()
	var provider_name: String = str(cap.get("provider", ""))
	if bool(cap.get("capable", false)) and _analysis_ctrl.has_provider_consent(provider_name):
		_use_hub_embeddings = true
		_analysis_ctrl.use_hub_embeddings = true
		_save_synaxes_settings()
		_refresh_themes_status_ui()
		return
	# Require disclosed consent before enabling — do not silently flip on.
	_pending_model_themes_from_checkbox = true
	if use_hub_embeddings_checkbox:
		use_hub_embeddings_checkbox.set_pressed_no_signal(false)
	_show_model_themes_consent_dialog()


func _show_model_themes_consent_dialog() -> void:
	var opt_label: String = _analysis_ctrl.disclosed_opt_in_label()
	if opt_label.is_empty():
		_set_status("No embed-capable SynTree model is active. Themes stay local.")
		_pending_model_themes_from_checkbox = false
		return
	if model_themes_consent_dialog:
		model_themes_consent_dialog.dialog_text = (
			"%s.\n\nThis is remembered for that provider. Default remains Local themes."
			% opt_label
		)
		model_themes_consent_dialog.popup_centered()
	else:
		# Fallback: one-click consent without dialog node.
		_on_model_themes_consent_confirmed()


func _on_model_themes_consent_confirmed() -> void:
	var cap: Dictionary = _analysis_ctrl.opt_in_model_themes_for_active_provider()
	if not bool(cap.get("capable", false)):
		_set_status("Model themes unavailable — no embed-capable provider.")
		_pending_model_themes_from_checkbox = false
		return
	_use_hub_embeddings = true
	_analysis_ctrl.use_hub_embeddings = true
	if use_hub_embeddings_checkbox:
		use_hub_embeddings_checkbox.set_pressed_no_signal(true)
	_save_synaxes_settings()
	_pending_model_themes_from_checkbox = false
	_set_status("Model themes enabled for %s. Item text will be sent on next import/discover." % str(cap.get("provider", "")))
	_refresh_themes_status_ui()
	if not _data.is_empty():
		_data = await _analysis_ctrl.apply_embeddings(_data, _current_context_graph_artifact_id)
		_analysis_ctrl.ensure_engine()
		_analysis_ctrl.engine.set_data(_data)
		_refresh_themes_status_ui()


func _on_model_themes_consent_canceled() -> void:
	_pending_model_themes_from_checkbox = false
	_use_hub_embeddings = false
	_analysis_ctrl.use_hub_embeddings = false
	if use_hub_embeddings_checkbox:
		use_hub_embeddings_checkbox.set_pressed_no_signal(false)
	_save_synaxes_settings()
	_refresh_themes_status_ui()


# ── Discover ──────────────────────────────────────────────────────────────

func _on_discover_pressed() -> void:
	if _data.is_empty():
		_set_status("No data. Click Import first.")
		return
	var active_data: Array = _get_selected_data()
	if active_data.is_empty():
		_set_status("No items selected. Check the Imported Data tab and select items to analyse.")
		return
	_analysis_ctrl.use_hub_jobs = _use_hub_jobs
	await _analysis_ctrl.discover(active_data, _current_context_graph_artifact_id, _data)


func _on_discovery_completed(result: Dictionary) -> void:
	## UI follow-up after analysis controller finishes discovery / reload.
	var hydrated: Array = result.get("hydrated_data", [])
	if not hydrated.is_empty():
		_data = hydrated
		var ctx_id: String = str(result.get("context_graph_artifact_id", ""))
		if not ctx_id.is_empty():
			_current_context_graph_artifact_id = ctx_id
		_populate_imported_data_preview()
	_update_provenance_display()
	_populate_pattern_overview()
	if _focus_closures_after_discover:
		_focus_closures_after_discover = false
		# Propose-themes path (REQ-NDP-016): Dream Inbox / Closure Editor.
		if bottom_tabs and bottom_tabs.get_tab_count() > 2:
			bottom_tabs.current_tab = 2
	elif bottom_tabs and bottom_tabs.get_tab_count() > 0:
		# Overview-first (REQ-NDP-004): analysis_controller already sets tab 0; reinforce here.
		bottom_tabs.current_tab = 0
	_set_spine_state("discovered")


func begin_propose_themes(session_id: String = "") -> void:
	## REQ-NDP-016: preload ScenSyn/Workshop session turns and queue Discover (dock path).
	_auto_discover_after_import = true
	_focus_closures_after_discover = true
	_set_status("Propose themes: importing session data…")
	await _import_ctrl.import_scensyn_session(session_id)
	# Failed imports do not emit import_completed — clear queued flags.
	if _auto_discover_after_import and _data.is_empty():
		_auto_discover_after_import = false
		_focus_closures_after_discover = false
		_set_status("Propose themes: no session data imported. Publish session turns to Hub first.")

# ── Clear ─────────────────────────────────────────────────────────────────

func _on_clear_pressed() -> void:
	_data = []
	_analysis_ctrl.ensure_engine()
	_analysis_ctrl.engine.set_data([])
	_analysis_ctrl.last_patterns = []
	_analysis_ctrl.clear_viewer()
	_set_spine_state("idle")
	_set_status("Cleared. %s" % _EMPTY_CTA)

# ── URI loading ───────────────────────────────────────────────────────────

func _load_json_from_uri(uri: String) -> Variant:
	if uri.begins_with("http://") or uri.begins_with("https://"):
		return await _load_json_from_http(uri)
	if uri.begins_with("file:"):
		return _load_json_from_file_uri(uri)
	return null

func _load_json_from_file_uri(uri: String) -> Variant:
	var path := uri
	path = path.replace("file:///", "")
	path = path.replace("file://", "")
	if path.length() > 2 and path[0] == "/" and path[2] == ":":
		path = path.substr(1)
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return null
	var raw := f.get_as_text()
	f.close()
	return JSON.parse_string(raw)

func _load_json_from_http(uri: String) -> Variant:
	var http_req := HTTPRequest.new()
	add_child(http_req)
	var err := http_req.request(uri)
	if err != OK:
		http_req.queue_free()
		return null
	var result: Array = await http_req.request_completed
	http_req.queue_free()
	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	if response_code < 200 or response_code >= 300:
		return null
	return JSON.parse_string(body.get_string_from_utf8())

# ── Provenance helpers ────────────────────────────────────────────────────

func _update_provenance_display() -> void:
	## Build provenance string and display it in the closure editor provenance label.
	var snap: Dictionary = _analysis_ctrl.provenance_snapshot(_current_context_graph_artifact_id)
	var parts: Array[String] = []
	var ctx_id: String = str(snap.get("context_graph_artifact_id", ""))
	if not ctx_id.is_empty():
		parts.append("Source: context_graph %s" % ctx_id.left(12))
	var method_label: String = ""
	if discovery_method and discovery_method.selected >= 0:
		method_label = discovery_method.get_item_text(discovery_method.selected)
	var dim_label: String = ""
	if dim_method and dim_method.selected >= 0:
		dim_label = dim_method.get_item_text(dim_method.selected)
	var k_val: int = int(snap.get("clusters_count", 0))
	if not method_label.is_empty():
		parts.append("Method: %s | DimRed: %s | k=%d" % [method_label, dim_label, k_val])
	var emb_label: String = str(snap.get("embedding_tier_label", ""))
	if emb_label != "" and emb_label != "no embeddings yet":
		parts.append("Embeddings: %s" % emb_label)
	parts.append("Via: %s" % ("Hub Jobs" if bool(snap.get("via_hub_jobs", false)) else "Local engine"))
	var run_id: String = str(snap.get("analysis_run_artifact_id", ""))
	var proj_id: String = str(snap.get("projection_artifact_id", ""))
	var clust_id: String = str(snap.get("cluster_artifact_id", ""))
	var bridge_id: String = str(snap.get("bridge_artifact_id", ""))
	var hub_id: String = str(snap.get("hub_artifact_id", ""))
	if not run_id.is_empty():
		parts.append("Analysis run: %s" % run_id.left(12))
	if not proj_id.is_empty():
		parts.append("Projection: %s" % proj_id.left(12))
	if not clust_id.is_empty():
		parts.append("Clusters: %s" % clust_id.left(12))
	if not bridge_id.is_empty():
		parts.append("Bridges: %s" % bridge_id.left(12))
	if not hub_id.is_empty():
		parts.append("Hubs: %s" % hub_id.left(12))
	var cache_count: int = _analysis_ctrl.cache_entry_count()
	if cache_count > 0:
		parts.append("Embedding cache: %d entries" % cache_count)
	var prov_text: String = " | ".join(parts) if not parts.is_empty() else ""
	if editor_provenance_label:
		editor_provenance_label.text = "Provenance: %s" % prov_text if not prov_text.is_empty() else ""

func _provenance_ctx() -> Dictionary:
	return _analysis_ctrl.provenance_snapshot(_current_context_graph_artifact_id)

# ── Status display ────────────────────────────────────────────────────────

func _update_embedding_ui() -> void:
	## Refresh the embedding-tier and cache-stats labels in the controls panel.
	if not _analysis_ctrl:
		return
	_refresh_themes_status_ui()
	if cache_stats_label:
		cache_stats_label.text = "Cache: %d entries" % _analysis_ctrl.cache_entry_count()

func _set_status(msg: String) -> void:
	print("[SynAxesRuntime] ", msg)
	_update_embedding_ui()
	# Update persistent status label (always visible below "Pattern Space" heading)
	if persistent_status_label:
		persistent_status_label.text = msg
	if debug_info:
		var extras: Array[String] = []
		if _analysis_ctrl:
			var run_id: String = str(_analysis_ctrl.last_analysis_run_artifact_id)
			var proj_id: String = str(_analysis_ctrl.last_projection_artifact_id)
			var clust_id: String = str(_analysis_ctrl.last_cluster_artifact_id)
			var bridge_id: String = str(_analysis_ctrl.last_bridge_artifact_id)
			var hub_id: String = str(_analysis_ctrl.last_hub_artifact_id)
			if not run_id.is_empty():
				extras.append("run=%s" % run_id.left(8))
			if not proj_id.is_empty():
				extras.append("proj=%s" % proj_id.left(8))
			if not clust_id.is_empty():
				extras.append("clust=%s" % clust_id.left(8))
			if not bridge_id.is_empty():
				extras.append("bridges=%s" % bridge_id.left(8))
			if not hub_id.is_empty():
				extras.append("hubs=%s" % hub_id.left(8))
		if not _current_context_graph_artifact_id.is_empty():
			extras.append("ctx=%s" % _current_context_graph_artifact_id.left(8))
		var method_label: String = ""
		if discovery_method and discovery_method.selected >= 0:
			method_label = discovery_method.get_item_text(discovery_method.selected)
		if not method_label.is_empty():
			extras.append("method=%s" % method_label)
		debug_info.text = msg + ("\n" + " | ".join(extras) if extras.size() > 0 else "")

# ── Misc ──────────────────────────────────────────────────────────────────

func _random_vector(dim: int) -> Array:
	var v: Array = []
	for _i in range(dim):
		v.append(randf() * 2.0 - 1.0)
	return v

func _next_seq() -> int:
	var v := _seq
	_seq += 1
	return v

# ── Imported data preview ──────────────────────────────────────────────────

func _populate_imported_data_preview() -> void:
	## Show all imported items in the "Imported Data" tab so users can review and curate.
	if not imported_data_list:
		return
	imported_data_list.clear()
	for item_any in _data:
		if typeof(item_any) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = item_any
		var content := str(it.get("content", ""))
		var item_id := str(it.get("id", ""))
		if content.is_empty():
			content = item_id if not item_id.is_empty() else "(no content)"
		if content.length() > 120:
			content = content.left(117) + "..."
		imported_data_list.add_item(content)
	# Select all by default
	for i in range(imported_data_list.item_count):
		imported_data_list.select(i, false)
	# Switch to the "Imported Data" tab so the user sees what was loaded
	if bottom_tabs and bottom_tabs.get_tab_count() > 1:
		bottom_tabs.current_tab = 1
	if imported_data_summary:
		var source_label := ""
		if source_list and not source_list.get_selected_items().is_empty():
			source_label = source_list.get_item_text(source_list.get_selected_items()[0])
		imported_data_summary.text = "%d items imported from %s. All selected for discovery." % [_data.size(), source_label if not source_label.is_empty() else "source"]

func _get_selected_data() -> Array:
	## Return only the items the user has selected in the Imported Data tab.
	if not imported_data_list or imported_data_list.item_count == 0:
		return _data  # Fallback: use all data if list not available
	var selected_indices := imported_data_list.get_selected_items()
	if selected_indices.is_empty():
		return _data  # If nothing selected, use all
	var result: Array = []
	for idx in selected_indices:
		if idx < _data.size():
			result.append(_data[idx])
	return result

func _on_select_all_imported() -> void:
	if not imported_data_list:
		return
	for i in range(imported_data_list.item_count):
		imported_data_list.select(i, false)
	if imported_data_summary:
		imported_data_summary.text = "%d / %d items selected." % [imported_data_list.item_count, _data.size()]

func _on_deselect_all_imported() -> void:
	if not imported_data_list:
		return
	imported_data_list.deselect_all()
	if imported_data_summary:
		imported_data_summary.text = "0 / %d items selected. Select items to include in discovery." % _data.size()

# ── Pattern selection → Details tab ────────────────────────────────────────

func _on_viewer_pattern_selected(pattern_id: int) -> void:
	## Called when a sphere is clicked in the 3D viewer.
	## Updates status, highlights member items, pre-selects Dream Inbox candidate,
	## and populates the closure editor's position/related/provenance labels.
	var pattern_data: Dictionary = {}
	for p_any in _analysis_ctrl.last_patterns:
		if typeof(p_any) == TYPE_DICTIONARY:
			var p: Dictionary = p_any
			if int(p.get("id", -1)) == pattern_id:
				pattern_data = p
				break

	var p_type := str(pattern_data.get("type", "pattern")).capitalize()
	var p_items: Array = pattern_data.get("items", [])
	var conf := float(pattern_data.get("confidence", 0.0))
	var conf_label := "low"
	if conf >= 0.7:
		conf_label = "high"
	elif conf >= 0.4:
		conf_label = "medium"
	var status_name := str(pattern_data.get("name", "Pattern %d" % pattern_id))
	_set_status("Selected: %s — %s, %d items, %s confidence. Check Closures tab to edit." % [
		status_name, p_type, p_items.size(), conf_label])

	# Cross-highlight member items in Imported Data tab
	_highlight_imported_items_for_pattern(pattern_data)

	# Pre-select matching candidate in Dream Inbox and populate closure editor
	_preselect_dream_inbox_candidate(pattern_id)

	# Populate closure editor labels with position, related patterns, provenance
	_update_editor_detail_labels(pattern_data)

	# Auto-switch to Closures tab so the user sees the populated editor
	if bottom_tabs and bottom_tabs.get_tab_count() > 2:
		bottom_tabs.current_tab = 2

func _highlight_imported_items_for_pattern(pattern_data: Dictionary) -> void:
	## Highlight the imported data list items that belong to this pattern.
	if not imported_data_list or imported_data_list.item_count == 0:
		return
	imported_data_list.deselect_all()
	var pattern_item_ids: Array = []
	var items: Array = pattern_data.get("items", [])
	for item_any in items:
		if typeof(item_any) == TYPE_DICTIONARY:
			pattern_item_ids.append(str((item_any as Dictionary).get("id", "")))
	if pattern_item_ids.is_empty():
		return
	for i in range(mini(imported_data_list.item_count, _data.size())):
		if typeof(_data[i]) == TYPE_DICTIONARY:
			var data_id := str((_data[i] as Dictionary).get("id", ""))
			if data_id in pattern_item_ids:
				imported_data_list.select(i, false)

func _preselect_dream_inbox_candidate(pattern_id: int) -> void:
	## If a Dream Inbox candidate maps to this pattern, select it and populate the editor.
	## Only matches on the PRIMARY pattern ID (first element of pattern_ids),
	## not related pattern IDs, to avoid cross-activation between clusters.
	if not _closure_ctrl:
		return
	var candidates: Array = _closure_ctrl.dream_candidates
	for i in range(candidates.size()):
		if typeof(candidates[i]) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = candidates[i]
		# Match only on the primary pattern ID (first element), not related ones
		var pids: Variant = c.get("pattern_ids", [])
		var is_match := false
		if typeof(pids) == TYPE_ARRAY and (pids as Array).size() > 0:
			is_match = int((pids as Array)[0]) == pattern_id
		if not is_match:
			# Fallback: check single-value keys
			is_match = int(c.get("pattern_id", c.get("id", -1))) == pattern_id
		if is_match:
			if _closure_ctrl.dream_inbox_list:
				_closure_ctrl.dream_inbox_list.select(i)
				_closure_ctrl.on_dream_candidate_selected(i)
			return

func _update_editor_detail_labels(pattern_data: Dictionary) -> void:
	## Populate the position, related patterns, and provenance labels in the closure editor.
	if editor_position_label:
		var pos: Variant = pattern_data.get("position", null)
		if pos is Vector3:
			editor_position_label.text = "Position: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]
		else:
			editor_position_label.text = ""
	if editor_related_label:
		var relations: Array = pattern_data.get("relations", [])
		if relations.is_empty():
			editor_related_label.text = ""
		else:
			var rel_parts: Array = []
			for rel_any in relations:
				if typeof(rel_any) == TYPE_DICTIONARY:
					var r: Dictionary = rel_any
					rel_parts.append("%s (%s)" % [str(r.get("id", "?")), str(r.get("type", "related"))])
			editor_related_label.text = "Related: %s" % ", ".join(rel_parts) if not rel_parts.is_empty() else ""
	_update_provenance_display()

func _on_viewer_pattern_deselected() -> void:
	_set_status("Selection cleared. Click a sphere to inspect a pattern.")
	# Restore full selection in imported data list
	if imported_data_list:
		for i in range(imported_data_list.item_count):
			imported_data_list.select(i, false)
	# Clear closure editor detail labels
	if editor_position_label:
		editor_position_label.text = ""
	if editor_related_label:
		editor_related_label.text = ""

# ── Pattern Overview tab ──────────────────────────────────────────────────

func _populate_pattern_overview() -> void:
	## Fill the Pattern Overview tab with a flat list of all discovered patterns.
	if not pattern_overview_list:
		return
	pattern_overview_list.clear()
	var patterns: Array = _analysis_ctrl.last_patterns
	if patterns.is_empty():
		if overview_summary_label:
			overview_summary_label.text = "No patterns discovered yet."
		return
	var cluster_count := 0
	var bridge_count := 0
	var hub_count := 0
	for p_any in patterns:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_any
		var p_id := int(p.get("id", -1))
		var p_type := str(p.get("type", "unknown"))
		var p_items: Array = p.get("items", [])
		var conf := float(p.get("confidence", 0.0))
		var conf_str := "%.0f%%" % (conf * 100.0)
		# Count by type
		match p_type:
			"cluster": cluster_count += 1
			"bridge": bridge_count += 1
			"hub": hub_count += 1
		# Content preview from first item
		var preview := ""
		if p_items.size() > 0 and typeof(p_items[0]) == TYPE_DICTIONARY:
			preview = str((p_items[0] as Dictionary).get("content", ""))
			if preview.length() > 40:
				preview = preview.left(37) + "..."
		# Clearer labels than cryptic single-line rows: include type + id + counts + confidence.
		var row_text := "%s #%d  •  %d items  •  %s" % [p_type.capitalize(), p_id, p_items.size(), conf_str]
		if not preview.is_empty():
			row_text += "  •  %s" % preview
		pattern_overview_list.add_item(row_text)
		var new_idx := pattern_overview_list.item_count - 1
		pattern_overview_list.set_item_metadata(new_idx, p_id)
		# Tooltip shows a slightly richer sample (first 3 items).
		var tip_parts: Array[String] = []
		tip_parts.append("%s #%d" % [p_type.capitalize(), p_id])
		tip_parts.append("%d items • %s confidence" % [p_items.size(), conf_str])
		var sample_parts: Array[String] = []
		for it_any in p_items:
			if sample_parts.size() >= 3:
				break
			if typeof(it_any) == TYPE_DICTIONARY:
				var ctext := str((it_any as Dictionary).get("content", "")).strip_edges()
				if ctext.length() > 80:
					ctext = ctext.left(77) + "..."
				if not ctext.is_empty():
					sample_parts.append("• " + ctext)
		if not sample_parts.is_empty():
			tip_parts.append("")
			tip_parts.append("Samples:")
			tip_parts.append("\n".join(sample_parts))
		pattern_overview_list.set_item_tooltip(new_idx, "\n".join(tip_parts))
	if overview_summary_label:
		var parts: Array = []
		if cluster_count > 0:
			parts.append("%d clusters" % cluster_count)
		if bridge_count > 0:
			parts.append("%d bridges" % bridge_count)
		if hub_count > 0:
			parts.append("%d hubs" % hub_count)
		overview_summary_label.text = "%d patterns: %s. Click a row to highlight it in Pattern Space and load it in the Closure Editor." % [
			patterns.size(), ", ".join(parts) if not parts.is_empty() else "none"]

func _on_overview_pattern_selected(index: int) -> void:
	## When a pattern is clicked in the overview list, highlight it in the 3D viewer
	## and run the full selection flow (status, cross-highlight, Dream Inbox pre-select).
	if not pattern_overview_list:
		return
	var p_id: int = pattern_overview_list.get_item_metadata(index)
	# Highlight sphere in the 3D viewer
	if pattern_viewer:
		if pattern_viewer.has_method("_highlight_pattern"):
			pattern_viewer._highlight_pattern(p_id)
	# Run the same handler as a sphere click (populates editor, cross-highlights, etc.)
	_on_viewer_pattern_selected(p_id)

# ── Panel toggles ─────────────────────────────────────────────────────────

func _on_toggle_left_panel(is_pressed: bool) -> void:
	if _left_panel_node:
		_left_panel_node.visible = is_pressed
		call_deferred("_refresh_split_layout")

func _on_toggle_viewer_panel(is_pressed: bool) -> void:
	if _viewer_panel_node:
		_viewer_panel_node.visible = is_pressed
		call_deferred("_refresh_split_layout")

func _on_toggle_bottom_panel(is_pressed: bool) -> void:
	if _bottom_panel_node:
		_bottom_panel_node.visible = is_pressed

	call_deferred("_refresh_split_layout")

func _on_synaxes_resized() -> void:
	call_deferred("_refresh_split_layout")

func _on_synaxes_visibility_changed() -> void:
	if is_visible_in_tree():
		call_deferred("_refresh_split_layout")

func _refresh_split_layout() -> void:
	var main_container_node: Control = _find("MainContainer") as Control
	if main_container_node:
		main_container_node.update_minimum_size()

	var main_split_node: SplitContainer = _find("VSplitContainer") as SplitContainer
	if main_split_node:
		main_split_node.update_minimum_size()
		main_split_node.queue_sort()

	var top_split_node: SplitContainer = _find("TopSection") as SplitContainer
	if top_split_node:
		top_split_node.update_minimum_size()
		top_split_node.queue_sort()


func _apply_initial_panel_layout() -> void:
	if _toggle_left_btn:
		_on_toggle_left_panel(_toggle_left_btn.button_pressed)
	if _toggle_viewer_btn:
		_on_toggle_viewer_panel(_toggle_viewer_btn.button_pressed)
	if _toggle_bottom_btn:
		_on_toggle_bottom_panel(_toggle_bottom_btn.button_pressed)

	# Set the vertical split proportionally so the Pattern Viewer always gets
	# a reasonable share of the available height regardless of window/dock size.
	var vsplit: SplitContainer = _find("VSplitContainer") as SplitContainer
	if vsplit and vsplit.size.y > 0:
		# 58% for the viewer area, 42% for the bottom tabs — clamp so neither
		# panel goes below its minimum usable height.
		var desired: int = int(vsplit.size.y * 0.58)
		desired = clampi(desired, 240, 600)
		vsplit.split_offset = desired

	_refresh_split_layout()
