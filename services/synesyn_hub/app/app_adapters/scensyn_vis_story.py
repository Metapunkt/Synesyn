from __future__ import annotations

import hashlib
from typing import Any, Dict, List


_ARC_TAG_BY_PHASE = {
    "setup": "founding_gestures",
    "incident": "civic_emergence",
    "rising": "systemic_repair",
    "climax": "transformation",
    "resolution": "renewal",
}

_PANELS: List[Dict[str, Any]] = [
    {
        "panel_index": 1,
        "sector": {"id": "governance", "name": "Governance", "color_hex": "#8ad0ff"},
        "theme": {"id": "transparent_rule", "name": "Transparent Rule"},
        "action": {"id": "transparent_rule", "name": "Transparent Rule"},
        "narrative_register": "civic_diary",
        "prompt_template": "{setting}; civic pathways around {anchor}; visible decision traces, governance-blue accents, calm crowd, naturalistic lighting, no readable text.",
    },
    {
        "panel_index": 2,
        "sector": {"id": "governance", "name": "Governance", "color_hex": "#8ad0ff"},
        "theme": {"id": "participatory_democracy", "name": "Participatory Democracy"},
        "action": {"id": "open_data", "name": "Open Data"},
        "narrative_register": "field_report",
        "prompt_template": "{setting}; public interfaces, ledgers, and route maps around {focus_a}; candid reportage framing, governance-blue accents, no readable text.",
    },
    {
        "panel_index": 3,
        "sector": {"id": "governance", "name": "Governance", "color_hex": "#8ad0ff"},
        "theme": {"id": "inclusive_leadership", "name": "Inclusive Leadership"},
        "action": {"id": "inclusive_leadership", "name": "Inclusive Leadership"},
        "narrative_register": "manifesto",
        "prompt_template": "{setting}; an assembly organized around {anchor} and {focus_a}; bold composition, cool blue highlights, no readable text.",
    },
    {
        "panel_index": 4,
        "sector": {"id": "social_equity", "name": "Social Equity & Justice", "color_hex": "#ffd27a"},
        "theme": {"id": "economic_inclusion", "name": "Economic Inclusion"},
        "action": {"id": "job_creation", "name": "Job Creation"},
        "narrative_register": "neighborhood_notice",
        "prompt_template": "{setting}; mutual aid, repair, and care infrastructures responding to {challenge}; warm amber palette, street-level human presence, no readable text.",
    },
    {
        "panel_index": 5,
        "sector": {"id": "environment", "name": "Environmental Sustainability", "color_hex": "#a6f4a1"},
        "theme": {"id": "resource_efficiency", "name": "Resource Efficiency"},
        "action": {"id": "energy_efficiency", "name": "Energy Efficiency"},
        "narrative_register": "design_spec",
        "prompt_template": "{setting}; green civic spaces reorganized around {focus_b}; verdant tones, naturalistic lighting, no readable text.",
    },
    {
        "panel_index": 6,
        "sector": {"id": "environment", "name": "Environmental Sustainability", "color_hex": "#a6f4a1"},
        "theme": {"id": "nature_tech_harmony", "name": "Nature & Tech Harmony"},
        "action": {"id": "water_conservation", "name": "Water Conservation"},
        "narrative_register": "recollection",
        "prompt_template": "{setting}; a reflective aftermath of {anchor} shaped by {tension}; serene early evening, verdant palette, memory-like framing, no readable text.",
    },
]

