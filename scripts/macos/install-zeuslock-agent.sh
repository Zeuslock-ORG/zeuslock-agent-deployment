#!/bin/bash
#
# ZeusLock agent — manual macOS install + config (single Mac / pilot).
# Mounts the downloaded .dmg, installs the app to /Applications, and writes the
# admin config file. Run with sudo.
#
#   Usage:  sudo bash install-zeuslock-agent.sh /path/to/ZeusLock.dmg
#
# The license key is a secret. Leave LICENSE_KEY below as the placeholder and the
# script asks for it (input hidden), so it never lands in this file, in your shell
# history or in a process list.
#
# Who can read the config: the agent runs in each user's login session (not as
# root), so it must be able to read config.json. The file is written root:staff
# 0640 (folder 0750): every local and mobile user account is in group staff, the
# system's daemon accounts (_www, nobody, ...) are not and cannot read the key.
#
set -euo pipefail

# ============================ EDIT THESE TWO ============================
SERVER_URL="YOUR_SERVER_URL"     # e.g. https://api.zeuslock.ai
LICENSE_KEY="YOUR_LICENSE_KEY"   # zl_...  (leave as is to be prompted, input hidden)
# =======================================================================

APP_NAME="ZeusLock - AI Data Protection.app"
OLD_APP_NAME="Zeus - AI Data Protection.app"   # name before 1.0.12 — removed on upgrade
CONFIG_DIR="/Library/Application Support/ZeusLockDLP"
CONFIG_GROUP="staff"

MOUNT=""
TMP_CONFIG=""
cleanup() {
  if [[ -n "$TMP_CONFIG" ]]; then rm -f "$TMP_CONFIG"; fi
  if [[ -n "$MOUNT" ]]; then hdiutil detach "$MOUNT" -quiet || true; fi
}
trap cleanup EXIT

die() { echo "ERROR: $*" >&2; exit 1; }

# A value goes inside a JSON string: refuse anything that could break it.
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

# write_config_json <dir> <owner> <group>
# Written to a 0600 temp file in the same folder, then given its final owner and
# mode and renamed into place: the key is never readable by anyone else, not even
# for a moment, and no copy is left behind.
write_config_json() {
  local dir=$1 owner=$2 group=$3
  mkdir -p "$dir"
  chown "$owner:$group" "$dir"
  chmod 0750 "$dir"
  TMP_CONFIG=$(umask 077 && mktemp "$dir/.config.json.XXXXXX")
  # printf is a shell builtin: the key is not passed on any command line.
  printf '{\n  "ServerUrl": "%s",\n  "LicenseKey": "%s"\n}\n' "$SERVER_URL" "$LICENSE_KEY" > "$TMP_CONFIG"
  chown "$owner:$group" "$TMP_CONFIG"
  chmod 0640 "$TMP_CONFIG"
  mv -f "$TMP_CONFIG" "$dir/config.json"
  TMP_CONFIG=""
}

main() {
  local dmg="${1:?Usage: sudo bash install-zeuslock-agent.sh /path/to/ZeusLock.dmg}"
  if [[ $EUID -ne 0 ]]; then echo "Please run with sudo." >&2; exit 1; fi
  read_values

  echo "==> Mounting $dmg"
  MOUNT=$(hdiutil attach "$dmg" -nobrowse -noverify | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)

  local src="$MOUNT/$APP_NAME"
  [[ -d "$src" ]] || die "Could not find '$APP_NAME' in the DMG."

  echo "==> Installing to /Applications"
  # Upgrade from a pre-1.0.12 install: the bundle was called "Zeus - AI Data
  # Protection.app". Quit it and remove it so only the new bundle remains
  # (bundle id com.zeuslock.desktop-agent is unchanged, so login-item / MDM
  # approvals carry over).
  if [[ -d "/Applications/$OLD_APP_NAME" ]]; then
    echo "==> Removing previous '$OLD_APP_NAME'"
    pkill -f "$OLD_APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$OLD_APP_NAME"
  fi
  rm -rf "/Applications/$APP_NAME"
  cp -R "$src" "/Applications/"

  echo "==> Writing config to $CONFIG_DIR/config.json (0640 root:$CONFIG_GROUP)"
  write_config_json "$CONFIG_DIR" root "$CONFIG_GROUP"

  # Upgrade from a pre-1.0.13 install: the admin config lived in ZeusDLP/. The
  # agent still reads it as a fallback, so remove it — one config file, one truth.
  rm -f "/Library/Application Support/ZeusDLP/config.json"
  rmdir "/Library/Application Support/ZeusDLP" 2>/dev/null || true

  echo "==> Done. Launch 'ZeusLock - AI Data Protection' from Applications and complete"
  echo "    any first-run approval prompts (login item, proxy trust)."
}

# Run only when executed, so the functions can be sourced and tested on their own.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
