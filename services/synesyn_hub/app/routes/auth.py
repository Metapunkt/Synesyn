from __future__ import annotations

from fastapi import APIRouter, Request


router = APIRouter()


@router.get("/auth/whoami")
async def whoami(request: Request):
	"""
	Auth verification endpoint.

	- If hub auth middleware is enabled, this endpoint is protected and returns ok:true only when the bearer token is valid.
	- If hub auth is disabled, return ok:false so downstream verifiers (Metapunkt) can fail-closed when configured to require auth.
	"""
	cfg = request.app.state.cfg
	if not getattr(cfg, "auth_enabled", False):
		return {"ok": False, "error": "auth_disabled"}

	# The middleware validates the bearer token; do not echo it back.
	return {
		"ok": True,
		"auth": "bearer_shared_secret",
		"user_id_hint": request.headers.get("x-user-id", "") or "",
	}


