#!/usr/bin/env bash
#
# Pterodactyl Wings Automated Installation Script
# Supported package managers: apt, dnf, yum, zypper, pacman
#
# Usage: sudo bash wings-install.sh
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
info()  { echo -e "\e[34m[INFO]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; }

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    error "This script must be run as root. Please re-run with 'sudo bash $0'."
    exit 1
  fi
}

detect_pkg_manager() {
  if command -v apt-get &>/dev/null; then
    echo "apt"
  elif command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v yum &>/dev/null; then
    echo "yum"
  elif command -v zypper &>/dev/null; then
    echo "zypper"
  elif command -v pacman &>/dev/null; then
    echo "pacman"
  else
    echo "unknown"
  fi
}

install_base_packages() {
  local pm="$1"
  info "Installing base packages (curl, sudo)..."
  case "$pm" in
    apt)
      apt-get update -y
      apt-get install -y sudo curl
      ;;
    dnf)
      dnf install -y sudo curl
      ;;
    yum)
      yum install -y sudo curl
      ;;
    zypper)
      zypper --non-interactive install sudo curl
      ;;
    pacman)
      pacman -Sy --noconfirm sudo curl
      ;;
    *)
      warn "Could not auto-detect a package manager. Make sure curl and sudo are already installed."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
require_root

echo "=============================================="
echo "   Pterodactyl Wings Installation Script"
echo "=============================================="
echo

read -rp "Enter the domain to use for the SSL certificate (e.g. panel.example.com): " DOMAIN
if [[ -z "${DOMAIN}" ]]; then
  error "Domain cannot be empty."
  exit 1
fi
info "Using '${DOMAIN}' as the domain."
echo

PKG_MANAGER=$(detect_pkg_manager)
info "Detected package manager: ${PKG_MANAGER}"

# ---------------------------------------------------------------------------
# 1) Base packages
# ---------------------------------------------------------------------------
install_base_packages "${PKG_MANAGER}"

# ---------------------------------------------------------------------------
# 2) Docker installation
# ---------------------------------------------------------------------------
info "Installing Docker..."
curl -sSL https://get.docker.com/ | CHANNEL=stable bash
systemctl enable --now docker
info "Docker installed and service started."

# ---------------------------------------------------------------------------
# 3) Pterodactyl directory and Wings binary
# ---------------------------------------------------------------------------
mkdir -p /etc/pterodactyl

ARCH=$(uname -m)
if [[ "${ARCH}" == "x86_64" ]]; then
  WINGS_ARCH="amd64"
else
  WINGS_ARCH="arm64"
fi

info "Downloading Wings (architecture: ${WINGS_ARCH})..."
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${WINGS_ARCH}"
chmod u+x /usr/local/bin/wings
info "Wings binary installed to /usr/local/bin/wings."

# ---------------------------------------------------------------------------
# 4) config.yml - paste from the panel
# ---------------------------------------------------------------------------
echo
info "Now paste the config.yml content you copied from the Pterodactyl panel below."
info "When you're done pasting, press ENTER for a new line, then press CTRL+D."
echo "----------------------------------------------"
cat > /etc/pterodactyl/config.yml
echo "----------------------------------------------"
info "config.yml saved to /etc/pterodactyl/config.yml."

# ---------------------------------------------------------------------------
# 5) acme.sh installation
# ---------------------------------------------------------------------------
echo
info "Installing acme.sh..."
curl https://get.acme.sh | sh

ACME_HOME="${HOME}/.acme.sh"
ACME_BIN="${ACME_HOME}/acme.sh"

if [[ ! -x "${ACME_BIN}" ]]; then
  error "acme.sh installation not found (${ACME_BIN}). Please check the installation."
  exit 1
fi

mkdir -p "/etc/letsencrypt/live/${DOMAIN}"

# ---------------------------------------------------------------------------
# 6) Cloudflare authentication details
# ---------------------------------------------------------------------------
echo
warn "If you have shared Cloudflare API credentials anywhere insecure (chat, email, etc.),"
warn "it's strongly recommended to revoke and regenerate them from the Cloudflare dashboard."
echo
info "Enter your Cloudflare credentials below. Press ENTER to leave any field empty (it will"
info "simply not be exported). Use CF_Token/CF_Account_ID/CF_Zone_ID for an API Token, or"
info "CF_Key/CF_Email for a Global API Key — you only need to fill in the set you use."
echo

read -rsp "CF_Token: " CF_Token; echo
read -rp  "CF_Account_ID: " CF_Account_ID
read -rp  "CF_Zone_ID: " CF_Zone_ID
read -rsp "CF_Key (Global API Key): " CF_Key; echo
read -rp  "CF_Email: " CF_Email

if [[ -n "${CF_Token}" ]]; then export CF_Token; fi
if [[ -n "${CF_Account_ID}" ]]; then export CF_Account_ID; fi
if [[ -n "${CF_Zone_ID}" ]]; then export CF_Zone_ID; fi
if [[ -n "${CF_Key}" ]]; then export CF_Key; fi
if [[ -n "${CF_Email}" ]]; then export CF_Email; fi

if [[ -z "${CF_Token}" && -z "${CF_Key}" ]]; then
  error "You must provide either CF_Token or CF_Key (Global API Key) to authenticate with Cloudflare."
  exit 1
fi

# ---------------------------------------------------------------------------
# 7) Issue the SSL certificate
# ---------------------------------------------------------------------------
echo
info "Issuing SSL certificate for ${DOMAIN}..."
set +e
"${ACME_BIN}" --issue --dns dns_cf -d "${DOMAIN}" --server letsencrypt \
  --key-file "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" \
  --fullchain-file "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
ACME_EXIT=$?
set -e

if [[ ${ACME_EXIT} -ne 0 ]]; then
  echo "----------------------------------------------"
  error "Failed to issue the SSL certificate (acme.sh exit code: ${ACME_EXIT})."
  error "Check the acme.sh output above for details — common causes are wrong"
  error "Cloudflare credentials, a Zone/Account ID mismatch, or DNS propagation delays."
  exit 1
fi

info "SSL certificate issued successfully."

# ---------------------------------------------------------------------------
# 8) wings --debug test (10 seconds)
# ---------------------------------------------------------------------------
echo
info "Starting wings --debug, watching logs for 10 seconds..."
LOGFILE=$(mktemp)
set +e
wings --debug > "${LOGFILE}" 2>&1 &
WINGS_PID=$!
set -e

sleep 10

if grep -Eiq "level=error|panic|fatal" "${LOGFILE}"; then
  error "Errors detected in wings --debug output:"
  echo "----------------------------------------------"
  cat "${LOGFILE}"
  echo "----------------------------------------------"
  kill "${WINGS_PID}" 2>/dev/null || true
  wait "${WINGS_PID}" 2>/dev/null || true
  rm -f "${LOGFILE}"
  error "Please check /etc/pterodactyl/config.yml and re-run the script."
  exit 1
fi

info "No errors found during the 10-second test. Stopping debug mode..."
kill "${WINGS_PID}" 2>/dev/null || true
wait "${WINGS_PID}" 2>/dev/null || true
rm -f "${LOGFILE}"

# ---------------------------------------------------------------------------
# 9) systemd service
# ---------------------------------------------------------------------------
echo
info "Creating wings.service..."
cat > /etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wings

echo
info "Wings service enabled and started."
sleep 2
systemctl status wings --no-pager || true

echo
echo "=============================================="
info "Installation complete! Wings should now be running for ${DOMAIN}."
echo "=============================================="
