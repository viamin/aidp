# Backward Compatibility Code Audit - Issue #307

## Overview

This document lists all backward compatibility code, stub methods, and deprecated features found in the AIDP codebase. As pre-release software (v0.x.x), AIDP does not need to maintain backward compatibility. This audit identifies code that can be safely removed.

## Findings

### 1. lib/aidp/harness/user_interface.rb

**Legacy Methods for Compatibility:**

- **Line 428-468**: `display_question_info()` - Legacy method for displaying question information
  - **Comment**: "Display question information (legacy method for compatibility)"
  - **Usage**: Only called within the same file and in specs
  - **Recommendation**: Remove if not actively used

- **Line 1579-1583**: `find_files()` - Legacy file finding wrapper
  - **Comment**: "Find files matching search term (legacy method for compatibility)"
  - **Code**: Simple wrapper calling `find_files_advanced()`
  - **Usage**: Not found in other files (only internal usage)
  - **Recommendation**: Remove - callers should use `find_files_advanced()` directly

- **Line 1662-1665**: `display_file_menu()` - Legacy file menu display
  - **Comment**: "Display file selection menu (legacy method for compatibility)"
  - **Code**: Wrapper calling `display_advanced_file_menu()` with empty defaults
  - **Usage**: Only in same file
  - **Recommendation**: Remove - callers should use `display_advanced_file_menu()` directly

- **Line 1766-1769**: `file_selection()` - Legacy file selection wrapper
  - **Comment**: "Get file selection from user (legacy method for compatibility)"
  - **Code**: Wrapper calling `advanced_file_selection()` with empty defaults
  - **Usage**: Not found in other files
  - **Recommendation**: Remove - callers should use `advanced_file_selection()` directly

### 2. lib/aidp/harness/error_handler.rb

**Legacy Error Type Mappings:**

- **Line 402-419**: Legacy alias configurations for `network_error` and `server_error`
  - **Comment**: "Legacy aliases for backward compatibility"
  - **Code**: Duplicate retry configurations
  - **Recommendation**: Remove aliases, use canonical error types only

- **Line 726-744**: Legacy error type mappings in strategy selection
  - **Comment**: "Legacy error type mappings for backward compatibility"
  - **Types**: `:timeout`, `:network_error`, `:server_error`
  - **Recommendation**: Remove legacy mappings, use new error type taxonomy

### 3. lib/aidp/execute/workflow_selector.rb

**Legacy Interactive Mode:**

- **Line 27-30**: Legacy workflow selection mode
  - **Comment**: "Legacy interactive mode for backward compatibility"
  - **Code**: `select_workflow_interactive()` fallback when `use_new_selector: false`
  - **Usage**: Only used in one spec file (`spec/aidp/execute/workflow_selector_spec.rb`)
  - **Recommendation**: Remove legacy mode - new selector is default since Issue #79

### 4. lib/aidp/watch/plan_processor.rb

**Legacy Class Method:**

- **Line 36-40**: `self.plan_label_from_config()` class method
  - **Comment**: "For backward compatibility"
  - **Usage**: Only in same file (self-reference)
  - **Recommendation**: Remove - consolidate label configuration logic

### 5. lib/aidp/harness/state_manager.rb

**Legacy Method:**

- **Line 106-111**: `current_step_from_state()`
  - **Comment**: "Get current step from state (legacy method - use progress tracker integration instead)"
  - **Usage**: Not found in other files
  - **Recommendation**: Remove - use progress tracker integration

### 6. lib/aidp/harness/config_manager.rb

**Legacy Alias:**

- **Line 106-109**: `max_retries()` method
  - **Comment**: "Get max retries (alias for backward compatibility with ErrorHandler)"
  - **Usage**: Not found in codebase
  - **Recommendation**: Remove alias - callers should use `retry_config[:max_attempts]`

### 7. lib/aidp/harness/ui/enhanced_workflow_selector.rb

**Legacy Method:**

- **Line 89-104**: `select_execute_workflow_interactive()`
  - **Comment**: "Legacy method - kept for backward compatibility if needed"
  - **Usage**: Found in specs and docs but not production code
  - **Recommendation**: Remove - use new unified workflow selector

### 8. lib/aidp/harness/ui/enhanced_tui.rb

**No-op for Compatibility:**

- **Line 47-49**: `start_display_loop()`
  - **Comment**: "Display loop is now just a no-op for compatibility"
  - **Usage**: Called from multiple files (CLI, EnhancedRunner, specs)
  - **Recommendation**: Remove method and update callers to remove calls

### 9. lib/aidp/provider_manager.rb

**Legacy Provider Creation:**

- **Line 16-18**: Fallback to `create_legacy_provider()`
  - **Comment**: "Fallback to legacy method"
  - **Code**: Falls back when harness factory is not available
  - **Usage**: Internal fallback mechanism
  - **Recommendation**: Remove fallback - always require harness factory

### 10. lib/aidp/init/runner.rb

**Test Compatibility Code:**

- **Line 285**: Compatibility with simplified prompts
  - **Comment**: "Compatibility with simplified prompts in tests (e.g. TestPrompt)"
  - **Recommendation**: Review if still needed for test infrastructure

### 11. lib/aidp/watch/repository_safety_checker.rb

**Backward Compatible Default:**

