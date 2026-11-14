# ReadyMade dogfood report — community content planning

**Branch:** `cursor/readymade-hardening-5f3a` (fork PR #8)  
**Scenario:** Plan roughly a month of dated community posts inside ReadyMade, using a **fictional** Example Art Collective as the dogfood fixture. The exercise was motivated by a real month-long community content-planning pass; org-specific material lives outside this repository.

## What was exercised

| Path | Result |
| --- | --- |
| Workplan create (`WorkplanManager.create_new_workplan`) | Worked. Named plan `Example Art Collective Nov–Dec 2026`. |
| Custom channels API | `add` / `rename` / `remove` / `set` / `get_effective_channels`; empty default on new workplans. |
| Task model fields (`publish_date`, `channel`, `content_theme`, `campaign_tag`, `generated_content`, `notes`) | Rich enough for Discord-style planning once filled; `STATUS:` in notes carries `draft` / `placeholder` / `open_slot` / `needs_approval`. |
| Scratchpad scene load + save under `Documents/Synesyn/readymade/` | Worked headless for brainstorm constraints. |
| Markdown export | `export_workplan_as_markdown` + export dialog `.md` filter. |

Dogfood scene: `synesyn_client/readymade/test_dogfood_content_plan.tscn`  
Fixture: `synesyn_client/readymade/dogfood/example_community_posts.json`  
Example destinations (fixture only): `#general`, `#studio-notes`, `#reading-group`, `#open-studio`, `#exhibitions`

## Channels in ReadyMade (de-hardcoded)

| Before | After |
| --- | --- |
| Org-specific server channel presets baked into a product mode | **Removed** — modes only expose generic platform/venue defaults |
| Destinations only via mode list / Other | **`Workplan.custom_channels`** — add / rename / remove / set; empty by default; persisted with the workplan |
| Task dialog = mode channels only | Mode platforms **plus** current workplan custom destinations (`get_effective_channels`) |

Acceptance asserts custom-channel CRUD and that product mode defaults do not ship Discord-style `#channel` presets (user destinations belong on the workplan).

## Friction log

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| `bulk_entry` | **high** | No CSV/JSON bulk import in UI. ~25 dated rows cannot reasonably be entered by hand. | **Deferred** (feature). Dogfood loads fixture via script. |
| `bulk_revise` | **high** | Draft rewrites need fixture re-import outside ReadyMade. | **Deferred**. |
| `markdown_export` | **high** | Export was `.tres`-only — useless for community handoff. | **Fixed** — markdown exporter + dialog default `.md`. |
| `discord_subchannels` | **medium** | Server channel names needed Other or a hardcoded mode. | **Fixed** — workplan `custom_channels`. |
| `recurring_tasks` | **medium** | `recurring_pattern` on `WorkplanTask` but no UI to set/expand Friday `#general` roundups. | **Deferred**. |
| `search_filter_campaign` | **medium** | Calendar channel filter TODO; `campaign_tag` / `content_theme` not first-class filters. | **Deferred**. |
| `open_slot_ux` | **medium** | No first-class “open slot” task type; encoded via title/notes/`STATUS: open_slot`. | **Deferred**. |
| `timezone_schedule` | **low** | Date strings only; local posting time stored in notes. | **Deferred**. |
| `channel_cap_warnings` | **low** | No ≤2 posts/channel/week guard. | **Deferred**. |
| `templates_for_discord` | **low** | No Discord post template; drafts in `generated_content`. | **Deferred**. |

## Bugs / UX gaps fixed in this dogfood pass

1. **Markdown workplan export** — `WorkplanMarkdownExport` + `WorkplanManager.export_workplan_as_markdown`; Plan status column from `STATUS:` notes (`draft` / `placeholder` / `open_slot` / `needs_approval`).
2. **De-hardcoded destinations** — `Workplan.custom_channels` + manager CRUD; task dialog merges custom list. Acceptance: `_test_custom_channels_and_no_org_presets`.

## Larger ideas (do not build here)

- Bulk import/export CSV ↔ workplan tasks (dates, channel, draft, status).
- First-class `open_slot` / `placeholder` / `needs_approval` content-plan status on `WorkplanTask`.
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
  res://readymade/test_dogfood_content_plan.tscn
```
