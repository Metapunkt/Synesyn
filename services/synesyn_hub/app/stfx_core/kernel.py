"""
stfx_core.kernel
================

Canonical, single-source-of-truth implementation of the STFX (Seed-to-Field
Expansion) closure algebra for the Synesyn Hub. This is the shared kernel that
StfxMemory, the SynAxes closure service, and the visual conditioning nodes all
build on, so that a given seed yields provably consistent structure across
memory and image generation.

Two strictly separated layers:

1. KERNEL (culture-neutral). Seeds are arbitrary binary matrices; the operators
   are pure mathematics with no hardcoded cultural content. The operator
   semantics are:
       * EXPANSION  (Boolean Tensor Product)  -> proxistance / scale
       * COMPLEMENT (twinning / Ìbejì)         -> decentering
       * COLLAPSE   (row indexing)             -> measurement / manifestation

2. LEXICON (pluggable binding). A ``Lexicon`` maps domain/cultural symbols onto
   bit signatures. ``IFA_ODU`` is provided as one binding; others can be added
   without touching the kernel.

The low-level functions ``boolean_tensor_product``, ``expand_seed_matrix``,
``complementarity_report`` and ``matrix_to_payload`` are kept byte-for-byte
behaviour-identical to the original engine (the accumulator is the OUTER
operand of the Boolean Tensor Product), so that existing persisted documents,
expansions and provenance remain reproducible.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass, field as dc_field
from typing import Any, Dict, List, Optional, Sequence, Tuple

import numpy as np


# ===========================================================================
# LAYER 1 -- KERNEL (culture-neutral)
# ===========================================================================

# --- Low-level operators (behaviour-identical to legacy engine) -------------

def boolean_tensor_product(matrix: np.ndarray, seed: np.ndarray) -> np.ndarray:
    """Boolean tensor product (canonical STFX operator).

    For each cell of ``matrix`` (the OUTER operand): place ``seed`` where the
    cell is 1 and the complement ``(1 - seed)`` where the cell is 0. This is the
    twinning-preserving variant of the Kronecker product (NOT the multiplicative
    ``np.kron``). Orientation is preserved from the original engine: the
    accumulator/parent is the outer operand.
    """
    h, w = matrix.shape
    sh, sw = seed.shape
    new_matrix = np.zeros((h * sh, w * sw), dtype=int)
    for i in range(h):
        for j in range(w):
            block = seed if matrix[i, j] == 1 else (1 - seed)
            new_matrix[i * sh:(i + 1) * sh, j * sw:(j + 1) * sw] = block
    return new_matrix


def expand_seed_matrix(seed_matrix: List[List[int]], depth: int) -> np.ndarray:
    """Recursively apply the Boolean Tensor Product ``depth`` times.

    ``depth`` is the SCALE / TimeLens parameter. Side length grows as
    ``seed_side ** (depth + 1)``.
    """
    if int(depth) < 0:
        raise ValueError("depth must be >= 0")
    seed = np.array(seed_matrix, dtype=int)
    matrix = seed.copy()
    for _ in range(int(depth)):
        matrix = boolean_tensor_product(matrix, seed)
    return matrix


def complementarity_report(matrix: np.ndarray) -> Dict[str, Any]:
    """Per-row complement (Ìbejì) statistics over the unique rows."""
    rows = {tuple(int(v) for v in row.tolist()) for row in matrix}
    pairs = 0
    seen: set[tuple[int, ...]] = set()
    for row in rows:
        if row in seen:
            continue
        comp = tuple(1 - v for v in row)
        if comp in rows:
            pairs += 1
            seen.add(row)
            seen.add(comp)
    return {
        "complementarity_verified": pairs > 0,
        "unique_rows": len(rows),
        "complementary_pairs": pairs,
    }


def matrix_to_payload(matrix: np.ndarray) -> Dict[str, Any]:
    """Serialisable payload for a generated field (matrix + complementarity meta)."""
    report = complementarity_report(matrix)
    return {
        "matrix_shape": [int(matrix.shape[0]), int(matrix.shape[1])],
        "matrix": matrix.astype(int).tolist(),
        "meta": report,
    }


def complement(block: np.ndarray) -> np.ndarray:
    """COMPLEMENT operator (twinning) -> decentering."""
    return 1 - block


# --- The SEED: an abstract symbolic coordinate ------------------------------

@dataclass(frozen=True)
class Seed:
    """A seed = a small square binary matrix + optional opaque row labels.

    The bridge object between Latent Reality (a symbolic coordinate) and Latent
    Space (a binary vector). The kernel attaches no meaning to ``labels`` --
    meaning is supplied by a ``Lexicon``.
    """

    matrix: Tuple[Tuple[int, ...], ...]
    labels: Tuple[str, ...] = ()

    @classmethod
    def from_array(cls, arr: np.ndarray, labels: Sequence[str] = ()) -> "Seed":
        return cls(matrix=tuple(tuple(int(v) for v in row) for row in arr),
                   labels=tuple(labels))

    @classmethod
    def from_signatures(cls, rows: Sequence[Sequence[int]],
                        labels: Sequence[str] = ()) -> "Seed":
        return cls(matrix=tuple(tuple(int(v) for v in r) for r in rows),
                   labels=tuple(labels))

    def as_list(self) -> List[List[int]]:
        return [list(row) for row in self.matrix]

    def as_array(self) -> np.ndarray:
        return np.array(self.matrix, dtype=int)

    @property
    def size(self) -> int:
        return self.as_array().shape[0]

    @property
    def density(self) -> float:
        a = self.as_array()
        return float(a.sum()) / a.size

    def fingerprint(self) -> str:
        a = self.as_array()
        return hashlib.sha256(a.tobytes() + str(a.shape).encode()).hexdigest()[:12]

    def label(self) -> str:
        return "+".join(self.labels) if self.labels else f"seed{self.fingerprint()}"


# --- Provenance -------------------------------------------------------------

@dataclass(frozen=True)
class ClosureRecord:
    """A complete, reproducible record of one latent -> manifest collapse.

    (seed + depth + index) fully determines the manifested pattern. Maps onto
    the Hub's ``substrate/provenance`` mandate.
    """

    seed_label: str
    seed_fingerprint: str
    depth: int
    index: int
    pattern_hash: str
    pattern_density: float

    def as_provenance(self) -> Dict[str, Any]:
        """Shape suitable for embedding in a substrate artifact's provenance."""
        return {
            "engine": "stfx_core",
            "seed_label": self.seed_label,
            "seed_fingerprint": self.seed_fingerprint,
            "depth": self.depth,
            "index": self.index,
            "pattern_hash": self.pattern_hash,
            "pattern_density": self.pattern_density,
        }

    def recipe(self) -> str:
        return (f"{self.seed_label}@d{self.depth}#row{self.index} "
                f"(seed={self.seed_fingerprint}, out={self.pattern_hash}, "
                f"rho={self.pattern_density:.4f})")


