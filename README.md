# AI Dev Pipeline (aidp) - Ruby Gem

![Coverage](./badges/coverage.svg)

A portable CLI that automates AI development workflows from idea to implementation using your existing IDE assistants. Features autonomous work loops, background execution, and comprehensive progress tracking.

## Quick Start

```bash
# Install the gem
gem install aidp

# Navigate to your project
cd /your/project

# Launch the interactive configuration wizard
aidp config --interactive

# Analyze and bootstrap project docs
aidp init
# Creates LLM_STYLE_GUIDE.md, PROJECT_ANALYSIS.md, CODE_QUALITY_PLAN.md

# Start Copilot interactive mode (default)
aidp
```

### First-Time Setup

On the first run in a project without an `aidp.yml`, AIDP launches a **First-Time Setup Wizard**. You'll be prompted to choose one of:

1. Minimal (single provider: cursor)
2. Development template (multiple providers, safe defaults)
3. Production template (full-feature example – review before committing)
4. Full example (verbose documented config)
5. Custom (interactive prompts for providers and defaults)

Non-interactive environments (CI, scripts, pipes) automatically receive a minimal `aidp.yml` so workflows can proceed without manual intervention.

You can re-run the wizard manually:

```bash
aidp --setup-config
```

## Devcontainer Support

AIDP provides first-class devcontainer support for sandboxed, secure AI agent execution. Devcontainers offer:

- **Network Security**: Strict firewall with allowlisted domains only
- **Sandboxed Environment**: Isolated from your host system
- **Consistent Setup**: Same environment across all developers
- **Automatic Management**: AIDP can generate and update your devcontainer configuration

### For AIDP Development

This repository includes a `.devcontainer/` setup for developing AIDP itself:

```bash
# Open in VS Code
code .

# Press F1 → "Dev Containers: Reopen in Container"
# Container builds automatically with Ruby 3.4.7, all tools, and firewall

# Run tests inside container
bundle exec rspec

# Run AIDP inside container
bundle exec aidp
```

See [.devcontainer/README.md](.devcontainer/README.md) for complete documentation.

### Generating Devcontainers for Your Projects

AIDP can automatically generate and manage devcontainer configurations through the interactive wizard:

```bash
# Launch the interactive configuration wizard
aidp config --interactive

# During the wizard, you'll be asked:
# - Whether you want AIDP to manage your devcontainer configuration
# - If you want to add custom ports beyond auto-detected ones

# The wizard will detect ports based on your project type and generate
# a complete devcontainer.json configuration
```

You can also manage devcontainer configuration manually:

```yaml
# .aidp/aidp.yml
devcontainer:
  manage: true
  custom_ports:
    - number: 3000
      label: "Application Server"
    - number: 5432
      label: "PostgreSQL"
```

Then apply the configuration:

```bash
# Preview changes
aidp devcontainer diff

# Apply configuration
aidp devcontainer apply

# List backups
aidp devcontainer list-backups

# Restore from backup
aidp devcontainer restore 0
```

See [docs/DEVELOPMENT_CONTAINER.md](docs/DEVELOPMENT_CONTAINER.md) for complete devcontainer management documentation.

### Devcontainer Detection

AIDP automatically detects when it's running inside a devcontainer and adjusts its behavior accordingly. This detection uses multiple heuristics including environment variables, filesystem markers, and cgroup information. See [DevcontainerDetector](lib/aidp/utils/devcontainer_detector.rb) for implementation details.

## Core Features

### Work Loops

AIDP implements **work loops** - an iterative execution pattern where AI agents autonomously work on tasks until completion, with automatic testing and linting feedback.

- **Iterative refinement**: Agent works in loops until task is 100% complete
- **Self-management**: Agent edits PROMPT.md to track its own progress
- **Automatic validation**: Tests and linters run after each iteration
- **Self-correction**: Only failures are fed back for the next iteration

See [Work Loops Guide](docs/WORK_LOOPS_GUIDE.md) for details.

### Job Management

Monitor and control background jobs:

```bash
# List and manage jobs
aidp jobs list                        # List all jobs
aidp jobs status <job_id>             # Show job status
aidp jobs logs <job_id> --tail        # View recent logs
aidp checkpoint summary --watch       # Watch metrics in real-time

# Control jobs
aidp jobs stop <job_id>               # Stop a running job
```

