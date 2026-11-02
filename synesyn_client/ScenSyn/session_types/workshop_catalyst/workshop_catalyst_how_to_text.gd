extends RefCounted
class_name WorkshopCatalystHowToText

## Baseline "how to use Workshop Catalyst" guidance shown in the How To
## workspace preset. Kept as a standalone constant (rather than inline in
## workshop_workspace_controller.gd) so the controller doesn't grow past the
## script-size ratchet just to hold static copy. This is app-level guidance —
## it applies to every scenario — and is distinct from a scenario's own
## optional `how_to_text`, which workshop_catalyst_controller.gd appends
## below it (see WorkshopWorkspaceController.set_how_to_text()).

const BASE_TEXT: String = """[b]What this workspace is[/b]
Workshop Catalyst is a live facilitation surface: you talk through a Scenario in stages, while the system extracts claims onto a Thinking Map and accumulates decisions/risks/open questions in a Session Record. Nothing becomes a permanent workshop summary until you Preview and then Commit.

[b]Screen layout (top → bottom)[/b]
[b]1. Header toolbar[/b] — Workspace presets (Show Chat / Map / Review / Full Dashboard / Custom / How To). These rearrange which panels fill the center and rails; they do not end the session.
[b]2. Main body[/b] — three regions you can resize with the drag splitters between them:
• [b]Left Session Menu[/b] — participants shortcuts, My Sessions (resume a prior save), Plans/Progress previews, Insights toggle.
• [b]Center workspace[/b] — the primary work surface for the active preset (conversation, map, review, or this How To page).
• [b]Right rail[/b] — AI Assistant and Session Record when the preset keeps them docked.
[b]3. Safety bar[/b] — always visible at the bottom: listening/mic status, facilitator/participant names, End & Save, and short status pulses after each turn.

Drag the vertical/horizontal splitters to widen a pane. Your split sizes are remembered for later sessions. Prefer a preset when you want a known layout quickly; use Custom when you need a one-off mix.

[b]Workspace presets (header buttons)[/b]
[b]Show Chat[/b] — conversation + input in the center; AI Assistant and Session Record stay on the right. This does not listen. Use Record to speak.
[b]Map[/b] — Thinking Map fills the center so you can inspect/edit claims and relationships live from the discussion.
[b]Review[/b] — the Session Record moves out of the right rail into the center, beside Compare Paths, so you can weigh one decision path against another. The right rail is empty here by design. Review needs at least one recorded decision before it opens: Compare Paths builds a path from each reviewed decision, so risks and open questions alone will not fill it.
[b]Full Dashboard[/b] — left menu, conversation, map, and right rail all visible at once.
[b]Custom ▾[/b] — opens panel toggles (Conversation, Thinking Map, AI Assistant, Session Record, Participants, Session Menu). Tick only what you need; the layout updates immediately and is saved.
[b]How To[/b] — this page in the center (scenario-specific notes appear below when authored).

[b]Navigating day-to-day[/b]
• Type into the message box and send to continue the workshop conversation.
• Use [b]Next Stage[/b] to advance the agenda. If there was discussion, this also asks the AI to suggest Session Record items for you to review — suggestions are not committed until you accept them.
• Press [b]End & Save[/b] on the safety bar when finished.
• [b]My Sessions[/b] (left Session Menu) resumes a previously saved local session live, same as [b]Load Story Log…[/b] under the ☰ settings menu.
• Toggle [b]Insights[/b] in the left menu when you want the specialist-reasoning rail more prominent.

[b]Facilitator slash commands[/b] (type into the message box)
[b]/note [text][/b] — post a note. Does not trigger an AI response.
[b]/decide [text][/b] — capture a decision directly into the Session Record.
[b]/risk [text][/b] — capture a named risk.
[b]/defer [text][/b] — capture a deferred or open question.
[b]/vote[/b] — ask the Session Record to propose a Yes/No vote from the recent discussion.
[b]/synthesis[/b] — recall the latest hidden specialist synthesis in full. It no longer posts automatically every turn; watch the status bar for a one-line pulse instead.

Toggle [b]Next input is note only[/b] in the settings panel to send your very next message as a note without typing [b]/note[/b].

[b]Where things show up[/b]
[b]Thinking Map[/b] (Map view / Full Dashboard) — live claims and relationships specialists extracted from the conversation.
[b]Session Record[/b] (right rail, or center in Review) — decisions, risks, open questions, owners, and next steps — typed by you or proposed by the AI. Preview → Commit makes them permanent for the workshop summary.
[b]AI Assistant panel[/b] — specialist reasoning trace if you expand "Show reasoning/analysis." Off by default.
[b]Status bar pulse[/b] (bottom) — a one-line heads-up after each turn, e.g. "2 causes, 1 opportunity noted." Type [b]/synthesis[/b] for the full recap behind it.

[b]Multiplayer presence[/b]
When Multiplayer is on, every instance must set a display name. Facilitator is claim-until-taken: stage advances, commits, and End & Save stay locked until someone claims Facilitator. Participants can join and rename; the Facilitator card stays up until a claim exists."""
