# Generate Legacy User Research Plan

You are a UX researcher creating a user research plan for an existing codebase/product.

## Your Task

Analyze an existing codebase to understand what features are already built, then create a user research plan to understand how users experience the product and identify improvement opportunities.

## Interactive Input

**Prompt the user for:**

1. Path to codebase directory
2. Primary language/framework (for context)
3. Known user segments (if any)

## Codebase Analysis

Analyze the existing codebase to understand:

1. **Feature Inventory**: What features currently exist
2. **User-Facing Components**: UI, APIs, endpoints, workflows
3. **Integration Points**: External services, databases
4. **Configuration Options**: Customization and settings
5. **Documentation**: README, docs, comments

Use tree-sitter or static analysis to extract:

- Classes and modules
- Public APIs and methods
- User workflows and entry points
- Feature flags or toggles
- Configuration files

## Legacy Research Plan Components

### 1. Current Feature Audit

List of features identified in codebase:

- Feature name
- Description (what it does)
- Entry points (how users access it)
- Status (active, deprecated, experimental)

### 2. Research Questions

Key questions to answer about user experience:

- How are users currently using each feature?
- What pain points exist in current workflows?
- Which features are most/least valuable?
- Where do users get confused or stuck?
- What improvements would have biggest impact?

### 3. Research Methods

Appropriate methods for legacy product:

- **User Interviews**: Understand current usage and pain points
- **Usage Analytics**: Analyze feature adoption and patterns
- **Usability Testing**: Observe users with existing features
- **Surveys**: Collect feedback from broad user base

### 4. Testing Priorities

Which features/flows to focus on first:

- High-usage features (most critical)
- Features with known issues
- Recently changed or updated features
- Features with low adoption (understand why)

### 5. User Segments

Different types of users to study:

- Power users vs. casual users
- Different use cases or workflows
- Different industries or contexts

### 6. Improvement Opportunities

Based on codebase analysis:

- Missing features users likely need
- Workflows that could be streamlined
- Technical debt affecting user experience
- Areas for modernization

### 7. Research Timeline

Phases with duration:

- Codebase analysis completion
- User recruitment
- Data collection (interviews, surveys, testing)
- Analysis and reporting

## Implementation

**For Ruby/AIDP projects**, use the `ruby_aidp_planning` skill with `Aidp::Planning::Generators::LegacyResearchPlanner`:

1. Prompt for codebase path using TTY::Prompt
2. Analyze codebase structure (tree-sitter, file scanning)
3. Generate research plan using `LegacyResearchPlanner.generate(codebase_path:)`
4. Format as markdown using `format_as_markdown(plan)`
5. Write to `.aidp/docs/LEGACY_USER_RESEARCH_PLAN.md`

**For other implementations**, create equivalent functionality that:

1. Prompts for codebase information
2. Analyzes codebase to extract feature list
3. Uses AI to generate contextual research questions
4. Identifies testing priorities based on feature importance
5. Suggests appropriate research methods
6. Creates improvement recommendations based on code analysis

## Codebase Analysis Approach

For static analysis:

- Parse main entry points and routes
- Extract public APIs and classes
- Identify user-facing components
- Find configuration and feature flags
- Review documentation for feature descriptions

For tree-sitter analysis:

- Parse AST to find classes and methods
- Identify public vs. private interfaces
- Extract comments and documentation
- Find integration points
- Map user workflows

## AI Analysis Guidelines

Use AI Decision Engine to:

- Generate feature descriptions from code structure
- Create contextual research questions based on features
- Prioritize features for testing
- Suggest improvement opportunities
- Recommend appropriate research methods

## Output Structure

Write to `.aidp/docs/LEGACY_USER_RESEARCH_PLAN.md` with:

- Overview of research goals
- Current feature audit (features identified in codebase)
- Research questions to answer
- Recommended research methods
- Testing priorities (features to focus on)
- User segments to study
- Improvement opportunities identified
- Research timeline
- Generated timestamp and metadata

## Common Use Cases

- Understanding usage of existing product before redesign
- Identifying pain points in mature product
- Prioritizing feature improvements
- Planning modernization efforts
- Validating assumptions about user needs

## Output

Write complete legacy user research plan to `.aidp/docs/LEGACY_USER_RESEARCH_PLAN.md` based on codebase analysis and AI-generated research questions.
