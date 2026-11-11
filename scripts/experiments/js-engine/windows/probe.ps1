# Experiment (throwaway): build and run one probe app on Windows.
# Runs inside a scheduled task in the interactive desktop session
# (flutter build windows fails in the SSH session 0). Started by start.ps1.
# ASCII only: PowerShell 5.1 reads BOM-less scripts as cp950.
param([Parameter(Mandatory = $true)][string]$Cand, [switch]$VerboseBuild)

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$app = Join-Path $root "probe_$Cand"
$out = Join-Path $root 'results'
New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $out "raw-$Cand-windows.log"
$done = Join-Path $out "done-$Cand-windows"
$json = Join-Path $out "$Cand-windows.json"
Remove-Item $done, $json -ErrorAction SilentlyContinue
"start $(Get-Date -Format o)" | Out-File $log -Encoding utf8

Push-Location $app
try {
  # Native stderr (CMake warnings) must not abort the script.
  $ErrorActionPreference = 'Continue'
  cmd /c "flutter pub get 2>&1" | Out-File $log -Append -Encoding utf8
  $v = if ($VerboseBuild) { ' -v' } else { '' }
  cmd /c "flutter build windows --debug$v 2>&1" | Out-File $log -Append -Encoding utf8
  "build exit $LASTEXITCODE" | Out-File $log -Append -Encoding utf8
  $exe = Get-ChildItem 'build\windows\x64\runner\Debug\*.exe' | Select-Object -First 1
  if ($null -eq $exe) { throw 'no exe built' }
  $result = Join-Path $env:TEMP "js-engine-probe-$Cand.json"
  Remove-Item $result -ErrorAction SilentlyContinue
  $p = Start-Process -FilePath $exe.FullName -PassThru
  if (-not $p.WaitForExit(300000)) { $p.Kill(); 'probe timed out after 300s' | Out-File $log -Append -Encoding utf8 }
  "probe exit $($p.ExitCode)" | Out-File $log -Append -Encoding utf8
  if (Test-Path $result) { Copy-Item $result $json } else { 'no result file' | Out-File $log -Append -Encoding utf8 }
} catch {
  "error: $_" | Out-File $log -Append -Encoding utf8
} finally {
  Pop-Location
  "end $(Get-Date -Format o)" | Out-File $log -Append -Encoding utf8
  New-Item -ItemType File -Force $done | Out-Null
}
