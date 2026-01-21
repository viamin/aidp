# Temporal Deployment Guide

This guide covers deploying and using Temporal for durable workflow orchestration in AIDP.

## Overview

Temporal provides durable workflow execution for AIDP, enabling:

- **Durability**: Workflows survive crashes and restarts
- **Observability**: Full execution history and replay capability
- **Reliability**: Built-in retry, timeout, and cancellation handling
- **Scalability**: Horizontal scaling of workers and workflows

## Quick Start

### 1. Start Temporal Server

For local development, use Docker Compose:

```bash
docker-compose -f docker-compose.temporal.yml up -d
```

This starts:
- PostgreSQL (persistence backend)
- Temporal Server (port 7233)
- Temporal UI (port 8080)
- Temporal Admin Tools

### 2. Configure AIDP

Add Temporal configuration to your `aidp.yml`:

```yaml
temporal:
  enabled: true
  target_host: "localhost:7233"
  namespace: "default"
  task_queue: "aidp-workflows"
```

Or use the setup wizard:

```bash
aidp temporal setup
```

### 3. Start the Worker

Run the AIDP Temporal worker:

```bash
aidp temporal worker
```

The worker executes workflows and activities on the configured task queue.

### 4. Start a Workflow

Start an issue-to-PR workflow:

```bash
aidp temporal start issue 123
```

Or a work loop workflow:

```bash
aidp temporal start workloop my_step
```

## Configuration Reference

### aidp.yml Settings

```yaml
temporal:
  # Enable/disable Temporal (default: true when configured)
  enabled: true

  # Temporal server address
  target_host: "localhost:7233"

  # Temporal namespace (must be created first)
  namespace: "default"

  # Task queue for workflows and activities
  task_queue: "aidp-workflows"

  # Enable TLS for server connection
  tls: false

  # API key for Temporal Cloud
  # api_key: "your-api-key"

  # Worker configuration
  worker:
    max_concurrent_activities: 10
    max_concurrent_workflows: 10
    shutdown_grace_period: 30

  # Timeout configuration (in seconds)
  timeouts:
    workflow_execution: 86400    # 24 hours
    workflow_run: 3600           # 1 hour
    activity_start_to_close: 600 # 10 minutes
    activity_schedule_to_close: 1800 # 30 minutes
    activity_heartbeat: 60       # 1 minute

  # Retry policy
  retry:
    initial_interval: 1
    backoff_coefficient: 2.0
    maximum_interval: 60
    maximum_attempts: 3
```

### Environment Variables

Environment variables override aidp.yml settings:

| Variable | Description |
|----------|-------------|
| `TEMPORAL_HOST` | Server address (e.g., `localhost:7233`) |
| `TEMPORAL_NAMESPACE` | Namespace name |
| `TEMPORAL_TASK_QUEUE` | Task queue name |
| `TEMPORAL_API_KEY` | API key for Temporal Cloud |
| `TEMPORAL_TLS` | Enable TLS (`true`/`false`) |
| `TEMPORAL_ENABLED` | Enable Temporal (`true`/`false`) |

## CLI Commands

### Workflow Management

```bash
# Start a workflow
aidp temporal start issue <number>
aidp temporal start workloop <step_name>

# List active workflows
aidp temporal list

# Get workflow status
aidp temporal status <workflow_id>
aidp temporal status <workflow_id> --follow

# Send signals to workflows
aidp temporal signal <workflow_id> pause
aidp temporal signal <workflow_id> resume
aidp temporal signal <workflow_id> inject_instruction "Fix the bug"
aidp temporal signal <workflow_id> escalate_model

# Cancel a workflow
aidp temporal cancel <workflow_id>
```

### Worker Management

```bash
# Run worker in foreground
aidp temporal worker

# Run worker with custom task queue
TEMPORAL_TASK_QUEUE=custom-queue aidp temporal worker
```

## Available Workflows

### IssueToPrWorkflow

Full pipeline from GitHub issue to pull request:

1. **Analyze**: Fetch and analyze the issue
2. **Plan**: Create implementation plan
3. **Implement**: Fix-forward work loop
4. **Test**: Validate changes
5. **Create PR**: Push and create pull request

