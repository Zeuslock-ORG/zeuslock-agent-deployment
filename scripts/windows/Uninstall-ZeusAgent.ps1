<#
.SYNOPSIS
    Removes the ZeusLock DLP agent and its managed configuration. Run as
    Administrator (or as a GPO computer Startup script for a managed removal).
#>
$ErrorActionPreference = "Continue"
$log = "C:\Windows\Temp\ZeusLock-Uninstall.log"
function Log($m) { $ts = Get-Date -Format "s"; Add-Content $log "$ts  $m"; Write-Output $m }

Log "=== ZeusLock agent uninstall starting ==="

# Stop the running agent (all user sessions)
Get-Process | Where-Object { $_.ProcessName -like "*Zeus*" } |
    Stop-Process -Force -ErrorAction SilentlyContinue

# Uninstall the package
$pkg = Get-Package -Name "*Zeus*" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pkg) { Log "Uninstalling $($pkg.Name) $($pkg.Version)"; Uninstall-Package -Name $pkg.Name -Force -ErrorAction SilentlyContinue | Out-Null }
else      { Log "No Zeus package installed." }

# Remove managed config + autostart
Remove-Item "HKLM:\SOFTWARE\Policies\ZeusLock" -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "ZeusLock Agent" -Force -ErrorAction SilentlyContinue

# Remove the admin JSON fallback (if used)
Remove-Item "C:\ProgramData\ZeusDLP\config.json" -Force -ErrorAction SilentlyContinue

Log "=== ZeusLock agent uninstall complete ==="
