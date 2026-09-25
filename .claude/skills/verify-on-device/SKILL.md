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

Closed loop for verifying FMP against a running app:
**bring up → run → observe → act → hot reload → tear down.** The Android
emulator is the required platform; add Windows for Windows-specific work. If the
loop cannot be completed, report the blocker.

Verified on a Windows 11 host with Orca CLI 1.4.187, AVD `Medium_Phone`
(Android SDK 37, x86_64), and Flutter 3.47.x.

| When | Read |
|------|------|
| An Android tap, typed text, timing or cold start behaves unexpectedly | `references/android.md` |
| Driving or measuring the Windows build | `references/windows.md` |
| Reading state instead of pixels, setting up a precondition the UI cannot reach, or needing playable media offline | `references/runtime-state.md` |

## Preconditions

- `adb` on `PATH`; `emulator.exe` is **not** — invoke it as
  `$ANDROID_HOME/emulator/emulator.exe`.
- `orca` on `PATH` and the app running (`orca status --json`; `orca open --json`
  if not). Substitute the executable per Orca's own rule: `ORCA_CLI_COMMAND` when
  set, `orca-dev` in a dev checkout, `orca-ide` on bare Linux, else `orca`.
- Run `orca skills get computer-use` / `orca skills get orca-cli` for the
  version-matched command reference rather than recalling flags.
- Git Bash mangles non-ASCII on stdout: prefix Python one-liners with
  `PYTHONIOENCODING=utf-8`, and read Orca JSON with `encoding='utf-8'`.

## 1. Bring up the emulator

```bash
"$ANDROID_HOME/emulator/emulator.exe" -list-avds
```

Launch it **detached** — an emulator started from a backgrounded Bash task gets
a graceful shutdown when that task ends:

```powershell
Start-Process -FilePath "$env:ANDROID_HOME\emulator\emulator.exe" -ArgumentList "-avd","<AVD>" -PassThru
```

Block until boot completes (the `sleep` runs on the device):

```bash
adb wait-for-device shell 'while [[ -z $(getprop sys.boot_completed) ]]; do sleep 1; done; echo BOOTED'
```

## 2. Run the app

Run `dart run build_runner build` and `dart run slang` first. The generated
`*.g.dart` files are gitignored, so a checkout that moved past a schema or i18n
edit fails in `assembleDebug` with a missing getter that looks like a source
bug. A fresh worktree needs both before its first build.

Own the process in an Orca terminal so it survives across turns and accepts
hot-reload keystrokes:

```bash
orca terminal create --worktree active --command "flutter run -d emulator-5554" --json
```

Keep the returned `terminal.handle`. The first Android build takes several
minutes; `orca terminal wait --for tui-idle` can time out while the build is
still healthy — read the tail before concluding anything failed.

`flutter run -d windows` works the same way. A `Failed to update ui::AXTree`
line in its output means the Windows accessibility tree has frozen (see
`docs/troubleshooting.md`); find the node before filtering the line away.

## 3. Observe

| Signal | Command |
|--------|---------|
| Element tree + tap coordinates (Android) | `orca emulator ax --device emulator-5554 --json` |
| Screenshot (Android) | `adb exec-out screencap -p > shot.png` |
| Dart/`I/flutter` logs | `orca terminal read --terminal <handle> --json` (`tail`, `nextCursor`) |
| Raw device log | `orca emulator logcat --lines <n> --device emulator-5554 --json` |
| Live object fields, HTTP traffic, Isar | Dart VM Service — `references/runtime-state.md` |
| Element tree (Windows) | MSAA — `references/windows.md` |

`scripts/ax_flatten.py` collapses the `ax` tree into one line per interesting
node with pixel and normalized centers:

```bash
PYTHONIOENCODING=utf-8 python .claude/skills/verify-on-device/scripts/ax_flatten.py --limit 30
```

Flutter's semantics surface through uiautomator, so labels, list rows and nav
destinations come back as text — prefer that to pixels. Screenshot when the
question is visual (layout, overflow, theming) or the tree is empty. Take device
pixels with `adb exec-out screencap`; `orca screenshot` returns inline base64
and burns context.

The VM Service URI in the run terminal is a local debug credential: quote the
port and purpose only.

## 4. Act

```bash
orca emulator tap <x> <y> --device emulator-5554 --json      # normalized 0..1
orca emulator type "<ascii>" --device emulator-5554 --json
orca emulator button back --device emulator-5554 --json
orca emulator gesture ... / rotate ... / permissions ...
orca emulator install <apk> --device emulator-5554 --json
orca emulator launch com.personal.fmp --device emulator-5554 --json
```

Element indexes and coordinates go stale after navigation or re-render: re-dump
`ax` after every UI-changing action before choosing the next target.

## 5. Hot reload

```bash
orca terminal send --terminal <handle> --text "r" --enter --json   # R = restart, q = quit
```

Then re-observe. This is the inner loop: edit → `r` → `ax`/screenshot → assert.
On Windows, `R` ends the process; quit with `q` and start a new run instead.

## 6. Tear down

An emulator plus two `flutter run` sessions is expensive. Unless the user asked
to keep them:

```bash
orca terminal close --terminal <handle> --json    # each run terminal
adb emu kill                                      # emulator
```

Revert anything installed or changed for the session (test APKs, IME changes,
DB edits) and confirm with `adb devices` and `tasklist`.

## Reporting

Report what was observed: quote the log line or tree node, or give the
screenshot path. Name every step that was skipped or blocked, and what blocked
it.