_PANEL_SPECS_V2: List[Dict[str, Any]] = [
    {
        "panel_role": "hero",
        "sector": {"id": "governance", "name": "Governance", "color_hex": "#8ad0ff"},
        "theme": {"id": "transparent_rule", "name": "Transparent Rule"},
        "action": {"id": "survey", "name": "Survey"},
        "narrative_register": "civic_diary",
        "prompt_template": "{setting}; communal gathering place near {anchor}; woven decision-cloth hung in the open, indigo-blue accents, people in deliberation, naturalistic lighting, no readable text.",
    },
    {
        "panel_role": "support",
        "sector": {"id": "social_equity", "name": "Social Equity & Justice", "color_hex": "#ffd27a"},
        "theme": {"id": "mutual_aid", "name": "Mutual Aid"},
        "action": {"id": "care", "name": "Care"},
        "narrative_register": "neighborhood_notice",
        "prompt_template": "{setting}; mutual aid and repair culture responding to {challenge}; warm amber palette, hands working together, shared tools, no readable text.",
    },
    {
        "panel_role": "detail",
        "sector": {"id": "environment", "name": "Environmental Sustainability", "color_hex": "#a6f4a1"},
        "theme": {"id": "resource_efficiency", "name": "Resource Efficiency"},
        "action": {"id": "restore", "name": "Restore"},
        "narrative_register": "design_spec",
        "prompt_template": "{setting}; cultivated terraces and water-management channels near {focus_b}; verdant tones, embedded craft detail, naturalistic lighting, no readable text.",
    },
    {
        "panel_role": "support",
        "sector": {"id": "governance", "name": "Governance", "color_hex": "#8ad0ff"},
        "theme": {"id": "open_data", "name": "Open Data"},
        "action": {"id": "map", "name": "Map"},
        "narrative_register": "field_report",
        "prompt_template": "{setting}; terrain survey and wayfinding markers around {focus_a}; documentary framing, indigo-blue accents, layered material traces, no readable text.",
    },
    {
        "panel_role": "bridge",
        "sector": {"id": "social_equity", "name": "Social Equity & Justice", "color_hex": "#ffd27a"},
        "theme": {"id": "deliberation", "name": "Deliberation"},
        "action": {"id": "convene", "name": "Convene"},
        "narrative_register": "manifesto",
        "prompt_template": "{setting}; circular gathering under shade canopy near {anchor}; warm amber tones, collective presence, woven textile backdrop, no readable text.",
    },
    {
        "panel_role": "closure",
        "sector": {"id": "environment", "name": "Environmental Sustainability", "color_hex": "#a6f4a1"},
        "theme": {"id": "nature_tech_harmony", "name": "Nature & Tech Harmony"},
        "action": {"id": "reflect", "name": "Reflect"},
        "narrative_register": "recollection",
        "prompt_template": "{setting}; reflective aftermath of {anchor} shaped by {tension}; serene evening, verdant palette with woven lattice, memory-like framing, no readable text.",
    },
    {
        "panel_role": "bridge",
        "sector": {"id": "governance", "name": "Governance", "color_hex": "#8ad0ff"},
        "theme": {"id": "inclusive_leadership", "name": "Inclusive Leadership"},
        "action": {"id": "debate", "name": "Debate"},
        "narrative_register": "manifesto",
        "prompt_template": "{setting}; open-air forum with layered textile enclosure near {anchor} and {focus_a}; bold composition, cool blue highlights, human figures in dialogue, no readable text.",
    },
    {
        "panel_role": "support",
        "sector": {"id": "social_equity", "name": "Social Equity & Justice", "color_hex": "#ffd27a"},
        "theme": {"id": "coordination", "name": "Coordination"},
        "action": {"id": "organize", "name": "Organize"},
        "narrative_register": "field_report",
        "prompt_template": "{setting}; workshop cluster with shared resources near {focus_a} responding to {challenge}; clear amber warmth, cooperative activity, no readable text.",
    },
    {
        "panel_role": "detail",
        "sector": {"id": "environment", "name": "Environmental Sustainability", "color_hex": "#a6f4a1"},
        "theme": {"id": "sensing", "name": "Sensing"},
        "action": {"id": "measure", "name": "Measure"},
        "narrative_register": "design_spec",
        "prompt_template": "{setting}; landscape with embedded natural growth near {focus_b}; open terrain, handmade material structures, natural daylight, no readable text.",
    },
    {
        "panel_role": "closure",
        "sector": {"id": "governance", "name": "Governance", "color_hex": "#8ad0ff"},
        "theme": {"id": "continuity", "name": "Continuity"},
        "action": {"id": "stabilize", "name": "Stabilize"},
        "narrative_register": "recollection",
        "prompt_template": "{setting}; reflective vista after {anchor}; quiet blue-washed surfaces, traces of communal use, memory-like framing, no readable text.",
    },
    {
        "panel_role": "support",
        "sector": {"id": "social_equity", "name": "Social Equity & Justice", "color_hex": "#ffd27a"},
        "theme": {"id": "access", "name": "Access"},
        "action": {"id": "open", "name": "Open"},
        "narrative_register": "neighborhood_notice",
        "prompt_template": "{setting}; thresholds and passageways opening toward shared ground near {focus_a}; warm gold accents, diverse silhouettes, no readable text.",
    },
    {
        "panel_role": "detail",
        "sector": {"id": "environment", "name": "Environmental Sustainability", "color_hex": "#a6f4a1"},
        "theme": {"id": "regeneration", "name": "Regeneration"},
        "action": {"id": "cultivate", "name": "Cultivate"},
        "narrative_register": "civic_diary",
        "prompt_template": "{setting}; regeneration corridors and rooftop garden ecologies responding to {challenge}; calm atmosphere, woven structures, naturalistic lighting, no readable text.",
    },
]


