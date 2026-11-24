<#
.SYNOPSIS
    Removes the ZeusLock agent and leaves the network clean. Run as Administrator, or
    as a GPO computer Startup script for a managed removal.

.DESCRIPTION
    1. Deletes the managed configuration (HKLM\SOFTWARE\Policies\ZeusLock), so the PC
       is no longer managed. Unlink the deployment GPO first, or Group Policy writes
       the key again.
    2. Stops the agent and its watchdog.
    3. In every signed-in user's session, runs the agent's own cleanup
       ("<agent exe>" --cleanup --uninstall): it gives back the Windows proxy (the
       company proxy that was there before, or none), the Chrome/Edge/Brave proxy
       policy, and the Claude Code and Cursor settings.
    4. Uninstalls every ZeusLock install (MSI and Setup .exe) with its own uninstaller.
    5. Removes the agent's certificate "ZeusLock DLP Proxy CA" from the machine store
       (and from your own user store when you run it by hand), the start-up values and
       the JSON configuration.

    Users who are not signed in get step 3 at their next sign-in: the agent left a
    small cleanup in their profile (%APPDATA%\ZeusLock DLP Agent) that runs once the
    agent is gone and then removes itself. This script leaves those folders in place
    for that reason. A certificate a standard user trusted in their own store stays
    there; remove it in their session with:
        certutil -user -delstore Root "ZeusLock DLP Proxy CA"

    Log: C:\Windows\Temp\ZeusLock-Uninstall.log
#>
$ErrorActionPreference = "Continue"
$log = "C:\Windows\Temp\ZeusLock-Uninstall.log"
function Log($m) { $ts = Get-Date -Format "s"; Add-Content $log "$ts  $m"; Write-Host $m }

$ExeName = "ZeusLock - AI Data Protection.exe"
$ExePaths = @(
    "C:\Program Files\ZeusLock - AI Data Protection\$ExeName",              # MSI
    "C:\Program Files\ZeusLock\ZeusLock - AI Data Protection\$ExeName"      # Setup .exe
)
$CaNames = @("ZeusLock DLP Proxy CA", "Zeus DLP Proxy CA")
$CleanupTask = "ZeusLockProxyCleanup"
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

# Signed-in users: the owner of each explorer.exe (one per interactive session).
function Get-SignedInUsers {
    $users = @{}
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue)) {
        try {
            $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner
            if ($o.ReturnValue -eq 0 -and $o.User) { $users["$($o.Domain)\$($o.User)"] = $p.SessionId }
        } catch {}
    }
    return @($users.Keys)
}

# Run one command once in a user's session (a one-shot scheduled task with an
# interactive principal: no password needed), wait for it, then remove the task.
function Invoke-InUserSession([string]$User, [string]$Execute, [string]$Argument, [int]$WaitSeconds) {
    $name = "ZeusLockUninstall-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
    try {
        $action = New-ScheduledTaskAction -Execute $Execute -Argument $Argument
        $principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName $name
        $deadline = (Get-Date).AddSeconds($WaitSeconds)
        do {
            Start-Sleep -Milliseconds 500
            $state = (Get-ScheduledTask -TaskName $name).State
        } while ($state -eq "Running" -and (Get-Date) -lt $deadline)
        $info = Get-ScheduledTaskInfo -TaskName $name
        Log "  ${User}: cleanup finished (state $state, result $($info.LastTaskResult))"
    } catch {
        Log "  ${User}: cleanup could not run: $($_.Exception.Message)"
    } finally {
        try { Unregister-ScheduledTask -TaskName $name -Confirm:$false } catch {}
    }
}

# The agent and its watchdog are the same executable. The per-user cleanup task is
# paused first: on a managed PC it would start the agent again.
function Stop-ZeusLockAgent {
    & schtasks.exe /Change /TN $CleanupTask /DISABLE 2>$null | Out-Null
    foreach ($round in 1..3) {
        $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "Zeus*AI Data Protection*" })
        if ($running.Count -eq 0) { return }
        & taskkill.exe /F /T /IM $ExeName 2>$null | Out-Null
        & taskkill.exe /F /T /IM "Zeus - AI Data Protection.exe" 2>$null | Out-Null
        Start-Sleep -Seconds 2
    }
}

