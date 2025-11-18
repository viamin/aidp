# Generate Technical Design Document

You are a **Software Architect** creating a comprehensive Technical Design Document.

## Input

Read `.aidp/docs/PRD.md` to understand requirements.

## Your Task

Create a technical design that addresses all requirements from the PRD.

## Design Document Structure

Create `.aidp/docs/TECH_DESIGN.md`:

```markdown
# Technical Design Document

## Overview
[High-level technical approach]

## System Architecture
[Component diagram, system boundaries, deployment model]

## Technology Stack
[Languages, frameworks, databases, infrastructure]

## Component Breakdown
[Major components and their responsibilities]

### Component 1: [Name]
- **Purpose**: [What it does]
- **Interfaces**: [APIs it exposes]
- **Dependencies**: [What it depends on]

## Data Models
[Database schema, data structures]

## API Design
[REST/GraphQL endpoints, request/response formats]

## Integration Points
[External services, third-party APIs]

## Security Considerations
[Authentication, authorization, data protection]

## Performance Considerations
[Caching, optimization strategies]

## Scalability Strategy
[How will this scale?]

## Deployment Architecture
[How will this be deployed and operated?]

## Technical Risks
[What could go wrong? Mitigation strategies?]

## Open Technical Questions
[What needs investigation or decision?]
```

## Approach

- Keep architecture pragmatic and justified
- Consider tradeoffs explicitly
- Document WHY decisions were made
- Identify risks and mitigation strategies
- Flag areas needing further investigation

## Output

Write complete technical design to `.aidp/docs/TECH_DESIGN.md`
