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
else      { Log "No ZeusLock package installed." }

# Remove managed config + autostart
Remove-Item "HKLM:\SOFTWARE\Policies\ZeusLock" -Recurse -Force -ErrorAction SilentlyContinue
foreach ($runValue in @("ZeusLock DLP Agent", "ZeusLock Agent", "Zeus DLP Agent")) {
    Remove-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $runValue -Force -ErrorAction SilentlyContinue
}
Remove-Item "C:\Program Files\ZeusLock - AI Data Protection\zeuslock-start.bat" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Program Files\ZeusLock\ZeusLock - AI Data Protection\zeuslock-start.bat" -Force -ErrorAction SilentlyContinue
# Setup EXE up to 1.0.41 also created a logon scheduled task
schtasks /delete /tn "ZeusLockDLPAgent" /f 2>$null | Out-Null

# Proxy settings that still point at the stopped agent (127.0.0.1:9876-9879), and
# nothing else: browser proxy policies machine-wide and per signed-in user (older
# agents wrote them; they keep Chrome/Edge offline once the agent is gone), each
# signed-in user's Windows proxy, and the agent's next-sign-in cleanup entry.
function Test-Own($v) { return ([string]$v) -match '(127\.0\.0\.1|localhost):987[6-9]' }
$users = @(Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -match '^S-1-5-21-[0-9-]+$' } |
    ForEach-Object { 'Registry::HKEY_USERS\' + $_.PSChildName + '\Software' })
foreach ($root in @('HKLM:\SOFTWARE') + $users) {
    foreach ($b in 'Google\Chrome', 'Microsoft\Edge', 'BraveSoftware\Brave') {
        $k = "$root\Policies\$b"; $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
        if ($p -and (Test-Own $p.ProxySettings)) { Remove-ItemProperty $k -Name ProxySettings -ErrorAction SilentlyContinue; Log "Removed $k ProxySettings" }
    }
}
foreach ($root in $users) {
    $is = "$root\Microsoft\Windows\CurrentVersion\Internet Settings"; $p = Get-ItemProperty $is -ErrorAction SilentlyContinue
    if ($p -and (Test-Own $p.ProxyServer) -and $p.ProxyEnable -eq 1) { Set-ItemProperty $is -Name ProxyEnable -Value 0 -Type DWord; Log "Proxy switched off: $is" }
    if ($p -and (Test-Own $p.AutoConfigURL)) { Remove-ItemProperty $is -Name AutoConfigURL -ErrorAction SilentlyContinue }
    Remove-ItemProperty "$root\Microsoft\Windows\CurrentVersion\Run" -Name ZeusLockProxyCleanup, ZeusProxyCleanup -ErrorAction SilentlyContinue
}

# Remove the admin JSON fallback (if used)
Remove-Item "C:\ProgramData\ZeusLockDLP\config.json" -Force -ErrorAction SilentlyContinue

Log "=== ZeusLock agent uninstall complete ==="
