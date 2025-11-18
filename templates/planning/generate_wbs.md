# Generate Work Breakdown Structure (WBS)

You are creating a phase-based Work Breakdown Structure.

## Input

Read:

- `.aidp/docs/PRD.md` - Requirements
- `.aidp/docs/TECH_DESIGN.md` - Technical approach

## Your Task

Generate a hierarchical breakdown of ALL work needed to deliver this project.

## WBS Structure

A Work Breakdown Structure organizes project work into:

1. **Phases** - Major project stages (Requirements, Design, Implementation, Testing, Deployment)
2. **Tasks** - Specific work items within each phase
3. **Subtasks** - Detailed breakdown of complex tasks
4. **Dependencies** - What must complete before this task
5. **Effort Estimates** - Story points or time estimates

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

## Implementation

**For Ruby/AIDP projects**, use the `ruby_aidp_planning` skill to:

1. Parse PRD and technical design documents using `Aidp::Planning::Parsers::DocumentParser`
2. Generate WBS structure using `Aidp::Planning::Generators::WBSGenerator`
3. Format as markdown
4. Write to `.aidp/docs/WBS.md`

The skill provides the complete Ruby implementation including:

- Module requires and namespacing
- Class instantiation
- Method calls with proper parameters
- File I/O operations

**For other language implementations**, implement equivalent functionality:

1. Parse input documents to extract requirements and design
2. Decompose into phases and tasks
3. Calculate effort estimates
4. Identify dependencies
5. Generate hierarchical markdown output

## Output

Write complete WBS to `.aidp/docs/WBS.md` with:

- All phases listed
- Tasks under each phase
- Subtasks where applicable
- Dependencies identified
- Effort estimates included
- Generated timestamp and metadata
