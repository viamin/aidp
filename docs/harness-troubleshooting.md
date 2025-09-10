# AIDP Harness Troubleshooting Guide

## Overview

This guide helps you diagnose and resolve common issues with the AIDP Harness. It covers error messages, configuration problems, provider issues, and performance problems.

## Quick Diagnostics

### Check System Status

```bash
# Check overall harness status
aidp harness status

# Check current progress
aidp status

# Check configuration
aidp config show

# Check background jobs
aidp jobs

# Validate configuration
aidp config validate
```

### Check Logs

```bash
# View harness logs
tail -f .aidp/logs/harness.log

# View error logs
tail -f .aidp/logs/errors.log

# View provider logs
tail -f .aidp/logs/providers.log

# View all logs
tail -f .aidp/logs/*.log
```

## Common Issues

### 1. Harness Won't Start

#### Symptoms
- `aidp analyze` or `aidp execute` fails to start
- Error: "Harness initialization failed"
- No progress display appears

#### Diagnosis
```bash
# Check if harness is enabled
aidp config show harness.enabled

# Check configuration validity
aidp config validate

# Check for missing dependencies
aidp version
```

#### Solutions

**Configuration Issues**
```bash
# Reset to default configuration
aidp config reset

# Or create minimal configuration
echo "harness:\n  enabled: true\n  default_provider: claude" > aidp.yml
```

**Missing Dependencies**
```bash
# Reinstall AIDP
gem install aidp

# Or update if already installed
gem update aidp
```

**Permission Issues**
```bash
# Check file permissions
ls -la aidp.yml
ls -la .aidp/

# Fix permissions if needed
chmod 644 aidp.yml
chmod -R 755 .aidp/
```

### 2. Provider Authentication Errors

#### Symptoms
- Error: "Authentication failed"
- Error: "Invalid API key"
- Error: "Provider not configured"

#### Diagnosis
```bash
# Check provider configuration
aidp config show providers

# Check environment variables
echo $AIDP_CLAUDE_API_KEY
echo $AIDP_GEMINI_API_KEY

# Test provider manually
aidp analyze 01_REPOSITORY_ANALYSIS
```

#### Solutions

**Missing API Keys**
```bash
# Set Claude API key
export AIDP_CLAUDE_API_KEY="your-claude-api-key"

# Set Gemini API key
export AIDP_GEMINI_API_KEY="your-gemini-api-key"

# Add to shell profile for persistence
echo 'export AIDP_CLAUDE_API_KEY="your-claude-api-key"' >> ~/.bashrc
echo 'export AIDP_GEMINI_API_KEY="your-gemini-api-key"' >> ~/.bashrc
```

**Invalid API Keys**
```bash
# Verify API key format
# Claude: sk-ant-api03-...
# Gemini: AIza...

# Test API key manually
curl -H "Authorization: Bearer $AIDP_CLAUDE_API_KEY" \
     -H "Content-Type: application/json" \
     https://api.anthropic.com/v1/messages
```

**Provider Configuration Issues**
```yaml
# aidp.yml - Fix provider configuration
providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
  gemini:
    type: "api"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
```

### 3. Rate Limit Issues

#### Symptoms
- Error: "Rate limit exceeded"
- Harness pauses frequently
- Slow execution with long waits

#### Diagnosis
```bash
# Check rate limit status
aidp harness status

# Check provider rate limits
aidp config show providers.claude.rate_limit_handling

# Check rotation strategy
aidp config show harness.rate_limit_strategy
```

#### Solutions

**Configure Fallback Providers**
```yaml
# aidp.yml - Add fallback providers
harness:
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]
  rate_limit_strategy: "provider_first"
```

**Adjust Rate Limit Strategy**
```yaml
# aidp.yml - Try different strategies
harness:
  rate_limit_strategy: "model_first"  # or "cost_optimized"
  rate_limit_cooldown: 30  # Reduce cooldown period
```

**Increase Rate Limits**
```yaml
# aidp.yml - Increase provider limits
providers:
  claude:
    rate_limit_handling:
      max_retries: 5
      cooldown_period: 60
```

### 4. Harness Stuck in Loop

#### Symptoms
- Harness keeps retrying the same step
- No progress for extended periods
- High CPU usage

#### Diagnosis
```bash
# Check current step
aidp status

# Check for stuck jobs
aidp jobs

# Check error logs
tail -f .aidp/logs/errors.log
```

#### Solutions

**Stop and Reset**
```bash
# Stop harness
aidp harness stop

# Reset state
aidp harness reset --mode=analyze

# Or reset specific step
aidp harness reset --mode=analyze --step=01_REPOSITORY_ANALYSIS
```

**Check for Infinite Loops**
```bash
# Check configuration for problematic settings
aidp config show harness.error_recovery

# Reduce retry counts
aidp config set harness.max_retries 1
```

