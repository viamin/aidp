# Mocking Audit Report: Issue #163

**Date**: 2025-10-22
**Issue**: <https://github.com/viamin/aidp/issues/163>
**Auditor**: Claude Code
**Scope**: Audit inappropriate or overuse of mocking in test suite per LLM_STYLE_GUIDE

## Executive Summary

This audit identified **200+ violations** across **95+ spec files** where mocking practices violate the LLM_STYLE_GUIDE and could allow production bugs to slip through the test suite.

### Progress Status (Updated 2025-10-23)

**✅ P0 COMPLETED** - All critical test-specific production code removed (confirmed zero remaining `defined?(RSpec)` or `ENV["RSPEC_RUNNING"]` checks in lib/)

- Final cleanup: Removed last 2 instances from `lib/aidp/harness/state/persistence.rb`
- Removed unused `test_mode?` method
- All specs updated to use explicit `skip_persistence: true` flag

**✅ P1 COMPLETED** - TTY::Prompt dependency injection across codebase

- Added class-level `CLI.create_prompt` method that can be stubbed in tests
- Replaced all 8 inline `TTY::Prompt.new` calls in CLI with `self.create_prompt`
- Updated 3 failing specs to stub `Aidp::CLI.create_prompt`
- Extended DI to runner classes: `Harness::Runner`, `Harness::EnhancedRunner`, `Skills::Wizard::Prompter`
- Fixed `MessageDisplay::ClassMethods` - removed memoization of class-level prompt to respect $stdout redirection in tests
- **All 3710 examples passing** with 79.2% line coverage
- No inline TTY::Prompt.new except for DI default parameters (proper pattern)

**✅ P1 COMPLETED** - All any_instance_of violations eliminated!

- ✅ **Sleep stub DI completed**: Added `Sleeper` class to `EnhancedRunner` and `ErrorHandler`; removed all sleep-related `allow_any_instance_of` stubs
- ✅ **Binary checker DI completed**: Added `BinaryChecker` class to `RepositoryClient`; removed `gh_cli_available?` any_instance_of stubs
- ✅ **IssueImporter DI improved**: Removed remaining `allow_any_instance_of` and `expect_any_instance_of` stubs; leveraged existing `gh_available:` parameter
- ✅ **ProviderInfo DI**: Stubbed `ProviderInfo.new` instead of using any_instance_of in CLI and MCP dashboard specs
- ✅ **GuidedAgent refactor**: Changed from any_instance_of to direct instance stubbing for `update_plan_from_answer`
- ✅ **WorkflowState DI**: Added `progress_tracker_factory:` injection to enable test doubles
- ✅ **BackgroundRunner DI**: Added `suppress_display:` flag to control message output without any_instance_of
- **0 allow_any_instance_of violations remaining** (down from ~35+) - 100% eliminated!

**⏸️ P2 PENDING** - 130+ violations remaining

**⏸️ P3 PENDING** - 50+ violations remaining

### Critical Findings

1. **🔴 CRITICAL: Mock Methods in Production Code** - ~~20 instances~~ → ✅ **0 instances (FIXED)** (Expanded scope: all 20 original `defined?(RSpec)` guards removed and replaced with explicit dependency injection flags)
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

### Violation 1.2: EnhancedTUI Headless Mode Detection (FIXED)

