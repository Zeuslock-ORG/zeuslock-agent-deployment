#!/bin/bash
#
# ZeusLock agent: macOS removal (one Mac, or as an MDM script).
# Stops the agent, gives the network back (system proxy, Chrome/Edge/Brave proxy policy,
# Claude Code and Cursor settings: only values that still point at the agent), removes
# its certificate, its LaunchAgents, the app and its files. Run with sudo.
#
#   Usage:  sudo bash uninstall-zeuslock-agent.sh
#
# Remove the com.zeuslock.agent configuration profile in your MDM as well.
#
set -uo pipefail

APP_NAME="ZeusLock - AI Data Protection.app"
OLD_APP_NAME="Zeus - AI Data Protection.app"   # older bundle name
CONFIG_DIRS=("/Library/Application Support/ZeusLockDLP" "/Library/Application Support/ZeusDLP")
LAUNCH_AGENT="/Library/LaunchAgents/com.zeuslock.agent.plist"
LAUNCH_AGENT_LABEL="com.zeuslock.agent"
CLEANUP_JOB_LABEL="ai.zeuslock.proxy-cleanup"   # per-user safety-net job the agent adds
CA_NAMES=("ZeusLock DLP Proxy CA" "Zeus DLP Proxy CA")
BROWSER_IDS=("com.google.Chrome" "com.brave.Browser" "com.microsoft.Edge")
MANAGED_PREFS="${MANAGED_PREFS:-/Library/Managed Preferences}"
OWN_PROXY="127.0.0.1:9876"

# True when a browser policy plist points Chrome/Edge/Brave at the agent.
plist_points_at_agent() {
  local plist=$1 server
  [[ -f "$plist" ]] || return 1
  server=$(/usr/bin/plutil -extract ProxySettings.ProxyServer raw -o - "$plist" 2>/dev/null) || return 1
  [[ "$server" == *"$OWN_PROXY"* ]]
}

# Remove the agent's keys from a user's Claude Code or Cursor settings.json, only when
# they still point at the agent. A file that does not parse is left as it is.
# JavaScript for Automation (osascript): present on every Mac, no Python needed.
read -r -d '' JXA_RESTORE <<'JS' || true
function run(argv) {
  ObjC.import('Foundation');
  var path = argv[0], kind = argv[1], own = argv[2];
  var text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  if (text.isNil()) return 'unreadable';
  var data;
  try { data = JSON.parse(text.js); } catch (e) { return 'not JSON, left as is'; }
  if (!data || typeof data !== 'object') return 'unchanged';
  var changed = false;
  var isOwn = function (v) { return String(v || '').indexOf(own) !== -1; };
  if (kind === 'claude' && data.env && typeof data.env === 'object') {
    if (isOwn(data.env.HTTPS_PROXY)) { delete data.env.HTTPS_PROXY; changed = true; }
    if (String(data.env.NODE_EXTRA_CA_CERTS || '').toLowerCase().indexOf('zeuslock') !== -1) {
      delete data.env.NODE_EXTRA_CA_CERTS; changed = true;
    }
  }
  if (kind === 'cursor' && isOwn(data['http.proxy'])) { delete data['http.proxy']; changed = true; }
  if (!changed) return 'unchanged';
  $(JSON.stringify(data, null, 2) + '\n').writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
  return 'restored';
}
JS

# restore_tool_settings <file> <claude|cursor> [user]   (prints what it did)
# With a user, it runs as that user, so the file keeps its owner.
restore_tool_settings() {
  local file=$1 kind=$2 user=${3:-}
  [[ -f "$file" ]] || return 0
  if [[ -n "$user" ]]; then
    sudo -u "$user" /usr/bin/osascript -l JavaScript - "$file" "$kind" "$OWN_PROXY" <<<"$JXA_RESTORE" 2>/dev/null
  else
    /usr/bin/osascript -l JavaScript - "$file" "$kind" "$OWN_PROXY" <<<"$JXA_RESTORE" 2>/dev/null
  fi
}

# delete_certs <keychain> [user]: every certificate named like the agent's CA, by its
# SHA-1 (`security delete-certificate -c` refuses when two share a name). Prints the count.
delete_certs() {
  local keychain=$1 user=${2:-} ca hash count=0
  local -a sec
  if [[ -n "$user" ]]; then sec=(sudo -u "$user" security); else sec=(security); fi
  for ca in "${CA_NAMES[@]}"; do
    for hash in $("${sec[@]}" find-certificate -a -c "$ca" -Z "$keychain" 2>/dev/null | awk '/^SHA-1 hash:/{print $NF}'); do
      "${sec[@]}" delete-certificate -Z "$hash" "$keychain" >/dev/null 2>&1 && count=$((count + 1))
    done
  done
  echo "$count"
}

