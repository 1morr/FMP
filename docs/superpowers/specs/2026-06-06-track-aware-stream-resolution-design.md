# Track-Aware Stream Resolution Design

## Context

FMP resolves audio streams for playback, fallback handoff, and downloads across
Bilibili, YouTube, and Netease. The current `BaseSource` stream interface accepts
only `sourceId`, while Bilibili multi-P tracks require `sourceId + cid` to select
the correct part. The current workaround lives in
`audio_stream_quality_fallback.dart`, which checks for `BilibiliSource` and calls
public cid-specific methods.

This keeps Bilibili track identity outside the source adapter. It also means the
shared fallback helper must know source-specific implementation details.

## Goal

Replace the source-id stream interface with a track-aware request interface so
stream identity is carried through playback, alternative fallback, downloads,
tests, and debug tooling.

The refactor is intentionally breaking. Existing direct calls such as
`source.getAudioStream('id')` and `source.getAudioUrl('id')` will be migrated to
`AudioStreamRequest`.

## Non-Goals

- Do not change backend playback error recovery.
- Do not change media request header or redirect policy.
- Do not change persisted schema or stream expiry semantics.
- Do not add new Bilibili multi-P detection behavior when `cid` is missing.
- Do not keep production convenience methods that preserve the old source-id
  stream vocabulary.

## Architecture

Add an immutable `AudioStreamRequest` DTO, defined near the source stream types
in `lib/data/sources/base_source.dart` or in a sibling file exported by it.

Required fields:

```dart
class AudioStreamRequest {
  final String sourceId;
  final int? cid;
  final int? pageNum;
  final AudioStreamConfig config;
  final Map<String, String>? authHeaders;
  final String? failedUrl;
}
```

`BaseSource` changes to request-based stream methods:

```dart
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request);

Future<AudioStreamResult?> getAlternativeAudioStream(
  AudioStreamRequest request,
) async => null;

Future<String> getAudioUrl(AudioStreamRequest request) async {
  final result = await getAudioStream(request);
  return result.url;
}
```

`AudioStreamRequest` should provide `copyWith` so quality fallback can preserve
identity and auth while replacing only `config`.

## Source Adapter Behavior

### Bilibili

`BilibiliSource.getAudioStream(request)` owns Bilibili identity rules:

- If `request.cid != null`, use the existing cid-aware implementation.
- If `request.cid == null`, keep the current behavior that derives or fetches
  the cid for source-id-only calls.
- Alternative fallback uses `request.cid` and `request.failedUrl`.

Public cid-specific methods are removed from the source interface surface:

- `getAudioStreamWithCid(...)`
- `getAlternativeAudioStreamWithCid(...)`

Their behavior remains as private implementation inside `BilibiliSource`.

### YouTube

`YouTubeSource` reads `request.sourceId`, `request.config`, and
`request.authHeaders`. Existing stream priority and format priority behavior
stays unchanged. Alternative fallback reads `request.failedUrl`.

### Netease

`NeteaseSource` reads `request.sourceId`, `request.config`, and
`request.authHeaders`. Existing login-required, VIP, copyright, region, and
expiry semantics stay unchanged. Alternative fallback may continue returning
`null`.

## Shared Fallback Flow

`audio_stream_quality_fallback.dart` stops importing `BilibiliSource` and stops
branching on source type.

Primary flow:

1. Receive `BaseSource source` and `AudioStreamRequest request`.
2. Iterate fallback quality levels.
3. Call `source.getAudioStream(request.copyWith(config: fallbackConfig))`.
4. Preserve existing `SourceApiException` fallback rules.

Alternative flow:

1. Receive `BaseSource source` and `AudioStreamRequest request` with
   `failedUrl`.
2. Try lower quality alternative streams first.
3. Try lower quality primary streams when allowed.
4. Try same-quality source alternative last.
5. Preserve `failedUrl`, `cid`, `pageNum`, and `authHeaders` throughout.

## Playback Data Flow

`AudioStreamDelegate.ensureAudioStream(track)` remains the playback entry point.
It builds an `AudioStreamRequest` from the `Track` and settings:

- `sourceId = track.sourceId`
- `cid = track.cid`
- `pageNum = track.pageNum`
- `config = AudioStreamConfig.fromSettings(settings, track.sourceType)`
- `authHeaders` only when `settings.useAuthForPlay(track.sourceType)` is true

The delegate calls the request-based quality fallback helper. After a successful
result, the delegate remains responsible for updating:

- `track.audioUrl`
- `track.audioUrlExpiry`
- `track.updatedAt`
- optional persistence

`AudioStreamDelegate.getAlternativeAudioStream(track, failedUrl)` builds the
same request shape with `failedUrl` populated.

## Download Data Flow

`DownloadService._startDownload()` builds the same request shape from the
downloaded `Track`, settings, and auth headers. It calls the shared request-based
quality fallback helper.

Download save path, isolate transport, metadata, images, repository completion,
and completion/failure events are out of scope for this refactor.

## Debug And Direct Source Callers

All direct source callers migrate to `AudioStreamRequest`, including source unit
tests and `lib/ui/pages/debug/youtube_stream_test_page.dart`.

Production code should not retain a `getAudioStream(String sourceId)` or
`getAudioUrl(String sourceId)` convenience path. Tests may use local helper
functions to construct requests, but the source interface remains request-based.

## Error Handling

This refactor preserves existing error semantics:

- `SourceErrorKind.unavailable` and `vipRequired` may fall back to lower quality.
- Retryable and non-fallbackable kinds are rethrown:
  `network`, `timeout`, `rateLimited`, `loginRequired`, `permissionDenied`,
  `geoRestricted`, and unknown non-fallbackable errors.
- Alternative fallback preserves current ordering: lower-quality alternatives,
  then allowed lower-quality primary streams, then same-quality source
  alternative.

Missing `cid` does not become a new error. Bilibili keeps the current behavior
for source-id-only calls.

## Testing

Update tests in three layers.

### Source Adapter Tests

- Migrate direct `getAudioStream('id')` calls to `AudioStreamRequest`.
- Verify Bilibili primary stream resolution uses `request.cid` when present.
- Verify Bilibili alternative stream resolution uses both `request.cid` and
  `request.failedUrl`.
- Verify YouTube and Netease stream behavior remains unchanged after request
  migration.

### Shared Fallback Tests

- Verify fallback helper copies the request and changes only quality in config.
- Verify identity fields (`sourceId`, `cid`, `pageNum`) survive every fallback
  attempt.
- Verify `authHeaders` and `failedUrl` survive alternative fallback attempts.
- Verify non-fallbackable `SourceApiException` kinds still rethrow.

### Service Tests

Preserve focused coverage:

- `test/services/audio/audio_stream_manager_test.dart`
  - `selectPlayback preserves Bilibili cid during stream resolution`
  - `selectFallbackPlayback preserves Bilibili cid for alternative streams`
- `test/services/download/download_service_phase1_test.dart`
  - `download start preserves Bilibili cid during stream resolution`

These tests should assert that request objects carry the expected identity
rather than asserting old public cid methods were called.

## Verification

Run targeted verification:

```bash
flutter test test/data/sources test/services/audio/audio_stream_manager_test.dart test/services/download/download_service_phase1_test.dart
flutter analyze
```

If fake migration creates a large intermediate failure set, first run the
narrowest affected source and audio tests, then finish with the full targeted
commands above.
