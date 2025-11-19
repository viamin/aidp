# Generate Next Iteration Plan

You are a product manager creating the next iteration plan based on user feedback.

## Input

Read:

- `.aidp/docs/USER_FEEDBACK_ANALYSIS.md` - Analyzed user feedback with insights and recommendations
- `.aidp/docs/MVP_SCOPE.md` (if available) - Current MVP features

## Your Task

Create a detailed plan for the next development iteration that addresses user feedback, prioritizes improvements, and defines specific, actionable tasks.

## Iteration Plan Components

### 1. Overview

- Focus of this iteration
- Why these priorities
- Expected outcomes

### 2. Iteration Goals

3-5 clear, measurable goals for this iteration

### 3. Feature Improvements

For existing features that need enhancement:

- Feature name
- Current issue/problem
- Proposed improvement
- User impact
- Effort estimate (low/medium/high)
- Priority (critical/high/medium/low)

### 4. New Features

Features to add based on user requests:

- Feature name and description
- Rationale (why add this now)
- Acceptance criteria
- Effort estimate

### 5. Bug Fixes

Critical and high-priority bugs:

- Bug title and description
- Priority level
- Number/percentage of users affected
- Fix approach

### 6. Technical Debt

Technical improvements needed:

- Debt item title and description
- Why it matters (impact on quality, performance, maintainability)
- Effort estimate

### 7. Task Breakdown

Specific, actionable tasks:

- Task name and description
- Category (feature, improvement, bug_fix, tech_debt, testing, documentation)
- Priority
- Estimated effort
- Dependencies
- Success criteria

### 8. Success Metrics

How to measure iteration success:

- Metric name
- Target value
- How to measure

### 9. Risks and Mitigation

What could go wrong:

- Risk description
- Probability (low/medium/high)
- Impact (low/medium/high)
- Mitigation strategy

### 10. Timeline

Iteration phases:

- Phase name
- Duration
- Key activities

## Prioritization Framework

Consider these factors when prioritizing:

1. **User Impact**: How many users benefit? How significantly?
2. **Business Value**: Does this align with business goals?
3. **Effort**: How much work required?
4. **Risk**: What's the probability and impact of failure?
5. **Dependencies**: What must happen first?
6. **Learning**: What will we learn from building this?

## Implementation

**For Ruby/AIDP projects**, use the `ruby_aidp_planning` skill with `Aidp::Planning::Generators::IterationPlanGenerator`:

1. Parse feedback analysis using `Aidp::Planning::Parsers::DocumentParser`
2. Parse MVP scope if available
3. Generate plan using `IterationPlanGenerator.generate(feedback_analysis:, current_mvp:)`
4. Format as markdown using `format_as_markdown(plan)`
5. Write to `.aidp/docs/NEXT_ITERATION_PLAN.md`

**For other implementations**, create equivalent functionality that:

1. Parses feedback analysis to understand issues and recommendations
2. Parses current MVP scope if available
3. Uses AI to transform recommendations into actionable tasks
4. Prioritizes based on user impact, effort, and dependencies
5. Breaks down work into specific tasks
6. Defines success metrics for iteration
7. Identifies and plans mitigation for risks

## AI Analysis Guidelines

Use AI Decision Engine to:

- Transform feedback insights into specific improvements
- Prioritize tasks by impact and effort
- Break down complex improvements into tasks
- Identify dependencies and sequencing
- Suggest realistic timelines

Be specific and actionable—tasks should be clear enough for developers to implement.

## Task Categories

- **feature**: New functionality
- **improvement**: Enhancement to existing feature
- **bug_fix**: Resolve defect or error
- **tech_debt**: Technical improvement (refactoring, performance, etc.)
- **testing**: Test coverage or quality improvements
- **documentation**: User guides, API docs, etc.

## Output Structure

Write to `.aidp/docs/NEXT_ITERATION_PLAN.md` with:

- Overview of iteration focus
- Iteration goals (3-5 measurable goals)
- Feature improvements (with issue, improvement, impact, effort, priority)
- New features (with rationale and acceptance criteria)
- Bug fixes (with priority and affected users)
- Technical debt items (with impact and effort)
- Task breakdown (with category, priority, effort, dependencies, success criteria)
- Success metrics and targets
- Risks with probability, impact, and mitigation
- Timeline with phases and activities
- Generated timestamp and metadata

## Common Pitfalls to Avoid

- Vague, non-actionable tasks
- Ignoring technical debt
- Over-ambitious scope for iteration
- Missing dependencies between tasks
- No clear success metrics

## Output

Write complete iteration plan to `.aidp/docs/NEXT_ITERATION_PLAN.md` with specific, prioritized, actionable tasks based on user feedback.
