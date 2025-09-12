# AIDP Harness Configuration Guide

## Overview

The AIDP Harness is configured through an `aidp.yml` file in your project root. This guide covers all configuration options, provides examples, and explains how to customize the harness for your specific needs.

## Configuration File Location

The harness looks for configuration in this order:

1. `./aidp.yml` (project root)
2. `./.aidp.yml` (project root, hidden)
3. `~/.aidp.yml` (user home directory)
4. Default values (built-in)

## Basic Configuration Structure

```yaml
# aidp.yml
harness:
  enabled: true
  max_retries: 2
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]

providers:
  claude:
    type: "api"
    max_tokens: 100000
    default_flags: ["--dangerously-skip-permissions"]
  gemini:
    type: "api"
    max_tokens: 50000
  cursor:
    type: "package"
```

## Harness Configuration

### Core Settings

```yaml
harness:
  # Enable/disable harness mode
  enabled: true

  # Maximum retry attempts per provider
  max_retries: 2

  # Default provider to use
  default_provider: "claude"

  # Fallback provider chain
  fallback_providers: ["gemini", "cursor"]

  # Restrict to non-BYOK providers only
  restrict_to_non_byok: false
```

### Rate Limit Configuration

```yaml
harness:
  # Rate limit handling strategy
  rate_limit_strategy: "provider_first"  # or "model_first", "cost_optimized"

  # Cooldown period for rate limits (seconds)
  rate_limit_cooldown: 60

  # Rate limit detection patterns
  rate_limit_patterns:
    - "rate limit exceeded"
    - "too many requests"
    - "quota exceeded"
    - "429"
```

### Error Recovery Configuration

```yaml
harness:
  # Error recovery strategies
  error_recovery:
    network_error:
      strategy: "linear_backoff"
      max_retries: 3
      base_delay: 1.0
    server_error:
      strategy: "exponential_backoff"
      max_retries: 5
      base_delay: 2.0
    timeout:
      strategy: "fixed_delay"
      max_retries: 2
      delay: 5.0
    authentication:
      strategy: "immediate_fail"
      max_retries: 0
    rate_limit:
      strategy: "immediate_switch"
      max_retries: 0
```

### User Interface Configuration

```yaml
harness:
  # User interface settings
  user_interface:
    # Timeout for user input (seconds, 0 = no timeout)
    input_timeout: 0

    # Show progress updates
    show_progress: true

    # Progress update interval (seconds)
    progress_interval: 5

    # Show detailed status
    show_detailed_status: true

    # Enable file selection with @
    enable_file_selection: true
```

### State Management Configuration

```yaml
harness:
  # State management settings
  state:
    # Auto-save interval (seconds)
    auto_save_interval: 30

    # Maximum state history entries
    max_history_entries: 100

    # Enable state compression
    enable_compression: true

    # State backup retention (days)
    backup_retention_days: 7
```

## Provider Configuration

### Provider Types

#### API Providers (Claude, Gemini)

```yaml
providers:
  claude:
    type: "api"
    # API key (set via environment variable AIDP_CLAUDE_API_KEY)
    api_key: "${AIDP_CLAUDE_API_KEY}"

    # Maximum tokens per request
    max_tokens: 100000

    # Default command-line flags
    default_flags: ["--dangerously-skip-permissions"]

    # Retry configuration
    retry_count: 3
    timeout: 30

    # Rate limit configuration
    rate_limit_strategy: "provider_first"

    # Cost tracking
    cost_tracking:
      enabled: true
      cost_per_token: 0.000015

  gemini:
    type: "api"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
    default_flags: []
    retry_count: 2
    timeout: 45
    rate_limit_strategy: "model_first"
    cost_tracking:
      enabled: true
      cost_per_token: 0.00001
```

#### Package Providers (Cursor)

```yaml
providers:
  cursor:
    type: "package"
    # No API key needed for package providers
    default_flags: []
    retry_count: 1
    timeout: 60
    rate_limit_strategy: "provider_first"
    cost_tracking:
      enabled: false
```

### Provider-Specific Settings

#### Claude Configuration

```yaml
providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
    default_flags: ["--dangerously-skip-permissions"]
    retry_count: 3
    timeout: 30

    # Claude-specific settings
    model_preferences:
      - "claude-3-5-sonnet"
      - "claude-3-opus"
      - "claude-3-sonnet"

    # Rate limit handling
    rate_limit_handling:
      strategy: "provider_first"
      cooldown_period: 60
      max_retries: 3

    # Cost optimization
    cost_optimization:
      enabled: true
      max_daily_cost: 50.0
      max_monthly_cost: 500.0
```

