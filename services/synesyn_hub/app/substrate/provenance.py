from __future__ import annotations

from typing import Any, Dict


RAW_ARTIFACT_TYPES = {
	"audio.input",
	"image.input",
	"video.input",
	"text.input",
}


def require_artifact_provenance(artifact_type: str) -> bool:
	# Anything not explicitly "raw input" must carry provenance metadata.
	return artifact_type not in RAW_ARTIFACT_TYPES


def validate_artifact_metadata(artifact_type: str, metadata: Dict[str, Any]) -> None:
	"""
	v0 enforcement: derived artifacts MUST include metadata.provenance with at least:
	- generated_by: str (capability/endpoint/job id, e.g. "voice.speak")
	Optional but recommended:
	- inputs: list[...] (artifact ids / hashes)
	- session_id: str
	"""
	if not require_artifact_provenance(artifact_type):
		return

	prov = (metadata or {}).get("provenance")
	if not isinstance(prov, dict):
		raise ValueError("artifact metadata.provenance must be an object for derived artifacts")
	gb = prov.get("generated_by")
	if not isinstance(gb, str) or not gb.strip():
		raise ValueError("artifact metadata.provenance.generated_by is required for derived artifacts")

