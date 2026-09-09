---
name: verify-on-device
description: >-
  Run FMP on the Android emulator or the Windows desktop build and verify a
  change against the live app: boot the emulator, install and launch, drive the
  UI, read Dart logs, hot reload, and inspect runtime state. Use after every
  change to UI pages or widgets, playback controls, source result rendering, or
  layout-affecting strings — root AGENTS.md requires an on-device check for those
  before reporting — and whenever asked to run, screenshot, tap, type into, or
  observe FMP on a device or emulator.
---

# Verify on Device

Closed loop for verifying FMP against a running app rather than tests alone:
**bring up → run → observe → act → hot reload → tear down.**

Verified on a Windows 11 host with Orca CLI 1.4.187, AVD `Medium_Phone`
(Android SDK 37, x86_64), and Flutter 3.47.x.

Root `AGENTS.md` makes this loop **mandatory** for user-visible changes and names
the Android emulator as the required platform. This file is the procedure. If the
loop cannot be completed, report the blocker — never fall back to tests silently.

## Preconditions

- `adb` on `PATH`; `emulator.exe` is **not** — invoke it as
  `$ANDROID_HOME/emulator/emulator.exe`.
- `orca` on `PATH` and the app running (`orca status --json`; `orca open --json`
  if not). Substitute the executable per Orca's own rule: `ORCA_CLI_COMMAND` when
  set, `orca-dev` in a dev checkout, `orca-ide` on bare Linux, else `orca`.
- Run `orca skills get computer-use` / `orca skills get orca-cli` for the full
  version-matched command reference. Do not guess flags from memory.
- Git Bash mangles non-ASCII on stdout: prefix Python one-liners with
  `PYTHONIOENCODING=utf-8`, and read Orca JSON with `encoding='utf-8'`.

## 1. Bring up the emulator

```bash
"$ANDROID_HOME/emulator/emulator.exe" -list-avds
```

Launch **detached**. Do not start it from a backgrounded Bash task — the
emulator receives a graceful shutdown when that task ends and dies mid-session:

```powershell
Start-Process -FilePath "$env:ANDROID_HOME\emulator\emulator.exe" -ArgumentList "-avd","<AVD>" -PassThru
```

Block until boot completes (the `sleep` runs on the device, not the host):

```bash
adb wait-for-device shell 'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 1; done; echo BOOTED'
```

## 2. Run the app

Own the process in an Orca terminal so it survives across turns and accepts
hot-reload keystrokes:

```bash
orca terminal create --worktree active --command "flutter run -d emulator-5554" --json
```

Keep the returned `terminal.handle`. First Android build takes several minutes;
`orca terminal wait --for tui-idle` can time out while the build is still
healthy — read the tail before concluding anything failed.

`flutter run -d windows` works the same way. Its output is flooded by the benign
`Failed to update ui::AXTree` spam (see `docs/troubleshooting.md`) — filter it
out when reading, never "fix" it.

## 3. Observe

| Signal | Command |
|--------|---------|
| Element tree + tap coordinates (Android) | `orca emulator ax --device emulator-5554 --json` |
| Screenshot (Android) | `adb exec-out screencap -p > shot.png` |
| Dart/`I/flutter` logs | `orca terminal read --terminal <handle> --json` (`tail`, `nextCursor`) |
| Raw device log | `orca emulator logcat --lines <n> --device emulator-5554 --json` |
| Heap, GC, isolates, Isar | Dart VM Service — see `docs/debugging-with-vm-service.md` |

`scripts/ax_flatten.py` collapses the `ax` tree into one line per interesting
node with both pixel and normalized centers:

```bash
PYTHONIOENCODING=utf-8 python .claude/skills/verify-on-device/scripts/ax_flatten.py --limit 30
```

Flutter's semantics surface through uiautomator, so widget labels, list rows,
and nav destinations come back as real text — prefer this over reading pixels.
Take a screenshot when the question is visual (layout, overflow, theming) or
when the tree is empty.

The VM Service URI appears in the run terminal's tail. **It is a local debug
credential — never paste the token into issues, PR bodies, logs, or reports.**
Quote the port and purpose only.

