from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve()
HUB_ROOT = HERE.parents[1]
if str(HUB_ROOT) not in sys.path:
	sys.path.insert(0, str(HUB_ROOT))

from app.config import WorkspaceConfig
from app.app_adapters import (
	build_scenario_continuity_state,
	build_vis_story_cycle_payload,
	build_vis_story_v2_cycle_payload,
)
from app.stfx_memory.service import StfxMemoryService


def _nested_analysis(_text: str) -> dict:
	return {
		"recommended_root_seed": "primary",
		"root_rationale": "Test analyzer root rationale.",
		"chunks": [
			{
				"id": "chapter_1",
				"summary": "Assembly memory",
				"recommended_sub_seed": "transitional",
				"selection_rationale": "Top-level context.",
				"start_offset": 0,
				"end_offset": 10,
				"sub_chunks": [
					{
						"id": "scene_a",
						"summary": "Doorway negotiation",
						"recommended_sub_seed": "rhythmic",
						"selection_rationale": "Branch focus.",
						"start_offset": 1,
						"end_offset": 4,
						"sub_chunks": [],
					},
					{
						"id": "scene_b",
						"summary": "Threshold crossing",
						"recommended_sub_seed": "alternating",
						"selection_rationale": "Sibling contrast.",
						"start_offset": 5,
						"end_offset": 8,
						"sub_chunks": [],
					},
				],
			},
		],
	}


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


