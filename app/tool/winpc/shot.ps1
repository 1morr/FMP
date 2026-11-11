# Launch fmp.exe in desktop session, wait, screenshot window to PNG, close app. ASCII only.
param([string]$Exe, [string]$Out = 'C:\fmp-wt\shot.png', [int]$Wait = 8)
$log = 'C:\fmp-wt\shot.log'
"start" | Out-File $log -Encoding ascii
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
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
}
"@
[W]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
"exe=[$Exe]" | Out-File $log -Append -Encoding ascii
try { $Exe = $Exe -replace "/", "\"; $p = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe) -PassThru -ErrorAction Stop } catch { "ERR $_" | Out-File $log -Append -Encoding ascii; exit 1 }
Start-Sleep -Seconds $Wait
$p.Refresh()
"pid=$($p.Id) exited=$($p.HasExited) title=$($p.MainWindowTitle)" | Out-File $log -Append -Encoding ascii
if (-not $p.HasExited -and $p.MainWindowHandle -ne 0) {
  $h = $p.MainWindowHandle
  [W]::ShowWindow($h, 9) | Out-Null
  # raise: attach to foreground thread, TOPMOST round trip, SetForegroundWindow
  $fg = [W]::GetForegroundWindow(); $ft = [W]::GetWindowThreadProcessId($fg, [IntPtr]::Zero); $me = [W]::GetCurrentThreadId()
  [W]::AttachThreadInput($me, $ft, $true) | Out-Null
  [W]::SetWindowPos($h, [IntPtr](-1), 0, 0, 0, 0, 0x43) | Out-Null   # HWND_TOPMOST, NOMOVE|NOSIZE|SHOWWINDOW
  [W]::SetForegroundWindow($h) | Out-Null
  [W]::AttachThreadInput($me, $ft, $false) | Out-Null
  "foreground_is_fmp=$([W]::GetForegroundWindow() -eq $h)" | Out-File $log -Append -Encoding ascii
  Start-Sleep -Milliseconds 800
  $r = New-Object W+RECT
  [W]::GetWindowRect($h, [ref]$r) | Out-Null
  $w = $r.R - $r.L; $hh = $r.B - $r.T
  "rect $($r.L),$($r.T) ${w}x${hh}" | Out-File $log -Append -Encoding ascii
  $bmp = New-Object System.Drawing.Bitmap $w, $hh
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
  $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  [W]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 0x43) | Out-Null   # HWND_NOTOPMOST
  "saved $Out" | Out-File $log -Append -Encoding ascii
}
if (-not $p.HasExited) { $null = $p.CloseMainWindow(); Start-Sleep 2; if (-not $p.HasExited) { $p.Kill() } }
"closed" | Out-File $log -Append -Encoding ascii
