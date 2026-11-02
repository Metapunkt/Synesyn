extends RefCounted
class_name SynpunktUiConnectionsUtils

static func _on_apply_present_camera_pressed(owner: Control) -> void:
	var present_selected_ref_any: Variant = owner.get("_present_selected_ref")
	var present_selected_ref: Dictionary = present_selected_ref_any if typeof(present_selected_ref_any) == TYPE_DICTIONARY else {}
	if not present_selected_ref.is_empty() and str(present_selected_ref.get("kind", "")).strip_edges() == "syndoc_frame":
		var frames: Array = owner.call("_get_frames")
		var fid := str(present_selected_ref.get("frame_id", "")).strip_edges()
		var fidx := int(owner.call("_frame_idx_by_id", frames, fid))
		if bool(owner.call("_frame_has_saved_camera", frames, fidx)):
			owner.call("_apply_present_camera_for_frame_idx", fidx, true)
			return
		var step_idx := int(owner.call("_find_deck_step_idx_for_frame_id", fid))
		if step_idx != -1:
			owner.set("_present_deck_step_idx", step_idx)
			owner.call("_apply_present_deck_step", step_idx, true, false)
			return
		owner.call("_set_status", "No camera saved for this frame (neither frame camera nor deck step).")
		return
	var present_view_tabs: TabContainer = owner.get("_present_view_tabs")
	if is_instance_valid(present_view_tabs) and int(present_view_tabs.current_tab) == 1:
		var steps: Array = owner.call("_get_presentation_steps")
		if steps.size() > 0:
			var present_deck_step_idx := int(owner.get("_present_deck_step_idx"))
			if present_deck_step_idx < 0:
				present_deck_step_idx = 0
				owner.set("_present_deck_step_idx", present_deck_step_idx)
			owner.call("_apply_present_deck_step", present_deck_step_idx, true, false)
			return
	owner.call("_apply_present_camera_for_active_frame", true)