```bash
aidp temporal start issue 123
```

### WorkLoopWorkflow

Fix-forward iteration pattern:

1. Create initial prompt
2. Run agent iteration
3. Run tests/linters
4. If failing, diagnose and continue
5. Repeat until passing or max iterations

```bash
aidp temporal start workloop my_step
```

### SubIssueWorkflow

Child workflow for decomposed tasks. Supports recursive decomposition when tasks are too complex.

## Signals

Workflows support these signals for external control:

| Signal | Description |
|--------|-------------|
| `pause` | Pause workflow execution |
| `resume` | Resume paused workflow |
| `inject_instruction` | Add instruction for next iteration |
| `escalate_model` | Request model escalation |

## Queries

Query workflow state without affecting execution:

| Query | Description |
|-------|-------------|
| `current_state` | Current workflow state |
| `iteration_count` | Number of iterations completed |
| `progress` | Full progress summary |
| `test_results` | Latest test results (WorkLoopWorkflow) |

## Production Deployment

### Self-Hosted

For production self-hosted deployment:

1. **Use managed database**: RDS, Cloud SQL, or Azure Database
2. **Run multiple server instances**: Behind load balancer
3. **Configure namespaces**: Separate dev/staging/prod
4. **Enable TLS**: Secure all connections
5. **Set up monitoring**: Prometheus metrics + Grafana

Example production docker-compose additions:

```yaml
services:
  temporal:
    environment:
      - DB=postgresql
      - DB_PORT=5432
      - POSTGRES_USER=${DB_USER}
      - POSTGRES_PWD=${DB_PASSWORD}
      - POSTGRES_SEEDS=${DB_HOST}
    deploy:
      replicas: 3
```

### Temporal Cloud

For Temporal Cloud deployment:

1. Create account at [temporal.io](https://temporal.io)
2. Create namespace
3. Generate API key
4. Configure AIDP:

```yaml
temporal:
  target_host: "<namespace>.tmprl.cloud:7233"
  namespace: "<namespace>"
  tls: true
  api_key: "${TEMPORAL_API_KEY}"
```

## Monitoring

### Temporal UI

Access at http://localhost:8080 (local) or cloud dashboard.

Features:
- Workflow list and search
- Execution history
- Pending activities
- Worker status

### Metrics

Temporal exposes Prometheus metrics on port 9090. Key metrics:

- `temporal_workflow_completed_total`
- `temporal_workflow_failed_total`
- `temporal_activity_execution_latency`
- `temporal_worker_task_slots_used`

### Logging

AIDP logs Temporal operations at `debug` level:

```bash
AIDP_LOG_LEVEL=debug aidp temporal worker
```

## Troubleshooting

### Connection Issues

```
Error: failed to connect to temporal server
```

1. Check Temporal server is running: `docker ps`
2. Verify target_host in config
3. Check network connectivity
4. Verify TLS settings match server

### Workflow Not Found

```
Error: workflow not found
```

1. Verify workflow ID
2. Check namespace is correct
3. Workflow may have completed and been archived

### Activity Timeouts

```
Error: activity timeout
```

1. Check activity is making progress (heartbeats)
2. Increase timeout in workflow definition
3. Check worker is running

### Worker Not Picking Up Tasks

1. Verify task queue name matches
2. Check worker is registered for correct workflows/activities
3. Verify namespace is correct
4. Check for resource exhaustion

## Migration from Legacy Orchestration

AIDP's `OrchestrationAdapter` automatically routes to Temporal or legacy based on configuration:

1. **Enable Temporal**: Add `temporal.enabled: true` to aidp.yml
2. **Start worker**: `aidp temporal worker`
3. **New workflows use Temporal**: Existing legacy jobs continue
4. **Gradual migration**: Both systems coexist

## Further Reading

- [Temporal Documentation](https://docs.temporal.io)
- [Temporal Ruby SDK](https://docs.temporal.io/develop/ruby)
- [AIDP Style Guide](../STYLE_GUIDE.md)
- [Work Loops Guide](WORK_LOOPS_GUIDE.md)
