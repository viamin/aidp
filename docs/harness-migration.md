# AIDP Harness Migration Guide

## Overview

This guide helps you migrate from the traditional step-by-step AIDP workflow to the new autonomous harness mode. The harness transforms AIDP from a manual tool into an intelligent development assistant that runs complete workflows automatically.

## What's Changing

### Before (Step-by-Step Mode)

- Manual execution of individual steps
- Manual provider management
- Manual error handling and retries
- Manual progress tracking
- Manual user input collection

### After (Harness Mode)

- Automatic execution of complete workflows
- Intelligent provider switching and management
- Automatic error recovery and retry logic
- Real-time progress tracking and monitoring
- Interactive user input collection

## Migration Benefits

### Immediate Benefits

- **Automation**: Complete workflows run without manual intervention
- **Intelligence**: Smart provider switching and error recovery
- **Efficiency**: Reduced manual overhead and faster execution
- **Reliability**: Better error handling and recovery mechanisms

### Long-term Benefits

- **Scalability**: Handle larger, more complex projects
- **Consistency**: Standardized execution across different environments
- **Monitoring**: Better visibility into execution progress and performance
- **Flexibility**: Easy configuration and customization

## Migration Steps

### Step 1: Update AIDP

First, ensure you have the latest version of AIDP with harness support:

```bash
# Update AIDP
gem update aidp

# Verify version
aidp version

# Should show version 0.7.0 or later
```

### Step 2: Backup Current Configuration

Backup your existing configuration and state:

```bash
# Backup existing configuration
cp .aidp.yml .aidp.yml.backup 2>/dev/null || echo "No existing config"

# Backup existing progress
cp .aidp-progress.yml .aidp-progress.yml.backup 2>/dev/null || echo "No existing progress"
cp .aidp-analyze-progress.yml .aidp-analyze-progress.yml.backup 2>/dev/null || echo "No existing progress"

# Backup existing state
cp -r .aidp .aidp.backup 2>/dev/null || echo "No existing state"
```

### Step 3: Create Basic Configuration

Create a basic `aidp.yml` configuration file:

```bash
# Create basic configuration
cat > aidp.yml << 'EOF'
harness:
  enabled: true
  max_retries: 2
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]

providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
    default_flags: ["--dangerously-skip-permissions"]
  gemini:
    type: "api"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
    cursor:
      type: "subscription"
EOF
```

### Step 4: Set Environment Variables

Set up your API keys:

```bash
# Set Claude API key
export AIDP_CLAUDE_API_KEY="your-claude-api-key"

# Set Gemini API key
export AIDP_GEMINI_API_KEY="your-gemini-api-key"

# Add to shell profile for persistence
echo 'export AIDP_CLAUDE_API_KEY="your-claude-api-key"' >> ~/.bashrc
echo 'export AIDP_GEMINI_API_KEY="your-gemini-api-key"' >> ~/.bashrc
```

### Step 5: Test Basic Functionality

Test the harness with a simple command:

```bash
# Test harness with a single step
aidp analyze 01_REPOSITORY_ANALYSIS

# Should show harness mode in action
```

### Step 6: Run Complete Workflow

Try running a complete workflow:

```bash
# Run complete analysis
aidp analyze

# Run complete development
aidp execute
```

## Configuration Migration

### Migrate Existing Configuration

If you have existing configuration, migrate it:

```bash
# Auto-migrate configuration
aidp config migrate

# Or manual migration
aidp config migrate --input=.aidp.yml.backup --output=aidp.yml
```

### Common Configuration Mappings

#### Provider Configuration

```yaml
# Old format (if any)
provider: "claude"
model: "claude-3-sonnet"

# New format
harness:
  default_provider: "claude"
providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
```

#### Retry Configuration

```yaml
# Old format (if any)
max_retries: 3

# New format
harness:
  max_retries: 3
  error_recovery:
    network_error:
      strategy: "linear_backoff"
      max_retries: 3
      base_delay: 1.0
```

#### Timeout Configuration

```yaml
# Old format (if any)
timeout: 30

# New format
providers:
  claude:
    timeout: 30
  gemini:
    timeout: 45
```

## Workflow Migration

### Analyze Mode Migration

#### Before (Step-by-Step)

```bash
# Manual step execution
aidp analyze 01_REPOSITORY_ANALYSIS
aidp analyze 02_ARCHITECTURE_ANALYSIS
aidp analyze 03_TEST_ANALYSIS
aidp analyze 04_FUNCTIONALITY_ANALYSIS
aidp analyze 05_DOCUMENTATION_ANALYSIS
aidp analyze 06_STATIC_ANALYSIS
aidp analyze 07_REFACTORING_RECOMMENDATIONS
```

