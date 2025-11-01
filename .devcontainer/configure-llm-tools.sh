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

# Create Claude wrapper that adds --dangerously-skip-permissions
echo "Creating Claude wrapper..."
cat << 'EOF' | sudo tee "$WRAPPER_DIR/claude" > /dev/null
#!/bin/bash
# Claude wrapper for devcontainer - dangerous mode
exec /usr/local/bin/claude.real --dangerously-skip-permissions "$@"
EOF
sudo chmod +x "$WRAPPER_DIR/claude"

# Rename original claude if it exists
if [ -f "/usr/local/bin/claude" ] && [ ! -f "/usr/local/bin/claude.real" ]; then
  sudo mv /usr/local/bin/claude /usr/local/bin/claude.real
  sudo ln -sf "$WRAPPER_DIR/claude" /usr/local/bin/claude
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

echo ""
echo "✓ LLM CLI tools configured for devcontainer!"
echo ""
echo "Configured tools:"
echo "  - Codex: Auto-approve mode (approval_policy=never, sandbox=danger-full-access)"
echo "  - Claude: Dangerous mode (--dangerously-skip-permissions)"
echo "  - Gemini CLI: Auto-accept mode (autoAccept=true)"
echo "  - OpenCode: Allow all (OPENCODE_PERMISSION=allow)"
echo ""
echo "⚠️  WARNING: These tools will auto-approve all operations inside this container."
echo "    This is safe because of the devcontainer's firewall and isolation."
echo "    Host configurations remain unchanged and safe."
