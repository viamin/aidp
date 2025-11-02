#!/bin/bash
# Firewall initialization script for AIDP devcontainer
# Implements strict network access control with allowlisted domains

set -euo pipefail

# If running without NET_ADMIN (capabilities missing), exit gracefully
if ! command -v iptables >/dev/null 2>&1 || ! command -v ipset >/dev/null 2>&1; then
    echo "⚠️  iptables/ipset not available (missing NET_ADMIN capability). Skipping firewall setup." >&2
    exit 0
fi

echo "🔒 Initializing firewall for AIDP development container..."

# Flush existing iptables rules, but preserve Docker's DNS configuration
iptables -F INPUT || true
iptables -F OUTPUT || true
iptables -F FORWARD || true

# Create ipset for allowed IP ranges
ipset create allowed-domains hash:net -exist

# Helper function to validate CIDR
validate_cidr() {
    local cidr=$1
    if [[ $cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 0
    fi
    return 1
}

# Helper function to validate IP
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

# Add IP range to ipset with validation
add_ip_range() {
    local range=$1
    if validate_cidr "$range"; then
        ipset add allowed-domains "$range" -exist
        echo "  ✓ Added IP range: $range"
    else
        echo "  ✗ Invalid CIDR: $range" >&2
    fi
}

# Add individual IP to ipset with validation
add_ip() {
    local ip=$1
    if validate_ip "$ip"; then
        ipset add allowed-domains "$ip/32" -exist
        echo "  ✓ Added IP: $ip"
    else
        echo "  ✗ Invalid IP: $ip" >&2
    fi
}

# Resolve domain and add IPs to ipset
add_domain() {
    local domain=$1
    echo "  Resolving $domain..."
    local ips
       # Allow dig or grep to fail without aborting script
       ips=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' || true)
    if [ -n "$ips" ]; then
        while IFS= read -r ip; do
            add_ip "$ip"
        done <<< "$ips"
    else
        echo "  ⚠️  Could not resolve $domain" >&2
    fi
}

echo "📋 Fetching GitHub IP ranges..."
GITHUB_META_JSON=$(curl -fsS --max-time 5 https://api.github.com/meta || true)
if [ -n "${GITHUB_META_JSON}" ]; then
    # Try jq if present for robust parsing
    if command -v jq >/dev/null 2>&1; then
        mapfile -t GITHUB_IPS < <(echo "$GITHUB_META_JSON" | jq -r '.git[]' 2>/dev/null || true)
    else
        # Fallback grep-based parsing
        GITHUB_IPS=$(echo "$GITHUB_META_JSON" | grep -oP '(?<="git": \[)[^\]]+' | tr -d '"' | tr ',' '\n' | tr -d ' ')
    fi
    if [ -n "${GITHUB_IPS:-}" ]; then
        for range in $GITHUB_IPS; do
            add_ip_range "$range"
        done
    else
        echo "  ⚠️  No GitHub git IP ranges parsed" >&2
    fi
else
    echo "  ⚠️  Failed to fetch GitHub meta API; continuing without GitHub ranges" >&2
fi

echo "📋 Adding Azure IP ranges for GitHub Copilot..."
# These are common Azure regions used by GitHub Copilot
# Using broader /16 ranges to handle dynamic IP allocation across Azure regions
# This is necessary because GitHub Copilot uses many IPs within these ranges
add_ip_range "20.189.0.0/16"      # Azure WestUS2 (broader range)
add_ip_range "104.208.0.0/16"     # Azure EastUS (broader range)
add_ip_range "52.168.0.0/16"      # Azure EastUS2 (broader range - covers .112 and .117)
add_ip_range "40.79.0.0/16"       # Azure WestUS (broader range)
add_ip_range "13.89.0.0/16"       # Azure EastUS (broader range)
add_ip_range "13.69.0.0/16"       # Azure (broader range - covers .239)
add_ip_range "20.42.0.0/16"       # Azure WestEurope (broader range - covers .65 and .73)
add_ip_range "20.50.0.0/16"       # Azure (broader range - covers .80)

echo "🌐 Adding essential service domains..."

# Ruby/Gem repositories
add_domain "rubygems.org"
add_domain "api.rubygems.org"
add_domain "index.rubygems.org"

# AI Provider APIs (Anthropic / OpenAI / Google Gemini)
add_domain "api.anthropic.com"              # Anthropic primary API
add_domain "claude.ai"                      # Anthropic web (auth flows / websocket)
add_domain "console.anthropic.com"          # Anthropic console (token management)

add_domain "api.openai.com"                 # OpenAI primary API
add_domain "auth.openai.com"                # OpenAI OAuth
add_domain "openai.com"                     # OpenAI site (redirects during auth)
add_domain "chat.openai.com"                # Chat UI (session/token refresh)
add_domain "chatgpt.com"                    # Legacy / redirect host
add_domain "cdn.openai.com"                 # Static assets used in auth/UI
add_domain "oaiusercontent.com"             # File / image assets (optional but common)

add_domain "generativelanguage.googleapis.com"  # Google AI (Gemini) API
add_domain "oauth2.googleapis.com"          # Google OAuth token endpoint
add_domain "accounts.google.com"            # Google account login
add_domain "www.googleapis.com"             # Discovery / ancillary APIs

# Package managers and registries
add_domain "registry.npmjs.org"
add_domain "registry.yarnpkg.com"

# GitHub / Copilot related
add_domain "github.com"                     # Main site (auth flows)
add_domain "api.github.com"                 # API (explicit for clarity)
add_domain "raw.githubusercontent.com"      # Raw file fetches
add_domain "objects.githubusercontent.com"  # Asset storage
add_domain "gist.githubusercontent.com"     # Gists (tool usage)
add_domain "cloud.githubusercontent.com"    # Cloud auth/token endpoints
add_domain "copilot-proxy.githubusercontent.com" # Copilot proxy service

# GitHub Copilot backend services (Azure)
add_domain "api.githubcopilot.com"          # Copilot API
add_domain "copilot-telemetry.githubusercontent.com" # Copilot telemetry
add_domain "default.exp-tas.com"            # Experimentation service
add_domain "copilot-completions.githubusercontent.com" # Completions service

# Cursor AI
add_domain "cursor.com"                     # Install script host
add_domain "www.cursor.com"                 # Redirect host
add_domain "downloads.cursor.com"           # Package downloads
add_domain "api.cursor.sh"
add_domain "cursor.sh"
add_domain "app.cursor.sh"
add_domain "www.cursor.sh"

# OpenCode AI
add_domain "api.opencode.ai"
add_domain "auth.opencode.ai"

# General CDNs occasionally used during auth / assets
add_domain "cdn.jsdelivr.net"

# VS Code services
add_domain "update.code.visualstudio.com"
add_domain "marketplace.visualstudio.com"
add_domain "vscode.blob.core.windows.net"
add_domain "vscode.download.prss.microsoft.com"
add_domain "az764295.vo.msecnd.net"
add_domain "gallerycdn.vsassets.io"           # VS Code extension gallery CDN
add_domain "vscode.gallerycdn.vsassets.io"    # VS Code gallery CDN (subdomain)

# Microsoft telemetry (optional, comment out if not desired)
add_domain "dc.services.visualstudio.com"
add_domain "vortex.data.microsoft.com"

# Detect host network for local access
echo "🏠 Detecting host network..."
HOST_NETWORK=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -n1 || true)
if [ -n "$HOST_NETWORK" ]; then
    HOST_CIDR="${HOST_NETWORK}/16"
    echo "  Adding host network: $HOST_CIDR"
    add_ip_range "$HOST_CIDR"
fi

# Allow localhost
add_ip_range "127.0.0.0/8"

echo "🛡️  Configuring iptables rules..."

# Set default policies
iptables -P INPUT DROP || true
iptables -P OUTPUT DROP || true
iptables -P FORWARD DROP || true

# Allow all loopback traffic
iptables -A INPUT -i lo -j ACCEPT || true
iptables -A OUTPUT -o lo -j ACCEPT || true

# Allow established and related connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT || true
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT || true

# Allow DNS queries (port 53)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT || true
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT || true

# Allow SSH (port 22)
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT || true

# Allow HTTPS (port 443) to allowlisted domains
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set allowed-domains dst -j ACCEPT || true

# Allow HTTP (port 80) to allowlisted domains
iptables -A OUTPUT -p tcp --dport 80 -m set --match-set allowed-domains dst -j ACCEPT || true

# Optional: logging for blocked egress (disabled by default to avoid log noise)
# Enable by setting AIDP_FIREWALL_LOG=1 in the container env
if [ "${AIDP_FIREWALL_LOG:-}" = "1" ]; then
    echo "🪵 Enabling logging of blocked outbound connections (rate-limited)" >&2
    # Create a custom chain for logging to prevent duplicate logs
    iptables -N AIDP_BLOCK_LOG 2>/dev/null || true
    # Add a rate-limited LOG target then DROP
    iptables -F AIDP_BLOCK_LOG || true
    iptables -A AIDP_BLOCK_LOG -m limit --limit 10/min --limit-burst 20 -j LOG --log-prefix "AIDP-FW-BLOCK " --log-level 4 || true
    iptables -A AIDP_BLOCK_LOG -j DROP || true
    # Append as final OUTPUT rule for TCP/UDP not yet accepted
    iptables -A OUTPUT -p tcp -j AIDP_BLOCK_LOG || true
    iptables -A OUTPUT -p udp -j AIDP_BLOCK_LOG || true
fi

# Allow all traffic on Docker bridge network (for docker-in-docker)
iptables -A INPUT -i docker0 -j ACCEPT 2>/dev/null || true
iptables -A OUTPUT -o docker0 -j ACCEPT 2>/dev/null || true

# Log dropped packets (optional, for debugging)
# iptables -A OUTPUT -j LOG --log-prefix "DROPPED: " --log-level 4

echo "✅ Firewall initialized successfully!"

# Verify firewall is working
echo "🧪 Verifying firewall configuration..."
if curl -s --max-time 5 https://api.github.com > /dev/null; then
    echo "  ✓ GitHub API accessible"
else
    echo "  ✗ GitHub API blocked" >&2
fi

if curl -s --max-time 5 https://rubygems.org > /dev/null; then
    echo "  ✓ RubyGems accessible"
else
    echo "  ✗ RubyGems blocked" >&2
fi

# Test that blocked domains are actually blocked
if timeout 2 curl -s https://example.com > /dev/null 2>&1; then
    echo "  ⚠️  WARNING: example.com is accessible (firewall may not be working)" >&2
else
    echo "  ✓ Unallowlisted domains blocked (example.com)"
fi

echo "🎉 Firewall setup complete!"
