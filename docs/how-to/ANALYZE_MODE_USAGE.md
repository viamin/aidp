# Aidp Analyze Mode Usage Guide

## Overview

Aidp's analyze mode is designed for analyzing legacy codebases to generate documentation and provide refactoring guidance. It uses specialized AI agents and integrates with the ruby-maat gem for repository mining analysis.

## Quick Start

### Basic Usage

```bash
# Start analyze mode
aidp analyze

# Run specific step
aidp analyze 01_REPOSITORY_ANALYSIS

# Force run a step (overrides dependencies)
aidp analyze 02_ARCHITECTURE_ANALYSIS --force

# Rerun a completed step
aidp analyze 03_TEST_COVERAGE_ANALYSIS --rerun
```

### Command Aliases

```bash
# Same as 'aidp analyze'
aidp analyze current
aidp analyze next

# Approve a gate step
aidp analyze-approve

# Reset analyze progress
aidp analyze-reset
```

## Analysis Steps

### 1. Repository Analysis

**Step**: `01_REPOSITORY_ANALYSIS`
**Agent**: Repository Analyst
**Purpose**: Mines Git history to understand code evolution and identify hotspots

**Outputs**:

- `01_REPOSITORY_ANALYSIS.md` - Detailed repository analysis
- `01_REPOSITORY_ANALYSIS.json` - Structured data for further analysis
- Ruby-maat integration results (churn, coupling, authorship)

**Example Output**:

```markdown
# Repository Analysis

## Code Evolution Overview
- **Total Commits**: 1,247
- **Time Span**: 2.5 years
- **Active Contributors**: 8

## Hotspots Identified
1. `lib/core/processor.rb` - High churn (45 revisions)
2. `app/controllers/api_controller.rb` - Complex coupling
3. `spec/integration/api_spec.rb` - Ownership concentration

## Recommendations
- Focus refactoring efforts on high-churn files
- Review coupling in API controller
- Distribute knowledge in test files
```

### 2. Architecture Analysis

**Step**: `02_ARCHITECTURE_ANALYSIS`
**Agent**: Architecture Analyst
**Purpose**: Analyzes system architecture, patterns, and design decisions

**Outputs**:

- `02_ARCHITECTURE_ANALYSIS.md` - Architecture assessment
- `02_ARCHITECTURE_ANALYSIS.json` - Architecture data
- Dependency graphs and pattern analysis

### 3. Test Coverage Analysis

**Step**: `03_TEST_COVERAGE_ANALYSIS`
**Agent**: Test Analyst
**Purpose**: Evaluates test coverage, quality, and testing strategies

**Outputs**:

- `03_TEST_COVERAGE_ANALYSIS.md` - Test coverage report
- `03_TEST_COVERAGE_ANALYSIS.json` - Coverage data
- Test quality metrics and recommendations

### 4. Functionality Analysis

**Step**: `04_FUNCTIONALITY_ANALYSIS`
**Agent**: Functionality Analyst (with feature-specific agents)
**Purpose**: Analyzes features, business logic, and functionality

**Outputs**:

- `04_FUNCTIONALITY_ANALYSIS.md` - Functionality assessment
- `04_FUNCTIONALITY_ANALYSIS.json` - Feature analysis data
- Multi-agent analysis results

### 5. Documentation Analysis

**Step**: `05_DOCUMENTATION_ANALYSIS`
**Agent**: Documentation Analyst
**Purpose**: Evaluates existing documentation and identifies gaps

**Outputs**:

- `05_DOCUMENTATION_ANALYSIS.md` - Documentation assessment
- `05_DOCUMENTATION_ANALYSIS.json` - Documentation data
- Gap analysis and improvement recommendations

### 6. Static Analysis

**Step**: `06_STATIC_ANALYSIS`
**Agent**: Static Analysis Expert
**Purpose**: Runs static analysis tools and interprets results

**Outputs**:

- `06_STATIC_ANALYSIS.md` - Static analysis report
- `06_STATIC_ANALYSIS.json` - Tool results
- Code quality metrics and issues

### 7. Refactoring Recommendations

**Step**: `07_REFACTORING_RECOMMENDATIONS`
**Agent**: Refactoring Specialist
**Purpose**: Provides actionable refactoring guidance

