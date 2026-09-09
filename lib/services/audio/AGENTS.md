# lib/services/audio AGENTS.md

`AudioController`, the playback backends, the queue, stream handoff, temporary
playback, Mix mode and network error recovery.

Every collaborator carries its own dartdoc saying what it deliberately does
*not* own; the budget constants carry the measurements behind their values, and
each backend carries the reasoning for its buffer profile. This file holds only
what spans files — the contracts no single class can state on its own.

## Architecture

```text
UI playback controls          RadioController
        |                            |
        v                            |
AudioController (audio_provider.dart)|
  - PlayerState projection           |
  - temporary/mix/detached modes     |
  - declares no provider: those live |
    in providers/audio/              |
        |         |         |        |
        v         v         v        v
FmpAudioService  Queue-   Queue-  NowPlayingPublisher
  (abstract)     Commands Manager   - owner arbitration
  |              - mix    - order    - PlaybackCapabilities
  v                gate   - nav      |            |
JustAudioService   - full            v            v
MediaKitAudioService -> result  FmpAudioHandler  WindowsSmtcHandler
                                (Android)        (Windows)

One play request at a time runs through two collaborators the controller
never bypasses:

  PlaybackRequestSession       PlaybackHandoffGate
  - request generation         - the controller's latch on that request
  - supersession, budget       - deferred seeks, stabilization window

A started track fans out to three side-effect collaborators, none of which
the playback path waits for:

  PlayHistoryRecorder        LyricsAutoMatchCoordinator   MixSessionCoordinator
  - one write, no state      - own request generation     - session + prefetch
```

**Projection stays in `AudioController`.** Every collaborator reports through
callbacks and none of them touches `PlayerState`. `clearQueue` and `playAt` were
deliberately *not* moved out: the first has session-state after-effects, the
second starts playback and belongs with the transport commands.

**UI must call `AudioController`, never `FmpAudioService` directly.** This is a
convention, not a compile-time boundary — use `rg` when reviewing UI playback
changes. Radio is the intentional non-UI exception: `RadioController` uses the
backend directly while ownership hooks make `AudioController` ignore radio-owned
events.

Music playback opens media through `playMedia()` / `setMedia()`. Direct
`playUrl()` / `setUrl()` remain for radio and compatibility paths — do not add
new music playback callers for the raw URL methods.

## Initialization

`build()` starts initialization on a microtask and returns, so **there is always
a window where the controller exists but its stream subscriptions do not**.
`initialize()` therefore shares one in-flight future: every caller awaits the
same completion, and a failure clears it so the next caller retries.

It used to be a boolean that returned early while the work was still in flight,
handing callers an already-completed future for a half-wired controller. The
failure is silent and permanent rather than slow, because `FmpAudioService`'s
streams are **broadcast** — an event emitted before `subscribe` is dropped and
never replayed.

## The Three Request Ids

They are not interchangeable, and there are exactly three. Do not add a fourth.

| Question | Ask |
|---|---|
| Is this still the newest request? | `PlaybackRequestSession.isSuperseded(id)` |
| Is the controller projecting *this* handoff? | `PlaybackHandoffGate.isCurrent(id)` |
| Did the user press skip again while this one was deciding? | `AudioController._navRequestId` |

The gate's `activeRequestId` is a **latch**, not a second counter: the session
mints the id and hands it over, and the latch is zeroed when the controller
finishes projecting. `_navRequestId` is a raw counter guarding the async window
inside `next()`/`previous()` only — those await a queue move before they reach
the session, so during that await there is no session id to ask about yet.

Any method that starts backend playback or fetches playback URLs outside
`PlaybackRequestSession` must either move into the session or take an explicit
session handle.

## Playback End Reasons

`FmpAudioService` exposes one `Stream<PlaybackEndReason> endReasons`.
**Backends translate; `AudioController` only dispatches** — only the backend
knows whether it is looking at mpv or ExoPlayer. Never re-introduce
error-string matching in the controller: that is what produced issue #41, where
mpv's "could not open/initialize audio device" matched a keyword meant for
*media* open failures and a dead output device was reported as a failed track.

| Variant | Backend emits it when | Controller does |
|---|---|---|
| `EndedNaturally` | position is within `completionTolerance` of duration | advance the queue |
| `EndedPrematurely` | engine says completed but position is far from duration, **or duration was never reported** | retry the current track from the saved position |
| `TransportFailed` | connection reset/timeout/DNS/TLS | retry or refetch the URL, **not** advance |
| `OutputDeviceFailed` | the audio *output* failed — nothing to do with the media | stop and show the output message; **must not** blame the track |
| `MediaUnopenable` / `DecoderFailed` | the media cannot be opened or decoded | delay briefly for self-recovery, then a terminal error |
| `UnclassifiedFailure` | anything the backend cannot place | log it and ignore — but visibly |

`duration == null` counts as `EndedPrematurely`, not a natural end: a stream that
connects but delivers zero bytes reports exactly that shape, and treating it as
"finished" makes the player skip the whole queue in silence.

`OutputDeviceFailed` is **the one end reason not ignored while radio owns
playback** — the device is broken regardless of who is playing, and
`RadioController` has never subscribed to `endReasons`.

