#!/bin/bash
export DISPLAY=":0"
export XAUTHORITY="${HOME}/.Xauthority"


ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ensure environment is synced to dbus and user systemd for proper modal windows
dbus-update-activation-environment --systemd DISPLAY=:0 XAUTHORITY="${HOME}/.Xauthority" 2>/dev/null || true

while true; do
    if ! pgrep -x "openbox" >/dev/null 2>&1; then
        openbox &
    fi
    if ! pgrep -x "tint2" >/dev/null 2>&1; then
        tint2 &
    fi
    if ! pgrep -x "pcmanfm" >/dev/null 2>&1; then
        pcmanfm --desktop &
    fi
    if ! pgrep -f "gpu_monitor.sh" >/dev/null 2>&1; then
        nohup "${ROOT}/config/gpu_monitor.sh" >/dev/null 2>&1 &
    fi
    if ! pgrep -x "conky" >/dev/null 2>&1; then
        conky -c "${ROOT}/config/conky.conf" &
    fi
    sleep 3
done

