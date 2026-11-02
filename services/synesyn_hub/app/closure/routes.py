"""
closure.routes
==============

HTTP surface for the SynAxes-facing closure service (mounted at ``/closure``).
The field/collapse/twin/neighbourhood endpoints are stateless and require no
workspace; ``/closure/commit`` persists a closure commitment as a substrate
artifact with provenance (mirroring the stfx-memory export pattern).
"""

from __future__ import annotations

from typing import List, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..substrate.artifact_store import ArtifactStore
from .service import ClosureService, resolve_seed


router = APIRouter()
_service = ClosureService()


class SeedSpec(BaseModel):
	seed_matrix: Optional[List[List[int]]] = None
	lexicon: str = "ifa_odu"
	family: str = ""
	symbols: Optional[List[str]] = None
	depth: int = 3


class IndexSpec(SeedSpec):
	index: int = 0


class NeighbourhoodSpec(IndexSpec):
	radius: int = 8


class CommitSpec(IndexSpec):
	metadata: dict = {}


def _resolve(spec: SeedSpec):
	try:
		return resolve_seed(
			seed_matrix=spec.seed_matrix,
			lexicon=spec.lexicon,
			family=spec.family,
			symbols=spec.symbols,
		)
	except KeyError as e:
		raise HTTPException(status_code=404, detail=str(e))
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


@router.get("/lexicons")
async def list_lexicons():
	return _service.list_lexicons()


@router.post("/field")
async def field(spec: SeedSpec):
	return _service.field(_resolve(spec), spec.depth)


@router.post("/collapse")
async def collapse(spec: IndexSpec):
	return _service.collapse(_resolve(spec), spec.index, spec.depth)


@router.post("/twin")
async def twin(spec: IndexSpec):
	return _service.twin(_resolve(spec), spec.index, spec.depth)


@router.post("/neighbourhood")
async def neighbourhood(spec: NeighbourhoodSpec):
	return _service.neighbourhood(_resolve(spec), spec.index, spec.radius, spec.depth)


@router.post("/commit")
async def commit(spec: CommitSpec, request: Request):
	seed = _resolve(spec)
	repo = getattr(request.app.state, "substrate_repo", None)
	cfg = getattr(request.app.state, "cfg", None)
	if not repo or not cfg or not cfg.workspace:
		raise HTTPException(status_code=503, detail="Workspace/substrate not initialized")
	built = _service.commit_artifact(seed, spec.index, spec.depth)
	metadata = spec.metadata if isinstance(spec.metadata, dict) else {}
	prov = metadata.get("provenance", {}) if isinstance(metadata.get("provenance", {}), dict) else {}
	prov.setdefault("generated_by", "closure.commit")
	prov.setdefault("inputs", [built["provenance"]])
	metadata["provenance"] = prov
	store = ArtifactStore(cfg.workspace.artifacts_dir)
	art_id, uri, h = store.write_json(built["artifact_type"], built["payload"], "json")
	await repo.insert_artifact({
		"id": art_id,
		"artifact_type": built["artifact_type"],
		"uri": uri,
		"hash": h,
		"metadata": metadata,
	})
	await repo.commit()
	return {"ok": True, "id": art_id, "artifact_type": built["artifact_type"],
			"uri": uri, "hash": h, "recipe": built["provenance"]}
