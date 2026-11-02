extends Node
class_name WorkshopPresenceSync

## Network-facing presence sync for Workshop Catalyst (ADR 0013).
## Mounted as a child of the Network autoload so both peers share a stable path
## for RPCs. Story Catalyst never activates this node.

signal presence_changed(snapshot: Dictionary)
signal claim_rejected(reason: String)

const PresenceStoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_presence_store.gd"
)

var _store: RefCounted = PresenceStoreScript.new()
var _active: bool = false


func activate_for_workshop() -> void:
	_active = true
	_store.reset()


func deactivate() -> void:
	_active = false
	_store.reset()


func is_active() -> bool:
	return _active


func get_store() -> RefCounted:
	return _store


func get_snapshot() -> Dictionary:
	return _store.get_snapshot()


func needs_facilitator() -> bool:
	return _store.needs_facilitator()


func local_peer_id() -> int:
	if not multiplayer or not multiplayer.multiplayer_peer:
		return 1
	return multiplayer.get_unique_id()


func has_local_facilitator_claim() -> bool:
	if not _active:
		# Single-player Workshop: local peer is always facilitator.
		return true
	return _store.is_facilitator(local_peer_id())


func local_display_name() -> String:
	var named: String = _store.get_display_name(local_peer_id())
	if not named.is_empty():
		return named
	return "Participant"


func request_register(display_name: String) -> void:
	if not _active:
		return
	if _is_host():
		_host_register(local_peer_id(), display_name)
	else:
		rpc_id(1, "rpc_request_register", display_name)


func request_claim(display_name: String) -> void:
	if not _active:
		return
	if _is_host():
		_host_claim(local_peer_id(), display_name)
	else:
		rpc_id(1, "rpc_request_claim", display_name)


func request_rename(display_name: String) -> void:
	if not _active:
		return
	if _is_host():
		_host_rename(local_peer_id(), display_name)
	else:
		rpc_id(1, "rpc_request_rename", display_name)


func notify_peer_disconnected(peer_id: int) -> void:
	if not _active or not _is_host():
		return
	var result: Dictionary = _store.on_peer_disconnected(peer_id)
	_broadcast_snapshot()
	if bool(result.get("needs_facilitator", false)):
		presence_changed.emit(_store.get_snapshot())


func _is_host() -> bool:
	var network_node: Node = get_parent()
	if network_node and network_node.has_method("is_server"):
		return bool(network_node.call("is_server"))
	return multiplayer.is_server() if multiplayer else true


@rpc("any_peer", "reliable")
func rpc_request_register(display_name: String) -> void:
	if not _active or not _is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_host_register(sender_id, display_name)


@rpc("any_peer", "reliable")
func rpc_request_claim(display_name: String) -> void:
	if not _active or not _is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_host_claim(sender_id, display_name)


@rpc("any_peer", "reliable")
func rpc_request_rename(display_name: String) -> void:
	if not _active or not _is_host():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_host_rename(sender_id, display_name)


@rpc("authority", "reliable")
func rpc_sync_presence(snapshot: Dictionary) -> void:
	if not _active:
		return
	_store.apply_snapshot(snapshot)
	presence_changed.emit(_store.get_snapshot())


@rpc("authority", "reliable")
func rpc_claim_rejected(reason: String) -> void:
	claim_rejected.emit(reason)


func _host_register(peer_id: int, display_name: String) -> void:
	var result: Dictionary = _store.register_participant(peer_id, display_name)
	if not bool(result.get("ok", false)):
		_notify_rejected(peer_id, String(result.get("reason", "rejected")))
		return
	_broadcast_snapshot()


func _host_claim(peer_id: int, display_name: String) -> void:
	var result: Dictionary = _store.try_claim_facilitator(peer_id, display_name)
	if not bool(result.get("ok", false)):
		_notify_rejected(peer_id, String(result.get("reason", "rejected")))
		return
	_broadcast_snapshot()


func _host_rename(peer_id: int, display_name: String) -> void:
	var result: Dictionary = _store.rename_peer(peer_id, display_name)
	if not bool(result.get("ok", false)):
		_notify_rejected(peer_id, String(result.get("reason", "rejected")))
		return
	_broadcast_snapshot()


func _notify_rejected(peer_id: int, reason: String) -> void:
	if peer_id == local_peer_id():
		claim_rejected.emit(reason)
		return
	rpc_id(peer_id, "rpc_claim_rejected", reason)


func _broadcast_snapshot() -> void:
	var snapshot: Dictionary = _store.get_snapshot()
	# Emit locally first — Godot "authority" RPCs do not always call_local on the
	# host the way callers expect, which left the claim dialog stuck open.
	presence_changed.emit(snapshot)
	if multiplayer and multiplayer.multiplayer_peer:
		rpc("rpc_sync_presence", snapshot)
