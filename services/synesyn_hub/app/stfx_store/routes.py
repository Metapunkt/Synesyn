from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from .service import StfxStoreService


router = APIRouter()


def _get_service(request: Request) -> StfxStoreService:
	cfg = getattr(request.app.state, "cfg", None)
	if not cfg or not cfg.workspace:
		raise HTTPException(status_code=503, detail="Workspace not configured")
	service = getattr(request.app.state, "stfx_store", None)
	service_root = getattr(getattr(service, "paths", None), "root", None)
	expected_root = cfg.workspace.root / "stfx_store"
	if service is None or service_root != expected_root:
		service = StfxStoreService(cfg.workspace)
		request.app.state.stfx_store = service
	return service


class IngestSourceRequest(BaseModel):
	source_path: str
	default_seed: str = "primary"
	llm_recommendations: Dict[str, Any] = {}


class RetrieveRequest(BaseModel):
	query: str
	active_source_ids: list[str] = []
	seed_family: str = ""
	top_k: int = 5
	expansion_depth: int = 1


class CommitArtifactRequest(BaseModel):
	artifact_type: str = "json.generic"
	payload: Dict[str, Any] = {}
	provenance: Dict[str, Any] = {}


class CommitContextGraphRequest(BaseModel):
	graph: Dict[str, Any] = {}
	provenance: Dict[str, Any] = {}


class CommitMemoryRequest(BaseModel):
	payload: Dict[str, Any] = {}
	provenance: Dict[str, Any] = {}


class CommitClosureRequest(BaseModel):
	payload: Dict[str, Any] = {}
	provenance: Dict[str, Any] = {}


class StoreConfigRequest(BaseModel):
	enabled: bool | None = None
	accelerators: Dict[str, Any] = {}
	admissibility: Dict[str, Any] | None = None


class UpdateChunkSymbolicRequest(BaseModel):
	symbolic: Dict[str, Any] = {}
	repair_note: str = ""


@router.get("/status")
async def status(request: Request):
	service = _get_service(request)
	return service.status()


@router.post("/config")
async def update_config(payload: StoreConfigRequest, request: Request):
	service = _get_service(request)
	return service.update_config(payload.enabled, payload.accelerators, payload.admissibility)


@router.get("/sources")
async def list_sources(request: Request):
	service = _get_service(request)
	return {"ok": True, "sources": service.list_sources()}


@router.get("/memories")
async def list_memories(request: Request):
	service = _get_service(request)
	return {"ok": True, "memories": service.list_memories()}


@router.get("/closures")
async def list_closures(request: Request):
	service = _get_service(request)
	return {"ok": True, "closures": service.list_closures()}


@router.get("/context-packs")
async def list_context_packs(request: Request):
	service = _get_service(request)
	return {"ok": True, "context_packs": service.list_context_packs()}


@router.post("/sources/ingest")
async def ingest_source(payload: IngestSourceRequest, request: Request):
	service = _get_service(request)
	try:
		return service.ingest_source(
			payload.source_path,
			default_seed=payload.default_seed,
			llm_recommendations=payload.llm_recommendations,
		)
	except FileNotFoundError as exc:
		raise HTTPException(status_code=404, detail=str(exc))
	except ValueError as exc:
		raise HTTPException(status_code=400, detail=str(exc))


@router.post("/indexes/rebuild")
async def rebuild_indexes(request: Request):
	service = _get_service(request)
	try:
		return service.rebuild_indexes()
	except ValueError as exc:
		raise HTTPException(status_code=400, detail=str(exc))


@router.post("/retrieve")
async def retrieve(payload: RetrieveRequest, request: Request):
	service = _get_service(request)
	try:
		return service.retrieve(
			query=payload.query,
			active_source_ids=payload.active_source_ids,
			seed_family=payload.seed_family,
			top_k=payload.top_k,
			expansion_depth=payload.expansion_depth,
		)
	except ValueError as exc:
		raise HTTPException(status_code=400, detail=str(exc))


@router.get("/traces/{trace_id}")
async def get_trace(trace_id: str, request: Request):
	service = _get_service(request)
	try:
		return {"ok": True, "trace": service.get_trace(trace_id)}
	except KeyError as exc:
		raise HTTPException(status_code=404, detail=str(exc))


@router.get("/context-packs/{context_pack_id}")
async def get_context_pack(context_pack_id: str, request: Request):
	service = _get_service(request)
	try:
		return {"ok": True, "context_pack": service.get_context_pack(context_pack_id)}
	except KeyError as exc:
		raise HTTPException(status_code=404, detail=str(exc))


@router.get("/indexes/{index_name}")
async def get_index(index_name: str, request: Request):
	service = _get_service(request)
	try:
		return service.get_index(index_name)
	except KeyError as exc:
		raise HTTPException(status_code=404, detail=str(exc))


@router.get("/chunks/{chunk_id}")
async def get_chunk(chunk_id: str, request: Request):
	service = _get_service(request)
	try:
		return service.get_chunk_record(chunk_id)
	except KeyError as exc:
		raise HTTPException(status_code=404, detail=str(exc))


@router.post("/chunks/{chunk_id}/symbolic")
async def update_chunk_symbolic(chunk_id: str, payload: UpdateChunkSymbolicRequest, request: Request):
	service = _get_service(request)
	try:
		return service.update_chunk_symbolic(chunk_id, payload.symbolic, payload.repair_note)
	except KeyError as exc:
		raise HTTPException(status_code=404, detail=str(exc))
	except ValueError as exc:
		raise HTTPException(status_code=400, detail=str(exc))


@router.post("/artifacts/commit")
async def commit_artifact(payload: CommitArtifactRequest, request: Request):
	service = _get_service(request)
	return service.commit_artifact(payload.artifact_type, payload.payload, payload.provenance)


@router.post("/context-graphs/commit")
async def commit_context_graph(payload: CommitContextGraphRequest, request: Request):
	service = _get_service(request)
	try:
		return service.commit_context_graph(payload.graph, payload.provenance)
	except ValueError as exc:
		raise HTTPException(status_code=400, detail=str(exc))


@router.post("/memories/commit")
async def commit_memory(payload: CommitMemoryRequest, request: Request):
	service = _get_service(request)
	try:
		return service.commit_memory(payload.payload, payload.provenance)
	except ValueError as exc:
		raise HTTPException(status_code=400, detail=str(exc))


@router.post("/closures/commit")
async def commit_closure(payload: CommitClosureRequest, request: Request):
	service = _get_service(request)
	try:
		return service.commit_closure(payload.payload, payload.provenance)
	except ValueError as exc:
		raise HTTPException(status_code=400, detail=str(exc))


@router.post("/validate")
async def validate_store(request: Request):
	service = _get_service(request)
	return service.validate_store()


@router.post("/repair/report")
async def repair_report(request: Request):
	service = _get_service(request)
	return service.repair_report()


@router.post("/migrations/stfx-memory/export")
async def export_stfx_memory(request: Request):
	service = _get_service(request)
	return service.export_legacy_stfx_memory()


@router.post("/migrations/syntree-context-graphs/export")
async def export_syntree_context_graphs(request: Request):
	service = _get_service(request)
	return service.export_syntree_context_graphs()


@router.post("/migrations/substrate-artifacts/export")
async def export_substrate_artifacts(request: Request):
	service = _get_service(request)
	return service.export_substrate_artifact_mirrors()
