<#
.SYNOPSIS
    Installs + configures the ZeusLock DLP agent machine-wide. Idempotent.

.DESCRIPTION
    Designed to run as a GPO computer Startup script (SYSTEM) or manually as
    Administrator. It:
      1. installs the (per-user) ZeusLock MSI as PER-MACHINE,
      2. writes the managed config to HKLM\SOFTWARE\Policies\ZeusLock,
      3. registers the agent to auto-start for any logged-in user.
    Re-running is safe: it skips the install if the target version is already
    present, and simply re-asserts the config.

.NOTES
    Fill in the variables below. Nothing else needs editing.

    The license key is a secret. A GPO startup script is stored in SYSVOL, which
    every domain user can read, so prefer $LicenseKeyPath: a file holding only the
    key, on a share that only Domain Computers (and admins) can read. The startup
    script runs as SYSTEM and reaches the share as the computer account. See
    docs/01-windows-gpo.md, A.1.

    Who can read the config: the agent runs in each user's session (not as SYSTEM),
    so it must be able to read HKLM\SOFTWARE\Policies\ZeusLock. The key's ACL is
    reset to SYSTEM and Administrators (full control) plus INTERACTIVE (read), with
    inheritance removed. Service accounts, network logons and sandboxed (AppContainer)
    apps can no longer read the license key. The ACL is set before the key is written
    and re-asserted on every run.
#>

# ============================ EDIT THESE ============================
$ServerUrl      = "YOUR_SERVER_URL"                    # e.g. https://api.zeuslock.ai
$LicenseKey     = "YOUR_LICENSE_KEY"                   # zl_...  (or leave as is and use $LicenseKeyPath)
$LicenseKeyPath = ""                                   # e.g. '\\DC01\ZeusLockKey$\license-key.txt' (recommended)
$MsiSource      = "\\DC01\ZeusLockDeploy\ZeusLock.msi"     # UNC path to the staged MSI
# ====================================================================

$ErrorActionPreference = "Stop"
$log = "C:\Windows\Temp\ZeusLock-Install.log"
# Never pass the license key to Log: only the Server URL and ACLs are logged.
function Log($m) { $ts = Get-Date -Format "s"; Add-Content $log "$ts  $m"; Write-Output $m }

# Well-known SIDs, so this works on any Windows display language.
$SidSystem      = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
$SidAdmins      = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$SidInteractive = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-4")

# Replaces the DACL of HKLM\<SubKey>: inheritance removed, SYSTEM + Administrators
# full control, INTERACTIVE (any logged-on user, where the agent runs) read only.
function Protect-PolicyKey([string]$SubKey) {
    $rights = [System.Security.AccessControl.RegistryRights]
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKey,
        [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
        $rights::ChangePermissions -bor $rights::ReadPermissions -bor $rights::ReadKey)
    if (-not $key) { throw "Cannot open HKLM\$SubKey to set its permissions" }
    try {
        $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
        $none    = [System.Security.AccessControl.PropagationFlags]::None
        $allow   = [System.Security.AccessControl.AccessControlType]::Allow
        $acl = New-Object System.Security.AccessControl.RegistrySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($SidSystem,      $rights::FullControl, $inherit, $none, $allow)))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($SidAdmins,      $rights::FullControl, $inherit, $none, $allow)))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.RegistryAccessRule($SidInteractive, $rights::ReadKey,     $inherit, $none, $allow)))
        $key.SetAccessControl($acl)
        $sddl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access).GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
        Log "Permissions on HKLM\$SubKey set: $sddl"
    } finally {
        $key.Close()
    }
}

