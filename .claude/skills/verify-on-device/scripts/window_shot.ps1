# 只截 App 視窗（不含桌面與其他視窗，截圖不會帶到個人資訊），存成 PNG。
#
# 兩種用法：
#   啟動並截圖：  ... -Exe <fmp.exe 路徑> [-ArgLine '--fmp-dev-plugin=<插件.js>'] -Out <png> [-Wait 8] [-KeepRunning]
#   接上已開的：  ... -Attach -Out <png>            （找行程 -Proc、視窗標題 -Title 的，
#                                                    預設 fmp 與 FMP Dev；舊版與 prod 也叫 fmp.exe）
#
# 預設截完就結束自己啟動的行程；加 -KeepRunning 讓它繼續開著（之後要跑
# msaa_tree.ps1 或繼續操作時）。-Attach 永遠不結束行程。
# 以 PrintWindow（PW_RENDERFULLCONTENT）截圖，視窗被別的視窗蓋住、不在最上層也
# 截得到；視窗最小化時截不到，會以 exit 1 結束。
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass `
#     -File .claude/skills/verify-on-device/scripts/window_shot.ps1 -Exe <路徑> -Out <png>
#
# 輸出檔放在 session 的暫存目錄，不要放進 repo。
# Exit codes: 0 = ok, 1 = 沒有視窗或視窗最小化, 2 = 參數錯誤。

[CmdletBinding()]
param(
    [string]$Exe = '',
    [string]$ArgLine = '',
    [Parameter(Mandatory)][string]$Out,
    [int]$Wait = 8,
    [switch]$KeepRunning,
    [switch]$Attach,
    [string]$Proc = 'fmp',
    [string]$Title = 'FMP Dev'
)

# 底下的 C# 區塊只能寫 ASCII（Windows PowerShell 5.1 以系統代碼頁讀暫存 .cs）。
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class WinShot {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  public struct RECT { public int L, T, R, B; }
}
"@
# 物理像素：不設的話 GetWindowRect 回傳被縮放過的座標，截圖會被裁掉。
[WinShot]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null

$started = $false
if ($Attach) {
    $p = Get-Process -Name $Proc -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -eq $Title } |
        Select-Object -First 1
    if (-not $p) { Write-Error "no '$Title' window for process '$Proc'"; exit 1 }
} else {
    if (-not $Exe) { Write-Error '-Exe or -Attach is required'; exit 2 }
    $startArgs = @{ FilePath = $Exe; PassThru = $true }
    if ($ArgLine) { $startArgs.ArgumentList = $ArgLine }
    $p = Start-Process @startArgs
    $started = $true
    Start-Sleep -Seconds $Wait
}

try {
    $p.Refresh()
    $h = $p.MainWindowHandle
    if ($h -eq [IntPtr]::Zero -or [WinShot]::IsIconic($h)) {
        Write-Error 'no visible main window'; exit 1
    }
    $r = New-Object WinShot+RECT
    [WinShot]::GetWindowRect($h, [ref]$r) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $dc = $g.GetHdc()
    [WinShot]::PrintWindow($h, $dc, 2) | Out-Null
    $g.ReleaseHdc($dc)
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    "saved $Out ($($bmp.Width)x$($bmp.Height)) pid=$($p.Id)"
} finally {
    if ($started -and -not $KeepRunning) { Stop-Process -Id $p.Id -ErrorAction SilentlyContinue }
}
