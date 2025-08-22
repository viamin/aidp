# AI Dev Pipeline (aidp) - Ruby Gem

A portable CLI that automates a complete AI development workflow from idea to implementation using your existing IDE assistants.

## Quick Start

```bash
# Install the gem
gem install aidp

# Navigate to your project
cd /your/project

# Start the workflow
aidp execute next
```

## User Workflow

The gem automates a complete development pipeline with **human-in-the-loop gates** at key decision points. Here's the simplest workflow:

### 1. Start Your Project

```bash
cd /your/project
aidp status                   # Check current progress
aidp execute next             # Run the next pending step
```

### 2. Handle Gate Steps

When you reach a **gate step** (PRD, Architecture, Tasks, Implementation), the AI will:

1. **Generate questions** in a file (e.g., `PRD_QUESTIONS.md`) if it needs more information
2. **Create the main output** (e.g., `docs/PRD.md`)
3. **Wait for your approval** before proceeding

**Your actions at gates:**

```bash
# Review the generated files
cat PRD_QUESTIONS.md          # Check if AI needs more information
cat docs/PRD.md              # Review the output

# If PRD_QUESTIONS.md exists, answer the questions:
# Edit the questions file directly with your answers
nano PRD_QUESTIONS.md         # Add your answers below each question

# Re-run the step to use your answers
aidp execute prd              # AI will read your answers and complete the step

# Once satisfied with the output, approve and continue
aidp approve current          # Mark the step complete
aidp execute next             # Continue to next step
```

### 3. Continue the Pipeline

For non-gate steps, the AI runs automatically:

```bash
aidp execute next             # Run next step automatically
aidp status                   # Check progress
```

### 4. Complete the Workflow

The pipeline includes 15 steps total:

- **Gates**: PRD, Architecture, Tasks, Implementation (require approval)
- **Auto**: NFRs, ADRs, Domains, Contracts, Threat Model, Test Plan, Scaffolding, Static Analysis, Observability, Delivery, Docs Portal, Post-Release

## Key Commands

```bash
aidp status                   # Show progress of all steps
aidp execute next             # Run next pending step
aidp approve current          # Approve current gate step
aidp jobs                     # Monitor background jobs (real-time)
aidp detect                   # See which AI provider will be used
aidp execute <step>           # Run specific step (e.g., prd, arch, tasks)
aidp approve <step>           # Approve specific step
aidp reset                    # Reset all progress (start over)
```

## AI Providers

The gem automatically detects and uses the best available AI provider:

- **Cursor CLI** (`cursor-agent`) - Preferred
- **Claude CLI** (`claude`/`claude-code`) - Fallback
- **Gemini CLI** (`gemini`/`gemini-cli`) - Fallback

### Override Provider

```bash
AIDP_PROVIDER=anthropic aidp execute next
AIDP_LLM_CMD=/usr/local/bin/claude aidp execute next
```

## Background Jobs

AIDP uses background jobs to handle all AI provider executions, providing better reliability and real-time monitoring capabilities.

### Job Monitoring

Monitor running and completed jobs in real-time:

```bash
aidp jobs                     # Show job status with real-time updates
```

The jobs view displays:

- **Running jobs** with live progress updates
- **Queued jobs** waiting to be processed
- **Completed jobs** with execution results
- **Failed jobs** with error details

### Job Controls

From the jobs view, you can:

- **Retry failed jobs** by pressing `r` on a failed job
- **View job details** by pressing `d` on any job
- **Exit monitoring** by pressing `q`

### Job Persistence

- Jobs persist across CLI restarts
- Job history is preserved for analysis
- Failed jobs can be retried at any time
- All job metadata and logs are stored

### Database Setup

AIDP uses PostgreSQL for job management. Ensure PostgreSQL is installed and running:

```bash
# macOS (using Homebrew)
brew install postgresql
brew services start postgresql

# Ubuntu/Debian
sudo apt-get install postgresql postgresql-contrib
sudo systemctl start postgresql

# The database will be created automatically on first use
```

## File-Based Interaction

At gate steps, the AI creates files for interaction instead of requiring real-time chat:

- **Questions files**: `PRD_QUESTIONS.md`, `ARCH_QUESTIONS.md`, `TASKS_QUESTIONS.md`, `IMPL_QUESTIONS.md` - Contains questions if AI needs more information
- **Output files**: `docs/PRD.md`, `docs/Architecture.md` - Review and edit as needed
- **Progress tracking**: `.aidp-progress.yml` - Tracks completion status

### Answering Questions

When the AI creates a questions file, follow these steps:

1. **Edit the file directly**: Add your answers below each question in the file
2. **Re-run the step**: The AI will read your answers and complete the step
3. **Approve when satisfied**: Mark the step complete and continue

The questions file is only created when the AI needs additional information beyond what it can infer from your project structure and existing files. Your answers are preserved for future reference.

## Debug and Logging

```bash
# Enable debug output to see AI provider communication
AIDP_DEBUG=1 aidp execute next

# Log to a file for debugging
AIDP_LOG_FILE=aidp.log aidp execute next

# Combine both for full debugging
AIDP_DEBUG=1 AIDP_LOG_FILE=aidp.log aidp execute next
```

## Workflow Example

Here's a typical session:

```bash
# 1. Start the workflow
aidp execute next
# → Creates docs/PRD.md and PRD_QUESTIONS.md

# 2. Monitor job progress (optional)
aidp jobs
# → Shows real-time job status and progress

# 3. Review the questions (if any)
cat PRD_QUESTIONS.md
# → If questions exist, edit the file with your answers, then re-run

# 4. Review the PRD
cat docs/PRD.md
# → Edit if needed

# 5. Approve and continue
aidp approve current
aidp execute next
# → Creates docs/NFRs.md automatically

# 6. Continue through gates
aidp execute next
# → Creates docs/Architecture.md and ARCH_QUESTIONS.md
# → Repeat review/approve cycle
```

## Development

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linter
bundle exec standardrb

# Auto-fix linting issues
bundle exec standardrb --fix

# Build gem
bundle exec rake build
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and conventional commit guidelines.

## Pipeline Steps

The gem automates a complete 15-step development pipeline:

### Gate Steps (Require Approval)

- **PRD** → Product Requirements Document (`docs/PRD.md`)
- **Architecture** → System architecture and ADRs (`docs/Architecture.md`)
- **Tasks** → Implementation tasks and backlog (`tasks/backlog.yaml`)
- **Implementation** → Implementation strategy and guidance (`docs/ImplementationGuide.md`)

### Automatic Steps

- **NFRs** → Non-Functional Requirements (`docs/NFRs.md`)
- **ADRs** → Architecture Decision Records (`docs/adr/`)
- **Domains** → Domain decomposition (`docs/DomainCharters/`)
- **Contracts** → API/Event contracts (`contracts/`)
- **Threat Model** → Security analysis (`docs/ThreatModel.md`)
- **Test Plan** → Testing strategy (`docs/TestPlan.md`)
- **Scaffolding** → Project structure guidance (`docs/ScaffoldingGuide.md`)
- **Static Analysis** → Code quality tools (`docs/StaticAnalysis.md`)
- **Observability** → Monitoring and SLOs (`docs/Observability.md`)
- **Delivery** → Deployment strategy (`docs/DeliveryPlan.md`)
- **Docs Portal** → Documentation portal (`docs/DocsPortalPlan.md`)
- **Post-Release** → Post-release analysis (`docs/PostReleaseReport.md`)

## Manual Workflow (Alternative)

The gem packages markdown prompts that can also be used directly with Cursor or any LLM. See the `templates/` directory for the individual prompt files that can be run manually.
