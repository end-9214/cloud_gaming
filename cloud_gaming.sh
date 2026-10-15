#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${DIR}/config/local.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "${DIR}/config/local.env"
    set +a
fi
DISPLAY_NUM=":0"
export DISPLAY="${DISPLAY_NUM}"
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only

start_audio() {
    echo ">> Initializing PulseAudio virtual audio sink..."
    if ! pulseaudio --check; then
        pulseaudio -D --exit-idle-time=-1 || true
    fi
    # Wait for pulseaudio daemon
    sleep 1
    # Check if null-sink is loaded
    if ! pactl list short sinks | grep -q "GameAudio"; then
        pactl load-module module-null-sink sink_name=GameAudio sink_properties=device.description="Virtual_Cloud_Audio" || true
    fi
    pactl set-default-sink GameAudio || true
    echo ">> Virtual audio ready."
}

start_display() {
    echo ">> Starting virtual X11 display on ${DISPLAY_NUM}..."
    if [ -f /tmp/.X0-lock ]; then
        echo "Display :0 lock found, cleaning up stale lock if needed..."
        sudo rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 || true
    fi
    
    # Group-writable devices for the logged-in user. The udev rule in setup.sh
    # keeps new devices on that group; do not make them world-writable.
    sudo chgrp "$(id -gn)" /dev/uinput /dev/dri/* 2>/dev/null || true
    sudo chmod 0660 /dev/uinput /dev/dri/* 2>/dev/null || true
    
    # Start Xorg dummy server with 96 DPI
    Xorg "${DISPLAY_NUM}" -config "${DIR}/config/xorg.conf" -dpi 96 -noreset +extension GLX +extension RANDR +extension RENDER &
    XORG_PID=$!
    echo "${XORG_PID}" > /tmp/xorg_cloud_gaming.pid
    
    # Wait for display
    for i in {1..10}; do
        if xdpyinfo -display "${DISPLAY_NUM}" >/dev/null 2>&1; then
            echo ">> Virtual display ${DISPLAY_NUM} is active!"
            break
        fi
        sleep 0.5
    done
    
    # Configure modes on DUMMY0
    DISPLAY="${DISPLAY_NUM}" xrandr --newmode "1920x1080_165.00" 525.00 1920 2088 2296 2672 1080 1083 1088 1192 -hsync +vsync 2>/dev/null || true
    DISPLAY="${DISPLAY_NUM}" xrandr --addmode DUMMY0 "1920x1080_165.00" 2>/dev/null || true
    DISPLAY="${DISPLAY_NUM}" xrandr --newmode "1920x1080_120.00" 369.50 1920 2080 2288 2656 1080 1083 1088 1160 -hsync +vsync 2>/dev/null || true
    DISPLAY="${DISPLAY_NUM}" xrandr --addmode DUMMY0 "1920x1080_120.00" 2>/dev/null || true
    DISPLAY="${DISPLAY_NUM}" xrandr --output DUMMY0 --mode "1920x1080_165.00" 2>/dev/null || \
    DISPLAY="${DISPLAY_NUM}" xrandr --output DUMMY0 --mode "1920x1080_120.00" 2>/dev/null || \
    DISPLAY="${DISPLAY_NUM}" xrandr --output DUMMY0 --mode "1920x1080" 2>/dev/null || true
    
    # Start desktop environment and watchdog
    export DISPLAY="${DISPLAY_NUM}"
    export XAUTHORITY="${HOME}/.Xauthority"
    pkill -f "ensure_desktop.sh" || true
    nohup "${DIR}/config/ensure_desktop.sh" >/dev/null 2>&1 &
    sleep 1
    DISPLAY="${DISPLAY_NUM}" feh --bg-fill "${DIR}/wallpaper.png" || true
}

start_sunshine() {
    echo ">> Starting dummy status notifier tray daemon..."
    pkill -f "dummy_tray.py" || true
    nohup python3 "${DIR}/config/dummy_tray.py" >/tmp/dummy_tray.log 2>&1 &
    sleep 1

    echo ">> Synchronizing Sunshine configuration..."
    mkdir -p "${HOME}/.config/sunshine"
    if [ -f "${DIR}/config/sunshine.conf" ]; then
        cp "${DIR}/config/sunshine.conf" "${HOME}/.config/sunshine/sunshine.conf"
    fi
    if [ -f "${DIR}/config/apps.json" ]; then
        cp "${DIR}/config/apps.json" "${HOME}/.config/sunshine/apps.json"
    fi
    if [ -n "${SUNSHINE_BIND_ADDRESS:-}" ] && [ -f "${HOME}/.config/sunshine/sunshine.conf" ]; then
        if grep -q '^bind_address' "${HOME}/.config/sunshine/sunshine.conf"; then
            sed -i "s/^bind_address.*/bind_address = ${SUNSHINE_BIND_ADDRESS}/" "${HOME}/.config/sunshine/sunshine.conf"
        else
            echo "bind_address = ${SUNSHINE_BIND_ADDRESS}" >> "${HOME}/.config/sunshine/sunshine.conf"
        fi
    fi

    echo ">> Starting Sunshine Game Streaming host..."
    if command -v sunshine >/dev/null 2>&1; then
        export DISPLAY="${DISPLAY_NUM}"
        export QT_QPA_PLATFORM=xcb
        export XAUTHORITY="${HOME}/.Xauthority"
        DISPLAY="${DISPLAY_NUM}" QT_QPA_PLATFORM=xcb nohup sunshine "${HOME}/.config/sunshine/sunshine.conf" > "${HOME}/.config/sunshine/sunshine.log" 2>&1 &
        echo ">> Sunshine started."
    else
        echo "!! Sunshine is not installed yet."
    fi
}

