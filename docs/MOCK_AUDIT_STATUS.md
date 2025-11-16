# Mock Usage Audit Status - Issue #295

## Executive Summary

**Status**: In Progress (13% complete)
**Started**: 2025-11-16
**Total Violations**: 1,177 violations across 87 files
**Fixed**: 11 spec files + 2 production files improved
**Remaining**: 76 spec files with 1,100+ violations

## Audit Results

The comprehensive audit found widespread violation of the LLM_STYLE_GUIDE principle:
> "Mock ONLY external boundaries (network, filesystem, user input, APIs)"

### Violation Breakdown

| Pattern | Count | Description |
|---------|-------|-------------|
| `allow().to receive` | 662 | Mocking internal AIDP classes |
| `instance_variable` manipulation | 577 | Direct access to private state |
| `expect().to receive` | 86 | Testing implementation details |
| `instance_double` | 62 | Creating test doubles of internal classes |
| `allow_any_instance_of` | 31 | **Critical anti-pattern** |
| `class_double` | 7 | Mocking internal class methods |

### Files with Most Violations

1. `cli_spec.rb` - 200 violations
2. `enhanced_runner_spec.rb` - 111 violations
3. `harness/runner_spec.rb` - 70 violations
4. `status_display_spec.rb` - 64 violations
5. `wizard_spec.rb` - 61 violations

## Work Completed

### Spec Files Fixed (11)

1. **json_file_storage_spec.rb** - Removed redundant initialization tests
2. **ruby_maat_integration_spec.rb** - Removed DI verification test
3. **kb_inspector_spec.rb** - Replaced instance_variable_set with proper setup
4. **tree_sitter_grammar_loader_spec.rb** - Removed initialization tests
5. **terminal_io_spec.rb** - Removed redundant test
6. **enhanced_input_spec.rb** - Used new attr_readers instead of instance_variable_get
7. **issue_importer_spec.rb** - Removed redundant test
8. **workflow_selector_spec.rb** - Removed initialization tests
9. **provider_config_spec.rb** - Removed initialization test
10. **mcp_dashboard_spec.rb** - Removed initialization tests
11. **tree_sitter_scan_spec.rb** - Removed initialization tests

### Production Files Improved (2)

1. **enhanced_input.rb** - Added `attr_reader :use_reline, :show_hints` for proper API
2. **jobs_command.rb** - Added dependency injection for `file_manager` and `background_runner`

### Additional Work

3. **guided_agent.rb** - Added dependency injection for `config_manager` and `provider_manager`

## Fix Patterns Demonstrated

### Pattern 1: Remove Redundant Initialization Tests

**Problem**: Tests checking internal state via `instance_variable_get`

```ruby
# BEFORE - Testing implementation details
describe "#initialize" do
  it "initializes with project directory" do
    expect(loader.instance_variable_get(:@project_dir)).to eq(temp_dir)
  end
end

# AFTER - Remove redundant test
# Initialization is tested implicitly through functionality tests
```

### Pattern 2: Add Public API Instead of Testing Private State

**Problem**: Tests need to verify state but access it via instance variables

```ruby
# BEFORE - In spec
expect(enhanced_input.instance_variable_get(:@use_reline)).to be true

# AFTER - In production code
class EnhancedInput
  attr_reader :use_reline, :show_hints  # Expose as public API
end

# In spec
expect(enhanced_input.use_reline).to be true
```

### Pattern 3: Replace instance_variable_set with Dependency Injection

**Problem**: Tests manipulate internal state directly

```ruby
# BEFORE - In spec
let(:jobs_command) do
  described_class.new(...).tap do |cmd|
    cmd.instance_variable_set(:@file_manager, file_manager)
    cmd.instance_variable_set(:@background_runner, background_runner)
  end
end

# AFTER - In production code
def initialize(..., file_manager: nil, background_runner: nil)
  @file_manager = file_manager || Aidp::Storage::FileManager.new(...)
  @background_runner = background_runner || Aidp::Jobs::BackgroundRunner.new(...)
end

# In spec
let(:jobs_command) do
  described_class.new(
    ...,
    file_manager: file_manager,
    background_runner: background_runner
  )
end
```

### Pattern 4: Fix allow_any_instance_of with Dependency Injection

**Problem**: Tests use `allow_any_instance_of` to mock internal classes