### Progress Checkpoints

Track code quality metrics and task progress throughout execution:

```bash
# View current progress
aidp checkpoint summary

# Watch with auto-refresh
aidp checkpoint summary --watch

# View historical data
aidp checkpoint history 20
```

**Tracked Metrics:**

- Lines of code
- Test coverage
- Code quality scores
- PRD task completion percentage
- File count and growth trends

### Parallel Workstreams

Work on multiple tasks simultaneously using isolated git worktrees:

```bash
# Create a workstream for each task
aidp ws new issue-123-fix-auth
aidp ws new feature-dashboard

# List all workstreams
aidp ws list

# Check status
aidp ws status issue-123-fix-auth

# Remove when complete
aidp ws rm issue-123-fix-auth --delete-branch
```

**Benefits:**

- Complete isolation between tasks
- Separate git branches for each workstream
- Independent state and history
- Work on multiple features in parallel

See [Workstreams Guide](docs/WORKSTREAMS.md) for detailed usage.

### Watch Mode (Automated GitHub Integration)

AIDP can automatically monitor GitHub repositories and respond to labeled issues, creating plans and executing implementations autonomously:

```bash
# Start watch mode for a repository
aidp watch https://github.com/owner/repo/issues

# Optional: specify polling interval, provider, and verbose output
aidp watch owner/repo --interval 60 --provider claude --verbose

# Run a single cycle (useful for CI/testing)
aidp watch owner/repo --once
```

**Label Workflow:**

AIDP uses a smart label-based workflow to manage both issues and pull requests:

#### Issue Workflow (Plan & Build)

1. **Planning Phase** (`aidp-plan` label):
   - Add this label to an issue to trigger plan generation
   - AIDP generates an implementation plan with task breakdown and clarifying questions
   - Posts the plan as a comment on the issue
   - Automatically removes the `aidp-plan` label

2. **Review & Clarification**:
   - **If questions exist**: AIDP adds `aidp-needs-input` label and waits for user response
     - User responds to questions in a comment
     - User manually removes `aidp-needs-input` and adds `aidp-build` to proceed
   - **If no questions**: AIDP adds `aidp-ready` label, indicating it's ready to build
     - User can review the plan before proceeding
     - User manually adds `aidp-build` label when ready

3. **Implementation Phase** (`aidp-build` label):
   - Triggers autonomous implementation via work loops
   - Creates a feature branch and commits changes
   - Runs tests and linters with automatic fixes
   - **If clarification needed during implementation**:
     - Posts clarification questions as a comment
     - Automatically removes `aidp-build` label and adds `aidp-needs-input`
     - Preserves work-in-progress for later resumption
     - User responds to questions, then manually removes `aidp-needs-input` and re-adds `aidp-build`
   - **On success**:
     - Posts completion comment with summary
     - Automatically removes the `aidp-build` label

#### Pull Request Workflow (Review, CI Fix, Change Requests)

4. **Code Review** (`aidp-review` label):
   - Add this label to any PR to trigger automated code review
   - AIDP analyzes code from three expert perspectives (Senior Developer, Security Specialist, Performance Analyst)
   - Posts a comprehensive review comment with severity-categorized findings (High Priority, Major, Minor, Nit)
   - Automatically removes the label after posting review
   - No commits are made - review only

5. **CI Fix** (`aidp-fix-ci` label):
   - Add this label to a PR with failing CI checks
   - AIDP analyzes CI failure logs and identifies root causes
   - Automatically fixes issues like linting errors, simple test failures, and dependency problems
   - Commits and pushes fixes to the PR branch
   - Posts a summary of what was fixed
   - Automatically removes the label after completion

6. **Change Requests** (`aidp-request-changes` label):
   - Comment on your own PR describing desired changes, then add this label
   - AIDP implements the requested changes on the PR branch
   - Runs tests/linters and commits changes
   - **If clarification needed**: Replaces label with `aidp-needs-input` and posts questions
   - User responds to questions and re-applies the label to continue
   - Automatically removes the label after completion

**Customizable Labels:**

All label names are configurable to match your repository's existing label scheme. Configure via the interactive wizard or manually in `aidp.yml`:

