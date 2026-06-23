#!/usr/bin/env bash
#
# vps-init.sh — New VPS setup wizard (Ubuntu 22.04 / 24.04)
# ------------------------------------------------------------
#  • Enable SSH password login (overrides cloud-init defaults)
#  • Permit root login (optional)
#  • Set/change an account password
#  • Change the SSH port (handles socket activation on Ubuntu 24)
#  • Install & configure fail2ban to protect SSH from brute-force
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/haydary1986/vps-init/main/setup.sh | sudo bash
#   sudo bash <(curl -fsSL https://raw.githubusercontent.com/haydary1986/vps-init/main/setup.sh)
#
set -euo pipefail

# ─────────────────────────── colors ───────────────────────────
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; CYN=""; RST=""
fi
info() { printf "%s\n" "${CYN}->${RST} $*"; }
ok()   { printf "%s\n" "${GRN}[OK]${RST} $*"; }
warn() { printf "%s\n" "${YLW}[!]${RST} $*"; }
err()  { printf "%s\n" "${RED}[x]${RST} $*" >&2; }
hr()   { printf "%s\n" "${DIM}----------------------------------------------${RST}"; }

# ─────────────────────────── require root ───────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  err "This script must run as root."
  err "Re-run as:  curl -fsSL <URL> | sudo bash"
  exit 1
fi

# ─────────────────────────── interactive input from the terminal ───────────────────────────
# When invoked via (curl | bash), stdin is the script itself,
# so we read user input directly from /dev/tty.
if [ -r /dev/tty ]; then
  INTERACTIVE=1
else
  INTERACTIVE=0
  warn "No interactive terminal detected — using defaults automatically."
fi

ask() {  # ask "Question" "default"  -> prints the answer
  local prompt="$1" def="${2:-}" ans=""
  if [ "$INTERACTIVE" -eq 1 ]; then
    if [ -n "$def" ]; then printf "%s" "${BOLD}${prompt}${RST} [${def}]: " > /dev/tty
    else                   printf "%s" "${BOLD}${prompt}${RST}: " > /dev/tty; fi
    read -r ans < /dev/tty || ans=""
  fi
  printf "%s" "${ans:-$def}"
}

ask_yn() {  # ask_yn "Question" "Y|N"  -> 0=yes 1=no
  local prompt="$1" def="${2:-Y}" ans="" hint="[Y/n]"
  [ "$def" = "N" ] && hint="[y/N]"
  if [ "$INTERACTIVE" -eq 1 ]; then
    printf "%s" "${BOLD}${prompt}${RST} ${hint}: " > /dev/tty
    read -r ans < /dev/tty || ans=""
  fi
  ans="${ans:-$def}"
  case "$ans" in [Yy]|[Yy][Ee][Ss]) return 0 ;; *) return 1 ;; esac
}

ask_pw() {  # ask_pw "Label"  -> prints the password (silent input)
  local prompt="$1" pw=""
  printf "%s" "${BOLD}${prompt}${RST}: " > /dev/tty
  read -rs pw < /dev/tty || pw=""
  printf "\n" > /dev/tty
  printf "%s" "$pw"
}

# ─────────────────────────── banner ───────────────────────────
hr
printf "%s\n" "${BOLD}   VPS Setup Wizard  --  SSH + fail2ban${RST}"
hr

# detect OS
OS_NAME="unknown"; OS_VER=""
if [ -r /etc/os-release ]; then . /etc/os-release; OS_NAME="${ID:-?}"; OS_VER="${VERSION_ID:-?}"; fi
info "Detected OS: ${BOLD}${OS_NAME} ${OS_VER}${RST}"
if [ "$OS_NAME" != "ubuntu" ] && [ "$OS_NAME" != "debian" ]; then
  warn "This script is tuned for Ubuntu/Debian. Continue at your own risk."
fi
CUR_PORT="$(grep -RhiE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
CUR_PORT="${CUR_PORT:-22}"
echo

# ─────────────────────────── collect options (wizard) ───────────────────────────
info "${BOLD}Step 1/5 — SSH authentication${RST}"
if ask_yn "Enable password login (PasswordAuthentication)?" "Y"; then PW_AUTH="yes"; else PW_AUTH="no"; fi
if ask_yn "Permit root login over SSH (PermitRootLogin)?" "Y";   then ROOT_LOGIN="yes"; else ROOT_LOGIN="no"; fi
echo

