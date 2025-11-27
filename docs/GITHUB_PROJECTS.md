# GitHub Projects Integration

AIDP supports GitHub Projects V2 integration for managing large, complex development projects. This enables automatic breakdown of issues into sub-issues, hierarchical PR strategies, and project board synchronization.

## Overview

The GitHub Projects integration provides:

- **Hierarchical Issue Planning**: AI-powered breakdown of large issues into manageable sub-issues
- **Project Board Synchronization**: Automatic linking and status updates
- **Custom Field Management**: Skills, personas, priorities, and dependencies
- **Hierarchical PR Strategy**: Parent PRs with targeted sub-issue PRs
- **Auto-Merge Support**: Automatic merging of sub-issue PRs upon CI success

## Configuration

Add the following to your `.aidp/aidp.yml`:

```yaml
watch:
  enabled: true
  polling_interval: 30

  labels:
    plan_trigger: "aidp-plan"
    build_trigger: "aidp-build"
    auto_trigger: "aidp-auto"
    parent_pr: "aidp-parent-pr"
    sub_pr: "aidp-sub-pr"

  projects:
    enabled: true
    default_project_id: "PVT_kwDOABCDEFGHIJKLMNOP"  # Your project ID

    field_mappings:
      status: "Status"
      priority: "Priority"
      skills: "Skills"
      personas: "Personas"
      blocking: "Blocking"

    auto_create_fields: true
    sync_interval: 60

    default_status_values:
      - "Backlog"
      - "Todo"
      - "In Progress"
      - "In Review"
      - "Done"

    default_priority_values:
      - "Low"
      - "Medium"
      - "High"
      - "Critical"

  auto_merge:
    enabled: true
    sub_issue_prs_only: true
    require_ci_success: true
    require_reviews: 0
    merge_method: "squash"
    delete_branch: true
```

### Finding Your Project ID

To get your GitHub Project ID, use the GitHub CLI:

```bash
# List organization projects
gh api graphql -f query='
  query {
    organization(login: "your-org") {
      projectsV2(first: 10) {
        nodes {
          id
          title
          number
        }
      }
    }
  }
'

# List user projects
gh api graphql -f query='
  query {
    viewer {
      projectsV2(first: 10) {
        nodes {
          id
          title
          number
        }
      }
    }
  }
'
```

The `id` field (starting with `PVT_`) is your `default_project_id`.

## Hierarchical Planning Workflow

### 1. Create a Large Issue

Create a GitHub issue describing a large feature or project. Example:

```markdown
Title: Implement Real-Time Collaboration Features

Body:
We need to add real-time collaboration features to our application:
- Live cursor tracking
- Real-time document editing
- Presence indicators
- Conflict resolution
- WebSocket infrastructure
```

### 2. Trigger Hierarchical Planning

Add the `aidp-plan` label to the issue. AIDP will:

1. Analyze the issue using AI
2. Determine if it should be broken into sub-issues
3. Generate a hierarchical plan with:
   - Sub-issue titles and descriptions
   - Required skills for each sub-issue
   - Suggested personas (roles)
   - Dependencies between sub-issues

### 3. Review the Plan

AIDP posts the plan as a comment:

```markdown
## 🤖 AIDP Plan Proposal

### Plan Summary
This project will implement real-time collaboration features...

### Sub-Issues to Create
1. **WebSocket Infrastructure Setup**
   - Skills: Backend, WebSockets, Redis
   - Personas: Backend Engineer, DevOps Engineer

2. **Live Cursor Tracking**
   - Skills: Frontend, WebSockets, React
   - Personas: Frontend Developer
   - Depends on: WebSocket Infrastructure Setup

3. **Real-Time Document Editing**
   - Skills: Frontend, CRDT, React
   - Personas: Frontend Developer, Algorithm Specialist
   - Depends on: WebSocket Infrastructure Setup
```

### 4. Approve and Create Sub-Issues

Reply with approval (or modify the plan). AIDP will:

