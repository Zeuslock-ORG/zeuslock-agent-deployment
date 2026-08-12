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
    Fill in the three variables below. Nothing else needs editing.
#>

# ============================ EDIT THESE THREE ============================
$ServerUrl  = "YOUR_SERVER_URL"                    # e.g. https://api.zeuslock.ai
$LicenseKey = "YOUR_LICENSE_KEY"                   # zl_...
$MsiSource  = "\\DC01\ZeusDeploy\ZeusLock.msi"     # UNC path to the staged MSI
# =========================================================================

$ErrorActionPreference = "Stop"
$log = "C:\Windows\Temp\ZeusLock-Install.log"
function Log($m) { $ts = Get-Date -Format "s"; Add-Content $log "$ts  $m"; Write-Output $m }

try {
    Log "=== ZeusLock agent install/config starting ==="

    # --- 1. Install (skip if already present) --------------------------------
    $pkg = Get-Package -Name "*Zeus*" -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -like "*Zeus*" } | Select-Object -First 1
    $installDir = "C:\Program Files\Zeus - AI Data Protection"
    $installed  = $pkg -and (Test-Path (Join-Path $installDir "resources\app.asar"))

    if ($installed) {
        Log "Agent already installed ($($pkg.Name) $($pkg.Version)) — skipping MSI."
    } else {
        # Remove any older/partial Zeus package first (different UpgradeCodes do
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
        Log "Installing (per-machine)…"
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
    New-ItemProperty $rk -Name ServerUrl         -Value $ServerUrl  -PropertyType String -Force | Out-Null
    New-ItemProperty $rk -Name LicenseKey        -Value $LicenseKey -PropertyType String -Force | Out-Null
    New-ItemProperty $rk -Name AgentEnabled      -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty $rk -Name BlockingEnabled   -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty $rk -Name FileMonitoring    -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty $rk -Name NetworkMonitoring -Value 1 -PropertyType DWord -Force | Out-Null
    Log "Wrote managed config to $rk (ServerUrl=$ServerUrl)"

    # --- 3. Auto-start for any logged-in user --------------------------------
    $exe = Join-Path $installDir "Zeus - AI Data Protection.exe"
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