def _dedupe_strs(values: List[str]) -> List[str]:
    seen = set()
    out: List[str] = []
    for value in values:
        text = str(value or "").strip()
        if not text or text in seen:
            continue
        seen.add(text)
        out.append(text)
    return out


def _scenario_context_dict(scenario_context: Dict[str, Any] | None) -> Dict[str, Any]:
    ctx = scenario_context or {}
    turn_ctx = ctx.get("turn_context", {}) if isinstance(ctx.get("turn_context"), dict) else {}
    recent_story_log = ctx.get("recent_story_log", []) if isinstance(ctx.get("recent_story_log"), list) else []
    return {
        "name": str(ctx.get("name", "")).strip(),
        "location_and_setting": str(ctx.get("location_and_setting", ctx.get("description", ""))).strip(),
        "objective": str(ctx.get("objective", "")).strip(),
        "current_turn": int(ctx.get("current_turn", 0) or 0),
        "narrative_phase": str(ctx.get("narrative_phase", "")).strip(),
        "suggested_narrative_phase": str(ctx.get("suggested_narrative_phase", "")).strip(),
        "turn_context": {str(k): str(v).strip() for k, v in turn_ctx.items() if str(v).strip()},
        "recent_story_log": [str(v).strip() for v in recent_story_log if str(v).strip()],
    }


def _clean_phrase(text: str) -> str:
    return " ".join(str(text or "").replace("\n", " ").split()).strip(" .;,-")


def _first_nonempty(*values: str) -> str:
    for value in values:
        text = _clean_phrase(value)
        if text:
            return text
    return ""


def _turn_context(ctx: Dict[str, Any]) -> Dict[str, str]:
    turn_ctx = ctx.get("turn_context", {}) if isinstance(ctx.get("turn_context"), dict) else {}
    return {str(k): _clean_phrase(v) for k, v in turn_ctx.items() if _clean_phrase(v)}


def _setting_phrase(ctx: Dict[str, Any], focus_summary: str) -> str:
    turn_ctx = _turn_context(ctx)
    province = turn_ctx.get("province_or_site", "")
    region = turn_ctx.get("tapestry_region_primary", "")
    if province and region:
        return _truncate_words(f"{province} in {region}", 8)
    if province:
        return _truncate_words(province, 6)
    if region:
        return _truncate_words(region, 6)
    location = _clean_phrase(str(ctx.get("location_and_setting", "") or ""))
    if location:
        return _truncate_words(_first_sentence(location), 10)
    if focus_summary:
        return _truncate_words(focus_summary, 8)
    return "a civic setting"


def _story_arc_tag(continuity_state: Dict[str, Any]) -> str:
    phase = str(
        ((continuity_state.get("continuity", {}) or {}).get("recommended_narrative_phase"))
        or ((continuity_state.get("state_patch", {}) or {}).get("current_narrative_phase_hint"))
        or "setup"
    ).strip().lower()
    return _ARC_TAG_BY_PHASE.get(phase, "founding_gestures")


def _deterministic_seed(*parts: Any) -> int:
    raw = "::".join(str(p) for p in parts).encode("utf-8")
    digest = hashlib.sha256(raw).hexdigest()
    return 10000 + (int(digest[:8], 16) % 900000)


