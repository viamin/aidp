# Optional External Tools for AIDP

**Status**: 📋 Reference Guide

**Last Updated**: 2025-10-27

---

## Overview

AIDP provides excellent built-in features for task management, context optimization, and work loop coordination. However, some users with specific needs may benefit from external tools that complement AIDP's capabilities.

This document describes optional external tools that work well with AIDP, when to consider them, and when AIDP's built-in features are sufficient.

---

## Philosophy: Built-in First

**AIDP's design principle**: Optimize built-in features before adding external dependencies.

AIDP already provides:

- ✅ **Persistent checkpoints** - Session state across restarts
- ✅ **Prompt optimization** - 30-50% context reduction via ZFC-powered fragment selection
- ✅ **Tasklist template** - Structured task tracking within sessions
- ✅ **Recent skills** - Context about work patterns
- ✅ **Style guide fragments** - Project-specific patterns and decisions

**Only consider external tools when**:

- Built-in features don't cover your specific use case
- You're willing to accept additional complexity/maintenance
- The value clearly exceeds the cost (context overhead, setup time)

---

## Tool Evaluation Framework

Before adopting any external tool, evaluate:

### Context Budget Impact

AIDP's prompt optimization works within a 16K token budget:

- Current usage: ~9,200 tokens (57% of budget)
- Remaining budget: ~6,800 tokens (43%)

**Question**: Does this tool add tokens that provide unique value, or duplicate existing context?

### Maintenance Burden

- Installation complexity?
- Configuration requirements?
- Ongoing maintenance?
- Failure modes and degradation?

### Redundancy Check

- Does AIDP already solve this problem?
- Could a simpler enhancement to AIDP provide the same value?
- Is there a lightweight alternative?

---

## Beads: Multi-Session Task Tracking

