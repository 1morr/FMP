# Audio

Read ADR 0003 first: Android uses `JustAudioService` (ExoPlayer), Windows uses
`MediaKitAudioService` (libmpv), and both stay.

## Who owns what

| Class | File | Owns |
|-------|------|------|
| `AudioController` (`Notifier<PlayerState>`) | `audio_provider.dart` | The only playback entry point for UI. Projection state, transport commands, applying routed actions. Declares no providers. `audioControllerProvider` and its core collaborators' providers live in `lib/providers/audio/audio_controller_provider.dart` (the two files import each other on purpose); `nowPlayingPublisherProvider`, `playbackSideEffectsProvider`, `queueStateProvider`, `audioRuntimePlatformProvider` sit next to their class in `lib/services/audio/`. |
| `FmpAudioService` | `audio_service.dart` | Backend contract. **Backend differences are documented on each member's dartdoc.** |
| `QueueManager` | `queue_manager.dart` | Pure queue logic and persistence; never operates the player. |
| `PlaybackRequestSession` | `playback_request_session.dart` | Mints the request id, runs start/restore, returns `PlaybackSessionResult`. |
| `PlaybackHandoffGate` | `playback_handoff_gate.dart` | A latched copy of the active request id plus deferred seeks. Not a second counter. |
| `PlaybackEventRouter` | `playback_event_router.dart` | Pure functions: backend event + `PlaybackEventContext` → one `PlaybackAction`. |
| `PlaybackRecoveryCoordinator`, `BufferStarvationWatchdog` | same names | Retry ladder and stall detection, injectable timers. |
| `NowPlayingPublisher` | `now_playing_publisher.dart` | The single outlet to notification bar / SMTC; arbitrates music vs radio. |
| `PlaybackSideEffect` + registry | `playback_side_effects.dart` | Fan-out of track started / state changed / stopped. |
| `AudioStreamManager` → `StreamResolutionService` | same names | Track → `PreparedPlaybackMedia` (`LocalPlaybackMedia` / `RemotePlaybackMedia`). |

Collaborators report through callbacks and **never touch `PlayerState`**; each
one's dartdoc has a "what it deliberately does not own" paragraph — keep it true.
`PlayerState` and `QueueState` share no field (`audio_seam_static_rule_test.dart`).
Every queue write goes through `_emitQueueState` (dartdoc convention, not gated).

Radio (`RadioController`) is the intentional exception that talks to the backend
directly and coordinates through `onPlaybackStarting` / `isRadioPlaying`.

## Adding a playback behaviour

1. **Backend event → decision**: add a `PlaybackAction` variant and a case in
   `test/services/audio/playback_event_router_test.dart`. Do not add an `if` in the
   applier; `AudioController._apply` is one exhaustive `switch`. Only
   `playback_event_router.dart` may pattern-match `PlaybackEndReason`
   (`playback_event_routing_static_rule_test.dart`). The context snapshot holds no
   collaborators, and time comes from `context.now`.
2. **Native error translation** belongs in the backend via the shared rule file,
   never string matching in the controller (#41).
3. **Something on every track start** → implement `PlaybackSideEffect` and
   register it in `playbackSideEffectsProvider`. A second call site in the
   controller is how lyrics stopped matching after gapless boundaries.
4. Queue mutation → `QueueCommands`; Mix → `MixSessionCoordinator`; temporary play
   → `TemporaryPlayHandler`.
5. `audio_provider.dart` has a code-line ratchet in both directions
   (`test/support/audio_provider_size_static_rule_test.dart`). Prefer extracting to
   a collaborator; raising the limit needs the reason in the commit body.

## Two backends

- Decisions that can converge are pure rule files both backends delegate to:
  `playback_end_reason_rules.dart`, `live_edge_seek_policy.dart`,
  `next_media_plan.dart` (`FakeAudioService` delegates to the first two). A
  keyword table copied into a backend, or a backend that stops delegating, is
  gated (`audio_backend_shared_rules_static_rule_test.dart`).
- A difference that cannot converge goes into the `FmpAudioService` member
  dartdoc — undocumented differences are only found on device.
- New cross-backend behaviour is written for both backends or extracted to a rule
  file.
- `MediaKitAudioService(platformPlayer:)` is the seam for running the desktop
  backend on a fake engine; `JustAudioService` has none.
- mpv reports output-device failures only on its log stream, so both `error` and
  `log` streams are subscribed (`056f20c3`). An output-device failure must not
  blame the track and must stop retries (#106).
- Android-only behaviour (audio focus, becoming-noisy) lives in
  `JustAudioService.initialize()` only.

## Races

The request id from `PlaybackRequestSession` is checked with
`isSuperseded(requestId)` after every await. Navigation (`_navRequestId`) and Mix
start (`_mixStartRequestId`) have their own counters. Before adding another
counter, check whether an existing one already orders the operation. Pause during
open and a stream drop while paused are both deliberate cases (`eef6f1bb`,
`349e20d0`).

## Tests

- Build the controller with `buildTestAudioController(...)` /
  `buildTestAudioControllerIn(...)` (`test/support/audio_controller_harness.dart`)
  over `FakeAudioService` (`test/support/fakes/fake_audio_service.dart`), which
  records `playMediaCalls`, `seekCalls`, … and emits backend events.
- Now-playing: `testNowPlayingPublisher()` (`test/support/now_playing.dart`).
- Short `PlaybackTimeoutBudget` values, injected `timerFactory:` — no real waits.
- Wait with `pumpUntil` / `drainEventQueue` / `CountWaiters` (`../testing/test-conventions.md`).
