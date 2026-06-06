# Track-Aware Stream Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace source-id-only audio stream resolution with a request-based interface that preserves Bilibili multi-P identity through playback, fallback, downloads, tests, and debug tooling.

**Architecture:** Add `AudioStreamRequest` next to the existing source stream types and make `BaseSource` stream methods accept that request. Source adapters own their own identity rules, while shared fallback code only copies the request and changes stream config. Playback and download callers build the same request shape from `Track`, settings, auth headers, and optional failed URL.

**Tech Stack:** Dart, Flutter, Riverpod, Isar, Dio, `youtube_explode_dart`, Flutter test.

---

## File Structure

- Modify: `lib/data/sources/base_source.dart`
  - Owns `AudioStreamConfig`, new `AudioStreamRequest`, `AudioStreamResult`, and the request-based `BaseSource` stream interface.
- Modify: `lib/data/sources/audio_stream_quality_fallback.dart`
  - Owns quality fallback only; no source-specific imports or Bilibili branches.
- Modify: `lib/data/sources/bilibili_source.dart`
  - Owns Bilibili `cid` handling internally through `AudioStreamRequest`.
- Modify: `lib/data/sources/youtube_source.dart`
  - Reads request fields and preserves existing stream priority behavior.
- Modify: `lib/data/sources/netease_source.dart`
  - Reads request fields and preserves existing stream/error semantics.
- Modify: `lib/services/audio/internal/audio_stream_delegate.dart`
  - Builds `AudioStreamRequest` from `Track`, settings, and auth headers for playback and alternative fallback.
- Modify: `lib/services/download/download_service.dart`
  - Builds `AudioStreamRequest` from `Track`, settings, and auth headers for downloads.
- Modify: `lib/ui/pages/debug/youtube_stream_test_page.dart`
  - Uses request-based debug stream calls.
- Modify: `lib/data/sources/AGENTS.md`
  - Documents the new request-based stream interface and Bilibili multi-P identity rule.
- Create: `test/data/sources/audio_stream_quality_fallback_test.dart`
  - Protects request-copy and identity-preservation behavior in the shared fallback module.
- Modify: source tests and service tests with `BaseSource` fakes:
  - `test/bilibili_source_test.dart`
  - `test/data/sources/youtube_source_test.dart`
  - `test/data/sources/netease_source_test.dart`
  - `test/services/audio/audio_stream_manager_test.dart`
  - `test/services/download/download_service_phase1_test.dart`
  - Additional compile fallout under `test/services/audio`, `test/services/import`, and `test/providers` where fakes override `getAudioStream`.

## Task 1: Add Request Interface And Fallback Tests

**Files:**
- Modify: `lib/data/sources/base_source.dart`
- Create: `test/data/sources/audio_stream_quality_fallback_test.dart`
- Modify: `lib/data/sources/audio_stream_quality_fallback.dart`

- [ ] **Step 1: Write failing tests for request preservation**

