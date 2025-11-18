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

Use the ProjectPlanBuilder to assemble everything into a comprehensive project plan.

## Implementation

```ruby
require_relative '../../../lib/aidp/workflows/waterfall/project_plan_builder'
require_relative '../../../lib/aidp/workflows/waterfall/document_parser'

# Load all artifacts
parser = Aidp::Workflows::Waterfall::DocumentParser.new
prd = parser.parse_file('.aidp/docs/PRD.md')
tech_design = parser.parse_file('.aidp/docs/TECH_DESIGN.md')

# Build plan (assuming components already generated)
ai_engine = get_ai_decision_engine  # Get configured AI engine
builder = Aidp::Workflows::Waterfall::ProjectPlanBuilder.new(
  ai_decision_engine: ai_engine
)

# Read existing components
wbs_markdown = File.read('.aidp/docs/WBS.md')
gantt_content = File.read('.aidp/docs/GANTT.md')
persona_map = YAML.load_file('.aidp/docs/persona_map.yml')

components = {
  prd: prd,
  tech_design: tech_design,
  wbs_markdown: wbs_markdown,
  gantt_mermaid: extract_mermaid_from_gantt(gantt_content),
  critical_path: extract_critical_path(gantt_content),
  persona_assignments: persona_map
}

# Assemble complete project plan
project_plan = builder.assemble_project_plan(components)

File.write('.aidp/docs/PROJECT_PLAN.md', project_plan)
```

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

## Output

Write the complete, integrated project plan to `.aidp/docs/PROJECT_PLAN.md`

This serves as the single source of truth for project planning.
