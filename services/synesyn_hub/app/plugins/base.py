from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict


@dataclass
class PluginLoadResult:
	name: str
	ok: bool
	error: str = ""
	capabilities: Dict[str, Any] = field(default_factory=dict)


