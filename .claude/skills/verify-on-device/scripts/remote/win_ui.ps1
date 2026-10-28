# FMP Dev 視窗的低階操作（在使用者桌面工作階段經 insession.ps1 執行；msaa_tree.ps1 讀不到或要拖曳、縮放、組合鍵時用）。
# 座標一律是相對視窗左上角的物理像素；只對行程 fmp、標題 FMP Dev 的視窗。
#   -Op info                         視窗矩形、DPI、前景與否、最大化與否
#   -Op raise                        拉到前景
#   -Op move   -X -Y                 游標移到 (X,Y)
#   -Op click  -X -Y [-Button right] [-Double]
#   -Op drag   -X -Y -X2 -Y2 [-Steps 20] [-HoldMs 0]   左鍵按住拖曳
#   -Op wheel  -X -Y -Delta -120     滾輪
#   -Op key    -Keys 'ctrl+f'        組合鍵（真實掃描碼）；多個用空白分開：'tab tab enter'
#   -Op bounds -X -Y -W -H           設定外框位置與大小（螢幕座標，物理像素）
#   -Op sys    -Cmd max|min|restore|close   WM_SYSCOMMAND / WM_CLOSE
#   -Op shot   -Out <png>            PrintWindow 截視窗
#   -Op screen -Out <png>            從螢幕截視窗所在的矩形（含 hover 等即時畫面）
param(
  [Parameter(Mandatory = $true)][string]$Op,
  [int]$X = 0, [int]$Y = 0, [int]$X2 = 0, [int]$Y2 = 0, [int]$W = 0, [int]$H = 0,
  [int]$Steps = 20, [int]$HoldMs = 0, [int]$Delta = -120,
  [string]$Button = 'left', [switch]$Double, [string]$Keys = '', [string]$Cmd = '', [string]$Out = '',
  [string]$Title = 'FMP Dev'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
if (-not ('FmpUi' -as [type])) {
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class FmpUi {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, int d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint f, UIntPtr e);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] public struct CURSORINFO { public int cbSize; public int flags; public IntPtr hCursor; public POINT pt; }
  [DllImport("user32.dll")] public static extern bool GetCursorInfo(ref CURSORINFO ci);
  [DllImport("user32.dll")] public static extern IntPtr LoadCursor(IntPtr inst, int id);
  public static IntPtr CurrentCursor() { CURSORINFO c = new CURSORINFO(); c.cbSize = Marshal.SizeOf(c); GetCursorInfo(ref c); return c.hCursor; }
  public static bool Raise(IntPtr h) {
    IntPtr fg = GetForegroundWindow(); uint pid;
    uint fgThread = GetWindowThreadProcessId(fg, out pid);
    uint me = GetCurrentThreadId();
    AttachThreadInput(me, fgThread, true);
    SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 3);
    SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, 3);
    SetForegroundWindow(h);
    AttachThreadInput(me, fgThread, false);
    System.Threading.Thread.Sleep(150);
    return GetForegroundWindow() == h;
  }
}
"@
}
[FmpUi]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null

$proc = Get-Process fmp -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq $Title } | Select-Object -First 1
if (-not $proc) { Write-Output "no '$Title' window"; exit 1 }
$hwnd = $proc.MainWindowHandle
$r = New-Object FmpUi+RECT
[FmpUi]::GetWindowRect($hwnd, [ref]$r) | Out-Null

function Abs([int]$x, [int]$y) { return @(($r.L + $x), ($r.T + $y)) }
function MouseTo([int]$x, [int]$y) { $p = Abs $x $y; [FmpUi]::SetCursorPos($p[0], $p[1]) | Out-Null }
$down = @{ left = 0x2; right = 0x8 }; $up = @{ left = 0x4; right = 0x10 }

$vk = @{
  ctrl = 0xA2; shift = 0xA0; alt = 0xA4; win = 0x5B; tab = 0x09; enter = 0x0D; esc = 0x1B; space = 0x20;
  left = 0x25; up = 0x26; right = 0x27; down = 0x28; f4 = 0x73; f6 = 0x75; f5 = 0x74; home = 0x24; end = 0x23;
  backspace = 0x08; delete = 0x2E; pageup = 0x21; pagedown = 0x22
}
$extended = @(0x25, 0x26, 0x27, 0x28, 0x24, 0x23, 0x2E, 0x21, 0x22, 0x5B)
function KeyCode([string]$k) {
  if ($vk.ContainsKey($k)) { return $vk[$k] }
  if ($k.Length -eq 1) { return [int][char]$k.ToUpper() }
  throw "unknown key $k"
}
function Press([string]$combo) {
  $codes = $combo.Split('+') | ForEach-Object { KeyCode $_ }
  foreach ($c in $codes) {
    $f = if ($extended -contains $c) { 1 } else { 0 }
    [FmpUi]::keybd_event([byte]$c, [byte][FmpUi]::MapVirtualKey($c, 0), $f, [UIntPtr]::Zero); Start-Sleep -Milliseconds 30
  }
  [array]::Reverse($codes)
  foreach ($c in $codes) {
    $f = if ($extended -contains $c) { 3 } else { 2 }
    [FmpUi]::keybd_event([byte]$c, [byte][FmpUi]::MapVirtualKey($c, 0), $f, [UIntPtr]::Zero); Start-Sleep -Milliseconds 30
  }
}
function Need-Front { if (-not [FmpUi]::Raise($hwnd)) { Write-Output 'could not raise the window'; exit 3 } }

