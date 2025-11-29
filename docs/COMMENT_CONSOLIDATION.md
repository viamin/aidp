# Comment Consolidation System

## Overview

The Comment Consolidation System helps manage GitHub comments by grouping them into categorized, updatable comments instead of creating multiple separate comments. This reduces comment clutter and makes AIDP-generated comments easier to track and filter.

## Categories

The system supports three main comment categories:

1. **Progress Report**: `## 🔄 Progress Report`
   - Tracks ongoing updates and incremental progress
   - Timestamps each update for clarity

2. **Exceptions and Errors**: `## 🚨 Exceptions and Errors`
   - Captures and consolidates error-related information
   - Helps track and understand potential issues

3. **Completion Summary**: `## ✅ Completion Summary`
   - Provides an overview of final results and key outcomes

## Key Features

- Automatically finds existing comments by category
- Appends new content with timestamps
- Creates new comments when no existing category comment exists
- Option to replace or append content
- Extensive debug logging

## Usage Example

```ruby
# Initialize the consolidator
consolidator = Aidp::CommentConsolidator.new(
  repository_client: client,
  number: pr_number
)

# Add progress update
consolidator.consolidate_comment(
  category: :progress,
  new_content: "Implemented comment consolidation"
)

# Add error details
consolidator.consolidate_comment(
  category: :exceptions,
  new_content: "Encountered parsing issue"
)

# Create completion summary
consolidator.consolidate_comment(
  category: :completion,
  new_content: "Feature implementation complete"
)
```

## Parameters

- `category`: `:progress`, `:exceptions`, or `:completion`
- `new_content`: The text to add to the comment
- `append`: `true` (default) to add content, `false` to replace

## Best Practices

- Use descriptive, concise content
- Include relevant context in each update
- Leverage the timestamp feature to track progression
