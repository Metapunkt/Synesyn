"""
Synesyn Hub — Local-first substrate service for Synesyn: A Latent Reality Framework.
Copyright © 2026 Ayodele Arigbabu | metapunkt.org | NTNU. All rights reserved.
Licensed under [licence pending].
Version: 0.0.3
Enquiries: metapunkt@metapunkt.org
"""
from __future__ import annotations

# ── SSL cert bootstrap (must run before any network imports) ──────────────
# PyInstaller bundles certifi's cacert.pem but Python's ssl module inside a
# frozen exe does NOT automatically find it.  Setting SSL_CERT_FILE alone is
# unreliable on Windows because conda-forge's OpenSSL may ignore the env var
# once the library is initialized.
#
# The guaranteed fix: monkey-patch ssl.create_default_context so that EVERY
# SSL context created by aiohttp / edge-tts / any library uses the bundled
# CA bundle from certifi.  This runs before any network library is imported.
import os as _os
import ssl as _ssl
try:
    import certifi as _certifi
    _cert_file = _certifi.where()
    _os.environ["SSL_CERT_FILE"] = _cert_file        # belt
    _os.environ["REQUESTS_CA_BUNDLE"] = _cert_file   # belt

    _original_create_default_context = _ssl.create_default_context

    def _certifi_create_default_context(
        purpose=_ssl.Purpose.SERVER_AUTH, *, cafile=None, capath=None, cadata=None
    ):
        """Wrapper that injects certifi's CA bundle when no explicit certs are given."""
        if cafile is None and capath is None and cadata is None:
            cafile = _cert_file
        return _original_create_default_context(
            purpose, cafile=cafile, capath=capath, cadata=cadata
        )

    _ssl.create_default_context = _certifi_create_default_context  # suspenders
except ImportError:
    pass  # certifi not available; fall through to OS defaults
# ──────────────────────────────────────────────────────────────────────────

import asyncio
import logging
import os
import sys

import uvicorn
from fastapi import FastAPI

# IMPORTANT (packaging):
# This file is used as a PyInstaller entrypoint (see `packaging/build_windows.ps1`).
# When executed as a script, relative imports like `from .config import ...` break with:
#   ImportError: attempted relative import with no known parent package
# Use absolute imports against the `app` package instead.
from app.config import load_config
from app.events import EventBus
from app.logging_setup import setup_logging
from app.routes.health import router as health_router
from app.routes.export import router as export_router
from app.routes.workspace import router as workspace_router
from app.routes.ws_events import router as ws_router
from app.routes.jobs import router as jobs_router
from app.routes.jobs import run_job
from app.routes.render import router as render_router
from app.routes.scensyn import router as scensyn_router
from app.routes.version import router as version_router
from app.routes.auth import router as auth_router
from app.routes.admin import router as admin_router
from app.stfx_memory.routes import router as stfx_memory_router
from app.stfx_store.routes import router as stfx_store_router
from app.closure.routes import router as closure_router
from app.udp_ingest import UdpIngestConfig, start_udp_ingest
from app.substrate.db import Substrate
from app.substrate.repo import SubstrateRepo
from app.substrate.routes import router as substrate_router
from app.voice.routes import router as voice_router
from app.voice.routes import self_test_edge_tts
from app.voice.sidecar import VoiceSidecarConfig, VoiceSidecarManager
from app.plugins.manager import load_plugins
from app.auth import install_auth


log = logging.getLogger("synesyn_hub")


