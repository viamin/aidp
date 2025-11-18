#!/bin/bash
# Firewall initialization script for AIDP devcontainer
# Implements strict network access control with allowlisted domains
# Configuration is read from .aidp/firewall-allowlist.yml

set -euo pipefail

# Path to firewall configuration YAML
FIREWALL_CONFIG="${FIREWALL_CONFIG:-/workspaces/aidp/.aidp/firewall-allowlist.yml}"

# If running without NET_ADMIN (capabilities missing), exit gracefully
if ! command -v iptables >/dev/null 2>&1 || ! command -v ipset >/dev/null 2>&1; then
    echo "⚠️  iptables/ipset not available (missing NET_ADMIN capability). Skipping firewall setup." >&2
    exit 0
fi

echo "🔒 Initializing firewall for AIDP development container..."

# Check if yq is available for YAML parsing (required)
if ! command -v yq >/dev/null 2>&1; then
    echo "❌ ERROR: yq not available. YAML parsing is required for firewall configuration." >&2
    echo "   Install yq or rebuild the devcontainer to include yq." >&2
    exit 1
fi

# Check if YAML config exists, generate if missing
if [ ! -f "$FIREWALL_CONFIG" ]; then
    echo "⚠️  Firewall config not found at $FIREWALL_CONFIG" >&2
    echo "   Generating configuration from provider requirements..." >&2

    # Try to generate the config using the Ruby utility
    if command -v bundle >/dev/null 2>&1 && [ -f "/workspaces/aidp/bin/update-firewall-config" ]; then
        cd /workspaces/aidp && bundle exec ruby bin/update-firewall-config
        if [ $? -ne 0 ]; then
            echo "❌ ERROR: Failed to generate firewall configuration" >&2
            exit 1
        fi
        echo "✅ Firewall configuration generated successfully" >&2
    else
        echo "❌ ERROR: Cannot generate firewall config - bundle or update-firewall-config not available" >&2
        echo "   Run 'bundle exec ruby bin/update-firewall-config' manually to generate the configuration" >&2
        exit 1
    fi
fi

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
       # Use +time=1 +tries=2 to limit timeout to 2s per domain (instead of default 15s)
       ips=$(dig +short +time=1 +tries=2 "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' || true)
    if [ -n "$ips" ]; then
        while IFS= read -r ip; do
            add_ip "$ip"
        done <<< "$ips"
    else
        echo "  ⚠️  Could not resolve $domain" >&2
    fi
}

# Read and parse YAML configuration
echo "📄 Reading firewall configuration from $FIREWALL_CONFIG..."

# Add static IP ranges
echo "📋 Adding static IP ranges..."
mapfile -t STATIC_IPS < <(yq eval '.static_ip_ranges[].cidr' "$FIREWALL_CONFIG" 2>/dev/null || true)
for range in "${STATIC_IPS[@]}"; do
    [ -n "$range" ] && [ "$range" != "null" ] && add_ip_range "$range"
done

# Add Azure IP ranges
echo "📋 Adding Azure IP ranges..."
mapfile -t AZURE_IPS < <(yq eval '.azure_ip_ranges[].cidr' "$FIREWALL_CONFIG" 2>/dev/null || true)
for range in "${AZURE_IPS[@]}"; do
    [ -n "$range" ] && [ "$range" != "null" ] && add_ip_range "$range"
done

# Add core domains
echo "🌐 Adding core infrastructure domains..."

# Ruby domains
mapfile -t RUBY_DOMAINS < <(yq eval '.core_domains.ruby[]' "$FIREWALL_CONFIG" 2>/dev/null || true)
for domain in "${RUBY_DOMAINS[@]}"; do
    [ -n "$domain" ] && [ "$domain" != "null" ] && add_domain "$domain"
done

# JavaScript domains
mapfile -t JS_DOMAINS < <(yq eval '.core_domains.javascript[]' "$FIREWALL_CONFIG" 2>/dev/null || true)
for domain in "${JS_DOMAINS[@]}"; do
    [ -n "$domain" ] && [ "$domain" != "null" ] && add_domain "$domain"
done

# GitHub domains
mapfile -t GITHUB_DOMAINS < <(yq eval '.core_domains.github[]' "$FIREWALL_CONFIG" 2>/dev/null || true)
for domain in "${GITHUB_DOMAINS[@]}"; do
    [ -n "$domain" ] && [ "$domain" != "null" ] && add_domain "$domain"
done

# CDN domains
mapfile -t CDN_DOMAINS < <(yq eval '.core_domains.cdn[]' "$FIREWALL_CONFIG" 2>/dev/null || true)
for domain in "${CDN_DOMAINS[@]}"; do
    [ -n "$domain" ] && [ "$domain" != "null" ] && add_domain "$domain"
done

# VS Code domains
mapfile -t VSCODE_DOMAINS < <(yq eval '.core_domains.vscode[]' "$FIREWALL_CONFIG" 2>/dev/null || true)
for domain in "${VSCODE_DOMAINS[@]}"; do
    [ -n "$domain" ] && [ "$domain" != "null" ] && add_domain "$domain"
done

# Telemetry domains (optional)
mapfile -t TELEMETRY_DOMAINS < <(yq eval '.core_domains.telemetry[]' "$FIREWALL_CONFIG" 2>/dev/null || true)
for domain in "${TELEMETRY_DOMAINS[@]}"; do
    [ -n "$domain" ] && [ "$domain" != "null" ] && add_domain "$domain"
done

# Add provider-specific domains
echo "🤖 Adding AI provider domains..."

# Get all provider names
mapfile -t PROVIDERS < <(yq eval '.provider_domains | keys | .[]' "$FIREWALL_CONFIG" 2>/dev/null || true)

for provider in "${PROVIDERS[@]}"; do
    [ -n "$provider" ] && [ "$provider" != "null" ] || continue
    echo "  Adding domains for $provider..."
    mapfile -t PROVIDER_DOMAINS < <(yq eval ".provider_domains.$provider[]" "$FIREWALL_CONFIG" 2>/dev/null || true)
    for domain in "${PROVIDER_DOMAINS[@]}"; do
        [ -n "$domain" ] && [ "$domain" != "null" ] && add_domain "$domain"
    done
done

# Always fetch GitHub IP ranges dynamically
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

# Detect host network for local access
echo "🏠 Detecting host network..."
HOST_NETWORK=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -n1 || true)
if [ -n "$HOST_NETWORK" ]; then
    HOST_CIDR="${HOST_NETWORK}/16"
    echo "  Adding host network: $HOST_CIDR"
    add_ip_range "$HOST_CIDR"
fi

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