# --- The CDCPState: a named, reversible bundle of closure operations --------

@dataclass
class CDCPState:
    """STFX as a reference implementation of the CDCP-state formalism.

        Projection   -> reshape + render/extraction map
        Scale        -> depth (Boolean-Tensor LOD / proxistance)
        TimeLens     -> depth read as a generation/semantic-evolution index
        Neighbourhood-> Hamming / complement (twin) relations between rows
        Uncertainty  -> pre-collapse field (superposition) vs collapsed row
        Narrative    -> traversal order over rows/seeds
        Interaction  -> seed editing + index selection
        Provenance   -> ClosureRecord (seed + depth + index)

    ``field()`` delegates to ``expand_seed_matrix`` so row ordering (and hence
    collapse indices) match the canonical matrix used by StfxMemory.
    """

    seed: Seed
    depth: int = 3
    traversal: str = "sequential"
    _cache: dict = dc_field(default_factory=dict, repr=False, compare=False)

    def field(self) -> np.ndarray:
        key = ("field", self.depth)
        if key not in self._cache:
            self._cache[key] = expand_seed_matrix(self.seed.as_list(), self.depth)
        return self._cache[key]

    @property
    def side(self) -> int:
        return self.field().shape[0]

    def collapse(self, index: int) -> Tuple[np.ndarray, ClosureRecord]:
        f = self.field()
        index %= f.shape[0]
        row = f[index].copy()
        record = ClosureRecord(
            seed_label=self.seed.label(),
            seed_fingerprint=self.seed.fingerprint(),
            depth=self.depth,
            index=index,
            pattern_hash=hashlib.sha256(row.tobytes()).hexdigest()[:12],
            pattern_density=float(row.mean()),
        )
        return row, record

    def twin_index(self, index: int) -> Optional[int]:
        f = self.field()
        target = complement(f[index % f.shape[0]])
        matches = np.where((f == target).all(axis=1))[0]
        return int(matches[0]) if matches.size else None

    def neighbourhood(self, index: int, radius: int) -> List[int]:
        f = self.field()
        dists = (f != f[index % f.shape[0]]).sum(axis=1)
        return sorted(int(i) for i in np.where(dists <= radius)[0])

    def at_depth(self, new_depth: int) -> "CDCPState":
        return CDCPState(seed=self.seed, depth=new_depth, traversal=self.traversal)

    def stats(self) -> Dict[str, Any]:
        f = self.field()
        report = complementarity_report(f)
        return {
            "side": int(f.shape[0]),
            "total": int(f.size),
            "density": float(f.mean()),
            "unique_rows": int(report["unique_rows"]),
            "complementary_pairs": int(report["complementary_pairs"]),
        }

    def verify_theorems(self) -> Dict[str, Any]:
        f = self.field()
        seed_side = self.seed.size
        t3 = f.shape[0] == seed_side ** (self.depth + 1)
        rowset = {tuple(int(v) for v in r) for r in np.unique(f, axis=0)}
        covered = sum(1 for r in rowset if tuple(1 - v for v in r) in rowset)
        t2 = covered / len(rowset) if rowset else 1.0
        return {
            "theorem2_twin_coverage": round(float(t2), 4),
            "theorem3_scaling": bool(t3),
        }

    def payload(self) -> Dict[str, Any]:
        """Canonical serialisable payload (matrix + complementarity meta)."""
        return matrix_to_payload(self.field())


