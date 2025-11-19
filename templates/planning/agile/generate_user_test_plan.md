# Generate User Testing Plan

You are a UX researcher creating a comprehensive user testing plan.

## Input

Read:

- `.aidp/docs/MVP_SCOPE.md` - MVP scope definition with features to test

## Your Task

Create a detailed user testing plan that includes recruitment criteria, testing stages, survey questions, interview scripts, and success metrics to validate the MVP with real users.

## User Testing Plan Components

### 1. Target Users

Define 2-3 user segments to test:

- Segment characteristics
- Why this segment is important
- Recommended sample size per segment

### 2. Recruitment

- Screener questions to qualify participants
- Recruitment channels (where to find users)
- Incentives for participation
- Timeline for recruitment

### 3. Testing Stages

Define 3-4 stages (e.g., Alpha, Beta, Launch):

- Objective of each stage
- Number of participants
- Duration
- Key activities
- Success criteria

### 4. Survey Questions

Create comprehensive surveys:

- **Likert Scale** (1-5): 5-7 questions about satisfaction, ease of use, value
- **Multiple Choice**: 3-5 questions with specific options
- **Open-Ended**: 3-5 questions for qualitative feedback

### 5. Interview Script

- Introduction explaining the research
- 5-7 main questions with follow-ups
- Closing thanking participants

### 6. Success Metrics

Quantitative and qualitative metrics:

- Task completion rates
- User satisfaction scores
- Feature adoption metrics
- Qualitative sentiment targets

### 7. Timeline

Phases with duration estimates:

- Recruitment
- Testing stages
- Analysis and reporting

## Question Design Principles

**Good Survey Questions:**

- Clear and unambiguous
- One topic per question
- Balanced response options
- Appropriate for quantitative analysis

**Good Interview Questions:**

- Open-ended to encourage discussion
- Non-leading
- Focused on specific experiences
- Include follow-up probes

**Avoid:**

- Double-barreled questions
- Leading or biased phrasing
- Jargon or technical terms
- Questions that assume knowledge

## Implementation

**For Ruby/AIDP projects**, use the `ruby_aidp_planning` skill with `Aidp::Planning::Generators::UserTestPlanGenerator`:

1. Parse MVP scope using `Aidp::Planning::Parsers::DocumentParser`
2. Generate test plan using `UserTestPlanGenerator.generate(mvp_scope:)`
3. Format as markdown using `format_as_markdown(test_plan)`
4. Write to `.aidp/docs/USER_TEST_PLAN.md`

**For other implementations**, create equivalent functionality that:

1. Parses MVP scope to understand features to test
2. Uses AI to generate contextual testing questions based on features
3. Creates persona-specific recruitment criteria
4. Designs appropriate testing stages
5. Generates survey questions (Likert, multiple choice, open-ended)
6. Creates interview scripts with follow-ups
7. Defines measurable success metrics

## AI Analysis Guidelines

Use AI Decision Engine to:

- Generate questions specific to MVP features
- Tailor recruitment criteria to target users
- Design appropriate testing stages
- Create unbiased, effective questions
- Suggest realistic success metrics

Make questions specific to the MVP features, not generic.

## Output Structure

Write to `.aidp/docs/USER_TEST_PLAN.md` with:

- Overview of testing goals
- Target user segments with characteristics
- Recruitment criteria and screener questions
- Testing stages with objectives
- Complete survey questions (all types)
- Interview script (intro, questions, closing)
- Success metrics and targets
- Timeline with phase durations
- Generated timestamp and metadata

## Output

Write complete user testing plan to `.aidp/docs/USER_TEST_PLAN.md` with all components listed above.
