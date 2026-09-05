# Reads what Windows actually believes about each media session's transport
# controls, straight from WinRT.
#
# Use this instead of screenshotting the media flyout: the popup dismisses on
# focus change, and FMP does not reliably hold the foreground on this host. The
# session manager is readable from any process, so the app does not need to be
# focused -- or even visible -- for this to work.
#
# MUST run under Windows PowerShell 5.1 (`powershell.exe`). PowerShell 7
# (`pwsh`) has no WinRT projection and `Add-Type -AssemblyName
# System.Runtime.WindowsRuntime` fails there.
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass `
#     -File .claude/skills/verify-on-device/scripts/smtc_probe.ps1 [-AppFilter fmp]
#
# Exit codes: 0 = at least one session found, 1 = no sessions, 2 = WinRT failed.

[CmdletBinding()]
param(
    # Substring match against SourceAppUserModelId. Omit to list every session.
    [string]$AppFilter = ''
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

$sessions = @($manager.GetSessions())
if ($AppFilter) {
    $sessions = @($sessions | Where-Object { $_.SourceAppUserModelId -like "*$AppFilter*" })
}

Write-Output ("PROBE_AT={0} SESSIONS={1}" -f (Get-Date -Format 'o'), $sessions.Count)
if ($sessions.Count -eq 0) {
    Write-Output 'NO_SESSION (is playback actually running?)'
    exit 1
}

foreach ($session in $sessions) {
    $info = $session.GetPlaybackInfo()
    $controls = $info.Controls

    $title = ''
    try { $title = (Await ($session.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])).Title }
    catch { $title = '<unavailable>' }

    Write-Output ("APP={0}" -f $session.SourceAppUserModelId)
    Write-Output ("  TITLE={0}" -f $title)
    Write-Output ("  STATUS={0}" -f $info.PlaybackStatus)
    Write-Output ("  IsNextEnabled={0}" -f $controls.IsNextEnabled)
    Write-Output ("  IsPreviousEnabled={0}" -f $controls.IsPreviousEnabled)
    Write-Output ("  IsPlaybackPositionEnabled={0}" -f $controls.IsPlaybackPositionEnabled)
    Write-Output ("  IsShuffleEnabled={0}" -f $controls.IsShuffleEnabled)
    Write-Output ("  IsRepeatEnabled={0}" -f $controls.IsRepeatEnabled)
    Write-Output ("  IsPlayEnabled={0} IsPauseEnabled={1} IsStopEnabled={2}" -f `
        $controls.IsPlayEnabled, $controls.IsPauseEnabled, $controls.IsStopEnabled)
}

exit 0
