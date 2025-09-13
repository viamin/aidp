# AI Dev Pipeline (aidp) - Ruby Gem

A portable CLI that automates a complete AI development workflow from idea to implementation using your existing IDE assistants. Now with **Harness Mode** - autonomous execution that runs complete workflows automatically with intelligent provider management and error recovery.

## Quick Start

```bash
# Install the gem
gem install aidp

# Navigate to your project
cd /your/project

# Start the workflow (now with autonomous harness mode)
aidp execute

# Or run analysis
aidp analyze
```

## 🚀 New: Harness Mode

AIDP now features **Harness Mode** - an autonomous execution system that transforms AIDP from a step-by-step tool into an intelligent development assistant. The harness runs complete workflows automatically, handling rate limits, user feedback, error recovery, and provider switching.

### Harness Features

- **🔄 Autonomous Execution**: Runs complete workflows from start to finish
- **🧠 Intelligent Provider Management**: Automatic switching between Claude, Gemini, and Cursor
- **⚡ Smart Error Recovery**: Handles rate limits, timeouts, and failures automatically
- **💬 Interactive User Input**: Collects feedback when agents need clarification
- **📊 Real-time Monitoring**: Live status updates and progress tracking
- **🔧 Configurable**: Customize behavior through `aidp.yml` configuration

### Quick Harness Start

```bash
# Run complete analysis workflow automatically
aidp analyze

# Run complete development workflow automatically
aidp execute

# Check harness status
aidp harness status

# View real-time progress
aidp status
```

### Harness Configuration

Create an `aidp.yml` file to customize harness behavior:

```yaml
# aidp.yml
harness:
  enabled: true
  max_retries: 2
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]

providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
  gemini:
    type: "api"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
  cursor:
    type: "package"
```

### Traditional Mode Still Available

You can still run individual steps manually:

```bash
# Traditional step-by-step mode
aidp execute next
aidp analyze 01_REPOSITORY_ANALYSIS
```

## User Workflow

The gem automates a complete development pipeline with **human-in-the-loop gates** at key decision points. Here's the simplest workflow:

### 1. Start Your Project

```bash
cd /your/project
aidp status                   # Check current progress
aidp execute next             # Run the next pending step
```

### 2. Handle Gate Steps

When you reach a **gate step** (PRD, Architecture, Tasks, Implementation), the AI will:

1. **Generate questions** in a file (e.g., `PRD_QUESTIONS.md`) if it needs more information
2. **Create the main output** (e.g., `docs/PRD.md`)
3. **Wait for your approval** before proceeding

**Your actions at gates:**

```bash
# Review the generated files
cat PRD_QUESTIONS.md          # Check if AI needs more information
cat docs/PRD.md              # Review the output

# If PRD_QUESTIONS.md exists, answer the questions:
# Edit the questions file directly with your answers
nano PRD_QUESTIONS.md         # Add your answers below each question

# Re-run the step to use your answers
aidp execute prd              # AI will read your answers and complete the step

# Once satisfied with the output, approve and continue
aidp approve current          # Mark the step complete
aidp execute next             # Continue to next step
```

### 3. Continue the Pipeline

For non-gate steps, the AI runs automatically:

```bash
aidp execute next             # Run next step automatically
aidp status                   # Check progress
```

### 4. Complete the Workflow

The pipeline includes 15 steps total:

- **Gates**: PRD, Architecture, Tasks, Implementation (require approval)
- **Auto**: NFRs, ADRs, Domains, Contracts, Threat Model, Test Plan, Scaffolding, Static Analysis, Observability, Delivery, Docs Portal, Post-Release

## Key Commands

### Harness Mode Commands

```bash
aidp execute                  # Run complete development workflow automatically
aidp analyze                  # Run complete analysis workflow automatically
aidp harness status           # Show detailed harness status and configuration
aidp harness reset --mode=analyze  # Reset harness state for analyze mode
aidp harness reset --mode=execute  # Reset harness state for execute mode
aidp config show              # Show current configuration
aidp config validate          # Validate configuration file
```

### Traditional Mode Commands

```bash
aidp status                   # Show progress of all steps
aidp execute next             # Run next pending step
aidp approve current          # Approve current gate step
aidp jobs                     # Monitor background jobs (real-time)
aidp detect                   # See which AI provider will be used
aidp execute <step>           # Run specific step (e.g., prd, arch, tasks)
aidp approve <step>           # Approve specific step
aidp reset                    # Reset all progress (start over)
```

### Universal Commands

```bash
aidp status                   # Show progress of all steps (works in both modes)
aidp jobs                     # Monitor background jobs (real-time)
aidp version                  # Show version information
aidp help                     # Show help information
```

## AI Providers

### Harness Mode (Recommended)

In harness mode, AIDP intelligently manages multiple providers with automatic switching:

- **Claude API** - Primary provider for complex analysis and code generation
- **Gemini API** - Cost-effective fallback for general tasks
- **Cursor CLI** - IDE-integrated provider for code-specific tasks

The harness automatically switches providers when:

- Rate limits are hit
- Providers fail or timeout
- Cost limits are reached
- Performance optimization is needed

### Traditional Mode

The gem automatically detects and uses the best available AI provider:

- **Cursor CLI** (`cursor-agent`) - Preferred
- **Claude CLI** (`claude`/`claude-code`) - Fallback
- **Gemini CLI** (`gemini`/`gemini-cli`) - Fallback

### Provider Configuration

#### Harness Mode Configuration

```yaml
# aidp.yml
harness:
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]

providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
  gemini:
    type: "api"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
  cursor:
    type: "package"
```

#### Environment Variables

