# Pterodactyl Wings Installer

A single Bash script that automates a full [Pterodactyl Wings](https://pterodactyl.io/wings/1.0/installing.html) installation, including Docker, the Wings binary, an SSL certificate via `acme.sh` (Cloudflare DNS challenge), and the `wings.service` systemd unit.

## Features

- Auto-detects your package manager (`apt`, `dnf`, `yum`, `zypper`, `pacman`) and installs base dependencies accordingly
- Installs Docker via the official `get.docker.com` script and enables it
- Downloads the latest Wings binary for your CPU architecture (`amd64` / `arm64`)
- Prompts you to paste your `config.yml` (copied from the Pterodactyl panel) directly into the terminal
- Installs `acme.sh` and issues a Let's Encrypt certificate using the Cloudflare DNS-01 challenge
- Prompts individually for `CF_Token`, `CF_Account_ID`, `CF_Zone_ID`, `CF_Key`, and `CF_Email` — press ENTER to skip any field you don't need (only API Token *or* Global API Key is required, not both), and unused fields are never exported
- Prints a clear error message if certificate issuance fails (wrong credentials, DNS propagation delay, etc.)
- Runs `wings --debug` for 10 seconds, checks the log for errors, and only proceeds if none are found
- Creates and enables the `wings.service` systemd unit

## Requirements

- A fresh Linux server supported by Wings (Debian, Ubuntu, CentOS/RHEL/Rocky/Alma, openSUSE, Arch, etc.)
- Root access
- A domain name pointed at your server, with its DNS zone managed by Cloudflare
- A Cloudflare API Token (recommended) or Global API Key
- A Pterodactyl panel already set up, with a node created so you have `config.yml` ready to copy

## Usage

```bash
chmod +x wings-install.sh
sudo bash wings-install.sh
```

The script will interactively ask you for:

1. The domain to issue the SSL certificate for
2. Your `config.yml` content (paste it, then press `CTRL+D` on a new line)
3. Your Cloudflare credentials (Token or Global Key — your choice)

## Security note

Never commit real Cloudflare API tokens, keys, or `config.yml` secrets to a public repository. This script intentionally asks for credentials at runtime instead of hardcoding them, and Cloudflare secrets are read with hidden input (`read -s`) so they aren't echoed to the terminal or saved to shell history.

If you ever paste API credentials into a chat, document, or commit by mistake, revoke and regenerate them from the Cloudflare dashboard as soon as possible.

## What gets installed / modified

| Path | Purpose |
|---|---|
| `/usr/local/bin/wings` | Wings binary |
| `/etc/pterodactyl/config.yml` | Wings configuration |
| `/etc/letsencrypt/live/<domain>/` | Issued SSL certificate and key |
| `~/.acme.sh/` | acme.sh installation |
| `/etc/systemd/system/wings.service` | systemd unit for Wings |

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

This script performs system-level changes (installs Docker, writes systemd units, issues TLS certificates). Review it before running on a production server. Use at your own risk.
