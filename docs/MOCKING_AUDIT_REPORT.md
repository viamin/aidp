# Mocking Audit Report: Issue #163

**Date**: 2025-10-22
**Issue**: <https://github.com/viamin/aidp/issues/163>
**Auditor**: Claude Code
**Scope**: Audit inappropriate or overuse of mocking in test suite per LLM_STYLE_GUIDE

## Executive Summary

This audit identified **200+ violations** across **95+ spec files** where mocking practices violate the LLM_STYLE_GUIDE and could allow production bugs to slip through the test suite.

### Progress Status

**✅ P0 COMPLETED** - All critical test-specific production code removed
**🔄 P1 IN PROGRESS** - 1 of ~50 violations fixed
**⏸️ P2 PENDING** - 130+ violations remaining
**⏸️ P3 PENDING** - 50+ violations remaining

### Critical Findings

1. **🔴 CRITICAL: Mock Methods in Production Code** - ~~4 instances~~ → ✅ **0 instances (FIXED)**
2. **🟠 HIGH: Missing Dependency Injection for TTY::Prompt** - 15+ instances
3. **🟡 MEDIUM: Using `allow_any_instance_of` Anti-Pattern** - ~~35+ instances~~ → **34+ instances** (1 fixed)
4. **🟡 MEDIUM: Testing Private Methods Directly** - 70+ instances
5. **🟢 LOW: Mocking Internal Methods Instead of External Boundaries** - 60+ instances
6. **🟢 LOW: File I/O Mocking Without Proper Abstraction** - 50+ instances

---

## Key Style Guide Rules (Reference)

From [docs/LLM_STYLE_GUIDE.md](docs/LLM_STYLE_GUIDE.md):

- **Line 84**: "Test public behavior; don't mock internal private methods"
- **Line 85**: "Mock ONLY external boundaries (network, filesystem, user input, provider APIs)"
- **Line 87**: "NEVER put mock methods in production code - use dependency injection instead"
- **Line 92**: "Use constructor dependency injection for TTY::Prompt, HTTP clients, file I/O"
- **Line 108**: "Don't test: Private methods, outgoing queries, implementation details"

---

## Category 1: 🔴 CRITICAL - Mock Methods in Production Code

**Rule Violated**: "NEVER put mock methods in production code - use dependency injection instead"

### Violation 1.1: ProviderManager Test Environment Checks

