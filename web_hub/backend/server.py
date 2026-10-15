import http.server
import json
import subprocess
import os
import urllib.parse
import sys
import hmac
import glob
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import host_config

PUBLIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "public")
ENV = host_config.load_local_env()
PORT = int(ENV.get("HUB_PORT") or "28990")
CLOUD_GAMING_SH = os.path.join(ROOT, "cloud_gaming.sh")
UNINSTALL_SH = os.path.join(ROOT, "uninstall_steam_game.sh")
PAIR_PY = os.path.join(ROOT, "pair.py")


def run_cmd(cmd):
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return res.stdout.strip(), res.returncode
    except Exception as e:
        return str(e), -1


def run_argv(argv, timeout=30):
    try:
        res = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return res.stdout.strip(), res.returncode
    except Exception as e:
        return str(e), -1


def get_installed_games():
    games = []
    steamapps = host_config.steam_apps_dir(ENV)
    for acf in glob.glob(os.path.join(steamapps, "appmanifest_*.acf")):
        try:
            with open(acf, "r", encoding="utf-8", errors="ignore") as handle:
                content = handle.read()
            appid = re.search(r'"appid"\s*"([^"]+)"', content)
            name = re.search(r'"name"\s*"([^"]+)"', content)
            installdir = re.search(r'"installdir"\s*"([^"]+)"', content)
            if appid and name:
                aid = appid.group(1)
                if aid not in ["228980", "4183110", "1493710"] and re.fullmatch(r"\d+", aid):
                    games.append({
                        "appid": aid,
                        "name": name.group(1),
                        "installdir": installdir.group(1) if installdir else "",
                    })
        except Exception:
            pass
    return sorted(games, key=lambda item: item["name"])


def get_gpu_telemetry():
    cmd = "nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit,clocks.current.graphics --format=csv,noheader,nounits"
    out, code = run_cmd(cmd)
    if code == 0 and out:
        parts = [p.strip() for p in out.split(",")]
        if len(parts) >= 7:
            return {
                "gpu_util": float(parts[0]),
                "vram_used": float(parts[1]),
                "vram_total": float(parts[2]),
                "temperature": float(parts[3]),
                "power_draw": float(parts[4]),
                "power_limit": float(parts[5]),
                "clock_graphics": float(parts[6]),
                "online": True,
            }
    return {
        "gpu_util": 0,
        "vram_used": 0,
        "vram_total": 0,
        "temperature": 0,
        "power_draw": 0,
        "power_limit": 0,
        "clock_graphics": 0,
        "online": False,
    }


