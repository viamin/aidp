# Agile Development Mode Implementation Plan

**Issue**: #210
**Created**: 2025-11-18
**Status**: Planning Complete, Implementation Starting

## Overview

Add an **Agile Development Mode** to AIDP that complements existing Waterfall planning by introducing iterative user feedback loops, user research planning, and marketing-ready reporting capabilities.

## Architecture Approach

### Design Principles

1. **Reuse Existing Components** (~35-40% code reuse)
   - DocumentParser for PRD/feedback ingestion
   - PersonaMapper for task assignment with AI Decision Engine
   - GanttGenerator for timeline visualization
   - Builder pattern for orchestration
   - Module organization (purpose-based, not workflow-based)

2. **Zero Framework Cognition (ZFC)**
   - All semantic decisions → AI Decision Engine
   - No heuristics, scoring formulas, or keyword matching
   - Use `mini` tier, define schemas, cache decisions

3. **Organize by PURPOSE**
   - New components go in existing directories: `parsers/`, `generators/`, `mappers/`
   - NOT in an `agile/` directory (workflows are process containers)

4. **Markdown-First**
   - All artifacts are markdown/YAML for version control
   - Metadata tracked (timestamps, counts, generation method)

## Components to Build

### 1. New Personas (Configuration)

**File**: `lib/aidp/personas/definitions.rb` (extend existing)

Add three new personas:
- **UX Researcher**: Study design, feedback analysis, user testing
- **Product Manager**: PRD ownership, MVP scope definition, backlog prioritization
- **Marketing Strategist**: Launch communications, differentiator summaries, success metrics

### 2. New Generators

#### MVPScopeGenerator
**File**: `lib/aidp/planning/generators/mvp_scope_generator.rb`

- Input: PRD document, user input on priorities
- Output: `MVP_SCOPE.md` with:
  - Must-have features for MVP
  - Nice-to-have features (deferred)
  - Success criteria
  - Out-of-scope items
- Uses AI Decision Engine to analyze features and determine MVP viability

#### UserTestPlanGenerator
**File**: `lib/aidp/planning/generators/user_test_plan_generator.rb`

- Input: MVP scope, target users
- Output: `USER_TEST_PLAN.md` with:
  - Recruitment criteria
  - Testing stages (alpha, beta, etc.)
  - Survey templates (Likert scale, open-ended)
  - Interview scripts
  - Success metrics
- Uses AI to generate contextual questions based on feature set

#### FeedbackAnalyzer
**File**: `lib/aidp/planning/analyzers/feedback_analyzer.rb`

- Input: Feedback data (CSV, JSON, markdown)
- Output: `USER_FEEDBACK_ANALYSIS.md` with:
  - Findings summary
  - Trends and patterns
  - User insights
  - Priority recommendations
- Uses AI Decision Engine for semantic analysis (NO regex or keyword matching)

#### IterationPlanGenerator
**File**: `lib/aidp/planning/generators/iteration_plan_generator.rb`

- Input: Feedback analysis, current codebase
- Output: `NEXT_ITERATION_PLAN.md` with:
  - Tasks to address feedback
  - Feature improvements
  - Bug fixes
  - Timeline estimate (reuses GanttGenerator)
- Generates WBS-style task breakdown

#### MarketingReportGenerator
**File**: `lib/aidp/planning/generators/marketing_report_generator.rb`

- Input: Feature set, user feedback, competitive analysis
- Output: `MARKETING_REPORT.md` with:
  - Key messages
  - Differentiators
  - Success metrics
  - Launch checklist
- Uses AI to craft compelling narratives from technical features

#### LegacyResearchPlanner
**File**: `lib/aidp/planning/generators/legacy_research_planner.rb`

- Input: Existing codebase (analyzed with tree-sitter)
- Output: `LEGACY_USER_RESEARCH_PLAN.md` with:
  - Current feature audit
  - User research questions
  - Testing priorities
  - Improvement opportunities
- Automatically analyzes codebase structure and suggests research areas

### 3. New Parser

#### FeedbackDataParser
**File**: `lib/aidp/planning/parsers/feedback_data_parser.rb`

