<#
.SYNOPSIS
    Installs or upgrades the ZeusLock agent from the MSI and writes its managed
    configuration. Safe to run at every start-up.

.DESCRIPTION
    Designed to run as a GPO computer Startup script (SYSTEM) or by hand as
    Administrator. It:
      1. installs the MSI when the agent is missing, or upgrades it when the MSI on
         the share is newer than the installed version. The same version is installed
         again only when it is a different build (the normal MSI vs the On-Device
         MSI); an equal or newer installed version is otherwise left alone. A copy
         installed with the Setup .exe is removed first, so the PC ends up with one
         install;
      2. writes ServerUrl + LicenseKey to HKLM\SOFTWARE\Policies\ZeusLock.
    The MSI installs per machine and starts the agent at every sign-in by itself
    (HKLM\...\Run "ZeusLock Agent"); this script adds nothing for that. An upgrade
    while the agent runs restarts it in each signed-in session within seconds.

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
    apps cannot read the license key. The ACL is set before the key is written and
    re-asserted on every run.

    Logs: C:\Windows\Temp\ZeusLock-Install.log (this script, never the key) and
    C:\Windows\Temp\ZeusLock-msi.log (msiexec).
#>

# ============================ EDIT THESE ============================
$ServerUrl      = "YOUR_SERVER_URL"                    # e.g. https://api.zeuslock.ai
$LicenseKey     = "YOUR_LICENSE_KEY"                   # zl_...  (or leave as is and use $LicenseKeyPath)
$LicenseKeyPath = ""                                   # e.g. '\\DC01\ZeusLockKey$\license-key.txt' (recommended)
$MsiSource      = "\\DC01\ZeusLockDeploy\ZeusLock.msi"     # UNC path to the staged MSI
# ====================================================================

$ErrorActionPreference = "Stop"
$log = "C:\Windows\Temp\ZeusLock-Install.log"
# Never pass the license key to Log: only the Server URL, versions and ACLs are logged.
function Log($m) { $ts = Get-Date -Format "s"; Add-Content $log "$ts  $m"; Write-Host $m }

$PolicySubKey = "SOFTWARE\Policies\ZeusLock"
$UninstallRoots = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

# Every ZeusLock install Windows knows about (MSI, Setup .exe, older product names).
function Get-ZeusLockInstalls {
    foreach ($root in $UninstallRoots) {
        foreach ($item in @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -Path $item.PSPath -ErrorAction SilentlyContinue
            if (-not $p -or -not ($p.DisplayName -like "Zeus*AI Data Protection*")) { continue }
            [pscustomobject]@{
                Name           = $p.DisplayName
                Version        = $p.DisplayVersion
                IsMsi          = ($p.WindowsInstaller -eq 1)
                ProductCode    = $item.PSChildName
                QuietUninstall = $p.QuietUninstallString
                Uninstall      = $p.UninstallString
            }
        }
    }
}

# "1.0.45" -> [version]; anything unreadable -> $null.
function ConvertTo-AgentVersion([string]$Text) {
    if (-not $Text) { return $null }
    $parsed = $null
    if ([version]::TryParse($Text.Trim(), [ref]$parsed)) { return $parsed }
    return $null
}

# A property inside an MSI file (ProductVersion, ProductCode), read with Windows Installer COM.
function Get-MsiProperty([string]$Path, [string]$Name) {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $db = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @($Path, 0))
    $view = $db.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $db, @("SELECT Value FROM Property WHERE Property='$Name'"))
    $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null) | Out-Null
    $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
    $value = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
    $view.GetType().InvokeMember("Close", "InvokeMethod", $null, $view, $null) | Out-Null
    return $value
}

# What to do, from what is installed and the MSI's version and product code:
#   Remove  = installs that are not the ZeusLock MSI (Setup .exe, older product names)
#   Install = $true when the MSI must run: nothing installed, an older version, or the
#             same version from another build (each MSI build has its own product code,
#             so the same file is never installed twice)
function Get-InstallPlan($Installed, [version]$MsiVersion, [string]$MsiProductCode) {
    $Installed = @($Installed | Where-Object { $_ })
    $msiInstalls = @($Installed | Where-Object { $_.IsMsi -and $_.Name -like "ZeusLock*" })
    $remove = @($Installed | Where-Object { -not ($_.IsMsi -and $_.Name -like "ZeusLock*") })
    $current = $null
    $currentCode = $null
    foreach ($entry in $msiInstalls) {
        $v = ConvertTo-AgentVersion $entry.Version
        if ($v -and (-not $current -or $v -gt $current)) { $current = $v; $currentCode = $entry.ProductCode }
    }
    $install = (-not $current) -or ($current -lt $MsiVersion) -or
        (($current -eq $MsiVersion) -and $MsiProductCode -and ($currentCode -ne $MsiProductCode))
    [pscustomobject]@{
        Remove         = $remove
        Install        = [bool]$install
        CurrentVersion = $current
    }
}

# Silent removal of one install: msiexec for an MSI, the uninstaller for a Setup .exe.
function Remove-ZeusLockInstall($Entry) {
    if ($Entry.IsMsi) {
        $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/x $($Entry.ProductCode) /qn /norestart"
        return $p.ExitCode
    }
    $command = if ($Entry.QuietUninstall) { $Entry.QuietUninstall } else { "$($Entry.Uninstall) /S" }
    if ($command -notmatch '^\s*"([^"]+)"\s*(.*)$') { throw "Cannot read the uninstall command of $($Entry.Name)" }
    $p = Start-Process -FilePath $Matches[1] -ArgumentList $Matches[2] -Wait -PassThru
    return $p.ExitCode
}