info "${BOLD}Step 2/5 — Password${RST}"
SET_PW=0; PW_USER=""
if [ "$INTERACTIVE" -eq 1 ] && ask_yn "Set/change an account password now?" "Y"; then
  PW_USER="$(ask "Username" "root")"
  SET_PW=1
fi
echo

info "${BOLD}Step 3/5 — SSH port${RST}"
SSH_PORT="$CUR_PORT"
if ask_yn "Change the SSH port (current: ${CUR_PORT})?" "N"; then
  SSH_PORT="$(ask "New port" "2222")"
fi
echo

info "${BOLD}Step 4/5 — fail2ban${RST}"
INSTALL_F2B=0; F2B_MAXRETRY="5"; F2B_BANTIME="1h"; F2B_FINDTIME="10m"; F2B_IGNOREIP=""
if ask_yn "Install and configure fail2ban to protect SSH?" "Y"; then
  INSTALL_F2B=1
  if [ "$INTERACTIVE" -eq 1 ]; then
    F2B_MAXRETRY="$(ask "Failed attempts before ban (maxretry)" "5")"
    F2B_BANTIME="$(ask  "Ban duration (bantime, e.g. 1h / 1d / -1 permanent)" "1h")"
    F2B_FINDTIME="$(ask "Counting window (findtime)" "10m")"
    F2B_IGNOREIP="$(ask "Trusted IP to whitelist (optional, blank=none)" "")"
  fi
fi
echo

info "${BOLD}Step 5/5 — Review${RST}"
hr
printf "  %-26s %s\n" "Password login:" "$PW_AUTH"
printf "  %-26s %s\n" "Root login:"     "$ROOT_LOGIN"
printf "  %-26s %s\n" "SSH port:"       "$SSH_PORT"
if [ "$SET_PW" -eq 1 ]; then printf "  %-26s %s\n" "Set password for:" "$PW_USER"; fi
if [ "$INSTALL_F2B" -eq 1 ]; then
  printf "  %-26s %s\n" "fail2ban:" "yes (maxretry=$F2B_MAXRETRY, bantime=$F2B_BANTIME, findtime=$F2B_FINDTIME)"
  [ -n "$F2B_IGNOREIP" ] && printf "  %-26s %s\n" "Whitelisted IP:" "$F2B_IGNOREIP"
else
  printf "  %-26s %s\n" "fail2ban:" "no"
fi
hr
if ! ask_yn "Apply the settings above?" "Y"; then err "Aborted. No changes were made."; exit 0; fi
echo

# ═══════════════════════════ apply ═══════════════════════════
SSHD_MAIN="/etc/ssh/sshd_config"
DROPIN_DIR="/etc/ssh/sshd_config.d"
OURFILE="${DROPIN_DIR}/00-vps-init.conf"
STAMP="$(date +%Y%m%d-%H%M%S)"

# ensure openssh-server is present (minimal LXC/Proxmox containers may lack it)
if ! command -v sshd >/dev/null 2>&1; then
  warn "openssh-server is not installed — installing it..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || warn "apt-get update failed — continuing."
  apt-get install -y -qq openssh-server
  systemctl enable ssh >/dev/null 2>&1 || true
fi

# backup (if the file exists)
[ -f "$SSHD_MAIN" ] && { cp -a "$SSHD_MAIN" "${SSHD_MAIN}.vps-init.bak.${STAMP}"; info "Backup: ${SSHD_MAIN}.vps-init.bak.${STAMP}"; }

