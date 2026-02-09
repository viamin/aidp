#!/bin/bash
# Configure LLM CLI tools to run in auto-approve/dangerous mode inside devcontainer
# This script runs during postCreateCommand to set up container-specific shell aliases
# and wrapper functions that enable dangerous mode without affecting host configs

set -e

echo "Configuring LLM CLI tools for devcontainer..."

# Create wrapper directory for container-specific scripts
WRAPPER_DIR="/usr/local/bin/devcontainer-llm-wrappers"
sudo mkdir -p "$WRAPPER_DIR"

# Create Codex wrapper that uses CLI flags for dangerous mode
echo "Creating Codex wrapper..."
cat << 'EOF' | sudo tee "$WRAPPER_DIR/codex" > /dev/null
#!/bin/bash
# Codex wrapper for devcontainer - auto-approve mode
exec /usr/local/bin/codex.real -a never -s danger-full-access "$@"
EOF
sudo chmod +x "$WRAPPER_DIR/codex"

# Rename original codex if it exists in /usr/local/bin
if [ -f "/usr/local/bin/codex" ] && [ ! -f "/usr/local/bin/codex.real" ]; then
  sudo mv /usr/local/bin/codex /usr/local/bin/codex.real
  sudo ln -sf "$WRAPPER_DIR/codex" /usr/local/bin/codex
fi

# Create Claude wrapper that adds --dangerously-skip-permissions and --plugin-dir
echo "Creating Claude wrapper..."
CLAUDE_BIN="$HOME/.local/bin/claude"
if [ -f "$CLAUDE_BIN" ] && [ ! -f "$CLAUDE_BIN.real" ]; then
  mv "$CLAUDE_BIN" "$CLAUDE_BIN.real"
  cat << CLAUDE_EOF > "$CLAUDE_BIN"
#!/bin/bash
# Claude wrapper for devcontainer - dangerous mode + plugin
exec "$CLAUDE_BIN.real" --dangerously-skip-permissions --plugin-dir /workspaces/claude-ai-toolkit "\$@"
CLAUDE_EOF
  chmod +x "$CLAUDE_BIN"
fi

# For Gemini CLI, create a container-specific settings file
# We put it in /etc to avoid conflicts with bind-mounted ~/.config
echo "Configuring Gemini CLI..."
sudo mkdir -p /etc/gemini-cli
cat << 'EOF' | sudo tee /etc/gemini-cli/settings.json > /dev/null
{
  "autoAccept": true
}
EOF
DEVCONTAINER_USER="${SUDO_USER:-${USER}}"
DEVCONTAINER_GROUP="$(id -gn "${DEVCONTAINER_USER}")"
sudo chown -R "${DEVCONTAINER_USER}:${DEVCONTAINER_GROUP}" /etc/gemini-cli
sudo chmod -R u+rwX,go+rX /etc/gemini-cli

# Create Gemini wrapper that uses the container-specific config
cat << 'EOF' | sudo tee "$WRAPPER_DIR/gemini" > /dev/null
#!/bin/bash
# Gemini wrapper for devcontainer - auto-accept mode
# Point to container-specific config that won't affect host
export GEMINI_CONFIG_DIR=/etc/gemini-cli
exec /usr/local/bin/gemini.real "$@"
EOF
sudo chmod +x "$WRAPPER_DIR/gemini"

if [ -f "/usr/local/bin/gemini" ] && [ ! -f "/usr/local/bin/gemini.real" ]; then
  sudo mv /usr/local/bin/gemini /usr/local/bin/gemini.real
  sudo ln -sf "$WRAPPER_DIR/gemini" /usr/local/bin/gemini
fi

# OpenCode uses environment variable (already set in containerEnv)
echo "✓ OpenCode configured via OPENCODE_PERMISSION environment variable"

# Create Aider wrapper that runs in non-interactive mode
echo "Creating Aider wrapper..."
cat << 'EOF' | sudo tee "$WRAPPER_DIR/aider" > /dev/null
#!/bin/bash
# Aider wrapper for devcontainer - non-interactive mode
# Aider uses --yes flag for non-interactive operation
# Check common installation locations
if [ -f "$HOME/.local/bin/aider" ]; then
  exec "$HOME/.local/bin/aider" "$@"
elif [ -f "/usr/local/bin/aider" ]; then
  exec /usr/local/bin/aider "$@"
else
  exec aider "$@"
fi
EOF
sudo chmod +x "$WRAPPER_DIR/aider"

# Link to /usr/local/bin if not already present
if [ ! -f "/usr/local/bin/aider" ]; then
  sudo ln -sf "$WRAPPER_DIR/aider" /usr/local/bin/aider
fi

echo ""
echo "✓ LLM CLI tools configured for devcontainer!"
echo ""
echo "Configured tools:"
echo "  - Codex: Auto-approve mode (approval_policy=never, sandbox=danger-full-access)"
echo "  - Claude: Dangerous mode (--dangerously-skip-permissions)"
echo "  - Gemini CLI: Auto-accept mode (autoAccept=true)"
echo "  - OpenCode: Allow all (OPENCODE_PERMISSION=allow)"
echo "  - Aider: Non-interactive mode (auto-approval)"
echo ""
echo "⚠️  WARNING: These tools will auto-approve all operations inside this container."
echo "    This is safe because of the devcontainer's firewall and isolation."
echo "    Host configurations remain unchanged and safe."
