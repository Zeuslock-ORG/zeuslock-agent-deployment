#!/bin/bash
#
# ZeusLock agent: start at login on macOS.
# The app does not register a login item of its own, so the deployment adds this
# LaunchAgent: it starts the agent in every user's session at login, and starts it now
# for the user who is signed in. Run it as root after the app is installed: as an MDM
# script (Jamf "After" priority, Kandji/Mosyle custom script, Intune shell script), or
# by hand with sudo. install-zeuslock-agent.sh runs it for you.
#
#   Usage:  sudo bash install-launchagent.sh
#
set -euo pipefail

APP_PATH="${APP_PATH:-/Applications/ZeusLock - AI Data Protection.app}"
PLIST_PATH="${PLIST_PATH:-/Library/LaunchAgents/com.zeuslock.agent.plist}"
LABEL="com.zeuslock.agent"

# write_launchagent <plist path> <app path>
write_launchagent() {
  local plist=$1 app=$2
  mkdir -p "$(dirname "$plist")"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>$app</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
PLIST
  chmod 644 "$plist"
  /usr/bin/plutil -lint "$plist" >/dev/null
}

# Start it now for the user at the screen, if any (otherwise at their next login).
load_for_console_user() {
  local plist=$1 user uid
  user=$(/usr/bin/stat -f '%Su' /dev/console)
  if [[ -z "$user" || "$user" == "root" || "$user" == "loginwindow" ]]; then
    echo "==> Nobody is signed in: the agent starts at the next login."
    return 0
  fi
  uid=$(/usr/bin/id -u "$user")
  /bin/launchctl bootout "gui/$uid" "$plist" 2>/dev/null || true
  /bin/launchctl bootstrap "gui/$uid" "$plist"
  /bin/launchctl kickstart "gui/$uid/$LABEL" 2>/dev/null || true
  echo "==> Started for $user."
}

main() {
  if [[ $EUID -ne 0 ]]; then echo "Please run with sudo." >&2; exit 1; fi
  [[ -d "$APP_PATH" ]] || { echo "ERROR: $APP_PATH is not installed." >&2; exit 1; }
  write_launchagent "$PLIST_PATH" "$APP_PATH"
  chown root:wheel "$PLIST_PATH"
  echo "==> LaunchAgent written: $PLIST_PATH"
  load_for_console_user "$PLIST_PATH"
}

# Run only when executed, so the functions can be sourced and tested on their own.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
