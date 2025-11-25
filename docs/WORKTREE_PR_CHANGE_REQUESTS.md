# Implementation Guide: Enhanced Worktree-Based PR Change Requests (Issue #326)

## Overview

This guide provides architectural patterns, design decisions, and implementation strategies for enhancing the `aidp-request-changes` label workflow to bypass diff size limitations by working directly in PR branch worktrees. The implementation follows SOLID principles, Domain-Driven Design (DDD), composition-first patterns, hexagonal architecture, and maintains compatibility with AIDP's existing architecture.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Domain Model](#domain-model)
3. [Design Patterns](#design-patterns)
4. [Implementation Contract](#implementation-contract)
5. [Component Design](#component-design)
6. [Testing Strategy](#testing-strategy)
7. [Pattern-to-Use-Case Matrix](#pattern-to-use-case-matrix)
8. [Error Handling Strategy](#error-handling-strategy)
9. [Integration Points](#integration-points)
10. [Security Considerations](#security-considerations)

---

## Architecture Overview

### Hexagonal Architecture Layers

```plaintext
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ WatchRunner      │           │ CLI Commands     │        │
│  │ (Orchestration)  │           │ (Entry Points)   │        │
│  └──────────────────┘           └──────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                            │
│  ┌────────────────────────────────────────────┐             │
│  │  ChangeRequestProcessor (ENHANCED)         │             │
│  │  - Orchestrates change request flow        │             │
│  │  - Determines worktree vs diff strategy    │             │
│  │  - Manages PR branch checkout/creation     │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  WorktreeBranchManager (NEW)               │             │
│  │  - Looks up existing worktrees by branch   │             │
│  │  - Creates worktrees for PR branches       │             │
│  │  - Manages worktree lifecycle              │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  ChangeApplicator (NEW)                    │             │
│  │  - Applies AI-generated changes to files   │             │
│  │  - Handles file operations safely          │             │
│  │  - Validates change applicability          │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  PullRequestSynchronizer (NEW)             │             │
│  │  - Commits changes with proper messages    │             │
│  │  - Pushes to PR branch                     │             │
│  │  - Handles merge conflicts                 │             │
│  └────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Infrastructure Layer                       │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ Worktree         │           │ RepositoryClient │        │
│  │ (Git Operations) │           │ (GitHub API)     │        │
│  └──────────────────┘           └──────────────────┘        │
│                                                               │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ TestRunner       │           │ StateStore       │        │
│  │ (Test/Lint)      │           │ (Persistence)    │        │
│  └──────────────────┘           └──────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **Worktree-First Strategy**: Eliminates diff size limitations by working directly in branches
2. **Composition Over Inheritance**: New services composed into existing ChangeRequestProcessor
3. **Single Responsibility**: Each class handles one aspect of the workflow
4. **Dependency Injection**: All git operations, file I/O, and GitHub API calls injected
5. **Adapter Pattern**: Worktree module serves as adapter for git operations
6. **Command Pattern**: Change application uses command objects for rollback capability
7. **Strategy Pattern**: Different strategies for worktree-based vs diff-based workflows

### Workflow Comparison

**Before (Diff-Based):**

```text
Label Applied → Fetch PR Diff → Parse Diff → Apply Changes → Commit → Push
                     ↓
              (Limited to 2000 lines)
```

**After (Worktree-Based):**

```text
Label Applied → Lookup/Create Worktree → Checkout PR Branch → Apply Changes → Test → Commit → Push
                                                ↓
                                    (No size limitation)
```

---

## Domain Model

### Core Entities

#### WorktreeInfo (Value Object - Existing, Enhanced)

```ruby
# Represents a git worktree for a PR branch
{
  slug: String,           # Workstream identifier (e.g., "pr-123-feature")
  path: String,           # Absolute path to worktree
  branch: String,         # Git branch name (e.g., "feature-branch")
  created_at: String,     # ISO8601 timestamp
  active: Boolean,        # Whether directory exists
  pr_number: Integer      # Associated PR number (NEW)
}
```

#### PRBranchContext (Value Object - NEW)

```ruby
# Context for working with a PR branch
{
  pr_number: Integer,           # PR number
  head_ref: String,             # Branch name from PR
  head_sha: String,             # Current commit SHA
  base_ref: String,             # Target branch (e.g., "main")
  worktree_path: String,        # Active worktree path
  worktree_slug: String,        # Worktree identifier
  is_new_worktree: Boolean      # Just created vs reused
}
```

#### ChangeRequest (Value Object - NEW)

```ruby
# Structured representation of requested changes
{
  pr_number: Integer,
  requested_by: String,         # Comment author
  request_text: String,         # Full request description
  changes: Array<FileChange>,   # AI-analyzed changes
  requires_tests: Boolean,      # Run tests before push
  created_at: String           # ISO8601 timestamp
}
```

#### FileChange (Value Object - NEW)

```ruby
# Represents a single file change
{
  file: String,              # Relative path from project root
  action: Symbol,            # :create, :edit, :delete
  content: String,           # Full file content (for :create/:edit)
  description: String,       # Human-readable description
  line_start: Integer,       # Optional: specific line range
  line_end: Integer          # Optional: specific line range
}
```

### Domain Services

#### WorktreeBranchManager (NEW)

**Responsibility**: Manage worktrees for PR branches

**Design Pattern**: Facade + Service Object

**Contract**:

```ruby
module Aidp
  module Watch
    # Manages git worktrees for PR change request workflows.
    # Provides lookup, creation, and lifecycle management for worktrees
    # associated with PR branches.
    class WorktreeBranchManager
      # @param project_dir [String] Project root directory
      # @param repository_client [RepositoryClient] GitHub API client
      def initialize(project_dir:, repository_client:)
        # Preconditions:
        # - project_dir must be a git repository
        # - repository_client must respond to PR fetch methods

        # Postconditions:
        # - Ready to manage worktrees
        # - project_dir validated as git repo
      end

      # Find or create a worktree for a PR branch
      # @param pr_data [Hash] PR information with :number, :head_ref, :base_ref
      # @return [PRBranchContext] Context for working with the PR
      def ensure_worktree_for_pr(pr_data)
        # Preconditions:
        # - pr_data must contain :number, :head_ref
        # - head_ref must be a valid branch name

        # Postconditions:
        # - Returns PRBranchContext with worktree path
        # - Worktree exists and is on correct branch
        # - Branch is up-to-date with remote
        # - is_new_worktree indicates if created or reused

        # Error Conditions:
        # - Raises Aidp::Worktree::Error if git operations fail
        # - Raises ArgumentError if pr_data invalid
      end

      # Check if worktree exists for a branch
      # @param branch [String] Branch name to search for
      # @return [WorktreeInfo, nil] Existing worktree or nil
      def find_worktree_by_branch(branch)
        # Preconditions:
        # - branch must be non-empty string

        # Postconditions:
        # - Returns WorktreeInfo if found
        # - Returns nil if not found
        # - Does not modify filesystem
      end

      # Create a new worktree for a PR branch
      # @param pr_data [Hash] PR information
      # @return [WorktreeInfo] Created worktree information
      def create_pr_worktree(pr_data)
        # Preconditions:
        # - pr_data must contain :number, :head_ref
        # - Branch must exist on remote or local
        # - No existing worktree for this branch

        # Postconditions:
        # - Worktree directory created
        # - Worktree checked out to PR branch
        # - Registered in worktree registry
        # - .aidp directory initialized in worktree

        # Error Conditions:
        # - Raises Aidp::Worktree::WorktreeExists if already exists
        # - Raises Aidp::Worktree::Error if creation fails
      end

      # Update existing worktree to latest remote changes
      # @param worktree_info [WorktreeInfo] Existing worktree
      # @param branch [String] Branch name
      # @return [Boolean] Success status
      def sync_worktree(worktree_info, branch)
        # Preconditions:
        # - worktree_info.active must be true
        # - worktree directory must exist

        # Postconditions:
        # - Worktree on correct branch
        # - Pulled latest changes from remote
        # - Returns true on success

        # Error Conditions:
        # - Returns false if sync fails
        # - Logs errors but does not raise
      end

      private

      # Generate slug for PR worktree
      # @param pr_number [Integer] PR number
      # @param head_ref [String] Branch name
      # @return [String] Worktree slug
      def generate_pr_slug(pr_number, head_ref)
        # Format: "pr-123-branch-name"
      end

      # Fetch branch from remote if not local
      # @param branch [String] Branch name
      def ensure_branch_available(branch)
        # Fetch from origin if branch not found locally
      end
    end
  end
end
```

#### ChangeApplicator (NEW)

**Responsibility**: Apply AI-generated changes to files in worktree

**Design Pattern**: Command Pattern + Service Object

**Contract**:

```ruby
module Aidp
  module Watch
    # Applies file changes in a transactional manner.
    # Supports rollback if any change fails.
    class ChangeApplicator
      # @param worktree_path [String] Path to worktree
      def initialize(worktree_path:)
        # Preconditions:
        # - worktree_path must exist and be writable

        # Postconditions:
        # - Ready to apply changes
        # - File operations scoped to worktree_path
      end

      # Apply a list of changes
      # @param changes [Array<FileChange>] Changes to apply
      # @return [Hash] Result with :success, :applied_count, :errors
      def apply_changes(changes)
        # Preconditions:
        # - changes must be array of valid FileChange objects
        # - Each change must have :file, :action, and :content (for create/edit)

        # Postconditions:
        # - All changes applied atomically (all or none)
        # - Returns result hash with details
        # - Logs each change with Aidp.log_debug

        # Error Conditions:
        # - If any change fails, rolls back all changes
        # - Returns success: false with error details
      end

      # Apply a single change
      # @param change [FileChange] Change to apply
      # @return [Boolean] Success status
      def apply_change(change)
        # Preconditions:
        # - change must be valid FileChange
        # - change.file must be relative path

        # Postconditions:
        # - File created/edited/deleted based on action
        # - Parent directories created if needed
        # - Returns true on success

        # Error Conditions:
        # - Returns false on failure
        # - Logs error but does not raise
      end

      # Validate changes before applying
      # @param changes [Array<FileChange>] Changes to validate
      # @return [Hash] Validation result with :valid, :errors
      def validate_changes(changes)
        # Preconditions:
        # - changes must be array

        # Postconditions:
        # - Returns validation status
        # - Lists any validation errors
        # - Does not modify filesystem

        # Validation Checks:
        # - All paths are relative (not absolute)
        # - No path traversal attempts (../)
        # - Required fields present for each action
        # - Content present for create/edit actions
      end

      private

      # Create or overwrite a file
      def create_or_edit_file(file_path, content)
      end

      # Delete a file
      def delete_file(file_path)
      end

      # Backup a file before modification
      def backup_file(file_path)
      end

      # Restore from backup (rollback)
      def restore_backup(file_path)
      end

      # Clean up backups after success
      def cleanup_backups
      end
    end
  end
end
```

#### PullRequestSynchronizer (NEW)

**Responsibility**: Commit and push changes to PR branch

**Design Pattern**: Service Object + Template Method

**Contract**:

```ruby
module Aidp
  module Watch
    # Commits changes and pushes to PR branch.
    # Handles commit message formatting and push errors.
    class PullRequestSynchronizer
      # @param worktree_path [String] Path to worktree
      # @param repository_client [RepositoryClient] GitHub API client
      def initialize(worktree_path:, repository_client:)
        # Preconditions:
        # - worktree_path must exist and be a git worktree
        # - repository_client must be configured

        # Postconditions:
        # - Ready to commit and push changes
      end

      # Commit and push changes to PR branch
      # @param pr_data [Hash] PR information
      # @param changes [Array<FileChange>] Applied changes
      # @param commit_prefix [String] Commit message prefix
      # @return [Hash] Result with :success, :commit_sha, :push_result
      def sync_changes(pr_data:, changes:, commit_prefix: "aidp: pr-change")
        # Preconditions:
        # - Working directory has changes to commit (checked via git status)
        # - pr_data contains :number, :head_ref
        # - changes array describes what was changed

        # Postconditions:
        # - Changes committed locally with descriptive message
        # - Commit pushed to origin/<head_ref>
        # - Returns result hash with commit SHA

        # Error Conditions:
        # - Returns success: false if no changes to commit
        # - Returns success: false if push fails
        # - Logs all git operations
      end

      # Check if there are uncommitted changes
      # @return [Boolean] True if changes exist
      def has_changes?
        # Preconditions:
        # - Must be in git worktree

        # Postconditions:
        # - Returns true if git status shows changes
        # - Returns false if working directory clean
      end

      # Build commit message
      # @param pr_data [Hash] PR information
      # @param changes [Array<FileChange>] Changes applied
      # @param prefix [String] Message prefix
      # @return [String] Formatted commit message
      def build_commit_message(pr_data:, changes:, prefix:)
        # Preconditions:
        # - pr_data contains :number
        # - changes is array of FileChange objects

        # Postconditions:
        # - Returns multi-line commit message
        # - First line: prefix + summary
        # - Body: details and co-authorship

        # Format:
        # <prefix>: <summary>
        #
        # Implements change request from PR #<number> review comments.
        #
        # Changes:
        # - file1: description1
        # - file2: description2
        #
        # Co-authored-by: AIDP Change Request Processor <ai@aidp.dev>
      end

      private

      # Stage all changes
      def stage_changes
      end

      # Create commit
      def create_commit(message)
      end

      # Push to remote branch
      def push_to_remote(branch)
      end

      # Handle push rejection (e.g., fast-forward required)
      def handle_push_error(error, branch)
      end
    end
  end
end
```

---

## Design Patterns

### 1. Facade Pattern

**Purpose**: Simplify worktree management complexity

**Application**: `WorktreeBranchManager` facades `Aidp::Worktree` module

**Benefits**:

- Hides git worktree complexity from change request flow
- Provides PR-specific abstractions
- Centralizes worktree lifecycle logic

**Implementation**:

```ruby
# Simple interface for complex worktree operations
manager = WorktreeBranchManager.new(project_dir: dir, repository_client: client)

# One method handles lookup + creation + sync
context = manager.ensure_worktree_for_pr(pr_data)

# Internally manages:
# - Worktree lookup by branch
# - Creation if not found
# - Branch synchronization
# - Error handling
```

### 2. Command Pattern

**Purpose**: Encapsulate file changes as commands for rollback

**Application**: `ChangeApplicator` treats each change as a command

**Benefits**:

- Atomic change application (all or none)
- Easy rollback on failure
- Audit trail of changes

**Implementation**:

```ruby
class FileChangeCommand
  def initialize(change, worktree_path)
    @change = change
    @worktree_path = worktree_path
    @backup_created = false
  end

  def execute
    backup_file if file_exists?
    apply_change
    @backup_created = true
  end

  def undo
    restore_backup if @backup_created
  end
end

# ChangeApplicator orchestrates commands
def apply_changes(changes)
  commands = changes.map { |c| FileChangeCommand.new(c, @worktree_path) }

  begin
    commands.each(&:execute)
    commands.each(&:cleanup_backup)
    {success: true, applied_count: commands.size}
  rescue => e
    commands.reverse_each(&:undo)
    {success: false, error: e.message}
  end
end
```

### 3. Template Method Pattern

**Purpose**: Define commit-push algorithm with customizable steps

**Application**: `PullRequestSynchronizer#sync_changes`

**Benefits**:

- Clear workflow structure
- Easy to override specific steps
- Consistent error handling

**Implementation**:

```ruby
def sync_changes(pr_data:, changes:, commit_prefix:)
  return no_changes_result unless has_changes?

  commit_sha = commit_changes(pr_data, changes, commit_prefix)
  push_result = push_changes(pr_data[:head_ref])

  {success: true, commit_sha: commit_sha, push_result: push_result}
rescue => e
  handle_sync_error(e)
end

# Template steps (can be overridden)
def commit_changes(pr_data, changes, prefix)
  message = build_commit_message(pr_data: pr_data, changes: changes, prefix: prefix)
  stage_changes
  create_commit(message)
end

def push_changes(branch)
  push_to_remote(branch)
rescue PushRejectedError => e
  handle_push_rejection(e, branch)
end
```

### 4. Strategy Pattern

**Purpose**: Different strategies for worktree vs diff-based workflows

**Application**: `ChangeRequestProcessor` selects strategy based on context

**Benefits**:

- Seamless transition between strategies
- Maintains backward compatibility
- Clear separation of concerns

**Implementation**:

```ruby
class ChangeRequestProcessor
  def process(pr)
    # Strategy selection
    strategy = select_strategy(pr)
    strategy.process(pr)
  end

  private

  def select_strategy(pr)
    # Always prefer worktree strategy (no size limit)
    WorktreeBasedStrategy.new(
      worktree_manager: @worktree_manager,
      change_applicator: @change_applicator,
      synchronizer: @synchronizer
    )
  end
end

class WorktreeBasedStrategy
  def process(pr)
    context = @worktree_manager.ensure_worktree_for_pr(pr)
    changes = analyze_requested_changes(pr)
    result = @change_applicator.apply_changes(changes)
    @synchronizer.sync_changes(pr_data: pr, changes: changes)
  end
end
```

### 5. Adapter Pattern

**Purpose**: Adapt existing `Aidp::Worktree` for PR workflow needs

**Application**: `WorktreeBranchManager` adapts `Aidp::Worktree`

**Benefits**:

- Reuses existing worktree infrastructure
- Adds PR-specific behavior
- No changes to core Worktree module

**Implementation**:

```ruby
class WorktreeBranchManager
  def find_worktree_by_branch(branch)
    # Adapts Aidp::Worktree.find_by_branch to add PR context
    info = Aidp::Worktree.find_by_branch(branch: branch, project_dir: @project_dir)
    return nil unless info

    # Enhance with PR information
    info.merge(pr_number: extract_pr_number(info[:slug]))
  end

  def create_pr_worktree(pr_data)
    # Adapts Aidp::Worktree.create with PR-specific slug
    slug = generate_pr_slug(pr_data[:number], pr_data[:head_ref])

    Aidp::Worktree.create(
      slug: slug,
      project_dir: @project_dir,
      branch: pr_data[:head_ref],
      base_branch: pr_data[:base_ref]
    )
  end
end
```

### 6. Dependency Injection Pattern

**Purpose**: Enable testing and flexibility

**Application**: All services accept dependencies via constructor

**Benefits**:

- Easy to test with mocks
- No hidden dependencies
- Clear dependency graph

**Implementation**:

```ruby
# Constructor injection
class ChangeRequestProcessor
  def initialize(
    repository_client:,
    state_store:,
    worktree_manager: nil,
    change_applicator: nil,
    synchronizer: nil,
    **options
  )
    @repository_client = repository_client
    @state_store = state_store

    # Lazy initialization with defaults
    @worktree_manager = worktree_manager ||
      WorktreeBranchManager.new(project_dir: @project_dir, repository_client: repository_client)

    @change_applicator = change_applicator ||
      ChangeApplicator.new(worktree_path: nil) # Set dynamically

    @synchronizer = synchronizer ||
      PullRequestSynchronizer.new(worktree_path: nil, repository_client: repository_client)
  end
end

# In tests
processor = ChangeRequestProcessor.new(
  repository_client: mock_client,
  state_store: mock_store,
  worktree_manager: mock_manager,  # Inject mock
  change_applicator: mock_applicator,
  synchronizer: mock_synchronizer
)
```

---

## Implementation Contract

### Design by Contract

All public methods follow Design by Contract principles with explicit preconditions and postconditions.

#### Contract Documentation Format

```ruby
# @param param_name [Type] Description
# @return [Type] Description
#
# Preconditions:
# - param must satisfy condition X
# - system state must be Y
#
# Postconditions:
# - result satisfies property Z
# - system state becomes W
#
# Error Conditions:
# - Raises ErrorType if condition A
# - Returns nil if condition B
def method_name(param)
  # Implementation
end
```

### Core Contracts

#### WorktreeBranchManager#ensure_worktree_for_pr

```ruby
# @param pr_data [Hash] PR information
# @return [PRBranchContext] Worktree context
#
# Preconditions:
# - pr_data[:number] is positive integer
# - pr_data[:head_ref] is non-empty string
# - project_dir is git repository
#
# Postconditions:
# - Returns PRBranchContext with valid worktree_path
# - Worktree directory exists at worktree_path
# - Worktree is on pr_data[:head_ref] branch
# - Branch is synchronized with remote
# - is_new_worktree indicates creation vs reuse
#
# Error Conditions:
# - Raises Aidp::Worktree::NotInGitRepo if project_dir not git repo
# - Raises Aidp::Worktree::Error if worktree creation fails
# - Raises ArgumentError if pr_data missing required fields
def ensure_worktree_for_pr(pr_data)
```

#### ChangeApplicator#apply_changes

```ruby
# @param changes [Array<FileChange>] Changes to apply
# @return [Hash] Result with :success, :applied_count, :errors
#
# Preconditions:
# - changes is array of FileChange objects
# - Each change has required fields for its action
# - worktree_path is writable directory
#
# Postconditions:
# - If success: all changes applied to filesystem
# - If failure: all changes rolled back (atomicity)
# - Returns result hash with status and details
# - Logs each change with Aidp.log_debug
#
# Error Conditions:
# - Returns {success: false, errors: [...]} if validation fails
# - Returns {success: false, errors: [...]} if any change fails
# - All successful changes rolled back on failure
def apply_changes(changes)
```

#### PullRequestSynchronizer#sync_changes

```ruby
# @param pr_data [Hash] PR information
# @param changes [Array<FileChange>] Applied changes
# @param commit_prefix [String] Commit message prefix
# @return [Hash] Result with :success, :commit_sha, :push_result
#
# Preconditions:
# - worktree_path has uncommitted changes (git status dirty)
# - pr_data[:head_ref] is valid branch name
# - Git user.name and user.email configured
#
# Postconditions:
# - If success: changes committed and pushed to remote
# - If success: returns commit SHA
# - If no changes: returns {success: false, reason: "no_changes"}
# - Logs git operations with Aidp.log_debug
#
# Error Conditions:
# - Returns {success: false, error: ...} if commit fails
# - Returns {success: false, error: ...} if push fails
# - Does not rollback commits on push failure (fix-forward)
def sync_changes(pr_data:, changes:, commit_prefix:)
```

### Contract Validation

Use guard clauses to enforce preconditions:

```ruby
def ensure_worktree_for_pr(pr_data)
  # Validate preconditions
  raise ArgumentError, "pr_data must be a Hash" unless pr_data.is_a?(Hash)
  raise ArgumentError, "pr_data must include :number" unless pr_data.key?(:number)
  raise ArgumentError, "pr_data must include :head_ref" unless pr_data.key?(:head_ref)
  raise ArgumentError, "pr_data[:number] must be positive" unless pr_data[:number].to_i > 0
  raise ArgumentError, "pr_data[:head_ref] must be non-empty" if pr_data[:head_ref].to_s.strip.empty?

  # Implementation
  # ...

  # Validate postconditions (in development/test)
  if defined?(AIDP_CONTRACT_VALIDATION)
    raise "Postcondition failed: worktree_path not set" unless result[:worktree_path]
    raise "Postcondition failed: worktree not active" unless Dir.exist?(result[:worktree_path])
  end

  result
end
```

---

## Component Design

### 1. WorktreeBranchManager

**Location**: `lib/aidp/watch/worktree_branch_manager.rb`

**Dependencies**:

- `Aidp::Worktree` (existing)
- `RepositoryClient` (for PR data)

**Key Methods**:

- `ensure_worktree_for_pr(pr_data)` - Main entry point
- `find_worktree_by_branch(branch)` - Lookup existing
- `create_pr_worktree(pr_data)` - Create new
- `sync_worktree(worktree_info, branch)` - Update existing

**Implementation Notes**:

- Use `Aidp::Worktree.find_by_branch` for lookup
- Use `Aidp::Worktree.create` for creation
- Generate slug format: `"pr-#{number}-#{sanitized_branch}"`
- Log all operations with `Aidp.log_debug("worktree_branch_manager", ...)`

**Example Usage**:

```ruby
manager = Aidp::Watch::WorktreeBranchManager.new(
  project_dir: "/path/to/project",
  repository_client: client
)

pr_data = {
  number: 123,
  head_ref: "feature-branch",
  base_ref: "main",
  head_sha: "abc123"
}

# Handles lookup, creation, and sync in one call
context = manager.ensure_worktree_for_pr(pr_data)
# => {
#   pr_number: 123,
#   head_ref: "feature-branch",
#   head_sha: "abc123",
#   base_ref: "main",
#   worktree_path: "/path/to/project/.worktrees/pr-123-feature-branch",
#   worktree_slug: "pr-123-feature-branch",
#   is_new_worktree: true
# }
```

### 2. ChangeApplicator

**Location**: `lib/aidp/watch/change_applicator.rb`

**Dependencies**:

- `FileUtils` (for file operations)

**Key Methods**:

- `apply_changes(changes)` - Apply all changes atomically
- `validate_changes(changes)` - Pre-apply validation
- `apply_change(change)` - Apply single change

**Implementation Notes**:

- Create backups before modifying files
- Use rollback on any failure
- Validate paths (no `..`, absolute paths, etc.)
- Log each change with `Aidp.log_debug("change_applicator", ...)`
- Handle parent directory creation

**Example Usage**:

```ruby
applicator = Aidp::Watch::ChangeApplicator.new(
  worktree_path: "/path/to/worktree"
)

changes = [
  {file: "lib/foo.rb", action: :edit, content: "...", description: "Fix typo"},
  {file: "spec/foo_spec.rb", action: :create, content: "...", description: "Add test"}
]

result = applicator.apply_changes(changes)
# => {success: true, applied_count: 2}

# On failure, all changes rolled back
result = applicator.apply_changes(invalid_changes)
# => {success: false, errors: ["Invalid path: ../etc/passwd"]}
```

### 3. PullRequestSynchronizer

**Location**: `lib/aidp/watch/pull_request_synchronizer.rb`

**Dependencies**:

- `Open3` (for git commands)
- `RepositoryClient` (for GitHub API)

**Key Methods**:

- `sync_changes(pr_data:, changes:, commit_prefix:)` - Main entry
- `has_changes?` - Check for uncommitted changes
- `build_commit_message(pr_data:, changes:, prefix:)` - Format message

**Implementation Notes**:

- Run git commands in worktree directory
- Use `Open3.capture3` for git operations
- Build descriptive commit messages
- Log all git operations with `Aidp.log_debug("pr_synchronizer", ...)`
- Handle push rejections gracefully

**Example Usage**:

```ruby
synchronizer = Aidp::Watch::PullRequestSynchronizer.new(
  worktree_path: "/path/to/worktree",
  repository_client: client
)

result = synchronizer.sync_changes(
  pr_data: {number: 123, head_ref: "feature-branch"},
  changes: [{file: "lib/foo.rb", description: "Fix typo"}],
  commit_prefix: "aidp: pr-change"
)
# => {
#   success: true,
#   commit_sha: "def456",
#   push_result: "To origin\n   abc123..def456  feature-branch -> feature-branch"
# }
```

### 4. Enhanced ChangeRequestProcessor

**Location**: `lib/aidp/watch/change_request_processor.rb` (existing, enhanced)

**Changes**:

1. Add worktree strategy
2. Remove max_diff_size check (or make optional for fallback)
3. Integrate new services

**Modified Methods**:

```ruby
def process(pr)
  # ... existing validation ...

  # NEW: Use worktree strategy (no diff size limit)
  context = ensure_pr_worktree(pr)
  changes = analyze_change_requests(pr_data: pr, comments: comments, diff: nil)

  if changes[:can_implement]
    implement_changes_in_worktree(pr: pr, context: context, analysis: changes)
  else
    handle_cannot_implement(pr: pr, analysis: changes)
  end
end

private

def ensure_pr_worktree(pr)
  @worktree_manager ||= WorktreeBranchManager.new(
    project_dir: @project_dir,
    repository_client: @repository_client
  )

  @worktree_manager.ensure_worktree_for_pr(pr)
end

def implement_changes_in_worktree(pr:, context:, analysis:)
  # Apply changes in worktree
  applicator = ChangeApplicator.new(worktree_path: context[:worktree_path])
  result = applicator.apply_changes(analysis[:changes])

  unless result[:success]
    handle_application_failure(pr: pr, result: result)
    return
  end

  # Run tests if configured
  if @config[:run_tests_before_push]
    test_result = run_tests_in_worktree(context[:worktree_path])
    unless test_result[:success]
      handle_test_failure(pr: pr, analysis: analysis, test_result: test_result)
      return
    end
  end

  # Commit and push
  synchronizer = PullRequestSynchronizer.new(
    worktree_path: context[:worktree_path],
    repository_client: @repository_client
  )

  sync_result = synchronizer.sync_changes(
    pr_data: pr,
    changes: analysis[:changes],
    commit_prefix: @config[:commit_message_prefix]
  )

  if sync_result[:success]
    handle_success(pr: pr, analysis: analysis)
  else
    handle_sync_failure(pr: pr, result: sync_result)
  end
end
```

---

## Testing Strategy

### Unit Tests

#### WorktreeBranchManager

**File**: `spec/aidp/watch/worktree_branch_manager_spec.rb`

```ruby
RSpec.describe Aidp::Watch::WorktreeBranchManager do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:manager) { described_class.new(project_dir: tmp_dir, repository_client: repository_client) }

  before do
    # Initialize git repo
    Dir.chdir(tmp_dir) { system("git init", out: File::NULL) }
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "#find_worktree_by_branch" do
    context "when worktree exists" do
      it "returns worktree info with PR number" do
        # Setup: Create worktree
        Aidp::Worktree.create(slug: "pr-123-feature", project_dir: tmp_dir, branch: "feature")

        result = manager.find_worktree_by_branch("feature")

        expect(result).to include(
          slug: "pr-123-feature",
          branch: "feature",
          pr_number: 123
        )
      end
    end

    context "when worktree does not exist" do
      it "returns nil" do
        result = manager.find_worktree_by_branch("nonexistent")
        expect(result).to be_nil
      end
    end
  end

  describe "#ensure_worktree_for_pr" do
    let(:pr_data) { {number: 123, head_ref: "feature", base_ref: "main", head_sha: "abc"} }

    context "when worktree exists" do
      before do
        Aidp::Worktree.create(slug: "pr-123-feature", project_dir: tmp_dir, branch: "feature")
      end

      it "reuses existing worktree" do
        result = manager.ensure_worktree_for_pr(pr_data)

        expect(result[:is_new_worktree]).to be false
        expect(result[:worktree_slug]).to eq("pr-123-feature")
      end

      it "syncs worktree to latest" do
        # Test that git fetch + pull executed
      end
    end

    context "when worktree does not exist" do
      it "creates new worktree" do
        result = manager.ensure_worktree_for_pr(pr_data)

        expect(result[:is_new_worktree]).to be true
        expect(Dir.exist?(result[:worktree_path])).to be true
      end
    end

    context "with invalid pr_data" do
      it "raises ArgumentError for missing number" do
        expect {
          manager.ensure_worktree_for_pr({head_ref: "feature"})
        }.to raise_error(ArgumentError, /must include :number/)
      end

      it "raises ArgumentError for missing head_ref" do
        expect {
          manager.ensure_worktree_for_pr({number: 123})
        }.to raise_error(ArgumentError, /must include :head_ref/)
      end
    end
  end
end
```

#### ChangeApplicator

**File**: `spec/aidp/watch/change_applicator_spec.rb`

```ruby
RSpec.describe Aidp::Watch::ChangeApplicator do
  let(:worktree_path) { Dir.mktmpdir }
  let(:applicator) { described_class.new(worktree_path: worktree_path) }

  after do
    FileUtils.rm_rf(worktree_path)
  end

  describe "#apply_changes" do
    context "with valid changes" do
      let(:changes) do
        [
          {file: "lib/foo.rb", action: :create, content: "# foo", description: "Create foo"},
          {file: "lib/bar.rb", action: :edit, content: "# bar", description: "Edit bar"}
        ]
      end

      it "applies all changes" do
        result = applicator.apply_changes(changes)

        expect(result[:success]).to be true
        expect(result[:applied_count]).to eq(2)
        expect(File.read("#{worktree_path}/lib/foo.rb")).to eq("# foo")
      end

      it "logs each change" do
        expect(Aidp).to receive(:log_debug).with("change_applicator", "apply_change", hash_including(file: "lib/foo.rb"))
        applicator.apply_changes(changes)
      end
    end

    context "with path traversal attempt" do
      let(:changes) { [{file: "../etc/passwd", action: :create, content: "bad"}] }

      it "rejects the change" do
        result = applicator.apply_changes(changes)

        expect(result[:success]).to be false
        expect(result[:errors]).to include(/path traversal/)
      end
    end

    context "when a change fails" do
      let(:changes) do
        [
          {file: "lib/foo.rb", action: :create, content: "# foo"},
          {file: "/absolute/path.rb", action: :create, content: "# bad"}
        ]
      end

      it "rolls back all changes" do
        result = applicator.apply_changes(changes)

        expect(result[:success]).to be false
        expect(File.exist?("#{worktree_path}/lib/foo.rb")).to be false  # Rolled back
      end
    end
  end

  describe "#validate_changes" do
    it "validates required fields" do
      changes = [{file: "foo.rb"}]  # Missing action
      result = applicator.validate_changes(changes)

      expect(result[:valid]).to be false
      expect(result[:errors]).to include(/missing action/)
    end

    it "validates paths" do
      changes = [{file: "../bad", action: :create, content: "x"}]
      result = applicator.validate_changes(changes)

      expect(result[:valid]).to be false
      expect(result[:errors]).to include(/path traversal/)
    end
  end
end
```

#### PullRequestSynchronizer

**File**: `spec/aidp/watch/pull_request_synchronizer_spec.rb`

```ruby
RSpec.describe Aidp::Watch::PullRequestSynchronizer do
  let(:worktree_path) { Dir.mktmpdir }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:synchronizer) { described_class.new(worktree_path: worktree_path, repository_client: repository_client) }

  before do
    # Initialize git repo in worktree
    Dir.chdir(worktree_path) do
      system("git init", out: File::NULL)
      system("git config user.email 'test@example.com'", out: File::NULL)
      system("git config user.name 'Test'", out: File::NULL)
    end
  end

  after do
    FileUtils.rm_rf(worktree_path)
  end

  describe "#has_changes?" do
    it "returns false for clean working directory" do
      expect(synchronizer.has_changes?).to be false
    end

    it "returns true with uncommitted changes" do
      File.write("#{worktree_path}/foo.rb", "# new file")
      expect(synchronizer.has_changes?).to be true
    end
  end

  describe "#build_commit_message" do
    let(:pr_data) { {number: 123, title: "Feature"} }
    let(:changes) do
      [
        {file: "lib/foo.rb", description: "Fix typo"},
        {file: "lib/bar.rb", description: "Add method"}
      ]
    end

    it "formats message with prefix and details" do
      message = synchronizer.build_commit_message(
        pr_data: pr_data,
        changes: changes,
        prefix: "aidp: pr-change"
      )

      expect(message).to include("aidp: pr-change")
      expect(message).to include("PR #123")
      expect(message).to include("Fix typo")
      expect(message).to include("Co-authored-by: AIDP")
    end
  end

  describe "#sync_changes" do
    let(:pr_data) { {number: 123, head_ref: "feature"} }
    let(:changes) { [{file: "lib/foo.rb", description: "Fix"}] }

    before do
      # Create a commit so we have something to push
      File.write("#{worktree_path}/foo.rb", "# content")
      Dir.chdir(worktree_path) do
        system("git add .", out: File::NULL)
        system("git commit -m 'Initial'", out: File::NULL)
      end
    end

    context "with uncommitted changes" do
      before do
        File.write("#{worktree_path}/foo.rb", "# modified")
      end

      it "commits and pushes changes" do
        # Mock git push (avoid actual remote push in tests)
        allow(Open3).to receive(:capture3).with("git", "push", "origin", "feature")
          .and_return(["", "", instance_double(Process::Status, success?: true)])

        result = synchronizer.sync_changes(pr_data: pr_data, changes: changes)

        expect(result[:success]).to be true
        expect(result[:commit_sha]).to match(/[a-f0-9]{40}/)
      end
    end

    context "without uncommitted changes" do
      it "returns no_changes result" do
        result = synchronizer.sync_changes(pr_data: pr_data, changes: changes)

        expect(result[:success]).to be false
        expect(result[:reason]).to eq("no_changes")
      end
    end
  end
end
```

### Integration Tests

#### End-to-End Change Request Flow

**File**: `spec/aidp/watch/change_request_processor_integration_spec.rb`

```ruby
RSpec.describe "Change Request Processor Integration", :integration do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }

  before do
    # Setup git repository
    Dir.chdir(tmp_dir) do
      system("git init", out: File::NULL)
      system("git config user.email 'test@test.com'", out: File::NULL)
      system("git config user.name 'Test'", out: File::NULL)
      system("git commit --allow-empty -m 'Initial'", out: File::NULL)
      system("git checkout -b feature", out: File::NULL)
      File.write("lib/example.rb", "# original")
      system("git add .", out: File::NULL)
      system("git commit -m 'Add example'", out: File::NULL)
      system("git checkout main", out: File::NULL)
    end
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it "processes change request using worktree" do
    pr = {
      number: 123,
      title: "Feature",
      body: "Description",
      head_ref: "feature",
      base_ref: "main",
      head_sha: "abc123",
      author: "alice"
    }

    comments = [
      {id: 1, body: "Please fix the typo", author: "alice", created_at: Time.now.iso8601}
    ]

    # Mock GitHub API responses
    allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
    allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
    allow(repository_client).to receive(:post_comment)
    allow(repository_client).to receive(:remove_labels)

    # Mock AI analysis
    provider = instance_double(Aidp::Providers::AnthropicProvider)
    allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
    allow(provider).to receive(:send_message).and_return(
      JSON.generate({
        can_implement: true,
        needs_clarification: false,
        changes: [
          {file: "lib/example.rb", action: "edit", content: "# fixed", description: "Fix typo"}
        ]
      })
    )

    processor = Aidp::Watch::ChangeRequestProcessor.new(
      repository_client: repository_client,
      state_store: state_store,
      project_dir: tmp_dir,
      change_request_config: {enabled: true, run_tests_before_push: false}
    )

    # Process the PR
    processor.process(pr)

    # Verify worktree created
    worktrees = Aidp::Worktree.list(project_dir: tmp_dir)
    expect(worktrees).not_to be_empty
    worktree = worktrees.first
    expect(worktree[:branch]).to eq("feature")

    # Verify changes applied
    file_path = File.join(worktree[:path], "lib/example.rb")
    expect(File.read(file_path)).to eq("# fixed")

    # Verify success comment posted
    expect(repository_client).to have_received(:post_comment).with(123, /Successfully implemented/)
    expect(repository_client).to have_received(:remove_labels).with(123, "aidp-request-changes")
  end
end
```

### Test Coverage Goals

- **Unit Tests**: 90%+ coverage for new classes
- **Integration Tests**: Cover end-to-end workflows
- **Edge Cases**: Path traversal, rollback, merge conflicts
- **Error Paths**: Git failures, file I/O errors, API failures

---

## Pattern-to-Use-Case Matrix

| Use Case                             | Patterns                      | Components                                  |
|--------------------------------------|-------------------------------|---------------------------------------------|
| **Lookup existing worktree for PR**  | Adapter, Facade               | WorktreeBranchManager → Aidp::Worktree      |
| **Create worktree for PR branch**    | Adapter, Factory              | WorktreeBranchManager, Aidp::Worktree       |
| **Apply file changes atomically**    | Command, Transaction          | ChangeApplicator, FileChangeCommand         |
| **Rollback on failure**              | Command, Memento              | ChangeApplicator (undo commands)            |
| **Commit and push changes**          | Template Method, Strategy     | PullRequestSynchronizer                     |
| **Select worktree vs diff strategy** | Strategy                      | ChangeRequestProcessor                      |
| **Build commit message**             | Builder                       | PullRequestSynchronizer                     |
| **Validate file paths**              | Chain of Responsibility       | ChangeApplicator validators                 |
| **Inject dependencies for testing**  | Dependency Injection          | All components                              |
| **Simplify complex git operations**  | Facade                        | WorktreeBranchManager                       |

---

## Error Handling Strategy

### Error Hierarchy

```ruby
module Aidp
  module Watch
    class ChangeRequestError < StandardError; end

    class WorktreeManagementError < ChangeRequestError; end
    class WorktreeNotFoundError < WorktreeManagementError; end
    class WorktreeCreationError < WorktreeManagementError; end
    class BranchSyncError < WorktreeManagementError; end

    class ChangeApplicationError < ChangeRequestError; end
    class InvalidChangeError < ChangeApplicationError; end
    class PathTraversalError < ChangeApplicationError; end
    class FileOperationError < ChangeApplicationError; end

    class SynchronizationError < ChangeRequestError; end
    class CommitError < SynchronizationError; end
    class PushError < SynchronizationError; end
    class MergeConflictError < SynchronizationError; end
  end
end
```

### Error Handling by Component

#### WorktreeBranchManager

```ruby
def ensure_worktree_for_pr(pr_data)
  Aidp.log_debug("worktree_branch_manager", "ensure_worktree_start", pr: pr_data[:number])

  validate_pr_data!(pr_data)

  existing = find_worktree_by_branch(pr_data[:head_ref])

  if existing && existing[:active]
    sync_worktree(existing, pr_data[:head_ref])
    return build_context(existing, is_new: false)
  end

  worktree = create_pr_worktree(pr_data)
  build_context(worktree, is_new: true)
rescue Aidp::Worktree::Error => e
  Aidp.log_error("worktree_branch_manager", "worktree_operation_failed", pr: pr_data[:number], error: e.message)
  raise WorktreeManagementError, "Failed to manage worktree: #{e.message}"
rescue => e
  Aidp.log_error("worktree_branch_manager", "unexpected_error", pr: pr_data[:number], error: e.message, backtrace: e.backtrace&.first(5))
  raise
end
```

#### ChangeApplicator

```ruby
def apply_changes(changes)
  Aidp.log_debug("change_applicator", "apply_changes_start", count: changes.size)

  validation = validate_changes(changes)
  unless validation[:valid]
    Aidp.log_warn("change_applicator", "validation_failed", errors: validation[:errors])
    return {success: false, errors: validation[:errors]}
  end

  backups = {}
  applied = []

  begin
    changes.each do |change|
      backups[change[:file]] = backup_file(change[:file]) if file_exists?(change[:file])
      apply_change(change)
      applied << change[:file]
      Aidp.log_debug("change_applicator", "change_applied", file: change[:file], action: change[:action])
    end

    cleanup_backups(backups)
    {success: true, applied_count: applied.size}
  rescue => e
    Aidp.log_error("change_applicator", "apply_failed", file: change[:file], error: e.message)
    rollback_changes(backups)
    {success: false, errors: [e.message], partial_applied: applied}
  end
end
```

#### PullRequestSynchronizer

```ruby
def sync_changes(pr_data:, changes:, commit_prefix:)
  Aidp.log_debug("pr_synchronizer", "sync_start", pr: pr_data[:number])

  unless has_changes?
    Aidp.log_info("pr_synchronizer", "no_changes_to_sync", pr: pr_data[:number])
    return {success: false, reason: "no_changes"}
  end

  begin
    commit_sha = commit_changes(pr_data, changes, commit_prefix)
    push_result = push_changes(pr_data[:head_ref])

    Aidp.log_info("pr_synchronizer", "sync_success", pr: pr_data[:number], commit_sha: commit_sha)
    {success: true, commit_sha: commit_sha, push_result: push_result}
  rescue CommitError => e
    Aidp.log_error("pr_synchronizer", "commit_failed", pr: pr_data[:number], error: e.message)
    {success: false, error: e.message, stage: "commit"}
  rescue PushError => e
    Aidp.log_error("pr_synchronizer", "push_failed", pr: pr_data[:number], error: e.message)
    {success: false, error: e.message, stage: "push", commit_sha: commit_sha}
  end
end
```

### Logging Strategy

All components log extensively using `Aidp.log_debug()`:

```ruby
# Method entry
Aidp.log_debug("component_name", "method_start", pr: 123, branch: "feature")

# State changes
Aidp.log_debug("component_name", "worktree_created", path: "/path", slug: "pr-123-feature")

# External calls
Aidp.log_debug("component_name", "git_checkout", branch: "feature")

# Decisions
Aidp.log_debug("component_name", "strategy_selected", strategy: "worktree_based")

# Errors
Aidp.log_error("component_name", "operation_failed", error: e.message, backtrace: e.backtrace&.first(5))
```

---

## Integration Points

### 1. Existing Worktree Module

**Interface**: `Aidp::Worktree`

**Integration**:

- `WorktreeBranchManager` wraps `Aidp::Worktree` methods
- No changes required to `Aidp::Worktree`
- Adds PR-specific behavior via adapter pattern

**Methods Used**:

- `Aidp::Worktree.find_by_branch(branch:, project_dir:)`
- `Aidp::Worktree.create(slug:, project_dir:, branch:, base_branch:)`
- `Aidp::Worktree.list(project_dir:)`

### 2. ChangeRequestProcessor

**Interface**: `Aidp::Watch::ChangeRequestProcessor`

**Integration**:

- Add `@worktree_manager` attribute
- Modify `#process` to use worktree strategy
- Keep existing AI analysis flow
- Keep existing comment posting logic

**Changes**:

```ruby
def initialize(**options)
  # ... existing initialization ...

  @worktree_manager = WorktreeBranchManager.new(
    project_dir: @project_dir,
    repository_client: @repository_client
  )
end

def process(pr)
  # ... existing validation ...

  # NEW: Ensure worktree instead of checking diff size
  context = @worktree_manager.ensure_worktree_for_pr(pr)

  # ... rest of flow ...
end
```

### 3. TestRunner

**Interface**: `Aidp::Harness::TestRunner`

**Integration**:

- Run tests in worktree context
- Pass worktree path to TestRunner

**Usage**:

```ruby
def run_tests_in_worktree(worktree_path)
  config_manager = Aidp::Harness::ConfigManager.new(worktree_path)
  config = config_manager.config || {}

  test_runner = Aidp::Harness::TestRunner.new(worktree_path, config)

  lint_result = test_runner.run_linters
  return {success: false, stage: "lint", output: lint_result[:output]} unless lint_result[:passed]

  test_result = test_runner.run_tests
  return {success: false, stage: "test", output: test_result[:output]} unless test_result[:passed]

  {success: true}
end
```

### 4. StateStore

**Interface**: `Aidp::Watch::StateStore`

**Integration**:

- Store worktree context in change request data
- Track worktree reuse vs creation

**Enhanced State**:

```ruby
@state_store.record_change_request(pr[:number], {
  status: "completed",
  timestamp: Time.now.utc.iso8601,
  changes_applied: changes.length,
  worktree_slug: context[:worktree_slug],
  worktree_reused: !context[:is_new_worktree],
  commit_sha: sync_result[:commit_sha]
})
```

### 5. RepositoryClient

**Interface**: `Aidp::Watch::RepositoryClient`

**Integration**:

- No changes required
- Used for PR data fetching and comment posting

**Methods Used**:

- `fetch_pull_request(number)`
- `fetch_pr_comments(number)`
- `post_comment(number, body)`
- `remove_labels(number, label)`

---

## Security Considerations

### 1. Path Traversal Prevention

**Risk**: Malicious file paths in AI-generated changes

**Mitigation**:

```ruby
def validate_file_path(path)
  # Reject absolute paths
  return false if path.start_with?("/")

  # Reject path traversal
  return false if path.include?("..")

  # Reject paths outside worktree
  full_path = File.expand_path(path, @worktree_path)
  return false unless full_path.start_with?(@worktree_path)

  true
end
```

### 2. Branch Access Control

**Risk**: Creating/modifying unauthorized branches

**Mitigation**:

- Only work with PR branches (head_ref from GitHub API)
- Verify PR ownership via repository_client
- Respect author_allowlist configuration

### 3. File Content Validation

**Risk**: AI-generated content contains malicious code

**Mitigation**:

- Run linters/tests before pushing
- User reviews changes via PR diff
- Author allowlist prevents unauthorized requests
- No automatic merge - requires manual approval

### 4. Git Operations Safety

**Risk**: Git commands with unsanitized input

**Mitigation**:

```ruby
def run_git_safely(args)
  # Use array form (not shell string)
  stdout, stderr, status = Open3.capture3("git", *args)

  raise "git command failed: #{stderr}" unless status.success?

  stdout
end
```

### 5. Worktree Isolation

**Risk**: Worktrees interfering with each other

**Mitigation**:

- Each worktree in isolated directory
- Use git worktree mechanism (built-in isolation)
- Registry tracks active worktrees
- No shared mutable state between worktrees

### 6. Secret Leakage

**Risk**: Secrets in logs or error messages

**Mitigation**:

- Never log file contents in full
- Truncate error messages
- Exclude `.env` files from change operations
- Follow existing `Aidp.log_debug` patterns (no secrets)

---

## Implementation Checklist

### Phase 1: Core Components

- [ ] Implement `WorktreeBranchManager`
  - [ ] `ensure_worktree_for_pr`
  - [ ] `find_worktree_by_branch`
  - [ ] `create_pr_worktree`
  - [ ] `sync_worktree`
- [ ] Implement `ChangeApplicator`
  - [ ] `apply_changes`
  - [ ] `validate_changes`
  - [ ] Rollback mechanism
- [ ] Implement `PullRequestSynchronizer`
  - [ ] `sync_changes`
  - [ ] `build_commit_message`
  - [ ] `has_changes?`

### Phase 2: Integration

- [ ] Enhance `ChangeRequestProcessor`
  - [ ] Add worktree strategy
  - [ ] Integrate new services
  - [ ] Remove/deprecate diff size check
- [ ] Update configuration
  - [ ] Make `max_diff_size` optional
  - [ ] Add worktree-specific options

### Phase 3: Testing

- [ ] Unit tests for `WorktreeBranchManager`
- [ ] Unit tests for `ChangeApplicator`
- [ ] Unit tests for `PullRequestSynchronizer`
- [ ] Integration tests for full flow
- [ ] Edge case tests (path traversal, rollback, etc.)

### Phase 4: Documentation

- [ ] Update `PR_CHANGE_REQUESTS.md`
- [ ] Add worktree workflow diagrams
- [ ] Document new configuration options
- [ ] Add troubleshooting guide

### Phase 5: Polish

- [ ] Add comprehensive logging
- [ ] Error message improvements
- [ ] Performance optimizations
- [ ] Security audit

---

## Future Enhancements

### 1. Automatic Worktree Cleanup

**Description**: Automatically remove worktrees after PR merge/close

**Implementation**:

- Watch for PR closed/merged events
- Call `Aidp::Worktree.remove` for associated worktree
- Configurable retention period

### 2. Worktree Reuse Optimization

**Description**: Intelligent worktree reuse based on branch history

**Implementation**:

- Track worktree last used timestamp
- Prioritize recent worktrees for reuse
- Clean up stale worktrees

### 3. Parallel PR Processing

**Description**: Process multiple PRs concurrently in separate worktrees

**Implementation**:

- Thread pool for PR processing
- One worktree per thread
- Coordinated state management

### 4. Incremental Change Application

**Description**: Apply changes incrementally with checkpoints

**Implementation**:

- Create commit after each logical change group
- Allow partial success with continuation
- Better error recovery

### 5. Merge Conflict Detection

**Description**: Detect and handle merge conflicts proactively

**Implementation**:

- Merge base_ref before applying changes
- Detect conflicts early
- Provide conflict resolution guidance

---

## Appendix: Example Scenarios

### Scenario 1: First-Time PR Change Request

**Context**: PR #123 with 5000 lines of changes

**Flow**:

1. User adds `aidp-request-changes` label
2. `ChangeRequestProcessor#process` called
3. `WorktreeBranchManager#ensure_worktree_for_pr` called
4. No existing worktree found → create new
5. Worktree created at `.worktrees/pr-123-feature-branch`
6. Branch checked out and synced
7. AI analyzes comments and generates changes
8. `ChangeApplicator#apply_changes` applies changes
9. Tests run in worktree (pass)
10. `PullRequestSynchronizer#sync_changes` commits and pushes
11. Success comment posted
12. Label removed

**Result**: Changes applied despite 5000-line PR (no size limit)

### Scenario 2: Follow-Up Change Request

**Context**: Same PR #123, user adds label again for more changes

**Flow**:

1. User adds `aidp-request-changes` label again
2. `ChangeRequestProcessor#process` called
3. `WorktreeBranchManager#ensure_worktree_for_pr` called
4. Existing worktree found → reuse
5. Worktree synced to latest (git pull)
6. AI analyzes new comments
7. Changes applied
8. Tests run (pass)
9. New commit created and pushed
10. Success comment posted

**Result**: Worktree reused, faster processing

### Scenario 3: Change Application Failure

**Context**: AI generates invalid file path

**Flow**:

1. Change request processed
2. `ChangeApplicator#validate_changes` detects path traversal
3. Validation fails
4. Error comment posted to PR
5. Label removed
6. No changes applied (atomic)

**Result**: Safe failure, no partial changes

### Scenario 4: Test Failure After Changes

**Context**: Changes applied but tests fail

**Flow**:

1. Changes applied successfully
2. Tests run in worktree
3. Tests fail
4. Commit created locally (NOT pushed)
5. Test failure comment posted
6. Label removed
7. User can fix manually or add new comment

**Result**: Fix-forward strategy, work preserved

---

## Glossary

- **Worktree**: Git feature allowing multiple working directories for one repository
- **PR Context**: Information needed to work with a PR (number, branch, SHA, etc.)
- **Change Applicator**: Service that applies file modifications
- **Synchronizer**: Service that commits and pushes changes
- **Atomic Changes**: All changes applied or none (transactional)
- **Fix-Forward**: Commit locally on failure, don't push, allow manual fix
- **Facade Pattern**: Simplified interface to complex subsystem
- **Command Pattern**: Encapsulate operations as objects with execute/undo
- **Template Method**: Define algorithm structure, allow step customization
- **Adapter Pattern**: Make existing interface compatible with new usage

---

**Document Version**: 1.0
**Last Updated**: 2025-11-22
**Author**: AI Implementation Guide Generator
**Status**: Ready for Implementation
