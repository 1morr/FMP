# Download pipeline, media handoff, accounts

Vocabulary: `CONTEXT.md`. Storage paths and Android permissions: ADR 0004.

## Download (`lib/services/download/`)

- Each download runs the top-level `_isolateDownload` in its own isolate, spawned
  with `onError` **and** `onExit` wired to the receive port. An isolate killed
  outside try/catch sends nothing; without `onExit` the main isolate waits forever
  and leaks the concurrency slot (`3a413e56`).
- Main ↔ isolate messages are `_IsolateMessage(_IsolateMessageType.x, data)`;
  isolate errors travel as JSON `{type, message, …}` and are mapped back to typed
  exceptions.
- Between enqueue and isolate registration, re-check
  `_shouldAbortBeforeRegistration(task.id)` after every await. A deleted task must
  not have its resume progress saved.
- Redirects are followed by hand (≤5), recomputing headers each hop through
  `DefaultMediaHandoff().prepareDownloadHop(...)`; non-http(s) schemes and
  public → private redirects are refused.
- Resume uses `Range`; a `200` instead of `206` restarts from zero. Write the temp
  file with `File.open(mode: …)`, **not** `openWrite()` (an eager open error kills
  the isolate).
- Per-tick progress is batched in memory and emitted on `progressStream`; it is
  **not** written to Isar (watch-triggered rebuilds). Isar gets progress only on
  complete / pause / failure.
- The stored failure reason is a translated sentence (`userMessageFor`); raw text
  goes to the log only.
- Deleting files deletes only files proven to be FMP's (`4cdf64d0`).
- Isolate timeouts cannot be driven by a fake clock; the reason is a comment at
  the `response.timeout(...)` call in `_isolateDownload`, not a slow test.

## Media handoff (`lib/services/media/media_handoff.dart`)

Media byte requests — playback and download — carry only
`SourceHttpPolicy.mediaHeaders(sourceType)` plus `Range`.
`streamResolutionAuth` is carried through but deliberately unused. Stream
Resolution Auth is for asking the adapter for a URL, never for fetching the
bytes. Do not add credentials here without changing `CONTEXT.md` and getting the
user's approval.

## Accounts and credentials (`lib/services/account/`)

- Credentials are JSON DTOs (`BilibiliCredentials`, …) in secure storage through
  `SecureKeyValueStore`; account services take an injectable
  `SecureKeyValueStore? secureStorage`.
- Loading credentials: an unavailable store (`SecureStorageUnavailable`) logs a
  **fixed** message and degrades to logged-out without setting the loaded flag, so
  it can recover. Malformed JSON is discarded and the account marked logged out.
  Never log raw credential JSON, cookie strings or token-bearing exceptions.
- `logout` deletes the account row; `markSessionExpired` keeps it with
  `sessionExpired = true`.
- Auth interceptors are built inside services and cannot reach Riverpod: they only
  call `markSessionExpired()`, which writes `Account.sessionExpired`. The user-facing prompt comes from
  `accountSessionExpiryWatcherProvider`, de-duplicated by `SessionExpiryNotifier`.
- `SourceAuthContext.authForPlay(sourceType)` returns credentials only when Auth
  For Play is on for that source. Playlist import and refresh have their own
  flags; search uses none. A source with no account service gets `null` — never
  another platform's cookies.
- API clients here also come from `SourceHttpPolicy.createApiDio(...)`.

## Tests

- `test/services/account/account_credentials_redaction_test.dart` puts sentinel
  secrets through the flows and asserts none reach `AppLogger.logs` — extend it
  when adding a credential path.
- Secure storage in tests: `MemorySecureKeyValueStore` /
  `UnavailableSecureKeyValueStore`, or `mockSecureStorageChannel(...)` for the
  platform channel. Prefer these over `FlutterSecureStorage.setMockInitialValues`
  (global, never restored — it silently bypasses channel mocks later in the same
  file). It is still used in a number of tests (`account_credentials_redaction_test.dart`,
  the NetEase / YouTube account service tests, `backup_service_test.dart`,
  `lyrics_source_settings_page_test.dart`); no file mixes the two, keep it that way.
- Download bytes: a loopback `HttpServer.bind(InternetAddress.loopbackIPv4, 0)`
  (`test/services/download/download_service_progress_and_disposal_test.dart`).
