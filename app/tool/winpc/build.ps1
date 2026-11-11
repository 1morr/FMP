# Runs inside the desktop session via scheduled task. ASCII only.
param([string]$Mode = 'debug')
$wt = 'C:\fmp-wt\app'
$log = 'C:\fmp-wt\build.log'
Set-Location $wt
"=== start $(Get-Date -Format s) mode=$Mode" | Out-File $log -Encoding ascii
# Native commands: do NOT use ErrorActionPreference=Stop (CMake stderr warnings).
& cmd /c "flutter pub get 2>&1" | Out-File $log -Append -Encoding ascii
"exit pubget=$LASTEXITCODE" | Out-File $log -Append -Encoding ascii
& cmd /c "dart run slang 2>&1" | Out-File $log -Append -Encoding ascii
"exit slang=$LASTEXITCODE" | Out-File $log -Append -Encoding ascii
& cmd /c "flutter build windows --$Mode 2>&1" | Out-File $log -Append -Encoding ascii
"exit build=$LASTEXITCODE" | Out-File $log -Append -Encoding ascii
"=== done $(Get-Date -Format s)" | Out-File $log -Append -Encoding ascii
