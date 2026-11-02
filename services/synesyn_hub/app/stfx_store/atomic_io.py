from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


def write_json_atomic(path: Path, obj: Any) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	tmp = path.with_name(path.name + ".tmp")
	tmp.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")
	os.replace(tmp, path)


def read_json(path: Path) -> Any:
	return json.loads(path.read_text(encoding="utf-8"))


def write_text_atomic(path: Path, text: str) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	tmp = path.with_name(path.name + ".tmp")
	tmp.write_text(text, encoding="utf-8")
	os.replace(tmp, path)


def read_text(path: Path) -> str:
	return path.read_text(encoding="utf-8")