**Outputs**:

- `07_REFACTORING_RECOMMENDATIONS.md` - Refactoring plan
- `07_REFACTORING_RECOMMENDATIONS.json` - Recommendations data
- Prioritized refactoring tasks

## Configuration

### Project-Level Configuration

Create `.aidp-tools.yml` in your project root:

```yaml
# Preferred static analysis tools
preferred_tools:
  ruby:
    - rubocop
    - reek
    - brakeman
  javascript:
    - eslint
    - prettier
  python:
    - flake8
    - pylint

# Tool execution settings
execution_settings:
  parallel_execution: true
  timeout: 300
  retry_attempts: 2

# Integration settings
integrations:
  ruby_maat:
    timeout: 600
```

### User-Level Configuration

Create `~/.aidp-tools.yml` for global preferences:

```yaml
# Global tool preferences
preferred_tools:
  ruby:
    - rubocop
    - reek
  javascript:
    - eslint
  python:
    - flake8

# Default execution settings
execution_settings:
  parallel_execution: true
  timeout: 300
```

## Large Codebase Handling

### Automatic Chunking

For large repositories, analyze mode automatically chunks the codebase:

```bash
# Analyze with automatic chunking
aidp analyze

# View chunking strategy
aidp analyze --chunk-strategy=feature_based
```

**Available Strategies**:

- `time_based` - Chunk by time periods
- `commit_count` - Chunk by number of commits
- `size_based` - Chunk by file size
- `feature_based` - Chunk by features/components

### Manual Chunking Configuration

Create `.aidp-chunk-config.yml`:

```yaml
time_based:
  chunk_size: 30d
  overlap: 7d

commit_count:
  chunk_size: 500
  overlap: 50

size_based:
  chunk_size: 100MB
  overlap: 10MB

feature_based:
  max_features_per_chunk: 5
  include_dependencies: true
```

## Focus Area Selection

### Interactive Selection

```bash
# Start with focus area selection
aidp analyze --interactive
```

This will present:

1. High-priority areas (based on ruby-maat data)
2. Medium-priority areas (based on feature analysis)
3. Low-priority areas (remaining code)
4. Custom focus strategies

### Predefined Focus Areas

```bash
# Focus on specific areas
aidp analyze --focus=api,core,testing
aidp analyze --focus=high-churn
aidp analyze --focus=security-critical
```

## Output Formats

### Markdown (Default)

```bash
aidp analyze
# Generates: 01_REPOSITORY_ANALYSIS.md
```

### JSON Export

```bash
aidp analyze --format=json
# Generates: 01_REPOSITORY_ANALYSIS.json
```

### CSV Export

```bash
aidp analyze --format=csv
# Generates: 01_REPOSITORY_ANALYSIS.csv
```

### Multiple Formats

```bash
aidp analyze --format=markdown,json,csv
# Generates all formats
```

## Progress Tracking

### View Progress

```bash
# View current progress
aidp analyze --status

# View detailed progress
aidp analyze --status --detailed
```

### Progress Files

- `.aidp-analyze-progress.yml` - Current progress
- `.aidp-analyze-progress_history.yml` - Progress history
- `.aidp-analysis.db` - SQLite database with results

### Resume Analysis

```bash
# Resume from where you left off
aidp analyze

# Resume specific step
aidp analyze 04_FUNCTIONALITY_ANALYSIS
```

## Dependencies and Gates

### Dependency Management

Steps have dependencies that must be satisfied:

```bash
# View dependencies
aidp analyze --dependencies

# Force run (ignores dependencies)
aidp analyze 03_TEST_COVERAGE_ANALYSIS --force
```

### Gate Steps

Some steps require human approval:

```bash
# Approve gate step
aidp analyze-approve

# View pending gates
aidp analyze --gates
```

## Error Handling

### Common Issues

**Large Repository Timeout**:

```bash
# Increase timeout for large repos
aidp analyze --timeout=1800
```

**Memory Issues**:

```bash
# Use memory management
aidp analyze --memory-strategy=chunking
```

### Debug Mode

```bash
# Enable debug output
aidp analyze --debug

# View detailed logs
aidp analyze --verbose
```