status() {
    if timeout 3 xdpyinfo -display "${DISPLAY_NUM}" >/dev/null 2>&1; then
        echo "[+] Virtual Display (${DISPLAY_NUM}): RUNNING"
    else
        echo "[-] Virtual Display (${DISPLAY_NUM}): STOPPED"
    fi

    if timeout 3 pulseaudio --check 2>/dev/null; then
        echo "[+] PulseAudio: RUNNING (Default sink: $(timeout 2 pactl get-default-sink 2>/dev/null || echo 'none'))"
    else
        echo "[-] PulseAudio: STOPPED"
    fi
    
    if pgrep -x "sunshine" >/dev/null 2>&1; then
        echo "[+] Sunshine Streamer: RUNNING (PID $(pgrep -x sunshine))"
    else
        echo "[-] Sunshine Streamer: STOPPED"
    fi

    if pgrep -f "web_hub/backend/server.py" >/dev/null 2>&1; then
        echo "[+] Web Hub Backend: RUNNING (Port 28990)"
    else
        echo "[-] Web Hub Backend: STOPPED"
    fi
}

stop_all() {
    echo ">> Stopping all cloud gaming services, games, and desktop apps..."
    # 0. Kill watchdog first so it doesn't immediately resurrect desktop apps
    pkill -f "ensure_desktop.sh" || true

    # 1. Kill any active games, Steam, Proton/Wine, and browsers
    pkill -f "steam" || true
    pkill -f "steamwebhelper" || true
    pkill -f "wineserver" || true
    pkill -f "wine" || true
    pkill -f "proton" || true
    pkill -f "google-chrome" || true
    pkill -f "xterm" || true
    
    # 2. Kill streaming daemons, web hub, and desktop environment
    pkill -f "dummy_tray.py" || true
    pkill -f "sunshine" || true
    pkill -f "web_hub/backend/server.py" || true
    pkill -f "xfce" || true
    pkill -f "xfwm4" || true
    pkill -f "xfdesktop" || true
    pkill -f "tint2" || true
    pkill -f "pcmanfm" || true
    pkill -f "openbox" || true
    pkill -f "conky" || true
    pkill -f "gpu_monitor.sh" || true
    
    # 3. Kill virtual display server (:0)
    if [ -f /tmp/xorg_cloud_gaming.pid ]; then
        kill "$(cat /tmp/xorg_cloud_gaming.pid)" 2>/dev/null || true
        rm -f /tmp/xorg_cloud_gaming.pid
    fi
    pkill -f "Xorg :0" || true
    sudo rm -f /tmp/.X0-lock /tmp/.X11-unix/X0 || true
    echo ">> All cloud gaming services, games, and desktop apps cleanly stopped."
}

start_webhub() {
    echo ">> Checking Web Hub backend on port 28990..."
    if ! pgrep -f "web_hub/backend/server.py" >/dev/null 2>&1; then
        echo ">> Starting Web Hub backend on port 28990..."
        nohup python3 "${DIR}/web_hub/backend/server.py" >/tmp/cloud_gaming_webhub.log 2>&1 &
        sleep 1
    else
        echo ">> Web Hub backend already active on port 28990."
    fi
}

case "$1" in
    start)
        if [ -x "${DIR}/config/lock_public_ports.sh" ]; then
            "${DIR}/config/lock_public_ports.sh" || true
        fi
        start_audio
        start_display
        start_sunshine
        start_webhub
        ;;
    stop)
        stop_all
        ;;
    restart)
        stop_all
        sleep 2
        if [ -x "${DIR}/config/lock_public_ports.sh" ]; then
            "${DIR}/config/lock_public_ports.sh" || true
        fi
        start_audio
        start_display
        start_sunshine
        start_webhub
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