**File**: [lib/aidp/harness/ui/enhanced_tui.rb:32](lib/aidp/harness/ui/enhanced_tui.rb#L32)

Original test-aware logic replaced. Current implementation:

```ruby
def initialize(prompt: TTY::Prompt.new, tty: $stdin)
  @headless = !!(tty.nil? || !tty.tty?)
end
```

Specs now inject a non-tty double (`tty?: false`) instead of relying on RSpec detection.

### Violation 1.3: CLI Step Execution Test Detection (FIXED)

**File**: [lib/aidp/cli.rb:507](lib/aidp/cli.rb#L507)

```ruby
if step.start_with?("00_PRD") && (defined?(RSpec) || ENV["RSPEC_RUNNING"])
```

Removed conditional; CLI always emits generic step message. Specs updated to assert only actual messages.

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

### Violation 3.1: WorkstreamExecutor Runner Mocking - ✅ FIXED

**File**: [spec/aidp/workstream_executor_spec.rb:101](spec/aidp/workstream_executor_spec.rb#L101)

**Original violation**:

```ruby
allow_any_instance_of(Aidp::Harness::Runner).to receive(:run).and_return({status: "completed"})
```

**Impact**: Mocking `.run` prevented testing actual integration between WorkstreamExecutor and Runner.

**Fix Applied**:

```ruby
# Added runner_factory: injection to WorkstreamExecutor
let(:mock_runner) { instance_double(Aidp::Harness::Runner, run: {status: "completed"}) }
let(:runner_factory) { ->(*_args) { mock_runner } }
let(:executor) { described_class.new(project_dir, runner_factory: runner_factory) }
```

**Result**: Removed 3 `allow_any_instance_of(Aidp::Harness::Runner)` usages from spec.

### Complete List of `allow_any_instance_of` Violations

**✅ ALL COMPLETED** - All 35+ violations eliminated through dependency injection!

**Completed Refactors (35+ removed)**:

- ✅ [spec/aidp/workstream_executor_spec.rb](spec/aidp/workstream_executor_spec.rb) - Added runner_factory DI (3 removed)
- ✅ [spec/aidp/harness/performance_simple_spec.rb](spec/aidp/harness/performance_simple_spec.rb) - Constructor wrapping for ProviderManager (7 removed)
- ✅ [spec/aidp/harness/config_loader_spec.rb](spec/aidp/harness/config_loader_spec.rb) - Validator DI (5 removed)
- ✅ [spec/aidp/harness/provider_failure_exhausted_spec.rb](spec/aidp/harness/provider_failure_exhausted_spec.rb) - Binary checker & sleeper DI (2 removed)
- ✅ [spec/aidp/harness/provider_manager_model_spec.rb](spec/aidp/harness/provider_manager_model_spec.rb) - Removed sleep stub (1 removed)
- ✅ [spec/aidp/harness/enhanced_runner_spec.rb](spec/aidp/harness/enhanced_runner_spec.rb) - Sleeper DI (1 removed)
- ✅ [spec/aidp/harness/error_handler_spec.rb](spec/aidp/harness/error_handler_spec.rb) - Sleeper DI (1 removed)
- ✅ [spec/aidp/watch/repository_client_spec.rb](spec/aidp/watch/repository_client_spec.rb) - Binary checker DI (1 removed)
- ✅ [spec/aidp/cli/issue_importer_spec.rb](spec/aidp/cli/issue_importer_spec.rb) - Leveraged existing gh_available param (1 removed)
- ✅ [spec/aidp/cli/issue_importer_bootstrap_spec.rb](spec/aidp/cli/issue_importer_bootstrap_spec.rb) - Leveraged existing gh_available param (1 removed)
- ✅ [spec/aidp/cli_spec.rb](spec/aidp/cli_spec.rb) - Stubbed ProviderInfo.new constructor (1 removed)
- ✅ [spec/aidp/workflows/guided_agent_spec.rb](spec/aidp/workflows/guided_agent_spec.rb) - Direct instance stubbing (1 removed)
- ✅ [spec/aidp/cli/mcp_dashboard_spec.rb](spec/aidp/cli/mcp_dashboard_spec.rb) - Stubbed ProviderInfo.new constructor (1 removed)
- ✅ [spec/aidp/harness/state/workflow_state_spec.rb](spec/aidp/harness/state/workflow_state_spec.rb) - Progress tracker factory DI (2 removed)
- ✅ [spec/aidp/jobs/background_runner_spec.rb](spec/aidp/jobs/background_runner_spec.rb) - Added suppress_display flag (1 removed)

**Remaining**: 0 instances

**Impact**: Test isolation dramatically improved; all tests can now run independently without global state modification.

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

**Stop testing private methods directly** (while maintaining coverage):

Current private method tests (70+ instances across 15+ files):

1. [spec/aidp/providers/anthropic_spec.rb](spec/aidp/providers/anthropic_spec.rb) - 23 instances
2. [spec/aidp/providers/cursor_spec.rb](spec/aidp/providers/cursor_spec.rb) - 7 instances
3. [spec/aidp/execute/runner_spec.rb](spec/aidp/execute/runner_spec.rb) - 6 instances
4. [spec/aidp/analyze/runner_spec.rb](spec/aidp/analyze/runner_spec.rb)
5. [spec/aidp/watch/plan_generator_spec.rb](spec/aidp/watch/plan_generator_spec.rb)
6. [spec/aidp/daemon/runner_spec.rb](spec/aidp/daemon/runner_spec.rb)
7. [spec/aidp/analyze/ruby_maat_integration_spec.rb](spec/aidp/analyze/ruby_maat_integration_spec.rb)
8. [spec/aidp/execute/interactive_repl_spec.rb](spec/aidp/execute/interactive_repl_spec.rb)

**Coverage Preservation Strategy** (CRITICAL):

Before removing private method tests:

1. **Measure baseline coverage** - Run `bundle exec rake coverage` and save baseline for each affected file
2. **Identify coverage gaps** - Determine which private methods are tested but not covered via public API
3. **Choose refactoring strategy per file**:

   **Option A: Test through public API** (Preferred)
   - Identify the public method that calls the private method
   - Add test cases to public method that exercise all private method branches
   - Example: Instead of testing `parse_stream_json_output`, test `send_message` with various streaming responses

   **Option B: Extract and promote** (When private logic is complex)
   - Extract private method into a separate class/module with clear responsibility
   - Make it public in the new context
   - Test it directly as a public interface
   - Example: `AnthropicStreamParser` class for parsing logic

   **Option C: Document and defer** (For truly internal details)
   - If private method is trivial (simple formatting, basic validation)
   - AND it's already covered indirectly by public tests
   - Document why direct testing was removed and which public tests provide coverage
   - Only remove after confirming coverage remains ≥ baseline

4. **Validate coverage post-refactor**:
   - Run coverage tool after each refactor
   - Ensure line/branch coverage doesn't drop below baseline
   - Add public API tests to fill any gaps before removing private tests

5. **Document coverage mapping**:
   - For each removed private method test, add comment showing which public test covers it:

   ```ruby
   # Coverage for internal parse_stream_json_output provided by:
   #   - "handles streaming JSON response" (line 45)
   #   - "processes multi-chunk streams" (line 67)
   ```

**Mock external boundaries, not internal wrappers:**

1. [spec/aidp/providers/anthropic_spec.rb](spec/aidp/providers/anthropic_spec.rb) - Mock TTY::Command instead of debug_execute_command
2. [spec/aidp/providers/cursor_spec.rb](spec/aidp/providers/cursor_spec.rb) - Mock TTY::Command instead of debug_execute_command

**Acceptance Criteria**:

- ✅ Zero decrease in line coverage (maintain current ~79.2%)
- ✅ Zero decrease in branch coverage
- ✅ All critical code paths covered via public API tests
- ✅ Coverage reports generated before/after for comparison
- ✅ Documentation mapping removed private tests to replacement public tests

**Estimated Effort**: 25-35 hours (increased from 20-30 to account for coverage validation)

#### Practical Example: Refactoring Anthropic Provider Tests

Current violation in `spec/aidp/providers/anthropic_spec.rb`:

```ruby
# BEFORE: Testing private method directly
describe "#parse_stream_json_output" do
  it "extracts text from streaming response" do
    output = '{"type":"content_block_delta","delta":{"text":"Hello"}}'
    result = provider.__send__(:parse_stream_json_output, output)
    expect(result).to eq("Hello")
  end
end
```

Refactored approach (Option A - Test through public API):

```ruby
# AFTER: Test through public send_message method
describe "#send_message" do
  it "handles streaming JSON response" do
    # Mock the external boundary (TTY::Command) not internal wrapper
    allow(TTY::Command).to receive(:new).and_return(mock_command)
    allow(mock_command).to receive(:run!).and_return(
      double(exit_status: 0, out: '{"type":"content_block_delta","delta":{"text":"Hello"}}')
    )
    
    result = provider.send_message(prompt: "test", stream: true)
    expect(result).to eq("Hello")
    # This test now covers parse_stream_json_output implicitly
  end
end
```

Coverage verification workflow:

```bash
# 1. Establish baseline
bundle exec rake coverage
cp coverage/index.html coverage/baseline.html

# 2. Refactor (remove private tests, add public tests)
# Edit spec files to test through public API

# 3. Verify no coverage loss
bundle exec rake coverage
# Compare anthropic.rb coverage: must stay ≥ baseline (e.g., 85.7%)
```

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

| Metric | Previous | Current | Target |
|--------|----------|---------|--------|
| Files with `allow_any_instance_of` | 35+ | 0 ✅ | 0 |
| Files with `defined?(RSpec)` in lib/ | 2 | 0 ✅ | 0 |
| Files testing private methods (`send`/`__send__`) | 15+ | 15+ | 0 |
| Provider specs mocking internal methods | 6+ | 6+ | 0 |
| Prompt DI violations (inline TTY::Prompt.new) | 8 (CLI) | 0 (CLI) ✅ | 0 (all files) |
| CLI specs with proper mocking | 241/244 | 244/244 ✅ | 244/244 |
| Sleep-related any_instance_of stubs | 3+ | 0 ✅ | 0 |
| Binary checker any_instance_of stubs | 3+ | 0 ✅ | 0 |

---

### Replacement Strategy for Removed Test-Specific Logic

All 20 production occurrences of `defined?(RSpec)` (and any implicit test gating) were eliminated. Behavior previously toggled by test-environment detection is now controlled via explicit, constructor-injected flags:

| Flag | Introduced In | Purpose | Replaces Prior Test Check |
|------|---------------|---------|---------------------------|
| `skip_persistence:` | `analyze/progress.rb`, `execute/progress.rb`, `harness/state_manager.rb` | Disable load/save side effects during selected runs (tests, dry runs) | `defined?(RSpec)` conditional around YAML/state file I/O |
| `async_updates:` | `harness/status_display.rb` | Opt into threaded status rendering vs. synchronous fallback | Test-only thread suppression logic using `defined?(RSpec)` |
| `async_control:` | `harness/user_interface.rb` | Control interface loop threading; allows deterministic test execution | Headless/test detection branch |
| `suppress_parse_warnings:` | `analyze/kb_inspector.rb` | Silence parse warnings when desired without implicit test silence | Test-mode warning suppression |

Residual compatibility: `harness/state/persistence.rb` still infers `test_mode?` (for legacy spec expectations) during initialization only; no other production classes branch on RSpec presence. Future work can remove this inference once specs are updated to rely solely on injected flags.

CI Recommendation: Add a grep-based check preventing reintroduction of `defined?(RSpec)` and enforcing usage of the above flags for any new conditional behavior between test and production contexts.

## Total Estimated Effort

**44-66 hours** to fix all violations across the codebase.

## Suggested Approach

1. Continue P1: eliminate remaining inline `TTY::Prompt.new` (introduce constructor DI).
2. Remove remaining `allow_any_instance_of` usages (convert to injected doubles).
3. Begin P2: refactor provider specs to test public `send_message` paths rather than private method calls.
4. Introduce a filesystem adapter (optional) to phase out global File mocks (P3).
5. After each refactor: run subset + full suite to verify no regressions.
6. Add CI grep check blocking `defined?(RSpec)` and `allow_any_instance_of` reintroduction.

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
