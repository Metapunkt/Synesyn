extends SceneTree

## Stage 12 / ADR 0013: Workshop Catalyst presence store + claim protocol
## (pure logic; no ENet required).

const PresenceStoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_presence_store.gd"
)
const FacilitatorSessionSetupScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/facilitator_session_setup.gd"
)
const WorkspaceScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_workspace_shell.tscn"
)
const PresenceControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_presence_controller.gd"
)

var _failures: Array[String] = []


class FakePresenceSync:
	extends Node
	signal presence_changed(snapshot: Dictionary)
	signal claim_rejected(reason: String)
	var _needs: bool = true

	func activate_for_workshop() -> void:
		_needs = true

	func deactivate() -> void:
		_needs = false

	func is_active() -> bool:
		return true

	func needs_facilitator() -> bool:
		return _needs

	func has_local_facilitator_claim() -> bool:
		return not _needs

	func local_peer_id() -> int:
		return 1

	func get_snapshot() -> Dictionary:
		if _needs:
			return {"facilitator_peer_id": -1, "peers": {}}
		return {
			"facilitator_peer_id": 1,
			"peers": {1: {"display_name": "Alex (Facilitator)", "is_facilitator": true}},
		}

	func get_store() -> Node:
		return self

	func get_display_name(_peer_id: int) -> String:
		return "Alex (Facilitator)"

	func emit_claimed_snapshot() -> void:
		_needs = false
		presence_changed.emit(get_snapshot())


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_claim_until_taken()
	_test_disconnect_reopens_claim()
	_test_rename_and_facilitator_format()
	_test_facilitator_identity_helpers()
	await _test_need_facilitator_dialog_present()
	_finish()


func _test_claim_until_taken() -> void:
	var store: RefCounted = PresenceStoreScript.new()
	_expect(store.needs_facilitator(), "Fresh store should need a facilitator")
	var first: Dictionary = store.try_claim_facilitator(1, "Alex")
	_expect(bool(first.get("ok", false)), "First claim should succeed")
	_expect(not store.needs_facilitator(), "Store should not need facilitator after claim")
	_expect(store.is_facilitator(1), "Peer 1 should be facilitator")
	_expect(
		store.get_display_name(1) == "Alex (Facilitator)",
		"Facilitator display name should use Name (Facilitator) form"
	)
	var second: Dictionary = store.try_claim_facilitator(2, "Blake")
	_expect(not bool(second.get("ok", false)), "Second claim should be rejected")
	_expect(String(second.get("reason", "")) == "already_claimed", "Reject reason already_claimed")
	var joined: Dictionary = store.register_participant(2, "Blake")
	_expect(bool(joined.get("ok", false)), "Participant register should succeed")
	_expect(not store.is_facilitator(2), "Participant must not be facilitator")
	_expect(store.get_display_name(2) == "Blake", "Participant keeps plain name")


func _test_disconnect_reopens_claim() -> void:
	var store: RefCounted = PresenceStoreScript.new()
	store.try_claim_facilitator(1, "Alex")
	store.register_participant(2, "Blake")
	var result: Dictionary = store.on_peer_disconnected(1)
	_expect(bool(result.get("cleared_facilitator", false)), "Disconnect should clear facilitator")
	_expect(bool(result.get("needs_facilitator", false)), "Disconnect should reopen claim")
	_expect(store.needs_facilitator(), "Store needs facilitator after host left")
	var reclaim: Dictionary = store.try_claim_facilitator(2, "Blake")
	_expect(bool(reclaim.get("ok", false)), "Remaining peer can reclaim")
	_expect(store.get_display_name(2) == "Blake (Facilitator)", "Reclaim formats name")


func _test_rename_and_facilitator_format() -> void:
	var store: RefCounted = PresenceStoreScript.new()
	store.try_claim_facilitator(1, "Alex")
	store.register_participant(2, "Blake")
	var renamed_fac: Dictionary = store.rename_peer(1, "Alexandra")
	_expect(bool(renamed_fac.get("ok", false)), "Facilitator rename should succeed")
	_expect(
		store.get_display_name(1) == "Alexandra (Facilitator)",
		"Facilitator rename keeps role suffix"
	)
	var renamed_peer: Dictionary = store.rename_peer(2, "Blake Jr")
	_expect(bool(renamed_peer.get("ok", false)), "Participant rename should succeed")
	_expect(store.get_display_name(2) == "Blake Jr", "Participant rename updates plain name")
	var snapshot: Dictionary = store.get_snapshot()
	var store_b: RefCounted = PresenceStoreScript.new()
	store_b.apply_snapshot(snapshot)
	_expect(store_b.is_facilitator(1), "Snapshot restore keeps facilitator peer")
	_expect(
		store_b.get_display_name(2) == "Blake Jr",
		"Snapshot restore keeps participant rename"
	)


