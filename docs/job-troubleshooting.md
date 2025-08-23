# Job Troubleshooting Guide

This guide helps you diagnose and resolve common issues with background jobs in AIDP.

## Quick Diagnosis

### Check Job Status

```bash
# View all jobs and their status
aidp jobs
```

### Check Job Output

```bash
# View job output and activity
aidp jobs
# Press 'o' to view output for a specific job
```

### Kill Hung Jobs

```bash
# Kill a job that's stuck
aidp jobs
# Navigate to the job and press 'k'
# Confirm with 'y'
```

## Common Issues

### 1. Jobs Not Starting

**Symptoms:**
- Jobs remain in "queued" status
- No progress updates
- Database connection errors

**Solutions:**

#### Check Database Connection

```bash
# Verify PostgreSQL is running
brew services list | grep postgresql

# Check database exists
psql -l | grep aidp

# Test connection
psql aidp -c "SELECT 1;"
```

#### Verify Que Setup

```bash
# Check Que tables exist
psql aidp -c "\dt" | grep que

# Should show:
# - que_jobs
# - que_lockers
# - que_values
```

#### Restart Services

```bash
# Restart PostgreSQL
brew services restart postgresql@14

# Restart AIDP CLI
# (just restart your terminal session)
```

### 2. Jobs Stuck in "Running" Status

**Symptoms:**
- Jobs show "running" for extended periods
- No progress updates
- System appears unresponsive

**Solutions:**

#### Check for Hung Jobs

```bash
# View job output to check activity
aidp jobs
# Press 'o' to view output
# Look for warning messages about long-running jobs
```

#### Kill Stuck Jobs

```bash
# Kill jobs that have been running too long
aidp jobs
# Navigate to stuck job and press 'k'
# Confirm with 'y'
```

#### Check System Resources

```bash
# Check CPU and memory usage
top -p $(pgrep -f aidp)

# Check disk space
df -h

# Check for hanging processes
ps aux | grep -E "(cursor-agent|claude|gemini)"
```

### 3. Failed Jobs

**Symptoms:**
- Jobs show "failed" status
- Error messages in job details
- Repeated failures

**Solutions:**

#### Review Error Details

```bash
# View job details and error messages
aidp jobs
# Navigate to failed job and press 'd'
```

#### Check Provider Availability

**Cursor:**

```bash
# Check if cursor-agent is available
which cursor-agent

# Install if missing
npm install -g @cursor/agent
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

#### Retry Failed Jobs

```bash
# Retry a failed job
aidp jobs
# Navigate to failed job and press 'r'
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

#### Use Job Output View

```bash
# Check job activity and detect hung jobs
aidp jobs
# Press 'o' to view output
# Look for warning messages about long-running jobs
```

#### Kill Hung Jobs

```bash
# Kill jobs that appear stuck
aidp jobs
# Navigate to hung job and press 'k'
# Confirm with 'y'
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
pg_dump aidp > aidp_backup.sql

# Drop and recreate database
dropdb aidp
createdb aidp

# Restore if needed
psql aidp < aidp_backup.sql
```

#### Check Database Integrity

```bash
# Check for corruption
psql aidp -c "VACUUM ANALYZE;"
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
psql aidp -c "VACUUM ANALYZE;"
psql aidp -c "REINDEX DATABASE aidp;"
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
export QUE_WORKER_COUNT=2

# Database settings
export AIDP_DB_NAME=aidp
export AIDP_DB_HOST=localhost
export AIDP_DB_PORT=5432
export AIDP_DB_USER=your_username
export AIDP_DB_PASSWORD=your_password
```

## Advanced Troubleshooting

### Check Job Output and Activity

```bash
# View detailed job output
aidp jobs
# Press 'o' to view output for a specific job
# This shows:
# - Recent output from job execution
# - Warning messages for hung jobs
# - Error details for failed jobs
```

### Monitor Job Progress

```bash
# Watch job status in real-time
watch -n 2 'aidp jobs'
```

### Check Database Queries

```bash
# View recent jobs
psql aidp -c "SELECT id, job_class, status, run_at, finished_at FROM que_jobs ORDER BY run_at DESC LIMIT 10;"

# Check for stuck jobs
psql aidp -c "SELECT id, job_class, run_at, EXTRACT(EPOCH FROM (NOW() - run_at))/60 as minutes_running FROM que_jobs WHERE finished_at IS NULL AND error_count = 0;"
```

### Kill Multiple Hung Jobs

```bash
# Kill all jobs running longer than 30 minutes
psql aidp -c "UPDATE que_jobs SET finished_at = NOW(), last_error_message = 'Job killed by system (timeout)', error_count = error_count + 1 WHERE finished_at IS NULL AND run_at < NOW() - INTERVAL '30 minutes';"
```

## Prevention Strategies

### 1. Regular Monitoring

- Check job status regularly during long workflows
- Use the output view to verify job activity
- Monitor system resources

### 2. Proper Job Management

- Kill jobs that have been running for extended periods
- Retry failed jobs after checking error messages
- Keep provider tools updated

### 3. System Maintenance

- Regularly restart PostgreSQL
- Monitor disk space and memory usage
- Keep AIDP and dependencies updated

### 4. Configuration Best Practices

- Set appropriate worker counts
- Use debug mode for troubleshooting
- Configure proper database timeouts

## Getting Help

If you're still experiencing issues:

1. **Enable debug mode** and check logs
2. **Review job output** using the output view
3. **Check system resources** and provider availability
4. **Kill hung jobs** and retry failed ones
5. **Restart services** if needed

For persistent issues, check:
- PostgreSQL logs: `tail -f /usr/local/var/log/postgresql@14.log`
- System logs: `dmesg | tail -20`
- Provider tool logs (check individual tool documentation)
