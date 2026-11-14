# ReadyMade dogfood report — Anya Discord content plan

**Branch:** `cursor/readymade-hardening-5f3a` (fork PR #8)  
**Scenario:** Plan Metapunkt Discord (Latent Space) posts for **16 Nov – 15 Dec 2026** inside ReadyMade, as Anya would.  
**Deliverable plan:** [`docs/community/discord_content_plan_2026-11.md`](../community/discord_content_plan_2026-11.md)

## Content guidance applied (Ayodele)

| Guidance | How the plan reflects it |
| --- | --- |
| Stochastic Dreams documentation URL | Fetched successfully: [Research Catalogue document](https://www.researchcatalogue.net/view/4351440/4351445/document) (+ exposition abstract). Exhibition posts cite that URL and use only facts from those pages (Galleri KiT, Meta.Morf 2026, 9–21 Apr 2026, Lubi Board, Stochastic Dream Box, Chaos Engine pendulum, credits, title proposition). Earlier exhibition placeholders converted to drafts. |
| Open Closure as research in motion | `#kernel_inference` posts are discursive / reflective; **no reveal countdown / TBD date**. |
| Nothing scheduled beyond the rhythm | **1–2 `open_slot` weekdays per week** (five across the month) left empty for timely updates. |
| Rhythm confirmed | Weekdays ≈11:00 Europe/Oslo; weekend light/optional; Friday `#general`; ≤≈2 posts/channel/week. |

## Anya voice-pass (14 Nov 2026)

Folded Anya’s Section 5 replacements into the fixture and plan (verbatim drafts; schedule/caps/`@everyone` kept in header rules only; ADR/88b labels moved to Source/notes). Dec 12 moved to `#synesyn`. Ayodele-pending items carry **NEEDS CONFIRMATION** in notes (paywalled foresight; May 2026 portfolio date; curator credits; exhibition stills marked `image needed`).

## What worked

| Path | Result |
| --- | --- |
| Workplan create (`WorkplanManager.create_new_workplan`) | Worked. Named plan `Anya Discord Nov–Dec 2026`. |
| Task model fields (`publish_date`, `channel`, `content_theme`, `campaign_tag`, `generated_content`, `notes`) | Rich enough for Discord planning once filled; `STATUS:` in notes carries `draft` / `placeholder` / `open_slot`. |
| Scratchpad scene load + save under `Documents/Synesyn/readymade/` | Worked headless for brainstorm constraints. |
| Markdown export (new) | `export_workplan_as_markdown` + export dialog `.md` filter. |
| Mode: Metapunkt Discord (new) | Latent Space channel presets; excludes `#start-here`, `#anya_workspace`, `#ask-anya`. |

Dogfood scene: `synesyn_client/readymade/test_dogfood_discord_content_plan.tscn`  
Fixture: `synesyn_client/readymade/dogfood/discord_posts_nov2026.json`

## Friction log

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| `bulk_entry` | **high** | No CSV/JSON bulk import in UI. ~26 dated rows cannot reasonably be entered by hand. | **Deferred** (feature). Dogfood loads fixture via script. |
| `bulk_revise` | **high** | Voice-pass rewrote ~20 drafts. No UI path to re-import or bulk-update existing workplan tasks from JSON — had to rewrite the fixture outside ReadyMade and recreate the workplan in dogfood. | **Deferred**. |
| `markdown_export` | **high** | Export was `.tres`-only — useless for Discord handoff. | **Fixed** — markdown exporter + dialog default `.md`. |
| `discord_subchannels` | **medium** | Single “Discord” checkbox; server channel names needed Other. | **Fixed (partial)** — `metapunkt_discord` mode with Latent Space channels. |
| `recurring_tasks` | **medium** | `recurring_pattern` on `WorkplanTask` but no UI to set/expand Friday `#general` roundups. | **Deferred**. |
| `search_filter_campaign` | **medium** | Calendar channel filter TODO; `campaign_tag` / `content_theme` not first-class filters. | **Deferred**. |
| `open_slot_ux` | **medium** | No first-class “open slot” task type; encoded via title/notes/`STATUS: open_slot`. | **Deferred** (notes convention + export status column for now). |
| `timezone_schedule` | **low** | Date strings only; Europe/Oslo 11:00 stored in notes. | **Deferred**. |
| `channel_cap_warnings` | **low** | No ≤2 posts/channel/week guard. | **Deferred**. |
| `templates_for_discord` | **low** | No Discord post template; drafts in `generated_content`. | **Deferred**. |
| `open_closure_89_missing` | **low** (content) | README cites `89_Open_Closure_Pivot.md` but file absent on public `main`. | Documented in plan; not a ReadyMade bug. |

## Bugs / UX gaps fixed this pass

1. **Markdown workplan export** — `WorkplanMarkdownExport` + `WorkplanManager.export_workplan_as_markdown`; export dialog prefers `.md`. Acceptance: `_test_workplan_markdown_export`.
2. **Metapunkt Discord mode** — Latent Space channel list. Acceptance: `_test_metapunkt_discord_mode_channels`.
3. **Plan status in export** — `STATUS: draft|placeholder|open_slot` → Plan status column (distinct from workflow To Do/Done).

## Larger ideas (do not build here)

- Bulk import/export CSV ↔ workplan tasks (dates, channel, draft, status).
- First-class `open_slot` / `placeholder` content-plan status on `WorkplanTask`.
- Recurring task expander (weekly Friday roundup).
- Timezone-aware publish datetime + weekly channel-cap warnings.
- Campaign dashboard: posts/channel/week, open-slot debt, open-thread queue.
- One-click “copy Discord markdown” from task card.

## How to re-run

```bash
# Acceptance (CI)
utilities/checks/run_readymade_acceptance.sh

# Dogfood walkthrough (creates workplan + export under Documents/Synesyn/readymade/)
godot --headless --path synesyn_client \
  res://readymade/test_dogfood_discord_content_plan.tscn
```

## Material honesty

- Stochastic Dreams **exhibition** facts come from the Research Catalogue pages above (fetch **succeeded**). Nov 18 / 26 / 5 Dec stay `draft` with **image needed** until actual stills are attached (not page URLs).
- Open Closure: discursive only; no reveal date; “not a launch date” phrasing removed.
- **NEEDS CONFIRMATION** (Ayodele): “paywalled foresight” (30 Nov); May 2026 portfolio date (7 Dec); curator credits Murray-Leslie / Busch; exhibition photo picks.
