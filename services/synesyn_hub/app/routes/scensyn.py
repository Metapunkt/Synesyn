from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict

from typing import Any, Dict

from ..app_adapters import (
	build_scenario_continuity_state,
	build_scenario_continuity_state_from_context_pack,
	build_store_context_continuity_artifact_payload,
	build_vis_story_cycle_payload,
	build_vis_story_v2_cycle_payload,
	compose_reading,
	compose_character_prompts,
	compose_vis_story_context,
	compose_seekers_journey_prompt,
	get_heartbeat_fragment,
)
from ..stfx_memory.routes import _get_service
from ..stfx_store.routes import _get_service as _get_store_service


router = APIRouter()


class ScenarioContinuityFromMemoryRequest(BaseModel):
	document_id: str
	chunk_path: str = ""
	depth: int = 2
	sibling_window: int = 2


class ScenarioContinuityFromStoreContextRequest(BaseModel):
	context_pack_id: str
	commit_artifact: bool = False
	session_id: str = ""


class ScenarioContextPayload(BaseModel):
	model_config = ConfigDict(extra="allow")
	name: str = ""
	location_and_setting: str = ""
	objective: str = ""


class VisStoryCycleFromContinuityRequest(BaseModel):
	continuity_state: Dict[str, Any]
	cycle_id: int = 1
	scenario_context: ScenarioContextPayload | None = None


class VisStoryCycleFromMemoryRequest(BaseModel):
	document_id: str
	chunk_path: str = ""
	depth: int = 2
	sibling_window: int = 2
	cycle_id: int = 1
	scenario_context: ScenarioContextPayload | None = None


class VisStoryV2CycleFromContinuityRequest(BaseModel):
	continuity_state: Dict[str, Any]
	cycle_id: int = 1
	scenario_context: ScenarioContextPayload | None = None
	max_panels_per_turn: int = 12
	panels_to_render: int = 6
	selection_mode: str = "spread"
	panel_indices: list[int] = []
	max_concurrent_renders: int = 2


class VisStoryV2CycleFromMemoryRequest(BaseModel):
	document_id: str
	chunk_path: str = ""
	depth: int = 2
	sibling_window: int = 2
	cycle_id: int = 1
	scenario_context: ScenarioContextPayload | None = None
	max_panels_per_turn: int = 12
	panels_to_render: int = 6
	selection_mode: str = "spread"
	panel_indices: list[int] = []
	max_concurrent_renders: int = 2


def _scenario_context_dict(payload: ScenarioContextPayload | None) -> Dict[str, Any]:
	if payload is None:
		return {}
	if hasattr(payload, "model_dump"):
		return payload.model_dump()
	return payload.dict()


@router.post("/continuity-state/from-memory")
async def continuity_state_from_memory(payload: ScenarioContinuityFromMemoryRequest, request: Request):
	service = _get_service(request)
	try:
		ctx = service.continuity_context(
			document_id=payload.document_id,
			chunk_path=payload.chunk_path,
			depth=payload.depth,
			sibling_window=payload.sibling_window,
		)
		return build_scenario_continuity_state(ctx)
	except KeyError as e:
		raise HTTPException(status_code=404, detail=str(e))
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


@router.post("/continuity-state/from-store-context")
async def continuity_state_from_store_context(payload: ScenarioContinuityFromStoreContextRequest, request: Request):
	service = _get_store_service(request)
	try:
		pack = service.get_context_pack(payload.context_pack_id)
		state = build_scenario_continuity_state_from_context_pack(pack)
		if payload.commit_artifact:
			artifact_payload = build_store_context_continuity_artifact_payload(
				state,
				context_pack_id=payload.context_pack_id,
				session_id=payload.session_id,
			)
			artifact_res = service.commit_artifact(
				"json.scensyn_continuity_context",
				artifact_payload,
				{
					"produced_by": "scensyn.continuity_state_from_store_context",
					"inputs": artifact_payload.get("continuity_state", {}).get("provenance", {}).get("inputs", []),
					"session_id": payload.session_id,
				},
			)
			artifact_id = str(artifact_res.get("artifact_id", "")).strip()
			if artifact_id:
				state.setdefault("provenance", {})
				state["provenance"]["continuity_artifact_id"] = artifact_id
				state["provenance"]["continuity_artifact_type"] = "json.scensyn_continuity_context"
				state.setdefault("state_patch", {})
				state["state_patch"].setdefault("memory_context", {})
				state["state_patch"]["memory_context"]["continuity_artifact_id"] = artifact_id
		return state
	except KeyError as e:
		raise HTTPException(status_code=404, detail=str(e))
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


