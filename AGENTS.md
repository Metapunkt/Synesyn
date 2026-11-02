# Synesyn — agent and contributor guide

Conventions for working in this repository. Paths are repo-relative.

You are working in a Godot 4 project (GDScript). Follow these rules to avoid debugger/linter warnings and hard-to-track bugs.

## GDScript naming rules (avoid shadowing)

### Never use these as local variables / parameters / loop iterators
- `name` (shadows `Node.name`)
- `visible` (shadows `CanvasItem.visible`)
- `mode` (shadows `Window.mode`)
- `position`, `rotation`, `scale` (common Node2D/Control properties)
- `log` (can collide with built-ins; prefer `story_log_entries`, `entries`, etc.)
- `call` / `signal` (can collide with base methods / language concepts)

### Preferred patterns
- Loop iterators: use explicit nouns, e.g. `for char_name in names`, `for mode_id in all_modes`, `for autoload_name in required`.
- UI node locals: suffix with `_node` (e.g. `content_viewer_node`, `tab_container_local`, `file_dialog_local`).
- Booleans: prefix with `is_`/`has_` (e.g. `is_visible`, `has_documents`).

### Preload / load variables
- If you preload a script, name it `SomethingScript` to avoid clashing with global `class_name` types.
  - Example: `const RuntimeConfigScript = preload("res://scripts/runtime_config.gd")`
- If you intend to use a global type, use the `class_name` symbol directly (e.g. `WorkplanTask.new()`), not the preload constant.

## Ternary rule (avoid incompatible types)
- Avoid `a if cond else null` unless the non-null branch is explicitly typed `Variant`.
- Prefer explicit `if/else` assignments when either branch could be `null`.

## Typing & type inference (avoid "Cannot infer the type" parse errors)

GDScript's `:=` operator infers the type from the right-hand side. It **fails** whenever the RHS evaluates to `Variant`. This is a hard parse error, not a warning.

### RULE: Never use `:=` when any of these apply — use `var x: Type = ...` instead:

1. **Ternary expressions** — both branches must be the same concrete type, or inference fails.
   - Bad:  `var label_text := pattern.name if cond else "fallback"`
   - Good: `var label_text: String = pattern.name if cond else "fallback"`

2. **Dictionary `.get()` returns** — always returns `Variant`.
   - Bad:  `var conf := data.get("confidence", 0.5)`
   - Good: `var conf: float = data.get("confidence", 0.5)` or `float(data.get(...))`

3. **Methods called on Variant values** — e.g. `array[i].distance_to(x)`, `dict_val.size()`.
   - Bad:  `var dist := positions[i].distance_to(center)` (positions is `Array`, element is `Variant`)
   - Good: `var dist: float = positions[i].distance_to(center)`

4. **Math on Variant operands** — e.g. `(p_matrix[i][j] + p_matrix[j][i]) / 2.0`.
   - Bad:  `var sym := (p_matrix[i][j] + p_matrix[j][i]) / 2.0`
   - Good: `var sym: float = (p_matrix[i][j] + p_matrix[j][i]) / 2.0`

5. **RefCounted method returns** — when the return type is not statically known (e.g. calling methods on a `Variant` reference to a `RefCounted`).
   - Bad:  `var cached := _embed_cache.get_cached_batch(texts, model_id, 0)`
   - Good: `var cached: Dictionary = _embed_cache.get_cached_batch(texts, model_id, 0)`

6. **Numeric helpers** — `abs()`, `min()`, `max()`, `snapped()` return `Variant`; use `absf()`, `minf()`, `maxf()`, `snappedf()` for floats, or `mini()`, `maxi()` for ints.
   - Bad:  `var overlap_x := (w * 2.0) - abs(dx)`
   - Good: `var overlap_x: float = (w * 2.0) - absf(dx)`

### When `:=` IS safe
- Literal assignments: `var x := 5.0`, `var s := "hello"`, `var v := Vector3.ZERO`
- Calls with concrete return types: `var n := node.get_child_count()` (returns `int`)
- Typed array methods: `var idx := cols.find("name")` (returns `int`)

### Awaited signals
- When awaiting signals like `HTTPRequest.request_completed`, explicitly type the result:
  - `var completed: Array = await http.request_completed`

## Scene / UI node rule (prefer .tscn over code)
- **Always** create UI layout nodes (ScrollContainer, MarginContainer, VBoxContainer, Panel, Label, Button, etc.) in the `.tscn` scene file via the inspector, not programmatically in GDScript.
- Only create nodes in code when they are **truly dynamic** (e.g. list items populated from data at runtime, nodes whose count or type is unknown at design time).
- Static structure changes (adding scroll wrappers, margin containers, rearranging layout hierarchy) must be done in the `.tscn`.

