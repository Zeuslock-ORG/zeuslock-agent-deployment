# Verify & Troubleshoot

How to confirm an endpoint is genuinely protected — and how to fix it when it
isn't. Applies to all platforms.

---

## The four checks (every platform)

An endpoint is protected only when **all four** pass. Run them on a target machine
**with a user logged into the desktop** (the agent runs in the user session).

### 1. Installed
| OS | Command | Expect |
|----|---------|--------|
| Windows | `Get-Package -Name "*Zeus*"` | the agent + version |
| macOS | `ls -d "/Applications/ZeusLock - AI Data Protection.app"` | the app path |
| Linux | `dpkg -l \| grep -i zeus` | the package |

### 2. Configured (Server URL + license key delivered)
| OS | Command | Expect |
|----|---------|--------|
| Windows | `reg query "HKLM\SOFTWARE\Policies\ZeusLock"` | `ServerUrl` + `LicenseKey` |
| macOS | `sudo defaults read /Library/Managed\ Preferences/com.zeuslock.agent` | `ServerUrl` + `LicenseKey` |
| Linux | `sudo cat /etc/zeuslock/agent.conf` | `ServerUrl` + `LicenseKey` |

(If you used the JSON fallback instead: Windows `C:\ProgramData\ZeusLockDLP\config.json`,
macOS `/Library/Application Support/ZeusLockDLP/config.json`, Linux `/etc/zeuslock-dlp/config.json`.)

### 3. Running + inspection proxy up
| OS | Command | Expect |
|----|---------|--------|
| Windows | `Get-Process *Zeus*` ; `Get-NetTCPConnection -LocalPort 9876 -State Listen` | process + listener |
| macOS | `pgrep -fl "ZeusLock - AI Data Protection"` ; `lsof -iTCP:9876 -sTCP:LISTEN` | process + listener |
| Linux | `pgrep -fa zeus` ; `ss -ltnp \| grep 9876` | process + listener |

The agent UI should read **"Protection active"** for the logged-in user.

### 4. Live DLP test
As a normal user, open the browser → **chatgpt.com** → paste a test secret such as
`4111 1111 1111 1111`. The agent should flag/block it, and a matching **incident**
should appear under **Incidents** in your dashboard within a few seconds.

> **Block vs. alert:** whether a data type is *blocked* or merely *alerted* is set
> by your **policy in the dashboard**, not on the endpoint. If a paste is logged
> but not blocked, that data type is set to *alert* in your policy — change it to
> *block* in the dashboard and the agents pick it up automatically.

---

## Troubleshooting (symptom → cause → fix)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Agent installed but **UI says "not configured" / inactive** | Step 3 config not delivered (no `LicenseKey` in the managed scope **or** the JSON file) | Re-check check #2. Ensure the managed policy actually reached the endpoint (GPO: `gpupdate /force`; MDM: re-push profile). Or drop the JSON fallback file. |
| **"Invalid license" / agent tries to reach `api.zeuslock.io`** | `ServerUrl` not being read — wrong key name, or config in the wrong location | Confirm the key is exactly `ServerUrl` in the right location (check #2). On Windows, values must be under `HKLM\SOFTWARE\Policies\ZeusLock`. |
| Config file present but **ignored / parser error** | The JSON/conf file was saved **with a UTF-8 BOM**, or invalid JSON | Re-save as UTF-8 **without BOM**. On Windows use `[IO.File]::WriteAllText($p,$json,(New-Object System.Text.UTF8Encoding($false)))`, never `Set-Content -Encoding UTF8`. |
| **No tray icon / agent not running**, yet installed | The agent only runs in an **interactive desktop session**; it was "started" with no user logged in | Log in as a normal user. Ensure autostart is set (Windows: `HKLM\...\Run`; macOS: login item; Linux: `/etc/xdg/autostart/`). |
| **Windows: agent missing after a GPO reboot** | The MSI is *per-user*; native "Assigned" computer install didn't apply it machine-wide | Use **Method A** (startup script `Install-ZeusAgent.ps1`), or add an `.mst` transform setting `ALLUSERS=1 MSIINSTALLPERUSER=""`. |
| Agent active but **ChatGPT paste not intercepted** | System proxy not routed to the agent, or the agent's proxy CA isn't trusted | Restart the agent inside the user session; confirm the proxy is `LISTENING` on `9876`; ensure the inspection CA is trusted (MDM/GPO can pre-push it). |
| **Endpoint doesn't appear under "Agents" in the dashboard** | Registration blocked — wrong/expired key, or can't reach the Server URL | Verify the key is valid and `https://<ServerUrl>` is reachable from the endpoint (firewall/proxy). Re-check `LicenseKey`. |
| Re-pointed to a new org/key but **old org still shows** | Stale per-user store from the previous registration | Clear the per-user config so it re-registers: delete `zeuslock-config.json` / the store in the user's app-data dir (Windows `%APPDATA%\ZeusLock DLP Agent\config.json`, macOS `~/Library/Application Support/ZeusLock DLP Agent/config.json`, Linux `~/.config/ZeusLock DLP Agent/config.json`; before 1.0.13 the folder was `Zeus DLP Agent`), then relaunch. |
| **macOS: user gets permission prompts** | TCC / login-item / network approvals not pre-granted | Pre-approve via MDM (PPPC + Managed Login Items + Certificate payloads) — see [macOS guide §5](02-macos-mdm.md#5-approvals-the-agent-needs). |

---

## Collect diagnostics for support

If you're still stuck, gather this and send it to ZeusLock support (it contains no
secrets beyond your own config, which you can redact):

**Windows**
```powershell
Get-Package -Name "*Zeus*" | Format-List Name,Version
reg query "HKLM\SOFTWARE\Policies\ZeusLock"
Get-Process *Zeus* | Format-Table ProcessName,Id
Get-NetTCPConnection -LocalPort 9876 -State Listen -ErrorAction SilentlyContinue
Get-Content C:\Windows\Temp\ZeusLock-Install.log -Tail 30   # if you used Method A
```

**macOS**
```bash
ls -d "/Applications/ZeusLock - AI Data Protection.app"
sudo defaults read /Library/Managed\ Preferences/com.zeuslock.agent 2>/dev/null
pgrep -fl "ZeusLock - AI Data Protection"; lsof -iTCP:9876 -sTCP:LISTEN
```

**Linux**
```bash
dpkg -l | grep -i zeus
sudo cat /etc/zeuslock/agent.conf
pgrep -fa zeus; ss -ltnp | grep 9876
```

Always include: the OS/version, your deployment method (GPO / MDM / Ansible /
manual), and **which of the four checks fails**.
