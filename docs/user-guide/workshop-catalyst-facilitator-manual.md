# Workshop Catalyst Facilitator Manual

This guide is for a facilitator who wants to run a Workshop Catalyst session in ScenSyn without prior knowledge of the system.

It focuses on the current practical workflow: how to start, how to steer, how to capture outputs, how to continue later, and what to look out for while the session is running.

Product scope and acceptance conditions are maintained in the
[`Workshop Catalyst PRD`](../product-requirements/PRD-SCENSYN-WORKSHOP-CATALYST.md).

---

## What Workshop Catalyst is

Workshop Catalyst is a facilitation-first ScenSyn mode for structured workshops.

Its positioning: **Explore, reflect on and streamline the decisions that need to be made before they become policy commitments — in a structured environment where all relevant institutional pressures are visible.**

The session has one primary output: a **decision record**.

A complete decision record contains:
- **3 decisions made** — each with an owning role and a confidence level (High / Medium / Low)
- **2 risks named** — each with a likelihood rating and who absorbs the cost
- **1 open question deferred** — with a stated owner and reason for deferral

Everything else the session produces — system maps, safeguards, principles, constraints, next steps — is supporting context. The decision record is the deliverable.

The AI is best used as a co-facilitator, not as a replacement for the human facilitator. Its job in this mode is to push the room toward decisions, not to generate comprehensive analysis.

---

## What the facilitator does

The facilitator is responsible for:

- choosing when to start, pause, and advance stages
- deciding when the group has explored enough and needs synthesis
- using facilitator notes when assumptions or clarifications need to be injected
- updating workshop notes (buckets) at sensible moments
- exporting a summary at the end of a useful session segment

The AI helps by:

- synthesizing several hidden specialist perspectives into one **Session Record**
  response per facilitator turn
- surfacing tensions and trade-offs without presenting specialists as participants
- helping the room move from vague discussion to concrete outputs
- proposing closure when convergence appears, while leaving voting and commitment
  to visible human action
- carrying forward context when continuity is available

---

## The facilitation method

Workshop Catalyst is not a neutral chat window with a timer. It runs a specific
method, and knowing the method is the difference between fighting the tool and
steering it. The method has three parts: four lenses, six cross-checks, and a
stage contract.

### Four lenses

Every facilitator turn is examined by the same four hidden lenses. They are
stable across every Scenario — the subject matter changes, the lenses do not.
Each lens has a characteristic way of reasoning:

| Lens | What it looks for | How it reasons |
|---|---|---|
| Systems & Consequences | Root causes, dependencies, second-order effects | Builds the most plausible account of an incomplete picture |
| Stakeholder & Communication | Who is affected, framing gaps, what needs saying | Reasons from inside an affected position |
| Risk & Feasibility | Failure modes, constraints, implementation risk | Narrows a claim against constraints until only what survives remains |
| Options & Innovation | Alternatives and reframings | Holds a provisional option open long enough to examine it |

Each lens also adopts whatever domain expertise the conversation calls for —
track engineering when you are discussing rail handoffs, pharmacovigilance when
you are discussing safety signals. This happens entirely backstage. No adopted
expertise is ever named, performed, or presented as a participant, and borrowing
expertise never upgrades a claim's status: anything the room did not say and the
evidence does not support is still labelled **AI inferred**.

### Six cross-checks

Four lenses produce six pairings, and the pairings are where the useful
questions live. Single-lens output tends to state what everyone already
suspects; the pairings are what a room under time pressure skips.

| Pairing | The question it forces |
|---|---|
| Systems + Stakeholder | Who absorbs the second-order effects, and where is harm displaced rather than removed |
| Systems + Options | Where would an intervention actually take hold, given the dependencies |
| Systems + Risk | What is the structural limit on what any intervention here can achieve |
| Stakeholder + Risk | Who bears the cost when this fails, and do they have any say |
| Stakeholder + Options | Would the affected parties accept or even recognise this alternative |
| Options + Risk | Which alternatives survive the constraints, and which predictably backfire |

You will not see these named in the response, and you should not expect all six
in every turn. The assistant works the ones the current stage needs. Two are
worth knowing by heart because they map directly onto the decision record:
**Stakeholder + Risk** produces a risk with a named cost-bearer, and
**Options + Risk** is what eliminates an option honestly rather than
rhetorically.

