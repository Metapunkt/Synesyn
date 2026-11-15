# ReadyMade content planning

ReadyMade helps you plan dated posts across channels without baking any
organisation’s server list into the product. Destinations, cadence, and timezones
are yours to set on each workplan.

## Workplans and destinations

1. Open **Workplan Manager**.
2. Create or select a workplan.
3. Actions are grouped: **Workplan** (new/duplicate/rename/delete/import/export),
   **Tasks import / export**, **Channels & caps** (channels, cadence, people),
   and **Time zones**.
4. Use **Manage Channels** to add, rename, remove, or reorder your destinations
   (for example `#general` or `Newsletter`). New workplans start with an empty
   custom list; platform defaults from the current mode still appear in the task
   dialog.

## Dating a post

In the task dialog **Calendar** tab:

- **Publish date** (`YYYY-MM-DD`)
- **Publish time** (`HH:MM`) and optional **IANA timezone** (empty inherits the
  workplan default, set via the manager when you use timezone-aware plans)
- **Content status**: `draft`, `placeholder`, `open_slot`, `needs_approval`,
  `approved`, or `posted` (separate from workflow To Do / Done)

## Viewer timezones

Each workplan has a default publish zone and an optional **viewer** zone. Lists
and the calendar show converted local times (including daylight-saving changes).
You can type a time in the viewer zone; ReadyMade stores it in the task’s publish
zone so collaborators keep a single source of truth.

## Campaign dashboard

Open the **Campaigns** tab to see posts grouped by campaign tag or content theme:
counts by content status, upcoming and overdue items, completion progress, and
how each channel sits against its weekly cadence cap.

## People and assignees

Use **Manage People** in Workplan Manager to list collaborators as
`{name, role, timezone}`. On each task, set **Assignee** to a person or free-text
agent id. Filter the Tasks list and calendar **By Assignee**. When the assignee
has a timezone, deadline/publish labels prefer that zone.

## Dependencies

In the task dialog, set **Depends on** to one or more predecessor task ids
(comma or semicolon separated). A task is **blocked** until every predecessor is
`Done` (missing ids also block). Blocked tasks show a clear indicator on cards
and the calendar. Self-links and cycles are rejected when you save.

## Stage board

Open the **Board** tab for a kanban of tasks by workflow lane (To Do → Done) or
by content status. Drag a card (or use the column arrows) to update status.
Blocked tasks stay highlighted. Filters for search and assignee apply here too.

## Approval log

Each content-status or workflow-status change appends an immutable entry
(`from`, `to`, `at`, optional person/note). The task dialog shows the ledger;
JSON/CSV export includes an `approval_log` column.

## Rescheduling on the calendar

Drag a task card onto another day to move its publish (or start/deadline) date.
Time and timezone stay the same. Right-click (or use **Move to date…** in the
side panel) for a keyboard-friendly date entry. Use **Undo last reschedule** to
roll back. Recurring instances move one at a time unless you choose **series**
(same title and channel). Cadence warnings update immediately after a move. If
other tasks depend on the one you moved, ReadyMade asks whether to shift those
dependents by the same number of days.

## Bulk CSV / JSON

Use **Export Tasks (CSV/JSON)** to review a month in a spreadsheet, then
**Import Tasks (CSV/JSON)**. ReadyMade shows a preview of creates, updates,
skips, and errors before applying. Matching prefers a stable `task_id`, then
falls back to date + channel + title.

Column details live in the developer guide bulk-IO schema (for contributors).

## Recurring posts

Set **Recurring** to weekly, tick weekdays, set an end date, then **Expand into
dates** to create dated instances (for example every Friday roundup).

## Calendar filters

On the calendar header, filter by channel, content status, campaign, or theme,
and search by title/theme/campaign.

## Cadence caps

**Cadence Caps** lets you set a maximum number of posts per channel per week.
Warnings are non-blocking: they appear in the manager and in a validation report
so you can still save an ambitious week.

## Templates and copy

Choose the **Community Post** format for chat-style drafts. On a task card, use
**Copy as Markdown** to paste a single post into another tool. Workplan **Export**
also offers Markdown for a full day-by-day handoff.
