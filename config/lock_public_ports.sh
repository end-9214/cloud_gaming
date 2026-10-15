#!/usr/bin/env bash
# Drop cloud-gaming control and stream ports on the public default interface.
# Tailscale traffic arrives on tailscale0 and is not matched by this chain.
set -euo pipefail

PUB_IF="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
if [ -z "${PUB_IF}" ] || [ "${PUB_IF}" = "tailscale0" ] || [ "${PUB_IF}" = "lo" ]; then
    echo "No public interface to lock."
    exit 0
fi

if ! command -v iptables >/dev/null 2>&1; then
    echo "iptables is not installed; skipping public port lock."
    exit 0
fi

sudo iptables -N CLOUD_GAMING_LOCK 2>/dev/null || sudo iptables -F CLOUD_GAMING_LOCK
if ! sudo iptables -C INPUT -i "${PUB_IF}" -j CLOUD_GAMING_LOCK 2>/dev/null; then
    sudo iptables -I INPUT -i "${PUB_IF}" -j CLOUD_GAMING_LOCK
fi

for port in 28990 47984 47989 47990 48010; do
    sudo iptables -A CLOUD_GAMING_LOCK -p tcp --dport "${port}" -j DROP
done
for port in 47998 47999 48000 48002 48010; do
    sudo iptables -A CLOUD_GAMING_LOCK -p udp --dport "${port}" -j DROP
done
sudo iptables -A CLOUD_GAMING_LOCK -j RETURN

echo "Cloud gaming ports are dropped on ${PUB_IF}."
