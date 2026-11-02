from __future__ import annotations

import asyncio
import os

from fastapi import APIRouter, HTTPException, Request


router = APIRouter()


def _is_local_request(request: Request) -> bool:
	# Only allow shutdown from localhost (Synesyn desktop app).
	# Note: In some proxy setups client may be None; treat as non-local.
	if request.client is None:
		return False
	host = (request.client.host or "").strip()
	return host in {"127.0.0.1", "::1", "localhost"}


@router.post("/admin/shutdown")
async def shutdown(request: Request):
	"""
	Local-only shutdown endpoint.

	Why: the Godot app may not know the hub PID (e.g. hub was started externally or
	already running), but still needs a reliable way to stop/restart it.
	"""
	if not _is_local_request(request):
		raise HTTPException(status_code=403, detail="Local requests only")

	# Let the response flush, then hard-exit the process.
	# (Uvicorn run() in our entrypoint doesn't expose a Server instance to request handlers.)
	loop = asyncio.get_running_loop()
	loop.call_later(0.25, lambda: os._exit(0))
	return {"ok": True}

