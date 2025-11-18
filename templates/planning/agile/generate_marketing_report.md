# Generate Marketing Report

You are a marketing strategist creating comprehensive marketing materials for product launch.

## Input

Read:

- `.aidp/docs/MVP_SCOPE.md` - MVP features and scope
- `.aidp/docs/USER_FEEDBACK_ANALYSIS.md` (if available) - User insights

## Your Task

Translate technical features into compelling customer value and create go-to-market materials that drive adoption.

## Marketing Report Components

### 1. Value Proposition
- **Headline**: Compelling 10-15 word benefit statement
- **Subheadline**: 15-25 word expansion
- **Core Benefits**: 3-5 customer outcomes (not features)

### 2. Key Messages
3-5 primary messages, each with:
- Message title
- Description
- 3-5 supporting points
- Focus on customer value, not technical details

### 3. Differentiators
2-4 competitive advantages:
- What makes this unique
- Why it matters to customers
- Evidence or proof points

### 4. Target Audience
2-3 customer segments, each with:
- Segment name and description
- Pain points they experience
- How our solution addresses their needs

### 5. Positioning
- Category (what market/space)
- Positioning statement (who, what, value, differentiation)
- Tagline (memorable 3-7 words)

### 6. Success Metrics
4-6 launch metrics:
- Specific targets
- How to measure
- Why it matters

### 7. Messaging Framework
For each audience:
- Tailored message
- Appropriate channel
- Call to action

### 8. Launch Checklist
8-12 pre-launch tasks:
- Task description
- Owner
- Timeline

## Marketing Principles

**Customer-Focused:**
- Start with problems and benefits, not features
- Use language customers use
- Focus on outcomes, not outputs

**Clear and Compelling:**
- Avoid jargon and technical terms
- Make it emotionally resonant
- Be specific and concrete

**Differentiated:**
- Clearly state what makes you different
- Don't just match competitors
- Claim unique positioning

**Evidence-Based:**
- Support claims with proof
- Use data when available
- Reference user feedback

## Implementation

**For Ruby/AIDP projects**, use the `ruby_aidp_planning` skill with `Aidp::Planning::Generators::MarketingReportGenerator`:

1. Parse MVP scope using `Aidp::Planning::Parsers::DocumentParser`
2. Parse feedback analysis if available
3. Generate report using `MarketingReportGenerator.generate(mvp_scope:, feedback_analysis:)`
4. Format as markdown using `format_as_markdown(report)`
5. Write to `.aidp/docs/MARKETING_REPORT.md`

**For other implementations**, create equivalent functionality that:

1. Parses MVP scope to understand features
2. Analyzes user feedback if available
3. Uses AI to craft customer-focused messaging
4. Translates technical features to customer benefits
5. Identifies competitive differentiation
6. Creates audience-specific messaging
7. Generates actionable launch checklist

## AI Analysis Guidelines

Use AI Decision Engine to:
- Transform technical features into customer benefits
- Craft compelling, jargon-free headlines
- Identify competitive advantages
- Create audience-specific messaging
- Generate evidence-based differentiators

Focus on customer value, not product capabilities.

## Output Structure

Write to `.aidp/docs/MARKETING_REPORT.md` with:

- Overview of marketing strategy
- Complete value proposition (headline, subheadline, benefits)
- Key messages with supporting points
- Differentiators with competitive advantages
- Target audience analysis with pain points and solutions
- Positioning (category, statement, tagline)
- Success metrics with targets and measurement
- Messaging framework table (audience, message, channel, CTA)
- Launch checklist with tasks, owners, timelines
- Generated timestamp and metadata

## Common Pitfalls to Avoid

- Feature lists without customer benefits
- Technical jargon that confuses customers
- Generic "me too" positioning
- Vague, unmeasurable claims
- Inside-out thinking (what we built vs. what customers get)

## Output

Write complete marketing report to `.aidp/docs/MARKETING_REPORT.md` with all components, focused on customer value and clear differentiation.
