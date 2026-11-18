# Runs one integration_test file on Windows inside the desktop session via
# scheduled task. Run build.ps1 first (it does pub get, slang and build_runner). ASCII only.
# -RealRunDir <dir>: a real-run scenario (integration_test/real_run/*_run.dart); its
# driver saves screenshots (shot.ps1 -AppPid, next to this script) and read-back text there.
# -ScratchData <name>: the app keeps its data in %TEMP%\<name> (FMP_SCRATCH_DATA), not the
# dev app's; the gate and real runs both pass it.
# A real run also asks Windows to keep the display and system on while it runs
# (SetThreadExecutionState on this thread, restored afterwards; no mouse or keyboard input):
# with the display asleep PrintWindow captures a blank window (ticket 06b).
param([string]$File, [string]$RealRunDir = '', [string]$ScratchData = '')
$wt = 'C:\fmp-wt\app'
$log = 'C:\fmp-wt\test.log'
Set-Location $wt
"=== start $(Get-Date -Format s) file=$File" | Out-File $log -Encoding ascii
$defines = ''
if ($ScratchData -ne '') { $defines = "--dart-define=FMP_SCRATCH_DATA=$ScratchData" }
if ($RealRunDir -ne '') {
  $shot = (Join-Path $PSScriptRoot 'shot.ps1') -replace '\\', '/'
  $defines = "$defines --dart-define=FMP_REAL_RUN_DIR=$RealRunDir --dart-define=FMP_REAL_RUN_SHOT_PS1=$shot"
}
if ($RealRunDir -ne '') {
  Add-Type @"
using System; using System.Runtime.InteropServices;
public class Awake { [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f); }
"@
  # ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED
  $previous = [Awake]::SetThreadExecutionState([uint32]2147483651)
  "awake previous=$previous" | Out-File $log -Append -Encoding ascii
}
try {
  & cmd /c "flutter test $File -d windows $defines 2>&1" | Out-File $log -Append -Encoding ascii
  "exit test=$LASTEXITCODE" | Out-File $log -Append -Encoding ascii
} finally {
  # ES_CONTINUOUS alone: back to the normal idle timers.
  if ($RealRunDir -ne '') { [Awake]::SetThreadExecutionState([uint32]2147483648) | Out-Null }
}
"=== done $(Get-Date -Format s)" | Out-File $log -Append -Encoding ascii
