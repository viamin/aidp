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

# Optional: specify polling interval and provider
aidp watch owner/repo --interval 60 --provider claude

# Run a single cycle (useful for CI/testing)
aidp watch owner/repo --once
```

**How it works:**

1. **Planning** (`aidp-plan` label): When this label is added to an issue, AIDP generates an implementation plan with task breakdown and clarifying questions, posting it as a comment
2. **Building** (`aidp-build` label): Once the plan is approved, this label triggers autonomous implementation via work loops, creating a branch and pull request

**Safety Features:**

- **Public Repository Protection**: Disabled by default for public repos (require explicit opt-in)
- **Author Allowlist**: Restrict automation to trusted GitHub users only
- **Container Requirement**: Optionally require sandboxed environment
- **Force Override**: `--force` flag to bypass safety checks (dangerous!)

**Configuration:**

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

See [Watch Mode Guide](docs/FULLY_AUTOMATIC_MODE.md) and [Watch Mode Safety](docs/WATCH_MODE_SAFETY.md) for complete documentation.

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

### System Commands

```bash
# Show system status
aidp status

# Provider health dashboard
aidp providers

# Harness state management
aidp harness status
aidp harness reset

# Configuration
aidp --setup-config             # Re-run setup wizard
aidp --help                     # Show all commands
aidp --version                  # Show version
```

## AI Providers

AIDP intelligently manages multiple providers with automatic switching:

- **Anthropic Claude CLI** - Primary provider for complex analysis and code generation
- **Codex CLI** - OpenAI's Codex command-line interface for code generation
- **Cursor CLI** - IDE-integrated provider for code-specific tasks
- **Gemini CLI** - Google's Gemini command-line interface for general tasks
- **GitHub Copilot CLI** - GitHub's AI pair programmer command-line interface
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

### Environment Variables

```bash
# Set API keys
export AIDP_CLAUDE_API_KEY="your-claude-api-key"
export AIDP_GEMINI_API_KEY="your-gemini-api-key"
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