## 4. Act

```bash
orca emulator tap <x> <y> --device emulator-5554 --json      # normalized 0..1
orca emulator type "<ascii>" --device emulator-5554 --json
orca emulator button back --device emulator-5554 --json
orca emulator gesture ... / rotate ... / permissions ...
orca emulator install <apk> --device emulator-5554 --json
orca emulator launch com.personal.fmp --device emulator-5554 --json
```

Element indexes and coordinates go stale after navigation or re-render. Re-dump
`ax` after every UI-changing action before choosing the next target.

`adb shell input keyevent 66` submits a text field (Enter).

## 5. Hot reload

```bash
orca terminal send --terminal <handle> --text "r" --enter --json   # R = restart, q = quit
```

Then re-observe. This is the inner loop: edit → `r` → `ax`/screenshot → assert.

## 6. Windows desktop build

The Windows app exposes **no semantics tree** to UI Automation — `get-app-state`
returns only `window > pane FLUTTERVIEW`. On Windows you drive by screenshot and
window-local coordinates, not element indexes:

```bash
orca computer list-apps --json                     # find pid of "fmp"
orca computer get-app-state --app pid:<pid> --json # screenshot only
orca computer click --app pid:<pid> --x <x> --y <y> --json
orca computer paste-text --app pid:<pid> --text "周杰倫" --json
orca computer press-key --app pid:<pid> --key Return --json
```

Windows Orca has no bundle IDs — select apps by name or `pid:<n>`. If the
screenshot reports `scale != 1`, divide screenshot pixels by it before using
them as action coordinates. Synthetic input reports `unverified`; confirm every
action with a fresh screenshot.

Computer-use also reaches the emulator's own window chrome (power, volume,
rotate, back) via its `qemu-system-x86_64` process — but drive the guest through
`orca emulator` instead; the bezel buttons' accessibility actions are unreliable.

## 7. Known limitations