# Silent removal of one install: msiexec for an MSI, the uninstaller for a Setup .exe.
function Remove-ZeusLockInstall($Entry) {
    if ($Entry.IsMsi) {
        $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/x $($Entry.ProductCode) /qn /norestart /l*v `"C:\Windows\Temp\ZeusLock-msi-uninstall.log`""
        return $p.ExitCode
    }
    $command = if ($Entry.QuietUninstall) { $Entry.QuietUninstall } else { "$($Entry.Uninstall) /S" }
    if ($command -notmatch '^\s*"([^"]+)"\s*(.*)$') { Log "  cannot read the uninstall command of $($Entry.Name)"; return -1 }
    $p = Start-Process -FilePath $Matches[1] -ArgumentList $Matches[2] -Wait -PassThru
    return $p.ExitCode
}

function Test-RunningAsSystem {
    return ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq "S-1-5-18")
}

function Remove-ZeusLockCertificates {
    foreach ($ca in $CaNames) {
        & certutil.exe -delstore Root $ca 2>$null | Out-Null
        if (-not (Test-RunningAsSystem)) { & certutil.exe -user -delstore Root $ca 2>$null | Out-Null }
    }
    Log "Certificate '$($CaNames[0])' removed from the machine store$(if (-not (Test-RunningAsSystem)) { ' and your user store' })"
}

function Invoke-Main {
    Log "=== ZeusLock agent uninstall starting ==="

    # 1. Not managed any more: the cleanup below then gives the network back instead
    #    of starting the agent again (ManagedUncleanStop=protect).
    Remove-Item "HKLM:\SOFTWARE\Policies\ZeusLock" -Recurse -Force -ErrorAction SilentlyContinue
    Log "Managed configuration removed (HKLM\SOFTWARE\Policies\ZeusLock)"

    $installs = @(Get-ZeusLockInstalls)
    if ($installs.Count -eq 0) { Log "No ZeusLock install found." }

    # 2. Stop the agent and its watchdog.
    Stop-ZeusLockAgent
    Log "Agent stopped"

    # 3. The agent's own cleanup in each signed-in session, while its executable exists.
    $exe = $ExePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $users = @(Get-SignedInUsers)
    if ($exe -and $users.Count -gt 0) {
        foreach ($user in $users) {
            Log "Restoring the network settings of $user"
            Invoke-InUserSession $user $exe "--cleanup --uninstall" 60
        }
    } elseif ($users.Count -eq 0) {
        Log "Nobody is signed in: each user's network settings are restored at their next sign-in"
    }

    # 4. Uninstall.
    foreach ($entry in $installs) {
        Log "Uninstalling $($entry.Name) $($entry.Version)"
        $code = Remove-ZeusLockInstall $entry
        Log "  exit code: $code"
    }

    # 5. What the uninstallers may leave.
    & schtasks.exe /Delete /F /TN $CleanupTask 2>$null | Out-Null
    & schtasks.exe /Delete /F /TN "ZeusLockDLPAgent" 2>$null | Out-Null
    foreach ($runValue in @("ZeusLock Agent", "ZeusLock DLP Agent", "Zeus DLP Agent")) {
        Remove-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name $runValue -Force -ErrorAction SilentlyContinue
    }
    Remove-ZeusLockCertificates
    Remove-Item "C:\ProgramData\ZeusLockDLP", "C:\ProgramData\ZeusDLP" -Recurse -Force -ErrorAction SilentlyContinue
    Log "JSON configuration removed (C:\ProgramData\ZeusLockDLP)"

    Log "=== ZeusLock agent uninstall complete ==="
    return 0
}

# Run only when executed, so the functions can be dot-sourced and tested on their own.
if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-Main) }
