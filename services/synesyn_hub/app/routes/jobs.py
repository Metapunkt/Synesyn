from __future__ import annotations

import asyncio
import copy
import json
import time
import hashlib
from typing import Any, Dict, Optional
from pathlib import Path
from urllib.parse import urlparse, unquote

import numpy as np
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from ..substrate.artifact_store import ArtifactStore
from ..utils import make_event_envelope
from app.render import comfy as comfyui, comfy_media


router = APIRouter()


class JobSubmit(BaseModel):
	type: str = Field(..., description="Job type, e.g. synaxes.project or synaxes.cluster")
	input: Dict[str, Any] = Field(default_factory=dict)
	output_target: Dict[str, Any] = Field(default_factory=dict)
	metadata: Dict[str, Any] = Field(default_factory=dict)


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


@router.post("/jobs")
async def submit_job(payload: JobSubmit, request: Request):
	repo, _cfg = _require_repo(request)
	q = _require_job_queue(request)

	job_type = payload.type.strip()
	if not job_type:
		raise HTTPException(status_code=400, detail="type is required")

	# Create job record
	job_id = await repo.create_job(
		{
			"job_type": job_type,
			"status": "queued",
			"input": {"input": payload.input, "output_target": payload.output_target, "metadata": payload.metadata},
			"metadata": payload.metadata,
		}
	)
	await repo.commit()

	# Emit job.queued
	bus = request.app.state.event_bus
	await bus.publish(
		make_event_envelope(
			event_type="job.queued",
			source_id="jobs",
			seq=1,
			payload={"job_id": job_id, "type": job_type},
			provenance={"job_id": job_id},
		)
	)

	# Enqueue for background processing
	await q.put(job_id)
	return {"ok": True, "id": job_id}


@router.get("/jobs/{job_id}")
async def get_job(job_id: str, request: Request):
	repo, _cfg = _require_repo(request)
	job = await repo.get_job(job_id)
	if not job:
		raise HTTPException(status_code=404, detail="Job not found")
	return {
		"ok": True,
		"job": {
			"id": job.get("id"),
			"type": job.get("job_type"),
			"status": job.get("status"),
			"created_at": job.get("created_at"),
			"started_at": job.get("started_at"),
			"completed_at": job.get("completed_at"),
			"input": job.get("input_json"),
			"output": job.get("output_json"),
			"artifacts": job.get("artifacts_json"),
			"error": job.get("error"),
			"metadata": job.get("metadata_json"),
		},
	}


@router.get("/jobs")
async def list_jobs(request: Request, limit: int = 50):
	repo, _cfg = _require_repo(request)
	limit = max(1, min(int(limit or 50), 200))
	res = await repo.query({"table": "jobs", "where": {}, "limit": limit})
	return {"ok": True, "result": res}


# ----------------------------
# Job execution (runner helpers)
# ----------------------------


def _pca_project(vectors: list[list[float]], dim: int) -> np.ndarray:
	x = np.asarray(vectors, dtype=np.float64)
	if x.ndim != 2:
		raise ValueError("vectors must be a 2D array")
	# center
	x = x - np.mean(x, axis=0, keepdims=True)
	# SVD
	u, s, vt = np.linalg.svd(x, full_matrices=False)
	# project
	components = vt[:dim].T
	return (x @ components).astype(np.float64)


def _kmeans(coords: np.ndarray, k: int, seed: int = 1337, iters: int = 25) -> tuple[np.ndarray, np.ndarray]:
	if coords.ndim != 2:
		raise ValueError("coords must be 2D")
	n = coords.shape[0]
	k = max(1, min(int(k), n))
	rng = np.random.default_rng(seed)
	centroids = coords[rng.choice(n, size=k, replace=False)]
	labels = np.zeros((n,), dtype=np.int32)
	for _ in range(iters):
		# assign
		d2 = np.sum((coords[:, None, :] - centroids[None, :, :]) ** 2, axis=2)
		new_labels = np.argmin(d2, axis=1).astype(np.int32)
		if np.array_equal(new_labels, labels):
			break
		labels = new_labels
		# update
		for ci in range(k):
			mask = labels == ci
			if np.any(mask):
				centroids[ci] = np.mean(coords[mask], axis=0)
	return centroids, labels


def _stable_embed(text: str, dim: int = 128) -> list[float]:
	"""
	Deterministic, dependency-free embedding placeholder (v1 scaffolding).
	Not a semantic embedding model; intended to stabilize the job contract until a real
	embedding backend is introduced.
	"""
	dim = max(8, min(int(dim), 2048))
	h = hashlib.sha256(text.encode("utf-8", errors="ignore")).digest()
	# Expand digest deterministically
	buf = bytearray()
	seed = h
	while len(buf) < dim:
		seed = hashlib.sha256(seed).digest()
		buf.extend(seed)
	arr = np.frombuffer(bytes(buf[:dim]), dtype=np.uint8).astype(np.float64)
	# Map to [-1,1] and normalize
	v = (arr / 127.5) - 1.0
	n = np.linalg.norm(v)
	if n > 0:
		v = v / n
	return v.tolist()


