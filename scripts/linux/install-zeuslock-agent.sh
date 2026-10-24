#!/bin/bash
#
# ZeusLock agent — manual Linux install + config (single desktop / pilot).
# Installs the .deb, writes the managed config, and adds a desktop autostart entry.
#
#   Usage:  sudo bash install-zeuslock-agent.sh ./zeuslock-desktop-agent_amd64.deb
#
# The license key is a secret. Leave LICENSE_KEY below as the placeholder and the
# script asks for it (input hidden), so it never lands in this file, in your shell
# history or in a process list.
#
# Who can read the config: the agent runs in each user's desktop session (not as
# root), so it must be able to read /etc/zeuslock/agent.conf. The file is written
# root:<CONFIG_GROUP> 0640 (directory 0750) and the local login accounts are added
# to that group — system and service accounts cannot read it. Users added later
# need `sudo usermod -aG zeuslock <user>` (see docs/03-linux.md).
#
set -euo pipefail

# ============================ EDIT THESE ============================
SERVER_URL="YOUR_SERVER_URL"     # e.g. https://api.zeuslock.ai
LICENSE_KEY="YOUR_LICENSE_KEY"   # zl_...  (leave as is to be prompted, input hidden)
ZEUS_EXEC="zeuslock-ai-data-protection"   # launcher command (1.0.12+; was zeus-ai-data-protection)
CONFIG_GROUP="zeuslock"          # group allowed to read the config; may be an existing
                                 # directory (SSSD/AD) group that holds your desktop users
# ====================================================================

CONFIG_FILE="/etc/zeuslock/agent.conf"
# JSON fallbacks the agent also reads; not written here, but tightened if present.
JSON_FALLBACKS=("/etc/zeuslock-dlp/config.json" "/etc/zeus-dlp/config.json")

TMP_CONFIG=""
cleanup() { if [[ -n "$TMP_CONFIG" ]]; then rm -f "$TMP_CONFIG"; fi; }
trap cleanup EXIT

die() { echo "ERROR: $*" >&2; exit 1; }

# A value goes on one KEY=VALUE line: refuse anything that could break the line
# or smuggle in another key.
check_value() {
  local name=$1 value=$2
  [[ -n "$value" ]] || die "$name is empty."
  [[ "$value" != *[[:space:]\"\'\\]* ]] || die "$name contains whitespace, a quote or a backslash."
}

read_values() {
  if [[ "$SERVER_URL" == "YOUR_SERVER_URL" ]]; then
    [[ -t 0 ]] || die "Set SERVER_URL at the top of the script (no terminal to prompt on)."
    read -r -p "Server URL (e.g. https://api.zeuslock.ai): " SERVER_URL
  fi
  if [[ "$LICENSE_KEY" == "YOUR_LICENSE_KEY" ]]; then
    [[ -t 0 ]] || die "Set LICENSE_KEY at the top of the script (no terminal to prompt on)."
    read -r -s -p "License key (input hidden): " LICENSE_KEY
    echo
  fi
  check_value SERVER_URL "$SERVER_URL"
  check_value LICENSE_KEY "$LICENSE_KEY"
}

# Local login accounts: UID_MIN..UID_MAX from /etc/login.defs, with a real shell.
local_login_users() {
  local uid_min uid_max
  uid_min=$(awk '$1 == "UID_MIN" {print $2}' /etc/login.defs 2>/dev/null || true)
  uid_max=$(awk '$1 == "UID_MAX" {print $2}' /etc/login.defs 2>/dev/null || true)
  awk -F: -v min="${uid_min:-1000}" -v max="${uid_max:-60000}" \
    '$3 >= min && $3 <= max && $7 !~ /(nologin|false)$/ {print $1}' /etc/passwd
}

# The group that may read the config. A local group is created if needed and the
# local login accounts are added; a directory group (SSSD/AD) is used as is.
ensure_config_group() {
  local group=$1 user
  if ! getent group "$group" >/dev/null; then
    groupadd --system "$group"
    echo "    created group '$group'"
  fi
  if grep -q "^${group}:" /etc/group; then
    while IFS= read -r user; do
      [[ -n "$user" ]] || continue
      if id -nG "$user" | tr ' ' '\n' | grep -qx "$group"; then continue; fi
      usermod -aG "$group" "$user"
      echo "    added '$user' to '$group' (takes effect at their next login)"
    done < <(local_login_users)
  else
    echo "    '$group' is a directory group: membership is managed by your directory"
  fi
}

# write_agent_conf <file> <owner> <group>
# Written to a 0600 temp file in the same directory, then given its final owner and
# mode and renamed into place: the key is never readable by anyone else, not even
# for a moment, and no copy is left behind.
write_agent_conf() {
  local file=$1 owner=$2 group=$3 dir
  dir=$(dirname "$file")
  mkdir -p "$dir"
  chown "$owner:$group" "$dir"
  chmod 0750 "$dir"
  TMP_CONFIG=$(umask 077 && mktemp "$dir/.agent.conf.XXXXXX")
  # printf is a shell builtin: the key is not passed on any command line.
  printf '%s\n' \
    "# ZeusLock agent — managed configuration (KEY=VALUE)." \
    "# root:$group 0640 — contains the organisation license key." \
    "ServerUrl=$SERVER_URL" \
    "LicenseKey=$LICENSE_KEY" \
    "AgentEnabled=true" \
    "BlockingEnabled=true" \
    "NetworkMonitoring=true" \
    "FileMonitoring=true" > "$TMP_CONFIG"
  chown "$owner:$group" "$TMP_CONFIG"
  chmod 0640 "$TMP_CONFIG"
  mv -f "$TMP_CONFIG" "$file"
  TMP_CONFIG=""
}

# Older installs may carry a world-readable JSON fallback holding the key.
tighten_json_fallbacks() {
  local owner=$1 group=$2 file
  for file in "${JSON_FALLBACKS[@]}"; do
    [[ -f "$file" ]] || continue
    chown "$owner:$group" "$file" "$(dirname "$file")"
    chmod 0640 "$file"
    chmod 0750 "$(dirname "$file")"
    echo "    tightened $file to 0640 $owner:$group"
  done
}

main() {
  local deb="${1:?Usage: sudo bash install-zeuslock-agent.sh /path/to/zeuslock-desktop-agent.deb}"
  if [[ $EUID -ne 0 ]]; then echo "Please run with sudo." >&2; exit 1; fi
  read_values

  echo "==> Installing $deb"
  apt-get install -y "$deb" || { dpkg -i "$deb"; apt-get install -f -y; }

  echo "==> Config reader group '$CONFIG_GROUP'"
  ensure_config_group "$CONFIG_GROUP"

  echo "==> Writing managed config to $CONFIG_FILE (0640 root:$CONFIG_GROUP)"
  write_agent_conf "$CONFIG_FILE" root "$CONFIG_GROUP"
  tighten_json_fallbacks root "$CONFIG_GROUP"

  echo "==> Adding desktop autostart entry"
  mkdir -p /etc/xdg/autostart
  cat > /etc/xdg/autostart/zeuslock-agent.desktop <<EOF
[Desktop Entry]
Type=Application
Name=ZeusLock Agent
Exec=$ZEUS_EXEC
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
  chmod 644 /etc/xdg/autostart/zeuslock-agent.desktop

  echo "==> Done. Log out/in (needed for the new group membership), then the agent"
  echo "    starts in your desktop session ('ZeusLock - AI Data Protection')."
}

# Run only when executed, so the functions can be sourced and tested on their own.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
