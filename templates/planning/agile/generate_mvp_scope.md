# Generate MVP Scope Definition

You are a product manager defining the Minimum Viable Product (MVP) scope.

## Input

Read:

- `.aidp/docs/PRD.md` - Product requirements document

## Your Task

Define the MVP scope by distinguishing must-have features from nice-to-have features, ensuring the MVP delivers core value while being achievable within constraints.

## Interactive Priority Collection

**Gather user priorities through TUI prompts:**

1. What is the primary goal of this MVP?
2. What is the main problem you're solving?
3. Who are your target users?
4. What is your target timeline for MVP launch?
5. Do you have any resource or technical constraints?

## MVP Scoping Principles

**MVP Must-Haves:**

- Features that deliver core value proposition
- Features required to solve the main problem
- Features necessary for minimal user workflows
- Features that validate key assumptions

**Nice-to-Have (Deferred):**

- Enhancements that improve but aren't essential
- Features that can be added based on user feedback
- Polish and optimization that can wait
- Features serving edge cases or secondary users

**Out of Scope:**

- Features not aligned with MVP goals
- Complex features that can wait for validation
- Features requiring significant unknowns
- Advanced capabilities beyond core use cases

## Implementation

**For Ruby/AIDP projects**, use the `ruby_aidp_planning` skill with `Aidp::Planning::Generators::MVPScopeGenerator`:

1. Parse PRD using `Aidp::Planning::Parsers::DocumentParser`
2. Collect user priorities interactively via TTY::Prompt
3. Generate MVP scope using `MVPScopeGenerator.generate(prd:, user_priorities:)`
4. Format as markdown using `format_as_markdown(mvp_scope)`
5. Write to `.aidp/docs/MVP_SCOPE.md`

**For other implementations**, create equivalent functionality that:

1. Parses the PRD to extract all features
2. Collects user priorities interactively
3. Uses AI to analyze features and determine MVP viability
4. Categorizes features as must-have, nice-to-have, or out-of-scope
5. Provides rationale for categorization decisions
6. Defines success criteria for MVP
7. Identifies assumptions and risks

## Output Structure

Write to `.aidp/docs/MVP_SCOPE.md` with:

### User Priorities

List of priorities collected from user input

### MVP Features (Must-Have)

For each feature:

- Name and description
- Rationale for inclusion in MVP
- Acceptance criteria

### Deferred Features (Nice-to-Have)

For each feature:

- Name and description
- Reason for deferral

### Out of Scope

List of explicitly excluded items

### Success Criteria

Measurable criteria for MVP success

### Assumptions

What we're assuming about users, technology, or market

### Risks

Potential issues and mitigation strategies

## AI Analysis Guidelines

Use AI Decision Engine to:

- Analyze each feature's importance to core value prop
- Assess complexity and effort required
- Consider user impact and business value
- Balance scope with timeline and resources
- Identify dependencies and prerequisites

Focus on delivering value quickly while managing risk and complexity.

## Output

Write complete MVP scope definition to `.aidp/docs/MVP_SCOPE.md` with:

- Clear categorization of all features
- Rationale for each decision
- Specific, measurable success criteria
- Realistic assumptions and identified risks
- Generated timestamp and metadata