def create_app() -> FastAPI:
	cfg = load_config()
	setup_logging(cfg)

	app = FastAPI(title="Synesyn Hub", version=cfg.version)
	app.state.cfg = cfg

	# Core shared state
	app.state.event_bus = EventBus(cfg.ring_buffer_size)
	app.state.db_write_queue = asyncio.Queue()
	app.state.substrate = None  # wired later
	app.state.udp_task = None  # wired later
	app.state.udp_transport = None
	app.state.substrate_repo = None
	app.state.voice_sidecar = None
	app.state.stfx_memory = None
	app.state.stfx_store = None

	app.include_router(health_router)
	app.include_router(ws_router)
	app.include_router(substrate_router, prefix="/substrate")
	app.include_router(voice_router, prefix="/voice")
	app.include_router(export_router, prefix="/export")
	app.include_router(workspace_router, prefix="/workspace")
	app.include_router(jobs_router)
	app.include_router(render_router)
	app.include_router(scensyn_router, prefix="/scensyn")
	app.include_router(version_router)
	app.include_router(auth_router)
	app.include_router(admin_router)
	app.include_router(stfx_memory_router, prefix="/stfx-memory")
	app.include_router(stfx_store_router, prefix="/stfx-store")
	app.include_router(closure_router, prefix="/closure")

	# Pluggable auth middleware (no-op by default).
	install_auth(app, cfg)

	# Minimal plugin system (best-effort).
	app.state.plugins_status = load_plugins(app, getattr(cfg, "plugins_enabled", []))

	# Future routers (added in subsequent tasks):
	# - /jobs/* (implemented)

	@app.on_event("startup")
	async def _startup():
		# Substrate init (requires workspace vault)
		if cfg.workspace:
			db_path = cfg.workspace.substrate_dir / "substrate.db"
			app.state.substrate = Substrate(db_path)
			await app.state.substrate.open()
			app.state.substrate_repo = SubstrateRepo(app.state.substrate, enforce_provenance=cfg.enforce_provenance)

		# Background DB writer: persists UDP-originated events asynchronously.
		async def _db_writer_loop():
			while True:
				kind, obj = await app.state.db_write_queue.get()
				try:
					if kind == "event" and app.state.substrate_repo:
						await app.state.substrate_repo.insert_event(obj)
						await app.state.substrate_repo.commit()
				except Exception:
					log.exception("DB writer failed")

		app.state.db_writer_task = asyncio.create_task(_db_writer_loop())

		# Jobs runner (hub-local compute / async pipelines)
		app.state.job_queue = asyncio.Queue()

		async def _job_runner_loop():
			while True:
				job_id = await app.state.job_queue.get()
				try:
					await run_job(job_id, app)
				except Exception:
					log.exception("Job runner failed for %s", job_id)

		app.state.job_runner_task = asyncio.create_task(_job_runner_loop())

		# Voice self-test (best-effort, non-blocking)
		async def _voice_self_test():
			try:
				await self_test_edge_tts()
			except Exception:
				log.exception("Voice self-test failed")

		asyncio.create_task(_voice_self_test())

		# Optional packaging topology (v0): hub-managed voice sidecar.
		# This is off by default; when enabled, hub will attempt to start the sidecar and use it for TTS/STT compute.
		try:
			vs_enabled = bool(getattr(cfg, "voice_sidecar_enabled", False))
			if vs_enabled:
				log_path = None
				if cfg.workspace:
					log_path = str((cfg.workspace.logs_dir / "voice_sidecar.log").resolve())
				sidecar_cfg = VoiceSidecarConfig(
					enabled=True,
					base_url=str(getattr(cfg, "voice_sidecar_url", "") or "").strip(),
					cmd=str(getattr(cfg, "voice_sidecar_cmd", "") or "").strip(),
					cwd=str(getattr(cfg, "voice_sidecar_cwd", "") or "").strip(),
				)
				app.state.voice_sidecar = VoiceSidecarManager(sidecar_cfg, logs_path=log_path)
				await app.state.voice_sidecar.start()
		except Exception:
			log.exception("Voice sidecar startup failed")

		# UDP ingest (sensor -> bus -> persist queue)
		transport, _protocol = await start_udp_ingest(
			app.state.event_bus,
			app.state.db_write_queue,
			UdpIngestConfig(port=cfg.udp_port),
		)
		app.state.udp_transport = transport
		app.state.udp_task = True

	@app.on_event("shutdown")
	async def _shutdown():
		if getattr(app.state, "voice_sidecar", None):
			try:
				await app.state.voice_sidecar.stop()
			except Exception:
				log.exception("Voice sidecar shutdown failed")
		if app.state.udp_transport:
			app.state.udp_transport.close()
		if getattr(app.state, "db_writer_task", None):
			app.state.db_writer_task.cancel()
		if getattr(app.state, "job_runner_task", None):
			app.state.job_runner_task.cancel()
		if app.state.substrate:
			await app.state.substrate.close()

	return app


app = create_app()


def main():
	cfg = app.state.cfg
	log.info("Starting Synesyn Hub on %s:%d", cfg.bind_host, cfg.http_port)

	# PyInstaller windowed builds (--noconsole) may have sys.stdout/sys.stderr set to None.
	# Uvicorn's default logging config uses StreamHandler streams and calls .isatty() -> crash if None.
	if sys.stdout is None:
		sys.stdout = open(os.devnull, "w")
	if sys.stderr is None:
		sys.stderr = open(os.devnull, "w")

	# We already configure logging via setup_logging(cfg). Prevent uvicorn from overriding it.
	try:
		uvicorn.run(app, host=cfg.bind_host, port=cfg.http_port, log_config=None, access_log=False)
	except OSError as e:
		# A --noconsole build has nowhere to print, so an unhandled bind failure
		# makes the hub look like it started and vanished. The usual cause is an
		# earlier hub that survived an abnormal client exit and still holds the
		# port, so name that remedy in the log the client can actually read.
		log.error(
			"Could not bind %s:%d - %s. Another Synesyn Hub is probably still running: "
			"stop it from Settings, or end synesyn_hub.exe in Task Manager.",
			cfg.bind_host,
			cfg.http_port,
			e,
		)
		raise SystemExit(98)


if __name__ == "__main__":
	main()


