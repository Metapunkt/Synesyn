extends RefCounted
class_name WorkshopPresenceController

## Mounts the Need-Facilitator / rename UI and keeps ParticipantsPanel labels
## in sync with WorkshopPresenceSync (ADR 0013).

const FacilitatorSessionSetupScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/facilitator_session_setup.gd"
)
const PresenceStoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_presence_store.gd"
)

signal facilitator_authority_changed(has_claim: bool)

var _shell_root_node: Control
var _presence_sync: Node
var _is_multiplayer_workshop: bool = false


func mount(shell_root_node: Control, presence_sync: Node) -> bool:
	if not shell_root_node:
		return false
	_shell_root_node = shell_root_node
	_presence_sync = presence_sync
	# NeedFacilitatorDialog is a Control overlay on ModalOverlayLayer (not a
	# Window/Popup): it cannot be dismissed by clicking outside or pressing
	# Escape, inherits the shell theme cascade, and fills the viewport even
	# when the shell itself is a VBoxContainer (exported builds used to pin
	# a top_level Control at (0,0) with card-sized layout).
	var dialog_node: Control = _find_node("NeedFacilitatorDialog") as Control
	var name_edit_node: LineEdit = _find_control("NeedFacilitatorNameEdit") as LineEdit
	var claim_button_node: Button = _find_control("NeedFacilitatorClaimButton") as Button
	var join_button_node: Button = _find_control("NeedFacilitatorJoinButton") as Button
	var rename_button_node: Button = _find_control("PresenceRenameButton") as Button
	if (
		not dialog_node
		or not name_edit_node
		or not claim_button_node
		or not join_button_node
	):
		return false
	if not claim_button_node.pressed.is_connected(_on_claim_pressed):
		claim_button_node.pressed.connect(_on_claim_pressed)
	if not join_button_node.pressed.is_connected(_on_join_as_participant_pressed):
		join_button_node.pressed.connect(_on_join_as_participant_pressed)
	if rename_button_node and not rename_button_node.pressed.is_connected(_on_rename_pressed):
		rename_button_node.pressed.connect(_on_rename_pressed)
	if _presence_sync and _presence_sync.has_signal("presence_changed"):
		if not _presence_sync.presence_changed.is_connected(_on_presence_changed):
			_presence_sync.presence_changed.connect(_on_presence_changed)
	if _presence_sync and _presence_sync.has_signal("claim_rejected"):
		if not _presence_sync.claim_rejected.is_connected(_on_claim_rejected):
			_presence_sync.claim_rejected.connect(_on_claim_rejected)
	var viewport: Viewport = _shell_root_node.get_viewport()
	if viewport and not viewport.size_changed.is_connected(_on_overlay_viewport_size_changed):
		viewport.size_changed.connect(_on_overlay_viewport_size_changed)
	return true


func begin_multiplayer_session() -> void:
	_is_multiplayer_workshop = true
	if _presence_sync and _presence_sync.has_method("activate_for_workshop"):
		_presence_sync.call("activate_for_workshop")
	_refresh_presence_labels()
	_show_need_facilitator_dialog_if_needed()


func begin_single_player_session() -> void:
	_is_multiplayer_workshop = false
	if _presence_sync and _presence_sync.has_method("deactivate"):
		_presence_sync.call("deactivate")
	_hide_need_facilitator_dialog()
	_refresh_presence_labels()
	facilitator_authority_changed.emit(true)


func has_local_facilitator_claim() -> bool:
	if not _is_multiplayer_workshop or not _presence_sync:
		return true
	return bool(_presence_sync.call("has_local_facilitator_claim"))


func _on_presence_changed(snapshot: Dictionary) -> void:
	_apply_local_identity_from_snapshot(snapshot)
	_refresh_presence_labels()
	var needs: bool = true
	if _presence_sync and _presence_sync.has_method("needs_facilitator"):
		needs = bool(_presence_sync.call("needs_facilitator"))
	if needs:
		_show_need_facilitator_dialog_if_needed()
	else:
		_hide_need_facilitator_dialog()
	facilitator_authority_changed.emit(has_local_facilitator_claim())


func _on_claim_rejected(reason: String) -> void:
	var status_node: Label = _find_control("NeedFacilitatorStatusLabel") as Label
	if status_node:
		if reason == "already_claimed":
			status_node.text = "Someone else claimed Facilitator. Join as a participant."
		elif reason == "name_required":
			status_node.text = "Enter a display name first."
		else:
			status_node.text = "Could not update presence (%s)." % reason
	_show_need_facilitator_dialog_if_needed()


func _on_claim_pressed() -> void:
	var name_edit_node: LineEdit = _find_control("NeedFacilitatorNameEdit") as LineEdit
	if not name_edit_node or not _presence_sync:
		return
	var display_name: String = name_edit_node.text.strip_edges()
	if display_name.is_empty():
		_on_claim_rejected("name_required")
		return
	_presence_sync.call("request_claim", display_name)


func _on_join_as_participant_pressed() -> void:
	var name_edit_node: LineEdit = _find_control("NeedFacilitatorNameEdit") as LineEdit
	if not name_edit_node or not _presence_sync:
		return
	var display_name: String = name_edit_node.text.strip_edges()
	if display_name.is_empty():
		_on_claim_rejected("name_required")
		return
	_presence_sync.call("request_register", display_name)
	var status_node: Label = _find_control("NeedFacilitatorStatusLabel") as Label
	if status_node and _presence_sync.call("needs_facilitator"):
		status_node.text = (
			"Joined as %s. Waiting for someone to claim Facilitator…" % display_name
		)


