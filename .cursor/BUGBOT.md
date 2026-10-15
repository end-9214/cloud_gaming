# Bugbot review rules

Review every pull request for ways a public commit could expose or control a host.

Reject changes that:

- Hardcode a password, token, API key, Tailscale auth key, SSH private key, or cloud credential.
- Hardcode a public address, a Tailscale address, or a live hostname.
- Add `shell=True` or string-built shell commands that include request data.
- Listen on `0.0.0.0` for the web hub or widen Sunshine `origin_web_ui_allowed` beyond localhost (`pc`).
- Add a GitHub Actions workflow that uses `pull_request_target`.
- Add a deploy step, SSH session, Tailscale login, or cloud credential to GitHub Actions.
- Commit `config/credentials.json`, `config/local.env`, or a real value copied from those files.
- Weaken the hub bearer-token check or accept a Steam app id that is not all digits.

The example files may contain the placeholder password `change-me` and empty addresses. Those are not live secrets.
