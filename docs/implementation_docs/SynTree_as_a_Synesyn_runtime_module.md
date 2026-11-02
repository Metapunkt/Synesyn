# SynTree as a Synesyn runtime module

## Purpose
SynTree started as a Godot **editor plugin** (bottom panel UI), but its **core domains** (content sources, conversation threads, hub integration) are useful in runtime apps too (e.g. ScenSyn, ReadyMade).

This document defines the v1 boundary:
- **SynTree core**: runtime-safe scripts (no EditorPlugin/editor UI dependencies)
- **SynTree editor UI**: the Godot editor panel, wiring, and UI controllers

## Core entrypoint
- `res://addons/syntree/scripts/core/syntree_core.gd` (`class_name SynTreeCore`)

Core is accessed primarily via autoloads.

## Runtime installer (optional)
If an app cannot (or does not want to) add autoloads in Project Settings, it can install core at runtime:
- `res://addons/syntree/scripts/core/syntree_runtime_installer.gd` (`class_name SynTreeRuntimeInstaller`)

```gdscript
var res := SynTreeRuntimeInstaller.ensure_core_installed()
if not res.ok:
	push_error(str(res))
```

## Required autoloads (runtime apps)
To use SynTree core in a runtime app, add these autoloads in **Project Settings → Autoload**:
- `ContentBus` → `res://addons/syntree/scripts/autoload/content_bus.gd`
- `NotificationManager` → `res://addons/syntree/scripts/utils/notification_manager.gd`

Then at runtime you can validate core availability:

```gdscript
var st := SynTreeCore.require_core()
if not st.ok:
	push_error(str(st))
```

## What is “editor UI” (not core)
These are considered editor-only / UI surface and should not be required by runtime apps:
- `res://addons/syntree/scripts/plugin.gd` (EditorPlugin autoload installer)
- `res://addons/syntree/scripts/syntree_panel.gd` and `res://addons/syntree/scenes/syntree_panel.tscn`
- `res://addons/syntree/scripts/ui/**` (panel controllers, node widgets, dialogs)

## Notes (v1 direction)
- Runtime apps should not depend on `EditorPlugin` to get core services.
- Over time, we will move/rename files so the boundary is reflected in folder structure, but v1 starts by codifying the contract (autoloads + core entrypoint).

---

## ConversationManager.chat() — full public contract

`ConversationManager` is the primary LLM call surface for all apps. Its `chat()` method signature (as of May 2026):

```gdscript
func chat(
    user_prompt: String,
    thread_name: String = "",
    model_override: String = ""
) -> Dictionary
```

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `user_prompt` | String | required | The message to send |
| `thread_name` | String | `""` | Thread id for history isolation. Empty → use the current default thread |
| `model_override` | String | `""` | If non-empty, this call uses the named model instead of the manager's current selection. The global `_current_model` state is **not** changed. Empty string preserves legacy behaviour |

**`model_override` usage rule**: only apps and agents that have scenario-specific routing needs should pass this argument. All existing callers that pass one or two arguments are unaffected; the third parameter defaults to `""`.

**`model_override` implementation path**:
`chat()` → `APIService.process_message_with_history(messages, context, model_override)` → `chat_completion(effective_model, messages, settings)` → `loader.prepare_request(messages, system_prompt, effective_model)`. Every concrete loader accepts the optional `effective_model` parameter and uses it for request body construction without mutating loader state.

**Per-call budget line (always on, no configuration needed)**:

Every `chat()` call emits one line to stdout:

```
[budget] <role-label> <size> (<model>)
```

Examples:
```
[budget] director_tactical_batch 4.8k chars (gpt-4o-mini)
[budget] actor_diviner 3.2k chars (claude-sonnet-4-6)
[budget] session_record_synth 2.1k chars (claude-sonnet-4-6)
```

- `role-label` is the meaningful part of `thread_name` with the scope prefix and trailing `_<ms>` timestamp stripped.
- Size is total chars sent (context + message history), rounded to one decimal in k.
- Model is `model_override` if set, otherwise the manager's current model.
- This line is unconditional. There is no flag to enable it and no config surface to check.


