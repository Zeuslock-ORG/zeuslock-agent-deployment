# Windows: deploy with Active Directory Group Policy

Deploy the ZeusLock agent to every domain-joined Windows PC from your domain controller and
bind it to your organisation, all through Group Policy. About 20 minutes of setup; PCs pick it
up at their next restart. For agent 1.0.45 or later.

**Steps:**
1. [Requirements](#1-requirements)
2. [Get your values and the MSI](#2-get-your-values-and-the-msi)
3. [Put the MSI on a share](#3-put-the-msi-on-a-share)
4. [Create the deployment GPO](#4-create-the-deployment-gpo)
5. [Method A: startup script (recommended)](#method-a-startup-script-recommended) or
   [Method B: Software Installation + Registry policy](#method-b-software-installation--registry-policy)
6. [Apply and verify](#6-apply-and-verify)

Also: [Intune / SCCM](#intune--sccm) · [One PC without GPO](#one-pc-without-gpo) ·
[Upgrade](#upgrade) · [Remove](#remove-the-agent) · [If something fails](#if-something-fails)

---

## 1. Requirements

- Windows 10 or 11, **x64**, domain-joined. (Windows Server 2022 is also used in our tests.)
- A domain controller with **Group Policy Management** (`gpmc.msc`) and rights to create and
  link a GPO.
- A file share the PCs can read (the examples use `\\DC01\ZeusLockDeploy`).
- The PCs reach your Server URL over HTTPS (443).

The agent runs in each user's session (tray icon and local proxy on `127.0.0.1:9876`). Group
Policy installs it for the whole machine; it protects a PC once a user signs in.

## 2. Get your values and the MSI

1. Get the **Server URL** and a **license key** (`zl_…`):
   [main guide, Step 1](../README.md#step-1-get-your-two-values).
2. In the dashboard: **Agents** → **Download Agent** → **Download MSI**.

Expected result: a file `ZeusLock-<version>.msi`.

What the MSI does: it installs **per machine** into
`C:\Program Files\ZeusLock - AI Data Protection\`, takes **no properties** and needs no
transform, starts the agent at every user's sign-in (`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`,
value `ZeusLock Agent`), and turns off QUIC (HTTP/3) in Chrome, Edge and Brave
(`QuicAllowed=0`), which would bypass the agent. A silent install does not start the agent: it
starts at the next sign-in. The MSI carries no credentials.

## 3. Put the MSI on a share

On the domain controller, PowerShell as Administrator:

```powershell
New-Item -ItemType Directory -Force -Path C:\ZeusLockDeployment | Out-Null
Copy-Item .\ZeusLock-<version>.msi C:\ZeusLockDeployment\ZeusLock.msi -Force
# Domain Computers by SID, so this works in any Windows language
$dc     = Get-ADGroup -Identity "$((Get-ADDomain).DomainSID.Value)-515"
$dcName = "$((Get-ADDomain).NetBIOSName)\$($dc.SamAccountName)"
New-SmbShare -Name ZeusLockDeploy -Path C:\ZeusLockDeployment -ReadAccess $dcName -ErrorAction SilentlyContinue
Test-Path \\$env:COMPUTERNAME\ZeusLockDeploy\ZeusLock.msi
```

Expected result: `True`.

For Method A, also copy
[scripts/windows/Install-ZeusLockAgent.ps1](../scripts/windows/Install-ZeusLockAgent.ps1)
to `C:\ZeusLockDeployment\`.

## 4. Create the deployment GPO

```powershell
Import-Module GroupPolicy
New-GPO -Name "ZeusLock Agent - Deployment" | Out-Null
New-GPLink -Name "ZeusLock Agent - Deployment" -Target (Get-ADDomain).DistinguishedName -LinkEnabled Yes
```

Expected result: the GPO **ZeusLock Agent - Deployment** appears in `gpmc.msc`, linked to the
domain. For a first rollout, link it to a pilot OU instead (`-Target "OU=Pilot,DC=corp,DC=local"`).

Then choose **Method A** or **Method B**. You need only one.

---

## Method A: startup script (recommended)

One computer startup script installs the agent, upgrades it when you put a newer MSI on the
share, and writes the configuration. It is safe to leave linked: a PC that already has the
same or a newer version is left alone.

### A.1 Put your values in the script

1. Put the license key in a file that only domain computers can read. A GPO script lives in
   SYSVOL, which every domain user can read, so the key does not go in the script. On the
   domain controller:

   ```powershell
   New-Item -ItemType Directory -Force -Path C:\ZeusLockKey | Out-Null
   Set-Content -Path C:\ZeusLockKey\license-key.txt -Value (Read-Host "License key")   # paste, Enter
   $dc     = Get-ADGroup -Identity "$((Get-ADDomain).DomainSID.Value)-515"
   $dcName = "$((Get-ADDomain).NetBIOSName)\$($dc.SamAccountName)"
   $admins = ([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value
   icacls C:\ZeusLockKey /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*$($dc.SID.Value):(OI)(CI)RX" /T
   New-SmbShare -Name 'ZeusLockKey$' -Path C:\ZeusLockKey -ReadAccess $dcName -FullAccess $admins
   ```

   Expected result: the share `ZeusLockKey$` exists (the `$` hides it from browsing).

2. Open `C:\ZeusLockDeployment\Install-ZeusLockAgent.ps1` and set the four lines at the top:

   ```powershell
   $ServerUrl      = "https://api.zeuslock.ai"
   $LicenseKey     = "YOUR_LICENSE_KEY"                        # leave as is
   $LicenseKeyPath = '\\DC01\ZeusLockKey$\license-key.txt'
   $MsiSource      = "\\DC01\ZeusLockDeploy\ZeusLock.msi"
   ```

   Expected result: the script holds the Server URL and the two paths, no key.

On each PC the script then writes `HKLM\SOFTWARE\Policies\ZeusLock` and locks it first:
inheritance removed, **SYSTEM** and **Administrators** full control, **INTERACTIVE** (signed-in
users, where the agent runs) read only. Service accounts, network logons and sandboxed apps
cannot read the key. The key is never written to the script's log.

### A.2 Attach the script to the GPO

1. `gpmc.msc` → right-click **ZeusLock Agent - Deployment** → **Edit**.
2. **Computer Configuration → Policies → Windows Settings → Scripts (Startup/Shutdown)**.
3. Double-click **Startup** → **PowerShell Scripts** tab → **Add** → **Browse**.
4. Copy `Install-ZeusLockAgent.ps1` into the folder that opens, select it → **OK** → **OK**.

Expected result: the script is listed on the **PowerShell Scripts** tab.

Go to [6. Apply and verify](#6-apply-and-verify).

---

## Method B: Software Installation + Registry policy

The classic click-through: Group Policy installs the MSI, and a Registry policy delivers the
configuration.

### B.1 Assign the MSI

1. `gpmc.msc` → **Edit** the GPO → **Computer Configuration → Policies → Software Settings →
   Software Installation**.
2. Right-click → **New → Package**.
3. Type the **UNC path**, not a local path: `\\DC01\ZeusLockDeploy\ZeusLock.msi` → **Open**.
4. Choose **Assigned** → **OK**.

Expected result: **ZeusLock - AI Data Protection** is listed, deployment state **Assigned**.

### B.2 Deliver the configuration

1. **Computer Configuration → Preferences → Windows Settings → Registry → New → Registry
   Item**. Add two items:

   | Action | Hive | Key path | Value name | Type | Value data |
   |---|---|---|---|---|---|
   | Update | HKEY_LOCAL_MACHINE | `SOFTWARE\Policies\ZeusLock` | `ServerUrl` | REG_SZ | `https://api.zeuslock.ai` |
   | Update | HKEY_LOCAL_MACHINE | `SOFTWARE\Policies\ZeusLock` | `LicenseKey` | REG_SZ | your `zl_…` key |

2. Restrict the key: **Computer Configuration → Policies → Windows Settings → Security Settings
   → Registry** → right-click → **Add Key** → `MACHINE\SOFTWARE\Policies\ZeusLock` →
   **Advanced** → **Disable inheritance** → **Remove all inherited permissions** → add
   **SYSTEM** (Full Control), **Administrators** (Full Control), **INTERACTIVE** (Read) → **OK**
   → **Replace existing permissions on all subkeys with inheritable permissions** → **OK**.

Expected result: both values and the key's permissions are in the GPO.

> A Registry preference keeps its values in SYSVOL (`Registry.xml`), which every domain user
> can read. Method A with `$LicenseKeyPath` avoids that. To use a file instead, edit
> [scripts/windows/ZeusLock-Policy.reg](../scripts/windows/ZeusLock-Policy.reg) and import it
> with `reg import ZeusLock-Policy.reg`, then restrict the key as in step 2.

---

## 6. Apply and verify

1. From the domain controller, refresh policy on a pilot PC and restart it:

   ```powershell
   Invoke-GPUpdate -Computer "CLIENT01" -Force -RandomDelayInMinutes 0
   Restart-Computer -ComputerName "CLIENT01" -Force
   ```

2. Sign in to the PC as a normal user. Do not start anything.

   Expected result: the ZeusLock icon appears in the tray.

3. At its first start the agent asks to trust its certificate **ZeusLock DLP Proxy CA**:
   a standard user gets a Windows **Security Warning** (click **Yes**), an administrator a UAC
   prompt. Approve it.

   Expected result: the tray icon shows **Protection active** and your organisation's name.

4. On the PC, PowerShell:

   ```powershell
   Get-Package -Name "ZeusLock*" | Format-Table Name, Version
   reg query "HKLM\SOFTWARE\Policies\ZeusLock"
   reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "ZeusLock Agent"
   (Get-Acl "HKLM:\SOFTWARE\Policies\ZeusLock").Access | Format-Table IdentityReference, RegistryRights, IsInherited
   Get-NetTCPConnection -LocalPort 9876 -State Listen
   ```

   Expected result: version 1.0.45 or later; `ServerUrl` and `LicenseKey`; the Run value;
   exactly `NT AUTHORITY\SYSTEM FullControl`, `BUILTIN\Administrators FullControl`,
   `NT AUTHORITY\INTERACTIVE ReadKey`, all `IsInherited False`; one listener on port 9876.

5. Open **chatgpt.com** and send `My card is 4111 1111 1111 1111`.

   Expected result: the agent flags or blocks it, an incident appears under **Incidents**,
   and the PC is listed under **Agents** in the dashboard.

Full checklist and logs: [verify-and-troubleshoot.md](verify-and-troubleshoot.md).

---

## Intune / SCCM

The same two parts: install the MSI, deliver the two values.

- **Install:** a Win32 app (Intune, `.intunewin`) or an Application (SCCM) with
  `msiexec /i ZeusLock-<version>.msi /qn /norestart`. No properties, no transform.
- **Configure:** a PowerShell script (Intune platform script or SCCM) that writes
  `ServerUrl` and `LicenseKey` to `HKLM\SOFTWARE\Policies\ZeusLock` with the permissions above.
  `Install-ZeusLockAgent.ps1` does both install and configuration when `$MsiSource` points
  to a copy the PC can read.

## One PC without GPO

Use the dashboard: **Agents** → **Installing on a single machine?** → **Local agent install**.

1. Download **Setup .exe (single PC)** and double-click it (Next → Install → Finish).
   Expected result: the agent starts. It installs per machine into
   `C:\Program Files\ZeusLock\ZeusLock - AI Data Protection\` and starts at every sign-in
   (`HKLM\...\Run`, value `ZeusLock DLP Agent`).
2. PowerShell as Administrator, the command the page shows (with your key):

   ```powershell
   $dir = "C:\ProgramData\ZeusLockDLP"
   New-Item -ItemType Directory -Force -Path $dir | Out-Null
   $json = '{"ServerUrl":"https://api.zeuslock.ai","LicenseKey":"zl_your_key_here"}'
   [System.IO.File]::WriteAllText("$dir\config.json", $json, (New-Object System.Text.UTF8Encoding($false)))
   Write-Host "ZeusLock configured."
   ```

3. Quit the agent (tray icon → **Quit**) and open it again from **Start**: it reads the file
   only when it starts. Approve the certificate prompt.
   Expected result: **Protection active**.

A PC set up this way is not managed: the user can quit the agent from the tray.

## Upgrade

The agent does not update itself.

- **Method A:** replace `ZeusLock.msi` on the share with the new version. At the next start-up
  each PC with an older version is upgraded; the others are left alone.
- **Method B:** add the new MSI as a new package in the same GPO → its **Properties** →
  **Upgrades** → **Add** → the current ZeusLock package → **Package can upgrade over the
  existing package** → **OK**.
- **Intune / SCCM:** publish the new MSI as a superseding app.

An MSI upgrade while the agent runs is fine: the agent is back in each signed-in session within
a few seconds, and browsers stay on the agent during the upgrade. To switch a PC to the
On-Device installer, deploy the On-Device MSI the same way.

## Remove the agent

1. Unlink the GPO (or, Method B, set the package to **Remove**), so Group Policy stops
   installing it and stops writing the configuration.
2. Run [scripts/windows/Uninstall-ZeusLockAgent.ps1](../scripts/windows/Uninstall-ZeusLockAgent.ps1)
   as Administrator, or as a startup script in a new GPO.

Expected result: `Get-Package -Name "ZeusLock*"` returns nothing and web browsing works.

The script removes the configuration, stops the agent, gives each signed-in user's network back
(Windows proxy, browser proxy policy, Claude Code and Cursor settings), uninstalls every
ZeusLock install, and removes the certificate from the machine store. Users who were not signed
in get their network settings back automatically at their next sign-in. Log:
`C:\Windows\Temp\ZeusLock-Uninstall.log`.

---

## If something fails

| Symptom | Fix |
|---|---|
| Agent not installed after the restart | Method A: read `C:\Windows\Temp\ZeusLock-Install.log` and `ZeusLock-msi.log`. Check the PC can read `\\DC01\ZeusLockDeploy\ZeusLock.msi` (the computer account, not the user). |
| Tray shows **Agent not configured** | `reg query "HKLM\SOFTWARE\Policies\ZeusLock"` on the PC. Empty: run `gpupdate /force`; Method A: check the PC can read the key file share. |
| Agent does not start at sign-in | `reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run` must show `ZeusLock Agent` (MSI) or `ZeusLock DLP Agent` (Setup .exe). Task Manager → **Startup apps** must show it **Enabled**. |
| Browsers show a certificate warning on AI sites | The user refused the certificate prompt. Quit the agent from the tray (or restart the PC) and approve the prompt at the next start. |
| No internet after the agent was stopped or crashed | Wait up to 3 minutes, or run the reset in [verify-and-troubleshoot.md](verify-and-troubleshoot.md#network-after-the-agent-stops). |

> **Known limits**
> - x64 only.
> - Each user approves the certificate once, at the agent's first start in their session.
> - Updating with the Setup .exe leaves a few seconds where browsers go direct; MSI upgrades
>   do not.
