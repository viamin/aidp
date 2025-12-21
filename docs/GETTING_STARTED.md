# Getting Started with AIDP

Welcome to AI Dev Pipeline (AIDP). This guide will help you get up and running quickly.

## Prerequisites

- Ruby 3.1+ installed (via [mise](https://mise.jdx.dev/) recommended)
- Git installed and configured
- An AI provider API key (Claude, Gemini, etc.) or IDE assistant (Cursor, Copilot)

## Installation

```bash
# Install the gem
gem install aidp

# Navigate to your project
cd /your/project
```

## Quick Start Paths

Choose the path that matches your goal:

### Path 1: Interactive Mode (Recommended for New Users)

Start with the interactive copilot mode for AI-guided development:

```bash
# Launch interactive mode
aidp

# Follow the prompts to:
# - Configure your AI provider
# - Analyze your project
# - Start developing with AI assistance
```

**Best for**: Learning AIDP, exploratory development, getting AI guidance on approach.

### Path 2: Configuration First

Set up your project configuration before diving in:

```bash
# Launch the interactive configuration wizard
aidp config --interactive

# This configures:
# - AI providers and API keys
# - Test and lint commands
# - Work loop settings
# - Optional devcontainer setup
```

After configuration, run `aidp` to start working.

**Best for**: Teams, CI/CD setup, specific provider requirements.

### Path 3: Watch Mode (Automated GitHub Workflows)

Automate your GitHub workflow with label-based triggers:

```bash
# Start monitoring a repository
aidp watch owner/repo

# AIDP will:
# - Monitor issues with aidp-* labels
# - Generate implementation plans
# - Create branches and PRs automatically
```

**Best for**: Automated issue resolution, CI integration, background automation.

## First-Time Setup Wizard

On first run in a new project, AIDP launches a setup wizard offering:

1. **Minimal** - Single provider (Cursor), get started fast
2. **Development** - Multiple providers, safe defaults
3. **Production** - Full features, review before committing
4. **Full Example** - Verbose documented configuration
5. **Custom** - Interactive prompts for all settings

Re-run anytime with:

```bash
aidp --setup-config
```

## Core Concepts

### Work Loops

AIDP uses iterative **work loops** where the AI:

1. Receives a task or issue
2. Makes code changes
3. Runs tests and linters
4. Fixes failures automatically
5. Repeats until complete

See [Work Loops Guide](how-to/WORK_LOOPS_GUIDE.md) for details.

### AI Providers

AIDP supports multiple providers with automatic failover:

- **Claude** - Anthropic's Claude CLI
- **Cursor** - IDE-integrated provider
- **Gemini** - Google's Gemini CLI
- **GitHub Copilot** - GitHub's AI pair programmer
- **Kilocode** - Modern AI coding assistant
- **OpenCode** - Open-source alternative

Configure in your `aidp.yml` or via the setup wizard.

### Labels (Watch Mode)

AIDP uses GitHub labels to trigger actions:

| Label | Action |
| ----- | ------ |
| `aidp-plan` | Generate implementation plan |
| `aidp-build` | Start implementation |
| `aidp-review` | Run code review on PR |
| `aidp-fix-ci` | Auto-fix failing CI checks |

See [Watch Mode Guide](how-to/FULLY_AUTOMATIC_MODE.md) for the complete workflow.

## Common Commands

```bash
# Interactive mode (default)
aidp

# Project analysis and documentation
aidp init

# Configuration
aidp config --interactive

# Watch mode
aidp watch owner/repo

# Job management
aidp jobs list
aidp jobs status <job_id>

# Progress tracking
aidp checkpoint summary

# Workstreams (parallel tasks)
aidp ws new feature-branch
aidp ws list
```

## Next Steps

Depending on your needs:

### Tutorials

- [Skills Quickstart](tutorials/SKILLS_QUICKSTART.md) - Create custom AI skills in 10 minutes
- [Setup Wizard](tutorials/SETUP_WIZARD.md) - Deep dive into configuration options

### How-To Guides

- [CLI User Guide](how-to/CLI_USER_GUIDE.md) - Complete command reference
- [Work Loops](how-to/WORK_LOOPS_GUIDE.md) - Master iterative AI workflows
- [Watch Mode](how-to/FULLY_AUTOMATIC_MODE.md) - Automate GitHub workflows
- [Workstreams](how-to/WORKSTREAMS.md) - Parallel task execution

### Configuration

- [Configuration Reference](reference/CONFIGURATION.md) - All `aidp.yml` options
- [REPL Reference](reference/REPL_REFERENCE.md) - Interactive control commands

## Getting Help

- **CLI help**: `aidp --help`
- **Command help**: `aidp <command> --help`
- **Debug mode**: `AIDP_DEBUG=1 aidp`
- **Documentation**: See [README.md](README.md) for the full documentation index
- **Issues**: [GitHub Issues](https://github.com/viamin/aidp/issues)

---

**Quick Links**: [CLI Guide](how-to/CLI_USER_GUIDE.md) | [Configuration](reference/CONFIGURATION.md) | [Work Loops](how-to/WORK_LOOPS_GUIDE.md) | [Watch Mode](how-to/FULLY_AUTOMATIC_MODE.md)
