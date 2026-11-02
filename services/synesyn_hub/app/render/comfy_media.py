"""
Files a render.comfyui job moves that are not a workflow or a still image.

A ComfyUI on another machine cannot read this machine's files, so any input a
workflow loads (a portrait, a line of synthesised speech) is uploaded to it first.
A render request names these under `input_uploads`:

	{"node_id": "4", "input": "image", "artifact_id": "art_...", "filename": "didi.png"}

The artifact is uploaded, and the node's input is set to the name ComfyUI gives it.

Finished prompts report files under `images`, and video and audio nodes under other
keys. Those other keys are collected only when the request opts in with
`output_routing.videos` or `output_routing.audio`, so existing image renders are
unaffected; the files are stored as `video.generated` / `audio.generated` artifacts
and reported apart from the image lists.
"""

from __future__ import annotations

import copy
from pathlib import Path
from typing import Any, Dict, List, Tuple
from urllib.parse import unquote, urlparse

from app.render import comfy as comfyui

VIDEO_ARTIFACT_TYPE = "video.generated"
AUDIO_ARTIFACT_TYPE = "audio.generated"

_VIDEO_EXTS = {"mp4", "webm", "mov", "mkv", "ogv"}
_AUDIO_EXTS = {"wav", "mp3", "flac", "ogg"}


def media_kind(filename: str) -> str:
	ext = comfyui.ext_for_filename(filename)
	if ext in _VIDEO_EXTS:
		return "video"
	if ext in _AUDIO_EXTS:
		return "audio"
	return "image"


def _routing_for(kind: str, output_routing: Any) -> Dict[str, Any] | None:
	if kind == "image" or not isinstance(output_routing, dict):
		return None
	cfg = output_routing.get("videos" if kind == "video" else "audio")
	return cfg if isinstance(cfg, dict) else None


def artifact_type_for(kind: str, output_routing: Any, image_artifact_type: str) -> str:
	"""The artifact type to store an output under. Without an opt-in, everything stays an image."""
	cfg = _routing_for(kind, output_routing)
	if cfg is None:
		return image_artifact_type
	default = VIDEO_ARTIFACT_TYPE if kind == "video" else AUDIO_ARTIFACT_TYPE
	return str(cfg.get("artifact_type") or default).strip() or default


def _output_keys(output_routing: Any) -> Tuple[str, ...]:
	keys: Tuple[str, ...] = ("images",)
	if _routing_for("video", output_routing) is not None:
		keys += ("videos", "gifs")
	if _routing_for("audio", output_routing) is not None:
		keys += ("audio",)
	return keys


def output_files_by_node(outputs: Any, output_routing: Any = None) -> List[Tuple[str, List[Dict[str, str]]]]:
	result: List[Tuple[str, List[Dict[str, str]]]] = []
	if not isinstance(outputs, dict):
		return result
	keys = _output_keys(output_routing)
	for node_id, out_any in outputs.items():
		if not isinstance(out_any, dict):
			continue
		files: List[Dict[str, str]] = []
		for key in keys:
			items = out_any.get(key)
			if not isinstance(items, list):
				continue
			for item in items:
				if not isinstance(item, dict):
					continue
				filename = str(item.get("filename") or "").strip()
				if not filename:
					continue
				files.append(
					{
						"filename": filename,
						"subfolder": str(item.get("subfolder") or "").strip(),
						"type": str(item.get("type") or "output").strip(),
						"kind": media_kind(filename),
					}
				)
		if files:
			result.append((str(node_id), files))
	return result


def _uri_to_path(uri: str) -> Path:
	u = (uri or "").strip()
	if u.startswith("file://"):
		p = unquote(urlparse(u).path or "")
		if len(p) > 2 and p[0] == "/" and p[2] == ":":
			p = p[1:]
		return Path(p)
	return Path(u)


async def _artifact_path(repo: Any, artifact_id: str) -> Path:
	qr = await repo.query({"table": "artifacts", "where": {"id": artifact_id}, "limit": 1})
	cols = [str(c) for c in (qr.get("columns") or [])]
	rows = qr.get("rows") or []
	if not rows:
		raise ValueError(f"Input artifact not found: {artifact_id}")
	rec = {cols[i]: rows[0][i] for i in range(len(cols))}
	uri = str(rec.get("uri") or "").strip()
	if not uri:
		raise ValueError(f"Input artifact has no uri: {artifact_id}")
	return _uri_to_path(uri)


async def apply_input_uploads(comfy_url: str, workflow: Dict[str, Any], uploads: Any, *, repo: Any) -> Dict[str, Any]:
	"""Upload each named input to ComfyUI and point its node at the uploaded name."""
	if not isinstance(uploads, list) or not uploads:
		return workflow
	wf = copy.deepcopy(workflow)
	for up in uploads:
		if not isinstance(up, dict):
			continue
		node_id = str(up.get("node_id") or "").strip()
		input_key = str(up.get("input") or "").strip()
		artifact_id = str(up.get("artifact_id") or "").strip()
		if not node_id or not input_key or not artifact_id:
			raise ValueError("input_uploads entries need node_id, input and artifact_id")
		node = wf.get(node_id)
		if not isinstance(node, dict):
			raise ValueError(f"input_uploads names node {node_id}, which the workflow does not have")
		path = await _artifact_path(repo, artifact_id)
		filename = str(up.get("filename") or "").strip() or f"{artifact_id}{path.suffix}"
		name = await comfyui.upload_input(
			comfy_url, path.read_bytes(), filename=filename, subfolder=str(up.get("subfolder", "synesyn") or "")
		)
		inputs = node.get("inputs") if isinstance(node.get("inputs"), dict) else {}
		inputs[input_key] = name
		node["inputs"] = inputs
	return wf
