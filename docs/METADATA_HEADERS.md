# Metadata Headers for AIDP Tools

This document describes the metadata header schema for AIDP skills, personas, and templates.

## Overview

All AIDP tools (skills, personas, templates) can include YAML frontmatter metadata headers that enable:

- **Automatic tool discovery** - Find relevant tools by tags, work unit types, and capabilities
- **Dependency resolution** - Automatically load required tools
- **Priority-based ranking** - Select the best tool for the job
- **Validation** - Ensure tool metadata is complete and correct
- **Caching** - Fast lookups via compiled tool directory

## Schema

### Required Fields

All tools **MUST** include these fields:

```yaml
---
type: skill                    # Tool type: "skill", "persona", or "template"
id: ruby_rspec_tdd            # Unique identifier (lowercase, alphanumeric, underscores)
title: Ruby RSpec TDD Expert  # Human-readable title
summary: Expert in Test-Driven Development with RSpec  # Brief one-line summary
version: 1.0.0                # Semantic version (X.Y.Z format)
---
```

### Optional Fields

```yaml
---
# ... required fields ...

# Applicability tags (for filtering and discovery)
applies_to:
  - ruby
  - testing
  - tdd
  - rspec

# Work unit types this tool supports
work_unit_types:
  - implementation
  - testing
  - refactoring

# Priority for ranking (1-10, default: 5)
# Higher priority tools are preferred when multiple match
priority: 8

# Capabilities provided by this tool
capabilities:
  - test_generation
  - refactoring_support
  - documentation

# Dependencies on other tools (by ID)
dependencies:
  - ruby_basics
  - test_framework_setup

# Experimental flag (warns users)
experimental: false
---
```

## Field Descriptions

### `type` (required)

The type of tool. Must be one of:

- `skill` - A skill or expertise area (defines HOW to do something)
- `persona` - An agent persona (WHO the agent is)
- `template` - A task template (WHAT to do)

**Example:**

```yaml
type: skill
```

### `id` (required)

Unique identifier for the tool. Used for lookups and dependencies.

**Rules:**

- Must be lowercase
- Alphanumeric characters and underscores only
- Must be unique across all tools

**Example:**

```yaml
id: ruby_rspec_tdd
```

### `title` (required)

Human-readable title displayed in tool listings and info.

**Example:**

```yaml
title: Ruby RSpec TDD Expert
```

### `summary` (required)

Brief one-line description of what the tool does or provides.

**Example:**

```yaml
summary: Expert in Test-Driven Development using Ruby and RSpec framework
```

### `version` (required)

Semantic version number.

**Format:** `X.Y.Z` where X, Y, Z are integers

**Example:**

```yaml
version: 1.0.0
```

### `applies_to` (optional)

Tags indicating what contexts, technologies, or scenarios this tool applies to.

Used for filtering and discovery. Tools are matched when ANY tag matches the query.

**Example:**

```yaml
applies_to:
  - ruby
  - testing
  - tdd
  - rspec
  - backend
```

### `work_unit_types` (optional)

Types of work units this tool supports.

**Common values:**

- `analysis` - Repository or code analysis
- `planning` - Planning documents (PRD, architecture, etc.)
- `implementation` - Code implementation
- `testing` - Test writing or test analysis
- `refactoring` - Code refactoring
- `documentation` - Documentation writing
- `review` - Code or design review

**Example:**

```yaml
work_unit_types:
  - implementation
  - testing
  - refactoring
```

### `priority` (optional)

Ranking priority when multiple tools match.

**Range:** 1-10 (default: 5)

- 1-3: Low priority
- 4-6: Medium priority
- 7-10: High priority

Higher priority tools are preferred when multiple tools match the same criteria.

**Example:**

```yaml
priority: 8
```

### `capabilities` (optional)

Capabilities or features provided by this tool.

**Example:**

```yaml
capabilities:
  - test_generation
  - refactoring_support
  - documentation
  - performance_optimization
```

### `dependencies` (optional)

IDs of other tools that must be available for this tool to work.

Dependencies are automatically resolved and loaded in the correct order.

**Example:**

```yaml
dependencies:
  - ruby_basics
  - test_framework_setup
```

### `experimental` (optional)

Whether this tool is experimental/unstable.

**Default:** `false`

