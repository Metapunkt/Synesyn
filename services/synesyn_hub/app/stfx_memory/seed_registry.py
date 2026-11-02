from __future__ import annotations

from typing import Any, Dict


DEFAULT_SEED_REGISTRY: Dict[str, Dict[str, Any]] = {
	"primary": {
		"family_id": "primary",
		"display_name": "Primary",
		"description": "Foundational contrast pairings",
		"oduu_members": ["Ogbe", "Oyeku", "Iwori", "Odi"],
		"seed_matrix": [
			[0, 0, 0, 0],
			[1, 1, 1, 1],
			[1, 0, 0, 1],
			[0, 1, 1, 0],
		],
	},
	"transitional": {
		"family_id": "transitional",
		"display_name": "Transitional",
		"description": "Threshold and emergence pairings",
		"oduu_members": ["Irosun", "Owonrin", "Obara", "Okanran"],
		"seed_matrix": [
			[0, 0, 1, 1],
			[1, 1, 0, 0],
			[0, 1, 1, 1],
			[1, 1, 1, 0],
		],
	},
	"rhythmic": {
		"family_id": "rhythmic",
		"display_name": "Rhythmic",
		"description": "Persistent, asymmetrical pulse pairings",
		"oduu_members": ["Ogunda", "Osa", "Ika", "Oturupon"],
		"seed_matrix": [
			[0, 0, 0, 1],
			[1, 0, 0, 0],
			[1, 1, 0, 1],
			[1, 0, 1, 1],
		],
	},
	"alternating": {
		"family_id": "alternating",
		"display_name": "Alternating",
		"description": "Oscillating checkerboard-adjacent pairings",
		"oduu_members": ["Otura", "Irete", "Ose", "Ofun"],
		"seed_matrix": [
			[0, 1, 0, 0],
			[0, 0, 1, 0],
			[0, 1, 0, 1],
			[1, 0, 1, 0],
		],
	},
}


def validate_seed_matrix(matrix: Any) -> None:
	if not isinstance(matrix, list) or len(matrix) != 4:
		raise ValueError("seed_matrix must be a 4x4 list")
	for row in matrix:
		if not isinstance(row, list) or len(row) != 4:
			raise ValueError("seed_matrix must be a 4x4 list")
		for val in row:
			if val not in (0, 1):
				raise ValueError("seed_matrix values must be 0 or 1")


def validate_seed_registry(registry: Dict[str, Dict[str, Any]]) -> None:
	if not isinstance(registry, dict) or not registry:
		raise ValueError("seed registry must be a non-empty object")
	for family_id, entry in registry.items():
		if not isinstance(entry, dict):
			raise ValueError(f"seed family {family_id} must be an object")
		if str(entry.get("family_id") or "").strip() != family_id:
			raise ValueError(f"seed family_id mismatch for {family_id}")
		validate_seed_matrix(entry.get("seed_matrix"))


def get_seed_matrix(registry: Dict[str, Dict[str, Any]], family_id: str) -> list[list[int]]:
	fid = str(family_id or "").strip().lower()
	entry = registry.get(fid)
	if not entry:
		raise KeyError(f"Unknown seed family: {family_id}")
	return entry["seed_matrix"]
