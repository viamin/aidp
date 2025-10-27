#!/bin/bash
# Firewall initialization script for AIDP devcontainer
# Implements strict network access control with allowlisted domains

set -euo pipefail

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
    ips=$(dig +short "$domain" A | grep -E '^[0-9]+\.')
    if [ -n "$ips" ]; then
        while IFS= read -r ip; do
            add_ip "$ip"
        done <<< "$ips"
    else
        echo "  ⚠️  Could not resolve $domain" >&2
    fi
}

echo "📋 Fetching GitHub IP ranges..."
# Add GitHub's IP ranges from their API
GITHUB_IPS=$(curl -s https://api.github.com/meta | grep -oP '(?<="git": \[)[^\]]+' | tr -d '"' | tr ',' '\n' | tr -d ' ')
for range in $GITHUB_IPS; do
    add_ip_range "$range"
done

echo "🌐 Adding essential service domains..."

# Ruby/Gem repositories
add_domain "rubygems.org"
add_domain "api.rubygems.org"
add_domain "index.rubygems.org"

# AI Provider APIs
add_domain "api.anthropic.com"
add_domain "api.openai.com"
add_domain "generativelanguage.googleapis.com"  # Google AI

# Package managers and registries
add_domain "registry.npmjs.org"
add_domain "registry.yarnpkg.com"

# Monitoring and error tracking
add_domain "sentry.io"
add_domain "o4504617924640768.ingest.us.sentry.io"

# VS Code services
add_domain "update.code.visualstudio.com"
add_domain "marketplace.visualstudio.com"
add_domain "vscode.blob.core.windows.net"
add_domain "vscode.download.prss.microsoft.com"
add_domain "az764295.vo.msecnd.net"

# Microsoft telemetry (optional, comment out if not desired)
add_domain "dc.services.visualstudio.com"
add_domain "vortex.data.microsoft.com"

# Detect host network for local access
echo "🏠 Detecting host network..."
HOST_NETWORK=$(ip route | grep default | awk '{print $3}' | head -n1)
if [ -n "$HOST_NETWORK" ]; then
    HOST_CIDR="${HOST_NETWORK}/16"
    echo "  Adding host network: $HOST_CIDR"
    add_ip_range "$HOST_CIDR"
fi

# Allow localhost
add_ip_range "127.0.0.0/8"

echo "🛡️  Configuring iptables rules..."

# Set default policies
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Allow all loopback traffic
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established and related connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS queries (port 53)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow SSH (port 22)
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# Allow HTTPS (port 443) to allowlisted domains
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set allowed-domains dst -j ACCEPT

# Allow HTTP (port 80) to allowlisted domains
iptables -A OUTPUT -p tcp --dport 80 -m set --match-set allowed-domains dst -j ACCEPT

# Allow all traffic on Docker bridge network (for docker-in-docker)
iptables -A INPUT -i docker0 -j ACCEPT || true
iptables -A OUTPUT -o docker0 -j ACCEPT || true

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
