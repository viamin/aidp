# Waterfall Planning Mode - User Guide

## Overview

Waterfall Planning Mode provides structured, comprehensive project planning with automatic generation of work breakdown structures, Gantt charts, and task assignments.

**When to use Waterfall Mode:**

- You need a complete project plan before starting implementation
- You want to visualize timelines and dependencies
- You need to coordinate multiple team members/personas
- You want to track critical path and identify bottlenecks
- You're working on complex projects with multiple phases

## Quick Start

```bash
# Start AIDP in Execute mode
aidp

# Select "Waterfall Planning" workflow
# Follow the prompts to:
# 1. Choose ingestion (existing docs) or generation (from scratch)
# 2. Provide requirements or documentation paths
# 3. Review and refine generated artifacts
```

## Two Planning Paths

### Path 1: Documentation Ingestion

**Use when:** You have existing PRDs, design docs, or task lists

```bash
# Waterfall mode will ask:
Do you have existing documentation? YES

# Provide paths:
- PRD: ./docs/product_requirements.md
- Design: ./docs/technical_design.md
- Tasks: ./docs/backlog.md
```

**What happens:**

1. AIDP parses your existing documents
2. Identifies gaps and missing information
3. Asks clarifying questions to fill gaps
4. Generates WBS, Gantt chart, and assignments from your docs

### Path 2: Generation from Scratch

**Use when:** Starting a new project with no documentation

```bash
# Waterfall mode will ask:
Do you have existing documentation? NO

# Then walks you through:
1. Problem statement
2. Goals and success criteria
3. Stakeholders and constraints
4. Technical approach
```

**What happens:**

1. AI-guided requirements elicitation
2. Generation of PRD and technical design
3. Automatic WBS and Gantt chart creation
4. Intelligent task-to-persona assignments

## Generated Artifacts

All artifacts are created in `.aidp/docs/`:

### 1. PRD.md - Product Requirements Document

Contains:

- Problem statement
- Goals and success criteria
- Functional requirements
- Constraints and assumptions
- Stakeholders
- Out of scope items

### 2. TECH_DESIGN.md - Technical Design

Contains:

- System architecture
- Component breakdown
- Technology stack
- Data models
- API design
- Security and performance considerations

### 3. WBS.md - Work Breakdown Structure

Contains:

- Phase-based decomposition (Requirements → Design → Implementation → Testing → Deployment)
- Task hierarchy with subtasks
- Effort estimates (story points)
- Dependencies between tasks
- Parallel work streams

### 4. GANTT.md - Gantt Chart & Critical Path

Contains:

- Mermaid Gantt chart visualization
- Task durations and dependencies
- **Critical path** (longest dependency chain)
- Timeline estimates

**Example Gantt Chart:**

```mermaid
gantt
    title Project Timeline
    dateFormat YYYY-MM-DD
    section Requirements
    Document requirements :task1, 2d
    Review requirements :task2, after task1, 1d
    section Implementation
    Build features :crit, task3, after task2, 4d
    Write tests :task4, after task3, 3d
```

### 5. TASK_LIST.md - Detailed Task List

Contains:

- Task IDs (TASK-001, TASK-002, etc.)
- Task descriptions
- Effort estimates
- Dependencies
- Acceptance criteria
- Phase assignments

### 6. persona_map.yml - Task Assignments

Contains:

- Task-to-persona mappings
- Role-based task distribution
- Automatic assignment using AI decision engine

**Example:**

```yaml
version: "1.0"
assignments:
  TASK-001:
    persona: product_strategist
    task: "Document functional requirements"
    phase: "Requirements"
  TASK-002:
    persona: architect
    task: "Design system architecture"
    phase: "Design"
```

### 7. PROJECT_PLAN.md - Master Document

Contains:

- Executive summary
- Complete WBS
- Gantt chart with critical path
- Persona assignments summary
- Project metadata (totals, estimates, timeline)

**This is your single source of truth for the project.**

## Workflows

### Standard Waterfall Workflow

Complete planning with all artifacts:

1. **Initialize** - Choose ingestion or generation mode
2. **PRD** - Product requirements (reuses existing `planning/create_prd.md`)
3. **Tech Design** - System architecture (reuses `planning/design_architecture.md`)
4. **WBS** - Work breakdown structure
5. **Gantt** - Timeline with critical path
6. **Tasks** - Detailed task list (reuses `planning/create_tasks.md`)
7. **Personas** - AI-powered task assignments
8. **Project Plan** - Final integration document
9. **Implementation** - Begin development