- Parses CSV, JSON, markdown feedback files
- Normalizes data into consistent structure
- Validates required fields
- Extracts metadata (timestamps, respondent IDs, etc.)

### 4. Orchestration Builder

#### AgilePlanBuilder
**File**: `lib/aidp/planning/builders/agile_plan_builder.rb`

Orchestrates the agile planning workflow:

```ruby
class AgilePlanBuilder
  def initialize(
    document_parser: DocumentParser.new,
    mvp_scope_generator: MVPScopeGenerator.new,
    user_test_plan_generator: UserTestPlanGenerator.new,
    persona_mapper: PersonaMapper.new,
    gantt_generator: GanttGenerator.new,
    prompt: TTY::Prompt.new
  )
    # Dependency injection for all components
  end

  def build_mvp_plan(prd_path)
    # 1. Parse PRD
    # 2. Prompt for MVP priorities
    # 3. Generate MVP scope
    # 4. Generate user test plan
    # 5. Generate timeline
    # 6. Assign personas
  end

  def analyze_feedback(feedback_path)
    # 1. Parse feedback data
    # 2. Analyze with AI
    # 3. Generate analysis report
  end

  def plan_next_iteration(feedback_analysis_path, codebase_path)
    # 1. Parse feedback analysis
    # 2. Analyze current codebase
    # 3. Generate iteration plan
    # 4. Generate timeline
    # 5. Assign personas
  end

  def plan_legacy_research(codebase_path)
    # 1. Analyze codebase with tree-sitter
    # 2. Generate research plan
    # 3. Generate test plan
  end
end
```

### 5. Workflow Steps

**File**: `lib/aidp/execute/steps.rb` (extend existing)

Add new workflow steps:
- `generate_mvp_scope` - Interactive MVP scoping
- `generate_user_test_plan` - Create testing plan
- `ingest_feedback` - Prompt-based feedback ingestion
- `analyze_feedback` - AI-powered analysis
- `generate_iteration_plan` - Next iteration planning
- `generate_marketing_report` - Marketing materials
- `analyze_legacy_codebase` - Existing product analysis

### 6. Workflow Definitions

**File**: `lib/aidp/workflows/definitions.rb` (extend existing)

Add new workflows:

```yaml
agile_mvp:
  name: "Agile MVP Planning"
  description: "Plan an MVP with user testing"
  steps:
    - parse_prd
    - generate_mvp_scope
    - generate_user_test_plan
    - generate_gantt
    - assign_personas
    - generate_marketing_report

agile_iteration:
  name: "Agile Iteration Planning"
  description: "Plan next iteration based on feedback"
  steps:
    - ingest_feedback
    - analyze_feedback
    - generate_iteration_plan
    - generate_gantt
    - assign_personas

agile_legacy_research:
  name: "Legacy Product Research"
  description: "Plan user research for existing software"
  steps:
    - analyze_legacy_codebase
    - generate_legacy_research_plan
    - generate_user_test_plan
```

### 7. Configuration

**File**: `lib/aidp/config.rb` (extend existing)

Add configuration options:

```ruby
config.agile = {
  mvp_first: true,              # Always generate MVP scope
  feedback_loops: true,          # Enable iterative feedback
  auto_iteration: false,         # Manual iteration triggering
  research_enabled: true,        # Enable user research planning
  marketing_enabled: true,       # Generate marketing reports
  legacy_analysis: true          # Enable legacy codebase analysis
}
```

## Implementation Plan

### Phase 1: Foundation (Core Infrastructure)

1. **Add New Personas** (UX Researcher, Product Manager, Marketing Strategist)
2. **Create FeedbackDataParser** (CSV/JSON/markdown parsing)
3. **Set up Configuration** (agile mode settings)
4. **Add Workflow Steps** (skeleton implementations)

### Phase 2: MVP Planning

5. **Build MVPScopeGenerator** (AI-based scope definition)
6. **Build UserTestPlanGenerator** (research planning)
7. **Build MarketingReportGenerator** (marketing materials)
8. **Create AgilePlanBuilder** (orchestration)
9. **Define `agile_mvp` workflow**

### Phase 3: Feedback Loop

