# ReadyMade dogfood report — Anya Discord content plan

**Branch:** `cursor/readymade-hardening-5f3a` (fork PR #8)  
**Scenario:** Plan Metapunkt Discord (Latent Space) posts for **16 Nov – 15 Dec 2026** inside ReadyMade, as Anya would.  
**Deliverable plan:** [`docs/community/discord_content_plan_2026-11.md`](../community/discord_content_plan_2026-11.md)

## Content guidance applied (Ayodele)

| Guidance | How the plan reflects it |
| --- | --- |
| Stochastic Dreams documentation URL | Fetched: [RC document](https://www.researchcatalogue.net/view/4351440/4351445/document), [About](https://www.researchcatalogue.net/view/document/4351440/about), [Gallery](https://www.researchcatalogue.net/view/document/4351440/gallery). Exhibition posts cite those pages. |
| Curator credits | Exact RC About wording: *The exhibition is curated by Professor Alexandra Murray-Leslie and Assistant Professor Annett Busch.* |
| Exhibition images (18 Nov, 26 Nov, 5 Dec) | Direct RC media URLs in each post’s `image` field (exhibition photographs / tapestry turn render). |
| Forward Remembrance horizon | Ongoing project **2023–2027**; May 2026 portfolio framing removed. |
| Open-core / foresight framing | Softened to “an open-core approach to foresight tools”; no competitor claims; “paywalled foresight” dropped. |
| Open Closure channel | Posts moved to `#mapping_latent_reality`. |
| `#kernel_inference` | **Journal only.** Fetched [kernel-inference.com](https://kernel-inference.com/) (guidelines, papers, agents) and used those slots for journal posts. |
| Accessibility | Technical terms get a first-use gloss + 1–3 https links; drafts stay under 2,000 characters. |
| metapunkt.org | Fetched via `https://www.metapunkt.org/` (apex `metapunkt.org` TLS timed out once). Cited for opener, FR, retrospectives. |
| Anya ops | Plan header: open-slot prompts ~1–2 days ahead; monthly metapunkt.org edit prompts. |
| Rhythm | Weekdays ≈11:00 Europe/Oslo; weekend light/optional; Friday `#general`; ≤≈2 posts/channel/week. |

## Channels in ReadyMade (de-hardcoded)

| Before | After |
| --- | --- |
| Built-in `metapunkt_discord` mode with Latent Space channel presets | **Removed** from `ModeManager` |
| Destinations only via mode list / Other | **`Workplan.custom_channels`** — add / rename / remove / set; empty by default; persisted with the workplan |
| Task dialog = mode channels only | Mode platforms **plus** current workplan custom destinations (`get_effective_channels`) |

Metapunkt Latent Space names appear **only** as example data in the dogfood fixture/test when it calls `WorkplanManager.set_custom_channels(...)`. Acceptance asserts custom-channel CRUD and greps product scripts for Metapunkt/Latent Space channel presets.

## What worked

| Path | Result |
| --- | --- |
| Workplan create (`WorkplanManager.create_new_workplan`) | Worked. Named plan `Anya Discord Nov–Dec 2026`. |
| Custom channels API | `add` / `rename` / `remove` / `set` / `get_effective_channels`; empty default. |
| Task model fields (`publish_date`, `channel`, `content_theme`, `campaign_tag`, `generated_content`, `notes`) | Rich enough for Discord planning once filled; `STATUS:` in notes carries `draft` / `placeholder` / `open_slot`. |
| Scratchpad scene load + save under `Documents/Synesyn/readymade/` | Worked headless for brainstorm constraints. |
| Markdown export | `export_workplan_as_markdown` + export dialog `.md` filter. |

Dogfood scene: `synesyn_client/readymade/test_dogfood_discord_content_plan.tscn`  
Fixture: `synesyn_client/readymade/dogfood/discord_posts_nov2026.json`

## Friction log

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| `bulk_entry` | **high** | No CSV/JSON bulk import in UI. ~26 dated rows cannot reasonably be entered by hand. | **Deferred** (feature). Dogfood loads fixture via script. |
| `bulk_revise` | **high** | Voice-pass / Ayodele rewrites need fixture re-import outside ReadyMade. | **Deferred**. |
| `markdown_export` | **high** | Export was `.tres`-only — useless for Discord handoff. | **Fixed** — markdown exporter + dialog default `.md`. |
| `discord_subchannels` | **medium** | Server channel names needed Other or a hardcoded mode. | **Fixed** — workplan `custom_channels` (org lists only in dogfood/examples). |
| `recurring_tasks` | **medium** | `recurring_pattern` on `WorkplanTask` but no UI to set/expand Friday `#general` roundups. | **Deferred**. |
| `search_filter_campaign` | **medium** | Calendar channel filter TODO; `campaign_tag` / `content_theme` not first-class filters. | **Deferred**. |
| `open_slot_ux` | **medium** | No first-class “open slot” task type; encoded via title/notes/`STATUS: open_slot`. | **Deferred**. |
| `timezone_schedule` | **low** | Date strings only; Europe/Oslo 11:00 stored in notes. | **Deferred**. |
| `channel_cap_warnings` | **low** | No ≤2 posts/channel/week guard. | **Deferred**. |
| `templates_for_discord` | **low** | No Discord post template; drafts in `generated_content`. | **Deferred**. |
| `open_closure_89_missing` | **low** (content) | README cites `89_Open_Closure_Pivot.md` but file absent on public `main`. | Documented in plan; not a ReadyMade bug. |

## Bugs / UX gaps fixed this pass

1. **Markdown workplan export** — `WorkplanMarkdownExport` + `WorkplanManager.export_workplan_as_markdown`.
2. **De-hardcoded destinations** — removed `metapunkt_discord`; `Workplan.custom_channels` + manager CRUD; task dialog merges custom list. Acceptance: `_test_custom_channels_and_no_org_presets`.
3. **Plan status in export** — `STATUS: draft|placeholder|open_slot` → Plan status column.

## Larger ideas (do not build here)

- Bulk import/export CSV ↔ workplan tasks (dates, channel, draft, status).
- First-class `open_slot` / `placeholder` content-plan status on `WorkplanTask`.
- Recurring task expander (weekly Friday roundup).
- Timezone-aware publish datetime + weekly channel-cap warnings.
- Campaign dashboard: posts/channel/week, open-slot debt, open-thread queue.
- One-click “copy Discord markdown” from task card.
- UI for managing custom channels (API exists; dialog still uses Other for ad-hoc one-offs).

## How to re-run

```bash
# Acceptance (CI)
utilities/checks/run_readymade_acceptance.sh

# Dogfood walkthrough (creates workplan + export under Documents/Synesyn/readymade/)
godot --headless --path synesyn_client \
  res://readymade/test_dogfood_discord_content_plan.tscn
```

## Material honesty / fetch status

| Source | Result |
| --- | --- |
| Research Catalogue document / About / Gallery | **Succeeded** — curator credit + media URLs used |
| kernel-inference.com (home, guidelines, papers, agents) | **Succeeded** — journal posts cite these |
| https://www.metapunkt.org/ (+ About / FR / Stories) | **Succeeded** |
| https://metapunkt.org/ (apex, no www) | **Failed once** — TLS handshake timeout; use www |

Open Closure remains discursive (no reveal date). Image fields hold direct RC media URLs (not bare page links).
