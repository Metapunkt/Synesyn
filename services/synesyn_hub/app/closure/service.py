"""
closure.service
===============

SynAxes-facing closure service. A thin, stateless wrapper over the shared
``stfx_core`` kernel that exposes the closure-algebra operations as the
Hub's canonical "latent reality engine" surface:

	field()         -> the un-collapsed superposition (UNCERTAINTY)
	collapse()      -> a determinate, provenanced pattern (the manifestation event)
	twin()          -> the Ìbejì complement (NEIGHBOURHOOD / decentering)
	neighbourhood() -> Hamming neighbours

Seeds may be supplied directly (a 4x4 binary matrix) or resolved from a
pluggable lexicon (e.g. the Ifá/Odù binding). The kernel itself is
culture-neutral; lexicons live here at the binding layer.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence

from ..stfx_core import CDCPState, IFA_ODU, Lexicon, Seed


# Registry of available lexicons (bindings). Add new paradigms here without
# touching the kernel.
LEXICONS: Dict[str, Lexicon] = {IFA_ODU.name: IFA_ODU}


def resolve_seed(
	seed_matrix: Optional[Sequence[Sequence[int]]] = None,
	lexicon: str = "",
	family: str = "",
	symbols: Optional[Sequence[str]] = None,
) -> Seed:
	"""Resolve a Seed from an explicit matrix or a lexicon family/symbols."""
	if seed_matrix:
		return Seed.from_signatures(seed_matrix)
	lex = LEXICONS.get(str(lexicon or "").strip().lower())
	if lex is None:
		raise KeyError(f"unknown lexicon: {lexicon!r} (have: {sorted(LEXICONS)})")
	if symbols:
		return lex.seed_from_symbols(symbols)
	if family:
		try:
			return lex.seed(str(family).strip().lower())
		except KeyError:
			raise KeyError(f"unknown family {family!r} in lexicon {lex.name!r}")
	raise ValueError("provide seed_matrix, or lexicon+family, or lexicon+symbols")


def _seed_info(seed: Seed) -> Dict[str, Any]:
	return {
		"labels": list(seed.labels),
		"matrix": seed.as_list(),
		"fingerprint": seed.fingerprint(),
		"density": seed.density,
	}


class ClosureService:
	"""Stateless closure-algebra operations over the shared kernel."""

	def list_lexicons(self) -> Dict[str, Any]:
		return {
			"ok": True,
			"lexicons": [
				{
					"name": lex.name,
					"families": {fam: list(syms) for fam, syms in lex.families.items()},
					"symbols": sorted(lex.signatures.keys()),
					"notes": lex.notes,
				}
				for lex in LEXICONS.values()
			],
		}

	def field(self, seed: Seed, depth: int = 3) -> Dict[str, Any]:
		state = CDCPState(seed=seed, depth=int(depth))
		payload = state.payload()
		payload.update({
			"ok": True,
			"seed": _seed_info(seed),
			"depth": int(depth),
			"theorems": state.verify_theorems(),
		})
		return payload

	def collapse(self, seed: Seed, index: int, depth: int = 3) -> Dict[str, Any]:
		state = CDCPState(seed=seed, depth=int(depth))
		row, record = state.collapse(int(index))
		return {
			"ok": True,
			"seed": _seed_info(seed),
			"depth": int(depth),
			"index": record.index,
			"pattern": [int(v) for v in row.tolist()],
			"provenance": record.as_provenance(),
			"recipe": record.recipe(),
		}

	def twin(self, seed: Seed, index: int, depth: int = 3) -> Dict[str, Any]:
		state = CDCPState(seed=seed, depth=int(depth))
		twin_idx = state.twin_index(int(index))
		out: Dict[str, Any] = {
			"ok": True,
			"seed": _seed_info(seed),
			"depth": int(depth),
			"index": int(index) % state.side,
			"twin_index": twin_idx,
		}
		if twin_idx is not None:
			out["twin_pattern"] = [int(v) for v in state.field()[twin_idx].tolist()]
		return out

	def neighbourhood(self, seed: Seed, index: int, radius: int = 8,
					  depth: int = 3) -> Dict[str, Any]:
		state = CDCPState(seed=seed, depth=int(depth))
		idx = list(state.neighbourhood(int(index), int(radius)))
		return {
			"ok": True,
			"seed": _seed_info(seed),
			"depth": int(depth),
			"index": int(index) % state.side,
			"radius": int(radius),
			"neighbour_indices": idx,
			"count": len(idx),
		}

	def commit_artifact(self, seed: Seed, index: int, depth: int = 3) -> Dict[str, Any]:
		"""Build a substrate-ready artifact for a committed closure.

		Returns the artifact_type, body payload and provenance for the route to
		persist via the substrate ArtifactStore + repo.
		"""
		state = CDCPState(seed=seed, depth=int(depth))
		row, record = state.collapse(int(index))
		return {
			"artifact_type": "json.closure_commitment",
			"payload": {
				"schema_version": 1,
				"seed": _seed_info(seed),
				"depth": int(depth),
				"index": record.index,
				"pattern": [int(v) for v in row.tolist()],
				"meta": state.stats(),
			},
			"provenance": record.as_provenance(),
		}
