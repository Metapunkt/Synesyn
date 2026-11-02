"""
SYNTREE ARCHITECTURE GUIDE

Component Responsibilities:
---------------------------
- ContentBus: Central event bus for cross-component communication
- ContentModel: Data management and business logic
- ContentViewManager: UI view switching and display logic
- SyntreePanel: Main container and coordination

Communication Patterns:
----------------------
✅ SyntreePanel -> ContentViewManager: Direct reference passing
✅ Components -> ContentBus: Signal-based communication
✅ ContentBus -> Components: Signal handlers
❌ Direct node searches across components (e.g., find_node, get_node)

Reference Management:
-------------------
✅ Pass references through constructor/setup methods
✅ Store references in properly named variables
❌ Search for nodes outside component boundaries

Development Guidelines:
---------------------
1. AVOID REGRESSION: Ensure changes don't break existing functionality
   - Maintain view switching/button visibility behavior
   - Preserve existing signal connections
   - Test all view modes after making changes

2. REDUCE REDUNDANCY: Leverage existing infrastructure
   - Reuse existing methods rather than creating duplicates
   - Check if functionality already exists in ContentBus/ContentModel
   - Place new code in appropriate component based on responsibility

3. MAINTAIN SIMPLICITY: Keep code clean and maintainable
   - Avoid overly complex solutions when simpler ones suffice
   - Don't add unnecessary abstraction layers
   - Keep method and class sizes reasonable

4. RESPECT COMPONENT BOUNDARIES: Follow the established architecture
   - UI logic belongs in view components
   - Data management belongs in ContentModel
   - Cross-component communication goes through ContentBus
   - Container/coordination logic belongs in SyntreePanel

Extension Patterns:
-----------------
- Add new view types by extending ContentViewManager with new view methods
- Add new content source types by extending ContentModel parsers
- Add new graph node types by creating new scene inheriting from ContentSourceGraphNode
- Add new signals to ContentBus for new cross-component events

Error Handling:
-------------
- Use NotificationManager (utils/notification_manager.gd) for user-facing notifications
- Use dedicated error handlers in utils/error_handling/ for structured error management
- Component-level errors should use appropriate error classes from error_handling/
- Log technical errors using push_error() for debugging
- Cross-component errors should be communicated via ContentBus to NotificationManager
- For UI components, emit show_error_requested signal to bubble errors up to notification display

Performance Considerations:
------------------------
- Defer heavy operations when UI responsiveness is important
- Batch updates to prevent multiple UI refreshes
- Cache frequently accessed data
- Use signals for asynchronous operations rather than polling

Documentation Preservation:
-------------------------
- Interface headers (COMPONENT, RESPONSIBILITY, etc.) must NOT be removed or modified without explicitly changing the component's architecture
- ARCHITECTURE-BOUNDARY comments serve as critical guardrails and should be preserved across code changes
- When making changes to a file, always retain these architectural markers unless specifically directed to modify them
- If architectural boundaries must change, update both the code AND the corresponding documentation

## Graph View System

The graph view system visualizes content nodes and their relationships. It consists of:

1. ContentGraphController: Manages the graph view and node connections
2. ContentSourceGraphNode: Visual representation of content nodes
3. GraphEdit: Godot's built-in graph editing control

### Connection Workflow

The graph connection system follows a specific workflow to ensure proper visualization:

1. Node Creation:
   - Instantiate ContentSourceGraphNode for each content node
   - Set basic properties (node_id, node_data, content, path)
   - Add nodes to the scene tree

2. UI Update:
   - Call update_ui_from_data() on each node after adding to tree
   - This updates all UI elements and initializes connection slots
   - Slots are configured based on relationship data (parents/children)

3. Connection Creation:
   - Create connections between nodes using GraphEdit.connect_node()
   - Use slot index 0 for all connections
   - Connections are made from parent's output slot to child's input slot
   - Force graph update after all connections are created

### Important Implementation Details

- Nodes must be added to the scene tree before UI update
- Slots must be initialized based on relationship data
- All connections use slot index 0
- The graph must be updated after all connections are created
- Relationship data structure: {"parents": [], "children": [], "dependencies": []}

## Content Source Selection Flow

The content source selection follows a strict single-channel pattern:

1. Selection Origin:
   - ContentSourceItem handles the select checkbox toggle
   - Emits directly to ContentBus.source_selected

2. Selection Broadcasting:
   - ContentBus.source_selected signal is the single source of truth
   - All components needing selection state listen to ContentBus

3. Selection Handling:
   - ContentViewManager updates UI state and button visibility
   - Other components can listen to ContentBus.source_selected as needed

This ensures consistent selection state across the application and prevents
duplicate or conflicting selection handling.

## View State Management

The view state management follows a strict pattern:

1. View State Source of Truth:
   - ContentBus maintains the single source of truth for current view mode
   - ContentBus.request_view_change() is the only way to change views
   - View changes are broadcast through ContentBus.view_changed signal

2. View Button Visibility Rules:
   - List View:
     * List button: Hidden (current view)
     * Hierarchy button: Visible and enabled only when source selected
     * Graph button: Hidden
   
   - Hierarchy View:
     * List button: Visible
     * Hierarchy button: Hidden (current view)
     * Graph button: Visible and enabled
   
   - Graph View:
     * List button: Visible
     * Hierarchy button: Visible and enabled
     * Graph button: Hidden (current view)

3. View UI Updates:
   - ContentViewManager._update_view_ui_for_mode handles all UI updates
   - View type label shows current view and source context
   - Button states are updated through _update_button_states
   - View visibility is managed centrally

This ensures consistent view state transitions and UI feedback across the application.

## Metaprompt State Management

The metaprompt state follows a centralized state management pattern with source-specific persistence:

1. State Source of Truth:
   - ContentBus maintains the runtime source of truth for metaprompt state
   - ContentBus.set_source_metaprompt() is the only way to change state
   - Changes are broadcast through ContentBus.metaprompt_state_changed signal

2. View Updates:
   - List View: Checkbox in ContentSourceItem
   - Hierarchy View: Visual state in hierarchy items
   - Graph View: Node appearance in ContentSourceGraphNode

3. State Flow:
   [Any View] -> ContentBus.set_source_metaprompt()
                 -> ContentModel.update_source()
                 -> ContentBus.metaprompt_state_changed
                 -> All views update
                 -> Source data saved

4. Source-Specific Persistence:
   - Each content source saves its complete state
   - Changes are saved with the source's other data
   - State is restored when source is loaded

This ensures consistent metaprompt state across views while maintaining source independence.
""" 