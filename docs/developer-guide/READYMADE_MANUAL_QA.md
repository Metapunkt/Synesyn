# ReadyMade Mission Control — manual QA pass

Short regression pass for Mission Control / orchestrator behavior that
automated acceptance cannot fully cover (timer, live hub drafting, calendar
drag feel, edit-mode UI). Pair with
`synesyn_client/readymade/TESTING_CHECKLIST.md` for deeper feature checks.

**Paths:** user data under `Documents/Synesyn/readymade/` (or
`storage.root_dir` from config). Drafts land in
`Documents/Synesyn/readymade/output/`.

| # | Step | Expected result |
| --- | --- | --- |
| 1 | **First launch (no workplans).** Clear or rename `Documents/Synesyn/readymade/workplans/`, launch ReadyMade → Mission Control. | First-launch choice offers **sample** vs **empty** workplan; choosing either creates a workplan and opens the dashboard without errors. |
| 2 | **Workplan switch.** Use the workplan selector to switch between two workplans (create a second if needed). | Active workplan name and task lists update; no leftover tasks from the previous plan. |
| 3 | **New task with instruments.** Ctrl+N (or Add New Task); set title, formats/channels, and at least one Cosmic Instrument; save. | Task appears in To Do with instruments persisted on reopen/edit. |
| 4 | **Draft To Do — hub off.** Stop the hub (or point config at a closed port). With Draft visible, click **Draft To Do tasks**. | Dialog/notice explains hub is unavailable and points at `synesyn_client.json` / config path; no false “orchestrator missing” message; tasks stay To Do. **OK**, window close, and **Escape** dismiss the dialog; drafting stops so the notice is not sticky. |
| 5 | **Draft To Do — hub on.** Start hub; click **Draft To Do tasks**. | Draft button hides and **Stop** appears; a To Do task moves to In Progress; agent status updates. |
| 6 | **Stop.** While drafting, click **Stop**. | Drafting stops; **Draft To Do tasks** returns; no Start/Stop both visible. |
| 7 | **Failed run → To Do.** Force a failed draft (invalid backend / cancel mid-run if available). | Failed task returns to **To Do** (or Review per product rules) with a visible error; UI is idle again. |
| 8 | **Calendar views + drag.** Open Calendar tab; switch Month / Week / Agenda; drag a task to a new day/slot. | Views render; drop updates the task date; onboarding drag hint dismisses and stays dismissed after relaunch. If the moved task has dependents, a **Move dependents?** prompt appears; accepting shifts them by the same offset. |
| 8b | **Dependencies.** Edit a task: set **Depends on** to another task’s id while that predecessor is still To Do. | Card/calendar show a blocked indicator; clearing the dependency or marking the predecessor Done removes it. Saving a cyclic depends_on list is rejected. |
| 9 | **All six edit modes.** Open edit/session UI and cycle every ModeManager mode. | Each mode applies without script errors; mode indicator matches selection. |
| 10 | **Shortcuts.** From Mission Control (focus not only on left panel): Ctrl+S, Ctrl+N, Ctrl+Shift+V. | Ctrl+S saves the task list (does not start drafting); Ctrl+N opens new task; Ctrl+Shift+V shows all tasks / clears filter as designed. |
| 11 | **Relaunch persistence.** Create/edit a task, note workplan name, quit, relaunch ReadyMade. | Same workplan and tasks reload from Documents storage. |
| 12 | **Drafts on disk.** After a successful draft, open `Documents/Synesyn/readymade/output/`. | New draft artifact(s) appear for the run (timestamped or named files). |
| 13 | **Legacy migration.** Seed legacy paths if present (`user://` or old ScenSyn-nested ReadyMade folders per ADR 0014), then launch. | Data appears under `Documents/Synesyn/readymade/`; getters alone do not move files — migration runs once at startup. |
| 14 | **Main tabs.** Click Tasks, Content, and Calendar tab centers at window sizes ~1152×648 and ~1920×1080. | Each click switches the page; tab chrome is not covered by page content. |
| 15 | **Start Agent exclusivity.** Idle vs drafting: confirm only one of Draft / Stop is shown; Start Agent (if present) does not fight Stop. | Mutual exclusivity holds after Draft, Stop, and failed-run recovery. |

## Automated coverage (for reviewers)

Acceptance script:
`synesyn_client/readymade/test_acceptance_workplan_instruments.gd`
(CI job `readymade-acceptance`).

| Area | Covered by acceptance | Thin / manual |
| --- | --- | --- |
| Path getters pure + `run_storage_migrations` | `_test_path_getters_are_pure_and_migrations_explicit`, `_test_top_level_readymade_path_and_migration` | Live Documents folder on a user machine |
| Workplan save/load + legacy migrate | `_test_workplan_save_load_and_legacy_migration` | Multi-workplan UI switch polish |
| First-launch sample vs empty API | `_test_first_launch_workplan_choice_api` | Actual modal UX / copy |
| Orchestrator hub gate / unavailable message | `_test_backend_unavailable_message_and_fail_task`, `_test_start_agent_batch_hub_gate` | Live hub Draft → In Progress → Done |
| WorkplanManager ready before UI | `_test_workplan_manager_ready_before_ui` | Race under slow disk |
| Edit metaprompt typed modes | `_test_edit_metaprompts_typed_modes` | Full six-mode UI chrome |
| Main tab center clicks (1152 + 1920) | `_test_main_tab_center_mouse_clicks` | Visual theme / focus rings |
| Calendar drag, Stop mid-run, output files, Ctrl shortcuts | — | **Manual** (steps 6–8, 10, 12) |
