# ReadyMade: An Agentic Content Creation System

## 1. Core Purpose

**ReadyMade** is an application layer built within the Godot Engine to orchestrate a semi-automated content creation workflow. It is designed to implement the "Found Concepts" framework by providing a human operator with a powerful cognitive partner.

The system manages a 6-month content strategy, turning it into a live, interactive workplan. Agents within this system handle the heavy lifting of research, synthesis, and adaptation, while the human operator retains full control over final validation, creative production, and publishing.

## 2. Architecture

ReadyMade is designed as a clean, self-contained system that sits on top of the existing addon stack.

- **Application Layer:** ReadyMade is an application, not a framework. It lives entirely within the `readymade/` directory.
- **One-Way Dependency:** It consumes the APIs provided by the `Metapunkt`, `LimboAI`, and `SynTree` addons but **never** modifies them.
- **Orchestration Client:** It acts as a client to the `Metapunkt` orchestration layer, using its services (for agents, tools, memory, etc.) as intended.
- **Central Singleton:** The `ReadyMadeOrchestrator` (`/root/ReadyMadeOrchestrator`) is the global singleton that manages application state, primarily the loading and saving of the workplan.

## 3. Key Components

- **`data/workplan.tres`**: The single source of truth for the entire content strategy. This is a custom `Workplan` resource that contains an array of `WorkplanTask` resources for each month.
- **`scripts/singletons/ReadyMadeOrchestrator.gd`**: The global controller that loads the workplan and provides functions for accessing and modifying it.
- **`ui/mission_control_dashboard.tscn`**: The main user interface for the human operator. It visualizes the data from `workplan.tres` and will serve as the primary interaction point with the system.
- **`readymade_main.tscn`**: The main scene and entry point for the ReadyMade application.

## 4. How to Run

To launch the ReadyMade application, run the `readymade/readymade_main.tscn` scene from the Godot editor.

## 5. User Guide

### Work Mode System

ReadyMade supports different work modes that adapt the interface and AI behavior to your current focus:

**Available Modes:**
- **📱 Social Media Focus**: Optimized for social content creation with engagement metrics
- **🎭 Creative Writing Focus**: Tailored for narrative development and character work  
- **🎓 Academic Writing Focus**: Configured for scholarly research and citation management

**Mode Features:**
- **Mode Selector**: Choose your current work mode from the dropdown in the left panel
- **Mode-Aware Task Templates**: New tasks show templates relevant to your selected mode
- **Adaptive AI Prompting**: AI agents use mode-specific prompts for better content generation
- **Smart Content Analysis**: Content viewer shows metrics relevant to your current mode
- **Persistent Preference**: Your mode selection is saved and restored between sessions

**Mode-Specific Templates:**

*Social Media Mode:*
- Instagram Post - Visual content with engagement focus
- Twitter Thread - Multi-tweet storytelling
- Content Calendar Entry - Cross-platform planning
- Hashtag Research - Trend analysis and optimization

*Creative Writing Mode:*
- Character Profile - Detailed character development
- Scene Draft - Complete scenes with dialogue
- Chapter Outline - Story structure planning
- Plot Development - Narrative arc creation

*Academic Writing Mode:*
- Research Note - Source documentation with citations
- Literature Review Section - Critical analysis synthesis
- Citation Check - Reference verification
- Thesis Section - Scholarly argument development

**Content Analysis by Mode:**

*Social Media Analytics:*
- Character count and platform suitability
- Hashtag analysis and engagement scoring
- Content optimization suggestions

*Creative Writing Analytics:*
- Reading time estimates and pacing analysis
- Dialogue distribution and narrative flow
- Character focus and development tracking

*Academic Writing Analytics:*
- Citation count and reference quality
- Academic tone strength assessment
- Argument structure analysis

### Task Management

**Creating Tasks:**
- Click "New Task" button or press `Ctrl+N`
- Fill out the task creation dialog with title, format, channel, priority, and dates

**Mode-Aware Task Dialog:**
The task creation dialog now adapts to your current work mode, showing only relevant options:

*Social Media Mode Format Options:*
- Video, Image(s), Carousel, Short Text
- Live Stream, Stories, Reels, Infographic

*Social Media Mode Channel Options:*
- Instagram, TikTok, YouTube, Twitter/X
- Facebook, LinkedIn, Snapchat, Pinterest

*Creative Writing Mode Format Options:*
- Novel Chapter, Short Story, Script/Screenplay, Poetry
- Blog Post, Character Profile, Scene Outline, Dialogue

*Creative Writing Mode Channel Options:*
- Publishing Platform, Literary Blog, Writing Portfolio
- Medium, Wattpad, AO3, Goodreads, Literary Journal

*Academic Writing Mode Format Options:*
- Research Paper, Literature Review, Thesis Chapter
- Conference Abstract, Journal Article, Research Proposal
- Citation Analysis, Academic Blog Post

*Academic Writing Mode Channel Options:*
- Academic Journal, Conference Proceedings, University Repository
- ResearchGate, Academia.edu, ORCID Profile
- Institutional Website, Peer Review Platform

**Benefits:**
- **Reduced Cognitive Load**: Only see options relevant to your current work
- **Mode-Specific Defaults**: Smart defaults based on your selected mode
- **Dynamic Updates**: Options update automatically when you switch modes
- **Backward Compatibility**: Existing tasks continue to work unchanged

**Mode Filtering Toggle:**
Each format and channel section includes a "🎯 Mode Filter" toggle that lets you:
- ✅ **Enabled (Default)**: Shows only options relevant to your current work mode
- ❌ **Disabled**: Shows all available options for maximum flexibility

