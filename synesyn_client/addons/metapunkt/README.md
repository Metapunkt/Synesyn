# Metapunkt - SLOP-Native AI Agent Orchestrator

Metapunkt is a sophisticated AI agent orchestration system for Godot that implements the SLOP (Simple Low-Overhead Protocol) for managing AI agents with different roles, capabilities, and decision-making systems.

## Features

- **Multi-Agent Orchestration**: Run multiple AI agents with different roles simultaneously
- **SLOP Protocol**: HTTP-based communication for external agent interaction
- **LimboAI Integration**: Behavior trees and state machines for agent decision logic
- **Tool Integration**: Modular tool system including SynTree AI assistant integration
- **Role-Based Permissions**: Agents can have specific roles with restricted capabilities
- **Persistent State**: Resource-based configuration and state management

## Quick Start

### 1. Enable the Plugin
Enable "Metapunkt" in Project Settings → Plugins

### 2. Create an Agent Definition
```gdscript
# Create a new AgentDefinition resource
var agent_def = AgentDefinition.new()
agent_def.agent_id = "my_agent"
agent_def.agent_name = "Agent-Helper"
agent_def.persona = "A helpful assistant that focuses on development tasks"
agent_def.role = "developer"
agent_def.logic_type = "limboai"
agent_def.required_tools = ["SynTree", "GodotUtils"]
```

### 3. Register and Spawn Agent
```gdscript
# Register the agent definition
AgentRegistry.register_agent_definition(agent_def)

# Spawn an agent instance
var agent = AgentManager.spawn_agent("my_agent")
```

## Agent Roles

### Developer Agents
- **Agent-Alexander**: General development agent inspired by Christopher Alexander
- Focus on systematic thinking and pattern recognition
- Can modify code, analyze projects, use SynTree AI capabilities

### Roleplay Agents  
- **Agent-Chaplin**: Character roleplay agent inspired by Charlie Chaplin
- Focus on staying in character and providing engaging interactions
- Read-only access, cannot modify codebase

## Tool Integration

### SynTree Integration
Agents can access SynTree's AI capabilities:
```gdscript
# Chat with AI assistant
var result = await agent.use_tool("SynTree", {
    "operation": "chat",
    "message": "Help me debug this function"
})

# Analyze code content
var analysis = await agent.use_tool("SynTree", {
    "operation": "analyze_content", 
    "content": "func my_function():\n\tpass",
    "type": "code"
})
```

### Tool discovery (/tools)
Metapunkt tools expose introspection metadata used by SLOP `/tools`:
- `description`
- `operations` (supported operation/action names)
- `input_schema` / `output_schema` (JSON-schema-ish dictionaries for UI/clients)

## Architecture

- **Core/**: Agent management, orchestration, and decision logic
- **Networking/**: SLOP server for external communication
- **TaskManager/**: Asynchronous task execution system
- **Integrations/**: Tool interfaces (SynTree, GodotUtils, etc.)

## SLOP API

Metapunkt exposes a REST API for external agent interaction:

```bash
# List available agents
GET /agents

# Execute agent action
POST /agents/{agent_id}/execute
{
    "action": "use_tool",
    "tool": "SynTree",
    "args": {"operation": "chat", "message": "Hello"}
}
```

For more details, see the full documentation. 

## Hub integration

Metapunkt can forward orchestration events and artifacts to the Synesyn Hub (system-of-record) and optionally subscribe to Hub WS events (sensors/jobs).
See `res://../docs/implementation_docs/Metapunkt_Hub_Integration.md`.

## Conversational Agents Quick-Start

The Chaplin UFO demo (`addons/test_chaplin_ufo_conversation.gd`) is a fully-working template you can copy.
Below is the distilled recipe.

### 1. Create Behaviour-Tree Asset
Use LimboAI's editor to make a tree that triggers three custom tasks shipped in `addons/metapunkt/limboai_tasks/`:

| Task | Purpose |
|------|---------|
| `SimpleConversationTask` | Generate the next utterance through SynTree and write it to shared memory |
| `SetMemoryTask`          | Flip `should_speak` flags to control turn-taking |
| `CheckMemoryCondition`   | Guard-node that checks `should_speak` before speaking |

Save the tree as `res://addons/metapunkt/behavior_trees/your_conversation.tres`.

### 2. Define Agents
```gdscript
var believer_def := AgentDefinition.new()
believer_def.agent_id = "believer"
believer_def.agent_name = "UFO Enthusiast"
believer_def.persona = "An excitable stargazer convinced aliens visit Earth."
believer_def.role = "roleplay"
believer_def.logic_type = "limboai"
believer_def.logic_config = {"path": "res://addons/metapunkt/behavior_trees/your_conversation.tres"}

var skeptic_def := believer_def.duplicate()
skeptic_def.agent_id  = "skeptic"
skeptic_def.agent_name = "UFO Skeptic"
skeptic_def.persona   = "A calm scientist demanding hard evidence."  
```

### 3. Spawn Agents & Shared Memory
```gdscript
var believer  = await agent_registry.create_agent_from_definition(believer_def, "user")
var skeptic   = await agent_registry.create_agent_from_definition(skeptic_def,  "user")

# Conversation metadata
short_term_memory.set_memory("conversation_log", [], "shared")
short_term_memory.set_memory("should_speak", true,  believer.agent_id)  # believer starts
short_term_memory.set_memory("should_speak", false, skeptic.agent_id)
```

### 4. Kick-off
Just enable the agents' behaviour trees (`AgentManager` handles the tick loop). When `SimpleConversationTask` runs, it builds a prompt like:
```
Your persona: A calm scientist demanding hard evidence.

Recent conversation:
<previous messages>

Respond directly to your conversation partner …
```
The task appends the generated text to `conversation_log` and flips the `should_speak` flags—giving you automatic turn-taking.

### 5. Live Logging (UI optional)
`_process()` in the Chaplin demo shows how to stream new messages to a `RichTextLabel`. Remove the recap loop if you only want live output (already done).

---

## Service Reference Additions

| Service | Path | What it does |
|---------|------|--------------|
| **ShortTermMemory** | `addons/metapunkt/Memory` | In-memory key/value store with per-agent or shared scopes |
| **ActionDispatcher** | `addons/metapunkt/Core/ActionDispatcher` | Routes tool calls; SynTree, web requests, etc. |
| **AuditLogger** | `addons/metapunkt/Audit` | Structured JSON log of *all* agent events |

These are auto-wired by `_initialize_metapunkt()` in the demo scene; reuse that helper or copy the module-assembly code.

## Tips for Advanced Scenarios
* Spawn a **Critic** agent that reads `conversation_log` every N turns and injects feedback.
* Replace `SimpleConversationTask` with your own task that calls arbitrary REST APIs mid-sentence and feeds the result back to the LLM.
* Gate expensive model calls by wrapping tasks in `CheckMemoryCondition` nodes that sniff a "budget_remaining" variable. 