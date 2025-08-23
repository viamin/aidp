# Jobs Command Usage Guide

The `aidp jobs` command provides real-time monitoring and management of background jobs that handle AI provider executions.

## Overview

All AI provider executions (Cursor, Claude, Gemini) are processed through background jobs to improve reliability and provide better visibility into long-running operations.

## Basic Usage

```bash
aidp jobs
```

This starts an interactive job monitoring session that displays:

- Currently running jobs
- Queued jobs waiting to be processed
- Recently completed jobs
- Failed jobs with error details

## Job Status Display

The jobs view shows a table with the following columns:

| Column | Description |
|--------|-------------|
| ID | Unique job identifier |
| Job | AI provider job type (ProviderExecutionJob, etc.) |
| Queue | Job queue name (default: "default") |
| Status | Current job status (running, completed, failed, queued) |
| Runtime | Execution time (for completed/failed jobs) |
| Error | Error message (for failed jobs) |

## Interactive Controls

While in the jobs view, you can use the following keyboard controls:

### Navigation

- **Arrow keys** - Navigate between jobs
- **Enter** - Select highlighted job for actions

### Actions

- **d** - View detailed job information
- **o** - View job output and check for hung jobs
- **r** - Retry a failed job
- **k** - Kill a running job (with confirmation)
- **q** - Exit the jobs view

### Job Details View

When viewing job details (press `d`), you'll see:

- **Job ID** - Unique identifier
- **Job Class** - Type of job being executed
- **Queue** - Job queue name
- **Status** - Current status
- **Runtime** - Total execution time
- **Started** - When execution began
- **Finished** - When execution finished
- **Attempts** - Number of execution attempts
- **Error** - Error details (if failed)

### Job Output View

When viewing job output (press `o`), you'll see:

- **Recent Output** - Any available output from the job execution
- **Hung Job Detection** - Warning if job has been running for more than 5 minutes
- **Error Messages** - Any error output from failed jobs
- **Activity Status** - Information about job activity and potential issues

**Note**: Job output availability depends on the job type and execution status. Some jobs may not produce output until completion.

## Job States

### Running

Jobs currently being processed by an AI provider. These show live progress updates.

### Queued

Jobs waiting to be processed. They will start automatically when a worker becomes available.

### Completed

Successfully finished jobs with their output stored.

### Failed

Jobs that encountered an error during execution. These can be retried.

## Hung Job Detection

The system automatically detects jobs that may be hung or stuck:

- **Warning Threshold**: Jobs running for more than 5 minutes
- **Detection Method**: Runtime analysis and activity monitoring
- **User Action**: Use the kill command (`k`) to terminate hung jobs

## Killing Jobs

To kill a running job:

1. Navigate to the running job using arrow keys
2. Press `k` to initiate kill command
3. Confirm the action by typing `y` or `yes`
4. The job will be marked as killed with an error message

**Safety Features**:
- Only running jobs can be killed
- Confirmation prompt prevents accidental kills
- Killed jobs are marked with "Job killed by user" error

## Retrying Failed Jobs

To retry a failed job:

1. Navigate to the failed job using arrow keys
2. Press `r` to retry
3. The job will be re-queued and processed again

**Note**: Retrying a job creates a new execution attempt while preserving the original job history.

## Job Persistence

- Jobs persist across CLI restarts
- Job history is preserved for analysis
- Failed jobs can be retried at any time
- All job metadata and logs are stored in the database

## Database Storage

Jobs are stored in PostgreSQL with the following structure:

- **que_jobs** - Core job metadata and status
- **que_lockers** - Job locking information
- **que_values** - Job configuration values

## Troubleshooting

### No Jobs Displayed

- Ensure PostgreSQL is running
- Check that you've executed at least one step
- Verify database connection

### Jobs Stuck in "Queued" Status

- Check if PostgreSQL is running
- Verify database connectivity
- Restart the CLI if needed

### Failed Jobs

- Review error messages in job details
- Check AI provider availability
- Retry the job if it was a transient failure

### Hung Jobs

- Use the output view (`o`) to check job activity
- Look for warning messages about long-running jobs
- Consider killing the job if it appears stuck
- Check system resources and provider availability

### Database Issues

- Ensure PostgreSQL is installed and running
- Check database permissions
- Verify connection settings

## Environment Variables

The following environment variables affect job behavior:

- `AIDP_DEBUG=1` - Enable debug logging for job processing
- `AIDP_LOG_FILE=path` - Log job operations to a file
- `QUE_WORKER_COUNT=N` - Number of background workers (default: 1)

## Integration with Workflow

The jobs command integrates seamlessly with the main workflow:

1. **Execute steps** - All AI provider calls are processed as background jobs
2. **Monitor progress** - Use `aidp jobs` to see real-time progress
3. **Handle failures** - Retry failed jobs without restarting the workflow
4. **Continue workflow** - Jobs don't block the main CLI execution
5. **Debug issues** - Use output view to check job activity and detect hung jobs

## Examples

### Monitor Jobs During Execution

```bash
# Start a background job
aidp analyze next --background

# Monitor job progress
aidp jobs
```

### Check Job Output and Activity

```bash
# View job output and check for hung jobs
aidp jobs
# Press 'o' to view output
```

### Kill a Hung Job

```bash
# Kill a job that's been running too long
aidp jobs
# Navigate to the job and press 'k'
# Confirm with 'y'
```

### Retry a Failed Job

```bash
# Retry a job that failed
aidp jobs
# Navigate to failed job and press 'r'
```

## Best Practices

1. **Regular Monitoring**: Check job status regularly during long workflows
2. **Output Review**: Use the output view to verify job activity
3. **Hung Job Management**: Kill jobs that have been running for extended periods
4. **Error Analysis**: Review error messages before retrying failed jobs
5. **Resource Management**: Monitor system resources when running multiple jobs
