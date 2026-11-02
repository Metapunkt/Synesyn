from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class AcceleratorConfig:
	lexical: bool = True
	symbolic: bool = True
	relation: bool = True
	vector: bool = False
	sqlite: bool = False

	@classmethod
	def canonical_v0(cls) -> "AcceleratorConfig":
		return cls(lexical=True, symbolic=True, relation=True, vector=False, sqlite=False)