Create `test/data/sources/audio_stream_quality_fallback_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/audio_stream_quality_fallback.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_exception.dart';

void main() {
  group('audio stream quality fallback', () {
    test('primary fallback preserves track identity and auth headers', () async {
      final source = _RecordingSource()
        ..failQualities.add(AudioQualityLevel.high);
      final request = AudioStreamRequest(
        sourceId: 'BVmulti',
        cid: 24680,
        pageNum: 2,
        config: const AudioStreamConfig(
          qualityLevel: AudioQualityLevel.high,
        ),
        authHeaders: const {'Cookie': 'SESSDATA=token'},
      );

      final result = await fetchAudioStreamWithQualityFallback(
        source: source,
        request: request,
      );

      expect(result.url, 'https://example.com/BVmulti-medium.m4a');
      expect(source.primaryRequests.map((r) => r.config.qualityLevel), [
        AudioQualityLevel.high,
        AudioQualityLevel.medium,
      ]);
      expect(source.primaryRequests.every((r) => r.sourceId == 'BVmulti'), isTrue);
      expect(source.primaryRequests.every((r) => r.cid == 24680), isTrue);
      expect(source.primaryRequests.every((r) => r.pageNum == 2), isTrue);
      expect(
        source.primaryRequests.every(
          (r) => r.authHeaders?['Cookie'] == 'SESSDATA=token',
        ),
        isTrue,
      );
    });

    test('alternative fallback preserves failedUrl and identity', () async {
      final source = _RecordingSource()..returnNullAlternativeForHigh = true;
      final request = AudioStreamRequest(
        sourceId: 'BVmulti',
        cid: 13579,
        pageNum: 3,
        failedUrl: 'https://failed.example/audio.m4a',
        config: const AudioStreamConfig(
          qualityLevel: AudioQualityLevel.high,
        ),
        authHeaders: const {'Cookie': 'SESSDATA=token'},
      );

      final result = await fetchAlternativeAudioStreamWithQualityFallback(
        source: source,
        request: request,
      );

      expect(result?.url, 'https://example.com/BVmulti-medium-alt.m4a');
      expect(source.alternativeRequests.map((r) => r.config.qualityLevel), [
        AudioQualityLevel.medium,
      ]);
      expect(source.alternativeRequests.single.failedUrl, request.failedUrl);
      expect(source.alternativeRequests.single.cid, 13579);
      expect(source.alternativeRequests.single.pageNum, 3);
    });

    test('non-fallbackable source errors are rethrown', () async {
      final source = _RecordingSource()
        ..failQualities.add(AudioQualityLevel.high)
        ..failingKind = SourceErrorKind.network;
      final request = AudioStreamRequest(
        sourceId: 'network-failure',
        config: const AudioStreamConfig(
          qualityLevel: AudioQualityLevel.high,
        ),
      );

      await expectLater(
        fetchAudioStreamWithQualityFallback(
          source: source,
          request: request,
        ),
        throwsA(isA<_FakeSourceException>()),
      );

      expect(source.primaryRequests.map((r) => r.config.qualityLevel), [
        AudioQualityLevel.high,
      ]);
    });
  });
}

class _RecordingSource extends BaseSource {
  final primaryRequests = <AudioStreamRequest>[];
  final alternativeRequests = <AudioStreamRequest>[];
  final failQualities = <AudioQualityLevel>{};
  var failingKind = SourceErrorKind.unavailable;
  var returnNullAlternativeForHigh = false;

  @override
  SourceType get sourceType => SourceType.bilibili;

  @override
  String? parseId(String url) => url;

  @override
  bool isValidId(String id) => id.isNotEmpty;

  @override
  Future<Track> getTrackInfo(
    String sourceId, {
    Map<String, String>? authHeaders,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
    primaryRequests.add(request);
    if (failQualities.contains(request.config.qualityLevel)) {
      throw _FakeSourceException(failingKind);
    }
    return AudioStreamResult(
      url:
          'https://example.com/${request.sourceId}-${request.config.qualityLevel.name}.m4a',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<AudioStreamResult?> getAlternativeAudioStream(
    AudioStreamRequest request,
  ) async {
    if (request.config.qualityLevel == AudioQualityLevel.high &&
        returnNullAlternativeForHigh) {
      return null;
    }
    alternativeRequests.add(request);
    return AudioStreamResult(
      url:
          'https://example.com/${request.sourceId}-${request.config.qualityLevel.name}-alt.m4a',
      streamType: StreamType.audioOnly,
    );
  }

  @override
  Future<Track> refreshAudioUrl(
    Track track, {
    Map<String, String>? authHeaders,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    return SearchResult.empty();
  }

  @override
  Future<PlaylistParseResult> parsePlaylist(
    String playlistUrl, {
    int page = 1,
    int pageSize = 20,
    Map<String, String>? authHeaders,
  }) async {
    throw UnimplementedError();
  }

  @override
  bool isPlaylistUrl(String url) => false;

  @override
  Future<bool> checkAvailability(String sourceId) async => true;
}

class _FakeSourceException extends SourceApiException {
  const _FakeSourceException(SourceErrorKind kind)
      : super(
          sourceType: SourceType.bilibili,
          kind: kind,
          code: 'fake',
          message: 'fake failure',
        );
}
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```bash
flutter test test/data/sources/audio_stream_quality_fallback_test.dart
```

Expected: FAIL because `AudioStreamRequest` and `fetchAlternativeAudioStreamWithQualityFallback` do not exist, and `BaseSource.getAudioStream` still accepts `String`.

- [ ] **Step 3: Add `AudioStreamRequest` and change `BaseSource` signatures**

In `lib/data/sources/base_source.dart`, add after `AudioStreamConfig`:

```dart
class AudioStreamRequest {
  final String sourceId;
  final int? cid;
  final int? pageNum;
  final AudioStreamConfig config;
  final Map<String, String>? authHeaders;
  final String? failedUrl;

  const AudioStreamRequest({
    required this.sourceId,
    this.cid,
    this.pageNum,
    this.config = AudioStreamConfig.defaultConfig,
    this.authHeaders,
    this.failedUrl,
  });