- **Gboard's "Try out your stylus" tutorial overlay steals `adb shell input
  text`.** On a fresh AVD the first tap into any text field can raise this
  overlay; the typed characters land in *its* field and the Flutter field stays
  empty, so it reads as a missed tap. The `ax` tree does not show the overlay.
  Screenshot to spot it, tap its Cancel, then retype.
- **`adb shell input text` silently composes instead of committing when
  Gboard's active language is Zhuyin**, which is the default on this AVD. The
  characters land in the candidate strip, the Flutter field stays empty, and the
  semantics tree shows an empty `EditText` either way — so it looks like the tap
  missed. Screenshot the keyboard to spot it: the spacebar reads `注音`. Tap the
  globe key (bottom-right) to switch to English, then retype. This applies to
  plain ASCII, so it is a separate problem from the CJK limitation below.
- **Non-ASCII input on Android is unavailable.** `orca emulator type` shells out
  to `adb shell input text`, which throws `NullPointerException` on CJK. Three
  workarounds were tested and all failed on SDK 37: ADBKeyboard (broadcast
  receivers no longer delivered), `cmd clipboard` (not implemented), host
  clipboard + `KEYCODE_PASTE` (Flutter ignores it). For Chinese-input coverage
  write an `integration_test` and use `WidgetTester.enterText`. Windows is
  unaffected — `orca computer paste-text` handles CJK.
- **Popup menus do not reach uiautomator on the tablet AVD.** An open
  `PopupMenuButton` is plainly visible in a screenshot while
  `orca emulator ax` reports zero `MenuItem` nodes — the tree looks exactly
  like the menu never opened, so the natural next move (tap the row again) is
  wrong and plays the track instead. Screenshot first, read the item's pixel
  centre off it, and drive with `adb shell input tap <x> <y>`. Measured on
  `Medium_Tablet` (2560x1600); the same menus come back fine on
  `Medium_Phone`.
- **No element tree on Windows** (§6).
- `orca screenshot` (Orca's embedded browser) returns inline base64 and burns
  context. For device pixels always use `adb exec-out screencap -p > file.png`.
- **A snapshot-restored `Medium_Phone` can come up wedged.** The screen is a
  frozen frame, `orca emulator tap` and `adb shell input` both do nothing, the
  `ax` tree reads `nodes=0`, and even a hot restart leaves the display
  unchanged; logcat shows only `F/bluetooth ... on_hardware_error ... code
  0x42`. Relaunch with `-no-snapshot-load` — do not spend time debugging the
  app, it is the emulator. `topResumedActivity` still names the app, so that
  check will not tell you either.
- Android's 16 KB page-size dialog appears on first launch on modern emulator
  images (`libisar.so` LOAD segment not aligned). Dismiss it via `ax` before
  asserting on the first screen.

### Measured during the 2026-09-04 data-layer acceptance run

- **Back at the root route exits the app; it does not background it.** Use
  `adb shell input keyevent 3` (HOME) to background. Pressing back and then
  relaunching from the launcher restarts the process and loses playback, which
  reads as "playback stopped in the background" if you are not watching for it.
- **`dumpsys media_session` is the cheapest continuous playback probe.** Grep for
  `state=PLAYING(3), position=` — position is in ms and advances monotonically,
  so polling it every minute shows both continuity and the wrap-around at a
  track/loop boundary without any UI interaction.
- **Setting up state the UI cannot reach: use `ext.isar.editProperty`.** The
  download path can only be chosen through the Android SAF picker, which does
  not respond to synthetic taps. Writing `Settings.customDownloadDir` through the
  Isar inspector extension sets up the precondition without faking the thing
  being verified. See `docs/debugging-with-vm-service.md` §5.
- **A directory created with `adb shell mkdir` belongs to `shell`, not the app**,
  so the app gets `PathAccessException ... errno = 13`. Create it with
  `adb shell run-as <package> mkdir -p files/<dir>` and point the setting at
  `/data/user/0/<package>/files/<dir>`.
- **Git Bash rewrites `/storage/...` and `/sdcard/...` into Windows paths.**
  Prefix `adb shell` calls with `MSYS_NO_PATHCONV=1`, or the argument arrives as
  `C:/Program Files/Git/storage/...`.

### Measured during the round-02 playback audit

Each of these cost real time to discover. They change what a timing or audio
observation on the emulator is worth.

- **Emulator audio runs ~1.68x faster than wall clock.** A track that should
  take 60s of playback reaches its end in ~36s. Never quote an emulator figure
  as a playback duration, and never assert gapless timing there — measure
  playback timing on Windows or a physical device.
- **The AVD resolver does not cache.** Every DNS lookup costs ~1s, on every
  request, so a "slow first play" on the emulator is usually resolver overhead
  rather than an FMP regression. Subtract it before reporting a stream-resolution
  measurement.
- **`adb emu network speed` does not affect Wi-Fi.** The emulator's Wi-Fi
  interface ignores the throttle, so it cannot be used to reproduce slow-network
  playback. Shape traffic on the host, or point the app at a deliberately slow
  local server instead.
- **Prefer the VM Service over screenshots for reading state.** Evaluating an
  expression against the running isolate
  (`docs/debugging-with-vm-service.md`) answers "what is the controller's state"
  directly, in one call, and returns text. A screenshot answers it indirectly,
  costs context, and cannot see anything off-screen. Reach for pixels only when
  the question is genuinely about layout.
- **The Windows `flutter run` terminal is unreadable.** `Failed to update
  ui::AXTree` spam (`flutter/flutter#182444`) scrolls Dart logs away within
  seconds. On Windows, read state through the VM Service and confirm visuals by
  screenshot — and raise the window to the foreground first, or the capture is
  of whatever is on top.
- **Read SMTC through WinRT, not the flyout.** Querying
  `GlobalSystemMediaTransportControlsSessionManager` returns the actual session
  properties as text; screenshotting the media flyout is unreliable because the
  popup dismisses on focus change. Use `scripts/smtc_probe.ps1`:

  ```bash
  powershell.exe -NoProfile -ExecutionPolicy Bypass     -File .claude/skills/verify-on-device/scripts/smtc_probe.ps1 -AppFilter fmp
  ```

  It prints `IsNextEnabled` / `IsPreviousEnabled` / `IsPlaybackPositionEnabled` /
  `IsShuffleEnabled` / `IsRepeatEnabled` per session. **It must run under
  `powershell.exe` (Windows PowerShell 5.1)** — `pwsh` 7 has no WinRT projection
  and `Add-Type -AssemblyName System.Runtime.WindowsRuntime` fails there. The
  session manager is readable from any process, so this sidesteps the
  foreground-focus problem entirely: FMP does not need to be visible.
