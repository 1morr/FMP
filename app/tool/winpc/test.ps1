# Runs one integration_test file on Windows inside the desktop session via
# scheduled task. Run build.ps1 first (it does pub get, slang and build_runner). ASCII only.
# -RealRunDir <dir>: a real-run scenario (integration_test/real_run/*_run.dart); its
# driver saves screenshots (shot.ps1 -AppPid, next to this script) and read-back text there.
param([string]$File, [string]$RealRunDir = '')
$wt = 'C:\fmp-wt\app'
$log = 'C:\fmp-wt\test.log'
Set-Location $wt
"=== start $(Get-Date -Format s) file=$File" | Out-File $log -Encoding ascii
$defines = ''
if ($RealRunDir -ne '') {
  $shot = (Join-Path $PSScriptRoot 'shot.ps1') -replace '\\', '/'
  $defines = "--dart-define=FMP_REAL_RUN_DIR=$RealRunDir --dart-define=FMP_REAL_RUN_SHOT_PS1=$shot"
}
& cmd /c "flutter test $File -d windows $defines 2>&1" | Out-File $log -Append -Encoding ascii
"exit test=$LASTEXITCODE" | Out-File $log -Append -Encoding ascii
"=== done $(Get-Date -Format s)" | Out-File $log -Append -Encoding ascii
