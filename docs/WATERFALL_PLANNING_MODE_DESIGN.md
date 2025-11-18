# Waterfall Planning Mode - Design & Implementation Plan

## Overview

This document describes the design and implementation plan for AIDP's Waterfall Planning Mode, which provides structured project planning with documentation ingestion, work breakdown structures, Gantt charts, and automated persona assignment.

**Issue:** #209
**Status:** Implementation in progress
**Last Updated:** 2025-11-18

## Goals

Enable AIDP users to:

1. **Ingest existing documentation** (PRDs, design docs, decision records) as starting points
2. **Generate documentation from scratch** through AI-guided requirements elicitation
3. **Create comprehensive project plans** with milestones, dependencies, and timelines
4. **Visualize project structure** using Gantt charts and dependency graphs (Mermaid format)
5. **Automatically assign tasks to personas** using Zero Framework Cognition (ZFC)

## Architecture

### Workflow Integration

Waterfall planning is implemented as a new workflow type in the existing AIDP workflow system:

```text
lib/aidp/workflows/
├── definitions.rb          # Add waterfall workflow definitions
├── selector.rb             # Already supports custom workflows
└── guided_agent.rb         # Orchestrates workflow execution
```

### New Components

**Note:** Components are organized by PURPOSE (not workflow) to maximize reusability.

```text
lib/aidp/planning/              # Generic planning utilities (usable by any workflow)
├── parsers/
│   └── document_parser.rb      # Parse existing documentation
├── generators/
│   ├── wbs_generator.rb        # Generate work breakdown structure
│   └── gantt_generator.rb      # Generate Mermaid Gantt charts
├── mappers/
│   └── persona_mapper.rb       # Map tasks to personas (ZFC)
└── builders/
    └── project_plan_builder.rb # Orchestrate plan generation
```

### Generated Artifacts

All artifacts are created in `.aidp/docs/`:

```text
.aidp/docs/
├── PRD.md                  # Product requirements document
├── TECH_DESIGN.md          # Technical design document
├── TASK_LIST.md            # Structured task list with dependencies
├── DECISIONS.md            # Architecture decision records
├── PROJECT_PLAN.md         # Complete plan with WBS, Gantt, critical path
└── persona_map.yml         # Task-to-persona assignments
```

## Implementation Decisions

Based on issue discussion (viamin comments 2025-11-12):

| Decision Area | Resolution |
|---------------|------------|
| **Parsing Libraries** | Text/markdown only - no special libraries needed |
| **Requirements Elicitation** | Use existing Q&A harness for dialogue |
| **Gantt Format** | Mermaid format for charts |
| **Duration Estimation** | LLM-based relative effort estimates |
| **Persona Strategy** | Enhance existing personas (no waterfall-specific ones) |
| **Dependency Graphs** | Mermaid/Graphviz embedded in PROJECT_PLAN.md |
| **Conflict Resolution** | Automatic assignment via agent cognition (ZFC) |
| **Parallel Execution** | No conflict concerns - run in parallel |
| **Documentation Init** | Create .aidp/docs/ on-demand |
| **Partial Docs** | Fill gaps via Q&A process |
| **Visualization** | Text output only - users handle external viz |
| **Change Tracking** | VCS tracks changes (not AIDP responsibility) |

## Workflow Design

### Waterfall Workflow Definitions

Add to `EXECUTE_WORKFLOWS` in `lib/aidp/workflows/definitions.rb`:

```ruby
waterfall_standard: {
  name: "Waterfall Planning",
  description: "Structured project planning with WBS and Gantt charts",
  icon: "📊",
  details: [
    "Documentation ingestion or generation",
    "Work breakdown structure (WBS)",
    "Gantt chart with critical path",
    "Task dependencies and milestones",
    "Persona/agent assignment",
    "Complete project plan"
  ],
  steps: [
    "22_PLANNING_MODE_INIT",     # Initialize planning mode (ingestion vs generation)
    "00_PRD",                    # Product requirements (reused)
    "02_ARCHITECTURE",           # Technical design (reused)
    "18_WBS",                    # Work breakdown structure (generic step)
    "19_GANTT_CHART",            # Gantt chart with critical path (generic step)
    "20_PERSONA_ASSIGNMENT",     # Persona/task mapping (generic step)
    "21_PROJECT_PLAN_ASSEMBLY",  # Assemble complete plan (generic step)
    "16_IMPLEMENTATION"          # Implementation (reused)
  ]
}
```

### Step Specifications

Add to `lib/aidp/execute/steps.rb`:

**Note:** Steps are named generically (not workflow-specific) to encourage reuse across any workflow.

