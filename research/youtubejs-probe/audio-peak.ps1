# Samples the Windows Core Audio peak meter of every audio session owned by a
# process name (default fmp) on the default render device. A peak > 0 means the
# process is sending non-silent audio to the output device.
# Usage: pwsh -File audio-peak.ps1 [-Name fmp] [-Samples 10]
param([string]$Name = 'fmp', [int]$Samples = 10)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int NotImpl1(); [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device); }
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
[Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionManager2 { int NotImpl1(); int NotImpl2(); [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator e); }
[Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionEnumerator { [PreserveSig] int GetCount(out int n); [PreserveSig] int GetSession(int i, out IAudioSessionControl2 s); }
[Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioSessionControl2 {
  [PreserveSig] int GetState(out int state); int a(); int b(); int c(); int d(); int e(); int f(); int g(); int h();
  int i(); int j(); [PreserveSig] int GetProcessId(out uint pid);
}
[Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioMeterInformation { [PreserveSig] int GetPeakValue(out float peak); }

public static class Peak {
  public static string Sample(uint[] pids) {
    var en = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
    IMMDevice dev; en.GetDefaultAudioEndpoint(0, 1, out dev);
    var iid = typeof(IAudioSessionManager2).GUID; object o;
    dev.Activate(ref iid, 23, IntPtr.Zero, out o);
    var mgr = (IAudioSessionManager2)o; IAudioSessionEnumerator se; mgr.GetSessionEnumerator(out se);
    int n; se.GetCount(out n); var sb = new System.Text.StringBuilder();
    for (int i = 0; i < n; i++) {
      IAudioSessionControl2 s; se.GetSession(i, out s); uint pid; s.GetProcessId(out pid);
      if (Array.IndexOf(pids, pid) < 0) continue;
      int st; s.GetState(out st); float peak; ((IAudioMeterInformation)s).GetPeakValue(out peak);
      sb.AppendFormat("pid={0} state={1} peak={2:F3}; ", pid, st == 1 ? "active" : st == 0 ? "inactive" : "expired", peak);
    }
    return sb.Length == 0 ? "no session" : sb.ToString();
  }
}
'@

$pids = [uint32[]]@(Get-Process -Name $Name -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
if ($pids.Count -eq 0) { Write-Output "no process named $Name"; exit 1 }
for ($i = 1; $i -le $Samples; $i++) {
  Write-Output ("sample {0}: {1}" -f $i, [Peak]::Sample($pids))
  Start-Sleep -Milliseconds 500
}