1. Create individual GitHub issues for each sub-task
2. Link all issues to the configured project
3. Set custom fields (skills, personas, priorities)
4. Apply the `aidp-auto` label for autonomous pickup
5. Post a summary comment with links to all sub-issues

### 5. Automatic Processing

Each sub-issue with `aidp-auto` will be:

1. Automatically picked up by watch mode
2. Planned individually
3. Implemented via work loops
4. Tested and committed
5. PR created targeting the parent's branch

## Project Board Features

### Custom Fields

AIDP can create and update custom fields in your project:

- **Status**: Tracks issue state (Backlog → In Progress → Done)
- **Priority**: Issue urgency (Low, Medium, High, Critical)
- **Skills**: Technical skills required (e.g., "React", "PostgreSQL")
- **Personas**: Roles needed (e.g., "Frontend Developer", "DBA")
- **Blocking**: Dependencies on other issues

### Automatic Synchronization

When `projects.enabled: true`, AIDP automatically:

- Links new issues to the project
- Updates status fields when work begins
- Moves cards through workflow states
- Updates blocking relationships
- Tracks parent-child issue hierarchies

### Example Project Setup

1. Create a GitHub Project (Projects V2)
2. Add custom fields:
   - **Status** (Single Select): Backlog, Todo, In Progress, In Review, Done
   - **Priority** (Single Select): Low, Medium, High, Critical
   - **Skills** (Text): Comma-separated skill tags
   - **Personas** (Text): Required roles

3. Configure field mappings in `aidp.yml` to match your field names

4. Get the project ID and add to config

## Hierarchical PR Strategy

### Parent Issue PRs

When AIDP processes a parent issue (one with sub-issues):

1. Creates a **draft PR** targeting `main`
2. Adds label `aidp-parent-pr`
3. PR description includes links to all sub-issue PRs
4. **Cannot be auto-merged** - requires manual review

### Sub-Issue PRs

When AIDP processes a sub-issue:

1. Creates a PR targeting the **parent's branch** (not `main`)
2. Adds label `aidp-sub-pr`
3. PR description includes parent issue reference
4. **Can be auto-merged** when CI passes

### Branch Strategy

```
main
 └── aidp/parent-292-collaboration-features
      ├── aidp/sub-292-293-websocket-infrastructure
      ├── aidp/sub-292-294-live-cursor-tracking
      └── aidp/sub-292-295-document-editing
```

### Merge Workflow

1. Sub-issue PRs are auto-merged into parent branch when CI passes
2. Parent PR description is updated to show merged sub-PRs
3. When all sub-PRs are merged, parent PR is ready for review
4. Manual review and merge of parent PR into `main`

## Auto-Merge Configuration

The `auto_merge` section controls automatic PR merging:

```yaml
auto_merge:
  enabled: true                    # Enable auto-merge
  sub_issue_prs_only: true        # Only auto-merge sub-issue PRs
  require_ci_success: true        # Wait for CI to pass
  require_reviews: 0              # Minimum required reviews (0 = none)
  merge_method: "squash"          # squash, merge, or rebase
  delete_branch: true             # Delete branch after merge
```

### Safety Features

- Parent PRs are **never** auto-merged
- Only PRs with `aidp-sub-pr` label can be auto-merged
- All CI checks must pass
- Configurable review requirements
- Conflict detection (PRs with conflicts are skipped)

## API Reference

### RepositoryClient Methods

#### `fetch_project(project_id)`

Fetches project details including all custom fields.

```ruby
project = repository_client.fetch_project("PVT_kwDOABCDEFGHIJKLMNOP")
# => {
#   id: "PVT_...",
#   title: "My Project",
#   number: 1,
#   url: "https://github.com/orgs/my-org/projects/1",
#   fields: [
#     {id: "PVTF_...", name: "Status", data_type: "SINGLE_SELECT", options: [...]}
#   ]
# }
```

#### `list_project_items(project_id)`

