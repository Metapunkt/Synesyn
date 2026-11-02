from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import json
import shutil
import sys
import tempfile
from types import SimpleNamespace
import unittest
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

HERE = Path(__file__).resolve()
HUB_ROOT = HERE.parents[1]
if str(HUB_ROOT) not in sys.path:
	sys.path.insert(0, str(HUB_ROOT))

from app.config import WorkspaceConfig
from app.stfx_store.routes import router as store_router
from app.stfx_store.service import StfxStoreService
from app.app_adapters.scensyn_continuity import (
	build_scenario_continuity_state_from_context_pack,
	build_store_context_continuity_artifact_payload,
)


def _make_workspace(root: Path, name: str, slug: str) -> WorkspaceConfig:
	root.mkdir(parents=True, exist_ok=True)
	return WorkspaceConfig(
		name=name,
		slug=slug,
		root=root,
		substrate_dir=root / "substrate",
		artifacts_dir=root / "artifacts",
		exports_dir=root / "exports",
		logs_dir=root / "logs",
	)


class TestStfxStore(unittest.TestCase):
	def setUp(self) -> None:
		self.tmp = tempfile.TemporaryDirectory()
		self.base = Path(self.tmp.name)
		self.source_md = self.base / "forward_remembrance.md"
		self.source_md.write_text(
			"# Forward Remembrance\n"
			"Memory and dreaming are coupled through social interpretation.\n"
			"## Human AI Agency\n"
			"Decision-making requires human agency, auditability, and repair.\n"
			"## Workshop Context\n"
			"The workshop uses scenario continuity and symbolic retrieval.\n",
			encoding="utf-8",
		)
		self.workspace = _make_workspace(self.base / "Workspace_A", "Workspace A", "workspace-a")

	def tearDown(self) -> None:
		self.tmp.cleanup()

	def test_bootstrap_creates_human_readable_store_layout(self) -> None:
		service = StfxStoreService(self.workspace)
		root = self.workspace.root / "stfx_store"
		self.assertTrue((root / "store_manifest.json").exists())
		self.assertTrue((root / "sources").exists())
		self.assertTrue((root / "traces").exists())
		status = service.status()
		self.assertTrue(status["ok"])
		self.assertEqual(status["manifest"]["canonical_authority"], "files")
		self.assertTrue(status["manifest"]["indexes"]["disposable"])
		self.assertFalse(status["manifest"]["accelerators"]["vector"])
		self.assertFalse(status["manifest"]["accelerators"]["sqlite"])

	def test_ingest_writes_source_original_and_chunk_records(self) -> None:
		service = StfxStoreService(self.workspace)
		res = service.ingest_source(str(self.source_md))
		self.assertTrue(res["ok"])
		source_id = res["source_id"]
		source_dir = self.workspace.root / "stfx_store" / "sources" / source_id
		self.assertTrue((source_dir / "source.json").exists())
		self.assertTrue((source_dir / "original.md").exists())
		chunks = sorted((source_dir / "chunks").glob("*.json"))
		self.assertEqual(len(chunks), 3)
		self.assertIn(source_id, chunks[0].stem)
		report_path = self.workspace.root / "stfx_store" / "ingest_reports" / f"{res['ingest_report_id']}.json"
		self.assertTrue(report_path.exists())

	def test_generated_indexes_can_be_deleted_and_rebuilt(self) -> None:
		service = StfxStoreService(self.workspace)
		service.ingest_source(str(self.source_md))
		indexes_dir = self.workspace.root / "stfx_store" / "indexes"
		self.assertTrue((indexes_dir / "symbolic_index.json").exists())
		shutil.rmtree(indexes_dir)
		self.assertFalse(indexes_dir.exists())
		res = service.rebuild_indexes()
		self.assertTrue(res["ok"])
		self.assertTrue((indexes_dir / "symbolic_index.json").exists())
		self.assertTrue((indexes_dir / "lexical_index.json").exists())
		self.assertTrue((indexes_dir / "relation_index.json").exists())

	def test_retrieval_emits_trace_and_context_pack(self) -> None:
		service = StfxStoreService(self.workspace)
		ingested = service.ingest_source(str(self.source_md))
		res = service.retrieve(
			query="How does human agency relate to repair?",
			active_source_ids=[ingested["source_id"]],
			seed_family="primary",
			top_k=2,
			expansion_depth=2,
		)
		self.assertTrue(res["ok"])
		trace = res["trace"]
		pack = res["context_pack"]
		self.assertEqual(trace["schema"], "stfx.retrieval_trace.v1")
		self.assertEqual(pack["trace_id"], trace["trace_id"])
		self.assertGreaterEqual(len(trace["candidates"]), 1)
		self.assertGreaterEqual(len(pack["chunks"]), 1)
		self.assertIn("why", trace["candidates"][0])
		self.assertIn("citation", pack["chunks"][0])
		self.assertEqual(trace["retrieval_plan"]["stfx_core"]["kernel"], "stfx_core")
		self.assertEqual(trace["retrieval_plan"]["stfx_core"]["matrix_shape"], [64, 64])
		loaded_trace = service.get_trace(trace["trace_id"])
		self.assertEqual(loaded_trace["trace_id"], trace["trace_id"])
		context_packs = service.list_context_packs()
		self.assertEqual(len(context_packs), 1)
		self.assertEqual(context_packs[0]["context_pack_id"], pack["context_pack_id"])
		self.assertIn("core_alignment", trace["candidates"][0]["scores"])
		self.assertEqual(trace["retrieval_plan"]["stfx_core"]["role"], "final_symbolic_expansion_and_ranking_prior")

	def test_validate_store_reports_ok_after_ingest(self) -> None:
		service = StfxStoreService(self.workspace)
		service.ingest_source(str(self.source_md))
		res = service.validate_store()
		self.assertTrue(res["ok"], res.get("errors"))

	def test_repair_report_checks_indexes_and_trace_references(self) -> None:
		service = StfxStoreService(self.workspace)
		ingested = service.ingest_source(str(self.source_md))
		service.retrieve(
			query="symbolic retrieval workshop continuity",
			active_source_ids=[ingested["source_id"]],
			seed_family="primary",
			top_k=1,
		)
		report = service.repair_report()
		self.assertTrue(report["ok"], report["report"])
		self.assertTrue((self.workspace.root / "stfx_store" / "repair_reports").exists())
		check_names = {check["name"] for check in report["report"]["checks"]}
		self.assertIn("canonical_validation", check_names)
		self.assertIn("generated_indexes", check_names)
		self.assertIn("trace_references", check_names)

	def test_relation_neighborhood_adds_related_candidates(self) -> None:
		service = StfxStoreService(self.workspace)
		ingested = service.ingest_source(str(self.source_md))
		source_dir = self.workspace.root / "stfx_store" / "sources" / ingested["source_id"]
		chunk_paths = sorted((source_dir / "chunks").glob("*.json"))
		self.assertEqual(len(chunk_paths), 3)
		agency_chunk = json.loads(chunk_paths[1].read_text(encoding="utf-8"))
		related_chunk = json.loads(chunk_paths[2].read_text(encoding="utf-8"))
		agency_chunk["relations"] = [{
			"type": "supports",
			"target": related_chunk["chunk_id"],
			"rationale": "Agency discussion supports the workshop continuity context.",
		}]
		chunk_paths[1].write_text(json.dumps(agency_chunk, indent=2), encoding="utf-8")
		service.rebuild_indexes()

		res = service.retrieve(
			query="human agency repair",
			active_source_ids=[ingested["source_id"]],
			seed_family="",
			top_k=3,
		)
		candidates_by_id = {item["chunk_id"]: item for item in res["trace"]["candidates"]}
		self.assertIn(related_chunk["chunk_id"], candidates_by_id)
		self.assertTrue(any("relation-neighborhood" in reason for reason in candidates_by_id[related_chunk["chunk_id"]]["why"]))
		self.assertGreater(candidates_by_id[related_chunk["chunk_id"]]["scores"]["relation"], 0.0)

	def test_context_graph_and_chat_artifacts_commit_to_store(self) -> None:
		service = StfxStoreService(self.workspace)
		graph = {
			"schema_version": 1,
			"name": "Test Context",
			"nodes": [{"id": "src_a", "kind": "content_source", "meta": {"name": "A"}}],
			"edges": [],
			"selection": {"active_source_ids": ["src_a"]},
		}
		graph_res = service.commit_context_graph(graph, {"produced_by": "test"})
		self.assertTrue(graph_res["ok"])
		graph_record = json.loads(Path(graph_res["path"]).read_text(encoding="utf-8"))
		self.assertEqual(graph_record["artifact_type"], "ui.context_graph")
		self.assertEqual(graph_record["payload"]["name"], "Test Context")

		chat_res = service.commit_artifact(
			"text.summary",
			{
				"assistant_response": "A response grounded in a context pack.",
				"context_meta": {"trace_id": "ret_1", "context_pack_id": "ctx_1"},
			},
			{
				"produced_by": "syntree.chat_with_stfx_store_context",
				"inputs": [
					{"type": "stfx_store.retrieval_trace", "trace_id": "ret_1"},
					{"type": "stfx_store.context_pack", "context_pack_id": "ctx_1"},
				],
			},
		)
		self.assertTrue(chat_res["ok"])
		chat_record = json.loads(Path(chat_res["path"]).read_text(encoding="utf-8"))
		self.assertEqual(chat_record["artifact_type"], "text.summary")
		self.assertEqual(chat_record["provenance"]["inputs"][0]["trace_id"], "ret_1")

	def test_memory_and_closure_records_are_canonical_and_indexed(self) -> None:
		service = StfxStoreService(self.workspace)
		ingested = service.ingest_source(str(self.source_md))
		source_dir = self.workspace.root / "stfx_store" / "sources" / ingested["source_id"]
		chunk_id = json.loads(sorted((source_dir / "chunks").glob("*.json"))[0].read_text(encoding="utf-8"))["chunk_id"]

		memory_res = service.commit_memory(
			{
				"title": "Human Agency Repair Memory",
				"summary": "Human agency is a repairable interpretive constraint.",
				"symbolic_address": {"primary_seed": "primary", "tensions": ["agency", "repair"]},
				"related": {"source_ids": [ingested["source_id"]], "chunk_ids": [chunk_id]},
				"rationale": "Captures a reusable symbolic memory from the ingested source.",
				"repair_notes": ["Review seed assignment after richer annotation."],
				"relations": [{
					"type": "grounds",
					"target": chunk_id,
					"rationale": "The source chunk grounds this memory.",
				}],
			},
			{"produced_by": "test.memory_commit"},
		)
		self.assertTrue(memory_res["ok"])
		memory_record = json.loads(Path(memory_res["path"]).read_text(encoding="utf-8"))
		self.assertEqual(memory_record["schema"], "stfx.memory.v1")
		self.assertEqual(memory_record["related"]["chunk_ids"], [chunk_id])

		closure_res = service.commit_closure(
			{
				"title": "Agency Repair Closure",
				"selected": {
					"source_ids": [ingested["source_id"]],
					"chunk_ids": [chunk_id],
					"memory_ids": [memory_res["memory_id"]],
				},
				"symbolic_constraints": {"primary_seed": "primary", "closure_depth": 2},
				"human_commit": {"committed_by": "tester", "decision": "accept"},
				"rationale": "Commits the source chunk and derived memory as a reviewable closure.",
				"relations": [{
					"type": "selects",
					"target": memory_res["memory_id"],
					"rationale": "The closure selects this memory.",
				}],
			},
			{"produced_by": "test.closure_commit"},
		)
		self.assertTrue(closure_res["ok"])
		closure_record = json.loads(Path(closure_res["path"]).read_text(encoding="utf-8"))
		self.assertEqual(closure_record["schema"], "stfx.closure.v1")
		self.assertEqual(closure_record["selected"]["memory_ids"], [memory_res["memory_id"]])

		validation = service.validate_store()
		self.assertTrue(validation["ok"], validation.get("errors"))
		status = service.status()
		self.assertEqual(status["manifest"]["counts"]["memories"], 1)
		self.assertEqual(status["manifest"]["counts"]["closures"], 1)
		self.assertEqual(len(service.list_memories()), 1)
		self.assertEqual(len(service.list_closures()), 1)

		relation_index = json.loads((self.workspace.root / "stfx_store" / "indexes" / "relation_index.json").read_text(encoding="utf-8"))
		edges = relation_index["edges"]
		self.assertTrue(any(edge["from"] == memory_res["memory_id"] and edge["to"] == chunk_id for edge in edges))
		self.assertTrue(any(edge["from"] == closure_res["closure_id"] and edge["to"] == memory_res["memory_id"] for edge in edges))

		symbolic_index = json.loads((self.workspace.root / "stfx_store" / "indexes" / "symbolic_index.json").read_text(encoding="utf-8"))
		self.assertIn(memory_res["memory_id"], symbolic_index["by_memory_seed"]["primary"])
		self.assertIn(memory_res["memory_id"], symbolic_index["by_memory_tension"]["agency"])
		self.assertEqual(symbolic_index["memory_related"][memory_res["memory_id"]]["chunk_ids"], [chunk_id])
		self.assertIn(closure_res["closure_id"], symbolic_index["by_closure_seed"]["primary"])
		self.assertEqual(symbolic_index["closure_selected"][closure_res["closure_id"]]["memory_ids"], [memory_res["memory_id"]])

	def test_concurrent_memory_commits_are_write_guarded(self) -> None:
		service = StfxStoreService(self.workspace)

		def commit_memory(idx: int) -> str:
			res = service.commit_memory(
				{
					"title": f"Concurrent Memory {idx}",
					"summary": "Concurrent memory write smoke test.",
					"symbolic_address": {"primary_seed": "primary", "tensions": ["concurrency"]},
					"related": {"source_ids": [], "chunk_ids": []},
					"rationale": "Ensures concurrent writers leave canonical records and indexes valid.",
				},
				{"produced_by": "test.concurrent_memory_commit"},
			)
			self.assertTrue(res["ok"])
			return str(res["memory_id"])

		with ThreadPoolExecutor(max_workers=4) as pool:
			memory_ids = list(pool.map(commit_memory, range(8)))

		validation = service.validate_store()
		self.assertTrue(validation["ok"], validation.get("errors"))
		status = service.status()
		self.assertEqual(status["manifest"]["counts"]["memories"], 8)
		self.assertEqual(len(service.list_memories()), 8)

		symbolic_index = json.loads((self.workspace.root / "stfx_store" / "indexes" / "symbolic_index.json").read_text(encoding="utf-8"))
		for memory_id in memory_ids:
			self.assertIn(memory_id, symbolic_index["by_memory_seed"]["primary"])
			self.assertIn(memory_id, symbolic_index["by_memory_tension"]["concurrency"])

	def test_context_pack_converts_to_scensyn_continuity_state(self) -> None:
		service = StfxStoreService(self.workspace)
		ingested = service.ingest_source(str(self.source_md))
		res = service.retrieve(
			query="human agency repair continuity",
			active_source_ids=[ingested["source_id"]],
			seed_family="primary",
			top_k=2,
		)
		state = build_scenario_continuity_state_from_context_pack(res["context_pack"])
		self.assertTrue(state["ok"])
		self.assertEqual(state["contract_type"], "scensyn.scenario_continuity_state")
		mem_ctx = state["state_patch"]["memory_context"]
		self.assertEqual(mem_ctx["context_pack_id"], res["context_pack"]["context_pack_id"])
		self.assertEqual(mem_ctx["trace_id"], res["trace"]["trace_id"])
		self.assertIn("stfx_store.context_pack", state["provenance"]["inputs"][0]["type"])

	def test_scensyn_continuity_context_artifact_payload_is_committable(self) -> None:
		service = StfxStoreService(self.workspace)
		ingested = service.ingest_source(str(self.source_md))
		res = service.retrieve(
			query="human agency repair continuity",
			active_source_ids=[ingested["source_id"]],
			seed_family="primary",
			top_k=2,
		)
		state = build_scenario_continuity_state_from_context_pack(res["context_pack"])
		payload = build_store_context_continuity_artifact_payload(
			state,
			context_pack_id=res["context_pack"]["context_pack_id"],
			session_id="sess_test",
		)
		artifact_res = service.commit_artifact(
			"json.scensyn_continuity_context",
			payload,
			{
				"produced_by": "scensyn.continuity_state_from_store_context",
				"inputs": state["provenance"]["inputs"],
				"session_id": "sess_test",
			},
		)
		self.assertTrue(artifact_res["ok"])
		record = json.loads(Path(artifact_res["path"]).read_text(encoding="utf-8"))
		self.assertEqual(record["artifact_type"], "json.scensyn_continuity_context")
		self.assertEqual(record["payload"]["session_id"], "sess_test")
		self.assertEqual(record["payload"]["context_pack_id"], res["context_pack"]["context_pack_id"])
		self.assertEqual(record["payload"]["trace_id"], res["trace"]["trace_id"])

	def test_llm_assisted_ingest_is_reviewable_and_not_runtime_dependency(self) -> None:
		service = StfxStoreService(self.workspace)
		res = service.ingest_source(
			str(self.source_md),
			llm_recommendations={
				"chunks": [{
					"chunk_index": 1,
					"summary": "Human agency and repairability.",
					"primary_seed": "rhythmic",
					"tensions": ["agency", "repair"],
					"nesting_path": ["Forward Remembrance", "Human AI Agency"],
					"rationale": "The section directly names agency and auditability.",
				}]
			},
		)
		self.assertTrue(res["ok"])
		chunks = sorted((self.workspace.root / "stfx_store" / "sources" / res["source_id"] / "chunks").glob("*.json"))
		agency_chunk = json.loads(chunks[1].read_text(encoding="utf-8"))
		self.assertEqual(agency_chunk["symbolic"]["primary_seed"], "rhythmic")
		self.assertTrue(agency_chunk["ingest_assist"]["review_required"])
		self.assertFalse(agency_chunk["ingest_assist"]["runtime_dependency"])
		self.assertTrue(service.validate_store()["ok"])

	def test_config_vector_sqlite_and_chunk_repair_are_rebuildable(self) -> None:
		service = StfxStoreService(self.workspace)
		ingested = service.ingest_source(str(self.source_md))
		cfg = service.update_config(True, {"vector": True, "sqlite": True})
		self.assertTrue(cfg["ok"])
		indexes_dir = self.workspace.root / "stfx_store" / "indexes"
		vector = json.loads((indexes_dir / "vector_index.manifest.json").read_text(encoding="utf-8"))
		self.assertTrue(vector["enabled"])
		self.assertGreaterEqual(len(vector["vectors"]), 1)
		self.assertTrue((indexes_dir / "store_mirror.sqlite").exists())
		chunk_id = next(iter(vector["vectors"].keys()))
		repair = service.update_chunk_symbolic(
			chunk_id,
			{"primary_seed": "transitional", "rationale": "Reviewed in test."},
			"Test symbolic repair.",
		)
		self.assertTrue(repair["ok"])
		chunk = service.get_chunk_record(chunk_id)["chunk"]
		self.assertEqual(chunk["symbolic"]["primary_seed"], "transitional")
		self.assertEqual(service.get_index("vector")["index"]["vectors"][chunk_id]["content_hash"], chunk["content_hash"])
		self.assertTrue(service.validate_store()["ok"])
		self.assertEqual(service.list_sources()[0]["source_id"], ingested["source_id"])

	def test_migration_export_reports_are_written(self) -> None:
		service = StfxStoreService(self.workspace)
		legacy_dir = self.workspace.root / "stfx_memory" / "documents"
		legacy_dir.mkdir(parents=True, exist_ok=True)
		(legacy_dir / "doc.json").write_text(json.dumps({"document_id": "doc_1"}), encoding="utf-8")
		artifact_dir = self.workspace.artifacts_dir / "ui.context_graph"
		artifact_dir.mkdir(parents=True, exist_ok=True)
		(artifact_dir / "graph.json").write_text(json.dumps({"artifact_type": "ui.context_graph"}), encoding="utf-8")
		mem_report = service.export_legacy_stfx_memory()
		graph_report = service.export_syntree_context_graphs()
		substrate_report = service.export_substrate_artifact_mirrors()
		self.assertTrue(mem_report["ok"])
		self.assertEqual(mem_report["report"]["candidate_count"], 1)
		self.assertTrue(graph_report["ok"])
		self.assertEqual(graph_report["report"]["candidate_count"], 1)
		self.assertTrue(substrate_report["ok"])
		self.assertTrue(Path(mem_report["path"]).exists())

	def test_hub_route_contract_methods_roundtrip(self) -> None:
		service = StfxStoreService(self.workspace)
		self.assertTrue(service.status()["ok"])
		self.assertTrue(service.update_config(True, {"vector": True, "sqlite": True})["ok"])
		ingest = service.ingest_source(str(self.source_md), default_seed="primary")
		source_id = ingest["source_id"]
		res = service.retrieve("human agency repair", active_source_ids=[source_id], top_k=1)
		trace_id = res["trace"]["trace_id"]
		context_pack_id = res["context_pack"]["context_pack_id"]
		chunk_id = res["context_pack"]["chunks"][0]["chunk_id"]
		self.assertEqual(service.get_trace(trace_id)["trace_id"], trace_id)
		self.assertEqual(service.get_context_pack(context_pack_id)["context_pack_id"], context_pack_id)
		self.assertEqual(service.list_context_packs()[0]["context_pack_id"], context_pack_id)
		self.assertTrue(service.get_index("vector")["ok"])
		self.assertTrue(service.update_chunk_symbolic(chunk_id, {"primary_seed": "primary", "rationale": "Route contract repair."}, "Route contract repair.")["ok"])
		self.assertTrue(service.export_legacy_stfx_memory()["ok"])

	def test_hub_route_integration_roundtrip(self) -> None:
		app = FastAPI()
		app.state.cfg = SimpleNamespace(workspace=self.workspace)
		app.state.stfx_store = None
		app.include_router(store_router, prefix="/stfx-store")
		client = TestClient(app)
		self.assertTrue(client.get("/stfx-store/status").json()["ok"])
		self.assertTrue(client.post("/stfx-store/config", json={"enabled": True, "accelerators": {"vector": True, "sqlite": True}}).json()["ok"])
		ingest = client.post("/stfx-store/sources/ingest", json={"source_path": str(self.source_md), "default_seed": "primary"})
		self.assertEqual(ingest.status_code, 200)
		source_id = ingest.json()["source_id"]
		retrieve = client.post("/stfx-store/retrieve", json={"query": "human agency repair", "active_source_ids": [source_id], "top_k": 1})
		self.assertEqual(retrieve.status_code, 200)
		body = retrieve.json()
		trace_id = body["trace"]["trace_id"]
		context_pack_id = body["context_pack"]["context_pack_id"]
		chunk_id = body["context_pack"]["chunks"][0]["chunk_id"]
		self.assertEqual(client.get(f"/stfx-store/traces/{trace_id}").status_code, 200)
		self.assertEqual(client.get(f"/stfx-store/context-packs/{context_pack_id}").status_code, 200)
		self.assertEqual(client.get("/stfx-store/indexes/vector").status_code, 200)
		repair = client.post(
			f"/stfx-store/chunks/{chunk_id}/symbolic",
			json={"symbolic": {"primary_seed": "primary", "rationale": "Route repair."}, "repair_note": "Route repair."},
		)
		self.assertEqual(repair.status_code, 200)
		self.assertTrue(client.post("/stfx-store/migrations/substrate-artifacts/export").json()["ok"])

	def test_admissibility_gate_excludes_promotional_sources(self) -> None:
		from app.stfx_store.admissibility import classify_source, normalize_admissibility_config

		service = StfxStoreService(self.workspace)
		canon = service.ingest_source(str(self.source_md))
		promo_path = self.workspace.root / "promo_note.md"
		promo_path.write_text("# Promo\n\nBuy our repair kit today.\n", encoding="utf-8")
		promo = service.ingest_source(str(promo_path))
		promo_source_path = self.workspace.root / "stfx_store" / "sources" / promo["source_id"] / "source.json"
		promo_record = json.loads(promo_source_path.read_text(encoding="utf-8"))
		promo_record["source_type"] = "promotional"
		promo_record["provenance"]["produced_by"] = "partner_marketing"
		promo_source_path.write_text(json.dumps(promo_record, indent=2), encoding="utf-8")
		service.rebuild_indexes()

		cfg = normalize_admissibility_config({
			"enabled": True,
			"uncertain_exclude": False,
			"forbidden_source_types": ["promotional"],
			"forbidden_produced_by_prefixes": ["llm_generation"],
			"forbidden_authorship_kinds": [],
		})
		forbidden, reason = classify_source(promo_record, cfg)
		self.assertTrue(forbidden)
		self.assertIn("promotional", reason)

		# Disabled: promotional chunks may still enter the pack.
		off = service.retrieve(
			query="repair kit",
			active_source_ids=[canon["source_id"], promo["source_id"]],
			top_k=5,
		)
		self.assertFalse(off["admissibility"]["enabled"])

		service.update_config(admissibility={
			"enabled": True,
			"uncertain_exclude": False,
			"forbidden_source_types": ["promotional"],
			"forbidden_produced_by_prefixes": ["llm_generation"],
			"forbidden_authorship_kinds": [],
			"persist_closure": True,
		})
		on = service.retrieve(
			query="repair kit",
			active_source_ids=[canon["source_id"], promo["source_id"]],
			top_k=5,
		)
		self.assertTrue(on["admissibility"]["enabled"])
		self.assertIn(promo["source_id"], on["admissibility"]["forbidden_source_ids"])
		pack_source_ids = {str(c.get("source_id", "")) for c in on["context_pack"]["chunks"]}
		self.assertNotIn(promo["source_id"], pack_source_ids)
		self.assertTrue(on["admissibility"]["provably_faithful"])
		self.assertEqual(on["admissibility"]["leakage"], 0.0)
		policy_rejects = [
			r for r in on["trace"]["rejected"]
			if str(r.get("rejection_axis", "")) == "admissibility"
		]
		self.assertGreaterEqual(len(policy_rejects), 1)
		self.assertTrue(str(on["admissibility"].get("closure_id", "")).startswith("clo_"))
		plan_adm = on["trace"]["retrieval_plan"].get("admissibility", {})
		self.assertTrue(plan_adm.get("enabled"))


if __name__ == "__main__":
	unittest.main()