function Install-ZeusLockMsi([string]$LocalMsi, [string]$MsiLog) {
    $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i `"$LocalMsi`" /qn /norestart /l*v `"$MsiLog`""
    return $p.ExitCode
}

# Replaces the DACL of HKLM\<SubKey>: inheritance removed, SYSTEM + Administrators
# full control, INTERACTIVE (any logged-on user, where the agent runs) read only.
function Protect-PolicyKey([string]$SubKey) {
    $SidSystem      = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $SidAdmins      = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $SidInteractive = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-4")
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

# Same restriction for the JSON config folder, if it exists (it may hold the key too).
# Not fatal: a failure here is logged and must not stop the rest.
function Protect-ConfigFolder([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    # The folder gets the explicit rules (inheritable to its files); the files then just
    # inherit them. (Applying "(OI)(CI)" grants to the files themselves with /T leaves
    # each file with inheritance removed and NO rule at all: nothing can read it.)
    & icacls.exe $Path /inheritance:r /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-4:(OI)(CI)RX" /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { Log "WARNING: icacls failed on $Path (exit $LASTEXITCODE); permissions unchanged"; return }
    if (Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue) {
        & icacls.exe (Join-Path $Path '*') /reset /T /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { Log "WARNING: icacls /reset failed under $Path (exit $LASTEXITCODE)" }
    }
    Log "Permissions on $Path set: SYSTEM + Administrators full, INTERACTIVE read"
}

function Set-ManagedConfig([string]$Url, [string]$Key) {
    $rk = "HKLM:\$PolicySubKey"
    if (-not (Test-Path $rk)) { New-Item -Path $rk -Force | Out-Null }
    # Restrict the key BEFORE the license key goes in (and re-assert it on every run).
    Protect-PolicyKey $PolicySubKey
    New-ItemProperty $rk -Name ServerUrl  -Value $Url -PropertyType String -Force | Out-Null
    New-ItemProperty $rk -Name LicenseKey -Value $Key -PropertyType String -Force | Out-Null
    Log "Wrote managed config to $rk (ServerUrl=$Url)"
    Protect-ConfigFolder "C:\ProgramData\ZeusLockDLP"
    Protect-ConfigFolder "C:\ProgramData\ZeusDLP"
}

function Invoke-Main {
    try {
        Log "=== ZeusLock agent install/config starting ==="

        # --- 0. Values -----------------------------------------------------------
        if ($LicenseKeyPath) {
            $script:LicenseKey = (Get-Content -LiteralPath $LicenseKeyPath -TotalCount 1 -ErrorAction Stop).Trim()
            Log "License key read from $LicenseKeyPath"
        }
        if ($ServerUrl -eq "YOUR_SERVER_URL" -or -not $ServerUrl) { throw "ServerUrl is not set (edit the top of the script)" }
        if ($LicenseKey -eq "YOUR_LICENSE_KEY" -or -not $LicenseKey) { throw "LicenseKey is not set (set `$LicenseKey or `$LicenseKeyPath)" }

        # --- 1. Managed config (HKLM policy scope) -------------------------------
        # Written BEFORE the install: the MSI starts the agent at once in every signed-in
        # session, and an agent that starts without the policy runs unmanaged until its
        # next restart.
        Set-ManagedConfig $ServerUrl $LicenseKey

        # --- 2. Install or upgrade -------------------------------------------------
        # Copy the MSI local (msiexec as SYSTEM is more reliable off a local path).
        $localMsi = "C:\Windows\Temp\ZeusLock.msi"
        Copy-Item $MsiSource $localMsi -Force
        $msiVersion = ConvertTo-AgentVersion (Get-MsiProperty $localMsi "ProductVersion")
        if (-not $msiVersion) { throw "Cannot read the version of $MsiSource" }
        $msiCode = Get-MsiProperty $localMsi "ProductCode"
        $plan = Get-InstallPlan (Get-ZeusLockInstalls) $msiVersion $msiCode
        Log "MSI on the share: $msiVersion; installed MSI: $(if ($plan.CurrentVersion) { $plan.CurrentVersion } else { 'none' })"

        foreach ($entry in $plan.Remove) {
            Log "Removing $($entry.Name) $($entry.Version) first (one install per PC)"
            $code = Remove-ZeusLockInstall $entry
            Log "  exit code: $code"
        }

        if ($plan.Install) {
            $msiLog = "C:\Windows\Temp\ZeusLock-msi.log"
            Log "Installing $msiVersion (msiexec log: $msiLog)"
            $code = Install-ZeusLockMsi $localMsi $msiLog
            Log "msiexec exit code: $code"
            if ($code -notin @(0, 1641, 3010)) { throw "MSI install failed (exit $code); see $msiLog" }
        } else {
            Log "Installed version $($plan.CurrentVersion) is up to date: nothing to install."
        }

        Log "=== ZeusLock agent install/config complete ==="
        return 0
    }
    catch {
        Log "ERROR: $($_.Exception.Message)"
        return 1
    }
}

# Run only when executed, so the functions can be dot-sourced and tested on their own.
if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-Main) }