- **CMake scratch projects must not sit deep in the path.** Building a probe
  under the session scratchpad exceeds the Windows path limit and fails with
  confusing compiler errors. Use a short root such as `C:/t/`.

### Driving the Windows build (measured in the 2026-09-04 Windows run)

§6 says Windows gives you screenshots and window coordinates only. That is still
true of the Flutter view — but the round that wrote §6 concluded the window
could not be driven at all, and that was wrong. It can. The missing step was
raising the window first.

- **Pass `--restore-window` on every click, scroll and capture.**
  `orca computer get-app-state --app pid:<n>` reports
  `coordinateSpace: "window"`, so `--x/--y` are window-local and correct — but
  without the flag the operation lands on whatever is topmost at that screen
  point, and `get-app-state` screenshots whatever is on top, which in this run
  meant capturing one of the user's unrelated windows. `--restore-window`
  brings the target forward first and is the whole fix.
  Win32 `SetForegroundWindow` + `AttachThreadInput` also works, but only
  sometimes — it silently no-ops when the foreground-lock rules say no, and the
  next capture is then of the wrong window. Prefer the flag; if you do use
  Win32, assert `GetForegroundWindow()` returns your HWND before you click.
- **`PrintWindow` with `PW_RENDERFULLCONTENT` returns a frozen frame.** It looks
  like a working capture — real colours, real layout — but it is the frame from
  whenever the surface was last handed to the DWM, and it does not advance. Four
  consecutive captures across two clicks and a keypress came back byte-identical
  (same md5), which reads exactly like "the input never landed" and sent this
  round chasing a non-existent click problem. Capture with
  `Graphics.CopyFromScreen` over the window rect instead; raise the window first.
- **A driving process that is not DPI-aware measures a different screen.**
  Without `SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)` (pass `-4`),
  `GetWindowRect` and `SetCursorPos` speak virtualized coordinates while
  `CopyFromScreen` speaks physical pixels — a 1.5x gap at 150% scaling. The
  symptom is that clicks computed off a screenshot land somewhere else entirely,
  and that a crop at the reported rect shows a neighbouring window. Call it once
  at the top of every script that measures, clicks or captures, and the three
  agree. `orca computer list-windows` already reports physical coordinates, so
  it disagreeing with your `GetWindowRect` by exactly the scale factor is the
  tell.
- **Pin the window with `--window-id`.** An app can own several top-level
  windows (FMP has the SMTC message window and two IME windows), and a modal
  file dialog is a window of its own.
- **Native dialogs *do* expose a full UIA tree.** The Flutter view is still
  `window > pane FLUTTERVIEW`, but a `FilePicker.saveFile` dialog comes back
  with ~100 real elements. Address it with `--window-id` from
  `orca computer list-windows` and click by `--element-index`. Both file exports
  (backup, log) were driven this way.
- **The save dialog's filename field rejects `set-value`**
  (`value_not_settable`), and `orca computer hotkey Control+a` does not reach
  it. What works: click the field's element, then `Set-Clipboard` the full path
  and send Ctrl+A / Ctrl+V with Win32 `keybd_event`. Typing a full path into the
  filename box is how you redirect an export away from the user's Documents.
- **`orca computer scroll` needs `--pages`.** There is no `--amount`; passing
  one is silently ignored and nothing scrolls.
- **Global hotkeys are the one input path that needs no focus at all.**
  `RegisterHotKey` combinations are swallowed by the system and delivered only
  to the registering app, so `keybd_event` cannot leak them into another window.
  **Read `Settings.hotkeyConfig` first** — it is a JSON string of custom
  bindings and the user's may differ from `HotkeyConfig.defaults()`. Decode the
  `keyId` numbers against `keyboard_key.g.dart`; in this run `toggleWindow` was
  Alt + numpadDivide (`0x20000022f`), not the default Ctrl+Alt+W.