## Best Practices

### 1. Start Small

```bash
# Begin with repository analysis
aidp analyze 01_REPOSITORY_ANALYSIS

# Review results before proceeding
cat 01_REPOSITORY_ANALYSIS.md
```

### 2. Use Focus Areas

```bash
# Focus on problematic areas first
aidp analyze --focus=high-churn,security-critical
```

### 3. Iterative Analysis

```bash
# Run analysis in phases
aidp analyze 01_REPOSITORY_ANALYSIS
aidp analyze 02_ARCHITECTURE_ANALYSIS
# Review and adjust focus
aidp analyze 03_TEST_COVERAGE_ANALYSIS
```

### 4. Export Results

```bash
# Export for further processing
aidp analyze --format=json,csv
aidp analyze --export=analysis_results.zip
```

### 5. Version Control

```bash
# Commit analysis results
git add *.md *.json
git commit -m "Add analyze mode results"
```

## Integration with CI/CD

### GitHub Actions

```yaml
name: Code Analysis
on: [push, pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.0
      - run: gem install aidp
      - run: aidp analyze --format=json
      - run: aidp analyze --export=analysis_results.zip
      - uses: actions/upload-artifact@v3
        with:
          name: analysis-results
          path: analysis_results.zip
```

### GitLab CI

```yaml
analyze:
  image: ruby:3.0
  script:
    - gem install aidp
    - aidp analyze --format=json
    - aidp analyze --export=analysis_results.zip
  artifacts:
    paths:
      - analysis_results.zip
```

## Troubleshooting

### Performance Issues

**Slow Analysis**:

```bash
# Use parallel processing
aidp analyze --parallel

# Reduce analysis scope
aidp analyze --focus=critical-only
```

**Memory Issues**:

```bash
# Use streaming mode
aidp analyze --memory-strategy=streaming

# Increase system memory
aidp analyze --memory-limit=4GB
```

### Tool Integration Issues

**Missing Tools**:

```bash
# Install missing tools
aidp analyze --install-tools

# Use available tools only
aidp analyze --skip-missing-tools
```

**Tool Configuration**:

```bash
# View tool configuration
aidp analyze --show-tool-config

# Update tool configuration
aidp analyze --update-tool-config
```

### Data Issues

**Corrupted Progress**:

```bash
# Reset progress
aidp analyze-reset

# Backup and restore
cp .aidp-analyze-progress.yml .aidp-analyze-progress.yml.backup
```

**Database Issues**:

```bash
# Rebuild database
aidp analyze --rebuild-database

# Export and import data
aidp analyze --export-database=analysis.db
aidp analyze --import-database=analysis.db
```

## Advanced Features

### Custom Templates

Create custom analysis templates in `templates/ANALYZE/`:

```markdown
# Custom Analysis Template

## Analysis Context
{{project_context}}

## Analysis Focus
{{analysis_focus}}

## Expected Output
{{expected_output}}
```

### Custom Agents

Extend agent personas in `lib/aidp/agent_personas.rb`:

```ruby
CUSTOM_PERSONA = {
  name: 'Custom Analyst',
  expertise: ['custom_domain'],
  characteristics: ['detailed', 'practical'],
  tools: ['custom_tool'],
  output_style: 'structured'
}
```

### Plugin System

Create custom analysis plugins:

```ruby
module Aidp
  module CustomPlugin
    def self.analyze(project_dir, options = {})
      # Custom analysis logic
    end
  end
end
```

## Support and Community

### Getting Help

- **Documentation**: Check this guide and inline help
- **Issues**: Report bugs on GitHub
- **Discussions**: Join community discussions
- **Examples**: See `examples/` directory

### Contributing

- **Bug Reports**: Include steps to reproduce
- **Feature Requests**: Describe use case and benefits
- **Code Contributions**: Follow contribution guidelines
- **Documentation**: Help improve this guide

### Resources

- **GitHub Repository**: <https://github.com/viamin/aidp>
- **Issues**: <https://github.com/viamin/aidp/issues>
- **Discussions**: <https://github.com/viamin/aidp/discussions>
- **Examples**: <https://github.com/viamin/aidp/examples>
