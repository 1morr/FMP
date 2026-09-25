# Errors and logging

## From exception to user

`lib/core/errors/user_message.dart` is the single mapping:

- `userMessageFor(Object error)` → translated sentence. It knows
  `SourceApiException`, `DioException`, socket/HTTP/TLS, timeout, format and
  path-access errors; anything else is "unknown error" rather than a guess (#41).
- `failureMessage(error, stack, what, {tag})` logs the original and returns the
  sentence — use it for `state.error` in notifiers and services.
- In widgets, the only way to show an exception is
  `ToastService.failure(context, error, stackTrace:, tag:)`, or an
  `ErrorDisplay(message: userMessageFor(e))`.
- Never put `e.toString()` or `'$e'` into an i18n template, a toast, an
  `ErrorDisplay` or `state.error` (`5e9d2929`). Gated by
  `test/ui/static_rules/error_presentation_static_rule_test.dart` for templates
  (all of `lib/`) and for toasts / `ErrorDisplay` (`lib/ui/`); `state.error` is
  held by convention only.

Lower layers throw typed exceptions: a `SourceApiException` subtype, a repository
exception (`PlaylistNotFoundException`), or `SecureStorageUnavailable` (it carries
the platform code only — the message can leak a key alias or path). A bare
`DioException` that reaches the UI is still classified, not shown as "unknown".

Global handlers (`FlutterError.onError`, `PlatformDispatcher.instance.onError`,
`runZonedGuarded`) are in `lib/main.dart`; a failure before `runApp` renders
`StartupFailureApp` (#37). There is no crash reporting service; logs stay on the
device.

## Logging

- Logger: `AppLogger` in `lib/core/logger.dart`. Classes mix in `Logging`
  (`logDebug` / `logInfo` / `logWarning` / `logError(msg, [error, stackTrace])`,
  tag = `runtimeType`). Code without an instance calls
  `AppLogger.info(msg, 'Tag')` with a PascalCase tag. No `print` or `debugPrint`
  in `lib/` outside `logger.dart` itself.
- Levels: debug = flow detail and timings; info = lifecycle milestones; warning =
  degraded or recoverable (retry scheduled, unclassified error, store
  unavailable); error = failures, with the stack. Release builds keep info and
  above.
- Stream-resolution logs identify tracks with `TrackKey.formatGroup(sourceType, sourceId)`
  so `AudioStreamManager` and `StreamResolutionService` lines join up (many older
  controller lines still log titles). Time things as
  `${stopwatch.elapsedMilliseconds}ms`.
- **Redaction is a safety net, not permission.** `AppLogger.redactSensitive`
  scrubs known header and key shapes (`Cookie:`, `Authorization`, `SESSDATA`,
  `MUSIC_U`, `access_token`, …) from every message. Still log ids and codes —
  not header maps, cookies, credential JSON or token-bearing exceptions. A new
  credential shape gets a key in `logger.dart` and a case in
  `test/core/logger/redaction_test.dart`.
- `redactSensitive` does **not** catch signed stream URLs: the signature sits in
  the query (Bilibili) or in middle path segments (YouTube HLS, NetEase). Log
  `PreparedPlaybackMedia.logLabel` or `redactStreamUrl(url)`
  (`lib/services/audio/playback_media.dart`), never `debugUrl` or a raw stream
  URL (#163). Behaviour tests read `AppLogger.logs` for `MediaKitAudioService`,
  `PlaybackRequestSession` and `AudioController`; `JustAudioService` is held
  only by `audio_backend_shared_rules_static_rule_test.dart` (it must call
  `redactStreamUrl`). A new log line elsewhere is not gated.
- Logs persist to a rotating file (`LogFileSink`); a per-second log line evicts
  everything useful (`e1bf1712`).
