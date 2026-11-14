# ReadyMade content planning

ReadyMade helps you plan dated posts across channels without baking any
organisation’s server list into the product. Destinations, cadence, and timezones
are yours to set on each workplan.

## Workplans and destinations

1. Open **Workplan Manager**.
2. Create or select a workplan.
3. Use **Manage Channels** to add, rename, remove, or reorder your destinations
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
