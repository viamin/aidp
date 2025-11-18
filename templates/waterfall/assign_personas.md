# Assign Tasks to Personas

You are assigning each task to the most appropriate persona using **Zero Framework Cognition** (ZFC).

## Critical: Use ZFC Pattern

**DO NOT use heuristics, regex, or keyword matching!**

Use the PersonaMapper class which leverages AIDecisionEngine for intelligent persona assignment.

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

## Implementation

Use the PersonaMapper class:

```ruby
require_relative '../../../lib/aidp/workflows/waterfall/persona_mapper'
require_relative '../../../lib/aidp/workflows/waterfall/gantt_generator'
require_relative '../../../lib/aidp/workflows/waterfall/wbs_generator'
require_relative '../../../lib/aidp/workflows/waterfall/document_parser'

# This is a placeholder - in production, use real AIDecisionEngine
class MockAIEngine
  def decide(context:, prompt:, data:, schema:)
    # Intelligent assignment based on task characteristics
    # In production, this calls the actual AI provider
    task_name = data[:task_name].downcase

    return "architect" if task_name.include?("design") || task_name.include?("architecture")
    return "qa_engineer" if task_name.include?("test")
    return "devops_engineer" if task_name.include?("deploy") || task_name.include?("infrastructure")
    return "tech_writer" if task_name.include?("documentation")
    return "product_strategist" if task_name.include?("requirements")

    "senior_developer"
  end
end

# Load tasks
parser = Aidp::Workflows::Waterfall::DocumentParser.new
prd = parser.parse_file('.aidp/docs/PRD.md')
wbs_generator = Aidp::Workflows::Waterfall::WBSGenerator.new
wbs = wbs_generator.generate(prd: prd)
gantt_generator = Aidp::Workflows::Waterfall::GanttGenerator.new
gantt = gantt_generator.generate(wbs: wbs)

# Assign personas using ZFC
ai_engine = MockAIEngine.new  # Replace with real AIDecisionEngine in production
mapper = Aidp::Workflows::Waterfall::PersonaMapper.new(ai_decision_engine: ai_engine)
assignments = mapper.assign_personas(gantt[:tasks])

# Generate YAML config
persona_yaml = mapper.generate_persona_map(assignments)
File.write('.aidp/docs/persona_map.yml', persona_yaml)
```

## Assignment Principles

The AI should consider:
- **Task type**: Requirements, design, implementation, testing, deployment
- **Required expertise**: Product, architecture, development, QA, operations
- **Phase**: Different personas for different phases
- **Complexity**: Senior developers for complex tasks

## Parallel Execution

Multiple personas can work in parallel - the system handles conflicts automatically.

## Output

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
