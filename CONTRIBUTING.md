# Contributing

This is a public codebase for a headless Steam, Proton, Sunshine, and Moonlight host. Friends can suggest and implement features. The maintainer (`@end-9214`) reviews and merges. A pull request does not deploy to anyone's machine. Whoever runs a host pulls `main` themselves.

You do not need write access. Fork the repository and open a pull request.

## Suggest a feature

Open a [feature request](https://github.com/end-9214/cloud_gaming/issues/new?template=feature_request.md) before a large change so the approach can be agreed. Small fixes can go straight to a pull request. Use the bug template for defects, and leave host addresses and credentials out of the issue.

## Pull requests

1. Fork the repository.
2. Create a branch from `main`. A short name such as `feature/hub-theme` or `fix/pair-timeout` is enough.
3. Keep the change focused on one behavior.
4. Open the pull request against `main` and fill in the template.
5. Wait for Bugbot. It reads `.cursor/BUGBOT.md` and `.cursor/config/bugbot.yaml` from `main`, so a pull request cannot loosen its own review. GitHub secret scanning and push protection also run on this repository.
6. The maintainer merges after reading the review. Do not merge your own pull request.

`main` is protected. Direct pushes, force-pushes, and commits that skip review are not part of the workflow.

## What a review looks for

- The change does what the pull request says, and the test notes are enough for someone else to try it.
- No password, token, key, public address, Tailscale address, or live hostname was added.
- New host controls require the hub bearer token.
- Request data is not built into a shell command. A Steam app id is digits only.
- The web hub is not bound to `0.0.0.0`, and Sunshine's admin UI stays localhost-only (`origin_web_ui_allowed = pc`).
- GitHub Actions do not use `pull_request_target` and do not log into a server.

## Never commit

- Passwords, hub tokens, API keys, Tailscale auth keys, SSH private keys, or cloud credentials
- Public addresses, Tailscale addresses, or hostnames of a running machine
- `config/credentials.json` or `config/local.env`
- Personal game data, logs, or anything under `albion_online_jev/`

Put machine-specific values in `config/local.env`. Put the Sunshine username and password in `config/credentials.json`. Commit only the `*.example` files.

## Try it locally

```bash
cp config/local.env.example config/local.env
cp config/credentials.json.example config/credentials.json
chmod 600 config/local.env config/credentials.json
```

Fill those files on your own machine. `./setup.sh` installs the stack. `./cloud_gaming.sh status` checks the display, audio, Sunshine, and the hub. Do not point a test at a host you do not operate.
