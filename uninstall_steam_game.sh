#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${DIR}/config/local.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "${DIR}/config/local.env"
    set +a
fi
STEAM_APPS="${STEAM_APPS_DIR:-${HOME}/.local/share/Steam/steamapps}"

APPID="$1"
if ! [[ "${APPID}" =~ ^[0-9]+$ ]]; then
    echo "Usage: $0 <numeric Steam AppID>"
    exit 1
fi

ACF=$(find "${STEAM_APPS}" -maxdepth 1 -name "appmanifest_${APPID}.acf" 2>/dev/null || true)

if [ -z "$ACF" ]; then
    echo "Game '${APPID}' not found in Steam manifests."
    exit 1
fi

REAL_APPID=$(basename "$ACF" | grep -oP '\d+')
INSTALL_DIR=$(grep -oP '"installdir"\s*"\K[^"]+' "$ACF")
GAME_NAME=$(grep -oP '"name"\s*"\K[^"]+' "$ACF")
if [[ -z "${INSTALL_DIR}" || "${INSTALL_DIR}" == *"/"* || "${INSTALL_DIR}" == *".."* ]]; then
    echo "Refusing unsafe install directory."
    exit 1
fi

echo "Found Game: ${GAME_NAME} (AppID: ${REAL_APPID})"
echo "Install Dir: ${INSTALL_DIR}"

# Tell Steam via steam-uri or steamcmd if running, or cleanly purge files and manifest
echo "1. Stopping Steam client to safely update library..."
pkill -9 -x steam || true
pkill -9 -x steamwebhelper || true
pkill -9 -f "ubuntu12_32/steam" || true
pkill -9 -f "ubuntu12_64/steam" || true
sleep 1

echo "2. Deleting game directory (100GB+)..."
rm -rf "${STEAM_APPS}/common/${INSTALL_DIR}"
rm -rf "${STEAM_APPS}/compatdata/${REAL_APPID}"
rm -rf "${STEAM_APPS}/shadercache/${REAL_APPID}"
rm -f "$ACF"
rm -f "${HOME}/Desktop/${GAME_NAME}.desktop"

echo "3. Restarting Steam client..."
DISPLAY=:0 nohup steam -nominidumps -nobreakpad >/tmp/steam.log 2>&1 &

echo "Successfully uninstalled ${GAME_NAME}! Storage freed."
