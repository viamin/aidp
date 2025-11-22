# Implementation Guide: GitHub Projects Integration (Issue #292)

## Overview

This guide provides architectural patterns, design decisions, and implementation strategies for integrating GitHub Projects into AIDP's planning and watch modes. The implementation enables hierarchical issue management with automated sub-issue creation, blocking relationships, custom metadata, and PR workflow orchestration.

**Core Capabilities:**
- Create GitHub Projects from WBS/Gantt planning artifacts
- Generate sub-issues with blocking relationships matching critical path dependencies
- Apply custom metadata for skills and persona assignments
- Implement hierarchical PR workflow (parent PR ← sub-issue PRs)
- Auto-merge sub-issue PRs when CI passes
- Extend watch mode to handle aidp-auto labeled sub-issues

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Domain Model](#domain-model)
3. [Design Patterns](#design-patterns)
4. [Implementation Contract](#implementation-contract)
5. [Component Design](#component-design)
6. [GitHub GraphQL Integration](#github-graphql-integration)
7. [Testing Strategy](#testing-strategy)
8. [Pattern-to-Use-Case Matrix](#pattern-to-use-case-matrix)
9. [Error Handling Strategy](#error-handling-strategy)
10. [Configuration Schema](#configuration-schema)

---

## Architecture Overview

### Hexagonal Architecture Layers

```plaintext
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ WaterfallRunner  │           │ WatchRunner      │        │
│  │ (Planning Mode)  │           │ (Execution)      │        │
│  └──────────────────┘           └──────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                            │
│  ┌────────────────────────────────────────────┐             │
│  │  ProjectOrchestrator (NEW)                 │             │
│  │  - Coordinates project creation workflow   │             │
│  │  - Manages parent issue and sub-issues     │             │
│  │  - Orchestrates PR hierarchy               │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  SubIssueManager (NEW)                     │             │
│  │  - Creates sub-issues from WBS tasks       │             │
│  │  - Maps dependencies to blocking relations │             │
│  │  - Applies aidp-auto labels                │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  HierarchicalPRWorkflow (NEW)              │             │
│  │  - Manages parent PR creation              │             │
│  │  - Creates sub-issue PRs targeting parent  │             │
│  │  - Handles auto-merge logic                │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  PlanGenerator (ENHANCED)                  │             │
│  │  - Generates implementation plan           │             │
│  │  - Triggers project creation when enabled  │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  BuildProcessor (ENHANCED)                 │             │
│  │  - Checks for unblocked sub-issues         │             │
│  │  - Auto-merges sub-issue PRs when complete │             │
│  └────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Infrastructure Layer                       │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ GitHubProjects   │           │ RepositoryClient │        │
│  │ Client (NEW)     │           │ (ENHANCED)       │        │
│  └──────────────────┘           └──────────────────┘        │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ Configuration    │           │ StateStore       │        │
│  │ (aidp.yml)       │           │ (Persistence)    │        │
│  └──────────────────┘           └──────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **Composition Over Inheritance**: GitHubProjectsClient composed into SubIssueManager
2. **Single Responsibility**: Each service has one clear purpose
3. **Dependency Injection**: All GitHub clients and dependencies injected for testability
4. **Service Object Pattern**: Stateless services for project/PR orchestration
5. **GraphQL First**: Use GitHub GraphQL API for Projects v2 operations
6. **Idempotency**: All operations support retries and partial completion
7. **Zero Framework Cognition**: Use AI for persona-to-task mapping decisions

---

## Domain Model

### Core Entities

#### GitHubProject (Value Object - NEW)

```ruby
# Represents a GitHub Project v2 instance
{
  id: String,                    # GraphQL node ID
  number: Integer,               # Project number
  title: String,                 # Project title
  url: String,                   # Project URL
  parent_issue_number: Integer,  # Associated parent issue
  created_at: Time,              # Creation timestamp
  metadata: Hash                 # Custom field values
}
```

#### SubIssue (Value Object - NEW)

```ruby
# Represents a sub-issue created from WBS task
{
  number: Integer,              # Issue number
  title: String,                # Issue title
  body: String,                 # Issue description
  labels: Array<String>,        # Labels including "aidp-auto"
  parent_issue: Integer,        # Parent issue number
  project_id: String,           # GraphQL project node ID
  task_id: String,              # Original WBS task ID
  dependencies: Array<Integer>, # Blocking issue numbers
  persona: String,              # Assigned persona/role
  skills: Array<String>,        # Required skills
  effort: Integer,              # Story points
  acceptance_criteria: Array<String>
}
```

#### PRHierarchy (Value Object - NEW)

```ruby
# Represents hierarchical PR structure
{
  parent_pr: {
    number: Integer,
    head: String,               # Branch name
    base: String,               # Target branch (usually main)
    draft: Boolean,
    issue_number: Integer       # Parent issue
  },
  sub_prs: Array<{
    number: Integer,
    head: String,               # Sub-issue branch
    base: String,               # Parent branch
    issue_number: Integer,      # Sub-issue number
    auto_merge: Boolean,        # Auto-merge enabled
    ci_status: Symbol           # :pending, :success, :failure
  }>
}
```

#### ProjectConfig (Value Object - NEW)

```ruby
# Configuration for GitHub Projects integration
{
  enabled: Boolean,                  # Feature flag
  auto_create: Boolean,              # Auto-create on planning
  custom_fields: Hash,               # Field name => field type
  default_metadata: Hash,            # Default field values
  auto_merge_sub_prs: Boolean,       # Enable auto-merge
  require_ci_pass: Boolean,          # Require CI before merge
  sub_issue_label: String            # Label for auto-pickup (default: "aidp-auto")
}
```

### Domain Services

#### GitHubProjectsClient (NEW)

**Responsibility**: Low-level GitHub Projects v2 API operations

**Design Pattern**: Adapter Pattern + Repository Pattern

**Contract**:

```ruby
module Aidp
  module Watch
    # GitHub Projects v2 client using GraphQL API
    # Wraps project creation, sub-issue management, and custom field operations
    class GitHubProjectsClient
      # @param repository_client [RepositoryClient] Authenticated GitHub client
      def initialize(repository_client:)
        # Preconditions:
        # - repository_client must be authenticated
        # - repository_client must have gh CLI available for GraphQL

        # Postconditions:
        # - Client ready for Projects v2 operations
        # - GraphQL queries cached for performance
      end

      # Create a new GitHub Project v2
      # @param owner [String] Repository owner
      # @param repo [String] Repository name
      # @param title [String] Project title
      # @param description [String] Project description
      # @return [Hash] Project data with GraphQL node ID
      def create_project(owner:, repo:, title:, description: nil)
        # Preconditions:
        # - owner and repo must be valid
        # - title must not be empty
        # - User must have project creation permissions

        # Postconditions:
        # - Project created in repository
        # - Returns project ID and URL
        # - Idempotent: returns existing project if title matches
      end

      # Add custom field to project
      # @param project_id [String] GraphQL node ID
      # @param field_name [String] Field name
      # @param field_type [Symbol] :text, :number, :single_select, :iteration
      # @param options [Hash] Field-specific options
      # @return [Hash] Field configuration
      def add_custom_field(project_id:, field_name:, field_type:, options: {})
        # Preconditions:
        # - project_id must be valid GraphQL node ID
        # - field_type must be supported

        # Postconditions:
        # - Custom field added to project
        # - Returns field ID for future updates
      end

      # Create sub-issue linked to parent
      # @param parent_issue [Integer] Parent issue number
      # @param title [String] Sub-issue title
      # @param body [String] Sub-issue body
      # @param labels [Array<String>] Labels to apply
      # @return [Hash] Created issue data
      def create_sub_issue(parent_issue:, title:, body:, labels: [])
        # Preconditions:
        # - parent_issue must exist
        # - title must not be empty

        # Postconditions:
        # - Sub-issue created with "aidp-auto" label
        # - Linked to parent via issue reference
        # - Added to project if parent is in project
      end

      # Set blocking relationship between issues
      # @param blocked_issue [Integer] Issue being blocked
      # @param blocking_issues [Array<Integer>] Issues that must complete first
      # @return [Boolean] Success status
      def set_blocking_relationships(blocked_issue:, blocking_issues:)
        # Preconditions:
        # - All issue numbers must exist
        # - No circular dependencies

        # Postconditions:
        # - Blocking relationships established in project
        # - Graph validation performed
        # - Errors raised on circular dependencies
      end

      # Update project item custom fields
      # @param project_id [String] GraphQL project ID
      # @param item_id [String] Project item ID
      # @param field_values [Hash] Field name => value
      # @return [Boolean] Success status
      def update_item_fields(project_id:, item_id:, field_values:)
        # Preconditions:
        # - project_id and item_id valid
        # - field_values keys match existing fields

        # Postconditions:
        # - Custom field values updated
        # - Validation errors raised for invalid values
      end

      private

      # Execute GraphQL mutation
      def execute_graphql_mutation(query, variables)
        # Uses gh CLI for GraphQL execution
      end

      # Execute GraphQL query
      def execute_graphql_query(query, variables)
        # Uses gh CLI for GraphQL execution
      end
    end
  end
end
```

#### SubIssueManager (NEW)

**Responsibility**: Orchestrate sub-issue creation from WBS/Gantt data

**Design Pattern**: Service Object + Facade Pattern

**Contract**:

```ruby
module Aidp
  module Watch
    # Manages sub-issue lifecycle: creation, dependency mapping, labeling
    class SubIssueManager
      # @param projects_client [GitHubProjectsClient] Projects API client
      # @param repository_client [RepositoryClient] General GitHub client
      def initialize(projects_client:, repository_client:)
        # Preconditions:
        # - Both clients must be initialized

        # Postconditions:
        # - Manager ready to create sub-issues
      end

      # Create sub-issues from WBS and Gantt chart
      # @param parent_issue [Integer] Parent issue number
      # @param wbs_data [Hash] WBS structure
      # @param gantt_data [Hash] Gantt chart with dependencies
      # @param persona_map [Hash] Task-to-persona mappings
      # @return [Array<Hash>] Created sub-issues with metadata
      def create_from_wbs(parent_issue:, wbs_data:, gantt_data:, persona_map: {})
        # Preconditions:
        # - parent_issue must exist
        # - wbs_data and gantt_data must be valid structures
        # - persona_map optional but recommended

        # Postconditions:
        # - Sub-issue created for each WBS task
        # - Dependencies mapped to blocking relationships
        # - aidp-auto label applied to all sub-issues
        # - Persona metadata set on project items
        # - Returns array of created issues
      end

      # Map Gantt dependencies to GitHub blocking relationships
      # @param gantt_tasks [Array<Hash>] Tasks with dependencies
      # @param created_issues [Hash] Map of task_id => issue_number
      # @return [Hash] Dependency graph
      def map_dependencies_to_blocks(gantt_tasks:, created_issues:)
        # Preconditions:
        # - gantt_tasks contains dependency information
        # - created_issues maps all task IDs to issue numbers

        # Postconditions:
        # - Returns graph of blocking relationships
        # - Validates no circular dependencies
        # - Ready for application via GitHubProjectsClient
      end

      # Check if sub-issue is unblocked and ready for execution
      # @param issue_number [Integer] Sub-issue to check
      # @return [Boolean] True if unblocked
      def unblocked?(issue_number)
        # Preconditions:
        # - issue_number must be a sub-issue

        # Postconditions:
        # - Returns true if all blocking issues are closed
        # - Returns false if any blockers open
        # - Handles missing/deleted blockers gracefully
      end

      private

      def build_sub_issue_body(task, persona, acceptance_criteria)
        # Generate markdown body with task details
      end

      def extract_skills_from_persona(persona, persona_map)
        # Extract skill requirements from persona definition
      end
    end
  end
end
```

#### HierarchicalPRWorkflow (NEW)

**Responsibility**: Manage parent/sub-issue PR creation and auto-merge

**Design Pattern**: Service Object + State Machine

**Contract**:

```ruby
module Aidp
  module Watch
    # Orchestrates hierarchical PR workflow for parent and sub-issues
    class HierarchicalPRWorkflow
      # @param repository_client [RepositoryClient] GitHub client
      # @param state_store [StateStore] Persistence layer
      def initialize(repository_client:, state_store:)
        # Preconditions:
        # - repository_client authenticated
        # - state_store initialized

        # Postconditions:
        # - Workflow manager ready
      end

      # Create parent PR for issue
      # @param parent_issue [Integer] Parent issue number
      # @param branch [String] Parent feature branch
      # @param base [String] Target branch (default: main)
      # @param draft [Boolean] Create as draft
      # @return [Hash] PR data
      def create_parent_pr(parent_issue:, branch:, base: "main", draft: true)
        # Preconditions:
        # - parent_issue exists
        # - branch exists in repository
        # - No existing PR from branch to base

        # Postconditions:
        # - Draft PR created targeting base
        # - PR linked to parent issue
        # - State stored for sub-PR creation
        # - Returns PR number and URL
      end

      # Create sub-issue PR targeting parent branch
      # @param sub_issue [Integer] Sub-issue number
      # @param branch [String] Sub-issue branch
      # @param parent_branch [String] Parent branch to target
      # @param auto_merge [Boolean] Enable auto-merge
      # @return [Hash] PR data
      def create_sub_pr(sub_issue:, branch:, parent_branch:, auto_merge: true)
        # Preconditions:
        # - sub_issue exists with aidp-auto label
        # - branch exists in repository
        # - parent_branch exists
        # - Parent PR exists targeting parent_branch

        # Postconditions:
        # - PR created targeting parent branch
        # - Auto-merge enabled if requested
        # - PR linked to sub-issue
        # - State stored for merge tracking
      end

      # Check and execute auto-merge for sub-PR if conditions met
      # @param pr_number [Integer] PR to check
      # @return [Symbol] :merged, :waiting, :failed
      def try_auto_merge(pr_number)
        # Preconditions:
        # - pr_number is a sub-issue PR
        # - PR has auto-merge enabled

        # Postconditions:
        # - Merges if CI passed and reviewable
        # - Returns :merged if successful
        # - Returns :waiting if CI pending
        # - Returns :failed if CI failed
        # - Removes aidp-auto label on merge
      end

      # Finalize parent PR when all sub-PRs merged
      # @param parent_pr [Integer] Parent PR number
      # @return [Boolean] True if finalized
      def finalize_parent_pr(parent_pr)
        # Preconditions:
        # - parent_pr exists
        # - All sub-PRs merged

        # Postconditions:
        # - Updates PR description with summary
        # - Marks PR as ready for review
        # - Posts completion comment
        # - Returns true if successful
      end

      private

      def all_sub_prs_merged?(parent_pr)
        # Check if all sub-PRs are merged
      end

      def generate_implementation_summary(parent_pr)
        # Generate summary of completed work
      end
    end
  end
end
```

---

## Design Patterns

### 1. Adapter Pattern (NEW)

**Purpose**: Adapt GitHub GraphQL API to AIDP's domain model

**Application**: `GitHubProjectsClient` adapts GraphQL Projects v2 API

**Benefits**:
- Isolates GraphQL complexity
- Makes testing easier (mock adapter, not API)
- Can swap implementations (REST fallback)

**Implementation**:

```ruby
class GitHubProjectsClient
  # GraphQL mutation templates
  CREATE_PROJECT_MUTATION = <<~GRAPHQL
    mutation($owner: String!, $repo: String!, $title: String!) {
      createProjectV2(input: {
        ownerId: $owner
        repositoryId: $repo
        title: $title
      }) {
        projectV2 {
          id
          number
          url
        }
      }
    }
  GRAPHQL

  def create_project(owner:, repo:, title:, description: nil)
    variables = {owner: owner, repo: repo, title: title}
    result = execute_graphql_mutation(CREATE_PROJECT_MUTATION, variables)

    # Adapt GraphQL response to domain model
    {
      id: result.dig("data", "createProjectV2", "projectV2", "id"),
      number: result.dig("data", "createProjectV2", "projectV2", "number"),
      url: result.dig("data", "createProjectV2", "projectV2", "url")
    }
  end
end
```

### 2. Facade Pattern (NEW)

**Purpose**: Simplify complex GitHub Projects workflow behind simple interface

**Application**: `SubIssueManager` facades multi-step sub-issue creation

**Benefits**:
- Hides GraphQL complexity
- Provides high-level operations
- Easier to test and maintain

### 3. Service Object Pattern (Enhanced)

**Purpose**: Encapsulate business logic in stateless services

**Application**: All orchestrators and managers

**Benefits**:
- Single Responsibility Principle
- Reusable across modes (planning, watch)
- Easily testable

### 4. Composition Pattern (Enhanced)

**Purpose**: Compose complex behavior from simple components

**Application**: Managers compose clients

```ruby
class SubIssueManager
  def initialize(projects_client:, repository_client:)
    @projects_client = projects_client
    @repository_client = repository_client
  end

  def create_from_wbs(parent_issue:, wbs_data:, gantt_data:, persona_map: {})
    # Use composed clients
    project = @projects_client.create_project(...)
    wbs_data[:phases].each do |phase|
      phase[:tasks].each do |task|
        issue = @repository_client.create_issue(...)
        @projects_client.add_to_project(project[:id], issue[:number])
      end
    end
  end
end
```

### 5. State Machine Pattern (NEW)

**Purpose**: Track PR workflow states and transitions

**Application**: `HierarchicalPRWorkflow` state management

**States**:
- `parent_pr_created`: Parent PR exists, waiting for sub-PRs
- `sub_pr_pending`: Sub-PR created, CI running
- `sub_pr_ready`: CI passed, ready to merge
- `sub_pr_merged`: Merged into parent
- `parent_pr_ready`: All sub-PRs merged, ready for review

**Implementation**:

```ruby
class HierarchicalPRWorkflow
  STATES = {
    parent_pr_created: :parent_pr_created,
    sub_pr_pending: :sub_pr_pending,
    sub_pr_ready: :sub_pr_ready,
    sub_pr_merged: :sub_pr_merged,
    parent_pr_ready: :parent_pr_ready
  }.freeze

  def try_auto_merge(pr_number)
    current_state = @state_store.get_pr_state(pr_number)

    case current_state
    when :sub_pr_pending
      check_ci_and_transition(pr_number)
    when :sub_pr_ready
      execute_merge(pr_number)
    else
      :waiting
    end
  end
end
```

### 6. Repository Pattern (Enhanced)

**Purpose**: Abstract data persistence and retrieval

**Application**: `StateStore` for PR state, project mappings

**Benefits**:
- Consistent data access interface
- Testable (in-memory vs. file-based)
- Hides persistence details

---

## Implementation Contract

### Design by Contract Principles

All public methods specify:

1. **Preconditions**: What must be true before execution
2. **Postconditions**: What will be true after execution
3. **Invariants**: What remains true throughout lifecycle
4. **Idempotency**: Operations can be safely retried

### Example Contracts

#### GitHubProjectsClient#create_sub_issue

```ruby
# Create sub-issue linked to parent issue
#
# @param parent_issue [Integer] Parent issue number
# @param title [String] Sub-issue title
# @param body [String] Sub-issue body
# @param labels [Array<String>] Labels including "aidp-auto"
# @return [Hash] Created issue data
#
# Preconditions:
#   - parent_issue must exist in repository
#   - title must not be empty
#   - User must have issue creation permissions
#   - labels must include "aidp-auto"
#
# Postconditions:
#   - Sub-issue created with all provided labels
#   - Issue body includes reference to parent: "Parent: #123"
#   - Issue added to same project as parent (if parent in project)
#   - Returns issue number, URL, and project item ID
#
# Idempotency:
#   - If issue with identical title exists under parent, returns existing
#   - Safe to retry on network failures
#
# Invariants:
#   - Total issue count increases by 1 (or 0 if idempotent match)
#   - Parent issue remains unchanged
#   - @repository_client and @projects_client remain valid
def create_sub_issue(parent_issue:, title:, body:, labels: [])
  Aidp.log_debug("github_projects_client", "create_sub_issue",
    parent: parent_issue,
    title: title,
    labels: labels.join(","))

  # Validate preconditions
  raise ArgumentError, "title cannot be empty" if title.nil? || title.strip.empty?
  raise ArgumentError, "must include aidp-auto label" unless labels.include?("aidp-auto")

  # Idempotency check
  existing = find_existing_sub_issue(parent_issue, title)
  return existing if existing

  # Implementation...

  Aidp.log_info("github_projects_client", "sub_issue_created",
    parent: parent_issue,
    number: result[:number],
    project_item: result[:project_item_id])

  result
end
```

---

## Component Design

### 1. GitHubProjectsClient (NEW)

#### File Location

`lib/aidp/watch/github_projects_client.rb`

#### Class Structure

```ruby
# frozen_string_literal: true

require "json"
require_relative "../logger"

module Aidp
  module Watch
    # GitHub Projects v2 client using GraphQL API
    # Handles project creation, sub-issues, custom fields, blocking relationships
    class GitHubProjectsClient
      # GraphQL mutation for creating project
      CREATE_PROJECT_MUTATION = <<~GRAPHQL
        mutation CreateProjectV2($ownerId: ID!, $title: String!, $repositoryId: ID) {
          createProjectV2(input: {
            ownerId: $ownerId
            title: $title
            repositoryId: $repositoryId
          }) {
            projectV2 {
              id
              number
              url
              title
            }
          }
        }
      GRAPHQL

      # GraphQL mutation for adding issue to project
      ADD_ITEM_MUTATION = <<~GRAPHQL
        mutation AddProjectV2Item($projectId: ID!, $contentId: ID!) {
          addProjectV2ItemById(input: {
            projectId: $projectId
            contentId: $contentId
          }) {
            item {
              id
            }
          }
        }
      GRAPHQL

      # GraphQL mutation for custom field creation
      CREATE_FIELD_MUTATION = <<~GRAPHQL
        mutation CreateProjectV2Field($projectId: ID!, $name: String!, $dataType: ProjectV2CustomFieldType!) {
          createProjectV2Field(input: {
            projectId: $projectId
            name: $name
            dataType: $dataType
          }) {
            projectV2Field {
              __typename
              id
              name
            }
          }
        }
      GRAPHQL

      def initialize(repository_client:)
        @repository_client = repository_client

        unless @repository_client.gh_available?
          raise ArgumentError, "GitHub CLI required for Projects v2 GraphQL operations"
        end

        Aidp.log_debug("github_projects_client", "initialized",
          owner: @repository_client.owner,
          repo: @repository_client.repo)
      end

      # Create GitHub Project v2
      def create_project(title:, description: nil)
        Aidp.log_debug("github_projects_client", "create_project", title: title)

        # Get repository and owner IDs
        owner_id = fetch_owner_id
        repo_id = fetch_repository_id

        variables = {
          ownerId: owner_id,
          title: title,
          repositoryId: repo_id
        }

        result = execute_graphql_mutation(CREATE_PROJECT_MUTATION, variables)
        project_data = result.dig("data", "createProjectV2", "projectV2")

        Aidp.log_info("github_projects_client", "project_created",
          id: project_data["id"],
          number: project_data["number"],
          url: project_data["url"])

        {
          id: project_data["id"],
          number: project_data["number"],
          url: project_data["url"],
          title: project_data["title"]
        }
      rescue => e
        Aidp.log_error("github_projects_client", "create_project_failed",
          error: e.message,
          title: title)
        raise
      end

      # Add issue to project
      def add_issue_to_project(project_id:, issue_number:)
        Aidp.log_debug("github_projects_client", "add_issue_to_project",
          project_id: project_id,
          issue_number: issue_number)

        # Get issue node ID
        issue_id = fetch_issue_node_id(issue_number)

        variables = {
          projectId: project_id,
          contentId: issue_id
        }

        result = execute_graphql_mutation(ADD_ITEM_MUTATION, variables)
        item_id = result.dig("data", "addProjectV2ItemById", "item", "id")

        Aidp.log_info("github_projects_client", "issue_added_to_project",
          issue_number: issue_number,
          item_id: item_id)

        {item_id: item_id}
      rescue => e
        Aidp.log_error("github_projects_client", "add_issue_failed",
          error: e.message,
          issue_number: issue_number)
        raise
      end

      # Create custom field on project
      def create_custom_field(project_id:, field_name:, field_type: "TEXT")
        Aidp.log_debug("github_projects_client", "create_custom_field",
          project_id: project_id,
          field_name: field_name,
          field_type: field_type)

        variables = {
          projectId: project_id,
          name: field_name,
          dataType: field_type
        }

        result = execute_graphql_mutation(CREATE_FIELD_MUTATION, variables)
        field_data = result.dig("data", "createProjectV2Field", "projectV2Field")

        Aidp.log_info("github_projects_client", "custom_field_created",
          field_id: field_data["id"],
          field_name: field_data["name"])

        {
          id: field_data["id"],
          name: field_data["name"]
        }
      rescue => e
        Aidp.log_error("github_projects_client", "create_field_failed",
          error: e.message,
          field_name: field_name)
        raise
      end

      # Update custom field value for project item
      def update_item_field(project_id:, item_id:, field_id:, value:)
        Aidp.log_debug("github_projects_client", "update_item_field",
          item_id: item_id,
          field_id: field_id)

        mutation = <<~GRAPHQL
          mutation UpdateProjectV2ItemField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $value: String!) {
            updateProjectV2ItemFieldValue(input: {
              projectId: $projectId
              itemId: $itemId
              fieldId: $fieldId
              value: {text: $value}
            }) {
              projectV2Item {
                id
              }
            }
          }
        GRAPHQL

        variables = {
          projectId: project_id,
          itemId: item_id,
          fieldId: field_id,
          value: value.to_s
        }

        execute_graphql_mutation(mutation, variables)

        Aidp.log_info("github_projects_client", "field_updated",
          item_id: item_id)
      rescue => e
        Aidp.log_error("github_projects_client", "update_field_failed",
          error: e.message,
          item_id: item_id)
        raise
      end

      private

      def execute_graphql_mutation(query, variables)
        # Use gh CLI to execute GraphQL
        query_json = {query: query, variables: variables}.to_json
        stdout, stderr, status = Open3.capture3(
          "gh", "api", "graphql",
          "-f", "query=#{query}",
          *variables.flat_map { |k, v| ["-F", "#{k}=#{v}"] }
        )

        unless status.success?
          raise "GraphQL mutation failed: #{stderr}"
        end

        JSON.parse(stdout)
      rescue => e
        Aidp.log_error("github_projects_client", "graphql_mutation_failed",
          error: e.message)
        raise
      end

      def fetch_owner_id
        # GraphQL query to get owner node ID
        query = <<~GRAPHQL
          query GetOwner($owner: String!) {
            repositoryOwner(login: $owner) {
              id
            }
          }
        GRAPHQL

        result = execute_graphql_query(query, {owner: @repository_client.owner})
        result.dig("data", "repositoryOwner", "id")
      end

      def fetch_repository_id
        # GraphQL query to get repository node ID
        query = <<~GRAPHQL
          query GetRepository($owner: String!, $repo: String!) {
            repository(owner: $owner, name: $repo) {
              id
            }
          }
        GRAPHQL

        result = execute_graphql_query(query, {
          owner: @repository_client.owner,
          repo: @repository_client.repo
        })
        result.dig("data", "repository", "id")
      end

      def fetch_issue_node_id(issue_number)
        # Use RepositoryClient to fetch issue, extract node_id
        issue = @repository_client.fetch_issue(issue_number)
        issue[:node_id]
      end

      def execute_graphql_query(query, variables)
        stdout, stderr, status = Open3.capture3(
          "gh", "api", "graphql",
          "-f", "query=#{query}",
          *variables.flat_map { |k, v| ["-F", "#{k}=#{v}"] }
        )

        unless status.success?
          raise "GraphQL query failed: #{stderr}"
        end

        JSON.parse(stdout)
      end
    end
  end
end
```

### 2. SubIssueManager (NEW)

#### File Location

`lib/aidp/watch/sub_issue_manager.rb`

#### Class Structure

```ruby
# frozen_string_literal: true

require_relative "github_projects_client"
require_relative "../logger"

module Aidp
  module Watch
    # Manages sub-issue creation from WBS/Gantt planning artifacts
    # Maps dependencies to GitHub blocking relationships
    class SubIssueManager
      DEFAULT_LABEL = "aidp-auto"

      def initialize(projects_client:, repository_client:, config: {})
        @projects_client = projects_client
        @repository_client = repository_client
        @config = config

        Aidp.log_debug("sub_issue_manager", "initialized",
          auto_label: auto_label)
      end

      # Create sub-issues from WBS and Gantt data
      def create_from_wbs(parent_issue:, wbs_data:, gantt_data:, persona_map: {}, project_id: nil)
        Aidp.log_debug("sub_issue_manager", "create_from_wbs",
          parent: parent_issue,
          task_count: count_tasks(wbs_data))

        created_issues = {}
        task_to_issue = {}

        # First pass: create all sub-issues
        wbs_data[:phases].each do |phase|
          phase[:tasks].each do |task|
            issue = create_sub_issue_for_task(
              parent_issue: parent_issue,
              task: task,
              phase: phase[:name],
              persona_map: persona_map
            )

            created_issues[task[:id]] = issue
            task_to_issue[task[:id]] = issue[:number]

            # Add to project if provided
            if project_id
              @projects_client.add_issue_to_project(
                project_id: project_id,
                issue_number: issue[:number]
              )
            end
          end
        end

        # Second pass: set blocking relationships from Gantt dependencies
        if gantt_data && gantt_data[:tasks]
          apply_blocking_relationships(gantt_data[:tasks], task_to_issue)
        end

        Aidp.log_info("sub_issue_manager", "sub_issues_created",
          parent: parent_issue,
          count: created_issues.size)

        created_issues.values
      end

      # Check if sub-issue is unblocked
      def unblocked?(issue_number)
        Aidp.log_debug("sub_issue_manager", "check_unblocked",
          issue: issue_number)

        # Fetch issue to check for blocking references
        issue = @repository_client.fetch_issue(issue_number)

        # Parse body for "Blocked by: #123, #456" pattern
        blocking_issues = extract_blocking_issues(issue[:body])

        if blocking_issues.empty?
          Aidp.log_debug("sub_issue_manager", "no_blockers", issue: issue_number)
          return true
        end

        # Check if all blocking issues are closed
        all_closed = blocking_issues.all? do |blocker_number|
          blocker = @repository_client.fetch_issue(blocker_number)
          blocker[:state] == "closed"
        rescue => e
          Aidp.log_warn("sub_issue_manager", "blocker_check_failed",
            issue: issue_number,
            blocker: blocker_number,
            error: e.message)
          false # Conservative: treat errors as still blocking
        end

        Aidp.log_debug("sub_issue_manager", "unblocked_check",
          issue: issue_number,
          blockers: blocking_issues,
          all_closed: all_closed)

        all_closed
      end

      private

      def auto_label
        @config.fetch(:sub_issue_label, DEFAULT_LABEL)
      end

      def create_sub_issue_for_task(parent_issue:, task:, phase:, persona_map:)
        Aidp.log_debug("sub_issue_manager", "create_task_issue",
          task_id: task[:id],
          task_name: task[:name])

        persona = persona_map[task[:id]]
        skills = extract_skills_for_task(task, persona_map)

        body = build_issue_body(
          task: task,
          parent_issue: parent_issue,
          phase: phase,
          persona: persona,
          skills: skills
        )

        # Create issue via repository client
        result = @repository_client.create_issue(
          title: task[:name],
          body: body,
          labels: [auto_label, phase.downcase.tr(" ", "-")]
        )

        Aidp.log_info("sub_issue_manager", "task_issue_created",
          task_id: task[:id],
          issue_number: result[:number])

        {
          number: result[:number],
          title: task[:name],
          task_id: task[:id],
          persona: persona,
          skills: skills
        }
      end

      def build_issue_body(task:, parent_issue:, phase:, persona:, skills:)
        parts = []
        parts << "**Parent Issue:** ##{parent_issue}"
        parts << ""
        parts << "**Phase:** #{phase}"
        parts << ""

        if task[:description]
          parts << "## Description"
          parts << task[:description]
          parts << ""
        end

        if persona
          parts << "**Assigned Persona:** #{persona}"
          parts << ""
        end

        if skills && skills.any?
          parts << "**Required Skills:** #{skills.join(", ")}"
          parts << ""
        end

        if task[:acceptance_criteria] && task[:acceptance_criteria].any?
          parts << "## Acceptance Criteria"
          task[:acceptance_criteria].each do |criterion|
            parts << "- [ ] #{criterion}"
          end
          parts << ""
        end

        if task[:effort]
          parts << "**Effort Estimate:** #{task[:effort]}"
          parts << ""
        end

        parts << "---"
        parts << "*This sub-issue was automatically created by AIDP from the project WBS.*"

        parts.join("\n")
      end

      def apply_blocking_relationships(gantt_tasks, task_to_issue)
        Aidp.log_debug("sub_issue_manager", "apply_blocking_relationships",
          task_count: gantt_tasks.size)

        gantt_tasks.each do |gantt_task|
          next if gantt_task[:dependencies].empty?

          blocked_issue = task_to_issue[gantt_task[:id]]
          next unless blocked_issue

          blocking_issue_numbers = gantt_task[:dependencies].map do |dep_task_id|
            task_to_issue[dep_task_id]
          end.compact

          next if blocking_issue_numbers.empty?

          # Update blocked issue body with blocking references
          add_blocking_references(blocked_issue, blocking_issue_numbers)
        end
      end

      def add_blocking_references(issue_number, blocking_issues)
        Aidp.log_debug("sub_issue_manager", "add_blocking_refs",
          issue: issue_number,
          blockers: blocking_issues)

        issue = @repository_client.fetch_issue(issue_number)

        blocking_line = "**Blocked by:** #{blocking_issues.map { |n| "##{n}" }.join(", ")}"
        updated_body = "#{blocking_line}\n\n#{issue[:body]}"

        @repository_client.update_issue(
          number: issue_number,
          body: updated_body
        )

        Aidp.log_info("sub_issue_manager", "blocking_refs_added",
          issue: issue_number,
          blocker_count: blocking_issues.size)
      end

      def extract_blocking_issues(body)
        return [] unless body

        # Match "Blocked by: #123, #456"
        match = body.match(/\*\*Blocked by:\*\*\s*((?:#\d+,?\s*)+)/)
        return [] unless match

        match[1].scan(/#(\d+)/).flatten.map(&:to_i)
      end

      def extract_skills_for_task(task, persona_map)
        # Placeholder: could parse from task description or persona definition
        []
      end

      def count_tasks(wbs_data)
        wbs_data[:phases].sum { |phase| phase[:tasks].size }
      end
    end
  end
end
```

---

## GitHub GraphQL Integration

### Projects v2 API Operations

GitHub Projects v2 uses GraphQL exclusively. Key operations:

#### 1. Create Project

```graphql
mutation CreateProjectV2($ownerId: ID!, $title: String!) {
  createProjectV2(input: {
    ownerId: $ownerId
    title: $title
  }) {
    projectV2 {
      id
      number
      url
    }
  }
}
```

#### 2. Add Issue to Project

```graphql
mutation AddProjectV2Item($projectId: ID!, $contentId: ID!) {
  addProjectV2ItemById(input: {
    projectId: $projectId
    contentId: $contentId
  }) {
    item {
      id
    }
  }
}
```

#### 3. Create Custom Field

```graphql
mutation CreateProjectV2Field($projectId: ID!, $name: String!, $dataType: ProjectV2CustomFieldType!) {
  createProjectV2Field(input: {
    projectId: $projectId
    name: $name
    dataType: $dataType
  }) {
    projectV2Field {
      id
      name
    }
  }
}
```

#### 4. Update Field Value

```graphql
mutation UpdateProjectV2ItemField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $value: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $projectId
    itemId: $itemId
    fieldId: $fieldId
    value: {text: $value}
  }) {
    projectV2Item {
      id
    }
  }
}
```

### Execution via gh CLI

All GraphQL operations use `gh api graphql`:

```ruby
def execute_graphql_mutation(query, variables)
  stdout, stderr, status = Open3.capture3(
    "gh", "api", "graphql",
    "-f", "query=#{query}",
    *variables.flat_map { |k, v| ["-F", "#{k}=#{v}"] }
  )

  unless status.success?
    raise "GraphQL mutation failed: #{stderr}"
  end

  JSON.parse(stdout)
end
```

---

## Testing Strategy

### Unit Tests

#### GitHubProjectsClient Specs

**File**: `spec/aidp/watch/github_projects_client_spec.rb`

```ruby
RSpec.describe Aidp::Watch::GitHubProjectsClient do
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient, gh_available?: true, owner: "viamin", repo: "aidp") }
  let(:client) { described_class.new(repository_client: repository_client) }

  describe "#create_project" do
    it "creates project via GraphQL mutation" do
      expect(client).to receive(:execute_graphql_mutation).and_return({
        "data" => {
          "createProjectV2" => {
            "projectV2" => {
              "id" => "PVT_abc123",
              "number" => 1,
              "url" => "https://github.com/orgs/viamin/projects/1",
              "title" => "Test Project"
            }
          }
        }
      })

      result = client.create_project(title: "Test Project")

      expect(result[:id]).to eq("PVT_abc123")
      expect(result[:number]).to eq(1)
      expect(result[:url]).to eq("https://github.com/orgs/viamin/projects/1")
    end

    it "raises error when gh CLI unavailable" do
      allow(repository_client).to receive(:gh_available?).and_return(false)

      expect {
        described_class.new(repository_client: repository_client)
      }.to raise_error(ArgumentError, /GitHub CLI required/)
    end
  end

  describe "#add_issue_to_project" do
    it "adds issue to project and returns item ID" do
      allow(client).to receive(:fetch_issue_node_id).and_return("I_issue123")
      expect(client).to receive(:execute_graphql_mutation).and_return({
        "data" => {
          "addProjectV2ItemById" => {
            "item" => {"id" => "PVTI_item456"}
          }
        }
      })

      result = client.add_issue_to_project(project_id: "PVT_abc", issue_number: 123)

      expect(result[:item_id]).to eq("PVTI_item456")
    end
  end

  describe "#create_custom_field" do
    it "creates text custom field" do
      expect(client).to receive(:execute_graphql_mutation).and_return({
        "data" => {
          "createProjectV2Field" => {
            "projectV2Field" => {
              "id" => "PVTF_field789",
              "name" => "Persona"
            }
          }
        }
      })

      result = client.create_custom_field(
        project_id: "PVT_abc",
        field_name: "Persona",
        field_type: "TEXT"
      )

      expect(result[:id]).to eq("PVTF_field789")
      expect(result[:name]).to eq("Persona")
    end
  end
end
```

#### SubIssueManager Specs

**File**: `spec/aidp/watch/sub_issue_manager_spec.rb`

```ruby
RSpec.describe Aidp::Watch::SubIssueManager do
  let(:projects_client) { instance_double(Aidp::Watch::GitHubProjectsClient) }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:manager) { described_class.new(projects_client: projects_client, repository_client: repository_client) }

  describe "#create_from_wbs" do
    let(:wbs_data) do
      {
        phases: [
          {
            name: "Implementation",
            tasks: [
              {
                id: "task1",
                name: "Build authentication",
                description: "Implement user auth",
                effort: "5 story points",
                acceptance_criteria: ["Users can log in", "Sessions persist"]
              }
            ]
          }
        ]
      }
    end

    let(:gantt_data) do
      {
        tasks: [
          {id: "task1", dependencies: []}
        ]
      }
    end

    it "creates sub-issues for all WBS tasks" do
      expect(repository_client).to receive(:create_issue).with(
        title: "Build authentication",
        body: include("Parent Issue: #100"),
        labels: ["aidp-auto", "implementation"]
      ).and_return({number: 101, title: "Build authentication"})

      results = manager.create_from_wbs(
        parent_issue: 100,
        wbs_data: wbs_data,
        gantt_data: gantt_data
      )

      expect(results.size).to eq(1)
      expect(results.first[:number]).to eq(101)
    end

    it "applies blocking relationships from Gantt dependencies" do
      wbs_with_deps = {
        phases: [
          {
            name: "Implementation",
            tasks: [
              {id: "task1", name: "Task 1"},
              {id: "task2", name: "Task 2"}
            ]
          }
        ]
      }

      gantt_with_deps = {
        tasks: [
          {id: "task1", dependencies: []},
          {id: "task2", dependencies: ["task1"]}
        ]
      }

      allow(repository_client).to receive(:create_issue).and_return(
        {number: 101},
        {number: 102}
      )

      # Expect task2 issue body to include blocking reference
      expect(manager).to receive(:add_blocking_references).with(102, [101])

      manager.create_from_wbs(
        parent_issue: 100,
        wbs_data: wbs_with_deps,
        gantt_data: gantt_with_deps
      )
    end
  end

  describe "#unblocked?" do
    it "returns true when no blocking issues" do
      allow(repository_client).to receive(:fetch_issue).and_return({
        number: 101,
        body: "No blockers"
      })

      expect(manager.unblocked?(101)).to be true
    end

    it "returns false when blocking issues are open" do
      allow(repository_client).to receive(:fetch_issue).with(102).and_return({
        number: 102,
        body: "**Blocked by:** #100, #101"
      })

      allow(repository_client).to receive(:fetch_issue).with(100).and_return({state: "closed"})
      allow(repository_client).to receive(:fetch_issue).with(101).and_return({state: "open"})

      expect(manager.unblocked?(102)).to be false
    end

    it "returns true when all blocking issues closed" do
      allow(repository_client).to receive(:fetch_issue).with(102).and_return({
        number: 102,
        body: "**Blocked by:** #100, #101"
      })

      allow(repository_client).to receive(:fetch_issue).with(100).and_return({state: "closed"})
      allow(repository_client).to receive(:fetch_issue).with(101).and_return({state: "closed"})

      expect(manager.unblocked?(102)).to be true
    end
  end
end
```

### Integration Tests

#### End-to-End GitHub Projects Workflow

**File**: `spec/integration/github_projects_workflow_spec.rb`

```ruby
RSpec.describe "GitHub Projects Workflow", type: :integration do
  # This test requires:
  # - GitHub CLI authenticated
  # - Test repository access
  # - Environment variable: AIDP_TEST_REPO=owner/repo

  let(:test_repo) { ENV.fetch("AIDP_TEST_REPO") }
  let(:owner) { test_repo.split("/").first }
  let(:repo_name) { test_repo.split("/").last }

  before(:each) do
    skip "Set AIDP_TEST_REPO for integration tests" unless ENV["AIDP_TEST_REPO"]
  end

  it "creates project, sub-issues, and applies blocking relationships" do
    repository_client = Aidp::Watch::RepositoryClient.new(owner: owner, repo: repo_name)
    projects_client = Aidp::Watch::GitHubProjectsClient.new(repository_client: repository_client)
    manager = Aidp::Watch::SubIssueManager.new(
      projects_client: projects_client,
      repository_client: repository_client
    )

    # Create parent issue
    parent = repository_client.create_issue(
      title: "[Integration Test] Parent Issue",
      body: "Testing GitHub Projects integration"
    )

    # Create project
    project = projects_client.create_project(
      title: "Integration Test Project #{Time.now.to_i}"
    )

    # Create sub-issues from mock WBS
    wbs_data = {
      phases: [
        {
          name: "Testing",
          tasks: [
            {id: "test1", name: "First task"},
            {id: "test2", name: "Second task"}
          ]
        }
      ]
    }

    gantt_data = {
      tasks: [
        {id: "test1", dependencies: []},
        {id: "test2", dependencies: ["test1"]}
      ]
    }

    sub_issues = manager.create_from_wbs(
      parent_issue: parent[:number],
      wbs_data: wbs_data,
      gantt_data: gantt_data,
      project_id: project[:id]
    )

    # Verify sub-issues created
    expect(sub_issues.size).to eq(2)

    # Verify second issue has blocking reference
    second_issue = repository_client.fetch_issue(sub_issues[1][:number])
    expect(second_issue[:body]).to include("Blocked by: ##{sub_issues[0][:number]}")

    # Cleanup
    repository_client.close_issue(parent[:number])
    sub_issues.each { |issue| repository_client.close_issue(issue[:number]) }
  end
end
```

---

## Pattern-to-Use-Case Matrix

| Use Case | Primary Pattern | Supporting Patterns | Rationale |
| ---------- | ---------------- | --------------------- | ----------- |
| GitHub GraphQL API | Adapter | Repository | Isolate GraphQL complexity |
| Sub-issue creation | Service Object | Facade, Composition | Single responsibility, testable |
| PR workflow | State Machine | Service Object | Track PR states and transitions |
| Dependency mapping | Graph Algorithm | - | Model task dependencies |
| Custom field management | Repository | - | Abstract persistence |
| Idempotent operations | Retry + Memoization | - | Handle network failures |
| Integration testing | Test Double | Dependency Injection | Mock external GitHub API |

---

## Error Handling Strategy

### Principle: Fail Fast for Bugs, Graceful Degradation for External Issues

#### Fail Fast (Raise Errors)

- Invalid configuration (feature disabled, missing permissions)
- Programming errors (nil checks, missing required fields)
- GraphQL schema mismatches
- Circular dependency detection

#### Graceful Degradation (Log and Continue)

- Network failures (retry with exponential backoff)
- GitHub rate limiting (wait and retry)
- Missing optional metadata (use defaults)
- Project already exists (return existing)

### Error Handling Implementation

```ruby
def create_sub_issue(parent_issue:, title:, body:, labels: [])
  # Validate preconditions - fail fast
  raise ArgumentError, "title cannot be empty" if title.nil? || title.strip.empty?
  raise ArgumentError, "parent_issue must exist" unless parent_issue.positive?

  # Idempotency check - graceful
  existing = find_existing_sub_issue(parent_issue, title)
  return existing if existing

  begin
    # External operation - retry on transient failures
    with_retry(max_retries: 3, initial_delay: 1.0) do
      create_issue_via_api(title: title, body: body, labels: labels)
    end
  rescue Aidp::Watch::RateLimitError => e
    # Specific error handling
    Aidp.log_warn("sub_issue_manager", "rate_limited",
      retry_after: e.retry_after,
      parent: parent_issue)
    sleep(e.retry_after)
    retry
  rescue => e
    # Log and re-raise unexpected errors
    Aidp.log_error("sub_issue_manager", "create_failed",
      error: e.message,
      parent: parent_issue,
      title: title)
    raise
  end
end
```

---

## Configuration Schema

### Extended YAML Schema

```yaml
github_projects:
  # Enable GitHub Projects integration
  enabled: true

  # Auto-create project during planning
  auto_create_on_planning: true

  # Sub-issue configuration
  sub_issues:
    # Label applied to all sub-issues for auto-pickup
    label: "aidp-auto"

    # Include persona assignments in issue body
    include_persona: true

    # Include skill requirements in issue body
    include_skills: true

  # Custom fields to create on project
  custom_fields:
    persona:
      type: "TEXT"
      default: "unassigned"

    skills:
      type: "TEXT"
      default: ""

    effort:
      type: "NUMBER"
      default: 0

  # PR workflow configuration
  pr_workflow:
    # Create hierarchical PRs (sub-PRs target parent branch)
    enabled: true

    # Auto-merge sub-PRs when CI passes
    auto_merge_sub_prs: true

    # Require CI to pass before auto-merge
    require_ci_pass: true

    # Create parent PR as draft
    parent_pr_draft: true

  # Blocking relationships
  blocking:
    # Map Gantt dependencies to blocking relationships
    enabled: true

    # Update issue bodies with blocking references
    add_blocking_comments: true
```

### Configuration Accessor Methods

Add to `Configuration` class:

```ruby
# Check if GitHub Projects integration enabled
def github_projects_enabled?
  config.dig(:github_projects, :enabled) == true
end

# Get sub-issue label
def github_projects_sub_issue_label
  config.dig(:github_projects, :sub_issues, :label) || "aidp-auto"
end

# Check if auto-create on planning
def github_projects_auto_create?
  config.dig(:github_projects, :auto_create_on_planning) == true
end

# Get custom field definitions
def github_projects_custom_fields
  config.dig(:github_projects, :custom_fields) || {}
end

# Check if PR workflow enabled
def github_projects_pr_workflow_enabled?
  config.dig(:github_projects, :pr_workflow, :enabled) == true
end

# Check if auto-merge enabled
def github_projects_auto_merge?
  config.dig(:github_projects, :pr_workflow, :auto_merge_sub_prs) == true
end
```

---

## Summary

This implementation guide provides:

1. **Architectural Foundation**: Hexagonal architecture with clear layers
2. **Design Patterns**: Adapter, Facade, Service Object, State Machine, Repository
3. **Contracts**: Preconditions, postconditions, invariants, and idempotency guarantees
4. **Component Design**: Detailed implementations for GitHubProjectsClient, SubIssueManager, HierarchicalPRWorkflow
5. **GraphQL Integration**: Projects v2 API operations with gh CLI execution
6. **Testing Strategy**: Comprehensive unit and integration test specifications
7. **Error Handling**: Fail-fast for bugs, graceful degradation for external failures
8. **Configuration Schema**: Extended YAML with feature flags and customization

The implementation follows AIDP's engineering principles:

- **SOLID Principles**: Single responsibility, composition, dependency inversion
- **Domain-Driven Design**: Clear domain models, value objects, and services
- **Composition First**: Favor composition over inheritance throughout
- **Design by Contract**: Explicit preconditions, postconditions, and invariants
- **Instrumentation**: Extensive logging with `Aidp.log_debug/info/warn/error`
- **Testability**: Dependency injection, clear interfaces, comprehensive specs
- **Idempotency**: All GitHub operations support safe retries
- **Zero Framework Cognition**: Use AI for semantic decisions (persona mapping)

This guide enables implementation with confidence, clarity, and adherence to AIDP's standards.
