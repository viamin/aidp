#!/bin/bash
# Debug script to identify what the firewall is blocking
# Run this, then try to install the VSCode extension, then check the output

echo "🔍 Firewall Debug Tool"
echo "===================="
echo ""

# Check if iptables logging is enabled
if sudo iptables -L AIDP_BLOCK_LOG -n &>/dev/null; then
    echo "✓ Logging chain exists"
else
    echo "⚠️  Logging chain doesn't exist. Creating it now..."

    # Create logging chain
    sudo iptables -N AIDP_BLOCK_LOG 2>/dev/null || true
    sudo iptables -F AIDP_BLOCK_LOG || true
    sudo iptables -A AIDP_BLOCK_LOG -m limit --limit 10/min --limit-burst 20 -j LOG --log-prefix "AIDP-FW-BLOCK " --log-level 4 || true
    sudo iptables -A AIDP_BLOCK_LOG -j DROP || true

    # Remove any existing DROP rules for TCP/UDP at the end of OUTPUT
    sudo iptables -D OUTPUT -p tcp -j AIDP_BLOCK_LOG 2>/dev/null || true
    sudo iptables -D OUTPUT -p udp -j AIDP_BLOCK_LOG 2>/dev/null || true

    # Add logging for blocked TCP/UDP
    sudo iptables -A OUTPUT -p tcp -j AIDP_BLOCK_LOG || true
    sudo iptables -A OUTPUT -p udp -j AIDP_BLOCK_LOG || true

    echo "✓ Logging chain created"
fi

echo ""
echo "📊 Current firewall statistics:"
sudo iptables -L OUTPUT -v -n --line-numbers | head -15

echo ""
echo "🌐 Allowed domains/IPs (first 20):"
sudo ipset list allowed-domains | grep -A 20 "Members:" | tail -20

echo ""
echo "📝 To monitor blocked connections in real-time, run:"
echo "   sudo tail -f /var/log/kern.log | grep AIDP-FW-BLOCK"
echo ""
echo "Or check recent blocks with:"
echo "   sudo grep AIDP-FW-BLOCK /var/log/kern.log | tail -20"
echo ""
echo "🔎 Extract unique blocked IPs from logs:"
echo "   sudo grep AIDP-FW-BLOCK /var/log/kern.log | grep -oP 'DST=\\K[0-9.]+' | sort -u"
echo ""
echo "🧪 Test a specific domain:"
echo "   ./debug-firewall.sh test <domain>"
echo ""

# Show recently blocked IPs if logging is enabled
if [ -f /var/log/kern.log ]; then
    BLOCKED_IPS=$(sudo grep AIDP-FW-BLOCK /var/log/kern.log 2>/dev/null | grep -oP 'DST=\K[0-9.]+' | sort -u | tail -10)
    if [ -n "$BLOCKED_IPS" ]; then
        echo "🚫 Recently blocked IPs (last 10 unique):"
        echo "$BLOCKED_IPS" | while read -r ip; do
            # Check if it's in the allowed set
            if sudo ipset test allowed-domains "$ip" 2>&1 | grep -q "is in set"; then
                echo "   $ip (now allowed - may need container restart)"
            else
                echo "   $ip (BLOCKED)"
            fi
        done
        echo ""
    fi
fi

# If first argument is "test" and second is a domain
if [ "$1" = "test" ] && [ -n "$2" ]; then
    DOMAIN=$2
    echo "Testing connection to $DOMAIN..."
    echo ""

    # Resolve domain
    echo "1. DNS Resolution:"
    IPS=$(dig +short "$DOMAIN" A 2>/dev/null | grep -E '^[0-9]+\.')
    if [ -n "$IPS" ]; then
        echo "$IPS"

        echo ""
        echo "2. Checking if IPs are in allowed set:"
        while IFS= read -r ip; do
            if sudo ipset test allowed-domains "$ip" 2>&1 | grep -q "is in set"; then
                echo "   ✓ $ip is ALLOWED"
            else
                echo "   ✗ $ip is BLOCKED"
            fi
        done <<< "$IPS"
    else
        echo "   ✗ Could not resolve $DOMAIN"
    fi

    echo ""
    echo "3. Testing HTTPS connection:"
    if timeout 5 curl -s https://"$DOMAIN" > /dev/null 2>&1; then
        echo "   ✓ Connection successful"
    else
        echo "   ✗ Connection failed (check logs above)"
    fi
fi

# Add command to allow a specific IP temporarily
if [ "$1" = "allow" ] && [ -n "$2" ]; then
    IP=$2
    echo "Adding $IP to allowed-domains set..."
    if sudo ipset add allowed-domains "$IP/32" -exist; then
        echo "✓ $IP added successfully"
        echo ""
        echo "To make this permanent, add it to .devcontainer/init-firewall.sh"
    else
        echo "✗ Failed to add $IP"
    fi
fi

# Add command to generate ranges from blocked IPs
if [ "$1" = "suggest-ranges" ]; then
    echo "🔍 Analyzing blocked IPs to suggest /24 ranges..."
    echo ""

    if [ ! -f /var/log/kern.log ]; then
        echo "✗ /var/log/kern.log not found"
        exit 1
    fi

    BLOCKED_IPS=$(sudo grep AIDP-FW-BLOCK /var/log/kern.log 2>/dev/null | grep -oP 'DST=\K[0-9.]+' | sort -u)

    if [ -z "$BLOCKED_IPS" ]; then
        echo "No blocked IPs found in logs"
        exit 0
    fi

    echo "Blocked IPs found:"
    echo "$BLOCKED_IPS"
    echo ""
    echo "Suggested /24 ranges to add to init-firewall.sh:"
    echo ""

    echo "$BLOCKED_IPS" | while read -r ip; do
        # Extract /24 range
        RANGE=$(echo "$ip" | grep -oP '([0-9]+\.){3}')
        if [ -n "$RANGE" ]; then
            echo "add_ip_range \"${RANGE}0/24\"    # Covers $ip"
        fi
    done | sort -u
fi
