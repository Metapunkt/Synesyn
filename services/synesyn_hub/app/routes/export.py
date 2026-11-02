from __future__ import annotations

import json
import time
import zipfile
from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..utils import new_id


router = APIRouter()


class ExportSessionRequest(BaseModel):
	session_id: Optional[str] = None
	scope: str = "all"  # v0: only "all" is implemented (workspace-level portable export)
	include_substrate_db: bool = True
	include_artifacts: bool = True
	include_table_dumps: bool = True


class ExportRangeRequest(BaseModel):
	# v1: export multiple sessions by created_at range (unix timestamps).
	start_ts: float
	end_ts: float
	limit: int = 500
	include_substrate_db: bool = True
	include_artifacts: bool = True
	include_table_dumps: bool = True


def _require_workspace(request: Request):
	cfg = request.app.state.cfg
	if not cfg.workspace:
		raise HTTPException(status_code=503, detail="Workspace not configured")
	return cfg.workspace


async def _read_session_and_events(request: Request, session_id: str) -> Dict[str, Any]:
	substrate = getattr(request.app.state, "substrate", None)
	if not substrate:
		raise HTTPException(status_code=503, detail="Substrate not initialized")

	# Sessions
	cur = await substrate.conn.execute("SELECT id, created_at, app_id, scenario_id, scenario_version, participants_json, metadata_json FROM sessions WHERE id=?", [session_id])
	row = await cur.fetchone()
	await cur.close()
	if not row:
		raise HTTPException(status_code=404, detail=f"Session not found: {session_id}")

	(sess_id, created_at, app_id, scenario_id, scenario_version, participants_json, metadata_json) = row
	session = {
		"id": sess_id,
		"created_at": created_at,
		"app_id": app_id,
		"scenario_id": scenario_id,
		"scenario_version": scenario_version,
		"participants": json.loads(participants_json or "{}"),
		"metadata": json.loads(metadata_json or "{}"),
	}

	# Events (JSONL)
	cur = await substrate.conn.execute(
		"SELECT id, session_id, event_type, source_id, seq, t_device, t_received, payload_json, provenance_json FROM events WHERE session_id=? ORDER BY t_received ASC",
		[session_id],
	)
	events = []
	async for r in cur:
		(evt_id, sess_id2, event_type, source_id, seq, t_device, t_received, payload_json, provenance_json) = r
		events.append(
			{
				"id": evt_id,
				"session_id": sess_id2,
				"event_type": event_type,
				"source_id": source_id,
				"seq": seq,
				"t_device": t_device,
				"t_received": t_received,
				"payload": json.loads(payload_json or "{}"),
				"provenance": json.loads(provenance_json or "{}"),
			}
		)
	await cur.close()

	return {"session": session, "events": events}


async def _dump_table(request: Request, table: str, limit: int = 10000) -> Dict[str, Any]:
	substrate = getattr(request.app.state, "substrate", None)
	if not substrate:
		raise HTTPException(status_code=503, detail="Substrate not initialized")
	if table not in {"artifacts", "entities", "relations"}:
		raise HTTPException(status_code=400, detail="Unsupported table dump")

	order = "created_at DESC"
	cur = await substrate.conn.execute(f"SELECT * FROM {table} ORDER BY {order} LIMIT ?", [int(limit)])
	rows = await cur.fetchall()
	cols = [d[0] for d in cur.description]
	await cur.close()
	return {"table": table, "columns": cols, "rows": rows}


async def _list_sessions_in_range(request: Request, start_ts: float, end_ts: float, limit: int = 500) -> list[str]:
	substrate = getattr(request.app.state, "substrate", None)
	if not substrate:
		raise HTTPException(status_code=503, detail="Substrate not initialized")
	limit = max(1, min(int(limit or 500), 5000))
	cur = await substrate.conn.execute(
		"SELECT id FROM sessions WHERE created_at>=? AND created_at<=? ORDER BY created_at ASC LIMIT ?",
		[float(start_ts), float(end_ts), limit],
	)
	rows = await cur.fetchall()
	await cur.close()
	return [str(r[0]) for r in rows]

def _zip_add_tree(zf: zipfile.ZipFile, root: Path, arc_root: str) -> int:
	count = 0
	if not root.exists():
		return 0
	for p in root.rglob("*"):
		if p.is_file():
			arcname = str(Path(arc_root) / p.relative_to(root))
			zf.write(p, arcname=arcname)
			count += 1
	return count


