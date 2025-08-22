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
| Provider | AI provider type (cursor, claude, gemini) |
| Status | Current job status (running, completed, failed, queued) |
| Duration | Execution time (for completed/failed jobs) |
| Error | Error message (for failed jobs) |

## Interactive Controls

While in the jobs view, you can use the following keyboard controls:

### Navigation

- **Arrow keys** - Navigate between jobs
- **Enter** - Select highlighted job for actions

### Actions

- **r** - Retry a failed job
- **d** - View detailed job information
- **q** - Exit the jobs view

### Job Details View

When viewing job details (press `d`), you'll see:

- **Job ID** - Unique identifier
- **Provider** - AI provider used
- **Status** - Current status
- **Created** - When the job was created
- **Started** - When execution began
- **Completed** - When execution finished
- **Duration** - Total execution time
- **Error** - Error details (if failed)
- **Metadata** - Additional job information

## Job States

### Running

Jobs currently being processed by an AI provider. These show live progress updates.

### Queued

Jobs waiting to be processed. They will start automatically when a worker becomes available.

### Completed

Successfully finished jobs with their output stored.

### Failed

Jobs that encountered an error during execution. These can be retried.

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

- **jobs** - Core job metadata and status
- **job_executions** - Execution attempts and outcomes
- **job_logs** - Detailed execution logs and progress

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

## Examples

### Monitor Jobs During Execution

```bash
# Start a step in one terminal
aidp execute next

# Monitor progress in another terminal
aidp jobs
```

### Retry Failed Jobs

```bash
aidp jobs
# Navigate to failed job and press 'r'
```

### View Job History

```bash
aidp jobs
# Navigate to any job and press 'd' for details
```

## Best Practices

1. **Monitor during long operations** - Use `aidp jobs` to track progress
2. **Retry transient failures** - Many failures are temporary and can be retried
3. **Check job details** - Use the details view to understand failures
4. **Keep PostgreSQL running** - Jobs require the database to be available
