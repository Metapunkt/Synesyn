extends RefCounted
class_name WorkshopPresenceStore

## Pure presence + facilitator-claim state for Workshop Catalyst multi-instance
## sessions (ADR 0013). No Network / Node dependencies — host applies mutations
## then broadcasts get_snapshot() to peers.

const NO_FACILITATOR_PEER_ID := -1


var _peers: Dictionary = {}  # peer_id (int) -> {display_name, is_facilitator}
var _facilitator_peer_id: int = NO_FACILITATOR_PEER_ID


func reset() -> void:
	_peers.clear()
	_facilitator_peer_id = NO_FACILITATOR_PEER_ID


func get_snapshot() -> Dictionary:
	var peers_out: Dictionary = {}
	for peer_id_any: Variant in _peers.keys():
		var peer_id: int = int(peer_id_any)
		var entry_any: Variant = _peers[peer_id]
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		peers_out[peer_id] = (entry_any as Dictionary).duplicate(true)
	return {
		"facilitator_peer_id": _facilitator_peer_id,
		"peers": peers_out,
	}


func apply_snapshot(snapshot: Dictionary) -> void:
	_peers.clear()
	_facilitator_peer_id = int(snapshot.get("facilitator_peer_id", NO_FACILITATOR_PEER_ID))
	var peers_any: Variant = snapshot.get("peers", {})
	if typeof(peers_any) != TYPE_DICTIONARY:
		return
	var peers_in: Dictionary = peers_any
	for peer_id_any: Variant in peers_in.keys():
		var peer_id: int = int(peer_id_any)
		var entry_any: Variant = peers_in[peer_id_any]
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		_peers[peer_id] = {
			"display_name": String(entry.get("display_name", "")).strip_edges(),
			"is_facilitator": bool(entry.get("is_facilitator", false)),
		}


func needs_facilitator() -> bool:
	return _facilitator_peer_id == NO_FACILITATOR_PEER_ID


func get_facilitator_peer_id() -> int:
	return _facilitator_peer_id


func get_peer(peer_id: int) -> Dictionary:
	var entry_any: Variant = _peers.get(peer_id, {})
	if typeof(entry_any) != TYPE_DICTIONARY:
		return {}
	return (entry_any as Dictionary).duplicate(true)


func get_display_name(peer_id: int) -> String:
	var entry: Dictionary = get_peer(peer_id)
	return String(entry.get("display_name", "")).strip_edges()


func is_facilitator(peer_id: int) -> bool:
	return _facilitator_peer_id == peer_id and peer_id != NO_FACILITATOR_PEER_ID


func list_peers() -> Array[Dictionary]:
	var listed: Array[Dictionary] = []
	for peer_id_any: Variant in _peers.keys():
		var peer_id: int = int(peer_id_any)
		var entry: Dictionary = get_peer(peer_id)
		if entry.is_empty():
			continue
		listed.append({
			"peer_id": peer_id,
			"display_name": String(entry.get("display_name", "")),
			"is_facilitator": bool(entry.get("is_facilitator", false)),
		})
	listed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("peer_id", 0)) < int(b.get("peer_id", 0))
	)
	return listed


## Registers or updates a participant without claiming facilitator.
func register_participant(peer_id: int, display_name: String) -> Dictionary:
	var clean_name: String = display_name.strip_edges()
	if peer_id < 0 or clean_name.is_empty():
		return {"ok": false, "reason": "name_required"}
	var was_facilitator: bool = is_facilitator(peer_id)
	_peers[peer_id] = {
		"display_name": clean_name,
		"is_facilitator": was_facilitator,
	}
	return {"ok": true, "reason": ""}


## Host-authoritative claim. First successful claim wins; others are rejected.
func try_claim_facilitator(peer_id: int, display_name: String) -> Dictionary:
	var clean_name: String = display_name.strip_edges()
	if peer_id < 0 or clean_name.is_empty():
		return {"ok": false, "reason": "name_required"}
	if not needs_facilitator() and _facilitator_peer_id != peer_id:
		return {"ok": false, "reason": "already_claimed"}
	_peers[peer_id] = {
		"display_name": format_facilitator_display_name(clean_name),
		"is_facilitator": true,
	}
	_facilitator_peer_id = peer_id
	# Clear facilitator flag on any stale peer entry.
	for other_id_any: Variant in _peers.keys():
		var other_id: int = int(other_id_any)
		if other_id == peer_id:
			continue
		var other_any: Variant = _peers[other_id]
		if typeof(other_any) != TYPE_DICTIONARY:
			continue
		var other_entry: Dictionary = (other_any as Dictionary).duplicate(true)
		other_entry["is_facilitator"] = false
		_peers[other_id] = other_entry
	return {"ok": true, "reason": ""}


func rename_peer(peer_id: int, display_name: String) -> Dictionary:
	var clean_name: String = display_name.strip_edges()
	if peer_id < 0 or clean_name.is_empty():
		return {"ok": false, "reason": "name_required"}
	if not _peers.has(peer_id):
		return {"ok": false, "reason": "unknown_peer"}
	var entry: Dictionary = get_peer(peer_id)
	if bool(entry.get("is_facilitator", false)):
		entry["display_name"] = format_facilitator_display_name(clean_name)
	else:
		entry["display_name"] = clean_name
	_peers[peer_id] = entry
	return {"ok": true, "reason": ""}


## Clears facilitator if that peer disconnected; peer row is removed.
func on_peer_disconnected(peer_id: int) -> Dictionary:
	var cleared_facilitator: bool = is_facilitator(peer_id)
	_peers.erase(peer_id)
	if cleared_facilitator:
		_facilitator_peer_id = NO_FACILITATOR_PEER_ID
	return {
		"ok": true,
		"cleared_facilitator": cleared_facilitator,
		"needs_facilitator": needs_facilitator(),
	}


static func format_facilitator_display_name(base_name: String) -> String:
	var clean_name: String = base_name.strip_edges()
	if clean_name.is_empty():
		return "Facilitator"
	if clean_name.ends_with("(Facilitator)"):
		return clean_name
	if clean_name == "Facilitator":
		return clean_name
	return "%s (Facilitator)" % clean_name


static func base_name_from_display(display_name: String) -> String:
	var clean_name: String = display_name.strip_edges()
	var suffix: String = " (Facilitator)"
	if clean_name.ends_with(suffix):
		return clean_name.substr(0, clean_name.length() - suffix.length()).strip_edges()
	return clean_name
