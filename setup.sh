#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "=========================================================="
echo "   NVIDIA L40S CLOUD GAMING & SUNSHINE AUTOMATED SETUP   "
echo "=========================================================="

echo ">> 1. Installing display server, audio, and utilities..."
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y \
    xserver-xorg-video-dummy x11-xserver-utils openbox xinit \
    pulseaudio pulseaudio-utils vulkan-tools mesa-utils joystick evtest wget curl

echo ">> 2. Downloading & Installing Sunshine Game Streaming..."
SUNSHINE_DEB="/tmp/sunshine.deb"
if ! command -v sunshine >/dev/null 2>&1; then
    echo ">> Fetching Sunshine deb package for Ubuntu 26.04..."
    wget -q --show-progress -O "${SUNSHINE_DEB}" \
        "https://github.com/LizardByte/Sunshine/releases/download/v2026.906.222525/sunshine_2026.906.222525-1%2Bubuntu26.04_amd64.deb"
    sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y "${SUNSHINE_DEB}"
    rm -f "${SUNSHINE_DEB}"
    echo ">> Sunshine installed successfully!"
else
    echo ">> Sunshine is already installed."
fi

echo ">> 3. Setting up virtual controller permissions (uinput)..."
sudo modprobe uinput || true
echo "KERNEL==\"uinput\", MODE=\"0660\", GROUP=\"$(id -gn)\"" | sudo tee /etc/udev/rules.d/85-sunshine-uinput.rules >/dev/null
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true
sudo chmod 666 /dev/uinput || true

echo ">> 4. Setting up Sunshine configuration..."
mkdir -p "${HOME}/.config/sunshine"
cp "${DIR}/config/sunshine.conf" "${HOME}/.config/sunshine/sunshine.conf"
cp "${DIR}/config/apps.json" "${HOME}/.config/sunshine/apps.json"

echo ">> 5. Installing Steam Client & Optimizing Shader Pre-Caching..."
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y steam-installer || true
TOTAL_THREADS=$(nproc 2>/dev/null || echo 16)
if [ "$TOTAL_THREADS" -gt 4 ]; then
    SHADER_THREADS=$(( TOTAL_THREADS - 4 ))
else
    SHADER_THREADS=2
fi
for STEAM_DIR in "${HOME}/.steam/steam" "${HOME}/.steam/debian-installation" "${HOME}/.local/share/Steam"; do
    if [ -d "$STEAM_DIR" ]; then
        echo "unShaderBackgroundProcessingThreads ${SHADER_THREADS}" > "${STEAM_DIR}/steam_dev.cfg"
    fi
done
echo ">> Configured Steam Shader Pre-Caching threads: ${SHADER_THREADS}"

echo ">> 6. Making manager scripts executable..."
chmod +x "${DIR}/cloud_gaming.sh"
chmod +x "${DIR}/web_hub/backend/server.py"

if [ ! -f "${DIR}/config/local.env" ]; then
    cp "${DIR}/config/local.env.example" "${DIR}/config/local.env"
    TOKEN="$(openssl rand -hex 32)"
    if grep -q '^HUB_TOKEN=' "${DIR}/config/local.env"; then
        sed -i "s/^HUB_TOKEN=.*/HUB_TOKEN=${TOKEN}/" "${DIR}/config/local.env"
    else
        echo "HUB_TOKEN=${TOKEN}" >> "${DIR}/config/local.env"
    fi
    chmod 600 "${DIR}/config/local.env"
    echo ">> Wrote config/local.env. Read HUB_TOKEN from that file. It is not printed here."
fi
if [ ! -f "${DIR}/config/credentials.json" ]; then
    echo ">> Create config/credentials.json from config/credentials.json.example, then run: sunshine --creds <username> <password>"
fi

UNIT_PATH="/etc/systemd/system/cloud-gaming-firewall.service"
sudo tee "${UNIT_PATH}" >/dev/null <<EOF
[Unit]
Description=Drop cloud gaming ports on the public interface
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${DIR}/config/lock_public_ports.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now cloud-gaming-firewall.service || true

echo ">> 7. Starting Cloud Gaming stack..."
chmod +x "${DIR}/config/lock_public_ports.sh" "${DIR}/config/ensure_desktop.sh" "${DIR}/config/gpu_monitor.sh"
"${DIR}/cloud_gaming.sh" restart

echo ""
echo "=========================================================="
echo "          CLOUD GAMING SETUP COMPLETE & ACTIVE!          "
echo "=========================================================="
echo ">> Web hub listens on the address in config/local.env (Tailscale or localhost)."
echo ">> Sunshine admin UI is localhost only: https://127.0.0.1:47990"
echo ">> Moonlight host address is the machine's Tailscale or LAN address."
echo ">> Hub token and Sunshine password stay in the gitignored local files."
echo "=========================================================="