def _register_turn_suffix(register: str, turn_ctx: Dict[str, str], cycle_id: int, panel_index: int) -> str:
    if not turn_ctx:
        return ""
    province = turn_ctx.get("province_or_site", "")
    predicament = turn_ctx.get("predicament_family", "")
    effect = turn_ctx.get("visible_world_effect", "")
    question = turn_ctx.get("next_question", "")
    risk = turn_ctx.get("failure_state_risk", "")
    potential = turn_ctx.get("flourishing_state_potential", "")
    operation = turn_ctx.get("diviner_operation_cue", "")
    omen = turn_ctx.get("echo_omen_cue", "")
    resonance = turn_ctx.get("resonance", "")
    odu = turn_ctx.get("odu_name", "")
    turn_label = turn_ctx.get("window_label", "")

    if register == "civic_diary":
        return _first_nonempty(effect, turn_label, province)
    if register == "field_report":
        return _first_nonempty(f"{province} under {predicament}" if province and predicament else "", effect, odu)
    if register == "manifesto":
        return _first_nonempty(operation, question, f"turn {cycle_id} panel {panel_index}")
    if register == "neighborhood_notice":
        return _first_nonempty(risk, potential, effect)
    if register == "design_spec":
        return _first_nonempty(
            f"resonance {resonance}" if resonance else "",
            turn_ctx.get("world_domain_focus", ""),
            turn_ctx.get("tapestry_region_secondary", ""),
        )
    if register == "recollection":
        return _first_nonempty(omen, question, potential)
    return _first_nonempty(effect, question, risk)


def _first_sentence(text: str) -> str:
    raw = str(text or "").strip()
    if not raw:
        return ""
    for sep in [". ", "; ", "! ", "? "]:
        if sep in raw:
            return raw.split(sep, 1)[0].strip(" .;!?")
    return raw.strip(" .;!?")


def _truncate_words(text: str, max_words: int = 18) -> str:
    words = [w for w in str(text or "").split() if w]
    if len(words) <= max_words:
        return " ".join(words)
    return " ".join(words[:max_words])


def _backdrop_phrase(ctx: Dict[str, Any], focus_summary: str, turn_ctx: Dict[str, str] | None = None) -> str:
    turn_ctx = turn_ctx or {}
    province = _clean_phrase(turn_ctx.get("province_or_site", ""))
    region = _clean_phrase(turn_ctx.get("tapestry_region_primary", ""))
    domain = _clean_phrase(turn_ctx.get("world_domain_focus", ""))
    if province and region:
        return _truncate_words(f"{province} in {region}", 12)
    if province:
        return _truncate_words(province, 10)
    if region:
        return _truncate_words(region, 10)
    if domain:
        return _truncate_words(f"{domain} civic domain", 10)
    location = _clean_phrase(_first_sentence(str(ctx.get("location_and_setting", "") or "")))
    if location:
        return _truncate_words(location, 16)
    if focus_summary:
        return _truncate_words(focus_summary, 14)
    return "symbolic civic-tapestry setting"


def _sector_visual_phrase(spec: Dict[str, Any]) -> str:
    sector = spec.get("sector", {}) if isinstance(spec.get("sector"), dict) else {}
    sector_id = str(sector.get("id", "")).strip().lower()
    if sector_id == "governance":
        return "cool blue tones"
    if sector_id == "social_equity":
        return "warm amber tones"
    if sector_id == "environment":
        return "verdant green tones"
    return "rich natural tones"


def _register_style_phrase(register: str) -> str:
    if register == "civic_diary":
        return "observational documentary framing"
    if register == "field_report":
        return "candid reportage framing"
    if register == "manifesto":
        return "collective staging, bold composition"
    if register == "neighborhood_notice":
        return "street-level intimacy, candid human presence"
    if register == "design_spec":
        return "measured compositional framing"
    if register == "recollection":
        return "reflective aftermath, quiet atmosphere"
    return "clear narrative framing"


def _role_composition_phrase(panel_role: str, cycle_band: int = 1) -> str:
    role = str(panel_role or "").strip().lower()
    if role == "hero":
        return "wide establishing view"
    if role == "bridge":
        return "mid-to-wide view with assembly or confrontation"
    if role == "detail":
        return "closer framing on textures and surfaces"
    if role == "closure":
        return "composed aftermath view"
    phrase = "supporting scene with distinct evidence"
    if cycle_band > 1:
        phrase += f", variation {cycle_band}"
    return phrase


