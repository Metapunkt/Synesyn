from __future__ import annotations

import base64
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import url2pathname

from fastapi import APIRouter, HTTPException, Request
from ..substrate.artifact_store import ArtifactStore
from pydantic import BaseModel
import logging

from .schemas import (
	SessionCreate,
	SessionResponse,
	EventCreate,
	ArtifactCreate,
	EntityCreate,
	RelationCreate,
)
from .closure_artifacts import validate_closure_artifact
from .workshop_artifacts import validate_workshop_artifact


router = APIRouter()
log = logging.getLogger("synesyn_hub.substrate.routes")


def _require_repo(request: Request):
	repo = getattr(request.app.state, "substrate_repo", None)
	if not repo:
		raise HTTPException(status_code=503, detail="Substrate not initialized")
	return repo


@router.post("/sessions", response_model=SessionResponse)
async def create_session(payload: SessionCreate, request: Request):
	repo = _require_repo(request)
	sess_id = await repo.create_session(payload.model_dump())
	await repo.commit()
	return SessionResponse(id=sess_id)


class SessionConsentRequest(BaseModel):
	# v0 consent gate used by /voice/transcribe when save_recordings=true
	save_recordings: bool = False

class ArtifactMetadataPatchRequest(BaseModel):
	metadata: dict = {}
	merge: bool = True


@router.post("/sessions/{session_id}/consent")
async def set_session_consent(session_id: str, payload: SessionConsentRequest, request: Request):
	repo = _require_repo(request)
	if not session_id.strip():
		raise HTTPException(status_code=400, detail="session_id is required")
	ok = await repo.set_session_consent_save_recordings(session_id, payload.save_recordings)
	if not ok:
		raise HTTPException(status_code=404, detail="Session not found")
	await repo.commit()
	return {"ok": True}


@router.post("/events")
async def create_event(payload: EventCreate, request: Request):
	repo = _require_repo(request)
	await repo.insert_event(payload.model_dump())
	await repo.commit()
	return {"ok": True}


@router.post("/artifacts")
async def create_artifact(payload: ArtifactCreate, request: Request):
	repo = _require_repo(request)
	try:
		data = payload.model_dump()

		# v0/v1 extension: allow inline_json / inline_bytes_base64 so clients (Godot) can publish artifacts without managing files.
		if data.get("inline_json") is not None:
			data["inline_json"] = validate_closure_artifact(
				data["artifact_type"],
				validate_workshop_artifact(
					data["artifact_type"],
					data["inline_json"],
				),
			)
			cfg = request.app.state.cfg
			if not cfg.workspace:
				raise HTTPException(status_code=503, detail="Workspace not configured")
			store = ArtifactStore(cfg.workspace.artifacts_dir)

			# Store JSON into the artifact store and index it in substrate.
			art_id, uri, h = store.write_json(data["artifact_type"], data["inline_json"], "json")
			data["id"] = art_id
			data["uri"] = uri
			data["hash"] = h
			data.pop("inline_json", None)

			created_id = await repo.insert_artifact(data)
			await repo.commit()
			return {"ok": True, "id": created_id, "uri": uri, "hash": h}

		if data.get("inline_bytes_base64") is not None:
			cfg = request.app.state.cfg
			if not cfg.workspace:
				raise HTTPException(status_code=503, detail="Workspace not configured")
			store = ArtifactStore(cfg.workspace.artifacts_dir)

			ext = str(data.get("ext") or "bin").lstrip(".").strip() or "bin"
			try:
				raw = base64.b64decode(str(data["inline_bytes_base64"]))
			except Exception as e:
				raise HTTPException(status_code=400, detail=f"Invalid base64: {e}")

			# Store bytes into the artifact store and index it in substrate.
			art_id, uri, h = store.write_bytes(data["artifact_type"], raw, ext)
			data["id"] = art_id
			data["uri"] = uri
			data["hash"] = h
			data.pop("inline_bytes_base64", None)
			data.pop("ext", None)

			created_id = await repo.insert_artifact(data)
			await repo.commit()
			return {"ok": True, "id": created_id, "uri": uri, "hash": h}

		# Legacy: uri/hash must be provided for external artifacts.
		if not data.get("uri") or not data.get("hash"):
			raise HTTPException(status_code=400, detail="Provide uri+hash or inline_json or inline_bytes_base64")

		art_id = await repo.insert_artifact(data)
		await repo.commit()
		return {"ok": True, "id": art_id}
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))
	except Exception as e:
		# Ensure clients always get a JSON error body (not plain "Internal Server Error"),
		# so Godot can surface actionable diagnostics.
		log.exception("create_artifact failed")
		raise HTTPException(status_code=500, detail=f"{type(e).__name__}: {e}")