#### Gemini Configuration

```yaml
providers:
  gemini:
    type: "api"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
    default_flags: []
    retry_count: 2
    timeout: 45

    # Gemini-specific settings
    model_preferences:
      - "gemini-pro"
      - "gemini-pro-vision"

    # Rate limit handling
    rate_limit_handling:
      strategy: "model_first"
      cooldown_period: 30
      max_retries: 2

    # Cost optimization
    cost_optimization:
      enabled: true
      max_daily_cost: 25.0
      max_monthly_cost: 250.0
```

#### Cursor Configuration

```yaml
providers:
  cursor:
    type: "package"
    default_flags: []
    retry_count: 1
    timeout: 60

    # Cursor-specific settings
    model_preferences:
      - "cursor-default"

    # Rate limit handling
    rate_limit_handling:
      strategy: "provider_first"
      cooldown_period: 0  # No rate limits for package providers
      max_retries: 1

    # Cost optimization
    cost_optimization:
      enabled: false  # No cost tracking for package providers
```

## Advanced Configuration

### Custom Step Sequences

```yaml
harness:
  # Custom step sequences
  custom_sequences:
    quick_analysis:
      - "01_REPOSITORY_ANALYSIS"
      - "02_ARCHITECTURE_ANALYSIS"
    full_analysis:
      - "01_REPOSITORY_ANALYSIS"
      - "02_ARCHITECTURE_ANALYSIS"
      - "03_TEST_ANALYSIS"
      - "04_FUNCTIONALITY_ANALYSIS"
      - "05_DOCUMENTATION_ANALYSIS"
      - "06_STATIC_ANALYSIS"
      - "07_REFACTORING_RECOMMENDATIONS"
    quick_execute:
      - "00_PRD"
      - "01_NFRS"
      - "02_ARCHITECTURE"
    full_execute:
      - "00_PRD"
      - "01_NFRS"
      - "02_ARCHITECTURE"
      - "02A_ARCH_GATE_QUESTIONS"
      - "03_ADR_FACTORY"
      - "04_DOMAIN_DECOMPOSITION"
      - "05_API_DESIGN"
      - "06_DATA_MODEL"
      - "07_SECURITY_REVIEW"
      - "08_PERFORMANCE_REVIEW"
      - "09_RELIABILITY_REVIEW"
      - "10_TESTING_STRATEGY"
      - "11_STATIC_ANALYSIS"
      - "12_OBSERVABILITY_SLOS"
      - "13_DELIVERY_ROLLOUT"
      - "14_DOCS_PORTAL"
      - "15_POST_RELEASE"
```

### Provider Rotation Strategies

```yaml
harness:
  # Provider rotation strategies
  rotation_strategies:
    provider_first:
      description: "Try all models in current provider before switching"
      order: ["provider", "model"]
    model_first:
      description: "Try all providers with current model before switching"
      order: ["model", "provider"]
    cost_optimized:
      description: "Prioritize providers by cost efficiency"
      order: ["cost", "provider", "model"]
    performance_optimized:
      description: "Prioritize providers by performance"
      order: ["performance", "provider", "model"]
    quota_aware:
      description: "Consider quota usage when rotating"
      order: ["quota", "provider", "model"]
```

### Circuit Breaker Configuration

```yaml
harness:
  # Circuit breaker settings
  circuit_breaker:
    enabled: true

    # Failure threshold before opening circuit
    failure_threshold: 5

    # Timeout before attempting to close circuit (seconds)
    timeout: 60

    # Success threshold to close circuit
    success_threshold: 3

    # Half-open state timeout (seconds)
    half_open_timeout: 30
```

### Metrics and Monitoring

```yaml
harness:
  # Metrics and monitoring
  metrics:
    enabled: true

    # Metrics collection interval (seconds)
    collection_interval: 30

    # Metrics retention (days)
    retention_days: 30

    # Export metrics
    export:
      enabled: true
      format: "json"  # or "csv", "yaml"
      destination: ".aidp/metrics"

  # Logging configuration
  logging:
    level: "info"  # debug, info, warn, error
    retention_days: 30
    max_file_size: "10MB"
    max_files: 5
```

## Configuration Examples

### Minimal Configuration

```yaml
# aidp.yml - Minimal setup
harness:
  enabled: true
  default_provider: "claude"

providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
```

### Development Configuration

