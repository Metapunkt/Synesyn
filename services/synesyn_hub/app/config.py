from __future__ import annotations

import os
import json
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional
import sys

import yaml


@dataclass(frozen=True)
class WorkspaceConfig:
	name: str
	slug: str
	root: Path
	substrate_dir: Path
	artifacts_dir: Path
	exports_dir: Path
	logs_dir: Path


@dataclass(frozen=True)
class HubConfig:
	version: str
	bind_host: str
	http_port: int
	udp_port: int
	ring_buffer_size: int
	enforce_provenance: bool
	plugins_enabled: List[str]
	auth_enabled: bool
	auth_token: str
	workspace: Optional[WorkspaceConfig]
	# Optional packaging topology (v0): hub-managed voice sidecar.
	# When enabled, hub will (best-effort) start a sidecar voice server and use it for synthesis/transcription,
	# while still persisting artifacts/provenance in the hub workspace/substrate.
	voice_sidecar_enabled: bool
	voice_sidecar_url: str
	voice_sidecar_cmd: str
	voice_sidecar_args: List[str]
	voice_sidecar_cwd: str


def _default_documents_root() -> Path:
	# Windows/macOS/Linux: prefer ~/Documents
	return Path.home() / "Documents" / "Synesyn"


def _safe_slug(text: str) -> str:
	s = "".join(c.lower() if c.isalnum() else "-" for c in text.strip())
	s = "-".join(filter(None, s.split("-")))
	return s[:64] if s else "workspace"


def _ensure_dirs(*paths: Path) -> None:
	for p in paths:
		p.mkdir(parents=True, exist_ok=True)


def _workspace_state_file(base_root: Optional[Path] = None) -> Path:
	root = base_root or _default_documents_root()
	root.mkdir(parents=True, exist_ok=True)
	return (root / "_current_workspace.json").resolve()


def _load_persisted_workspace() -> Optional[dict]:
	"""
	Load last selected workspace saved by Godot via `POST /workspace/select`.
	Returns dict with keys: name, slug, root.
	"""
	try:
		path = _workspace_state_file()
		if not path.exists():
			return None
		obj = json.loads(path.read_text(encoding="utf-8"))
		if not isinstance(obj, dict):
			return None
		if not obj.get("name"):
			return None
		# Normalize root semantics:
		# - In hub config loading, SYNESYN_WORKSPACE_ROOT is a *base root* folder.
		# - Older persisted files stored root as the *workspace root* (base_root/slug),
		#   which caused double-slug paths on restart. Fix that here.
		name = str(obj.get("name")).strip()
		slug = str(obj.get("slug") or _safe_slug(name)).strip()

		root_raw = str(obj.get("root") or "").strip()
		ws_root_raw = str(obj.get("workspace_root") or "").strip()

		# Prefer the explicit base root if present; otherwise infer.
		root_str = root_raw or ws_root_raw
		if root_str:
			p = Path(root_str).expanduser()
			try:
				# If persisted path ends with /<slug> (or /<slug>/<slug>), treat it as workspace-root.
				if p.name == slug:
					base_root = p.parent
					if base_root.name == slug:
						base_root = base_root.parent
				else:
					base_root = p
				obj["root"] = str(base_root.resolve())
			except Exception:
				obj["root"] = str(p)
		obj["slug"] = slug
		obj["name"] = name
		return obj
	except Exception:
		return None


