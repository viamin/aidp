# AIDP Skills System

## Overview

Skills define **WHO** the agent is (persona, expertise, capabilities), separate from templates/procedures which define **WHAT** task to execute.

This separation allows for:

- Reusable personas across multiple tasks
- Provider-agnostic skill definitions
- Clear distinction between agent identity and task execution
- Easier customization and overriding of agent behaviors

## Skill Structure

Each skill is a directory containing a `SKILL.md` file:

```text
skills/
└── repository_analyst/
    └── SKILL.md
```

### SKILL.md Format

Skills use YAML frontmatter for metadata and markdown for content:

```markdown
---
id: repository_analyst
name: Repository Analyst
description: Expert in version control analysis and code evolution patterns
version: 1.0.0
expertise:
  - version control system analysis (Git, SVN, etc.)
  - code churn analysis and hotspots identification
keywords:
  - git
  - metrics
  - hotspots
when_to_use:
  - Analyzing repository history
  - Identifying technical debt through metrics
when_not_to_use:
  - Writing new code
  - Debugging runtime issues
compatible_providers:
  - anthropic
  - openai
  - cursor
---

# Repository Analyst

You are a **Repository Analyst**, an expert in version control analysis...

## Your Core Capabilities

### Version Control Analysis
- Analyze commit history...

## Analysis Philosophy

**Data-Driven**: Base all recommendations on actual repository metrics...
```

## Required Frontmatter Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | String | Unique identifier (lowercase, alphanumeric, underscores only) |
| `name` | String | Human-readable name |
| `description` | String | Brief one-line description |
| `version` | String | Semantic version (X.Y.Z format) |

## Optional Frontmatter Fields

| Field | Type | Description |
|-------|------|-------------|
| `expertise` | Array | List of expertise areas |
| `keywords` | Array | Search/filter keywords |
| `when_to_use` | Array | Guidance for when to use this skill |
| `when_not_to_use` | Array | Guidance for when NOT to use this skill |
| `compatible_providers` | Array | Compatible provider names (empty = all) |

## Skill Locations

### Template Skills

Located in `templates/skills/` in the AIDP gem. These are read-only templates installed with the AIDP gem and cover common use cases; they cannot be modified directly in your project.

- **repository_analyst**: Version control and code evolution analysis
- **product_strategist**: Product planning and requirements gathering
- **architecture_analyst**: Architecture analysis and pattern identification
- **test_analyzer**: Test suite analysis and quality assessment

### Project Skills

Located in `.aidp/skills/` for project-specific skills:

```text
.aidp/
└── skills/
    └── my_custom_skill/
        └── SKILL.md
```

Project skills with matching IDs override template skills.

## Using Skills

### In Step Specifications