func _test_facilitator_identity_helpers() -> void:
	_expect(
		FacilitatorSessionSetupScript.is_facilitator_sender("Facilitator"),
		"Literal Facilitator sender still recognized"
	)
	_expect(
		FacilitatorSessionSetupScript.is_facilitator_sender("Alex (Facilitator)"),
		"Name (Facilitator) sender recognized"
	)
	_expect(
		not FacilitatorSessionSetupScript.is_facilitator_sender("Blake"),
		"Plain participant sender is not facilitator"
	)
	var identity: Dictionary = FacilitatorSessionSetupScript.build_facilitator_identity("Alex")
	_expect(
		String(identity.get("name", "")) == "Alex (Facilitator)",
		"build_facilitator_identity formats display name"
	)


func _test_need_facilitator_dialog_present() -> void:
	var shell_node: Control = WorkspaceScene.instantiate() as Control
	root.add_child(shell_node)
	await process_frame
	# NeedFacilitatorDialog is a Control overlay on a CanvasLayer (not a
	# Window/Popup): it cannot be dismissed by an outside click or Escape, and
	# it inherits the shell's theme cascade. top_level on a VBox child pins the
	# card at (0,0) in exported builds, so the overlay must fill the viewport
	# through the CanvasLayer instead.
	var dialog_node: Control = shell_node.find_child("NeedFacilitatorDialog", true, false) as Control
	var name_edit_node: LineEdit = shell_node.find_child("NeedFacilitatorNameEdit", true, false) as LineEdit
	var claim_button_node: Button = shell_node.find_child("NeedFacilitatorClaimButton", true, false) as Button
	var join_button_node: Button = shell_node.find_child("NeedFacilitatorJoinButton", true, false) as Button
	_expect(dialog_node != null, "NeedFacilitatorDialog missing from shell")
	_expect(name_edit_node != null, "NeedFacilitatorNameEdit missing")
	_expect(claim_button_node != null, "NeedFacilitatorClaimButton missing")
	_expect(join_button_node != null, "NeedFacilitatorJoinButton missing")
	var overlay_layer: CanvasLayer = null
	if dialog_node:
		overlay_layer = dialog_node.get_parent() as CanvasLayer
	_expect(
		overlay_layer != null,
		"NeedFacilitatorDialog should live on a CanvasLayer, not as a VBox child"
	)
	_expect(
		dialog_node != null and not bool(dialog_node.top_level),
		"NeedFacilitatorDialog must not be top_level (export pins that at 0,0)"
	)
	_expect(
		dialog_node != null
		and is_equal_approx(dialog_node.anchor_right, 1.0)
		and is_equal_approx(dialog_node.anchor_bottom, 1.0),
		"NeedFacilitatorDialog should fill the viewport so Join as Participant is centered"
	)
	_expect(
		claim_button_node.theme_type_variation == "SynesynPrimaryAction",
		"Become Facilitator should use SynesynPrimaryAction theme variation"
	)
	var controller: RefCounted = PresenceControllerScript.new()
	_expect(
		controller.mount(shell_node, null),
		"Presence controller should mount against shell dialog nodes"
	)
	# Simulate claim-until-taken close path via a fake sync node.
	var fake_sync := FakePresenceSync.new()
	root.add_child(fake_sync)
	var controller_b: RefCounted = PresenceControllerScript.new()
	_expect(controller_b.mount(shell_node, fake_sync), "Presence controller mount with sync failed")
	controller_b.begin_multiplayer_session()
	await process_frame
	_expect(dialog_node.visible, "Need-facilitator dialog should open when claim is open")
	fake_sync.emit_claimed_snapshot()
	await process_frame
	_expect(not dialog_node.visible, "Need-facilitator dialog should close after claim")
	fake_sync.queue_free()
	shell_node.queue_free()
	await process_frame


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures.append(failure_message)
	push_error(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst Stage 12 presence tests: all passed")
		quit(0)
	else:
		push_error("Workshop Catalyst Stage 12 presence: %d failure(s)" % _failures.size())
		quit(1)
