#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.error
import ssl
import re
import os
import subprocess
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
import host_config

user, pwd = host_config.require_credentials()

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

import base64
auth = base64.b64encode(f"{user}:{pwd}".encode()).decode()
headers = {
    "Authorization": f"Basic {auth}",
    "Content-Type": "application/json"
}

def get_pending():
    try:
        req = urllib.request.Request("https://localhost:47990/api/pin", headers=headers)
        with urllib.request.urlopen(req, context=ctx, timeout=3) as resp:
            data = json.loads(resp.read().decode())
            return data.get("pairings", [])
    except Exception as e:
        print(f"[-] GET /api/pin failed: {e}")
        return []

def pair(pin, pairing_id=None, name="Client"):
    pairings = get_pending()
    if not pairing_id:
        if pairings:
            pairing_id = pairings[0].get("id")
            name = pairings[0].get("name", name)
            print(f"[+] Found pending pairing request from '{name}' ({pairings[0].get('address')}) - ID: {pairing_id}")
        else:
            print("[-] No pairing request is currently waiting in Sunshine.")
            print("    Make sure Moonlight has clicked the host and is showing the 4-digit PIN.")
            # Also write to submit pin file for daemon to catch as soon as request arrives
            with open("/tmp/sunshine_pin_submit.txt", "w") as f:
                f.write(str(pin))
            print(f"[+] Saved PIN {pin} to auto-submit as soon as Moonlight connects.")
            return False

    payload = json.dumps({
        "pairing_id": str(pairing_id),
        "pin": str(pin),
        "name": str(name)
    }).encode("utf-8")
    
    try:
        req = urllib.request.Request("https://localhost:47990/api/pin", data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, context=ctx, timeout=5) as resp:
            res_text = resp.read().decode()
            print(f"[+] Sunshine Pair Response: {res_text}")
            return True
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        print(f"[-] HTTP Error {e.code}: {err}")
        return False
    except Exception as e:
        print(f"[-] Pair request error: {e}")
        return False

def reset_sunshine():
    print("[+] Restarting Sunshine to clear any stuck pairing sessions...")
    subprocess.run("pkill -f 'dummy_tray.py' || true", shell=True)
    subprocess.run("pkill -f 'sunshine' || true", shell=True)
    time.sleep(1)
    env = os.environ.copy()
    env["DISPLAY"] = ":0"
    env["QT_QPA_PLATFORM"] = "xcb"
    env["XAUTHORITY"] = os.path.expanduser("~/.Xauthority")
    tray = os.path.join(ROOT, "config", "dummy_tray.py")
    conf = os.path.expanduser("~/.config/sunshine/sunshine.conf")
    log = os.path.expanduser("~/.config/sunshine/sunshine.log")
    subprocess.Popen(
        [sys.executable, tray],
        stdout=open("/tmp/dummy_tray.log", "a"),
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    time.sleep(1)
    subprocess.Popen(
        ["sunshine", conf],
        env=env,
        stdout=open(log, "a"),
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    time.sleep(2)
    print("[+] Sunshine restarted successfully. Ready for fresh pairing.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 pair.py <4-digit-pin> OR python3 pair.py --reset")
        sys.exit(1)
    if sys.argv[1] == "--reset":
        reset_sunshine()
        sys.exit(0)
    pin = sys.argv[1]
    pid = sys.argv[2] if len(sys.argv) > 2 else None
    success = pair(pin, pid)
    if success:
        print("\n🎉 SUCCESS! Moonlight is now paired! Return to Moonlight and tap the host to stream!")
    else:
        print("\n⚠️ Pair request could not be completed immediately.")
