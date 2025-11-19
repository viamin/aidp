# Tool Directory System

This document explains the AIDP tool directory compilation, caching, and querying system.

## Overview

The tool directory system provides fast, metadata-driven discovery and selection of AIDP tools (skills, personas, templates). It compiles tool metadata into a cached JSON structure with indexes for efficient querying.

## Architecture

```
┌─────────────────┐
│ Source Files    │
│ (.md with YAML) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Scanner         │  Recursively finds all .md files
│                 │  in configured directories
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Parser          │  Extracts YAML frontmatter
│                 │  Computes file hashes
│                 │  Creates ToolMetadata objects
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Validator       │  Validates required fields
│                 │  Checks for duplicate IDs
│                 │  Resolves dependencies
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Compiler        │  Builds indexes
│                 │  Creates dependency graph
│                 │  Generates statistics
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Cache           │  Writes tool_directory.json
│                 │  Stores file hashes
│                 │  Manages TTL
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Query Interface │  Filters by tags/types
│                 │  Ranks by priority
│                 │  Resolves dependencies
└─────────────────┘
```

## Components

### Scanner (`lib/aidp/metadata/scanner.rb`)

Recursively scans configured directories for `.md` files.

**Features:**
- Recursive directory traversal
- File filtering
- Change detection (compares file hashes)

**Example:**
```ruby
scanner = Aidp::Metadata::Scanner.new([".aidp/skills", ".aidp/templates"])
tools = scanner.scan_all
```

### Parser (`lib/aidp/metadata/parser.rb`)

Extracts YAML frontmatter and creates `ToolMetadata` objects.

**Features:**
- YAML frontmatter parsing
- File hash computation (SHA256)
- Legacy skill format conversion
- Type auto-detection

**Example:**
```ruby
metadata = Aidp::Metadata::Parser.parse_file("/path/to/skill.md")
```

### Validator (`lib/aidp/metadata/validator.rb`)

Validates tool metadata and detects issues.

**Checks:**
- Required fields present
- Field type validation
- Duplicate ID detection
- Dependency resolution
- Version format validation

**Example:**
```ruby
validator = Aidp::Metadata::Validator.new(tools)
results = validator.validate_all

results.each do |result|
  puts "#{result.tool_id}: #{result.valid? ? "PASS" : "FAIL"}"
  result.errors.each { |err| puts "  ERROR: #{err}" }
  result.warnings.each { |warn| puts "  WARNING: #{warn}" }
end
```

### Compiler (`lib/aidp/metadata/compiler.rb`)

Compiles tool metadata into a cached directory structure.

**Builds:**
- Tool catalog (all metadata)
- Indexes by type, tag, work unit type
- Dependency graph
- Statistics

**Example:**
```ruby
compiler = Aidp::Metadata::Compiler.new(
  directories: [".aidp/skills", ".aidp/templates"],
  strict: false
)
directory = compiler.compile(output_path: ".aidp/cache/tool_directory.json")
```

### Cache (`lib/aidp/metadata/cache.rb`)

Manages cached tool directory with automatic invalidation.

**Features:**
- TTL-based expiration (default: 24 hours)
- File hash-based change detection
- Automatic regeneration on changes
- Graceful degradation

**Example:**
```ruby
cache = Aidp::Metadata::Cache.new(
  cache_path: ".aidp/cache/tool_directory.json",
  directories: [".aidp/skills", ".aidp/templates"],
  ttl: 86400  # 24 hours
)

# Load from cache or regenerate if stale
directory = cache.load

# Force regeneration
directory = cache.reload
```

### Query (`lib/aidp/metadata/query.rb`)

Query interface for finding and filtering tools.

**Features:**
- Find by ID, type, tags, work unit type
- Multi-criteria filtering
- Priority-based ranking
- Dependency resolution
- Statistics

**Example:**
```ruby
query = Aidp::Metadata::Query.new(cache: cache)

# Find by ID
tool = query.find_by_id("ruby_rspec_tdd")

# Find by tags
tools = query.find_by_tags(["ruby", "testing"])

# Find by work unit type
tools = query.find_by_work_unit_type("implementation")

# Complex filtering
tools = query.filter(
  type: "skill",
  tags: ["ruby"],
  work_unit_type: "testing",
  experimental: false
)

# Rank by priority
ranked = query.rank_by_priority(tools)

# Resolve dependencies
deps = query.resolve_dependencies("ruby_rspec_tdd")
```

## Directory Structure

The compiled `tool_directory.json` has this structure:

```json
{
  "version": "1.0.0",
  "compiled_at": "2025-11-19T12:00:00Z",

  "tools": [
    {
      "type": "skill",
      "id": "ruby_rspec_tdd",
      "title": "Ruby RSpec TDD Expert",
      "summary": "Expert in Test-Driven Development",
      "version": "1.0.0",
      "applies_to": ["ruby", "testing", "tdd"],
      "work_unit_types": ["implementation", "testing"],
      "priority": 8,
      "capabilities": ["test_generation"],
      "dependencies": ["ruby_basics"],
      "experimental": false,
      "source_path": "/path/to/skill.md",
      "file_hash": "abc123..."
    }
  ],

  "indexes": {
    "by_type": {
      "skill": ["ruby_rspec_tdd", "..."],
      "template": ["..."]
    },
    "by_tag": {
      "ruby": ["ruby_rspec_tdd", "..."],
      "testing": ["ruby_rspec_tdd", "..."]
    },
    "by_work_unit_type": {
      "implementation": ["ruby_rspec_tdd", "..."],
      "testing": ["ruby_rspec_tdd", "..."]
    }
  },

  "dependency_graph": {
    "ruby_rspec_tdd": {
      "dependencies": ["ruby_basics"],
      "dependents": []
    }
  },

  "statistics": {
    "total_tools": 42,
    "by_type": {
      "skill": 15,
      "template": 27
    },
    "total_tags": 50,
    "total_work_unit_types": 8
  }
}
```

