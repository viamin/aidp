# Tree-sitter Static Analysis

The Tree-sitter static analysis feature provides advanced code analysis capabilities using Tree-sitter parsers to build a comprehensive knowledge base of your codebase structure, dependencies, and complexity metrics.

## Overview

This feature implements Michael Feathers' "Working Effectively with Legacy Code" strategies by:

- **Seam Detection**: Identifying integration points and dependency injection opportunities
- **Hotspot Analysis**: Finding high-change, high-complexity areas that need attention
- **Dependency Mapping**: Mapping import/require relationships and detecting cycles
- **Test Gap Analysis**: Identifying untested public APIs and recommending characterization tests

## Quick Start

### Basic Usage

```bash
# Run Tree-sitter analysis on Ruby files
aidp analyze code

# Analyze multiple languages
aidp analyze code --langs ruby,js,ts,py

# Use more threads for faster processing
aidp analyze code --threads 8

# Rebuild knowledge base from scratch
aidp analyze code --rebuild
```

### Inspecting Results

```bash
# Show summary of analysis results
aidp kb show summary

# Show detected seams (integration points)
aidp kb show seams

# Show code hotspots
aidp kb show hotspots

# Show dependency cycles
aidp kb show cycles

# Show untested public APIs
aidp kb show apis
```

### Generating Visualizations

```bash
# Generate import dependency graph in DOT format
aidp kb graph imports --format dot --output imports.dot

# Generate Mermaid diagram
aidp kb graph imports --format mermaid --output imports.mmd

# Generate JSON graph data
aidp kb graph imports --format json --output imports.json
```

## Knowledge Base Structure

The analysis generates a comprehensive knowledge base in `.aidp/kb/` with the following files:

### Core Data Files

- **`symbols.json`** - Classes, modules, methods with metadata (visibility, arity, nesting depth)
- **`imports.json`** - Require/import statements and dependencies
- **`calls.json`** - Method call relationships and edges
- **`metrics.json`** - Complexity and size metrics per method and file

### Analysis Results

- **`seams.json`** - Integration points and dependency injection opportunities
- **`hotspots.json`** - High-change, high-complexity areas ranked by priority
- **`tests.json`** - Test coverage mapping for public APIs
- **`cycles.json`** - Import/dependency cycles with breaking strategies

## Seam Detection

The system identifies three types of seams based on Feathers' strategies:

### I/O Integration Seams

- File operations (`File.*`, `IO.*`, `Dir.*`)
- Network operations (`Net::HTTP.*`, `Socket.*`)
- System operations (`Kernel.system`, `Process.*`)
- Database operations (`ActiveRecord.*`, `Sequel.*`)

**Recommendations**: Extract I/O operations to separate service classes, use dependency injection for external dependencies.

### Global State and Singleton Seams

- Global variables (`$var`, `@@var`)
- Singleton patterns (`include Singleton`, `extend Singleton`)
- Module-level mutable state

**Recommendations**: Replace singletons with dependency injection, encapsulate global state in configuration objects.

### Constructor with Work Seams

- Complex initialization with significant logic
- External dependencies in constructors
- High complexity constructors with multiple branches

**Recommendations**: Extract initialization logic to factory methods, use builder pattern for complex object creation.

## Hotspot Analysis

Hotspots are identified by combining:

- **Change Frequency**: Number of times files have been modified (from git history)
- **Complexity**: Cyclomatic complexity and nesting depth
- **Size**: Lines of code and method count
- **Dependencies**: Fan-in and fan-out metrics

The top 20 hotspots are ranked by score and include specific refactoring recommendations.

## Integration with Analyze Mode

The Tree-sitter analysis integrates seamlessly with the existing analyze mode:

```bash
# Run as part of the full analysis pipeline
aidp analyze 06A_TREE_SITTER_SCAN

# Or run the complete analysis pipeline
aidp analyze
```

The analysis results are consumed by other analysis steps to provide more accurate and actionable recommendations.

## Configuration

### Language Support

Currently supports:

- **Ruby** (primary focus)
- **JavaScript/TypeScript** (basic support)
- **Python** (basic support)

Additional languages can be added by extending the grammar loader.

### File Filtering

The analysis respects `.gitignore` patterns and automatically excludes:

- Common build directories (`tmp/`, `log/`, `vendor/`)
- Node.js dependencies (`node_modules/`)
- Git metadata (`.git/`)
- Aidp internal files (`.aidp/`)

### Performance Tuning

- **Threading**: Use `--threads` to control parallel processing
- **Caching**: Results are cached by file modification time for incremental updates
- **Memory**: Large codebases may require adjusting thread count based on available memory

## Advanced Usage

### Custom Grammar Loading

The system is designed to be extensible. You can add support for additional languages by:

1. Adding grammar configurations to `TreeSitterGrammarLoader::GRAMMAR_CONFIGS`
2. Implementing language-specific node extraction methods
3. Adding file pattern matching for the new language

### Custom Seam Detection

You can extend seam detection by:

1. Adding new patterns to the `Seams` module constants
2. Implementing custom detection methods
3. Adding new seam types and recommendations

### Integration with CI/CD

The knowledge base can be generated as part of CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Generate Knowledge Base
  run: |
    gem install aidp
    aidp analyze code --langs ruby,js,ts
    aidp kb show summary
```

## Troubleshooting

### Common Issues

1. **Memory Issues**: Reduce thread count for large codebases
2. **Parse Errors**: Check for syntax errors in source files
3. **Missing Dependencies**: Ensure `tree_sitter` gem is installed
4. **Permission Issues**: Ensure write access to `.aidp/kb/` directory

### Debug Mode

Enable verbose output for debugging:

```bash
# Run with debug output
AIDP_DEBUG=1 aidp analyze code
```

## Future Enhancements

Planned improvements include:

- **Real Tree-sitter Integration**: Replace mock parsers with actual Tree-sitter grammars
- **Advanced Metrics**: More sophisticated complexity and maintainability metrics
- **IDE Integration**: Real-time analysis and suggestions in development environments
- **Custom Rules**: User-defined seam detection patterns and refactoring rules
- **Visualization**: Interactive dependency graphs and hotspot visualizations

## Contributing

To contribute to the Tree-sitter analysis feature:

1. Add tests for new functionality
2. Follow the existing code patterns and conventions
3. Update documentation for new features
4. Ensure compatibility with existing analyze mode steps

For more information, see the main [README.md](../README.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).