```ruby
"22_PLANNING_MODE_INIT" => {
  "templates" => ["planning/initialize_planning_mode.md"],
  "description" => "Initialize planning mode (ingestion of existing docs vs generation from scratch)",
  "outs" => [".aidp/docs/.planning_mode"],
  "gate" => true,  # User chooses ingestion or generation path
  "interactive" => true
}

# Reuse existing steps for PRD and Architecture
"00_PRD" => {
  # Already exists - reused from existing planning steps
}

"02_ARCHITECTURE" => {
  # Already exists - reused from existing planning steps
}

"18_WBS" => {
  "templates" => ["planning/generate_wbs.md"],
  "description" => "Generate Work Breakdown Structure with phases and tasks",
  "outs" => [".aidp/docs/WBS.md"],
  "gate" => false
}

"19_GANTT_CHART" => {
  "templates" => ["planning/generate_gantt.md"],
  "description" => "Generate Gantt chart with timeline and critical path",
  "outs" => [".aidp/docs/GANTT.md"],
  "gate" => false
}

"20_PERSONA_ASSIGNMENT" => {
  "templates" => ["planning/assign_personas.md"],
  "description" => "Assign tasks to personas/roles using AI (ZFC)",
  "outs" => [".aidp/docs/persona_map.yml"],
  "gate" => false
}

"21_PROJECT_PLAN_ASSEMBLY" => {
  "templates" => ["planning/assemble_project_plan.md"],
  "description" => "Assemble complete project plan from all artifacts",
  "outs" => [".aidp/docs/PROJECT_PLAN.md"],
  "gate" => false
}
```

## Component Design

### 1. DocumentParser

**Purpose:** Parse existing documentation to extract structured information

**Location:** `lib/aidp/planning/parsers/document_parser.rb`

**Responsibilities:**

- Read markdown files from user-provided paths
- Extract sections (problem statement, goals, constraints, etc.)
- Detect structure using AI (ZFC pattern)
- Return structured hash of parsed content

**Key Methods:**

```ruby
def parse_file(file_path)
  # Returns: { type: :prd/:design/:adr, sections: {...} }
end

def parse_directory(dir_path)
  # Parse all markdown files in directory
end

def extract_structure(content)
  # Use AIDecisionEngine to detect document structure
end
```

### 2. WBSGenerator

**Purpose:** Generate work breakdown structure with phases and tasks

**Location:** `lib/aidp/planning/generators/wbs_generator.rb`

**Responsibilities:**

- Decompose project into phases (Requirements, Design, Implementation, Testing, Deployment)
- Break phases into tasks
- Identify parallel work streams
- Generate WBS markdown output

**Key Methods:**

```ruby
def generate(prd:, tech_design:)
  # Returns WBS structure
end

def format_as_markdown(wbs)
  # Generate markdown representation
end
```

### 3. GanttGenerator

**Purpose:** Generate Mermaid Gantt charts with critical path

**Location:** `lib/aidp/planning/generators/gantt_generator.rb`

**Responsibilities:**

- Create Mermaid gantt syntax
- Calculate effort estimates (via LLM)
- Identify critical path
- Support parallel tasks
- Generate dependency relationships

**Key Methods:**

```ruby
def generate(wbs:, task_list:)
  # Returns Mermaid gantt chart
end

def calculate_critical_path(tasks)
  # Identify longest path through dependencies
end

def format_mermaid(gantt_data)
  # Generate Mermaid syntax
end
```

### 4. PersonaMapper

**Purpose:** Map tasks to personas using Zero Framework Cognition

**Location:** `lib/aidp/planning/mappers/persona_mapper.rb`

**Responsibilities:**

- Use AIDecisionEngine to determine best persona for each task
- Consider task type, complexity, and required skills
- Generate persona_map.yml configuration
- No regex or heuristics - pure AI decision making

**Key Methods:**

```ruby
def assign_personas(task_list)
  # Use AIDecisionEngine.decide() for each task
end

def generate_persona_map(assignments)
  # Create YAML configuration
end
```

### 5. ProjectPlanBuilder

**Purpose:** Orchestrate generation of complete project plan

**Location:** `lib/aidp/planning/builders/project_plan_builder.rb`

**Responsibilities:**

- Coordinate all generators
- Assemble PROJECT_PLAN.md with all components
- Handle both ingestion and generation paths
- Manage Q&A for missing information

**Key Methods:**

```ruby
def build_from_ingestion(docs_path)
  # Parse existing docs and fill gaps
end

def build_from_scratch(requirements)
  # Generate all docs from user input
end

def assemble_project_plan(components)
  # Combine all artifacts into PROJECT_PLAN.md
end
```

## Configuration

Add to `lib/aidp/config.rb` schema:

```ruby
waterfall: {
  enabled: true,
  docs_directory: ".aidp/docs",
  generate_decisions_md: true,
  gantt_format: "mermaid",
  wbs_phases: [
    "Requirements",
    "Design",
    "Implementation",
    "Testing",
    "Deployment"
  ],
  effort_estimation: {
    method: "llm_relative",
    units: "story_points"
  },
  persona_assignment: {
    method: "zfc_automatic",
    allow_parallel: true
  }
}
```

## Template Design

### Design Philosophy: Waterfall as Process Container

**Key Insight:** Waterfall is a **process container**, not a different planning methodology. The value is in:

1. **Sequencing** - Structured flow through planning steps
2. **Integration** - Ruby classes that generate WBS, Gantt, personas, and integrate artifacts
3. **Dual paths** - Ingestion vs generation modes

Therefore, we **reuse existing templates** for content generation and create only waterfall-specific integration templates.

### Reused Templates (from `planning/`)

These existing templates are already proven and handle content generation:

- **Step 21 (PRD):** `planning/create_prd.md` - Product requirements generation
- **Step 22 (Tech Design):** `planning/design_architecture.md` - System architecture design
- **Step 25 (Task List):** `planning/create_tasks.md` - Task list creation

### Generic Planning Templates

Only 5 generic planning templates were created (usable by any workflow):

#### 1. `planning/initialize_planning_mode.md` (Step 22)

**Purpose:** Mode selection - ingestion vs generation path

**Actions:**

- Ask user: Do they have existing documentation?
- If YES: Request paths to PRD, design docs, ADRs, task lists
- If NO: Start requirements elicitation dialogue
- Create `.aidp/docs/.planning_mode` to track mode selection

**Output:** `.aidp/docs/.planning_mode` (yaml file with mode and paths)

#### 2. `planning/generate_wbs.md` (Step 18)

**Purpose:** Work Breakdown Structure generation via WBSGenerator Ruby class

**Actions:**

- Calls `Aidp::Planning::Generators::WBSGenerator.generate(prd:, tech_design:)`
- Phase-based decomposition (Requirements, Design, Implementation, Testing, Deployment)
- Task hierarchy with dependencies
- Parallel work stream identification
- Effort estimates

**Output:** `.aidp/docs/WBS.md`

#### 3. `planning/generate_gantt.md` (Step 19)

**Purpose:** Gantt chart with critical path via GanttGenerator Ruby class

**Actions:**

- Calls `Aidp::Planning::Generators::GanttGenerator.generate(wbs:, task_list:)`
- Creates Mermaid gantt syntax
- Calculates task durations from effort estimates
- Identifies critical path (longest dependency chain)
- Supports parallel tasks

**Output:** `.aidp/docs/GANTT.md` (includes Mermaid chart and critical path list)

#### 4. `planning/assign_personas.md` (Step 20)

**Purpose:** ZFC-based persona assignment via PersonaMapper Ruby class

**CRITICAL:** Uses **Zero Framework Cognition** - NO heuristics, NO regex, NO keyword matching!

**Actions:**

- Calls `Aidp::Planning::Mappers::PersonaMapper.assign_personas(task_list)`
- Uses `AIDecisionEngine.decide()` for each task
- Considers task type, complexity, phase, required skills
- Generates `persona_map.yml` configuration

**Output:** `.aidp/docs/persona_map.yml`

#### 5. `planning/assemble_project_plan.md` (Step 21)

**Purpose:** Final integration via ProjectPlanBuilder Ruby class

**Actions:**

- Calls `Aidp::Planning::Builders::ProjectPlanBuilder.assemble_project_plan(components)`
- Integrates all artifacts into single document
- Includes: WBS, Gantt chart, critical path, persona summary, metadata
- Creates single source of truth for project planning

**Output:** `.aidp/docs/PROJECT_PLAN.md`

### Template Summary

| Step | Template | Type | Purpose |
|------|----------|------|---------|
| 22 | `planning/initialize_planning_mode.md` | NEW | Mode selection |
| 00 | `planning/create_prd.md` | REUSED | PRD generation |
| 02 | `planning/design_architecture.md` | REUSED | Tech design |
| 18 | `planning/generate_wbs.md` | NEW | WBS via Ruby class |
| 19 | `planning/generate_gantt.md` | NEW | Gantt via Ruby class |
| 20 | `planning/assign_personas.md` | NEW | Personas via ZFC |
| 21 | `planning/assemble_project_plan.md` | NEW | Final integration |

**Total:** 5 new generic planning templates, 3 reused templates

**Note:** All templates are in `templates/planning/` (not workflow-specific) to maximize reusability across any workflow that needs planning capabilities.

## Implementation Task List

### Phase 1: Foundation

- [x] Review issue and comments for requirements
- [x] Create design document with implementation plan
- [x] Add waterfall workflow to `lib/aidp/workflows/definitions.rb`
- [x] Add step specifications to `lib/aidp/execute/steps.rb`
- [x] Add waterfall configuration schema to `lib/aidp/config.rb`