When `true`, users are warned that the tool may change or have issues.

**Example:**

```yaml
experimental: true
```

## Complete Example

```yaml
---
type: skill
id: ruby_rspec_tdd
title: Ruby RSpec TDD Expert
summary: Expert in Test-Driven Development using Ruby and RSpec framework
version: 1.0.0

applies_to:
  - ruby
  - testing
  - tdd
  - rspec

work_unit_types:
  - implementation
  - testing
  - refactoring

priority: 8

capabilities:
  - test_generation
  - refactoring_support
  - documentation

dependencies:
  - ruby_basics

experimental: false
---

# Ruby RSpec TDD Expert

You are an expert in Test-Driven Development using Ruby and RSpec...

[Rest of skill content in markdown]
```

## Legacy Skill Format

Existing skills use a slightly different format that is automatically converted:

```yaml
---
id: skill_id
name: Skill Name              # Maps to "title"
description: Brief description # Maps to "summary"
version: 1.0.0
expertise:                    # Informational only
  - Area 1
  - Area 2
keywords:                     # Maps to "applies_to"
  - keyword1
  - keyword2
when_to_use:                  # Informational only
  - Use case 1
when_not_to_use:             # Informational only
  - Avoid case 1
compatible_providers:         # Informational only
  - anthropic
  - openai
---
```

The parser automatically converts these fields to the new schema:

- `name` → `title`
- `description` → `summary`
- `keywords` → `applies_to`
- `type` is auto-detected as "skill"

## Validation

Use `aidp tools lint` to validate all tool metadata:

```bash
aidp tools lint
```

This checks for:

- Required fields present
- Correct field types
- Valid version format
- Valid ID format
- Duplicate IDs
- Missing dependencies
- Invalid priority values

## Configuration

Configure tool metadata behavior in `.aidp/aidp.yml`:

```yaml
tool_metadata:
  # Enable metadata system
  enabled: true

  # Directories to scan for tools
  directories:
    - .aidp/skills
    - .aidp/personas
    - .aidp/templates

  # Cache file location
  cache_file: .aidp/cache/tool_directory.json

  # Strict mode (fail on validation errors)
  strict: false
```

## CLI Commands

```bash
# Validate all metadata
aidp tools lint

# Show tool details
aidp tools info ruby_rspec_tdd

# Force regenerate cache
aidp tools reload

# List all tools
aidp tools list
```

## Authoring Guidelines

### Choosing Tags

**Good tags:**

- Technology names: `ruby`, `javascript`, `python`
- Domain areas: `testing`, `security`, `performance`
- Methodologies: `tdd`, `bdd`, `agile`
- Tool names: `rspec`, `jest`, `pytest`

**Avoid:**

- Generic terms: `coding`, `development`, `software`
- Redundant tags: If ID is `ruby_rspec_tdd`, don't repeat all three in tags
- Over-tagging: Keep to 3-7 relevant tags

### Setting Priority

- **10 (Critical):** Core tools required for most workflows
- **8-9 (High):** Specialized tools with clear advantages
- **5-7 (Medium):** Standard tools, good defaults
- **3-4 (Low):** Alternative approaches, niche use cases
- **1-2 (Fallback):** Deprecated or experimental alternatives

### Writing Summaries

**Good summaries:**

- "Expert in Test-Driven Development using Ruby and RSpec framework"
- "Analyzes repository history and generates code metrics using git log"
- "Creates comprehensive PRDs with user stories and acceptance criteria"

**Avoid:**

- Too vague: "Helps with testing"
- Too long: Summaries should be one sentence
- Redundant: Don't repeat the title

## Migration from Existing Skills

Existing skills will continue to work without modification. To add metadata headers:

1. Add `type: skill` at the top of frontmatter
2. Rename `name` → `title` and `description` → `summary`
3. Add optional fields as needed (`applies_to`, `work_unit_types`, `priority`)
4. Run `aidp tools lint` to validate

The system will automatically convert old-style skills during parsing.

## See Also

- [TOOL_DIRECTORY.md](TOOL_DIRECTORY.md) - Tool directory compilation and querying
- [CONFIGURATION.md](CONFIGURATION.md) - Configuration reference
- [CLI_USER_GUIDE.md](CLI_USER_GUIDE.md) - CLI command reference
