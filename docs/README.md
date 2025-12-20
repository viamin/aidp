# AIDP Documentation

Complete documentation for the AI Dev Pipeline (AIDP) project, organized using the [Diataxis framework](https://diataxis.fr/).

## Start Here

**New to AIDP?** Start with [GETTING_STARTED.md](GETTING_STARTED.md) for quick setup and core concepts.

---

## Documentation Structure

This documentation is organized into four categories:

| Category | Purpose | When to Use |
| -------- | ------- | ----------- |
| [Tutorials](tutorials/) | Learning-oriented lessons | Learning AIDP for the first time |
| [How-To Guides](how-to/) | Goal-oriented guides | Solving a specific problem |
| [Explanation](explanation/) | Understanding-oriented | Learning why things work |
| [Reference](reference/) | Information-oriented | Looking up technical details |

---

## Tutorials

Step-by-step lessons that take you through a specific workflow from start to finish.

| Tutorial | Description | Time |
| -------- | ----------- | ---- |
| [Skills Quickstart](tutorials/SKILLS_QUICKSTART.md) | Create custom AI skills | 10 min |
| [Setup Wizard](tutorials/SETUP_WIZARD.md) | Configure AIDP for your project | 5 min |

---

## How-To Guides

Practical guides for accomplishing specific tasks.

### Core Workflows

| Guide | Description |
| ----- | ----------- |
| [CLI User Guide](how-to/CLI_USER_GUIDE.md) | Complete CLI command reference |
| [Work Loops](how-to/WORK_LOOPS_GUIDE.md) | Iterative AI execution with auto-validation |
| [Copilot Mode](how-to/COPILOT_MODE_FLOW.md) | Interactive AI-guided development |
| [Interactive REPL](how-to/INTERACTIVE_REPL.md) | Live control during work loops |

### Automation & CI

| Guide | Description |
| ----- | ----------- |
| [Watch Mode](how-to/FULLY_AUTOMATIC_MODE.md) | Automated GitHub issue monitoring |
| [Watch Mode Labels](how-to/WATCH_MODE.md) | Label-based workflow automation |
| [Non-Interactive Mode](how-to/NON_INTERACTIVE_MODE.md) | Headless/CI execution |
| [PR Automation](how-to/PR_AUTOMATION.md) | Automated PR workflows |
| [PR Change Requests](how-to/PR_CHANGE_REQUESTS.md) | Handling PR change requests |
| [Worktree PR Changes](how-to/WORKTREE_PR_CHANGE_REQUESTS.md) | Worktree-based PR workflows |

### Development Modes

| Guide | Description |
| ----- | ----------- |
| [Init Mode](how-to/INIT_MODE.md) | High-level project analysis |
| [Agile Mode](how-to/AGILE_MODE_GUIDE.md) | Iterative development with user feedback |
| [Waterfall Planning](how-to/WATERFALL_PLANNING_MODE.md) | Comprehensive project planning |
| [Workstreams](how-to/WORKSTREAMS.md) | Parallel task execution with git worktrees |

### Configuration & Setup

| Guide | Description |
| ----- | ----------- |
| [Development Container](how-to/DEVELOPMENT_CONTAINER.md) | Devcontainer integration |
| [Devcontainer Auto Restart](how-to/DEVCONTAINER_AUTO_RESTART.md) | Auto-restart configuration |
| [Firewall Configuration](how-to/FIREWALL_CONFIGURATION.md) | Network security setup |
| [Provider Adapter Guide](how-to/PROVIDER_ADAPTER_GUIDE.md) | Adding new AI providers |

### GitHub Integration

| Guide | Description |
| ----- | ----------- |
| [GitHub Projects](how-to/GITHUB_PROJECTS.md) | GitHub Projects V2 integration |
| [GitHub API Signed Commits](how-to/GITHUB_API_SIGNED_COMMITS.md) | Commit signing with GitHub API |
| [Release Please Signed Commits](how-to/RELEASE_PLEASE_SIGNED_COMMITS.md) | Release automation |

### Skills & Customization

| Guide | Description |
| ----- | ----------- |
| [Skills User Guide](how-to/SKILLS_USER_GUIDE.md) | Complete skills documentation |

### Troubleshooting

| Guide | Description |
| ----- | ----------- |
| [Debug Guide](how-to/DEBUG_GUIDE.md) | Debugging AIDP issues |
| [Job Troubleshooting](how-to/JOB_TROUBLESHOOTING.md) | Background job issues |
| [Jobs Command Usage](how-to/JOBS_COMMAND_USAGE.md) | Job management commands |
| [Analyze Mode Usage](how-to/ANALYZE_MODE_USAGE.md) | Analysis workflow usage |
| [Migration Guide](how-to/MIGRATION_GUIDE.md) | Version migration instructions |

---

## Explanation

Conceptual documentation that explains how and why things work.

### Architecture & Design

| Document | Description |
| -------- | ----------- |
| [AIDP Capabilities](explanation/AIDP_CAPABILITIES.md) | System capabilities overview |
| [AI-Generated Determinism](explanation/AI_GENERATED_DETERMINISM.md) | AGD pattern for AI-generated code |
| [Concurrency Patterns](explanation/CONCURRENCY_PATTERNS.md) | Thread safety patterns |
| [Memory Integration](explanation/MEMORY_INTEGRATION.md) | Memory/context management |

### Security & Safety

| Document | Description |
| -------- | ----------- |
| [Security Framework](explanation/SECURITY_FRAMEWORK.md) | Rule of Two security model |
| [Safety Guards](explanation/SAFETY_GUARDS.md) | Safety mechanisms |
| [Watch Mode Safety](explanation/WATCH_MODE_SAFETY.md) | Watch mode security features |
| [Read-Only GitHub Mode](explanation/READ_ONLY_GITHUB_MODE.md) | Safe GitHub operations |

### AI & Models

| Document | Description |
| -------- | ----------- |
| [Thinking Depth](explanation/THINKING_DEPTH.md) | Dynamic model tier selection |
| [Prompt Optimization](explanation/PROMPT_OPTIMIZATION.md) | Context management strategies |
| [Automated Model Discovery](explanation/AUTOMATED_MODEL_DISCOVERY.md) | Model auto-detection |
| [Model Deprecation Handling](explanation/MODEL_DEPRECATION_HANDLING.md) | Handling deprecated models |

### Metadata & Discovery

| Document | Description |
| -------- | ----------- |
| [Metadata Headers](explanation/METADATA_HEADERS.md) | File metadata format |
| [Metadata Tool Discovery](explanation/METADATA_TOOL_DISCOVERY.md) | Tool discovery patterns |
| [Comment Consolidation](explanation/COMMENT_CONSOLIDATION.md) | Comment handling |

### Design Documents

| Document | Description |
| -------- | ----------- |
| [Skill Authoring Wizard Design](explanation/SKILL_AUTHORING_WIZARD_DESIGN.md) | Skill wizard architecture |
| [Work Loop Alignment PRD](explanation/WORK_LOOP_ALIGNMENT_PRD.md) | Work loop design |
| [Waterfall Planning Design](explanation/WATERFALL_PLANNING_MODE_DESIGN.md) | Planning mode design |
| [PRD Devcontainer Integration](explanation/PRD_DEVCONTAINER_INTEGRATION.md) | Devcontainer requirements |
| [GitHub Projects Implementation](explanation/GITHUB_PROJECTS_IMPLEMENTATION.md) | Projects V2 implementation |
| [Evaluations](explanation/EVALUATIONS.md) | Evaluation framework |
| [Tree-sitter Analysis](explanation/TREE_SITTER_ANALYSIS.md) | Code analysis with tree-sitter |

---

## Reference

Technical reference documentation for configuration and APIs.

| Document | Description |
| -------- | ----------- |
| [Configuration](reference/CONFIGURATION.md) | Complete `aidp.yml` reference |
| [REPL Reference](reference/REPL_REFERENCE.md) | REPL macro commands |
| [Key Bindings](reference/KEY_BINDINGS.md) | Keyboard shortcuts |
| [Labels](reference/LABELS.md) | GitHub label reference |
| [Ports](reference/PORTS.md) | Port configuration |
| [Tool Directory](reference/TOOL_DIRECTORY.md) | Available tools reference |
| [Optional Tools](reference/OPTIONAL_TOOLS.md) | Optional tool configuration |
| [Persistent Tasklist](reference/PERSISTENT_TASKLIST.md) | Cross-session task tracking |
| [Self Update](reference/SELF_UPDATE.md) | Self-update reference |

---

## Style Guides

Coding standards and style guides (maintained separately from Diataxis categories):

| Document | Description |
| -------- | ----------- |
| [LLM Style Guide](LLM_STYLE_GUIDE.md) | AI-optimized coding standards |
| [Style Guide](STYLE_GUIDE.md) | Comprehensive style guide (93KB) |

---

## Devcontainer Documentation

The `devcontainer/` subfolder contains devcontainer-specific documentation:

| Document | Description |
| -------- | ----------- |
| [README](devcontainer/README.md) | Devcontainer overview |
| [Quick Start](devcontainer/QUICK_START.md) | Getting started with devcontainer |
| [Commit Guide](devcontainer/COMMIT_GUIDE.md) | Commit conventions |
| [Final Status](devcontainer/FINAL_STATUS.md) | Integration status |
| [Handoff Checklist](devcontainer/HANDOFF_CHECKLIST.md) | Implementation checklist |
| [Phase 1 Summary](devcontainer/PHASE_1_SUMMARY.md) | Phase 1 completion |
| [Session Summary](devcontainer/SESSION_SUMMARY.md) | Implementation summary |

---

## Other Documentation

| Document | Description |
| -------- | ----------- |
| [Follow-Up Opportunities](FOLLOW_UP_OPPORTUNITIES.md) | Planned enhancements |

---

## Getting Help

- **CLI help**: `aidp --help`
- **Debug mode**: `AIDP_DEBUG=1 aidp`
- **Issues**: [GitHub Issues](https://github.com/viamin/aidp/issues)

---

**Quick Links**: [Getting Started](GETTING_STARTED.md) | [CLI Guide](how-to/CLI_USER_GUIDE.md) | [Configuration](reference/CONFIGURATION.md) | [Work Loops](how-to/WORK_LOOPS_GUIDE.md)