  AudioStreamRequest copyWith({
    String? sourceId,
    int? cid,
    bool clearCid = false,
    int? pageNum,
    bool clearPageNum = false,
    AudioStreamConfig? config,
    Map<String, String>? authHeaders,
    bool clearAuthHeaders = false,
    String? failedUrl,
    bool clearFailedUrl = false,
  }) {
    return AudioStreamRequest(
      sourceId: sourceId ?? this.sourceId,
      cid: clearCid ? null : (cid ?? this.cid),
      pageNum: clearPageNum ? null : (pageNum ?? this.pageNum),
      config: config ?? this.config,
      authHeaders:
          clearAuthHeaders ? null : (authHeaders ?? this.authHeaders),
      failedUrl: clearFailedUrl ? null : (failedUrl ?? this.failedUrl),
    );
  }
}
```

Then change `BaseSource` stream methods to:

```dart
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request);

Future<String> getAudioUrl(AudioStreamRequest request) async {
  final result = await getAudioStream(request);
  return result.url;
}

Future<AudioStreamResult?> getAlternativeAudioStream(
  AudioStreamRequest request,
) async {
  return null;
}

Future<String?> getAlternativeAudioUrl(AudioStreamRequest request) async {
  final result = await getAlternativeAudioStream(request);
  return result?.url;
}
```

- [ ] **Step 4: Rewrite shared fallback helper around requests**

In `lib/data/sources/audio_stream_quality_fallback.dart`, remove the `BilibiliSource` import and replace the stream functions with:

```dart
Future<AudioStreamResult> fetchAudioStreamWithQualityFallback({
  required BaseSource source,
  required AudioStreamRequest request,
}) async {
  final levels = audioQualityFallbackLevels(request.config.qualityLevel);
  SourceApiException? lastQualityError;
  StackTrace? lastQualityStackTrace;

  for (var i = 0; i < levels.length; i++) {
    final level = levels[i];
    try {
      return await source.getAudioStream(
        request.copyWith(
          config: request.config.copyWith(qualityLevel: level),
        ),
      );
    } on SourceApiException catch (error, stackTrace) {
      lastQualityError = error;
      lastQualityStackTrace = stackTrace;
      final hasLowerQuality = i < levels.length - 1;
      if (!hasLowerQuality || !error.kind.canFallbackToLowerAudioQuality) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  Error.throwWithStackTrace(lastQualityError!, lastQualityStackTrace!);
}

Future<AudioStreamResult?> fetchAlternativeAudioStreamWithQualityFallback({
  required BaseSource source,
  required AudioStreamRequest request,
}) async {
  for (final level in audioQualityFallbackLevels(
    request.config.qualityLevel,
    includeCurrent: false,
  )) {
    final fallbackRequest = request.copyWith(
      config: request.config.copyWith(qualityLevel: level),
    );
    final sourceAlternative =
        await source.getAlternativeAudioStream(fallbackRequest);
    if (sourceAlternative != null) return sourceAlternative;

    try {
      final primaryFallback = await source.getAudioStream(fallbackRequest);
      if (primaryFallback.url != request.failedUrl) {
        return primaryFallback;
      }
    } on SourceApiException catch (error) {
      if (!error.kind.canFallbackToLowerAudioQuality) rethrow;
    }
  }

  return source.getAlternativeAudioStream(request);
}
```

Remove `fetchTrackAudioStreamWithQualityFallback`, `fetchTrackAudioStream`, and `fetchTrackAlternativeAudioStream`.

- [ ] **Step 5: Run the new fallback test**

Run:

```bash
flutter test test/data/sources/audio_stream_quality_fallback_test.dart
```

Expected: PASS for the new fallback tests, but the wider project will not compile until source adapters and fakes are migrated.

- [ ] **Step 6: Checkpoint**

Run:

```bash
git diff -- lib/data/sources/base_source.dart lib/data/sources/audio_stream_quality_fallback.dart test/data/sources/audio_stream_quality_fallback_test.dart
```

Expected: diff contains only the request DTO, fallback helper rewrite, and new focused tests.

Do not commit unless the user explicitly requested commits.

## Task 2: Migrate Source Adapters

**Files:**
- Modify: `lib/data/sources/bilibili_source.dart`
- Modify: `lib/data/sources/youtube_source.dart`
- Modify: `lib/data/sources/netease_source.dart`

- [ ] **Step 1: Migrate `BilibiliSource` primary stream method**

Change the override in `lib/data/sources/bilibili_source.dart` to:

```dart
@override
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
  final bvid = request.sourceId;
  logDebug(
    'Getting audio stream for bvid: $bvid with config: '
    'qualityLevel=${request.config.qualityLevel}',
  );
  try {
    final cid = request.cid ?? await _getCid(
      bvid,
      authHeaders: request.authHeaders,
    );
    logDebug('Got cid: $cid for bvid: $bvid');

    return _getAudioStreamWithCid(
      bvid,
      cid,
      request.config,
      authHeaders: request.authHeaders,
    );
  } on BilibiliApiException catch (e) {
    logError(
      'Bilibili API error for $bvid: code=${e.code}, message=${e.message}',
    );
    rethrow;
  } on DioException catch (e) {
    logError(
      'Network error getting audio URL for $bvid: ${e.type}, ${e.message}',
    );
    throw _handleDioError(e);
  }
}
```

- [ ] **Step 2: Remove public Bilibili cid stream methods**

Delete these public methods from `BilibiliSource`:

```dart
Future<AudioStreamResult> getAudioStreamWithCid(...)
Future<String> getAudioUrlWithCid(...)
Future<AudioStreamResult?> getAlternativeAudioStreamWithCid(...)
```

Keep `_getAudioStreamWithCid(...)` and `_tryGetStreamByType(...)` as private implementation.

- [ ] **Step 3: Migrate Bilibili alternative stream method**

Replace the alternative override with:

```dart
@override
Future<AudioStreamResult?> getAlternativeAudioStream(
  AudioStreamRequest request,
) async {
  final bvid = request.sourceId;
  try {
    final cid = request.cid ?? await _getCid(
      bvid,
      authHeaders: request.authHeaders,
    );
    return _getAlternativeAudioStreamWithCid(
      bvid,
      cid,
      failedUrl: request.failedUrl,
      config: request.config,
      authHeaders: request.authHeaders,
    );
  } on BilibiliApiException {
    rethrow;
  } on DioException catch (e) {
    throw _handleDioError(e);
  }
}
```

Add the private helper by renaming the old public `getAlternativeAudioStreamWithCid`:

```dart
Future<AudioStreamResult?> _getAlternativeAudioStreamWithCid(
  String bvid,
  int cid, {
  String? failedUrl,
  AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  Map<String, String>? authHeaders,
}) async {
  SourceApiException? lastFallbackableError;
  for (final streamType in config.streamPriority) {
    try {
      final result = await _tryGetStreamByType(
        bvid,
        cid,
        streamType,
        config,
        authHeaders: authHeaders,
        failedUrl: failedUrl,
      );
      if (result != null) return result;
    } catch (e) {
      final sourceError = e is DioException ? _handleDioError(e) : e;
      if (_shouldAbortStreamFallback(sourceError)) throw sourceError;
      if (sourceError is SourceApiException) {
        lastFallbackableError = sourceError;
      }
      logDebug(
        'Alternative stream type $streamType failed for $bvid:$cid: $sourceError',
      );
    }
  }

  if (lastFallbackableError != null &&
      !lastFallbackableError.kind.canFallbackToLowerAudioQuality) {
    throw lastFallbackableError;
  }
  return null;
}
```

- [ ] **Step 4: Update Bilibili internal `getTrackInfo` audio URL call**

Where `getTrackInfo` currently calls `getAudioUrl(bvid, authHeaders: authHeaders)`, change it to:

```dart
final audioUrl = await getAudioUrl(
  AudioStreamRequest(
    sourceId: bvid,
    authHeaders: authHeaders,
  ),
);
```

- [ ] **Step 5: Migrate `YouTubeSource` stream methods**

Change `getAudioStream` signature and local variables:

```dart
@override
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
  final videoId = request.sourceId;
  final config = request.config;
  final authHeaders = request.authHeaders;
  logDebug(
    'Getting audio stream for YouTube video: $videoId with config: '
    'qualityLevel=${config.qualityLevel}, streamPriority=${config.streamPriority}',
  );

  // Keep the existing method body after this point.
}
```

Change `getAlternativeAudioStream` similarly:

```dart
@override
Future<AudioStreamResult?> getAlternativeAudioStream(
  AudioStreamRequest request,
) async {
  final videoId = request.sourceId;
  final config = request.config;
  final authHeaders = request.authHeaders;
  final failedUrl = request.failedUrl;
  logDebug('Getting alternative audio stream for YouTube video: $videoId');

  // Keep the existing method body after this point.
}
```

- [ ] **Step 6: Update YouTube `refreshAudioUrl` if it calls stream methods**

Find `refreshAudioUrl` in `lib/data/sources/youtube_source.dart`. If it calls `getAudioStream(track.sourceId, ...)`, change that call to:

```dart
final result = await getAudioStream(
  AudioStreamRequest(
    sourceId: track.sourceId,
    config: config ?? AudioStreamConfig.defaultConfig,
    authHeaders: authHeaders,
  ),
);
```

If `config` is not in scope, use:

```dart
final result = await getAudioStream(
  AudioStreamRequest(
    sourceId: track.sourceId,
    authHeaders: authHeaders,
  ),
);
```

- [ ] **Step 7: Migrate `NeteaseSource` stream and refresh methods**

Change `getAudioStream` to:

```dart
@override
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
  final sourceId = request.sourceId;
  final config = request.config;
  final authHeaders = request.authHeaders;
  logDebug(
    'Getting audio stream for netease song: $sourceId, quality: '
    '${config.qualityLevel}',
  );

  // Keep the existing method body after this point.
}
```

In `refreshAudioUrl`, replace:

```dart
final result =
    await getAudioStream(track.sourceId, authHeaders: authHeaders);