```ruby
# BEFORE - Anti-pattern
allow_any_instance_of(Aidp::Harness::ConfigManager).to receive(:config).and_return(...)

# AFTER - Production code supports DI
def initialize(..., config_manager: nil, provider_manager: nil)
  @config_manager = config_manager || Aidp::Harness::ConfigManager.new(...)
  @provider_manager = provider_manager || Aidp::Harness::ProviderManager.new(...)
end

# In spec - Create test doubles
let(:mock_config_manager) { instance_double(Aidp::Harness::ConfigManager, config: {...}) }
let(:agent) { described_class.new(..., config_manager: mock_config_manager) }
```

## Remaining Work

### High Priority (31 violations)

**`allow_any_instance_of` violations** - These are the most critical anti-patterns:

1. `spec/aidp/init/runner_spec.rb` (2 violations)
2. `spec/aidp/watch/change_request_processor_spec.rb` (1 violation)
3. `spec/aidp/watch/review_processor_spec.rb` (12 violations)
4. `spec/aidp/workflows/guided_agent_spec.rb` (12 violations) - DI added to production code
5. `spec/system/guided_workflow_golden_path_spec.rb` (4 violations)

**Recommended approach**: Add dependency injection to the production classes, then update specs to use test doubles via DI.

### Medium Priority (662 violations)

**Internal class mocking** - Files mocking `Aidp::` classes with `allow().to receive`:

Major files to address:
- `cli_spec.rb` (massive, 200 violations)
- `enhanced_runner_spec.rb` (111 violations)
- `harness/runner_spec.rb` (70 violations)
- Provider specs (anthropic, gemini, etc.) - These mock `Aidp::Util`, `described_class`

**Recommended approach**:
1. Add dependency injection to production classes
2. Replace `allow(Aidp::SomeClass).to receive(...)` with proper test doubles
3. For external dependencies like `Aidp::Util.which`, add abstraction layer

### Lower Priority (577 violations)

**`instance_variable` manipulation** - Mostly in test setup:

Files with many violations:
- `enhanced_runner_spec.rb` (101 violations)
- `harness/runner_spec.rb` (70 violations)
- `status_display_spec.rb` (58 violations)
- `wizard_spec.rb` (45 violations)

**Recommended approach**:
1. Remove simple initialization tests (as demonstrated)
2. For setup code using `instance_variable_set`, refactor to use public methods or DI
3. For state verification using `instance_variable_get`, add readers or test public behavior

## Tools Created

### Audit Script: `scripts/audit_mocks.rb`

Comprehensive audit tool that can be run anytime to check for violations:

```bash
ruby scripts/audit_mocks.rb
```

Generates:
- Console report with detailed violations
- `mock_audit_report.json` with full details

### Allowed Mocks

The audit script recognizes these as legitimate external dependencies:
- TTY::* (user input/output)
- Net::HTTP, Faraday, etc. (network)
- File, Dir, FileUtils (filesystem when testing file handling)
- Time, Date (system time)
- External AI clients (Anthropic::Client, etc.)

## Next Steps

1. **Continue fixing allow_any_instance_of violations** (highest priority)
   - Update specs for `guided_agent_spec.rb` to use new DI
   - Fix `review_processor_spec.rb` by adding DI to ReviewProcessor
   - Fix `guided_workflow_golden_path_spec.rb` integration tests

2. **Tackle major files with internal class mocking**
   - Start with provider specs (relatively isolated)
   - Then tackle CLI specs
   - Finally address harness specs (most complex)

3. **Clean up remaining instance_variable manipulations**
   - Continue pattern of removing redundant init tests
   - Add DI where needed for test setup

4. **Run test suite** after each major batch of fixes to catch regressions

5. **Update contributing docs** with testing best practices from this work

## Estimated Effort

- **Completed**: ~8 hours
- **Remaining**: ~40-60 hours for complete fix
- **Quick wins** (fix all allow_any_instance_of): ~4-6 hours
- **Medium effort** (fix provider and CLI specs): ~15-20 hours
- **Full completion** (all 1,177 violations): ~50+ hours

## References

- **Issue**: https://github.com/viamin/aidp/issues/295
- **Style Guide**: `docs/LLM_STYLE_GUIDE.md` (lines 87-120 for testing rules)
- **Audit Report**: `mock_audit_report.json`
- **Branch**: `claude/implement-issue-295-012hefuYSYi4xYRtqGkZJJXJ`
