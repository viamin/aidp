# GitHub Projects Integration - Implementation Plan

**Issue**: [#292](https://github.com/viamin/aidp/issues/292) - Use GitHub projects feature to track large projects
**Implementation Branch**: `claude/implement-issue-292-01GEAYeG1ndSdTpg11CDQSic`
**Status**: In Progress
**Started**: 2025-11-19

## Overview

This document tracks the implementation of GitHub Projects V2 integration for AIDP, enabling hierarchical project management with sub-issues, project board synchronization, and automated PR workflows.

## Implementation Phases

### ✅ Phase 1: GitHub Projects API Foundation (COMPLETED)

**Goal**: Add GraphQL Projects V2 API client and configuration support

#### Completed Tasks

- [x] Add GitHub Projects V2 GraphQL queries to `RepositoryClient`
  - [x] `fetch_project(project_id)` - Get project details
  - [x] `list_project_items(project_id)` - List all items in project
  - [x] `link_issue_to_project(project_id, issue_number)` - Add issue to project
  - [x] `update_project_item_field(item_id, field_id, value)` - Update custom fields
  - [x] `create_project_field(project_id, name, type)` - Create custom fields
  - [x] `fetch_project_fields(project_id)` - Get available fields
  - [x] Add comprehensive logging with `Aidp.log_debug`
  - [x] Add error handling for GraphQL failures

- [x] Extend `Config` class with projects section
  - [x] `projects.enabled` (boolean, default: false)
  - [x] `projects.default_project_id` (string)
  - [x] `projects.field_mappings` (hash: status, priority, skills, personas)
  - [x] `projects.auto_create_fields` (boolean, default: true)
  - [x] Add configuration validation
  - [x] Add configuration documentation

- [x] Create helper methods for issue/PR operations
  - [x] `create_issue(title:, body:, labels:, assignees:)` - Create GitHub issues
  - [x] `merge_pull_request(number, merge_method:)` - Merge PRs with auto-delete

#### Files Modified

- `lib/aidp/watch/repository_client.rb` - Added 500+ lines of GraphQL integration
- `lib/aidp/config.rb` - Added watch mode and projects configuration

#### Commit

- Commit: `6410a1a` - feat: Add GitHub Projects V2 API integration (Phase 1)

---

### ✅ Phase 2: Sub-Issue Creation and Planning (COMPLETED)

**Goal**: Enable AI-powered hierarchical planning and sub-issue creation

#### Completed Tasks

- [x] Extend `PlanGenerator` to support hierarchical planning
  - [x] Add `HIERARCHICAL_PROVIDER_PROMPT` for breaking down into sub-issues
  - [x] Request AI to identify:
    - [x] Sub-tasks that can become independent issues
    - [x] Dependencies between sub-tasks
    - [x] Required skills for each sub-task
    - [x] Suggested personas for each sub-task
  - [x] Return structured JSON with sub-issue data
  - [x] Add `hierarchical` parameter to `generate()` method
  - [x] Update `parse_structured_response()` to extract sub-issues
  - [x] Add logging for plan breakdown decisions

- [x] Create new `Watch::SubIssueCreator` class
  - [x] `create_sub_issues(parent_issue, plan_data)` method
  - [x] Generate sub-issue titles and descriptions
  - [x] Apply `aidp-auto` label to sub-issues
  - [x] Link sub-issues to parent in description
  - [x] Link all issues to project (if configured)
  - [x] Set custom fields (skills, personas)
  - [x] Post comment on parent with sub-issue links
  - [x] Add comprehensive logging

- [x] Extend `StateStore` with project and hierarchy tracking
  - [x] Add `projects` hash for tracking project item IDs
  - [x] Add `hierarchies` hash for parent-child relationships
  - [x] `project_item_id(issue_number)` - Get project item ID
  - [x] `record_project_item_id(issue_number, item_id)` - Track in project
  - [x] `project_sync_data(issue_number)` - Get sync status
  - [x] `record_project_sync(issue_number, data)` - Update sync state
  - [x] `sub_issues(parent_number)` - Get sub-issues for parent
  - [x] `parent_issue(sub_issue_number)` - Get parent for sub-issue
  - [x] `record_sub_issues(parent_number, sub_issues)` - Record relationships
  - [x] `blocking_status(issue_number)` - Check if blocked by sub-issues

#### Files Modified

- `lib/aidp/watch/plan_generator.rb` - Added hierarchical planning support
- `lib/aidp/watch/state_store.rb` - Added projects and hierarchies tracking
- `lib/aidp/watch/sub_issue_creator.rb` - New 220-line class

#### Commit

- Commit: `25c24e1` - feat: Add sub-issue creation and hierarchical planning (Phase 2)

---

### ✅ Phase 3: Project Board Synchronization (COMPLETED)

**Goal**: Create ProjectsProcessor for automatic project board updates

#### Completed Tasks

- [x] Create new `Watch::ProjectsProcessor` class
  - [x] `sync_issue_to_project(issue_number)` method
  - [x] `update_issue_status(issue_number, status)` method
  - [x] `check_blocking_dependencies(issue_number)` method
  - [x] Determine if issue is blocked by open sub-issues
  - [x] Update project fields based on issue state
  - [x] Handle parent/child relationship updates
  - [x] Add comprehensive logging

- [x] Add `sync_all_issues(issues)` for batch synchronization
- [x] Add `ensure_project_fields` for field auto-creation

- [x] Add project field auto-creation
  - [x] Detect missing fields in project
  - [x] Create fields with configured names
  - [x] Use default values from config
  - [x] Handle field creation errors gracefully
  - [x] Cache project fields to avoid repeated fetches

#### Files Created

- `lib/aidp/watch/projects_processor.rb` - 280+ line class

#### Implementation Notes

Key features:

- Rate limiting: Field cache to reduce API calls
- Error recovery: Continue processing if one issue fails
- Idempotency: Safe to run sync multiple times
- Performance: Cached project field IDs

---

### ✅ Phase 4: Hierarchical PR Strategy (COMPLETED)

**Goal**: Implement parent and sub-issue PR creation with proper targeting

#### Completed Tasks

- [x] Create `Watch::HierarchicalPrStrategy` helper class
  - [x] `parent_issue?(issue_number)` - Detect parent issues
  - [x] `sub_issue?(issue_number)` - Detect sub-issues
  - [x] `pr_options_for_issue(issue)` - Get PR options based on hierarchy
  - [x] `branch_name_for(issue)` - Generate hierarchical branch names
  - [x] `pr_description_for(issue)` - Build hierarchy-aware descriptions

- [x] Parent issue handling
  - [x] Detect parent issues (has sub-issues)
  - [x] Create draft PR for parent issue
  - [x] Set base branch to main/master
  - [x] Add PR description linking all sub-issue PRs
  - [x] Set PR to draft mode
  - [x] Add label: `aidp-parent-pr`

- [x] Sub-issue handling
  - [x] Detect sub-issues (has parent reference)
  - [x] Create PR targeting parent's branch (not main)
  - [x] Add PR description with parent links
  - [x] Add label: `aidp-sub-pr`

- [x] Update branch naming for hierarchical structure
  - [x] Parent: `aidp/parent-{number}-{slug}`
  - [x] Sub-issue: `aidp/sub-{parent}-{number}-{slug}`
  - [x] Regular: `aidp/issue-{number}-{slug}`

#### Files Created

- `lib/aidp/watch/hierarchical_pr_strategy.rb` - 200+ line class

#### Implementation Notes

Branch strategy:

```text
main
 └── aidp/parent-292-feature
      ├── aidp/sub-292-293-subtask-1
      ├── aidp/sub-292-294-subtask-2
      └── aidp/sub-292-295-subtask-3
```

---

### ✅ Phase 5: Auto-Merge for Sub-Issue PRs (COMPLETED)

**Goal**: Automatically merge sub-issue PRs when CI passes

#### Completed Tasks

- [x] Create new `Watch::AutoMerger` class
  - [x] `can_auto_merge?(pr_number)` method
    - [x] Check if PR is sub-issue PR (has label)
    - [x] Check CI status is success
    - [x] Check no conflicts
    - [x] Check not a parent PR
  - [x] `merge_pr(pr_number)` method
    - [x] Merge using GitHub API
    - [x] Use squash or merge strategy (configurable)
    - [x] Delete branch after merge (via gh CLI)
    - [x] Post comment on PR
    - [x] Update parent issue status
  - [x] `process_auto_merge_candidates(prs)` for batch processing
  - [x] `list_sub_pr_candidates` to find eligible PRs
  - [x] Add comprehensive logging

- [x] Add safeguards against auto-merging parent PRs
  - [x] Check for `aidp-parent-pr` label
  - [x] Require manual review (never auto-merge parents)
  - [x] Post reminder comment when all sub-PRs merged
  - [x] Mark parent PR ready for review when complete

#### Files Created

- `lib/aidp/watch/auto_merger.rb` - 250+ line class

#### Implementation Notes

Auto-merge eligibility:

- Must have `aidp-sub-pr` label
- Must NOT have `aidp-parent-pr` label
- CI must be passing (state: success)
- PR must have no merge conflicts
- PR must be in "open" state

---

### 📋 Phase 6: Gantt Chart Synchronization (PENDING)

**Goal**: Sync dependencies from product requirements documents

#### Pending Tasks

- [ ] Create new `Watch::PRDParser` class
  - [ ] Parse Gantt chart data from PRD
  - [ ] Extract task dependencies
  - [ ] Extract timelines and milestones
  - [ ] Map PRD tasks to GitHub issues
  - [ ] Add comprehensive logging

- [ ] Extend `ProjectsProcessor` with Gantt sync
  - [ ] `sync_from_gantt(prd_path)` method
  - [ ] Create blocking relationships matching Gantt
  - [ ] Update project timeline fields
  - [ ] Set milestone dates
  - [ ] Add validation for circular dependencies

- [ ] Add PRD configuration
  - [ ] `projects.prd_path` - Path to PRD file
  - [ ] `projects.auto_sync_gantt` - Enable/disable auto-sync
  - [ ] `projects.gantt_format` - Format of Gantt data (Mermaid, etc.)

#### Implementation Notes

Supported Gantt formats:

- Mermaid Gantt charts
- Microsoft Project XML
- CSV with task dependencies

---

### 📋 Phase 7: Documentation and Polish (PENDING)

**Goal**: Comprehensive documentation and error handling

#### Pending Tasks

- [x] Create `docs/GITHUB_PROJECTS.md` guide
  - [x] Feature overview
  - [x] Configuration examples
  - [x] Workflow diagrams
  - [x] Troubleshooting guide
  - [x] API reference
  - [x] Best practices

- [ ] Update existing documentation
  - [ ] `docs/CLI_USER_GUIDE.md` with projects commands
  - [ ] `docs/CONFIGURATION.md` with projects settings
  - [ ] `README.md` with projects feature
  - [ ] Add code comments with references

- [ ] Error handling audit
  - [ ] Review all error paths
  - [ ] Add helpful error messages
  - [ ] Add recovery suggestions
  - [ ] Test failure scenarios

- [ ] Logging audit
  - [ ] Ensure all methods use `Aidp.log_debug`
  - [ ] Add operation timing logs
  - [ ] Add decision rationale logs
  - [ ] Test log output clarity

- [ ] Performance optimization
  - [ ] Review GraphQL query efficiency
  - [ ] Add caching where appropriate
  - [ ] Batch operations when possible
  - [ ] Test with large projects (100+ issues)

---

### 📋 Phase 8: Integration Testing and Validation (PENDING)

**Goal**: Comprehensive testing and final cleanup

#### Pending Tasks

- [ ] Create end-to-end tests
  - [ ] Test complete flow: issue → plan → sub-issues → PRs → merge
  - [ ] Test with real GitHub repository (test repo)
  - [ ] Test error recovery scenarios
  - [ ] Test concurrent sub-issue processing

- [ ] Create unit tests
  - [ ] Test `RepositoryClient` GraphQL methods
  - [ ] Test `SubIssueCreator` issue creation
  - [ ] Test `PlanGenerator` hierarchical planning
  - [ ] Test `StateStore` hierarchy tracking
  - [ ] Test project field updates
  - [ ] Test auto-merge eligibility logic

- [ ] Manual testing checklist
  - [ ] Create test project in GitHub
  - [ ] Import complex issue
  - [ ] Verify sub-issue creation
  - [ ] Verify PR hierarchy
  - [ ] Verify auto-merge behavior
  - [ ] Verify parent PR manual review requirement

- [ ] Final cleanup
  - [ ] Run linter: `bundle exec standardrb --fix`
  - [ ] Remove any commented code
  - [ ] Remove debug logging
  - [ ] Final documentation review
  - [ ] Update CHANGELOG.md

---

## Architecture Decisions

### GraphQL Over REST

**Decision**: Use GitHub's GraphQL API for Projects V2

**Rationale**:

- Projects V2 only available via GraphQL
- More efficient (single query for multiple resources)
- Better type safety with structured queries

### State Storage

**Decision**: Extend existing YAML-based StateStore

**Rationale**:

- Consistent with existing watch mode state
- Simple file-based persistence
- Easy to inspect and debug
- No additional dependencies

### Hierarchical Planning Mode

**Decision**: Explicit hierarchical flag vs automatic detection

**Rationale**:

- User control over when to break down issues
- Prevents unwanted sub-issue creation
- Can be overridden by AI's `should_create_sub_issues` flag

### Parent PR Strategy

**Decision**: Draft PRs that can't be auto-merged

**Rationale**:

- Ensures human review of integration
- Shows progress as sub-PRs merge
- Prevents accidental merge to main

## Dependencies

### GitHub Requirements

- GitHub Projects V2 (not Classic Projects)
- GitHub CLI (`gh`) with authentication
- Project admin permissions for field creation
- Workflow permissions for PR merging

### Code Dependencies

- `RepositoryClient` - GraphQL API access
- `PlanGenerator` - AI-powered planning
- `StateStore` - State persistence
- `BuildProcessor` - PR creation
- `Watch::Runner` - Main watch loop

## Testing Strategy

### Unit Tests

- Mock GraphQL responses for API methods
- Test field mapping logic
- Test hierarchy tracking
- Test auto-merge eligibility

### Integration Tests

- Use VCR for recording real API interactions
- Test full workflow with test repository
- Test error recovery and retries
- Test concurrent operations

### Manual Testing

- Real GitHub project
- Complex multi-component issues
- Various project configurations
- Error scenarios

## Performance Considerations

### GraphQL Query Optimization

- Batch field updates where possible
- Use pagination for large projects
- Cache project field IDs
- Minimize redundant fetches

### Rate Limiting

- Respect GitHub API rate limits
- Add exponential backoff for retries
- Use conditional requests where possible
- Monitor rate limit headers

### Scalability

- Support projects with 100+ issues
- Handle concurrent sub-issue processing
- Efficient state storage and lookups
- Background processing for large operations

## Security Considerations

### Authentication

- Require GitHub CLI authentication
- Verify project access permissions
- Handle token expiration gracefully

### Authorization

- Check author allowlist for public repos
- Verify project admin for field creation
- Validate PR merge permissions

### Data Safety

- Never auto-merge parent PRs
- Require CI success for auto-merge
- Validate all GraphQL mutations
- Handle concurrent updates safely

## Migration Path

### Existing Watch Mode Users

1. Update to latest version
2. Add `projects` config section
3. Enable feature with `projects.enabled: true`
4. Existing issues continue working
5. New issues can use hierarchical planning

### Rollback Plan

- Feature flag: `projects.enabled: false` disables entirely
- Existing state files remain compatible
- No breaking changes to existing workflows
- Can revert to previous version safely

## Future Enhancements

### Potential Additions

- GitHub Milestones integration
- Dependency graphs visualization
- Gantt chart generation from issues
- Multi-project support
- Custom field templates
- Automated sprint planning
- Effort estimation tracking
- Team workload balancing

### Community Feedback

- Gather usage patterns
- Collect feature requests
- Monitor performance metrics
- Iterate based on real-world usage

## References

- [GitHub Issue #292](https://github.com/viamin/aidp/issues/292)
- [GitHub Projects V2 API](https://docs.github.com/en/graphql/reference/objects#projectv2)
- [AIDP Style Guide](LLM_STYLE_GUIDE.md)
- [GitHub Projects Documentation](GITHUB_PROJECTS.md)

## Progress Summary

**Overall Completion**: 5/8 phases complete (62.5%)

- ✅ Phase 1: API Foundation - **Complete**
- ✅ Phase 2: Sub-Issue Creation - **Complete**
- ✅ Phase 3: Project Synchronization - **Complete**
- ✅ Phase 4: Hierarchical PRs - **Complete**
- ✅ Phase 5: Auto-Merge - **Complete**
- 📋 Phase 6: Gantt Sync - Pending (optional enhancement)
- 📋 Phase 7: Documentation - Partial (guides complete, need updates)
- 📋 Phase 8: Testing - Pending

**Next Steps**: Add unit tests for new classes and run the test suite to verify functionality.