**Manual Step Completion**
```bash
# Mark step as completed manually
aidp progress mark-completed 01_REPOSITORY_ANALYSIS

# Continue from next step
aidp analyze
```

### 5. User Input Issues

#### Symptoms
- Harness waits indefinitely for user input
- Input validation errors
- File selection not working

#### Diagnosis
```bash
# Check user interface configuration
aidp config show harness.user_interface

# Check current state
aidp harness status
```

#### Solutions

**Input Timeout Issues**
```yaml
# aidp.yml - Set input timeout
harness:
  user_interface:
    input_timeout: 300  # 5 minutes
```

**File Selection Problems**
```yaml
# aidp.yml - Enable file selection
harness:
  user_interface:
    enable_file_selection: true
```

**Input Validation Errors**
```bash
# Check input format
# Make sure to answer questions in the expected format

# Reset user input state
aidp harness reset --mode=analyze --clear-user-input
```

### 6. Performance Issues

#### Symptoms
- Slow execution
- High memory usage
- Timeout errors

#### Diagnosis
```bash
# Check performance metrics
aidp metrics show

# Check provider response times
aidp harness status

# Check system resources
top
htop
```

#### Solutions

**Optimize Provider Configuration**
```yaml
# aidp.yml - Optimize for performance
providers:
  claude:
    timeout: 30
    retry_count: 2
  gemini:
    timeout: 45
    retry_count: 2
```

**Reduce Memory Usage**
```yaml
# aidp.yml - Reduce memory usage
harness:
  state:
    max_history_entries: 50
    enable_compression: true
```

**Increase Timeouts**
```yaml
# aidp.yml - Increase timeouts
providers:
  claude:
    timeout: 60
  gemini:
    timeout: 90
```

### 7. State Corruption Issues

#### Symptoms
- Error: "State file corrupted"
- Harness can't resume from previous state
- Inconsistent progress tracking

#### Diagnosis
```bash
# Check state files
ls -la .aidp/harness/

# Check state file integrity
aidp harness status

# Check progress files
ls -la .aidp-*-progress.yml
```

#### Solutions

**Reset State**
```bash
# Reset harness state
aidp harness reset --mode=analyze

# Reset all state
aidp harness reset --mode=analyze --clear-all
```

**Backup and Restore**
```bash
# Backup current state
aidp harness backup

# Restore from backup
aidp harness restore --backup=backup-2024-01-01.json
```

**Manual State Repair**
```bash
# Remove corrupted state files
rm -f .aidp/harness/analyze_state.json
rm -f .aidp/harness/execute_state.json

# Restart harness
aidp analyze
```

### 8. Configuration Issues

#### Symptoms
- Error: "Invalid configuration"
- Configuration not loading
- Default values not working

#### Diagnosis
```bash
# Validate configuration
aidp config validate

# Check configuration file
cat aidp.yml

# Check configuration location
aidp config show --path
```

#### Solutions

**Fix Configuration Syntax**
```yaml
# aidp.yml - Fix common syntax errors
harness:
  enabled: true  # Use boolean, not string
  max_retries: 2  # Use number, not string
  default_provider: "claude"  # Use string for provider names
```

**Reset Configuration**
```bash
# Reset to defaults
aidp config reset

# Or create new configuration
rm aidp.yml
aidp config init
```

**Check Configuration Priority**
```bash
# Check which configuration is being used
aidp config show --path

# Configuration is loaded in this order:
# 1. ./aidp.yml
# 2. ./.aidp.yml
# 3. ~/.aidp.yml
# 4. Default values
```

### 9. Provider Switching Issues

#### Symptoms
- Providers not switching when expected
- Fallback providers not working
- Provider rotation not working

#### Diagnosis
```bash
# Check provider configuration
aidp config show providers

# Check fallback chain
aidp config show harness.fallback_providers

# Check rotation strategy
aidp config show harness.rate_limit_strategy
```

#### Solutions

**Configure Fallback Providers**
```yaml
# aidp.yml - Ensure fallback providers are configured
harness:
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]
```

**Check Provider Availability**
```bash
# Test each provider manually
aidp analyze 01_REPOSITORY_ANALYSIS --provider=claude
aidp analyze 01_REPOSITORY_ANALYSIS --provider=gemini
aidp analyze 01_REPOSITORY_ANALYSIS --provider=cursor
```

**Adjust Rotation Strategy**
```yaml
# aidp.yml - Try different rotation strategies
harness:
  rate_limit_strategy: "provider_first"  # or "model_first", "cost_optimized"
```

### 10. Job Management Issues

#### Symptoms
- Background jobs not starting
- Jobs stuck in queue
- Job cleanup not working

#### Diagnosis
```bash
# Check job status
aidp jobs

# Check job queue
aidp jobs list

# Check job logs
tail -f .aidp/logs/jobs.log
```

