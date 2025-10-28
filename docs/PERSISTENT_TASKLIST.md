# Persistent Tasklist - Product Requirements Document (PRD)

**Feature**: Persistent Tasklist

**Status**: 📋 Ready for Implementation

**Priority**: High

**Estimated Effort**: 1-2 days

**Created**: 2025-10-27

**Related Issues**: [#176](https://github.com/viamin/aidp/issues/176)

---

## Executive Summary

Enhance AIDP's existing tasklist template to persist tasks across sessions via a git-committable `.aidp/tasklist.jsonl` file. This provides 90% of the value of external project tracking tools (like Beads) at 10% of the complexity, with zero external dependencies and zero context overhead.

### Value Proposition

**Problem**: Current tasklist template is session-scoped - tasks disappear between major workflow changes or when agents discover sub-tasks during implementation.

**Solution**: Persist tasks in `.aidp/tasklist.jsonl` (append-only JSONL format) so agents can:

- Resume work across sessions ("What was I working on?")
- Track discovered tasks during implementation
- Maintain task context across workflow changes
- Git-commit task state alongside code changes

**Impact**: Eliminates context loss between sessions, saving 10-15 minutes per session resume (2-3 times/day = 20-45 min/day saved).

---

## Table of Contents

1. [Background](#background)
2. [Goals & Non-Goals](#goals--non-goals)
3. [User Stories](#user-stories)
4. [Technical Design](#technical-design)
5. [Implementation Plan](#implementation-plan)
6. [Testing Strategy](#testing-strategy)
7. [Risks & Mitigation](#risks--mitigation)
8. [Success Metrics](#success-metrics)
9. [Future Enhancements](#future-enhancements)

---

## Background

### Current State

AIDP's tasklist template (used in work loops) provides excellent structure for organizing current work:

```markdown
## Tasklist
- [ ] Task 1
- [ ] Task 2
- [x] Task 3
```

**Limitations**:

1. **Session-scoped**: Cleared when workflow changes or agent restarts with new context
2. **Ephemeral**: Tasks discovered during implementation are often lost
3. **No history**: Cannot see what was worked on yesterday/last week
4. **Manual tracking**: Users resort to external tools or markdown files

### Why Now?

Issue #176 investigated external tools (Beads, memory-bank-mcp) but analysis showed:

- Beads provides multi-session task persistence (valuable)
- But adds 3% context overhead + external dependency
- 90% of value achievable via simple AIDP enhancement
- Better to enhance core than add dependencies

---

## Goals & Non-Goals

### Goals

✅ **Persist tasks across sessions**

- Tasks survive workflow changes, agent restarts, compaction cycles
- Git-committable task history

✅ **Zero context overhead**

- Task persistence doesn't consume prompt budget
- Tasks loaded on-demand (agent queries when needed)

✅ **Simple, Git-friendly format**

- Human-readable JSONL (one task per line)
- Easy to review in diffs
- Merge-friendly (append-only structure)

✅ **Backward compatible**

- Existing tasklist template continues to work
- Persistence is optional enhancement
- No breaking changes

✅ **Discovery support**

- Agents can file new tasks discovered during implementation
- Link discovered tasks to current work context

### Non-Goals

❌ **Complex dependency graphs**

- No "Task A blocks Task B" relationships
- Keep it simple (flat task list with priorities)
- Users wanting complex dependencies can use Beads (see [OPTIONAL_TOOLS.md](OPTIONAL_TOOLS.md))

❌ **UI/Dashboard**

- No fancy task management UI (at least initially)
- REPL commands + file viewing is sufficient
- Future: Could add `/tasks` REPL command for browsing

❌ **Automatic task detection**

- No AI parsing of agent responses to auto-file tasks
- Explicit task filing only (via template or API)
- Keeps behavior predictable and debuggable

❌ **Integration with external trackers**

- No syncing with Jira, GitHub Issues, etc.
- AIDP-local task management only
- Users can manually copy tasks if needed

---

## User Stories

### Story 1: Resume Work After Weekend

**As a** developer returning to a project Monday morning

**I want** to see what tasks I was working on Friday

**So that** I can pick up where I left off without memory loss

**Acceptance Criteria**:

- Agent can query `.aidp/tasklist.jsonl` at session start
- Shows tasks with status `pending` or `in_progress`
- Includes context: when discovered, related session, priority
- Takes < 1 second to load and display

### Story 2: Track Discovered Work

**As an** agent implementing a feature

**I want** to file sub-tasks discovered during implementation

**So that** they don't get forgotten after I complete the current work

**Acceptance Criteria**:

- Agent can file new task via template extension: `File task: "Add rate limiting"`
- Task persisted to `.aidp/tasklist.jsonl` with metadata
- Linked to current session/work context
- Can prioritize (high/medium/low)

### Story 3: Git-Tracked Task History

**As a** developer reviewing project history

**I want** tasks committed alongside code changes

**So that** I can understand what work was planned vs. completed

**Acceptance Criteria**:

- `.aidp/tasklist.jsonl` is git-tracked (not in `.gitignore`)
- Can run `git log .aidp/tasklist.jsonl` to see task evolution
- Diffs show task additions/status changes clearly
- Merge-friendly (append-only reduces conflicts)

### Story 4: Query Task Status

**As an** agent or developer

**I want** to see what tasks are pending/done/in-progress

**So that** I can make informed decisions about what to work on next

**Acceptance Criteria**:

- Can filter tasks by status: `pending`, `in_progress`, `done`, `abandoned`
- Can filter by priority: `high`, `medium`, `low`
- Can filter by age (tasks older than N days)
- Results displayed clearly in REPL or prompt

### Story 5: Abandon Obsolete Tasks

**As a** developer cleaning up old work

**I want** to mark tasks as abandoned (not deleted)

**So that** history is preserved but noise is reduced

**Acceptance Criteria**:

- Can update task status to `abandoned`
- Abandoned tasks excluded from default queries
- Still visible in full history
- Can include reason: `"Abandoned: Feature request cancelled"`

---

## Technical Design

### File Format: `.aidp/tasklist.jsonl`

**JSONL (JSON Lines)** - one JSON object per line, append-only:

```jsonl
{"id":"task_001","description":"Add rate limiting to API","status":"done","priority":"high","created_at":"2025-10-25T10:30:00Z","updated_at":"2025-10-26T14:20:00Z","session":"auth-implementation","discovered_during":"implementing OAuth flow","completed_at":"2025-10-26T14:20:00Z"}
{"id":"task_002","description":"Update API documentation","status":"pending","priority":"medium","created_at":"2025-10-25T10:35:00Z","updated_at":"2025-10-25T10:35:00Z","session":"auth-implementation","discovered_during":"implementing OAuth flow"}
{"id":"task_003","description":"Add integration tests for auth","status":"in_progress","priority":"high","created_at":"2025-10-26T09:00:00Z","updated_at":"2025-10-27T11:00:00Z","session":"testing-phase","started_at":"2025-10-27T11:00:00Z"}
```

**Why JSONL?**

- ✅ Human-readable (for debugging)
- ✅ Git-friendly (line-based diffs)
- ✅ Merge-friendly (append-only structure reduces conflicts)
- ✅ Fast to parse (Ruby's `JSON.parse` per line)
- ✅ Supports structured queries (filter by status, priority, date)

### Task Schema

```ruby
Task = Struct.new(
  :id,                  # String: Unique identifier (e.g., "task_001")
  :description,         # String: Task description (1-200 chars)
  :status,              # Symbol: :pending, :in_progress, :done, :abandoned
  :priority,            # Symbol: :high, :medium, :low (optional, default :medium)
  :created_at,          # Time: When task was created
  :updated_at,          # Time: Last update timestamp
  :session,             # String: Work loop session identifier (optional)
  :discovered_during,   # String: Context when task was discovered (optional)
  :started_at,          # Time: When work started (status → in_progress)
  :completed_at,        # Time: When work completed (status → done)
  :abandoned_at,        # Time: When task was abandoned
  :abandoned_reason,    # String: Why task was abandoned (optional)
  :tags,                # Array<String>: Tags for categorization (optional)
  keyword_init: true
)
```

### Architecture

#### Core Classes

**1. `Aidp::Execute::PersistentTasklist`**

Main interface for persistent tasklist operations:

```ruby
module Aidp
  module Execute
    class PersistentTasklist
      attr_reader :project_dir, :file_path

      def initialize(project_dir)
        @project_dir = project_dir
        @file_path = File.join(project_dir, ".aidp", "tasklist.jsonl")
        ensure_file_exists
      end

      # Create a new task
      def create(description, priority: :medium, session: nil, discovered_during: nil, tags: [])
        task = Task.new(
          id: generate_id,
          description: description,
          status: :pending,
          priority: priority,
          created_at: Time.now,
          updated_at: Time.now,
          session: session,
          discovered_during: discovered_during,
          tags: tags
        )

        append_task(task)
        task
      end

      # Update task status
      def update_status(task_id, new_status, reason: nil)
        task = find(task_id)
        raise TaskNotFound, task_id unless task

        task.status = new_status
        task.updated_at = Time.now

        case new_status
        when :in_progress
          task.started_at = Time.now
        when :done
          task.completed_at = Time.now
        when :abandoned
          task.abandoned_at = Time.now
          task.abandoned_reason = reason
        end

        append_task(task)  # Append updated version
        task
      end

      # Query tasks
      def all(status: nil, priority: nil, since: nil, tags: nil)
        tasks = load_latest_tasks

        tasks = tasks.select { |t| t.status == status } if status
        tasks = tasks.select { |t| t.priority == priority } if priority
        tasks = tasks.select { |t| t.created_at >= since } if since
        tasks = tasks.select { |t| (t.tags & tags).any? } if tags

        tasks.sort_by(&:created_at).reverse
      end

      # Find single task
      def find(task_id)
        all.find { |t| t.id == task_id }
      end

      # Query pending tasks (common operation)
      def pending
        all(status: :pending)
      end

      # Query in-progress tasks
      def in_progress
        all(status: :in_progress)
      end

      # Count tasks by status
      def counts
        tasks = load_latest_tasks
        {
          total: tasks.size,
          pending: tasks.count { |t| t.status == :pending },
          in_progress: tasks.count { |t| t.status == :in_progress },
          done: tasks.count { |t| t.status == :done },
          abandoned: tasks.count { |t| t.status == :abandoned }
        }
      end

      private

      def append_task(task)
        File.open(@file_path, "a") do |f|
          f.puts task.to_h.to_json
        end
      end

      def load_latest_tasks
        # Load all tasks, keeping only latest version of each ID
        tasks_by_id = {}

        File.readlines(@file_path).each do |line|
          data = JSON.parse(line, symbolize_names: true)
          task = Task.new(**data.merge(
            created_at: Time.parse(data[:created_at]),
            updated_at: Time.parse(data[:updated_at]),
            started_at: data[:started_at] ? Time.parse(data[:started_at]) : nil,
            completed_at: data[:completed_at] ? Time.parse(data[:completed_at]) : nil,
            abandoned_at: data[:abandoned_at] ? Time.parse(data[:abandoned_at]) : nil
          ))

          tasks_by_id[task.id] = task
        end

        tasks_by_id.values
      end

      def generate_id
        "task_#{Time.now.to_i}_#{SecureRandom.hex(4)}"
      end

      def ensure_file_exists
        FileUtils.mkdir_p(File.dirname(@file_path))
        FileUtils.touch(@file_path) unless File.exist?(@file_path)
      end
    end
  end
end
```

**2. `Aidp::Execute::TasklistTemplate` (Enhancement)**

Extend existing tasklist template to support persistence:

```ruby
# In existing work loop template rendering
class TasklistTemplate
  def render(tasks: [], persistent_tasklist: nil)
    output = "## Tasklist\n\n"

    # Show in-memory tasks (current session)
    tasks.each do |task|
      checkbox = task[:done] ? "[x]" : "[ ]"
      output << "- #{checkbox} #{task[:description]}\n"
    end

    # Show pending persistent tasks (cross-session)
    if persistent_tasklist
      pending = persistent_tasklist.pending

      if pending.any?
        output << "\n### Tasks from Previous Sessions\n\n"
        pending.each do |task|
          priority_marker = task.priority == :high ? "⚠️" : ""
          age_days = ((Time.now - task.created_at) / 86400).to_i
          age_label = age_days > 0 ? " (#{age_days}d ago)" : ""

          output << "- [ ] #{priority_marker} #{task.description}#{age_label}\n"
        end
      end
    end

    # Instructions for filing new tasks
    output << "\n### File New Task\n"
    output << "To persist a task for future sessions: `File task: \"description\" [priority: high|medium|low]`\n"

    output
  end
end
```

**3. REPL Command: `/tasks`**

Add new REPL command for browsing tasks:

```ruby
module Aidp
  module Repl
    class TasksCommand
      def initialize(project_dir)
        @tasklist = Aidp::Execute::PersistentTasklist.new(project_dir)
      end

      def execute(args)
        subcommand = args[0]

        case subcommand
        when "list", nil
          list_tasks(status: args[1]&.to_sym)
        when "show"
          show_task(args[1])
        when "done"
          mark_done(args[1])
        when "abandon"
          abandon_task(args[1], reason: args[2..-1].join(" "))
        when "stats"
          show_stats
        else
          show_help
        end
      end

      private

      def list_tasks(status: nil)
        tasks = status ? @tasklist.all(status: status) : @tasklist.all

        if tasks.empty?
          puts "No tasks found."
          return
        end

        # Group by status
        by_status = tasks.group_by(&:status)

        [:pending, :in_progress, :done, :abandoned].each do |status|
          next unless by_status[status]

          puts "\n#{status.to_s.upcase.gsub('_', ' ')} (#{by_status[status].size})"
          puts "=" * 50

          by_status[status].each do |task|
            priority_icon = case task.priority
            when :high then "⚠️"
            when :medium then "○"
            when :low then "·"
            end

            age = ((Time.now - task.created_at) / 86400).to_i
            age_str = age > 0 ? " (#{age}d ago)" : " (today)"

            puts "  #{priority_icon} [#{task.id}] #{task.description}#{age_str}"
          end
        end
      end

      def show_task(task_id)
        task = @tasklist.find(task_id)

        unless task
          puts "Task not found: #{task_id}"
          return
        end

        puts "\nTask Details:"
        puts "=" * 50
        puts "ID:          #{task.id}"
        puts "Description: #{task.description}"
        puts "Status:      #{task.status}"
        puts "Priority:    #{task.priority}"
        puts "Created:     #{task.created_at}"
        puts "Updated:     #{task.updated_at}"
        puts "Session:     #{task.session}" if task.session
        puts "Context:     #{task.discovered_during}" if task.discovered_during
        puts "Started:     #{task.started_at}" if task.started_at
        puts "Completed:   #{task.completed_at}" if task.completed_at
        puts "Abandoned:   #{task.abandoned_at} (#{task.abandoned_reason})" if task.abandoned_at
        puts "Tags:        #{task.tags.join(', ')}" if task.tags&.any?
      end

      def mark_done(task_id)
        task = @tasklist.update_status(task_id, :done)
        puts "✓ Task marked as done: #{task.description}"
      end

      def abandon_task(task_id, reason: nil)
        task = @tasklist.update_status(task_id, :abandoned, reason: reason)
        puts "✗ Task abandoned: #{task.description}"
      end

      def show_stats
        counts = @tasklist.counts

        puts "\nTask Statistics:"
        puts "=" * 50
        puts "Total:       #{counts[:total]}"
        puts "Pending:     #{counts[:pending]}"
        puts "In Progress: #{counts[:in_progress]}"
        puts "Done:        #{counts[:done]}"
        puts "Abandoned:   #{counts[:abandoned]}"
      end

      def show_help
        puts <<~HELP
          Usage: /tasks <command> [args]

          Commands:
            list [status]     List all tasks (optionally filter by status)
            show <id>         Show task details
            done <id>         Mark task as done
            abandon <id> [reason]  Abandon task with optional reason
            stats             Show task statistics

          Examples:
            /tasks list pending
            /tasks show task_001
            /tasks done task_001
            /tasks abandon task_002 "Feature cancelled"
            /tasks stats
        HELP
      end
    end
  end
end
```

### Integration Points

#### 1. Work Loop Runner

Inject persistent tasklist into work loop context:

```ruby
# lib/aidp/execute/work_loop_runner.rb
def initialize(project_dir, provider_manager, config, options = {})
  # ... existing initialization
  @persistent_tasklist = PersistentTasklist.new(project_dir)
end

def execute_step(step_name, step_spec, context = {})
  # Before starting work loop, show pending tasks
  pending_tasks = @persistent_tasklist.pending

  if pending_tasks.any?
    display_message("📋 You have #{pending_tasks.size} pending tasks from previous sessions:", type: :info)
    pending_tasks.take(5).each do |task|
      display_message("  • #{task.description}", type: :info)
    end
    display_message("  Use /tasks list to see all tasks", type: :info) if pending_tasks.size > 5
  end

  # Inject persistent tasklist into prompt context
  enriched_context = context.merge(
    persistent_tasklist: @persistent_tasklist
  )

  # ... existing work loop execution
end
```

#### 2. Agent Signal Parser

Parse task filing signals from agent responses:

```ruby
# lib/aidp/execute/agent_signal_parser.rb
def parse_task_filing(response_text)
  # Pattern: "File task: \"description\" [priority: high|medium|low] [tags: tag1,tag2]"
  pattern = /File task:\s*"([^"]+)"(?:\s+priority:\s*(high|medium|low))?(?:\s+tags:\s*([^\s]+))?/i

  matches = response_text.scan(pattern)

  matches.map do |description, priority, tags|
    {
      description: description.strip,
      priority: (priority || "medium").downcase.to_sym,
      tags: tags ? tags.split(",").map(&:strip) : []
    }
  end
end

# In work loop runner
def process_agent_response(response)
  # ... existing processing

  # Check for task filing signals
  filed_tasks = @agent_signal_parser.parse_task_filing(response.content)

  filed_tasks.each do |task_data|
    task = @persistent_tasklist.create(
      task_data[:description],
      priority: task_data[:priority],
      session: @step_name,
      discovered_during: "#{@step_name} iteration #{@iteration_count}",
      tags: task_data[:tags]
    )

    Aidp.log_info("tasklist", "Filed new task", task_id: task.id, description: task.description)
    display_message("📋 Filed task: #{task.description} (#{task.id})", type: :success)
  end
end
```

---

## Implementation Plan

### Phase 1: Core Persistence (Day 1, AM)

**Tasks**:

1. Create `lib/aidp/execute/persistent_tasklist.rb`
   - Implement Task struct
   - Implement PersistentTasklist class
   - JSONL read/write operations
   - Query methods (all, find, pending, in_progress, counts)
   - Effort: 2 hours

2. Add comprehensive tests `spec/aidp/execute/persistent_tasklist_spec.rb`
   - Test task creation
   - Test status updates
   - Test queries (filtering, sorting)
   - Test JSONL format
   - Test append-only behavior
   - Effort: 1.5 hours

3. Update `.gitignore` if needed
   - Ensure `.aidp/tasklist.jsonl` is NOT ignored
   - Effort: 5 minutes

**Deliverable**: Working persistent tasklist with full test coverage

### Phase 2: Work Loop Integration (Day 1, PM)

**Tasks**:

1. Update `lib/aidp/execute/work_loop_runner.rb`
   - Initialize PersistentTasklist
   - Display pending tasks at session start
   - Inject into prompt context
   - Effort: 1 hour

2. Update `lib/aidp/execute/tasklist_template.rb`
   - Render persistent tasks in template
   - Add filing instructions
   - Effort: 1 hour

3. Update `lib/aidp/execute/agent_signal_parser.rb`
   - Parse "File task:" signals
   - Create tasks from agent responses
   - Log filed tasks
   - Effort: 1 hour

4. Integration tests
   - Test work loop with persistent tasklist
   - Test task filing during work loop
   - Test task display in prompts
   - Effort: 1 hour

**Deliverable**: Persistent tasklist integrated into work loops

### Phase 3: REPL Command (Day 2, AM)

**Tasks**:

1. Create `lib/aidp/repl/tasks_command.rb`
   - Implement /tasks command
   - Subcommands: list, show, done, abandon, stats
   - Formatted output
   - Effort: 1.5 hours

2. Register command in REPL dispatcher
   - Add /tasks to command registry
   - Update help text
   - Effort: 15 minutes

3. Tests for REPL command
   - Test all subcommands
   - Test output formatting
   - Effort: 1 hour

**Deliverable**: Working /tasks REPL command

### Phase 4: Documentation & Polish (Day 2, PM)

**Tasks**:

1. Update user documentation
   - Add section to CLI_USER_GUIDE.md
   - Add examples to WORK_LOOPS_GUIDE.md
   - Update REPL_REFERENCE.md
   - Effort: 1 hour

2. Update LLM_STYLE_GUIDE.md
   - Document task filing pattern for agents
   - Best practices for task descriptions
   - Effort: 30 minutes

3. Add example to templates
   - Show task filing in example prompts
   - Effort: 15 minutes

4. Final testing & edge cases
   - Concurrent access (multiple agents)
   - Large task lists (100+ tasks)
   - Malformed JSONL handling
   - Effort: 1 hour

**Deliverable**: Complete, documented persistent tasklist feature

### Total Timeline

**Day 1**: Core + Integration (8 hours)
**Day 2**: REPL + Docs (6 hours)

**Total**: ~14 hours (conservative estimate: 2 days)

---

## Testing Strategy

### Unit Tests

**PersistentTasklist**:

```ruby
RSpec.describe Aidp::Execute::PersistentTasklist do
  let(:project_dir) { Dir.mktmpdir }
  let(:tasklist) { described_class.new(project_dir) }

  after { FileUtils.rm_rf(project_dir) }

  describe "#create" do
    it "creates a new task with pending status" do
      task = tasklist.create("Test task", priority: :high)

      expect(task.description).to eq("Test task")
      expect(task.status).to eq(:pending)
      expect(task.priority).to eq(:high)
      expect(task.id).to match(/^task_/)
    end

    it "persists task to JSONL file" do
      task = tasklist.create("Test task")

      file_content = File.read(tasklist.file_path)
      expect(file_content).to include(task.id)
      expect(file_content).to include("Test task")
    end
  end

  describe "#update_status" do
    it "updates task status and appends to JSONL" do
      task = tasklist.create("Test task")

      updated = tasklist.update_status(task.id, :done)

      expect(updated.status).to eq(:done)
      expect(updated.completed_at).to be_a(Time)

      # Check JSONL has 2 entries (original + update)
      lines = File.readlines(tasklist.file_path)
      expect(lines.size).to eq(2)
    end
  end

  describe "#all" do
    before do
      tasklist.create("Task 1", priority: :high)
      tasklist.create("Task 2", priority: :low)
      task3 = tasklist.create("Task 3", priority: :high)
      tasklist.update_status(task3.id, :done)
    end

    it "returns all tasks with latest state" do
      tasks = tasklist.all
      expect(tasks.size).to eq(3)
    end

    it "filters by status" do
      pending = tasklist.all(status: :pending)
      expect(pending.size).to eq(2)

      done = tasklist.all(status: :done)
      expect(done.size).to eq(1)
    end

    it "filters by priority" do
      high_priority = tasklist.all(priority: :high)
      expect(high_priority.size).to eq(2)
    end
  end

  describe "#pending" do
    it "returns only pending tasks" do
      tasklist.create("Pending 1")
      task2 = tasklist.create("Pending 2")
      tasklist.update_status(task2.id, :in_progress)

      pending = tasklist.pending
      expect(pending.size).to eq(1)
      expect(pending.first.description).to eq("Pending 1")
    end
  end
end
```

### Integration Tests

**Work Loop Integration**:

```ruby
RSpec.describe "Persistent Tasklist Integration" do
  it "displays pending tasks at work loop start" do
    # Create tasks before work loop
    tasklist = Aidp::Execute::PersistentTasklist.new(project_dir)
    tasklist.create("Previous task 1")
    tasklist.create("Previous task 2", priority: :high)

    # Start work loop
    runner = Aidp::Execute::WorkLoopRunner.new(project_dir, provider_manager, config)

    expect {
      runner.execute_step("test_step", step_spec)
    }.to output(/You have 2 pending tasks/).to_stdout
  end

  it "files tasks when agent signals" do
    runner = Aidp::Execute::WorkLoopRunner.new(project_dir, provider_manager, config)

    # Simulate agent response with task filing
    agent_response = 'I implemented auth. File task: "Add rate limiting" priority: high'

    runner.process_agent_response(agent_response)

    # Check task was filed
    tasklist = Aidp::Execute::PersistentTasklist.new(project_dir)
    tasks = tasklist.pending

    expect(tasks.size).to eq(1)
    expect(tasks.first.description).to eq("Add rate limiting")
    expect(tasks.first.priority).to eq(:high)
  end
end
```

### Manual Testing

**Checklist**:

- [ ] Create tasks via /tasks command
- [ ] File tasks from agent responses
- [ ] Resume work loop and see pending tasks
- [ ] Mark tasks as done via /tasks done
- [ ] Abandon tasks with reason
- [ ] Git commit .aidp/tasklist.jsonl
- [ ] Git merge scenarios (conflicts?)
- [ ] Load 100+ tasks (performance check)
- [ ] Concurrent access (two agents running)

---

## Risks & Mitigation

### Risk 1: Merge Conflicts

**Risk**: Multiple developers/agents editing tasklist simultaneously

**Mitigation**:

- Append-only JSONL reduces conflict surface
- Each line is independent (easier to resolve)
- Document conflict resolution: "Accept both changes, delete duplicates"
- Future: Could add automatic deduplication

**Likelihood**: Medium

**Impact**: Low (manual resolution straightforward)

### Risk 2: File Corruption

**Risk**: Malformed JSONL breaks tasklist loading

**Mitigation**:

- Robust error handling (skip invalid lines, log errors)
- Add `/tasks repair` command to rebuild from valid lines
- Regular validation during load
- Tests cover malformed input

**Likelihood**: Low

**Impact**: Medium (fixable but annoying)

### Risk 3: Performance with Large Tasklists

**Risk**: Loading 1000+ tasks slows down work loop start

**Mitigation**:

- Lazy loading (only load on-demand)
- Index last N tasks for quick queries
- Periodic archival (move old done/abandoned tasks to archive file)
- Future: SQLite backend if JSONL too slow

**Likelihood**: Low (most projects have <100 tasks)

**Impact**: Low (optimizable)

### Risk 4: User Confusion

**Risk**: Users don't understand difference between session tasklist and persistent tasklist

**Mitigation**:

- Clear documentation with examples
- Visual separation in prompt ("Tasks from Previous Sessions")
- REPL command help text
- Examples in templates

**Likelihood**: Medium

**Impact**: Low (documentation can address)

---

## Success Metrics

### Quantitative

**Adoption**:

- % of work loops that create persistent tasks: Target >30%
- Avg tasks per project: Target 10-20
- % of projects using persistent tasklist: Target >50%

**Performance**:

- Task file loading time: <100ms for <1000 tasks
- Task creation time: <10ms
- REPL command response time: <200ms

**Quality**:

- Test coverage: >95%
- Zero P0/P1 bugs in first month
- Zero file corruption incidents

### Qualitative

**User Feedback**:

- Users report less context loss between sessions
- Users file discovered tasks instead of forgetting them
- Developers appreciate git-tracked task history

**Agent Behavior**:

- Agents reference pending tasks when starting work
- Agents file tasks discovered during implementation
- Task filing doesn't disrupt work loop flow

---

## Future Enhancements

### Phase 5: Task Archival (Future)

Move old done/abandoned tasks to `.aidp/tasklist_archive.jsonl`:

- Keep active tasklist small (<100 tasks)
- Archive tasks older than 90 days
- `/tasks archive` command
- Effort: 0.5 days

### Phase 6: Task Dependencies (Future)

Add basic "blocks" relationships:

```jsonl
{"id":"task_002","description":"Deploy API","status":"pending","blocks":["task_001"]}
```

- Query: "What's blocking this task?"
- Auto-detect: Can't work on X until Y is done
- Effort: 1 day

### Phase 7: Task Dashboard (Future)

Add `/tasks dashboard` with visual overview:

- Progress bars (% done)
- Priority distribution
- Age histogram
- Burndown chart
- Effort: 2 days

### Phase 8: Export/Import (Future)

Export tasks to other formats:

- Markdown checklist
- GitHub Issues
- Jira CSV
- Effort: 1 day

---

## Conclusion

Persistent tasklist provides 90% of external project tracking value at 10% of complexity:

✅ **Zero context overhead** (unlike Beads: +450 tokens)

✅ **Zero external dependencies** (unlike Beads: npm install + setup)

✅ **Git-native** (commit tasks alongside code)

✅ **Simple, maintainable** (single file, 300 lines of code)

✅ **Backward compatible** (existing workflow unchanged)

**Estimated effort**: 1-2 days

**Expected value**: 20-45 min/day saved (context recovery), better task tracking

**Recommendation**: Implement immediately as replacement for external tools.

---

## Appendix A: Example Usage

### Scenario: Implementing OAuth Feature

**Friday afternoon - Discovery**:

```text
Agent: "I'm implementing OAuth. I notice we'll need rate limiting for the token endpoint."
Agent: File task: "Add rate limiting to /auth/token" priority: high
System: 📋 Filed task: Add rate limiting to /auth/token (task_170310_a3f2)

Agent: "Also, we should update API docs."
Agent: File task: "Update API docs with OAuth flow" priority: medium
System: 📋 Filed task: Update API docs with OAuth flow (task_170315_b8d1)

[Agent completes OAuth implementation]
[Commit includes code + .aidp/tasklist.jsonl]
```

**Monday morning - Resume**:

```text
Developer: $ aidp execute

System: 📋 You have 2 pending tasks from previous sessions:
  • Add rate limiting to /auth/token (3d ago)
  • Update API docs with OAuth flow (3d ago)
  Use /tasks list to see all tasks

Agent: "I see there are pending tasks. Let me work on rate limiting first."
[Picks up exactly where Friday left off]
```

**Later - Check status**:

```text
Developer: /tasks list pending

PENDING (1)
==================================================
  ⚠️ [task_170310_a3f2] Add rate limiting to /auth/token (3d ago)

IN PROGRESS (1)
==================================================
  ○ [task_170315_b8d1] Update API docs with OAuth flow (0d ago)
```

**Completion**:

```text
Developer: /tasks done task_170310_a3f2
System: ✓ Task marked as done: Add rate limiting to /auth/token

Developer: /tasks stats

Task Statistics:
==================================================
Total:       5
Pending:     0
In Progress: 1
Done:        3
Abandoned:   1
```

---

## Appendix B: JSONL Format Details

### Why JSONL over alternatives?

**vs. YAML**:

- JSONL: Line-based, merge-friendly
- YAML: Block-based, merge conflicts common

**vs. SQLite**:

- JSONL: Human-readable, git-friendly, simple
- SQLite: Binary, harder to diff, more complexity

**vs. Single JSON Array**:

- JSONL: Append-only, partial corruption ok
- JSON Array: Full rewrite per update, all-or-nothing parsing

### Example Git Diff

```diff
diff --git a/.aidp/tasklist.jsonl b/.aidp/tasklist.jsonl
index a3f2b8d..c9d4e1a 100644
--- a/.aidp/tasklist.jsonl
+++ b/.aidp/tasklist.jsonl
@@ -1,2 +1,3 @@
 {"id":"task_001","description":"Add rate limiting","status":"pending",...}
 {"id":"task_002","description":"Update docs","status":"pending",...}
+{"id":"task_001","description":"Add rate limiting","status":"done","completed_at":"2025-10-27T14:30:00Z",...}
```

Clear, readable, merge-friendly.

---

## References

- [Issue #176 Investigation](MEMORY_INTEGRATION.md)
- [Optional Tools Guide](OPTIONAL_TOOLS.md)
- [Work Loops Guide](WORK_LOOPS_GUIDE.md)
- [REPL Reference](REPL_REFERENCE.md)