```yaml
# .aidp/aidp.yml
watch:
  labels:
    # Issue-based automation
    plan_trigger: aidp-plan                    # Trigger plan generation
    needs_input: aidp-needs-input              # Needs user input/clarification
    ready_to_build: aidp-ready                 # Plan ready for implementation
    build_trigger: aidp-build                  # Trigger implementation

    # PR-based automation
    review_trigger: aidp-review                # Trigger code review
    ci_fix_trigger: aidp-fix-ci                # Trigger CI auto-fix
    change_request_trigger: aidp-request-changes  # Trigger PR change implementation
```

Run `aidp config --interactive` and enable watch mode to configure labels interactively.

**Safety Features:**

- **Public Repository Protection**: Disabled by default for public repos (require explicit opt-in)
- **Author Allowlist**: Restrict automation to trusted GitHub users only
- **Container Requirement**: Optionally require sandboxed environment
- **Force Override**: `--force` flag to bypass safety checks (dangerous!)

**Safety Configuration:**

```yaml
# .aidp/aidp.yml
watch:
  safety:
    allow_public_repos: true  # Required for public repositories
    author_allowlist:          # Only these users can trigger automation
      - trusted-maintainer
      - team-member
    require_container: true    # Require devcontainer/Docker environment
```

Run `aidp config --interactive` and enable watch mode to configure safety settings interactively.

**Clarification Requests:**

AIDP can automatically request clarification when it needs more information during implementation. This works in both watch mode and interactive mode:

- **Watch Mode**: Posts clarification questions as a GitHub comment, updates labels to `aidp-needs-input`, and waits for user response
- **Interactive Mode**: Prompts the user directly in the terminal to answer questions before continuing

This ensures AIDP never gets stuck - if it needs more information, it will ask for it rather than making incorrect assumptions or failing silently.

**Additional Documentation:**

- [Watch Mode Guide](docs/FULLY_AUTOMATIC_MODE.md) - Complete guide to watch mode setup and operation
- [Watch Mode Safety](docs/WATCH_MODE_SAFETY.md) - Security features and best practices
- [PR Automation Guide](docs/PR_AUTOMATION.md) - Detailed guide for code review, CI fixes, and PR changes
- [PR Change Requests](docs/PR_CHANGE_REQUESTS.md) - Comprehensive documentation for automated PR modifications

## Command Reference

### Copilot Mode

```bash
# Start interactive Copilot mode (default)
aidp                            # AI-guided workflow selection

# Copilot can perform both analysis and development based on your needs
# It will interactively help you choose the right approach
```

### Job Management

```bash
# List all background jobs
aidp jobs list

# Show job status
aidp jobs status <job_id>
aidp jobs status <job_id> --follow  # Follow with auto-refresh

# View job logs
aidp jobs logs <job_id>
aidp jobs logs <job_id> --tail      # Last 50 lines
aidp jobs logs <job_id> --follow    # Stream in real-time

# Stop a running job
aidp jobs stop <job_id>
```

### Checkpoint Monitoring

```bash
# View latest checkpoint
aidp checkpoint show

# Progress summary with trends
aidp checkpoint summary
aidp checkpoint summary --watch             # Auto-refresh every 5s
aidp checkpoint summary --watch --interval 10  # Custom interval

# View checkpoint history
aidp checkpoint history           # Last 10 checkpoints
aidp checkpoint history 50        # Last 50 checkpoints

# Detailed metrics
aidp checkpoint metrics

# Clear checkpoint data
aidp checkpoint clear
aidp checkpoint clear --force     # Skip confirmation
```

### Workstream Commands

```bash
# Create a new workstream
aidp ws new <slug>
aidp ws new <slug> --base-branch <branch>

# List all workstreams
aidp ws list

# Check workstream status
aidp ws status <slug>

# Remove a workstream
aidp ws rm <slug>
aidp ws rm <slug> --delete-branch  # Also delete git branch
aidp ws rm <slug> --force          # Skip confirmation
```

### Configuration Commands

```bash
# Interactive configuration wizard (recommended)
aidp config --interactive       # Configure all settings including watch mode

# Legacy setup wizard
aidp --setup-config             # Re-run basic setup wizard

# Help and version
aidp --help                     # Show all commands
aidp --version                  # Show version
```

### System Commands

