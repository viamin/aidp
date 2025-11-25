# AIDP Documentation

Complete documentation for the AI Dev Pipeline (AIDP) project.

## Quick Start

New to AIDP? Start here:

1. **[CLI User Guide](CLI_USER_GUIDE.md)** - Complete guide to using AIDP CLI commands
2. **[Skills Quickstart](SKILLS_QUICKSTART.md)** - Get started with skills in 5 minutes
3. **[Setup Wizard](SETUP_WIZARD.md)** - Initial configuration guide

## User Guides

### Core Features

| Document | Description |
| ---------- | ------------- |
| [CLI User Guide](CLI_USER_GUIDE.md) | Complete CLI command reference with examples |
| [Copilot Mode](COPILOT_MODE_FLOW.md) | Interactive AI assistant mode |
| [Work Loops Guide](WORK_LOOPS_GUIDE.md) | Understanding iterative execution |
| [Interactive REPL](INTERACTIVE_REPL.md) | Live control during work loops |
| [Background Jobs](CLI_USER_GUIDE.md#background-jobs) | Running workflows in background |

### Skills System

| Document | Description |
| ---------- | ------------- |
| [Skills User Guide](SKILLS_USER_GUIDE.md) | Complete skills documentation |
| [Skills Quickstart](SKILLS_QUICKSTART.md) | Quick 5-minute skills introduction |
| [Skill Authoring Wizard](SKILL_AUTHORING_WIZARD_DESIGN.md) | Interactive skill creation |

### Modes & Workflows

| Document | Description |
| ---------- | ------------- |
| [Init Mode](INIT_MODE.md) | High-level project analysis |
| [Fully Automatic Mode](FULLY_AUTOMATIC_MODE.md) | Autonomous execution |
| [Non-Interactive Mode](NON_INTERACTIVE_MODE.md) | Headless/CI execution |
| [Watch Mode Safety](WATCH_MODE_SAFETY.md) | File watching safeguards |
| [Read-Only GitHub Mode](READ_ONLY_GITHUB_MODE.md) | Safe GitHub operations |

### Advanced Features

| Document | Description |
| ---------- | ------------- |
| [Thinking Depth](THINKING_DEPTH.md) | Dynamic model tier selection |
| [Workstreams](WORKSTREAMS.md) | Parallel workflow execution |
| [Prompt Optimization](PROMPT_OPTIMIZATION.md) | Context management |
| [Persistent Tasklist](PERSISTENT_TASKLIST.md) | Cross-session task tracking |
| [Streaming Guide](STREAMING_GUIDE.md) | Real-time output streaming |

## Configuration

| Document | Description |
| ---------- | ------------- |
| [Configuration](CONFIGURATION.md) | Complete configuration reference |
| [Setup Wizard](SETUP_WIZARD.md) | Interactive setup |
| [Provider Adapter Guide](PROVIDER_ADAPTER_GUIDE.md) | Adding new AI providers |
| [Optional Tools](OPTIONAL_TOOLS.md) | Additional tool configuration |
| [Key Bindings](KEY_BINDINGS.md) | Keyboard shortcuts |

## Developer Documentation

### Architecture & Design

| Document | Description |
| ---------- | ------------- |
| [AIDP Capabilities](AIDP_CAPABILITIES.md) | System capabilities overview |
| [Worktree PR Change Requests](WORKTREE_PR_CHANGE_REQUESTS.md) | Worktree-based PR change workflow |
| [Metadata Tool Discovery](METADATA_TOOL_DISCOVERY.md) | Metadata-driven skill/persona/template discovery |
| [Concurrency Patterns](CONCURRENCY_PATTERNS.md) | Thread safety patterns |
| [Safety Guards](SAFETY_GUARDS.md) | Safety mechanisms |
| [Work Loop Alignment PRD](WORK_LOOP_ALIGNMENT_PRD.md) | Work loop design |

### Code Quality & Style

| Document | Description |
| ---------- | ------------- |
| [Style Guide](STYLE_GUIDE.md) | Comprehensive style guide (73KB) |
| [LLM Style Guide](LLM_STYLE_GUIDE.md) | AI-optimized style guide |
| [Tree-sitter Analysis](tree-sitter-analysis.md) | Code analysis with tree-sitter |
| [Mocking Audit Report](MOCKING_AUDIT_REPORT.md) | Testing quality assessment |
| [Coverage Baseline](COVERAGE_BASELINE_IN_RELEASES.md) | Test coverage tracking |

### Integration & Tooling

| Document | Description |
| ---------- | ------------- |
| [Development Container](DEVELOPMENT_CONTAINER.md) | Devcontainer integration |
| [Devcontainer Auto Restart](DEVCONTAINER_AUTO_RESTART.md) | Auto-restart configuration |
| [PRD: Devcontainer Integration](PRD_DEVCONTAINER_INTEGRATION.md) | Devcontainer requirements |
| [GitHub API Signed Commits](GITHUB_API_SIGNED_COMMITS.md) | Commit signing with GitHub API |
| [Release Please Signed Commits](RELEASE_PLEASE_SIGNED_COMMITS.md) | Release automation |

## Reference Documentation

### Command References

| Document | Description |
| ---------- | ------------- |
| [CLI User Guide](CLI_USER_GUIDE.md) | All CLI commands |
| [REPL Reference](REPL_REFERENCE.md) | REPL macro commands |
| [Interactive REPL](INTERACTIVE_REPL.md) | Work loop REPL commands |
| [Jobs Command Usage](jobs-command-usage.md) | Background job management |
| [Analyze Mode Usage](analyze-mode-usage.md) | Analysis workflow commands |

### Migration & Updates

| Document | Description |
| ---------- | ------------- |
| [Migration Guide](MIGRATION_GUIDE.md) | Version migration instructions |
| [Follow-Up Opportunities](FOLLOW_UP_OPPORTUNITIES.md) | Planned enhancements |
| [Logging Improvements](LOGGING_IMPROVEMENTS.md) | Logging system changes |
| [Memory Integration](MEMORY_INTEGRATION.md) | Memory/context management |

### Troubleshooting

| Document | Description |
| ---------- | ------------- |
| [CLI User Guide: Troubleshooting](CLI_USER_GUIDE.md#troubleshooting) | Common issues & solutions |
| [Debug Guide](DEBUG_GUIDE.md) | Debugging AIDP issues |
| [Job Troubleshooting](job-troubleshooting.md) | Background job issues |

### Specialized Topics

| Document | Description |
| ---------- | ------------- |
| [Ports](PORTS.md) | Port configuration |
| [Copilot Mode Testing](COPILOT_MODE_TESTING_TODO.md) | Test coverage tracking |

## Devcontainer Documentation

The `devcontainer/` subfolder contains devcontainer integration documentation:

```bash
docs/devcontainer/
├── ARCHITECTURE.md           # Devcontainer architecture
├── CONFIGURATION.md          # Configuration options
├── FINAL_STATUS.md          # Integration status
├── HANDOFF_CHECKLIST.md     # Implementation checklist
├── PHASE_1_SUMMARY.md       # Phase 1 completion
└── SESSION_SUMMARY.md       # Implementation summary
```

## Documentation Organization

### By Audience

**End Users** (start here):

- CLI User Guide
- Skills Quickstart
- Work Loops Guide
- Configuration

**Power Users**:

- Interactive REPL
- Thinking Depth
- Workstreams
- Prompt Optimization

**Developers**:

- Implementation Guide
- Provider Adapter Guide
- Style Guide
- Architecture documents

### By Topic

**Getting Started**: Setup Wizard, Skills Quickstart, CLI User Guide
**Daily Usage**: Copilot Mode, Work Loops, Skills
**Advanced**: Thinking Depth, Workstreams, Prompt Optimization
**Configuration**: Configuration, Setup Wizard, Provider Adapter
**Development**: Implementation Guide, Style Guide, Architecture
**Troubleshooting**: Debug Guide, Job Troubleshooting, Migration Guide

## Document Formats

All documentation follows a consistent format:

### User Guides

```markdown
# Title
## Overview
## Getting Started
## Usage
## Configuration
## Troubleshooting
```

### Technical Documentation

```markdown
# Title
## Overview
## Architecture
## Implementation
## Examples
## References
```

## Contributing to Documentation

When adding or updating documentation:

1. **Follow the standard format** - Use the templates above
2. **Update this README** - Add new documents to the appropriate section
3. **Keep it current** - Update docs when features change
4. **Cross-reference** - Link to related documents
5. **Test examples** - Ensure all code examples work

## Getting Help

- **General Help**: [CLI User Guide](CLI_USER_GUIDE.md)
- **Configuration Issues**: [Configuration](CONFIGURATION.md)
- **Troubleshooting**: [Debug Guide](DEBUG_GUIDE.md)
- **GitHub Issues**: Report bugs and request features at <https://github.com/viamin/aidp/issues>

## Documentation Stats

- **Total Documents**: 48 markdown files
- **User Guides**: 15+ guides
- **Developer Docs**: 10+ technical documents
- **Reference Docs**: 10+ command references
- **Last Updated**: 2025-11-11

---

**Quick Links**: [CLI Guide](CLI_USER_GUIDE.md) | [Skills](SKILLS_QUICKSTART.md) | [Work Loops](WORK_LOOPS_GUIDE.md) | [Configuration](CONFIGURATION.md) | [REPL](INTERACTIVE_REPL.md)
