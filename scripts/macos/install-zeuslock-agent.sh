#!/bin/bash
#
# ZeusLock agent: macOS install + config (one Mac, or a pilot before the MDM rollout).
# Installs or upgrades the app from the downloaded .pkg or .dmg, writes the admin config
# file, and adds the start-at-login LaunchAgent (install-launchagent.sh, next to this
# script). Apple silicon Macs. Run with sudo.
#
#   Usage:  sudo bash install-zeuslock-agent.sh /path/to/ZeusLock-<version>-arm64.pkg
#           sudo bash install-zeuslock-agent.sh /path/to/ZeusLock-<version>-arm64.dmg
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
OLD_APP_NAME="Zeus - AI Data Protection.app"   # older bundle name, removed if present
CONFIG_DIR="${CONFIG_DIR:-/Library/Application Support/ZeusLockDLP}"
CONFIG_GROUP="staff"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# A running agent (an upgrade) is stopped before its files are replaced. On a managed
# Mac the agent refuses to quit, so it is ended; it starts again from the LaunchAgent.
stop_running_agent() {
  local name
  for name in "$APP_NAME" "$OLD_APP_NAME"; do
    pgrep -f "/Applications/$name/" >/dev/null 2>&1 || continue
    echo "==> Stopping the running agent ($name)"
    pkill -f "/Applications/$name/" 2>/dev/null || true
    sleep 2
    pkill -9 -f "/Applications/$name/" 2>/dev/null || true
  done
}

install_app() {
  local installer_file=$1
  case "$installer_file" in
    *.pkg)
      echo "==> Installing $installer_file"
      installer -pkg "$installer_file" -target / ;;
    *.dmg)
      echo "==> Mounting $installer_file"
      MOUNT=$(hdiutil attach "$installer_file" -nobrowse -noverify | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
      [[ -d "$MOUNT/$APP_NAME" ]] || die "Could not find '$APP_NAME' in the DMG."
      echo "==> Copying the app to /Applications"
      rm -rf "/Applications/$APP_NAME"
      cp -R "$MOUNT/$APP_NAME" "/Applications/" ;;
    *)
      die "Expected a .pkg or a .dmg: $installer_file" ;;
  esac
  [[ -d "/Applications/$APP_NAME" ]] || die "The app is not in /Applications after the install."
  if [[ -d "/Applications/$OLD_APP_NAME" ]]; then
    echo "==> Removing the old '$OLD_APP_NAME'"
    rm -rf "/Applications/$OLD_APP_NAME"
  fi
}

main() {
  local installer_file="${1:?Usage: sudo bash install-zeuslock-agent.sh /path/to/ZeusLock-<version>-arm64.pkg (or .dmg)}"
  if [[ $EUID -ne 0 ]]; then echo "Please run with sudo." >&2; exit 1; fi
  [[ -f "$installer_file" ]] || die "No such file: $installer_file"
  [[ -f "$SCRIPT_DIR/install-launchagent.sh" ]] || die "install-launchagent.sh must sit next to this script."
  read_values

  stop_running_agent
  install_app "$installer_file"

  echo "==> Writing config to $CONFIG_DIR/config.json (0640 root:$CONFIG_GROUP)"
  write_config_json "$CONFIG_DIR" root "$CONFIG_GROUP"
  # An older admin config path is still read as a fallback: one config file only.
  rm -f "/Library/Application Support/ZeusDLP/config.json"
  rmdir "/Library/Application Support/ZeusDLP" 2>/dev/null || true

  bash "$SCRIPT_DIR/install-launchagent.sh"

  echo "==> Done. At its first start the agent asks to trust its certificate: approve it"
  echo "    with your password. The menu bar icon then shows 'Protection active'."
}

# Run only when executed, so the functions can be sourced and tested on their own.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
