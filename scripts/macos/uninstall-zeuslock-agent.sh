#!/bin/bash
#
# ZeusLock agent — manual macOS uninstall (single Mac / pilot).
# Quits the agent, restores the system proxy settings it managed, removes its
# trusted proxy certificate, and deletes the app and its files. Run with sudo.
#
#   Usage:  sudo bash uninstall-zeuslock-agent.sh
#
set -uo pipefail

APP_NAME="ZeusLock - AI Data Protection.app"
OLD_APP_NAME="Zeus - AI Data Protection.app"   # bundle name before 1.0.12
CONFIG_DIR="/Library/Application Support/ZeusLockDLP"
OLD_CONFIG_DIR="/Library/Application Support/ZeusDLP"
CA_NAMES=("ZeusLock DLP Proxy CA" "Zeus DLP Proxy CA")

if [[ $EUID -ne 0 ]]; then echo "Please run with sudo." >&2; exit 1; fi

echo "==> Quitting the ZeusLock agent"
# Ask nicely first so the agent restores the proxy settings itself on the way
# out; fall back to a kill if it does not exit.
osascript -e 'tell application "ZeusLock - AI Data Protection" to quit' >/dev/null 2>&1 || true
for _ in 1 2 3 4 5; do
  pgrep -f "$APP_NAME" >/dev/null 2>&1 || break
  sleep 1
done
pkill -f "$APP_NAME" 2>/dev/null || true
pkill -f "$OLD_APP_NAME" 2>/dev/null || true

# Even after a clean quit, belt-and-braces: make sure no network service is
# left pointing at the agent's local proxy (a leftover here breaks every
# connection the PAC used to route — the "PROXY 127.0.0.1:9876" errors).
echo "==> Restoring system proxy settings"
networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while IFS= read -r service; do
  service="${service#\*}"
  [[ -n "$service" ]] || continue
  pac_url=$(networksetup -getautoproxyurl "$service" 2>/dev/null | awk -F': ' '/^URL/{print $2}')
  if [[ "$pac_url" == *"127.0.0.1"* || "$pac_url" == *"localhost"* ]]; then
    networksetup -setautoproxystate "$service" off 2>/dev/null || true
    networksetup -setautoproxyurl "$service" " " 2>/dev/null || true
    networksetup -setautoproxystate "$service" off 2>/dev/null || true
  fi
  web_proxy=$(networksetup -getwebproxy "$service" 2>/dev/null | awk -F': ' '/^Server/{print $2}')
  if [[ "$web_proxy" == "127.0.0.1" || "$web_proxy" == "localhost" ]]; then
    networksetup -setwebproxystate "$service" off 2>/dev/null || true
  fi
  secure_proxy=$(networksetup -getsecurewebproxy "$service" 2>/dev/null | awk -F': ' '/^Server/{print $2}')
  if [[ "$secure_proxy" == "127.0.0.1" || "$secure_proxy" == "localhost" ]]; then
    networksetup -setsecurewebproxystate "$service" off 2>/dev/null || true
  fi
done

echo "==> Removing the ZeusLock proxy certificate from the System keychain"
for ca in "${CA_NAMES[@]}"; do
  while security find-certificate -c "$ca" /Library/Keychains/System.keychain >/dev/null 2>&1; do
    security delete-certificate -c "$ca" /Library/Keychains/System.keychain 2>/dev/null || break
  done
done

echo "==> Removing the app and its files"
rm -rf "/Applications/$APP_NAME" "/Applications/$OLD_APP_NAME"
rm -rf "$CONFIG_DIR" "$OLD_CONFIG_DIR"
# Per-user agent data (settings, logs, generated certificates)
for home in /Users/*; do
  [[ -d "$home/Library/Application Support" ]] || continue
  rm -rf "$home/Library/Application Support/ZeusLock DLP Agent" \
         "$home/Library/Application Support/Zeus DLP Agent" 2>/dev/null || true
done

echo "==> Done. ZeusLock has been removed and network settings are restored."
