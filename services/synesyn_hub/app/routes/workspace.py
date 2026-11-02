from __future__ import annotations

import json
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..config import HubConfig, WorkspaceConfig, _default_documents_root, _ensure_dirs, _safe_slug
from ..substrate.db import Substrate
from ..substrate.repo import SubstrateRepo


router = APIRouter()


def _workspace_state_file(base_root: Optional[Path] = None) -> Path:
	root = base_root or _default_documents_root()
	root.mkdir(parents=True, exist_ok=True)
	return (root / "_current_workspace.json").resolve()


def _persist_workspace_selection(ws: WorkspaceConfig) -> None:
	# Persist selection for next hub start.
	#
	# IMPORTANT:
	# - We persist in the default Documents/Synesyn folder so the hub can always find it,
	#   regardless of which base root the workspace uses.
	# - We persist "root" as the *base root* (folder that contains the slug),
	#   because hub config loading expects SYNESYN_WORKSPACE_ROOT to be a base folder.
	base_root = ws.root.parent
	obj = {
		"name": ws.name,
		"slug": ws.slug,
		"root": str(base_root),
		"workspace_root": str(ws.root),
	}

	# Global state file (authoritative)
	_workspace_state_file().write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
	# Local copy next to the workspace (best-effort convenience)
	try:
		_workspace_state_file(base_root).write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
	except Exception:
		pass


class WorkspaceSelectRequest(BaseModel):
	name: str
	slug: Optional[str] = None
	# Optional override base folder: if not set, uses ~/Documents/Synesyn/<slug>/
	root: Optional[str] = None


@router.get("")
async def get_workspace(request: Request):
	cfg: HubConfig = request.app.state.cfg
	ws = cfg.workspace
	return {
		"ok": True,
		"workspace": {
			"name": ws.name if ws else None,
			"slug": ws.slug if ws else None,
			"root": str(ws.root) if ws else None,
		},
	}


@router.post("/select")
async def select_workspace(payload: WorkspaceSelectRequest, request: Request):
	"""
	Select (and persist) the workspace. This is intended for Godot to call on first-run.
	v0 behavior: applies immediately (re-inits substrate) and persists for next start.
	"""
	if not payload.name.strip():
		raise HTTPException(status_code=400, detail="Workspace name is empty")

	name = payload.name.strip()
	slug = payload.slug.strip() if payload.slug and payload.slug.strip() else _safe_slug(name)

	if payload.root and payload.root.strip():
		# Accept either:
		# - base root folder (recommended): <base_root> -> <base_root>/<slug>/
		# - full workspace root (tolerated): <base_root>/<slug>/
		root_in = Path(payload.root).expanduser().resolve()
		if root_in.name == slug:
			root = root_in
		else:
			root = (root_in / slug).resolve()
	else:
		root = (_default_documents_root() / slug).resolve()

	# Harden against accidental "double-slug" roots like .../<slug>/<slug>.
	# This can happen if a client stores a workspace root and then appends the slug again on re-select,
	# or if a user manually pastes a root that already includes the slug into a UI that also applies it.
	# Normalize so the workspace root is stable and predictable.
	try:
		if root.name == slug and root.parent.name == slug:
			root = root.parent
	except Exception:
		# Best-effort normalization only; never fail selection due to this.
		pass

	substrate_dir = root / "substrate"
	artifacts_dir = root / "artifacts"
	exports_dir = root / "exports"
	logs_dir = root / "logs"
	_ensure_dirs(root, substrate_dir, artifacts_dir, exports_dir, logs_dir)

	ws = WorkspaceConfig(
		name=name,
		slug=slug,
		root=root,
		substrate_dir=substrate_dir,
		artifacts_dir=artifacts_dir,
		exports_dir=exports_dir,
		logs_dir=logs_dir,
	)

	# Persist selection for next start
	_persist_workspace_selection(ws)

	# Apply immediately: replace cfg (dataclass is frozen) and re-init substrate connection
	old_cfg: HubConfig = request.app.state.cfg
	request.app.state.cfg = HubConfig(
		version=old_cfg.version,
		bind_host=old_cfg.bind_host,
		http_port=old_cfg.http_port,
		udp_port=old_cfg.udp_port,
		ring_buffer_size=old_cfg.ring_buffer_size,
		enforce_provenance=old_cfg.enforce_provenance,
		plugins_enabled=old_cfg.plugins_enabled,
		auth_enabled=old_cfg.auth_enabled,
		auth_token=old_cfg.auth_token,
		workspace=ws,
		voice_sidecar_enabled=old_cfg.voice_sidecar_enabled,
		voice_sidecar_url=old_cfg.voice_sidecar_url,
		voice_sidecar_cmd=old_cfg.voice_sidecar_cmd,
		voice_sidecar_args=old_cfg.voice_sidecar_args,
		voice_sidecar_cwd=old_cfg.voice_sidecar_cwd,
	)

	# Reinitialize substrate repo (best-effort)
	try:
		if request.app.state.substrate:
			await request.app.state.substrate.close()
		db_path = ws.substrate_dir / "substrate.db"
		request.app.state.substrate = Substrate(db_path)
		await request.app.state.substrate.open()
		request.app.state.substrate_repo = SubstrateRepo(request.app.state.substrate, enforce_provenance=old_cfg.enforce_provenance)
		# Workspace-bound capabilities must be recreated lazily on next use.
		request.app.state.stfx_memory = None
		request.app.state.stfx_store = None
	except Exception as e:
		raise HTTPException(status_code=500, detail=f"Workspace selected but substrate init failed: {e}")

	return {
		"ok": True,
		"workspace": {"name": ws.name, "slug": ws.slug, "root": str(ws.root)},
	}


