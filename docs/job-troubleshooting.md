# Job Troubleshooting Guide

This guide helps you resolve common issues with AIDP's background job system.

## Common Issues

### 1. PostgreSQL Connection Issues

**Symptoms:**

- "database connection failed" errors
- Jobs not appearing in `aidp jobs`
- CLI hangs when trying to access jobs

**Solutions:**

#### Check PostgreSQL Installation

```bash
# macOS
brew list postgresql || brew install postgresql

# Ubuntu/Debian
sudo systemctl status postgresql
```

#### Start PostgreSQL Service

```bash
# macOS
brew services start postgresql

# Ubuntu/Debian
sudo systemctl start postgresql
```

#### Verify Connection

```bash
# Test PostgreSQL connection
psql -h localhost -U postgres -c "SELECT version();"
```

#### Check Database Creation

AIDP creates the database automatically on first use. If it fails:

```bash
# Create database manually
createdb aidp_jobs
```

### 2. Jobs Not Starting

**Symptoms:**

- Jobs remain in "queued" status
- No progress updates
- CLI shows "waiting for job" indefinitely

**Solutions:**

#### Check Worker Process

```bash
# Check if Que workers are running
ps aux | grep que
```

#### Restart Workers

```bash
# Kill existing workers
pkill -f que

# Restart AIDP (workers start automatically)
aidp status
```

#### Check Database Permissions

```bash
# Ensure your user can access the database
psql -h localhost -U postgres -d aidp_jobs -c "SELECT 1;"
```

### 3. Failed Jobs

**Symptoms:**

- Jobs show "failed" status
- Error messages in job details
- Repeated failures

**Solutions:**

#### Check AI Provider Availability

```bash
# Test provider availability
aidp detect
```

#### Review Error Messages

```bash
# View job details for error information
aidp jobs
# Navigate to failed job and press 'd'
```

#### Common Provider Issues

**Cursor Agent:**

```bash
# Check if cursor-agent is installed
which cursor-agent

# Install if missing
npm install -g @cursor/cli
```

**Claude:**

```bash
# Check if claude CLI is available
which claude

# Install if missing
pip install claude-cli
```

**Gemini:**

```bash
# Check if gemini CLI is available
which gemini

# Install if missing
pip install google-generativeai
```

### 4. Job Timeout Issues

**Symptoms:**

- Jobs hang indefinitely
- No progress updates
- Provider processes not responding

**Solutions:**

#### Check Provider Process

```bash
# Look for hanging provider processes
ps aux | grep -E "(cursor-agent|claude|gemini)"
```

#### Kill Hanging Processes

```bash
# Kill hanging provider processes
pkill -f cursor-agent
pkill -f claude
pkill -f gemini
```

#### Retry Jobs

```bash
# Retry failed jobs
aidp jobs
# Navigate to failed job and press 'r'
```

### 5. Database Corruption

**Symptoms:**

- Unexpected errors when accessing jobs
- Missing job history
- CLI crashes when running jobs

**Solutions:**

#### Backup and Reset Database

```bash
# Backup existing database
pg_dump aidp_jobs > aidp_jobs_backup.sql

# Drop and recreate database
dropdb aidp_jobs
createdb aidp_jobs

# Restore if needed
psql aidp_jobs < aidp_jobs_backup.sql
```

#### Check Database Integrity

```bash
# Check for corruption
psql aidp_jobs -c "VACUUM ANALYZE;"
```

### 6. Performance Issues

**Symptoms:**

- Slow job processing
- High memory usage
- Database connection timeouts

**Solutions:**

#### Optimize Database

```bash
# Run database maintenance
psql aidp_jobs -c "VACUUM ANALYZE;"
psql aidp_jobs -c "REINDEX DATABASE aidp_jobs;"
```

#### Adjust Worker Count

```bash
# Set worker count (default: 1)
export QUE_WORKER_COUNT=2
aidp execute next
```

#### Monitor Resource Usage

```bash
# Check memory and CPU usage
top -p $(pgrep -f aidp)
```

## Debug Mode

Enable debug mode to get detailed information about job processing:

```bash
# Enable debug logging
AIDP_DEBUG=1 aidp jobs

# Log to file
AIDP_DEBUG=1 AIDP_LOG_FILE=aidp_jobs.log aidp jobs
```

## Environment Variables

Use these environment variables to troubleshoot:

```bash
# Debug mode
export AIDP_DEBUG=1

# Log file
export AIDP_LOG_FILE=/path/to/logfile.log

# Worker count
export QUE_WORKER_COUNT=1

# Database connection
export DATABASE_URL=postgresql://user:pass@localhost/aidp_jobs
```

## Log Analysis

Check logs for specific error patterns:

```bash
# Search for error patterns
grep -i "error\|failed\|timeout" aidp_jobs.log

# Check provider-specific errors
grep -i "cursor\|claude\|gemini" aidp_jobs.log
```

## Getting Help

If you're still experiencing issues:

1. **Enable debug mode** and reproduce the issue
2. **Check the logs** for error messages
3. **Note the exact steps** that cause the problem
4. **Include environment information** (OS, Ruby version, etc.)

## Prevention

To avoid job-related issues:

1. **Keep PostgreSQL running** - Use system services or process managers
2. **Monitor disk space** - Ensure adequate storage for job logs
3. **Regular maintenance** - Run database maintenance periodically
4. **Update providers** - Keep AI provider CLIs up to date
5. **Check connectivity** - Ensure stable network for provider API calls
