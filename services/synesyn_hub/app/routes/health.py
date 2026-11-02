from __future__ import annotations

import time
from fastapi import APIRouter, Request

from ..voice.routes import get_voice_providers_status

router = APIRouter()

_START_TIME = time.time()
_BUILD_ID = "workspace_select_fix_2026-02-09"


@router.get("/health")
async def health(request: Request):
	cfg = request.app.state.cfg
	ok = cfg.workspace is not None
	has_jobs = bool(getattr(request.app.state, "job_queue", None)) and bool(getattr(request.app.state, "job_runner_task", None))
	plugins_status = getattr(request.app.state, "plugins_status", {}) or {}
	plugins_list = plugins_status.get("plugins", []) if isinstance(plugins_status, dict) else []
	voice_status = get_voice_providers_status() or {}
	whisper_ok = bool(((voice_status.get("stt", {}) or {}).get("whisper", {}) or {}).get("available", False))
	sidecar = getattr(request.app.state, "voice_sidecar", None)
	sidecar_enabled = bool(sidecar and getattr(sidecar, "is_enabled", None) and sidecar.is_enabled())
	return {
		"ok": ok,
		"version": cfg.version,
		"build_id": _BUILD_ID,
		"uptime_sec": int(time.time() - _START_TIME),
		"time_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
		"capabilities": {
			"substrate": bool(getattr(request.app.state, "substrate", None)),
			"ws_events": bool(getattr(request.app.state, "event_bus", None)),
			"udp_ingest": bool(getattr(request.app.state, "udp_task", None)),
			# Voice endpoints require a configured workspace vault (artifact store + substrate).
			"voice_tts": ok,
			# STT is available either via in-hub Whisper (optional dep) OR an enabled sidecar.
			"voice_stt": ok and (whisper_ok or sidecar_enabled),
			"synaxes_jobs": has_jobs and ok,
			"stfx_memory": ok,
			"render_submit": False,
			"workspace_configured": ok,
			"plugins": bool(plugins_list),
		},
		"plugins": plugins_status,
		"reason": None if ok else "workspace_not_configured",
	}


@router.get("/status")
async def status(request: Request):
	cfg = request.app.state.cfg
	bus = getattr(request.app.state, "event_bus", None)
	dbq = getattr(request.app.state, "db_write_queue", None)
	plugins_status = getattr(request.app.state, "plugins_status", {}) or {}
	return {
		"ok": True,
		"build_id": _BUILD_ID,
		"workspace": {
			"name": cfg.workspace.name if cfg.workspace else None,
			"slug": cfg.workspace.slug if cfg.workspace else None,
			"root": str(cfg.workspace.root) if cfg.workspace else None,
		},
		"udp": {
			"port": cfg.udp_port,
			"sources": bus.get_source_stats() if bus else {},
		},
		"event_bus": {
			"clients": bus.client_count() if bus else 0,
			"ring_buffer_events": bus.ring_size() if bus else 0,
		},
		"storage": {
			"backend": "sqlite",
			"path": str(getattr(getattr(request.app.state, "substrate", None), "db_path", "")),
			"queue_depth": dbq.qsize() if dbq else 0,
		},
		"voice": get_voice_providers_status(),
		"jobs": {
			"enabled": bool(getattr(request.app.state, "job_queue", None)),
			"queue_depth": getattr(getattr(request.app.state, "job_queue", None), "qsize", lambda: 0)(),
		},
		"plugins": plugins_status,
	}