- **`WM_CLOSE` to the main HWND is the honest "user clicked X".** `PostMessage`
  it to the specific window handle — no coordinates, nothing else on the desktop
  touched. With `minimizeToTrayOnClose`, `IsWindowVisible` flips to false while
  the process stays alive; that pair is the tray assertion.

### Getting media to play when every source is blocked

Playback verification needs playing media, and all three sources can be
unavailable at once on a dev machine (Bilibili `playurl` answering HTTP 412
`request was banned`, YouTube demanding sign-in, and a library with nothing
downloaded). `Track.audioUrl` does not rescue you — the reuse cache
(`stream_resolution_service.dart:326`) also requires an in-memory entry.

What works offline: `_inspectLocalFiles` (`:428`) plays the first
`Track.allDownloadPaths` entry that exists on disk, with **no playlist-id
match** and no network. Generate a long near-silent WAV, point one track's
`playlistInfo[].downloadPath` at it, and playback is real, local, and silent.
Save the original `playlistInfo` first and put it back afterwards.

Two traps around that:

- **Orphan cleanup deletes tracks you swap out of the queue.** `QueueManager`
  runs `TrackRepository.deleteOrphanTracks` ~10 s after start, excluding only
  the current queue. A track that is in no playlist and no longer in the queue
  is **gone** — this run destroyed a leftover test track that way.
- **A DB edit under a running app is not durable.** See the write-race note in
  `docs/debugging-with-vm-service.md` §5: reading the new value back proves
  nothing. Kill the process immediately after the edit, or make the change
  through the app's own UI. Restoring the play queue at the end only stuck once
  it went through the queue page's clear button and the mini player's loop
  toggle.
- **The VM Service URI scrolls out of the terminal tail.** Read it with
  `orca terminal read --cursor 0 --limit 5000`, not from the default tail.

## 8. Tear down

Leaving an emulator plus two `flutter run` sessions alive is expensive. Unless
the user asked to keep them:

```bash
orca terminal close --terminal <handle> --json    # each run terminal
adb emu kill                                      # emulator
```

Revert anything installed for the session (test APKs, IME changes) and confirm
with `adb devices` and `tasklist`.

## Reporting

Report what was observed, not what should have happened: quote the log line, the
tree node, or attach the screenshot path. Say explicitly when a step was skipped
or a limitation blocked it.

### Measured during the 2026-09-07 UI acceptance run

- **`adb shell am force-stop` detaches `flutter run`, and every later `r` / `R`
  is then a silent no-op.** The terminal prints `Lost connection to device.`
  once and nothing after, so the app keeps running from the *last installed*
  kernel while you think you are driving your edits. This run produced two
  screenshots of pre-fix behaviour that looked like the fix had failed. If you
  need a cold process start, close the run terminal and start a new
  `flutter run` instead — and read the tail for `Lost connection` before
  trusting any observation that follows a force-stop.
- **Toast assertions need the state to change, not just the action to repeat.**
  Error toasts here fire from `ref.listen(... next.error != previous?.error)`,
  so a second identical failure shows nothing. Hot restart (`R`) between
  attempts, or drive a different failure.
- **Catch a toast by burst-screenshotting, not by sleeping.** `adb exec-out
  screencap -p` costs ~0.4 s, so a bare `for i in $(seq 1 20)` loop covers ~8 s
  with no gaps; fire the taps in a backgrounded subshell so the loop is already
  running. Then score the frames for the toast's colour rather than eyeballing
  twenty images.
- **Turn the network off with `adb shell svc wifi disable && adb shell svc data
  disable`** (`adb emu network speed` does not touch Wi-Fi, see above). It is
  the cheapest way to reach real error paths: search, radio playback, login and
  remote playlist refresh all fail immediately with `Failed host lookup`. Local
  Isar reads do not, so provider-backed sections that read only the database
  cannot be failed this way at all — say so rather than claiming coverage.