# Every network service: switch off a PAC or web proxy that points at the agent.
restore_system_proxy() {
  local service pac_url web_proxy secure_proxy
  networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while IFS= read -r service; do
    service="${service#\*}"
    [[ -n "$service" ]] || continue
    pac_url=$(networksetup -getautoproxyurl "$service" 2>/dev/null | awk -F': ' '/^URL/{print $2}')
    if [[ "$pac_url" == *"127.0.0.1"* || "$pac_url" == *"localhost"* ]]; then
      networksetup -setautoproxystate "$service" off 2>/dev/null || true
      networksetup -setautoproxyurl "$service" " " 2>/dev/null || true
      networksetup -setautoproxystate "$service" off 2>/dev/null || true
      echo "    $service: automatic proxy (PAC) switched off"
    fi
    web_proxy=$(networksetup -getwebproxy "$service" 2>/dev/null | awk -F': ' '/^Server/{print $2}')
    if [[ "$web_proxy" == "127.0.0.1" || "$web_proxy" == "localhost" ]]; then
      networksetup -setwebproxystate "$service" off 2>/dev/null || true
      echo "    $service: web proxy switched off"
    fi
    secure_proxy=$(networksetup -getsecurewebproxy "$service" 2>/dev/null | awk -F': ' '/^Server/{print $2}')
    if [[ "$secure_proxy" == "127.0.0.1" || "$secure_proxy" == "localhost" ]]; then
      networksetup -setsecurewebproxystate "$service" off 2>/dev/null || true
      echo "    $service: secure web proxy switched off"
    fi
  done
}

# One user's settings: browser proxy policy, Claude Code, Cursor, certificate, jobs, data.
restore_user() {
  local home=$1 user id result keychain
  user=$(/usr/bin/stat -f '%Su' "$home")
  id -u "$user" >/dev/null 2>&1 || return 0
  for id in "${BROWSER_IDS[@]}"; do
    if plist_points_at_agent "$home/Library/Preferences/$id.plist"; then
      sudo -u "$user" defaults delete "$id" ProxySettings 2>/dev/null || true
      sudo -u "$user" defaults delete "$id" QuicAllowed 2>/dev/null || true
      echo "    $user: $id proxy policy removed"
    fi
  done
  result=$(restore_tool_settings "$home/.claude/settings.json" claude "$user")
  if [[ "$result" == "restored" ]]; then echo "    $user: Claude Code settings restored"; fi
  result=$(restore_tool_settings "$home/Library/Application Support/Cursor/User/settings.json" cursor "$user")
  if [[ "$result" == "restored" ]]; then echo "    $user: Cursor settings restored"; fi
  keychain="$home/Library/Keychains/login.keychain-db"
  if [[ -f "$keychain" ]]; then
    result=$(delete_certs "$keychain" "$user")
    if [[ "$result" != 0 ]]; then echo "    $user: ZeusLock certificate removed from the login keychain"; fi
  fi
  rm -f "$home/Library/LaunchAgents/$CLEANUP_JOB_LABEL.plist"
  rm -rf "$home/Library/Application Support/ZeusLock DLP Agent" \
         "$home/Library/Application Support/Zeus DLP Agent"
  killall -u "$user" cfprefsd 2>/dev/null || true
}

main() {
  if [[ $EUID -ne 0 ]]; then echo "Please run with sudo." >&2; exit 1; fi
  local console_user console_uid="" name id home

  console_user=$(/usr/bin/stat -f '%Su' /dev/console)
  if [[ -n "$console_user" && "$console_user" != "root" && "$console_user" != "loginwindow" ]]; then
    console_uid=$(id -u "$console_user")
  fi

  echo "==> Stopping the ZeusLock agent"
  if [[ -n "$console_uid" ]]; then
    launchctl bootout "gui/$console_uid/$LAUNCH_AGENT_LABEL" 2>/dev/null || true
    launchctl bootout "gui/$console_uid/$CLEANUP_JOB_LABEL" 2>/dev/null || true
    # A clean quit gives the network back by itself (a managed Mac refuses it: then the
    # steps below do it).
    launchctl asuser "$console_uid" sudo -u "$console_user" \
      osascript -e 'tell application "ZeusLock - AI Data Protection" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do
      pgrep -f "/Applications/$APP_NAME/" >/dev/null 2>&1 || break
      sleep 1
    done
  fi
  rm -f "$LAUNCH_AGENT"
  for name in "$APP_NAME" "$OLD_APP_NAME"; do
    pkill -f "/Applications/$name/" 2>/dev/null || true
  done
  sleep 2
  for name in "$APP_NAME" "$OLD_APP_NAME"; do
    pkill -9 -f "/Applications/$name/" 2>/dev/null || true
  done

  echo "==> Restoring the network settings"
  restore_system_proxy
  for id in "${BROWSER_IDS[@]}"; do
    if plist_points_at_agent "$MANAGED_PREFS/$id.plist"; then
      rm -f "$MANAGED_PREFS/$id.plist"
      echo "    $MANAGED_PREFS/$id.plist removed"
    fi
  done
  for home in /Users/*; do
    [[ -d "$home/Library" && "$home" != "/Users/Shared" ]] || continue
    restore_user "$home"
  done
  killall cfprefsd 2>/dev/null || true

  echo "==> Removing the ZeusLock certificate from the System keychain"
  delete_certs /Library/Keychains/System.keychain >/dev/null

  echo "==> Removing the app and its files"
  rm -rf "/Applications/$APP_NAME" "/Applications/$OLD_APP_NAME"
  rm -rf "${CONFIG_DIRS[@]}"

  echo "==> Done. ZeusLock is removed and the network settings are restored."
  echo "    Restart open browsers. If this Mac uses a company proxy, your MDM re-applies it."
}

# Run only when executed, so the functions can be sourced and tested on their own.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
