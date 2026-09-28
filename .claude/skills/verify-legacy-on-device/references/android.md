# Android emulator traps

Read when an Android observation does not match what you expected: a tap or
typed text seems lost, the screen does not change, a timing looks wrong, or you
need a cold start or an error path.

## Text input

- **Gboard's "Try out your stylus" tutorial steals `adb shell input text`.** On a
  fresh AVD the first tap into a text field can raise it; the characters land in
  *its* field, the Flutter field stays empty, and the `ax` tree does not show the
  overlay. Screenshot, tap its Cancel, retype.
- **Zhuyin composes instead of committing.** Gboard's default language on this
  AVD is Zhuyin: `adb shell input text` fills the candidate strip, and the
  semantics tree shows an empty `EditText` either way. The spacebar reads `注音`
  in a screenshot. Tap the globe key (bottom-right) to switch to English, retype.
  This hits plain ASCII too.
- **Non-ASCII input is unavailable.** `orca emulator type` shells out to
  `adb shell input text`, which throws `NullPointerException` on CJK. ADBKeyboard
  (broadcasts no longer delivered), `cmd clipboard` (not implemented) and host
  clipboard + `KEYCODE_PASTE` (Flutter ignores it) all failed on SDK 37. Cover
  Chinese input with an `integration_test` and `WidgetTester.enterText`.
- `adb shell input keyevent 66` submits a text field (Enter).

## The tree or the screen does not respond

- **Popup menus do not reach uiautomator on `Medium_Tablet`.** An open
  `PopupMenuButton` is visible in a screenshot while `ax` reports zero
  `MenuItem` nodes, so tapping the row again plays the track instead. Read the
  item's pixel centre off a screenshot and use `adb shell input tap <x> <y>`.
  `Medium_Phone` reports the same menus fine.
- **A snapshot-restored `Medium_Phone` can come up wedged**: frozen frame, taps
  and `adb shell input` do nothing, `ax` reads `nodes=0`, a hot restart changes
  nothing, logcat shows only `F/bluetooth ... on_hardware_error ... code 0x42`.
  `topResumedActivity` still names the app. It is the emulator — relaunch with
  `-no-snapshot-load`.
- **A page-size dialog on first launch** (16 KB alignment) blocks the first
  screen on modern images. Dismiss it via `ax` before asserting.

## Process lifecycle

- **Back at the root route exits the app.** Background it with
  `adb shell input keyevent 3` (HOME). Back plus relaunch restarts the process
  and loses playback, which reads as "playback stopped in the background".
- **`adb shell am force-stop` detaches `flutter run`.** The terminal prints
  `Lost connection to device.` once; every later `r` / `R` is a silent no-op and
  the app keeps running the last installed kernel. For a cold start, close the
  run terminal and start a new `flutter run`. Check the tail for
  `Lost connection` before trusting anything after a force-stop.

## Timing and network

- **Emulator audio runs ~1.68x faster than wall clock** (60 s of audio ends in
  ~36 s). Never quote an emulator figure as a playback duration or assert
  gapless timing there; measure on Windows or a physical device.
- **The AVD resolver does not cache**: every DNS lookup costs ~1 s. Subtract it
  before calling a slow first play an FMP regression.
- **`adb emu network speed` does not affect Wi-Fi.** To shape traffic, do it on
  the host or point the app at a slow local server (`test/manual/`).
- **Reach error paths with the network off**:
  `adb shell svc wifi disable && adb shell svc data disable`. Search, radio,
  login and remote playlist refresh fail at once with `Failed host lookup`.
  Sections that read only Isar cannot be failed this way — say so rather than
  claiming coverage.

## Toasts

- Error toasts fire from `ref.listen(... next.error != previous?.error)`, so a
  second identical failure shows nothing. Hot restart between attempts or drive
  a different failure.
- Catch one by burst-screenshotting: `adb exec-out screencap -p` costs ~0.4 s,
  so a bare 20-iteration loop covers ~8 s. Fire the taps from a backgrounded
  subshell so the loop is already running, then score frames by the toast's
  colour instead of eyeballing them.

## Files and paths

- **A directory made with `adb shell mkdir` belongs to `shell`**, and the app
  gets `PathAccessException ... errno = 13`. Use
  `adb shell run-as <package> mkdir -p files/<dir>` and point the setting at
  `/data/user/0/<package>/files/<dir>`.
- **Git Bash rewrites `/storage/...` and `/sdcard/...` into Windows paths.**
  Prefix `adb shell` calls with `MSYS_NO_PATHCONV=1`.