#### Solutions

**Clear Job Queue**
```bash
# Clear all jobs
aidp jobs clear

# Clear specific job types
aidp jobs clear --type=harness
```

**Restart Job Manager**
```bash
# Stop job manager
aidp jobs stop

# Start job manager
aidp jobs start
```

**Check Job Configuration**
```yaml
# aidp.yml - Configure job management
harness:
  job_management:
    max_concurrent_jobs: 3
    job_timeout: 3600
    cleanup_interval: 300
```

## Advanced Troubleshooting

### Debug Mode

Enable debug mode for detailed logging:

```bash
# Run with debug logging
AIDP_DEBUG=1 aidp analyze

# Run with verbose output
AIDP_VERBOSE=1 aidp execute

# Set debug log level
AIDP_LOG_LEVEL=debug aidp analyze
```

### Performance Profiling

Profile harness performance:

```bash
# Enable performance profiling
AIDP_PROFILE=1 aidp analyze

# Check performance metrics
aidp metrics show --format=json

# Export performance data
aidp metrics export --format=csv --output=performance.csv
```

### Network Issues

Diagnose network connectivity:

```bash
# Test provider connectivity
curl -I https://api.anthropic.com
curl -I https://generativelanguage.googleapis.com

# Check DNS resolution
nslookup api.anthropic.com
nslookup generativelanguage.googleapis.com

# Check proxy settings
echo $HTTP_PROXY
echo $HTTPS_PROXY
```

### System Resource Issues

Check system resources:

```bash
# Check disk space
df -h

# Check memory usage
free -h

# Check CPU usage
top

# Check file descriptors
lsof | wc -l
```

## Error Code Reference

### Common Error Codes

| Error Code | Description | Solution |
|------------|-------------|----------|
| `HARNESS_INIT_FAILED` | Harness initialization failed | Check configuration and dependencies |
| `PROVIDER_AUTH_FAILED` | Provider authentication failed | Check API keys and configuration |
| `RATE_LIMIT_EXCEEDED` | Rate limit exceeded | Configure fallback providers |
| `STATE_CORRUPTED` | State file corrupted | Reset state or restore from backup |
| `CONFIG_INVALID` | Configuration is invalid | Validate and fix configuration |
| `PROVIDER_UNAVAILABLE` | Provider is unavailable | Check provider status and configuration |
| `JOB_QUEUE_FULL` | Job queue is full | Clear job queue or increase limits |
| `TIMEOUT_EXCEEDED` | Operation timed out | Increase timeout values |
| `INPUT_VALIDATION_FAILED` | User input validation failed | Check input format and requirements |
| `CIRCUIT_BREAKER_OPEN` | Circuit breaker is open | Wait for circuit to close or reset |

### Error Recovery Strategies

```bash
# Automatic recovery
aidp harness recover

# Manual recovery
aidp harness reset --mode=analyze

# Emergency recovery
aidp harness emergency-reset
```

## Getting Help

### Self-Service Resources

```bash
# Show help
aidp help

# Show harness help
aidp harness help

# Show configuration help
aidp config help

# Show troubleshooting tips
aidp troubleshoot
```

### Log Analysis

```bash
# Analyze error patterns
aidp logs analyze --pattern=error

# Export logs for analysis
aidp logs export --format=json --output=logs.json

# Search logs
aidp logs search --query="rate limit"
```

### Community Support

- **GitHub Issues**: Report bugs and request features
- **Documentation**: Check the official documentation
- **Community Forum**: Ask questions and share solutions

## Prevention

### Best Practices

1. **Regular Backups**
   ```bash
   # Backup configuration
   aidp config backup

   # Backup state
   aidp harness backup
   ```

2. **Monitor Usage**
   ```bash
   # Check usage regularly
   aidp metrics show

   # Monitor costs
   aidp cost show
   ```

3. **Test Configuration**
   ```bash
   # Test before production use
   aidp config validate

   # Test with simple commands
   aidp analyze 01_REPOSITORY_ANALYSIS
   ```

4. **Keep Updated**
   ```bash
   # Update AIDP regularly
   gem update aidp

   # Check for updates
   aidp version --check-updates
   ```

### Monitoring Setup

```yaml
# aidp.yml - Enable monitoring
harness:
  metrics:
    enabled: true
    collection_interval: 60
    retention_days: 30

  logging:
    level: "info"
    retention_days: 30
    max_file_size: "10MB"
```

## Conclusion

This troubleshooting guide covers the most common issues you might encounter with the AIDP Harness. Most problems can be resolved by:

1. Checking the configuration
2. Validating the setup
3. Reviewing the logs
4. Resetting the state if needed

If you continue to experience issues, please check the logs and provide detailed information when seeking help. The harness is designed to be robust and self-healing, but understanding these troubleshooting steps will help you resolve issues quickly.
