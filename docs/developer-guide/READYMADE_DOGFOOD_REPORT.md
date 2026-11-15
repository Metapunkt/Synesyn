# ReadyMade dogfood report — community content planning

**Branch:** `cursor/readymade-hardening-5f3a` (fork PR #8)  
**Scenario:** Plan roughly a month of dated community posts inside ReadyMade, using a **fictional** Example Art Collective as the dogfood fixture. The exercise was motivated by a real month-long community content-planning pass; org-specific material lives outside this repository.

## What was exercised

| Path | Result |
| --- | --- |
| Workplan create (`WorkplanManager.create_new_workplan`) | Worked. Named plan `Example Art Collective Nov–Dec 2026`. |
| Custom channels API + Manage Channels UI | `add` / `rename` / `remove` / `move` / `set` / `get_effective_channels`; empty default on new workplans. |
| Task model (`publish_date`/`time`/`timezone`, `content_status`, `campaign_tag`, …) | First-class content-plan fields; legacy `STATUS:` notes migrate. |
| Bulk CSV/JSON import-export | Export → edit → re-import updates by `task_id` (fallback date+channel+title) with preview. |
| Recurring weekly expand | Friday `#general` roundup expands into dated instances. |
| Calendar filters / search | Channel, content status, campaign, theme + search box. |
| Cadence caps | Per-channel max posts/week; non-blocking validation report. |
| Campaign dashboard | Per-campaign and per-theme status counts, progress, cadence vs caps. |
| Viewer timezone conversion | DST-aware display/entry between task zone and viewer zone. |
| Calendar drag-drop reschedule | Day moves with undo, series toggle, live cadence warnings. |
| Scratchpad + Markdown / Copy as Markdown | Worked headless under `Documents/Synesyn/readymade/`. |

Dogfood scene: `synesyn_client/readymade/test_dogfood_content_plan.tscn`  
Fixture: `synesyn_client/readymade/dogfood/example_community_posts.json`  
Example destinations (fixture only): `#general`, `#studio-notes`, `#reading-group`, `#open-studio`, `#exhibitions`

## Channels in ReadyMade (de-hardcoded)

| Before | After |
| --- | --- |
| Org-specific server channel presets baked into a product mode | **Removed** — modes only expose generic platform/venue defaults |
| Destinations only via mode list / Other | **`Workplan.custom_channels`** + Manage Channels UI |
| Task dialog = mode channels only | Mode platforms **plus** current workplan custom destinations |

Acceptance asserts custom-channel CRUD/reorder and that product mode defaults do not ship Discord-style `#channel` presets.

## Friction log

| ID | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| `bulk_entry` | **high** | No CSV/JSON bulk import in UI. | **Fixed** — `WorkplanTaskBulkIO` + Import/Export Tasks. |
| `bulk_revise` | **high** | Draft rewrites needed fixture re-import outside ReadyMade. | **Fixed** — update-by-`task_id` re-import with preview. |
| `markdown_export` | **high** | Export was `.tres`-only. | **Fixed** — markdown exporter + `.md` dialog. |
| `discord_subchannels` | **medium** | Server channel names needed Other or a hardcoded mode. | **Fixed** — `custom_channels` + Manage Channels. |
| `recurring_tasks` | **medium** | `recurring_pattern` with no UI/expand. | **Fixed** — weekday + end date + expand. |
| `search_filter_campaign` | **medium** | Calendar channel filter TODO. | **Fixed** — channel/status/campaign/theme + search. |
| `open_slot_ux` | **medium** | No first-class content-plan status. | **Fixed** — `content_status` + migration. |
| `timezone_schedule` | **low** | Date strings only. | **Fixed** — time + IANA zone + workplan default. |
| `channel_cap_warnings` | **low** | No weekly channel-cap guard. | **Fixed** — caps + non-blocking warnings. |
| `templates_for_discord` | **low** | No community post template / copy Markdown. | **Fixed** — Community Post template + Copy as Markdown. |
| `campaign_dashboard` | **medium** | No per-campaign progress / cadence view. | **Fixed** — Campaigns tab + `WorkplanCampaignDashboard`. |
| `tz_conversion` | **medium** | Zones stored as labels without viewer conversion. | **Fixed** — DST-aware `WorkplanTimezone.convert_zones`. |
| `calendar_dnd` | **medium** | Reschedule required edit dialog. | **Fixed** — drag-drop + Move to date + undo + series. |

## Bugs / UX gaps fixed in this dogfood pass

1. **Markdown workplan export** — day-by-day handoff with plan status and publish labels.
2. **De-hardcoded destinations** — `Workplan.custom_channels` + manager CRUD + Manage Channels UI.
3. **Bulk CSV/JSON task IO** — preview create/update/skip; schema in [readymade-task-bulk-io.md](readymade-task-bulk-io.md).
4. **First-class `content_status`** — dialog, calendar, markdown; migrates `STATUS:` notes.
5. **Recurring weekly expand**, calendar filters, timezone publish, cadence caps, Community Post + copy Markdown.
6. **Campaign dashboard** — status counts, upcoming/overdue, completion, channel distribution vs caps ([API notes](readymade-campaign-calendar.md)).
7. **Viewer timezone conversion** — enter in one zone, store/display in another with DST.
8. **Calendar reschedule** — drag or Move to date; undo; instance vs series; live cadence banner.

## Larger ideas (still out of scope)

- Hourly time-slot calendar (current views are day-granular).
- First-class assignees / reviewers / editors (and per-person zones); today roles live in notes.
- Task dependency graph + cascade reschedule after slips.
- Per-role approval audit records (beyond `needs_approval` / `approved`).
- Charts beyond the text/list campaign dashboard (sparkline / week heatmap UI).

## Journal production dogfood (2026-11-15)

Separate end-to-end pass: multi-person issue pipeline (stages, peer review, slip +
DnD, campaign dashboard, announcement drafts only). Plan data stayed in workspace
artifacts (not committed). Product fixes from that pass: `Africa/Lagos` timezone
coverage + unknown-zone warnings; bulk IO `deadline` / `start_date` /
`workflow_status` columns. Full write-up:
`/opt/cursor/artifacts/kijournal-dogfood/TEST_REPORT.md` (local artifact).

## How to re-run

```bash
# Acceptance (CI)
utilities/checks/run_readymade_acceptance.sh

# Dogfood walkthrough (creates workplan + export under Documents/Synesyn/readymade/)
godot --headless --path synesyn_client \
  res://readymade/test_dogfood_content_plan.tscn
```