If a turn feels thin, the most productive facilitator move is to ask for a
pairing directly: "who pays if the second option fails?" or "what would make
this impossible rather than merely difficult?"

### The stage contract

Every stage carries the same four-part contract, whether it came from an
authored Scenario or was generated for a Scenario you created:

- **Facilitator goal** — what you are trying to get from the room
- **AI goal** — what the assistant is trying to do for you in this stage
- **Required output before advancing** — what must exist before you move on
- **Decision-forcing question** — the sentence that converts discussion into a
  recorded commitment

Do not advance a stage on discussion alone. The required output is the whole
point of the stage, and the decision-forcing question is there for the moment
the room is circling.

The default six-stage agenda gives each lens a beat of its own, bracketed by
opening and closing:

1. **Frame the Scenario** — agree what is being decided, and what counts as good enough
2. **Map Causes and Effects** — Systems lens leads
3. **Weigh Who Is Affected** — Stakeholder lens leads
4. **Develop Options** — Options lens leads
5. **Test Risks and Feasibility** — Risk lens leads
6. **Synthesize Decisions and Next Steps** — reduce to the decision record

Authored Scenarios may use their own agenda and their own stage guidance; when
they do, theirs takes precedence.

### Closure is the point

The vocabulary is worth stating plainly because it explains why the interface
behaves as it does. A committed decision is a **closure** — a boundary the room
draws so it can act. A deferred question is openness the room chooses to keep
rather than resolve badly. Nothing closes without you: proposals stay proposals
until you accept, edit, reject, or defer them, and every commit keeps its
lineage. The do-nothing path exists so that refusing to close is a visible,
examinable option rather than a silent default.

---

## Before you begin

Before starting a session:

1. Choose the **Workshop Catalyst** Session Type, its **Decision Triage**
   Collection, and the scenario you want to run.
2. Decide whether this is a one-off session or part of a multi-day series.
3. Choose a session duration in the Workshop Catalyst controls.
4. Brief the human participants on the decision question and how the facilitator
   will record their input.
5. Explain that the AI will help structure the conversation, but the facilitator still decides when to move on.

For a first run, a 1-hour or 2-hour session is usually easiest to manage.

---

## Getting started: launching a session

### Step 1 — Open Synesyn and start the local hub

When Synesyn opens you will see the launcher. Check that **Hub: running** is shown in the Local Hub panel. If it is not, click **Start Hub** and wait a few seconds for the status to update.

Once the hub is running, click **Open ScenSyn**.

---

### Step 2 — Open the scenario player

On the ScenSyn home screen, click **Play A Scenario**. You do not need to visit Tools to run the workshop. Hub, model, and voice setup live under **Settings** (hamburger menu, or Tools → Settings).

---

### Step 3 — Select the scenario

The selector opens with:
- **Session Type**: Workshop Catalyst
- **Collection**: Decision Triage
- **Create New Scenario / Describe Your Scenario** as the default action

Enter a title, central question/objective, context, desired outcomes,
constraints, time horizon, relevant stakeholders/perspectives, and optional
evidence notes. Review the fields, then choose **Save Local Draft & Use
Scenario**. The draft is stored on this device and is clearly labelled
**local draft**; this does not publish or commit it to the Hub.

Authored Scenarios such as
`karlsruhe_library_future_design` remain available as optional templates.
Selecting one shows its Overview before confirmation; Workshop entry does not
force-load any template.

---

### Step 4 — Enter as Facilitator

Workshop Catalyst bypasses character selection. The local human sender is
**Facilitator**; no stakeholder persona needs to be selected. Story Catalyst
continues to use character selection, but that flow does not apply here.

---

### Step 5 — The session screen

The Workshop Catalyst screen uses three regions on a wide display: product and
session navigation on the left, the active conversation/map/review workspace in
the center, and AI Assistant plus Session Record on the right. Participant
presence and Invite status stay compact in the session header.

The default **Show Chat** workspace prioritizes conversation. It does not listen;
use **Record** to speak. **Map** makes the Live Thinking Map the main center canvas. **Review**
places the editable Session Record and Compare Paths together in the center.
**Full Dashboard** shows the complete left + center + right hierarchy. **Custom**
remembers manual region visibility and collapsed rails.

On medium displays, use **Navigation** and **Insights** in the header to collapse
either rail. On narrow displays, the center remains primary and labelled buttons
open one rail at a time as a drawer. The interface does not stack every dashboard
surface into one long column.

