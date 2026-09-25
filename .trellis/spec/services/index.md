# Services layer (`lib/services/`, `lib/core/services/`)

Applies to business logic: audio, account, download, import, library, lyrics,
radio, search, cache, network, platform, update, backup, and the shared
`ToastService` / image-loading services in `lib/core/services/`.

Terms used here — Source Auth Context, Media Handoff, Auth For Play, Media Request
Credentials — are defined in `CONTEXT.md`; use them as defined.

## Guidelines

| File | Read when |
|------|-----------|
| [service-conventions.md](./service-conventions.md) | Writing or changing any service: constructor shape, disposal, streams, async guards, timers, platform branching, error flow |
| [audio.md](./audio.md) | Anything in `lib/services/audio/` or `lib/services/radio/`; a new playback behaviour; either audio backend |
| [download-and-auth.md](./download-and-auth.md) | The download pipeline, media handoff, account services, credentials, auth interceptors |

Error and logging rules shared with other layers: [../shared/errors-and-logging.md](../shared/errors-and-logging.md).

## Pre-Development Checklist

- [ ] Audio change → read `audio.md` and ADR 0003 (two backends). UI calls `AudioController`, never `FmpAudioService`; radio is the one exception (AGENTS.md § Boundaries).
- [ ] Download / storage path change → read `download-and-auth.md` and ADR 0004.
- [ ] Anything that decides which credentials go where → read `CONTEXT.md` first. Changing the auth boundary needs the user's approval (AGENTS.md § Conventions).
- [ ] A new repeating timer, outbound host or cross-feature import → plan the static-rule entry with its reason.

## Quality Check

- Run the AGENTS.md § Verification row that matches: *Audio playback/controller/queue*, *Source adapters / HTTP policy*, or *Download pipeline*.
- Playback controls or anything the user hears/sees → on-device check with the `verify-on-device` skill.
- Every `await` in a disposable service or notifier is followed by a disposed / superseded / `ref.mounted` check where state is touched afterwards.
- Not gated — check by hand: provider owns `dispose`; no cookie or token in a new log line, and a stream URL goes through `logLabel` / `redactStreamUrl`; `Platform.is*` placement; `unawaited(...)` with `.catchError` for futures that can fail.
