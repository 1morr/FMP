# Reads, and clicks, what a screen reader can reach in the Windows build, via MSAA.
#
# UI Automation (and so `orca computer get-app-state`) shows nothing under
# `pane FLUTTERVIEW`, walked or hit-tested, even with a healthy tree and
# Narrator running: flutter_windows.dll answers WM_GETOBJECT through MSAA
# (`LresultFromObject`) and carries no UIA provider (`UiaReturnRawElementProvider`
# is absent; checked on Flutter 3.47.1). oleacc reaches the real tree.
# Semantics are on from startup, so Narrator does not need to be running.
#
# Dump, with each element's screen rectangle in physical pixels:
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass `
#     -File .claude/skills/verify-on-device/scripts/msaa_tree.ps1 [-Proc fmp] [-Filter button]
#
# Click an element by its exact accessible name (after raising the window):
#
#   ... msaa_tree.ps1 -Click '關閉' [-Role 'push button'] [-Index 0]
#
# The engine exposes no MSAA default action, so -Click moves the mouse to the
# element's centre and clicks; the element must be on screen. It then parks the
# cursor on the window's top-left corner: a tooltip left under the pointer
# freezes the tree for the rest of the run (docs/troubleshooting.md). A name
# matches when it equals -Click or when its first line does: rail tabs and list
# rows carry multi-line names such as "設定" + "第 6 個分頁 (共 6 個)".
#
# First output line is `nodes=<n>`. Compare it with the framework's tree
# (`ext.flutter.debugDumpSemanticsTreeInInverseHitTestOrder`): a handful of
# nodes against a full framework tree means the accessibility bridge stopped
# taking updates (see docs/troubleshooting.md), and -Click cannot see past it.
#
# Exit codes: 0 = ok, 1 = no window or no FLUTTERVIEW, 2 = -Click matched
# nothing, 3 = the window could not be brought to the foreground.

[CmdletBinding()]
param(
    [string]$Proc = 'fmp',
    [string]$Filter = '',
    [string]$Click = '',
    [string]$Role = '',
    [int]$Index = 0,
    [int]$MaxDepth = 40,
    [int]$Limit = 3000
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 下面的 C# 區塊只能寫 ASCII：Windows PowerShell 5.1 用系統代碼頁讀 Add-Type 的
# 暫存 .cs，中文註解會解碼壞掉，把下一行吞進註解。
# Raise：SetForegroundWindow 單獨呼叫時常被前景鎖擋掉而且不報錯，所以先掛上目前
# 前景的輸入執行緒，再做一次置頂來回，最後確認前景真的換了。
Add-Type -ReferencedAssemblies Accessibility -TypeDefinition @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text; using Accessibility;
public class MsaaNode {
  public int Depth; public string Role; public string Name; public int X, Y, W, H; public bool HasRect;
  public override string ToString() {
    return new string(' ', Depth * 2) + "[" + Role + "] '" + Name + "'" + (HasRect ? " @(" + X + "," + Y + " " + W + "x" + H + ")" : "");
  }
}
public static class MsaaTree {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr h, uint id, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out object o);
  [DllImport("oleacc.dll")] static extern int AccessibleChildren(IAccessible p, int start, int n, [Out] object[] kids, out int got);
  [DllImport("oleacc.dll", CharSet = CharSet.Unicode)] static extern uint GetRoleText(uint role, StringBuilder s, uint n);

  [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);

  public static IntPtr FindChild(IntPtr parent, string cls) {
    IntPtr found = IntPtr.Zero;
    EnumChildWindows(parent, (h, l) => {
      var sb = new StringBuilder(256); GetClassName(h, sb, 256);
      if (sb.ToString() == cls) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }

  public static List<MsaaNode> Dump(IntPtr hwnd, int maxDepth, int limit) {
    var nodes = new List<MsaaNode>();
    Guid iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71"); object o;
    AccessibleObjectFromWindow(hwnd, 0xFFFFFFFC, ref iid, out o); // OBJID_CLIENT
    Walk((IAccessible)o, 0, maxDepth, limit, nodes);
    return nodes;
  }

  static void Walk(IAccessible a, int depth, int maxDepth, int limit, List<MsaaNode> nodes) {
    if (depth > maxDepth || nodes.Count >= limit) return;
    var node = new MsaaNode { Depth = depth, Role = "", Name = "" };
    try { node.Name = a.get_accName(0) ?? ""; } catch {}
    try {
      object r = a.get_accRole(0);
      if (r is int) { var sb = new StringBuilder(64); GetRoleText((uint)(int)r, sb, 64); node.Role = sb.ToString(); } else { node.Role = "" + r; }
    } catch {}
    try { a.accLocation(out node.X, out node.Y, out node.W, out node.H, 0); node.HasRect = true; } catch {}
    nodes.Add(node);
    int n = 0; try { n = a.accChildCount; } catch {}
    if (n == 0) return;
    var kids = new object[n]; int got;
    AccessibleChildren(a, 0, n, kids, out got);
    for (int i = 0; i < got; i++) { var k = kids[i] as IAccessible; if (k != null) Walk(k, depth + 1, maxDepth, limit, nodes); }
  }

  public static bool Raise(IntPtr h) {
    IntPtr fg = GetForegroundWindow(); uint pid;
    uint fgThread = GetWindowThreadProcessId(fg, out pid);
    uint me = GetCurrentThreadId();
    AttachThreadInput(me, fgThread, true);
    SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 3);
    SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, 3);
    SetForegroundWindow(h);
    AttachThreadInput(me, fgThread, false);
    System.Threading.Thread.Sleep(250);
    return GetForegroundWindow() == h;
  }

  public static void ClickAt(int x, int y, int parkX, int parkY) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(80);
    mouse_event(2, 0, 0, 0, UIntPtr.Zero);
    mouse_event(4, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(150);
    SetCursorPos(parkX, parkY);
  }

  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L, T, R, B; }
  public static int[] TopLeft(IntPtr h) { RECT r; GetWindowRect(h, out r); return new int[] { r.L, r.T }; }
}
"@

# accLocation 回傳實體像素；不宣告 DPI 感知的話，SetCursorPos 用的是縮放後的座標。
[MsaaTree]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null

$window = Get-Process $Proc -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $window) { Write-Output "no visible window for process '$Proc'"; exit 1 }
$view = [MsaaTree]::FindChild($window.MainWindowHandle, 'FLUTTERVIEW')
if ($view -eq [IntPtr]::Zero) { Write-Output 'no FLUTTERVIEW child window'; exit 1 }

$nodes = [MsaaTree]::Dump($view, $MaxDepth, $Limit)
Write-Output "nodes=$($nodes.Count)"

if (-not $Click) {
    $nodes | ForEach-Object { $_.ToString() } | Where-Object { -not $Filter -or $_ -match $Filter }
    exit 0
}

# 名稱整段相符，或第一行相符：導覽分頁與列表項目的名稱常是多行（「設定」換行接
# 「第 6 個分頁 (共 6 個)」）。
$found = @($nodes | Where-Object {
    ($_.Name -eq $Click -or ($_.Name -split "`n")[0] -eq $Click) -and $_.HasRect -and
    (-not $Role -or $_.Role -eq $Role)
})
if ($found.Count -le $Index) {
    Write-Output "no element named '$Click'$(if ($Role) { " with role '$Role'" }) at index $Index ($($found.Count) found)"
    exit 2
}
$target = $found[$Index]
if (-not [MsaaTree]::Raise($window.MainWindowHandle)) { Write-Output 'could not bring the window to the foreground'; exit 3 }
$cx = $target.X + [int]($target.W / 2)
$cy = $target.Y + [int]($target.H / 2)
# 點完把游標移到視窗左上角（標題列）：停在有 tooltip 的按鈕上會讓無障礙樹停住，
# 下一次讀到的就是舊樹。
$corner = [MsaaTree]::TopLeft($window.MainWindowHandle)
[MsaaTree]::ClickAt($cx, $cy, [Math]::Max(0, $corner[0] + 20), [Math]::Max(0, $corner[1] + 5))
Write-Output "clicked [$($target.Role)] '$($target.Name)' at ($cx,$cy), match $($Index + 1) of $($found.Count)"