func _on_rename_pressed() -> void:
	var name_edit_node: LineEdit = _find_control("NeedFacilitatorNameEdit") as LineEdit
	if not name_edit_node or not _presence_sync:
		return
	var display_name: String = name_edit_node.text.strip_edges()
	if display_name.is_empty():
		_on_claim_rejected("name_required")
		return
	_presence_sync.call("request_rename", display_name)


func _show_need_facilitator_dialog_if_needed() -> void:
	if not _is_multiplayer_workshop:
		return
	if not _presence_sync or not bool(_presence_sync.call("needs_facilitator")):
		return
	var dialog_node: Control = _find_node("NeedFacilitatorDialog") as Control
	if not dialog_node:
		return
	var claim_button_node: Button = _find_control("NeedFacilitatorClaimButton") as Button
	if claim_button_node:
		claim_button_node.disabled = false
	dialog_node.visible = true
	fit_viewport_overlay(dialog_node)
	dialog_node.call_deferred("set_anchors_and_offsets_preset", Control.PRESET_FULL_RECT)


func _on_overlay_viewport_size_changed() -> void:
	var dialog_node: Control = _find_node("NeedFacilitatorDialog") as Control
	if dialog_node and dialog_node.visible:
		fit_viewport_overlay(dialog_node)
	var sessions_node: Control = _find_node("MySessionsDialog") as Control
	if sessions_node and sessions_node.visible:
		fit_viewport_overlay(sessions_node)


static func fit_viewport_overlay(dialog_node: Control) -> void:
	if dialog_node == null:
		return
	dialog_node.top_level = false
	dialog_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var viewport: Viewport = dialog_node.get_viewport()
	if viewport == null:
		return
	var view_size: Vector2 = viewport.get_visible_rect().size
	dialog_node.position = Vector2.ZERO
	dialog_node.size = view_size


func _hide_need_facilitator_dialog() -> void:
	var dialog_node: Control = _find_node("NeedFacilitatorDialog") as Control
	if dialog_node:
		dialog_node.visible = false


func _apply_local_identity_from_snapshot(snapshot: Dictionary) -> void:
	if not _presence_sync:
		return
	var local_id: int = int(_presence_sync.call("local_peer_id"))
	var peers_any: Variant = snapshot.get("peers", {})
	if typeof(peers_any) != TYPE_DICTIONARY:
		return
	var peers: Dictionary = peers_any
	var entry_any: Variant = peers.get(local_id, peers.get(str(local_id), {}))
	if typeof(entry_any) != TYPE_DICTIONARY:
		return
	var entry: Dictionary = entry_any
	var display_name: String = String(entry.get("display_name", "")).strip_edges()
	if display_name.is_empty():
		return
	var is_fac: bool = bool(entry.get("is_facilitator", false))
	var global_node: Node = _autoload_node("Global")
	var story_state_node: Node = _autoload_node("StoryState")
	if is_fac:
		FacilitatorSessionSetupScript.apply_facilitator(
			global_node,
			story_state_node,
			PresenceStoreScript.base_name_from_display(display_name)
		)
	else:
		FacilitatorSessionSetupScript.apply_participant(
			global_node, story_state_node, display_name
		)
	_update_character_label(display_name)


func _update_character_label(display_name: String) -> void:
	if not _shell_root_node:
		return
	var scene_tree: SceneTree = _shell_root_node.get_tree()
	if not scene_tree:
		return
	var game_session_node: Node = scene_tree.get_first_node_in_group("game_session")
	if not game_session_node:
		return
	var label_node: Label = game_session_node.get_node_or_null("%CharacterLabel") as Label
	if label_node:
		label_node.text = display_name


func _refresh_presence_labels() -> void:
	var facilitator_name_node: Label = _find_control("FacilitatorName") as Label
	var participants_status_node: Label = _find_control("ParticipantsStatus") as Label
	if not facilitator_name_node:
		return
	if not _is_multiplayer_workshop or not _presence_sync:
		facilitator_name_node.text = "Facilitator · Present on this device"
		if participants_status_node:
			participants_status_node.visible = false
		return
	var snapshot: Dictionary = _presence_sync.call("get_snapshot")
	var peers_any: Variant = snapshot.get("peers", {})
	var peers: Dictionary = peers_any if typeof(peers_any) == TYPE_DICTIONARY else {}
	var facilitator_id: int = int(snapshot.get("facilitator_peer_id", -1))
	if facilitator_id < 0:
		facilitator_name_node.text = "Facilitator · Needed"
	else:
		var fac_entry_any: Variant = peers.get(facilitator_id, peers.get(str(facilitator_id), {}))
		var fac_name: String = "Facilitator"
		if typeof(fac_entry_any) == TYPE_DICTIONARY:
			fac_name = String((fac_entry_any as Dictionary).get("display_name", fac_name))
		facilitator_name_node.text = fac_name
	if participants_status_node:
		var names: Array[String] = []
		for peer_id_any: Variant in peers.keys():
			var entry_any: Variant = peers[peer_id_any]
			if typeof(entry_any) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_any
			if bool(entry.get("is_facilitator", false)):
				continue
			var peer_name: String = String(entry.get("display_name", "")).strip_edges()
			if not peer_name.is_empty():
				names.append(peer_name)
		if names.is_empty():
			participants_status_node.text = "Participants: none yet"
		else:
			participants_status_node.text = "Participants: " + ", ".join(names)
		participants_status_node.visible = true


func _find_control(control_id: String) -> Control:
	return _find_node(control_id) as Control


func _find_node(node_id: String) -> Node:
	if not _shell_root_node:
		return null
	return _shell_root_node.find_child(node_id, true, false)


func _autoload_node(autoload_name: String) -> Node:
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not scene_tree or not scene_tree.root:
		return null
	return scene_tree.root.get_node_or_null(autoload_name)