# ===========================================================================
# LAYER 2 -- LEXICON (pluggable binding). The ONLY place cultural content lives.
# ===========================================================================

@dataclass(frozen=True)
class Lexicon:
    """Maps domain/cultural symbols onto bit signatures and named seed families."""

    name: str
    signatures: Dict[str, Tuple[int, ...]]
    families: Dict[str, List[str]]
    notes: str = ""

    def seed(self, family: str) -> Seed:
        symbols = self.families[family]
        rows = [self.signatures[s] for s in symbols]
        return Seed.from_signatures(rows, labels=symbols)

    def seed_from_symbols(self, symbols: Sequence[str]) -> Seed:
        rows = [self.signatures[s] for s in symbols]
        return Seed.from_signatures(rows, labels=list(symbols))


# Ifá/Odù reference lexicon. Signatures and families are kept consistent with
# the production ``stfx_memory.seed_registry`` so the two never drift.
IFA_ODU = Lexicon(
    name="ifa_odu",
    signatures={
        "Ogbe": (0, 0, 0, 0), "Oyeku": (1, 1, 1, 1),
        "Iwori": (1, 0, 0, 1), "Odi": (0, 1, 1, 0),
        "Irosun": (0, 0, 1, 1), "Owonrin": (1, 1, 0, 0),
        "Obara": (0, 1, 1, 1), "Okanran": (1, 1, 1, 0),
        "Ogunda": (0, 0, 0, 1), "Osa": (1, 0, 0, 0),
        "Ika": (1, 1, 0, 1), "Oturupon": (1, 0, 1, 1),
        "Otura": (0, 1, 0, 0), "Irete": (0, 0, 1, 0),
        "Ose": (0, 1, 0, 1), "Ofun": (1, 0, 1, 0),
    },
    families={
        "primary":      ["Ogbe", "Oyeku", "Iwori", "Odi"],
        "transitional": ["Irosun", "Owonrin", "Obara", "Okanran"],
        "rhythmic":     ["Ogunda", "Osa", "Ika", "Oturupon"],
        "alternating":  ["Otura", "Irete", "Ose", "Ofun"],
    },
    notes="Longe (1998) 4-bit Odu codings; one binding among many possible.",
)


# ===========================================================================
# Self-test (known-answer against STFX seed-family invariants).
# ===========================================================================

if __name__ == "__main__":
    expected = {
        "primary":      (0.5000, 32, 16),
        "transitional": (0.5020, 146, 65),
        "alternating":  (0.5020, 146, 65),
    }
    print("stfx_core.kernel self-test:")
    all_ok = True
    for fam, (ed, eu, ep) in expected.items():
        st = CDCPState(seed=IFA_ODU.seed(fam), depth=3)
        s = st.stats()
        ok = (abs(s["density"] - ed) < 5e-4
              and s["unique_rows"] == eu
              and s["complementary_pairs"] == ep)
        all_ok = all_ok and ok
        print(f"  {fam:13s} density={s['density']:.4f} unique={s['unique_rows']:<4d} "
              f"pairs={s['complementary_pairs']:<4d} {'OK' if ok else 'MISMATCH'}")
    print("ALL OK" if all_ok else "FAILURES PRESENT")
