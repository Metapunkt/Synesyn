# SynTree Architecture 2.0: Resource-Based Framework

## Context

SynTree is transitioning from a signal-based to a resource-based architecture to address several critical issues:

1. Recursive signal chains causing stack overflows
2. Complex initialization order dependencies 
3. Difficult state synchronization across views
4. Hard-to-debug state management issues

## Core Resource Types

### ViewStateResource

A centralized resource that tracks and manages view state:
- Current view mode (LIST, HIERARCHY, GRAPH)
- Currently selected source(s)
- View state history
- Selection state  

### ContentSourceResource

The source of truth for content data:
- Source data storage (Dictionary mapping IDs to data)
- Node-to-source mapping
- Normalized ID management
- Source data validation
- Metaprompt state for each source
- Source metadata management

### GraphStateResource

Manages graph view state:
- Node positions in graph view
- Graph zoom and scroll state
- Visibility of nodes

## Component Responsibilities

### Resources
- **Single source of truth** for all state
- **Self-validating** when state changes
- **Emit changed signal** when modified
- **Handle serialization** for persistent data

### Views
- **Read from Resources** for rendering
- **Never modify Resources directly**
- **Send user actions** to Services
- **Subscribe to Resource changes** for updates

### Services
- **Modify Resources** in response to requests
- **Implement business logic**
- **Coordinate across Resources**
- **Handle validation** before state changes

## Communication Pattern

```
[User Action] → [View] → [Service] → [Resource] → [Views update]
```

- Views observe Resources through their `changed` signals
- Services modify Resources based on user actions or other events
- All components access the same Resource instances
- No signals between components except Resource.changed

## Persistence Model

- Resources provide serialization methods
- Serialized data matches JSON structure of existing files
- ContentSourceResource handles both in-memory and on-disk state
- A persistence service mediates writing to disk

## Migration Approach

### Phase 1: Parallel Architecture
- Resource-based and signal-based systems coexist
- All updates flow through both systems
- Views can choose which system to use for rendering

### Phase 2: View Migration
- One view at a time transitions to resource-based rendering
- Each view validates output matches existing behavior
- Gradually increase resource-based dependence

### Phase 3: Signal Deprecation
- Remove redundant signals
- Simplify view logic to only use resources
- Clean up legacy code paths

## Implementation Guidelines

### Resource Management
- Resources are referenced, not duplicated
- Resources extend Godot's Resource class
- Resources use strong typing with @export
- Resources validate their own state

### Service Design
- Services are stateless
- Services only modify Resources, never UI
- Services validate inputs before modifying Resources
- Services provide clear, focused APIs

### View Principles
- Views never directly modify Resources
- Views update in response to Resource changes
- Views send requests to Services
- Views minimize internal state

## Testing Approach

- Resources: Unit test state changes and serialization
- Services: Unit test business logic
- Views: Test rendering from mock Resources
- End-to-end: Test through full stack with real Resources

## Architecture Benefits

1. **Stability**
   - No signal recursion
   - Clear state ownership
   - Type-safe state updates

2. **Developer Experience**
   - Resource inspection in editor
   - Built-in undo/redo support
   - Clear data flow

3. **Maintainability**
   - Centralized state management
   - Easier testing
   - Better separation of concerns 