```yaml
# aidp.yml - Development setup
harness:
  enabled: true
  max_retries: 3
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]

  # Development-specific settings
  user_interface:
    show_progress: true
    show_detailed_status: true
    enable_file_selection: true

  # More lenient error handling for development
  error_recovery:
    network_error:
      strategy: "linear_backoff"
      max_retries: 5
      base_delay: 1.0

providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
    default_flags: ["--dangerously-skip-permissions"]
    retry_count: 3
    timeout: 30

  gemini:
    type: "api"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
    retry_count: 2
    timeout: 45

  cursor:
    type: "package"
    retry_count: 1
    timeout: 60
```

### Production Configuration

```yaml
# aidp.yml - Production setup
harness:
  enabled: true
  max_retries: 2
  default_provider: "claude"
  fallback_providers: ["gemini"]

  # Production-specific settings
  user_interface:
    show_progress: false
    show_detailed_status: false
    enable_file_selection: false

  # Strict error handling for production
  error_recovery:
    network_error:
      strategy: "exponential_backoff"
      max_retries: 3
      base_delay: 2.0
    server_error:
      strategy: "exponential_backoff"
      max_retries: 3
      base_delay: 2.0
    timeout:
      strategy: "fixed_delay"
      max_retries: 2
      delay: 10.0

  # Circuit breaker for production
  circuit_breaker:
    enabled: true
    failure_threshold: 3
    timeout: 120
    success_threshold: 2

  # Metrics for production monitoring
  metrics:
    enabled: true
    collection_interval: 60
    retention_days: 90
    export:
      enabled: true
      format: "json"
      destination: "/var/log/aidp/metrics"

providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
    default_flags: ["--dangerously-skip-permissions"]
    retry_count: 2
    timeout: 30

    # Cost limits for production
    cost_tracking:
      enabled: true
      max_daily_cost: 100.0
      max_monthly_cost: 1000.0

  gemini:
    type: "api"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
    retry_count: 2
    timeout: 45

    # Cost limits for production
    cost_tracking:
      enabled: true
      max_daily_cost: 50.0
      max_monthly_cost: 500.0
```

### Cost-Optimized Configuration

```yaml
# aidp.yml - Cost-optimized setup
harness:
  enabled: true
  max_retries: 2
  default_provider: "gemini"  # Start with cheaper provider
  fallback_providers: ["claude", "cursor"]

  # Cost-optimized rotation
  rotation_strategies:
    cost_optimized:
      description: "Prioritize providers by cost efficiency"
      order: ["cost", "provider", "model"]

  # Strict cost limits
  cost_limits:
    daily_limit: 25.0
    monthly_limit: 250.0
    warning_threshold: 0.8  # Warn at 80% of limit

providers:
  gemini:
    type: "api"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
    retry_count: 3
    timeout: 45

    # Cost tracking
    cost_tracking:
      enabled: true
      cost_per_token: 0.00001
      max_daily_cost: 25.0
      max_monthly_cost: 250.0

  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
    retry_count: 2
    timeout: 30

    # Cost tracking
    cost_tracking:
      enabled: true
      cost_per_token: 0.000015
      max_daily_cost: 50.0
      max_monthly_cost: 500.0

  cursor:
    type: "package"
    retry_count: 1
    timeout: 60

    # No cost tracking for package providers
    cost_tracking:
      enabled: false
```

### Performance-Optimized Configuration

```yaml
# aidp.yml - Performance-optimized setup
harness:
  enabled: true
  max_retries: 3
  default_provider: "claude"  # Start with fastest provider
  fallback_providers: ["cursor", "gemini"]

  # Performance-optimized rotation
  rotation_strategies:
    performance_optimized:
      description: "Prioritize providers by performance"
      order: ["performance", "provider", "model"]

  # Aggressive retry for performance
  error_recovery:
    network_error:
      strategy: "linear_backoff"
      max_retries: 5
      base_delay: 0.5
    server_error:
      strategy: "exponential_backoff"
      max_retries: 5
      base_delay: 1.0
    timeout:
      strategy: "fixed_delay"
      max_retries: 3
      delay: 2.0

providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
    default_flags: ["--dangerously-skip-permissions"]
    retry_count: 3
    timeout: 30

    # Performance tracking
    performance_tracking:
      enabled: true
      target_response_time: 2.0
      max_response_time: 5.0

  cursor:
    type: "package"
    retry_count: 2
    timeout: 60

    # Performance tracking
    performance_tracking:
      enabled: true
      target_response_time: 1.0
      max_response_time: 3.0

  gemini:
    type: "api"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
    retry_count: 2
    timeout: 45

    # Performance tracking
    performance_tracking:
      enabled: true
      target_response_time: 3.0
      max_response_time: 8.0
```

