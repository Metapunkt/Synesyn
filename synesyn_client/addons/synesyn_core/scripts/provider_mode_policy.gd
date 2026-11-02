## Purpose: Shared provider-mode policy (single interpretation of user://synesyn_client.json)
##
## v1 goal: avoid per-app drift when interpreting provider modes (hub/local/BYO/hosted).
## Today we primarily standardize:
## - hub base URL resolution (cfg.hub.base_url with back-compat to cfg.voice.hub_url)
## - voice provider mode ("hub" | "direct") normalization
extends RefCounted
class_name ProviderModePolicy

static func _as_dict(v: Variant) -> Dictionary:
	return v as Dictionary if typeof(v) == TYPE_DICTIONARY else {}

static func _normalize_url(url: String, default_url: String) -> String:
	var u := String(url).strip_edges()
	if u.is_empty():
		u = String(default_url).strip_edges()
	if u.is_empty():
		u = "http://127.0.0.1:17777"

	# Be forgiving: allow "127.0.0.1:17777" or "localhost:17777".
	if u.find("://") == -1:
		u = "http://" + u

	# Windows/Godot can prefer IPv6 for "localhost" and fail to fall back when
	# the hub only binds IPv4 (127.0.0.1). Normalize localhost and loopback IPv6.
	var lower := u.to_lower()
	if lower.begins_with("http://localhost"):
		u = "http://127.0.0.1" + u.substr("http://localhost".length())
	elif lower.begins_with("https://localhost"):
		u = "https://127.0.0.1" + u.substr("https://localhost".length())
	elif lower.begins_with("http://[::1]"):
		u = "http://127.0.0.1" + u.substr("http://[::1]".length())
	elif lower.begins_with("https://[::1]"):
		u = "https://127.0.0.1" + u.substr("https://[::1]".length())
	return u

static func _norm_mode(s: String) -> String:
	var m := String(s).strip_edges().to_lower()
	if m in ["hub", "hosted"]:
		return "hub"
	if m in ["direct", "local", "byo", "self", "self_hosted"]:
		return "direct"
	return m

static func get_hub_base_url(cfg: Dictionary) -> String:
	# Canonical hub URL location.
	var hub_cfg := _as_dict(cfg.get("hub", {}))
	var base_url := String(hub_cfg.get("base_url", "")).strip_edges()
	if not base_url.is_empty():
		return _normalize_url(base_url, "http://127.0.0.1:17777")

	# Back-compat: older configs may only set voice.hub_url.
	var voice_cfg := _as_dict(cfg.get("voice", {}))
	base_url = String(voice_cfg.get("hub_url", "")).strip_edges()
	if not base_url.is_empty():
		return _normalize_url(base_url, "http://127.0.0.1:17777")

	return _normalize_url("", "http://127.0.0.1:17777")

static func get_voice_provider_mode(cfg: Dictionary) -> String:
	var voice_cfg := _as_dict(cfg.get("voice", {}))
	return _norm_mode(String(voice_cfg.get("provider_mode", "direct")))

static func get_voice_service_url(cfg: Dictionary) -> String:
	var voice_cfg := _as_dict(cfg.get("voice", {}))
	var url := String(voice_cfg.get("service_url", "")).strip_edges()
	if url.is_empty():
		url = "http://127.0.0.1:8000"
	return url

static func get_voice_hub_url(cfg: Dictionary) -> String:
	# Prefer canonical hub base URL.
	return get_hub_base_url(cfg)

static func get_voice_save_recordings(cfg: Dictionary) -> bool:
	var voice_cfg := _as_dict(cfg.get("voice", {}))
	return bool(voice_cfg.get("save_recordings", false))

static func get_voice_hub_tts_provider_preference(cfg: Dictionary) -> String:
	var voice_cfg := _as_dict(cfg.get("voice", {}))
	var pref := String(voice_cfg.get("hub_tts_provider_preference", "auto")).strip_edges().to_lower()
	if pref in ["", "auto"]:
		return "auto"
	if pref in ["edge", "edge_tts", "edgetts"]:
		return "edge_tts"
	if pref in ["sapi", "pyttsx3"]:
		return "sapi"
	if pref in ["sidecar", "voice_sidecar"]:
		return "sidecar"
	return "auto"


