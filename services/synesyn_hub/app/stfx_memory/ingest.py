from __future__ import annotations

from pathlib import Path
from typing import Any, Callable, Dict, Optional
import time
import uuid

from .schemas import SCHEMA_VERSION
from .seed_registry import get_seed_matrix


def build_document_id(title: str) -> str:
	base = "".join(c.lower() if c.isalnum() else "_" for c in title).strip("_")
	base = base or "document"
	return f"stfxmem_{base}_{uuid.uuid4().hex[:8]}"


def simple_parse_fallback(text: str) -> Dict[str, Any]:
	lines = text.splitlines()
	chunks: list[Dict[str, Any]] = []
	current: Optional[Dict[str, Any]] = None
	current_start = 0
	for i, line in enumerate(lines):
		if line.startswith("#"):
			if current is not None:
				current["end_offset"] = i
				chunks.append(current)
			title = line.lstrip("#").strip() or f"section_{len(chunks)}"
			current_start = i
			current = {
				"id": f"section_{len(chunks)}",
				"summary": title[:160],
				"recommended_sub_seed": "primary",
				"selection_rationale": "Fallback heading-based ingest; default primary seed family applied.",
				"start_offset": current_start,
				"end_offset": current_start,
				"sub_chunks": [],
			}
	if current is not None:
		current["end_offset"] = len(lines)
		chunks.append(current)
	if not chunks:
		chunks = [{
			"id": "root_section",
			"summary": (text.strip().splitlines()[0][:160] if text.strip() else "Untitled document"),
			"recommended_sub_seed": "primary",
			"selection_rationale": "No headings detected; single fallback chunk created.",
			"start_offset": 0,
			"end_offset": len(lines),
			"sub_chunks": [],
		}]
	return {
		"recommended_root_seed": "primary",
		"root_rationale": "Fallback heading-based ingest; default primary seed family applied.",
		"chunks": chunks,
	}


def _normalize_chunk(chunk: Dict[str, Any], registry: Dict[str, Dict[str, Any]], parent_path: str = "") -> Dict[str, Any]:
	chunk_id = str(chunk.get("id") or "chunk").strip()
	path = f"{parent_path}.{chunk_id}" if parent_path else chunk_id
	family = str(chunk.get("recommended_sub_seed") or "primary").strip().lower()
	return {
		"chunk_id": chunk_id,
		"path": path,
		"parent_path": parent_path,
		"start_offset": int(chunk.get("start_offset", 0)),
		"end_offset": int(chunk.get("end_offset", 0)),
		"summary": str(chunk.get("summary") or ""),
		"recommended_sub_seed_family": family,
		"sub_seed_matrix": get_seed_matrix(registry, family),
		"selection_rationale": str(chunk.get("selection_rationale") or ""),
		"sub_chunks": {
			str(sub.get("id") or f"sub_{idx}"): _normalize_chunk(sub, registry, path)
			for idx, sub in enumerate(chunk.get("sub_chunks", []) or [])
		},
	}


def ingest_markdown_document(
	md_path: Path,
	registry: Dict[str, Dict[str, Any]],
	llm_callable: Optional[Callable[[str], Dict[str, Any]]] = None,
	parse_strategy: str = "headings",
) -> tuple[Dict[str, Any], Dict[str, Any]]:
	text = md_path.read_text(encoding="utf-8")
	analysis = llm_callable(text) if llm_callable else simple_parse_fallback(text)
	root_family = str(analysis.get("recommended_root_seed") or "primary").strip().lower()
	now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
	document_id = build_document_id(md_path.stem)
	doc = {
		"schema_version": SCHEMA_VERSION,
		"document_id": document_id,
		"title": md_path.stem,
		"source_ref": {"kind": "file", "path": str(md_path)},
		"ingested_at": now,
		"ingest_strategy": "llm_once" if llm_callable else parse_strategy,
		"root_seed_family": root_family,
		"root_seed_matrix": get_seed_matrix(registry, root_family),
		"ingest_rationale": str(analysis.get("root_rationale") or ""),
		"chunks": {
			str(chunk.get("id") or f"chunk_{idx}"): _normalize_chunk(chunk, registry)
			for idx, chunk in enumerate(analysis.get("chunks", []) or [])
		},
		"metadata": {},
	}
	report = {
		"schema_version": SCHEMA_VERSION,
		"document_id": document_id,
		"created_at": now,
		"source_ref": {"kind": "file", "path": str(md_path)},
		"analysis": analysis,
	}
	return doc, report
