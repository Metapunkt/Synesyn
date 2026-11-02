from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..substrate.artifact_store import ArtifactStore
from .service import StfxMemoryService


router = APIRouter()


def _get_service(request: Request) -> StfxMemoryService:
	cfg = getattr(request.app.state, "cfg", None)
	if not cfg or not cfg.workspace:
		raise HTTPException(status_code=503, detail="Workspace not configured")
	service = getattr(request.app.state, "stfx_memory", None)
	service_root = getattr(getattr(service, "store", None), "root", None)
	expected_root = cfg.workspace.root / "stfx_memory"
	if service is None or service_root != expected_root:
		service = StfxMemoryService(cfg.workspace)
		request.app.state.stfx_memory = service
	return service


class IngestRequest(BaseModel):
	md_path: str
	parse_strategy: str = "headings"


class ExpandRequest(BaseModel):
	document_id: str
	chunk_path: str = ""
	depth: int = 2


class RetrieveRequest(BaseModel):
	document_id: str = ""
	chunk_path: str = ""
	seed_family: str = ""


class SnapshotRequest(BaseModel):
	document_id: str
	label: str = ""


class ContinuityContextRequest(BaseModel):
	document_id: str
	chunk_path: str = ""
	depth: int = 2
	sibling_window: int = 2


class ExportSubstrateArtifactRequest(BaseModel):
	document_id: str = ""
	export_kind: str = "document"
	chunk_path: str = ""
	depth: int = 2
	metadata: dict = {}


@router.get("/documents")
async def list_documents(request: Request):
	service = _get_service(request)
	return {"ok": True, "documents": service.list_documents()}


@router.get("/documents/{document_id}")
async def get_document(document_id: str, request: Request):
	service = _get_service(request)
	try:
		return {"ok": True, "document": service.get_document(document_id)}
	except KeyError:
		raise HTTPException(status_code=404, detail="Document not found")


@router.post("/documents/ingest")
async def ingest_document(payload: IngestRequest, request: Request):
	service = _get_service(request)
	try:
		return service.ingest_document(payload.md_path, parse_strategy=payload.parse_strategy)
	except FileNotFoundError as e:
		raise HTTPException(status_code=404, detail=str(e))
	except Exception as e:
		raise HTTPException(status_code=400, detail=str(e))


@router.post("/expand")
async def expand(payload: ExpandRequest, request: Request):
	service = _get_service(request)
	try:
		return service.expand(payload.document_id, payload.chunk_path, payload.depth)
	except KeyError as e:
		raise HTTPException(status_code=404, detail=str(e))
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


@router.post("/retrieve")
async def retrieve(payload: RetrieveRequest, request: Request):
	service = _get_service(request)
	try:
		return service.retrieve(payload.document_id, payload.chunk_path, payload.seed_family)
	except KeyError as e:
		raise HTTPException(status_code=404, detail=str(e))
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


@router.post("/snapshots/create")
async def create_snapshot(payload: SnapshotRequest, request: Request):
	service = _get_service(request)
	try:
		return service.create_snapshot(payload.document_id, payload.label)
	except KeyError:
		raise HTTPException(status_code=404, detail="Document not found")
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


@router.post("/context/continuity")
async def continuity_context(payload: ContinuityContextRequest, request: Request):
	service = _get_service(request)
	try:
		return service.continuity_context(
			document_id=payload.document_id,
			chunk_path=payload.chunk_path,
			depth=payload.depth,
			sibling_window=payload.sibling_window,
		)
	except KeyError as e:
		raise HTTPException(status_code=404, detail=str(e))
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


@router.post("/export/substrate-artifact")
async def export_substrate_artifact(payload: ExportSubstrateArtifactRequest, request: Request):
	service = _get_service(request)
	repo = getattr(request.app.state, "substrate_repo", None)
	cfg = getattr(request.app.state, "cfg", None)
	if not repo or not cfg or not cfg.workspace:
		raise HTTPException(status_code=503, detail="Workspace/substrate not initialized")
	try:
		exported = service.export_payload(
			export_kind=payload.export_kind,
			document_id=payload.document_id,
			chunk_path=payload.chunk_path,
			depth=payload.depth,
		)
		artifact_type = exported["artifact_type"]
		body = exported["payload"]
		metadata = payload.metadata if isinstance(payload.metadata, dict) else {}
		prov = metadata.get("provenance", {}) if isinstance(metadata.get("provenance", {}), dict) else {}
		prov.setdefault("generated_by", "stfx_memory.export.substrate")
		input_ref = {"export_kind": payload.export_kind}
		if payload.document_id:
			input_ref["document_id"] = payload.document_id
		if payload.chunk_path:
			input_ref["chunk_path"] = payload.chunk_path
		prov.setdefault("inputs", [input_ref])
		metadata["provenance"] = prov
		metadata.setdefault("refs", {})
		if payload.document_id:
			metadata["refs"]["document_id"] = payload.document_id
		if payload.chunk_path:
			metadata["refs"]["chunk_path"] = payload.chunk_path

		store = ArtifactStore(cfg.workspace.artifacts_dir)
		art_id, uri, h = store.write_json(artifact_type, body, "json")
		await repo.insert_artifact({
			"id": art_id,
			"artifact_type": artifact_type,
			"uri": uri,
			"hash": h,
			"metadata": metadata,
		})
		await repo.commit()
		return {
			"ok": True,
			"id": art_id,
			"artifact_type": artifact_type,
			"uri": uri,
			"hash": h,
		}
	except KeyError as e:
		raise HTTPException(status_code=404, detail=str(e))
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))
