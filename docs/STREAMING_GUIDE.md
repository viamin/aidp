# AIDP Streaming Output Guide

## Overview

AIDP now supports real-time streaming output for AI provider commands, allowing you to see responses as they are generated instead of waiting for the complete response.

## How to Enable Streaming

Streaming can be enabled in two ways:

### Option 1: Environment Variable

```bash
export AIDP_STREAMING=1
bundle exec aidp
```

### Option 2: Debug Mode (enables streaming automatically)

```bash
DEBUG=1 bundle exec aidp
```

## When Streaming is Useful

- **Long-running analysis steps** (like TEST_ANALYSIS that may take 5+ minutes)
- **Debugging provider issues** - see output in real-time instead of waiting
- **Progress monitoring** - get immediate feedback that the AI is working
- **Early termination** - stop if you see the response going in wrong direction

## Example Usage

```bash
# Enable streaming for better visibility during analysis
AIDP_STREAMING=1 bundle exec aidp

# Or combine with debug mode for maximum visibility
DEBUG=1 AIDP_STREAMING=1 bundle exec aidp
```

## What You'll See

With streaming enabled:

- ✅ Real-time output from claude/gemini CLI tools
- 📺 Progress indicator showing streaming is active
- 🔄 Immediate feedback when commands start
- ⚡ Response chunks appear as they're generated

Without streaming (default):

- ⏳ Silent execution until completion
- 📋 Results appear all at once
- ❓ No indication of progress during execution

## Supported Providers

AIDP supports two types of streaming:

### 🚀 **True Streaming** (Real-time API streaming)

- **Anthropic Claude** (`claude --print --output-format=stream-json`)
  - ✅ Real-time chunks from Claude API as they're generated
  - ✅ Includes partial messages and progressive content

### 📺 **Display Streaming** (Reduced output buffering)

- **Google Gemini** (`gemini --print`)
- **Cursor AI** (`cursor-agent`)
- **Codex CLI** (`codex exec`)
- **OpenCode** (`opencode run`)
- **GitHub Copilot CLI** (`copilot`)
  - ✅ Reduced TTY output buffering for faster display
  - ⚠️ Content is still generated in full before being shown (CLI limitation)

All providers will automatically use their best available streaming mode when enabled.

## Troubleshooting

### TTY::Command Progress Output

The streaming uses TTY::Command's `:progress` printer, which shows:

- Command execution status
- Real-time stdout/stderr
- Execution timing

### If Streaming Doesn't Work

1. Check if your provider CLI supports real-time output
2. Verify TTY::Command is working correctly
3. Try DEBUG=1 to see detailed execution logs

## Technical Details

Streaming is implemented by:

1. Setting `TTY::Command` printer to `:progress` instead of `:null`
2. Allowing real-time output from provider CLI tools
3. Maintaining backward compatibility with non-streaming mode

The implementation is in:

- `lib/aidp/debug_mixin.rb` - Core streaming logic
- `lib/aidp/providers/anthropic.rb` - Claude streaming support
- `lib/aidp/providers/gemini.rb` - Gemini streaming support  
- `lib/aidp/providers/cursor.rb` - Cursor AI streaming support
- `lib/aidp/providers/codex.rb` - Codex CLI streaming support
- `lib/aidp/providers/opencode.rb` - OpenCode streaming support
- `lib/aidp/providers/github_copilot.rb` - GitHub Copilot CLI streaming support
