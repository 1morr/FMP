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

- **Non-ASCII input on Android is unavailable.** `orca emulator type` shells out
  to `adb shell input text`, which throws `NullPointerException` on CJK. Three
  workarounds were tested and all failed on SDK 37: ADBKeyboard (broadcast
  receivers no longer delivered), `cmd clipboard` (not implemented), host
  clipboard + `KEYCODE_PASTE` (Flutter ignores it). For Chinese-input coverage
  write an `integration_test` and use `WidgetTester.enterText`. Windows is
  unaffected — `orca computer paste-text` handles CJK.
- **No element tree on Windows** (§6).
- `orca screenshot` (Orca's embedded browser) returns inline base64 and burns
  context. For device pixels always use `adb exec-out screencap -p > file.png`.
- Android's 16 KB page-size dialog appears on first launch on modern emulator
  images (`libisar.so` LOAD segment not aligned). Dismiss it via `ax` before
  asserting on the first screen.

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