### Phase 2: Core Components

- [x] Create `lib/aidp/planning/` directory
- [x] Implement `document_parser.rb` with tests
- [x] Implement `wbs_generator.rb` with tests
- [x] Implement `gantt_generator.rb` with tests
- [x] Implement `persona_mapper.rb` with tests (using ZFC)
- [x] Implement `project_plan_builder.rb` with tests

### Phase 3: Templates

- [x] Create `templates/planning/` directory (generic planning templates, not workflow-specific)
- [x] Create `initialize_planning_mode.md` template
- [x] Create `generate_wbs.md` template
- [x] Create `generate_gantt.md` template
- [x] Create `assign_personas.md` template
- [x] Create `assemble_project_plan.md` template
- [x] Reuse existing `planning/create_prd.md`, `planning/design_architecture.md`, `planning/create_tasks.md`

### Phase 4: Quality & Completion

- [x] Check Ruby syntax for all files
- [x] Refactor to reuse existing templates
- [x] Update design document with template reuse philosophy
- [x] Write unit tests (DocumentParser, WBSGenerator, GanttGenerator, PersonaMapper, ProjectPlanBuilder)
- [ ] Write integration tests for full workflow
- [ ] Run full test suite and verify all tests pass
- [ ] Create user documentation

### Phase 5: Integration Testing (Steps 20-23)

- [ ] Create integration test for ingestion path
- [ ] Create integration test for generation path
- [ ] Test end-to-end workflow with real project
- [ ] Verify all artifacts are generated correctly

### Phase 6: Quality & Delivery

- [ ] Run full test suite and fix failures
- [ ] Run standardrb linter and fix issues
- [ ] Manual testing of complete workflow

### Phase 7: Documentation & Completion

- [ ] Add user guide to `docs/WATERFALL_PLANNING_MODE.md`
- [ ] Update README.md with waterfall mode documentation
- [ ] Final commit and push

## Testing Strategy

### Unit Tests

Each component has its own spec file:

- `spec/aidp/planning/document_parser_spec.rb`
- `spec/aidp/planning/wbs_generator_spec.rb`
- `spec/aidp/planning/gantt_generator_spec.rb`
- `spec/aidp/planning/persona_mapper_spec.rb`
- `spec/aidp/planning/project_plan_builder_spec.rb`

**Test Strategy:**

- Mock AIDecisionEngine calls (external boundary)
- Mock file I/O (external boundary)
- Test public methods only
- Use dependency injection for testability
- Follow Sandi Metz testing rules

### Integration Tests

- `spec/integration/waterfall_ingestion_workflow_spec.rb`
- `spec/integration/waterfall_generation_workflow_spec.rb`

**Test Strategy:**

- Use real files in tmp directory
- Mock only AI provider calls
- Verify all artifacts are created
- Test error handling and edge cases

## Code Quality Standards

Following `docs/LLM_STYLE_GUIDE.md`:

✅ **Small objects** - Each generator ~100 lines
✅ **Single responsibility** - One class per concern
✅ **TTY components** - Use prompt.say(), never puts
✅ **ZFC for decisions** - PersonaMapper uses AIDecisionEngine
✅ **Extensive logging** - Use Aidp.log_debug() throughout
✅ **Test external boundaries** - Mock AI, file I/O, user input
✅ **Dependency injection** - Constructor injection for all dependencies
✅ **No backward compatibility** - AIDP is v0.x.x, break freely

## Success Criteria

- [ ] User can select "Waterfall Planning" workflow from Execute mode
- [ ] User can ingest existing documentation and fill gaps via Q&A
- [ ] User can generate documentation from scratch via dialogue
- [ ] All artifacts are generated in `.aidp/docs/`
- [ ] Gantt charts use valid Mermaid syntax
- [ ] Persona assignment uses ZFC (no heuristics)
- [ ] Tests achieve >85% coverage
- [ ] All tests pass
- [ ] Linter passes (standardrb)
- [ ] End-to-end manual testing successful

## Future Enhancements

Not in scope for initial implementation:

- PNG/SVG generation from Mermaid (users handle externally)
- Advanced change tracking (handled by VCS)
- Resource allocation and capacity planning
- Cost estimation
- Risk management matrix
- Custom phase definitions
- Export to MS Project / Jira

## References

- **Issue:** #209
- **LLM Style Guide:** `docs/LLM_STYLE_GUIDE.md`
- **Style Guide:** `docs/STYLE_GUIDE.md`
- **Workflow System:** `lib/aidp/workflows/`
- **Execute Steps:** `lib/aidp/execute/steps.rb`
- **Zero Framework Cognition:** See LLM_STYLE_GUIDE.md Section 2