Recording/listening, consent, transcription errors, Hub save status,
uncommitted-change warnings, and **End & Save Session** remain in the compact
footer when you change workspace presets or collapse a rail.

You can still type in the dialogue input and click **Send** (or press Enter);
typed input is unchanged. For speech:

1. Click **Record**, speak, then click **Stop**.
2. Review and edit the speech transcript preview.
3. Click **Send transcript** to submit it, or **Cancel / re-record** to discard it.

Speech is never auto-sent in Workshop Catalyst, even if the shared voice
auto-send setting is enabled. Raw microphone audio is not retained unless
**Save STT recordings** has been explicitly enabled.

After a spoken turn is sent, the correction panel keeps the original visible.
**Save correction only** creates a new transcript-record version and does not
change the conversation or call the AI again. Use **Resend corrected text** only
when you intentionally want a separate new turn. If the Hub is unavailable,
the conversation continues and the safety bar reports that transcript retention
is local/degraded.

Workshop Catalyst speaks exactly one AI output per turn: the **Session Record**.
Hidden specialist summaries remain silent even when their reasoning disclosure
is opened. Story Catalyst voice behavior is unchanged.

The **hamburger menu (≡)** in the top-right corner opens the Workshop Catalyst controls panel — see the next section.

---

## Main controls

Open the Workshop Catalyst controls panel by clicking **≡** in the top-right corner of the session screen.

### Session controls

- `Session Duration`: choose 1 to 4 hours. Set this before clicking Start — it determines stage timing for the whole session. **A 2-hour session is a good default for a first run.**
- `Part of multi-day session`: leave this off for a single-day workshop.

### Stage controls

- `Start`: starts the timer for the current stage — **click this as soon as the session begins**
- `Pause`: pauses the current stage
- `Next Stage`: advances to the next stage
- `+5m` / `+10m`: adds extra time to the current stage

### Facilitation controls

- `Next input is note only`: the next message is stored as a facilitator note and does not trigger an assistant response
- `Send as Facilitator (visible to AI)`: toggle this on to send a facilitator intervention that the Session Record will consider. Toggle it off again after use.
- `Update Workshop Notes`: updates the workshop buckets from the recent discussion (LLM extraction over the last 40 turns). **Run this after every stage advance or decision capture.**
- `Export Workshop Summary`: writes a markdown summary file for the current session. **Run this before closing the application.**
- `Export Decision Record`: writes a minimal, human-readable file containing only decisions, risks, and deferred questions — suitable for sharing with non-technical stakeholders without additional processing.
- `Inject Stress`: posts the current stage's authored stress injection scenario text into the session as a Facilitator Note. **This button is only enabled when the current stage is a Stress Injection stage.** See below for details.

### How stress injections work

Stress Injection stages appear in the workshop agenda at the points where a pre-written scenario shock is introduced. The shock text — describing a realistic disruption participants must respond to — is authored in the scenario file, but is **not posted automatically**. The facilitator controls when it enters the session.

**To trigger a stress injection:**

1. Advance to the Stress Injection stage using **Next Stage**.
2. When you are ready to introduce the shock, click **Inject Stress** in the Workshop Catalyst controls. This posts the shock text as a Facilitator Note — visible in the session log but not triggering an assistant response.
3. Optionally add a short framing message using **Send as Facilitator** (e.g. "This is the situation as of now — what should the room examine first?") to request synthesis.
4. The session then proceeds normally; characters respond to the injected scenario and the voting system continues to operate.

If you want to introduce the shock verbally to the room first (e.g. reading it aloud on a shared screen) before posting it, do so before clicking Inject Stress.

### Session Record tab

The **Session Record** tab is the facilitator's editable review surface. It has
separate sections for decisions, risks, open questions, owners, and next steps.
Direct `/decide`, `/risk`, `/defer`, and adopted-vote captures enter the reviewed
draft as facilitator-authorized material.

`Update Workshop Notes` does not merge AI text. It creates proposal rows beneath
the reviewed sections. For each proposal:

- **Accept** keeps the suggested wording in the reviewed local draft.
- **Accept Edited** keeps the text after your edit; this wording takes precedence
  over later model suggestions.
- **Reject** records the decision and suppresses the same suggestion.
- **Defer** records it for later and also suppresses silent repetition.