### Minimal Waterfall Workflow

Faster planning with essential artifacts only:

1. **Initialize** - Choose mode
2. **PRD** - Requirements
3. **WBS** - Work breakdown
4. **Tasks** - Task list
5. **Implementation** - Begin development

### Waterfall with TDD Workflow

Waterfall planning combined with Test-Driven Development:

1. **Initialize** - Choose ingestion or generation mode
2. **PRD** - Product requirements
3. **Tech Design** - System architecture
4. **WBS** - Work breakdown structure
5. **Gantt** - Timeline with critical path
6. **Tasks** - Detailed task list
7. **TDD Specifications** - Write test specs FIRST (RED phase)
8. **Personas** - AI-powered task assignments
9. **Project Plan** - Final integration document
10. **Implementation** - Implement to pass tests (GREEN phase), then refactor

**TDD Benefits:**

- Tests written before code (specification by example)
- Better design (forces you to think about interfaces)
- Confidence in refactoring (tests protect you)
- Living documentation (tests show how code should work)

## Key Features

### Intelligent Persona Assignment

Uses **Zero Framework Cognition** (ZFC) - AI-powered semantic analysis instead of simple heuristics.

**Available personas:**

- `product_strategist` - Requirements, stakeholder management
- `architect` - System design, technical decisions
- `senior_developer` - Implementation, code quality
- `qa_engineer` - Testing strategy and execution
- `devops_engineer` - Infrastructure, deployment
- `tech_writer` - Documentation

The AI analyzes each task's characteristics (type, complexity, phase, required skills) and assigns the best persona automatically.

### Critical Path Analysis

Identifies the **longest sequence of dependent tasks** - any delay in critical path tasks delays the entire project.

Use this to:

- Focus on high-risk tasks first
- Identify potential bottlenecks
- Optimize parallel work streams
- Adjust resource allocation

### Mermaid Visualizations

