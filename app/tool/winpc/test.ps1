# Runs one integration_test file on Windows inside the desktop session via
# scheduled task. Run build.ps1 first (it does pub get and slang). ASCII only.
param([string]$File)
$wt = 'C:\fmp-wt\app'
$log = 'C:\fmp-wt\test.log'
Set-Location $wt
"=== start $(Get-Date -Format s) file=$File" | Out-File $log -Encoding ascii
& cmd /c "flutter test $File -d windows 2>&1" | Out-File $log -Append -Encoding ascii
"exit test=$LASTEXITCODE" | Out-File $log -Append -Encoding ascii
"=== done $(Get-Date -Format s)" | Out-File $log -Append -Encoding ascii
