# Experiment (throwaway), M0 ticket 04: build the probe on Windows, launch it,
# wait for the page-loaded result file, screenshot the window, close the app.
# Runs as a scheduled task in the desktop session (started by run-windows.sh
# through app/tool/winpc/run_task.sh). ASCII only: PowerShell 5.1 reads
# BOM-less scripts as cp950.
param([string]$Mode = 'debug', [int]$Wait = 90, [switch]$VerboseBuild)

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$app = Join-Path $root 'probe'
$out = Join-Path $root 'results'
New-Item -ItemType Directory -Force $out | Out-Null
$log = Join-Path $out 'raw-windows.log'
$json = Join-Path $out 'windows.json'
$png = Join-Path $out 'windows.png'
Remove-Item $json, $png -ErrorAction SilentlyContinue
"start $(Get-Date -Format o) mode=$Mode patch=$env:FMPX_WIN_PATCH codepage=$([Console]::OutputEncoding.CodePage)" | Out-File $log -Encoding utf8

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
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@
[W]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null

Push-Location $app
try {
  # Native stderr (CMake warnings) must not abort the script.
  $ErrorActionPreference = 'Continue'
  cmd /c "flutter pub get 2>&1" | Out-File $log -Append -Encoding utf8
  $v = if ($VerboseBuild) { ' -v' } else { '' }
  cmd /c "flutter build windows --$Mode$v 2>&1" | Out-File $log -Append -Encoding utf8
  "exit build=$LASTEXITCODE" | Out-File $log -Append -Encoding utf8
  $cfg = if ($Mode -eq 'release') { 'Release' } else { 'Debug' }
  $exe = Get-ChildItem "build\windows\x64\runner\$cfg\*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $exe) { throw 'no exe built' }

  $result = Join-Path $env:TEMP 'inappwebview-probe.json'
  Remove-Item $result -ErrorAction SilentlyContinue
  $p = Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru -ErrorAction Stop
  for ($i = 0; $i -lt $Wait -and -not (Test-Path $result); $i++) { Start-Sleep 1 }
  Start-Sleep 2
  $p.Refresh()
  "pid=$($p.Id) exited=$($p.HasExited) waited=${i}s" | Out-File $log -Append -Encoding utf8
  if (Test-Path $result) { Copy-Item $result $json } else { 'no result file' | Out-File $log -Append -Encoding utf8 }

  if (-not $p.HasExited -and $p.MainWindowHandle -ne 0) {
    $h = $p.MainWindowHandle
    [W]::ShowWindow($h, 9) | Out-Null
    [W]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x43) | Out-Null
    [W]::SetForegroundWindow($h) | Out-Null
    "foreground_is_probe=$([W]::GetForegroundWindow() -eq $h)" | Out-File $log -Append -Encoding utf8
    Start-Sleep -Milliseconds 800
    $r = New-Object W+RECT
    [W]::GetWindowRect($h, [ref]$r) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    [W]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 0x43) | Out-Null
  }
  if (-not $p.HasExited) { $null = $p.CloseMainWindow(); Start-Sleep 2; if (-not $p.HasExited) { $p.Kill() } }
} catch {
  "error: $_" | Out-File $log -Append -Encoding utf8
} finally {
  Pop-Location
  "=== done $(Get-Date -Format o)" | Out-File $log -Append -Encoding utf8
}
