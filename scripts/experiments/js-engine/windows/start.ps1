# Experiment (throwaway): run probe.ps1 as a scheduled task in the logged-in
# user's desktop session, so the Windows build and the app get a desktop.
# ASCII only: PowerShell 5.1 reads BOM-less scripts as cp950.
param([Parameter(Mandatory = $true)][string]$Cand, [switch]$VerboseBuild)

$probe = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'probe.ps1'
$name = "fmp-js-engine-probe-$Cand"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$probe`" -Cand $Cand$(if ($VerboseBuild) { ' -VerboseBuild' })"
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $name
"started $name"
