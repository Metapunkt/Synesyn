from __future__ import annotations

from fastapi import APIRouter, Request


router = APIRouter()


@router.get("/version")
async def version(request: Request):
	cfg = request.app.state.cfg
	return {
		"ok": True,
		"version": cfg.version,
		"schema": {
			"event_envelope": 1,
			"tool_call": 1,
		},
		"plugins": getattr(request.app.state, "plugins_status", {}),
	}


