from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Optional, Tuple

from ..utils import new_id


class ArtifactStore:
	def __init__(self, artifacts_root: Path):
		self.root = artifacts_root

	def _hash_bytes(self, data: bytes) -> str:
		return hashlib.sha256(data).hexdigest()

	def _path_for(self, artifact_type: str, artifact_id: str, ext: str) -> Path:
		# Map artifact types to subfolders for human discoverability
		parts = artifact_type.split(".")
		top = parts[0] if parts else "misc"
		sub = parts[1] if len(parts) > 1 else "data"
		dir_path = self.root / top / sub
		dir_path.mkdir(parents=True, exist_ok=True)
		return dir_path / f"{artifact_id}.{ext.lstrip('.')}"

	def write_bytes(self, artifact_type: str, data: bytes, ext: str) -> Tuple[str, str, str]:
		artifact_id = new_id("art")
		h = self._hash_bytes(data)
		path = self._path_for(artifact_type, artifact_id, ext)
		path.write_bytes(data)
		uri = path.resolve().as_uri()
		return artifact_id, uri, h

	def write_text(self, artifact_type: str, text: str, ext: str = "txt") -> Tuple[str, str, str]:
		data = text.encode("utf-8")
		return self.write_bytes(artifact_type, data, ext)

	def write_json(self, artifact_type: str, obj, ext: str = "json") -> Tuple[str, str, str]:
		data = json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8")
		return self.write_bytes(artifact_type, data, ext)