10. **Build FeedbackAnalyzer** (AI-powered analysis)
11. **Build IterationPlanGenerator** (next iteration planning)
12. **Define `agile_iteration` workflow**
13. **Add feedback ingestion step** (interactive prompt)

### Phase 4: Legacy Research

14. **Build LegacyResearchPlanner** (codebase analysis)
15. **Define `agile_legacy_research` workflow**
16. **Integrate tree-sitter analysis** (reuse existing code)

### Phase 5: Integration & Testing

17. **Write RSpec tests** (all components, mock external boundaries)
18. **Integration testing** (expect scripts for TUI flows)
19. **Documentation updates** (CLI_USER_GUIDE, README)
20. **Final validation** (all 7 acceptance criteria)

## Acceptance Criteria

From issue #210:

- [ ] Agile mode can be initialized with a PRD or existing codebase
- [ ] User testing plans are generated with recruitment criteria and survey templates
- [ ] Feedback data can be ingested and analyzed with AI-powered insights
- [ ] Iteration plans and marketing reports are produced
- [ ] Legacy research planning works for existing codebases
- [ ] New personas (UX Researcher, Product Manager, Marketing Strategist) are available
- [ ] Documentation is updated (CLI guide, README)

## Technical Details

### AI Decision Engine Integration

All semantic analysis uses `AIDecisionEngine.decide(...)`:

```ruby
# MVPScopeGenerator
decision = AIDecisionEngine.decide(
  prompt: "Analyze these features and determine MVP viability",
  context: { features: features, priorities: user_priorities },
  schema: { type: "object", properties: { ... } },
  tier: "mini",
  cache: true
)
```

### Logging Strategy

Instrument all components with `Aidp.log_debug()`:

```ruby
Aidp.log_debug("mvp_scope_generator", "generating_scope", features_count: features.size)
Aidp.log_debug("feedback_analyzer", "analyzing_responses", responses: data.size, format: file_format)
Aidp.log_debug("iteration_plan_generator", "creating_tasks", feedback_items: items.size)
```

### Error Handling

- Specific error classes (e.g., `FeedbackParseError`, `InvalidMVPScopeError`)
- Always log rescued errors with context
- Let internal errors surface (fail fast)
- Only rescue to wrap external failures or clean up resources

### Testing Approach

- **Unit tests**: Mock external boundaries (AI calls, file I/O, user input)
- **Integration tests**: Use expect scripts for TUI flows
- **Dependency injection**: All components injectable via constructor
- **Test doubles**: Create test doubles with same interface as real dependencies

### Template Structure

All templates follow existing patterns:
- Markdown with front matter (YAML metadata)
- Clear sections with consistent formatting
- Examples and instructions inline
- Version control friendly

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| AI analysis quality varies | Use structured schemas, validate outputs, provide clear examples |
| Feedback data format diversity | Robust parser with validation, clear error messages |
| User confusion (waterfall vs agile) | Clear documentation, workflow selection prompts |
| Codebase analysis complexity | Reuse existing tree-sitter infrastructure, limit scope |

## Timeline Estimate

- **Phase 1**: 2-3 hours (foundation)
- **Phase 2**: 4-5 hours (MVP planning)
- **Phase 3**: 3-4 hours (feedback loop)
- **Phase 4**: 2-3 hours (legacy research)
- **Phase 5**: 4-5 hours (integration & testing)

**Total**: 15-20 hours

## Success Metrics

- All 7 acceptance criteria met
- Tests pass (85%+ coverage for business logic)
- StandardRB clean (no linting errors)
- Documentation complete and accurate
- Example workflows demonstrate all features

## Next Steps

1. Create task list with TodoWrite
2. Start Phase 1 implementation
3. Commit and push regularly to feature branch
4. Test incrementally as components are built
5. Create PR when all acceptance criteria are met

---

**References**:
- Issue #210: https://github.com/viamin/aidp/issues/210
- LLM Style Guide: `docs/LLM_STYLE_GUIDE.md`
- Existing Waterfall Implementation: `lib/aidp/planning/`
- Workflow Definitions: `lib/aidp/workflows/definitions.rb`
