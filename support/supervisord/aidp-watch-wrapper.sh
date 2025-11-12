#!/bin/bash
set -euo pipefail

# Aidp Watch Mode Supervisor Wrapper
# This script wraps `aidp watch` to handle auto-update requests (exit code 75)

PROJECT_DIR="${PROJECT_DIR:-/workspace/project}"
AIDP_LOG="${PROJECT_DIR}/.aidp/logs/wrapper.log"

# Ensure log directory exists
mkdir -p "$(dirname "$AIDP_LOG")"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >> "$AIDP_LOG"
}

# Change to project directory
if ! cd "$PROJECT_DIR"; then
  log "ERROR: Failed to change to project directory: $PROJECT_DIR"
  exit 1
fi

log "Starting aidp watch in $PROJECT_DIR"

# Run aidp watch
if command -v mise &> /dev/null; then
  # Use mise if available (recommended)
  mise exec -- bundle exec aidp watch
else
  # Fallback to direct bundle exec
  bundle exec aidp watch
fi

EXIT_CODE=$?
log "Aidp exited with code $EXIT_CODE"

# Exit code 75 = update requested by auto-update system
if [ $EXIT_CODE -eq 75 ]; then
  log "Update requested, running bundle update aidp"

  # Update aidp gem
  if command -v mise &> /dev/null; then
    if mise exec -- bundle update aidp >> "$AIDP_LOG" 2>&1; then
      NEW_VERSION=$(bundle exec aidp version 2>/dev/null || echo "unknown")
      log "Aidp updated successfully to version $NEW_VERSION"
      # Supervisor will restart us automatically with exit code 0
      exit 0
    else
      log "ERROR: Bundle update failed"
      exit 1
    fi
  else
    if bundle update aidp >> "$AIDP_LOG" 2>&1; then
      NEW_VERSION=$(bundle exec aidp version 2>/dev/null || echo "unknown")
      log "Aidp updated successfully to version $NEW_VERSION"
      # Supervisor will restart us automatically with exit code 0
      exit 0
    else
      log "ERROR: Bundle update failed"
      exit 1
    fi
  fi
fi

# Pass through other exit codes to supervisor
exit $EXIT_CODE