```

with:

```dart
final result = await getAudioStream(
  AudioStreamRequest(
    sourceId: track.sourceId,
    authHeaders: authHeaders,
  ),
);
```

- [ ] **Step 8: Run analyzer for source files to expose remaining adapter errors**

Run:

```bash
flutter analyze lib/data/sources
```

Expected: source-adapter stream signature errors are gone. Errors in tests and services may remain.

- [ ] **Step 9: Checkpoint**

Run:

```bash
git diff -- lib/data/sources/bilibili_source.dart lib/data/sources/youtube_source.dart lib/data/sources/netease_source.dart
```

Expected: source adapters use `AudioStreamRequest`; no public Bilibili `getAudioStreamWithCid`, `getAudioUrlWithCid`, or `getAlternativeAudioStreamWithCid` remains.

Do not commit unless the user explicitly requested commits.

## Task 3: Migrate Playback And Download Callers

**Files:**
- Modify: `lib/services/audio/internal/audio_stream_delegate.dart`
- Modify: `lib/services/download/download_service.dart`

- [ ] **Step 1: Build request in playback primary path**

In `AudioStreamDelegate.ensureAudioStream`, replace the call to `fetchTrackAudioStreamWithQualityFallback` with:

```dart
final streamRequest = AudioStreamRequest(
  sourceId: track.sourceId,
  cid: track.cid,
  pageNum: track.pageNum,
  config: config,
  authHeaders: authHeaders,
);
final streamResult = await fetchAudioStreamWithQualityFallback(
  source: source,
  request: streamRequest,
);
```

- [ ] **Step 2: Build request in playback alternative path**

In `AudioStreamDelegate.getAlternativeAudioStream`, replace the manual fallback loop with:

```dart
final streamRequest = AudioStreamRequest(
  sourceId: track.sourceId,
  cid: track.cid,
  pageNum: track.pageNum,
  config: config,
  authHeaders: authHeaders,
  failedUrl: failedUrl,
);