**File**: [lib/aidp/harness/provider_manager.rb:1073-1082](lib/aidp/harness/provider_manager.rb#L1073-L1082)

```ruby
def provider_cli_available?(provider_name)
  # Handle test environment overrides
  if defined?(RSpec) || ENV["RSPEC_RUNNING"]
    # Force claude to be missing for testing
    if ENV["AIDP_FORCE_CLAUDE_MISSING"] == "1" && normalized == "claude"
      return [false, "binary_missing"]
    end
    # Force claude to be available for testing
    if ENV["AIDP_FORCE_CLAUDE_AVAILABLE"] == "1" && normalized == "claude"
      return [true, "available"]
    end
  end
```

**Impact**: Production code behaves differently in tests vs. production. This is a **HIGH RISK** for production bugs slipping through.

**Fix**:

```ruby
class ProviderManager
  def initialize(configuration, command_executor: Aidp::Util)
    @configuration = configuration
    @command_executor = command_executor
  end

  def provider_cli_available?(provider_name)
    # Remove ALL test environment checks
    @command_executor.which(binary_name)
  end
end

# In tests:
let(:mock_executor) { instance_double("CommandExecutor") }
let(:manager) { described_class.new(configuration, command_executor: mock_executor) }
```

### Violation 1.2: EnhancedTUI Headless Mode Detection

**File**: [lib/aidp/harness/ui/enhanced_tui.rb:32](lib/aidp/harness/ui/enhanced_tui.rb#L32)

```ruby
@headless = !!(defined?(RSpec) || ENV["RSPEC_RUNNING"] || $stdin.nil? || !$stdin.tty?)
```

**Impact**: Production code checks for RSpec, making it test-aware.

**Fix**:

```ruby
def initialize(state_manager, condition_detector, tty: $stdin)
  @headless = !!(tty.nil? || !tty.tty?)
end

# In tests:
let(:mock_tty) { double("TTY", tty?: false) }
let(:tui) { described_class.new(state_manager, condition_detector, tty: mock_tty) }
```

### Violation 1.3: CLI Step Execution Test Detection

**File**: [lib/aidp/cli.rb:507](lib/aidp/cli.rb#L507)

```ruby
if step.start_with?("00_PRD") && (defined?(RSpec) || ENV["RSPEC_RUNNING"])
```

**Impact**: Business logic changes based on test environment detection.

**Fix**: Remove the test detection entirely. Make behavior explicit through configuration or parameters.

---

## Category 2: 🟠 HIGH - Missing Dependency Injection for TTY::Prompt

**Rule Violated**: "Use constructor dependency injection for TTY::Prompt, HTTP clients, file I/O"

### Violation 2.1: CLI Workstream Command

**File**: [lib/aidp/cli.rb:1247](lib/aidp/cli.rb#L1247)

```ruby
when "rm"
  unless force
    prompt = TTY::Prompt.new  # VIOLATION: Created inline without DI
    confirm = prompt.yes?("Remove workstream '#{slug}'?")
    return unless confirm
  end
```

**Current Test Violation**: [spec/aidp/cli_workstream_spec.rb:194](spec/aidp/cli_workstream_spec.rb#L194)

```ruby
allow_any_instance_of(TTY::Prompt).to receive(:yes?).and_return(true)
```

**Impact**: Tests use `allow_any_instance_of` anti-pattern. Cannot test CLI in isolation from TTY::Prompt.

**Fix**:

```ruby
# In CLI class
class CLI
  def initialize(prompt: TTY::Prompt.new)
    @prompt = prompt
  end

  def run_ws_command(args)
    # ...
    unless force
      confirm = @prompt.yes?("Remove workstream '#{slug}'?")
      return unless confirm
    end
  end
end

# In spec
let(:mock_prompt) { instance_double(TTY::Prompt) }
let(:cli) { described_class.new(prompt: mock_prompt) }

before do
  allow(mock_prompt).to receive(:yes?).and_return(true)
end
```

### Additional TTY::Prompt Violations

All need dependency injection:

- [spec/aidp/harness/ui/progress_display_spec.rb:154](spec/aidp/harness/ui/progress_display_spec.rb#L154)
- [spec/aidp/harness/ui/progress_display_spec.rb:183](spec/aidp/harness/ui/progress_display_spec.rb#L183)
- [spec/aidp/harness/ui/question_collector_spec.rb:13](spec/aidp/harness/ui/question_collector_spec.rb#L13)
- [spec/aidp/harness/ui/question_collector_spec.rb:21](spec/aidp/harness/ui/question_collector_spec.rb#L21)
- [spec/aidp/harness/ui/question_collector_spec.rb:30](spec/aidp/harness/ui/question_collector_spec.rb#L30)

---

## Category 3: 🟡 MEDIUM - Using `allow_any_instance_of` Anti-Pattern

**Issue**: `allow_any_instance_of` is a code smell indicating missing dependency injection. Makes tests brittle and unclear.

### Violation 3.1: WorkstreamExecutor Runner Mocking

**File**: [spec/aidp/workstream_executor_spec.rb:101](spec/aidp/workstream_executor_spec.rb#L101)

```ruby
allow_any_instance_of(Aidp::Harness::Runner).to receive(:run).and_return({status: "completed"})
```

**Impact**: Mocking `.run` prevents testing actual integration between WorkstreamExecutor and Runner.

**Fix**:

```ruby
let(:mock_runner) { instance_double(Aidp::Harness::Runner) }
before do
  allow(Aidp::Harness::Runner).to receive(:new).and_return(mock_runner)
  allow(mock_runner).to receive(:run).and_return({status: "completed"})
end
```

### Complete List of `allow_any_instance_of` Violations

- [spec/aidp/cli_workstream_spec.rb:194](spec/aidp/cli_workstream_spec.rb#L194) - TTY::Prompt
- [spec/aidp/cli_workstream_spec.rb:221](spec/aidp/cli_workstream_spec.rb#L221) - TTY::Prompt
- [spec/aidp/cli_workstream_spec.rb:239](spec/aidp/cli_workstream_spec.rb#L239) - TTY::Prompt
- [spec/aidp/cli_workstream_spec.rb:259](spec/aidp/cli_workstream_spec.rb#L259) - TTY::Prompt
- [spec/aidp/cli_workstream_spec.rb:283](spec/aidp/cli_workstream_spec.rb#L283) - TTY::Prompt
- [spec/aidp/jobs/background_runner_spec.rb:16](spec/aidp/jobs/background_runner_spec.rb#L16) - display_message
- [spec/aidp/cli/issue_importer_spec.rb:29](spec/aidp/cli/issue_importer_spec.rb#L29) - gh_cli_available?
- [spec/aidp/harness/provider_failure_exhausted_spec.rb:19](spec/aidp/harness/provider_failure_exhausted_spec.rb#L19) - ProviderManager
- [spec/aidp/harness/provider_failure_exhausted_spec.rb:22](spec/aidp/harness/provider_failure_exhausted_spec.rb#L22) - ProviderManager
- [spec/aidp/harness/error_handler_spec.rb:24](spec/aidp/harness/error_handler_spec.rb#L24) - sleep
- [spec/aidp/harness/provider_manager_spec.rb:16-17](spec/aidp/harness/provider_manager_spec.rb#L16-L17) - Multiple methods
- [spec/aidp/harness/performance_simple_spec.rb:350-357](spec/aidp/harness/performance_simple_spec.rb#L350-L357) - 7 different methods

**All require**: Dependency injection pattern instead of any_instance_of.

---

## Category 4: 🟡 MEDIUM - Testing Private Methods Directly

**Rule Violated**: "Don't test: Private methods, outgoing queries, implementation details"

### Violation 4.1: Anthropic Provider Private Method Testing

**File**: [spec/aidp/providers/anthropic_spec.rb](spec/aidp/providers/anthropic_spec.rb)
**Lines**: 238, 245, 252, 259, 268, 275, 282, 287, 298, 318, 508, 521, 532, 541, 552, 560, 567, 575, 582, 591, 600, 605, 611

```ruby
result = provider.__send__(:parse_stream_json_output, output)  # VIOLATION
servers = provider.__send__(:parse_claude_mcp_output, output)  # VIOLATION
```

**Impact**:

1. Tests implementation details, not public behavior
2. Private methods can change without breaking the contract
3. Prevents refactoring

**Fix**: Test only the public `send_message` method which uses these private methods:

```ruby
# Instead of testing parse_stream_json_output directly:
it "handles streaming JSON response" do
  allow(provider).to receive(:debug_execute_command).and_return(
    double(exit_status: 0, out: '{"type":"content_block_delta","delta":{"text":"Hello"}}')
  )

  result = provider.send_message(prompt: "test")
  expect(result).to eq("Hello")
end
```

### Additional Private Method Test Violations

- [spec/aidp/providers/cursor_spec.rb:190-239](spec/aidp/providers/cursor_spec.rb#L190-L239) - parse_mcp_servers_output
- [spec/aidp/execute/interactive_repl_spec.rb:75-150](spec/aidp/execute/interactive_repl_spec.rb#L75-L150) - handle_command
- [spec/aidp/execute/runner_spec.rb:255-359](spec/aidp/execute/runner_spec.rb#L255-L359) - build_harness_context, process_result_for_harness
- [spec/aidp/analyze/runner_spec.rb:165-185](spec/aidp/analyze/runner_spec.rb#L165-L185) - Private methods
- [spec/aidp/watch/plan_generator_spec.rb:182-244](spec/aidp/watch/plan_generator_spec.rb#L182-L244) - Multiple private methods
- [spec/aidp/daemon/runner_spec.rb:69-93](spec/aidp/daemon/runner_spec.rb#L69-L93) - Private methods
- [spec/aidp/analyze/ruby_maat_integration_spec.rb:34-72](spec/aidp/analyze/ruby_maat_integration_spec.rb#L34-L72) - Private methods

**Fix for all**: Test through public interface or make methods public if they need direct testing.

---

## Category 5: 🟢 LOW - Mocking Internal Methods Instead of External Boundaries

**Rule Violated**: "Mock ONLY external boundaries (network, filesystem, user input, provider APIs)"

### Violation 5.1: Provider Specs Mocking Internal Debug Methods

**File**: [spec/aidp/providers/anthropic_spec.rb:49-55](spec/aidp/providers/anthropic_spec.rb#L49-L55)

```ruby
before do
  allow(provider).to receive(:debug_execute_command).and_return(successful_result)
  allow(provider).to receive(:debug_command)
  allow(provider).to receive(:debug_provider)
  allow(provider).to receive(:debug_log)
  allow(provider).to receive(:debug_error)
  allow(provider).to receive(:display_message)
  allow(provider).to receive(:calculate_timeout).and_return(300)
end
```

**Impact**:

1. `debug_execute_command` wraps TTY::Command (external boundary)
2. Tests mock the wrapper instead of actual external dependency
3. `calculate_timeout` is internal business logic that should be tested, not mocked

**Fix**: Mock the actual external dependency (TTY::Command):

```ruby
let(:mock_command) { instance_double(TTY::Command) }

before do
  allow(TTY::Command).to receive(:new).and_return(mock_command)
  allow(mock_command).to receive(:run!).and_return(
    double(exit_status: 0, out: "Test response", err: "")
  )
end
```

### Additional Internal Method Mocking Violations

Similar patterns in:

- [spec/aidp/providers/cursor_spec.rb](spec/aidp/providers/cursor_spec.rb) - debug methods
- [spec/aidp/providers/opencode_spec.rb](spec/aidp/providers/opencode_spec.rb) - debug methods
- [spec/aidp/harness/provider_manager_spec.rb:16-17](spec/aidp/harness/provider_manager_spec.rb#L16-L17) - provider_cli_available?

**Fix**: Don't mock debug methods. Let them run or disable debug mode via ENV.

---

## Category 6: 🟢 LOW - File I/O Mocking Without Proper Abstraction

**Rule Violated**: "Mock ONLY external boundaries" - but global File/Dir mocking creates issues.

### Pattern: Global File/Dir/FileUtils Mocking

**Files with this pattern**:

- [spec/aidp/execute/work_loop_runner_spec.rb:24-27](spec/aidp/execute/work_loop_runner_spec.rb#L24-L27)
- [spec/aidp/execute/runner_spec.rb:15-28](spec/aidp/execute/runner_spec.rb#L15-L28)
- [spec/aidp/analyze/runner_spec.rb:15-28](spec/aidp/analyze/runner_spec.rb#L15-L28)
- [spec/aidp/harness/state_manager_spec.rb:11-17](spec/aidp/harness/state_manager_spec.rb#L11-L17)
- [spec/aidp/providers/cursor_spec.rb:132-176](spec/aidp/providers/cursor_spec.rb#L132-L176)

```ruby
allow(File).to receive(:exist?).and_return(true)
allow(File).to receive(:read).and_return("")
allow(FileUtils).to receive(:mkdir_p)
```

**Impact**:

1. Global mocking affects all code in the test
2. Prevents testing actual file operations
3. Makes tests fragile - must mock every file operation
4. Can hide bugs in file handling

**Fix Option 1**: Use real temp directories:

```ruby
let(:project_dir) { Dir.mktmpdir("aidp-test") }

after do
  FileUtils.rm_rf(project_dir)
end

# Let the code create real files - they're isolated in temp dir
```

**Fix Option 2**: Inject a FileSystem abstraction:

```ruby
class FileSystemAdapter
  def read(path)
    File.read(path)
  end

  def write(path, content)
    File.write(path, content)
  end

  def exist?(path)
    File.exist?(path)
  end
end

# In production code:
def initialize(fs: FileSystemAdapter.new)
  @fs = fs
end

# In tests:
let(:mock_fs) { instance_double(FileSystemAdapter) }
let(:runner) { described_class.new(fs: mock_fs) }
```

---

## Category 7: Mocking Internal Business Logic

### Violation: Mocking Validation Methods

**File**: [spec/aidp/harness/configuration_spec.rb:13](spec/aidp/harness/configuration_spec.rb#L13)

```ruby
allow(Aidp::Config).to receive(:validate_harness_config).with(mock_config, project_dir).and_return([])
```

**Impact**: Validation is core business logic that should be tested, not mocked.

**Fix**: Test actual validation or create valid test fixtures:

```ruby
let(:valid_config) do
  {
    providers: {anthropic: {model: "claude-3-5-sonnet"}},
    workflow: "execute"
  }
end

# Don't mock validation - let it run
it "accepts valid configuration" do
  configuration = described_class.new(valid_config, project_dir)
  expect(configuration).to be_valid
end
```

---

## Priority Recommendations

### 🔴 P0: Immediate (HIGH RISK of Production Bugs) - ✅ COMPLETED

**Remove all test-specific code from production files:**

1. ✅ **FIXED** [lib/aidp/harness/provider_manager.rb:1073-1082](lib/aidp/harness/provider_manager.rb#L1073-L1082) - Removed `defined?(RSpec)` checks, added `binary_checker` dependency injection
2. ✅ **FIXED** [lib/aidp/harness/ui/enhanced_tui.rb:32](lib/aidp/harness/ui/enhanced_tui.rb#L32) - Removed `defined?(RSpec)` check, added `tty` dependency injection
3. ✅ **FIXED** [lib/aidp/cli.rb:507](lib/aidp/cli.rb#L507) - Removed `defined?(RSpec)` check and test-specific PRD simulation code

**Also Fixed:**

- ✅ [spec/aidp/harness/provider_manager_spec.rb](spec/aidp/harness/provider_manager_spec.rb) - Replaced `allow_any_instance_of` with proper dependency injection
- ✅ [spec/aidp/cli/providers_cli_availability_spec.rb](spec/aidp/cli/providers_cli_availability_spec.rb) - Removed environment variable overrides, tests now verify real behavior

**Status**: All P0 violations resolved. Production code no longer contains test-specific logic.

**Estimated Effort**: 4-8 hours → **Actual: ~4 hours**

### 🟠 P1: High Priority (Test Quality Issues)

**Add dependency injection for TTY::Prompt:**

1. [lib/aidp/cli.rb](lib/aidp/cli.rb) - Inject TTY::Prompt into CLI class
2. Update all CLI command specs to use injected prompt

**Replace all `allow_any_instance_of` patterns:**

1. [spec/aidp/cli_workstream_spec.rb](spec/aidp/cli_workstream_spec.rb) - 5 instances
2. ✅ **FIXED** [spec/aidp/harness/provider_manager_spec.rb](spec/aidp/harness/provider_manager_spec.rb) - Replaced with `binary_checker` dependency injection
3. [spec/aidp/harness/performance_simple_spec.rb](spec/aidp/harness/performance_simple_spec.rb) - 7 instances

**Estimated Effort**: 12-16 hours

### 🟡 P2: Medium Priority (Refactoring for Better Tests)

**Stop testing private methods directly:**

1. [spec/aidp/providers/anthropic_spec.rb](spec/aidp/providers/anthropic_spec.rb) - 23 instances
2. [spec/aidp/providers/cursor_spec.rb](spec/aidp/providers/cursor_spec.rb) - 7 instances
3. [spec/aidp/execute/runner_spec.rb](spec/aidp/execute/runner_spec.rb) - 6 instances

**Mock external boundaries, not internal wrappers:**

1. [spec/aidp/providers/anthropic_spec.rb](spec/aidp/providers/anthropic_spec.rb) - Mock TTY::Command instead of debug_execute_command
2. [spec/aidp/providers/cursor_spec.rb](spec/aidp/providers/cursor_spec.rb) - Mock TTY::Command instead of debug_execute_command

**Estimated Effort**: 20-30 hours

### 🟢 P3: Low Priority (Nice to Have)

**Use real temp directories or FileSystem abstraction:**

1. [spec/aidp/execute/work_loop_runner_spec.rb](spec/aidp/execute/work_loop_runner_spec.rb)
2. [spec/aidp/execute/runner_spec.rb](spec/aidp/execute/runner_spec.rb)
3. [spec/aidp/harness/state_manager_spec.rb](spec/aidp/harness/state_manager_spec.rb)

**Estimated Effort**: 8-12 hours

---

## Impact Analysis

These violations allow bugs to slip through because:

1. **Test-specific production code**: Production behaves differently in CI/tests than in real usage
2. **Mocking internal methods**: Tests pass but real integrations fail
3. **Testing private methods**: Refactoring breaks tests even when public API works
4. **Over-mocking**: Tests become "change detectors" not behavior validators
5. **Missing dependency injection**: Hard to test in isolation, forces use of anti-patterns like `any_instance_of`

## Success Metrics

Track progress by counting occurrences:

| Metric | Current | Target |
|--------|---------|--------|
| Files with `allow_any_instance_of` | 35+ | 0 |
| Files with `defined?(RSpec)` in lib/ | 4 | 0 |
| Files testing private methods with `send`/`__send__` | 15+ | 0 |
| Provider specs mocking internal methods | 6+ | 0 |

---

## Total Estimated Effort

**44-66 hours** to fix all violations across the codebase.

## Suggested Approach

1. Start with **P0 violations** (production code with test awareness)
2. Then work through **P1** (dependency injection and `any_instance_of`)
3. Systematically address **P2** and **P3** one category at a time
4. Fix one file completely before moving to the next
5. Run full test suite after each file to catch regressions

---

## Next Steps

1. Review this report and prioritize based on team capacity
2. Create individual issues for each P0 and P1 violation
3. Assign work to team members
4. Set up pre-commit hooks to prevent new violations
5. Update CI to fail on `allow_any_instance_of` usage
6. Document dependency injection patterns in STYLE_GUIDE.md

---

**Report Generated**: 2025-10-22
**Related Issue**: #163
**Contact**: For questions about this audit, comment on the issue.
