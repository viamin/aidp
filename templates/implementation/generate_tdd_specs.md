# Generate TDD Test Specifications

You are creating **test specifications** following Test-Driven Development (TDD) principles.

## TDD Philosophy

### RED → GREEN → REFACTOR

1. **RED**: Write failing tests that specify desired behavior
2. **GREEN**: Write minimal code to make tests pass
3. **REFACTOR**: Improve code while keeping tests green

## Context

Read these artifacts to understand requirements:

- `.aidp/docs/PRD.md` - Product requirements (if exists)
- `.aidp/docs/TECH_DESIGN.md` - Technical design (if exists)
- `.aidp/docs/TASK_LIST.md` - Task breakdown (if exists)
- `.aidp/docs/WBS.md` - Work breakdown structure (if exists)

## Your Task

Generate comprehensive test specifications BEFORE implementation.

## Test Specification Structure

Create `docs/tdd_specifications.md`:

```markdown
# TDD Test Specifications

Generated: <timestamp>

## Overview

This document defines tests to write BEFORE implementing features.
Follow TDD: write tests first, watch them fail, then implement.

## Test Categories

### Unit Tests

#### Feature: [Feature Name]

**Test Cases:**
1. **should handle valid input**
   - Given: Valid input parameters
   - When: Feature is invoked
   - Then: Returns expected output
   - Status: ⭕ Not yet written

2. **should reject invalid input**
   - Given: Invalid parameters
   - When: Feature is invoked
   - Then: Raises appropriate error
   - Status: ⭕ Not yet written

3. **should handle edge cases**
   - Given: Edge case inputs (empty, nil, boundary values)
   - When: Feature is invoked
   - Then: Handles gracefully
   - Status: ⭕ Not yet written

### Integration Tests

#### Integration: [Component A + Component B]

**Test Cases:**
1. **should integrate successfully**
   - Given: Both components configured
   - When: Integration point is called
   - Then: Data flows correctly
   - Status: ⭕ Not yet written

### Acceptance Tests

#### User Story: [As a user, I want to...]

**Test Cases:**
1. **should complete user workflow**
   - Given: User starts workflow
   - When: User performs actions
   - Then: Achieves expected outcome
   - Status: ⭕ Not yet written

## Test Implementation Order

1. **Phase 1: Critical Path**
   - Write tests for core functionality first
   - Focus on happy path
   - Estimated: X hours

2. **Phase 2: Edge Cases**
   - Add tests for error conditions
   - Boundary testing
   - Estimated: Y hours

3. **Phase 3: Integration**
   - Test component interactions
   - End-to-end workflows
   - Estimated: Z hours

## Coverage Goals

- **Unit Tests:** 90%+ coverage
- **Integration Tests:** All integration points
- **Acceptance Tests:** All user stories from PRD

## Notes

- Tests should be **fast** (< 1s per test ideal)
- Tests should be **isolated** (no shared state)
- Tests should be **deterministic** (same result every time)
- Mock external dependencies (APIs, databases, file I/O)
- Test behavior, not implementation

## Next Steps

1. Review this specification
2. Write tests (they should fail - RED)
3. Implement minimal code (make tests pass - GREEN)
4. Refactor code (keep tests green - REFACTOR)
```

## TDD Best Practices

### 1. Test One Thing

Each test should verify ONE behavior.

❌ BAD: Testing multiple behaviors in one test
✅ GOOD: Separate tests for separate behaviors

### 2. Use Descriptive Names

Test names should describe the behavior being tested, not implementation details.

### 3. Follow Given-When-Then

Structure tests clearly:

- **GIVEN**: Setup test data and preconditions
- **WHEN**: Execute the behavior being tested
- **THEN**: Verify expected outcomes

### 4. Mock External Dependencies

Don't hit real APIs, databases, or file systems in unit tests.
Use test doubles/mocks for external dependencies.

### 5. Test Behavior, Not Implementation

❌ BAD: Testing that internal helper methods are called
✅ GOOD: Testing that public interface returns correct results

## Framework-Specific Implementation

**For language/framework-specific test generation, use the appropriate skill:**

- **Ruby/RSpec**: Use `ruby_rspec_tdd` skill for RSpec-specific test files, fixtures, and syntax
- **Python/pytest**: Use `python_pytest_tdd` skill for pytest-specific implementation
- **JavaScript/Jest**: Use `javascript_jest_tdd` skill for Jest-specific implementation
- **Other frameworks**: Use ZFC skill matching to find appropriate testing skill

## Skill Delegation

After creating the language-agnostic test specification above, delegate to the framework-specific skill to generate:

1. **Skeleton test files** in the framework's directory structure and naming conventions
2. **Test fixtures** or factories in the framework's format
3. **Test execution commands** for the specific framework
4. **Framework-specific examples** and best practices

**Example skill invocation:**

For a Ruby project using RSpec:

```text
Use the `ruby_rspec_tdd` skill to:
1. Generate skeleton RSpec test files in spec/ directory
2. Create FactoryBot factories or fixtures as needed
3. Provide RSpec-specific examples and matchers
4. Include bundle exec rspec execution commands
```

For a Python project using pytest:

```text
Use the `python_pytest_tdd` skill to:
1. Generate skeleton pytest test files in tests/ directory
2. Create pytest fixtures as needed
3. Provide pytest-specific examples and assertions
4. Include pytest execution commands
```

## Output Files

Generate:

1. **`docs/tdd_specifications.md`** - Framework-agnostic test specifications (as shown above)
2. **Framework-specific test files** - Via appropriate skill delegation
3. **Test data/fixtures** - Via appropriate skill delegation

## Remember

- **Write tests FIRST** - before any implementation
- **Watch tests FAIL** - ensure they actually test something
- **Write minimal code** - just enough to pass tests
- **Refactor** - improve code with confidence (tests protect you)
- **Use skills for framework-specific implementation** - keep this template language-agnostic

**TDD gives you confidence, better design, and executable documentation!** 🧪
