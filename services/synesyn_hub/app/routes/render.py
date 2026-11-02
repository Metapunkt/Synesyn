from __future__ import annotations

import asyncio
import time
from typing import Any, Dict, Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.utils import make_event_envelope


router = APIRouter()


class RenderSubmit(BaseModel):
	request: Dict[str, Any] = Field(..., description="SynesynRenderRequestV1 payload")


class RenderBatchSubmit(BaseModel):
	request: Dict[str, Any] = Field(..., description="Generic render batch request payload")


def _require_repo(request: Request):
	repo = getattr(request.app.state, "substrate_repo", None)
	cfg = getattr(request.app.state, "cfg", None)
	if not repo or not cfg or not cfg.workspace:
		raise HTTPException(status_code=503, detail="Workspace/substrate not initialized")
	return repo, cfg


def _require_job_queue(request: Request) -> asyncio.Queue:
	q = getattr(request.app.state, "job_queue", None)
	if not q:
		raise HTTPException(status_code=503, detail="Job runner not initialized")
	return q


@router.get("/render/jobs/{job_id}")
async def render_get_job(job_id: str, request: Request):
	"""
	Convenience wrapper for render clients:
	return a stable shape without requiring clients to understand generic /jobs schema.
	"""
	repo, _cfg = _require_repo(request)
	jid = (job_id or "").strip()
	if not jid:
		raise HTTPException(status_code=400, detail="job_id is required")

	job = await repo.get_job(jid)
	if not job:
		raise HTTPException(status_code=404, detail="Job not found")

	job_type = str(job.get("job_type") or "")
	if not job_type.startswith("render."):
		raise HTTPException(status_code=404, detail="Render job not found")

	output = job.get("output_json") or {}
	artifacts = job.get("artifacts_json") or []
	return {
		"ok": True,
		"job_id": job.get("id"),
		"status": job.get("status"),
		"provider": "comfyui" if job_type == "render.comfyui" else "batch",
		"job_type": job_type,
		"created_at": job.get("created_at"),
		"started_at": job.get("started_at"),
		"completed_at": job.get("completed_at"),
		"error": job.get("error"),
		"render_request_artifact_id": (output.get("render_request_artifact_id") if isinstance(output, dict) else None),
		"prompt_id": (output.get("prompt_id") if isinstance(output, dict) else None),
		"image_artifact_ids": (output.get("image_artifact_ids") if isinstance(output, dict) else None),
		"artifacts": artifacts,
		"output": output,
	}


@router.get("/render/jobs")
async def render_list_jobs(request: Request, limit: int = 50):
	"""
	List recent render jobs (single and batch).
	"""
	repo, _cfg = _require_repo(request)
	limit = max(1, min(int(limit or 50), 200))
	res = await repo.query({"table": "jobs", "where": {}, "limit": limit * 3})
	cols = [str(c) for c in (res.get("columns") or [])]
	rows = res.get("rows") or []
	job_type_idx = cols.index("job_type") if "job_type" in cols else -1
	if job_type_idx >= 0:
		rows = [row for row in rows if len(row) > job_type_idx and str(row[job_type_idx] or "").startswith("render.")]
	return {"ok": True, "result": {"columns": cols, "rows": rows[:limit]}}


@router.post("/render/jobs/{job_id}/cancel")
async def render_cancel_job(job_id: str, request: Request):
	repo, _cfg = _require_repo(request)
	jid = (job_id or "").strip()
	if not jid:
		raise HTTPException(status_code=400, detail="job_id is required")
	job = await repo.get_job(jid)
	if not job:
		raise HTTPException(status_code=404, detail="Job not found")
	if str(job.get("job_type") or "") != "render.comfyui":
		raise HTTPException(status_code=404, detail="Render job not found")
	status = str(job.get("status") or "").strip().lower()
	if status in {"completed", "failed", "canceled"}:
		return {"ok": True, "job_id": jid, "status": status, "noop": True}
	if status != "queued":
		raise HTTPException(status_code=409, detail=f"Only queued jobs are cancelable (current status: {status})")
	await repo.update_job_status(
		jid,
		status="canceled",
		completed_at=time.time(),
		error="Canceled by user.",
	)
	await repo.commit()
	bus = request.app.state.event_bus
	evt = make_event_envelope(
		event_type="render.failed",
		source_id="render",
		seq=2,
		payload={"job_id": jid, "error": "Canceled by user.", "provider": "comfyui", "canceled": True},
		provenance={"job_id": jid},
	)
	await bus.publish(evt)
	await repo.insert_event(evt)
	await repo.commit()
	return {"ok": True, "job_id": jid, "status": "canceled"}


