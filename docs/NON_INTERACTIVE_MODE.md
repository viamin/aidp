# Non-Interactive Background Mode

## Overview

AIDP's **Non-Interactive Background Mode** allows the system to run fully autonomously as a persistent background daemon process. This mode is designed for long-running work loops and fully automated "listen" operations with minimal user supervision.

When running in non-interactive mode, AIDP operates independently of the terminal session and communicates with users primarily via GitHub issue labels and comments.

This feature implements [GitHub Issue #104](https://github.com/viamin/aidp/issues/104).

## Core Concepts

### Modes of Operation

AIDP can operate in three distinct modes:

| Mode | Description | Terminal Required | User Interaction |
|------|-------------|-------------------|------------------|
| **Interactive** | Full REPL with real-time control | Yes | High - via REPL commands |
| **Background** | Autonomous daemon process | No | Minimal - via GitHub |
| **Attached** | REPL attached to background daemon | Yes | High - with daemon visibility |

### Mode Transitions

```
┌─────────────┐
│ Interactive │────────┐
│    REPL     │        │ /background
└─────────────┘        │
      ↑                ↓
      │            ┌────────────┐
      │ attach     │ Background │
      │            │   Daemon   │
      │            └────────────┘
      │                ↑
      └────────────────┘
       aidp attach
```

## Starting Background Mode

### From CLI

Start AIDP in background mode directly:

```bash
# Start in watch mode (monitors GitHub issues)
aidp listen --background

# Start specific work loop in background
aidp execute 16_IMPLEMENTATION --background

# Specify poll interval for watch mode
aidp listen --background --interval 120
```

### From Interactive REPL

Detach from an active REPL session:

```bash
# In REPL
aidp[10]> /background
Detaching REPL and entering background daemon mode...
Daemon started (PID: 12345)
Log file: .aidp/logs/current.log

# Terminal returns to shell, AIDP continues in background
$
```

### Verification

Check if daemon is running:

```bash
$ aidp status
Daemon Status: RUNNING
PID: 12345
Mode: watch
Socket: .aidp/daemon/aidp.sock
Log: .aidp/logs/current.log
```

## Autonomous Background Execution

### What Runs Autonomously

When in background mode, AIDP:

1. **Work Loops** - Continue iterating without user prompts
2. **Watch Mode** - Monitor GitHub for label/comment triggers
3. **Test/Lint Cycles** - Run automatically after each iteration
4. **Checkpoints** - Save progress periodically
5. **GitHub Integration** - Post comments, create PRs automatically

### No Blocking Operations

Background mode ensures:

- ✅ No terminal prompts block execution
- ✅ No user confirmation required
- ✅ All decisions made autonomously
- ✅ External triggers via GitHub only

### GitHub as Primary Interface

While in background mode, interact via GitHub:

```
Issue #123: Add user authentication

User adds label: aidp-plan
  ↓
Daemon detects label
  ↓
Daemon generates plan
  ↓
Daemon posts plan as comment

User adds label: aidp-build
  ↓
Daemon starts implementation
  ↓
Daemon creates PR when complete
```

## Reattaching to Daemon

### Using aidp attach

Restore interactive REPL while daemon continues:

```bash
$ aidp attach
🔗 Attaching to daemon (PID: 12345)

📊 Recent Activity Summary (last hour):
  Total events: 142
  By type:
    work_loop_iteration: 85
    watch_mode: 12
    daemon_lifecycle: 3
  By level:
    INFO: 135
    WARN: 5
    ERROR: 2

📝 Last 10 events:
  [2025-10-12T23:15:30] INFO work_loop_iteration - Iteration 15 for 16_IMPLEMENTATION: tests_passed
  [2025-10-12T23:15:45] INFO work_loop_iteration - Iteration 16 for 16_IMPLEMENTATION: running
  [2025-10-12T23:16:00] INFO checkpoint - Checkpoint saved at iteration 16
  ...

✅ REPL attached - daemon continues in background

aidp[16]>
```

### What Happens on Attach

1. **Daemon Continues** - Work loops/watch mode keep running
2. **Activity Replay** - Shows summary of recent activity
3. **REPL Restored** - Full interactive control available
4. **Live Monitoring** - See real-time output from daemon

### Detaching Again

From attached REPL, detach back to background:

```bash
aidp[20]> /background
Detaching REPL...
Daemon continues in background (PID: 12345)

$
```

## Logging and Monitoring

### Structured Logging

All daemon activity is logged to `.aidp/logs/current.log`:

```
[2025-10-12T23:00:00] INFO daemon_lifecycle - Daemon started | mode=watch pid=12345
[2025-10-12T23:00:15] INFO watch_mode - Watch cycle completed | issues_checked=5
[2025-10-12T23:00:30] INFO work_loop_iteration - Iteration 1 for 16_IMPLEMENTATION: running | step=16_IMPLEMENTATION iteration=1 status=running
[2025-10-12T23:00:45] INFO work_loop_iteration - Iteration 1 for 16_IMPLEMENTATION: tests_passed | step=16_IMPLEMENTATION iteration=1 status=tests_passed
```

### Log Format

Each log entry contains:

- **Timestamp** - ISO 8601 format
- **Level** - INFO, WARN, ERROR, DEBUG
- **Event Type** - Categorizes the event
- **Message** - Human-readable description
- **Metadata** - Key-value pairs with context

### Real-Time Monitoring

Tail logs to watch daemon activity:

```bash
$ tail -f .aidp/logs/current.log

# Filter for specific events
$ tail -f .aidp/logs/current.log | grep work_loop_iteration

# Filter by level
$ tail -f .aidp/logs/current.log | grep ERROR
```

### Log Rotation

Logs automatically rotate:

- **Max size**: 10MB per file
- **Max files**: 5 files kept
- **Rotation**: Automatic when size limit reached

### Event Types

| Event Type | Description |
|------------|-------------|
| `daemon_lifecycle` | Daemon start/stop events |
| `work_loop_iteration` | Work loop progress |
| `watch_mode` | Watch mode polling cycles |
| `checkpoint` | Checkpoint save events |
| `ipc_error` | IPC communication errors |
| `daemon_error` | Fatal daemon errors |

## Safety and Shutdown

### Graceful Shutdown

Stop daemon safely:

```bash
$ aidp stop
Sending SIGTERM to daemon (PID: 12345)...
Daemon stopped gracefully
Checkpoint saved at iteration 25
```

### What Happens on Shutdown

1. **SIGTERM Signal** - Sent to daemon process
2. **Work Loop Pause** - Current iteration completes
3. **Checkpoint Save** - Progress preserved
4. **Cleanup** - PID file, socket removed
5. **Exit** - Daemon terminates cleanly

### Force Stop (Not Recommended)

If daemon doesn't respond:

```bash
$ aidp stop --force
Force killing daemon (PID: 12345)...
⚠️  Checkpoint may not be saved
```

### Orphan Prevention

AIDP ensures no orphaned processes:

- ✅ All threads joined on shutdown
- ✅ Work loops cancelled gracefully
- ✅ Resources cleaned up properly
- ✅ PID file removed

### Safe Stop from REPL

The recommended way to stop:

```bash
# Attach first
$ aidp attach
aidp[10]>

# Then cancel or stop
aidp[10]> /cancel
Work loop cancelled at iteration 10
Checkpoint saved

aidp[10]> /stop
Daemon stopping gracefully...
```

## Integration with Watch Mode

### Fully Automatic Workflow

Background mode + watch mode = fully autonomous:

```bash
# Start watching GitHub in background
$ aidp listen --background
Daemon started in watch mode (PID: 12345)
Monitoring: https://github.com/owner/repo/issues
Interval: 60s
Log: .aidp/logs/current.log

# Daemon now autonomously:
# 1. Polls GitHub for label changes
# 2. Generates plans when aidp-plan added
# 3. Implements when aidp-build added
# 4. Creates PRs when complete
# 5. Posts status comments
```

### Autonomous Cycle

```
┌─────────────────────────────────────────┐
│           Background Daemon              │
│                                          │
│  ┌────────────────────────────────┐     │
│  │  Watch Mode Loop               │     │
│  │                                │     │
│  │  1. Poll GitHub (60s interval) │     │
│  │  2. Detect label changes       │     │
│  │  3. Trigger appropriate action │     │
│  │  4. Log all activity           │     │
│  │  5. Repeat                     │     │
│  └────────────────────────────────┘     │
│           ↓                              │
│  ┌────────────────────────────────┐     │
│  │  Work Loop (if triggered)      │     │
│  │                                │     │
│  │  1. Execute iteration          │     │
│  │  2. Run tests/linters          │     │
│  │  3. Save checkpoint            │     │
│  │  4. Continue until done        │     │
│  └────────────────────────────────┘     │
└─────────────────────────────────────────┘
```

### GitHub as Control Interface

While daemon runs in background:

| GitHub Action | Daemon Response |
|---------------|-----------------|
| Add `aidp-plan` label | Generate and post plan |
| Add `aidp-build` label | Start implementation |
| Comment with questions | Incorporate into plan |
| Remove `aidp-build` label | Cancel work loop |

See [FULLY_AUTOMATIC_MODE.md](FULLY_AUTOMATIC_MODE.md) for complete watch mode details.

## Configuration

### Enable Background Mode

In `.aidp.yml`:

```yaml
daemon:
  enabled: true
  log_dir: ".aidp/logs"
  max_log_size: 10485760  # 10MB
  max_log_files: 5
  socket_path: ".aidp/daemon/aidp.sock"

watch:
  background_mode: true
  interval: 60  # seconds
  auto_start: false
```

### Command-Line Options

```bash
# Background mode options
aidp listen --background           # Start in background
aidp listen --background --interval 120  # Custom interval
aidp listen --background --once    # Single cycle then exit

# Daemon control
aidp status                        # Check daemon status
aidp attach                        # Attach to running daemon
aidp stop                          # Stop daemon gracefully
aidp stop --force                  # Force stop (not recommended)
```

## File Structure

### Daemon Files

```
.aidp/
├── daemon/
│   ├── aidp.pid          # Process ID file
│   ├── aidp.sock         # IPC Unix socket
│   └── daemon.log        # Daemon-specific log
├── logs/
│   ├── current.log       # Main structured log
│   ├── current.log.1     # Rotated log (older)
│   ├── current.log.2     # Rotated log (older)
│   └── ...
└── checkpoints/
    └── ...               # Work loop checkpoints
```

### PID File

Contains single line with process ID:

```
12345
```

### Socket File

Unix domain socket for IPC:

- Commands: `status`, `stop`, `attach`
- JSON-formatted responses
- Automatic cleanup on shutdown

## Use Cases

### 1. Long-Running Implementation

```bash
# Start complex implementation in background
$ aidp execute 16_IMPLEMENTATION --background
Daemon started (PID: 12345)

# Go home, implementation continues overnight

# Next day, check status
$ aidp attach
📊 Work loop completed! 47 iterations, all tests passing
```

### 2. Continuous GitHub Monitoring

```bash
# Start watch mode in background on server
$ aidp listen --background
Daemon started in watch mode

# Daemon runs 24/7 monitoring GitHub
# Automatically implements when labels added
# Creates PRs without human intervention
```

### 3. Detach During Long Wait

```bash
# Work loop waiting for slow tests
aidp[5]> /background
Detaching... daemon continues

# Come back later
$ aidp attach
aidp[12]> # Tests finished, work progressed
```

### 4. CI/CD Integration

```bash
# In CI pipeline
$ aidp listen --background --once
# Runs single watch cycle
# Processes any pending GitHub triggers
# Exits when complete
```

## IPC Communication

### Unix Socket Protocol

AIDP uses Unix domain sockets for inter-process communication:

**Client → Daemon:**

```
status\n
```

**Daemon → Client:**

```json
{
  "status": "running",
  "pid": 12345,
  "mode": "watch",
  "uptime": 3600
}
```

### Supported Commands

| Command | Response | Description |
|---------|----------|-------------|
| `status` | JSON status | Get daemon status |
| `stop` | `{"status": "stopping"}` | Stop daemon |
| `attach` | Activity summary | Prepare for attach |

### Client Implementation

```ruby
require "socket"

socket = UNIXSocket.new(".aidp/daemon/aidp.sock")
socket.puts("status")
response = JSON.parse(socket.gets)
socket.close

puts "Daemon PID: #{response['pid']}"
```

## Troubleshooting

### Daemon Won't Start

**Symptoms**: `aidp listen --background` fails

**Causes**:

- Daemon already running
- Permission issues
- Invalid configuration

**Solutions**:

```bash
# Check if already running
$ aidp status

# Stop existing daemon
$ aidp stop

# Check permissions
$ ls -la .aidp/daemon/

# Validate config
$ aidp config validate
```

### Can't Attach

**Symptoms**: `aidp attach` fails

**Causes**:

- No daemon running
- Socket file missing
- Permission denied

**Solutions**:

```bash
# Verify daemon is running
$ aidp status

# Check socket exists
$ ls -la .aidp/daemon/aidp.sock

# Check socket permissions
$ stat .aidp/daemon/aidp.sock
```

### Daemon Stops Unexpectedly

**Symptoms**: Daemon exits on its own

**Causes**:

- Fatal error
- Out of memory
- Provider failure

**Solutions**:

```bash
# Check logs for errors
$ tail -100 .aidp/logs/current.log | grep ERROR

# Check system resources
$ top -p $(cat .aidp/daemon/aidp.pid)

# Review daemon log
$ cat .aidp/daemon/daemon.log
```

### Orphaned Processes

**Symptoms**: Daemon process remains after stop

**Solutions**:

```bash
# Find daemon process
$ ps aux | grep aidp

# Force kill if needed
$ kill -9 $(cat .aidp/daemon/aidp.pid)

# Clean up stale files
$ rm .aidp/daemon/aidp.pid
$ rm .aidp/daemon/aidp.sock
```

### Logs Not Updating

**Symptoms**: Log file not being written

**Causes**:

- Log directory permissions
- Disk full
- Log rotation issue

**Solutions**:

```bash
# Check disk space
$ df -h .

# Check log directory
$ ls -la .aidp/logs/

# Check log file permissions
$ chmod 644 .aidp/logs/current.log
```

## Best Practices

### 1. Always Use Attach for Control

```bash
# ✅ Good - safe control
$ aidp attach
aidp[10]> /cancel

# ❌ Bad - may lose state
$ kill $(cat .aidp/daemon/aidp.pid)
```

### 2. Monitor Logs Regularly

```bash
# Set up log monitoring
$ tail -f .aidp/logs/current.log | grep -E "ERROR|WARN"

# Or use log aggregation
$ aidp logs --follow --level error
```

### 3. Use Checkpoints

Background mode creates checkpoints automatically, but you can force:

```bash
$ aidp attach
aidp[15]> /checkpoint save "Before risky change"
aidp[15]> /background
```

### 4. Set Resource Limits

In `.aidp.yml`:

```yaml
daemon:
  max_iterations: 100
  timeout: 7200  # 2 hours
  memory_limit: "2GB"
```

### 5. Configure Alerts

Set up notifications for errors:

```bash
# Email on error
$ tail -f .aidp/logs/current.log | \
  grep ERROR | \
  mail -s "AIDP Error" admin@example.com
```

## Security Considerations

### File Permissions

Daemon files should be restricted:

```bash
# Recommended permissions
$ chmod 700 .aidp/daemon
$ chmod 600 .aidp/daemon/aidp.pid
$ chmod 600 .aidp/daemon/aidp.sock
$ chmod 600 .aidp/logs/current.log
```

### Socket Security

- Socket in project directory (not /tmp)
- Only project user can access
- Automatic cleanup on exit

### Process Isolation

- Daemon runs as current user
- No privilege escalation
- Respects system resource limits

## API Reference

### ProcessManager

```ruby
manager = Aidp::Daemon::ProcessManager.new(project_dir)

# Check status
manager.running?  # => true/false
manager.pid       # => 12345
manager.status    # => {running: true, pid: 12345, ...}

# Control
manager.stop(timeout: 30)
manager.write_pid(pid)
manager.remove_pid
```

### DaemonLogger

```ruby
logger = Aidp::Daemon::DaemonLogger.new(project_dir)

# Log events
logger.info("work_loop_iteration", "Iteration 5 complete", iteration: 5)
logger.error("daemon_error", "Provider failed", error: e.message)

# Get activity
logger.recent_entries(count: 50)
logger.activity_summary(since: 1.hour.ago)
```

### Runner

```ruby
runner = Aidp::Daemon::Runner.new(project_dir, config, options)

# Start daemon
result = runner.start_daemon(mode: :watch)

# Attach
result = runner.attach
```

## Related Documentation

- [FULLY_AUTOMATIC_MODE.md](FULLY_AUTOMATIC_MODE.md) - Watch mode integration
- [INTERACTIVE_REPL.md](INTERACTIVE_REPL.md) - Interactive REPL features
- [WORK_LOOPS_GUIDE.md](WORK_LOOPS_GUIDE.md) - Work loop fundamentals

## Summary

Non-Interactive Background Mode enables AIDP to run as an autonomous daemon:

- **Daemon Process** - Runs independently of terminal
- **Detach/Attach** - Seamlessly switch between modes
- **Structured Logging** - Complete activity trail
- **Graceful Shutdown** - Safe stop with checkpoints
- **GitHub Integration** - Control via labels/comments
- **IPC Communication** - Socket-based control

Perfect for:

- Long-running implementations
- Continuous GitHub monitoring
- Unattended automation
- CI/CD integration

The daemon architecture ensures AIDP can operate 24/7 with minimal supervision while maintaining full observability and control when needed.
