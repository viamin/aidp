# Ingest User Feedback Data

You are a UX researcher ingesting user feedback data for analysis.

## Your Task

Collect user feedback data from CSV, JSON, or markdown files and normalize it into a consistent format for AI-powered analysis.

## Interactive Data Collection

**Prompt the user for:**

1. Path to feedback data file (CSV, JSON, or markdown)
2. Confirm file format is correct
3. Validate file exists and is readable

## Supported Formats

### CSV Format

Expected columns (flexible names):

- `id` or `respondent_id` or `user_id` - Respondent identifier
- `timestamp` or `date` or `submitted_at` - When submitted
- `rating` or `score` - Numeric rating (1-5, 1-10, etc.)
- `feedback` or `comments` or `response` - Text feedback
- `feature` or `area` - Feature being commented on
- `sentiment` - Positive/negative/neutral
- `tags` - Comma-separated tags

### JSON Format

Two structures supported:

**Array of responses:**

```json
[
  {
    "id": "user123",
    "timestamp": "2025-01-15",
    "rating": 4,
    "feedback": "Great product!",
    "feature": "dashboard",
    "sentiment": "positive"
  }
]
```

**Object with responses key:**

```json
{
  "survey_name": "MVP Feedback",
  "responses": [...]
}
```

### Markdown Format

Responses in sections:

```markdown
## Response 1
**ID:** user123
**Timestamp:** 2025-01-15
**Rating:** 4
**Feedback:** Great product!
```

## Normalization

Normalize all formats to consistent structure:

- `respondent_id` - User identifier
- `timestamp` - Submission time
- `rating` - Numeric rating (normalized)
- `feedback_text` - Text feedback
- `feature` - Feature name
- `sentiment` - Sentiment classification
- `tags` - Array of tags
- `raw_data` - Original data for reference

## Implementation

**For Ruby/AIDP projects**, use the `ruby_aidp_planning` skill with `Aidp::Planning::Parsers::FeedbackDataParser`:

1. Prompt user for file path using TTY::Prompt
2. Validate file exists and is readable
3. Parse using `FeedbackDataParser.new(file_path:).parse`
4. Save normalized data to `.aidp/docs/feedback_data.json`

Example:

```ruby
prompt = TTY::Prompt.new
file_path = prompt.ask("Enter path to feedback data file:", required: true)

unless File.exist?(file_path)
  prompt.error("File not found: #{file_path}")
  exit 1
end

parser = Aidp::Planning::Parsers::FeedbackDataParser.new(file_path: file_path)
feedback_data = parser.parse

File.write(".aidp/docs/feedback_data.json", JSON.pretty_generate(feedback_data))
prompt.ok("Feedback data ingested: #{feedback_data[:response_count]} responses")
```

**For other implementations**, create equivalent functionality that:

1. Prompts user for file path
2. Detects format from file extension
3. Parses format-specific data
4. Normalizes to consistent structure
5. Validates required fields
6. Saves to JSON format

## Validation

Check for:

- File exists and is readable
- Format is supported (.csv, .json, .md)
- Required fields present (at minimum: feedback text or rating)
- Data is parseable (valid CSV/JSON/markdown)

## Error Handling

Handle gracefully:

- File not found
- Invalid format
- Missing required fields
- Parse errors (malformed JSON, etc.)
- Empty datasets

Provide clear error messages to help user fix issues.

## Output Structure

Save to `.aidp/docs/feedback_data.json`:

```json
{
  "format": "csv|json|markdown",
  "source_file": "path/to/file",
  "parsed_at": "2025-01-15T10:30:00Z",
  "response_count": 42,
  "responses": [
    {
      "respondent_id": "user123",
      "timestamp": "2025-01-15",
      "rating": 4,
      "feedback_text": "Text feedback",
      "feature": "feature_name",
      "sentiment": "positive",
      "tags": ["tag1", "tag2"],
      "raw_data": {...}
    }
  ],
  "metadata": {
    "total_rows": 42,
    "columns": [...],
    "has_timestamps": true,
    "has_ratings": true
  }
}
```

## Output

Write normalized feedback data to `.aidp/docs/feedback_data.json` and confirm successful ingestion with count to user via TUI.
