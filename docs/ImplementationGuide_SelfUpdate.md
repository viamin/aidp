# Implementation Guide: Self-Updating Aidp in Devcontainers

## Overview

This guide provides architectural patterns, design decisions, and implementation strategies for adding self-updating capabilities to Aidp running in devcontainers. The implementation follows SOLID principles, Domain-Driven Design (DDD), and hexagonal architecture patterns consistent with the existing Aidp codebase.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Domain Model](#domain-model)
3. [Design Patterns](#design-patterns)
4. [Implementation Contract](#implementation-contract)
5. [Component Design](#component-design)
6. [Testing Strategy](#testing-strategy)
7. [Pattern-to-Use-Case Matrix](#pattern-to-use-case-matrix)
8. [Error Handling Strategy](#error-handling-strategy)
9. [Security Considerations](#security-considerations)

---

## Architecture Overview

### Hexagonal Architecture Layers

```plaintext
┌────────────────────────────────────────────────────────────────────┐
│                    Application Layer                                │
│  ┌──────────────────┐    ┌──────────────────┐                      │
│  │ Watch::Runner    │    │ CLI (settings)   │                      │
│  │ (Orchestration)  │    │ (User Commands)  │                      │
│  └──────────────────┘    └──────────────────┘                      │
└────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│                      Domain Layer                                   │
│  ┌──────────────────────────────────────────────────────┐          │
│  │  AutoUpdate::Coordinator                              │          │
│  │  - Orchestrates update workflow                       │          │
│  │  - Enforces semver policy                             │          │
│  │  - Coordinates checkpoint + restart                   │          │
│  └──────────────────────────────────────────────────────┘          │
│  ┌──────────────────┐  ┌────────────────┐  ┌────────────────────┐ │
│  │VersionDetector   │  │CheckpointStore │  │UpdateLogger        │ │
│  │ - Semver policy  │  │ - State mgmt   │  │ - Audit trail      │ │
│  └──────────────────┘  └────────────────┘  └────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│                   Infrastructure Layer                              │
│  ┌──────────────────┐  ┌────────────────┐  ┌────────────────────┐ │
│  │ Bundler Adapter  │  │ RubyGems API   │  │ Supervisor Scripts │ │
│  │ (Version Check)  │  │ (Gem Metadata) │  │ (Process Mgmt)     │ │
│  └──────────────────┘  └────────────────┘  └────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **Separation of Concerns**: Version detection, checkpoint persistence, and process restart are separate, composable components
2. **Dependency Injection**: All external dependencies (Bundler, file I/O, process management) are injected for testability
3. **Single Responsibility**: Each class has one reason to change
4. **Composition Over Inheritance**: Use service objects rather than inheritance hierarchies
5. **Fail-Safe Design**: Multiple layers of protection prevent update loops and data loss

---

## Domain Model

### Core Entities

#### UpdateCheck (Value Object)

```ruby
# Represents the result of checking for updates
{
  current_version: String,      # "0.24.0"
  available_version: String,    # "0.25.0"
  update_available: Boolean,    # true/false
  update_allowed: Boolean,      # true/false based on policy
  policy_reason: String,        # "major version change requires manual update"
  checked_at: Time             # When check was performed
}
```

#### Checkpoint (Aggregate Root)

```ruby
# Represents the complete state needed to resume after restart
{
  checkpoint_id: String,        # UUID
  created_at: Time,            # When checkpoint was created
  aidp_version: String,        # Version that created checkpoint
  mode: String,                # "watch", "execute", "analyze"
  watch_state: {               # Only for watch mode
    repository: String,
    interval: Integer,
    provider_name: String,
    persona: String,
    safety_config: Hash,
    worktree_context: {
      branch: String,
      commit_sha: String,
      remote_url: String
    },
    state_store_snapshot: Hash # Current watch state
  },
  metadata: {
    hostname: String,
    project_dir: String,
    ruby_version: String
  }
}
```

#### UpdatePolicy (Value Object)

```ruby
# Configuration for update behavior
{
  enabled: Boolean,            # Master switch
  policy: String,             # "major", "minor", "patch", "exact", "off"
  allow_prerelease: Boolean,  # Allow X.Y.Z-alpha/beta/rc
  check_interval_seconds: Integer,  # How often to check (in watch mode)
  supervisor: String          # "supervisord", "s6", "runit", "none"
}
```

### Domain Services

#### VersionDetector

**Responsibility**: Detect available gem versions and enforce semver policy

**Design Pattern**: Service Object + Strategy Pattern (for different policy types)

**Contract**:

```ruby
class VersionDetector
  # @param current_version [String] Current Aidp version (from Aidp::VERSION)
  # @param policy [UpdatePolicy] Policy configuration
  # @param bundler_adapter [BundlerAdapter] Dependency for version checking
  def initialize(current_version:, policy:, bundler_adapter: BundlerAdapter.new)
    @current_version = Gem::Version.new(current_version)
    @policy = policy
    @bundler_adapter = bundler_adapter
  end

  # Check for updates according to policy
  # @return [UpdateCheck] Result of update check
  def check_for_update
    # Implementation...
  end

  private

  # Apply semver policy to determine if update is allowed
  # @param available [Gem::Version] Available version
  # @return [Boolean] Whether update is permitted
  def update_allowed_by_policy?(available)
    case @policy.policy
    when "off"
      false
    when "exact"
      available == @current_version
    when "patch"
      same_major_minor?(available) && available >= @current_version
    when "minor"
      same_major?(available) && available >= @current_version
    when "major"
      available >= @current_version
    else
      false
    end
  end

  def same_major?(version)
    version.segments[0] == @current_version.segments[0]
  end

  def same_major_minor?(version)
    same_major?(version) && version.segments[1] == @current_version.segments[1]
  end
end
```

**Preconditions**:

- `current_version` must be a valid semver string
- `policy` must be a valid UpdatePolicy object
- Bundler must be available in the environment

**Postconditions**:

- Returns an UpdateCheck object
- Never raises exceptions (returns error state in UpdateCheck)
- Logs all version comparisons for audit trail

#### CheckpointStore

**Responsibility**: Persist and restore watch mode state

**Design Pattern**: Repository Pattern + Memento Pattern

**Contract**:

```ruby
class CheckpointStore
  # @param project_dir [String] Project root directory
  # @param logger [Logger] Logger instance
  def initialize(project_dir:, logger: Aidp.logger)
    @checkpoint_dir = File.join(project_dir, ".aidp", "checkpoints")
    @logger = logger
    ensure_checkpoint_directory
  end

  # Save current state as checkpoint
  # @param checkpoint [Checkpoint] State to persist
  # @return [Boolean] Success status
  def save_checkpoint(checkpoint)
    # Implementation...
  end

  # Find most recent checkpoint for restoration
  # @return [Checkpoint, nil] Most recent checkpoint or nil
  def latest_checkpoint
    # Implementation...
  end

  # Delete checkpoint after successful restoration
  # @param checkpoint_id [String] Checkpoint UUID
  # @return [Boolean] Success status
  def delete_checkpoint(checkpoint_id)
    # Implementation...
  end

  # Clean up old checkpoints (retention policy)
  # @param max_age_days [Integer] Maximum age to retain
  # @return [Integer] Number of checkpoints deleted
  def cleanup_old_checkpoints(max_age_days: 7)
    # Implementation...
  end

  private

  def checkpoint_path(checkpoint_id)
    File.join(@checkpoint_dir, "#{checkpoint_id}.json")
  end

  def ensure_checkpoint_directory
    FileUtils.mkdir_p(@checkpoint_dir)
  end
end
```

**Preconditions**:

- `project_dir` must exist and be writable
- Checkpoint data must be serializable to JSON

**Postconditions**:

- Checkpoint saved atomically (write to temp file, then rename)
- Checkpoint integrity verified via checksum
- Logs all save/restore operations

#### AutoUpdate::Coordinator

**Responsibility**: Orchestrate the complete update workflow

**Design Pattern**: Facade Pattern + Template Method

**Contract**:

```ruby
class AutoUpdate::Coordinator
  # @param version_detector [VersionDetector] Version checking service
  # @param checkpoint_store [CheckpointStore] State persistence
  # @param update_logger [UpdateLogger] Audit logging
  # @param policy [UpdatePolicy] Update configuration
  def initialize(version_detector:, checkpoint_store:, update_logger:, policy:)
    @version_detector = version_detector
    @checkpoint_store = checkpoint_store
    @update_logger = update_logger
    @policy = policy
    @failure_tracker = FailureTracker.new
  end

  # Check if update is available and allowed
  # @return [UpdateCheck] Update check result
  def check_for_update
    return unless @policy.enabled

    update_check = @version_detector.check_for_update
    @update_logger.log_check(update_check)
    update_check
  end

  # Initiate update process (checkpoint + exit with code 75)
  # @param current_state [Hash] Current application state
  # @return [void] (exits process with code 75)
  def initiate_update(current_state)
    raise UpdateError, "Updates disabled" unless @policy.enabled

    # Check for restart loops
    if @failure_tracker.too_many_failures?
      @update_logger.log_failure("Restart loop detected")
      raise UpdateLoopError, "Too many consecutive update failures"
    end

    # Create checkpoint
    checkpoint = build_checkpoint(current_state)
    @checkpoint_store.save_checkpoint(checkpoint)

    # Log update initiation
    @update_logger.log_update_initiated(checkpoint)

    # Exit with special code to signal supervisor
    exit(75)
  end

  # Restore from checkpoint after update
  # @return [Checkpoint, nil] Restored checkpoint or nil
  def restore_from_checkpoint
    checkpoint = @checkpoint_store.latest_checkpoint
    return nil unless checkpoint

    @update_logger.log_restore(checkpoint)
    @failure_tracker.reset_on_success

    checkpoint
  rescue => e
    @failure_tracker.record_failure
    @update_logger.log_failure("Checkpoint restore failed: #{e.message}")
    nil
  end

  private

  def build_checkpoint(current_state)
    # Implementation...
  end
end
```

**Preconditions**:

- All dependencies must be initialized
- For `initiate_update`: current_state must be complete and valid

**Postconditions**:

- `check_for_update`: Never raises, always returns UpdateCheck
- `initiate_update`: Either exits with code 75 or raises UpdateError
- `restore_from_checkpoint`: Returns checkpoint or nil, never raises

---

## Design Patterns

### 1. Repository Pattern (CheckpointStore)

**Problem**: Need to persist and retrieve checkpoint state without coupling to storage mechanism

**Solution**: CheckpointStore abstracts persistence behind a clean interface

**Benefits**:

- Easy to swap storage backends (JSON → SQLite → Redis)
- Simplified testing with in-memory implementation
- Consistent error handling

### 2. Strategy Pattern (UpdatePolicy)

**Problem**: Different update policies require different version comparison logic

**Solution**: Policy object encapsulates the decision logic

**Benefits**:

- New policies added without modifying existing code
- Policy configuration decoupled from enforcement
- Easy to test each policy in isolation

### 3. Facade Pattern (AutoUpdate::Coordinator)

**Problem**: Complex workflow involving version check → checkpoint → exit

**Solution**: Coordinator provides simple interface for complex multi-step process

**Benefits**:

- Simplified caller code
- Centralized error handling and logging
- Transaction-like semantics for update workflow

### 4. Memento Pattern (Checkpoint)

**Problem**: Need to capture and restore application state

**Solution**: Checkpoint encapsulates state snapshot

**Benefits**:

- Preserves encapsulation (no need to expose internal state)
- State evolution handled via versioned schema
- Rollback capability

### 5. Adapter Pattern (BundlerAdapter, RubyGemsAPIAdapter)

**Problem**: External APIs (Bundler, RubyGems) should not be called directly

**Solution**: Adapters wrap external dependencies

**Benefits**:

- Testability via adapter mocks
- Isolates changes to external APIs
- Consistent error handling

---

## Implementation Contract

### Phase 1: Configuration Schema (lib/aidp/auto_update/config_schema.rb)

**Objective**: Add auto_update configuration to aidp.yml

**Location**: Extend `lib/aidp/harness/config_schema.rb`

**Schema Definition**:

```ruby
# Add to SCHEMA hash in ConfigSchema
auto_update: {
  type: :hash,
  required: false,
  default: {
    enabled: false,
    policy: "off",
    allow_prerelease: false,
    check_interval_seconds: 3600,
    supervisor: "none"
  },
  properties: {
    enabled: {
      type: :boolean,
      required: false,
      default: false
    },
    policy: {
      type: :string,
      required: false,
      default: "off",
      enum: ["off", "exact", "patch", "minor", "major"]
    },
    allow_prerelease: {
      type: :boolean,
      required: false,
      default: false
    },
    check_interval_seconds: {
      type: :integer,
      required: false,
      default: 3600,
      min: 300,      # Minimum 5 minutes
      max: 86400     # Maximum 24 hours
    },
    supervisor: {
      type: :string,
      required: false,
      default: "none",
      enum: ["none", "supervisord", "s6", "runit"]
    },
    max_consecutive_failures: {
      type: :integer,
      required: false,
      default: 3,
      min: 1,
      max: 10
    }
  }
}
```

**Example Configuration**:

```yaml
# .aidp/aidp.yml
auto_update:
  enabled: true
  policy: minor          # Allow minor + patch updates
  allow_prerelease: false
  check_interval_seconds: 3600
  supervisor: supervisord
  max_consecutive_failures: 3
```

### Phase 2: Version Detection (lib/aidp/auto_update/version_detector.rb)

**Objective**: Detect available gem versions using bundler and RubyGems API

**Dependencies**:

- `Gem::Version` (Ruby stdlib)
- `Bundler` CLI
- `Net::HTTP` for RubyGems API (fallback)

**Implementation**:

```ruby
module Aidp
  module AutoUpdate
    class VersionDetector
      # Use bundler outdated first, fallback to RubyGems API
      def check_for_update
        available = fetch_latest_version

        UpdateCheck.new(
          current_version: @current_version.to_s,
          available_version: available.to_s,
          update_available: available > @current_version,
          update_allowed: update_allowed_by_policy?(available),
          policy_reason: policy_reason(available),
          checked_at: Time.now
        )
      rescue => e
        Aidp.log_error("auto_update", "version_check_failed", error: e.message)
        UpdateCheck.failed(e.message)
      end

      private

      def fetch_latest_version
        # Try bundler first
        bundler_version = @bundler_adapter.latest_version_for("aidp")
        return bundler_version if bundler_version

        # Fallback to RubyGems API
        @rubygems_adapter.latest_version_for("aidp")
      end
    end
  end
end
```

### Phase 3: Checkpoint Persistence (lib/aidp/auto_update/checkpoint_store.rb)

**Objective**: Save and restore watch mode state

**Storage Format**: JSON files in `.aidp/checkpoints/`

**Schema**:

```json
{
  "checkpoint_id": "uuid-v4",
  "created_at": "2025-01-15T10:30:00Z",
  "aidp_version": "0.24.0",
  "mode": "watch",
  "watch_state": {
    "repository": "viamin/aidp",
    "interval": 30,
    "provider_name": "anthropic",
    "persona": null,
    "safety_config": { ... },
    "worktree_context": {
      "branch": "main",
      "commit_sha": "abc123",
      "remote_url": "git@github.com:viamin/aidp.git"
    },
    "state_store_snapshot": {
      "plans": { ... },
      "builds": { ... }
    }
  },
  "metadata": {
    "hostname": "codespace-abc",
    "project_dir": "/workspaces/aidp",
    "ruby_version": "3.3.0"
  },
  "checksum": "sha256-hash"
}
```

**Atomic Write Pattern**:

```ruby
def save_checkpoint(checkpoint)
  temp_file = "#{checkpoint_path(checkpoint.id)}.tmp"
  File.write(temp_file, JSON.pretty_generate(checkpoint.to_h))

  # Atomic rename
  File.rename(temp_file, checkpoint_path(checkpoint.id))

  Aidp.log_info("auto_update", "checkpoint_saved", id: checkpoint.id)
  true
rescue => e
  Aidp.log_error("auto_update", "checkpoint_save_failed", error: e.message)
  File.delete(temp_file) if File.exist?(temp_file)
  false
end
```

### Phase 4: Graceful Shutdown (lib/aidp/auto_update/shutdown_handler.rb)

**Objective**: Exit with code 75 when update is available

**Integration Point**: `Aidp::Watch::Runner#process_cycle`

**Implementation**:

```ruby
module Aidp
  module Watch
    class Runner
      def process_cycle
        # Existing logic...
        process_plan_triggers
        process_build_triggers

        # NEW: Check for updates
        check_for_updates_if_due
      end

      private

      def check_for_updates_if_due
        return unless auto_update_enabled?
        return unless time_for_update_check?

        coordinator = build_update_coordinator
        update_check = coordinator.check_for_update

        if update_check.update_available && update_check.update_allowed
          Aidp.log_info("auto_update", "initiating_update",
            from: update_check.current_version,
            to: update_check.available_version
          )

          coordinator.initiate_update(capture_current_state)
          # Never returns - exits with code 75
        end
      end

      def capture_current_state
        {
          mode: "watch",
          watch_state: {
            repository: @repository_client.full_repo,
            interval: @interval,
            provider_name: @plan_processor.provider_name,
            persona: @persona,
            safety_config: @safety_config,
            worktree_context: capture_worktree_context,
            state_store_snapshot: @state_store.to_h
          }
        }
      end
    end
  end
end
```

### Phase 5: Supervisor Wrapper Scripts

**Objective**: Detect exit code 75 and execute bundle update

**Approach**: Provide reference scripts for common supervisors

#### supervisord Configuration

**File**: `support/supervisord/aidp-watch.conf`

```ini
[program:aidp-watch]
command=/usr/local/bin/aidp-watch-wrapper.sh
directory=/workspace/project
autostart=true
autorestart=true
exitcodes=0,75
stdout_logfile=/workspace/.aidp/logs/supervisor.log
stderr_logfile=/workspace/.aidp/logs/supervisor-error.log
environment=HOME="/home/vscode",USER="vscode"
```

**File**: `support/supervisord/aidp-watch-wrapper.sh`

```bash
#!/bin/bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/workspace/project}"
AIDP_LOG="/workspace/.aidp/logs/wrapper.log"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >> "$AIDP_LOG"
}

# Run aidp watch
cd "$PROJECT_DIR"
log "Starting aidp watch"
mise exec -- bundle exec aidp watch

EXIT_CODE=$?
log "Aidp exited with code $EXIT_CODE"

# Exit code 75 = update requested
if [ $EXIT_CODE -eq 75 ]; then
  log "Update requested, running bundle update aidp"

  # Update gem
  if mise exec -- bundle update aidp; then
    log "Aidp updated successfully"
    # Supervisor will restart us automatically
    exit 0
  else
    log "Bundle update failed"
    exit 1
  fi
fi

# Pass through other exit codes
exit $EXIT_CODE
```

#### s6 Configuration

**File**: `support/s6/aidp-watch/run`

```bash
#!/command/execlineb -P
with-contenv
s6-setuidgid vscode
cd /workspace/project
mise exec -- bundle exec aidp watch
```

**File**: `support/s6/aidp-watch/finish`

```bash
#!/bin/bash
set -euo pipefail

EXIT_CODE=$1
PROJECT_DIR="/workspace/project"

if [ $EXIT_CODE -eq 75 ]; then
  cd "$PROJECT_DIR"
  mise exec -- bundle update aidp
  exit 0
fi

# Pass through exit code
exit $EXIT_CODE
```

#### runit Configuration

**File**: `support/runit/aidp-watch/run`

```bash
#!/bin/sh
exec 2>&1
cd /workspace/project
exec chpst -u vscode mise exec -- bundle exec aidp watch
```

**File**: `support/runit/aidp-watch/finish`

```bash
#!/bin/bash
set -euo pipefail

EXIT_CODE=$1
PROJECT_DIR="/workspace/project"

if [ $EXIT_CODE -eq 75 ]; then
  cd "$PROJECT_DIR"
  mise exec -- bundle update aidp
  exit 0
fi

exit $EXIT_CODE
```

### Phase 6: Restart Loop Protection (lib/aidp/auto_update/failure_tracker.rb)

**Objective**: Prevent infinite restart loops

**Mechanism**: Track failures in persistent state file

**Implementation**:

```ruby
module Aidp
  module AutoUpdate
    class FailureTracker
      FAILURE_STATE_FILE = ".aidp/auto_update_failures.json"

      def initialize(project_dir:, max_failures: 3)
        @state_file = File.join(project_dir, FAILURE_STATE_FILE)
        @max_failures = max_failures
        @state = load_state
      end

      def record_failure
        @state[:failures] << {
          timestamp: Time.now.utc.iso8601,
          version: Aidp::VERSION
        }

        # Keep only recent failures (last hour)
        @state[:failures].select! { |f|
          Time.parse(f[:timestamp]) > Time.now - 3600
        }

        save_state
      end

      def too_many_failures?
        @state[:failures].size >= @max_failures
      end

      def reset_on_success
        @state[:failures] = []
        @state[:last_success] = Time.now.utc.iso8601
        save_state
      end

      private

      def load_state
        return default_state unless File.exist?(@state_file)

        JSON.parse(File.read(@state_file), symbolize_names: true)
      rescue
        default_state
      end

      def save_state
        File.write(@state_file, JSON.pretty_generate(@state))
      end

      def default_state
        { failures: [], last_success: nil }
      end
    end
  end
end
```

### Phase 7: CLI Commands (lib/aidp/cli.rb)

**Objective**: Provide user commands to manage auto-update settings

**Commands**:

```ruby
# aidp settings auto-update on|off
# aidp settings auto-update policy [off|exact|patch|minor|major]
# aidp settings auto-update prerelease [on|off]
# aidp settings auto-update status

def run_settings_command(args)
  subcommand = args.shift

  case subcommand
  when "auto-update"
    handle_auto_update_settings(args)
  # ... existing settings commands
  end
end

def handle_auto_update_settings(args)
  action = args.shift

  case action
  when "on"
    update_config(:auto_update, :enabled, true)
    display_message("Auto-update enabled", type: :success)

  when "off"
    update_config(:auto_update, :enabled, false)
    display_message("Auto-update disabled", type: :success)

  when "policy"
    policy = args.shift
    unless %w[off exact patch minor major].include?(policy)
      display_message("Invalid policy. Must be: off, exact, patch, minor, major", type: :error)
      exit 1
    end

    update_config(:auto_update, :policy, policy)
    display_message("Auto-update policy set to: #{policy}", type: :success)

  when "prerelease"
    value = args.shift == "on"
    update_config(:auto_update, :allow_prerelease, value)
    display_message("Prerelease updates: #{value ? 'enabled' : 'disabled'}", type: :success)

  when "status"
    show_auto_update_status

  else
    display_message("Unknown auto-update command: #{action}", type: :error)
    exit 1
  end
end
```

### Phase 8: Update Logging (lib/aidp/auto_update/update_logger.rb)

**Objective**: Maintain audit trail of update attempts

**Log Format**: JSON Lines in `.aidp/logs/updates.log`

**Implementation**:

```ruby
module Aidp
  module AutoUpdate
    class UpdateLogger
      def initialize(project_dir:)
        @log_file = File.join(project_dir, ".aidp", "logs", "updates.log")
        ensure_log_directory
      end

      def log_check(update_check)
        write_log_entry(
          event: "check",
          current_version: update_check.current_version,
          available_version: update_check.available_version,
          update_available: update_check.update_available,
          update_allowed: update_check.update_allowed,
          policy_reason: update_check.policy_reason
        )
      end

      def log_update_initiated(checkpoint)
        write_log_entry(
          event: "update_initiated",
          checkpoint_id: checkpoint.id,
          from_version: checkpoint.aidp_version,
          to_version: checkpoint.target_version
        )
      end

      def log_restore(checkpoint)
        write_log_entry(
          event: "restore",
          checkpoint_id: checkpoint.id,
          restored_version: Aidp::VERSION
        )
      end

      def log_failure(reason)
        write_log_entry(
          event: "failure",
          reason: reason,
          version: Aidp::VERSION
        )
      end

      private

      def write_log_entry(data)
        entry = data.merge(
          timestamp: Time.now.utc.iso8601,
          hostname: Socket.gethostname
        )

        File.open(@log_file, "a") do |f|
          f.puts(JSON.generate(entry))
        end
      end

      def ensure_log_directory
        FileUtils.mkdir_p(File.dirname(@log_file))
      end
    end
  end
end
```

---

## Testing Strategy

### Unit Tests

**File**: `spec/aidp/auto_update/version_detector_spec.rb`

```ruby
RSpec.describe Aidp::AutoUpdate::VersionDetector do
  describe "#check_for_update" do
    context "with policy: off" do
      it "returns update_allowed: false even when update available" do
        policy = UpdatePolicy.new(enabled: true, policy: "off")
        bundler = instance_double(BundlerAdapter, latest_version_for: Gem::Version.new("0.25.0"))

        detector = described_class.new(
          current_version: "0.24.0",
          policy: policy,
          bundler_adapter: bundler
        )

        result = detector.check_for_update

        expect(result.update_available).to be true
        expect(result.update_allowed).to be false
        expect(result.policy_reason).to include("disabled by policy")
      end
    end

    context "with policy: patch" do
      it "allows patch updates (0.24.0 -> 0.24.1)" do
        policy = UpdatePolicy.new(enabled: true, policy: "patch")
        bundler = instance_double(BundlerAdapter, latest_version_for: Gem::Version.new("0.24.1"))

        detector = described_class.new(
          current_version: "0.24.0",
          policy: policy,
          bundler_adapter: bundler
        )

        result = detector.check_for_update

        expect(result.update_allowed).to be true
      end

      it "blocks minor updates (0.24.0 -> 0.25.0)" do
        policy = UpdatePolicy.new(enabled: true, policy: "patch")
        bundler = instance_double(BundlerAdapter, latest_version_for: Gem::Version.new("0.25.0"))

        detector = described_class.new(
          current_version: "0.24.0",
          policy: policy,
          bundler_adapter: bundler
        )

        result = detector.check_for_update

        expect(result.update_allowed).to be false
        expect(result.policy_reason).to include("minor version change")
      end
    end

    # More test cases for minor, major policies...
  end
end
```

### Integration Tests

**File**: `spec/integration/auto_update_workflow_spec.rb`

```ruby
RSpec.describe "Auto-update workflow", type: :integration do
  let(:project_dir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(project_dir) }

  it "saves checkpoint and exits with code 75 when update available" do
    # Setup config
    config = {
      auto_update: {
        enabled: true,
        policy: "minor",
        supervisor: "supervisord"
      }
    }
    write_config(project_dir, config)

    # Mock newer version available
    allow_any_instance_of(BundlerAdapter).to receive(:latest_version_for)
      .and_return(Gem::Version.new("0.25.0"))

    # Run watch mode with --once flag
    pid = spawn(
      "bundle exec aidp watch --once --interval 5",
      chdir: project_dir,
      out: "/dev/null",
      err: "/dev/null"
    )

    _, status = Process.wait2(pid)

    # Should exit with code 75
    expect(status.exitstatus).to eq(75)

    # Should have created checkpoint
    checkpoints = Dir.glob(File.join(project_dir, ".aidp/checkpoints/*.json"))
    expect(checkpoints).not_to be_empty

    # Checkpoint should be valid
    checkpoint = JSON.parse(File.read(checkpoints.first))
    expect(checkpoint["mode"]).to eq("watch")
    expect(checkpoint["watch_state"]).to be_present
  end

  it "restores from checkpoint after update" do
    # Create a checkpoint
    checkpoint = create_checkpoint(project_dir, {
      mode: "watch",
      watch_state: {
        repository: "viamin/aidp",
        interval: 30
      }
    })

    # Simulate restart after update
    coordinator = AutoUpdate::Coordinator.new(
      version_detector: nil,
      checkpoint_store: CheckpointStore.new(project_dir: project_dir),
      update_logger: UpdateLogger.new(project_dir: project_dir),
      policy: UpdatePolicy.new(enabled: true, policy: "minor")
    )

    restored = coordinator.restore_from_checkpoint

    expect(restored).not_to be_nil
    expect(restored.mode).to eq("watch")
    expect(restored.watch_state[:repository]).to eq("viamin/aidp")
  end
end
```

### Container-Based Tests

**File**: `spec/integration/devcontainer_update_spec.rb`

Use Docker to test actual update flow in ephemeral containers:

```ruby
RSpec.describe "Devcontainer auto-update", type: :integration, slow: true do
  it "performs full update cycle in supervisord container" do
    # Build test container with supervisord + old version of aidp
    # Start watch mode
    # Trigger update by publishing newer version to test gem server
    # Verify exit code 75
    # Verify bundle update executed
    # Verify restart with new version
    # Verify checkpoint restored
  end
end
```

---

## Pattern-to-Use-Case Matrix

| Pattern | Use Case | Implementation |
|---------|----------|----------------|
| **Repository** | Checkpoint persistence | `CheckpointStore` |
| **Strategy** | Semver policy selection | `UpdatePolicy` + `VersionDetector` |
| **Facade** | Update orchestration | `AutoUpdate::Coordinator` |
| **Memento** | State capture/restore | `Checkpoint` object |
| **Adapter** | External API isolation | `BundlerAdapter`, `RubyGemsAPIAdapter` |
| **Template Method** | Update workflow steps | `Coordinator#initiate_update` |
| **Observer** | Update events | `UpdateLogger` |
| **Null Object** | Disabled updates | `NullCoordinator` when policy = off |

---

## Error Handling Strategy

### Error Categories

1. **Transient Errors** (retry-able):
   - Network failures connecting to RubyGems API
   - Temporary file system issues

2. **Permanent Errors** (fail-fast):
   - Invalid checkpoint data
   - Corrupted state files
   - Unsupported version transitions

3. **Safety Errors** (prevent damage):
   - Too many consecutive failures (restart loop)
   - Checkpoint version mismatch
   - Missing required dependencies

### Error Handling Rules

```ruby
# 1. Always log errors with context
rescue => e
  Aidp.log_error("auto_update", "operation_failed",
    error: e.message,
    checkpoint_id: checkpoint.id,
    operation: "save"
  )
  raise
end

# 2. Use specific exception classes
class UpdateError < StandardError; end
class UpdateLoopError < UpdateError; end
class CheckpointError < UpdateError; end
class VersionPolicyError < UpdateError; end

# 3. Graceful degradation for non-critical features
def check_for_update
  # Implementation...
rescue => e
  Aidp.log_error("auto_update", "check_failed", error: e.message)
  UpdateCheck.unavailable
end

# 4. Validate preconditions early
def initiate_update(current_state)
  raise ArgumentError, "state required" if current_state.nil?
  raise UpdateError, "updates disabled" unless @policy.enabled
  raise UpdateLoopError, "too many failures" if @failure_tracker.too_many_failures?

  # Proceed with update...
end
```

---

## Security Considerations

### 1. Code Execution Safety

**Risk**: Malicious gem update could execute arbitrary code

**Mitigation**:

- Only update via `bundle update aidp` (respects Gemfile.lock)
- Require explicit user opt-in (disabled by default)
- Log all update attempts for audit trail
- Checksum verification for checkpoints

### 2. Checkpoint Data Integrity

**Risk**: Corrupted checkpoint could cause data loss or unexpected behavior

**Mitigation**:

- Atomic writes (temp file + rename)
- SHA256 checksum validation
- Schema version in checkpoint
- Graceful degradation if checkpoint invalid

### 3. Restart Loop Protection

**Risk**: Buggy update could cause infinite restart loop

**Mitigation**:

- Track consecutive failures in persistent state
- Max 3 failures before disabling auto-update
- Exponential backoff between retries
- Manual override required to re-enable after loop detection

### 4. Supervisor Script Safety

**Risk**: Wrapper scripts could be exploited if project_dir is malicious

**Mitigation**:

- Use absolute paths only
- Validate `PROJECT_DIR` before cd
- Run with minimal privileges
- Avoid shell interpolation of user input

```bash
# Good: Safe variable expansion
PROJECT_DIR="${PROJECT_DIR:-/workspace/project}"
cd "$PROJECT_DIR" || exit 1

# Bad: Shell injection risk
# cd $PROJECT_DIR  # Don't do this!
```

### 5. Log Security

**Risk**: Sensitive data in checkpoint/logs

**Mitigation**:

- Aidp.logger already redacts secrets
- No API keys in checkpoint
- File permissions: 0600 for checkpoints
- Log rotation to prevent disk fill

---

## Component Checklist

- [ ] Configuration schema added to `ConfigSchema::SCHEMA`
- [ ] `UpdatePolicy` value object
- [ ] `UpdateCheck` value object
- [ ] `Checkpoint` aggregate root
- [ ] `VersionDetector` service
- [ ] `BundlerAdapter` infrastructure
- [ ] `RubyGemsAPIAdapter` infrastructure (fallback)
- [ ] `CheckpointStore` repository
- [ ] `FailureTracker` service
- [ ] `UpdateLogger` service
- [ ] `AutoUpdate::Coordinator` facade
- [ ] `Watch::Runner` integration (update check in poll cycle)
- [ ] CLI commands (`aidp settings auto-update ...`)
- [ ] Supervisor wrapper scripts (supervisord, s6, runit)
- [ ] Unit tests for all components
- [ ] Integration tests for workflow
- [ ] Container-based tests
- [ ] Documentation: `SELF_UPDATE.md`
- [ ] Documentation: Update `CONFIGURATION.md`
- [ ] Documentation: Update `DEVELOPMENT_ENVIRONMENTS.md`
- [ ] Documentation: Update `WATCH_MODE.md`

---

## Implementation Order

1. **Foundation** (Day 1-2):
   - Configuration schema
   - Value objects (UpdatePolicy, UpdateCheck, Checkpoint)
   - UpdateLogger

2. **Core Services** (Day 3-4):
   - VersionDetector + adapters
   - CheckpointStore
   - FailureTracker

3. **Orchestration** (Day 5):
   - AutoUpdate::Coordinator
   - Watch::Runner integration

4. **User Interface** (Day 6):
   - CLI commands
   - Status display

5. **Supervisor Integration** (Day 7):
   - Wrapper scripts
   - Container testing

6. **Documentation** (Day 8):
   - User guides
   - Configuration examples
   - Troubleshooting

---

## Success Criteria

- [ ] Auto-update can be enabled via aidp.yml
- [ ] Version detection works for all semver policies
- [ ] Watch mode checkpoints state before update
- [ ] Exit code 75 triggers supervisor to run bundle update
- [ ] Successful restore from checkpoint after update
- [ ] Restart loop protection prevents infinite failures
- [ ] CLI commands allow runtime configuration
- [ ] Update log provides complete audit trail
- [ ] All tests pass (unit + integration + container)
- [ ] Documentation covers setup, configuration, troubleshooting

---

**End of Implementation Guide**