Reference skills in step specs (e.g., [analyze/steps.rb](lib/aidp/analyze/steps.rb#L6-L60)):

```ruby
SPEC = {
  "01_REPOSITORY_ANALYSIS" => {
    "skill" => "repository_analyst",
    "templates" => ["analysis/analyze_repository.md"],
    "description" => "Repository mining",
    "outs" => ["docs/analysis/repository_analysis.md"],
    "gate" => false
  }
}
```

### Programmatic Access

```ruby
# Load skills registry
registry = Aidp::Skills::Registry.new(project_dir: Dir.pwd)
registry.load_skills

# Find a skill
skill = registry.find("repository_analyst")

# Search skills
matching_skills = registry.search("git")

# Filter by keyword
analysis_skills = registry.by_keyword("analysis")

# Check provider compatibility
compatible = registry.compatible_with("anthropic")
```

### Composing with Templates

Skills are automatically composed with templates by the runner:

```ruby
# In runner
skill = skills_registry.find(step_spec["skill"])
template = File.read(template_path)

# Compose skill + template
composed_prompt = @skills_composer.compose(
  skill: skill,
  template: template,
  options: { variable: "value" }
)
```

The composition structure is:

```text
1. Skill content (persona, expertise, philosophy)
2. Separator (---)
3. "# Current Task" header
4. Template content (task-specific instructions)
```

## Configuration

Configure skills in `.aidp/aidp.yml`:

```yaml
skills:
  search_paths: []  # Additional skill search paths (optional)
  default_provider_filter: true  # Filter by provider compatibility
  enable_custom_skills: true  # Enable custom skill overrides
```

## Provider Compatibility

Skills can declare compatible providers in frontmatter:

```yaml
compatible_providers:
  - anthropic
  - openai
```

- Empty list = compatible with all providers
- Registry filters skills by provider when initialized
- Incompatible skills are skipped during loading

## Best Practices

### Skill Design

1. **Focus on WHO, not WHAT**: Skills define agent identity, not task steps
2. **Be specific**: Clearly describe expertise areas and capabilities
3. **Provide guidance**: Use `when_to_use` and `when_not_to_use` to help with selection
4. **Version carefully**: Use semantic versioning for tracking changes
5. **Test compatibility**: Verify skills work with intended providers

### Naming Conventions

- **ID**: `lowercase_with_underscores` (e.g., `repository_analyst`)
- **Name**: `Title Case` (e.g., `Repository Analyst`)
- **Files**: Always name the file `SKILL.md` (uppercase)

### Content Guidelines

From the [LLM_STYLE_GUIDE](../docs/LLM_STYLE_GUIDE.md#L1-L202):

- Use clear, professional language
- Organize with markdown headers
- Bullet points for lists of capabilities
- Explain philosophy and approach
- Provide concrete examples when helpful

## Creating a New Skill

1. **Create directory structure**:

   ```bash
   mkdir -p skills/my_skill
   ```

2. **Create SKILL.md**:

   ```bash
   touch skills/my_skill/SKILL.md
   ```

3. **Add frontmatter and content**:

   ```markdown
   ---
   id: my_skill
   name: My Skill Name
   description: Brief description
   version: 1.0.0
   expertise:
     - Area 1
     - Area 2
   keywords:
     - keyword1
   when_to_use:
     - Situation 1
   when_not_to_use:
     - Situation 2
   compatible_providers:
     - anthropic
   ---

   # My Skill Name

   You are a **My Skill Name**, an expert in...
   ```

4. **Reference in steps**:

   ```ruby
   "MY_STEP" => {
     "skill" => "my_skill",
     "templates" => ["path/to/template.md"],
     ...
   }
   ```

## Architecture

### Core Components

- **[Skill](lib/aidp/skills/skill.rb#L1-L187)**: Model representing a skill
- **[Loader](lib/aidp/skills/loader.rb#L1-L179)**: Parses SKILL.md files
- **[Registry](lib/aidp/skills/registry.rb#L1-L213)**: Manages available skills
- **[Composer](lib/aidp/skills/composer.rb#L1-L162)**: Combines skills with templates

### Integration Points

- **[Analyze Runner](lib/aidp/analyze/runner.rb#L198-L236)**: Uses skills in analysis mode
- **[Execute Runner](lib/aidp/execute/runner.rb#L320-L355)**: Uses skills in execution mode
- **[Config](lib/aidp/config.rb#L166-L170)**: Skills configuration support

## Future Enhancements

Planned for future versions (out of scope for v1):

- **Skill Inheritance**: Skills extending other skills
- **Skill Composition**: Combining multiple skills for complex tasks
- **AI-Powered Selection**: Automatically selecting best skill for a task
- **Skill Marketplace**: Sharing skills across teams/organizations
- **Dynamic Generation**: Creating skills from examples
- **Execution Validation**: Checking if output matches skill expectations

## Related Documentation

- [PRD: Skills System](../docs/prd_skills_system.md) - Product requirements and architecture
- [LLM Style Guide](../docs/LLM_STYLE_GUIDE.md) - Coding standards for skills content
- [Issue #148](https://github.com/viamin/aidp/issues/148) - Original feature request

## Troubleshooting

### Skill Not Found

If a skill is referenced but not found:

1. Check the skill ID matches exactly (case-sensitive in SPEC, but lowercase in file)
2. Verify the SKILL.md file exists in the correct directory
3. Check for YAML syntax errors in frontmatter
4. Review logs for loading errors

### Provider Compatibility Issues

If skills aren't loading for a provider:

1. Check `compatible_providers` in frontmatter
2. Verify provider name matches exactly
3. Check `default_provider_filter` in config
4. Review registry initialization logs

### Validation Errors

Common validation errors:

- **"id must be lowercase"**: Use only lowercase letters, numbers, underscores
- **"version must be in format X.Y.Z"**: Use semantic versioning (e.g., "1.0.0")
- **"YAML frontmatter missing"**: Ensure `---` delimiters are present
- **Missing required field**: Add required frontmatter fields (id, name, description, version)
