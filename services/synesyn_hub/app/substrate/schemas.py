from __future__ import annotations

from typing import Any, Dict, Optional

from pydantic import BaseModel, Field
import base64


class SessionCreate(BaseModel):
	app_id: Optional[str] = None
	scenario_id: Optional[str] = None
	scenario_version: Optional[str] = None
	participants: Dict[str, Any] = Field(default_factory=dict)
	metadata: Dict[str, Any] = Field(default_factory=dict)


class SessionResponse(BaseModel):
	id: str


class EventCreate(BaseModel):
	session_id: Optional[str] = None
	event_type: str
	source_id: str
	seq: int
	t_device: Optional[float] = None
	t_received: float
	payload: Dict[str, Any] = Field(default_factory=dict)
	provenance: Dict[str, Any] = Field(default_factory=dict)


class ArtifactCreate(BaseModel):
	artifact_type: str
	# Either provide (uri + hash) for an already-stored artifact, OR provide inline_json / inline_bytes_base64 and let the hub store it.
	uri: Optional[str] = None
	hash: Optional[str] = None
	inline_json: Optional[Dict[str, Any]] = None
	inline_bytes_base64: Optional[str] = None
	ext: Optional[str] = None
	metadata: Dict[str, Any] = Field(default_factory=dict)


class EntityCreate(BaseModel):
	entity_type: str
	name: Optional[str] = None
	summary: Optional[str] = None
	tags: list[str] = Field(default_factory=list)
	metadata: Dict[str, Any] = Field(default_factory=dict)


class RelationCreate(BaseModel):
	relation_type: str
	from_entity_id: str
	to_entity_id: str
	weight: Optional[float] = None
	metadata: Dict[str, Any] = Field(default_factory=dict)


