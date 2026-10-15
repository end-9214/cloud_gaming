# Cloud gaming host

Headless Steam and Proton, streamed with [Sunshine](https://github.com/LizardByte/Sunshine) and played from [Moonlight](https://moonlight-stream.org/). The web hub shows GPU telemetry, launches Steam, pairs a Moonlight client, and uninstalls games.

Friends can suggest a feature or send a pull request. See [CONTRIBUTING.md](CONTRIBUTING.md). The maintainer reviews those pull requests and merges them. Nothing in this repository logs into a live machine.

This repository is the code only. Addresses, the hub token, and the Sunshine password stay on the machine that runs the stack.

## What starts

`./cloud_gaming.sh start` brings up:

1. A PulseAudio null sink named `GameAudio`.
2. A dummy Xorg display on `:0` using `config/xorg.conf`.
3. An Openbox desktop (panel, wallpaper, Conky) kept alive by `config/ensure_desktop.sh`.
4. Sunshine, capturing that display with NVENC. The admin UI accepts localhost only.
5. The web hub, bound to the Tailscale address when one is configured, otherwise `127.0.0.1`.

`./cloud_gaming.sh stop` stops the desktop, Steam, Sunshine, and the hub. `status` and `restart` do what they say.

On start, `config/lock_public_ports.sh` drops the hub and Sunshine ports on the machine's default public interface. Traffic that arrives through Tailscale is not on that interface.

## First-time setup

Install the host packages and the firewall unit:

```bash
./setup.sh
```

Before you expose the hub, create the two local files. Both are gitignored.

```bash
cp config/local.env.example config/local.env
cp config/credentials.json.example config/credentials.json
chmod 600 config/local.env config/credentials.json
```

Edit `config/local.env` and set `HUB_TOKEN` (`openssl rand -hex 32`). Leave `PUBLIC_IP` empty. Leave `HUB_BIND_ADDRESS` empty to listen on the Tailscale IPv4 address, or set it to `127.0.0.1` for a local-only hub. Do not set it to `0.0.0.0`.

Edit `config/credentials.json` with a username and password, then load them into Sunshine:

```bash
sunshine --creds USERNAME PASSWORD
```

Restart Sunshine after that so the running process picks up the new password. The web hub reads the same file when it submits a pairing PIN.

## Play

1. Connect the client and the host with Tailscale, or use a LAN address you already trust.
2. In Moonlight, add the host using that address.
3. Open the web hub in a browser on the same network. The dashboard shows the address Moonlight should use.
4. When Moonlight shows a 4-digit PIN, enter it on the Pair tab. The hub asks for `HUB_TOKEN` and stores it in the browser.
5. Launch Steam from the hub, or start the Steam app inside Moonlight.

The Sunshine admin UI is `https://127.0.0.1:47990` on the host. It is not reachable from other machines.

## Layout

| Path | Role |
| :--- | :--- |
| `cloud_gaming.sh` | Start, stop, restart, and status |
| `setup.sh` | Install packages and the firewall unit |
| `config/sunshine.conf` | Sunshine template copied into `~/.config/sunshine` on start |
| `config/apps.json` | Moonlight apps: Steam and the desktop |
| `web_hub/` | Phone dashboard and its Python server |
| `pair.py` | Submit a Moonlight PIN to local Sunshine |
| `host_config.py` | Read the gitignored local files |

MangoHud is enabled for Steam games from `config/apps.json`. The in-game toggle is Right Shift + F12.

## Contributing

Fork the repository, open a pull request, and do not commit secrets. See [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through [SECURITY.md](SECURITY.md).

Nothing in this repository deploys to a live host. After a pull request is merged, the person who runs a host pulls the code on that machine themselves.
