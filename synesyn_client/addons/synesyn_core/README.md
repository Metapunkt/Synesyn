# Synesyn Core

Shared library addon for Synesyn product tools. **No dock, no product UI.**

See ADR 0017.

## Contents (`scripts/`)

| Area | Scripts |
|------|---------|
| Config / policy | `runtime_config.gd`, `provider_mode_policy.gd` |
| Hub client | `hub_substrate_transport.gd`, `hub_substrate_client.gd` |
| Theme | `theme_config.gd`, `theme_manager.gd`, `themes/` (+ Noto fonts) |
| Cross-app helpers | `synesyn_session.gd`, `thread_scope_utils.gd`, `auth_context_utils.gd`, `tool_call_schema.gd` |
| Render | `synesyn_render_request_v1.gd`, `synesyn_comfy_client.gd`, `synesyn_render_service.gd` |
| Graph workspace | `graph_workspace/**` |

## Drop-in

Enable this plugin **before** SynAxes, SynTree, Metapunkt, or SynPunkt.

```
addons/synesyn_core/   ← required
addons/<product>/      ← the product you want
```

Bundled themes live under `themes/` (Utility/Base light+dark). Product addon
scenes reference those paths. A fuller host pack at `ScenSyn/themes/` is still
preferred by ThemeManager when present.