def _panel_subject_phrase(
    spec: Dict[str, Any],
    *,
    anchor: str,
    challenge: str,
    tension: str,
    focus_a: str,
    focus_b: str,
) -> str:
    register = str(spec.get("narrative_register", "")).strip().lower()
    action = _clean_phrase(((spec.get("action", {}) or {}).get("name")) if isinstance(spec.get("action"), dict) else "")
    theme = _clean_phrase(((spec.get("theme", {}) or {}).get("name")) if isinstance(spec.get("theme"), dict) else "")
    if register == "civic_diary":
        return _first_nonempty(
            f"public life around {anchor}, with {action.lower()} making {theme.lower()} visible" if action and theme else "",
            f"public life around {anchor}",
        )
    if register == "field_report":
        return _first_nonempty(
            f"maps, ledgers, interfaces, and civic traces around {focus_a}",
            f"evidence surfaces around {anchor}",
        )
    if register == "manifesto":
        return _first_nonempty(
            f"assembly and public debate around {anchor}, focused through {action.lower()} and {theme.lower()}" if action and theme else "",
            f"assembly and public debate around {anchor}",
        )
    if register == "neighborhood_notice":
        return _first_nonempty(
            f"care, repair, and mutual aid responding to {challenge}",
            f"street-level response to {challenge}",
        )
    if register == "design_spec":
        action_l = action.lower() if action else ""
        theme_l = theme.lower() if theme else ""
        if "sens" in theme_l or "measure" in action_l:
            return _first_nonempty(
                f"landscape with embedded natural indicators near {focus_b}",
                f"terrain shaped by {anchor}",
            )
        if "regenerat" in theme_l or "cultivat" in action_l:
            return _first_nonempty(
                f"green corridors and rooftop gardens near {focus_b}",
                f"verdant spaces recovering near {anchor}",
            )
        if "resource" in theme_l or "restor" in action_l:
            return _first_nonempty(
                f"repurposed civic grounds and green infrastructure around {focus_b}",
                f"restored commons around {anchor}",
            )
        return _first_nonempty(
            f"open terrain and natural features near {focus_b}",
            f"landscape detail near {anchor}",
        )
    if register == "recollection":
        return _first_nonempty(
            f"aftermath of {anchor}, with the memory of {tension}",
            f"aftermath of {anchor}",
        )
    return _first_nonempty(f"{action} around {anchor}", f"{theme} around {anchor}", anchor)


def _compose_panel_prompt(
    spec: Dict[str, Any],
    *,
    ctx: Dict[str, Any],
    focus_summary: str,
    anchor: str,
    challenge: str,
    tension: str,
    focus_a: str,
    focus_b: str,
    turn_ctx: Dict[str, str],
    cycle_id: int,
    panel_index: int,
    cycle_band: int = 1,
) -> str:
    panel_role = str(spec.get("panel_role", "") or spec.get("narrative_register", "")).strip().lower()
    register = str(spec.get("narrative_register", "")).strip().lower()
    parts = [
        _panel_subject_phrase(
            spec,
            anchor=anchor,
            challenge=challenge,
            tension=tension,
            focus_a=focus_a,
            focus_b=focus_b,
        ),
        _role_composition_phrase(panel_role, cycle_band),
        _register_style_phrase(register),
        _sector_visual_phrase(spec),
    ]
    parts.append("no readable text")
    cleaned = []
    seen = set()
    for part in parts:
        text = _clean_phrase(part)
        if not text:
            continue
        key = text.lower()
        if key in seen:
            continue
        seen.add(key)
        cleaned.append(text)
    return ". ".join(cleaned) + "."


def _panel_caption(
    register: str,
    anchor: str,
    challenge: str,
    tension: str,
    focus_terms: List[str],
) -> str:
    focus_text = ", ".join(focus_terms[:2]) if focus_terms else anchor
    if register == "civic_diary":
        return f"We made {anchor} visible so people could walk the consequence together."
    if register == "field_report":
        return f"Each trace around {focus_text} turned procedure into something the street could inspect."
    if register == "manifesto":
        return f"{anchor} became a public shape rather than a private instruction."
    if register == "neighborhood_notice":
        return f"The pressure of {challenge} redistributed labor into forms of care the district could keep."
    if register == "design_spec":
        return f"Infrastructure reorganized itself around {focus_text}, making efficiency legible as a social decision."
    return f"After {anchor}, even the quiet spaces held the memory of {tension}."


