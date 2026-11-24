#!/bin/bash
#
# ZeusLock agent: Linux removal (one desktop; run it with Ansible `script:` for a fleet).
# Removes the package, its configuration, and the certificate trust the agent added for
# the system store, Chrome/Chromium/Brave and Firefox. Run with sudo.
#
#   Usage:  sudo bash uninstall-zeuslock-agent.sh
#
# Network: removing the package stops every running agent and gives each signed-in
# user's GNOME proxy, Claude Code and Cursor settings back. Users who are not signed in
# get the same at their next login, from the small per-user job the agent left in their
# data folder (~/.config/ZeusLock DLP Agent): this script leaves those folders in place
# for that reason. The job removes itself once it has run.
#
set -uo pipefail

PACKAGE="zeuslock-desktop-agent"
CONFIG_DIRS=("/etc/zeuslock" "/etc/zeuslock-dlp" "/etc/zeus-dlp")
CA_FILES=("/usr/local/share/ca-certificates/zeuslock-dlp-ca.crt"
          "/usr/local/share/ca-certificates/zeus-dlp-ca.crt")
BROWSER_POLICY_FILES=("/etc/chromium-browser/policies/managed/zeuslock-dlp-ca.json"
                      "/etc/chromium-browser/policies/managed/zeus-dlp-ca.json"
                      "/etc/opt/chrome/policies/managed/zeuslock-dlp-ca.json"
                      "/etc/brave/policies/managed/zeuslock-dlp-ca.json")
FIREFOX_POLICY="${FIREFOX_POLICY:-/etc/firefox/policies/policies.json}"
FIREFOX_CA="$(dirname "$FIREFOX_POLICY")/zeuslock-dlp-ca.crt"

# Firefox: take only the ZeusLock certificate out of Certificates.Install. Every other
# policy stays. The file is deleted when ZeusLock was the only thing in it.
remove_firefox_policy_entry() {
  local policy=$1 ca=$2
  [[ -f "$policy" ]] || return 0
  if ! command -v python3 >/dev/null 2>&1; then
    echo "    python3 not found: remove the line with $ca from $policy by hand"
    return 0
  fi
  python3 - "$policy" "$ca" <<'PY'
import json, os, sys
path, ca = sys.argv[1], sys.argv[2]
try:
    doc = json.load(open(path))
except Exception as error:
    print("    %s is not valid JSON, left untouched (%s)" % (path, error))
    sys.exit(0)
pol = doc.get("policies") if isinstance(doc, dict) else None
certs = pol.get("Certificates") if isinstance(pol, dict) else None
inst = certs.get("Install") if isinstance(certs, dict) else None
if not isinstance(inst, list) or ca not in inst:
    sys.exit(0)
inst[:] = [c for c in inst if c != ca]
if not inst:
    certs.pop("Install")
if not certs:
    pol.pop("Certificates")
if not pol and len(doc) == 1:
    os.remove(path)
    print("    removed %s (ZeusLock was its only policy)" % path)
    sys.exit(0)
tmp = path + ".zl-tmp"
with open(tmp, "w") as out:
    json.dump(doc, out, indent=2)
    out.write("\n")
os.chmod(tmp, 0o644)
os.replace(tmp, path)
print("    removed the ZeusLock certificate from %s" % path)
PY
}

main() {
  if [[ $EUID -ne 0 ]]; then echo "Please run with sudo." >&2; exit 1; fi

  echo "==> Removing the package"
  if dpkg-query -W -f='${Status}' "$PACKAGE" 2>/dev/null | grep -q "install ok installed"; then
    DEBIAN_FRONTEND=noninteractive apt-get remove -y "$PACKAGE"
  else
    echo "    $PACKAGE is not installed"
  fi

  echo "==> Removing the configuration"
  local dir
  for dir in "${CONFIG_DIRS[@]}"; do
    rm -f "$dir/agent.conf" "$dir/config.json"
    rmdir "$dir" 2>/dev/null || true
  done

  echo "==> Removing the certificate trust"
  local file ca_removed=0
  for file in "${CA_FILES[@]}"; do
    if [[ -f "$file" ]]; then rm -f "$file"; ca_removed=1; fi
  done
  if [[ "$ca_removed" == 1 ]] && command -v update-ca-certificates >/dev/null 2>&1; then
    update-ca-certificates --fresh >/dev/null
  fi
  rm -f "${BROWSER_POLICY_FILES[@]}"
  remove_firefox_policy_entry "$FIREFOX_POLICY" "$FIREFOX_CA"
  rm -f "$FIREFOX_CA"

  echo "==> Done. ZeusLock is removed. Restart open browsers. The group 'zeuslock'"
  echo "    is kept; remove it with: sudo groupdel zeuslock"
}

# Run only when executed, so the functions can be sourced and tested on their own.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
