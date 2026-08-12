#!/bin/bash
#
# ZeusLock agent — manual Linux install + config (single desktop / pilot).
# Installs the .deb, writes the managed config, and adds a desktop autostart entry.
#
#   Usage:  sudo bash install-zeus-agent.sh ./zeus-desktop-agent_amd64.deb
#
set -euo pipefail

# ============================ EDIT THESE TWO ============================
SERVER_URL="YOUR_SERVER_URL"     # e.g. https://api.zeuslock.ai
LICENSE_KEY="YOUR_LICENSE_KEY"   # zl_...
ZEUS_EXEC="zeus-ai-data-protection"   # launcher command (adjust if the .deb differs)
# =======================================================================

DEB="${1:?Usage: sudo bash install-zeus-agent.sh /path/to/zeus-desktop-agent.deb}"
if [[ $EUID -ne 0 ]]; then echo "Please run with sudo." >&2; exit 1; fi

echo "==> Installing $DEB"
apt-get install -y "$DEB" || { dpkg -i "$DEB"; apt-get install -f -y; }

echo "==> Writing managed config to /etc/zeuslock/agent.conf"
mkdir -p /etc/zeuslock
cat > /etc/zeuslock/agent.conf <<EOF
# ZeusLock agent — managed configuration (KEY=VALUE).
ServerUrl=$SERVER_URL
LicenseKey=$LICENSE_KEY
AgentEnabled=true
BlockingEnabled=true
NetworkMonitoring=true
FileMonitoring=true
EOF
chmod 644 /etc/zeuslock/agent.conf

echo "==> Adding desktop autostart entry"
cat > /etc/xdg/autostart/zeuslock-agent.desktop <<EOF
[Desktop Entry]
Type=Application
Name=ZeusLock Agent
Exec=$ZEUS_EXEC
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
chmod 644 /etc/xdg/autostart/zeuslock-agent.desktop

echo "==> Done. Log out/in (or launch 'Zeus - AI Data Protection' from the app menu)"
echo "    to start the agent in your desktop session."