## Cache Invalidation

The cache is automatically regenerated when:

1. **TTL expires** (default: 24 hours)
2. **Files change** (detected via SHA256 hashes)
3. **Manual reload** (`aidp tools reload`)

### How File Change Detection Works

1. On compilation, compute SHA256 hash for each source file
2. Store hashes in `.aidp/cache/tool_directory.json.hashes`
3. On load, compute current hashes and compare
4. If any hash differs, regenerate cache

**Example `.aidp/cache/tool_directory.json.hashes`:**
```json
{
  "/path/to/skill1.md": "abc123...",
  "/path/to/skill2.md": "def456..."
}
```

## Configuration

Configure in `.aidp/aidp.yml`:

```yaml
tool_metadata:
  # Enable metadata system
  enabled: true

  # Directories to scan (in order)
  directories:
    - .aidp/skills        # Project-specific skills
    - .aidp/personas      # Project-specific personas
    - .aidp/templates     # Project-specific templates
    # Built-in directories are automatically added

  # Cache file location
  cache_file: .aidp/cache/tool_directory.json

  # Cache TTL in seconds (default: 86400 = 24 hours)
  ttl: 86400

  # Strict mode (fail compilation on validation errors)
  strict: false
```

## CLI Commands

```bash
# Validate all metadata
aidp tools lint

# Show tool details
aidp tools info <tool_id>

# Force regenerate cache
aidp tools reload

# List all tools
aidp tools list
```

## Integration Points

### Prompt Generation

The query interface can be integrated into prompt generation to automatically select relevant tools:

```ruby
# Example integration (future implementation)
query = Aidp::Metadata::Query.new(cache: cache)

# Find tools for a work unit
work_unit_type = "implementation"
tags = ["ruby", "testing"]

tools = query.filter(
  type: "skill",
  tags: tags,
  work_unit_type: work_unit_type,
  experimental: false
)

# Rank by priority
ranked_tools = query.rank_by_priority(tools)

# Select top tool
best_tool = ranked_tools.first
```

### AI Decision Engine

The metadata system can be queried by the AI decision engine for tool selection:

```ruby
# Let AI choose which tool to use
decision = AIDecisionEngine.decide(
  prompt: "Choose the best skill for TDD implementation in Ruby",
  context: {
    available_tools: query.find_by_tags(["ruby", "testing"]),
    work_unit_type: "implementation",
    project_context: "..."
  }
)
```

## Performance

**Compilation Time:**
- ~100 tools: <1 second
- ~1000 tools: ~5 seconds

**Query Time:**
- By ID: O(1) - instant
- By tag: O(1) index lookup + O(n) filtering
- By multiple criteria: O(n) where n = matching tools

**Cache Loading:**
- Cold cache (regenerate): 1-5 seconds
- Warm cache (valid): <100ms

## Error Handling

### Validation Errors

When `strict: false` (default):
- Invalid tools are logged as warnings
- Compilation continues with valid tools
- Error log written to `.aidp/logs/metadata_errors.log`

When `strict: true`:
- Validation errors fail compilation
- Exception raised
- No cache file generated

### Missing Dependencies

- Detected during validation
- Reported as errors
- Circular dependencies raise exception

### File Format Errors

- Invalid YAML: exception with line number
- Missing frontmatter: validation error
- Malformed UTF-8: automatic conversion attempted

## Best Practices

### For Tool Authors

1. **Always validate** after editing: `aidp tools lint`
2. **Use semantic versioning** for version numbers
3. **Keep tags focused** (3-7 relevant tags)
4. **Set appropriate priority** (most tools should be 5-7)
5. **Document dependencies** explicitly
6. **Write clear summaries** (one sentence)

### For System Integrators

1. **Cache aggressively** - use the Query interface, don't recompile
2. **Handle failures gracefully** - tools may be temporarily invalid
3. **Log tool selection decisions** - for debugging and optimization
4. **Monitor cache hit rate** - regeneration should be rare
5. **Use TTL wisely** - 24 hours is good for most use cases

## Troubleshooting

### Cache always regenerating

- Check file permissions on `.aidp/cache/`
- Verify `.aidp/cache/tool_directory.json.hashes` is writable
- Look for file encoding issues (should be UTF-8)

### Tools not found

- Run `aidp tools list` to see all available tools
- Check `directories` configuration in `aidp.yml`
- Verify file has valid YAML frontmatter
- Run `aidp tools lint` to check for validation errors

### Slow queries

- Cache should be loaded once and reused
- Don't create new Query instances per query
- Use indexes (by_type, by_tag) when possible
- Consider reducing tool count if >10,000 tools

## See Also

- [METADATA_HEADERS.md](METADATA_HEADERS.md) - Metadata schema reference
- [CONFIGURATION.md](CONFIGURATION.md) - Configuration reference
- [CLI_USER_GUIDE.md](CLI_USER_GUIDE.md) - CLI command reference