- **Line 60**: Allow-all default for backward compatibility
  - **Comment**: "If no allowlist configured, allow all (backward compatible)"
  - **Recommendation**: Consider making this explicit rather than "backward compatible"

### 12. Additional Legacy Code Patterns

**Legacy format parsers and handlers:**

- `lib/aidp/harness/provider_info.rb:223` - Legacy MCP table format parsing
- `lib/aidp/harness/provider_info.rb:253` - Legacy table format fallback
- `lib/aidp/providers/anthropic.rb:337` - Legacy MCP table format parsing
- `lib/aidp/providers/cursor.rb:260` - Extended format for "future compatibility"
- `lib/aidp/harness/test_runner.rb:64` - Handle legacy string command format
- `lib/aidp/harness/runner.rb:63` - Legacy pattern matching fallback
- `lib/aidp/setup/wizard.rb` - Legacy tier/model_family normalization (multiple locations)

**ZFC Legacy Fallbacks:**

Multiple files include legacy pattern matching fallbacks when ZFC is disabled or fails:

- `lib/aidp/harness/zfc_condition_detector.rb` - Extensive legacy fallback logic
- `lib/aidp/harness/runner.rb:63` - Falls back to legacy pattern matching
- `lib/aidp/harness/enhanced_runner.rb:66` - Falls back to legacy pattern matching

**Note**: ZFC fallbacks are intentional design for graceful degradation and should NOT be removed.

## TODO Comments (Incomplete Features)

Found 6 TODO comments without issue references:

1. `lib/aidp/analyze/seams.rb:139` - "TODO: Implement actual AST analysis"
2. `lib/aidp/setup/wizard.rb:156` - "TODO: Add default selection back once TTY-Prompt default validation issue is resolved"
3. `lib/aidp/execute/async_work_loop_runner.rb:169` - "TODO: This requires enhancing WorkLoopRunner to accept iteration callbacks"
4. `lib/aidp/harness/error_handler.rb:481` - "TODO: Integrate with actual provider execution"
5. `lib/aidp/execute/work_loop_runner.rb:1215` - "TODO: Implement interactive confirmation via REPL"

**Per LLM_STYLE_GUIDE.md Section 1**: "No introducing TODO without issue reference"

**Recommendation**: Create issues for these TODOs or implement/remove them

## FIXME Comments (Mock Violations)

Found 4 FIXME comments related to testing mock violations:

1. `spec/aidp/workflows/guided_agent_spec.rb:47`
2. `spec/aidp/jobs/background_runner_spec.rb:35`
3. `spec/aidp/execute/work_loop_runner_spec.rb:87`
4. `spec/aidp/watch/runner_spec.rb:23`

All reference: "docs/TESTING_MOCK_VIOLATIONS_REMEDIATION.md"

**Recommendation**: Address these mock violations as per the remediation guide

## Recommended Actions

### Phase 1: Safe Removals (No External Usage)

These can be removed immediately as they're not used outside their files or only in specs:

1. ✅ `UserInterface#display_question_info` - unused legacy method
2. ✅ `UserInterface#find_files` - wrapper for advanced version
3. ✅ `UserInterface#display_file_menu` - wrapper for advanced version
4. ✅ `UserInterface#file_selection` - wrapper for advanced version
5. ✅ `StateManager#current_step_from_state` - unused legacy method
6. ✅ `ConfigManager#max_retries` - unused alias
7. ✅ `PlanProcessor.plan_label_from_config` - only self-referenced
8. ✅ `EnhancedWorkflowSelector#select_execute_workflow_interactive` - only in specs

### Phase 2: Requires Caller Updates

These need careful removal with caller updates:

1. ⚠️ `EnhancedTui#start_display_loop` - Remove no-op and update callers
2. ⚠️ `EnhancedTui#stop_display_loop` - Ensure cleanup logic is retained
3. ⚠️ `WorkflowSelector` legacy mode - Remove `use_new_selector` parameter
4. ⚠️ `ProviderManager#create_legacy_provider` - Remove fallback mechanism

### Phase 3: Error Handler Cleanup

1. ⚠️ Remove legacy error type aliases (`network_error`, `server_error`, `timeout`)
2. ⚠️ Update any code using legacy error types to use canonical types
3. ⚠️ Remove legacy error type mappings in strategy selection

### Phase 4: Legacy Format Parsers

Review and remove legacy parsers only if new formats are confirmed stable:

1. Legacy MCP table format parsing
2. Legacy string command format handling
3. Legacy tier/model_family normalization

### Phase 5: TODOs and FIXMEs

1. Create issues for all TODOs or implement them
2. Address FIXME mock violations per remediation guide

## Summary

- **Total backward compatibility markers found**: 20+ locations
- **Safe immediate removals**: 8 methods/features
- **Requires caller updates**: 4 features
- **TODOs without issue references**: 5
- **Testing mock violations**: 4

## Next Steps

1. ✅ Add backward compatibility policy to LLM_STYLE_GUIDE.md
2. ✅ Add detailed explanation to STYLE_GUIDE.md
3. ✅ Remove Phase 1 items (safe removals)
4. ✅ Update callers for Phase 2 items
5. ✅ Run full test suite after each phase
6. ⚠️ Create issues for TODOs or implement them
7. ⚠️ Address FIXME mock violations