Use **Preview** to inspect the complete resulting summary and semantic diff. It
does not save or mutate anything. Use **Commit New Version** only after review.
This creates an immutable `ui.workshop_summary` artifact with provenance and a
link to the previous committed version. If the Hub is unavailable, the draft
remains visibly uncommitted and **Retry Commit** sends the retained payload
without losing edits.

**Propose themes** opens Tools → SynAxes with the current (or latest Hub)
session turns preloaded and discovery queued, then focuses the Closures /
Dream Inbox tab. Leave Advanced closed; review candidates with **Work on this**,
name them, and commit Closures you can stand behind. Requires Hub session.turn
events for that session.

Exports reference the last committed summary when one exists. If there has been
no successful commit, the existing file export still works but is clearly
labelled **Uncommitted fallback export**.

### Thinking Map

Choose the **Map** workspace preset to open the live
**Causes / Effects / Opportunities** projection. Structured candidates extracted
inside the existing batched specialist review appear as suggestions. Their badges distinguish **Participant said**,
**AI inferred**, and **External evidence supported**; an unsourced model item
always remains labelled **AI inferred**.

Cause means a driving factor, Effect means an actual or plausible consequence,
and Opportunity means an intervention, opening, option, or actionable
possibility. Process guidance, clarification requests, preview/commit
instructions, status messages, and unavailable-context notices remain
facilitator cues and never become map cards. A malformed specialist batch creates
no map suggestions; the application does not copy raw participant or Session
Record prose into a column.

For each suggestion, use **Accept**, edit its text and use **Edit**, **Reject**,
or **Defer**. These actions update only the local reviewed draft. Use
**Preview map impact** to inspect the semantic change, then
**Commit reviewed map** to create a new immutable
`ui.workshop_thinking_map` version. If Hub persistence fails, keep facilitating
and use **Retry map commit**; the prior committed lineage is unchanged.

Approved decision, risk, owner, and next-step cards can be routed to the Session
Record only with the explicit route action. Map items never create closure by
themselves.

**Allow committed map context for hidden specialists** defaults off. Enable it
only when you want the last successfully committed map included in later
specialist review. The choice records a trace and can be revoked at any time.
Draft, absent, disabled, or failed-to-commit maps do not affect prompts.

### Compare Paths

Choose **Review** to use **Compare Paths** with the editable Session Record in
the center review surface. Click
**Propose from reviewed notes** to create candidate cards. Candidates do not
select or commit themselves. Review each card with **Accept**, **Accept edits**,
**Reject**, or **Defer**.

One card always represents continuing without a new intervention. Treat it as a
real path: review its outcomes, biggest risk, assumptions, uncertainty, and time
horizon. It cannot disappear from a committed comparison, and the interface
does not describe it as neutral or risk-free.

Click **Retrieve evidence** to query available STFX Store context. Each
reference is displayed as a source label and excerpt. A path with no references
shows **Evidence: none**. Service failure shows degraded or unavailable status;
it never creates a citation. Retrieval does not select a path.

Select one accepted path, or check at least two accepted paths, name the
combination, and click **Combine checked paths**. The selection is still a
draft. Click **Preview comparison** to inspect the complete set and semantic
diff, then **Commit selected path set**. Successful commitment creates an
immutable path-set artifact and sends the explicit closure action. If Hub or
closure delivery fails, use **Retry commit**; the status states whether an
artifact was stored and does not claim closure prematurely.

Committed outcomes do not alter the Session Record automatically. Click
**Add committed outcomes to Session Record** when you want them added to its
editable reviewed draft.

### Participants, Plans, and Progress

The compact participant area in the session header currently represents this
device, not a shared remote session. It shows **Facilitator, Present on this
device**. It does not infer remote attendance or keep a separate participant
list.

**Invite (unavailable)** opens an explanation of the current boundary. It does
not ask for an email address or other contact detail, and it does not send an
invitation or outbound message. Remote participant presence and multi-client
session synchronization are deferred.

The left navigation rail keeps **Plans** and **Progress** visible as previews:

- **Plans** points to the Session Record and Compare Paths material available in
  the current session. It does not assign or execute work.
- **Progress** points to committed workshop artifacts and the local Session
  Record. It does not track remote updates or provide analytics.

Both previews are labelled **coming soon**. There are no reminders, email
notifications, or follow-up automations behind these controls.

### Closure commands (typed in chat input)

The following commands write directly to the decision record and do not trigger a hidden-specialist turn:

