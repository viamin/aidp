# Provider Adapter Authoring Guide

This guide explains how to create a new AI model provider adapter for AIDP that conforms to the standardized ProviderAdapter interface.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Core Interface Methods](#core-interface-methods)
- [Capability Declaration](#capability-declaration)
- [Dangerous Permissions](#dangerous-permissions)
- [Error Classification](#error-classification)
- [Configuration Validation](#configuration-validation)
- [Testing Your Adapter](#testing-your-adapter)
- [Example Implementation](#example-implementation)

## Overview

The ProviderAdapter interface ensures consistent behavior across different AI model providers (Anthropic Claude, OpenAI, Google Gemini, etc.) without leaking provider-specific logic into the coordinator layer.

### Design Philosophy

- **Stateless adapters**: Delegate throttling, retries, and escalation to the coordinator
- **Provider-specific patterns**: Store error regex matchers adjacent to adapters for maintainability
- **Semantic flags**: Single flags (like `dangerous: true`) map to provider-specific equivalents
- **Normalized errors**: Five standardized categories enable consistent retry and escalation logic

## Quick Start

1. Create a new file in `lib/aidp/providers/your_provider.rb`
2. Inherit from `Aidp::Providers::Base` (which includes `Aidp::Providers::Adapter`)
3. Implement required interface methods
4. Add provider-specific error patterns
5. Declare capabilities
6. Write conformance tests
7. Update configuration schema

```ruby
# lib/aidp/providers/your_provider.rb
require_relative "base"

module Aidp
  module Providers
    class YourProvider < Base
      def name
        "your_provider"
      end

      def display_name
        "Your Provider Name"
      end

      def send_message(prompt:, session: nil, **options)
        # Your implementation
      end

      def capabilities
        {
          reasoning_tiers: ["fast", "standard"],
          context_window: 100_000,
          supports_tool_use: true,
          # ... more capabilities
        }
      end

      def error_patterns
        {
          rate_limited: [/rate limit/i],
          auth_expired: [/invalid token/i],
          # ... more patterns
        }
      end
    end
  end
end
```

## Core Interface Methods

### Required Methods

#### `name`

Returns the provider's unique identifier (lowercase, alphanumeric + underscores/hyphens).

```ruby
def name
  "anthropic"
end
```

#### `display_name`

Returns a human-friendly name for UI display.

```ruby
def display_name
  "Anthropic Claude CLI"
end
```

#### `send_message(prompt:, session: nil, **options)`

Sends a prompt to the provider and returns the response.

**Parameters:**

- `prompt` (String): The prompt to send
- `session` (String, nil): Optional session identifier for context
- `options` (Hash): Additional provider-specific options

**Returns:** String or Hash (provider response)

```ruby
def send_message(prompt:, session: nil, **options)
  # Execute provider CLI or API call
  result = execute_provider_command(prompt, options)

  # Handle errors
  raise "Provider failed" unless result.success?

  # Return response
  result.output
end
```

### Optional Methods

#### `available?`

Checks if the provider CLI or API is accessible.

```ruby
def available?
  !!Aidp::Util.which("claude")
end
```

#### `supports_mcp?`

Returns true if the provider supports Model Context Protocol.

```ruby
def supports_mcp?
  true
end
```

#### `fetch_mcp_servers`

Returns array of configured MCP servers.

```ruby
def fetch_mcp_servers
  # Query provider for MCP server list
  result = execute_command("provider", ["mcp", "list"])
  parse_mcp_output(result)
end
```

## Capability Declaration

The `capabilities` method declares what features your provider supports. This enables runtime feature detection and provider selection based on requirements.

### Standard Capability Keys

```ruby
def capabilities
  {
    # Array of reasoning tier names (e.g., ["mini", "standard", "thinking"])
    reasoning_tiers: [],

    # Maximum context window size in tokens
    context_window: 100_000,

    # Boolean capabilities
    supports_json_mode: false,
    supports_tool_use: false,
    supports_vision: false,
    supports_file_upload: false,
    streaming: false
  }
end
```

### Anthropic Example

```ruby
def capabilities
  {
    reasoning_tiers: ["mini", "standard", "thinking"],
    context_window: 200_000,
    supports_json_mode: true,
    supports_tool_use: true,
    supports_vision: false,
    supports_file_upload: true,
    streaming: true
  }
end
```

## Dangerous Permissions

Some providers support an elevated permissions mode for development environments (e.g., devcontainers, codespaces) where security restrictions can be relaxed.

### Interface Methods

#### `supports_dangerous_mode?`

Returns true if the provider supports dangerous/elevated permissions.

```ruby
def supports_dangerous_mode?
  true
end
```

#### `dangerous_mode_flags`

Returns array of provider-specific CLI flags for enabling dangerous mode.

```ruby
def dangerous_mode_flags
  ["--dangerously-skip-permissions"]
end
```

#### Usage in send_message

```ruby
def send_message(prompt:, session: nil, **options)
  args = ["--print"]

  # Check if dangerous mode should be enabled
  if should_skip_permissions? || dangerous_mode_enabled?
    args += dangerous_mode_flags
    Aidp.log_debug(name, "dangerous mode enabled")
  end

  execute_command(args, prompt)
end
```

## Error Classification

The ProviderAdapter interface uses five standardized error categories:

1. **rate_limited**: Provider is rate-limiting requests (switch provider immediately)
2. **auth_expired**: Authentication credentials are invalid (switch provider or escalate)
3. **quota_exceeded**: Usage quota has been exceeded (switch provider)
4. **transient**: Temporary error that may resolve on retry (retry with backoff)
5. **permanent**: Permanent error that won't resolve (escalate or abort)

### Error Patterns

Define regex patterns for each error category:

```ruby
def error_patterns
  {
    rate_limited: [
      /rate.?limit/i,
      /too.?many.?requests/i,
      /429/,
      /throttl(ed|ing)/i
    ],
    auth_expired: [
      /oauth.*token.*expired/i,
      /authentication.*error/i,
      /invalid.*api.*key/i,
      /unauthorized/i,
      /401/
    ],
    quota_exceeded: [
      /quota.*exceeded/i,
      /usage.*limit/i,
      /credit.*exhausted/i
    ],
    transient: [
      /timeout/i,
      /connection.*reset/i,
      /temporary.*error/i,
      /service.*unavailable/i,
      /503/,
      /502/,
      /504/
    ],
    permanent: [
      /invalid.*model/i,
      /unsupported.*operation/i,
      /not.*found/i,
      /404/
    ]
  }
end
```

### Error Classification Flow

1. Provider raises error during `send_message`
2. ErrorHandler catches error and calls `classify_error`
3. `classify_error` checks provider's `error_patterns`
4. ErrorHandler applies appropriate retry/recovery strategy

## Configuration Validation

Implement `validate_config` to check provider configuration:

```ruby
def validate_config(config)
  errors = []
  warnings = []

  # Validate required fields
  unless config[:type]
    errors << "Provider type is required"
  end

  # Validate provider-specific requirements
  if config[:type] == "usage_based" && !config[:auth]
    warnings << "API key configuration recommended for usage-based providers"
  end

  {
    valid: errors.empty?,
    errors: errors,
    warnings: warnings
  }
end
```

## Testing Your Adapter

### Conformance Tests

Use the shared conformance test suite to verify your adapter implements the interface correctly:

```ruby
# spec/aidp/providers/your_provider_spec.rb
require "spec_helper"
require "aidp/providers/your_provider"

RSpec.describe Aidp::Providers::YourProvider do
  it_behaves_like "a conforming provider adapter", Aidp::Providers::YourProvider

  # Add provider-specific tests
  describe "#send_message" do
    it "handles rate limit errors correctly" do
      # Your test
    end
  end
end
```

### Capability Registry Tests

Test that your provider registers correctly:

```ruby
describe "capability registration" do
  let(:registry) { Aidp::Providers::CapabilityRegistry.new }
  let(:provider) { Aidp::Providers::YourProvider.new }

  it "registers capabilities" do
    registry.register(provider)
    caps = registry.capabilities_for("your_provider")

    expect(caps[:context_window]).to eq(100_000)
    expect(caps[:supports_tool_use]).to be true
  end
end
```

## Example Implementation

See `lib/aidp/providers/anthropic.rb` for a complete reference implementation.

### Minimal Working Example

```ruby
# lib/aidp/providers/example.rb
require_relative "base"

module Aidp
  module Providers
    class Example < Base
      def self.available?
        !!Aidp::Util.which("example-cli")
      end

      def name
        "example"
      end

      def display_name
        "Example Provider"
      end

      def available?
        self.class.available?
      end

      def capabilities
        {
          reasoning_tiers: ["standard"],
          context_window: 50_000,
          supports_json_mode: true,
          supports_tool_use: false,
          supports_vision: false,
          supports_file_upload: false,
          streaming: false
        }
      end

      def supports_dangerous_mode?
        false
      end

      def error_patterns
        {
          rate_limited: [/rate limit/i],
          auth_expired: [/invalid api key/i],
          quota_exceeded: [/quota exceeded/i],
          transient: [/timeout/i, /503/],
          permanent: [/invalid model/i, /400/]
        }
      end

      def send_message(prompt:, session: nil, **options)
        raise "example-cli not available" unless available?

        # Execute CLI command
        result = system("example-cli", "--prompt", prompt)

        # Handle errors
        unless result.success?
          raise "Example provider failed: #{result.stderr}"
        end

        result.stdout
      end
    end
  end
end
```

## Configuration

Add your provider to `.aidp/aidp.yml`:

```yaml
providers:
  example:
    type: usage_based
    priority: 3
    models: ["example-default", "example-fast"]
    dangerous_mode:
      enabled: false
      flags: []
    features:
      file_upload: false
      code_generation: true
      analysis: true
```

## Checklist

- [ ] Inherit from `Aidp::Providers::Base`
- [ ] Implement `name` and `display_name`
- [ ] Implement `send_message`
- [ ] Declare `capabilities`
- [ ] Define `error_patterns` for all 5 categories
- [ ] Implement dangerous mode support (if applicable)
- [ ] Add `validate_config` method
- [ ] Write conformance tests
- [ ] Add provider to configuration schema
- [ ] Update documentation
- [ ] Register provider in `ProviderFactory`

## References

- [Issue #243 - Standardized Provider Interfaces](https://github.com/viamin/aidp/issues/243)
- [ErrorTaxonomy](../lib/aidp/providers/error_taxonomy.rb)
- [ProviderAdapter Module](../lib/aidp/providers/adapter.rb)
- [Anthropic Provider (Reference)](../lib/aidp/providers/anthropic.rb)
- [Conformance Test Suite](../spec/aidp/providers/adapter_conformance_spec.rb)