@router.delete("/artifacts/{artifact_id}")
async def delete_artifact(artifact_id: str, request: Request, delete_file: bool = True):
	repo = _require_repo(request)
	aid = (artifact_id or "").strip()
	if not aid:
		raise HTTPException(status_code=400, detail="artifact_id is required")

	rec = await repo.get_artifact_record(aid)
	if not rec:
		raise HTTPException(status_code=404, detail="Artifact not found")

	deleted_file = False
	if delete_file:
		cfg = request.app.state.cfg
		if getattr(cfg, "workspace", None):
			artifacts_root = Path(cfg.workspace.artifacts_dir).resolve()
			uri = str(rec.get("uri") or "").strip()
			if uri.startswith("file:"):
				try:
					p = Path(url2pathname(urlparse(uri).path)).resolve()
					# Only delete files inside the workspace artifacts dir (safety).
					if p.is_relative_to(artifacts_root):
						try:
							p.unlink()
							deleted_file = True
						except FileNotFoundError:
							deleted_file = False
				except Exception as e:
					raise HTTPException(status_code=400, detail=f"Failed to delete artifact file: {e}")

	ok = await repo.delete_artifact(aid)
	if not ok:
		raise HTTPException(status_code=404, detail="Artifact not found")
	await repo.commit()
	return {"ok": True, "deleted_file": deleted_file, "id": aid}

@router.patch("/artifacts/{artifact_id}/metadata")
async def patch_artifact_metadata(artifact_id: str, payload: ArtifactMetadataPatchRequest, request: Request):
	repo = _require_repo(request)
	aid = (artifact_id or "").strip()
	if not aid:
		raise HTTPException(status_code=400, detail="artifact_id is required")
	meta_patch = payload.metadata if isinstance(payload.metadata, dict) else {}
	try:
		updated = await repo.update_artifact_metadata(aid, meta_patch, bool(payload.merge))
		if not updated:
			raise HTTPException(status_code=404, detail="Artifact not found")
		await repo.commit()
		return {"ok": True, "id": aid, "metadata": updated.get("metadata", {})}
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))

@router.post("/entities")
async def create_entity(payload: EntityCreate, request: Request):
	repo = _require_repo(request)
	ent_id = await repo.insert_entity(payload.model_dump())
	await repo.commit()
	return {"ok": True, "id": ent_id}


@router.post("/relations")
async def create_relation(payload: RelationCreate, request: Request):
	repo = _require_repo(request)
	rel_id = await repo.insert_relation(payload.model_dump())
	await repo.commit()
	return {"ok": True, "id": rel_id}


class QueryRequest(BaseModel):
	table: str
	where: dict = {}
	limit: int = 100
	offset: int = 0
	order_by: str = ""
	order_dir: str = "desc"
	time_range: dict = {}  # {field:"t_received"/"created_at"/..., start:float?, end:float?}


@router.post("/query")
async def query(payload: QueryRequest, request: Request):
	repo = _require_repo(request)
	try:
		return {"ok": True, "result": await repo.query(payload.model_dump())}
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


