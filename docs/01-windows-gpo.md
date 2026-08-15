# Windows — Active Directory / Group Policy (GPO) Deployment

Deploy the ZeusLock agent to every domain-joined Windows machine from your domain
controller, and bind them to your organization — all through Group Policy. This is
the exact flow validated end-to-end on a Windows Server AD lab.

**Time:** ~20 minutes for the GPO setup, then it applies to endpoints on their
next reboot/policy refresh.

**You'll do:**
1. [Prerequisites](#1-prerequisites)
2. [Get your values + the installer](#2-get-your-values--the-installer)
3. [Stage the installer on a share](#3-stage-the-installer-on-a-share)
4. [Create the deployment GPO](#4-create-the-deployment-gpo)
5. [Method A — Startup-script deploy (recommended)](#method-a--startup-script-deploy-recommended)
6. [Method B — Native Software Installation + Registry policy](#method-b--native-software-installation--registry-policy)
7. [Apply + verify](#7-apply--verify)

---

## 1. Prerequisites

- A **domain controller** (Windows Server) with **Group Policy Management** (`gpmc.msc`).
- Target machines are **domain-joined** and can reach your **Server URL** over HTTPS (443).
- A file share readable by the machines you're deploying to (we use `\\DC01\ZeusDeploy`).
- Rights to create/link a GPO at the domain or target OU.

> ℹ️ **Why the agent needs a logged-in user:** the agent is a per-user tray app +
> local inspection proxy. GPO installs it machine-wide and delivers config, but it
> only becomes *active* once a user logs in. That's expected and correct.

---

## 2. Get your values + the installer

1. **Server URL** and **License key** — see [the main guide, Step 1](../README.md#before-you-start--get-your-two-values-step-1).
   Keep them handy; you'll paste them into the GPO/script.
2. **Download the Windows installer** from your dashboard (**Agents → Download**,
   Windows MSI). You'll get a file like `ZeusLock-<version>.msi`.

> The MSI is **generic** (no embedded credentials) and, by default, a **per-user**
> package. The steps below install it **per-machine** so one policy covers every
> user on the endpoint.

---

## 3. Stage the installer on a share

On the domain controller (or any file server), place the MSI where domain machines
can read it.

```powershell
# On DC01 (PowerShell as Administrator)
New-Item -ItemType Directory -Force -Path C:\ZeusDeployment | Out-Null
Copy-Item .\ZeusLock-<version>.msi C:\ZeusDeployment\ZeusLock.msi -Force

# Share it read-only to domain computers (skip if the share already exists)
New-SmbShare -Name ZeusDeploy -Path C:\ZeusDeployment -ReadAccess Everyone -ErrorAction SilentlyContinue
Grant-SmbShareAccess -Name ZeusDeploy -AccountName "Domain Computers" -AccessRight Read -Force

# Confirm
Test-Path \\$env:COMPUTERNAME\ZeusDeploy\ZeusLock.msi
```

Also copy **[scripts/windows/Install-ZeusAgent.ps1](../scripts/windows/Install-ZeusAgent.ps1)**
into `C:\ZeusDeployment\` (Method A uses it).

---

## 4. Create the deployment GPO

```powershell
# On DC01
Import-Module GroupPolicy
$gpo = New-GPO -Name "ZeusLock Agent - Deployment"
New-GPLink -Name "ZeusLock Agent - Deployment" -Target (Get-ADDomain).DistinguishedName -LinkEnabled Yes
```

> Link it at the **domain root** to cover everyone, or at a specific **OU** to
> pilot on a subset of machines first (recommended for the first rollout).

Now choose **Method A** (recommended, reliable) or **Method B** (native GPMC
click-through). You only need one.

---

## Method A — Startup-script deploy (recommended)

A single computer **startup script** installs the agent per-machine, writes the
config, and sets it to auto-start. It is **idempotent** — it skips machines that
already have the right version, so it's safe to leave linked. This is the most
reliable way to deploy the per-user MSI machine-wide.

### A.1 — Edit the script's values

Open **[scripts/windows/Install-ZeusAgent.ps1](../scripts/windows/Install-ZeusAgent.ps1)**
and set the three variables at the top:

```powershell
$ServerUrl  = "YOUR_SERVER_URL"      # e.g. https://api.zeuslock.ai
$LicenseKey = "YOUR_LICENSE_KEY"     # zl_...
$MsiSource  = "\\DC01\ZeusDeploy\ZeusLock.msi"
```

### A.2 — Attach it as a computer Startup script

1. `gpmc.msc` → right-click **ZeusLock Agent - Deployment** → **Edit**.
2. **Computer Configuration → Policies → Windows Settings → Scripts (Startup/Shutdown)**.
3. Double-click **Startup → Add → Browse** — this opens the GPO's script folder.
4. Copy `Install-ZeusAgent.ps1` into that folder, select it, click **OK**.
   - If prompted for PowerShell vs. classic scripts, use the **PowerShell Scripts**
     tab so it runs under PowerShell.

That's it — no separate config step. The script installs the MSI per-machine,
writes `HKLM\SOFTWARE\Policies\ZeusLock`, and registers autostart.

Jump to **[Apply + verify](#7-apply--verify)**.

---

## Method B — Native Software Installation + Registry policy

Prefer the classic GPMC click-through? Deploy the MSI with **Software Installation**
and deliver config with a **Registry policy**. Two parts.

### B.1 — Assign the MSI (Software Installation)

1. `gpmc.msc` → **Edit** the GPO → **Computer Configuration → Policies → Software
   Settings → Software Installation**.
2. Right-click → **New → Package**.
3. In the file picker, type the **UNC path** (not a local `C:\` path):
   `\\DC01\ZeusDeploy\ZeusLock.msi`
4. Choose **Assigned**.

> ⚠️ **Per-machine caveat:** the ZeusLock MSI is a *per-user* package. Native
> "Assigned" computer installs can misbehave with per-user MSIs. If endpoints show
> the agent missing after reboot, either:
> - switch to **[Method A](#method-a--startup-script-deploy-recommended)** (handles
>   the per-machine override for you — recommended), **or**
> - apply a transform (`.mst`) that sets `ALLUSERS=1` and `MSIINSTALLPERUSER=""`
>   (Software Installation → package **Properties → Modifications → Add**).

### B.2 — Deliver config via Registry policy

Deliver `ServerUrl` + `LicenseKey` (and any toggles) to
`HKLM\SOFTWARE\Policies\ZeusLock` — the agent's managed scope.

**Option 1 — GPO Registry preference (click-through):**
**Computer Configuration → Preferences → Windows Settings → Registry → New →
Registry Item**, then add each value:

| Action | Hive | Key path | Value name | Type | Value data |
|--------|------|----------|-----------|------|-----------|
| Update | HKEY_LOCAL_MACHINE | `SOFTWARE\Policies\ZeusLock` | `ServerUrl` | REG_SZ | `YOUR_SERVER_URL` |
| Update | HKEY_LOCAL_MACHINE | `SOFTWARE\Policies\ZeusLock` | `LicenseKey` | REG_SZ | `YOUR_LICENSE_KEY` |
| Update | HKEY_LOCAL_MACHINE | `SOFTWARE\Policies\ZeusLock` | `AgentEnabled` | REG_DWORD | `1` |
| Update | HKEY_LOCAL_MACHINE | `SOFTWARE\Policies\ZeusLock` | `BlockingEnabled` | REG_DWORD | `1` |

**Option 2 — import the .reg template:** edit
**[scripts/windows/ZeusLock-Policy.reg](../scripts/windows/ZeusLock-Policy.reg)**
(fill in your values), then either import it on a reference machine
(`reg import ZeusLock-Policy.reg`) or add it as a startup command. Option 1 (GPO
preference) is cleaner for fleets because it self-heals on every refresh.

> Method B **does not set autostart** (Method A does). The agent's own
> "start at login" setting handles this on first run, but if you want a guaranteed
> machine-wide autostart, also push an `HKLM\...\Run` entry (see the reg template).

---

## 7. Apply + verify

Force a target machine to pull the new policy, then reboot so the install + config
take effect:

```powershell
# From DC01, against a specific client (or just reboot the client)
Invoke-GPUpdate -Computer "CLIENT01" -Force -RandomDelayInMinutes 0
Restart-Computer -ComputerName "CLIENT01" -Force
```

After the client reboots **and a user logs in**, verify on the client (or remotely):

```powershell
# 1. Installed?
Get-Package -Name "*Zeus*" | Format-Table Name, Version

# 2. Config delivered?
reg query "HKLM\SOFTWARE\Policies\ZeusLock"

# 3. Group Policy applied?
gpresult /r /scope computer | Select-String "ZeusLock"

# 4. Agent running + proxy up? (run while the user is logged in)
Get-Process | Where-Object { $_.ProcessName -like "*Zeus*" }
Get-NetTCPConnection -LocalPort 9876 -State Listen -ErrorAction SilentlyContinue
```

Then the **live test**: log in as a normal user, open a browser to **chatgpt.com**,
and paste a test secret such as `4111 1111 1111 1111`. The agent should
flag/block it and an **incident** should appear under **Incidents** in your
dashboard.

Full check-list and troubleshooting: **[verify-and-troubleshoot.md](verify-and-troubleshoot.md)**.

---

## SCCM / Intune (brief)

The same two ingredients apply — deploy the MSI, deliver the config:

- **SCCM:** package the MSI as an Application; install command
  `msiexec /i ZeusLock.msi /qn ALLUSERS=1 MSIINSTALLPERUSER=""`. Deliver config via
  a Configuration Item that writes `HKLM\SOFTWARE\Policies\ZeusLock`, or ship
  `Install-ZeusAgent.ps1` as the install script.
- **Intune:** wrap the MSI as a Win32 app (`.intunewin`) with the same install
  command, or deploy `Install-ZeusAgent.ps1` as a platform script; deliver config
  via a **Settings catalog / OMA-URI** registry policy to the same key.

---

## Upgrading from 1.0.8 or earlier (product was "Zeus - AI Data Protection")

Version 1.0.9 renamed the product to **ZeusLock - AI Data Protection**: the install
folder is now `C:\Program Files\ZeusLock - AI Data Protection\` and the exe
`ZeusLock - AI Data Protection.exe`. Same UpgradeCode, so the MSI upgrades in place
(the old folder and shortcut are removed). Two things to know:

- **Method A** (`Install-ZeusAgent.ps1`) needs no change — it uninstalls the older
  package, installs the new MSI and re-registers autostart against the new exe.
- **Method B / anyone using `ZeusLock-Policy.reg`**: the `Run` value points at the exe
  path. Deploy the updated `.reg` **first**, then the new MSI. Until both have arrived
  the machine has a `Run` entry for a path that does not exist yet — harmless, nothing
  launches — and the next logon after both are in place starts the agent normally.
- `Get-Package -Name "*Zeus*"` and the `*Zeus*` process matchers keep working (they
  match the new name too).

## Removing the agent

```powershell
# On the client
$p = Get-Package -Name "*Zeus*"; if ($p) { Uninstall-Package -Name $p.Name -Force }
Remove-Item "HKLM:\SOFTWARE\Policies\ZeusLock" -Recurse -Force -ErrorAction SilentlyContinue
```

To stop deploying, unlink the GPO (or set the Software Installation package to
**Remove** for a managed uninstall on next reboot). A ready
**[Uninstall-ZeusAgent.ps1](../scripts/windows/Uninstall-ZeusAgent.ps1)** is provided.
