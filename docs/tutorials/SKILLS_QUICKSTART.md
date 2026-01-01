# Skills Quickstart Tutorial

This tutorial will walk you through creating and using custom skills in AIDP in just 10 minutes.

## Prerequisites

- AIDP installed and configured
- Basic familiarity with command line

## Tutorial Overview

In this tutorial, you'll:

1. Explore built-in template skills
2. Create your first custom skill
3. Set up skill routing
4. Use skills in your workflow

**Estimated time**: 10 minutes

## Step 1: Explore Template Skills (2 minutes)

First, let's see what skills are available:

```bash
aidp skill list
```

You should see template skills like:

- `architecture_analyst`
- `product_strategist`
- `repository_analyst`
- `test_analyzer`

Let's examine one in detail:

```bash
aidp skill show repository_analyst
```

This shows the skill's metadata: expertise areas, keywords, and when to use it.

To see the full instructions:

```bash
aidp skill preview repository_analyst
```

## Step 2: Create Your First Custom Skill (3 minutes)

Let's create a custom skill for Rails API development. We'll inherit from the template to get started quickly:

```bash
aidp skill new --from-template architecture_analyst --id rails_api_expert --name "Rails API Expert"
```

The wizard will guide you through:

1. **Description**: "Expert in Rails API development with best practices"
2. **Expertise**: Add "rails", "api", "rest", "graphql"
3. **Keywords**: Add "rails", "api", "endpoint", "controller"
4. **When to use**: "Building REST APIs", "GraphQL endpoints", "API authentication"
5. **When not to use**: "Frontend development", "Pure database work"
6. **Providers**: Select "anthropic", "openai" (or keep defaults)
7. **Content**: The wizard opens your editor with template content - customize it or keep as-is

When you're done, confirm to save the skill.

Verify it was created:

```bash
aidp skill list
```

You should now see `rails_api_expert` in your list!

## Step 3: Set Up Skill Routing (3 minutes)

Now let's configure automatic routing so AIDP uses the right skill for the right files.

Create or edit `.aidp/aidp.yml`:

```yaml
skills:
  routing:
    enabled: true
    default: architecture_analyst

    # Route Rails API files to your custom skill
    path_rules:
      rails_api_expert:
        - "app/controllers/api/**/*.rb"
        - "app/graphql/**/*.rb"

      repository_analyst:
        - "lib/**/*.rb"
        - "app/models/**/*.rb"

    # Route tasks by keywords
    task_rules:
      rails_api_expert:
        - "api"
        - "endpoint"
        - "rest"
        - "graphql"

      test_analyzer:
        - "test"
        - "spec"
        - "coverage"

    # Combined rules (both path AND task must match)
    combined_rules:
      rails_api_expert:
        paths: ["app/controllers/api/**/*.rb"]
        tasks: ["api", "endpoint", "authentication"]
```

Save the file.

## Step 4: Test Your Skill (2 minutes)

Now let's test the routing:

```bash
# This should route to rails_api_expert
aidp --path "app/controllers/api/v1/users_controller.rb" --task "Add authentication endpoint"

# This should route to repository_analyst
aidp --path "lib/services/user_service.rb" --task "Refactor service"
```

You can also verify routing in Ruby:

```ruby
require 'aidp'

router = Aidp::Skills::Router.new(project_dir: Dir.pwd)

puts router.route(
  path: "app/controllers/api/v1/users_controller.rb",
  task: "Add new API endpoint"
)
# => "rails_api_expert"
```

## Next Steps

### Customize Your Skill

Edit your custom skill to add project-specific knowledge:

```bash
aidp skill edit rails_api_expert
```

Add information about:

- Your authentication system (JWT, OAuth, etc.)
- API versioning strategy
- Project-specific conventions
- Common patterns and anti-patterns

### View Differences from Template

See what you've customized:

```bash
aidp skill diff rails_api_expert
```

This shows differences between your skill and the template it inherits from.

### Create More Skills

Build a library of project-specific skills:

```bash
# Frontend expert
aidp skill new --from-template architecture_analyst --id frontend_expert

# DevOps expert
aidp skill new --from-template product_strategist --id devops_expert

# Database expert
aidp skill new --from-template repository_analyst --id database_expert
```

### Share with Your Team

Commit your skills to version control:

```bash
git add .aidp/skills/
git add .aidp/aidp.yml
git commit -m "Add custom Rails API expert skill"
git push
```

Your team will now have access to the same expertise!

## Common Workflows

### Creating a New Feature

```bash
# AIDP automatically selects rails_api_expert based on file path
cd app/controllers/api/v1
aidp --task "Add new user registration endpoint"
```

### Refactoring Code

```bash
# Use a specific skill
aidp --skill architecture_analyst --task "Refactor controllers for better separation of concerns"
```

### Analyzing Repository

```bash
# Repository analyst for code metrics
aidp --skill repository_analyst --task "Analyze code churn and identify hotspots"
```

### Testing

```bash
# Test analyzer for coverage improvements
aidp --skill test_analyzer --task "Identify untested code paths"
```

## Tips and Tricks

### Quick Skill Creation

For rapid prototyping, use minimal mode:

```bash
aidp skill new --minimal --id quick_skill --name "Quick Skill"
```

### Non-Interactive Creation

For automation or scripts:

```bash
aidp skill new \
  --from-template repository_analyst \
  --id automated_skill \
  --name "Automated Skill" \
  --minimal
```

### Validate Before Committing

Always validate your skills:

```bash
aidp skill validate
```

### Preview Before Saving

Test changes without saving:

```bash
aidp skill edit my_skill --dry-run
```

## Troubleshooting

### "Skill not found"

Make sure the skill ID matches exactly:

```bash
aidp skill list  # Check exact ID
aidp skill show the_exact_id
```

### Validation errors

Fix common issues:

```bash
# Check what's wrong
aidp skill validate .aidp/skills/my_skill/SKILL.md

# Common fixes:
# - Version must be X.Y.Z format (e.g., "1.0.0")
# - ID must be lowercase with underscores only
# - All required fields must be present
```

### Routing not working

1. Check routing is enabled in `.aidp/aidp.yml`
2. Verify glob patterns match your file paths
3. Test patterns manually with `fnmatch`

## What You've Learned

✅ How to explore template skills
✅ How to create custom skills with inheritance
✅ How to set up automatic skill routing
✅ How to use skills in your workflow
✅ How to manage and validate skills

## Next Reading

- [Skills User Guide](../how-to/SKILLS_USER_GUIDE.md) - Complete reference
- [Skill Authoring Wizard Design](../explanation/SKILL_AUTHORING_WIZARD_DESIGN.md) - Technical details
- [aidp.yml Example](../../examples/aidp.yml.example) - Configuration options

## Need Help?

- Run `aidp skill --help` for command reference
- Report issues: <https://github.com/viamin/aidp/issues>
- Check the [User Guide](../how-to/SKILLS_USER_GUIDE.md) for detailed documentation

Happy coding! 🚀