@router.post("/render/jobs/{job_id}/retry")
async def render_retry_job(job_id: str, request: Request):
	repo, _cfg = _require_repo(request)
	q = _require_job_queue(request)
	bus = request.app.state.event_bus
	jid = (job_id or "").strip()
	if not jid:
		raise HTTPException(status_code=400, detail="job_id is required")
	job = await repo.get_job(jid)
	if not job:
		raise HTTPException(status_code=404, detail="Job not found")
	if str(job.get("job_type") or "") != "render.comfyui":
		raise HTTPException(status_code=404, detail="Render job not found")
	status = str(job.get("status") or "").strip().lower()
	if status not in {"failed", "canceled", "completed"}:
		raise HTTPException(status_code=409, detail=f"Only terminal jobs can be retried (current status: {status})")
	input_pack = job.get("input_json") if isinstance(job.get("input_json"), dict) else {}
	meta = job.get("metadata_json") if isinstance(job.get("metadata_json"), dict) else {}
	new_job_id = await repo.create_job(
		{
			"job_type": "render.comfyui",
			"status": "queued",
			"input": input_pack,
			"metadata": {
				"request_id": meta.get("request_id"),
				"session_id": meta.get("session_id"),
				"retried_from_job_id": jid,
			},
		}
	)
	await repo.commit()
	evt = make_event_envelope(
		event_type="render.queued",
		source_id="render",
		seq=1,
		payload={
			"job_id": new_job_id,
			"request_id": (meta.get("request_id") if isinstance(meta, dict) else None),
			"provider": "comfyui",
			"retried_from_job_id": jid,
		},
		provenance={"job_id": new_job_id},
	)
	await bus.publish(evt)
	await repo.insert_event(evt)
	await repo.commit()
	await q.put(new_job_id)
	return {"ok": True, "job_id": new_job_id, "retried_from_job_id": jid}


@router.post("/render/submit")
async def render_submit(payload: RenderSubmit, request: Request):
	repo, _cfg = _require_repo(request)
	q = _require_job_queue(request)
	bus = request.app.state.event_bus

	rr = payload.request or {}
	if not isinstance(rr, dict):
		raise HTTPException(status_code=400, detail="request must be an object")

	client = rr.get("client") if isinstance(rr.get("client"), dict) else {}
	session_id: Optional[str] = client.get("session_id") if isinstance(client, dict) else None
	request_id: Optional[str] = client.get("request_id") if isinstance(client, dict) else None

	# Create job record. The job runner will:
	# - emit render.started/progress/completed/failed
	# - execute ComfyUI submit + artifact persistence
	job_id = await repo.create_job(
		{
			"job_type": "render.comfyui",
			"status": "queued",
			"input": {"input": {"render_request": rr}, "output_target": {"session_id": session_id}, "metadata": {}},
			"metadata": {"request_id": request_id, "session_id": session_id},
		}
	)
	await repo.commit()

	# Emit render.queued (separate from job.* contract)
	evt = make_event_envelope(
		event_type="render.queued",
		source_id="render",
		seq=1,
		payload={"job_id": job_id, "request_id": request_id, "provider": "comfyui"},
		provenance={"job_id": job_id, "session_id": session_id} if session_id else {"job_id": job_id},
	)
	await bus.publish(evt)
	# Persist render events for auditability/replay.
	await repo.insert_event(evt)
	await repo.commit()

	await q.put(job_id)
	return {"ok": True, "job_id": job_id}


@router.post("/render/submit-batch")
async def render_submit_batch(payload: RenderBatchSubmit, request: Request):
	repo, _cfg = _require_repo(request)
	q = _require_job_queue(request)
	bus = request.app.state.event_bus

	rb = payload.request or {}
	if not isinstance(rb, dict):
		raise HTTPException(status_code=400, detail="request must be an object")

	items = rb.get("items") if isinstance(rb.get("items"), list) else []
	if not items:
		raise HTTPException(status_code=400, detail="request.items must be a non-empty array")

	client = rb.get("client") if isinstance(rb.get("client"), dict) else {}
	session_id: Optional[str] = client.get("session_id") if isinstance(client, dict) else None
	request_id: Optional[str] = client.get("request_id") if isinstance(client, dict) else None

	job_id = await repo.create_job(
		{
			"job_type": "render.batch",
			"status": "queued",
			"input": {"input": {"render_batch_request": rb}, "output_target": {"session_id": session_id}, "metadata": {}},
			"metadata": {"request_id": request_id, "session_id": session_id},
		}
	)
	await repo.commit()

	evt = make_event_envelope(
		event_type="render.batch.queued",
		source_id="render",
		seq=1,
		payload={"job_id": job_id, "request_id": request_id, "item_count": len(items)},
		provenance={"job_id": job_id, "session_id": session_id} if session_id else {"job_id": job_id},
	)
	await bus.publish(evt)
	await repo.insert_event(evt)
	await repo.commit()

	await q.put(job_id)
	return {"ok": True, "job_id": job_id}