@router.post("/session")
async def export_session(payload: ExportSessionRequest, request: Request):
	ws = _require_workspace(request)
	if payload.scope != "all":
		raise HTTPException(status_code=400, detail="v0 only supports scope='all'")

	export_id = new_id("exp")
	ts = int(time.time())
	zip_path = ws.exports_dir / f"{export_id}_{ts}.zip"

	manifest: Dict[str, Any] = {
		"ok": True,
		"export_id": export_id,
		"created_at": time.time(),
		"hub_version": request.app.state.cfg.version,
		"hub_status": None,
		"provenance": {"generated_by": "export.session"},
		"workspace": {"name": ws.name, "slug": ws.slug},
		"session_id": payload.session_id,
		"contents": {},
	}

	session_bundle: Optional[Dict[str, Any]] = None
	if payload.session_id:
		session_bundle = await _read_session_and_events(request, payload.session_id)

	with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
		# Manifest
		zf.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))

		# Optional session bundle (metadata + events jsonl-like array in v0)
		if session_bundle:
			zf.writestr(f"sessions/{payload.session_id}/session.json", json.dumps(session_bundle["session"], ensure_ascii=False, indent=2))
			# v0: keep it as JSON array (simple); v1 can switch to JSONL if desired.
			zf.writestr(f"sessions/{payload.session_id}/events.json", json.dumps(session_bundle["events"], ensure_ascii=False, indent=2))

		# Substrate DB
		if payload.include_substrate_db:
			db_path = ws.substrate_dir / "substrate.db"
			if db_path.exists():
				zf.write(db_path, arcname="substrate/substrate.db")

		# Table dumps (human-readable indices)
		table_dumps = {}
		if payload.include_table_dumps:
			for t in ["artifacts", "entities", "relations"]:
				table_dumps[t] = await _dump_table(request, t)
				zf.writestr(f"substrate/{t}.json", json.dumps(table_dumps[t], ensure_ascii=False, indent=2))

		# Artifacts
		artifact_files = 0
		if payload.include_artifacts:
			artifact_files = _zip_add_tree(zf, ws.artifacts_dir, "artifacts")

	# Update manifest (best-effort) by rewriting it (simple v0 approach)
	manifest["contents"] = {
		"substrate_db": bool(payload.include_substrate_db),
		"table_dumps": bool(payload.include_table_dumps),
		"artifacts": bool(payload.include_artifacts),
		"artifact_files": artifact_files,
		"session_bundle": bool(session_bundle),
	}
	with zipfile.ZipFile(zip_path, "a", compression=zipfile.ZIP_DEFLATED) as zf:
		zf.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))

	return {
		"ok": True,
		"export_id": export_id,
		"zip_url": zip_path.resolve().as_uri(),
		"zip_path": str(zip_path),
		"session_id": payload.session_id,
		"artifact_files": artifact_files,
	}


@router.post("/range")
async def export_range(payload: ExportRangeRequest, request: Request):
	ws = _require_workspace(request)
	start_ts = float(payload.start_ts)
	end_ts = float(payload.end_ts)
	if end_ts < start_ts:
		raise HTTPException(status_code=400, detail="end_ts must be >= start_ts")

	session_ids = await _list_sessions_in_range(request, start_ts, end_ts, payload.limit)

	export_id = new_id("exp")
	ts = int(time.time())
	zip_path = ws.exports_dir / f"{export_id}_{ts}.zip"

	manifest: Dict[str, Any] = {
		"ok": True,
		"export_id": export_id,
		"created_at": time.time(),
		"hub_version": request.app.state.cfg.version,
		"provenance": {"generated_by": "export.range"},
		"workspace": {"name": ws.name, "slug": ws.slug},
		"range": {"start_ts": start_ts, "end_ts": end_ts, "limit": int(payload.limit)},
		"session_ids": session_ids,
		"contents": {},
	}

	with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
		zf.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))

		# Session bundles
		for sid in session_ids:
			bundle = await _read_session_and_events(request, sid)
			zf.writestr(f"sessions/{sid}/session.json", json.dumps(bundle["session"], ensure_ascii=False, indent=2))
			zf.writestr(f"sessions/{sid}/events.json", json.dumps(bundle["events"], ensure_ascii=False, indent=2))

		# Substrate DB
		if payload.include_substrate_db:
			db_path = ws.substrate_dir / "substrate.db"
			if db_path.exists():
				zf.write(db_path, arcname="substrate/substrate.db")

		# Table dumps
		table_dumps = {}
		if payload.include_table_dumps:
			for t in ["artifacts", "entities", "relations"]:
				table_dumps[t] = await _dump_table(request, t)
				zf.writestr(f"substrate/{t}.json", json.dumps(table_dumps[t], ensure_ascii=False, indent=2))

		# Artifacts
		artifact_files = 0
		if payload.include_artifacts:
			artifact_files = _zip_add_tree(zf, ws.artifacts_dir, "artifacts")

	manifest["contents"] = {
		"substrate_db": bool(payload.include_substrate_db),
		"table_dumps": bool(payload.include_table_dumps),
		"artifacts": bool(payload.include_artifacts),
		"artifact_files": artifact_files,
		"sessions": len(session_ids),
	}
	with zipfile.ZipFile(zip_path, "a", compression=zipfile.ZIP_DEFLATED) as zf:
		zf.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))

	return {
		"ok": True,
		"export_id": export_id,
		"zip_url": zip_path.resolve().as_uri(),
		"zip_path": str(zip_path),
		"sessions": len(session_ids),
		"artifact_files": artifact_files,
	}


