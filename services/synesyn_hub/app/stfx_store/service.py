from __future__ import annotations

from functools import wraps
import shutil
from pathlib import Path
from threading import RLock
from typing import Any, Dict

from ..config import WorkspaceConfig
from ..stfx_core import expand_seed_matrix, matrix_to_payload
from ..stfx_memory.seed_registry import DEFAULT_SEED_REGISTRY, get_seed_matrix
from .admissibility import (
	DEFAULT_ADMISSIBILITY, build_admissibility_closure_payload,
	gate_selected_candidates, normalize_admissibility_config,
)
from .atomic_io import read_json, write_json_atomic, write_text_atomic
from .lexical_index import build_lexical_index
from .paths import StfxStorePaths
from .provenance import provenance_record
from .records import content_hash, make_trace_id, safe_slug, tokenize, utc_now
from .relation_index import build_relation_index
from .retrieval import score_candidate, sort_candidates
from .schemas import (
	ARTIFACT_SCHEMA, CLOSURE_SCHEMA, INGEST_REPORT_SCHEMA, MEMORY_SCHEMA,
	REPAIR_REPORT_SCHEMA, STORE_SCHEMA, validate_chunk_record, validate_closure_record,
	validate_context_pack, validate_ingest_report, validate_manifest,
	validate_memory_record, validate_repair_report, validate_source_record,
	validate_trace_record,
)
from .source_ingest import ingest_text_file
from .sqlite_mirror import rebuild_sqlite_mirror
from .symbolic_index import build_symbolic_index
from .traces import build_context_pack, build_retrieval_trace
from .vector_index import build_vector_manifest, empty_vector_manifest, external_vector_backend_manifest


def _with_write_lock(method):
	@wraps(method)
	def wrapped(self, *args, **kwargs):
		with self._write_lock:
			return method(self, *args, **kwargs)
	return wrapped


