# Driving the Windows build

Read before driving the Windows app, and again when a click, capture or scroll
does not do what you expected.

## Reading and clicking through MSAA

The Flutter view exposes **no UI Automation tree** — `get-app-state` and every
UIA client see only `window > pane FLUTTERVIEW`, walked or hit-tested, even with
Narrator running. The engine answers through MSAA only (checked in
`flutter_windows.dll`, Flutter 3.47.1):

```bash
S=.claude/skills/verify-on-device/scripts
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/msaa_tree.ps1 -Filter button
#   [push button] '查看佇列' @(3156,1228 121x49)     screen rect, physical px
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $S/msaa_tree.ps1 -Click '查看佇列'
#   clicked [push button] '查看佇列' at (3216,1252), match 1 of 1
```

- The script prints `nodes=<n>` first. A healthy tree is 120-odd nodes on the
  home page; a handful (7 against 93 in the framework tree) means the
  accessibility bridge is stuck — see `docs/troubleshooting.md`.
- `-Click` raises the window, clicks the element's centre and parks the cursor
  on the title bar (`-Role` / `-Index` pick among duplicates; exit 2 = no
  match). It matches a name exactly or by its first line, so `-Click '設定'`
  reaches the rail tab `設定` + `第 6 個分頁 (共 6 個)`.
- **`-Click` is a real mouse click on the user's own data.** There is no MSAA
  default action. Resolve the label with `-Filter` first; a stray
  `-Click '清空佇列'` opens the clear-queue confirmation on the user's real queue.
- It sees only what the semantics tree carries. For anything else, drive by
  window coordinates (below).

## Driving by coordinates

```bash
orca computer list-apps --json                     # find pid of "fmp"
orca computer get-app-state --app pid:<pid> --json # screenshot only
orca computer click --app pid:<pid> --x <x> --y <y> --json
orca computer paste-text --app pid:<pid> --text "周杰倫" --json
orca computer press-key --app pid:<pid> --key Return --json
```

Windows Orca has no bundle IDs — select apps by name or `pid:<n>`. If the
screenshot reports `scale != 1`, divide screenshot pixels by it. Synthetic input
reports `unverified`; confirm every action with a fresh screenshot.
`get-app-state` coordinates are window-local, so they are right only while the
window is on top — otherwise clicks and captures hit whatever is topmost.

- **Raise the window yourself; `--restore-window` is unreliable.** What works:
  Win32 `AttachThreadInput` to the foreground thread, an `HWND_TOPMOST` /
  `HWND_NOTOPMOST` round trip through `SetWindowPos`, then
  `SetForegroundWindow`. Assert `GetForegroundWindow()` returns your HWND before
  every click — a bare `SetForegroundWindow` silently no-ops under the
  foreground-lock rules.
- **Maximize before driving.** A raise can restore the window mostly
  off-screen, which reads as "the page cannot scroll". Check the rect from
  `list-windows` first.
- **Call `SetProcessDpiAwarenessContext(-4)` (PER_MONITOR_AWARE_V2) at the top
  of every script that measures, clicks or captures.** Without it
  `GetWindowRect` / `SetCursorPos` use virtualized coordinates while
  `CopyFromScreen` uses physical pixels. `orca computer list-windows` reports
  physical coordinates, so disagreeing with `GetWindowRect` by exactly the scale
  factor is the tell.
- **Capture with `Graphics.CopyFromScreen` over the window rect.** `PrintWindow`
  with `PW_RENDERFULLCONTENT` returns a frozen frame that looks real and never
  advances — byte-identical captures read exactly like "the input never landed".
- **Pin the window with `--window-id`.** FMP owns several top-level windows (the
  SMTC message window, two IME windows), and a modal file dialog is its own.
- **`orca computer scroll` needs `--pages`**; an `--amount` is silently ignored.
- The emulator's bezel (power, volume, rotate) is reachable through its
  `qemu-system-x86_64` process, but drive the guest with `orca emulator`.

## Native dialogs

- File dialogs expose a full UIA tree (~100 elements). Address them with
  `--window-id` from `orca computer list-windows` and click by
  `--element-index`.
- The save dialog's filename field rejects `set-value` (`value_not_settable`)
  and `orca computer hotkey Control+a` does not reach it. Click the field, then
  `Set-Clipboard` the full path and send Ctrl+A / Ctrl+V with Win32
  `keybd_event`. Typing a full path is how you keep an export out of the user's
  Documents.

## Keys, lifecycle and state

- **Global hotkeys need no focus**: `RegisterHotKey` combinations go only to the
  registering app. Read `Settings.hotkeyConfig` first — it is the user's custom
  bindings as JSON and may differ from `HotkeyConfig.defaults()`; decode `keyId`
  against `keyboard_key.g.dart`.
- **Hot restart (`R`) ends the Windows process** while media_kit tears down its
  native player, and `flutter run` loses the device. Hot reload (`r`) is fine.
  When a change needs a restart, quit with `q` and start a new run.
- **`WM_CLOSE` posted to the main HWND is the honest "user clicked X".** With
  `minimizeToTrayOnClose`, `IsWindowVisible` turns false while the process
  stays alive — that pair is the tray assertion.
- **Once a tooltip shows, `Failed to update ui::AXTree` floods the `flutter run`
  terminal** and scrolls Dart logs away; a synthetic click hovers too. Read state
  through the VM Service and confirm visuals by screenshot.
- **Accessibility measurements depend on where the cursor rests.** A tooltip
  under the pointer breaks the tree for the rest of the run. Park the cursor on
  empty space before the step you measure, or drive by keyboard.
- To toggle Narrator, send Win+Ctrl+Enter; `Stop-Process` cannot stop it.

## SMTC

Read SMTC through WinRT, not the media flyout (the flyout dismisses on focus
change). FMP does not need to be visible:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .claude/skills/verify-on-device/scripts/smtc_probe.ps1 -AppFilter fmp
```

It prints `IsNextEnabled` / `IsPreviousEnabled` / `IsPlaybackPositionEnabled` /
`IsShuffleEnabled` / `IsRepeatEnabled` per session. It must run under
`powershell.exe` (5.1): `pwsh` 7 has no WinRT projection.

## Native probes

Build CMake scratch projects under a short root such as `C:/t/`; the session
scratchpad path exceeds the Windows path limit and fails with confusing
compiler errors.