return fetchAlternativeAudioStreamWithQualityFallback(
  source: source,
  request: streamRequest,
);
```

Remove now-unused imports or helper references to `fetchTrackAudioStream` and `fetchTrackAlternativeAudioStream`.

- [ ] **Step 3: Build request in download stream resolution**

In `DownloadService._startDownload`, replace the call to `fetchTrackAudioStreamWithQualityFallback` with:

```dart
final streamRequest = AudioStreamRequest(
  sourceId: track.sourceId,
  cid: track.cid,
  pageNum: track.pageNum,
  config: config,
  authHeaders: authHeaders,
);
final streamResult = await fetchAudioStreamWithQualityFallback(
  source: source,
  request: streamRequest,
);
```

- [ ] **Step 4: Run targeted service compile check**

Run:

```bash
flutter test test/services/audio/audio_stream_manager_test.dart --plain-name "selectPlayback preserves Bilibili cid during stream resolution"
```

Expected: FAIL at compile time because tests/fakes still override old stream signatures.

- [ ] **Step 5: Checkpoint**

Run:

```bash
git diff -- lib/services/audio/internal/audio_stream_delegate.dart lib/services/download/download_service.dart
```

Expected: playback and download callers build `AudioStreamRequest` from `Track`; no source-specific stream branching appears in these files.

Do not commit unless the user explicitly requested commits.

## Task 4: Migrate Focused Service Tests And Fakes

**Files:**
- Modify: `test/services/audio/audio_stream_manager_test.dart`
- Modify: `test/services/download/download_service_phase1_test.dart`

- [ ] **Step 1: Update generic audio stream manager fake**

In `test/services/audio/audio_stream_manager_test.dart`, change fake source fields:

```dart
final List<AudioStreamRequest> audioStreamRequests = [];
AudioStreamRequest? lastAlternativeRequest;
```

Change fake `getAudioStream` override to:

```dart
@override
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
  audioStreamRequests.add(request);
  audioStreamQualityRequests.add(request.config.qualityLevel);
  lastAudioAuthHeaders = request.authHeaders;
  if (failingAudioQualities.contains(request.config.qualityLevel)) {
    throw _FakeSourceException(
      kind: failingAudioKind,
      message: 'quality ${request.config.qualityLevel.name} failed',
    );
  }
  final expiry = nextAudioExpiry;
  nextAudioExpiry = null;
  final qualitySuffix =
      encodeQualityInAudioUrl && !reuseFailedUrlForPrimaryFallback
          ? '-${request.config.qualityLevel.name}'
          : '';
  return AudioStreamResult(
    url: 'https://example.com/${request.sourceId}$qualitySuffix.m4a',
    bitrate: bitrateByQuality[request.config.qualityLevel],
    container: 'm4a',
    codec: 'aac',
    streamType: StreamType.audioOnly,
    expiry: expiry,
  );
}
```

Change fake `getAlternativeAudioStream` override to:

```dart
@override
Future<AudioStreamResult?> getAlternativeAudioStream(
  AudioStreamRequest request,
) async {
  lastAlternativeRequest = request;
  lastFailedUrl = request.failedUrl;
  lastAlternativeConfig = request.config;
  lastAlternativeAuthHeaders = request.authHeaders;
  alternativeQualityRequests.add(request.config.qualityLevel);
  if (returnNullAlternative) {
    return null;
  }
  return AudioStreamResult(
    url: 'https://example.com/${request.sourceId}-fallback.m3u8',
    container: 'm3u8',
    codec: 'aac',
    streamType: request.config.streamPriority.first,
    expiry: const Duration(minutes: 16),
  );
}
```

- [ ] **Step 2: Replace `_FakeBilibiliSource` cid-method assertions**

In `_FakeBilibiliSource`, remove overrides for public cid methods and implement request-based methods:

```dart
final List<AudioStreamRequest> primaryRequests = [];
final List<AudioStreamRequest> alternativeRequests = [];