#### After (Harness Mode)

```bash
# Automatic execution
aidp analyze
```

### Execute Mode Migration

#### Before (Step-by-Step)

```bash
# Manual step execution
aidp execute 00_PRD
aidp execute 01_NFRS
aidp execute 02_ARCHITECTURE
aidp execute 02A_ARCH_GATE_QUESTIONS
aidp execute 03_ADR_FACTORY
aidp execute 04_DOMAIN_DECOMPOSITION
aidp execute 05_API_DESIGN
aidp execute 06_DATA_MODEL
aidp execute 07_SECURITY_REVIEW
aidp execute 08_PERFORMANCE_REVIEW
aidp execute 09_RELIABILITY_REVIEW
aidp execute 10_TESTING_STRATEGY
aidp execute 11_STATIC_ANALYSIS
aidp execute 12_OBSERVABILITY_SLOS
aidp execute 13_DELIVERY_ROLLOUT
aidp execute 14_DOCS_PORTAL
aidp execute 15_POST_RELEASE
```

#### After (Harness Mode)

```bash
# Automatic execution
aidp execute
```

## State Migration

### Progress Migration

The harness automatically migrates existing progress:

```bash
# Check existing progress
aidp status

# Harness will automatically load existing progress
# and continue from where you left off
```

### State File Migration

```bash
# Old state files
.aidp-progress.yml
.aidp-analyze-progress.yml

# New state files
.aidp/harness/analyze_state.json
.aidp/harness/execute_state.json
```

## Provider Migration

### API Key Migration

#### Before

```bash
# Manual API key management
export ANTHROPIC_API_KEY="your-key"
export GEMINI_API_KEY="your-key"
```

#### After

```bash
# Standardized API key management
export AIDP_CLAUDE_API_KEY="your-key"
export AIDP_GEMINI_API_KEY="your-key"
```

### Provider Configuration Migration

#### Before

```yaml
# Old provider configuration (if any)
provider: "claude"
model: "claude-3-sonnet"
max_tokens: 100000
```

#### After

```yaml
# New provider configuration
harness:
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]

providers:
  claude:
    type: "api"
    api_key: "${AIDP_CLAUDE_API_KEY}"
    max_tokens: 100000
    default_flags: ["--dangerously-skip-permissions"]
  gemini:
    type: "api"
    api_key: "${AIDP_GEMINI_API_KEY}"
    max_tokens: 50000
    cursor:
      type: "subscription"
```

## Error Handling Migration

### Before (Manual Error Handling)

```bash
# Manual retry on failure
aidp analyze 01_REPOSITORY_ANALYSIS
# If fails, manually retry or switch providers
aidp analyze 01_REPOSITORY_ANALYSIS --provider=gemini
```

### After (Automatic Error Handling)

```yaml
# Automatic error handling configuration
harness:
  max_retries: 2
  fallback_providers: ["gemini", "cursor"]
  error_recovery:
    network_error:
      strategy: "linear_backoff"
      max_retries: 3
      base_delay: 1.0
    server_error:
      strategy: "exponential_backoff"
      max_retries: 5
      base_delay: 2.0
    rate_limit:
      strategy: "immediate_switch"
      max_retries: 0
```

## User Interaction Migration

### Before (Manual Input)

```bash
# Manual step execution with manual input
aidp execute 00_PRD
# Manually answer questions when prompted
aidp execute 01_NFRS
# Manually answer questions when prompted
```

### After (Interactive Input)

```bash
# Automatic execution with interactive input
aidp execute
# Harness automatically presents questions and collects input
```

## Monitoring Migration

### Before (Manual Monitoring)

```bash
# Manual progress checking
aidp status
# Manual job monitoring
aidp jobs
```

### After (Real-time Monitoring)

```bash
# Real-time status display
aidp harness status

# Real-time progress tracking
aidp status

# Real-time job monitoring
aidp jobs
```

## Testing Migration

### Test Harness Functionality

```bash
# Test basic harness functionality
aidp analyze 01_REPOSITORY_ANALYSIS

# Test complete workflow
aidp analyze

# Test error handling
aidp execute 00_PRD
```

### Validate Configuration

```bash
# Validate configuration
aidp config validate

# Show configuration
aidp config show

# Test provider connectivity
aidp analyze 01_REPOSITORY_ANALYSIS --provider=claude
aidp analyze 01_REPOSITORY_ANALYSIS --provider=gemini
```

## Rollback Plan

### If You Need to Rollback

