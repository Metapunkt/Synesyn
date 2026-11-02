from __future__ import annotations

from fastapi import FastAPI, Request
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

from .config import HubConfig


class AuthMiddleware(BaseHTTPMiddleware):
	def __init__(self, app: FastAPI, token: str):
		super().__init__(app)
		self._token = token

	async def dispatch(self, request: Request, call_next):
		# Allow unauthenticated health checks for local UX.
		if request.url.path in ("/health", "/status", "/version"):
			return await call_next(request)

		h = request.headers.get("authorization", "")
		if not h.startswith("Bearer "):
			return JSONResponse({"ok": False, "error": "missing_bearer_token"}, status_code=401)
		if h.removeprefix("Bearer ").strip() != self._token:
			return JSONResponse({"ok": False, "error": "invalid_token"}, status_code=403)
		return await call_next(request)


def install_auth(app: FastAPI, cfg: HubConfig) -> None:
	# Pluggable auth middleware. Disabled by default for local/offline mode.
	if not getattr(cfg, "auth_enabled", False):
		return
	token = getattr(cfg, "auth_token", "") or ""
	if not token.strip():
		# Fail-open is safer for local dev; configs that enable auth should provide a token.
		return
	app.add_middleware(AuthMiddleware, token=token.strip())


