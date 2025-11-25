# Implementation Guide: Metadata-Driven Skill/Persona/Template Discovery (Issue #270)

## Overview

This guide provides architectural patterns, design decisions, and implementation strategies for the metadata-driven tool discovery system in AIDP. The implementation enables intelligent selection of skills, personas, and templates based on YAML frontmatter metadata, improving prompt generation and tool selection for AI agents.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Domain Model](#domain-model)
3. [Design Patterns](#design-patterns)
4. [Implementation Contract](#implementation-contract)
5. [Component Design](#component-design)
6. [Testing Strategy](#testing-strategy)
7. [Pattern-to-Use-Case Matrix](#pattern-to-use-case-matrix)
8. [Error Handling Strategy](#error-handling-strategy)
9. [Configuration Schema](#configuration-schema)

---

## Architecture Overview

### Hexagonal Architecture Layers

```plaintext
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ CLI Commands     │           │ Prompt Builder   │        │
│  │ (tools lint/info)│           │ (Tool Selection) │        │
│  └──────────────────┘           └──────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                            │
│  ┌────────────────────────────────────────────┐             │
│  │  ToolMetadata (Value Object)               │             │
│  │  - type, id, title, summary, version       │             │
│  │  - applies_to, work_unit_types, priority   │             │
│  │  - capabilities, dependencies              │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  Parser (Service)                          │             │
│  │  - Extracts YAML frontmatter               │             │
│  │  - Normalizes legacy formats               │             │
│  │  - Computes file hashes                    │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  Validator (Service)                       │             │
│  │  - Required field validation               │             │
│  │  - Duplicate ID detection                  │             │
│  │  - Dependency resolution checks            │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  Compiler (Service)                        │             │
│  │  - Aggregates metadata                     │             │
│  │  - Builds indexes (by type, tag, WUT)      │             │
│  │  - Generates dependency graph              │             │
│  │  - Outputs tool_directory.json             │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  Query (Service)                           │             │
│  │  - Filters tools by criteria               │             │
│  │  - Ranks by priority                       │             │
│  │  - Resolves dependencies                   │             │
│  └────────────────────────────────────────────┘             │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  Cache (Service)                           │             │
│  │  - Loads compiled directory                │             │
│  │  - Detects file changes                    │             │
│  │  - Invalidates on TTL/change               │             │
│  └────────────────────────────────────────────┘             │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Infrastructure Layer                       │
│  ┌──────────────────┐           ┌──────────────────┐        │
│  │ Filesystem       │           │ JSON Serializer  │        │
│  │ (File I/O)       │           │ (tool_directory) │        │
│  └──────────────────┘           └──────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **Composition Over Inheritance**: All services are independent, composed together via dependency injection
2. **Single Responsibility**: Each class has one clear purpose (parse, validate, compile, query, cache)
3. **Dependency Injection**: All dependencies injected for testability and flexibility
4. **Value Objects**: ToolMetadata is immutable after creation with validation
5. **Service Objects**: Stateless services for parsing, validation, compilation, querying
6. **Repository Pattern**: Cache acts as repository for compiled tool directory
7. **Strategy Pattern**: Different validation and normalization strategies per tool type

---

## Domain Model

### Core Entities

#### ToolMetadata (Value Object)

Represents metadata for a skill, persona, or template. Immutable after creation.

```ruby
# Represents the metadata of a tool (skill, persona, or template)
{
  type: String,              # "skill", "persona", or "template"
  id: String,                # Unique identifier (lowercase_alphanumeric_underscore)
  title: String,             # Human-readable title
  summary: String,           # Brief one-line summary
  version: String,           # Semantic version (X.Y.Z)
  applies_to: Array<String>, # Tags indicating applicability (e.g., ["ruby", "testing"])
  work_unit_types: Array<String>, # Work unit types supported (e.g., ["implementation"])
  priority: Integer,         # Priority for ranking (1-10, default 5)
  capabilities: Array<String>, # Capabilities provided
  dependencies: Array<String>, # IDs of required tools
  experimental: Boolean,     # Experimental flag
  content: String,           # Tool content (markdown)
  source_path: String,       # Path to source .md file
  file_hash: String          # SHA256 hash of source file
}
```

#### ValidationResult (Value Object)

Result of validating a tool's metadata.

```ruby
ValidationResult = Struct.new(
  :tool_id,      # String - Tool ID
  :file_path,    # String - Source file path
  :valid,        # Boolean - Validation passed
  :errors,       # Array<String> - Validation errors
  :warnings,     # Array<String> - Validation warnings
  keyword_init: true
)
```

### Domain Services

#### Parser

**Responsibility**: Extract and parse YAML frontmatter from markdown files

**Pattern**: Service Object

**Contract**:

```ruby
# Parse metadata from a file
# @param file_path [String] Path to .md file
# @param type [String, nil] Tool type or nil to auto-detect
# @return [ToolMetadata] Parsed metadata
# @raise [Aidp::Errors::ValidationError] if format is invalid
#
# Preconditions:
#   - file_path must exist and be readable
#   - File must have YAML frontmatter (--- delimited)
#
# Postconditions:
#   - Returns valid ToolMetadata instance
#   - File hash computed via SHA256
#   - Legacy formats normalized to new schema
def self.parse_file(file_path, type: nil)
```

#### Validator

**Responsibility**: Validate tool metadata and detect issues

**Pattern**: Service Object + Visitor Pattern

**Contract**:

```ruby
# Validate all tools
# @param tools [Array<ToolMetadata>] Tools to validate
# @return [Array<ValidationResult>] Validation results
#
# Preconditions:
#   - tools must be an array of ToolMetadata instances
#
# Postconditions:
#   - Returns ValidationResult for each tool
#   - Detects duplicate IDs across tools
#   - Validates dependencies are satisfied
#   - Logs validation errors and warnings
def validate_all
```

#### Compiler

**Responsibility**: Compile tool directory with indexes and dependency graph

**Pattern**: Service Object + Builder Pattern

**Contract**:

```ruby
# Compile tool directory
# @param output_path [String] Path to output JSON file
# @return [Hash] Compiled directory structure
#
# Preconditions:
#   - directories must be configured
#   - directories must be readable
#
# Postconditions:
#   - Scans all directories for .md files
#   - Validates all tools
#   - Builds indexes (by_type, by_tag, by_work_unit_type)
#   - Builds dependency graph
#   - Writes JSON to output_path
#   - Returns compiled directory structure
def compile(output_path:)
```

#### Query

**Responsibility**: Query and filter tools from compiled directory

**Pattern**: Repository Pattern + Query Object

**Contract**:

```ruby
# Filter tools by multiple criteria
# @param type [String, nil] Tool type filter
# @param tags [Array<String>, nil] Tag filter (any matching tag)
# @param work_unit_type [String, nil] Work unit type filter
# @param experimental [Boolean, nil] Experimental filter
# @return [Array<Hash>] Filtered tools
#
# Preconditions:
#   - directory must be loaded from cache
#
# Postconditions:
#   - Returns tools matching ALL criteria (AND logic)
#   - Empty array if no matches
#   - Tools are ranked by priority (highest first)
def filter(type:, tags:, work_unit_type:, experimental:)
```

#### Cache

**Responsibility**: Manage cached tool directory with automatic invalidation

**Pattern**: Repository Pattern + Cache Invalidation

**Contract**:

```ruby
# Load tool directory from cache or regenerate
# @return [Hash] Tool directory structure
#
# Preconditions:
#   - cache_path configured
#   - directories configured
#
# Postconditions:
#   - Returns cached directory if valid (not expired, files unchanged)
#   - Regenerates directory if cache invalid
#   - Saves file hashes for change detection
#   - Logs cache hits/misses
def load
```

---

## Design Patterns

### 1. Value Object Pattern

**Purpose**: Immutable data structures with built-in validation

**Application**: `ToolMetadata`

**Benefits**:

- Prevents invalid state
- Self-validating
- Immutable after creation
- Easy to test

**Implementation**:

```ruby
class ToolMetadata
  attr_reader :type, :id, :title, :summary, :version, ...

  def initialize(type:, id:, title:, summary:, version:, ...)
    @type = type
    @id = id
    # ...
    validate!  # Validate on construction
  end

  private

  def validate!
    validate_required_fields!
    validate_types!
    validate_formats!
    validate_ranges!
  end
end
```

### 2. Service Object Pattern

**Purpose**: Encapsulate complex operations as stateless services

**Application**: `Parser`, `Validator`, `Compiler`, `Scanner`

**Benefits**:

- Single Responsibility Principle
- Reusable across application
- Easy to test
- Clear dependencies

**Implementation**:

```ruby
class Parser
  def self.parse_file(file_path, type: nil)
    # Stateless operation
    # No instance state required
  end
end
```

### 3. Repository Pattern

**Purpose**: Abstract data access and caching logic

**Application**: `Cache`

**Benefits**:

- Single source of truth for tool directory
- Encapsulates cache invalidation logic
- Testable with mock repositories
- Clear interface for clients

**Implementation**:

```ruby
class Cache
  def load
    cache_valid? ? load_from_cache : regenerate
  end

  def reload
    regenerate  # Force reload
  end

  private

  def cache_valid?
    !cache_expired? && !files_changed?
  end
end
```

### 4. Query Object Pattern

**Purpose**: Encapsulate complex query logic

**Application**: `Query`

**Benefits**:

- Fluent interface for filtering
- Composable queries
- Testable in isolation
- Clear intent

**Implementation**:

```ruby
class Query
  def filter(type: nil, tags: nil, work_unit_type: nil, experimental: nil)
    tools = directory["tools"]
    tools = tools.select { |t| t["type"] == type } if type
    tools = filter_by_tags(tools, tags) if tags
    tools = filter_by_work_unit_type(tools, work_unit_type) if work_unit_type
    tools = tools.select { |t| t["experimental"] == experimental } unless experimental.nil?
    tools
  end

  def rank_by_priority(tools)
    tools.sort_by { |t| -(t["priority"] || DEFAULT_PRIORITY) }
  end
end
```

### 5. Builder Pattern

**Purpose**: Construct complex objects step by step

**Application**: Compiler index building

**Benefits**:

- Separates construction from representation
- Supports incremental building
- Clear construction process

**Implementation**:

```ruby
class Compiler
  def build_indexes
    @indexes = {
      by_id: {},
      by_type: {},
      by_tag: {},
      by_work_unit_type: {}
    }

    @tools.each do |tool|
      add_to_id_index(tool)
      add_to_type_index(tool)
      add_to_tag_index(tool)
      add_to_work_unit_type_index(tool)
    end
  end
end
```

### 6. Strategy Pattern

**Purpose**: Different normalization strategies for legacy formats

**Application**: Metadata normalization in Parser

**Benefits**:

- Easy to add new legacy format support
- Clear separation of concerns
- Testable strategies

**Implementation**:

```ruby
class Parser
  def self.normalize_metadata(metadata, type:)
    # Strategy: detect and normalize legacy formats
    normalized = {}
    normalized["title"] = metadata["title"] || metadata["name"]  # Legacy "name"
    normalized["summary"] = metadata["summary"] || metadata["description"]  # Legacy
    normalized["applies_to"] = extract_applies_to(metadata)  # Combine keywords, tags
    normalized
  end
end
```

### 7. Dependency Graph Pattern

**Purpose**: Model and resolve tool dependencies

**Application**: Dependency resolution in Compiler and Query

**Benefits**:

- Topological sort for dependency order
- Cycle detection
- Transitive dependency resolution

**Implementation**:

```ruby
def build_dependency_graph
  @dependency_graph = {}

  @tools.each do |tool|
    @dependency_graph[tool.id] = {
      dependencies: tool.dependencies,
      dependents: []
    }
  end

  # Build reverse edges (dependents)
  @tools.each do |tool|
    tool.dependencies.each do |dep_id|
      @dependency_graph[dep_id][:dependents] << tool.id if @dependency_graph[dep_id]
    end
  end
end
```

---

## Implementation Contract

### Design by Contract Principles

All public methods specify:

1. **Preconditions**: What must be true before the method executes
2. **Postconditions**: What will be true after the method executes
3. **Invariants**: What remains true throughout the object's lifetime

### Example Contracts

#### Parser#parse_file

```ruby
# Parse metadata from a file
#
# @param file_path [String] Path to .md file
# @param type [String, nil] Tool type or nil to auto-detect
# @return [ToolMetadata] Parsed metadata
#
# Preconditions:
#   - file_path must exist and be readable
#   - File must start with YAML frontmatter (---)
#   - YAML frontmatter must be valid
#   - Required fields must be present (type, id, title, summary, version)
#
# Postconditions:
#   - Returns valid ToolMetadata instance
#   - file_hash computed via SHA256
#   - Legacy formats normalized to new schema
#   - Content extracted (without frontmatter)
#
# Invariants:
#   - Parser has no state (class methods only)
#   - Original file is not modified
def self.parse_file(file_path, type: nil)
  Aidp.log_debug("metadata", "Parsing file", file: file_path, type: type)

  unless File.exist?(file_path)
    raise Aidp::Errors::ValidationError, "File not found: #{file_path}"
  end

  content = File.read(file_path, encoding: "UTF-8")
  file_hash = compute_file_hash(content)
  type ||= detect_type(file_path)

  parse_string(content, source_path: file_path, file_hash: file_hash, type: type)
end
```

#### Validator#validate_all

```ruby
# Validate all tools
#
# @return [Array<ValidationResult>] Validation results for each tool
#
# Preconditions:
#   - @tools must be initialized (may be empty)
#   - Each tool in @tools must be a ToolMetadata instance
#
# Postconditions:
#   - Returns ValidationResult for each tool
#   - Validates required fields for each tool
#   - Detects duplicate IDs across all tools
#   - Validates dependencies are satisfied
#   - Logs validation summary (total, valid, invalid count)
#
# Side Effects:
#   - Logs validation errors and warnings
def validate_all
  Aidp.log_debug("metadata", "Validating all tools", count: @tools.size)

  results = @tools.map { |tool| validate_tool(tool) }

  # Cross-tool validations
  validate_duplicate_ids(results)
  validate_dependencies(results)

  Aidp.log_info(
    "metadata",
    "Validation complete",
    total: results.size,
    valid: results.count(&:valid),
    invalid: results.count { |r| !r.valid }
  )

  results
end
```

#### Compiler#compile

```ruby
# Compile tool directory
#
# @param output_path [String] Path to output JSON file
# @return [Hash] Compiled directory structure
#
# Preconditions:
#   - @directories must be configured (may be empty)
#   - Directories must be readable
#   - output_path parent directory must exist or be creatable
#
# Postconditions:
#   - Scans all configured directories for .md files
#   - Parses all tools found
#   - Validates all tools
#   - Builds indexes (by_type, by_tag, by_work_unit_type)
#   - Builds dependency graph
#   - Writes JSON to output_path
#   - Returns compiled directory structure
#   - In strict mode: raises if validation errors found
#   - In non-strict mode: excludes invalid tools, logs warnings
#
# Side Effects:
#   - Creates output directory if needed
#   - Writes tool_directory.json
#   - Logs compilation progress and summary
def compile(output_path:)
  Aidp.log_info("metadata", "Compiling tool directory",
    directories: @directories, output: output_path)

  scanner = Scanner.new(@directories)
  @tools = scanner.scan_all

  validator = Validator.new(@tools)
  validation_results = validator.validate_all

  handle_validation_results(validation_results)

  build_indexes
  build_dependency_graph

  directory = create_directory_structure
  write_directory(directory, output_path)

  Aidp.log_info("metadata", "Compilation complete",
    tools: @tools.size, output: output_path)

  directory
end
```

#### Query#filter

```ruby
# Filter tools by multiple criteria
#
# @param type [String, nil] Tool type filter
# @param tags [Array<String>, nil] Tag filter
# @param work_unit_type [String, nil] Work unit type filter
# @param experimental [Boolean, nil] Experimental filter
# @return [Array<Hash>] Filtered tools
#
# Preconditions:
#   - directory must be loaded (via #load or explicit load)
#   - directory must have "tools" key
#
# Postconditions:
#   - Returns tools matching ALL criteria (AND logic)
#   - Empty array if no matches
#   - Tags are case-insensitive
#   - Work unit types are case-insensitive
#   - Returns tool hashes (not ToolMetadata objects)
#
# Invariants:
#   - Original directory is not modified
#   - Results are a subset of directory["tools"]
def filter(type: nil, tags: nil, work_unit_type: nil, experimental: nil)
  Aidp.log_debug("metadata", "Filtering tools",
    type: type, tags: tags, work_unit_type: work_unit_type, experimental: experimental)

  tools = directory["tools"]
  tools = tools.select { |t| t["type"] == type } if type
  tools = filter_by_tags(tools, tags) if tags && !tags.empty?
  tools = filter_by_work_unit_type(tools, work_unit_type) if work_unit_type
  tools = tools.select { |t| t["experimental"] == experimental } unless experimental.nil?

  Aidp.log_debug("metadata", "Filtered tools", count: tools.size)

  tools
end
```

#### Cache#load

```ruby
# Load tool directory from cache or regenerate
#
# @return [Hash] Tool directory structure
#
# Preconditions:
#   - @cache_path configured
#   - @directories configured
#   - Directories must be readable
#
# Postconditions:
#   - Returns cached directory if valid (not expired, files unchanged)
#   - Regenerates directory if cache invalid
#   - Saves file hashes for change detection
#   - Logs cache hits/misses
#
# Side Effects:
#   - May regenerate cache (scan, parse, validate, compile)
#   - May write tool_directory.json
#   - May write file_hashes.json
#   - Logs cache status
def load
  Aidp.log_debug("metadata", "Loading cache", path: @cache_path)

  if cache_valid?
    Aidp.log_debug("metadata", "Using cached directory")
    load_from_cache
  else
    Aidp.log_info("metadata", "Cache invalid, regenerating")
    regenerate
  end
end
```

---

## Component Design

### Directory Structure

```text
lib/aidp/metadata/
├── tool_metadata.rb    # Value object for tool metadata
├── parser.rb           # Parse YAML frontmatter
├── validator.rb        # Validate metadata
├── scanner.rb          # Scan directories for .md files
├── compiler.rb         # Compile tool directory with indexes
├── query.rb            # Query interface for tool selection
└── cache.rb            # Cache management with invalidation
```

### Component Dependencies

```text
Cache → Compiler → Scanner → Parser → ToolMetadata
  ↓        ↓
Query    Validator
```

**Dependency Flow**:

1. `Cache` depends on `Compiler` for regeneration
2. `Compiler` depends on `Scanner` and `Validator`
3. `Scanner` depends on `Parser`
4. `Parser` depends on `ToolMetadata`
5. `Validator` depends on `ToolMetadata`
6. `Query` depends on `Cache` for directory access

### File Format Example

#### Skill with Metadata

```markdown
---
type: skill
id: ruby_rspec_tdd
title: Ruby RSpec TDD Implementer
summary: Expert in Test-Driven Development with RSpec
version: 1.0.0
applies_to:
  - ruby
  - testing
  - rspec
work_unit_types:
  - implementation
  - testing
priority: 8
capabilities:
  - Test-first development
  - RSpec best practices
  - Mock and stub patterns
dependencies: []
experimental: false
---

# Ruby RSpec TDD Skill

You are an expert in Test-Driven Development using RSpec...

[Skill content continues...]
```

### Compiled Directory Structure

```json
{
  "version": "1.0.0",
  "compiled_at": "2025-11-22T12:00:00Z",
  "tools": [
    {
      "type": "skill",
      "id": "ruby_rspec_tdd",
      "title": "Ruby RSpec TDD Implementer",
      "summary": "Expert in Test-Driven Development with RSpec",
      "version": "1.0.0",
      "applies_to": ["ruby", "testing", "rspec"],
      "work_unit_types": ["implementation", "testing"],
      "priority": 8,
      "capabilities": ["Test-first development", "RSpec best practices"],
      "dependencies": [],
      "experimental": false,
      "source_path": "/path/to/SKILL.md",
      "file_hash": "abc123..."
    }
  ],
  "indexes": {
    "by_type": {
      "skill": ["ruby_rspec_tdd"],
      "persona": [],
      "template": []
    },
    "by_tag": {
      "ruby": ["ruby_rspec_tdd"],
      "testing": ["ruby_rspec_tdd"],
      "rspec": ["ruby_rspec_tdd"]
    },
    "by_work_unit_type": {
      "implementation": ["ruby_rspec_tdd"],
      "testing": ["ruby_rspec_tdd"]
    }
  },
  "dependency_graph": {
    "ruby_rspec_tdd": {
      "dependencies": [],
      "dependents": []
    }
  },
  "statistics": {
    "total_tools": 1,
    "by_type": {
      "skill": 1,
      "persona": 0,
      "template": 0
    },
    "total_tags": 3,
    "total_work_unit_types": 2
  }
}
```

---

## Testing Strategy

### Unit Tests

#### ToolMetadata Validation

**File**: `spec/aidp/metadata/tool_metadata_spec.rb`

```ruby
RSpec.describe Aidp::Metadata::ToolMetadata do
  describe "#initialize" do
    let(:valid_params) do
      {
        type: "skill",
        id: "test_skill",
        title: "Test Skill",
        summary: "A test skill",
        version: "1.0.0",
        content: "Test content",
        source_path: "/path/to/test.md",
        file_hash: "a" * 64
      }
    end

    it "creates valid metadata" do
      expect { described_class.new(valid_params) }.not_to raise_error
    end

    it "validates required fields" do
      expect { described_class.new(valid_params.except(:id)) }
        .to raise_error(Aidp::Errors::ValidationError, /id is required/)
    end

    it "validates type enum" do
      params = valid_params.merge(type: "invalid")
      expect { described_class.new(params) }
        .to raise_error(Aidp::Errors::ValidationError, /must be one of/)
    end

    it "validates version format" do
      params = valid_params.merge(version: "invalid")
      expect { described_class.new(params) }
        .to raise_error(Aidp::Errors::ValidationError, /must be in format X.Y.Z/)
    end

    it "validates id format" do
      params = valid_params.merge(id: "Invalid-ID")
      expect { described_class.new(params) }
        .to raise_error(Aidp::Errors::ValidationError, /lowercase alphanumeric/)
    end

    it "validates priority range" do
      params = valid_params.merge(priority: 20)
      expect { described_class.new(params) }
        .to raise_error(Aidp::Errors::ValidationError, /between 1 and 10/)
    end

    it "validates file_hash format" do
      params = valid_params.merge(file_hash: "invalid")
      expect { described_class.new(params) }
        .to raise_error(Aidp::Errors::ValidationError, /valid SHA256/)
    end
  end

  describe "#applies_to?" do
    let(:metadata) do
      described_class.new(
        type: "skill",
        id: "test",
        title: "Test",
        summary: "Test",
        version: "1.0.0",
        applies_to: ["ruby", "testing"],
        content: "Test",
        source_path: "/test.md",
        file_hash: "a" * 64
      )
    end

    it "matches when tag is in applies_to" do
      expect(metadata.applies_to?(["ruby"])).to be true
    end

    it "is case-insensitive" do
      expect(metadata.applies_to?(["RUBY"])).to be true
    end

    it "does not match when no tags match" do
      expect(metadata.applies_to?(["python"])).to be false
    end

    it "matches when empty applies_to" do
      metadata = described_class.new(
        type: "skill", id: "test", title: "Test", summary: "Test",
        version: "1.0.0", applies_to: [], content: "Test",
        source_path: "/test.md", file_hash: "a" * 64
      )
      expect(metadata.applies_to?(["anything"])).to be true
    end
  end
end
```

#### Parser Tests

**File**: `spec/aidp/metadata/parser_spec.rb`

```ruby
RSpec.describe Aidp::Metadata::Parser do
  describe ".parse_file" do
    let(:temp_file) { Tempfile.new(["test", ".md"]) }

    after { temp_file.unlink }

    it "parses valid YAML frontmatter" do
      content = <<~MD
        ---
        type: skill
        id: test_skill
        title: Test Skill
        summary: A test skill
        version: 1.0.0
        ---
        # Skill Content

        This is the skill content.
      MD

      temp_file.write(content)
      temp_file.rewind

      metadata = described_class.parse_file(temp_file.path, type: "skill")

      expect(metadata.id).to eq("test_skill")
      expect(metadata.title).to eq("Test Skill")
      expect(metadata.content).to include("Skill Content")
      expect(metadata.file_hash).to match(/^[a-f0-9]{64}$/)
    end

    it "raises error for missing frontmatter" do
      temp_file.write("# No frontmatter\n\nJust content")
      temp_file.rewind

      expect { described_class.parse_file(temp_file.path) }
        .to raise_error(Aidp::Errors::ValidationError, /missing YAML frontmatter/)
    end

    it "raises error for invalid YAML" do
      content = <<~MD
        ---
        invalid: yaml: syntax: error
        ---
        Content
      MD

      temp_file.write(content)
      temp_file.rewind

      expect { described_class.parse_file(temp_file.path) }
        .to raise_error(Aidp::Errors::ValidationError, /Invalid YAML/)
    end

    it "normalizes legacy field names" do
      content = <<~MD
        ---
        type: skill
        id: test
        name: Legacy Name
        description: Legacy description
        version: 1.0.0
        ---
        Content
      MD

      temp_file.write(content)
      temp_file.rewind

      metadata = described_class.parse_file(temp_file.path)

      expect(metadata.title).to eq("Legacy Name")
      expect(metadata.summary).to eq("Legacy description")
    end
  end

  describe ".compute_file_hash" do
    it "computes SHA256 hash" do
      content = "Test content"
      hash = described_class.compute_file_hash(content)

      expect(hash).to match(/^[a-f0-9]{64}$/)
      expect(hash).to eq(Digest::SHA256.hexdigest(content))
    end
  end
end
```

#### Validator Tests

**File**: `spec/aidp/metadata/validator_spec.rb`

```ruby
RSpec.describe Aidp::Metadata::Validator do
  let(:valid_tool) do
    Aidp::Metadata::ToolMetadata.new(
      type: "skill",
      id: "test_skill",
      title: "Test Skill",
      summary: "Test",
      version: "1.0.0",
      content: "Content",
      source_path: "/test.md",
      file_hash: "a" * 64
    )
  end

  describe "#validate_all" do
    it "validates all tools" do
      validator = described_class.new([valid_tool])
      results = validator.validate_all

      expect(results.size).to eq(1)
      expect(results.first.valid).to be true
      expect(results.first.errors).to be_empty
    end

    it "detects duplicate IDs" do
      tool1 = valid_tool
      tool2 = Aidp::Metadata::ToolMetadata.new(
        type: "skill", id: "test_skill", title: "Duplicate",
        summary: "Dup", version: "1.0.0", content: "C",
        source_path: "/dup.md", file_hash: "b" * 64
      )

      validator = described_class.new([tool1, tool2])
      results = validator.validate_all

      expect(results.all?(&:valid)).to be false
      expect(results.first.errors).to include(/Duplicate ID/)
    end

    it "detects missing dependencies" do
      tool = Aidp::Metadata::ToolMetadata.new(
        type: "skill", id: "dependent", title: "Dependent",
        summary: "Dep", version: "1.0.0", dependencies: ["missing_dep"],
        content: "C", source_path: "/dep.md", file_hash: "c" * 64
      )

      validator = described_class.new([tool])
      results = validator.validate_all

      expect(results.first.valid).to be false
      expect(results.first.errors).to include(/Missing dependency/)
    end

    it "warns about empty applies_to and work_unit_types" do
      tool = Aidp::Metadata::ToolMetadata.new(
        type: "skill", id: "empty_tags", title: "Empty",
        summary: "E", version: "1.0.0", applies_to: [],
        work_unit_types: [], content: "C",
        source_path: "/empty.md", file_hash: "d" * 64
      )

      validator = described_class.new([tool])
      results = validator.validate_all

      expect(results.first.valid).to be true
      expect(results.first.warnings).to include(/not be discoverable/)
    end
  end
end
```

#### Compiler Tests

**File**: `spec/aidp/metadata/compiler_spec.rb`

```ruby
RSpec.describe Aidp::Metadata::Compiler do
  let(:temp_dir) { Dir.mktmpdir }
  let(:output_path) { File.join(temp_dir, "tool_directory.json") }

  after { FileUtils.rm_rf(temp_dir) }

  it "compiles tool directory" do
    # Create test skill file
    skills_dir = File.join(temp_dir, "skills")
    FileUtils.mkdir_p(skills_dir)

    skill_path = File.join(skills_dir, "test_skill.md")
    File.write(skill_path, <<~MD)
      ---
      type: skill
      id: test_skill
      title: Test Skill
      summary: A test skill
      version: 1.0.0
      applies_to: [ruby]
      work_unit_types: [implementation]
      priority: 5
      ---
      # Skill Content
    MD

    compiler = described_class.new(directories: [skills_dir])
    directory = compiler.compile(output_path: output_path)

    expect(File.exist?(output_path)).to be true
    expect(directory["tools"].size).to eq(1)
    expect(directory["indexes"]["by_tag"]["ruby"]).to eq(["test_skill"])
    expect(directory["statistics"]["total_tools"]).to eq(1)
  end

  it "builds dependency graph" do
    skills_dir = File.join(temp_dir, "skills")
    FileUtils.mkdir_p(skills_dir)

    # Base skill
    File.write(File.join(skills_dir, "base.md"), <<~MD)
      ---
      type: skill
      id: base_skill
      title: Base Skill
      summary: Base
      version: 1.0.0
      ---
      Base
    MD

    # Dependent skill
    File.write(File.join(skills_dir, "dependent.md"), <<~MD)
      ---
      type: skill
      id: dependent_skill
      title: Dependent Skill
      summary: Dependent
      version: 1.0.0
      dependencies: [base_skill]
      ---
      Dependent
    MD

    compiler = described_class.new(directories: [skills_dir])
    directory = compiler.compile(output_path: output_path)

    expect(directory["dependency_graph"]["base_skill"]["dependents"])
      .to eq(["dependent_skill"])
    expect(directory["dependency_graph"]["dependent_skill"]["dependencies"])
      .to eq(["base_skill"])
  end

  it "handles validation errors in strict mode" do
    skills_dir = File.join(temp_dir, "skills")
    FileUtils.mkdir_p(skills_dir)

    # Invalid skill (missing version)
    File.write(File.join(skills_dir, "invalid.md"), <<~MD)
      ---
      type: skill
      id: invalid
      title: Invalid
      summary: Invalid
      ---
      Invalid
    MD

    compiler = described_class.new(directories: [skills_dir], strict: true)

    expect { compiler.compile(output_path: output_path) }
      .to raise_error(Aidp::Errors::ValidationError)
  end

  it "excludes invalid tools in non-strict mode" do
    skills_dir = File.join(temp_dir, "skills")
    FileUtils.mkdir_p(skills_dir)

    # Valid skill
    File.write(File.join(skills_dir, "valid.md"), <<~MD)
      ---
      type: skill
      id: valid
      title: Valid
      summary: Valid
      version: 1.0.0
      ---
      Valid
    MD

    # Invalid skill
    File.write(File.join(skills_dir, "invalid.md"), <<~MD)
      ---
      type: skill
      id: invalid
      title: Invalid
      summary: Invalid
      ---
      Invalid
    MD

    compiler = described_class.new(directories: [skills_dir], strict: false)
    directory = compiler.compile(output_path: output_path)

    # Only valid tool should be included
    expect(directory["tools"].size).to eq(1)
    expect(directory["tools"].first["id"]).to eq("valid")
  end
end
```

#### Query Tests

**File**: `spec/aidp/metadata/query_spec.rb`

```ruby
RSpec.describe Aidp::Metadata::Query do
  let(:cache) { instance_double(Aidp::Metadata::Cache) }
  let(:query) { described_class.new(cache: cache) }

  let(:directory) do
    {
      "tools" => [
        {
          "type" => "skill",
          "id" => "ruby_skill",
          "title" => "Ruby Skill",
          "applies_to" => ["ruby", "testing"],
          "work_unit_types" => ["implementation"],
          "priority" => 8,
          "experimental" => false
        },
        {
          "type" => "skill",
          "id" => "python_skill",
          "title" => "Python Skill",
          "applies_to" => ["python"],
          "work_unit_types" => ["implementation"],
          "priority" => 5,
          "experimental" => true
        },
        {
          "type" => "template",
          "id" => "test_template",
          "title" => "Test Template",
          "applies_to" => ["testing"],
          "work_unit_types" => ["testing"],
          "priority" => 6,
          "experimental" => false
        }
      ],
      "indexes" => {
        "by_type" => {
          "skill" => ["ruby_skill", "python_skill"],
          "template" => ["test_template"]
        },
        "by_tag" => {
          "ruby" => ["ruby_skill"],
          "python" => ["python_skill"],
          "testing" => ["ruby_skill", "test_template"]
        },
        "by_work_unit_type" => {
          "implementation" => ["ruby_skill", "python_skill"],
          "testing" => ["test_template"]
        }
      },
      "dependency_graph" => {}
    }
  end

  before do
    allow(cache).to receive(:load).and_return(directory)
  end

  describe "#find_by_id" do
    it "finds tool by ID" do
      tool = query.find_by_id("ruby_skill")
      expect(tool["id"]).to eq("ruby_skill")
    end

    it "returns nil for unknown ID" do
      tool = query.find_by_id("unknown")
      expect(tool).to be_nil
    end
  end

  describe "#find_by_type" do
    it "finds all skills" do
      tools = query.find_by_type("skill")
      expect(tools.size).to eq(2)
      expect(tools.map { |t| t["id"] }).to contain_exactly("ruby_skill", "python_skill")
    end

    it "finds all templates" do
      tools = query.find_by_type("template")
      expect(tools.size).to eq(1)
      expect(tools.first["id"]).to eq("test_template")
    end
  end

  describe "#find_by_tags" do
    it "finds tools with any matching tag" do
      tools = query.find_by_tags(["ruby"])
      expect(tools.map { |t| t["id"] }).to eq(["ruby_skill"])
    end

    it "finds tools with multiple tags (OR)" do
      tools = query.find_by_tags(["ruby", "python"])
      expect(tools.size).to eq(2)
    end

    it "is case-insensitive" do
      tools = query.find_by_tags(["RUBY"])
      expect(tools.size).to eq(1)
    end

    it "supports match_all mode (AND)" do
      tools = query.find_by_tags(["ruby", "testing"], match_all: true)
      expect(tools.map { |t| t["id"] }).to eq(["ruby_skill"])
    end
  end

  describe "#filter" do
    it "filters by type" do
      tools = query.filter(type: "skill")
      expect(tools.size).to eq(2)
    end

    it "filters by tags" do
      tools = query.filter(tags: ["ruby"])
      expect(tools.size).to eq(1)
    end

    it "filters by work_unit_type" do
      tools = query.filter(work_unit_type: "implementation")
      expect(tools.size).to eq(2)
    end

    it "filters by experimental flag" do
      tools = query.filter(experimental: false)
      expect(tools.size).to eq(2)
    end

    it "combines filters (AND logic)" do
      tools = query.filter(
        type: "skill",
        tags: ["testing"],
        experimental: false
      )
      expect(tools.size).to eq(1)
      expect(tools.first["id"]).to eq("ruby_skill")
    end
  end

  describe "#rank_by_priority" do
    it "ranks tools by priority (highest first)" do
      tools = directory["tools"]
      ranked = query.rank_by_priority(tools)

      expect(ranked.map { |t| t["id"] }).to eq([
        "ruby_skill",    # priority 8
        "test_template", # priority 6
        "python_skill"   # priority 5
      ])
    end
  end
end
```

#### Cache Tests

**File**: `spec/aidp/metadata/cache_spec.rb`

```ruby
RSpec.describe Aidp::Metadata::Cache do
  let(:temp_dir) { Dir.mktmpdir }
  let(:cache_path) { File.join(temp_dir, "tool_directory.json") }
  let(:skills_dir) { File.join(temp_dir, "skills") }

  before do
    FileUtils.mkdir_p(skills_dir)

    # Create test skill
    File.write(File.join(skills_dir, "test.md"), <<~MD)
      ---
      type: skill
      id: test
      title: Test
      summary: Test
      version: 1.0.0
      ---
      Content
    MD
  end

  after { FileUtils.rm_rf(temp_dir) }

  describe "#load" do
    let(:cache) do
      described_class.new(
        cache_path: cache_path,
        directories: [skills_dir],
        ttl: 3600
      )
    end

    it "regenerates cache on first load" do
      directory = cache.load

      expect(File.exist?(cache_path)).to be true
      expect(directory["tools"].size).to eq(1)
    end

    it "uses cache on second load" do
      cache.load  # First load (regenerate)

      # Mock compiler to verify it's not called
      allow(Aidp::Metadata::Compiler).to receive(:new).and_call_original

      cache_instance = described_class.new(
        cache_path: cache_path,
        directories: [skills_dir],
        ttl: 3600
      )
      directory = cache_instance.load

      # Should load from cache, not compile
      expect(Aidp::Metadata::Compiler).not_to have_received(:new)
      expect(directory["tools"].size).to eq(1)
    end

    it "regenerates when file changes" do
      cache.load  # First load

      # Modify file
      sleep 0.1  # Ensure mtime changes
      File.write(File.join(skills_dir, "test.md"), <<~MD)
        ---
        type: skill
        id: test
        title: Test Modified
        summary: Test
        version: 1.0.0
        ---
        Modified
      MD

      directory = cache.load

      # Should regenerate due to file change
      tool = directory["tools"].find { |t| t["id"] == "test" }
      expect(tool["title"]).to eq("Test Modified")
    end

    it "regenerates when cache expires" do
      cache_with_short_ttl = described_class.new(
        cache_path: cache_path,
        directories: [skills_dir],
        ttl: 1  # 1 second TTL
      )

      cache_with_short_ttl.load

      sleep 2  # Wait for TTL to expire

      # Mock to verify regeneration
      expect(Aidp::Metadata::Compiler).to receive(:new).and_call_original

      cache_with_short_ttl.load
    end
  end

  describe "#reload" do
    it "forces regeneration" do
      cache = described_class.new(
        cache_path: cache_path,
        directories: [skills_dir]
      )

      cache.load  # First load

      # Force reload
      expect(Aidp::Metadata::Compiler).to receive(:new).and_call_original
      cache.reload
    end
  end
end
```

---

## Pattern-to-Use-Case Matrix

| Use Case | Primary Pattern | Supporting Patterns | Rationale |
| -------- | --------------- | ------------------- | --------- |
| Immutable metadata | Value Object | - | Prevent invalid state, self-validating |
| Parse YAML frontmatter | Service Object | Strategy (normalization) | Stateless operation, reusable |
| Validate metadata | Service Object | Visitor (validation rules) | Single responsibility, composable |
| Scan directories | Service Object | Iterator | Reusable file discovery |
| Compile tool directory | Service Object | Builder (indexes), Repository | Complex aggregation, multiple outputs |
| Query tools | Query Object | Repository | Encapsulate query logic, composable filters |
| Cache management | Repository | Cache Invalidation | Abstract data access, automatic updates |
| Dependency resolution | Graph Algorithm | Topological Sort | Detect cycles, order dependencies |
| Index building | Builder | Hash Maps | Incremental construction, multiple indexes |
| Legacy format support | Strategy | Adapter | Different normalization per format |

---

## Error Handling Strategy

### Principle: Fail Fast for Bugs, Graceful Degradation for Data Issues

#### Fail Fast (Raise Errors)

- Invalid configuration (missing cache_path, directories)
- File not found when explicitly specified
- Corrupt cache files (invalid JSON)
- Circular dependencies
- Invalid YAML frontmatter syntax
- **Strict mode**: Any validation errors

#### Graceful Degradation (Log and Continue)

- Individual file parse failures (skip file, log warning)
- Missing optional fields (use defaults)
- Unknown legacy fields (ignore)
- **Non-strict mode**: Validation errors (exclude tool, log error)

### Error Handling Implementation

```ruby
# Fail fast: Invalid configuration
def initialize(cache_path:, directories:, **opts)
  raise ArgumentError, "cache_path is required" if cache_path.nil?
  raise ArgumentError, "directories must be an array" unless directories.is_a?(Array)
end

# Graceful degradation: Individual file failures
def scan_directory(directory, type: nil)
  md_files.each do |file_path|
    begin
      tool = Parser.parse_file(file_path, type: type)
      tools << tool
    rescue Aidp::Errors::ValidationError => e
      Aidp.log_warn("metadata", "Failed to parse file",
        file: file_path, error: e.message)
      # Continue with next file
    end
  end
end

# Fail fast: Circular dependencies
def resolve_recursive(tool_id, graph, resolved, seen)
  if seen.include?(tool_id)
    raise Aidp::Errors::ValidationError, "Circular dependency detected: #{tool_id}"
  end
  # ...
end

# Strict mode: Fail on validation errors
def handle_validation_results(results)
  invalid_results = results.reject(&:valid)

  if invalid_results.any? && @strict
    raise Aidp::Errors::ValidationError,
      "#{invalid_results.size} tool(s) failed validation (strict mode enabled)"
  end

  # Non-strict: Exclude invalid tools, log warnings
  invalid_ids = invalid_results.map(&:tool_id)
  @tools.reject! { |tool| invalid_ids.include?(tool.id) }
end
```

### Logging Strategy

**Use `Aidp.log_*` extensively**:

```ruby
# Method entry
Aidp.log_debug("metadata", "Parsing file", file: file_path, type: type)

# Success with metrics
Aidp.log_info("metadata", "Scan complete",
  directories: @directories.size,
  tools_found: all_tools.size)

# Warnings (non-fatal)
Aidp.log_warn("metadata", "Failed to parse file",
  file: file_path,
  error: e.message)

# Errors (failures)
Aidp.log_error("metadata", "Tool validation failed",
  tool_id: result.tool_id,
  file: result.file_path,
  errors: result.errors)
```

---

## Configuration Schema

### Extended YAML Schema

```yaml
metadata:
  # Enable/disable metadata-driven tool selection
  enabled: true

  # Directories to scan for tools
  directories:
    - .aidp/skills
    - .aidp/personas
    - .aidp/templates
    - ~/.aidp/global_skills  # Global tools

  # Cache configuration
  cache:
    path: .aidp/cache/tool_directory.json
    ttl: 86400  # 24 hours
    hashes_path: .aidp/cache/tool_directory.json.hashes

  # Validation mode
  strict: false  # Exclude invalid tools instead of failing

  # Default filters for tool selection
  defaults:
    experimental: false  # Exclude experimental tools by default
    min_priority: 3      # Minimum priority threshold
```

### Configuration Accessor Methods

Add to `Configuration` class:

```ruby
# Get metadata configuration
def metadata_config
  get_nested([:metadata]) || default_metadata_config
end

# Check if metadata system is enabled
def metadata_enabled?
  metadata_config[:enabled] != false  # Enabled by default
end

# Get metadata directories
def metadata_directories
  metadata_config[:directories] || default_metadata_directories
end

# Get metadata cache path
def metadata_cache_path
  metadata_config.dig(:cache, :path) || ".aidp/cache/tool_directory.json"
end

# Get metadata cache TTL
def metadata_cache_ttl
  metadata_config.dig(:cache, :ttl) || 86400  # 24 hours
end

# Check strict validation mode
def metadata_strict?
  metadata_config[:strict] == true
end

# Get default experimental filter
def metadata_default_experimental
  metadata_config.dig(:defaults, :experimental)
end

# Get minimum priority filter
def metadata_min_priority
  metadata_config.dig(:defaults, :min_priority) || 1
end

private

def default_metadata_config
  {
    enabled: true,
    directories: default_metadata_directories,
    cache: {
      path: ".aidp/cache/tool_directory.json",
      ttl: 86400
    },
    strict: false,
    defaults: {
      experimental: false,
      min_priority: 3
    }
  }
end

def default_metadata_directories
  [
    ".aidp/skills",
    ".aidp/personas",
    ".aidp/templates"
  ]
end
```

---

## Summary

This implementation guide provides:

1. **Architectural Foundation**: Hexagonal architecture with clear layers and boundaries
2. **Design Patterns**: Value Object, Service Object, Repository, Query Object, Builder, Strategy, Graph Algorithms
3. **Contracts**: Preconditions, postconditions, and invariants for all public methods
4. **Component Design**: Detailed implementation for ToolMetadata, Parser, Validator, Scanner, Compiler, Query, Cache
5. **Testing Strategy**: Comprehensive unit test specifications for all components
6. **Error Handling**: Fail-fast for bugs, graceful degradation for data issues
7. **Configuration Schema**: Extended YAML configuration with sensible defaults
8. **Observability**: Extensive logging and metrics recommendations

The implementation follows AIDP's engineering principles:

- **SOLID Principles**: Single responsibility, composition, dependency inversion
- **Domain-Driven Design**: Clear domain models, value objects, and services
- **Composition First**: Favor composition over inheritance throughout
- **Design by Contract**: Explicit preconditions, postconditions, and invariants
- **Instrumentation**: Extensive logging with `Aidp.log_debug/info/warn/error`
- **Testability**: Dependency injection, clear interfaces, comprehensive specs
- **Immutability**: Value objects prevent invalid state
- **Cache Invalidation**: Automatic regeneration on file changes or TTL expiration

This guide enables implementation with confidence, clarity, and adherence to AIDP's standards.
