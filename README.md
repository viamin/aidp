# AI Dev Pipeline (aidp) - Ruby Gem

A portable CLI that automates AI development workflows from idea to implementation using your existing IDE assistants. Features autonomous work loops, background execution, and comprehensive progress tracking.

## Quick Start

```bash
# Install the gem
gem install aidp

# Navigate to your project
cd /your/project

# Analyze and bootstrap project docs
aidp init
# Creates LLM_STYLE_GUIDE.md, PROJECT_ANALYSIS.md, CODE_QUALITY_PLAN.md

# Start an interactive workflow
aidp execute

# Or run in background
aidp execute --background
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

## Core Features

### Work Loops

AIDP implements **work loops** - an iterative execution pattern where AI agents autonomously work on tasks until completion, with automatic testing and linting feedback.

- **Iterative refinement**: Agent works in loops until task is 100% complete
- **Self-management**: Agent edits PROMPT.md to track its own progress
- **Automatic validation**: Tests and linters run after each iteration
- **Self-correction**: Only failures are fed back for the next iteration

See [Work Loops Guide](docs/WORK_LOOPS_GUIDE.md) for details.

### Background Execution

Run workflows in the background while monitoring progress from separate terminals:

```bash
# Start in background
aidp execute --background
✓ Started background job: 20251005_235912_a1b2c3d4

# Monitor progress
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

## Command Reference

### Execution Modes

```bash
# Execute mode - Build new features
aidp execute                    # Interactive workflow selection
aidp execute --background       # Run in background
aidp execute --background --follow  # Start and follow logs

# Analyze mode - Analyze codebase
aidp analyze                    # Interactive analysis
aidp analyze --background       # Background analysis
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
- **macOS UI** - macOS-specific UI automation provider
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
# Start execute mode
aidp execute

# Select workflow type (e.g., "Full PRD to Implementation")
# Answer any questions interactively
# Review generated files (PRD, architecture, etc.)
# Workflow runs automatically with harness managing retries
```

### Background Workflow with Monitoring

```bash
# Terminal 1: Start background execution
aidp execute --background
✓ Started background job: 20251005_235912_a1b2c3d4

# Terminal 2: Watch progress in real-time
aidp checkpoint summary --watch

# Terminal 3: Monitor job status
aidp jobs status 20251005_235912_a1b2c3d4 --follow

# Later: Check final results
aidp checkpoint summary
aidp jobs logs 20251005_235912_a1b2c3d4 --tail
```

### Quick Analysis

```bash
# Run analysis in background
aidp analyze --background

# Check progress
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