def _bridges_from_clusters(coords: np.ndarray, labels: np.ndarray) -> list[Dict[str, Any]]:
	"""
	Compute "bridge" candidates: points close to the boundary between their cluster and the nearest other cluster.
	Returns list of {item_index, cluster_a, cluster_b, score}.
	"""
	if coords.ndim != 2:
		raise ValueError("coords must be 2D")
	if labels.ndim != 1:
		raise ValueError("labels must be 1D")
	k = int(np.max(labels)) + 1 if labels.size > 0 else 0
	if k <= 1:
		return []
	centroids = np.vstack([np.mean(coords[labels == i], axis=0) for i in range(k)])
	out: list[Dict[str, Any]] = []
	for i in range(coords.shape[0]):
		ci = int(labels[i])
		d2 = np.sum((centroids - coords[i]) ** 2, axis=1)
		order = np.argsort(d2)
		a = int(order[0])
		b = int(order[1])
		if a != ci:
			# Fallback if cluster label doesn't match nearest centroid (can happen with empty clusters)
			a = ci
		# Margin: smaller margin => more bridge-like
		margin = float(d2[b] - d2[a])
		score = 1.0 / (1.0 + margin)
		out.append({"item_index": i, "cluster_a": a, "cluster_b": b, "score": score})
	# Return top-N by score
	out.sort(key=lambda x: x["score"], reverse=True)
	return out[: min(50, len(out))]


def _hubs_from_knn(coords: np.ndarray, k: int = 8) -> list[Dict[str, Any]]:
	"""
	Compute "hub" candidates using kNN degree in coordinate space.
	Returns list of {item_index, degree, score}.
	"""
	if coords.ndim != 2:
		raise ValueError("coords must be 2D")
	n = coords.shape[0]
	if n <= 1:
		return []
	k = max(1, min(int(k), n - 1))
	# Pairwise distances (n is expected modest for v1 UI; scale later via ANN)
	d2 = np.sum((coords[:, None, :] - coords[None, :, :]) ** 2, axis=2)
	np.fill_diagonal(d2, np.inf)
	knn = np.argsort(d2, axis=1)[:, :k]
	deg = np.zeros((n,), dtype=np.int32)
	for i in range(n):
		for j in knn[i]:
			deg[int(j)] += 1
	max_deg = int(np.max(deg)) if n > 0 else 1
	out = [{"item_index": int(i), "degree": int(deg[i]), "score": float(deg[i]) / float(max_deg or 1)} for i in range(n)]
	out.sort(key=lambda x: x["degree"], reverse=True)
	return out[: min(50, len(out))]


