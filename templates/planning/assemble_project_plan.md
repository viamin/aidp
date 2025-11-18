# Assemble Complete Project Plan

You are creating the master PROJECT_PLAN.md document that integrates all planning artifacts.

## Input Files

Read all generated artifacts:

- `.aidp/docs/PRD.md` - Product requirements
- `.aidp/docs/TECH_DESIGN.md` - Technical design
- `.aidp/docs/WBS.md` - Work breakdown structure
- `.aidp/docs/GANTT.md` - Gantt chart and critical path
- `.aidp/docs/TASK_LIST.md` - Detailed task list
- `.aidp/docs/persona_map.yml` - Persona assignments

## Your Task

Assemble everything into a comprehensive, integrated project plan document.

## Project Plan Structure

```markdown
# Project Plan

Generated: <timestamp>

## Executive Summary
[Brief overview of the project and plan]

## Work Breakdown Structure
[Include WBS content]

## Timeline and Gantt Chart
[Include Gantt chart with Mermaid visualization]

## Critical Path
[List critical path tasks]

## Persona Assignments
[Summary of task assignments by persona]

## Metadata
- Total Phases: X
- Total Tasks: Y
- Critical Path Length: Z tasks
- Personas Used: N

## References
- [PRD](./PRD.md)
- [Technical Design](./TECH_DESIGN.md)
- [Task List](./TASK_LIST.md)
- [Persona Map](./persona_map.yml)
```

## Assembly Guidelines

1. **Integrate all artifacts** - Combine WBS, Gantt, personas into one document
2. **Maintain structure** - Preserve hierarchies and relationships
3. **Add cross-references** - Link related sections
4. **Include metadata** - Counts, timestamps, generation info
5. **Format consistently** - Use consistent markdown styling

## Implementation

**For Ruby/AIDP projects**, use the `ruby_aidp_planning` skill to:

1. Parse all input documents using `Aidp::Planning::Parsers::DocumentParser`
2. Use `Aidp::Planning::Builders::ProjectPlanBuilder` to orchestrate assembly
3. Call `assemble_project_plan(components)` with all artifacts
4. Write to `.aidp/docs/PROJECT_PLAN.md`

The skill provides the complete Ruby implementation including:

- Document parsing and loading
- Component assembly and integration
- Markdown formatting
- Metadata calculation
- File output operations

**For other language implementations**, implement equivalent functionality:

1. Read and parse all input markdown files
2. Extract key information from each:
   - WBS: phases, tasks, estimates
   - Gantt: timeline, critical path
   - Personas: task assignments by role
3. Assemble into single structured document:
   - Executive summary
   - Full WBS content
   - Gantt visualization
   - Critical path list
   - Persona assignments grouped by persona
   - Metadata and statistics
4. Format as markdown with proper headings and structure
5. Write to output file

## Output

Write the complete, integrated project plan to `.aidp/docs/PROJECT_PLAN.md`

This serves as the single source of truth for project planning.

## Quality Checks

Ensure the assembled plan includes:

- ✅ All phases from WBS
- ✅ All tasks with dependencies
- ✅ Gantt chart visualization
- ✅ Complete critical path
- ✅ Every task assigned to a persona
- ✅ Accurate metadata counts
- ✅ Cross-references to source documents
