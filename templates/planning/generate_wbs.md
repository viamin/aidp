# Generate Work Breakdown Structure (WBS)

You are creating a phase-based Work Breakdown Structure.

## Input

Read:
- `.aidp/docs/PRD.md` - Requirements
- `.aidp/docs/TECH_DESIGN.md` - Technical approach

## Your Task

Generate a hierarchical breakdown of ALL work needed to deliver this project.

## WBS Structure

Use the WBSGenerator Ruby class to create the structure programmatically:

```ruby
require_relative '../../../lib/aidp/planning/generators/wbs_generator'
require_relative '../../../lib/aidp/planning/parsers/document_parser'

parser = Aidp::Planning::Parsers::DocumentParser.new
prd = parser.parse_file('.aidp/docs/PRD.md')
tech_design = parser.parse_file('.aidp/docs/TECH_DESIGN.md')

generator = Aidp::Planning::Generators::WBSGenerator.new
wbs = generator.generate(prd: prd, tech_design: tech_design)
markdown = generator.format_as_markdown(wbs)

File.write('.aidp/docs/WBS.md', markdown)
```

## Default Phases

1. **Requirements** - Finalize all requirements
2. **Design** - Complete architectural and detailed design
3. **Implementation** - Build all features
4. **Testing** - Comprehensive testing
5. **Deployment** - Deploy to production

## Task Attributes

For each task, include:
- **Name**: Clear, action-oriented
- **Description**: What needs to be done
- **Effort**: Story points or time estimate
- **Dependencies**: What must complete first
- **Subtasks**: Breakdown if complex

## Guidelines

- Be comprehensive - include ALL work
- Break large tasks into subtasks
- Identify dependencies clearly
- Provide realistic effort estimates
- Consider parallel work streams

## Output

Write complete WBS to `.aidp/docs/WBS.md` using the generator.