```bash
# Show system status
aidp status

# Provider health dashboard
aidp providers

# Harness state management
aidp harness status
aidp harness reset
```

## AI Providers

AIDP intelligently manages multiple providers with automatic switching:

- **Anthropic Claude CLI** - Primary provider for complex analysis and code generation
- **Codex CLI** - OpenAI's Codex command-line interface for code generation
- **Cursor CLI** - IDE-integrated provider for code-specific tasks
- **Gemini CLI** - Google's Gemini command-line interface for general tasks
- **GitHub Copilot CLI** - GitHub's AI pair programmer command-line interface
- **Kilocode** - Modern AI coding assistant with autonomous mode support
- **OpenCode** - Alternative open-source code generation provider

The system automatically switches providers when:

- Rate limits are hit
- Providers fail or timeout
- Cost limits are reached
- Performance optimization is needed

### Provider Configuration

```yaml
# aidp.yml
harness:
  work_loop:
    enabled: true
    max_iterations: 50
    test_commands:
      - "bundle exec rspec"
    lint_commands:
      - "bundle exec standardrb"
    units:
      deterministic:
        - name: run_full_tests
          command: "bundle exec rake spec"
          enabled: false
          next:
            success: agentic
            failure: decide_whats_next
        - name: wait_for_github
          type: "wait"
          metadata:
            interval_seconds: 60
      defaults:
        on_no_next_step: wait_for_github
        fallback_agentic: decide_whats_next

providers:
  claude:
    type: "usage_based"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
  gemini:
    type: "usage_based"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
  cursor:
    type: "subscription"
```

### Provider Installation

Each provider requires its CLI tool to be installed:

```bash
# Cursor CLI
npm install -g @cursor/cli

# Kilocode CLI
npm install -g @kilocode/cli

# OpenCode CLI
npm install -g @opencode/cli

# GitHub Copilot CLI (requires GitHub account)
gh extension install github/gh-copilot
```

### Environment Variables

```bash
# Set API keys for usage-based providers
export AIDP_CLAUDE_API_KEY="your-claude-api-key"
export AIDP_GEMINI_API_KEY="your-gemini-api-key"

# Kilocode authentication (get token from kilocode.ai profile)
export KILOCODE_TOKEN="your-kilocode-api-token"

# Optional: Configure provider-specific settings
export KILOCODE_MODEL="your-preferred-model"
export AIDP_KILOCODE_TIMEOUT="600"  # Custom timeout in seconds
```

## Tree-sitter Static Analysis

AIDP includes powerful Tree-sitter-based static analysis capabilities for code.

### Tree-sitter Dependencies

The Tree-sitter analysis requires the Tree-sitter system library and pre-compiled language parsers:

```bash
# Install Tree-sitter system library
# macOS
brew install tree-sitter

# Ubuntu/Debian
sudo apt-get install tree-sitter

# Or follow the ruby_tree_sitter README for other platforms
# https://github.com/Faveod/ruby-tree-sitter#installation

# Install Tree-sitter parsers
./install_tree_sitter_parsers.sh
```

### Parser Installation Script

The `install_tree_sitter_parsers.sh` script automatically downloads and installs pre-built Tree-sitter parsers:

```bash
# Make the script executable
chmod +x install_tree_sitter_parsers.sh

# Run the installation script
./install_tree_sitter_parsers.sh
```

The script will:

- Detect your OS and architecture (macOS ARM64, Linux x64, etc.)
- Download the appropriate parser bundle from [Faveod/tree-sitter-parsers](https://github.com/Faveod/tree-sitter-parsers/releases/tag/v4.9)
- Extract parsers to `.aidp/parsers/` directory
- Set up the `TREE_SITTER_PARSERS` environment variable

### Environment Setup

After running the installation script, make the environment variable permanent:

```bash
# Add to your shell profile (e.g., ~/.zshrc, ~/.bashrc)
echo 'export TREE_SITTER_PARSERS="$(pwd)/.aidp/parsers"' >> ~/.zshrc

# Reload your shell
source ~/.zshrc
```

### Knowledge Base Structure

The Tree-sitter analysis generates structured JSON files in `.aidp/kb/`:

- **`symbols.json`** - Classes, modules, methods, and their metadata
- **`imports.json`** - Require statements and dependencies
- **`calls.json`** - Method calls and invocation patterns
- **`metrics.json`** - Code complexity and size metrics
- **`seams.json`** - Integration points and dependency injection opportunities
- **`hotspots.json`** - Frequently changed code areas (based on git history)
- **`tests.json`** - Test coverage analysis
- **`cycles.json`** - Circular dependency detection

### Legacy Code Analysis Features

The Tree-sitter analysis specifically supports:

- **Seam Detection**: Identifies I/O operations, global state access, and constructor dependencies
- **Change Hotspots**: Uses git history to identify frequently modified code
- **Dependency Analysis**: Maps import relationships and call graphs
- **Test Coverage**: Identifies untested public APIs
- **Refactoring Opportunities**: Suggests dependency injection points and seam locations

## File-Based Interaction

At gate steps, the AI creates files for interaction instead of requiring real-time chat:

- **Questions files**: `PRD_QUESTIONS.md`, `ARCH_QUESTIONS.md`, `TASKS_QUESTIONS.md`, `IMPL_QUESTIONS.md` - Contains questions if AI needs more information
- **Output files**: `docs/PRD.md`, `docs/Architecture.md` - Review and edit as needed
- **Progress tracking**: `.aidp-progress.yml` - Tracks completion status

### Answering Questions

When the AI creates a questions file, follow these steps:

1. **Edit the file directly**: Add your answers below each question in the file
2. **Re-run the step**: The AI will read your answers and complete the step
3. **Approve when satisfied**: Mark the step complete and continue

The questions file is only created when the AI needs additional information beyond what it can infer from your project structure and existing files. Your answers are preserved for future reference.

## Workflow Examples

### Standard Interactive Workflow

```bash
# Start Copilot mode (default)
aidp

# Copilot will guide you through:
# - Understanding your project goals
# - Selecting the right workflow (analysis, development, or both)
# - Answering questions about your requirements
# - Reviewing generated files (PRD, architecture, etc.)
# - Automatic execution with harness managing retries
```

### Project Analysis

```bash
# High-level project analysis and documentation
aidp init

# Creates:
# - LLM_STYLE_GUIDE.md
# - PROJECT_ANALYSIS.md
# - CODE_QUALITY_PLAN.md
```

### Progress Monitoring

```bash
# Watch progress in real-time
aidp checkpoint summary --watch

# Check job status
aidp jobs list
aidp checkpoint summary
```

## Debug and Logging

```bash
# Enable debug output to see AI provider communication
AIDP_DEBUG=1 aidp

# Log to a file for debugging
AIDP_LOG_FILE=aidp.log aidp

# Combine both for full debugging
AIDP_DEBUG=1 AIDP_LOG_FILE=aidp.log aidp
```

## Development

```bash
# Install dependencies
bundle install

# Install Tree-sitter parsers for development
./install_tree_sitter_parsers.sh

# Set up environment variables
export TREE_SITTER_PARSERS="$(pwd)/.aidp/parsers"

# Run tests
bundle exec rspec

# Run Tree-sitter analysis tests specifically
bundle exec rspec spec/aidp/analysis/
bundle exec rspec spec/integration/tree_sitter_analysis_workflow_spec.rb

# Run linter
bundle exec standardrb

# Auto-fix linting issues
bundle exec standardrb --fix

# Build gem
bundle exec rake build
```

### Development Dependencies

The following system dependencies are required for development:

- **Tree-sitter** - System library for parsing (install via `brew install tree-sitter` or package manager)
- **Ruby gems** - All required gems are specified in `aidp.gemspec` and installed via `bundle install`

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and conventional commit guidelines.

## Documentation

For detailed information:

- **[CLI User Guide](docs/CLI_USER_GUIDE.md)** - Complete guide to using AIDP commands
- **[Work Loops Guide](docs/WORK_LOOPS_GUIDE.md)** - Iterative workflows with automatic validation
- **[Configuration Guide](docs/harness-configuration.md)** - Detailed configuration options and examples
- **[Troubleshooting Guide](docs/harness-troubleshooting.md)** - Common issues and solutions

## Manual Workflow (Alternative)

The gem packages markdown prompts that can also be used directly with Cursor or any LLM. See the `templates/` directory for the individual prompt files that can be run manually.
