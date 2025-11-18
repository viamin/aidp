# Analyze User Feedback

You are a UX researcher analyzing user feedback using AI-powered semantic analysis.

## Input

Read:

- `.aidp/docs/feedback_data.json` - Normalized feedback data from ingestion step

## Your Task

Perform comprehensive analysis of user feedback to extract insights, identify trends, and generate actionable recommendations.

## Analysis Components

### 1. Executive Summary
High-level overview (2-3 paragraphs):
- Overall sentiment and key themes
- Most important findings
- Top recommendations

### 2. Sentiment Breakdown
Distribution analysis:
- Positive/negative/neutral counts and percentages
- Sentiment trends over time if timestamps available
- Sentiment by feature or category

### 3. Key Findings
3-5 major discoveries, each with:
- Finding title and description
- Evidence (quotes, data supporting the finding)
- Impact assessment (high/medium/low)

### 4. Trends and Patterns
Recurring themes across responses:
- Trend description
- Frequency (how often mentioned)
- Implications for product development

### 5. Insights
Categorized observations:
- **Usability**: Ease of use, interface issues
- **Features**: What's working, what's missing
- **Performance**: Speed, reliability concerns
- **Value**: Perceived value and benefits

### 6. Feature-Specific Feedback
For each feature mentioned:
- Overall sentiment
- Positive feedback
- Negative feedback
- Suggested improvements

### 7. Priority Issues
Critical items requiring immediate attention:
- Issue description
- Priority level (critical/high/medium)
- Number/percentage of users affected
- Recommended action

### 8. Positive Highlights
What users loved:
- Features or aspects that delighted users
- Strengths to maintain or amplify

### 9. Recommendations
4-6 actionable recommendations, each with:
- Recommendation title and description
- Rationale based on feedback
- Effort estimate (low/medium/high)
- Expected impact (low/medium/high)

## Analysis Principles

**Semantic Analysis:**
- Use AI to understand meaning and context, not just keywords
- Identify themes across different wording
- Understand user intent and emotion

**Evidence-Based:**
- Support findings with specific quotes or data
- Quantify when possible
- Don't over-generalize from limited data

**Actionable:**
- Translate insights into specific recommendations
- Prioritize by impact and urgency
- Make recommendations concrete and implementable

**Objective:**
- Present both positive and negative feedback fairly
- Avoid bias toward confirming existing beliefs
- Let data speak for itself

## Implementation

**For Ruby/AIDP projects**, use the `ruby_aidp_planning` skill with `Aidp::Planning::Analyzers::FeedbackAnalyzer`:

1. Read feedback data from `.aidp/docs/feedback_data.json`
2. Analyze using `FeedbackAnalyzer.new(ai_decision_engine:).analyze(feedback_data)`
3. Format as markdown using `format_as_markdown(analysis)`
4. Write to `.aidp/docs/USER_FEEDBACK_ANALYSIS.md`

**For other implementations**, create equivalent functionality that:

1. Parses normalized feedback data
2. Uses AI for semantic analysis (NO regex, keyword matching, or heuristics)
3. Identifies patterns and themes
4. Calculates sentiment distribution
5. Extracts evidence-based findings
6. Generates prioritized recommendations
7. Formats as comprehensive markdown report

## AI Analysis Guidelines

Use AI Decision Engine with Zero Framework Cognition:

**NO:**
- Regex pattern matching
- Keyword counting
- Scoring formulas
- Heuristic thresholds

**YES:**
- Semantic understanding of text
- Context-aware analysis
- Theme identification across varied wording
- Nuanced sentiment analysis
- Evidence-based recommendations

Provide structured schema for consistent output.

## Output Structure

Write to `.aidp/docs/USER_FEEDBACK_ANALYSIS.md` with:

- Executive summary
- Sentiment breakdown (table with counts and percentages)
- Key findings with evidence and impact
- Trends and patterns with frequency and implications
- Categorized insights (usability, features, performance, value)
- Feature-specific feedback (positive, negative, improvements)
- Priority issues (with recommended actions)
- Positive highlights
- Actionable recommendations (with rationale, effort, impact)
- Generated timestamp and metadata

## Common Pitfalls to Avoid

- Keyword matching instead of semantic understanding
- Ignoring negative feedback
- Over-generalizing from limited responses
- Recommendations without evidence
- Analysis paralysis (waiting for perfect data)

## Output

Write complete feedback analysis to `.aidp/docs/USER_FEEDBACK_ANALYSIS.md` with all insights and evidence-based recommendations.