## Environment Variables

### Required Environment Variables

```bash
# Claude API Key
export AIDP_CLAUDE_API_KEY="your-claude-api-key"

# Gemini API Key
export AIDP_GEMINI_API_KEY="your-gemini-api-key"
```

### Optional Environment Variables

```bash
# Debug mode
export AIDP_DEBUG=1

# Verbose output
export AIDP_VERBOSE=1

# Log level
export AIDP_LOG_LEVEL=debug

# Configuration file path
export AIDP_CONFIG_FILE="/path/to/custom/aidp.yml"
```

## Configuration Validation

### Validate Configuration

```bash
# Validate configuration file
aidp config validate

# Show configuration
aidp config show

# Show specific section
aidp config show harness
aidp config show providers
```

### Common Validation Errors

#### Missing API Keys

```yaml
# Error: Missing API key for Claude
providers:
  claude:
    type: "api"
    # api_key: "${AIDP_CLAUDE_API_KEY}"  # Missing!
```

**Solution**: Set the environment variable or add the API key to the configuration.

#### Invalid Provider Type

```yaml
# Error: Invalid provider type
providers:
  claude:
    type: "invalid_type"  # Should be "api" or "package"
```

**Solution**: Use `"api"` for API-based providers or `"package"` for package-based providers.

#### Invalid Rotation Strategy

```yaml
# Error: Invalid rotation strategy
harness:
  rate_limit_strategy: "invalid_strategy"  # Should be valid strategy
```

**Solution**: Use one of the valid strategies: `"provider_first"`, `"model_first"`, `"cost_optimized"`, `"performance_optimized"`, or `"quota_aware"`.

## Configuration Migration

### From Old Configuration Format

If you have an existing configuration, you can migrate it:

```bash
# Auto-migrate configuration
aidp config migrate

# Manual migration
aidp config migrate --input=old-config.yml --output=aidp.yml
```

### Configuration Backup

```bash
# Backup current configuration
aidp config backup

# Restore from backup
aidp config restore --backup=backup-2024-01-01.yml
```

## Best Practices

### 1. Start Simple

Begin with minimal configuration and add complexity as needed:

```yaml
# Start with this
harness:
  enabled: true
  default_provider: "claude"

providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
```

### 2. Use Environment Variables

Never commit API keys to version control:

```yaml
# Good
providers:
  claude:
    api_key: "${AIDP_CLAUDE_API_KEY}"

# Bad
providers:
  claude:
    api_key: "sk-ant-api03-..."  # Don't do this!
```

### 3. Set Appropriate Limits

Configure cost and rate limits based on your needs:

```yaml
harness:
  cost_limits:
    daily_limit: 25.0
    monthly_limit: 250.0

providers:
  claude:
    cost_tracking:
      max_daily_cost: 50.0
      max_monthly_cost: 500.0
```

### 4. Monitor and Adjust

Regularly review your configuration and adjust based on usage:

```bash
# Check current usage
aidp harness status

# Review metrics
aidp metrics show

# Adjust configuration as needed
```

### 5. Test Configuration

Always test your configuration before using in production:

```bash
# Test with a simple command
aidp analyze 01_REPOSITORY_ANALYSIS

# Check for errors
aidp config validate
```

## Troubleshooting

### Configuration Not Loading

```bash
# Check if configuration file exists
ls -la aidp.yml

# Check configuration location
aidp config show --path

# Validate configuration
aidp config validate
```

### Provider Errors

```bash
# Check provider configuration
aidp config show providers

# Test provider manually
aidp analyze 01_REPOSITORY_ANALYSIS

# Check provider status
aidp harness status
```

### Rate Limit Issues

```bash
# Check rate limit configuration
aidp config show harness.rate_limit_strategy

# Check provider rate limits
aidp harness status

# Adjust rate limit strategy
aidp config set harness.rate_limit_strategy model_first
```

## Conclusion

The AIDP Harness configuration system provides powerful customization options while maintaining simplicity for basic use cases. Start with the minimal configuration and gradually add complexity as you become more familiar with the system.

Remember to:

- Use environment variables for sensitive data
- Set appropriate cost and rate limits
- Test your configuration before production use
- Monitor usage and adjust as needed
- Keep your configuration in version control (without API keys)