```bash
# Restore old configuration
cp .aidp.yml.backup .aidp.yml

# Restore old progress
cp .aidp-progress.yml.backup .aidp-progress.yml 2>/dev/null || true
cp .aidp-analyze-progress.yml.backup .aidp-analyze-progress.yml 2>/dev/null || true

# Restore old state
rm -rf .aidp
cp -r .aidp.backup .aidp 2>/dev/null || true

# Use traditional mode
aidp analyze 01_REPOSITORY_ANALYSIS --no-harness
```

### Disable Harness Temporarily

```yaml
# aidp.yml - Disable harness
harness:
  enabled: false
```

## Best Practices for Migration

### 1. Start Small

Begin with simple workflows:

```bash
# Start with single step
aidp analyze 01_REPOSITORY_ANALYSIS

# Then try complete workflow
aidp analyze
```

### 2. Test Thoroughly

Test all your common workflows:

```bash
# Test analyze mode
aidp analyze

# Test execute mode
aidp execute

# Test specific steps
aidp analyze 01_REPOSITORY_ANALYSIS
aidp execute 00_PRD
```

### 3. Monitor Performance

Keep an eye on performance:

```bash
# Check status regularly
aidp harness status

# Monitor metrics
aidp metrics show

# Check logs
tail -f .aidp/logs/harness.log
```

### 4. Configure Gradually

Add configuration options gradually:

```yaml
# Start with basic configuration
harness:
  enabled: true
  default_provider: "claude"

# Add fallback providers
harness:
  enabled: true
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]

# Add error recovery
harness:
  enabled: true
  default_provider: "claude"
  fallback_providers: ["gemini", "cursor"]
  error_recovery:
    network_error:
      strategy: "linear_backoff"
      max_retries: 3
```

### 5. Keep Backups

Always keep backups:

```bash
# Regular backups
aidp config backup
aidp harness backup

# Before major changes
cp aidp.yml aidp.yml.$(date +%Y%m%d)
```

## Common Migration Issues

### Issue 1: Configuration Not Loading

**Symptoms**: Harness not starting, configuration errors

**Solution**:

```bash
# Validate configuration
aidp config validate

# Reset to defaults
aidp config reset

# Create minimal configuration
echo "harness:\n  enabled: true" > aidp.yml
```

### Issue 2: Provider Authentication

**Symptoms**: Authentication errors, provider not working

**Solution**:

```bash
# Check environment variables
echo $AIDP_CLAUDE_API_KEY
echo $AIDP_GEMINI_API_KEY

# Set API keys
export AIDP_CLAUDE_API_KEY="your-key"
export AIDP_GEMINI_API_KEY="your-key"
```

### Issue 3: State Corruption

**Symptoms**: Harness can't resume, state errors

**Solution**:

```bash
# Reset state
aidp harness reset --mode=analyze

# Or restore from backup
aidp harness restore --backup=backup-2024-01-01.json
```

### Issue 4: Performance Issues

**Symptoms**: Slow execution, timeouts

**Solution**:

```yaml
# Optimize configuration
harness:
  max_retries: 2
providers:
  claude:
    timeout: 30
  gemini:
    timeout: 45
```

## Migration Checklist

### Pre-Migration

- [ ] Update AIDP to latest version
- [ ] Backup existing configuration
- [ ] Backup existing progress and state
- [ ] Set up API keys
- [ ] Test basic functionality

### Migration

- [ ] Create basic configuration
- [ ] Test single step execution
- [ ] Test complete workflow
- [ ] Validate configuration
- [ ] Test error handling

### Post-Migration

- [ ] Monitor performance
- [ ] Check logs for errors
- [ ] Test all common workflows
- [ ] Configure advanced features
- [ ] Document any customizations

## Support

### Getting Help

If you encounter issues during migration:

1. **Check Documentation**: Review the harness usage and configuration guides
2. **Validate Configuration**: Use `aidp config validate`
3. **Check Logs**: Review error logs for specific issues
4. **Test Incrementally**: Start with simple configurations and add complexity
5. **Community Support**: Ask questions in the community forum

### Useful Commands

```bash
# Configuration
aidp config validate
aidp config show
aidp config reset

# Harness
aidp harness status
aidp harness reset --mode=analyze
aidp harness backup

# Testing
aidp analyze 01_REPOSITORY_ANALYSIS
aidp execute 00_PRD
aidp status
```

## Conclusion

The migration to harness mode transforms AIDP from a manual tool into an intelligent development assistant. While the migration requires some initial setup, the benefits of automation, intelligence, and reliability make it worthwhile.

Take your time with the migration, test thoroughly, and don't hesitate to rollback if needed. The harness is designed to be backward compatible, so you can always fall back to traditional mode if necessary.

Once migrated, you'll enjoy the benefits of:

- Automatic workflow execution
- Intelligent provider management
- Robust error handling
- Real-time monitoring
- Interactive user experience

Welcome to the future of AI-assisted development with AIDP Harness!
