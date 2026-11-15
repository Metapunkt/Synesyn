# ReadyMade task bulk CSV / JSON schema

Bulk import and export let a reviewer edit workplan tasks outside ReadyMade
(spreadsheet or JSON), then re-import creates and updates into the current
workplan.

## UI

In **Workplan Manager**:

- **Export Tasks (CSV/JSON)** — writes the current workplan’s tasks.
- **Import Tasks (CSV/JSON)** — opens a file, shows a preview
  (`created` / `updated` / `skipped` / `errors`), then applies on confirm.
- Workplan **Export** also accepts `.csv` / `.json` filters for the selected plan.

## Columns

| Column | Required | Notes |
| --- | --- | --- |
| `task_id` | recommended | Stable id. Match key for updates. Auto-assigned on export if missing. |
| `publish_date` | for dating | `YYYY-MM-DD` |
| `publish_time` | no | `HH:MM` local to the task/workplan timezone |
| `publish_timezone` | no | IANA zone (e.g. `Europe/Oslo`); empty inherits workplan default |
| `deadline` | no | `YYYY-MM-DD` production/due date (distinct from publish when needed) |
| `start_date` | no | `YYYY-MM-DD` work start |
| `channel` | no | Destination label (e.g. `#general`, `YouTube`) |
| `content_theme` | no | Theme / pillar |
| `campaign_tag` | no | Campaign grouping |
| `title` | **yes** | Empty title rows are skipped |
| `draft` | no | Body text (`generated_content`) |
| `status` | no | Content-plan status: `draft`, `placeholder`, `open_slot`, `needs_approval`, `approved`, `posted` |
| `workflow_status` | no | Workflow lane: `To Do`, `In Progress`, `Review`, `Done` |
| `notes` | no | Free-form notes (do not encode status here) |
| `depends_on` | no | Predecessor `task_id` values, separated by `;` or `,` |
| `assignee` | no | Person name or agent label from the workplan people list (or free text) |
| `approval_log` | no | JSON array of `{from,to,at,person,note}` status-change entries (append-only) |

JSON shape:

```json
{
  "tasks": [
    {
      "task_id": "task_…",
      "publish_date": "2026-11-14",
      "publish_time": "11:00",
      "channel": "#general",
      "content_theme": "Weekly roundup",
      "campaign_tag": "nov-campaign",
      "title": "Friday roundup",
      "draft": "…",
      "status": "draft",
      "notes": ""
    }
  ]
}
```

## Matching rules (import)

1. If `task_id` is present and matches an existing task → **update**.
2. Else if `publish_date` + `channel` + `title` (case-insensitive) match → **update**.
3. Else → **create** (new `task_id` if the row left it blank).

Preview never mutates the workplan; apply runs only after confirmation.
