@tool
extends Resource
class_name AgentDefinition

# Defines agent capabilities, required tools, decision logic config. 

## Defines the configuration and capabilities of a type of Synesyn Agent.

## AgentDefinition schema version. v1 introduces Synterfaces/Bindings metadata used by Metapunkt provisioning.
## Keep this as a simple string for forwards/backwards compatibility in .tres files.
@export var schema_version: String = "metapunkt.agentdef.v1"

## Unique identifier for this agent instance
@export var agent_id: String = ""

## Agent's display name for identification and logging  
@export var agent_name: String = ""

## Agent's persona/personality description for roleplay consistency
@export_multiline var persona: String = ""

## Agent's role definition - affects behavior and tool permissions
@export var role: String = ""

## The type of decision logic this agent uses.
## Must match a key in DecisionLogicManager.RUNNER_SCRIPTS (e.g., "behaviortree", "fsm", "policy", "pinebt").
@export var logic_type: String = "behaviortree"

## Configuration specific to the chosen logic_type.
## Examples:
## - For "behaviortree": { "path": "res://path/to/tree.tres" }
## - For "policy" (API): { "api_endpoint": "http://...", "model_id": "..." }
## - For "policy" (ONNX): { "model_path": "res://path/to/model.onnx" }
@export var logic_config: Dictionary = {}

## Synterfaces/Bindings (v1):
## - required_synterfaces: the synterfaces this agent requires from the application host (autoload `MetapunktAppHost`).
## - synterface_defaults: optional defaults for synterfaces (e.g., default scope values, runner hints).
## - binding_hints: optional non-binding hints for the host (e.g., preferred group names).
## NOTE: Use Array (not Array[String]) for resource file compatibility.
@export var required_synterfaces: Array = []
@export var synterface_defaults: Dictionary = {}
@export var binding_hints: Dictionary = {}

## List of tool names (matching ToolRegistry) required by this agent.
## TODO: Use this for validation or restricting available tools.
## Changed from Array[String] to Array for resource file compatibility
@export var required_tools: Array = []

## General capabilities or metadata about the agent.
## Example: { "role": "explorer", "movement_speed": 5.0 }
@export var capabilities: Dictionary = {}

## Optional description for editor/debugging.
@export var description: String = "" 