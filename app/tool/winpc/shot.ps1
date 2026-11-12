# Launch fmp.exe in desktop session, wait, screenshot window to PNG, close app. ASCII only.
# -Type <text>: after raising the window, press Tab (focus the first field), type
# <text> as Unicode SendInput (bypasses the IME), press Enter, wait -TypeWait s.
# -Click "x,y": then left-click at x,y logical pixels of the client area (scaled by
# the window DPI), wait -ClickWait s. Several clicks "x,y;x,y;...": each one is
# followed by -ClickWait s and a screenshot <Out without .png>-<n>.png (n from 1).
# The app's stdout/stderr go to C:\fmp-wt\app-stdout.txt / app-stderr.txt (a Dart VM
# abort prints there); after closing the window the log says exited_after_close.
param([string]$Exe, [string]$Out = 'C:\fmp-wt\shot.png', [int]$Wait = 8, [string]$Type = '', [int]$TypeWait = 10, [string]$Click = '', [int]$ClickWait = 8)
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
 [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
 [StructLayout(LayoutKind.Sequential)] public struct KI { public ushort vk; public ushort scan; public uint flags; public uint time; public IntPtr extra; }
 [StructLayout(LayoutKind.Sequential)] public struct MI { public int dx; public int dy; public uint data; public uint flags; public uint time; public IntPtr extra; }
 [StructLayout(LayoutKind.Explicit)] public struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; [FieldOffset(8)] public MI mi; }
 [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] i, int size);
 [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
 static void Send(ushort vk, ushort scan, uint flags) {
  var i = new INPUT[1]; i[0].type = 1; i[0].ki.vk = vk; i[0].ki.scan = scan; i[0].ki.flags = flags;
  SendInput(1, i, Marshal.SizeOf(typeof(INPUT)));
 }
 public static void Key(ushort vk) { ushort s = (ushort)MapVirtualKey(vk, 0); Send(vk, s, 0); Send(vk, s, 2); }
 public static void Text(string t) { foreach (char c in t) { Send(0, c, 4); Send(0, c, 6); } }
 public static string Click(IntPtr h, int x, int y) {
  double k = GetDpiForWindow(h) / 96.0; var p = new POINT(); p.X = (int)(x * k); p.Y = (int)(y * k);
  ClientToScreen(h, ref p); SetCursorPos(p.X, p.Y);
  var i = new INPUT[2]; i[0].type = 0; i[0].mi.flags = 2; i[1].type = 0; i[1].mi.flags = 4;
  SendInput(2, i, Marshal.SizeOf(typeof(INPUT)));
  return p.X + "," + p.Y;
 }
}
"@
[W]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
"exe=[$Exe]" | Out-File $log -Append -Encoding ascii
try { $Exe = $Exe -replace "/", "\"; $p = Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe) -PassThru -ErrorAction Stop -RedirectStandardOutput C:\fmp-wt\app-stdout.txt -RedirectStandardError C:\fmp-wt\app-stderr.txt } catch { "ERR $_" | Out-File $log -Append -Encoding ascii; exit 1 }
Start-Sleep -Seconds $Wait
$p.Refresh()
"pid=$($p.Id) exited=$($p.HasExited) title=$($p.MainWindowTitle)" | Out-File $log -Append -Encoding ascii
if (-not $p.HasExited -and $p.MainWindowHandle -ne 0) {
  $h = $p.MainWindowHandle
  [W]::ShowWindow($h, 9) | Out-Null
  # raise: attach to foreground thread, TOPMOST round trip, SetForegroundWindow.
  # Repeated before typing and clicking: another app can take the foreground meanwhile.
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
  if ($Type -ne '') {
    Raise; "foreground_is_fmp_before_typing=$([W]::GetForegroundWindow() -eq $h)" | Out-File $log -Append -Encoding ascii
    [W]::Key(0x09); Start-Sleep -Milliseconds 300
    [W]::Text($Type); Start-Sleep -Milliseconds 300
    [W]::Key(0x0D)
    "typed [$Type], waiting $TypeWait s" | Out-File $log -Append -Encoding ascii
    Start-Sleep -Seconds $TypeWait
    "foreground_is_fmp_after_typing=$([W]::GetForegroundWindow() -eq $h)" | Out-File $log -Append -Encoding ascii
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
  if ($Click -ne '') {
    $clicks = $Click.Split(';')
    $n = 0
    foreach ($c in $clicks) {
      $n++
      Raise; "foreground_is_fmp_before_click_$n=$([W]::GetForegroundWindow() -eq $h)" | Out-File $log -Append -Encoding ascii
      $xy = $c.Split(',')
      $at = [W]::Click($h, [int]$xy[0], [int]$xy[1])
      "clicked [$c] at screen $at, waiting $ClickWait s" | Out-File $log -Append -Encoding ascii
      Start-Sleep -Seconds $ClickWait
      "foreground_is_fmp_after_click_$n=$([W]::GetForegroundWindow() -eq $h)" | Out-File $log -Append -Encoding ascii
      if ($clicks.Count -gt 1) { Shot ($Out -replace '\.png$', "-$n.png") }
    }
  }
  Shot $Out
  [W]::SetWindowPos($h, [IntPtr](-2), 0, 0, 0, 0, 0x43) | Out-Null   # HWND_NOTOPMOST
}
if (-not $p.HasExited) { $null = $p.CloseMainWindow(); Start-Sleep 6; "exited_after_close=$($p.HasExited) code=$($p.ExitCode)" | Out-File $log -Append -Encoding ascii; if (-not $p.HasExited) { $p.Kill() } }
"closed" | Out-File $log -Append -Encoding ascii