@override
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
  primaryRequests.add(request);
  if (request.cid == null) {
    throw StateError('Bilibili request must preserve cid');
  }
  return AudioStreamResult(
    url: 'https://example.com/${request.sourceId}-${request.cid}.m4a',
    streamType: StreamType.audioOnly,
    expiry: const Duration(minutes: 16),
  );
}

@override
Future<AudioStreamResult?> getAlternativeAudioStream(
  AudioStreamRequest request,
) async {
  alternativeRequests.add(request);
  if (request.cid == null) {
    throw StateError('Bilibili alternative request must preserve cid');
  }
  return AudioStreamResult(
    url:
        'https://example.com/${request.sourceId}-${request.cid}-${request.config.qualityLevel.name}-alternative.m4a',
    streamType: request.config.streamPriority.first,
    expiry: const Duration(minutes: 16),
  );
}
```

Update expectations in the two Bilibili cid tests:

```dart
expect(bilibili.primaryRequests.map((r) => (sourceId: r.sourceId, cid: r.cid)), [
  (sourceId: 'BVmultiPage', cid: 24680),
]);
```

and:

```dart
expect(bilibili.alternativeRequests.map((r) => (
  sourceId: r.sourceId,
  cid: r.cid,
  failedUrl: r.failedUrl,
  quality: r.config.qualityLevel,
)), [
  (
    sourceId: 'BVmultiPage',
    cid: 13579,
    failedUrl: failedUrl,
    quality: AudioQualityLevel.medium,
  ),
]);
```

- [ ] **Step 3: Run focused audio stream manager tests**

Run:

```bash
flutter test test/services/audio/audio_stream_manager_test.dart
```

Expected: PASS for `audio_stream_manager_test.dart`, or compile failures only from additional old fake signatures in the same file. Fix same-file fake signatures using the pattern above until this command passes.

- [ ] **Step 4: Update download service fakes**

In `test/services/download/download_service_phase1_test.dart`, change `_StaticAudioSource.getAudioStream` to:

```dart
@override
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
  return AudioStreamResult(
    url: audioUrl,
    streamType: StreamType.audioOnly,
    expiry: streamExpiry,
  );
}
```

Change `_BlockingAudioSource.getAudioStream` to:

```dart
@override
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
  if (!_requested.isCompleted) {
    _requested.complete();
  }
  await _release.future;
  return super.getAudioStream(request);
}
```

Change `_RecordingAudioSource.getAudioStream` to:

```dart
@override
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
  recordedAuthHeaders.add(
    request.authHeaders == null
        ? null
        : Map<String, String>.from(request.authHeaders!),
  );
  return super.getAudioStream(request);
}
```

Change `_RecordingBilibiliSource` to record request identity:

```dart
final List<AudioStreamRequest> primaryRequests = [];

