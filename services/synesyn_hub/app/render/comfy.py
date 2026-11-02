from __future__ import annotations

import asyncio
import json
import time
import uuid
from typing import Any, Callable, Dict, Optional, Tuple
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def _post_json_sync(url: str, payload: Dict[str, Any], timeout_sec: float = 20.0) -> Dict[str, Any]:
	"""
	Minimal JSON POST without new deps.
	Run in a worker thread via asyncio.to_thread.
	"""
	body = json.dumps(payload).encode("utf-8")
	req = Request(url=url, data=body, headers={"Content-Type": "application/json", "Accept": "application/json"}, method="POST")
	with urlopen(req, timeout=timeout_sec) as resp:
		raw = resp.read().decode("utf-8") if resp else ""
		obj = json.loads(raw) if raw else {}
		return obj if isinstance(obj, dict) else {"ok": False, "error": "invalid_json", "raw": raw}


def _get_json_sync(url: str, timeout_sec: float = 12.0) -> Dict[str, Any]:
	req = Request(url=url, headers={"Accept": "application/json"}, method="GET")
	with urlopen(req, timeout=timeout_sec) as resp:
		raw = resp.read().decode("utf-8") if resp else ""
		obj = json.loads(raw) if raw else {}
		return obj if isinstance(obj, dict) else {"ok": False, "error": "invalid_json", "raw": raw}


def _get_bytes_sync(url: str, timeout_sec: float = 30.0) -> bytes:
	req = Request(url=url, headers={"Accept": "*/*"}, method="GET")
	with urlopen(req, timeout=timeout_sec) as resp:
		return resp.read() if resp else b""


def multipart_body(fields: Dict[str, str], *, file_field: str, filename: str, data: bytes) -> Tuple[bytes, str]:
	"""Encode form fields plus one file as multipart/form-data. Returns (body, content_type)."""
	boundary = f"----synesyn{uuid.uuid4().hex}"
	parts: list[bytes] = []
	for key, value in fields.items():
		parts.append(
			f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode("utf-8")
		)
	safe_name = filename.replace('"', "_")
	parts.append(
		(
			f'--{boundary}\r\nContent-Disposition: form-data; name="{file_field}"; filename="{safe_name}"\r\n'
			"Content-Type: application/octet-stream\r\n\r\n"
		).encode("utf-8")
		+ data
		+ b"\r\n"
	)
	parts.append(f"--{boundary}--\r\n".encode("utf-8"))
	return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def _post_multipart_sync(url: str, body: bytes, content_type: str, timeout_sec: float = 60.0) -> Dict[str, Any]:
	req = Request(url=url, data=body, headers={"Content-Type": content_type, "Accept": "application/json"}, method="POST")
	with urlopen(req, timeout=timeout_sec) as resp:
		raw = resp.read().decode("utf-8") if resp else ""
		obj = json.loads(raw) if raw else {}
		return obj if isinstance(obj, dict) else {"ok": False, "error": "invalid_json", "raw": raw}


async def upload_input(base_url: str, data: bytes, *, filename: str, subfolder: str = "synesyn") -> str:
	"""
	Put a file into the input folder of a ComfyUI that may be on another machine, and
	return the name a LoadImage / LoadAudio node takes ("subfolder/name").

	ComfyUI's /upload/image endpoint stores any file type, audio included.
	"""
	base = (base_url or "").strip().rstrip("/")
	if not base:
		raise ValueError("comfy_base_url is required")
	fields = {"type": "input", "overwrite": "true"}
	if subfolder:
		fields["subfolder"] = subfolder
	body, content_type = multipart_body(fields, file_field="image", filename=filename, data=data)
	res = await asyncio.to_thread(_post_multipart_sync, f"{base}/upload/image", body, content_type, 60.0)
	name = str(res.get("name") or "").strip()
	if not name:
		raise ValueError(f"ComfyUI upload returned no name: {res}")
	sub = str(res.get("subfolder") or "").strip()
	return f"{sub}/{name}" if sub else name


MEDIA_EXTS = ("png", "jpg", "jpeg", "webp", "gif", "mp4", "webm", "mov", "mkv", "ogv", "wav", "mp3", "flac", "ogg")


def ext_for_filename(filename: str) -> str:
	low = (filename or "").strip().lower()
	for e in MEDIA_EXTS:
		if low.endswith("." + e):
			return "jpg" if e == "jpeg" else e
	return "png"


async def submit_workflow(base_url: str, workflow: Dict[str, Any], *, client_id: str) -> str:
	base = (base_url or "").strip().rstrip("/")
	if not base:
		raise ValueError("comfy_base_url is required")
	res = await asyncio.to_thread(_post_json_sync, f"{base}/prompt", {"prompt": workflow, "client_id": client_id}, 30.0)
	pid = str(res.get("prompt_id") or "").strip()
	if not pid:
		raise ValueError(f"ComfyUI missing prompt_id: {res}")
	return pid


async def poll_history_until_done(
	base_url: str,
	prompt_id: str,
	*,
	timeout_sec: float = 180.0,
	poll_interval_sec: float = 0.75,
	require_outputs: bool = True,
	on_progress: Optional[Callable[[float], None]] = None,
) -> Dict[str, Any]:
	base = (base_url or "").strip().rstrip("/")
	pid = (prompt_id or "").strip()
	if not base or not pid:
		raise ValueError("base_url and prompt_id required")
	t0 = time.time()
	while True:
		elapsed = time.time() - t0
		if elapsed > float(timeout_sec):
			raise TimeoutError("ComfyUI history poll timed out")
		# Best-effort progress: just a time-based heartbeat.
		if on_progress:
			on_progress(min(99.0, max(1.0, (elapsed / max(1.0, float(timeout_sec))) * 100.0)))
		obj = await asyncio.to_thread(_get_json_sync, f"{base}/history/{pid}", 12.0)
		entry = obj.get(pid)
		if isinstance(entry, dict):
			if not require_outputs:
				# Scheduler/orchestration prompts can complete successfully without
				# direct image outputs in their own history entry.
				return entry
			outputs = entry.get("outputs")
			if isinstance(outputs, dict) and len(outputs) > 0:
				return entry
		await asyncio.sleep(float(poll_interval_sec))


async def fetch_image_bytes(base_url: str, *, filename: str, subfolder: str, typ: str) -> Tuple[bytes, str]:
	base = (base_url or "").strip().rstrip("/")
	if not base:
		raise ValueError("base_url required")
	fn = (filename or "").strip()
	if not fn:
		raise ValueError("filename required")
	sf = (subfolder or "").strip()
	t = (typ or "output").strip()
	q = urlencode({"filename": fn, "subfolder": sf, "type": t})
	url = f"{base}/view?{q}"
	data = await asyncio.to_thread(_get_bytes_sync, url, 120.0)
	return data, ext_for_filename(fn)