`MediaKitAudioService` must subscribe to **both** `player.stream.error` and
`player.stream.log`: media_kit only forwards a fixed set of log prefixes to its
error stream, so `ao`-prefixed audio-output failures never reach it at all.

Other rules that survive the change:

- Retry suppression must be generation- and current-track-aware. A fresh backend
  error during retry handoff schedules a new generation; stale handoff
  completion must not clear the fresh retry state.
- Ignore every end reason while in loading/retrying/network-error state.
- Only failures marked `SourceErrorKind.shouldSkipTrack` auto-skip.
- Playback-visible stream metadata belongs to the active request. Entering a
  controller-owned load or clearing the playing track must clear stale values
  first. Detail providers must clear stale `VideoDetail` on track change, or the
  panel shows the previous song's metadata during loading or failure.
- On resume after a long pause, refresh expired audio URLs before playing.
- Fire-and-forget backend cleanup futures must catch and log; async `dispose()`
  failures must not become unhandled async errors.

## Timeout Budget

`PlaybackTimeoutBudget` bounds each loading stage — T1 stream resolution, T2
media open, T3 buffer starvation. The measurements behind the values live on the
class. What matters across files:

- Exceeding a budget throws `PlaybackTimeoutException`, **not**
  `TimeoutException`. The distinction carries the policy: a budget overrun means
  FMP chose to stop waiting, so it gets one fallback stream and then stops with
  a message; a `TimeoutException` from an adapter is one network hiccup and goes
  through the backoff ladder. `PlaybackErrorPresenter.isRetryable` must keep
  checking `PlaybackTimeoutException` **first**, or every timeout turns into
  five full re-resolutions.
- A superseded request never reports a timeout — being replaced is not a
  failure.
- **Re-buffering is a substate of playing.** `BufferStarvationWatchdog` never
  tears playback down; it reports that buffering has been *continuous* for
  longer than T3, which is the backstop for an engine that says nothing at all.
  The countdown starts when buffering begins and is **not** restarted by further
  buffering events — restarting it on every event means it never fires.
- Starvation recovery re-issues the request once and stops; it deliberately does
  **not** enter the backoff ladder. A track is rescued at most once, and the
  guard clears when the playing track changes, not when a request starts, or the
  rescue would clear its own guard and loop.
- Each request carries a single deadline of T1+T2, so the fallback attempt
  spends what is left rather than starting a fresh budget.

## Next Medium (Who Owns The Advance)

`setNextMedia(PreparedPlaybackMedia?)` hands the backend the medium to play
after the current one; `advancedToNext` reports that it did. **While something
is armed the advance belongs to the backend**: there is no `EndedNaturally` at
the boundary, and the controller follows rather than starts playback.

Only one lookahead item, never a whole queue. Stream URLs are resolved one track
at a time, expire in 1–2 hours and can be rate-limited, so a `setQueue(List)`
shape cannot be honoured. There is no `supportsQueue`: both backends would
return `true`.

- Arm from the prefetch that already runs after a request succeeds. It must not
  happen earlier: every request unconditionally stops the backend first, which
  clears the playlist.
- **Arm again right after following a boundary.** The follow path starts no
  request, so without that step only the first boundary in a queue is gapless.
  Found on device, not by a test.
- Do not arm under `LoopMode.one` (the next-index calculation ignores loop-one,
  so the prefetched track is the wrong one), while playing out of the queue,
  while radio owns the backend, or while Mix is loading more.
- Disarming hangs off the queue-state update — every queue change already
  reaches it, so one comparison there replaces a disarm call on each of the
  seven queue commands.
- The one-second position fallback yields while something is armed, but only for
  a few ticks. It exists because Android loses the completed event in the
  background; standing down for good would trade one bug for another.
- `audio_backend_static_test.dart` pins the playlist wrapper, the mpv property
  and the fact that the follow path goes through the shared track-change path
  that the handoff gate and the starvation watchdog both depend on.

## Queue, Shuffle And Mix

- UI must use `upcomingTracks` / provider state instead of computing next-track
  order itself.
- `Settings.rememberPlaybackPosition` controls *restoring*; saving is always on.
- Mix playlists are dynamic and infinite: shuffle is disabled and the
  add-to-queue commands are blocked. If the final queued track completes while
  load-more is pending, completion **waits** for it — the only place playback
  waits on a side effect, pinned by `audio_controller_mix_boundary_test.dart`.
- Mix metadata may only be read through `QueuePersistenceManager.restoreState()`.
  That guard scans **every** file under `lib/services/audio/`; scoped to one file
  it would go vacuous the moment the code moved.

## Verification

```bash
flutter test test/services/audio
```

Also run `test/data/sources` if stream resolution, source fallback or auth
headers changed.

Loading, timeout and recovery behaviour cannot be covered by unit tests alone —
what is under test is how mpv and ExoPlayer react to a sick connection, which
FMP cannot fake and a real CDN will not perform on request. Use the two
deliberately broken servers instead:

```bash
dart run test/manual/pathological_stream_servers.dart
```

`test/manual/README.md` has the URLs; the script's header carries the measured
per-platform baselines a change has to improve on.