| Command | What it does |
|---|---|
| `/decide [text]` | Records a decision immediately |
| `/risk [text]` | Records a named risk immediately |
| `/defer [text] owner:[Name]` | Records a deferred question immediately |
| `/vote` | Asks the Session Record to synthesize a Yes/No proposal from the recent discussion and call a vote |

Use `/decide`, `/risk`, and `/defer` when the group has reached a workable position but the AI keeps generating qualifications.  
Use `/vote` when you can see the room has converged but the system has not yet called a vote on its own.

---

## How the voting system works

Workshop Catalyst can use a **visible vote proposal** to help formulate closure,
but it never treats hidden specialist analysis as a vote or a decision.

### What triggers a vote

The Session Record may propose a vote when visible discussion appears to converge
or when the record has gone several turns without a capture. The facilitator can
always type `/vote` to request a proposal directly.

### What a vote looks like

When a vote is triggered, the Session Record posts:

> **PROPOSAL — Decision:** "The proposal in one sentence." Owner: [role]. Confidence: High.  
> Vote Yes or No (open your next turn with that word). Tally completes when participants have spoken.

Hidden specialists do not answer this proposal and do not cast votes. Gather
assent from the people in the room, then enter the visible result through the
local Facilitator input. Open with **Yes** or **No**, or use `<<YES>>` /
`<<NO>>` inline when needed. Remote participant synchronization is unavailable,
so the software does not independently verify remote attendance or ballots.

### Vote tally

Only visible participant/facilitator inputs are eligible for tallying. A generated
specialist contribution is advisory and cannot establish closure. If the
software-visible tally does not faithfully represent the room, use
`/decide [corrected text]` only after the facilitator has confirmed the wording.

### After a capture: the riff window

Immediately after any capture, there is a **4-turn riff window** during which no
new vote is called autonomously. This gives the room space to comment on the
captured item or pivot without that commentary immediately becoming another
proposal.

The facilitator `/vote` command still works inside the riff window.

### If a vote is wrong

If the Session Record calls a vote on a formulation that does not yet reflect the room's actual position, the facilitator can:
- Type `/vote` to call a fresh one after discussion has advanced
- Type `/decide [corrected text]` to override with a direct capture

---

## Recommended live workflow

Use this loop during a session:

1. Let the group discuss the current stage for a few turns.
2. Watch for convergence, productive disagreement, or the group cycling on the same point.
3. Review any Session Record vote proposal; type `/vote` when a proposal is needed
   and none appears.
4. Confirm assent in the room, then enter the visible result as Facilitator.
5. After a decision captures, the Session Record posts the remaining targets and a pivot prompt — the room should move to the next outstanding output.
6. Click `Update Workshop Notes` after meaningful progress to generate reviewable
   proposals from the full log.
7. Accept, edit, reject, or defer every useful proposal; none merge automatically.
8. Preview the complete summary and semantic diff, then explicitly commit a new
   version when the reviewed draft is ready.
9. Before advancing a stage, confirm that the decision record has progressed.
10. When the current stage has done enough work, click `Next`.

**Keep the decision record in view throughout.** After each stage, mentally check: do we have enough decisions, risks, and a deferred question to end the session if we had to stop now?

Do not wait for the AI to manage all pacing on its own. The facilitator decides when a stage has achieved enough — and what counts as "achieved" is producing a contribution to the decision record.

---

## How to force closure on a decision

Use this when the group has reached a workable position but the AI keeps generating qualifications, or when you want to capture something without going through a vote.

### Direct closure commands

```
/decide Market integrity means platforms route patients toward clinically appropriate use and harm is traceable to a person or affected population. Owner: Alice. Confidence: High.
```

```
/risk Patients who hit a dispensing wall will reroute silently to unregulated supply. Likelihood: High. Cost-bearer: patient.
```

```
/defer Is the equity threshold operationally measurable? owner:Samira
```

These write immediately to the decision record, post a Session Record confirmation,
and do not trigger a hidden-specialist turn. The AI treats captured items as
closed in all subsequent turns.

### When to use direct commands instead of the vote system

- The group has reached a workable formulation but keeps adding caveats
- A character keeps "yes, but"-ing rather than assenting
- The stage timer has run out and you need to capture before advancing
- The vote-synthesized formulation doesn't quite match what was actually agreed

The text after the command is stored exactly as written. Include ownership and confidence information inline:

