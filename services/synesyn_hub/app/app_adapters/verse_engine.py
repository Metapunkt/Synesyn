"""
Verse expansion engine and reading composer for Stochastic Dreams.

Loads the canonical verse corpus (JSON), selects and composes divinatory
readings from fragments based on turn data, and produces constrained
prompts for the four-voice character system.

The engine is deterministic: same inputs produce the same reading.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

_corpus_cache: Optional[Dict[str, Any]] = None


def _resolve_corpus_path() -> Path:
    """Resolve verse_corpus.json path, handling both source and PyInstaller frozen bundles."""
    candidates = [
        Path(__file__).parent / "verse_corpus.json",
    ]
    # PyInstaller frozen bundle: try the source tree relative to the Hub root
    import sys
    if getattr(sys, "frozen", False):
        base = Path(sys.executable).parent
        candidates.append(base / "_internal" / "app" / "app_adapters" / "verse_corpus.json")
        candidates.append(base / "app" / "app_adapters" / "verse_corpus.json")
    for p in candidates:
        if p.exists():
            return p
    raise FileNotFoundError(
        f"verse_corpus.json not found in any candidate path: {[str(c) for c in candidates]}"
    )


def _load_corpus() -> Dict[str, Any]:
    global _corpus_cache
    if _corpus_cache is not None:
        return _corpus_cache
    corpus_path = _resolve_corpus_path()
    with open(corpus_path, "r", encoding="utf-8") as f:
        _corpus_cache = json.load(f)
    return _corpus_cache


def _verse_by_odu(odu_name: str) -> Optional[Dict[str, Any]]:
    corpus = _load_corpus()
    name_upper = odu_name.strip().upper()
    for v in corpus["verses"]:
        if v["odu_name"].upper() == name_upper:
            return v
    return None


def _verse_by_predicament(predicament_id: str) -> Optional[Dict[str, Any]]:
    corpus = _load_corpus()
    pid = predicament_id.strip().upper()
    for v in corpus["verses"]:
        if v["predicament_id"].upper() == pid:
            return v
    return None


def _join_fragment(lines: List[str]) -> str:
    return "\n".join(lines)


def _deterministic_float(seed_str: str) -> float:
    """Hash a string to a float in [0, 1) for deterministic selection."""
    h = hashlib.sha256(seed_str.encode("utf-8")).hexdigest()
    return int(h[:8], 16) / 0xFFFFFFFF


def compose_reading(
    odu_name: str,
    resonance: float = 0.5,
    complement_odu: Optional[str] = None,
    stability: float = 0.5,
    crossings: int = 0,
    turn_seed: str = "",
) -> Dict[str, Any]:
    """
    Compose a divinatory reading from the canonical verse corpus.

    Parameters
    ----------
    odu_name : str
        Primary Odu for this turn (e.g. "OKANRAN MEJI").
    resonance : float
        Turn resonance [0, 1].  Controls reading length:
        < 0.3  -> operation + question only (short reading)
        0.3-0.7 -> operation + omen + question (medium)
        > 0.7  -> full three-layer reading
    complement_odu : str, optional
        Complementary Odu name.  If provided and stability is low,
        the omen layer may be drawn from the complement verse.
    stability : float
        Pendulum stability [0, 1].  Low stability increases the
        chance of cross-Odu fragment borrowing.
    crossings : int
        Number of sector crossings.  High crossings may extend
        the manifestation layer.
    turn_seed : str
        Seed string for deterministic variation (e.g. cycle_id + panel).

    Returns
    -------
    dict with keys:
        reading_text : str      — the full composed reading for the Diviner
        fragments_used : dict   — which Odu contributed each layer
        operation_text : str    — [A] layer text
        omen_text : str         — [B] layer text (may be empty for short readings)
        manifestation_text : str — [C] layer text (may be empty for short/medium)
        question_text : str     — [Q] layer text
        primary_verse : dict    — the primary verse metadata
        reading_length : str    — "short", "medium", or "full"
    """
    primary = _verse_by_odu(odu_name)
    if primary is None:
        return _fallback_reading(odu_name)

    complement = None
    if complement_odu:
        complement = _verse_by_odu(complement_odu)

    source_a = primary
    source_b = primary
    source_c = primary
    source_q = primary

    if complement and stability < 0.4:
        det = _deterministic_float(f"omen_cross:{turn_seed}:{odu_name}")
        if det < (0.6 - stability):
            source_b = complement

    if crossings > 6 and complement:
        det = _deterministic_float(f"manifest_cross:{turn_seed}:{odu_name}")
        if det < 0.4:
            source_c = complement

    operation_text = _join_fragment(primary["fragments"]["A"])
    omen_text = _join_fragment(source_b["fragments"]["B"])
    manifestation_text = _join_fragment(source_c["fragments"]["C"])
    question_text = _join_fragment(source_q["fragments"]["Q"])

    if resonance < 0.3:
        reading_length = "short"
        reading_text = f"{operation_text}\n\n{question_text}"
        omen_text_out = ""
        manifestation_text_out = ""
    elif resonance <= 0.7:
        reading_length = "medium"
        reading_text = f"{operation_text}\n\n{omen_text}\n\n{question_text}"
        omen_text_out = omen_text
        manifestation_text_out = ""
    else:
        reading_length = "full"
        reading_text = (
            f"{operation_text}\n\n{omen_text}\n\n"
            f"{manifestation_text}\n\n{question_text}"
        )
        omen_text_out = omen_text
        manifestation_text_out = manifestation_text

    return {
        "reading_text": reading_text,
        "fragments_used": {
            "A": primary["odu_name"],
            "B": source_b["odu_name"],
            "C": source_c["odu_name"],
            "Q": source_q["odu_name"],
        },
        "operation_text": operation_text,
        "omen_text": omen_text_out,
        "manifestation_text": manifestation_text_out,
        "question_text": question_text,
        "primary_verse": {
            "odu_name": primary["odu_name"],
            "title": primary["title"],
            "province": primary["province"],
            "region": primary["region"],
            "predicament": primary["predicament"],
            "predicament_id": primary["predicament_id"],
            "domain": primary["domain"],
            "deep_agent": primary["deep_agent"],
            "group": primary["group"],
        },
        "reading_length": reading_length,
    }


def compose_character_prompts(
    reading: Dict[str, Any],
    turn_context: Dict[str, Any],
) -> Dict[str, str]:
    """
    Produce constrained prompts for each character based on the reading.

    Parameters
    ----------
    reading : dict
        Output from compose_reading().
    turn_context : dict
        Turn packet data containing character cues from the ontology
        (seeker_manifestation_cue, echo_omen_cue, narrator_handoff_cue,
        visible_gain, hidden_cost, failure_state_risk,
        flourishing_state_potential, etc.).

    Returns
    -------
    dict with keys: diviner, seeker, echo, narrator
        Each value is the text/prompt for that character.
    """
    verse_meta = reading["primary_verse"]

    diviner_text = reading["reading_text"]

    seeker_cue = turn_context.get("seeker_manifestation_cue", "")
    visible_gain = turn_context.get("visible_gain", "")
    flourishing = turn_context.get("flourishing_state_potential", "")
    seeker_prompt = (
        f"The Diviner has read a verse about {verse_meta['predicament']} "
        f"at {verse_meta['province']}. The reading ended with: "
        f'"{reading["question_text"]}"\n\n'
        f"As the Seeker, respond in 1-2 sentences. You advocate for the "
        f"dream. What does this mean for the desired future? "
        f"Draw on: {seeker_cue} "
        f"The visible gain is: {visible_gain}. "
        f"The flourishing state is: {flourishing}. "
        f"Do not repeat the verse. Do not use colons or quotation marks."
    )

    echo_cue = turn_context.get("echo_omen_cue", "")
    failure_risk = turn_context.get("failure_state_risk", "")
    complement_odu = turn_context.get("complementary_odu", "")
    echo_prompt = (
        f"The Diviner has read a verse about {verse_meta['predicament']} "
        f"at {verse_meta['province']}. The omen layer said: "
        f'"{reading["omen_text"] or reading["operation_text"]}"\n\n'
        f"As the Echo, respond in 1-2 sentences. You speak for collective "
        f"memory and recurring patterns. What does this recall, what "
        f"warning does it carry? "
        f"Draw on: {echo_cue} "
        f"The failure risk is: {failure_risk}. "
        f"The complementary Odu is {complement_odu}. "
        f"Do not repeat the verse. Do not use colons or quotation marks."
    )

    narrator_cue = turn_context.get("narrator_handoff_cue", "")
    next_question = turn_context.get("next_question", "")
    narrator_prompt = (
        f"The Diviner has read a verse about {verse_meta['predicament']} "
        f"at {verse_meta['province']}. The Seeker and Echo have responded.\n\n"
        f"As the Narrator, compress into 1 sentence: what changed and "
        f"what is inherited by the next turn. "
        f"Draw on: {narrator_cue} "
        f"The question for the next turn is: {next_question} "
        f"Do not repeat the verse. Do not use colons or quotation marks."
    )

    return {
        "diviner": diviner_text,
        "seeker": seeker_prompt,
        "echo": echo_prompt,
        "narrator": narrator_prompt,
    }


def compose_vis_story_context(
    reading: Dict[str, Any],
    turn_context: Dict[str, Any],
) -> Dict[str, str]:
    """
    Produce context for the vis_story prompt generator, derived from
    the verse reading rather than from free-form dialogue.

    Returns a dict with keys that scensyn_vis_story.py can consume:
        narrative_text, focus_theme, setting_phrase, palette_hint, domain.
    """
    verse_meta = reading["primary_verse"]

    narrative_text = reading["reading_text"]

    focus_theme = (
        f"{verse_meta['predicament']} — "
        f"{turn_context.get('visible_gain', '')} "
        f"against {turn_context.get('hidden_cost', '')}"
    )

    setting_phrase = (
        f"{verse_meta['province']}, "
        f"{verse_meta['region']}"
    )

    palette_hint = verse_meta["region"]
    domain = verse_meta["domain"]

    return {
        "narrative_text": narrative_text,
        "focus_theme": focus_theme,
        "setting_phrase": setting_phrase,
        "palette_hint": palette_hint,
        "domain": domain,
    }


def compose_seekers_journey_prompt(
    reading: Dict[str, Any],
    turn_context: Dict[str, Any],
    previous_paragraphs: List[str],
    turn_number: int,
) -> str:
    """
    Produce a constrained LLM prompt for generating the next paragraph
    of the Seeker's Journey prose narrative.

    Parameters
    ----------
    reading : dict
        Output from compose_reading().
    turn_context : dict
        Turn packet data with ontology cues.
    previous_paragraphs : list of str
        The last 3-5 paragraphs of the Journey for context continuity.
    turn_number : int
        Sequential turn number for chapter tracking.

    Returns
    -------
    str : the system+user prompt to send to the LLM.
    """
    verse_meta = reading["primary_verse"]
    seeker_cue = turn_context.get("seeker_manifestation_cue", "")
    visible_effect = turn_context.get("visible_world_effect", "")
    flourishing = turn_context.get("flourishing_state_potential", "")
    failure = turn_context.get("failure_state_risk", "")

    context_window = "\n\n".join(previous_paragraphs[-3:]) if previous_paragraphs else ""

    prompt = (
        "You are writing The Seeker's Journey — a continuous prose narrative "
        "about a pilgrim traveling through the Tapestry, a world woven by "
        "two cosmological forces (the Map Maker and the Path Finder). "
        "The Seeker searches for a viable utopia through landscapes that "
        "embody civic predicaments.\n\n"
        "Write the next paragraph (3-5 sentences, ~60-80 words). "
        "The prose should be vivid, grounded, and imagistic — like a travel "
        "diary written by someone who pays attention to surfaces, sounds, "
        "and the faces of strangers.\n\n"
        f"TURN {turn_number}:\n"
        f"The Seeker has arrived at {verse_meta['province']} "
        f"in the {verse_meta['region']}.\n"
        f"The predicament here is: {verse_meta['predicament']}.\n"
        f"What is visible: {seeker_cue}\n"
        f"What is at stake: {visible_effect}\n"
        f"The best outcome: {flourishing}. The worst: {failure}.\n"
        f"The divination reading said:\n{reading['reading_text']}\n\n"
        "CONSTRAINTS:\n"
        "- Write in third person ('The Seeker').\n"
        "- Do not explain the predicament abstractly; show it through "
        "what the Seeker sees, hears, and feels.\n"
        "- Do not use colons, quotation marks, or bullet points.\n"
        "- End the paragraph with the Seeker still in motion — arriving, "
        "witnessing, or departing, never concluded.\n"
    )

    if context_window:
        prompt += (
            f"\nPREVIOUS PARAGRAPHS (for continuity):\n{context_window}\n\n"
            "Continue naturally from where the previous text left off.\n"
        )

    return prompt


def get_heartbeat_fragment(
    past_readings: List[Dict[str, Any]],
    seed: str = "",
) -> Optional[Dict[str, str]]:
    """
    Select a single omen fragment from a past reading for the
    heartbeat (lull-period) display.

    Returns dict with keys: omen_fragment, province, predicament,
    or None if no past readings exist.
    """
    if not past_readings:
        return None

    det = _deterministic_float(f"heartbeat:{seed}")
    idx = int(det * len(past_readings)) % len(past_readings)
    reading = past_readings[idx]

    omen = reading.get("omen_text", "")
    if not omen:
        omen = reading.get("operation_text", "")

    verse_meta = reading.get("primary_verse", {})

    return {
        "omen_fragment": omen,
        "province": verse_meta.get("province", ""),
        "predicament": verse_meta.get("predicament", ""),
    }


def _fallback_reading(odu_name: str) -> Dict[str, Any]:
    """Fallback when the requested Odu is not in the corpus."""
    return {
        "reading_text": f"The signs were cast for {odu_name}, but the verse has not yet been written.",
        "fragments_used": {"A": odu_name, "B": odu_name, "C": odu_name, "Q": odu_name},
        "operation_text": f"The signs were cast for {odu_name}, but the verse has not yet been written.",
        "omen_text": "",
        "manifestation_text": "",
        "question_text": "What will the next hand bring?",
        "primary_verse": {
            "odu_name": odu_name,
            "title": "Unknown",
            "province": "Unknown",
            "region": "Unknown",
            "predicament": "Unknown",
            "predicament_id": "PF00",
            "domain": "Unknown",
            "deep_agent": "unknown",
            "group": "Unknown",
        },
        "reading_length": "short",
    }