def get_system_stats():
    cpu_cmd = "top -bn1 | grep 'Cpu(s)' | awk '{for(i=1;i<=NF;i++) if($i ~ /id/) print 100 - $(i-1)}'"
    cpu_out, _ = run_cmd(cpu_cmd)

    mem_cmd = "free -m | awk '/Mem:/ {print $3, $2}'"
    mem_out, _ = run_cmd(mem_cmd)
    mem_parts = mem_out.split()

    disk_cmd = "df -h / | awk 'NR==2 {print $3, $2, $5}'"
    disk_out, _ = run_cmd(disk_cmd)
    disk_parts = disk_out.split()

    gpu_data = get_gpu_telemetry()

    sunshine_running = subprocess.run(["pgrep", "-x", "sunshine"], check=False).returncode == 0
    display_running = subprocess.run(
        ["xdpyinfo", "-display", ":0"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0
    audio_running = subprocess.run(
        ["pulseaudio", "--check"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0
    steam_running = subprocess.run(["pgrep", "-x", "steam"], check=False).returncode == 0

    return {
        "gpu": gpu_data,
        "cpu_usage": float(cpu_out) if cpu_out and cpu_out.replace(".", "", 1).isdigit() else 0.0,
        "ram_used_mb": int(mem_parts[0]) if len(mem_parts) >= 2 else 0,
        "ram_total_mb": int(mem_parts[1]) if len(mem_parts) >= 2 else 0,
        "disk_used": disk_parts[0] if len(disk_parts) >= 1 else "?",
        "disk_total": disk_parts[1] if len(disk_parts) >= 2 else "?",
        "disk_pct": disk_parts[2] if len(disk_parts) >= 3 else "?",
        "services": {
            "display": display_running,
            "audio": audio_running,
            "sunshine": sunshine_running,
            "steam": steam_running,
        },
        "network": {
            "tailscale_ip": host_config.tailscale_ipv4(),
            "public_ip": ENV.get("PUBLIC_IP", "").strip(),
            "sunshine_web_port": 47990,
            "sunshine_stream_port": 47989,
        },
    }


class CloudGamingHandler(http.server.SimpleHTTPRequestHandler):
    timeout = 10

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PUBLIC_DIR, **kwargs)

    def authorized(self):
        expected = ENV.get("HUB_TOKEN", "").strip()
        if not expected:
            return False
        header = self.headers.get("Authorization", "")
        try:
            return hmac.compare_digest(header, f"Bearer {expected}")
        except (TypeError, ValueError):
            return False

    def send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, status, text):
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/stats":
            self.send_json(200, get_system_stats())
            return
        if parsed.path == "/api/status":
            out, _ = run_argv([CLOUD_GAMING_SH, "status"])
            self.send_text(200, out)
            return
        if parsed.path == "/api/installed_games":
            self.send_json(200, get_installed_games())
            return
        if parsed.path == "/api/pair_state":
            pair_data = {"pairings": []}
            state_file = "/tmp/sunshine_pairing_state.json"
            if os.path.exists(state_file):
                try:
                    with open(state_file, "r", encoding="utf-8") as handle:
                        pair_data = json.load(handle)
                except Exception:
                    pass
            self.send_json(200, pair_data)
            return
        super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        content_len = int(self.headers.get("Content-Length", 0))
        post_body = self.rfile.read(content_len) if content_len else b""
        try:
            payload = json.loads(post_body.decode("utf-8")) if post_body else {}
        except Exception:
            payload = {}

        if not self.authorized():
            self.send_json(401, {"success": False, "error": "Unauthorized"})
            return

        if parsed.path == "/api/uninstall_game":
            appid = str(payload.get("appid", "")).strip()
            if not re.fullmatch(r"\d+", appid):
                res = {"success": False, "error": "AppID must be digits only"}
            else:
                out, code = run_argv([UNINSTALL_SH, appid], timeout=120)
                res = {"success": code == 0, "output": out}
            self.send_json(200, res)
            return

        if parsed.path == "/api/services":
            action = payload.get("action", "")
            if action in ["start", "stop", "restart"]:
                out, code = run_argv([CLOUD_GAMING_SH, action], timeout=60)
                res = {"success": code == 0, "output": out}
            else:
                res = {"success": False, "error": "Invalid action"}
            self.send_json(200, res)
            return

        if parsed.path == "/api/launch_steam":
            env = os.environ.copy()
            env["DISPLAY"] = ":0"
            env["__NV_PRIME_RENDER_OFFLOAD"] = "1"
            env["__GLX_VENDOR_LIBRARY_NAME"] = "nvidia"
            subprocess.Popen(
                ["steam"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            self.send_json(200, {"success": True, "message": "Steam Desktop launched on virtual display"})
            return

        if parsed.path == "/api/reset_pairing":
            out, code = run_argv([sys.executable, PAIR_PY, "--reset"], timeout=30)
            self.send_json(200, {
                "success": code == 0,
                "message": "Sunshine restarted, all pairing sessions cleared!" if code == 0 else out,
                "output": out,
            })
            return

        if parsed.path == "/api/pair_pin":
            pin = str(payload.get("pin", "")).strip()
            if not re.fullmatch(r"\d{4}", pin):
                res = {"success": False, "error": "PIN must be 4 digits"}
            else:
                out, code = run_argv([sys.executable, PAIR_PY, pin], timeout=20)
                res = {"success": code == 0 and "SUCCESS" in out, "message": out, "output": out}
            self.send_json(200, res)
            return

        self.send_response(404)
        self.end_headers()


if __name__ == "__main__":
    os.chdir(PUBLIC_DIR)
    bind_host = host_config.hub_bind_address(ENV)
    http.server.ThreadingHTTPServer.allow_reuse_address = True
    http.server.ThreadingHTTPServer.daemon_threads = True
    with http.server.ThreadingHTTPServer((bind_host, PORT), CloudGamingHandler) as httpd:
        print(f"Cloud Gaming Hub listening on {bind_host}:{PORT}")
        httpd.serve_forever()
