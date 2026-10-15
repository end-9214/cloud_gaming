# Security

This is a public source repository. It does not contain a live host address, and opening an issue here will not reach a running machine.

## Reporting a problem

If you find a vulnerability in this code, open a private GitHub security advisory on the repository instead of a public issue. Describe the code path. Do not include a live host address, a token, or a password.

The maintainer runs any private host separately from this repository. Please do not probe machines you do not own.

## What this repository already refuses

- The web hub does not listen on all interfaces unless the operator sets that bind address locally.
- POST actions require a bearer token that is not in git.
- The Sunshine admin UI template allows localhost only.
- `config/lock_public_ports.sh` drops the hub and Sunshine ports on the default public interface.
- GitHub secret scanning and push protection are enabled on the repository. Workflows must not deploy and must not receive host credentials.