switch ($Op) {
  'info' {
    "rect=$($r.L),$($r.T),$($r.R),$($r.B) size=$($r.R - $r.L)x$($r.B - $r.T) dpi=$([FmpUi]::GetDpiForWindow($hwnd)) fg=$([FmpUi]::GetForegroundWindow() -eq $hwnd) max=$([FmpUi]::IsZoomed($hwnd)) min=$([FmpUi]::IsIconic($hwnd)) pid=$($proc.Id)"
  }
  'raise' { Need-Front; 'raised' }
  'cursor' {
    Need-Front
    $names = @{ 32512 = 'arrow'; 32644 = 'size-we'; 32645 = 'size-ns'; 32642 = 'size-nwse'; 32643 = 'size-nesw'; 32649 = 'hand'; 32513 = 'ibeam' }
    foreach ($pt in $Keys.Split(' ')) {
      if (-not $pt) { continue }
      $xy = $pt.Split(','); MouseTo ([int]$xy[0]) ([int]$xy[1]); Start-Sleep -Milliseconds 350
      $cur = [FmpUi]::CurrentCursor(); $n = 'other'
      foreach ($k in $names.Keys) { if ([FmpUi]::LoadCursor([IntPtr]::Zero, $k) -eq $cur) { $n = $names[$k] } }
      "$pt -> $n"
    }
  }
  'move' { MouseTo $X $Y; 'moved' }
  'click' {
    Need-Front; MouseTo $X $Y; Start-Sleep -Milliseconds 80
    $n = if ($Double) { 2 } else { 1 }
    for ($i = 0; $i -lt $n; $i++) {
      [FmpUi]::mouse_event($down[$Button], 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
      [FmpUi]::mouse_event($up[$Button], 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
    }
    'clicked'
  }
  'drag' {
    Need-Front; MouseTo $X $Y; Start-Sleep -Milliseconds 100
    [FmpUi]::mouse_event(0x2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120
    for ($i = 1; $i -le $Steps; $i++) {
      $p = Abs ([int]($X + ($X2 - $X) * $i / $Steps)) ([int]($Y + ($Y2 - $Y) * $i / $Steps))
      $sw = [Windows.Forms.Screen]::PrimaryScreen.Bounds.Width; $sh = [Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
      [FmpUi]::mouse_event(0x8001, [int]($p[0] * 65535 / ($sw - 1)), [int]($p[1] * 65535 / ($sh - 1)), 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 25
    }
    if ($HoldMs -gt 0) { Start-Sleep -Milliseconds $HoldMs }
    [FmpUi]::mouse_event(0x4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150
    'dragged'
  }
  'wheel' { Need-Front; MouseTo $X $Y; Start-Sleep -Milliseconds 80; [FmpUi]::mouse_event(0x800, 0, 0, $Delta, [UIntPtr]::Zero); 'wheeled' }
  'key' { Need-Front; foreach ($k in $Keys.Split(' ')) { if ($k) { Press $k; Start-Sleep -Milliseconds 120 } }; 'keys sent' }
  'bounds' { [FmpUi]::SetWindowPos($hwnd, [IntPtr]::Zero, $X, $Y, $W, $H, 0x14) | Out-Null; Start-Sleep -Milliseconds 300; [FmpUi]::GetWindowRect($hwnd, [ref]$r) | Out-Null; "size=$($r.R - $r.L)x$($r.B - $r.T)" }
  'sys' {
    switch ($Cmd) {
      'max' { [FmpUi]::PostMessage($hwnd, 0x112, [IntPtr]0xF030, [IntPtr]::Zero) | Out-Null }
      'min' { [FmpUi]::PostMessage($hwnd, 0x112, [IntPtr]0xF020, [IntPtr]::Zero) | Out-Null }
      'restore' { [FmpUi]::PostMessage($hwnd, 0x112, [IntPtr]0xF120, [IntPtr]::Zero) | Out-Null }
      'close' { [FmpUi]::PostMessage($hwnd, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null }
    }
    Start-Sleep -Milliseconds 500; "sys $Cmd sent"
  }
  'shot' {
    $bmp = New-Object Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
    $g = [Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc()
    [FmpUi]::PrintWindow($hwnd, $dc, 2) | Out-Null
    $g.ReleaseHdc($dc); $g.Dispose(); $bmp.Save($Out, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); "saved $Out"
  }
  'screen' {
    Need-Front
    $bmp = New-Object Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size); $g.Dispose()
    $bmp.Save($Out, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); "saved $Out"
  }
  default { "unknown op $Op"; exit 2 }
}