# neutralize conflicting directives in the main config and cloud-init files (top cause of failure)
KEYS="PasswordAuthentication PermitRootLogin KbdInteractiveAuthentication ChallengeResponseAuthentication"
neutralize() {  # comment out active directives in a file
  local f="$1" k
  for k in $KEYS; do
    sed -i -E "s/^([[:space:]]*)(${k}[[:space:]])/\1# [vps-init] \2/I" "$f" 2>/dev/null || true
  done
}
neutralize "$SSHD_MAIN"
mkdir -p "$DROPIN_DIR"
shopt -s nullglob
for f in "$DROPIN_DIR"/*.conf; do
  [ "$f" = "$OURFILE" ] && continue
  neutralize "$f"
done
shopt -u nullglob

# write the authoritative drop-in (read first -> its value wins)
{
  echo "# Managed by vps-init.sh — ${STAMP}"
  echo "PasswordAuthentication ${PW_AUTH}"
  echo "PermitRootLogin ${ROOT_LOGIN}"
  echo "KbdInteractiveAuthentication no"
  echo "UsePAM yes"
  echo "Port ${SSH_PORT}"
} > "$OURFILE"
chmod 644 "$OURFILE"
ok "Wrote SSH settings to ${OURFILE}"

# SSH port via socket activation (Ubuntu 22.10+/24.04: port lives in ssh.socket, not sshd_config)
if [ "$SSH_PORT" != "22" ] && systemctl cat ssh.socket >/dev/null 2>&1; then
  mkdir -p /etc/systemd/system/ssh.socket.d
  {
    echo "[Socket]"
    echo "ListenStream="
    echo "ListenStream=${SSH_PORT}"
  } > /etc/systemd/system/ssh.socket.d/override.conf
  ok "Configured port ${SSH_PORT} via ssh.socket."
fi

# open the port in the firewall (if ufw is active)
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "${SSH_PORT}/tcp" >/dev/null 2>&1 || true
  ok "Opened port ${SSH_PORT}/tcp in ufw."
fi

# validate config before restart (prevents locking yourself out)
if ! sshd -t; then
  err "SSH config validation failed — service NOT restarted. Backup left intact."
  exit 1
fi
ok "sshd -t validation passed."

# restart (handles socket activation)
systemctl daemon-reload
systemctl restart ssh.socket 2>/dev/null || true
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
ok "SSH service restarted."

# set password
if [ "$SET_PW" -eq 1 ] && [ -n "$PW_USER" ]; then
  if ! id "$PW_USER" >/dev/null 2>&1; then
    warn "User '$PW_USER' does not exist — creating it."
    useradd -m -s /bin/bash "$PW_USER"
  fi
  while :; do
    P1="$(ask_pw "Password for ${PW_USER}")"
    P2="$(ask_pw "Repeat the password")"
    [ -z "$P1" ] && { warn "Empty password, try again."; continue; }
    [ "$P1" != "$P2" ] && { warn "Passwords do not match, try again."; continue; }
    break
  done
  echo "${PW_USER}:${P1}" | chpasswd && ok "Password set for ${PW_USER}." || err "Failed to set password."
  unset P1 P2
fi

# install & configure fail2ban
if [ "$INSTALL_F2B" -eq 1 ]; then
  info "Installing fail2ban..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || warn "apt-get update failed — continuing with cached packages."
  apt-get install -y -qq fail2ban
  IGNORE_LINE="ignoreip = 127.0.0.1/8 ::1"
  [ -n "$F2B_IGNOREIP" ] && IGNORE_LINE="ignoreip = 127.0.0.1/8 ::1 ${F2B_IGNOREIP}"
  cat > /etc/fail2ban/jail.local <<EOF
# Managed by vps-init.sh — ${STAMP}
[DEFAULT]
backend          = systemd
${IGNORE_LINE}
bantime          = ${F2B_BANTIME}
findtime         = ${F2B_FINDTIME}
maxretry         = ${F2B_MAXRETRY}
bantime.increment = true

[sshd]
enabled = true
port    = ${SSH_PORT}
EOF
  systemctl enable fail2ban >/dev/null 2>&1 || true
  systemctl restart fail2ban
  sleep 1
  ok "fail2ban installed and enabled."
fi

# ═══════════════════════════ final summary ═══════════════════════════
echo
hr
printf "%s\n" "${BOLD}   Setup complete${RST}"
hr
info "Effective SSH settings:"
sshd -T 2>/dev/null | grep -Ei "^(passwordauthentication|permitrootlogin|port|kbdinteractiveauthentication) " | sed 's/^/    /' || true
if [ "$INSTALL_F2B" -eq 1 ]; then
  echo
  info "fail2ban status (sshd):"
  fail2ban-client status sshd 2>/dev/null | sed 's/^/    /' || warn "Could not read fail2ban status."
fi
echo
warn "${BOLD}Important:${RST} do NOT close your current session before testing login in a new window."
if [ "$SSH_PORT" != "22" ]; then
  warn "Port changed — connect now with:  ssh -p ${SSH_PORT} user@server-address"
fi
hr