## Script size rule (maintainability / bug prevention)
- The canonical thresholds are **900 lines soft warning** and **1200 lines hard limit**, as defined in `docs/developer-guide/architecture.md` and enforced by `utilities/checks/check_line_limits.py`.
- If a script approaches the hard limit, split it into smaller focused modules (e.g. controllers, state holders, loaders).
- Do not introduce or worsen a hard violation; run the line-limit ratchet after changes.
- Prefer session-type-scoped modules (e.g. `ScenSyn/session_types/<session_type>/...`) over growing shared monoliths like `game_session.gd`.

## ScenSyn test harness (self-service CI)

After making changes to any ScenSyn file — metaprompt managers, theme controllers, session record, scenario `.txt` files, harness itself — run the harness autonomously before reporting findings. Do not ask the user to manually test things the harness can verify.

**Commands (run from workspace root).** Each spec carries its own assertions, so
pass only `--spec`; do not re-add assertion flags.
```
# Smoke test — scenario loads, one specialist turn runs, no errors (~70s)
python utilities/harness/test_harness.py \
 --spec docs/technical-review/run_specs/scensyn_workshop_catalyst_smoke.json

# Multi-turn — 3 exchanges, map accumulates, no errors (~150s)
python utilities/harness/test_harness.py \
 --spec docs/technical-review/run_specs/scensyn_workshop_catalyst_multiturn.json
```

**Never assert `--min-story-log` on a Workshop spec.** Workshop Catalyst caches its
assistant narrative for `/synthesis` rather than posting it to the story log (ADR
0009, 2026-08-03), so the log holds only the Narrator welcome plus the
facilitator's own turns. Assert on the `workshop_catalyst` snapshot block instead
(`session_record_pulse`, `thinking_map.node_count`, `thinking_map.edge_count`) via
the `snapshot_field` assertion type. Workshop also
has no scenario-defined cast, so `min_unique_senders` does not apply. Both hold
only for Workshop; Story Catalyst characters do post to the log.

**`session_record_text_length` is for single-turn specs only.** It reports the
*latest* turn's cached narrative, so a turn that surfaces no new claims correctly
shortens it to the 127-character `NO_CLAIMS_TEXT`. Asserting `min: 200` on a
multi-turn spec therefore fails on a healthy session. Multi-turn evidence must come
from state that accumulates, or from the pulse, which is present either way.

**Custom specs:** write to `docs/technical-review/run_specs/` using the existing JSON format. Add `wait_seconds` actions between messages for multi-turn flows.

**Harness limitations (use manual testing instead):**
- Workshop Catalyst timer, agenda, bucket extraction, and Session Record voice — these require the scenario to be selected *before* the session starts (as a human would), which the harness cannot replicate.
- Use the harness for: scenario loading, error detection, AI response quality, and — for Story Catalyst — character registration and rotation.

## Where writing goes (ADR 0025)

`docs/` is published and is read by people outside the project. Everything in it
must read as an account of the system, not of the work.

| Writing | Goes to |
| --- | --- |
| What the system must do | `docs/implementation_docs/` (a contract) |
| Why it is built this way | `docs/architectural-decisions/` (append-only) |
| What problem it solves | `docs/product-requirements/` |
| How to use or set it up | `docs/user-guide/`, `docs/developer-guide/` |
| What we intend to do next, and what we did | `implementation_tracking/active/`, then `completed/` |

Rules that matter when editing:

- **Never put a checklist or a delivery plan in `docs/`.** Tick boxes in
  `implementation_tracking/active/`; move a finished plan to `completed/`.
- **Never restate a contract inside a tracker.** Link to it.
- A user-guide page must not ask the reader to act on something they cannot reach:
  no `res://` paths, no repository paths, no source symbols as instructions.
- Linking from `docs/` into `implementation_tracking/` or into code requires an
  absolute `https://github.com/Metapunkt/Synesyn/blob/main/...` URL, because the
  generated site contains only `docs/`. A relative link out of `docs/` fails the
  strict build.
- After editing documentation, run `mkdocs build --strict`. It fails on a broken
  cross-reference, a bad anchor, or a document missing from the navigation in
  `mkdocs.yml` — so a new page must be added there.
- Defining a new term? Add it to `docs/concepts/glossary.md` rather than defining
  it in passing.



