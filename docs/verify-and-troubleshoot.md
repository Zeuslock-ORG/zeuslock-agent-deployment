# Verify and troubleshoot

How to confirm a computer is protected, where the agent's logs are, what happens to the
network when the agent stops, and how to fix the common problems. All platforms; agent 1.0.45
or later.

---

## The four checks

A computer is protected only when **all four** pass. Run them **with a user signed in to the
desktop** (the agent runs in the user's session).

### 1. Installed

| OS | Command | Expected result |
|---|---|---|
| Windows | `Get-Package -Name "ZeusLock*" \| Format-Table Name, Version` | `ZeusLock - AI Data Protection`, 1.0.45 or later |
| macOS | `defaults read "/Applications/ZeusLock - AI Data Protection.app/Contents/Info" CFBundleShortVersionString` | 1.0.45 or later |
| Linux | `dpkg-query -W zeuslock-desktop-agent` | 1.0.45 or later |

### 2. Configured (Server URL + license key delivered)

| OS | Command | Expected result |
|---|---|---|
| Windows | `reg query "HKLM\SOFTWARE\Policies\ZeusLock" /v ServerUrl` | your Server URL |
| macOS | `sudo defaults read "/Library/Managed Preferences/com.zeuslock.agent" ServerUrl` | your Server URL |
| Linux | `sudo grep ServerUrl /etc/zeuslock/agent.conf` ; `stat -c '%a %U:%G' /etc/zeuslock/agent.conf` | your Server URL ; `640 root:zeuslock` |

Configured with the JSON file instead (one computer): Windows
`C:\ProgramData\ZeusLockDLP\config.json`, macOS
`/Library/Application Support/ZeusLockDLP/config.json`, Linux `/etc/zeuslock-dlp/config.json`.

### 3. Running, with its proxy up

| OS | Command | Expected result |
|---|---|---|
| Windows | `Get-Process "ZeusLock*"` ; `Get-NetTCPConnection -LocalPort 9876 -State Listen` | processes + one listener |
| macOS | `pgrep -fl "ZeusLock - AI Data Protection"` ; `lsof -iTCP:9876 -sTCP:LISTEN` | processes + one listener |
| Linux | `pgrep -fa zeuslock-ai-data-protection` ; `ss -ltn \| grep 9876` | processes + one listener |

The tray (Windows), menu bar (macOS) or top bar (Linux) icon shows **Protection active** and
your organisation's name.

**After a restart:** restart the computer, sign in (also as a second, standard user) and,
without opening anything, repeat this check. The agent must be running in that user's session.
On Windows it must not run elevated (Task Manager → **Details** → **Elevated** = No).

### 4. Live test

As a normal user, open **chatgpt.com** and send `My card is 4111 1111 1111 1111`.

Expected result: the agent flags or blocks it, and an incident appears under **Incidents** in
the dashboard within a few seconds.

> Whether a type of data is anonymised or blocked is set by your **policy in the dashboard**
> (**Policies**), not on the computer. Change it there and the agents pick it up by themselves.

---

## Logs

The agent's data folder, per user:

| OS | Data folder | Logs |
|---|---|---|
| Windows | `%APPDATA%\ZeusLock DLP Agent` | `%APPDATA%\ZeusLock DLP Agent\logs` |
| macOS | `~/Library/Application Support/ZeusLock DLP Agent` | `~/Library/Application Support/ZeusLock DLP Agent/logs` |
| Linux | `~/.config/ZeusLock DLP Agent` | `~/.config/ZeusLock DLP Agent/logs` |

**Always written:**

| File | What |
|---|---|
| `logs/watchdog.log` | Watchdog restarts of the agent |
| `logs/cleanup.log` (macOS, Linux) | Network cleanup after the agent was stopped |
| `logs/cleanup-fallback.log` (Windows) | Network cleanup after an uninstall |
| `%ProgramData%\ZeusLock\logs\msi-session.log` (Windows) | MSI install, upgrade and removal in users' sessions |
| `C:\Windows\Temp\ZeusLock-Install.log`, `ZeusLock-msi.log`, `ZeusLock-Uninstall.log` (Windows) | The scripts in this repository |

**Testing logs** (`logs/agent.log` and `logs/requests.jsonl`) are written only when you switch
them on. Do it on one computer while you investigate:

1. Create an empty file `testing-logs.on` in the data folder (not in `logs`):

   ```powershell
   # Windows
   New-Item -ItemType File -Force "$env:APPDATA\ZeusLock DLP Agent\testing-logs.on"
   ```
   ```bash
   # macOS
   touch ~/Library/Application\ Support/ZeusLock\ DLP\ Agent/testing-logs.on
   # Linux
   touch ~/.config/ZeusLock\ DLP\ Agent/testing-logs.on
   ```

2. Restart the agent: tray icon → **Quit** and open it again, or (managed computers, no
   **Quit**) sign out and back in.

   Expected result: `logs/agent.log` and `logs/requests.jsonl` appear.

3. Reproduce the problem, then send both files to support.
4. Delete `testing-logs.on` and restart the agent to switch them off.

Prompt text, file text and file names are recorded only as a length and a fingerprint, unless
the policy key `AllowContentLogging` is set (test computers only). Each log is kept to 5 files
of 50 MB.

---

## Network after the agent stops

While it runs, the agent points the system proxy, the Chrome/Edge/Brave proxy policy, Claude
Code and Cursor at itself (`127.0.0.1:9876`).

- **Quit from the tray, sign-out, shutdown, uninstall:** everything is put back as it was
  (your company proxy, or none).
- **Killed or crashed:** AI and web traffic fails until the agent runs again or the cleanup
  runs. That is deliberate: nothing goes out unchecked.
  - Windows: the watchdog restarts the agent in about 15–20 seconds; if every ZeusLock process
    was ended, a cleanup task gives the network back within 3 minutes, or at the next sign-in.
    During a restart the proxy stays on the agent.
  - macOS and Linux: a cleanup job gives the network back within 3 minutes (Linux: 1 to 3
    minutes), or at the next login.
  - **Managed computers** (`ManagedUncleanStop=protect`, the default): the agent is started again
    instead, and the network stays on it until it runs.

**Reset by hand** (no admin needed), as the signed-in user:

| OS | Command |
|---|---|
| Windows (MSI) | `& "C:\Program Files\ZeusLock - AI Data Protection\ZeusLock - AI Data Protection.exe" --cleanup` |
| Windows (Setup .exe) | `& "C:\Program Files\ZeusLock\ZeusLock - AI Data Protection\ZeusLock - AI Data Protection.exe" --cleanup` |
| Windows, agent already uninstalled | `powershell -ExecutionPolicy Bypass -File "$env:APPDATA\ZeusLock DLP Agent\zeuslock-cleanup.ps1"` |
| Windows, last resort | `reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 0 /f` |
| macOS | `"/Applications/ZeusLock - AI Data Protection.app/Contents/MacOS/ZeusLock - AI Data Protection" --cleanup` |
| Linux | `zeuslock-ai-data-protection --cleanup` |

Expected result: web browsing works again; restart the browser if a page still fails. The
reset does nothing while the agent runs. On a **managed** Mac or Linux desktop it starts the
agent instead, which also brings the network back.

---

## Certificate warnings

The agent trusts its own certificate **ZeusLock DLP Proxy CA** at its first start in each
user's session. If that prompt was cancelled, browsers show **Your connection is not private**
(Chrome, Edge) or **Warning: Potential Security Risk Ahead** (Firefox) on AI sites.

1. Restart the agent (tray icon → **Quit**, open it again; managed computers: sign out and in)
   and approve the prompt:
   - Windows: **Yes** in the **Security Warning** (standard user), or the UAC prompt
     (administrator).
   - macOS: the user's password, to trust it in the login keychain.
   - Linux: an administrator password (**Authentication Required**). It also writes the
     Chrome/Chromium/Brave and Firefox policies.
2. Fully close and reopen the browser (on Linux also the Firefox snap).

Expected result: AI sites open without a warning.

If the prompt cannot be approved, an administrator can trust the certificate by hand, in the
user's session (the commands the dashboard **Local agent install** page shows):

```bash
# macOS
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$HOME/Library/Application Support/ZeusLock DLP Agent/certs/zeuslock-ca.crt"
# Windows (PowerShell as Admin)
certutil -addstore -f Root "$env:APPDATA\ZeusLock DLP Agent\certs\zeuslock-ca.cer"
# Linux
sudo install -D -m 0644 "$HOME/.config/ZeusLock DLP Agent/certs/zeuslock-ca.crt" /usr/local/share/ca-certificates/zeuslock-dlp-ca.crt && sudo update-ca-certificates
```

On Linux this covers the system store only; Chrome and Firefox also need the browser policies,
which the agent writes when its prompt is approved.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Agent shows **Agent not configured** | No `LicenseKey` in the managed policy or the JSON file | Check #2. GPO: `gpupdate /force`; MDM: re-push the profile; Linux: re-run the playbook. Then restart the agent. |
| Agent shows **Configuration not readable - ask your administrator** | The agent, running as the user, cannot read the file | Linux: `sudo usermod -aG zeuslock <user>`, then log out and in. macOS JSON file: `0640 root:staff`. Windows: re-run `Install-ZeusLockAgent.ps1` (the key needs **INTERACTIVE** read). |
| Configured, but the computer never appears under **Agents** | Wrong or revoked key, or the computer cannot reach the Server URL | Check the key on the **API Keys** page (status **Active**) and that `ServerUrl` is exactly `https://api.zeuslock.ai` (or your own server) and reachable on 443. |
| JSON file ignored | Invalid JSON (smart quotes, missing comma) | Re-run the dashboard's command exactly; do not edit the file by hand in a word processor. |
| Agent not running after a restart | No start at login | Windows: `reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` shows `ZeusLock Agent` (MSI) or `ZeusLock DLP Agent` (Setup .exe). macOS: `/Library/LaunchAgents/com.zeuslock.agent.plist` exists ([macOS guide](02-macos-mdm.md)). Linux: `/etc/xdg/autostart/zeuslock-agent.desktop` exists. |
| Agent running, but a ChatGPT test is not caught | The browser was open before the agent started, or the certificate is not trusted | Fully restart the browser. See [Certificate warnings](#certificate-warnings). |
| No internet after the agent stopped | Proxy still points at the stopped agent | See [Network after the agent stops](#network-after-the-agent-stops). |
| AI tools blocked with "…has the standard ZeusLock agent. Install the ZeusLock On-Device version…" | The organisation uses ZeusLock On-Device | Deploy the On-Device installer from the dashboard **On-Device** page. |
| AI tools blocked with "On-device protection needs to reach the ZeusLock server to renew its licence key" | On-Device computer offline for about 30 days | Connect it to the network; the key renews by itself. |
| AI tools blocked with "On-device protection could not run on this PC" | The computer cannot run ZeusLock Ama | Check the PC on the dashboard **On-Device** page (**Too weak**, **Model problem**). |
| Agent shows the wrong organisation | An older registration is cached | Quit the agent, delete `config.json` in its data folder ([Logs](#logs) table), open it again. |

---

## Collect diagnostics for support

Run these on the computer and send the output, with the OS version, your deployment method
(GPO / Intune / MDM / Ansible / by hand) and **which of the four checks fails**. They do not
print the license key.

**Windows** (PowerShell as Administrator)
```powershell
Get-Package -Name "ZeusLock*" | Format-List Name, Version
reg query "HKLM\SOFTWARE\Policies\ZeusLock" | Select-String -NotMatch "LicenseKey"
Get-Process "ZeusLock*" | Format-Table ProcessName, Id, SessionId
Get-NetTCPConnection -LocalPort 9876 -State Listen -ErrorAction SilentlyContinue
Get-Content C:\Windows\Temp\ZeusLock-Install.log -Tail 30 -ErrorAction SilentlyContinue
Get-ChildItem "C:\Users\*\AppData\Roaming\ZeusLock DLP Agent\logs" -ErrorAction SilentlyContinue
```

**macOS**
```bash
defaults read "/Applications/ZeusLock - AI Data Protection.app/Contents/Info" CFBundleShortVersionString
sudo defaults read "/Library/Managed Preferences/com.zeuslock.agent" | grep -v LicenseKey
ls -l /Library/LaunchAgents/com.zeuslock.agent.plist
pgrep -fl "ZeusLock - AI Data Protection"; lsof -iTCP:9876 -sTCP:LISTEN
tail -30 ~/Library/Application\ Support/ZeusLock\ DLP\ Agent/logs/*.log
```

**Linux**
```bash
dpkg-query -W zeuslock-desktop-agent
sudo grep -v LicenseKey /etc/zeuslock/agent.conf; stat -c '%a %U:%G' /etc/zeuslock/agent.conf
id -nG; pgrep -fa zeuslock-ai-data-protection; ss -ltn | grep 9876
tail -30 ~/.config/ZeusLock\ DLP\ Agent/logs/*.log
```

If support asks for them, add `agent.log` and `requests.jsonl` from the [testing logs](#logs).
