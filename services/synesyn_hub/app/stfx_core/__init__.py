"""stfx_core: canonical closure-algebra kernel for the Synesyn Hub.

Single source of truth for the STFX (Seed-to-Field Expansion) operator and the
CDCP-state formalism. Consumed by StfxMemory (memory specialisation), the
SynAxes closure service, and the visual conditioning nodes.
"""

from .kernel import (
    # Low-level operators (behaviour-identical to the legacy engine)
    boolean_tensor_product,
    expand_seed_matrix,
    complementarity_report,
    matrix_to_payload,
    complement,
    # Rich closure-algebra API
    Seed,
    ClosureRecord,
    CDCPState,
    Lexicon,
    IFA_ODU,
)

__all__ = [
    "boolean_tensor_product",
    "expand_seed_matrix",
    "complementarity_report",
    "matrix_to_payload",
    "complement",
    "Seed",
    "ClosureRecord",
    "CDCPState",
    "Lexicon",
    "IFA_ODU",
]