@router.post("/vis-story-cycle/from-continuity")
async def vis_story_cycle_from_continuity(payload: VisStoryCycleFromContinuityRequest):
	try:
		return build_vis_story_cycle_payload(
			payload.continuity_state,
			cycle_id=payload.cycle_id,
			scenario_context=_scenario_context_dict(payload.scenario_context),
		)
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


@router.post("/vis-story-cycle/from-memory")
async def vis_story_cycle_from_memory(payload: VisStoryCycleFromMemoryRequest, request: Request):
	service = _get_service(request)
	try:
		ctx = service.continuity_context(
			document_id=payload.document_id,
			chunk_path=payload.chunk_path,
			depth=payload.depth,
			sibling_window=payload.sibling_window,
		)
		state = build_scenario_continuity_state(ctx)
		return build_vis_story_cycle_payload(
			state,
			cycle_id=payload.cycle_id,
			scenario_context=_scenario_context_dict(payload.scenario_context),
		)
	except KeyError as e:
		raise HTTPException(status_code=404, detail=str(e))
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


@router.post("/vis-story-v2-cycle/from-continuity")
async def vis_story_v2_cycle_from_continuity(payload: VisStoryV2CycleFromContinuityRequest):
	try:
		return build_vis_story_v2_cycle_payload(
			payload.continuity_state,
			cycle_id=payload.cycle_id,
			scenario_context=_scenario_context_dict(payload.scenario_context),
			max_panels_per_turn=payload.max_panels_per_turn,
			panels_to_render=payload.panels_to_render,
			selection_mode=payload.selection_mode,
			panel_indices=payload.panel_indices,
			max_concurrent_renders=payload.max_concurrent_renders,
		)
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


@router.post("/vis-story-v2-cycle/from-memory")
async def vis_story_v2_cycle_from_memory(payload: VisStoryV2CycleFromMemoryRequest, request: Request):
	service = _get_service(request)
	try:
		ctx = service.continuity_context(
			document_id=payload.document_id,
			chunk_path=payload.chunk_path,
			depth=payload.depth,
			sibling_window=payload.sibling_window,
		)
		state = build_scenario_continuity_state(ctx)
		return build_vis_story_v2_cycle_payload(
			state,
			cycle_id=payload.cycle_id,
			scenario_context=_scenario_context_dict(payload.scenario_context),
			max_panels_per_turn=payload.max_panels_per_turn,
			panels_to_render=payload.panels_to_render,
			selection_mode=payload.selection_mode,
			panel_indices=payload.panel_indices,
			max_concurrent_renders=payload.max_concurrent_renders,
		)
	except KeyError as e:
		raise HTTPException(status_code=404, detail=str(e))
	except ValueError as e:
		raise HTTPException(status_code=400, detail=str(e))


# ── Verse system endpoints ─────────────────────────────────────────────


class VerseReadingRequest(BaseModel):
	odu_name: str
	resonance: float = 0.5
	complement_odu: str = ""
	stability: float = 0.5
	crossings: int = 0
	turn_seed: str = ""


class VerseCharacterPromptsRequest(BaseModel):
	odu_name: str
	resonance: float = 0.5
	complement_odu: str = ""
	stability: float = 0.5
	crossings: int = 0
	turn_seed: str = ""
	turn_context: Dict[str, Any] = {}


