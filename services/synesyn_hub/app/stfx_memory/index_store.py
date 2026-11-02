from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict

from ..config import WorkspaceConfig
from .schemas import SCHEMA_VERSION, validate_document_record, validate_memory_index
from .seed_registry import DEFAULT_SEED_REGISTRY, validate_seed_registry


class StfxMemoryStore:
	def __init__(self, workspace: WorkspaceConfig):
		self.workspace = workspace
		self.root = workspace.root / "stfx_memory"
		self.seeds_dir = self.root / "seeds"
		self.docs_dir = self.root / "documents"
		self.sources_dir = self.root / "sources"
		self.snapshots_dir = self.root / "snapshots"
		self.reports_dir = self.root / "ingest_reports"
		self.index_path = self.root / "memory_index.json"
		self.config_path = self.root / "memory_config.json"
		self.seed_registry_path = self.seeds_dir / "seed_registry.json"
		self._ensure_layout()

	def _ensure_layout(self) -> None:
		for p in (self.root, self.seeds_dir, self.docs_dir, self.sources_dir, self.snapshots_dir, self.reports_dir):
			p.mkdir(parents=True, exist_ok=True)
		if not self.config_path.exists():
			self._atomic_write_json(self.config_path, {
				"schema_version": SCHEMA_VERSION,
				"default_ingest_strategy": "headings",
				"llm_ingest_enabled": False,
			})
		if not self.index_path.exists():
			self._atomic_write_json(self.index_path, {
				"schema_version": SCHEMA_VERSION,
				"documents": {},
			})
		if not self.seed_registry_path.exists():
			validate_seed_registry(DEFAULT_SEED_REGISTRY)
			self._atomic_write_json(self.seed_registry_path, DEFAULT_SEED_REGISTRY)

	def _atomic_write_json(self, path: Path, obj: Any) -> None:
		tmp = path.with_suffix(path.suffix + ".tmp")
		tmp.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
		tmp.replace(path)

	def load_index(self) -> Dict[str, Any]:
		obj = json.loads(self.index_path.read_text(encoding="utf-8"))
		validate_memory_index(obj)
		return obj

	def save_index(self, index: Dict[str, Any]) -> None:
		validate_memory_index(index)
		self._atomic_write_json(self.index_path, index)

	def load_seed_registry(self) -> Dict[str, Dict[str, Any]]:
		obj = json.loads(self.seed_registry_path.read_text(encoding="utf-8"))
		validate_seed_registry(obj)
		return obj

	def document_path(self, document_id: str) -> Path:
		return self.docs_dir / f"{document_id}.json"

	def source_copy_path(self, document_id: str, original_path: Path) -> Path:
		name = original_path.name or f"{document_id}.md"
		return self.sources_dir / f"{document_id}__{name}"

	def load_document(self, document_id: str) -> Dict[str, Any]:
		path = self.document_path(document_id)
		if not path.exists():
			raise KeyError(f"document not found: {document_id}")
		doc = json.loads(path.read_text(encoding="utf-8"))
		validate_document_record(doc)
		return doc

	def save_document(self, doc: Dict[str, Any]) -> None:
		validate_document_record(doc)
		self._atomic_write_json(self.document_path(doc["document_id"]), doc)

	def save_ingest_report(self, report_id: str, report: Dict[str, Any]) -> Path:
		path = self.reports_dir / f"{report_id}.json"
		self._atomic_write_json(path, report)
		return path

	def save_snapshot(self, snapshot_id: str, payload: Dict[str, Any]) -> Path:
		path = self.snapshots_dir / f"{snapshot_id}.json"
		self._atomic_write_json(path, payload)
		return path
