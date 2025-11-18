# Generate Gantt Chart and Critical Path

You are creating a Mermaid Gantt chart with critical path analysis.

## Input

Read `.aidp/docs/WBS.md` - Work breakdown structure with tasks and dependencies

## Your Task

Generate a Gantt chart in Mermaid format showing timeline, dependencies, and critical path.

## Gantt Chart Components

1. **Timeline** - Task durations and sequencing
2. **Dependencies** - Task relationships ("after" clauses)
3. **Critical Path** - Longest sequence of dependent tasks
4. **Phase Sections** - Group tasks by project phase

## Critical Path

The critical path represents the longest sequence of dependent tasks. Any delay in critical path tasks delays the entire project.

Critical path tasks should be highlighted in the visualization.

## Gantt Features

- Phase-based sections
- Task dependencies (after relationships)
- Critical tasks highlighted
- Relative durations based on effort estimates

## Duration Calculation

Convert effort estimates to time:
- Story points → days (e.g., 1 story point = 0.5 days)
- Minimum duration = 1 day
- Account for dependencies when calculating start dates

## Implementation

**For Ruby/AIDP projects**, use the `ruby_aidp_planning` skill to:

1. Load WBS using `Aidp::Planning::Parsers::DocumentParser`
2. Generate Gantt chart using `Aidp::Planning::Generators::GanttGenerator`
3. Calculate critical path
4. Format as Mermaid syntax
5. Write to `.aidp/docs/GANTT.md`

The skill provides the complete Ruby implementation including:
- WBS parsing and task extraction
- Duration calculation algorithms
- Critical path analysis (longest dependency chain)
- Mermaid format generation
- File output operations

**For other language implementations**, implement equivalent functionality:

1. Parse WBS to extract tasks and dependencies
2. Calculate task durations from effort estimates
3. Build dependency graph
4. Find critical path (longest path through dependencies)
5. Generate Mermaid gantt syntax with proper formatting
6. Highlight critical path tasks

## Mermaid Gantt Syntax

```
gantt
    title Project Timeline
    dateFormat YYYY-MM-DD
    section Phase Name
    Task Name :status, task_id, duration
    Task with dependency :status, task_id, after other_task, duration
```

## Output

Write Gantt chart with critical path to `.aidp/docs/GANTT.md` including:
- Mermaid visualization (in code block)
- Critical path task list
- Timeline metadata
- Generation timestamp
