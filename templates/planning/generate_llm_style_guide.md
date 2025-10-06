# Generate LLM Style Guide

Your task is to create a project-specific **LLM_STYLE_GUIDE.md** that will be used by AI agents working on this project. This guide should be concise, actionable, and tailored to this specific codebase.

## Context

You have access to the project directory. Examine the codebase to understand:

- Programming language(s) used
- Existing code style and patterns
- Testing framework and patterns
- Build tools and configuration
- Project structure
- Dependencies and frameworks

## Requirements

Create a file at `docs/LLM_STYLE_GUIDE.md` with the following sections:

### 1. Core Engineering Rules

- Single Responsibility Principle applications
- Code organization patterns specific to this project
- When to extract methods/classes/modules
- Dead code and TODO policies

### 2. Naming & Structure

- Language-specific naming conventions (if not standard)
- File organization patterns
- Module/package structure guidelines
- Public API design principles

### 3. Parameters & Data

- Parameter passing conventions
- Data structure preferences
- Configuration management patterns

### 4. Error Handling

- Error handling strategy for this project
- Logging patterns
- Exception types and when to use them
- Recovery strategies

### 5. Testing Contracts

- Testing philosophy for this project
- What to test vs what not to test
- Mocking/stubbing guidelines
- Test organization and naming
- Code coverage expectations

### 6. Framework-Specific Guidelines

- Key patterns from the frameworks used
- Anti-patterns to avoid
- Performance considerations
- Security guidelines

### 7. Dependencies & External Services

- Dependency injection patterns
- External service interaction patterns
- API client patterns
- Database interaction patterns (if applicable)

### 8. Build & Development

- Build commands and what they do
- Linting and formatting tools
- Pre-commit hooks (if any)
- Development workflow

### 9. Performance

- Performance considerations for this codebase
- Optimization strategies
- Caching patterns
- Resource management

### 10. Project-Specific Anti-Patterns

- Known anti-patterns in this codebase to avoid
- Previous mistakes to learn from
- Deprecated patterns to avoid

## Output Format

The LLM_STYLE_GUIDE.md should be:

- **Concise**: Use bullet points and tables where possible
- **Specific**: Reference actual code patterns from this project
- **Actionable**: Provide clear do's and don'ts
- **Scannable**: Use headers, lists, and formatting for easy reference

## Example Structure

```markdown
# Project LLM Style Guide

> Concise rules for AI agents working on [Project Name]. Based on [Language/Framework].

## 1. Core Engineering Rules
- [Specific rule based on this project]
- [Another specific rule]

## 2. Naming & Structure
- Classes: [convention]
- Files: [convention]
- [etc.]

[Continue with all sections...]
```

## Deliverable

Create `docs/LLM_STYLE_GUIDE.md` with all the sections above, tailored specifically to this project's codebase, languages, and frameworks.
