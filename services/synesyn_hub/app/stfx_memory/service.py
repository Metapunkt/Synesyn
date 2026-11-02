from __future__ import annotations

import time
import json
from pathlib import Path
from typing import Any, Callable, Dict, Optional
import shutil

from ..config import WorkspaceConfig
from .adapter_contracts import build_continuity_context
from ..stfx_core import expand_seed_matrix, matrix_to_payload
from .index_store import StfxMemoryStore
from .ingest import ingest_markdown_document
from .retrieve import document_summary, get_chunk_by_path


class StfxMemoryService:
	def __init__(self, workspace: WorkspaceConfig):
		self.store = StfxMemoryStore(workspace)

	def list_documents(self) -> list[Dict[str, Any]]:
		index = self.store.load_index()
		out: list[Dict[str, Any]] = []
		for doc_id in index.get("documents", {}):
			try:
				out.append(document_summary(self.store.load_document(doc_id)))
			except Exception:
				continue
		return sorted(out, key=lambda x: str(x.get("ingested_at", "")), reverse=True)

	def get_document(self, document_id: str) -> Dict[str, Any]:
		return self.store.load_document(document_id)

	def ingest_document(
		self,
		md_path: str,
		llm_callable: Optional[Callable[[str], Dict[str, Any]]] = None,
		parse_strategy: str = "headings",
	) -> Dict[str, Any]:
		path = Path(md_path).expanduser().resolve()
		if not path.exists():
			raise FileNotFoundError(f"source markdown not found: {path}")
		registry = self.store.load_seed_registry()
		doc, report = ingest_markdown_document(path, registry, llm_callable=llm_callable, parse_strategy=parse_strategy)
		# Workspace-local source copy: each Synesyn workspace owns its own ingested corpus.
		source_copy = self.store.source_copy_path(doc["document_id"], path)
		shutil.copy2(path, source_copy)
		doc["source_ref"] = {"kind": "file", "path": str(source_copy)}
		doc.setdefault("metadata", {})
		doc["metadata"]["original_source_ref"] = {"kind": "file", "path": str(path)}
		self.store.save_document(doc)
		index = self.store.load_index()
		index["documents"][doc["document_id"]] = {
			"title": doc["title"],
			"ingested_at": doc["ingested_at"],
			"root_seed_family": doc["root_seed_family"],
			"source_ref": doc["source_ref"],
		}
		self.store.save_index(index)
		report_id = f"ingest_{doc['document_id']}_{int(time.time())}"
		report["document_id"] = doc["document_id"]
		report["workspace_source_ref"] = {"kind": "file", "path": str(source_copy)}
		report["original_source_ref"] = {"kind": "file", "path": str(path)}
		self.store.save_ingest_report(report_id, report)
		doc["metadata"]["latest_ingest_report_id"] = report_id
		self.store.save_document(doc)
		return {
			"ok": True,
			"document_id": doc["document_id"],
			"title": doc["title"],
			"ingest_report_id": report_id,
		}

	def expand(self, document_id: str, chunk_path: str = "", depth: int = 2) -> Dict[str, Any]:
		doc = self.store.load_document(document_id)
		if chunk_path:
			target = get_chunk_by_path(doc.get("chunks", {}), chunk_path)
			if target is None:
				raise KeyError(f"chunk path not found: {chunk_path}")
			seed_matrix = target["sub_seed_matrix"]
			seed_family = target["recommended_sub_seed_family"]
		else:
			target = None
			seed_matrix = doc["root_seed_matrix"]
			seed_family = doc["root_seed_family"]
		matrix = expand_seed_matrix(seed_matrix, int(depth))
		payload = matrix_to_payload(matrix)
		payload.update({
			"ok": True,
			"document_id": document_id,
			"chunk_path": chunk_path or "",
			"seed_family": seed_family,
			"depth": int(depth),
			"source_ref": doc.get("source_ref", {}),
			"summary": (target.get("summary", "") if target else doc.get("title", "")),
		})
		return payload

	def retrieve(
		self,
		document_id: str = "",
		chunk_path: str = "",
		seed_family: str = "",
	) -> Dict[str, Any]:
		if document_id:
			doc = self.store.load_document(document_id)
			if chunk_path:
				chunk = get_chunk_by_path(doc.get("chunks", {}), chunk_path)
				if chunk is None:
					raise KeyError(f"chunk path not found: {chunk_path}")
				return {
					"ok": True,
					"document": document_summary(doc),
					"chunk": chunk,
				}
			return {
				"ok": True,
				"document": doc,
			}
		if seed_family:
			docs = [d for d in self.list_documents() if str(d.get("root_seed_family", "")).strip().lower() == str(seed_family).strip().lower()]
			return {"ok": True, "documents": docs}
		raise ValueError("retrieve requires document_id or seed_family")

	def create_snapshot(self, document_id: str, label: str = "") -> Dict[str, Any]:
		doc = self.store.load_document(document_id)
		now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
		snapshot_id = f"snapshot_{document_id}_{int(time.time())}"
		payload = {
			"schema_version": doc.get("schema_version", 1),
			"snapshot_id": snapshot_id,
			"created_at": now,
			"label": str(label or "").strip(),
			"document_id": document_id,
			"document": doc,
		}
		path = self.store.save_snapshot(snapshot_id, payload)
		return {
			"ok": True,
			"snapshot_id": snapshot_id,
			"document_id": document_id,
			"path": str(path),
		}

	def continuity_context(
		self,
		document_id: str,
		chunk_path: str = "",
		depth: int = 2,
		sibling_window: int = 2,
	) -> Dict[str, Any]:
		doc = self.store.load_document(document_id)
		return build_continuity_context(
			doc=doc,
			document_id=document_id,
			chunk_path=chunk_path,
			depth=depth,
			sibling_window=sibling_window,
		)

	def export_payload(self, export_kind: str, document_id: str, chunk_path: str = "", depth: int = 2) -> Dict[str, Any]:
		kind = str(export_kind or "").strip().lower()
		if kind == "document":
			doc = self.store.load_document(document_id)
			return {
				"artifact_type": "json.stfx_memory_snapshot",
				"payload": {
					"schema_version": doc.get("schema_version", 1),
					"document_id": document_id,
					"export_kind": "document",
					"document": doc,
				},
			}
		if kind == "expansion":
			expanded = self.expand(document_id, chunk_path=chunk_path, depth=depth)
			return {
				"artifact_type": "json.stfx_expansion",
				"payload": expanded,
			}
		if kind == "ingest_report":
			doc = self.store.load_document(document_id)
			report_id = str(((doc.get("metadata", {}) or {}).get("latest_ingest_report_id")) or "").strip()
			if not report_id:
				raise ValueError("document has no latest_ingest_report_id")
			report_path = self.store.reports_dir / f"{report_id}.json"
			if not report_path.exists():
				raise KeyError(f"ingest report not found: {report_id}")
			return {
				"artifact_type": "json.stfx_memory_ingest_report",
				"payload": {
					"report_id": report_id,
					"document_id": document_id,
					"report": json.loads(report_path.read_text(encoding="utf-8")),
				},
			}
		if kind == "seed_registry":
			return {
				"artifact_type": "json.stfx_seed_registry_export",
				"payload": {
					"schema_version": 1,
					"seed_registry": self.store.load_seed_registry(),
				},
			}
		raise ValueError("export_kind must be 'document', 'expansion', 'ingest_report', or 'seed_registry'")