# Same restriction for the JSON fallback folder, if it exists (it may hold the key too).
# Not fatal: a failure here is logged and must not stop autostart registration.
function Protect-ConfigFolder([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    & icacls.exe $Path /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-4:(OI)(CI)RX" /T /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { Log "WARNING: icacls failed on $Path (exit $LASTEXITCODE); permissions unchanged"; return }
    Log "Permissions on $Path set: SYSTEM + Administrators full, INTERACTIVE read"
}

try {
    Log "=== ZeusLock agent install/config starting ==="

    # --- 0. Values -----------------------------------------------------------
    if ($LicenseKeyPath) {
        $LicenseKey = (Get-Content -LiteralPath $LicenseKeyPath -TotalCount 1 -ErrorAction Stop).Trim()
        Log "License key read from $LicenseKeyPath"
    }
    if ($ServerUrl -eq "YOUR_SERVER_URL" -or -not $ServerUrl) { throw "ServerUrl is not set (edit the top of the script)" }
    if ($LicenseKey -eq "YOUR_LICENSE_KEY" -or -not $LicenseKey) { throw "LicenseKey is not set (set `$LicenseKey or `$LicenseKeyPath)" }

    # --- 1. Install (skip if already present) --------------------------------
    $pkg = Get-Package -Name "*Zeus*" -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -like "*Zeus*" } | Select-Object -First 1
    $installDir = "C:\Program Files\ZeusLock - AI Data Protection"   # 1.0.12+; older installs (\Zeus - AI Data Protection) are removed below and replaced
    $installed  = $pkg -and (Test-Path (Join-Path $installDir "resources\app.asar"))

    if ($installed) {
        Log "Agent already installed ($($pkg.Name) $($pkg.Version)) - skipping MSI."
    } else {
        # Remove any older/partial ZeusLock package first (different UpgradeCodes do
        # not auto-upgrade).
        if ($pkg) {
            Log "Removing existing package $($pkg.Name) $($pkg.Version)"
            Get-Process | Where-Object { $_.ProcessName -like "*Zeus*" } |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Uninstall-Package -Name $pkg.Name -Force -ErrorAction SilentlyContinue | Out-Null
        }

        # Copy the MSI local (msiexec as SYSTEM is more reliable off a local path).
        $localMsi = "C:\Windows\Temp\ZeusLock.msi"
        Log "Copying MSI from $MsiSource"
        Copy-Item $MsiSource $localMsi -Force

        # Force a PER-MACHINE install of the per-user MSI.
        $msiLog = "C:\Windows\Temp\ZeusLock-msi.log"
        Log "Installing (per-machine)..."
        $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList `
            "/i `"$localMsi`" /qn /norestart /l*v `"$msiLog`" ALLUSERS=1 MSIINSTALLPERUSER=`"`""
        Log "msiexec exit code: $($p.ExitCode)"
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
            throw "MSI install failed (exit $($p.ExitCode)); see $msiLog"
        }
    }

    # --- 2. Managed config (HKLM policy scope) -------------------------------
    $rk = "HKLM:\SOFTWARE\Policies\ZeusLock"
    if (-not (Test-Path $rk)) { New-Item -Path $rk -Force | Out-Null }
    # Restrict the key BEFORE the license key goes in (and re-assert it on every run).
    Protect-PolicyKey "SOFTWARE\Policies\ZeusLock"
    New-ItemProperty $rk -Name ServerUrl         -Value $ServerUrl  -PropertyType String -Force | Out-Null
    New-ItemProperty $rk -Name LicenseKey        -Value $LicenseKey -PropertyType String -Force | Out-Null
    New-ItemProperty $rk -Name AgentEnabled      -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty $rk -Name BlockingEnabled   -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty $rk -Name FileMonitoring    -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty $rk -Name NetworkMonitoring -Value 1 -PropertyType DWord -Force | Out-Null
    Log "Wrote managed config to $rk (ServerUrl=$ServerUrl)"
    Protect-ConfigFolder "C:\ProgramData\ZeusLockDLP"
    Protect-ConfigFolder "C:\ProgramData\ZeusDLP"

    # --- 3. Auto-start for any logged-in user --------------------------------
    $exe = Join-Path $installDir "ZeusLock - AI Data Protection.exe"
    if (Test-Path $exe) {
        New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
            -Name "ZeusLock Agent" -Value "`"$exe`"" -PropertyType String -Force | Out-Null
        Log "Autostart registered -> $exe"
    } else {
        Log "WARNING: agent exe not found at $exe (autostart not set)"
    }

    Log "=== ZeusLock agent install/config complete ==="
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    exit 1
}