@override
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request) async {
  primaryRequests.add(request);
  if (request.cid == null) {
    throw StateError('Bilibili request must preserve cid');
  }
  return AudioStreamResult(
    url: audioUrl,
    streamType: StreamType.audioOnly,
    expiry: const Duration(minutes: 16),
  );
}
```

Update the download cid test expectation to:

```dart
expect(
  bilibili.primaryRequests.map((r) => (sourceId: r.sourceId, cid: r.cid)),
  [(sourceId: 'BV-download', cid: 24680)],
);
```

- [ ] **Step 5: Run focused download tests**

Run:

```bash
flutter test test/services/download/download_service_phase1_test.dart --plain-name "download start preserves Bilibili cid during stream resolution"
```

Expected: PASS for the Bilibili cid preservation test.

Then run:

```bash
flutter test test/services/download/download_service_phase1_test.dart
```

Expected: PASS for the full download phase1 test file, or compile failures only from remaining old fake stream signatures in this file. Fix same-file fake signatures using the same request-based pattern.

- [ ] **Step 6: Checkpoint**

Run:

```bash
git diff -- test/services/audio/audio_stream_manager_test.dart test/services/download/download_service_phase1_test.dart
```

Expected: focused service tests assert request identity instead of public Bilibili cid method calls.

Do not commit unless the user explicitly requested commits.

## Task 5: Migrate Source Tests, Debug Page, And Compile Fallout

**Files:**
- Modify: `test/bilibili_source_test.dart`
- Modify: `test/data/sources/youtube_source_test.dart`
- Modify: `test/data/sources/netease_source_test.dart`
- Modify: `lib/ui/pages/debug/youtube_stream_test_page.dart`
- Modify: any remaining test fake files reported by analyzer.

- [ ] **Step 1: Migrate Bilibili source tests**

Replace direct stream calls such as:

```dart
final result = await source.getAudioStream(
  'BV123',
  config: config,
  authHeaders: authHeaders,
);
```

with:

```dart
final result = await source.getAudioStream(
  AudioStreamRequest(
    sourceId: 'BV123',
    config: config,
    authHeaders: authHeaders,
  ),
);
```

Replace cid-specific public calls such as:

```dart
final result = await source.getAudioStreamWithCid(
  'BV123',
  456,
  config: config,
);
```

with:

```dart
final result = await source.getAudioStream(
  AudioStreamRequest(
    sourceId: 'BV123',
    cid: 456,
    config: config,
  ),
);
```

Replace alternative cid-specific calls with:

```dart
final result = await source.getAlternativeAudioStream(
  AudioStreamRequest(
    sourceId: 'BV123',
    cid: 456,
    failedUrl: failedUrl,
    config: config,
  ),
);
```

- [ ] **Step 2: Migrate YouTube source tests**

Replace calls in `test/data/sources/youtube_source_test.dart`:

```dart
final result = await source.getAudioStream(
  videoId,
  config: config,
  authHeaders: authHeaders,
);
```

with:

```dart
final result = await source.getAudioStream(
  AudioStreamRequest(
    sourceId: videoId,
    config: config,
    authHeaders: authHeaders,
  ),
);
```

Replace alternative calls with:

```dart
final result = await source.getAlternativeAudioStream(
  AudioStreamRequest(
    sourceId: videoId,
    failedUrl: failedUrl,
    config: config,
    authHeaders: authHeaders,
  ),
);
```

- [ ] **Step 3: Migrate Netease source tests**

Replace calls in `test/data/sources/netease_source_test.dart`:

```dart
await source.getAudioStream('123');
```

with:

```dart
await source.getAudioStream(
  const AudioStreamRequest(sourceId: '123'),
);
```

When auth or config is present, include it in the request:

```dart
await source.getAudioStream(
  AudioStreamRequest(
    sourceId: '123',
    config: config,
    authHeaders: authHeaders,
  ),
);
```

- [ ] **Step 4: Migrate YouTube debug page**

In `lib/ui/pages/debug/youtube_stream_test_page.dart`, replace:

```dart
final stream = await source.getAudioStream(
  videoId,
  config: fmp.AudioStreamConfig.defaultConfig,
  authHeaders: authHeaders,
);
```

with:

```dart
final stream = await source.getAudioStream(
  fmp.AudioStreamRequest(
    sourceId: videoId,
    config: fmp.AudioStreamConfig.defaultConfig,
    authHeaders: authHeaders,
  ),
);
```

- [ ] **Step 5: Find remaining old stream call sites**

Run:

```bash
rg -n "getAudioStream\\(|getAudioUrl\\(|getAlternativeAudioStream\\(|getAlternativeAudioUrl\\(|getAudioStreamWithCid|getAudioUrlWithCid|getAlternativeAudioStreamWithCid" lib test
```

Expected: no call passes a raw `String` to stream methods, and no public Bilibili cid method references remain. Allowed matches are method declarations using `AudioStreamRequest` and private Bilibili helpers with leading `_`.

- [ ] **Step 6: Fix remaining fake overrides reported by analyzer**

For each compile error shaped like:

```text
'getAudioStream' isn't a valid override
```

change:

```dart
Future<AudioStreamResult> getAudioStream(
  String sourceId, {
  AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  Map<String, String>? authHeaders,
})
```

to:

```dart
Future<AudioStreamResult> getAudioStream(AudioStreamRequest request)
```

Then replace local uses:

```dart
sourceId -> request.sourceId
config -> request.config
authHeaders -> request.authHeaders
```

For alternative overrides, replace local uses:

```dart
failedUrl -> request.failedUrl
```

- [ ] **Step 7: Run source tests**

Run:

```bash
flutter test test/bilibili_source_test.dart test/data/sources/youtube_source_test.dart test/data/sources/netease_source_test.dart
```

Expected: PASS for migrated source tests.

- [ ] **Step 8: Run broad compile-oriented targeted tests**

Run:

```bash
flutter test test/services/audio test/services/download/download_service_phase1_test.dart test/services/import test/providers/refresh_provider_stale_cleanup_test.dart
```

Expected: PASS, or failures unrelated to stream signature migration. Fix remaining stream-signature compile errors before moving on.

- [ ] **Step 9: Checkpoint**

Run:

```bash
git diff -- test/bilibili_source_test.dart test/data/sources/youtube_source_test.dart test/data/sources/netease_source_test.dart lib/ui/pages/debug/youtube_stream_test_page.dart
```

Expected: direct source tests and debug page use `AudioStreamRequest`.

Do not commit unless the user explicitly requested commits.

## Task 6: Update Documentation And Final Verification

**Files:**
- Modify: `lib/data/sources/AGENTS.md`
- Verify: all modified Dart/test files.

- [ ] **Step 1: Update source adapter guidance**

In `lib/data/sources/AGENTS.md`, replace the current audio stream config paragraph:

```text
`AudioStreamConfig` is passed to source `getAudioStream()` and returns
`AudioStreamResult` with bitrate/codec metadata. `BaseSource.getAlternativeAudioStream()`
also accepts `authHeaders`; playback handoff fallback must pass the same
auth-for-play headers as primary stream resolution.
```

with:

```text
`AudioStreamRequest` is passed to source `getAudioStream()` /
`getAlternativeAudioStream()` and carries source identity (`sourceId`, optional
`cid` / `pageNum`), `AudioStreamConfig`, auth headers, and the failed media URL
for alternative fallback. Source adapters own source-specific identity rules:
Bilibili multi-P stream resolution must use `request.cid` when present, and
shared fallback helpers must not branch on `BilibiliSource`.

