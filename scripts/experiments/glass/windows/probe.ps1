# Experiment (throwaway), M0 ticket 05b: build the glass probe on Windows,
# launch it, screenshot the window for every scene the probe announces in
# %TEMP%\glass-probe-status.json, then copy the results. Runs as a scheduled
# task in the desktop session (started by run-windows.sh through
# app/tool/winpc/run_task.sh). ASCII only: PowerShell 5.1 reads BOM-less
# scripts as cp950.
param([string]$Mode = 'profile', [string]$Defines = '', [string]$Name = 'windows', [string]$AppArgs = '', [int]$Wait = 400)

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$app = Join-Path $root 'probe'
$out = Join-Path $root 'results'
$shots = Join-Path $out 'shots'
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $shots | Out-Null
$log = Join-Path $out 'raw-windows.log'
"start $(Get-Date -Format o) mode=$Mode defines=$Defines" | Out-File $log -Encoding utf8

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W {
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int s);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@
[W]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null

function Shot($h, $path) {
  [W]::ShowWindow($h, 9) | Out-Null
  $fg = [W]::GetForegroundWindow(); $ft = [W]::GetWindowThreadProcessId($fg, [IntPtr]::Zero); $me = [W]::GetCurrentThreadId()
  [W]::AttachThreadInput($me, $ft, $true) | Out-Null
  [W]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x43) | Out-Null
  [W]::SetForegroundWindow($h) | Out-Null
  [W]::AttachThreadInput($me, $ft, $false) | Out-Null
  Start-Sleep -Milliseconds 1000
  $r = New-Object W+RECT
  [W]::GetWindowRect($h, [ref]$r) | Out-Null
  # Screen copy (CopyFromScreen) came back white for this probe (2026-11-12),
  # so render the window itself: PrintWindow with PW_RENDERFULLCONTENT (2).
  $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  $ok = [W]::PrintWindow($h, $hdc, 2)
  $g.ReleaseHdc($hdc)
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  $g2 = $null
  $bmp2 = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
  $g2 = [System.Drawing.Graphics]::FromImage($bmp2)
  $g2.CopyFromScreen($r.L, $r.T, 0, 0, $bmp2.Size)
  $bmp2.Save(($path -replace '\.png$', '.screen.png'), [System.Drawing.Imaging.ImageFormat]::Png)
  $g2.Dispose(); $bmp2.Dispose()
  [W]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 0x43) | Out-Null
  "shot $path printwindow=$ok foreground=$([W]::GetForegroundWindow() -eq $h)" | Out-File $log -Append -Encoding utf8
}

Push-Location $app
try {
  $ErrorActionPreference = 'Continue'
  cmd /c "flutter pub get 2>&1" | Out-File $log -Append -Encoding utf8
  $d = ''
  foreach ($kv in ($Defines -split ';')) { if ($kv) { $d += " --dart-define=$kv" } }
  cmd /c "flutter build windows --$Mode$d 2>&1" | Out-File $log -Append -Encoding utf8
  "exit build=$LASTEXITCODE" | Out-File $log -Append -Encoding utf8
  $cfg = (Get-Culture).TextInfo.ToTitleCase($Mode)
  $exe = Get-ChildItem "build\windows\x64\runner\$cfg\*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $exe) { throw 'no exe built' }

  $status = Join-Path $env:TEMP 'glass-probe-status.json'
  $result = Join-Path $env:TEMP 'glass-probe.json'
  Remove-Item $status, $result -ErrorAction SilentlyContinue
  if ($AppArgs) {
    $p = Start-Process -FilePath $exe.FullName -ArgumentList $AppArgs -WorkingDirectory $exe.DirectoryName -PassThru -ErrorAction Stop
  } else {
    $p = Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru -ErrorAction Stop
  }
  $seen = @{}
  $done = $false
  for ($i = 0; $i -lt $Wait * 2 -and -not $done; $i++) {
    Start-Sleep -Milliseconds 500
    if ($p.HasExited) { 'app exited early' | Out-File $log -Append -Encoding utf8; break }
    if (-not (Test-Path $status)) { continue }
    try { $s = Get-Content $status -Raw | ConvertFrom-Json } catch { continue }
    if ($s.phase -eq 'scene' -and -not $seen.ContainsKey($s.variant)) {
      $seen[$s.variant] = $true
      $p.Refresh()
      Shot $p.MainWindowHandle (Join-Path $shots "windows-$($s.variant).png")
    }
    if ($s.phase -eq 'done') { $done = $true }
  }
  "done=$done" | Out-File $log -Append -Encoding utf8
  if ($done -and $Name -like '*a11y*') { $p.Refresh(); Shot $p.MainWindowHandle (Join-Path $shots 'windows-a11y.png') }
  if (Test-Path $result) { Copy-Item $result (Join-Path $out "$Name.json") } else { 'no result file' | Out-File $log -Append -Encoding utf8 }
  $p.Refresh()
  if (-not $p.HasExited) { $null = $p.CloseMainWindow(); Start-Sleep 2; if (-not $p.HasExited) { $p.Kill() } }
} catch {
  "error: $_" | Out-File $log -Append -Encoding utf8
} finally {
  Pop-Location
  "=== done $(Get-Date -Format o)" | Out-File $log -Append -Encoding utf8
}