static func init_ui_connections_all(owner: Control) -> void:
	var test_comfy: Button = owner.get("_test_comfy")
	if test_comfy:
		test_comfy.pressed.connect(owner._on_test_comfy_pressed)
	var comfy_url_history: OptionButton = owner.get("_comfy_url_history")
	if comfy_url_history and not comfy_url_history.item_selected.is_connected(owner._on_comfy_url_history_selected):
		comfy_url_history.item_selected.connect(owner._on_comfy_url_history_selected)
	var render_route_mode_picker: OptionButton = owner.get("_render_route_mode_picker")
	if render_route_mode_picker and not render_route_mode_picker.item_selected.is_connected(owner._on_render_route_mode_selected):
		render_route_mode_picker.item_selected.connect(owner._on_render_route_mode_selected)
	var workflow_select: OptionButton = owner.get("_workflow_select")
	if workflow_select:
		owner.call("_init_workflow_selector")
		if not workflow_select.item_selected.is_connected(owner._on_render_workflow_selected):
			workflow_select.item_selected.connect(owner._on_render_workflow_selected)
	var submit_render: Button = owner.get("_submit_render")
	if submit_render:
		submit_render.pressed.connect(owner._on_submit_render_pressed)
	var load_workflow_from_flowdoc: Button = owner.get("_load_workflow_from_flowdoc")
	if load_workflow_from_flowdoc:
		load_workflow_from_flowdoc.pressed.connect(owner._on_load_workflow_from_flowdoc)
	var save_workflow_preset: Button = owner.get("_save_workflow_preset")
	if save_workflow_preset:
		save_workflow_preset.pressed.connect(owner._on_save_workflow_preset_pressed)
	var save_preset_version_btn: Button = owner.get("_save_preset_version_btn")
	if save_preset_version_btn:
		save_preset_version_btn.pressed.connect(func(): await owner._on_save_preset_version_pressed())
	var diff_selected_preset_btn: Button = owner.get("_diff_selected_preset_btn")
	if diff_selected_preset_btn:
		diff_selected_preset_btn.pressed.connect(func(): await owner._on_diff_selected_preset_pressed())
	var archive_selected_preset_btn: Button = owner.get("_archive_selected_preset_btn")
	if archive_selected_preset_btn:
		archive_selected_preset_btn.pressed.connect(func(): await owner._on_archive_selected_preset_pressed())
	var prune_archived_preset_btn: Button = owner.get("_prune_archived_preset_btn")
	if prune_archived_preset_btn:
		prune_archived_preset_btn.pressed.connect(func(): await owner._on_prune_archived_preset_pressed())
	var load_default_workflow: Button = owner.get("_load_default_workflow")
	if load_default_workflow:
		load_default_workflow.pressed.connect(owner._on_load_default_workflow_pressed)
	var clear_workflow_inputs: Button = owner.get("_clear_workflow_inputs")
	if clear_workflow_inputs:
		clear_workflow_inputs.pressed.connect(owner._on_clear_workflow_inputs_pressed)
	var workflow_json: TextEdit = owner.get("_workflow_json")
	if workflow_json and not workflow_json.text_changed.is_connected(owner._on_workflow_json_text_changed):
		workflow_json.text_changed.connect(owner._on_workflow_json_text_changed)
	owner.call("_refresh_workflow_health_indicator")
	var common_detect_from_workflow: Button = owner.get("_common_detect_from_workflow")
	if common_detect_from_workflow:
		common_detect_from_workflow.pressed.connect(owner._on_common_detect_from_workflow_pressed)
	var common_apply_to_patch: Button = owner.get("_common_apply_to_patch")
	if common_apply_to_patch:
		common_apply_to_patch.pressed.connect(owner._on_common_apply_to_patch_pressed)
	var render_copy_artifact_id: Button = owner.get("_render_copy_artifact_id")
	if render_copy_artifact_id:
		render_copy_artifact_id.pressed.connect(func(): await owner._copy_selected_render_artifact_id())
	var render_open_artifact_folder: Button = owner.get("_render_open_artifact_folder")
	if render_open_artifact_folder:
		render_open_artifact_folder.pressed.connect(func(): await owner._open_selected_render_artifact_folder())
	var render_clear_results: Button = owner.get("_render_clear_results")
	if render_clear_results:
		render_clear_results.pressed.connect(owner._clear_render_results_list)
	var render_refresh_results: Button = owner.get("_render_refresh_results")
	if render_refresh_results:
		render_refresh_results.pressed.connect(func(): await owner._refresh_render_results_from_hub(200, "manual"))
	var render_delete_render_request: Button = owner.get("_render_delete_render_request")
	if render_delete_render_request:
		render_delete_render_request.pressed.connect(func(): await owner._delete_selected_render_request_artifact())
	var render_delete_selected_artifacts: Button = owner.get("_render_delete_selected_artifacts")
	if render_delete_selected_artifacts:
		render_delete_selected_artifacts.pressed.connect(func(): await owner._delete_selected_render_image_artifacts())
	var render_insert_into_frame: Button = owner.get("_render_insert_into_frame")
	if render_insert_into_frame:
		render_insert_into_frame.pressed.connect(owner._insert_selected_render_artifacts_into_current_frame)
	var save_render_artifact_name_default: Button = owner.get("_save_render_artifact_name_default")
	if save_render_artifact_name_default:
		save_render_artifact_name_default.pressed.connect(owner._save_render_artifact_default_name_from_ui)
	var rename_selected_render_artifact_btn: Button = owner.get("_rename_selected_render_artifact_btn")
	if rename_selected_render_artifact_btn:
		rename_selected_render_artifact_btn.pressed.connect(func(): await owner._rename_selected_render_artifact())
	var reset_selected_render_artifact_name_btn: Button = owner.get("_reset_selected_render_artifact_name_btn")
	if reset_selected_render_artifact_name_btn:
		reset_selected_render_artifact_name_btn.pressed.connect(func(): await owner._reset_selected_render_artifact_name())
	var render_results: ItemList = owner.get("_render_results")
	if render_results:
		render_results.select_mode = ItemList.SELECT_MULTI
		if not render_results.item_selected.is_connected(owner._on_render_results_item_selected):
			render_results.item_selected.connect(owner._on_render_results_item_selected)
		if render_results.has_signal("item_clicked") and not render_results.item_clicked.is_connected(owner._on_render_results_item_clicked):
			render_results.item_clicked.connect(owner._on_render_results_item_clicked)
		if render_results.has_signal("multi_selected") and not render_results.multi_selected.is_connected(owner._on_render_results_multi_selected):
			render_results.multi_selected.connect(owner._on_render_results_multi_selected)
	var render_details_load_workflow_btn: Button = owner.get("_render_details_load_workflow_btn")
	if render_details_load_workflow_btn:
		render_details_load_workflow_btn.pressed.connect(func(): await owner._on_render_details_load_linked_workflow())
	var render_details_load_render_request_btn: Button = owner.get("_render_details_load_render_request_btn")
	if render_details_load_render_request_btn:
		render_details_load_render_request_btn.pressed.connect(func(): await owner._on_render_details_load_linked_render_request())
	var render_details_copy_links_btn: Button = owner.get("_render_details_copy_links_btn")
	if render_details_copy_links_btn:
		render_details_copy_links_btn.pressed.connect(owner._on_render_details_copy_all_links)
	var render_results_filter: LineEdit = owner.get("_render_results_filter")
	if render_results_filter and not render_results_filter.text_changed.is_connected(owner._on_render_results_filter_changed):
		render_results_filter.text_changed.connect(owner._on_render_results_filter_changed)
	var render_results_sort: OptionButton = owner.get("_render_results_sort")
	if render_results_sort and not render_results_sort.item_selected.is_connected(owner._on_render_results_sort_changed):
		render_results_sort.item_selected.connect(owner._on_render_results_sort_changed)
	var delete_confirm_dialog: ConfirmationDialog = owner.get("_delete_confirm_dialog")
	if delete_confirm_dialog:
		delete_confirm_dialog.confirmed.connect(owner._on_delete_confirmed)
	var closures_list: Tree = owner.get("_closures_list")
	if closures_list:
		closures_list.item_edited.connect(owner._on_closures_tree_item_edited)
	var flowdocs_list: Tree = owner.get("_flowdocs_list")
	if flowdocs_list:
		flowdocs_list.item_edited.connect(owner._on_syndocs_tree_item_edited)
	var save_render_recipe: Button = owner.get("_save_render_recipe")
	if save_render_recipe:
		save_render_recipe.pressed.connect(owner._on_save_render_recipe_pressed)
	var enable_sensor_overlay: BaseButton = owner.get("_enable_sensor_overlay")
	if enable_sensor_overlay:
		owner.set("_sensor_enabled", enable_sensor_overlay.button_pressed)
		enable_sensor_overlay.toggled.connect(func(v: bool):
			owner.set("_sensor_enabled", v)
			if v:
				owner._hub.ensure_ws_connected()
				owner._hub.ws_subscribe(["sensor.", "sensor.warning"])
				owner._hub.ws_replay(5.0, ["sensor.", "sensor.warning"])
				owner._set_status("Sensor overlay enabled.")
			else:
				owner._set_status("Sensor overlay disabled.")
		)
	var snapshot_sensors: Button = owner.get("_snapshot_sensors")
	if snapshot_sensors:
		snapshot_sensors.pressed.connect(owner._on_snapshot_sensors_pressed)
	var refresh_render_jobs_btn: Button = owner.get("_refresh_render_jobs_btn")
	if refresh_render_jobs_btn:
		refresh_render_jobs_btn.pressed.connect(func(): await owner._refresh_render_jobs(100, "manual"))
	var cancel_render_job_btn: Button = owner.get("_cancel_render_job_btn")
	if cancel_render_job_btn:
		cancel_render_job_btn.pressed.connect(func(): await owner._cancel_selected_render_job())
	var retry_render_job_btn: Button = owner.get("_retry_render_job_btn")
	if retry_render_job_btn:
		retry_render_job_btn.pressed.connect(func(): await owner._retry_selected_render_job())
	var resume_render_job_btn: Button = owner.get("_resume_render_job_btn")
	if resume_render_job_btn:
		resume_render_job_btn.pressed.connect(func(): await owner._resume_selected_render_job())
	var render_jobs_list: ItemList = owner.get("_render_jobs_list")
	if render_jobs_list and not render_jobs_list.item_selected.is_connected(owner._on_render_jobs_item_selected):
		render_jobs_list.item_selected.connect(owner._on_render_jobs_item_selected)
	var build_edgeless_layout: Button = owner.get("_build_edgeless_layout")
	if build_edgeless_layout:
		build_edgeless_layout.pressed.connect(owner._on_build_edgeless_layout_pressed)
	var rebuild_edgeless_keep_edits: Button = owner.get("_rebuild_edgeless_keep_edits")
	if rebuild_edgeless_keep_edits:
		rebuild_edgeless_keep_edits.pressed.connect(owner._on_rebuild_edgeless_keep_edits_pressed)
	var reset_edgeless_view: Button = owner.get("_reset_edgeless_view")
	if reset_edgeless_view:
		reset_edgeless_view.pressed.connect(owner._on_reset_edgeless_view)
	var fit_edgeless_to_layout: Button = owner.get("_fit_edgeless_to_layout")
	if fit_edgeless_to_layout:
		fit_edgeless_to_layout.pressed.connect(owner._on_fit_edgeless_to_layout)
	var edgeless_preview: Control = owner.get("_edgeless_preview")
	if edgeless_preview:
		edgeless_preview.selection_changed.connect(owner._on_edgeless_selection_changed)
		edgeless_preview.node_moved.connect(owner._on_design_edgeless_node_moved)
		edgeless_preview.drag_ended.connect(owner._on_design_edgeless_drag_ended)
		edgeless_preview.label_changed.connect(owner._on_design_edgeless_label_changed)
		edgeless_preview.gui_input.connect(owner._on_edgeless_preview_gui_input)
	var edgeless_show_labels: BaseButton = owner.get("_edgeless_show_labels")
	if edgeless_show_labels:
		edgeless_show_labels.toggled.connect(func(v: bool):
			if owner._edgeless_preview:
				owner._edgeless_preview.set_show_labels(v)
		)
	var edgeless_edit_layout: BaseButton = owner.get("_edgeless_edit_layout")
	if edgeless_edit_layout:
		edgeless_edit_layout.toggled.connect(func(v: bool):
			if owner._edgeless_preview:
				owner._edgeless_preview.set_editable(v)
		)
	var edgeless_avoid_overlap: BaseButton = owner.get("_edgeless_avoid_overlap")
	if edgeless_avoid_overlap:
		edgeless_avoid_overlap.toggled.connect(func(v: bool):
			if owner._edgeless_preview:
				owner._edgeless_preview.set_avoid_overlap(v)
			if owner._present_edgeless_preview:
				owner._present_edgeless_preview.set_avoid_overlap(v)
		)
	var edgeless_snap: BaseButton = owner.get("_edgeless_snap")
	if edgeless_snap:
		edgeless_snap.toggled.connect(func(v: bool):
			if owner._edgeless_preview:
				owner._edgeless_preview.set_snap_enabled(v)
		)
	var edgeless_grid_size: SpinBox = owner.get("_edgeless_grid_size")
	if edgeless_grid_size:
		edgeless_grid_size.value_changed.connect(func(v: float):
			if owner._edgeless_preview:
				owner._edgeless_preview.set_grid_size(v)
		)
	var edgeless_view_style: OptionButton = owner.get("_edgeless_view_style")
	if edgeless_view_style:
		owner.call("_init_edgeless_view_style")
	var edgeless_align_to_grid: Button = owner.get("_edgeless_align_to_grid")
	if edgeless_align_to_grid:
		edgeless_align_to_grid.pressed.connect(owner._on_align_selected_to_grid)
	var edgeless_center_x: Button = owner.get("_edgeless_center_x")
	if edgeless_center_x:
		edgeless_center_x.pressed.connect(func(): owner._center_selected_axis(true))
	var edgeless_center_y: Button = owner.get("_edgeless_center_y")
	if edgeless_center_y:
		edgeless_center_y.pressed.connect(func(): owner._center_selected_axis(false))
	var edgeless_apply_label: Button = owner.get("_edgeless_apply_label")
	if edgeless_apply_label:
		edgeless_apply_label.pressed.connect(owner._on_apply_design_edgeless_label)
		edgeless_apply_label.disabled = true
	var edgeless_label_edit: LineEdit = owner.get("_edgeless_label_edit")
	if edgeless_label_edit:
		edgeless_label_edit.editable = false
		edgeless_label_edit.placeholder_text = "(click a node/cluster, then rename it here)"
	var edgeless_resize_handle: Control = owner.get("_edgeless_resize_handle")
	if edgeless_resize_handle:
		edgeless_resize_handle.gui_input.connect(owner._on_edgeless_resize_gui_input)
	var flowdoc_json_resize_handle: Control = owner.get("_flowdoc_json_resize_handle")
	if flowdoc_json_resize_handle:
		flowdoc_json_resize_handle.gui_input.connect(owner._on_flowdoc_json_resize_gui_input)
	var blocks_list: ItemList = owner.get("_blocks_list")
	if blocks_list and not blocks_list.item_selected.is_connected(owner._on_block_selected):
		blocks_list.item_selected.connect(owner._on_block_selected)
	var move_up_block: Button = owner.get("_move_up_block")
	if move_up_block:
		move_up_block.pressed.connect(func(): owner._move_block(-1))
	var move_down_block: Button = owner.get("_move_down_block")
	if move_down_block:
		move_down_block.pressed.connect(func(): owner._move_block(1))
	var delete_block: Button = owner.get("_delete_block")
	if delete_block:
		delete_block.pressed.connect(owner._delete_selected_block)
	var insert_after_block: Button = owner.get("_insert_after_block")
	if insert_after_block:
		insert_after_block.pressed.connect(owner._insert_block_after)
	var block_type: OptionButton = owner.get("_block_type")
	if block_type:
		block_type.item_selected.connect(func(_i: int): owner._on_block_edited())
	var block_text: TextEdit = owner.get("_block_text")
	if block_text:
		block_text.text_changed.connect(func(): owner._on_block_edited())
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	if flowdoc_json:
		flowdoc_json.focus_exited.connect(func(): owner._sync_from_raw_json())
	var frames_list: ItemList = owner.get("_frames_list")
	if frames_list and not frames_list.item_selected.is_connected(owner._on_frame_selected):
		frames_list.item_selected.connect(owner._on_frame_selected)
	var add_frame: Button = owner.get("_add_frame")
	if add_frame:
		add_frame.pressed.connect(owner._add_new_frame)
	var delete_frame: Button = owner.get("_delete_frame")
	if delete_frame:
		delete_frame.pressed.connect(owner._delete_selected_frame)
	var apply_frame_id: Button = owner.get("_apply_frame_id")
	if apply_frame_id:
		apply_frame_id.pressed.connect(owner._rename_selected_frame)
	var move_frame_up: Button = owner.get("_move_frame_up")
	if move_frame_up:
		move_frame_up.pressed.connect(func(): owner._move_frame(-1))
	var move_frame_down: Button = owner.get("_move_frame_down")
	if move_frame_down:
		move_frame_down.pressed.connect(func(): owner._move_frame(1))
	var move_block_to_frame: Button = owner.get("_move_block_to_frame")
	if move_block_to_frame:
		move_block_to_frame.pressed.connect(owner._move_selected_block_to_target_frame)
	var prev_frame: Button = owner.get("_prev_frame")
	if prev_frame:
		prev_frame.pressed.connect(func(): owner._select_frame_delta(-1))
	var next_frame: Button = owner.get("_next_frame")
	if next_frame:
		next_frame.pressed.connect(func(): owner._select_frame_delta(1))
	var perform_prev: Button = owner.get("_perform_prev")
	if perform_prev:
		perform_prev.pressed.connect(func(): owner._on_present_prev_next(-1))
	var perform_next: Button = owner.get("_perform_next")
	if perform_next:
		perform_next.pressed.connect(func(): owner._on_present_prev_next(1))
	var present_edgeless_preview: Control = owner.get("_present_edgeless_preview")
	if present_edgeless_preview:
		present_edgeless_preview.selection_changed.connect(owner._on_present_edgeless_selection_changed)
	if render_results and not render_results.item_activated.is_connected(owner._on_render_result_activated):
		render_results.item_activated.connect(owner._on_render_result_activated)
	var present_reset_view: Button = owner.get("_present_reset_view")
	if present_reset_view:
		present_reset_view.pressed.connect(func():
			if owner._present_edgeless_preview:
				owner._present_edgeless_preview.reset_view()
		)
	var present_show_labels: BaseButton = owner.get("_present_show_labels")
	if present_show_labels:
		present_show_labels.visible = false
		present_show_labels.button_pressed = false
		if owner._present_edgeless_preview:
			owner._present_edgeless_preview.set_show_labels(false)
	var present_prev_cluster: Button = owner.get("_present_prev_cluster")
	if present_prev_cluster:
		present_prev_cluster.pressed.connect(func(): owner._select_present_cluster_delta(-1))
	var present_next_cluster: Button = owner.get("_present_next_cluster")
	if present_next_cluster:
		present_next_cluster.pressed.connect(func(): owner._select_present_cluster_delta(1))
	var present_make_frame: Button = owner.get("_present_make_frame")
	if present_make_frame:
		present_make_frame.pressed.connect(owner._on_present_make_frame_from_cluster)
	var present_capture_camera: Button = owner.get("_present_capture_camera")
	if present_capture_camera:
		present_capture_camera.pressed.connect(owner._on_present_capture_camera)
	var present_clear_deck: Button = owner.get("_present_clear_deck")
	if present_clear_deck:
		present_clear_deck.pressed.connect(owner._on_present_clear_deck)
	var present_apply_camera: Button = owner.get("_present_apply_camera")
	if present_apply_camera:
		present_apply_camera.pressed.connect(func(): _on_apply_present_camera_pressed(owner))
	var root = owner.get("_root")
	var mode_tabs: TabContainer = (root as Node).get_node_or_null("Body/Right/ModeTabs") as TabContainer if is_instance_valid(root) else null
	if mode_tabs and not mode_tabs.tab_changed.is_connected(owner._on_mode_tabs_tab_changed):
		mode_tabs.tab_changed.connect(owner._on_mode_tabs_tab_changed)
	owner.call("_post_ready_refresh")
	owner.call("_refresh_frames_ui")
	owner.call("_refresh_blocks_ui")
	owner.call("_refresh_performer_ui")
	owner.call("_refresh_edgeless_preview")
	owner.call("_refresh_present_edgeless")
	if owner._edgeless_preview:
		if owner._edgeless_avoid_overlap:
			owner._edgeless_preview.set_avoid_overlap(owner._edgeless_avoid_overlap.button_pressed)
			if owner._present_edgeless_preview:
				owner._present_edgeless_preview.set_avoid_overlap(owner._edgeless_avoid_overlap.button_pressed)
		if owner._edgeless_snap:
			owner._edgeless_preview.set_snap_enabled(owner._edgeless_snap.button_pressed)
		if owner._edgeless_grid_size:
			owner._edgeless_preview.set_grid_size(float(owner._edgeless_grid_size.value))
		if owner._edgeless_view_style:
			owner.call("_init_edgeless_view_style")