**Strategy Tab Mode Awareness:**
The Strategy tab now provides mode-specific guidance:

*Social Media Strategy Focus:*
- Hook attention in first 3 seconds
- Use trending hashtags and platform-specific formats  
- Optimize for platform algorithms (timing, engagement)
- Include clear call-to-action for audience interaction
- Consider visual appeal and mobile-first design

*Creative Writing Strategy Focus:*
- Develop compelling characters with clear motivations
- Build engaging narrative structure and pacing
- Use vivid imagery and emotional resonance
- Consider target audience and genre conventions
- Focus on authentic voice and unique perspective

*Academic Writing Strategy Focus:*
- Present clear thesis and logical argument structure
- Use credible sources and proper citations
- Maintain objective, scholarly tone
- Follow discipline-specific formatting guidelines
- Ensure methodological rigor and evidence-based claims

**Task List Operations:**
- **New Task List**: `Ctrl+L` - Clear selection to start a new task list
- **Save Task List**: `Ctrl+S` - Save selected tasks to current or new file
- **Save As**: `Ctrl+Shift+S` - Save selected tasks to a new file
- **Open Task List**: `Ctrl+O` - Load task list (see Import Behavior below)
- **Select All**: `Ctrl+A` - Toggle selection of all visible tasks
- **View All Tasks**: `Ctrl+V` - Clear filters and show all workplan tasks

**Task List Import Behavior:**
When loading a task list in a different workplan:
- If tasks match existing ones → **Filter View**: Show matching tasks only
- If no tasks match → **Import Choice Dialog** with options:
  - **Import Tasks**: Copy tasks from list into current workplan + show filtered view
  - **Filter Only**: Show empty filter (tasks don't exist in current workplan)
  - **Cancel**: Exit without changes

### Workplan Management

**Workplan Operations:**
- **Workplan Manager**: `Ctrl+W` - Open workplan management dialog
- **Switch Workplans**: Use dropdown in left panel
- **Create New Workplan**: Via workplan manager dialog
- **Duplicate Workplan**: Copy existing workplan with new name
- **Rename/Delete**: Manage existing workplans
- **Import/Export**: Share workplans as `.tres` files

### Calendar Features

**Date Management:**
- **Drag & Drop**: Drag task cards between calendar days to change dates
- **Context Menu**: Right-click task cards for quick actions
- **Overflow Popup**: Click "+X more" to see all tasks for busy days
- **Navigation**: Use month/year selectors or "Today" button

### Keyboard Shortcuts

- `Ctrl+N` - New Task
- `Ctrl+R` - Refresh Dashboard  
- `Ctrl+S` - Save Task List
- `Ctrl+Shift+S` - Save Task List As
- `Ctrl+O` - Open Task List
- `Ctrl+L` - New Task List
- `Ctrl+A` - Select/Deselect All Tasks
- `Ctrl+V` - View All Tasks (Clear Filter)
- `Ctrl+W` - Workplan Manager
- `Ctrl+Q` - Stop Agent Processing
- `F5` - Refresh Dashboard

### Agent Operations

**AI Processing:**
- **Start Agent**: Begin batch processing of all available tasks
- **Stop Agent**: `Ctrl+Q` - Halt agent processing
- **Individual Task Processing**: Use "Start" button on specific tasks

### Content Viewer

The Content Viewer tab displays all tasks with generated content, allowing you to:
- Review AI-generated content
- Edit content directly
- Navigate between completed tasks

### Edit Session Workflow

ReadyMade 5.2 introduces **Edit Sessions** – a live workspace where you can load **multiple documents at once**, lazily stream large files, and generate optimised context windows for AI agents.

Key concepts:
• **Document Context** – Every document is broken into 50 KB chunks and only the chunks you view (or the AI needs) are loaded into memory.
• **Context Mode Selector** – Choose between:
  1. **Single Document** – Only the active document is sent to the AI.
  2. **All Documents** – Merge all open documents into one large context window (up to your selected token limit).
  3. **Auto Context** – ReadyMade automatically selects the most relevant document(s) based on your prompt and available context budget.
• **Context Window Limit** – Set a global token budget (default **8 000 tokens**) so the system never sends more text than your LLM can handle.
• **Session Performance Panel** – Shows real-time metrics (loaded chunks, processing times, memory footprint) so you can see exactly what the optimiser is doing.

**Basic Workflow**
1. Load one or more documents with **Load Document** / **Load from Text**.
2. Use the **Context Mode** dropdown in the left panel to pick your scope.
3. Edit or review content; ReadyMade lazily loads chunks on demand.
4. Trigger an AI action (rewrite, summarise, etc.) – the optimiser assembles a context window and streams it to the model.
5. Monitor performance in the dashboard.

### Multi-Document Sessions

You can open as many documents as you like. The session manager:
• Keeps track of which document is **Primary** (🎯 Set Primary).
• Computes cross-document links (citations, references) and shows them in the **Relationships** panel.
• Allows per-document or batch AI operations.

### Edit Modes

Use the **Edit Mode** selector to switch the UI & agent prompts between:
• **Drafting** – Focus on generating new content.
• **Revising** – Emphasise structure, tone, and consistency checks.
• **Proofreading** – Prioritise grammar, spelling, and citation validation.

### Troubleshooting

See `readymade/TROUBLESHOOTING.md` for common issues (lazy-loading glitches, splitter layout problems, export errors, etc.).
