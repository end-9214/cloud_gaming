#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${DIR}/config/local.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "${DIR}/config/local.env"
    set +a
fi
STEAM_APPS="${STEAM_APPS_DIR:-${HOME}/.local/share/Steam/steamapps}"
export DISPLAY=":0"
export XAUTHORITY="${HOME}/.Xauthority"

GAMES_LIST=()
while IFS= read -r acf; do
    [ -f "$acf" ] || continue
    APPID=$(grep -oP '"appid"\s*"\K[^"]+' "$acf" || true)
    NAME=$(grep -oP '"name"\s*"\K[^"]+' "$acf" || true)
    INSTALLDIR=$(grep -oP '"installdir"\s*"\K[^"]+' "$acf" || true)
    
    # Filter out redistributables and runtimes
    if [[ "$APPID" == "228980" || "$APPID" == "4183110" || "$APPID" == "1493710" ]]; then
        continue
    fi
    
    if [ -n "$APPID" ] && [ -n "$NAME" ]; then
        GAMES_LIST+=("$APPID" "$NAME ($INSTALLDIR)")
    fi
done < <(find "${STEAM_APPS}" -maxdepth 1 -name "appmanifest_*.acf" 2>/dev/null)

if [ ${#GAMES_LIST[@]} -eq 0 ]; then
    zenity --info --title="Steam Uninstaller" --text="No installed user games found to uninstall!" --width=350
    exit 0
fi

SELECTED_APPID=$(zenity --list --title="Cloud Gaming Steam Game Uninstaller" \
    --column="AppID" --column="Game Title" \
    "${GAMES_LIST[@]}" \
    --height=350 --width=450 --text="Select a game to completely uninstall and free disk space:")

if [ -n "$SELECTED_APPID" ]; then
    if zenity --question --title="Confirm Uninstall" --text="Are you sure you want to completely uninstall AppID ${SELECTED_APPID}?\nThis will wipe the game files and update Steam instantly." --width=400; then
        "${DIR}/uninstall_steam_game.sh" "$SELECTED_APPID"
        zenity --info --title="Uninstalled" --text="Game successfully uninstalled and storage freed!" --width=350
    fi
fi
