#!/bin/bash
#
# ZeusLock agent — manual macOS install + config (single Mac / pilot).
# Mounts the downloaded .dmg, installs the app to /Applications, and writes the
# admin config file. Run with sudo.
#
#   Usage:  sudo bash install-zeus-agent.sh /path/to/ZeusLock.dmg
#
set -euo pipefail

# ============================ EDIT THESE TWO ============================
SERVER_URL="YOUR_SERVER_URL"     # e.g. https://api.zeuslock.ai
LICENSE_KEY="YOUR_LICENSE_KEY"   # zl_...
# =======================================================================

DMG="${1:?Usage: sudo bash install-zeus-agent.sh /path/to/ZeusLock.dmg}"
APP_NAME="Zeus - AI Data Protection.app"
CONFIG_DIR="/Library/Application Support/ZeusDLP"

if [[ $EUID -ne 0 ]]; then echo "Please run with sudo." >&2; exit 1; fi

echo "==> Mounting $DMG"
MOUNT=$(hdiutil attach "$DMG" -nobrowse -noverify | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
trap '[[ -n "${MOUNT:-}" ]] && hdiutil detach "$MOUNT" -quiet || true' EXIT

SRC="$MOUNT/$APP_NAME"
[[ -d "$SRC" ]] || { echo "Could not find '$APP_NAME' in the DMG." >&2; exit 1; }

echo "==> Installing to /Applications"
rm -rf "/Applications/$APP_NAME"
cp -R "$SRC" "/Applications/"

echo "==> Writing config to $CONFIG_DIR/config.json"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/config.json" <<EOF
{
  "ServerUrl": "$SERVER_URL",
  "LicenseKey": "$LICENSE_KEY"
}
EOF
chmod 644 "$CONFIG_DIR/config.json"

echo "==> Done. Launch 'Zeus - AI Data Protection' from Applications and complete"
echo "    any first-run approval prompts (login item, proxy trust)."
