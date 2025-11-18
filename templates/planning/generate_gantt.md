# Generate Gantt Chart and Critical Path

You are creating a Mermaid Gantt chart with critical path analysis.

## Input

Read `.aidp/docs/WBS.md` - Work breakdown structure with tasks and dependencies

## Your Task

Generate a Gantt chart in Mermaid format showing timeline, dependencies, and critical path.

## Implementation

Use the GanttGenerator class:

```ruby
require_relative '../../../lib/aidp/planning/generators/gantt_generator'
require_relative '../../../lib/aidp/planning/generators/wbs_generator'
require_relative '../../../lib/aidp/planning/parsers/document_parser'

# Load WBS
parser = Aidp::Planning::Parsers::DocumentParser.new
prd = parser.parse_file('.aidp/docs/PRD.md')
wbs_generator = Aidp::Planning::Generators::WBSGenerator.new
wbs = wbs_generator.generate(prd: prd)

# Generate Gantt chart
gantt_generator = Aidp::Planning::Generators::GanttGenerator.new
gantt = gantt_generator.generate(wbs: wbs)

# Write output
output = ["# Project Gantt Chart", ""]
output << "Generated: #{Time.now.iso8601}"
output << ""
output << "## Timeline Visualization"
output << ""
output << "```mermaid"
output << gantt[:mermaid]
output << "```"
output << ""
output << "## Critical Path"
output << ""
output << "The following tasks form the critical path (longest dependency chain):"
output << ""
gantt[:critical_path].each_with_index do |task_id, idx|
  output << "#{idx + 1}. #{task_id}"
end

File.write('.aidp/docs/GANTT.md', output.join("\n"))
```

## Critical Path

The critical path represents the longest sequence of dependent tasks. Any delay in critical path tasks delays the entire project.

## Gantt Features

- Phase-based sections
- Task dependencies (after relationships)
- Critical tasks highlighted
- Relative durations based on effort estimates

## Output

Write Gantt chart with critical path to `.aidp/docs/GANTT.md`