```bash
# Set API keys for harness mode
export AIDP_CLAUDE_API_KEY="your-claude-api-key"
export AIDP_GEMINI_API_KEY="your-gemini-api-key"

# Traditional mode override
AIDP_PROVIDER=anthropic aidp execute next
AIDP_LLM_CMD=/usr/local/bin/claude aidp execute next
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

### Tree-sitter Analysis Commands

```bash
# Run Tree-sitter static analysis
aidp analyze code

# Analyze specific languages
aidp analyze code --langs ruby,javascript,typescript

# Use multiple threads for faster analysis
aidp analyze code --threads 8

# Rebuild knowledge base from scratch
aidp analyze code --rebuild

# Specify custom KB directory
aidp analyze code --kb-dir .aidp/custom-kb

# Inspect generated knowledge base
aidp kb show

# Show specific KB data
aidp kb show symbols
aidp kb show imports
aidp kb show seams

# Generate dependency graphs
aidp kb graph imports
aidp kb graph calls
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

## Background Jobs

AIDP uses background jobs to handle all AI provider executions, providing better reliability and real-time monitoring capabilities.

### Job Monitoring

Monitor running and completed jobs in real-time:

```bash
aidp jobs                     # Show job status with real-time updates
```

The jobs view displays:

- **Running jobs** with live progress updates
- **Queued jobs** waiting to be processed
- **Completed jobs** with execution results
- **Failed jobs** with error details

### Job Controls

From the jobs view, you can:

- **Retry failed jobs** by pressing `r` on a failed job
- **View job details** by pressing `d` on any job
- **Exit monitoring** by pressing `q`

### Job Persistence

- Jobs persist across CLI restarts
- Job history is preserved for analysis
- Failed jobs can be retried at any time
- All job metadata and logs are stored

### Database Setup

AIDP uses PostgreSQL for job management. Ensure PostgreSQL is installed and running:

```bash
# macOS (using Homebrew)
brew install postgresql
brew services start postgresql

# Ubuntu/Debian
sudo apt-get install postgresql postgresql-contrib
sudo systemctl start postgresql

# The database will be created automatically on first use
```

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

## Debug and Logging

```bash
# Enable debug output to see AI provider communication
AIDP_DEBUG=1 aidp execute next

# Log to a file for debugging
AIDP_LOG_FILE=aidp.log aidp execute next

# Combine both for full debugging
AIDP_DEBUG=1 AIDP_LOG_FILE=aidp.log aidp execute next
```

## Workflow Example

Here's a typical session:

```bash
# 1. Start the workflow
aidp execute next
# → Creates docs/PRD.md and PRD_QUESTIONS.md

# 2. Monitor job progress (optional)
aidp jobs
# → Shows real-time job status and progress

# 3. Review the questions (if any)
cat PRD_QUESTIONS.md
# → If questions exist, edit the file with your answers, then re-run

# 4. Review the PRD
cat docs/PRD.md
# → Edit if needed

# 5. Approve and continue
aidp approve current
aidp execute next
# → Creates docs/NFRs.md automatically

# 6. Continue through gates
aidp execute next
# → Creates docs/Architecture.md and ARCH_QUESTIONS.md
# → Repeat review/approve cycle
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
- **PostgreSQL** - Database for job management
- **Ruby gems** - All required gems are specified in `aidp.gemspec` and installed via `bundle install`

Optional gems with fallbacks:

- **`concurrent-ruby`** - Parallel processing (fallback to basic threading if not available)
- **`tty-table`** - Table rendering (fallback to basic ASCII tables if not available)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and conventional commit guidelines.

## Pipeline Steps

The gem automates a complete 15-step development pipeline:

### Gate Steps (Require Approval)

- **PRD** → Product Requirements Document (`docs/PRD.md`)
- **Architecture** → System architecture and ADRs (`docs/Architecture.md`)
- **Tasks** → Implementation tasks and backlog (`tasks/backlog.yaml`)
- **Implementation** → Implementation strategy and guidance (`docs/ImplementationGuide.md`)

### Automatic Steps

- **NFRs** → Non-Functional Requirements (`docs/NFRs.md`)
- **ADRs** → Architecture Decision Records (`docs/adr/`)
- **Domains** → Domain decomposition (`docs/DomainCharters/`)
- **Contracts** → API/Event contracts (`contracts/`)
- **Threat Model** → Security analysis (`docs/ThreatModel.md`)
- **Test Plan** → Testing strategy (`docs/TestPlan.md`)
- **Scaffolding** → Project structure guidance (`docs/ScaffoldingGuide.md`)
- **Static Analysis** → Code quality tools and Tree-sitter analysis (`docs/StaticAnalysis.md`, `.aidp/kb/`)
- **Observability** → Monitoring and SLOs (`docs/Observability.md`)
- **Delivery** → Deployment strategy (`docs/DeliveryPlan.md`)
- **Docs Portal** → Documentation portal (`docs/DocsPortalPlan.md`)
- **Post-Release** → Post-release analysis (`docs/PostReleaseReport.md`)

## Harness Documentation

For detailed information about harness mode:

- **[Harness Usage Guide](docs/harness-usage.md)** - Complete guide to using harness mode
- **[Configuration Guide](docs/harness-configuration.md)** - Detailed configuration options and examples
- **[Troubleshooting Guide](docs/harness-troubleshooting.md)** - Common issues and solutions
- **[Migration Guide](docs/harness-migration.md)** - Migrating from step-by-step to harness mode

## Manual Workflow (Alternative)

The gem packages markdown prompts that can also be used directly with Cursor or any LLM. See the `templates/` directory for the individual prompt files that can be run manually.