class TestStfxMemory(unittest.TestCase):
	def setUp(self) -> None:
		self.tmp = tempfile.TemporaryDirectory()
		self.base = Path(self.tmp.name)
		self.source_md = self.base / "source.md"
		self.source_md.write_text(
			"# Chapter One\n"
			"alpha\n"
			"## Section A\n"
			"beta\n"
			"# Chapter Two\n"
			"gamma\n",
			encoding="utf-8",
		)
		self.ws1 = _make_workspace(self.base / "Workspace_A", "Workspace A", "workspace-a")
		self.ws2 = _make_workspace(self.base / "Workspace_B", "Workspace B", "workspace-b")

	def tearDown(self) -> None:
		self.tmp.cleanup()

	def test_ingest_copies_source_into_workspace_store(self) -> None:
		service = StfxMemoryService(self.ws1)
		res = service.ingest_document(str(self.source_md))
		doc = service.get_document(res["document_id"])
		source_path = Path(doc["source_ref"]["path"])
		self.assertTrue(source_path.exists())
		self.assertIn("stfx_memory", str(source_path))
		self.assertIn("sources", str(source_path))
		self.assertEqual(doc["metadata"]["original_source_ref"]["path"], str(self.source_md))

	def test_chunk_path_traversal_returns_target_chunk(self) -> None:
		service = StfxMemoryService(self.ws1)
		res = service.ingest_document(str(self.source_md))
		doc = service.get_document(res["document_id"])
		self.assertIn("section_0", doc["chunks"])
		chunk = service.retrieve(document_id=res["document_id"], chunk_path="section_0")["chunk"]
		self.assertEqual(chunk["path"], "section_0")
		self.assertEqual(chunk["summary"], "Chapter One")

	def test_expansion_returns_expected_shape_and_metadata(self) -> None:
		service = StfxMemoryService(self.ws1)
		res = service.ingest_document(str(self.source_md))
		expanded = service.expand(res["document_id"], depth=2)
		self.assertTrue(expanded["ok"])
		self.assertEqual(expanded["seed_family"], "primary")
		self.assertEqual(expanded["depth"], 2)
		self.assertEqual(expanded["matrix_shape"], [64, 64])
		self.assertIn("complementarity_verified", expanded["meta"])

	def test_export_payload_supports_ingest_report_and_seed_registry(self) -> None:
		service = StfxMemoryService(self.ws1)
		res = service.ingest_document(str(self.source_md))
		report_export = service.export_payload("ingest_report", res["document_id"])
		self.assertEqual(report_export["artifact_type"], "json.stfx_memory_ingest_report")
		self.assertEqual(report_export["payload"]["document_id"], res["document_id"])
		reg_export = service.export_payload("seed_registry", "")
		self.assertEqual(reg_export["artifact_type"], "json.stfx_seed_registry_export")
		self.assertIn("primary", reg_export["payload"]["seed_registry"])

	def test_workspaces_are_isolated(self) -> None:
		service_a = StfxMemoryService(self.ws1)
		service_b = StfxMemoryService(self.ws2)
		res_a = service_a.ingest_document(str(self.source_md))
		docs_a = service_a.list_documents()
		docs_b = service_b.list_documents()
		self.assertEqual(len(docs_a), 1)
		self.assertEqual(docs_a[0]["document_id"], res_a["document_id"])
		self.assertEqual(docs_b, [])
		index_a = json.loads((self.ws1.root / "stfx_memory" / "memory_index.json").read_text(encoding="utf-8"))
		index_b = json.loads((self.ws2.root / "stfx_memory" / "memory_index.json").read_text(encoding="utf-8"))
		self.assertEqual(len(index_a["documents"]), 1)
		self.assertEqual(len(index_b["documents"]), 0)

	def test_continuity_context_contract_is_app_agnostic_and_deterministic(self) -> None:
		service = StfxMemoryService(self.ws1)
		res = service.ingest_document(str(self.source_md), llm_callable=_nested_analysis)
		ctx = service.continuity_context(
			document_id=res["document_id"],
			chunk_path="chapter_1.scene_a",
			depth=2,
			sibling_window=1,
		)
		self.assertTrue(ctx["ok"])
		self.assertEqual(ctx["contract_type"], "stfx_memory.continuity_context")
		self.assertEqual(ctx["target"]["chunk_path"], "chapter_1.scene_a")
		self.assertEqual(ctx["target"]["seed_family"], "rhythmic")
		self.assertEqual(len(ctx["lineage"]), 2)
		self.assertEqual(ctx["lineage"][0]["path"], "chapter_1")
		self.assertEqual(ctx["lineage"][1]["path"], "chapter_1.scene_a")
		self.assertEqual(len(ctx["sibling_context"]), 1)
		self.assertEqual(ctx["sibling_context"][0]["path"], "chapter_1.scene_b")
		self.assertEqual(ctx["symbolic_context"]["matrix_shape"], [64, 64])
		self.assertIn("assembly", ctx["carry_forward"]["focus_terms"])

	def test_scensyn_scenario_continuity_state_contract_maps_memory_context(self) -> None:
		service = StfxMemoryService(self.ws1)
		res = service.ingest_document(str(self.source_md), llm_callable=_nested_analysis)
		ctx = service.continuity_context(
			document_id=res["document_id"],
			chunk_path="chapter_1.scene_a",
			depth=2,
			sibling_window=1,
		)
		state = build_scenario_continuity_state(ctx)
		self.assertTrue(state["ok"])
		self.assertEqual(state["contract_type"], "scensyn.scenario_continuity_state")
		self.assertEqual(state["scenario_focus"]["chunk_path"], "chapter_1.scene_a")
		self.assertEqual(state["continuity"]["recommended_narrative_phase"], "rising")
		self.assertEqual(state["symbolic_signals"]["active_seed_family"], "rhythmic")
		self.assertEqual(state["state_patch"]["current_narrative_phase_hint"], "rising")
		self.assertIn("Doorway negotiation", state["continuity"]["anchors"])
		self.assertEqual(state["continuity"]["latent_tensions"][0]["path"], "chapter_1.scene_b")

	def test_vis_story_cycle_payload_is_deterministic_and_cycle_shaped(self) -> None:
		service = StfxMemoryService(self.ws1)
		res = service.ingest_document(str(self.source_md), llm_callable=_nested_analysis)
		ctx = service.continuity_context(
			document_id=res["document_id"],
			chunk_path="chapter_1.scene_a",
			depth=2,
			sibling_window=1,
		)
		state = build_scenario_continuity_state(ctx)
		payload = build_vis_story_cycle_payload(
			state,
			cycle_id=7,
			scenario_context={
				"name": "Stochastic Dreams",
				"location_and_setting": "The Oscillator's Court",
				"objective": "Interpret the current divination window.",
			},
		)
		self.assertTrue(payload["ok"])
		self.assertEqual(payload["contract_type"], "scensyn.vis_story_cycle")
		story = payload["story_json"]
		self.assertEqual(story["version"], "sd_phase2_v1")
		self.assertEqual(len(story["cycles"]), 1)
		cycle = story["cycles"][0]
		self.assertEqual(cycle["cycle_id"], 7)
		self.assertEqual(cycle["story_arc_tag"], "systemic_repair")
		self.assertEqual(len(cycle["panels"]), 6)
		self.assertEqual(cycle["panels"][0]["narrative_register"], "civic_diary")
		self.assertEqual(cycle["panels"][5]["narrative_register"], "recollection")
		self.assertEqual(cycle["panels"][0]["story_state_in"]["continuity_anchor"], "Doorway negotiation")
		self.assertEqual(cycle["panels"][0]["story_state_out"]["latent_tension"], "Threshold crossing")
		self.assertEqual(cycle["panels"][0]["seed"], build_vis_story_cycle_payload(state, cycle_id=7)["story_json"]["cycles"][0]["panels"][0]["seed"])

	def test_vis_story_v2_cycle_payload_carries_render_plan_and_variable_panel_count(self) -> None:
		service = StfxMemoryService(self.ws1)
		res = service.ingest_document(str(self.source_md), llm_callable=_nested_analysis)
		ctx = service.continuity_context(
			document_id=res["document_id"],
			chunk_path="chapter_1.scene_a",
			depth=2,
			sibling_window=1,
		)
		state = build_scenario_continuity_state(ctx)
		payload = build_vis_story_v2_cycle_payload(
			state,
			cycle_id=11,
			scenario_context={
				"name": "Stochastic Dreams",
				"location_and_setting": "The Oscillator's Court",
				"objective": "Interpret the current divination window.",
			},
			max_panels_per_turn=12,
			panels_to_render=6,
			selection_mode="spread",
			panel_indices=[],
			max_concurrent_renders=2,
		)
		self.assertTrue(payload["ok"])
		self.assertEqual(payload["contract_type"], "scensyn.vis_story_v2_cycle")
		story = payload["story_json"]
		self.assertEqual(story["version"], "sd_phase3_v1")
		self.assertEqual(len(story["cycles"]), 1)
		cycle = story["cycles"][0]
		self.assertEqual(cycle["cycle_id"], 11)
		self.assertEqual(cycle["story_arc_tag"], "systemic_repair")
		self.assertEqual(cycle["render_plan"]["max_panels_per_turn"], 12)
		self.assertEqual(cycle["render_plan"]["panels_to_render"], 6)
		self.assertEqual(cycle["render_plan"]["selection_mode"], "spread")
		self.assertEqual(cycle["render_plan"]["max_concurrent_renders"], 2)
		self.assertEqual(len(cycle["panels"]), 12)
		self.assertEqual(cycle["panels"][0]["panel_role"], "hero")
		self.assertEqual(cycle["panels"][11]["panel_index"], 12)
		self.assertEqual(
			cycle["panels"][0]["seed"],
			build_vis_story_v2_cycle_payload(
				state,
				cycle_id=11,
				max_panels_per_turn=12,
				panels_to_render=6,
				selection_mode="spread",
			)["story_json"]["cycles"][0]["panels"][0]["seed"],
		)


if __name__ == "__main__":
	unittest.main()
