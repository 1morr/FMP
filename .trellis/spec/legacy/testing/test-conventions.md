# Test conventions

## Layout and naming

- `test/` mostly mirrors `lib/`: `test/{core,data,services,ui}/<feature>/`,
  plus `support/`, `live/`, `workflows/`, `manual/` and `performance/`.
  `test/providers/` is largely flat (only `download/` and `static_rules/` are
  subdirectories), and two files sit at the root (`test/bilibili_source_test.dart`,
  `test/app_content_wrapper_test.dart`).
- One class may have several files split by behaviour:
  `<class>_<aspect>_test.dart` (`audio_controller_handoff_and_errors_test.dart`,
  `media_kit_audio_service_buffer_test.dart`).
- Shared helpers live in `test/support/`, shared fakes in `test/support/fakes/`,
  imported **relatively** (`'../../support/pump_until.dart'`) because `test/` is not
  under `package:fmp`.
- Only `*_test.dart` runs. Anything that must not run in CI is deliberately named
  otherwise: `test/manual/` (human-watched probes, see its README),
  `test/performance/*_benchmark.dart` (wall-clock budgets), `tool/demo/*_demo.dart`
  (real APIs; analysed and formatted, never executed).
- Test names and `reason:` strings are English sentences in behavioural voice:
  `'the superseded seek must not reach the backend'`. Some older tests have
  Chinese names (`test/core/constants/download_filenames_test.dart`).

## Tags

The only tag is `live`, declared in `dart_test.yaml` and excluded in CI. Use
file-level `@Tags(['live'])` + `library;`, or per-test `tags: 'live'`. A test that
builds a real source with its default constructor must carry it
(`test/support/live_source_tag_static_rule_test.dart`).

## Doubles

- **No mocking library.** Hand-written fakes only: `class _FakeX implements Y`,
  `class _FakeX extends RealY` overriding members, or `extends Fake implements Y`.
  Unimplemented members throw (`noSuchMethod`) rather than return a fake value.
- Fakes record calls in public lists for assertions (`FakeAudioService.seekCalls`).
- Shared fakes cover the default case; a test-specific variation is usually a
  file-local `_Fake…` (dartdoc on `FakeSourceAuthContext`). A few shared fakes
  carry a switch (`FakeAudioService.playUrlSettlesReady`).
- Reuse before writing: `FakeAudioService`, `CountWaiters`, `FakeIsar`,
  `FakeSettingsRepository`, `FakeSourceAuthContext`,
  `MemorySecureKeyValueStore` / `UnavailableSecureKeyValueStore`,
  `mockSecureStorageChannel` (`test/support/fakes/`); `buildTestAudioController`,
  `audioSettingsNotifierFor`, `testNowPlayingPublisher`, `initializeIsarForTests`,
  `stripDartComments` (`test/support/`).

## Time

No `fake_async` or clock package. Some production classes take the time source:
timer factories (`PlaybackRecoveryTimerFactory` in `BufferStarvationWatchdog` /
`PlaybackRecoveryCoordinator`), `DateTime Function()? now`, `delay:` params,
`PlaybackTimeoutBudget` values. Most timers are not injectable, so their tests wait
in real time (`QueueManager`'s position saver makes `queue_manager_test.dart`
wait 11 s). A new timer in production code comes with its injection point.

## Isar

Real Isar in a temp directory, opened with only the needed schemas, after
`setUpAll(initializeIsarForTests)` — the full pattern is in
`../data/persistence.md` § Tests. `initializeIsarForTests` is the only place that
knows the native library's location; it needs `flutter pub get` first.

## HTTP and platform channels

- Inject a `Dio` and set `dio.httpClientAdapter` to a file-local
  `_FakeHttpClientAdapter`, or use an interceptor. There is no shared adapter.
- Byte streams (download, playback): a loopback `HttpServer.bind(InternetAddress.loopbackIPv4, 0)`.
- Platform channels: `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(...)`,
  reset in teardown.

## Riverpod and widgets

`ProviderContainer(overrides: …)` + `addTearDown(container.dispose)` (a few use
`tearDown`, e.g. `search_pagination_stale_test.dart`). About half of the widget
test files wrap in `TranslationProvider` + `ProviderScope` with the locale set to
`en`; the rest pump without `TranslationProvider`.
Details in `../ui/riverpod.md` § Tests and `../ui/widgets.md` § Widget tests.
Clean up with `addTearDown(...)`.

## Waiting

`test/support/pump_until.dart`, from #43 and #55:

```dart
await pumpUntil(() => lyricsService.enabledSourceCalls.length == 1,
    reason: 'the auto-match call should record its enabled source list');
await drainEventQueue(reason: 'the superseded seek must not reach the backend');
expect(audioService.seekCalls, isEmpty);
```

- `pumpUntil` needs a condition that is **false on entry**; `reason` is the
  timeout message.
- `drainEventQueue` only to assert something did not happen; better still, first
  `pumpUntil` a later milestone.
- "N calls happened" on a fake: `CountWaiters.waitFor(n)`.
- A direct `pumpEventQueue` outside `pump_until.dart` is gated
  (`test/support/wait_convention_static_rule_test.dart`). Widget-test
  `tester.pump` / `pumpAndSettle` are not gated.
