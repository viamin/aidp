# Generate LLM Style Guide

Your task is to create a project-specific **LLM_STYLE_GUIDE.md** and **STYLE_GUIDE.md** that will be used by AI agents working on this project. The LLM guide should be concise and actionable, while the full guide provides detailed context and rationale.

## Context

You have access to the project directory. Examine the codebase to understand:

- Programming language(s) used
- Existing code style and patterns
- Testing framework and patterns
- Build tools and configuration
- Project structure
- Dependencies and frameworks

## Two-Guide Approach

Create **TWO** complementary guides:

### 1. STYLE_GUIDE.md (Detailed Reference)

- Comprehensive explanations with examples
- Rationale and context for each guideline
- Deep dives into patterns and anti-patterns
- Located at `docs/STYLE_GUIDE.md`

### 2. LLM_STYLE_GUIDE.md (Quick Reference)

- Ultra-concise bullet points for quick scanning
- Each guideline references back to STYLE_GUIDE.md with line numbers
- Format: `Guideline text. STYLE_GUIDE:start-end`
- Located at `docs/LLM_STYLE_GUIDE.md`

## Requirements for LLM_STYLE_GUIDE.md

Create a file at `docs/LLM_STYLE_GUIDE.md` with the following sections, **adding line number references to the detailed guide**:

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

### STYLE_GUIDE.md Format

The detailed guide should be:

- **Comprehensive**: Full explanations with context and rationale
- **Example-driven**: Show code examples for each pattern
- **Well-structured**: Clear section headers that can be referenced by line number
- **Numbered sections**: Use consistent heading levels for easy reference

### LLM_STYLE_GUIDE.md Format

The concise guide should be:

- **Concise**: Use bullet points and tables where possible
- **Cross-referenced**: Every guideline includes `STYLE_GUIDE:start-end` reference
- **Specific**: Reference actual code patterns from this project
- **Actionable**: Provide clear do's and don'ts
- **Scannable**: Use headers, lists, and formatting for easy reference

## Creating Cross-References

### Step 1: Write STYLE_GUIDE.md first

```markdown
## Code Organization      # Line 18

### Class Structure       # Line 20
...detailed explanation...

### File Organization     # Line 45
...detailed explanation...
```

### Step 2: Add references to LLM_STYLE_GUIDE.md

For each guideline in the LLM guide, add the line range from STYLE_GUIDE.md:

```markdown
## 1. Core Engineering Rules

- Small objects, clear roles. Avoid god classes. `STYLE_GUIDE:18-50`
- Methods: do one thing; extract early. `STYLE_GUIDE:108-117`
```

### Step 3: Verify line numbers

Use `grep -n "^##" docs/STYLE_GUIDE.md` to find section headers and their line numbers.

## Example Structure

### STYLE_GUIDE.md

```markdown
# Project Style Guide

## Code Organization

Detailed explanation of code organization principles...

### Single Responsibility Principle

Detailed explanation with examples...

## Testing Guidelines

Comprehensive testing approach...
```

### LLM_STYLE_GUIDE.md

```markdown
# Project LLM Style Cheat Sheet

> Ultra-concise rules for automated coding agents.

## 1. Core Engineering Rules

- Small objects, clear roles. `STYLE_GUIDE:18-50`
- Methods: do one thing; extract early. `STYLE_GUIDE:108-117`

## 2. Testing Contracts

- Test public behavior only. `STYLE_GUIDE:1022-1261`
- Mock external boundaries only. `STYLE_GUIDE:1022-1261`
```

## Deliverable

Create **BOTH** files:

1. `docs/STYLE_GUIDE.md` - Comprehensive guide with detailed explanations
2. `docs/LLM_STYLE_GUIDE.md` - Quick reference with line number cross-references to the detailed guide

The guides should work together: AI agents read the concise LLM guide for quick decisions, then reference the detailed STYLE_GUIDE for context and examples when needed.
