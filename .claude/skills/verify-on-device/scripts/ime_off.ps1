# Closes the IME (alphanumeric input) for the FMP Dev window only, then reports its state.
Add-Type @"
using System; using System.Runtime.InteropServices;
public class ImeS {
  [DllImport("imm32.dll")] public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l,t,r,b; }
  [StructLayout(LayoutKind.Sequential)] public struct GTI { public int cbSize; public int flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rc; }
  [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GTI g);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
"@
$p = Get-Process fmp -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq 'FMP Dev' } | Select-Object -First 1
if (-not $p) { 'no FMP Dev window'; exit 2 }
$pid2=0; $tid=[ImeS]::GetWindowThreadProcessId($p.MainWindowHandle,[ref]$pid2)
$g = New-Object ImeS+GTI; $g.cbSize=[Runtime.InteropServices.Marshal]::SizeOf($g); [ImeS]::GetGUIThreadInfo($tid,[ref]$g) | Out-Null
$ime = [ImeS]::ImmGetDefaultIMEWnd($g.hwndFocus)
[void][ImeS]::SendMessage($ime, 0x283, [IntPtr]6, [IntPtr]0)
$open = [ImeS]::SendMessage($ime, 0x283, [IntPtr]5, [IntPtr]0)
$conv = [ImeS]::SendMessage($ime, 0x283, [IntPtr]1, [IntPtr]0)
"focus=$($g.hwndFocus) imeWnd=$ime open=$open conversion=0x{0:X}" -f [int64]$conv
