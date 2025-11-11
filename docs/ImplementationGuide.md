# Implementation Guide: User Tagging and PR Assignment in Watch Mode

## Overview

This guide provides architectural patterns, design decisions, and implementation strategies for adding GitHub user tagging and PR assignment features to AIDP's watch mode. The implementation follows SOLID principles, Domain-Driven Design (DDD), and hexagonal architecture patterns.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Domain Model](#domain-model)
3. [Design Patterns](#design-patterns)
4. [Implementation Contract](#implementation-contract)
5. [Component Design](#component-design)
6. [Testing Strategy](#testing-strategy)
7. [Pattern-to-Use-Case Matrix](#pattern-to-use-case-matrix)
8. [Error Handling Strategy](#error-handling-strategy)

---

## Architecture Overview

### Hexagonal Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ PlanProcessor    │           │ BuildProcessor   │        │
│  │ (Orchestration)  │           │ (Orchestration)  │        │
│  └──────────────────┘           └──────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                            │
│  ┌────────────────────────────────────────────┐             │
│  │  LabelEventService (NEW)                   │             │
│  │  - Fetches label events from GitHub        │             │
│  │  - Extracts actor information              │             │
│  │  - Domain logic for "most recent actor"    │             │
│  └────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Infrastructure Layer                       │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ RepositoryClient │           │ GraphQL Adapter  │        │
│  │ (Port/Adapter)   │◄──────────│    (NEW)         │        │
│  └──────────────────┘           └──────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **Separation of Concerns**: GraphQL integration is encapsulated in RepositoryClient, maintaining clean boundaries
2. **Dependency Injection**: All external dependencies (GitHub API, state) are injected, enabling testing
3. **Single Responsibility**: Each class has one reason to change
4. **Composition Over Inheritance**: Use service objects rather than inheritance hierarchies

---

## Domain Model

### Core Entities

#### LabelEvent (Value Object)
```ruby
# Represents a single label addition event
{
  label_name: String,      # "aidp-plan", "aidp-build", etc.
  actor: String,           # GitHub username who added the label
  created_at: Time,        # When the label was added
  event_type: String       # "labeled", "unlabeled"
}
```

#### Actor (Value Object)
```ruby
# Represents the GitHub user who performed an action
{
  login: String,           # GitHub username
  type: String             # "User", "Bot", etc.
}
```

### Domain Services

#### LabelActorResolver
**Responsibility**: Determine which user to tag/assign based on label events

**Design Pattern**: Strategy Pattern + Service Object

**Contract**:
```ruby
class LabelActorResolver
  # @param label_events [Array<Hash>] Array of label events
  # @param label_names [Array<String>] Labels to consider (e.g., ["aidp-plan", "aidp-build"])
  # @return [String, nil] The username to tag/assign, or nil if none found
  def resolve_actor(label_events:, label_names:)
    # Preconditions:
    # - label_events must be an array
    # - label_names must be an array of strings

    # Postconditions:
    # - Returns a string username or nil
    # - Returns the most recent actor who added any of the specified labels
  end
end
```

**Implementation Strategy**:
1. Filter events to only "labeled" type
2. Filter to only the specified label names
3. Sort by created_at descending
4. Return the first actor found
5. Handle edge cases (no events, bot users, etc.)

---

## Design Patterns

### 1. Repository Pattern (Existing)

**Purpose**: Abstract data access to GitHub API

**Application**: `RepositoryClient` acts as a repository for GitHub resources

**Benefits**:
- Testable without hitting real GitHub API
- Centralized API interaction logic
- Easy to swap between gh CLI and REST API

### 2. Service Object Pattern (NEW)

**Purpose**: Encapsulate domain logic for label event processing

**Application**: `LabelActorResolver` service

**Benefits**:
- Single Responsibility Principle
- Reusable across PlanProcessor and BuildProcessor
- Easily testable in isolation

### 3. Adapter Pattern (NEW)

**Purpose**: Adapt GitHub GraphQL API responses to domain objects

**Application**: GraphQL query execution and response parsing in `RepositoryClient`

**Benefits**:
- Isolates GraphQL-specific code
- Domain layer doesn't know about GraphQL structure
- Easy to change query structure without affecting callers

### 4. Template Method Pattern

**Purpose**: Define skeleton of comment generation with customization points

**Application**: Comment building in PlanProcessor and BuildProcessor

**Current Structure**:
```ruby
# Template in processors
def build_comment(issue:, plan:, actor: nil)
  parts = []
  parts << comment_header(actor)  # Customization point
  parts << common_sections(issue, plan)
  parts << next_steps(plan, actor)  # Customization point
  parts.join("\n")
end
```

### 5. Null Object Pattern

**Purpose**: Handle missing actor gracefully

**Application**: When no label actor is found

**Implementation**:
```ruby
actor = resolve_label_actor(issue_number) || AnonymousActor.new
comment = build_comment_with_actor(actor)

class AnonymousActor
  def mention; "" end
  def username; nil end
  def present?; false end
end
```

### 6. Facade Pattern (Existing)

**Purpose**: Simplify complex GitHub API interactions

**Application**: `RepositoryClient` provides simple interface to complex gh CLI and GraphQL operations

---

## Implementation Contract

### Design by Contract Principles

All public methods must specify:
1. **Preconditions**: What must be true before the method executes
2. **Postconditions**: What will be true after the method executes
3. **Invariants**: What remains true throughout the object's lifetime

### Example Contracts

#### RepositoryClient#fetch_label_events

```ruby
# Fetches label events for a given issue
#
# @param issue_number [Integer] The issue number
# @return [Array<Hash>] Array of label events, sorted by created_at descending
#
# Preconditions:
#   - issue_number must be a positive integer
#   - GitHub CLI must be available (gh_available? == true)
#   - Repository must exist and be accessible
#
# Postconditions:
#   - Returns an array (may be empty if no events)
#   - Each event has keys: :label_name, :actor, :created_at, :event_type
#   - Events are sorted newest first
#   - Raises error if GitHub API fails (fail-fast)
#
# Invariants:
#   - owner and repo remain unchanged
#   - gh_available? state remains unchanged
def fetch_label_events(issue_number)
  # Implementation
end
```

#### PlanProcessor#process (Updated)

```ruby
# Generates and posts a plan for the given issue
#
# @param issue [Hash] The issue data
# @return [void]
#
# Preconditions:
#   - issue must have :number, :title keys
#   - plan not already processed for this issue number
#
# Postconditions:
#   - Plan comment posted to GitHub
#   - Plan data recorded in state store
#   - Labels updated (plan label removed, status label added)
#   - If label actor found, actor is @mentioned in comment
#
# Side Effects:
#   - GitHub API calls (comment, labels)
#   - State store writes
#   - Logging via Aidp.log_*
def process(issue)
  # Implementation
end
```

---

## Component Design

### 1. RepositoryClient Enhancement

#### New Method: `fetch_label_events`

**Signature**:
```ruby
def fetch_label_events(issue_number)
```

**GraphQL Query**:
```graphql
query($owner: String!, $repo: String!, $issueNumber: Int!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $issueNumber) {
      timelineItems(itemTypes: [LABELED_EVENT, UNLABELED_EVENT], last: 50) {
        nodes {
          ... on LabeledEvent {
            label {
              name
            }
            actor {
              login
            }
            createdAt
          }
          ... on UnlabeledEvent {
            label {
              name
            }
            actor {
              login
            }
            createdAt
          }
        }
      }
    }
  }
}
```

**Implementation Strategy**:
```ruby
def fetch_label_events(issue_number)
  raise "GraphQL not available without gh CLI" unless gh_available?

  query = build_label_events_query
  variables = {
    owner: @owner,
    repo: @repo,
    issueNumber: issue_number
  }

  stdout, stderr, status = Open3.capture3(
    "gh", "api", "graphql",
    "-f", "query=#{query}",
    "-F", "owner=#{@owner}",
    "-F", "repo=#{@repo}",
    "-F", "issueNumber=#{issue_number}"
  )

  raise "GraphQL query failed: #{stderr}" unless status.success?

  parse_label_events_response(JSON.parse(stdout))
end

private

def build_label_events_query
  # Return the GraphQL query string
end

def parse_label_events_response(response)
  nodes = response.dig("data", "repository", "issue", "timelineItems", "nodes") || []

  nodes.map do |node|
    {
      label_name: node.dig("label", "name"),
      actor: node.dig("actor", "login"),
      created_at: Time.parse(node["createdAt"]),
      event_type: node.key?("__typename") ? node["__typename"].downcase.gsub("event", "") : "labeled"
    }
  end.compact.sort_by { |event| event[:created_at] }.reverse
end
```

#### Updated Method: `create_pull_request`

**Current Signature**:
```ruby
def create_pull_request(title:, body:, head:, base:, issue_number:, draft: false, assignee: nil)
```

**Enhancement**: Already supports `assignee` parameter - just needs to be used

**Implementation Note**: The assignee parameter is already threaded through to `create_pull_request_via_gh`:
```ruby
cmd += ["--assignee", assignee] if assignee
```

### 2. PlanProcessor Enhancement

#### Updated Method: `process`

**Changes**:
1. Fetch label actor after generating plan
2. Pass actor to comment builder
3. Include actor mention in comment

**Implementation**:
```ruby
def process(issue)
  number = issue[:number]
  if @state_store.plan_processed?(number)
    display_message("ℹ️  Plan for issue ##{number} already posted. Skipping.", type: :muted)
    return
  end

  display_message("🧠 Generating plan for issue ##{number} (#{issue[:title]})", type: :info)
  plan_data = @plan_generator.generate(issue)

  # NEW: Fetch label actor
  label_actor = fetch_label_actor(number)

  comment_body = build_comment(issue: issue, plan: plan_data, actor: label_actor)
  @repository_client.post_comment(number, comment_body)

  display_message("💬 Posted plan comment for issue ##{number}", type: :success)
  @state_store.record_plan(number, plan_data.merge(comment_body: comment_body, comment_hint: COMMENT_HEADER))

  update_labels_after_plan(number, plan_data)
end

private

def fetch_label_actor(issue_number)
  events = @repository_client.fetch_label_events(issue_number)
  resolve_actor_from_events(events, [@plan_label])
rescue => e
  Aidp.log_warn("plan_processor", "Failed to fetch label actor", issue: issue_number, error: e.message)
  nil
end

def resolve_actor_from_events(events, target_labels)
  labeled_events = events.select { |e| e[:event_type] == "labeled" }
  relevant_events = labeled_events.select { |e| target_labels.include?(e[:label_name]) }
  relevant_events.first&.dig(:actor)
end
```

#### Updated Method: `build_comment`

**Changes**:
1. Accept optional `actor` parameter
2. Add mention in header or next steps

**Implementation Strategy 1** (Header Mention):
```ruby
def build_comment(issue:, plan:, actor: nil)
  summary = plan[:summary].to_s.strip
  tasks = Array(plan[:tasks])
  questions = Array(plan[:questions])
  has_questions = questions.any? && !questions.all? { |q| q.to_s.strip.empty? }

  parts = []
  parts << COMMENT_HEADER
  parts << actor_mention_line(actor) if actor  # NEW
  parts << ""
  parts << "**Issue**: [##{issue[:number]}](#{issue[:url]})"
  # ... rest of comment
end

def actor_mention_line(actor)
  "cc @#{actor}"
end
```

**Implementation Strategy 2** (Next Steps Mention - RECOMMENDED):
```ruby
def build_comment(issue:, plan:, actor: nil)
  # ... build comment parts ...

  # Add instructions based on whether there are questions
  parts << if has_questions
    next_steps_with_questions(actor)
  else
    next_steps_ready(actor)
  end

  parts.join("\n")
end

def next_steps_with_questions(actor)
  mention = actor ? " @#{actor}" : ""
  "**Next Steps**:#{mention} Please reply with answers to the questions above. Once resolved, remove the `#{@needs_input_label}` label and add the `#{@build_label}` label to begin implementation."
end

def next_steps_ready(actor)
  mention = actor ? " @#{actor}" : ""
  "**Next Steps**:#{mention} This plan is ready for implementation. Add the `#{@build_label}` label to begin."
end
```

### 3. BuildProcessor Enhancement

#### Updated Method: `handle_clarification_request`

**Changes**:
1. Fetch label actor
2. Include mention in clarification comment

**Implementation**:
```ruby
def handle_clarification_request(issue:, slug:, result:)
  questions = result[:clarification_questions] || []
  workstream_note = @use_workstreams ? " The workstream `#{slug}` has been preserved." : " The branch has been preserved."

  # NEW: Fetch label actor
  label_actor = fetch_label_actor(issue[:number])

  # Build comment with questions
  comment_parts = []
  comment_parts << build_clarification_header(label_actor)  # NEW
  comment_parts << ""
  comment_parts << "The AI agent needs additional information to proceed with implementation:"
  comment_parts << ""
  questions.each_with_index do |question, index|
    comment_parts << "#{index + 1}. #{question}"
  end
  comment_parts << ""
  comment_parts << build_next_steps_line(label_actor)  # NEW
  comment_parts << ""
  comment_parts << workstream_note.to_s

  comment = comment_parts.join("\n")
  @repository_client.post_comment(issue[:number], comment)

  # ... rest of method
end

private

def build_clarification_header(actor)
  mention = actor ? " @#{actor}" : ""
  "❓ Implementation needs clarification for ##{issue[:number]}.#{mention}"
end

def build_next_steps_line(actor)
  mention = actor ? " @#{actor}" : ""
  "**Next Steps**:#{mention} Please reply with answers to the questions above. Once resolved, remove the `#{@needs_input_label}` label and add the `#{@build_label}` label to resume implementation."
end
```

#### Updated Method: `handle_success`

**Changes**:
1. Fetch label actor for most recent build label
2. Pass to PR creation
3. Include mention in success comment

**Implementation**:
```ruby
def handle_success(issue:, slug:, branch_name:, base_branch:, plan_data:, working_dir:)
  changes_committed = stage_and_commit(issue, working_dir: working_dir)

  vcs_config = config.dig(:work_loop, :version_control) || {}
  auto_create_pr = vcs_config.fetch(:auto_create_pr, true)

  # NEW: Fetch label actor for assignment
  label_actor = fetch_label_actor(issue[:number])

  pr_url = if !changes_committed
    # ... existing no-commit handling
  elsif auto_create_pr
    Aidp.log_info(
      "build_processor",
      "creating_pull_request",
      issue: issue[:number],
      branch: branch_name,
      base_branch: base_branch,
      working_dir: working_dir,
      assignee: label_actor  # NEW
    )
    create_pull_request(
      issue: issue,
      branch_name: branch_name,
      base_branch: base_branch,
      working_dir: working_dir,
      assignee: label_actor  # NEW
    )
  else
    # ... existing disabled PR handling
  end

  workstream_note = @use_workstreams ? "\n- Workstream: `#{slug}`" : ""
  pr_line = pr_url ? "\n- Pull Request: #{pr_url}" : ""

  # NEW: Add mention
  mention = label_actor ? " @#{label_actor}" : ""

  comment = <<~COMMENT
    ✅ Implementation complete for ##{issue[:number]}.#{mention}
    - Branch: `#{branch_name}`#{workstream_note}#{pr_line}

    Summary:
    #{plan_value(plan_data, "summary")}
  COMMENT

  @repository_client.post_comment(issue[:number], comment)

  # ... rest of method
end
```

#### Updated Method: `create_pull_request`

**Changes**:
1. Accept assignee parameter
2. Pass to repository_client
3. Update PR body with "Fixes #" syntax

**Implementation**:
```ruby
def create_pull_request(issue:, branch_name:, base_branch:, working_dir: @project_dir, assignee: nil)
  title = "aidp: Resolve ##{issue[:number]} - #{issue[:title]}"
  test_summary = gather_test_summary(working_dir: working_dir)

  # NEW: Prepend Fixes syntax for auto-close
  body = <<~BODY
    Fixes ##{issue[:number]}

    ## Summary
    - Automated resolution for ##{issue[:number]}

    ## Testing
    #{test_summary}
  BODY

  vcs_config = config.dig(:work_loop, :version_control) || {}
  pr_strategy = vcs_config[:pr_strategy] || "draft"
  draft = (pr_strategy == "draft")

  # NEW: Use provided assignee instead of issue author
  # Fall back to issue author if no label actor found
  pr_assignee = assignee || issue[:author]

  output = @repository_client.create_pull_request(
    title: title,
    body: body,
    head: branch_name,
    base: base_branch,
    issue_number: issue[:number],
    draft: draft,
    assignee: pr_assignee
  )

  pr_url = extract_pr_url(output)
  Aidp.log_info(
    "build_processor",
    "pull_request_created",
    issue: issue[:number],
    branch: branch_name,
    base_branch: base_branch,
    pr_url: pr_url,
    assignee: pr_assignee
  )
  pr_url
end
```

#### New Private Method: `fetch_label_actor`

**Implementation**:
```ruby
private

def fetch_label_actor(issue_number)
  events = @repository_client.fetch_label_events(issue_number)
  resolve_actor_from_events(events, [@build_label])
rescue => e
  Aidp.log_warn("build_processor", "Failed to fetch label actor", issue: issue_number, error: e.message)
  nil
end

def resolve_actor_from_events(events, target_labels)
  labeled_events = events.select { |e| e[:event_type] == "labeled" }
  relevant_events = labeled_events.select { |e| target_labels.include?(e[:label_name]) }
  relevant_events.first&.dig(:actor)
end
```

---

## Testing Strategy

### Unit Tests

#### RepositoryClient Specs

**File**: `spec/aidp/watch/repository_client_spec.rb`

**Test Cases**:
```ruby
describe "#fetch_label_events" do
  context "when GitHub CLI is available" do
    it "executes GraphQL query via gh api" do
      # Mock Open3.capture3 to return sample GraphQL response
      # Assert correct query structure and variables
    end

    it "parses label events from GraphQL response" do
      # Provide sample GraphQL JSON response
      # Assert returned array has correct structure
    end

    it "sorts events by created_at descending" do
      # Provide events in random order
      # Assert returned events are newest-first
    end

    it "handles empty event list" do
      # Return empty nodes array
      # Assert returns []
    end

    it "raises error when gh cli fails" do
      # Mock failed command execution
      # Assert raises with appropriate message
    end
  end

  context "when GitHub CLI is not available" do
    it "raises error for GraphQL operations" do
      # gh_available? returns false
      # Assert raises NotImplementedError or similar
    end
  end
end

describe "#create_pull_request" do
  it "passes assignee to gh pr create" do
    # Mock Open3.capture3
    # Call with assignee: "someuser"
    # Assert command includes ["--assignee", "someuser"]
  end

  it "omits assignee flag when nil" do
    # Call with assignee: nil
    # Assert command does not include "--assignee"
  end
end
```

#### PlanProcessor Specs

**File**: `spec/aidp/watch/plan_processor_spec.rb`

**Test Cases**:
```ruby
describe "#process" do
  context "when label actor is found" do
    before do
      allow(repository_client).to receive(:fetch_label_events).and_return([
        {label_name: "aidp-plan", actor: "alice", created_at: Time.now, event_type: "labeled"}
      ])
    end

    it "includes actor mention in comment" do
      expect(repository_client).to receive(:post_comment) do |number, body|
        expect(body).to include("@alice")
      end

      processor.process(issue)
    end

    it "mentions actor in next steps section" do
      expect(repository_client).to receive(:post_comment) do |number, body|
        expect(body).to match(/Next Steps.*@alice/m)
      end

      processor.process(issue)
    end
  end

  context "when label actor is not found" do
    before do
      allow(repository_client).to receive(:fetch_label_events).and_return([])
    end

    it "posts comment without mention" do
      expect(repository_client).to receive(:post_comment) do |number, body|
        expect(body).not_to include("@")
      end

      processor.process(issue)
    end

    it "handles fetch errors gracefully" do
      allow(repository_client).to receive(:fetch_label_events).and_raise("API error")

      expect {
        processor.process(issue)
      }.not_to raise_error

      # Should still post comment without mention
      expect(repository_client).to have_received(:post_comment)
    end
  end
end
```

#### BuildProcessor Specs

**File**: `spec/aidp/watch/build_processor_spec.rb`

**Test Cases**:
```ruby
describe "#handle_clarification_request" do
  let(:result) { {status: "needs_clarification", clarification_questions: ["Q1", "Q2"]} }

  context "when label actor is found" do
    before do
      allow(repository_client).to receive(:fetch_label_events).and_return([
        {label_name: "aidp-build", actor: "bob", created_at: Time.now, event_type: "labeled"}
      ])
    end

    it "mentions actor in clarification comment" do
      expect(repository_client).to receive(:post_comment) do |number, body|
        expect(body).to include("@bob")
      end

      processor.send(:handle_clarification_request, issue: issue, slug: "test-slug", result: result)
    end
  end

  context "when label actor is not found" do
    before do
      allow(repository_client).to receive(:fetch_label_events).and_return([])
    end

    it "posts comment without mention" do
      expect(repository_client).to receive(:post_comment) do |number, body|
        expect(body).not_to include("@")
      end

      processor.send(:handle_clarification_request, issue: issue, slug: "test-slug", result: result)
    end
  end
end

describe "#handle_success" do
  context "when label actor is found" do
    before do
      allow(repository_client).to receive(:fetch_label_events).and_return([
        {label_name: "aidp-build", actor: "charlie", created_at: Time.now, event_type: "labeled"}
      ])
    end

    it "mentions actor in success comment" do
      # Mock git operations and harness runner
      # Assert comment includes @charlie
    end

    it "assigns PR to label actor" do
      # Mock git operations
      expect(repository_client).to receive(:create_pull_request) do |args|
        expect(args[:assignee]).to eq("charlie")
      end.and_return("https://github.com/owner/repo/pull/1")

      # Trigger handle_success
    end
  end

  context "when label actor is not found" do
    before do
      allow(repository_client).to receive(:fetch_label_events).and_return([])
    end

    it "falls back to issue author for PR assignment" do
      expect(repository_client).to receive(:create_pull_request) do |args|
        expect(args[:assignee]).to eq(issue[:author])
      end.and_return("https://github.com/owner/repo/pull/1")

      # Trigger handle_success
    end
  end
end
```

**File**: `spec/aidp/watch/build_processor_vcs_spec.rb`

**Test Cases**:
```ruby
describe "PR body generation" do
  it "includes Fixes syntax at the beginning" do
    allow(repository_client).to receive(:create_pull_request) do |args|
      expect(args[:body]).to start_with("Fixes ##{issue[:number]}")
    end.and_return("https://github.com/owner/repo/pull/1")

    # Trigger PR creation
  end

  it "maintains existing PR body structure" do
    allow(repository_client).to receive(:create_pull_request) do |args|
      body = args[:body]
      expect(body).to include("## Summary")
      expect(body).to include("## Testing")
      expect(body).to include("Automated resolution")
    end.and_return("https://github.com/owner/repo/pull/1")

    # Trigger PR creation
  end
end
```

### Integration Tests

**Approach**: Use tmux-based testing for end-to-end verification

**Test Scenario**:
1. Set up test repository with labeled issue
2. Run watch mode
3. Verify comment posted with correct mention
4. Verify PR created with correct assignee
5. Verify issue auto-closed when PR merges

---

## Pattern-to-Use-Case Matrix

| Use Case | Primary Pattern | Supporting Patterns | Rationale |
|----------|----------------|---------------------|-----------|
| Fetch label events from GitHub | Adapter | Repository, Facade | Isolate GraphQL complexity from domain |
| Determine which user to tag | Service Object | Strategy | Single responsibility, reusable logic |
| Handle missing actor gracefully | Null Object | - | Avoid nil checks throughout code |
| Build comments with mentions | Template Method | Composition | Reuse structure, customize details |
| Parse GraphQL responses | Adapter | Value Object | Transform external format to domain model |
| Inject GitHub client for testing | Dependency Injection | Repository | Enable mocking, maintain testability |
| Assign PR to user | Repository | Command | Encapsulate external mutation |
| Log actor resolution failures | Error Handling | - | Observability without breaking flow |

---

## Error Handling Strategy

### Principle: Fail Fast for Programmer Errors, Graceful Degradation for External Failures

#### Fail Fast (Raise Errors)
- Invalid method arguments (precondition violations)
- GitHub CLI not available when required
- Malformed GraphQL responses that indicate bugs
- Contract violations

#### Graceful Degradation (Log and Continue)
- Label events not found (return empty array)
- Actor resolution returns nil (proceed without mention)
- GraphQL API temporary failures (log warning, return nil)
- Rate limiting (log error, retry with backoff)

### Error Handling Implementation

```ruby
def fetch_label_actor(issue_number)
  # Validate preconditions - fail fast
  raise ArgumentError, "issue_number must be positive" unless issue_number.to_i > 0

  begin
    events = @repository_client.fetch_label_events(issue_number)
    resolve_actor_from_events(events, [@plan_label])
  rescue GitHub::RateLimitError => e
    # External failure - graceful degradation
    Aidp.log_error("plan_processor", "Rate limited fetching label events",
                   issue: issue_number,
                   error: e.message,
                   retry_after: e.retry_after)
    nil
  rescue StandardError => e
    # Unexpected error - log but don't break workflow
    Aidp.log_warn("plan_processor", "Failed to fetch label actor",
                  issue: issue_number,
                  error: e.message,
                  error_class: e.class.name)
    nil
  end
end
```

### Logging Strategy

**Use `Aidp.log_*` extensively**:

```ruby
# Method entry
Aidp.log_debug("plan_processor", "fetching_label_actor", issue: issue_number)

# Success with data
Aidp.log_info("plan_processor", "resolved_label_actor",
              issue: issue_number,
              actor: actor,
              event_count: events.length)

# Graceful degradation
Aidp.log_warn("plan_processor", "no_label_actor_found",
              issue: issue_number,
              reason: "no_matching_events")

# Error conditions
Aidp.log_error("plan_processor", "graphql_query_failed",
               issue: issue_number,
               error: e.message,
               query: query_name)
```

---

## Implementation Checklist

### Phase 1: Infrastructure (RepositoryClient)
- [ ] Add `fetch_label_events` method with GraphQL query
- [ ] Implement GraphQL query builder
- [ ] Implement GraphQL response parser
- [ ] Add error handling for GraphQL failures
- [ ] Verify `create_pull_request` assignee parameter works
- [ ] Add comprehensive unit tests for GraphQL integration
- [ ] Add logging for all GraphQL operations

### Phase 2: Domain Logic (Actor Resolution)
- [ ] Implement `resolve_actor_from_events` helper
- [ ] Handle edge cases (no events, bot actors, multiple labels)
- [ ] Add unit tests for actor resolution logic
- [ ] Add logging for actor resolution decisions

### Phase 3: PlanProcessor Integration
- [ ] Add `fetch_label_actor` method
- [ ] Update `process` to fetch actor
- [ ] Update `build_comment` to accept actor parameter
- [ ] Modify comment templates to include mentions
- [ ] Add unit tests for comment generation with/without actor
- [ ] Add integration tests for full flow

### Phase 4: BuildProcessor Integration
- [ ] Add `fetch_label_actor` method (reuse logic from PlanProcessor)
- [ ] Update `handle_clarification_request` with actor mention
- [ ] Update `handle_success` with actor mention
- [ ] Update `create_pull_request` to use label actor for assignment
- [ ] Update PR body template with "Fixes #" syntax
- [ ] Add unit tests for all comment variations
- [ ] Add unit tests for PR assignment logic
- [ ] Add integration tests for PR creation and issue closure

### Phase 5: Testing and Validation
- [ ] Run full test suite and ensure all tests pass
- [ ] Test with real GitHub repository (manual testing)
- [ ] Verify GraphQL query performance
- [ ] Verify issue auto-closure when PR merges
- [ ] Add performance logging for GraphQL queries
- [ ] Document any limitations or known issues

---

## Advanced Considerations

### Performance Optimization

**GraphQL Query Caching**: Consider caching label events within a single watch loop iteration:

```ruby
class BuildProcessor
  def initialize(...)
    @label_event_cache = {}
  end

  private

  def fetch_label_actor(issue_number)
    events = @label_event_cache[issue_number] ||= @repository_client.fetch_label_events(issue_number)
    resolve_actor_from_events(events, [@build_label])
  rescue => e
    Aidp.log_warn("build_processor", "Failed to fetch label actor", issue: issue_number, error: e.message)
    nil
  end
end
```

### Rate Limiting

**GitHub GraphQL API Limits**:
- 5,000 points per hour
- Each query costs points based on complexity
- Monitor `X-RateLimit-*` headers

**Mitigation**:
```ruby
def fetch_label_events(issue_number)
  response = execute_graphql_query(query, variables)

  # Check rate limit headers
  remaining = response.headers["X-RateLimit-Remaining"]
  if remaining && remaining.to_i < 100
    Aidp.log_warn("repository_client", "low_rate_limit", remaining: remaining)
  end

  parse_label_events_response(response.body)
end
```

### Security Considerations

1. **Validate Actor Names**: Ensure actor logins are valid GitHub usernames
2. **Sanitize Mentions**: Prevent injection attacks via actor names
3. **Permission Checks**: Verify bot has necessary permissions for GraphQL queries

```ruby
def sanitize_actor(actor)
  # GitHub usernames: alphanumeric + hyphens, max 39 chars
  return nil unless actor =~ /\A[a-zA-Z0-9-]{1,39}\z/
  actor
end

def actor_mention_line(actor)
  safe_actor = sanitize_actor(actor)
  return "" unless safe_actor
  "cc @#{safe_actor}"
end
```

### Observability

**Metrics to Track**:
- GraphQL query latency
- Actor resolution success rate
- PR assignment success rate
- Issue auto-closure rate

**Implementation**:
```ruby
def fetch_label_events(issue_number)
  start_time = Time.now

  result = execute_graphql_query(...)

  duration_ms = ((Time.now - start_time) * 1000).round(2)
  Aidp.log_info("repository_client", "graphql_query_completed",
                query: "label_events",
                duration_ms: duration_ms,
                event_count: result.length)

  result
end
```

---

## Appendix: GraphQL Query Reference

### Full Query with Comments

```graphql
query FetchLabelEvents($owner: String!, $repo: String!, $issueNumber: Int!) {
  # Rate limit info for monitoring
  rateLimit {
    cost
    remaining
    resetAt
  }

  repository(owner: $owner, name: $repo) {
    issue(number: $issueNumber) {
      # Fetch last 50 label events (adjust if needed)
      timelineItems(itemTypes: [LABELED_EVENT, UNLABELED_EVENT], last: 50) {
        nodes {
          # Fragment for LABELED_EVENT
          ... on LabeledEvent {
            __typename
            label {
              name
            }
            actor {
              login
            }
            createdAt
          }

          # Fragment for UNLABELED_EVENT
          ... on UnlabeledEvent {
            __typename
            label {
              name
            }
            actor {
              login
            }
            createdAt
          }
        }
      }
    }
  }
}
```

### Sample Response

```json
{
  "data": {
    "rateLimit": {
      "cost": 1,
      "remaining": 4999,
      "resetAt": "2025-11-11T12:00:00Z"
    },
    "repository": {
      "issue": {
        "timelineItems": {
          "nodes": [
            {
              "__typename": "LabeledEvent",
              "label": {
                "name": "aidp-plan"
              },
              "actor": {
                "login": "alice"
              },
              "createdAt": "2025-11-11T10:30:00Z"
            },
            {
              "__typename": "LabeledEvent",
              "label": {
                "name": "aidp-build"
              },
              "actor": {
                "login": "bob"
              },
              "createdAt": "2025-11-11T11:00:00Z"
            }
          ]
        }
      }
    }
  }
}
```

---

## Summary

This implementation guide provides:

1. **Architectural Foundation**: Hexagonal architecture with clear separation of concerns
2. **Design Patterns**: Repository, Adapter, Service Object, Template Method, Null Object
3. **Contracts**: Preconditions, postconditions, and invariants for all public methods
4. **Component Design**: Detailed implementation strategies for each affected class
5. **Testing Strategy**: Comprehensive unit and integration test approach
6. **Error Handling**: Fail-fast for bugs, graceful degradation for external failures
7. **Observability**: Extensive logging and monitoring recommendations

The implementation follows SOLID principles:
- **S**: Single Responsibility - Each class/method has one reason to change
- **O**: Open/Closed - Extension points through dependency injection
- **L**: Liskov Substitution - Null Object pattern for missing actors
- **I**: Interface Segregation - Small, focused public APIs
- **D**: Dependency Inversion - Depend on abstractions (RepositoryClient interface)

Domain-Driven Design principles:
- **Ubiquitous Language**: LabelEvent, Actor, resolve_actor, mention
- **Value Objects**: LabelEvent, Actor (immutable data structures)
- **Domain Services**: LabelActorResolver (stateless domain logic)
- **Repositories**: RepositoryClient (infrastructure abstraction)

This guide should enable any domain agent to implement the feature with confidence, clarity, and adherence to AIDP's engineering standards.
