# Assign Tasks to Personas

You are assigning each task to the most appropriate persona using **Zero Framework Cognition** (ZFC).

## Critical: Use ZFC Pattern

**DO NOT use heuristics, regex, or keyword matching!**

All task-to-persona assignments must be made using semantic AI decision making, not programmatic rules.

## Input

Read `.aidp/docs/TASK_LIST.md` - All project tasks

## Available Personas

Default personas include:
- **product_strategist** - Product requirements, user research, stakeholder management
- **architect** - System design, architecture decisions, technology choices
- **senior_developer** - Implementation, code quality, technical problem solving
- **qa_engineer** - Testing strategy, test implementation, quality assurance
- **devops_engineer** - Infrastructure, CI/CD, deployment, monitoring
- **tech_writer** - Documentation, user guides, API documentation

## Assignment Principles

The AI should consider:
- **Task type**: Requirements, design, implementation, testing, deployment
- **Required expertise**: Product, architecture, development, QA, operations
- **Phase**: Different personas for different phases
- **Complexity**: Senior developers for complex tasks

## Zero Framework Cognition

**FORBIDDEN**:
- Regex pattern matching on task names
- Keyword matching ("test" → qa_engineer)
- Heuristic rules
- Scoring formulas

**REQUIRED**:
- Use AI decision engine for ALL assignments
- Provide task context to AI (name, description, phase, effort)
- Let AI make semantic decisions
- Assignment rationale comes from AI, not code

## Parallel Execution

Multiple personas can work in parallel - the system handles conflicts automatically.

## Implementation

**For Ruby/AIDP projects**, use the `ruby_aidp_planning` skill to:

1. Load tasks from Gantt chart or task list
2. Use `Aidp::Planning::Mappers::PersonaMapper` with AI decision engine
3. Call `AIDecisionEngine.decide()` for each task assignment
4. Generate `persona_map.yml` configuration
5. Write to `.aidp/docs/persona_map.yml`

The skill provides the complete Ruby implementation including:
- AI engine integration
- ZFC-based decision making (NO heuristics!)
- YAML configuration generation
- Proper error handling and logging

**For other language implementations**, implement equivalent functionality:

1. Load task list with descriptions, phases, and effort
2. For each task, invoke AI decision engine with:
   - Task characteristics (name, description, phase, effort)
   - Available personas list
   - Decision prompt asking for best persona match
3. Store AI's decision (persona assignment)
4. Generate configuration file mapping tasks to personas
5. Include assignment rationale from AI

## Output Format

Write assignments to `.aidp/docs/persona_map.yml`:

```yaml
version: "1.0"
generated_at: "<timestamp>"
assignments:
  TASK-001:
    persona: product_strategist
    task: "Document Functional Requirements"
    phase: "Requirements"
  TASK-002:
    persona: architect
    task: "Design System Architecture"
    phase: "Design"
  ...
```

## Remember

- Use AIDecisionEngine - NO manual heuristics!
- Assignment rationale comes from AI, not code
- Every task must be assigned
- Personas can work in parallel
- This is a ZFC pattern - meaning goes to AI, structure goes to code
