# 在使用者登入中的桌面工作階段（console）執行一段 PowerShell，等它結束，印出它的輸出與 exit code。
# SSH 的工作階段沒有桌面：GUI 的啟動、截圖、點擊都要經這裡。
# 用法（在 Windows 上，通常經 wrun.sh）：insession.ps1 -Script <.ps1 路徑> [-Timeout 120]
# 以排程工作（Interactive、目前使用者）在 console 工作階段跑 -Script，輸出寫到檔案再印回來。
# 使用者要登入著、螢幕沒鎖；跑完刪掉排程工作與暫存檔。
param(
  [Parameter(Mandatory = $true)][string]$Script,
  [string]$ScriptArgs = '',
  [int]$Timeout = 120
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$dir = Join-Path $PSScriptRoot 'runs'
New-Item -ItemType Directory -Force $dir | Out-Null
$id = [guid]::NewGuid().ToString('N').Substring(0, 8)
$body = Join-Path $dir "$id.ps1"
$out = Join-Path $dir "$id.out"
$code = Join-Path $dir "$id.code"
@"
`$ProgressPreference = 'SilentlyContinue'
try {
  & '$Script' $ScriptArgs *>&1 | Out-File -FilePath '$out' -Encoding utf8 -Width 400
  `$c = if (`$LASTEXITCODE) { `$LASTEXITCODE } else { 0 }
} catch {
  `$_ | Out-File -FilePath '$out' -Append -Encoding utf8
  `$c = 99
}
Set-Content -Path '$code' -Value `$c
"@ | Set-Content -Path $body -Encoding utf8

$name = "fmp-verify-$id"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$body`""
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings | Out-Null
try {
  Start-ScheduledTask -TaskName $name
  $deadline = (Get-Date).AddSeconds($Timeout)
  while (-not (Test-Path $code)) {
    if ((Get-Date) -gt $deadline) { Write-Output "TIMEOUT after $Timeout s"; exit 124 }
    Start-Sleep -Milliseconds 300
  }
  Start-Sleep -Milliseconds 200
  if (Test-Path $out) { Get-Content $out -Encoding utf8 }
  $c = [int](Get-Content $code)
} finally {
  Unregister-ScheduledTask -TaskName $name -Confirm:$false
  Remove-Item $body, $out, $code -ErrorAction SilentlyContinue
}
exit $c
