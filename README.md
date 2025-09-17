# AI Dev Pipeline (aidp) - Ruby Gem

A portable CLI that automates a complete AI development workflow from idea to implementation using your existing IDE assistants. Now with **Enhanced TUI** and **Harness Mode** - autonomous execution with a rich terminal interface that runs complete workflows automatically with intelligent provider management and error recovery.

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

## 🚀 New: Enhanced TUI with Harness Mode

AIDP now features **Enhanced TUI** and **Harness Mode** - a rich terminal interface with autonomous execution that transforms AIDP from a step-by-step tool into an intelligent development assistant. The enhanced TUI provides beautiful, interactive terminal components while the harness runs complete workflows automatically, handling rate limits, user feedback, error recovery, and provider switching.

### Enhanced TUI Features

- **🎨 Rich Terminal Interface**: Beautiful CLI UI components with progress bars, spinners, and frames
- **📋 Interactive Navigation**: Hierarchical menu system with breadcrumb navigation
- **⌨️ Keyboard Shortcuts**: Full keyboard navigation and control
- **📊 Real-time Dashboards**: Live monitoring of jobs, progress, and system status
- **🔄 Workflow Control**: Pause, resume, cancel, and stop workflows with visual feedback
- **💬 Smart Question Collection**: Interactive prompts with validation and error handling

### Harness Features

- **🔄 Autonomous Execution**: Runs complete workflows from start to finish
- **🧠 Intelligent Provider Management**: Automatic switching between Claude, Gemini, and Cursor
- **⚡ Smart Error Recovery**: Handles rate limits, timeouts, and failures automatically
- **💬 Interactive User Input**: Collects feedback when agents need clarification
- **📊 Real-time Monitoring**: Live status updates and progress tracking
- **🔧 Configurable**: Customize behavior through `aidp.yml` configuration

### Quick Harness Start

```bash
# Start the interactive TUI (default)
aidp start

# Run complete analysis workflow (redirects to TUI)
aidp analyze

# Run complete development workflow (redirects to TUI)
aidp execute

# Check harness status
aidp harness status

# Run code analysis with tree-sitter
aidp analyze-code
```

## 🎨 Enhanced TUI Commands

The new Terminal User Interface provides rich, interactive terminal components for a better user experience:

### Harness Management

```bash
# Reset harness state
aidp harness reset --mode analyze
aidp harness reset --mode execute

# Show detailed harness status
aidp harness status
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

## User Workflow

The gem automates a complete development pipeline with **human-in-the-loop gates** at key decision points. Here's the simplest workflow:

### 1. Start the TUI

```bash
cd /your/project
aidp start                    # Start the interactive TUI
```

### 2. Choose Your Mode

The TUI will guide you through choosing between:

1. **Analyze Mode** - Analyze your codebase for insights and recommendations
2. **Execute Mode** - Build new features with guided development workflow

### 3. Follow the Interactive Workflow

The TUI will guide you through each step, providing:

- **Interactive Prompts** - Answer questions and provide input
- **Real-time Progress** - See your progress through the workflow
- **Visual Feedback** - Beautiful UI components show status and progress
- **Keyboard Navigation** - Use arrow keys and shortcuts to navigate

### 4. Complete the Workflow

The pipeline includes 15 steps total:

- **Gates**: PRD, Architecture, Tasks, Implementation (require approval)
- **Auto**: NFRs, ADRs, Domains, Contracts, Threat Model, Test Plan, Scaffolding, Static Analysis, Observability, Delivery, Docs Portal, Post-Release

## Key Commands

### Harness Mode Commands

```bash
aidp start                    # Start the interactive TUI (default)
aidp analyze                  # Run complete analysis workflow (redirects to TUI)
aidp execute                  # Run complete development workflow (redirects to TUI)
aidp harness status          # Show detailed harness status and configuration
aidp harness reset --mode=analyze  # Reset harness state for analyze mode
aidp harness reset --mode=execute  # Reset harness state for execute mode
```

### Available Commands

```bash
aidp start                   # Start the interactive TUI (default)
aidp analyze                 # Run analyze mode (redirects to TUI)
aidp execute                 # Run execute mode (redirects to TUI)
aidp analyze-code           # Run code analysis with tree-sitter
aidp harness status         # Show harness status
aidp harness reset          # Reset harness state
aidp version                # Show version information
aidp help                   # Show help information
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
aidp analyze-code

# Analyze specific languages
aidp analyze-code --langs ruby,javascript,typescript

# Use multiple threads for faster analysis
aidp analyze-code --threads 8

# Specify custom KB directory
aidp analyze-code --kb-dir .aidp/custom-kb
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
- **Ruby gems** - All required gems are specified in `aidp.gemspec` and installed via `bundle install`

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