- Good: `/decide We will audit the top 3 platforms within 72 hours. Owner: Gareth. Confidence: High.`
- Also fine: `/risk Grey market entry at the telehealth-to-e-pharmacy handoff. Likelihood: High. Cost: patient.`

Entries do not need to be long. A single clear sentence with named owner or cost-bearer is enough.

---

## How to use buckets

Buckets are the structured notes store for the session.

Current buckets are: `ideas`, `constraints`, `risks`, `decisions`, `open_questions`, `next_steps`

The three buckets that form the decision record are: **decisions**, **risks**, and **open_questions**.

### Two ways to populate buckets

**1. Voting system (automatic, for decisions/risks/deferred questions)**

The voting system captures decisions, risks, and deferred questions directly to their buckets as soon as a majority vote lands. No manual action is needed.

**2. Closure commands (manual override)**

Use `/decide`, `/risk`, and `/defer` to write directly to buckets at any time, bypassing the vote system.

**3. Update Workshop Notes (for supporting context)**

Click `Update Workshop Notes` to run an LLM extraction across the last 40 turns. This is useful for capturing ideas, constraints, and next steps, or for catching near-decisions the voting system may have missed.

For best results, the conversation should have produced explicit statements like:
- **Decision entries**: "We agree that [action], owned by [role], confidence [level]."
- **Risk entries**: "The named risk is [risk], likelihood [level], cost absorbed by [who]."
- **Deferred question entries**: "We cannot settle [question] in this session. [Role] will own it."

The richer the conversation, the richer the extraction. Vague discussion produces vague buckets.

### What buckets contain (and what they don't)

The `constraints` bucket is for **scenario constraints** — institutional, regulatory, or structural limits described inside the workshop content (e.g., "MHRA enforcement reach stops at the regulated boundary"). It is not a workshop-management checklist.

The `next_steps` bucket is for things the participants and owners need to do next — not workshop-meta directions like "capture more decisions" or "propose Decision N".

### Best practice

- Let the vote system capture decisions/risks/deferred questions automatically.
- Use `/decide`, `/risk`, `/defer` when you need immediate override.
- Use `Update Workshop Notes` at the end of each stage to sweep up supporting context.
- **Check the buckets against the decision record target** (3 decisions / 2 risks / 1 deferred) before advancing to the Synthesis stage. The Synthesis stage is for confirming and completing the record, not starting it.

If the buckets remain empty after substantial dialogue, the group is speaking too vaguely. Use a closure command to force the room's best current position onto the record.

---

## How to advance stages well

Advancing stages is a facilitation decision, not just a timer event.

The timer helps with pacing, but the group should usually move on when one of these is true:

- the stage has produced a workable definition or scope boundary
- the same point is being repeated with little new value
- the room has enough material to summarize into outputs
- the timebox has run out and further debate would reduce workshop quality

### Before clicking `Next`

Try to do three things:

1. Name what the group has actually settled.
2. Name what remains unresolved.
3. Name what should be carried into the next stage.

This makes the stage transition more meaningful and improves the quality of both continuity and summary export.

Any unresolved pending vote at stage advance is flagged in the Session Record (Yes/No counts are shown), and the facilitator can capture it manually with `/decide` if appropriate.

---

## How to use facilitator notes

Facilitator notes are useful when you want to inject structure without consuming a role turn.

Use note-only mode for:

- clarifying an assumption
- freezing a definition
- naming the question the room should answer next
- reminding the group of the required output for the stage

Example note-only prompts:

- `Note: treat harm displacement into grey-market channels as in scope for this stage.`
- `Note: before advancing, capture one decision, one risk, and one open question.`
- `Note: ask the group for a concrete threshold rather than another general concern.`

Use `Send as Facilitator (visible to AI)` when you want the AI to treat your intervention as part of the live workshop rather than as a silent structural note.

---

## How the Session Record steers the room

The Session Record is a system voice that runs throughout the session. It is not a participant — it does not debate or deliberate. It posts:

- **Progress flags**: "No decisions captured yet. N turns elapsed."
- **Stage starts/advances**: what the record looks like at each transition.
- **Time warnings**: 20, 10, and 5 minutes remaining.
- **Vote proposals**: the PROPOSAL entries that trigger Yes/No voting.
- **Capture confirmations**: "Decision captured (Yes): …" with remaining targets named.
- **Analytical observations**: LLM-generated session-state summaries at longer intervals.