async def run_job(job_id: str, app) -> None:
	"""
	Run a job. Called by the background job runner loop.
	"""
	# `app` is the FastAPI instance
	repo = getattr(app.state, "substrate_repo", None)
	cfg = getattr(app.state, "cfg", None)
	if not repo or not cfg or not cfg.workspace:
		return
	job = await repo.get_job(job_id)
	if not job:
		return
	status0 = str(job.get("status") or "").strip().lower()
	# Queue items can become stale (e.g. user canceled before worker picked it up).
	if status0 != "queued":
		return

	bus = app.state.event_bus
	job_type = str(job.get("job_type") or "")
	input_pack = job.get("input_json") or {}
	payload = input_pack.get("input") or {}
	output_target = input_pack.get("output_target") or {}
	meta = input_pack.get("metadata") or {}
	session_id: Optional[str] = output_target.get("session_id") if isinstance(output_target, dict) else None

	seq = 1
	def emit(event_type: str, p: Dict[str, Any]) -> None:
		nonlocal seq
		seq += 1
		return bus.publish(
			make_event_envelope(
				event_type=event_type,
				source_id="jobs",
				seq=seq,
				payload=p,
				provenance={"job_id": job_id, "session_id": session_id} if session_id else {"job_id": job_id},
			)
		)

	started_at = time.time()
	await repo.update_job_status(job_id, status="started", started_at=started_at)
	await repo.commit()
	await emit("job.started", {"job_id": job_id, "type": job_type})

	store = ArtifactStore(cfg.workspace.artifacts_dir)

	try:
		if job_type == "render.batch":
			render_batch_request = payload.get("render_batch_request") if isinstance(payload, dict) else None
			if not isinstance(render_batch_request, dict):
				raise ValueError("render_batch_request is required")
			items = render_batch_request.get("items") if isinstance(render_batch_request.get("items"), list) else []
			if not items:
				raise ValueError("render_batch_request.items must be a non-empty array")
			job_queue = getattr(app.state, "job_queue", None)
			if job_queue is None:
				raise ValueError("job queue unavailable")

			client = render_batch_request.get("client") if isinstance(render_batch_request.get("client"), dict) else {}
			request_id = str(client.get("request_id") or "").strip()
			turn_id = str(client.get("turn_id") or "").strip()
			batch_artifact_type = "json.render_batch_request"

			async def emit_render_batch(event_type: str, p: Dict[str, Any]) -> None:
				evt = make_event_envelope(
					event_type=event_type,
					source_id="render",
					seq=1,
					payload=p,
					provenance={"job_id": job_id, "session_id": session_id} if session_id else {"job_id": job_id},
				)
				await bus.publish(evt)
				await repo.insert_event(evt)
				await repo.commit()

			batch_art_id, batch_uri, batch_hash = store.write_json(batch_artifact_type, render_batch_request, "json")
			created_batch_art_id = await repo.insert_artifact(
				{
					"id": batch_art_id,
					"artifact_type": batch_artifact_type,
					"uri": batch_uri,
					"hash": batch_hash,
					"metadata": {
						"provenance": {
							"generated_by": "synesyn_hub.render.batch.submit",
							"session_id": session_id,
							"turn_id": turn_id,
							"request_id": request_id,
							"job_id": job_id,
						}
					},
				}
			)
			await repo.commit()
			await emit_render_batch(
				"render.batch.started",
				{
					"job_id": job_id,
					"request_id": request_id,
					"render_batch_request_artifact_id": created_batch_art_id,
					"item_count": len(items),
				},
			)

			child_job_ids: list[str] = []
			child_items: list[Dict[str, Any]] = []
			for idx, item_any in enumerate(items):
				if not isinstance(item_any, dict):
					raise ValueError(f"render batch item {idx} must be an object")
				item = item_any
				render_request = item.get("request") if isinstance(item.get("request"), dict) else None
				if not isinstance(render_request, dict):
					raise ValueError(f"render batch item {idx} missing request")
				routing = render_request.get("routing") if isinstance(render_request.get("routing"), dict) else {}
				provider = str(routing.get("provider") or "").strip().lower()
				if provider != "comfyui":
					raise ValueError(f"render batch item {idx} uses unsupported provider: {provider}")

				item_id = str(item.get("item_id") or f"item_{idx+1}").strip()
				item_meta = item.get("metadata") if isinstance(item.get("metadata"), dict) else {}
				child_client = render_request.get("client") if isinstance(render_request.get("client"), dict) else {}
				child_request_id = str(
					item_meta.get("request_id")
					or child_client.get("request_id")
					or ("%s_%02d" % (request_id if request_id else job_id, idx + 1))
				).strip()

				child_job_id = await repo.create_job(
					{
						"job_type": "render.comfyui",
						"status": "queued",
						"input": {"input": {"render_request": render_request}, "output_target": {"session_id": session_id}, "metadata": {}},
						"metadata": {
							"request_id": child_request_id,
							"session_id": session_id,
							"batch_job_id": job_id,
							"batch_item_id": item_id,
							"batch_index": idx,
							"batch_render_request_artifact_id": created_batch_art_id,
						},
					}
				)
				child_job_ids.append(child_job_id)
				child_items.append({"item_id": item_id, "job_id": child_job_id, "metadata": item_meta})
				child_evt = make_event_envelope(
					event_type="render.queued",
					source_id="render",
					seq=1,
					payload={
						"job_id": child_job_id,
						"request_id": child_request_id,
						"provider": "comfyui",
						"batch_job_id": job_id,
						"batch_item_id": item_id,
					},
					provenance={"job_id": child_job_id, "session_id": session_id} if session_id else {"job_id": child_job_id},
				)
				await bus.publish(child_evt)
				await repo.insert_event(child_evt)
				await job_queue.put(child_job_id)

			await repo.commit()
			await repo.update_job_status(
				job_id,
				status="completed",
				completed_at=time.time(),
				output={
					"child_job_ids": child_job_ids,
					"items": child_items,
					"render_batch_request_artifact_id": created_batch_art_id,
				},
				artifacts=[{"artifact_id": created_batch_art_id, "artifact_type": batch_artifact_type, "uri": batch_uri}],
			)
			await repo.commit()
			await emit_render_batch(
				"render.batch.completed",
				{
					"job_id": job_id,
					"item_count": len(items),
					"child_job_ids": child_job_ids,
					"render_batch_request_artifact_id": created_batch_art_id,
				},
			)
			await emit("job.completed", {"job_id": job_id, "child_job_ids": child_job_ids})
			return

		if job_type == "render.comfyui":
			render_request = payload.get("render_request") if isinstance(payload, dict) else None
			if not isinstance(render_request, dict):
				raise ValueError("render_request is required")

			routing = render_request.get("routing") if isinstance(render_request.get("routing"), dict) else {}
			comfy_url = str(routing.get("comfy_base_url") or "").strip()
			if not comfy_url:
				raise ValueError("routing.comfy_base_url is required for render.comfyui")

			client = render_request.get("client") if isinstance(render_request.get("client"), dict) else {}
			client_id = str(client.get("client_id") or "").strip() or f"hub_{job_id}"
			request_id = str(client.get("request_id") or "").strip()
			turn_id = str(client.get("turn_id") or "").strip()

			output_routing = render_request.get("output_routing") if isinstance(render_request.get("output_routing"), dict) else {}
			images_cfg = output_routing.get("images") if isinstance(output_routing.get("images"), dict) else {}
			image_artifact_type = str(images_cfg.get("artifact_type") or "image.generated").strip() or "image.generated"
			rr_artifact_type = str(output_routing.get("render_request_artifact_type") or "json.render_request").strip() or "json.render_request"

			# --- helper: emit render.* events (separate from job.*)
			render_seq = 1

			async def emit_render(event_type: str, p: Dict[str, Any]) -> None:
				nonlocal render_seq
				render_seq += 1
				evt = make_event_envelope(
					event_type=event_type,
					source_id="render",
					seq=render_seq,
					payload=p,
					provenance={"job_id": job_id, "session_id": session_id} if session_id else {"job_id": job_id},
				)
				await bus.publish(evt)
				# Persist render events for auditability/replay.
				await repo.insert_event(evt)
				await repo.commit()

			# Persist render_request artifact (stable replay) early.
			rr_art_id, rr_uri, rr_hash = store.write_json(rr_artifact_type, render_request, "json")
			created_rr_id = await repo.insert_artifact(
				{
					"id": rr_art_id,
					"artifact_type": rr_artifact_type,
					"uri": rr_uri,
					"hash": rr_hash,
					"metadata": {
						"provenance": {
							"generated_by": "synesyn_hub.render.submit",
							"session_id": session_id,
							"turn_id": turn_id,
							"request_id": request_id,
							"job_id": job_id,
						}
					},
				}
			)
			await repo.commit()

			await emit_render(
				"render.started",
				{"job_id": job_id, "request_id": request_id, "render_request_artifact_id": created_rr_id, "provider": "comfyui"},
			)

			# Resolve workflow
			wf = render_request.get("workflow") if isinstance(render_request.get("workflow"), dict) else {}
			workflow: Dict[str, Any] = {}

			def _uri_to_path(uri: str) -> Path:
				u = (uri or "").strip()
				if u.startswith("file://"):
					parsed = urlparse(u)
					p = unquote(parsed.path or "")
					# Windows file URIs often look like /C:/...
					if len(p) > 2 and p[0] == "/" and p[2] == ":":
						p = p[1:]
					return Path(p)
				return Path(u)

			def _row_to_dict(cols: list[str], row: Any) -> Dict[str, Any]:
				return {cols[i]: row[i] for i in range(len(cols))}

			inline = wf.get("inline")
			if isinstance(inline, dict):
				workflow = inline
			else:
				artifact_id = str(wf.get("artifact_id") or "").strip()
				if not artifact_id:
					raise ValueError("workflow.inline or workflow.artifact_id required")
				qr = await repo.query({"table": "artifacts", "where": {"id": artifact_id}, "limit": 1})
				cols = qr.get("columns") or []
				rows = qr.get("rows") or []
				if not rows:
					raise ValueError(f"Workflow artifact not found: {artifact_id}")
				rec = _row_to_dict([str(c) for c in cols], rows[0])
				uri = str(rec.get("uri") or "").strip()
				if not uri:
					raise ValueError(f"Workflow artifact has no uri: {artifact_id}")
				path = _uri_to_path(uri)
				raw = path.read_text(encoding="utf-8")
				obj = json.loads(raw) if raw else {}
				if not isinstance(obj, dict):
					raise ValueError("Workflow JSON must be an object")
				workflow = obj

			patches = render_request.get("patches") if isinstance(render_request.get("patches"), list) else []
			if patches:
				# Apply patches (same stable schema as the Godot-side bridge).
				wf2: Dict[str, Any] = copy.deepcopy(workflow)
				for p in patches:
					if not isinstance(p, dict):
						continue
					node_id = str(p.get("node_id") or "").strip()
					input_key = str(p.get("input") or "").strip()
					if not node_id or not input_key:
						continue
					node = wf2.get(node_id)
					if not isinstance(node, dict):
						continue
					inputs = node.get("inputs")
					if not isinstance(inputs, dict):
						inputs = {}
					inputs[input_key] = p.get("value", None)
					node["inputs"] = inputs
					wf2[node_id] = node
				workflow = wf2
			workflow = await comfy_media.apply_input_uploads(comfy_url, workflow, render_request.get("input_uploads"), repo=repo)

			# Provenance extraction
			workflow_hash_sha256 = hashlib.sha256(
				json.dumps(workflow, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
			).hexdigest()

			seed_values: list[Any] = []
			seed_offsets: list[Dict[str, Any]] = []
			for p in patches:
				if not isinstance(p, dict):
					continue
				k = str(p.get("input") or "").strip().lower()
				if not k:
					continue
				if k == "seed" or "seed" in k:
					seed_values.append(p.get("value"))
				if "offset" in k:
					seed_offsets.append({"input": k, "value": p.get("value")})
			seed_info = {"seeds": seed_values, "offsets": seed_offsets}

			model_identifiers: list[str] = []
			for _nid, node_any in workflow.items():
				if not isinstance(node_any, dict):
					continue
				ins = node_any.get("inputs")
				if not isinstance(ins, dict):
					continue
				for kk in ("ckpt_name", "checkpoint", "model_name", "vae_name", "lora_name"):
					val = str(ins.get(kk) or "").strip()
					if val and val not in model_identifiers:
						model_identifiers.append(val)

			refs = render_request.get("refs") if isinstance(render_request.get("refs"), dict) else {}
			prompt_artifact_id = str(refs.get("prompt_artifact_id") or "").strip()
			sensor_snapshot_artifact_id = str(refs.get("sensor_snapshot_artifact_id") or "").strip()
			workflow_artifact_id = str(wf.get("artifact_id") or refs.get("workflow_artifact_id") or "").strip()

			# Submit to ComfyUI
			await emit_render("render.progress", {"job_id": job_id, "stage": "submit", "percent": 5.0})
			prompt_id = await comfyui.submit_workflow(comfy_url, workflow, client_id=client_id)
			await emit_render("render.progress", {"job_id": job_id, "stage": "queued", "prompt_id": prompt_id, "percent": 10.0})

			# Poll for completion (best-effort progress is time-based).
			# vis_story_v2_turn is an orchestration request: the scheduler prompt can
			# complete without direct image outputs in its own history entry because it
			# enqueues downstream panel prompts into ComfyUI.
			scensyn_ref = refs.get("scensyn") if isinstance(refs.get("scensyn"), dict) else {}
			render_purpose_ref = str(scensyn_ref.get("render_purpose") or "").strip()
			require_history_outputs = render_purpose_ref != "vis_story_v2_turn"
			def _on_progress(pct: float) -> None:
				# fire-and-forget (don’t block polling)
				asyncio.create_task(
					emit_render("render.progress", {"job_id": job_id, "stage": "poll_history", "prompt_id": prompt_id, "percent": float(pct)})
				)

			history_entry = await comfyui.poll_history_until_done(
				comfy_url,
				prompt_id,
				timeout_sec=min(max(float(render_request.get("timeout_sec") or 180.0), 1.0), 1800.0),
				poll_interval_sec=0.75,
				require_outputs=require_history_outputs,
				on_progress=_on_progress,
			)

			# Fetch images + persist artifacts
			outputs = history_entry.get("outputs") if isinstance(history_entry.get("outputs"), dict) else {}
			image_artifact_ids: list[str] = []
			artifacts_out: list[Dict[str, Any]] = []

			final_image_artifact_ids: list[str] = []
			media_artifact_ids: list[str] = []

			for node_id, out_files in comfy_media.output_files_by_node(outputs, output_routing):
				for img_any in out_files:
					filename, subfolder, typ = img_any["filename"], img_any["subfolder"], img_any["type"]
					out_type = comfy_media.artifact_type_for(img_any["kind"], output_routing, image_artifact_type)
					_fn_lower = filename.lower()
					_sf_lower = subfolder.lower()
					_intermediate_markers = [
						"seam_edge_map", "micro_line_map", "height_map", "surface_image",
						"byte_luma_map", "semantic_field_map", "semantic_edge_map",
						"graded_surface_image", "region_id_map", "region_map",
						"stfx_region", "spectre_region", "sketch",
					]
					_is_intermediate = any(m in _fn_lower or m in _sf_lower for m in _intermediate_markers)
					is_final = not _is_intermediate
					await emit_render("render.progress", {"job_id": job_id, "stage": "fetch_image", "prompt_id": prompt_id, "node_id": str(node_id), "percent": 90.0})
					data, ext = await comfyui.fetch_image_bytes(comfy_url, filename=filename, subfolder=subfolder, typ=typ)
					art_id, uri, h = store.write_bytes(out_type, data, ext)
					meta = {
						"provenance": {
							"generated_by": "synesyn_hub.render.comfyui",
							"job_id": job_id,
							"session_id": session_id,
							"turn_id": turn_id,
							"request_id": request_id,
							"route_mode": "hub",
							"route_provider": "comfyui",
							"prompt_id": prompt_id,
							"comfy_url": comfy_url,
							"node_id": str(node_id),
							"filename": filename,
							"subfolder": subfolder,
							"is_final_output": is_final,
							"workflow_hash_sha256": workflow_hash_sha256,
							"seed_info": seed_info,
							"model_identifiers": model_identifiers,
							"workflow_patch_set": patches,
							"input_uploads": render_request.get("input_uploads") or [],
							"inputs": [
								({"artifact_id": workflow_artifact_id, "artifact_type": "json.workflow"} if workflow_artifact_id else None),
								({"artifact_id": created_rr_id, "artifact_type": rr_artifact_type}),
								({"artifact_id": prompt_artifact_id, "artifact_type": "text.prompt"} if prompt_artifact_id else None),
								({"artifact_id": sensor_snapshot_artifact_id, "artifact_type": "json.sensor_snapshot"} if sensor_snapshot_artifact_id else None),
							],
						},
						"refs": refs,
					}
					# prune None entries from provenance.inputs
					if isinstance(meta["provenance"].get("inputs"), list):
						meta["provenance"]["inputs"] = [x for x in meta["provenance"]["inputs"] if x]
					created_id = await repo.insert_artifact({"id": art_id, "artifact_type": out_type, "uri": uri, "hash": h, "metadata": meta})
					artifacts_out.append({"artifact_id": created_id, "artifact_type": out_type, "uri": uri, "is_final_output": is_final})
					if out_type != image_artifact_type:
						media_artifact_ids.append(created_id)
						continue
					image_artifact_ids.append(created_id)
					if is_final:
						final_image_artifact_ids.append(created_id)

			await repo.commit()

			await repo.update_job_status(
				job_id,
				status="completed",
				completed_at=time.time(),
				output={
					"prompt_id": prompt_id,
					"image_artifact_ids": image_artifact_ids,
					"final_image_artifact_ids": final_image_artifact_ids,
					"media_artifact_ids": media_artifact_ids,
					"render_request_artifact_id": created_rr_id,
				},
				artifacts=artifacts_out,
			)
			await repo.commit()
			await emit_render(
				"render.completed",
				{
					"job_id": job_id,
					"prompt_id": prompt_id,
					"render_request_artifact_id": created_rr_id,
					"image_artifact_ids": image_artifact_ids,
					"final_image_artifact_ids": final_image_artifact_ids,
					"media_artifact_ids": media_artifact_ids,
					"artifacts": artifacts_out,
				},
			)
			return

		if job_type == "synaxes.project":
			item_ids = payload.get("item_ids") or []
			vectors = payload.get("vectors") or []
			dim = int(payload.get("dim") or 3)
			method = str(payload.get("method") or "pca")
			if method != "pca":
				raise ValueError("v0 supports only method=pca")
			if not isinstance(item_ids, list) or not isinstance(vectors, list) or len(item_ids) != len(vectors):
				raise ValueError("item_ids and vectors must be lists of equal length")
			if dim not in (2, 3):
				raise ValueError("dim must be 2 or 3")

			await emit("job.progress", {"job_id": job_id, "stage": "project", "phase": "compute", "percent": 25})
			coords_arr = _pca_project(vectors=vectors, dim=dim)
			coords: Dict[str, Any] = {}
			for i, iid in enumerate(item_ids):
				vec = coords_arr[i].tolist()
				coords[str(iid)] = vec
			await emit("job.progress", {"job_id": job_id, "stage": "project", "phase": "persist", "percent": 75})
			artifact_type = "coords.projection_3d" if dim == 3 else "coords.projection_2d"
			proj_payload = {
				"schema_version": 1,
				"method": method,
				"dim": dim,
				"coords": coords,
			}
			proj_meta = {
				"provenance": {
					"generated_by": "synesyn_hub.jobs.synaxes.project",
					"parameters": {"method": method, "dim": dim},
					"session_id": session_id,
				}
			}
			art_id, uri, h = store.write_json(artifact_type, proj_payload, "json")
			created_id = await repo.insert_artifact(
				{"id": art_id, "artifact_type": artifact_type, "uri": uri, "hash": h, "metadata": proj_meta}
			)
			await repo.commit()
			await emit("job.progress", {"job_id": job_id, "stage": "project", "phase": "finalize", "percent": 95})

			artifacts = [{"artifact_id": created_id, "artifact_type": artifact_type, "uri": uri}]
			await repo.update_job_status(
				job_id,
				status="completed",
				completed_at=time.time(),
				output={"projection_artifact_id": created_id},
				artifacts=artifacts,
			)
			await repo.commit()
			await emit("job.completed", {"job_id": job_id, "artifacts": artifacts})
			return

		if job_type == "synaxes.cluster":
			# Accept either coords dict OR vectors+item_ids.
			item_ids = payload.get("item_ids") or []
			coords_map = payload.get("coords")
			vectors = payload.get("vectors") or []
			k = int(payload.get("k") or 5)
			seed = int(payload.get("seed") or 1337)

			if isinstance(coords_map, dict):
				item_ids = list(coords_map.keys())
				coords_arr = np.asarray([coords_map[iid] for iid in item_ids], dtype=np.float64)
			else:
				if not isinstance(item_ids, list) or not isinstance(vectors, list) or len(item_ids) != len(vectors):
					raise ValueError("Provide coords dict OR item_ids+vectors (equal length)")
				coords_arr = _pca_project(vectors=vectors, dim=3)

			await emit("job.progress", {"job_id": job_id, "stage": "cluster", "phase": "compute", "percent": 25})
			centroids, labels = _kmeans(coords_arr, k=k, seed=seed, iters=25)

			clusters_out = []
			for ci in range(centroids.shape[0]):
				member_ids = [str(item_ids[i]) for i in range(len(item_ids)) if int(labels[i]) == int(ci)]
				clusters_out.append(
					{
						"cluster_id": int(ci),
						"item_ids": member_ids,
						"center": centroids[ci].tolist(),
						"confidence": 1.0,  # v0 placeholder
					}
				)

			cluster_payload = {
				"schema_version": 1,
				"method": "kmeans",
				"k": k,
				"clusters": clusters_out,
			}
			cluster_meta = {
				"provenance": {
					"generated_by": "synesyn_hub.jobs.synaxes.cluster",
					"parameters": {"k": k, "seed": seed},
					"session_id": session_id,
				}
			}
			await emit("job.progress", {"job_id": job_id, "stage": "cluster", "phase": "persist", "percent": 75})
			artifact_type = "graph.cluster_result"
			art_id, uri, h = store.write_json(artifact_type, cluster_payload, "json")
			created_id = await repo.insert_artifact(
				{"id": art_id, "artifact_type": artifact_type, "uri": uri, "hash": h, "metadata": cluster_meta}
			)
			await repo.commit()
			await emit("job.progress", {"job_id": job_id, "stage": "cluster", "phase": "finalize", "percent": 95})

			artifacts = [{"artifact_id": created_id, "artifact_type": artifact_type, "uri": uri}]
			await repo.update_job_status(
				job_id,
				status="completed",
				completed_at=time.time(),
				output={"cluster_artifact_id": created_id},
				artifacts=artifacts,
			)
			await repo.commit()
			await emit("job.completed", {"job_id": job_id, "artifacts": artifacts})
			return

		if job_type == "synaxes.embed_text":
			item_ids = payload.get("item_ids") or []
			texts = payload.get("texts") or []
			dim = int(payload.get("dim") or 128)
			if not isinstance(item_ids, list) or not isinstance(texts, list) or len(item_ids) != len(texts):
				raise ValueError("item_ids and texts must be lists of equal length")

			await emit("job.progress", {"job_id": job_id, "stage": "embed_text", "phase": "compute", "percent": 25})
			vecs: Dict[str, Any] = {}
			for i, iid in enumerate(item_ids):
				vecs[str(iid)] = _stable_embed(str(texts[i]), dim=dim)

			await emit("job.progress", {"job_id": job_id, "stage": "embed_text", "phase": "persist", "percent": 75})
			artifact_type = "embeddings.text"
			out_payload = {"schema_version": 1, "dim": dim, "vectors": vecs}
			out_meta = {
				"provenance": {
					"generated_by": "synesyn_hub.jobs.synaxes.embed_text",
					"parameters": {"dim": dim},
					"session_id": session_id,
				}
			}
			art_id, uri, h = store.write_json(artifact_type, out_payload, "json")
			created_id = await repo.insert_artifact({"id": art_id, "artifact_type": artifact_type, "uri": uri, "hash": h, "metadata": out_meta})
			await repo.commit()
			await emit("job.progress", {"job_id": job_id, "stage": "embed_text", "phase": "finalize", "percent": 95})

			artifacts = [{"artifact_id": created_id, "artifact_type": artifact_type, "uri": uri}]
			await repo.update_job_status(job_id, status="completed", completed_at=time.time(), output={"embeddings_artifact_id": created_id}, artifacts=artifacts)
			await repo.commit()
			await emit("job.completed", {"job_id": job_id, "artifacts": artifacts})
			return

		if job_type == "synaxes.embed_image":
			# v1 scaffolding: accept ids + image hashes/uris and return deterministic vectors based on that identifier.
			item_ids = payload.get("item_ids") or []
			refs = payload.get("image_refs") or payload.get("hashes") or payload.get("uris") or []
			dim = int(payload.get("dim") or 128)
			if not isinstance(item_ids, list) or not isinstance(refs, list) or len(item_ids) != len(refs):
				raise ValueError("item_ids and image_refs must be lists of equal length")

			await emit("job.progress", {"job_id": job_id, "stage": "embed_image", "phase": "compute", "percent": 25})
			vecs: Dict[str, Any] = {}
			for i, iid in enumerate(item_ids):
				vecs[str(iid)] = _stable_embed(str(refs[i]), dim=dim)

			await emit("job.progress", {"job_id": job_id, "stage": "embed_image", "phase": "persist", "percent": 75})
			artifact_type = "embeddings.image"
			out_payload = {"schema_version": 1, "dim": dim, "vectors": vecs}
			out_meta = {
				"provenance": {
					"generated_by": "synesyn_hub.jobs.synaxes.embed_image",
					"parameters": {"dim": dim},
					"session_id": session_id,
				}
			}
			art_id, uri, h = store.write_json(artifact_type, out_payload, "json")
			created_id = await repo.insert_artifact({"id": art_id, "artifact_type": artifact_type, "uri": uri, "hash": h, "metadata": out_meta})
			await repo.commit()
			await emit("job.progress", {"job_id": job_id, "stage": "embed_image", "phase": "finalize", "percent": 95})

			artifacts = [{"artifact_id": created_id, "artifact_type": artifact_type, "uri": uri}]
			await repo.update_job_status(job_id, status="completed", completed_at=time.time(), output={"embeddings_artifact_id": created_id}, artifacts=artifacts)
			await repo.commit()
			await emit("job.completed", {"job_id": job_id, "artifacts": artifacts})
			return

		if job_type == "synaxes.bridges":
			# Input: coords dict + cluster labels dict (item_id -> cluster_id), or arrays.
			coords_map = payload.get("coords") or {}
			labels_map = payload.get("labels") or {}
			if not isinstance(coords_map, dict) or not isinstance(labels_map, dict):
				raise ValueError("coords and labels must be objects")
			item_ids = list(coords_map.keys())
			if not item_ids:
				raise ValueError("coords empty")
			coords_arr = np.asarray([coords_map[iid] for iid in item_ids], dtype=np.float64)
			labels_arr = np.asarray([labels_map.get(iid, 0) for iid in item_ids], dtype=np.int32)

			await emit("job.progress", {"job_id": job_id, "stage": "bridges", "phase": "compute", "percent": 25})
			bridges = _bridges_from_clusters(coords_arr, labels_arr)
			bridges_out = [
				{
					"item_id": str(item_ids[int(b["item_index"])]),
					"cluster_a": int(b["cluster_a"]),
					"cluster_b": int(b["cluster_b"]),
					"score": float(b["score"]),
				}
				for b in bridges
			]
			await emit("job.progress", {"job_id": job_id, "stage": "bridges", "phase": "persist", "percent": 75})
			artifact_type = "graph.bridge_result"
			out_payload = {"schema_version": 1, "method": "centroid_margin", "bridges": bridges_out}
			out_meta = {"provenance": {"generated_by": "synesyn_hub.jobs.synaxes.bridges", "parameters": {}, "session_id": session_id}}
			art_id, uri, h = store.write_json(artifact_type, out_payload, "json")
			created_id = await repo.insert_artifact({"id": art_id, "artifact_type": artifact_type, "uri": uri, "hash": h, "metadata": out_meta})
			await repo.commit()
			await emit("job.progress", {"job_id": job_id, "stage": "bridges", "phase": "finalize", "percent": 95})

			artifacts = [{"artifact_id": created_id, "artifact_type": artifact_type, "uri": uri}]
			await repo.update_job_status(job_id, status="completed", completed_at=time.time(), output={"bridge_artifact_id": created_id}, artifacts=artifacts)
			await repo.commit()
			await emit("job.completed", {"job_id": job_id, "artifacts": artifacts})
			return

		if job_type == "synaxes.hubs":
			coords_map = payload.get("coords") or {}
			if not isinstance(coords_map, dict):
				raise ValueError("coords must be an object")
			item_ids = list(coords_map.keys())
			if not item_ids:
				raise ValueError("coords empty")
			coords_arr = np.asarray([coords_map[iid] for iid in item_ids], dtype=np.float64)
			k = int(payload.get("k") or 8)

			await emit("job.progress", {"job_id": job_id, "stage": "hubs", "phase": "compute", "percent": 25})
			hubs = _hubs_from_knn(coords_arr, k=k)
			hubs_out = [{"item_id": str(item_ids[int(h["item_index"])]), "degree": int(h["degree"]), "score": float(h["score"])} for h in hubs]

			await emit("job.progress", {"job_id": job_id, "stage": "hubs", "phase": "persist", "percent": 75})
			artifact_type = "graph.hub_result"
			out_payload = {"schema_version": 1, "method": "knn_degree", "k": k, "hubs": hubs_out}
			out_meta = {"provenance": {"generated_by": "synesyn_hub.jobs.synaxes.hubs", "parameters": {"k": k}, "session_id": session_id}}
			art_id, uri, h = store.write_json(artifact_type, out_payload, "json")
			created_id = await repo.insert_artifact({"id": art_id, "artifact_type": artifact_type, "uri": uri, "hash": h, "metadata": out_meta})
			await repo.commit()
			await emit("job.progress", {"job_id": job_id, "stage": "hubs", "phase": "finalize", "percent": 95})

			artifacts = [{"artifact_id": created_id, "artifact_type": artifact_type, "uri": uri}]
			await repo.update_job_status(job_id, status="completed", completed_at=time.time(), output={"hub_artifact_id": created_id}, artifacts=artifacts)
			await repo.commit()
			await emit("job.completed", {"job_id": job_id, "artifacts": artifacts})
			return

		raise ValueError(f"Unknown job type: {job_type}")

	except Exception as e:
		await repo.update_job_status(job_id, status="failed", completed_at=time.time(), error=str(e))
		await repo.commit()
		# If this was a render job, also emit render.failed (separate from job.*).
		if job_type == "render.comfyui":
			req_id = None
			if isinstance(meta, dict):
				req_id = meta.get("request_id")
			evt = make_event_envelope(
				event_type="render.failed",
				source_id="render",
				seq=9999,  # best-effort; consumers should not rely on strict seq across restarts
				payload={"job_id": job_id, "request_id": req_id, "error": str(e), "provider": "comfyui"},
				provenance={"job_id": job_id, "session_id": session_id} if session_id else {"job_id": job_id},
			)
			await bus.publish(evt)
			await repo.insert_event(evt)
			await repo.commit()
		await emit("job.failed", {"job_id": job_id, "error": str(e)})


