# Sends one transport command to FMP's own media session through WinRT, the
# way the media flyout does -- never to any other app's session.
#
# Do not use global keyboard media keys (VK_MEDIA_PLAY_PAUSE and friends) to
# verify FMP: Windows routes them to whichever session it considers current,
# which may be another app that happens to be playing.
#
# MUST run under Windows PowerShell 5.1 (`powershell.exe`); `pwsh` has no
# WinRT projection.
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass `
#     -File .claude/skills/verify-on-device/scripts/smtc_command.ps1 `
#     -Command play|pause|toggle|next|previous|stop [-Aumid com.personal.fmp.dev]
#
# -Aumid is an exact match (not a substring), so the dev build never reaches
# the prod or old app (`com.personal.fmp`), and nothing else is touched.
#
# Exit codes: 0 = the session accepted the command, 1 = no FMP session (SMTC is
# disabled until something plays), 2 = WinRT failed, 3 = the session refused
# the command. ACCEPTED=True does not prove the app got it: on 2026-10-07 a
# Stop sent while FMP's stop button was disabled came back accepted and never
# reached the app. Confirm in FMP's log (`Playback state`, `Track requested`).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('play', 'pause', 'toggle', 'next', 'previous', 'stop')]
    [string]$Command,
    [ValidateNotNullOrEmpty()]
    [string]$Aumid = 'com.personal.fmp.dev'
)

$ErrorActionPreference = 'Stop'

try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime

    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        })[0]

    function Await($operation, $resultType) {
        $task = $asTaskGeneric.MakeGenericMethod($resultType).Invoke($null, @($operation))
        if (-not $task.Wait(5000)) { throw 'WinRT call timed out after 5s' }
        $task.Result
    }

    $managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
    $manager = Await ($managerType::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
}
catch {
    Write-Output "WINRT_FAILED $($_.Exception.Message)"
    exit 2
}

$sessions = @($manager.GetSessions() | Where-Object { $_.SourceAppUserModelId -eq $Aumid })
if ($sessions.Count -eq 0) {
    Write-Output "NO_SESSION $Aumid (SMTC is disabled until a track plays)"
    exit 1
}

$session = $sessions[0]
try {
    $operation = switch ($Command) {
        'play' { $session.TryPlayAsync() }
        'pause' { $session.TryPauseAsync() }
        'toggle' { $session.TryTogglePlayPauseAsync() }
        'next' { $session.TrySkipNextAsync() }
        'previous' { $session.TrySkipPreviousAsync() }
        'stop' { $session.TryStopAsync() }
    }
    $accepted = Await $operation ([bool])
}
catch {
    Write-Output "WINRT_FAILED $($_.Exception.Message)"
    exit 2
}

Write-Output ("SENT={0} APP={1} ACCEPTED={2}" -f $Command, $session.SourceAppUserModelId, $accepted)
if (-not $accepted) { exit 3 }
exit 0