All charts use [Mermaid](https://mermaid.js.org/) format - viewable in:

- GitHub markdown
- GitLab markdown
- VS Code (with Mermaid extension)
- Most documentation tools

**To view:**

```bash
# In VS Code with Mermaid extension
code .aidp/docs/GANTT.md

# Or paste into GitHub markdown preview
# Or use online viewer: https://mermaid.live
```

## Configuration

Customize waterfall planning in `aidp.yml`:

```yaml
waterfall:
  enabled: true
  docs_directory: ".aidp/docs"
  gantt_format: "mermaid"

  # Customize WBS phases
  wbs_phases:
    - "Requirements"
    - "Design"
    - "Implementation"
    - "Testing"
    - "Deployment"

  # Effort estimation settings
  effort_estimation:
    method: "llm_relative"  # AI-based estimates
    units: "story_points"

  # Persona assignment
  persona_assignment:
    method: "zfc_automatic"  # Zero Framework Cognition
    allow_parallel: true     # Multiple personas can work simultaneously
```

## Test-Driven Development (TDD)

The TDD step is available in any workflow, not just waterfall. Use it when you want to follow the **RED-GREEN-REFACTOR** cycle.

### What TDD Generates

**docs/tdd_specifications.md:**

- Comprehensive test specifications
- Test implementation order
- Test data and fixtures
- Coverage goals

**Skeleton test files:**

- Unit test templates
- Integration test templates
- Acceptance test templates
- Ready to run (they'll fail initially - that's the RED phase!)

### TDD Workflow

1. **RED**: Write tests that specify desired behavior (they fail)
2. **GREEN**: Write minimal code to make tests pass
3. **REFACTOR**: Improve code design while keeping tests green

### When to Use TDD

**Great for:**

- Complex business logic
- APIs and interfaces
- Critical functionality
- Code you'll need to maintain long-term

**Skip for:**

- Quick prototypes
- Exploratory code
- Simple CRUD operations
- UI layouts

### TDD Best Practices

- **Test behavior, not implementation** - Don't test internal methods
- **One assertion per test** - Each test verifies one thing
- **Mock external dependencies** - Don't hit real APIs, databases, file systems
- **Keep tests fast** - < 1 second per test is ideal
- **Make tests deterministic** - Same input = same result, every time

### Non-Waterfall TDD Workflows

TDD isn't limited to waterfall. Use these workflows:

**TDD Feature Development:**

```bash
aidp  # Select: Execute Mode → TDD Feature Development
```

This workflow:

1. Creates PRD
2. Designs architecture
3. **Generates TDD specifications**
4. Implements features (with tests driving design)

**Custom with TDD:**

```bash
aidp  # Select: Execute Mode → Custom Workflow
# Then select: 17_TDD_SPECIFICATION in your custom steps
```

## Tips & Best Practices

### 1. Start with Good Requirements

**Ingestion path:**

- Provide complete PRDs and design docs
- The better your input, the better the plan
- AIDP will ask clarifying questions for gaps

**Generation path:**

- Be specific about problems and goals
- Define clear success criteria
- Identify constraints early

### 2. Review Before Implementing

- Check the WBS for completeness
- Verify the critical path makes sense
- Review persona assignments
- Adjust effort estimates if needed

### 3. Use Critical Path Strategically

- Start critical path tasks early
- Add buffer time to critical tasks
- Look for opportunities to parallelize
- Monitor critical path progress closely

### 4. Iterate on the Plan

- Update artifacts as you learn more
- Re-run waterfall planning after major changes
- Keep PROJECT_PLAN.md as living document
- Track changes in version control

### 5. Leverage Personas

- Assign work based on persona recommendations
- Consider skill development opportunities
- Balance workload across personas
- Use parallel assignments for faster delivery

## Examples

### Example 1: New Feature Development

```bash
aidp  # Start AIDP

# Select: Execute Mode → Waterfall Planning

# Provide requirements:
Problem: Users need to export reports as PDF
Goals: Support PDF export for all report types
Success: 95%+ of users can generate PDFs without issues
```

**Generates:**

- Complete PRD with user stories
- Technical design (PDF library selection, API design)
- WBS with 15 tasks across 5 phases
- Gantt showing 6-week timeline
- Critical path through PDF generation and testing
- Task assignments (3 to senior_developer, 2 to qa_engineer, etc.)

### Example 2: Refactoring Project

```bash
aidp  # Start AIDP

# Select: Execute Mode → Waterfall Planning
# Choose: Ingestion mode
# Provide: ./docs/refactoring_plan.md

# AIDP asks clarifying questions:
# - Which modules are highest priority?
# - What's the testing strategy?
# - Are there breaking changes?
```

**Generates:**

- Enhanced PRD with refactoring goals
- Technical design for new architecture
- WBS with refactoring phases
- Gantt showing gradual migration
- Critical path through core module refactoring
- Assignments with emphasis on architect and senior_developer

## Troubleshooting

### "No documentation found"

**Problem:** Ingestion mode can't find your docs

**Solution:**

- Provide absolute paths or paths relative to project root
- Ensure files are markdown (.md)
- Check file permissions

### "Critical path seems wrong"

**Problem:** Critical path doesn't match expectations

**Solution:**

- Review task dependencies in TASK_LIST.md
- Verify effort estimates in WBS.md
- Some parallel tasks may not be on critical path (that's good!)

### "Persona assignments don't match team"

**Problem:** Assigned personas don't align with your team structure

**Solution:**

- Edit persona_map.yml manually
- Customize available personas in configuration
- Re-run persona assignment step with custom persona list

### "Gantt chart won't render"

**Problem:** Mermaid visualization not displaying

**Solution:**

- Install Mermaid extension for VS Code
- View on GitHub (renders natively)
- Copy to <https://mermaid.live> for preview
- Check Mermaid syntax is valid

## Next Steps

After waterfall planning:

1. **Review & Approve** - Walk through PROJECT_PLAN.md with stakeholders
2. **Refine** - Edit any artifacts that need adjustment
3. **Implement** - Use step 16_IMPLEMENTATION or manual development
4. **Track** - Keep PROJECT_PLAN.md updated as work progresses
5. **Iterate** - Re-run planning for major scope changes

## Related Documentation

- [Work Loops Guide](WORK_LOOPS_GUIDE.md) - Iterative execution
- [CLI User Guide](CLI_USER_GUIDE.md) - Complete CLI reference
- [Configuration Guide](CONFIGURATION.md) - AIDP configuration options
- [Skills Guide](SKILLS_USER_GUIDE.md) - Understanding personas and skills

## Support

- **Documentation:** [docs/README.md](README.md)
- **Issues:** <https://github.com/viamin/aidp/issues>
- **Design Doc:** [WATERFALL_PLANNING_MODE_DESIGN.md](WATERFALL_PLANNING_MODE_DESIGN.md)

---

Waterfall Planning Mode provides the structure and visibility you need for confident project execution. Happy planning! 📊
