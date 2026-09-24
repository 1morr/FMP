# Dumps what a screen reader can reach in the Windows build, via MSAA.
#
# UI Automation shows nothing under `pane FLUTTERVIEW`, walked or hit-tested,
# with or without Narrator running: the engine is built without
# FLUTTER_ENGINE_USE_UIA and only answers MSAA. oleacc reaches the real tree.
# Semantics are on from startup here, so Narrator does not need to be running.
#
# Compare the node count with the framework's own tree
# (`ext.flutter.debugDumpSemanticsTreeInInverseHitTestOrder`). A handful of
# nodes against a full framework tree means the accessibility bridge has
# stopped taking updates; see docs/troubleshooting.md.
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass `
#     -File .claude/skills/verify-on-device/scripts/msaa_tree.ps1 [-Proc fmp] [-Filter button]
#
# First output line is `nodes=<n>`. Exit code 1 = no window or no FLUTTERVIEW.

[CmdletBinding()]
param(
    [string]$Proc = 'fmp',
    [string]$Filter = '',
    [int]$MaxDepth = 40,
    [int]$Limit = 3000
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -ReferencedAssemblies Accessibility -TypeDefinition @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text; using Accessibility;
public static class MsaaTree {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr h, uint id, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out object o);
  [DllImport("oleacc.dll")] static extern int AccessibleChildren(IAccessible p, int start, int n, [Out] object[] kids, out int got);
  [DllImport("oleacc.dll", CharSet = CharSet.Unicode)] static extern uint GetRoleText(uint role, StringBuilder s, uint n);

  public static IntPtr FindChild(IntPtr parent, string cls) {
    IntPtr found = IntPtr.Zero;
    EnumChildWindows(parent, (h, l) => {
      var sb = new StringBuilder(256); GetClassName(h, sb, 256);
      if (sb.ToString() == cls) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }

  public static List<string> Dump(IntPtr hwnd, int maxDepth, int limit) {
    var lines = new List<string>();
    Guid iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71"); object o;
    AccessibleObjectFromWindow(hwnd, 0xFFFFFFFC, ref iid, out o); // OBJID_CLIENT
    Walk((IAccessible)o, 0, maxDepth, limit, lines);
    return lines;
  }

  static void Walk(IAccessible a, int depth, int maxDepth, int limit, List<string> lines) {
    if (depth > maxDepth || lines.Count >= limit) return;
    string name = "", role = "";
    try { name = a.get_accName(0); } catch {}
    try {
      object r = a.get_accRole(0);
      if (r is int) { var sb = new StringBuilder(64); GetRoleText((uint)(int)r, sb, 64); role = sb.ToString(); } else { role = "" + r; }
    } catch {}
    lines.Add(new string(' ', depth * 2) + "[" + role + "] '" + name + "'");
    int n = 0; try { n = a.accChildCount; } catch {}
    if (n == 0) return;
    var kids = new object[n]; int got;
    AccessibleChildren(a, 0, n, kids, out got);
    for (int i = 0; i < got; i++) { var k = kids[i] as IAccessible; if (k != null) Walk(k, depth + 1, maxDepth, limit, lines); }
  }
}
"@

$window = Get-Process $Proc -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $window) { Write-Output "no visible window for process '$Proc'"; exit 1 }
$view = [MsaaTree]::FindChild($window.MainWindowHandle, 'FLUTTERVIEW')
if ($view -eq [IntPtr]::Zero) { Write-Output 'no FLUTTERVIEW child window'; exit 1 }

$lines = [MsaaTree]::Dump($view, $MaxDepth, $Limit)
Write-Output "nodes=$($lines.Count)"
$lines | Where-Object { -not $Filter -or $_ -match $Filter }