Lists all items in a project with field values.

```ruby
items = repository_client.list_project_items(project_id)
# => [
#   {
#     id: "PVTI_...",
#     type: "ISSUE",
#     content: {number: 123, title: "...", state: "OPEN", url: "..."},
#     field_values: {"Status" => "In Progress", "Priority" => "High"}
#   }
# ]
```

#### `link_issue_to_project(project_id, issue_number)`

Adds an issue to a project.

```ruby
item_id = repository_client.link_issue_to_project(project_id, 123)
# => "PVTI_kwDOABCDEFGHIJKLMNOP"
```

#### `update_project_item_field(item_id, field_id, value)`

Updates a custom field on a project item.

```ruby
# Text field
repository_client.update_project_item_field(
  item_id,
  field_id,
  {project_id: project_id, text: "Backend, API, PostgreSQL"}
)

# Single select field
repository_client.update_project_item_field(
  item_id,
  field_id,
  {project_id: project_id, option_id: "PVTO_..."}
)
```

#### `create_issue(title:, body:, labels:, assignees:)`

Creates a new GitHub issue.

```ruby
result = repository_client.create_issue(
  title: "Implement WebSocket infrastructure",
  body: "...",
  labels: ["aidp-auto", "backend"],
  assignees: ["username"]
)
# => {number: 123, url: "https://github.com/..."}
```

#### `merge_pull_request(number, merge_method:)`

Merges a pull request.

```ruby
repository_client.merge_pull_request(123, merge_method: "squash")
```

### SubIssueCreator

Creates sub-issues from hierarchical plan data.

```ruby
creator = Aidp::Watch::SubIssueCreator.new(
  repository_client: repository_client,
  state_store: state_store,
  project_id: "PVT_..."
)

sub_issues_data = [
  {
    title: "Setup WebSocket infrastructure",
    description: "Implement WebSocket server with Redis pub/sub",
    tasks: ["Setup WebSocket server", "Configure Redis", "Add authentication"],
    skills: ["Backend", "WebSockets", "Redis"],
    personas: ["Backend Engineer"],
    dependencies: []
  }
]

created_issues = creator.create_sub_issues(parent_issue, sub_issues_data)
# => [
#   {number: 124, url: "...", title: "...", skills: [...], personas: [...]}
# ]
```

### StateStore Methods

#### Project Tracking

```ruby
# Record project item ID for an issue
state_store.record_project_item_id(123, "PVTI_...")

# Get project item ID
item_id = state_store.project_item_id(123)

# Record project sync data
state_store.record_project_sync(123, {
  status_field_id: "PVTF_...",
  priority_field_id: "PVTF_..."
})

# Get project sync data
sync_data = state_store.project_sync_data(123)
```

#### Hierarchy Tracking

```ruby
# Record parent-child relationships
state_store.record_sub_issues(123, [124, 125, 126])

# Get sub-issues for a parent
sub_issue_numbers = state_store.sub_issues(123)
# => [124, 125, 126]

# Get parent for a sub-issue
parent_number = state_store.parent_issue(124)
# => 123

# Check blocking status
status = state_store.blocking_status(123)
# => {blocked: true, blockers: [124, 125, 126], blocker_count: 3}
```

## Example: Full Workflow

### 1. Configure AIDP

```yaml
# .aidp/aidp.yml
watch:
  enabled: true
  projects:
    enabled: true
    default_project_id: "PVT_kwDOABCDEFGHIJKLMNOP"
  auto_merge:
    enabled: true
```

### 2. Create and Label Issue

```bash
gh issue create \
  --title "Add multi-tenant support" \
  --body "Implement tenant isolation across database, caching, and API layers" \
  --label "aidp-plan"
```

### 3. AIDP Processes Issue