Session Record entries do not trigger hidden-specialist votes or additional
visible assistant messages. Each normal facilitator turn produces one synthesized
Session Record response; technical and specialist messages remain silent.

---

## How hidden synthesis supports closure

Workshop Catalyst uses one batched specialist analysis operation, then synthesizes
the result into the Session Record voice. The specialists may surface:

- competing risks and feasibility concerns
- institutional pressures and missing assumptions
- possible formulations or paths for facilitator review

These contributions remain advisory, collapsed by default, and revocable from
view. They do not vote, commit map items, alter the Session Record, or establish
closure. The facilitator must still review proposals and use visible vote or
commit actions.

---

## How to prevent the AI from cornering one participant

If the AI keeps pressing the same participant:

1. Pause the stage if needed.
2. Add a facilitator note or facilitator-visible message that asks for synthesis.
3. Ask for one explicit decision or wording from the pressured participant.
4. Redirect to another role for implications, risks, or operational consequences.

Useful interventions:

- `Facilitator: summarize the current disagreement in one sentence, then ask another role for the operational implication.`
- `Facilitator: we have enough pressure on this point; turn it into two options and one decision question.`
- `Facilitator: move from challenge to synthesis and tell us what belongs in the TOR.`

---

## How to test and use continuity

There are two forms of continuity to know about.

### 1. Resume a prior session directly

Use this when you want to continue a previous session with its transcript and workshop state.

Recommended flow:

1. Run a session with some meaningful discussion.
2. Update buckets at least once.
3. Advance at least one stage if possible.
4. Export the workshop summary.
5. Later, start again and load the previous session log.

What to expect:

- prior transcript appears again
- workshop state is restored from the matching workshop sidecar
- resume metadata should indicate that this is a continuation

### 2. Start a new session with cross-session continuity

Use this when you want a fresh session that still remembers prior work through the continuity system.

Recommended test:

1. End a substantive session cleanly.
2. Start a new session of the same scenario without manually loading the old log.
3. Ask the AI to restate what seems previously settled and what remains unresolved.

What to expect:

- the AI should carry forward important prior decisions or tensions
- it should not replay the whole old transcript
- it should behave like a continued workshop context, not total amnesia

---

## Exporting a useful summary

Use `Export Workshop Summary` after:

- a solid stage boundary
- a meaningful checkpoint in a multi-day workshop
- the end of a session

The summary is only as useful as the captured buckets and stage progress.

For a better summary, make sure you have:

- at least one bucket update
- at least one stage advance when appropriate
- some clear decisions or open questions in the transcript

The exported summary includes the full decision record (decisions with owners and confidence, risks with likelihood and cost-bearer, deferred questions with owners and reason for deferral), supporting notes (ideas, constraints, next steps), and a stage history snapshot.

---

## Suggested minimum good session

If you are new to the system, aim for this minimum viable session:

1. Start the scenario and set the duration.
2. Start the Kickoff stage. Discuss the working definition of the scenario's key
   term. Review a Session Record proposal, or type `/vote` to request one, then
   record only the result confirmed by the room.
3. Advance to the Baseline Map stage. Get the room to name the two highest-risk
   handoffs, review the proposed capture, and record visible assent.
4. Introduce one Stress Injection. Push for at least one concrete action
   statement; use `/decide` only after the facilitator confirms the wording.
5. Advance to Synthesis. Confirm what has been decided and what is being consciously deferred. Use `/defer [the unresolved question] owner:[role]` if the system hasn't already captured it.
6. Export the summary.

A session is successful if the exported summary shows at least one decision with an owner, one named risk, and one deferred question. That is enough to build on in a follow-up session.

**Do not try to produce a comprehensive strategy document in one session. Produce the decision record first.**

---

## Manual acceptance checklist

The automated integration suite does not certify hardware, projection, focus,
acoustics, or full human interaction quality. Before pilot or production use,
complete this checklist on the intended room setup:

- [ ] Select Workshop Catalyst → Decision Triage before launch; confirm character
  selection is bypassed and the local identity reads **Facilitator**.
- [ ] At the intended projector resolution, inspect Show Chat, Map, Review, Full
  Dashboard, and Custom layouts for readability, clipping, overlap, and dialog
  placement.
- [ ] In every preset, confirm recording/listening state, consent, connection and
  transcription errors, uncommitted-change warnings, and **End & Save** remain
  visible.
- [ ] Traverse every visible control by keyboard; confirm focus order and focus
  indication are clear, editable fields are reachable, and dialogs can be
  dismissed without a pointer.
