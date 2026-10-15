"""Load machine-local settings that must never be committed."""

import json
import os
import subprocess

ROOT = os.path.dirname(os.path.abspath(__file__))
LOCAL_ENV = os.path.join(ROOT, "config", "local.env")
CREDENTIALS = os.path.join(ROOT, "config", "credentials.json")
PLACEHOLDER_PASSWORD = "change-me"


def load_local_env():
    env = {}
    if not os.path.isfile(LOCAL_ENV):
        return env
    with open(LOCAL_ENV, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def require_credentials():
    if not os.path.isfile(CREDENTIALS):
        raise SystemExit(
            "Missing config/credentials.json. Copy config/credentials.json.example "
            "and set a username and password. Do not commit that file."
        )
    with open(CREDENTIALS, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    username = str(data.get("username") or "").strip()
    password = str(data.get("password") or "")
    if not username or not password or password == PLACEHOLDER_PASSWORD:
        raise SystemExit(
            "config/credentials.json must contain a real username and password."
        )
    return username, password


def tailscale_ipv4():
    try:
        result = subprocess.run(
            ["tailscale", "ip", "-4"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    if result.returncode != 0:
        return ""
    for line in result.stdout.splitlines():
        candidate = line.strip()
        if candidate:
            return candidate
    return ""


def hub_bind_address(env=None):
    env = load_local_env() if env is None else env
    chosen = env.get("HUB_BIND_ADDRESS", "").strip()
    if chosen:
        return chosen
    return tailscale_ipv4() or "127.0.0.1"


def steam_apps_dir(env=None):
    env = load_local_env() if env is None else env
    custom = env.get("STEAM_APPS_DIR", "").strip()
    if custom:
        return custom
    return os.path.join(os.path.expanduser("~"), ".local", "share", "Steam", "steamapps")