```
[Watch Mode] 🧠 Generating hierarchical plan for issue #456
[Plan Generator] ✓ Generated plan with 5 sub-issues
[Sub-Issue Creator] 🔨 Creating 5 sub-issues for #456
  ✓ Created sub-issue #457: Database schema for multi-tenancy
  ✓ Created sub-issue #458: Tenant context middleware
  ✓ Created sub-issue #459: Cache key namespacing
  ✓ Created sub-issue #460: API tenant isolation
  ✓ Created sub-issue #461: Admin tenant management UI
[Projects] 📊 Linking issues to project
  ✓ Linked parent issue #456
  ✓ Linked sub-issues #457-461
[Watch Mode] 💬 Posted sub-issues summary to parent issue
```

### 4. Automatic Implementation

Each sub-issue is automatically:
- Planned individually
- Implemented via work loops
- Tested and committed
- PR created targeting parent branch
- Auto-merged when CI passes

### 5. Final Review

When all sub-PRs are merged:
- Parent PR shows all completed work
- Manual review ensures everything integrates correctly
- Merge parent PR to main

## Troubleshooting

### Project Not Found

**Error**: `Project not found: PVT_...`

**Solution**: Verify the project ID is correct and the GitHub token has access:

```bash
gh api graphql -f query='
  query {
    node(id: "YOUR_PROJECT_ID") {
      ... on ProjectV2 {
        title
      }
    }
  }
'
```

### Field Updates Failing

**Error**: `Failed to update project item field`

**Solution**: Ensure field names in config match exactly (case-sensitive):

```bash
# List project fields
gh api graphql -f query='
  query {
    node(id: "YOUR_PROJECT_ID") {
      ... on ProjectV2 {
        fields(first: 20) {
          nodes {
            ... on ProjectV2Field {
              name
              dataType
            }
            ... on ProjectV2SingleSelectField {
              name
              options {
                id
                name
              }
            }
          }
        }
      }
    }
  }
'
```

### Sub-Issues Not Created

**Issue**: Hierarchical planning doesn't create sub-issues

**Solutions**:
1. Ensure issue is large enough (AI determines complexity)
2. Add explicit instruction in issue body: "Please break this into sub-issues"
3. Check AI provider is available and responding
4. Review logs for planning errors: `tail -f .aidp/logs/aidp.log`

### Auto-Merge Not Working

**Issue**: Sub-issue PRs not auto-merging

**Checklist**:
- [ ] `auto_merge.enabled: true` in config
- [ ] PR has `aidp-sub-pr` label
- [ ] CI checks are passing
- [ ] PR has no conflicts
- [ ] Required reviews met (if `require_reviews > 0`)
- [ ] Watch mode is running

## Best Practices

### Issue Size

- **Small issues** (< 1 day): Don't need sub-issues
- **Medium issues** (1-3 days): Optional sub-issues
- **Large issues** (> 3 days): Strongly recommend sub-issues

### Sub-Issue Organization

- Each sub-issue should be independently testable
- Minimize dependencies between sub-issues
- Clearly specify required skills
- Assign appropriate personas

### Project Board Setup

- Use consistent status names across projects
- Create standard priority levels
- Document skill tags in team wiki
- Define personas/roles clearly

### Review Strategy

- Review sub-issue PRs for code quality
- Review parent PR for integration and architecture
- Use GitHub's draft PR feature for work-in-progress
- Add CODEOWNERS for automatic review assignment

## Related Documentation

- [Watch Mode Guide](WATCH_MODE.md) - Watch mode configuration
- [Work Loops Guide](WORK_LOOPS_GUIDE.md) - Work loop execution
- [CLI User Guide](CLI_USER_GUIDE.md) - Command reference
- [Configuration Reference](CONFIGURATION.md) - Full config options

## GitHub GraphQL API Resources

- [GitHub Projects V2 API](https://docs.github.com/en/graphql/reference/objects#projectv2)
- [Project Items](https://docs.github.com/en/graphql/reference/objects#projectv2item)
- [Custom Fields](https://docs.github.com/en/graphql/reference/mutations#createprojectv2field)