**Repository**: [github.com/steveyegge/beads](https://github.com/steveyegge/beads)

**Status**: ⚠️ Alpha - Use with caution

### What It Is

Beads is a git-distributed issue tracker designed specifically for AI coding agents:

- SQLite for fast local queries
- JSONL committed to git as source of truth
- Dependency tracking (blocks, related, parent-child)
- Automatic "ready work" detection
- Distributed sync via git push/pull

### When to Consider Beads

✅ **Good fit if you**:

- Work on long-horizon features spanning multiple days/weeks
- Need complex dependency tracking between tasks
- Have multiple developers/machines working on the same project
- Want agents to automatically pick up work across sessions
- Frequently discover sub-tasks during implementation

❌ **Not needed if you**:

- Work on focused, short-duration tasks (hours, not days)
- Single-session work loops are typical
- AIDP's built-in tasklist template is sufficient
- Solo developer on simple projects

### Value vs. AIDP Built-ins

**What Beads adds over AIDP's tasklist**:

1. **Persistence across major workflow changes** - AIDP tasklist is session-scoped
2. **Dependency graphs** - "Task A blocks Task B" relationships
3. **Distributed coordination** - Multiple machines/developers share queue via git
4. **Automatic discovery filing** - "I found 3 new tasks while implementing"

**Context cost**: ~450 tokens per session start (3% overhead)

**AIDP's tasklist is better for**:

- Today's work (same session)
- Simple linear task lists
- Fast iteration cycles

### Installation (Optional)

Only install if you've determined Beads addresses a real gap in your workflow:

```bash
# 1. Install Beads globally
npm install -g beads

# 2. Initialize in your project
cd /path/to/your/project
bd init

# 3. Basic usage
bd create "Implement rate limiting" --priority high
bd list --status ready
bd ready  # Show what's ready to work on

# 4. Git workflow
git add .beads/issues.jsonl
git commit -m "Add rate limiting task"
git push

# 5. On another machine
git pull
bd ready  # See the new task
```

### Using Beads with AIDP

Beads works alongside AIDP via MCP protocol or CLI:

```bash
# Before starting AIDP work loop
bd ready --json > ready_tasks.json

# In AIDP prompt or context
# "Available tasks from Beads: [contents of ready_tasks.json]"

# After completing work
bd done 42  # Mark task #42 as done
git add .beads/issues.jsonl && git commit -m "Complete task #42"
```

AIDP's MCP dashboard will automatically detect Beads if installed and show basic status.

### When to Skip Beads

**Use AIDP's enhanced persistent tasklist instead** (see PRD below) if:

- You need simple cross-session task persistence
- You don't need complex dependency graphs
- You want zero external dependencies
- Simpler is better for your workflow

AIDP's persistent tasklist provides 90% of Beads value at 10% of the complexity.

---

## Memory Bank MCP: Not Recommended

**Repository**: [github.com/AceOfWands/memory-bank-mcp](https://github.com/AceOfWands/memory-bank-mcp)

**Status**: ❌ Not recommended for AIDP users

### Why Not Recommended

Memory Bank MCP provides persistent, semantic memory for LLMs using Zettelkasten note-taking and vector search.

**Sounds useful, but**:

1. **High redundancy with AIDP's prompt optimization**
   - AIDP's fragment selector already includes relevant style guide sections
   - Semantic search is already built-in via relevance scoring
   - Adding 5 memory notes = ~1,500 tokens (18% overhead) for marginal value

2. **Better alternatives exist in AIDP**
   - Style guide sections → Already optimized by fragment selector
   - Git history → `git log` for "why did we do this?"
   - Project-specific config → Faster, more reliable than AI memory

3. **High complexity, low ROI**
   - Requires PostgreSQL + pgvector
   - Embeddings infrastructure
   - Maintenance burden
   - Context bloat

### Use Style Guide Sections Instead

Instead of memory-bank-mcp, add project-specific sections to your style guide:

```markdown
# docs/LLM_STYLE_GUIDE.md

## Project-Specific Patterns

### Authentication (Decided: 2025-10-15)
- Using OAuth 2.0 with Auth0
- Reason: Client requires Google/GitHub login support
- PKCE flow for security
- Sliding window token refresh (15 min access, 7 day refresh)

### Database Pagination
- Using cursor-based pagination for all large lists
- Reason: Better performance than offset-based (see commit abc123)
- Pattern: `?cursor=opaque_token&limit=50`

### Error Handling
- Prefer `Aidp::Errors::*` specific exceptions
- Always log with `Aidp.log_error(component, message, error: e.message)`
- User-facing errors use TTY::Prompt error formatting
```

**Benefits**:

- Zero context overhead (AIDP's fragment selector includes only when relevant)
- Git-versioned, human-readable
- No external service needed
- Already optimized by prompt minimization
- Faster than semantic search

**This is the recommended approach** for persistent project knowledge.

---

## Other MCP Servers

AIDP supports any MCP-compliant server via its existing MCP integration. However, evaluate carefully:

### Good Candidates

✅ **Domain-specific tools** that AIDP doesn't provide:

- Database query tools (if you need live DB access)
- API testing tools (if beyond what test runners provide)
- Deployment automation (if AIDP agents need to deploy)

### Poor Candidates

❌ **General-purpose tools** that duplicate AIDP features:

- File operations (AIDP has built-in file handling)
- Code search (AIDP's tree-sitter and grep are excellent)
- Test runners (AIDP's test harness is comprehensive)
- Context/memory systems (AIDP's prompt optimization is superior)

### Evaluation Questions

Before adding an MCP server:

1. Does AIDP already provide this capability?
2. What's the context cost (tokens added per query)?
3. Could I achieve the same result with a style guide section or config?
4. Is the setup/maintenance effort justified?
5. What happens when the MCP server is unavailable?

---

## Recommendations Summary

### For Most Users

**Use AIDP's built-in features**:

- ✅ Tasklist template (within session)
- ✅ Persistent tasklist (cross-session, see PRD)
- ✅ Style guide fragments (project knowledge)
- ✅ Checkpoint system (progress tracking)
- ✅ Prompt optimization (context management)

**Total external dependencies**: Zero

**Context overhead**: Zero

### For Advanced Long-Horizon Work

**Consider Beads** if you need:

- Multi-session task persistence
- Complex dependency graphs
- Distributed team coordination

**Context overhead**: ~3% (450 tokens)

**Setup effort**: 15 minutes

**Maintenance**: Low (git-based)

### For Project-Specific Knowledge

**Use style guide sections**, not memory-bank-mcp:

- Create `docs/LLM_STYLE_GUIDE.md` sections
- Document decisions as you make them
- Let AIDP's fragment selector include them automatically

**Context overhead**: Zero (already included in budget)

**Setup effort**: 5 minutes

**Maintenance**: Standard git workflow

---

## Future AIDP Enhancements

Instead of external tools, AIDP is investing in:

1. **Persistent Tasklist** (Planned)
   - Cross-session task tracking
   - Git-committable `.aidp/tasklist.jsonl`
   - Provides 90% of Beads value
   - See PRD: [PERSISTENT_TASKLIST.md](PERSISTENT_TASKLIST.md)

2. **Style Guide Templates** (Documentation)
   - Best practices for project-specific sections
   - Examples and patterns
   - Integration with fragment selector

3. **Checkpoint Enhancement** (Future)
   - Richer context about previous sessions
   - "What was I working on?" summaries
   - Automatic session bridging

These enhancements provide better integration, lower complexity, and zero context overhead compared to external tools.

---

## Conclusion

**Default answer**: Use AIDP's built-in features. They're excellent and designed to work together efficiently.

**Only add external tools when**:

- You've identified a specific gap
- You've evaluated the cost/benefit
- You've considered simpler alternatives
- The value clearly exceeds the complexity

**Remember**: Every external dependency adds:

- Setup friction
- Maintenance burden
- Failure modes
- Context overhead (often redundant)

AIDP's philosophy is **"optimize the core"** before expanding the surface area.

---

## References

- [Beads GitHub Repository](https://github.com/steveyegge/beads)
- [Persistent Tasklist PRD](PERSISTENT_TASKLIST.md)
- [AIDP Prompt Optimization](PROMPT_OPTIMIZATION.md)
- [AIDP Style Guide](LLM_STYLE_GUIDE.md)
- [MCP Dashboard](CLI_USER_GUIDE.md#mcp-dashboard)