`AudioStreamResult` returns bitrate/codec/container/stream-type metadata and
the URL expiry. Playback handoff fallback must pass the same auth-for-play
headers as primary stream resolution.
```

- [ ] **Step 2: Run final old-interface search**

Run:

```bash
rg -n "getAudioStreamWithCid|getAudioUrlWithCid|getAlternativeAudioStreamWithCid|fetchTrackAudioStream|fetchTrackAlternativeAudioStream|fetchTrackAudioStreamWithQualityFallback" lib test
```

Expected: no matches, except historical documentation if intentionally retained. Remove stale references from current code or current AGENTS guidance.

- [ ] **Step 3: Run targeted verification**

Run:

```bash
flutter test test/data/sources test/services/audio/audio_stream_manager_test.dart test/services/download/download_service_phase1_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: PASS, or only pre-existing warnings explicitly confirmed by the user. Do not ignore new stream-interface errors.

- [ ] **Step 5: Review diff for scope creep**

Run:

```bash
git diff --stat
git diff -- lib/data/sources/base_source.dart lib/data/sources/audio_stream_quality_fallback.dart lib/data/sources/bilibili_source.dart lib/services/audio/internal/audio_stream_delegate.dart lib/services/download/download_service.dart lib/data/sources/AGENTS.md
```

Expected: changes are limited to request-based stream resolution, tests/fakes, debug page migration, and scoped documentation.

- [ ] **Step 6: Final checkpoint**

Run:

```bash
git status --short
```

Expected: only files related to this plan are modified or added.

Do not commit unless the user explicitly requested commits.

## Self-Review Notes

- Spec coverage: request DTO, breaking `BaseSource` signatures, removal of public Bilibili cid stream methods, playback/download request construction, debug tooling migration, tests, documentation, and verification are all covered.
- Placeholder scan: no open-ended or unfinished implementation instructions are present.
- Type consistency: all new stream methods accept `AudioStreamRequest`; fallback helpers use `fetchAudioStreamWithQualityFallback` and `fetchAlternativeAudioStreamWithQualityFallback`; `failedUrl` lives on the request.