class SeekersJourneyRequest(BaseModel):
	odu_name: str
	resonance: float = 0.5
	complement_odu: str = ""
	stability: float = 0.5
	crossings: int = 0
	turn_seed: str = ""
	turn_context: Dict[str, Any] = {}
	previous_paragraphs: list[str] = []
	turn_number: int = 1


class HeartbeatRequest(BaseModel):
	past_readings: list[Dict[str, Any]] = []
	seed: str = ""


@router.post("/verse/reading")
async def verse_reading(payload: VerseReadingRequest):
	import traceback
	try:
		reading = compose_reading(
			odu_name=payload.odu_name,
			resonance=payload.resonance,
			complement_odu=payload.complement_odu or None,
			stability=payload.stability,
			crossings=payload.crossings,
			turn_seed=payload.turn_seed,
		)
		return {"ok": True, "reading": reading}
	except Exception as e:
		traceback.print_exc()
		raise HTTPException(status_code=500, detail=f"verse/reading failed: {e}")


@router.post("/verse/character-prompts")
async def verse_character_prompts(payload: VerseCharacterPromptsRequest):
	import traceback
	try:
		reading = compose_reading(
			odu_name=payload.odu_name,
			resonance=payload.resonance,
			complement_odu=payload.complement_odu or None,
			stability=payload.stability,
			crossings=payload.crossings,
			turn_seed=payload.turn_seed,
		)
		prompts = compose_character_prompts(reading, payload.turn_context)
		vis_context = compose_vis_story_context(reading, payload.turn_context)
		return {
			"ok": True,
			"reading": reading,
			"character_prompts": prompts,
			"vis_story_context": vis_context,
		}
	except Exception as e:
		traceback.print_exc()
		raise HTTPException(status_code=500, detail=f"verse/character-prompts failed: {e}")


@router.post("/verse/seekers-journey-prompt")
async def seekers_journey_prompt(payload: SeekersJourneyRequest):
	import traceback
	try:
		reading = compose_reading(
			odu_name=payload.odu_name,
			resonance=payload.resonance,
			complement_odu=payload.complement_odu or None,
			stability=payload.stability,
			crossings=payload.crossings,
			turn_seed=payload.turn_seed,
		)
		prompt_text = compose_seekers_journey_prompt(
			reading=reading,
			turn_context=payload.turn_context,
			previous_paragraphs=payload.previous_paragraphs,
			turn_number=payload.turn_number,
		)
		return {
			"ok": True,
			"reading": reading,
			"journey_prompt": {
				"system": "",
				"user": prompt_text,
			},
		}
	except Exception as e:
		traceback.print_exc()
		raise HTTPException(status_code=500, detail=f"verse/seekers-journey-prompt failed: {e}")


@router.post("/verse/heartbeat")
async def verse_heartbeat(payload: HeartbeatRequest):
	import traceback
	try:
		fragment = get_heartbeat_fragment(
			past_readings=payload.past_readings,
			seed=payload.seed,
		)
		if fragment is None:
			return {"ok": True, "fragment": None}
		return {"ok": True, "fragment": fragment}
	except Exception as e:
		traceback.print_exc()
		raise HTTPException(status_code=500, detail=f"verse/heartbeat failed: {e}")


@router.get("/verse/health")
async def verse_health():
	"""Diagnostic endpoint to verify the verse corpus is loaded and healthy."""
	import traceback
	try:
		from ..app_adapters.verse_engine import _load_corpus
		corpus = _load_corpus()
		verse_count = len(corpus.get("verses", []))
		odu_names = [v["odu_name"] for v in corpus.get("verses", [])]
		return {
			"ok": True,
			"corpus_version": corpus.get("corpus_version", "unknown"),
			"verse_count": verse_count,
			"odu_names": odu_names,
		}
	except Exception as e:
		traceback.print_exc()
		return {"ok": False, "error": str(e)}