def load_config() -> HubConfig:
	"""
	Load hub config from `app/config.yaml` (optional) + environment variables.

	Workspace selection is typically provided by Godot on first run; for dev you can set:
	- SYNESYN_WORKSPACE_NAME
	- SYNESYN_WORKSPACE_SLUG
	- SYNESYN_WORKSPACE_ROOT (optional override)
	"""
	# Config resolution:
	# - dev: app/config.yaml next to this file
	# - packaged: config.yaml next to the exe (or override via SYNESYN_HUB_CONFIG)
	override = os.environ.get("SYNESYN_HUB_CONFIG") or ""
	cfg_path: Optional[Path] = None
	if override.strip():
		cfg_path = Path(override).expanduser().resolve()
	else:
		here = Path(__file__).resolve().parent
		candidate = here / "config.yaml"
		if candidate.exists():
			cfg_path = candidate
		elif getattr(sys, "frozen", False):
			exe_dir = Path(sys.executable).resolve().parent
			candidate2 = exe_dir / "config.yaml"
			if candidate2.exists():
				cfg_path = candidate2
	raw = {}
	if cfg_path and cfg_path.exists():
		raw = yaml.safe_load(cfg_path.read_text(encoding="utf-8")) or {}

	version = str(raw.get("version", "0.1.0"))
	bind_host = str(raw.get("bind_host", os.environ.get("SYNESYN_BIND_HOST", "127.0.0.1")))
	http_port = int(raw.get("http_port", os.environ.get("SYNESYN_HTTP_PORT", 17777)))
	udp_port = int(raw.get("udp_port", os.environ.get("SYNESYN_UDP_PORT", 5000)))
	ring_buffer_size = int(raw.get("ring_buffer_size", os.environ.get("SYNESYN_RING_BUFFER_SIZE", 2048)))
	enforce_provenance_raw = raw.get("enforce_provenance", os.environ.get("SYNESYN_ENFORCE_PROVENANCE", "true"))
	enforce_provenance = str(enforce_provenance_raw).strip().lower() not in {"0", "false", "no", "off"}

	plugins_enabled_any = raw.get("plugins_enabled", os.environ.get("SYNESYN_PLUGINS_ENABLED", "")) or []
	if isinstance(plugins_enabled_any, str):
		plugins_enabled = [p.strip() for p in plugins_enabled_any.split(",") if p.strip()]
	elif isinstance(plugins_enabled_any, list):
		plugins_enabled = [str(p).strip() for p in plugins_enabled_any if str(p).strip()]
	else:
		plugins_enabled = []

	auth_enabled_raw = raw.get("auth_enabled", os.environ.get("SYNESYN_AUTH_ENABLED", "false"))
	auth_enabled = str(auth_enabled_raw).strip().lower() in {"1", "true", "yes", "on"}
	auth_token = str(raw.get("auth_token", os.environ.get("SYNESYN_AUTH_TOKEN", "")) or "").strip()

	# Voice sidecar config (optional). Supports both YAML and env overrides.
	vs_enabled_raw = raw.get("voice_sidecar_enabled", os.environ.get("SYNESYN_VOICE_SIDECAR_ENABLED", "false"))
	voice_sidecar_enabled = str(vs_enabled_raw).strip().lower() in {"1", "true", "yes", "on"}
	voice_sidecar_url = str(raw.get("voice_sidecar_url", os.environ.get("SYNESYN_VOICE_SIDECAR_URL", "http://127.0.0.1:8765")) or "").strip()
	voice_sidecar_cmd = str(raw.get("voice_sidecar_cmd", os.environ.get("SYNESYN_VOICE_SIDECAR_CMD", "")) or "").strip()
	voice_sidecar_args_any = raw.get("voice_sidecar_args", os.environ.get("SYNESYN_VOICE_SIDECAR_ARGS", "")) or []
	if isinstance(voice_sidecar_args_any, str):
		voice_sidecar_args = [p.strip() for p in voice_sidecar_args_any.split(",") if p.strip()]
	elif isinstance(voice_sidecar_args_any, list):
		voice_sidecar_args = [str(p).strip() for p in voice_sidecar_args_any if str(p).strip()]
	else:
		voice_sidecar_args = []
	voice_sidecar_cwd = str(raw.get("voice_sidecar_cwd", os.environ.get("SYNESYN_VOICE_SIDECAR_CWD", "")) or "").strip()

	ws_name = os.environ.get("SYNESYN_WORKSPACE_NAME") or raw.get("workspace_name")
	ws_slug = os.environ.get("SYNESYN_WORKSPACE_SLUG") or raw.get("workspace_slug")
	ws_root_override = os.environ.get("SYNESYN_WORKSPACE_ROOT") or raw.get("workspace_root")

	if not ws_name:
		persisted = _load_persisted_workspace()
		if persisted:
			ws_name = persisted.get("name")
			ws_slug = persisted.get("slug")
			ws_root_override = persisted.get("root")

	workspace: Optional[WorkspaceConfig] = None
	if ws_name:
		name = str(ws_name)
		slug = str(ws_slug) if ws_slug else _safe_slug(name)
		base_root = Path(ws_root_override).expanduser() if ws_root_override else _default_documents_root()
		root = (base_root / slug).resolve()

		substrate_dir = root / "substrate"
		artifacts_dir = root / "artifacts"
		exports_dir = root / "exports"
		logs_dir = root / "logs"
		_ensure_dirs(root, substrate_dir, artifacts_dir, exports_dir, logs_dir)

		workspace = WorkspaceConfig(
			name=name,
			slug=slug,
			root=root,
			substrate_dir=substrate_dir,
			artifacts_dir=artifacts_dir,
			exports_dir=exports_dir,
			logs_dir=logs_dir,
		)

	return HubConfig(
		version=version,
		bind_host=bind_host,
		http_port=http_port,
		udp_port=udp_port,
		ring_buffer_size=ring_buffer_size,
		enforce_provenance=enforce_provenance,
		plugins_enabled=plugins_enabled,
		auth_enabled=auth_enabled,
		auth_token=auth_token,
		workspace=workspace,
		voice_sidecar_enabled=voice_sidecar_enabled,
		voice_sidecar_url=voice_sidecar_url,
		voice_sidecar_cmd=voice_sidecar_cmd,
		voice_sidecar_args=voice_sidecar_args,
		voice_sidecar_cwd=voice_sidecar_cwd,
	)