class StfxStoreService:
	def __init__(self, workspace: WorkspaceConfig):
		self.workspace = workspace
		self.paths = StfxStorePaths(workspace)
		self._write_lock = RLock()
		self._ensure_layout()

	def _ensure_layout(self) -> None:
		for path in self.paths.canonical_dirs():
			path.mkdir(parents=True, exist_ok=True)
		if not self.paths.manifest_path.exists():
			write_json_atomic(self.paths.manifest_path, self._default_manifest())
		manifest = self.load_manifest()
		validate_manifest(manifest)

	def _default_manifest(self) -> Dict[str, Any]:
		now = utc_now()
		return {
			"schema": STORE_SCHEMA,
			"store_id": f"stfxstore_{self.workspace.slug}",
			"workspace": {"name": self.workspace.name, "slug": self.workspace.slug, "root": str(self.workspace.root)},
			"created_at": now,
			"updated_at": now,
			"enabled": True,
			"canonical_authority": "files",
			"indexes": {
				"authority": "generated",
				"disposable": True,
				"rebuildable_from": ["sources", "memories", "closures", "artifacts"],
			},
			"accelerators": {"symbolic": True, "lexical": True, "relation": True, "vector": False, "sqlite": False},
			# Open Closure–aligned provenance gate (Note 87). Default off.
			"admissibility": dict(DEFAULT_ADMISSIBILITY),
			"counts": {
				"sources": 0, "chunks": 0, "memories": 0, "closures": 0,
				"traces": 0, "context_packs": 0, "ingest_reports": 0, "repair_reports": 0,
			},
		}

	def load_manifest(self) -> Dict[str, Any]:
		return read_json(self.paths.manifest_path)

	@_with_write_lock
	def save_manifest(self, manifest: Dict[str, Any]) -> None:
		manifest["updated_at"] = utc_now()
		validate_manifest(manifest)
		write_json_atomic(self.paths.manifest_path, manifest)

	def status(self) -> Dict[str, Any]:
		manifest = self.load_manifest()
		return {
			"ok": True,
			"enabled": bool(manifest.get("enabled", True)),
			"root": str(self.paths.root),
			"manifest": manifest,
			"indexes_present": {
				"symbolic": self.paths.index_path("symbolic_index.json").exists(),
				"lexical": self.paths.index_path("lexical_index.json").exists(),
				"relation": self.paths.index_path("relation_index.json").exists(),
				"vector": self.paths.index_path("vector_index.manifest.json").exists(),
				"sqlite": self.paths.sqlite_mirror_path().exists(),
			},
		}

	@_with_write_lock
	def update_config(
		self,
		enabled: bool | None = None,
		accelerators: Dict[str, Any] | None = None,
		admissibility: Dict[str, Any] | None = None,
	) -> Dict[str, Any]:
		manifest = self.load_manifest()
		if enabled is not None:
			manifest["enabled"] = bool(enabled)
		if accelerators is not None:
			current = manifest.get("accelerators", {}) if isinstance(manifest.get("accelerators", {}), dict) else {}
			for key in ["symbolic", "lexical", "relation", "vector", "sqlite"]:
				if key in accelerators:
					current[key] = bool(accelerators[key])
			manifest["accelerators"] = current
		if admissibility is not None and isinstance(admissibility, dict):
			current_adm = normalize_admissibility_config(manifest.get("admissibility", {}))
			for key in DEFAULT_ADMISSIBILITY:
				if key in admissibility:
					current_adm[key] = admissibility[key]
			manifest["admissibility"] = normalize_admissibility_config(current_adm)
		elif "admissibility" not in manifest:
			manifest["admissibility"] = dict(DEFAULT_ADMISSIBILITY)
		self.save_manifest(manifest)
		self.rebuild_indexes()
		return {
			"ok": True,
			"config": {
				"enabled": bool(manifest.get("enabled", True)),
				"accelerators": manifest.get("accelerators", {}),
				"admissibility": normalize_admissibility_config(manifest.get("admissibility", {})),
			},
		}

	@_with_write_lock
	def ingest_source(self, source_path: str, default_seed: str = "primary", llm_recommendations: Dict[str, Any] | None = None) -> Dict[str, Any]:
		self._ensure_enabled()
		source, chunks, text = ingest_text_file(Path(source_path), default_seed=default_seed)
		assist_decisions = self._apply_ingest_recommendations(chunks, llm_recommendations or {})
		source_id = str(source["source_id"])
		source_dir = self.paths.source_dir(source_id)
		source_dir.mkdir(parents=True, exist_ok=True)
		source_suffix = Path(source_path).suffix or ".txt"
		store_original = self.paths.source_original_path(source_id, source_suffix)
		write_text_atomic(store_original, text)
		source["store_ref"] = {"kind": "file", "path": str(store_original)}
		validate_source_record(source)
		write_json_atomic(self.paths.source_record_path(source_id), source)
		for chunk in chunks:
			validate_chunk_record(chunk)
			write_json_atomic(self.paths.chunk_path(source_id, str(chunk["chunk_id"])), chunk)
		report_id = f"ingest_{source_id}_{utc_now().replace(':', '').replace('-', '')}"
		report = {
			"schema": INGEST_REPORT_SCHEMA,
			"report_id": report_id,
			"source_id": source_id,
			"created_at": utc_now(),
			"method": "headings+reviewable_ingest_assist" if assist_decisions else "headings",
			"default_seed": default_seed,
			"llm_assist": {"enabled": bool(assist_decisions), "review_required": bool(assist_decisions), "runtime_dependency": False},
			"original_ref": source.get("original_ref", {}),
			"store_ref": source.get("store_ref", {}),
			"chunk_ids": [str(chunk["chunk_id"]) for chunk in chunks],
			"decisions": [
				{"kind": "chunking", "method": "deterministic_heading_scan", "rationale": "Markdown headings define initial human-reviewable chunk boundaries."},
				{"kind": "symbolic_seed", "method": "default_seed_assignment", "seed": default_seed, "rationale": "Default symbolic seed assigned until human or ingest assistant annotates chunks."},
			] + assist_decisions,
			"provenance": provenance_record(
				"stfx_store.ingest@v0",
				inputs=[source.get("original_ref", {})],
				parameters={"default_seed": default_seed, "method": "headings"},
			),
		}
		validate_ingest_report(report)
		write_json_atomic(self.paths.ingest_report_path(report_id), report)
		self.rebuild_indexes()
		return {
			"ok": True, "source_id": source_id, "title": source["title"],
			"chunk_count": len(chunks), "ingest_report_id": report_id,
			"source_record": str(self.paths.source_record_path(source_id)),
		}

	def list_sources(self) -> list[Dict[str, Any]]:
		return sorted(self._load_sources(), key=lambda source: str(source.get("title", "")))

	def list_memories(self) -> list[Dict[str, Any]]:
		return sorted(self._load_memories(), key=lambda memory: str(memory.get("title", "")))

	def list_closures(self) -> list[Dict[str, Any]]:
		return sorted(self._load_closures(), key=lambda closure: str(closure.get("created_at", "")))

	def list_context_packs(self) -> list[Dict[str, Any]]:
		out: list[Dict[str, Any]] = []
		for path in sorted((self.paths.artifacts_dir / "context_packs").glob("*.json")):
			pack = read_json(path)
			validate_context_pack(pack)
			out.append(pack)
		return sorted(out, key=lambda pack: str(pack.get("created_at", "")))

	def _load_sources(self) -> list[Dict[str, Any]]:
		out: list[Dict[str, Any]] = []
		for path in sorted(self.paths.sources_dir.glob("*/source.json")):
			source = read_json(path)
			validate_source_record(source)
			out.append(source)
		return out

	def _load_chunks(self) -> list[Dict[str, Any]]:
		out: list[Dict[str, Any]] = []
		for path in sorted(self.paths.sources_dir.glob("*/chunks/*.json")):
			chunk = read_json(path)
			validate_chunk_record(chunk)
			out.append(chunk)
		return out

	def _load_memories(self) -> list[Dict[str, Any]]:
		out: list[Dict[str, Any]] = []
		for path in sorted(self.paths.memories_dir.glob("*.json")):
			memory = read_json(path)
			validate_memory_record(memory)
			out.append(memory)
		return out

	def _load_closures(self) -> list[Dict[str, Any]]:
		out: list[Dict[str, Any]] = []
		for path in sorted(self.paths.closures_dir.glob("*.json")):
			closure = read_json(path)
			validate_closure_record(closure)
			out.append(closure)
		return out

	def _chunk_by_id(self) -> Dict[str, Dict[str, Any]]:
		return {str(chunk["chunk_id"]): chunk for chunk in self._load_chunks()}

	def _source_by_id(self) -> Dict[str, Dict[str, Any]]:
		return {str(source["source_id"]): source for source in self._load_sources()}

	@_with_write_lock
	def rebuild_indexes(self) -> Dict[str, Any]:
		sources = self._load_sources()
		chunks = self._load_chunks()
		memories = self._load_memories()
		closures = self._load_closures()
		manifest = self.load_manifest()
		accelerators = manifest.get("accelerators", {}) if isinstance(manifest.get("accelerators", {}), dict) else {}
		symbolic = build_symbolic_index(sources, chunks, memories, closures)
		lexical = build_lexical_index(sources, chunks)
		relation = build_relation_index(chunks, memories, closures)
		vector_manifest = build_vector_manifest(chunks, enabled=bool(accelerators.get("vector", False)))
		external_vector_manifest = external_vector_backend_manifest(enabled=False)
		write_json_atomic(self.paths.index_path("symbolic_index.json"), symbolic)
		write_json_atomic(self.paths.index_path("lexical_index.json"), lexical)
		write_json_atomic(self.paths.index_path("relation_index.json"), relation)
		write_json_atomic(self.paths.index_path("vector_index.manifest.json"), vector_manifest)
		write_json_atomic(self.paths.index_path("external_vector_backend.manifest.json"), external_vector_manifest)
		sqlite_mirror = {"enabled": False, "path": str(self.paths.sqlite_mirror_path()), "status": "disabled"}
		if bool(accelerators.get("sqlite", False)):
			sqlite_mirror = rebuild_sqlite_mirror(self.paths.sqlite_mirror_path(), sources, chunks, memories, closures)
		report = {
			"schema": "stfx.index_report.v1", "authority": "generated", "built_at": utc_now(),
			"source_count": len(sources), "chunk_count": len(chunks),
			"memory_count": len(memories), "closure_count": len(closures),
			"source_hashes": {str(source["source_id"]): source.get("content_hash", "") for source in sources},
			"indexes": {
				"symbolic": "symbolic_index.json", "lexical": "lexical_index.json",
				"relation": "relation_index.json", "vector": "vector_index.manifest.json",
				"external_vector_backend": "external_vector_backend.manifest.json",
				"sqlite": "store_mirror.sqlite" if sqlite_mirror.get("enabled") else "",
			},
			"sqlite_mirror": sqlite_mirror, "warnings": [],
		}
		write_json_atomic(self.paths.index_path("index_report.json"), report)
		manifest = self.load_manifest()
		manifest["counts"] = {
			"sources": len(sources), "chunks": len(chunks), "memories": len(memories), "closures": len(closures),
			"traces": len(list(self.paths.traces_dir.glob("*/*.json"))),
			"context_packs": len(list((self.paths.artifacts_dir / "context_packs").glob("*.json"))),
			"ingest_reports": len(list(self.paths.ingest_reports_dir.glob("*.json"))),
			"repair_reports": len(list(self.paths.repair_reports_dir.glob("*.json"))),
		}
		self.save_manifest(manifest)
		return {"ok": True, "report": report}

	def validate_store(self) -> Dict[str, Any]:
		errors: list[str] = []
		try:
			validate_manifest(self.load_manifest())
		except Exception as exc:
			errors.append(f"manifest: {exc}")
		for source_path in sorted(self.paths.sources_dir.glob("*/source.json")):
			try:
				validate_source_record(read_json(source_path))
			except Exception as exc:
				errors.append(f"{source_path}: {exc}")
		for chunk_path in sorted(self.paths.sources_dir.glob("*/chunks/*.json")):
			try:
				chunk = read_json(chunk_path)
				validate_chunk_record(chunk)
				self._validate_ingest_assist(chunk, str(chunk_path))
			except Exception as exc:
				errors.append(f"{chunk_path}: {exc}")
		for report_path in sorted(self.paths.ingest_reports_dir.glob("*.json")):
			try:
				validate_ingest_report(read_json(report_path))
			except Exception as exc:
				errors.append(f"{report_path}: {exc}")
		for memory_path in sorted(self.paths.memories_dir.glob("*.json")):
			try:
				validate_memory_record(read_json(memory_path))
			except Exception as exc:
				errors.append(f"{memory_path}: {exc}")
		for closure_path in sorted(self.paths.closures_dir.glob("*.json")):
			try:
				validate_closure_record(read_json(closure_path))
			except Exception as exc:
				errors.append(f"{closure_path}: {exc}")
		return {"ok": not errors, "errors": errors}

	@_with_write_lock
	def repair_report(self) -> Dict[str, Any]:
		checks: list[Dict[str, Any]] = []
		validation = self.validate_store()
		checks.append({
			"name": "canonical_validation",
			"ok": bool(validation.get("ok", False)),
			"details": validation.get("errors", []),
		})

		index_check = self._check_indexes_fresh()
		checks.append(index_check)

		trace_check = self._check_trace_references()
		checks.append(trace_check)

		report_id = f"repair_{utc_now().replace(':', '').replace('-', '')}"
		report = {
			"schema": REPAIR_REPORT_SCHEMA,
			"report_id": report_id,
			"created_at": utc_now(),
			"checks": checks,
			"ok": all(bool(check.get("ok", False)) for check in checks),
			"repair_loop": [
				"Inspect failed checks.",
				"Edit canonical source/chunk/memory/closure records as needed.",
				"Run /stfx-store/indexes/rebuild.",
				"Rerun retrieval and compare traces.",
			],
		}
		validate_repair_report(report)
		write_json_atomic(self.paths.repair_report_path(report_id), report)
		self.rebuild_indexes()
		return {"ok": bool(report["ok"]), "report": report}

	def _check_indexes_fresh(self) -> Dict[str, Any]:
		required = [
			self.paths.index_path("symbolic_index.json"),
			self.paths.index_path("lexical_index.json"),
			self.paths.index_path("relation_index.json"),
			self.paths.index_path("index_report.json"),
		]
		missing = [str(path) for path in required if not path.exists()]
		if missing:
			return {"name": "generated_indexes", "ok": False, "details": {"missing": missing, "stale": []}}
		report = read_json(self.paths.index_path("index_report.json"))
		recorded_hashes = report.get("source_hashes", {}) if isinstance(report.get("source_hashes", {}), dict) else {}
		current_hashes = {str(source["source_id"]): source.get("content_hash", "") for source in self._load_sources()}
		stale = [
			source_id
			for source_id, current_hash in current_hashes.items()
			if recorded_hashes.get(source_id) != current_hash
		]
		return {"name": "generated_indexes", "ok": not stale, "details": {"missing": [], "stale": stale}}

	def _check_trace_references(self) -> Dict[str, Any]:
		chunks = self._chunk_by_id()
		missing: list[Dict[str, Any]] = []
		for trace_path in sorted(self.paths.traces_dir.glob("*/*.json")):
			try:
				trace = read_json(trace_path)
				validate_trace_record(trace)
			except Exception as exc:
				missing.append({"trace_path": str(trace_path), "error": str(exc)})
				continue
			for chunk_id in trace.get("selected", []) if isinstance(trace.get("selected", []), list) else []:
				if str(chunk_id) not in chunks:
					missing.append({
						"trace_id": trace.get("trace_id", ""),
						"missing_chunk_id": str(chunk_id),
					})
			context_pack_id = str(trace.get("produced_context_artifact", "")).strip()
			if context_pack_id and not self.paths.context_pack_path(context_pack_id).exists():
				missing.append({
					"trace_id": trace.get("trace_id", ""),
					"missing_context_pack_id": context_pack_id,
				})
		return {"name": "trace_references", "ok": not missing, "details": missing}

	@_with_write_lock
	def retrieve(
		self,
		query: str,
		active_source_ids: list[str] | None = None,
		seed_family: str = "",
		top_k: int = 5,
		expansion_depth: int = 1,
	) -> Dict[str, Any]:
		self._ensure_enabled()
		self._ensure_indexes_present()
		query_terms = tokenize(query)
		active = {str(source_id).strip() for source_id in (active_source_ids or []) if str(source_id).strip()}
		lexical = read_json(self.paths.index_path("lexical_index.json"))
		symbolic = read_json(self.paths.index_path("symbolic_index.json"))
		relation = read_json(self.paths.index_path("relation_index.json"))
		chunks = self._chunk_by_id()
		candidate_ids: set[str] = set()
		lexical_hits: dict[str, int] = {}
		relation_reasons: dict[str, list[str]] = {}

		for term in query_terms:
			for chunk_id in lexical.get("terms", {}).get(term, []):
				candidate_ids.add(str(chunk_id))
				lexical_hits[str(chunk_id)] = lexical_hits.get(str(chunk_id), 0) + 1

		seed = str(seed_family or "").strip().lower()
		if seed:
			for chunk_id in symbolic.get("by_seed", {}).get(seed, []):
				candidate_ids.add(str(chunk_id))

		initial_candidate_ids = set(candidate_ids)
		self._expand_relation_candidates(initial_candidate_ids, candidate_ids, relation_reasons, relation)

		if not candidate_ids:
			candidate_ids = set(chunks.keys())

		candidates: list[Dict[str, Any]] = []
		for chunk_id in sorted(candidate_ids):
			chunk = chunks.get(chunk_id)
			if not chunk:
				continue
			source_id = str(chunk.get("source_id", ""))
			if active and source_id not in active:
				continue
			candidates.append(score_candidate(
				chunk=chunk,
				chunk_id=chunk_id,
				source_id=source_id,
				seed_family=seed,
				query_term_count=len(query_terms),
				lexical_hit_count=lexical_hits.get(chunk_id, 0),
				relation_reasons=relation_reasons.get(chunk_id, []),
				core_alignment=self._core_alignment_score(seed, chunk),
			))

		candidates = sort_candidates(candidates)
		selected = candidates[:max(1, int(top_k))]
		rejected = [
			{
				"chunk_id": item["chunk_id"],
				"reason": "lower combined symbolic/lexical score",
			}
			for item in candidates[max(1, int(top_k)):]
		]
		# Note 87: Open Closure–aligned admissibility gate (opt-in via manifest.admissibility).
		manifest = self.load_manifest()
		adm_cfg = normalize_admissibility_config(manifest.get("admissibility", {}))
		sources_by_id = self._source_by_id()
		adm_report = gate_selected_candidates(selected, sources_by_id, adm_cfg)
		if bool(adm_report.get("enabled", False)):
			selected = list(adm_report.get("admissible", []))
			for item in adm_report.get("policy_rejected", []) or []:
				rejected.append({
					"chunk_id": item.get("chunk_id"),
					"reason": str(item.get("reason", "inadmissible provenance")),
					"rejection_axis": "admissibility",
					"source_id": item.get("source_id", ""),
				})
		trace_id = make_trace_id(query)
		date_label = utc_now()[:10]
		context_pack = build_context_pack(trace_id, query, selected, chunks)
		context_pack_id = str(context_pack["context_pack_id"])
		core_summary = self._core_expansion_summary(seed, expansion_depth)
		trace = build_retrieval_trace(
			query=query,
			active_source_ids=sorted(active),
			seed_family=seed,
			top_k=top_k,
			expansion_depth=expansion_depth,
			query_terms=query_terms,
			core_summary=core_summary,
			candidates=candidates,
			selected=selected,
			rejected=rejected,
			context_pack_id=context_pack_id,
		)
		if bool(adm_report.get("enabled", False)):
			plan = trace.get("retrieval_plan", {}) if isinstance(trace.get("retrieval_plan", {}), dict) else {}
			plan["admissibility"] = {
				"enabled": True,
				"policy": adm_report.get("policy", ""),
				"forbidden_source_ids": list(adm_report.get("forbidden_source_ids", [])),
				"provably_faithful": bool(adm_report.get("provably_faithful", True)),
				"leakage": float(adm_report.get("leakage", 0.0)),
				"method": str(adm_report.get("method", "hard_provenance_filter")),
			}
			trace["retrieval_plan"] = plan
			validate_trace_record(trace)
		write_json_atomic(self.paths.trace_path(trace_id, date_label), trace)
		write_json_atomic(self.paths.context_pack_path(context_pack_id), context_pack)
		result: Dict[str, Any] = {
			"ok": True,
			"trace": trace,
			"context_pack": context_pack,
			"admissibility": {
				"enabled": bool(adm_report.get("enabled", False)),
				"policy": adm_report.get("policy", ""),
				"forbidden_source_ids": list(adm_report.get("forbidden_source_ids", [])),
				"policy_rejected": list(adm_report.get("policy_rejected", [])),
				"provably_faithful": bool(adm_report.get("provably_faithful", True)),
				"leakage": float(adm_report.get("leakage", 0.0)),
				"method": str(adm_report.get("method", "")),
				"open_closure": adm_report.get("open_closure"),
			},
		}
		if bool(adm_report.get("enabled", False)) and bool(adm_cfg.get("persist_closure", False)):
			closure_payload = build_admissibility_closure_payload(
				query=query,
				admissible=selected,
				report=adm_report,
				context_pack_id=context_pack_id,
				trace_id=str(trace.get("trace_id", "")),
			)
			closure_res = self.commit_closure(
				closure_payload,
				provenance=provenance_record(
					"stfx_store.admissibility@v0",
					inputs=[{"kind": "trace", "trace_id": str(trace.get("trace_id", ""))}],
					parameters={"policy": adm_report.get("policy", "")},
				),
			)
			result["admissibility"]["closure_id"] = closure_res.get("closure_id", "")
		return result

	def get_trace(self, trace_id: str) -> Dict[str, Any]:
		for path in self.paths.traces_dir.glob(f"*/*{trace_id}.json"):
			trace = read_json(path)
			validate_trace_record(trace)
			return trace
		raise KeyError(f"trace not found: {trace_id}")

	def get_context_pack(self, context_pack_id: str) -> Dict[str, Any]:
		cpid = str(context_pack_id or "").strip()
		if not cpid:
			raise KeyError("context_pack_id is required")
		path = self.paths.context_pack_path(cpid)
		if not path.exists():
			raise KeyError(f"context pack not found: {cpid}")
		pack = read_json(path)
		return pack

	def get_index(self, index_name: str) -> Dict[str, Any]:
		clean = str(index_name or "").strip()
		allowed = {
			"symbolic": "symbolic_index.json",
			"lexical": "lexical_index.json",
			"relation": "relation_index.json",
			"vector": "vector_index.manifest.json",
			"external_vector_backend": "external_vector_backend.manifest.json",
			"report": "index_report.json",
		}
		if clean not in allowed:
			raise KeyError(f"unknown index: {clean}")
		self._ensure_indexes_present()
		path = self.paths.index_path(allowed[clean])
		if not path.exists():
			raise KeyError(f"index not found: {clean}")
		return {"ok": True, "index_name": clean, "path": str(path), "index": read_json(path)}

	def get_chunk_record(self, chunk_id: str) -> Dict[str, Any]:
		cid = str(chunk_id or "").strip()
		if not cid:
			raise KeyError("chunk_id is required")
		for path in sorted(self.paths.sources_dir.glob("*/chunks/*.json")):
			chunk = read_json(path)
			if str(chunk.get("chunk_id", "")).strip() == cid:
				validate_chunk_record(chunk)
				return {"ok": True, "chunk": chunk, "path": str(path), "folder": str(path.parent)}
		raise KeyError(f"chunk not found: {cid}")

	@_with_write_lock
	def update_chunk_symbolic(self, chunk_id: str, symbolic: Dict[str, Any], repair_note: str = "") -> Dict[str, Any]:
		cid = str(chunk_id or "").strip()
		if not cid:
			raise ValueError("chunk_id is required")
		if not isinstance(symbolic, dict):
			raise ValueError("symbolic metadata must be an object")
		for path in sorted(self.paths.sources_dir.glob("*/chunks/*.json")):
			chunk = read_json(path)
			if str(chunk.get("chunk_id", "")).strip() != cid:
				continue
			current = chunk.get("symbolic", {}) if isinstance(chunk.get("symbolic", {}), dict) else {}
			for key in ["primary_seed", "secondary_seed", "tensions", "rationale"]:
				if key in symbolic:
					current[key] = symbolic[key]
			if not str(current.get("rationale", "")).strip():
				current["rationale"] = str(repair_note or "Human-reviewed symbolic repair.").strip()
			chunk["symbolic"] = current
			notes = chunk.get("repair_notes", []) if isinstance(chunk.get("repair_notes", []), list) else []
			if repair_note:
				notes.append({"created_at": utc_now(), "note": str(repair_note)})
			chunk["repair_notes"] = notes
			validate_chunk_record(chunk)
			write_json_atomic(path, chunk)
			self.rebuild_indexes()
			return {"ok": True, "chunk_id": cid, "path": str(path), "chunk": chunk}
		raise KeyError(f"chunk not found: {cid}")

	@_with_write_lock
	def export_legacy_stfx_memory(self) -> Dict[str, Any]:
		source_root = self.workspace.root / "stfx_memory"
		report_id = f"migration_stfx_memory_{utc_now().replace(':', '').replace('-', '')}"
		candidates = sorted(str(path) for path in source_root.glob("**/*.json")) if source_root.exists() else []
		report = {
			"schema": REPAIR_REPORT_SCHEMA, "report_id": report_id, "created_at": utc_now(),
			"ok": True, "migration_type": "stfx_memory_to_store", "source_root": str(source_root),
			"candidate_count": len(candidates), "candidates": candidates,
			"checks": [{"name": "legacy_stfx_memory_scan", "ok": True, "details": {"candidate_count": len(candidates)}}],
			"repair_loop": [
				"Review candidate legacy memory documents.",
				"Commit selected documents as canonical Store source/memory records.",
				"Rebuild generated indexes.",
			],
		}
		write_json_atomic(self.paths.migration_report_path(report_id), report)
		return {"ok": True, "report": report, "path": str(self.paths.migration_report_path(report_id))}

	@_with_write_lock
	def export_syntree_context_graphs(self) -> Dict[str, Any]:
		return self._export_artifact_mirror_report("syntree_context_graphs", ["ui.context_graph", "bridge.ui_context_graph"])

	@_with_write_lock
	def export_substrate_artifact_mirrors(self) -> Dict[str, Any]:
		return self._export_artifact_mirror_report("substrate_artifact_mirrors", [])

	def _export_artifact_mirror_report(self, report_kind: str, artifact_types: list[str]) -> Dict[str, Any]:
		artifacts_root = self.workspace.artifacts_dir
		report_id = f"migration_{report_kind}_{utc_now().replace(':', '').replace('-', '')}"
		json_paths = sorted(artifacts_root.glob("**/*.json")) if artifacts_root.exists() else []
		candidates: list[Dict[str, Any]] = []
		for path in json_paths:
			try:
				payload = read_json(path)
			except Exception:
				continue
			artifact_type = str(payload.get("artifact_type", payload.get("kind", ""))).strip()
			if artifact_types and artifact_type not in artifact_types:
				continue
			candidates.append({
				"path": str(path), "artifact_type": artifact_type,
				"mirror_recommendation": "commit_to_store_artifact_if_used_for_memory",
			})
		report = {
			"schema": REPAIR_REPORT_SCHEMA, "report_id": report_id, "created_at": utc_now(),
			"ok": True, "migration_type": report_kind, "source_root": str(artifacts_root),
			"candidate_count": len(candidates), "candidates": candidates,
			"checks": [{"name": f"{report_kind}_scan", "ok": True, "details": {"candidate_count": len(candidates)}}],
			"repair_loop": [
				"Review candidate artifacts.",
				"Mirror only artifacts that participate in STFX memory/provenance.",
				"Keep operational-only artifacts in LatentSubstrate.",
			],
		}
		write_json_atomic(self.paths.migration_report_path(report_id), report)
		return {"ok": True, "report": report, "path": str(self.paths.migration_report_path(report_id))}

	def _expand_relation_candidates(
		self,
		initial_candidate_ids: set[str],
		candidate_ids: set[str],
		relation_reasons: dict[str, list[str]],
		relation_index: Dict[str, Any],
	) -> None:
		if not initial_candidate_ids:
			return
		chunk_ids = set(self._chunk_by_id().keys())
		edges = relation_index.get("edges", []) if isinstance(relation_index.get("edges", []), list) else []
		reverse = relation_index.get("reverse", {}) if isinstance(relation_index.get("reverse", {}), dict) else {}

		for edge in edges:
			if not isinstance(edge, dict):
				continue
			from_id = str(edge.get("from", "")).strip()
			to_id = str(edge.get("to", "")).strip()
			rel_type = str(edge.get("type", "")).strip() or "related"
			if from_id in initial_candidate_ids and to_id in chunk_ids:
				candidate_ids.add(to_id)
				relation_reasons.setdefault(to_id, []).append(
					"relation-neighborhood: %s -> %s via %s" % (from_id, to_id, rel_type)
				)

		for target_id, from_ids_any in reverse.items():
			target = str(target_id).strip()
			if target not in initial_candidate_ids:
				continue
			from_ids = from_ids_any if isinstance(from_ids_any, list) else []
			for from_id_any in from_ids:
				from_id = str(from_id_any).strip()
				if from_id in chunk_ids:
					candidate_ids.add(from_id)
					relation_reasons.setdefault(from_id, []).append(
						"relation-neighborhood: %s points to initial candidate %s" % (from_id, target)
					)

	def _core_expansion_summary(self, seed_family: str, expansion_depth: int) -> Dict[str, Any]:
		seed = str(seed_family or "primary").strip().lower() or "primary"
		try:
			seed_matrix = get_seed_matrix(DEFAULT_SEED_REGISTRY, seed)
		except KeyError:
			seed = "primary"
			seed_matrix = get_seed_matrix(DEFAULT_SEED_REGISTRY, seed)
		matrix = expand_seed_matrix(seed_matrix, max(0, int(expansion_depth)))
		payload = matrix_to_payload(matrix)
		return {
			"kernel": "stfx_core",
			"role": "final_symbolic_expansion_and_ranking_prior",
			"seed_family": seed,
			"expansion_depth": max(0, int(expansion_depth)),
			"matrix_shape": payload.get("matrix_shape", []),
			"complementarity": payload.get("meta", {}),
		}

	def _core_alignment_score(self, seed_family: str, chunk: Dict[str, Any]) -> float:
		seed = str(seed_family or "").strip().lower()
		if not seed:
			return 0.25
		symbolic = chunk.get("symbolic", {}) if isinstance(chunk.get("symbolic", {}), dict) else {}
		chunk_seed = str(symbolic.get("primary_seed", "")).strip().lower()
		if chunk_seed == seed:
			return 1.0
		tensions = symbolic.get("tensions", []) if isinstance(symbolic.get("tensions", []), list) else []
		return 0.5 if seed in {str(tension).strip().lower() for tension in tensions} else 0.0

	@_with_write_lock
	def commit_artifact(self, artifact_type: str, payload: Dict[str, Any], provenance: Dict[str, Any] | None = None) -> Dict[str, Any]:
		artifact_id = f"art_{content_hash(str(payload))[-12:]}"
		record = {
			"schema": ARTIFACT_SCHEMA, "artifact_id": artifact_id,
			"artifact_type": str(artifact_type or "json.generic"), "created_at": utc_now(),
			"payload": payload, "provenance": provenance or {}, "content_hash": content_hash(str(payload)),
		}
		write_json_atomic(self.paths.artifact_path(artifact_id), record)
		return {"ok": True, "artifact_id": artifact_id, "path": str(self.paths.artifact_path(artifact_id))}

	@_with_write_lock
	def commit_context_graph(self, graph: Dict[str, Any], provenance: Dict[str, Any] | None = None) -> Dict[str, Any]:
		if not isinstance(graph, dict):
			raise ValueError("context graph must be an object")
		if not isinstance(graph.get("nodes", []), list):
			raise ValueError("context graph nodes must be a list")
		if not isinstance(graph.get("edges", []), list):
			raise ValueError("context graph edges must be a list")
		prov = provenance or {}
		prov.setdefault("produced_by", "syntree.publish_context_graph")
		prov.setdefault("inputs", [{"type": "syntree.context_graph", "node_count": len(graph.get("nodes", []))}])
		return self.commit_artifact("ui.context_graph", graph, prov)

	@_with_write_lock
	def commit_memory(self, payload: Dict[str, Any], provenance: Dict[str, Any] | None = None) -> Dict[str, Any]:
		if not isinstance(payload, dict):
			raise ValueError("memory payload must be an object")
		title = str(payload.get("title", "")).strip()
		if not title:
			raise ValueError("memory title is required")
		rationale = str(payload.get("rationale", "")).strip()
		if not rationale:
			raise ValueError("memory rationale is required")
		body_hash = content_hash(str(payload))
		memory_id = str(payload.get("memory_id", "")).strip() or f"mem_{safe_slug(title, 'memory')}_{body_hash[-10:]}"
		record = {
			"schema": MEMORY_SCHEMA, "memory_id": memory_id, "title": title,
			"created_at": str(payload.get("created_at", "")).strip() or utc_now(), "updated_at": utc_now(),
			"symbolic_address": payload.get("symbolic_address", {}), "related": payload.get("related", {}),
			"summary": str(payload.get("summary", "")).strip(), "rationale": rationale,
			"repair_notes": payload.get("repair_notes", []), "relations": payload.get("relations", []),
			"provenance": provenance or payload.get("provenance", {}), "content_hash": body_hash,
		}
		validate_memory_record(record)
		write_json_atomic(self.paths.memory_path(memory_id), record)
		self.rebuild_indexes()
		return {"ok": True, "memory_id": memory_id, "path": str(self.paths.memory_path(memory_id))}

	@_with_write_lock
	def commit_closure(self, payload: Dict[str, Any], provenance: Dict[str, Any] | None = None) -> Dict[str, Any]:
		if not isinstance(payload, dict):
			raise ValueError("closure payload must be an object")
		title = str(payload.get("title", "")).strip()
		if not title:
			raise ValueError("closure title is required")
		rationale = str(payload.get("rationale", "")).strip()
		if not rationale:
			raise ValueError("closure rationale is required")
		body_hash = content_hash(str(payload))
		closure_id = str(payload.get("closure_id", "")).strip() or f"clo_{safe_slug(title, 'closure')}_{body_hash[-10:]}"
		record = {
			"schema": CLOSURE_SCHEMA, "closure_id": closure_id, "title": title,
			"created_at": str(payload.get("created_at", "")).strip() or utc_now(), "updated_at": utc_now(),
			"selected": payload.get("selected", {}), "symbolic_constraints": payload.get("symbolic_constraints", {}),
			"human_commit": payload.get("human_commit", {}), "rationale": rationale,
			"relations": payload.get("relations", []),
			"provenance": provenance or payload.get("provenance", {}), "content_hash": body_hash,
		}
		validate_closure_record(record)
		write_json_atomic(self.paths.closure_path(closure_id), record)
		self.rebuild_indexes()
		return {"ok": True, "closure_id": closure_id, "path": str(self.paths.closure_path(closure_id))}

	def _ensure_indexes_present(self) -> None:
		required = [
			self.paths.index_path("symbolic_index.json"),
			self.paths.index_path("lexical_index.json"),
			self.paths.index_path("relation_index.json"),
		]
		if not all(path.exists() for path in required):
			self.rebuild_indexes()

	def _ensure_enabled(self) -> None:
		if not bool(self.load_manifest().get("enabled", True)):
			raise ValueError("STFX Store is disabled by configuration")

	def _apply_ingest_recommendations(self, chunks: list[Dict[str, Any]], recommendations: Dict[str, Any]) -> list[Dict[str, Any]]:
		if not recommendations:
			return []
		decisions: list[Dict[str, Any]] = []
		chunk_recs = recommendations.get("chunks", []) if isinstance(recommendations.get("chunks", []), list) else []
		for rec_any in chunk_recs:
			if not isinstance(rec_any, dict):
				continue
			chunk_index = int(rec_any.get("chunk_index", -1))
			if chunk_index < 0 or chunk_index >= len(chunks):
				continue
			chunk = chunks[chunk_index]
			rationale = str(rec_any.get("rationale", "")).strip() or "LLM-assisted ingest recommendation; requires human review."
			symbolic = chunk.get("symbolic", {}) if isinstance(chunk.get("symbolic", {}), dict) else {}
			seed = str(rec_any.get("primary_seed", "")).strip()
			if seed:
				symbolic["primary_seed"] = seed
			tensions = rec_any.get("tensions", [])
			if isinstance(tensions, list):
				symbolic["tensions"] = [str(tension).strip() for tension in tensions if str(tension).strip()]
			symbolic["rationale"] = rationale
			chunk["symbolic"] = symbolic
			summary = str(rec_any.get("summary", "")).strip()
			nesting = rec_any.get("nesting_path", [])
			chunk["ingest_assist"] = {
				"source": "llm_assisted_ingest", "review_required": True, "runtime_dependency": False,
				"summary_recommendation": summary,
				"nesting_recommendation": nesting if isinstance(nesting, list) else [],
				"rationale": rationale,
			}
			decisions.append({
				"kind": "llm_assisted_chunk_recommendation", "chunk_id": chunk.get("chunk_id", ""),
				"review_required": True, "runtime_dependency": False,
				"summary": summary, "seed": seed,
				"nesting_path": nesting if isinstance(nesting, list) else [],
				"rationale": rationale,
			})
		return decisions

	def _validate_ingest_assist(self, chunk: Dict[str, Any], label: str) -> None:
		assist = chunk.get("ingest_assist", {})
		if not assist:
			return
		if not isinstance(assist, dict):
			raise ValueError(f"{label}: ingest_assist must be an object")
		if not bool(assist.get("review_required", False)):
			raise ValueError(f"{label}: ingest_assist.review_required must be true")
		if bool(assist.get("runtime_dependency", False)):
			raise ValueError(f"{label}: ingest_assist must not be a runtime dependency")
		if not str(assist.get("rationale", "")).strip():
			raise ValueError(f"{label}: ingest_assist.rationale is required")

	@_with_write_lock
	def reset_generated_indexes(self) -> None:
		if self.paths.indexes_dir.exists():
			shutil.rmtree(self.paths.indexes_dir)
		self.paths.indexes_dir.mkdir(parents=True, exist_ok=True)
