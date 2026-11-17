# Screenshot the FMP window to PNG with the screen copy of its window rect. ASCII only.
# Default: launch -Exe in the desktop session, wait -Wait s, screenshot, close the app.
# -AppPid <id>: screenshot the window of that running process instead and leave it open;
# the real-run driver calls this from inside the app (docs/development.md, real runs).
# Neither moves the cursor: the window is raised to the top before the copy.
# -Size "w,h": before the screenshot, resize the window to w x h logical pixels
# (scaled by the window DPI, frame included); the log records the client size the
# app ended up with, so a size under the minimum shows the clamp.
# The app's stdout/stderr go to C:\fmp-wt\app-stdout.txt / app-stderr.txt (a Dart VM
# abort prints there); after closing the window the log says exited_after_close.
param([string]$Exe, [int]$AppPid = 0, [string]$Out = 'C:\fmp-wt\shot.png', [int]$Wait = 8, [string]$Size = '')
$log = if ($AppPid -ne 0) { 'C:\fmp-wt\shot-pid.log' } else { 'C:\fmp-wt\shot.log' }
"start" | Out-File $log -Encoding ascii
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W { 
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
}
"@
[W]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
if ($AppPid -ne 0) {
  "pid=[$AppPid] out=[$Out]" | Out-File $log -Append -Encoding ascii
  try { $p = Get-Process -Id $AppPid -ErrorAction Stop } catch { "ERR $_" | Out-File $log -Append -Encoding ascii; exit 1 }
} else {
  "exe=[$Exe]" | Out-File $log -Append -Encoding ascii
  try { $Exe = $Exe -replace "/", "\"; $p = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe) -PassThru -ErrorAction Stop -RedirectStandardOutput C:\fmp-wt\app-stdout.txt -RedirectStandardError C:\fmp-wt\app-stderr.txt } catch { "ERR $_" | Out-File $log -Append -Encoding ascii; exit 1 }
  Start-Sleep -Seconds $Wait
}
$p.Refresh()
"pid=$($p.Id) exited=$($p.HasExited) title=$($p.MainWindowTitle)" | Out-File $log -Append -Encoding ascii
if (-not $p.HasExited -and $p.MainWindowHandle -ne 0) {
  $h = $p.MainWindowHandle
  [W]::ShowWindow($h, 9) | Out-Null
  # raise: attach to foreground thread, TOPMOST round trip, SetForegroundWindow.
  function Raise {
    $fg = [W]::GetForegroundWindow(); $ft = [W]::GetWindowThreadProcessId($fg, [IntPtr]::Zero); $me = [W]::GetCurrentThreadId()
    [W]::AttachThreadInput($me, $ft, $true) | Out-Null
    [W]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x43) | Out-Null   # HWND_TOPMOST, NOMOVE|NOSIZE|SHOWWINDOW
    [W]::SetForegroundWindow($h) | Out-Null
    [W]::AttachThreadInput($me, $ft, $false) | Out-Null
  }
  Raise
  "foreground_is_fmp=$([W]::GetForegroundWindow() -eq $h)" | Out-File $log -Append -Encoding ascii
  Start-Sleep -Milliseconds 800
  if ($Size -ne '') {
    $wh = $Size.Split(','); $k = [W]::GetDpiForWindow($h) / 96.0
    [W]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, [int]([int]$wh[0] * $k), [int]([int]$wh[1] * $k), 0x16) | Out-Null   # NOMOVE|NOZORDER|NOACTIVATE
    Start-Sleep -Seconds 2
    $c = New-Object W+RECT; [W]::GetClientRect($h, [ref]$c) | Out-Null
    "size [$Size] client_logical=$([int](($c.R - $c.L) / $k))x$([int](($c.B - $c.T) / $k))" | Out-File $log -Append -Encoding ascii
  }
  function Shot($path) {
    $r = New-Object W+RECT
    [W]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $hh = $r.B - $r.T
    "rect $($r.L),$($r.T) ${w}x${hh}" | Out-File $log -Append -Encoding ascii
    $bmp = New-Object System.Drawing.Bitmap $w, $hh
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    "saved $path" | Out-File $log -Append -Encoding ascii
  }
  Shot $Out
  [W]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 0x43) | Out-Null   # HWND_NOTOPMOST
}
if ($AppPid -ne 0) { if ($p.HasExited -or $p.MainWindowHandle -eq 0 -or -not (Test-Path $Out)) { "no window or no shot" | Out-File $log -Append -Encoding ascii; exit 1 }; "done" | Out-File $log -Append -Encoding ascii; exit 0 }
if (-not $p.HasExited) { $null = $p.CloseMainWindow(); Start-Sleep 6; "exited_after_close=$($p.HasExited) code=$($p.ExitCode)" | Out-File $log -Append -Encoding ascii; if (-not $p.HasExited) { $p.Kill() } }
"closed" | Out-File $log -Append -Encoding ascii
