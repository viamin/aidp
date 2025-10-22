# AIDP Skills User Guide

## Table of Contents

1. [Introduction](#introduction)
2. [What are Skills?](#what-are-skills)
3. [Getting Started](#getting-started)
4. [Managing Skills](#managing-skills)
5. [Creating Custom Skills](#creating-custom-skills)
6. [Skill Routing](#skill-routing)
7. [Advanced Topics](#advanced-topics)
8. [Troubleshooting](#troubleshooting)

## Introduction

Skills in AIDP are specialized AI personas that provide domain-specific expertise for your development workflow. Each skill contains instructions, expertise areas, and guidelines that help the AI provide better, more focused assistance for specific tasks.

## What are Skills?

A skill is a packaged set of instructions and metadata stored in a `SKILL.md` file that defines:

- **Identity**: Name and description of the skill's expertise
- **Expertise**: Areas of knowledge and capabilities
- **When to Use**: Scenarios where this skill excels
- **Instructions**: Detailed guidelines for the AI to follow

### Built-in Skills

AIDP comes with several template skills:

- **architecture_analyst**: Expert in software architecture patterns and system design
- **product_strategist**: Specialist in product planning and requirements gathering
- **repository_analyst**: Expert in code evolution and repository metrics
- **test_analyzer**: Specialist in test coverage and quality assessment

### Project Skills

You can create custom skills specific to your project in `.aidp/skills/`. These skills can:

- Inherit from template skills
- Override or extend template functionality
- Provide project-specific expertise

## Getting Started

### Listing Available Skills

```bash
# List all skills (templates and project skills)
aidp skill list

# View detailed information about a skill
aidp skill show repository_analyst

# Preview full SKILL.md content
aidp skill preview repository_analyst
```

### Using Skills in Your Workflow

Skills are automatically selected based on routing rules (see [Skill Routing](#skill-routing)) or can be manually specified:

```bash
# Use a specific skill for a task
aidp --skill rails_expert
```

### Using Skills in REPL

When working in an interactive REPL session, you can manage skills with slash commands:

```bash
# List available skills
/skill list

# Show skill details
/skill show repository_analyst

# Search for skills
/skill search api

# Switch to a specific skill for the session
/skill use repository_analyst
```

After using `/skill use`, all subsequent AI interactions in that REPL session will use the specified skill's expertise and guidelines.

## Managing Skills

### Searching for Skills

```bash
# Search for skills by keyword
aidp skill search "api"
aidp skill search "testing"
```text

### Validating Skills

```bash
# Validate all skills
aidp skill validate

# Validate a specific skill file
aidp skill validate .aidp/skills/my_skill/SKILL.md
```text

### Comparing Skills

```bash
# Show differences between your project skill and its template
aidp skill diff my_custom_skill
```text

<a id="creating-custom-skills"></a>
## Creating Custom Skills

### Interactive Wizard

The easiest way to create a new skill is using the interactive wizard:

```bash
aidp skill new
```text

The wizard will guide you through:

1. **Template Selection**: Choose to start from scratch, inherit from a template, or clone an existing skill
2. **Identity**: Set the skill's ID, name, and description
3. **Expertise**: Define areas of expertise and keywords
4. **Usage Guidelines**: Specify when to use (and when not to use) this skill
5. **Provider Compatibility**: Select compatible AI providers
6. **Content**: Write the detailed instructions for the AI

### Quick Creation Options

For faster skill creation, use command-line options:

```bash
# Create with minimal prompts
aidp skill new --minimal --id my_skill --name "My Skill"

# Inherit from a template
aidp skill new --from-template repository_analyst --id my_repo_analyzer

# Clone an existing skill
aidp skill new --clone existing_skill --id improved_version

# Preview without saving
aidp skill new --dry-run
```text

### Editing Existing Skills

```bash
# Edit an existing project skill
aidp skill edit my_custom_skill

# Preview changes without saving
aidp skill edit my_custom_skill --dry-run
```text

### Deleting Skills

```bash
# Delete a project skill (with confirmation)
aidp skill delete my_custom_skill
```text

**Note**: You can only delete project skills in `.aidp/skills/`, not template skills.

<a id="skill-routing"></a>
## Skill Routing

Skills can be automatically selected based on file paths and task descriptions using routing rules in your `.aidp/aidp.yml` configuration.

### Configuration

Create or edit `.aidp/aidp.yml`:

```yaml
skills:
  routing:
    enabled: true
    default: general_developer

    # Path-based routing
    path_rules:
      rails_expert:
        - "app/controllers/**/*.rb"
        - "app/models/**/*.rb"
      frontend_expert:
        - "app/javascript/**/*.{js,jsx,ts,tsx}"

    # Task-based routing
    task_rules:
      backend_developer:
        - "api"
        - "endpoint"
        - "database"
      frontend_developer:
        - "ui"
        - "component"
        - "styling"

    # Combined routing (highest priority)
    combined_rules:
      full_stack_expert:
        paths: ["app/controllers/api/**/*.rb"]
        tasks: ["api", "endpoint"]
```text

### Routing Priority

1. **Combined Rules**: Both path AND task must match (highest priority)
2. **Path Rules**: File path matches pattern
3. **Task Rules**: Task description contains keywords
4. **Default Skill**: Fallback when nothing matches

### Example Routing

```ruby
# Given this configuration, routing works as follows:

router = Aidp::Skills::Router.new(project_dir: Dir.pwd)

# Combined rule match
router.route(
  path: "app/controllers/api/users_controller.rb",
  task: "Add new API endpoint"
)
# => "full_stack_expert"

# Path rule match (task doesn't match combined)
router.route(
  path: "app/models/user.rb",
  task: "Add validation"
)
# => "rails_expert"

# Task rule match (path doesn't match)
router.route(
  path: "lib/services/api_client.rb",
  task: "Add API endpoint"
)
# => "backend_developer"

# Default fallback (nothing matches)
router.route(
  path: "README.md",
  task: "Update documentation"
)
# => "general_developer"
```text

<a id="advanced-topics"></a>
## Advanced Topics

### Skill Inheritance

Skills can inherit from template skills to reuse and extend functionality:

1. **Automatic Merging**: Arrays (expertise, keywords) are merged with deduplication
2. **Override Support**: Scalar fields (version, compatible_providers) can be overridden
3. **Content Extension**: You can use template content or provide your own

### Skill Structure

Skills are stored in the following structure:

```text
.aidp/skills/
└── my_custom_skill/
    └── SKILL.md        # Main skill file
```text

### SKILL.md Format

```markdown
---
id: my_custom_skill
name: My Custom Skill
description: A custom skill for my project
version: 1.0.0
expertise:
  - domain_area_1
  - domain_area_2
keywords:
  - keyword1
  - keyword2
when_to_use:
  - Scenario 1
  - Scenario 2
when_not_to_use:
  - Avoid for scenario X
compatible_providers:
  - anthropic
  - openai
---

# My Custom Skill

Detailed instructions for the AI to follow when using this skill...

## Core Capabilities

- Capability 1
- Capability 2

## Guidelines

- Guideline 1
- Guideline 2
```text

### Template Skills Location

Template skills are stored in the gem:

```text
templates/skills/
├── architecture_analyst/
│   └── SKILL.md
├── product_strategist/
│   └── SKILL.md
├── repository_analyst/
│   └── SKILL.md
└── test_analyzer/
    └── SKILL.md
```text

<a id="troubleshooting"></a>
## Troubleshooting

### Skill Not Found

**Problem**: `aidp skill show my_skill` returns "Skill not found"

**Solutions**:

1. Check the skill ID matches: `aidp skill list`
2. Verify the skill exists in `.aidp/skills/my_skill/SKILL.md`
3. Validate the skill file: `aidp skill validate`

### Validation Errors

**Problem**: Skill validation fails

**Common issues**:

- Missing required fields (id, name, description, version, content)
- Invalid version format (must be X.Y.Z, e.g., "1.0.0")
- Invalid ID format (must be lowercase alphanumeric with underscores)

**Solution**:

```bash
aidp skill validate .aidp/skills/my_skill/SKILL.md
```text

### Routing Not Working

**Problem**: Skills aren't being automatically selected

**Solutions**:

1. Check routing is enabled in `.aidp/aidp.yml`:

   ```yaml
   skills:
     routing:
       enabled: true
   ```

1. Verify your path patterns use correct glob syntax
1. Check task keywords match your descriptions
1. Test routing manually:

   ```ruby
   router = Aidp::Skills::Router.new(project_dir: Dir.pwd)
   router.route(path: "your/file.rb", task: "your task")
   ```

### Cannot Delete Skill

**Problem**: "Cannot delete template skill"

**Explanation**: Template skills (in `templates/skills/`) cannot be deleted, only project skills (in `.aidp/skills/`) can be removed.

**Solution**: Create a project skill to override the template instead of deleting it.

## Best Practices

1. **Start with Templates**: Inherit from template skills when possible
2. **Clear Expertise**: Define specific expertise areas for better routing
3. **Descriptive IDs**: Use clear, descriptive IDs (e.g., `rails_api_expert` not `skill1`)
4. **Version Control**: Commit skills to version control to share with your team
5. **Test Routing**: Verify routing rules work as expected before relying on them
6. **Document Usage**: Add clear `when_to_use` and `when_not_to_use` guidelines

## Getting Help

- View command help: `aidp skill --help`
- Check skill structure: `aidp skill show <id>`
- Validate configuration: `aidp skill validate`
- Report issues: <https://github.com/viamin/aidp/issues>

## See Also

- [Skill Authoring Wizard Design](SKILL_AUTHORING_WIZARD_DESIGN.md) - Technical design document
- [aidp.yml Example](../examples/aidp.yml.example) - Configuration examples
- [Skills API Documentation](../lib/aidp/skills/) - Developer documentation
