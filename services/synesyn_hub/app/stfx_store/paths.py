from __future__ import annotations

from pathlib import Path
from typing import Iterable

from ..config import WorkspaceConfig


class StfxStorePaths:
	def __init__(self, workspace: WorkspaceConfig):
		self.workspace = workspace
		self.root = workspace.root / "stfx_store"
		self.schemas_dir = self.root / "schemas"
		self.seeds_dir = self.root / "seeds"
		self.sources_dir = self.root / "sources"
		self.memories_dir = self.root / "memories"
		self.closures_dir = self.root / "closures"
		self.artifacts_dir = self.root / "artifacts"
		self.traces_dir = self.root / "traces"
		self.ingest_reports_dir = self.root / "ingest_reports"
		self.repair_reports_dir = self.root / "repair_reports"
		self.indexes_dir = self.root / "indexes"
		self.manifest_path = self.root / "store_manifest.json"

	def canonical_dirs(self) -> Iterable[Path]:
		return (
			self.root,
			self.schemas_dir,
			self.seeds_dir,
			self.sources_dir,
			self.memories_dir,
			self.closures_dir,
			self.artifacts_dir,
			self.traces_dir,
			self.ingest_reports_dir,
			self.repair_reports_dir,
			self.indexes_dir,
		)

	def source_dir(self, source_id: str) -> Path:
		return self.sources_dir / source_id

	def source_record_path(self, source_id: str) -> Path:
		return self.source_dir(source_id) / "source.json"

	def source_original_path(self, source_id: str, suffix: str) -> Path:
		clean_suffix = suffix if suffix.startswith(".") else f".{suffix}" if suffix else ".txt"
		return self.source_dir(source_id) / f"original{clean_suffix}"

	def chunk_dir(self, source_id: str) -> Path:
		return self.source_dir(source_id) / "chunks"

	def chunk_path(self, source_id: str, chunk_id: str) -> Path:
		return self.chunk_dir(source_id) / f"{chunk_id}.json"

	def memory_path(self, memory_id: str) -> Path:
		return self.memories_dir / f"{memory_id}.json"

	def closure_path(self, closure_id: str) -> Path:
		return self.closures_dir / f"{closure_id}.json"

	def index_path(self, name: str) -> Path:
		return self.indexes_dir / name

	def sqlite_mirror_path(self) -> Path:
		return self.indexes_dir / "store_mirror.sqlite"

	def migration_report_path(self, report_id: str) -> Path:
		return self.repair_reports_dir / f"{report_id}.json"

	def ingest_report_path(self, report_id: str) -> Path:
		return self.ingest_reports_dir / f"{report_id}.json"

	def repair_report_path(self, report_id: str) -> Path:
		return self.repair_reports_dir / f"{report_id}.json"

	def trace_path(self, trace_id: str, date_label: str) -> Path:
		return self.traces_dir / date_label / f"{trace_id}.json"

	def context_pack_path(self, context_pack_id: str) -> Path:
		return self.artifacts_dir / "context_packs" / f"{context_pack_id}.json"

	def artifact_path(self, artifact_id: str) -> Path:
		return self.artifacts_dir / f"{artifact_id}.json"