def _clamp_int(value: Any, default: int, min_value: int, max_value: int) -> int:
    try:
        ivalue = int(value)
    except (TypeError, ValueError):
        ivalue = default
    return max(min_value, min(ivalue, max_value))


def _normalize_selection_mode(value: Any) -> str:
    mode = str(value or "").strip().lower()
    if mode in {"first_n", "spread", "hero_only", "custom"}:
        return mode
    return "spread"


def _normalize_panel_indices(values: Any) -> List[int]:
    if not isinstance(values, list):
        return []
    out: List[int] = []
    seen = set()
    for value in values:
        try:
            ivalue = int(value)
        except (TypeError, ValueError):
            continue
        if ivalue < 1 or ivalue > 24 or ivalue in seen:
            continue
        seen.add(ivalue)
        out.append(ivalue)
    return out


def build_vis_story_cycle_payload(
    continuity_state: Dict[str, Any],
    cycle_id: int = 1,
    scenario_context: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    state = continuity_state or {}
    ctx = _scenario_context_dict(scenario_context)
    focus = state.get("scenario_focus", {}) or {}
    continuity = state.get("continuity", {}) or {}
    prompt_cues = state.get("prompt_cues", {}) or {}
    state_patch = state.get("state_patch", {}) or {}
    turn_ctx = _turn_context(ctx)
    recent_story_log = [str(v).strip() for v in (ctx.get("recent_story_log", []) or []) if str(v).strip()]

    anchors = _dedupe_strs([str(v) for v in continuity.get("anchors", []) or []])
    tensions = [t for t in (continuity.get("latent_tensions", []) or []) if isinstance(t, dict)]
    unresolved = _dedupe_strs([str(v) for v in state_patch.get("unresolved_challenges", []) or []])
    focus_terms = _dedupe_strs([str(v) for v in continuity.get("focus_terms", []) or []])

    focus_summary = str(focus.get("summary", "")).strip()
    anchor = _first_nonempty(turn_ctx.get("province_or_site", ""), turn_ctx.get("tapestry_region_primary", ""), anchors[0] if anchors else "", focus_summary, "the active continuity anchor")
    challenge = _first_nonempty(turn_ctx.get("predicament_family", ""), unresolved[0] if unresolved else "", focus_summary, "the active civic pressure")
    tension = _first_nonempty(turn_ctx.get("visible_world_effect", ""), turn_ctx.get("failure_state_risk", ""), str(tensions[0].get("summary", "")).strip() if tensions else "", challenge)
    focus_a = _first_nonempty(turn_ctx.get("tapestry_region_primary", ""), turn_ctx.get("world_domain_focus", ""), focus_terms[0] if focus_terms else "", anchor)
    focus_b = _first_nonempty(turn_ctx.get("flourishing_state_potential", ""), turn_ctx.get("tapestry_region_secondary", ""), focus_terms[1] if len(focus_terms) > 1 else "", focus_a)
    setting = _setting_phrase(ctx, focus_summary)
    story_arc_tag = _story_arc_tag(state)
    scenario_brief = _first_nonempty(turn_ctx.get("next_question", ""), str(prompt_cues.get("scenario_brief", "")).strip(), anchor)

    panels: List[Dict[str, Any]] = []
    for panel_spec in _PANELS:
        panel_index = int(panel_spec["panel_index"])
        prompt = _compose_panel_prompt(
            panel_spec,
            ctx=ctx,
            focus_summary=focus_summary,
            anchor=anchor,
            challenge=challenge,
            tension=tension,
            focus_a=focus_a,
            focus_b=focus_b,
            turn_ctx=turn_ctx,
            cycle_id=cycle_id,
            panel_index=panel_index,
            cycle_band=1,
        )
        caption = _panel_caption(
            panel_spec["narrative_register"],
            anchor,
            challenge,
            tension,
            focus_terms,
        )
        seed = _deterministic_seed(
            focus.get("document_id", ""),
            focus.get("chunk_path", ""),
            cycle_id,
            panel_index,
            panel_spec["narrative_register"],
        )
        panels.append(
            {
                "panel_index": panel_index,
                "sector": panel_spec["sector"],
                "theme": panel_spec["theme"],
                "action": panel_spec["action"],
                "narrative_register": panel_spec["narrative_register"],
                "prompt": prompt,
                "caption": caption,
                "story_state_in": {
                    "scenario_brief": scenario_brief,
                    "continuity_anchor": anchor,
                    "recommended_phase": continuity.get("recommended_narrative_phase", ""),
                    "active_seed_family": ((state.get("symbolic_signals", {}) or {}).get("active_seed_family", "")),
                    "current_turn": int(ctx.get("current_turn", cycle_id) or cycle_id),
                    "turn_site": turn_ctx.get("province_or_site", ""),
                },
                "story_state_out": {
                    "next_pressure": challenge,
                    "latent_tension": tension,
                    "focus_shift": focus_b,
                    "next_question": turn_ctx.get("next_question", ""),
                },
                "seed": seed,
                "split": "runtime",
                "source_model": "ScenSyn-StfxMemory-v1",
                "created_at": "runtime",
                "file_paths": {"image": "", "caption": ""},
                "turn_context": turn_ctx,
                "recent_story_log": recent_story_log[:3],
            }
        )

    story_json = {
        "version": "sd_phase2_v1",
        "cycles": [
            {
                "cycle_id": int(cycle_id),
                "story_arc_tag": story_arc_tag,
                "global_register_hint": "varied",
                "panels": panels,
            }
        ],
    }

    return {
        "ok": True,
        "contract_type": "scensyn.vis_story_cycle",
        "contract_version": 1,
        "source_contract": {
            "contract_type": state.get("contract_type", ""),
            "contract_version": state.get("contract_version", 0),
        },
        "scenario_context": ctx,
        "story_json": story_json,
        "provenance": state.get("provenance", {}),
    }


def build_vis_story_v2_cycle_payload(
    continuity_state: Dict[str, Any],
    cycle_id: int = 1,
    scenario_context: Dict[str, Any] | None = None,
    max_panels_per_turn: int = 12,
    panels_to_render: int = 6,
    selection_mode: str = "spread",
    panel_indices: List[int] | None = None,
    max_concurrent_renders: int = 2,
) -> Dict[str, Any]:
    state = continuity_state or {}
    ctx = _scenario_context_dict(scenario_context)
    focus = state.get("scenario_focus", {}) or {}
    continuity = state.get("continuity", {}) or {}
    prompt_cues = state.get("prompt_cues", {}) or {}
    state_patch = state.get("state_patch", {}) or {}
    turn_ctx = _turn_context(ctx)
    recent_story_log = [str(v).strip() for v in (ctx.get("recent_story_log", []) or []) if str(v).strip()]

    anchors = _dedupe_strs([str(v) for v in continuity.get("anchors", []) or []])
    tensions = [t for t in (continuity.get("latent_tensions", []) or []) if isinstance(t, dict)]
    unresolved = _dedupe_strs([str(v) for v in state_patch.get("unresolved_challenges", []) or []])
    focus_terms = _dedupe_strs([str(v) for v in continuity.get("focus_terms", []) or []])

    focus_summary = str(focus.get("summary", "")).strip()
    anchor = _first_nonempty(turn_ctx.get("province_or_site", ""), turn_ctx.get("tapestry_region_primary", ""), anchors[0] if anchors else "", focus_summary, "the active continuity anchor")
    challenge = _first_nonempty(turn_ctx.get("predicament_family", ""), unresolved[0] if unresolved else "", focus_summary, "the active civic pressure")
    tension = _first_nonempty(turn_ctx.get("visible_world_effect", ""), turn_ctx.get("failure_state_risk", ""), str(tensions[0].get("summary", "")).strip() if tensions else "", challenge)
    focus_a = _first_nonempty(turn_ctx.get("tapestry_region_primary", ""), turn_ctx.get("world_domain_focus", ""), focus_terms[0] if focus_terms else "", anchor)
    focus_b = _first_nonempty(turn_ctx.get("flourishing_state_potential", ""), turn_ctx.get("tapestry_region_secondary", ""), focus_terms[1] if len(focus_terms) > 1 else "", focus_a)
    setting = _setting_phrase(ctx, focus_summary)
    story_arc_tag = _story_arc_tag(state)
    scenario_brief = _first_nonempty(turn_ctx.get("next_question", ""), str(prompt_cues.get("scenario_brief", "")).strip(), anchor)

    resolved_max_panels = _clamp_int(max_panels_per_turn, 12, 1, 24)
    resolved_panels_to_render = _clamp_int(panels_to_render, min(6, resolved_max_panels), 1, 24)
    resolved_panels_to_render = min(resolved_panels_to_render, resolved_max_panels)
    resolved_selection_mode = _normalize_selection_mode(selection_mode)
    resolved_panel_indices = _normalize_panel_indices(panel_indices or [])
    resolved_max_concurrent = _clamp_int(max_concurrent_renders, 2, 1, 24)

    panels: List[Dict[str, Any]] = []
    template_count = len(_PANEL_SPECS_V2)
    for panel_index in range(1, resolved_max_panels + 1):
        spec = _PANEL_SPECS_V2[(panel_index - 1) % template_count]
        cycle_band = 1 + ((panel_index - 1) // template_count)
        prompt = _compose_panel_prompt(
            spec,
            ctx=ctx,
            focus_summary=focus_summary,
            anchor=anchor,
            challenge=challenge,
            tension=tension,
            focus_a=focus_a,
            focus_b=focus_b,
            turn_ctx=turn_ctx,
            cycle_id=cycle_id,
            panel_index=panel_index,
            cycle_band=cycle_band,
        )
        caption = _panel_caption(
            spec["narrative_register"],
            anchor,
            challenge,
            tension,
            focus_terms,
        )
        seed = _deterministic_seed(
            focus.get("document_id", ""),
            focus.get("chunk_path", ""),
            cycle_id,
            panel_index,
            spec["narrative_register"],
            cycle_band,
        )
        panels.append(
            {
                "panel_index": panel_index,
                "panel_role": spec["panel_role"],
                "sector": spec["sector"],
                "theme": spec["theme"],
                "action": spec["action"],
                "narrative_register": spec["narrative_register"],
                "prompt": prompt,
                "caption": caption,
                "story_state_in": {
                    "scenario_brief": scenario_brief,
                    "continuity_anchor": anchor,
                    "recommended_phase": continuity.get("recommended_narrative_phase", ""),
                    "active_seed_family": ((state.get("symbolic_signals", {}) or {}).get("active_seed_family", "")),
                    "current_turn": int(ctx.get("current_turn", cycle_id) or cycle_id),
                    "turn_site": turn_ctx.get("province_or_site", ""),
                },
                "story_state_out": {
                    "next_pressure": challenge,
                    "latent_tension": tension,
                    "focus_shift": focus_b,
                    "next_question": turn_ctx.get("next_question", ""),
                },
                "seed": seed,
                "split": "runtime",
                "source_model": "ScenSyn-StfxMemory-v2",
                "created_at": "runtime",
                "file_paths": {"image": "", "caption": ""},
                "turn_context": turn_ctx,
                "recent_story_log": recent_story_log[:3],
            }
        )

    render_plan: Dict[str, Any] = {
        "max_panels_per_turn": resolved_max_panels,
        "panels_to_render": resolved_panels_to_render,
        "selection_mode": resolved_selection_mode,
        "max_concurrent_renders": resolved_max_concurrent,
    }
    if resolved_selection_mode == "custom":
        render_plan["panel_indices"] = resolved_panel_indices[:resolved_panels_to_render]

    story_json = {
        "version": "sd_phase3_v1",
        "cycles": [
            {
                "cycle_id": int(cycle_id),
                "story_arc_tag": story_arc_tag,
                "global_register_hint": "varied",
                "render_plan": render_plan,
                "panels": panels,
            }
        ],
    }

    return {
        "ok": True,
        "contract_type": "scensyn.vis_story_v2_cycle",
        "contract_version": 1,
        "source_contract": {
            "contract_type": state.get("contract_type", ""),
            "contract_version": state.get("contract_version", 0),
        },
        "scenario_context": ctx,
        "story_json": story_json,
        "provenance": state.get("provenance", {}),
    }
