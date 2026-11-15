# ReadyMade campaign dashboard, timezones, and calendar reschedule

Generic helpers for content-plan workplans. Product code stays free of
organisation, server, or channel names; fixtures may use example destinations.

## Campaign dashboard

- Script: `synesyn_client/readymade/scripts/workplan_campaign_dashboard.gd`
  (`WorkplanCampaignDashboard`)
- UI: `synesyn_client/readymade/ui/campaign_dashboard.tscn` (Mission Control
  **Campaigns** tab)

`build(workplan, group_by)` with `group_by` of `"campaign"` or `"theme"` returns
group rows with `content_status` counts, upcoming/overdue tallies, completion
ratio, per-channel distribution, and the current cadence-cap warning list.
`render_text()` produces a plain-text report for copy/export.

## Timezone conversion

- `WorkplanTimezone` (`workplan_timezone.gd`) — IANA labels, DST-aware
  `convert_zones(date, time, from_zone, to_zone)` → `{date, time, timezone, known}`
  (includes `Africa/Lagos` and other common Africa zones; unknown zones fall
  back to UTC and are flagged in viewer labels)
- `WorkplanPublishTime` — `format_publish_label(task, workplan, viewer_zone)` and
  `set_task_publish_from_viewer(...)` so entry can be in the viewer zone while
  storage keeps the task’s publish zone (or workplan default)

Workplan fields: `default_timezone`, `viewer_timezone`. Task fields:
`publish_date`, `publish_time`, `publish_timezone`. Assignee/contributor zones are
not modeled; conversion is task zone ↔ viewer zone.

Workplan Manager exposes **Default Timezone** and **Viewer Timezone** (compact
dialogs; Enter confirms). Task/workplan Import and Export file dialogs use
`FileDialog.ACCESS_FILESYSTEM` and open under the ReadyMade Documents data
directory (not `res://`). Typing a name in the File: field enables Open when that
file exists (or Save when the path is valid); Enter confirms. Nested manager
dialogs set `exclusive = false` so Godot does not reject a second exclusive child
window.

## Calendar reschedule

- `WorkplanCalendarReschedule` (`workplan_calendar_reschedule.gd`)
- Wired from Mission Control calendar and `CalendarView`

`move_task_to_date(task, new_date, fields, preserve_time, workplan, series_mode)`
updates publish/scheduled/deadline/start as requested, keeps time + IANA zone,
emits live cadence warnings, and pushes an undo snapshot. `series_mode` is
`"instance"` (default) or `"series"` (same title + channel). `undo_last()`
restores the previous snapshot.

UI affordances: drag a card onto another day; context menu / detail
**Move to date…**; **Undo last reschedule**; toggle series vs instance. Month and
week views are day-granular (no hourly slots yet).

After a move, if other tasks list this task in `depends_on`, ReadyMade offers
**Move dependents by the same offset** (ConfirmationDialog). Cycles are rejected
when editing dependencies. Blocked tasks (predecessors not `Done`, or missing)
show an amber/⛔ indicator on calendar cards and task cards.

See `WorkplanDependencies` (`workplan_dependencies.gd`).

## People, board, approval log

- `WorkplanPeople` — normalize people `{name, role, timezone}`, assignee filter,
  deadline labels in the assignee zone.
- `WorkplanStageBoard` + Mission Control **Board** tab — kanban by workflow or
  `content_status`, with drag/arrow moves and blocked highlighting.
- `WorkplanApprovalLog` — append-only `{from,to,at,person,note}` ledger on each
  task; hooked from `set_content_status`, task-card workflow actions, and board
  moves; exported via bulk IO `approval_log`.

Workplan Manager groups actions into Workplan / Tasks import-export /
Channels & caps (includes Manage People) / Time zones.

## Acceptance

Covered in `test_acceptance_hardening_helpers.gd` via
`utilities/checks/run_readymade_acceptance.sh`.
