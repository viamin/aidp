# AIDP Capabilities Reference

**Purpose**: This document describes AIDP's capabilities for AI agents to understand what AIDP can do and help users select appropriate workflows.

## Core Concept

AIDP (AI Development Pipeline) automates development workflows using AI agents in **work loops** - iterative execution where agents work autonomously until completion, with automatic testing and validation feedback.

## Key Features

### Work Loops

- **Autonomous iteration**: Agent works until task is 100% complete
- **Self-managing**: Agent edits PROMPT.md to track progress
- **Automatic validation**: Tests and linters run after each iteration
- **Self-correction**: Agent fixes failures automatically
- **Configurable limits**: max_iterations (default: 50), test_commands, lint_commands

### Two Primary Modes

1. **Analyze Mode**: Understand existing codebases
2. **Execute Mode**: Build new features and systems

## Analyze Mode Capabilities

### Quick Overview

- Repository structure scanning
- High-level functionality mapping
- Documentation review
**Use when**: User wants to understand what a project does

### Style & Patterns

- Code pattern analysis
- Style consistency review
- Generate LLM style guide
**Use when**: User wants coding standards or style enforcement

### Architecture Review

- Architecture pattern analysis
- Dependency mapping
- Component relationships
**Use when**: User needs system design understanding

### Quality Assessment

- Test coverage analysis
- Code quality metrics
- Static analysis review
- Refactoring opportunities
**Use when**: User wants quality improvements

### Deep Analysis

- Complete repository analysis (all above + more)
- Tree-sitter knowledge base creation
**Use when**: User planning major refactoring or extension

## Execute Mode Capabilities

### Quick Prototype

- Minimal planning (basic PRD)
- Testing strategy
- Fast implementation
**Use when**: User wants rapid proof of concept

### Exploration/Experiment

- Quick PRD generation
- Testing + static analysis
- Work loop implementation
**Use when**: User building experiment with basic quality checks

### Feature Development

- Product requirements
- Architecture design
- Testing + static analysis
- Work loop implementation
**Use when**: User building standard production feature

### Production-Ready

- Comprehensive PRD
- Non-functional requirements (NFRs)
- Security + performance reviews
- Observability & SLOs
- Delivery planning
**Use when**: User needs enterprise-grade feature

### Full Enterprise

- Complete governance (all planning docs)
- Architecture decision records (ADRs)
- Domain decomposition
- API design
- Documentation portal
**Use when**: User needs maximum rigor and documentation

## Available Template Steps

### Planning Steps (Execute Mode)

- `00_PRD`: Product Requirements Document
- `00_LLM_STYLE_GUIDE`: Generate project style guide
- `01_NFRS`: Non-Functional Requirements
- `02_ARCHITECTURE`: System Architecture Design
- `03_ADR_FACTORY`: Architecture Decision Records
- `04_DOMAIN_DECOMPOSITION`: Domain Analysis
- `05_API_DESIGN`: API and Interface Design
- `07_SECURITY_REVIEW`: Security Analysis
- `08_PERFORMANCE_REVIEW`: Performance Planning
- `09_RELIABILITY_REVIEW`: Reliability & SRE Planning
- `10_TESTING_STRATEGY`: Testing Strategy
- `11_STATIC_ANALYSIS`: Static Analysis Configuration
- `12_OBSERVABILITY_SLOS`: Monitoring & SLOs
- `13_DELIVERY_ROLLOUT`: Deployment Planning
- `14_DOCS_PORTAL`: Documentation Portal
- `16_IMPLEMENTATION`: Actual development work

### Analysis Steps (Analyze Mode)

- `01_REPOSITORY_ANALYSIS`: Repository structure scan
- `02_ARCHITECTURE_ANALYSIS`: Architecture deep dive
- `03_TEST_ANALYSIS`: Test coverage analysis
- `04_FUNCTIONALITY_ANALYSIS`: Functionality mapping
- `05_DOCUMENTATION_ANALYSIS`: Documentation review
- `06_STATIC_ANALYSIS`: Static analysis review
- `06A_TREE_SITTER_SCAN`: Tree-sitter knowledge base creation
- `07_REFACTORING_RECOMMENDATIONS`: Refactoring suggestions

## Hybrid Workflows

### Legacy Modernization

- Deep analysis + refactoring recommendations
- Architecture design for new system
- Migration planning + implementation
**Use when**: Modernizing legacy code

### Style Guide Enforcement

- Pattern analysis
- Style guide generation
- Static analysis configuration
- Enforcement implementation
**Use when**: Establishing coding standards

### Test Coverage Improvement

- Coverage analysis
- Functionality mapping
- Testing strategy
- Test implementation
**Use when**: Improving test quality

## Matching User Intent to Workflows

### User says: "understand this codebase"

→ Analyze Mode: Quick Overview or Deep Analysis

### User says: "build [feature]"

→ Execute Mode: Feature Development or Production-Ready

### User says: "quick prototype" or "proof of concept"

→ Execute Mode: Quick Prototype or Exploration

### User says: "improve code quality" or "add tests"

→ Hybrid: Test Coverage Improvement or Quality Assessment

### User says: "modernize" or "refactor"

→ Hybrid: Legacy Modernization

### User says: "establish standards" or "style guide"

→ Hybrid: Style Guide Enforcement or Analyze: Style & Patterns

### User says: "enterprise feature" or "production ready"

→ Execute Mode: Production-Ready or Full Enterprise

## Custom Workflows

When existing workflows don't fit:

1. Identify which steps are needed
2. Select from available template steps
3. Combine in logical order (planning → implementation)
4. Can mix analyze and execute steps

### Custom Template Creation

If AIDP lacks a specific template step:

- Base on existing templates in `templates/` directory
- Follow template structure (## Task, ## Questions, ## Context, etc.)
- Keep concise to preserve context window
- Follow LLM_STYLE_GUIDE conventions
- Must be within AIDP's capabilities (analysis or code generation)

## AIDP Strengths

✅ **Excellent for**:

- Iterative development with validation
- Pattern-based code generation
- Analysis and documentation
- Multi-step workflows with dependencies
- Quality-gated development (tests must pass)

❌ **Not suitable for**:

- Real-time interactive applications
- Tasks requiring human judgment calls
- Workflows without clear completion criteria
- Tasks needing external service access not configured

## Configuration Requirements

Users need `aidp.yml` with:

- Provider configuration (Claude, Cursor, Gemini, etc.)
- Work loop settings (enabled, max_iterations)
- Test commands (optional but recommended)
- Lint commands (optional but recommended)

## Key Constraints

- Work loops require clear completion criteria
- Templates must fit in context window
- Tests and linters should run quickly
- Agent needs write access to PROMPT.md
- All work through provider APIs (respects rate limits)
