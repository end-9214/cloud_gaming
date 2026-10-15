#!/usr/bin/env python3
"""
Sunshine Auto-Pair & Pin Helper Daemon
Continuously monitors for Moonlight clients requesting pairing.
Provides instant feedback and submits PINs seamlessly.
"""

import urllib.request
import ssl
import json
import base64
import time
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
import host_config

STATE_FILE = "/tmp/sunshine_pairing_state.json"
SUBMIT_PIN_FILE = "/tmp/sunshine_pin_submit.txt"
LOG_FILE = "/tmp/auto_pair.log"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

user, pwd = host_config.require_credentials()
auth = base64.b64encode(f"{user}:{pwd}".encode()).decode()
headers = {
    "Authorization": f"Basic {auth}",
    "Content-Type": "application/json"
}

def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    formatted = f"[{ts}] {msg}"
    print(formatted, flush=True)
    with open(LOG_FILE, "a") as f:
        f.write(formatted + "\n")

def get_pairings():
    try:
        req = urllib.request.Request("https://localhost:47990/api/pin", headers=headers, method="GET")
        with urllib.request.urlopen(req, context=ctx, timeout=2) as r:
            return json.loads(r.read().decode()).get("pairings", [])
    except Exception as e:
        return None

def submit_pin(pairing_id, pin, name="Client"):
    try:
        payload = json.dumps({
            "pairing_id": pairing_id,
            "pin": pin,
            "name": name
        }).encode("utf-8")
        req = urllib.request.Request("https://localhost:47990/api/pin", data=payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, context=ctx, timeout=4) as r:
            res = json.loads(r.read().decode())
            return True, res
    except Exception as e:
        return False, str(e)

def run():
    log("Starting Sunshine Auto-Pair Daemon...")
    last_id = None
    
    while True:
        pairings = get_pairings()
        
        # Write state file for Web Hub
        state_data = {
            "timestamp": time.time(),
            "pairings": pairings if pairings is not None else []
        }
        with open(STATE_FILE, "w") as f:
            json.dump(state_data, f)
            
        if pairings:
            for p in pairings:
                pid = p.get("id")
                pname = p.get("name", "Unknown")
                paddr = p.get("address", "")
                if pid != last_id:
                    log(f"ALERT: Pairing request detected from '{pname}' ({paddr}) - ID: {pid}")
                    last_id = pid
                    
            # Check if a PIN has been submitted via file
            if os.path.exists(SUBMIT_PIN_FILE):
                try:
                    with open(SUBMIT_PIN_FILE, "r") as f:
                        pin = f.read().strip()
                    if pin:
                        target = pairings[0]
                        log(f"Submitting PIN '{pin}' for client '{target.get('name')}' (ID: {target.get('id')})...")
                        success, resp = submit_pin(target.get("id"), pin, target.get("name", "Client"))
                        log(f"Result: success={success}, resp={resp}")
                        os.remove(SUBMIT_PIN_FILE)
                except Exception as e:
                    log(f"Error handling submitted pin: {e}")
        else:
            if last_id is not None:
                log("No devices currently waiting to pair.")
                last_id = None
                
        time.sleep(0.5)

if __name__ == "__main__":
    run()
