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
echo "🧪 Test a specific domain:"
echo "   ./debug-firewall.sh test <domain>"
echo ""

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
