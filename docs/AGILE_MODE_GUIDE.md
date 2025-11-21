# Agile Development Mode Guide

Complete guide to using AIDP's Agile Development Mode for iterative product development with user feedback loops.

## Table of Contents

- [Overview](#overview)
- [When to Use Agile Mode](#when-to-use-agile-mode)
- [Workflows](#workflows)
  - [MVP Planning](#mvp-planning)
  - [Iteration Planning](#iteration-planning)
  - [Legacy Research](#legacy-research)
- [Getting Started](#getting-started)
- [Workflow Details](#workflow-details)
- [Output Artifacts](#output-artifacts)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

Agile Development Mode transforms AIDP from a traditional waterfall planning tool into an iterative, user-centered development system. It helps you:

- **Define MVP scope** - Separate must-have features from nice-to-haves
- **Plan user testing** - Generate comprehensive user research plans
- **Analyze feedback** - AI-powered semantic analysis of user feedback
- **Iterate intelligently** - Plan next iterations based on actual user needs
- **Market effectively** - Translate technical features into customer value

### Key Features

- **Zero Framework Cognition** - AI-powered semantic analysis (no heuristics or regex)
- **Markdown-First** - All outputs version-controllable
- **Multi-Format Support** - Ingest feedback from CSV, JSON, or markdown
- **Three New Personas** - Product Manager, UX Researcher, Marketing Strategist
- **Iterative Loops** - Continuous improvement based on real user data

## When to Use Agile Mode

### Use Agile Mode When

✅ Building a new product and want to validate with users early
✅ Starting with an MVP and planning iterative releases
✅ Have existing user feedback data to analyze
✅ Need to understand user needs for an existing product
✅ Want to translate technical features into marketing materials
✅ Planning research for a legacy codebase

### Use Waterfall Mode When

❌ Building well-defined features with known requirements
❌ Working on internal tools without user feedback loops
❌ Implementing a complete specification up front
❌ Need comprehensive technical design before starting

### Comparison: Agile vs Waterfall

| Aspect | Agile Mode | Waterfall Mode |
| ------ | ---------- | -------------- |
| **Planning Approach** | Iterative, user-centered | Comprehensive, up-front |
| **Scope Definition** | MVP with deferred features | Complete feature set |
| **User Involvement** | Built-in feedback loops | Documentation review only |
| **Marketing** | Value propositions & messaging | Technical documentation |
| **Research** | User testing plans | Architecture analysis |
| **Iteration** | Feedback-driven improvements | Fixed scope execution |

## Workflows

Agile Mode provides three distinct workflows:

### 1. MVP Planning

**Purpose**: Define a minimum viable product from a PRD, create user testing plan, and generate marketing materials.

**When to use**:

- Starting a new product
- Launching an MVP
- Need to prioritize features

**Input**: Product Requirements Document (PRD)

**Outputs**:

- MVP Scope (must-have vs nice-to-have features)
- User Testing Plan (surveys, interviews, metrics)
- Marketing Report (value propositions, messaging, launch checklist)

**Time**: ~15-30 minutes

### 2. Iteration Planning

**Purpose**: Analyze user feedback and plan the next development iteration.

**When to use**:

- Received user feedback from MVP
- Planning next release
- Need to prioritize improvements

**Input**:

- User Feedback Data (CSV/JSON/markdown)
- Current MVP Scope (optional)

**Outputs**:

- Feedback Analysis (insights, trends, recommendations)
- Iteration Plan (improvements, new features, bug fixes, tasks)

**Time**: ~10-20 minutes

### 3. Legacy Research

**Purpose**: Analyze an existing codebase and create a user research plan.

**When to use**:

- Understanding usage of existing product
- Planning modernization efforts
- Identifying pain points in mature product

**Input**:

- Codebase path
- Programming language
- Known user segments (optional)

**Outputs**:

- Legacy Research Plan (feature audit, research questions, testing priorities)
- User Testing Plan (recruitment, methodology, timeline)

**Time**: ~20-40 minutes (depends on codebase size)

## Getting Started

### Prerequisites

1. **AIDP Installed**: `gem install aidp`
2. **AI Provider Configured**: Run `aidp config --interactive`
3. **Project Initialized**: Navigate to your project directory

### Quick Start: MVP Planning

```bash
# Navigate to your project
cd /path/to/your/project

# Start AIDP
aidp execute

# Select workflow
# → "Agile MVP Planning"

# Provide PRD (one of):
# - Path to existing PRD file
# - Generate interactively with AI

# Optionally provide priorities
# (or let workflow prompt you)

# Review generated artifacts in .aidp/docs/
```

### Quick Start: Iteration Planning

```bash
# Prepare feedback data in one of these formats:
# - CSV with columns: id, timestamp, rating, feedback, feature, sentiment
# - JSON array of feedback objects
# - Markdown with feedback sections

# Start AIDP
aidp execute

# Select workflow
# → "Agile Iteration Planning"

# Provide feedback file path
# → /path/to/feedback.csv

# Optionally provide current MVP scope
# → .aidp/docs/MVP_SCOPE.md

# Review analysis and iteration plan
```

### Quick Start: Legacy Research

```bash
# Start AIDP
aidp execute

# Select workflow
# → "Legacy Product Research"

# Provide codebase information:
# - Path to codebase: /path/to/codebase
# - Language: Ruby (or auto-detect)
# - Known user segments: (optional)

# Review research plan and testing strategy
```

## Workflow Details

### MVP Planning Workflow

#### Step 1: PRD Input

Provide a Product Requirements Document describing your product vision:

##### Option A: Use Existing PRD

```bash
Path to PRD: docs/prd.md
```

##### Option B: Generate PRD Interactively

```bash
# AIDP will ask questions:
# - What problem does this solve?
# - Who are the target users?
# - What are the key features?
# - What are the success criteria?
```

#### Step 2: Priority Collection

AIDP will ask you to prioritize features interactively:

```text
📋 Feature Prioritization

Based on your PRD, we identified these features:
1. User authentication
2. Dashboard with metrics
3. Report generation
4. Email notifications
5. API access

On a scale of 1-5, how important is each feature for the MVP?
(1 = Nice to have, 5 = Critical)

Feature: User authentication
Priority (1-5): 5

Feature: Dashboard with metrics
Priority (1-5): 5

Feature: Report generation
Priority (1-5): 4
...
```

#### Step 3: AI Analysis & Scope Generation

AIDP uses AI to analyze your PRD and priorities to generate:

1. **MVP Features** - Must-have for first release
2. **Deferred Features** - Important but not critical
3. **Out of Scope** - Future considerations
4. **Success Criteria** - How to measure MVP success

#### Step 4: User Testing Plan

AIDP generates a comprehensive user testing plan:

- **Testing Stages** (Alpha, Beta, Launch)
- **Recruitment Criteria** (user segments, demographics)
- **Survey Questions** (Likert scale, multiple choice, open-ended)
- **Interview Guides** (topic areas, sample questions)
- **Success Metrics** (quantitative and qualitative)

#### Step 5: Marketing Report

AIDP translates technical features into customer value:

- **Value Propositions** - Customer benefits for each feature
- **Key Messages** - Positioning statements
- **Differentiators** - Competitive advantages
- **Target Personas** - Customer segments
- **Launch Checklist** - Go-to-market tasks

#### Step 6: Review Artifacts

All outputs are written to `.aidp/docs/`:

```bash
.aidp/docs/
├── PRD.md                  # Product requirements (if generated)
├── MVP_SCOPE.md            # MVP feature breakdown
├── USER_TEST_PLAN.md       # Comprehensive testing plan
└── MARKETING_REPORT.md     # Customer-facing messaging
```

### Iteration Planning Workflow

#### Step 1: Feedback Data Ingestion

Provide user feedback in one of these formats:

**CSV Format**:

```csv
id,timestamp,rating,feedback,feature,sentiment
user123,2025-01-15,4,"Great dashboard!",dashboard,positive
user456,2025-01-15,2,"Login is confusing",authentication,negative
```

**JSON Format**:

```json
[
  {
    "id": "user123",
    "timestamp": "2025-01-15",
    "rating": 4,
    "feedback": "Great dashboard!",
    "feature": "dashboard",
    "sentiment": "positive"
  }
]
```

**Markdown Format**:

```markdown
## Response 1
**ID:** user123
**Timestamp:** 2025-01-15
**Rating:** 4
**Feedback:** Great dashboard!
**Feature:** dashboard
**Sentiment:** positive
```

#### Step 2: AI-Powered Analysis

AIDP performs semantic analysis using Zero Framework Cognition:

- **Sentiment Breakdown** - Distribution of positive/negative/neutral feedback
- **Key Findings** - 3-5 major discoveries with evidence
- **Trends & Patterns** - Recurring themes across responses
- **Insights by Category** - Usability, features, performance, value
- **Feature-Specific Feedback** - Feedback grouped by feature
- **Priority Issues** - Critical items requiring attention
- **Recommendations** - 4-6 actionable next steps

**No Regex, No Heuristics** - All analysis uses AI semantic understanding.

#### Step 3: Iteration Plan Generation

AIDP transforms insights into actionable tasks:

- **Iteration Goals** - 3-5 measurable objectives
- **Feature Improvements** - Enhancements with effort/impact estimates
- **New Features** - Additions based on user requests
- **Bug Fixes** - Prioritized defects to resolve
- **Technical Debt** - Infrastructure improvements
- **Task Breakdown** - Specific, assignable work items
- **Success Metrics** - How to measure iteration success
- **Risks & Mitigation** - What could go wrong

#### Step 4: Review & Execute

```bash
.aidp/docs/
├── feedback_data.json           # Normalized feedback
├── USER_FEEDBACK_ANALYSIS.md    # AI analysis with insights
└── NEXT_ITERATION_PLAN.md       # Prioritized task breakdown
```

### Legacy Research Workflow

#### Step 1: Codebase Analysis

AIDP scans your existing codebase to understand:

- **Feature Inventory** - What features currently exist
- **User-Facing Components** - UI, APIs, workflows
- **Integration Points** - External services, databases
- **Configuration Options** - Customization available
- **Documentation** - README, docs, comments

#### Step 2: Research Plan Generation

AIDP creates a user research plan based on codebase analysis:

- **Current Feature Audit** - Comprehensive feature list
- **Research Questions** - What to learn about user experience
- **Research Methods** - Interviews, surveys, analytics, usability testing
- **Testing Priorities** - Which features to focus on first
- **User Segments** - Different user types to study
- **Improvement Opportunities** - Potential enhancements
- **Timeline** - Research phases and duration

#### Step 3: User Testing Plan

AIDP generates testing methodology:

- **Recruitment Criteria** - Who to interview
- **Testing Stages** - Phases of research
- **Interview Guides** - Questions to ask
- **Success Metrics** - How to measure findings

#### Step 4: Review Research Strategy

```bash
.aidp/docs/
├── LEGACY_USER_RESEARCH_PLAN.md  # Research strategy
└── USER_TEST_PLAN.md              # Testing methodology
```

## Output Artifacts

### MVP_SCOPE.md

**Structure**:

```markdown
# MVP Scope

## Overview
- Focus and rationale
- Target launch timeline
- Success criteria

## Must-Have Features
### 1. Feature Name
- Description
- User value
- Acceptance criteria
- Dependencies
- Effort estimate

## Deferred Features
### 1. Feature Name
- Why deferred
- Revisit in iteration

## Out of Scope
- Features explicitly excluded
```

### USER_TEST_PLAN.md

**Structure**:

```markdown
# User Testing Plan

## Overview
- Research goals
- Timeline
- Recruitment needs

## Testing Stages

### Alpha Testing
- Participants: 5-10 early adopters
- Duration: 2 weeks
- Focus: Core usability

### Beta Testing
- Participants: 50-100 users
- Duration: 4 weeks
- Focus: Broader validation

## Survey Questions

### Satisfaction (Likert Scale)
1. How satisfied are you with [feature]?
   (1 = Very Unsatisfied, 5 = Very Satisfied)

### Multiple Choice
1. Which feature do you use most often?
   a) Feature A
   b) Feature B
   c) Feature C

### Open-Ended
1. What improvements would you suggest?

## Interview Guide
- Topic areas
- Sample questions
- Probes and follow-ups

## Success Metrics
- Quantitative: NPS, satisfaction scores, completion rates
- Qualitative: Key themes, feature requests
```

### MARKETING_REPORT.md

**Structure**:

```markdown
# Marketing Report

## Value Propositions

### For Persona A
- Primary benefit
- Secondary benefits
- Proof points

## Key Messages

### Message 1: [Theme]
- Message
- Supporting evidence
- Channels

## Differentiators
- Competitive advantage 1
- Competitive advantage 2

## Messaging Framework
| Persona | Pain Point | Solution | Value |
| --------- | ----------- | ---------- | ------- |
| ... | ... | ... | ... |

## Launch Checklist
- [ ] Website copy updated
- [ ] Demo video created
- [ ] Sales deck prepared
```

### USER_FEEDBACK_ANALYSIS.md

**Structure**:

```markdown
# User Feedback Analysis

## Executive Summary
High-level overview (2-3 paragraphs)

## Sentiment Breakdown
| Sentiment | Count | Percentage |
| ----------- | ------- | ------------ |
| Positive | 42 | 60% |
| Neutral | 15 | 21% |
| Negative | 13 | 19% |

## Key Findings

### Finding 1: [Title]
**Description**: ...
**Evidence**: "Quote from user", "Another quote"
**Impact**: High

## Trends and Patterns
- Trend 1: Description (frequency, implications)
- Trend 2: Description

## Insights by Category

### Usability
- Observation 1
- Observation 2

### Features
- What's working
- What's missing

## Priority Issues
1. **Issue Title** (Critical)
   - Description
   - Affected users: 40%
   - Recommended action

## Recommendations
1. **Recommendation Title**
   - Description
   - Rationale
   - Effort: Medium
   - Impact: High
```

### NEXT_ITERATION_PLAN.md

**Structure**:

```markdown
# Next Iteration Plan

## Overview
- Focus
- Rationale
- Expected outcomes

## Iteration Goals
1. Goal 1 (measurable)
2. Goal 2 (measurable)
3. Goal 3 (measurable)

## Feature Improvements
### 1. Feature Name
- Current issue
- Proposed improvement
- User impact
- Effort: Medium
- Priority: High

## New Features
### 1. Feature Name
- Description
- Rationale
- Acceptance criteria
- Effort: High

## Bug Fixes
### 1. Bug Title (Priority: Critical)
- Description
- Affected users: 30%
- Fix approach

## Task Breakdown
### Task 1: [Name]
- Category: feature
- Priority: high
- Effort: 3 days
- Dependencies: None
- Success criteria

## Success Metrics
- Metric 1: Target value
- Metric 2: Target value

## Risks and Mitigation
### Risk 1
- Probability: Medium
- Impact: High
- Mitigation: Strategy

## Timeline
- Week 1: Phase 1 activities
- Week 2: Phase 2 activities
```

## Best Practices

### MVP Planning

✅ **Do**:

- Involve stakeholders in priority collection
- Be ruthless about MVP scope (less is more)
- Use real user quotes in PRD if available
- Review marketing report with sales/marketing teams
- Test with actual users during alpha/beta

❌ **Don't**:

- Include every feature in MVP (defeats purpose)
- Skip user testing plan (feedback is critical)
- Ignore marketing materials (go-to-market matters)
- Set unrealistic timelines
- Forget to define success criteria

### Iteration Planning

✅ **Do**:

- Collect feedback systematically (surveys, interviews)
- Include both positive and negative feedback
- Review analysis for surprises (AI finds patterns humans miss)
- Prioritize high-impact, low-effort improvements
- Set measurable iteration goals
- Track success metrics after iteration

❌ **Don't**:

- Cherry-pick feedback (include all responses)
- Ignore positive feedback (know what to preserve)
- Over-generalize from limited data
- Add too many features in one iteration
- Skip technical debt (it compounds)
- Forget to validate assumptions with users

### Legacy Research

✅ **Do**:

- Run on complete codebase (not partial)
- Review generated feature list for accuracy
- Involve long-time users in research
- Focus on high-usage and problematic features
- Use research to guide modernization

❌ **Don't**:

- Skip codebase analysis (generates better questions)
- Ignore low-adoption features (understand why)
- Plan research without budget/resources
- Rush through user recruitment
- Forget to document current state before changes

## Examples

### Example 1: SaaS Dashboard MVP

**Scenario**: Building a new analytics dashboard for SaaS customers.

**Workflow**: MVP Planning

**Input**:

```markdown
# PRD: Analytics Dashboard

## Problem
SaaS customers can't easily understand usage patterns.

## Solution
Real-time analytics dashboard with key metrics.

## Features
- User activity tracking
- Usage metrics (DAU, MAU, retention)
- Custom reports
- Email digests
- API access
- Export to CSV/PDF
```

**User Priorities**:

- User activity: 5/5 (Critical)
- Usage metrics: 5/5 (Critical)
- Custom reports: 4/5 (Important)
- Email digests: 3/5 (Nice to have)
- API access: 2/5 (Future)
- Export: 3/5 (Nice to have)

**Generated MVP Scope**:

**Must-Have**:

1. User activity tracking
2. Core usage metrics (DAU, MAU, retention)
3. Basic reporting interface

**Deferred**:

1. Custom report builder
2. Email digests
3. Export functionality

**Out of Scope**:

1. API access (v2.0)
2. Advanced analytics (ML predictions)

**Outcome**: Shipped MVP in 6 weeks, gathered feedback from 50 beta users, planned iteration based on actual usage.

### Example 2: Mobile App Feedback Analysis

**Scenario**: Received 150 user feedback responses from beta testing a mobile app.

**Workflow**: Iteration Planning

**Feedback Data** (CSV):

```csv
id,timestamp,rating,feedback,feature,sentiment
u1,2025-01-15,5,"Love the UI!",interface,positive
u2,2025-01-15,2,"App crashes often",stability,negative
u3,2025-01-15,4,"Fast and responsive",performance,positive
u4,2025-01-15,1,"Can't find settings",navigation,negative
...
```

**AI Analysis Findings**:

**Key Finding 1**: Stability issues (High Impact)

- 35% of users mentioned crashes
- Most common on Android 13
- Usually during photo upload

**Key Finding 2**: Navigation confusion (High Impact)

- 28% couldn't find settings
- Onboarding needed
- Menu structure unclear

**Key Finding 3**: Performance praised (Positive)

- 60% mentioned speed positively
- Differentiator vs. competitors

**Iteration Plan**:

**Improvements**:

1. Fix Android 13 crash during photo upload (Priority: Critical, Effort: Medium)
2. Add onboarding tutorial (Priority: High, Effort: High)
3. Redesign settings navigation (Priority: High, Effort: Medium)

**Tasks**:

1. Debug photo upload on Android 13 (3 days)
2. Create onboarding flow mockups (2 days)
3. User test navigation with 10 users (1 week)
4. Implement onboarding tutorial (5 days)

**Outcome**: Iteration completed in 3 weeks, crash rate dropped 80%, user satisfaction increased from 3.2 to 4.5.

### Example 3: Legacy CRM System Research

**Scenario**: 10-year-old CRM system with usability complaints. Need to understand user pain points before modernization.

**Workflow**: Legacy Research

**Input**:

- Codebase: `/path/to/crm`
- Language: Ruby on Rails
- Known users: Sales reps, account managers, executives

**Generated Feature Audit**:

1. **Contact Management** (Entry: /contacts)
   - Create/edit contacts
   - Search and filtering
   - Contact history
   - Status: Active, complex UI

2. **Deal Pipeline** (Entry: /deals)
   - Drag-and-drop pipeline
   - Deal stages
   - Forecasting
   - Status: Active, frequently used

3. **Reporting** (Entry: /reports)
   - Canned reports
   - Excel export
   - Status: Active, slow performance

**Research Questions**:

1. How do sales reps currently manage contacts?
   - What's working well?
   - What's frustrating?
   - Workarounds being used?

2. Is the pipeline view meeting needs?
   - Missing information?
   - Too slow?
   - Mobile usage?

3. What reports are actually used?
   - Which are ignored?
   - What's missing?

**Testing Priorities**:

1. **High**: Deal pipeline (most used, business critical)
2. **High**: Contact search (performance complaints)
3. **Medium**: Reporting (export workarounds observed)
4. **Low**: Admin settings (rarely used)

**Research Plan**:

**Phase 1** (Week 1-2): User interviews (15 sales reps, 5 managers)
**Phase 2** (Week 3-4): Usability testing on pipeline and search
**Phase 3** (Week 5-6): Analytics analysis (usage patterns)
**Phase 4** (Week 7): Synthesis and recommendations

**Outcome**: Identified 8 high-priority improvements, validated with users, guided 6-month modernization roadmap.

## Troubleshooting

### Common Issues

#### "Template not found" Error

**Symptom**: Workflow fails with "Template not found for step..."

**Solution**:

```bash
# Verify templates exist
ls templates/planning/agile/

# Expected files:
# - generate_mvp_scope.md
# - generate_user_test_plan.md
# - generate_marketing_report.md
# - ingest_feedback.md
# - analyze_feedback.md
# - generate_iteration_plan.md
# - generate_legacy_research_plan.md

# Reinstall AIDP if missing
gem uninstall aidp
gem install aidp
```

#### Feedback Ingestion Fails

**Symptom**: "Could not parse feedback file"

**Solutions**:

1. **Check file format**:

   ```bash
   # For CSV: must have header row
   head -n 2 feedback.csv

   # For JSON: must be valid JSON
   cat feedback.json | jq .

   # For Markdown: must have ## Response headers
   grep "## Response" feedback.md
   ```

2. **Check required fields**:
   - At minimum: feedback text OR rating
   - Recommended: id, timestamp, rating, feedback

3. **Check encoding**:

   ```bash
   file feedback.csv
   # Should be: UTF-8 Unicode text

   # Convert if needed:
   iconv -f ISO-8859-1 -t UTF-8 feedback.csv > feedback_utf8.csv
   ```

#### AI Analysis Returns Generic Results

**Symptom**: Analysis lacks specific insights, recommendations are vague

**Solutions**:

1. **Provide more feedback data**:
   - Minimum: 20-30 responses for meaningful patterns
   - Ideal: 50+ responses

2. **Include open-ended feedback**:
   - Ratings alone don't provide context
   - Text feedback enables semantic analysis

3. **Ensure variety in feedback**:
   - Mix of positive, negative, neutral
   - Multiple features/topics

#### Codebase Analysis Incomplete

**Symptom**: Feature list missing known features

**Solutions**:

1. **Check codebase path**:

   ```bash
   ls -la /path/to/codebase
   # Should show project structure
   ```

2. **Specify language explicitly**:

   ```bash
   # If auto-detection fails
   Language: Ruby
   ```

3. **Review generated feature list**:
   - Manually add missing features
   - AIDP uses static analysis (may miss dynamic features)

#### MVP Scope Too Large

**Symptom**: "Must-have" features list is too long

**Solutions**:

1. **Re-run with stricter priorities**:
   - Only give 5/5 to truly critical features
   - Be honest about nice-to-haves

2. **Review AI rationale**:
   - Check why features were included
   - Override if needed by editing MVP_SCOPE.md

3. **Remember MVP principle**:
   - Minimum **Viable** Product
   - What's the smallest thing that provides value?

#### Iteration Plan Lacks Detail

**Symptom**: Tasks are vague, no clear acceptance criteria

**Solutions**:

1. **Provide current MVP scope**:
   - Helps AI understand context
   - Generates more specific improvements

2. **Ensure feedback analysis is complete**:
   - Rich analysis → detailed iteration plan
   - Review USER_FEEDBACK_ANALYSIS.md first

3. **Manually refine tasks**:
   - Edit NEXT_ITERATION_PLAN.md
   - Add specific acceptance criteria
   - Break down large tasks

### Getting Help

```bash
# Check AIDP version
aidp --version

# View agile workflow status
aidp status

# Check provider health
aidp providers

# Enable debug logging
AIDP_DEBUG=1 aidp execute

# Review logs
cat .aidp/logs/aidp.log
```

## Next Steps

- Review [CLI User Guide](CLI_USER_GUIDE.md) for command reference
- See [Waterfall Planning Mode](WATERFALL_PLANNING_MODE.md) for comparison
- Read [Work Loops Guide](WORK_LOOPS_GUIDE.md) for implementation details
- Check [Configuration Guide](CONFIGURATION.md) for customization options

## Feedback

Have suggestions for improving Agile Mode? File an issue at:
<https://github.com/viamin/aidp/issues>

---

**Generated**: 2025-01-18
**Version**: 1.0.0
**Issue**: #210