- [ ] On the target microphone and audio device, verify permission prompts, device
  selection, recording/stop/cancel/re-record, acoustic STT quality, transcript
  editing, and the no-auto-send guarantee.
- [ ] Verify audible playback uses only the Session Record in Workshop Catalyst;
  specialist, facilitator, and technical messages remain silent.
- [ ] Exercise timer, agenda, pause/advance, stress injection timing, and
  facilitator-reviewed bucket extraction in a real preselected session.
- [ ] Run one session from a Scenario you created rather than an authored
  template; confirm each stage presents a usable required output and
  decision-forcing question, and that the six-stage default agenda paces
  sensibly at the chosen duration.
- [ ] Judge whether the assistant is working the cross-checks: does it raise who
  bears the cost, what gets displaced, and which option fails on feasibility
  without being asked? Note any turn where it restated agreement instead.
- [ ] Review, edit, reject, defer, preview, commit, and retry one Session Record,
  Thinking Map, and Compare Paths proposal; confirm lineage and degraded-state
  messages are understandable to the facilitator.
- [ ] Confirm local participant status is readable; Invite requests no contact
  details; Plans and Progress remain clearly labelled **coming soon**.
- [ ] Sweep all dynamic proposal/map/path controls and hardware-dependent states;
  every visible action must work or resolve to a clearly labelled unavailable
  state.
- [ ] Verify same-session resume, opt-in continuity, End & Save, summary export,
  and decision-record export with representative workshop data.

Keep these items open until witnessed on real target hardware. Automated checks
are evidence for parser, contract, routing, and deterministic UI behavior only.

---

## Troubleshooting

### The session log looks empty

Check the runtime location rather than the project folder. Session files are written to `Documents/Synesyn/scensyn/story_logs/`: the workshop summary as a `.md` file, with its state in a matching `.workshop.json` sidecar. Artifacts held by the hub are separate, under `Documents/Synesyn/Workspaces/<workspace>/artifacts/`. See [Privacy and data](privacy-and-data.md) for what is stored where.

### Every turn says "I could not retain a reliable specialist analysis"

The four lenses need a structured response. Workshop Catalyst first asks for the
full package in one call; if that fails to parse, it retries with a smaller
roles-only call and then a synthesis call. You still see this fallback when the
model cannot complete even the roles step. Your input is retained, and anything
you stated plainly can still reach the Thinking Map.

Check for this line in a setup run before a live room. If it appears on every
turn, switch to a model that can produce structured JSON — not because Workshop
Catalyst pins a model, but because the analysis cannot invent what the model
did not return.

### Buckets are empty

Usually this means:

- neither `Update Workshop Notes` nor closure commands (`/decide`, `/risk`, `/defer`) were used
- the discussion has remained too vague for LLM extraction
- the session did not yet produce capture-ready outputs

Use `/decide` or `/risk` to force at least one entry immediately, then use `Update Workshop Notes` to sweep for anything else.

### No vote was called even though the room agreed

Type `/vote` to request a visible proposal, or use `/decide [text]` after the
facilitator has confirmed the group's exact wording. Never infer assent from the
hidden specialist trace.

### The vote keeps triggering on the same material

This should not happen with current code — a 4-turn capture cooldown prevents re-triggering immediately after any capture. If it recurs:

- Use `/decide` to force-capture the pending item and move on
- The `/vote` command itself always works even inside a cooldown

### The AI keeps circling the same participant

Use a facilitator intervention to force synthesis, then redirect another role into the conversation.

### Continuity seems missing

Test both forms separately:

- direct resume by loading a prior session
- fresh continuity by starting a new session without loading the old transcript

### The timer ended but the workshop did not move on

This is expected. The facilitator decides when to advance.

---

## Facilitation posture

The best results usually come from a simple posture:

- keep the decision record in view throughout the session
- let the AI generate useful pressure and surface constraints
- use vote proposals as review aids, not as proof that the room consented
- convert pressure into explicit decision statements (name the decision, name the owner, name the confidence level)
- move on before repetition takes over
- park unresolvable questions cleanly — with an owner — rather than letting them drift

**The test at the end of every stage:** does the decision record have something in it that was not there before this stage?

Workshop Catalyst works best when the facilitator treats it as a disciplined co-facilitator whose primary job is to help the group leave with decisions, not to produce an elegant discussion.
