# Generate TDD Test Specifications

You are creating **test specifications** following Test-Driven Development (TDD) principles.

## TDD Philosophy

**RED → GREEN → REFACTOR**

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

**File:** `spec/unit/feature_name_spec.rb`

**Test Cases:**
1. **should handle valid input**
   - Given: Valid input parameters
   - When: Feature is invoked
   - Then: Returns expected output
   - Status: ⭕ Not yet written

2. **should reject invalid input**
   - Given: Invalid parameters
   - When: Feature is invoked
   - Then: Raises ValidationError
   - Status: ⭕ Not yet written

3. **should handle edge cases**
   - Given: Edge case inputs (empty, nil, boundary values)
   - When: Feature is invoked
   - Then: Handles gracefully
   - Status: ⭕ Not yet written

### Integration Tests

#### Integration: [Component A + Component B]

**File:** `spec/integration/component_integration_spec.rb`

**Test Cases:**
1. **should integrate successfully**
   - Given: Both components configured
   - When: Integration point is called
   - Then: Data flows correctly
   - Status: ⭕ Not yet written

### Acceptance Tests

#### User Story: [As a user, I want to...]

**File:** `spec/acceptance/user_story_spec.rb`

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

## Test Data

### Fixtures

```ruby
# spec/fixtures/sample_data.rb
VALID_INPUT = {
  field: "value",
  # ...
}

INVALID_INPUT = {
  field: nil,
  # ...
}
```

### Factories

```ruby
# spec/factories/model_factory.rb
FactoryBot.define do
  factory :model do
    field { "value" }
  end
end
```

## Coverage Goals

- **Unit Tests:** 90%+ coverage
- **Integration Tests:** All integration points
- **Acceptance Tests:** All user stories from PRD

## Test Execution

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/unit/feature_name_spec.rb

# Run tests with coverage
COVERAGE=true bundle exec rspec
```

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

## Actual Test Generation

Based on the requirements, also generate SKELETON test files:

### Example Unit Test Skeleton

```ruby
# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/your_module/feature_name"

RSpec.describe YourModule::FeatureName do
  describe "#main_method" do
    context "with valid input" do
      it "returns expected output" do
        # GIVEN: Valid input
        input = valid_test_data

        # WHEN: Method is called
        result = subject.main_method(input)

        # THEN: Expected output
        expect(result).to eq(expected_output)
      end
    end

    context "with invalid input" do
      it "raises ValidationError" do
        # GIVEN: Invalid input
        input = invalid_test_data

        # WHEN/THEN: Should raise error
        expect {
          subject.main_method(input)
        }.to raise_error(ValidationError)
      end
    end

    context "with edge cases" do
      it "handles nil gracefully" do
        expect {
          subject.main_method(nil)
        }.to raise_error(ArgumentError)
      end

      it "handles empty input" do
        result = subject.main_method({})
        expect(result).to be_nil
      end
    end
  end
end
```

## TDD Best Practices

### 1. Test One Thing

Each test should verify ONE behavior.

❌ BAD:
```ruby
it "processes user and sends email and logs activity" do
  # Testing 3 things!
end
```

✅ GOOD:
```ruby
it "processes user data" do
  # Tests only data processing
end

it "sends confirmation email" do
  # Tests only email
end
```

### 2. Use Descriptive Names

Test names should describe the behavior:

```ruby
describe "#calculate_total" do
  it "sums line item prices" do
  it "applies discount when coupon is valid" do
  it "raises error when items array is empty" do
end
```

### 3. Follow Given-When-Then

Structure tests clearly:

```ruby
it "calculates total with discount" do
  # GIVEN: Setup test data
  items = [create(:item, price: 100)]
  coupon = create(:coupon, discount: 0.1)

  # WHEN: Execute the behavior
  total = calculator.calculate_total(items, coupon)

  # THEN: Verify expectations
  expect(total).to eq(90)
end
```

### 4. Mock External Dependencies

Don't hit real APIs, databases, or file systems:

```ruby
it "fetches user data from API" do
  # Mock the API client
  api_client = instance_double(APIClient)
  allow(api_client).to receive(:fetch_user).and_return(mock_user_data)

  service = UserService.new(api_client: api_client)
  user = service.get_user(123)

  expect(user.name).to eq("Test User")
end
```

### 5. Test Behavior, Not Implementation

❌ BAD:
```ruby
it "calls internal helper method" do
  expect(subject).to receive(:internal_helper)
  subject.public_method
end
```

✅ GOOD:
```ruby
it "returns formatted output" do
  result = subject.public_method
  expect(result).to match(/\d{3}-\d{3}-\d{4}/)
end
```

## Output Files

Generate:
1. **`docs/tdd_specifications.md`** - Complete test specifications
2. **Skeleton test files** in `spec/` directory structure
3. **Test data fixtures** in `spec/fixtures/`

## Remember

- **Write tests FIRST** - before any implementation
- **Watch tests FAIL** - ensure they actually test something
- **Write minimal code** - just enough to pass tests
- **Refactor** - improve code with confidence (tests protect you)

**TDD gives you confidence, better design, and executable documentation!** 🧪
