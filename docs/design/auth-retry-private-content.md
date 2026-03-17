# Design: Authenticated Retry for Private Content

## Overview

Enable access to private Bilibili favorites and YouTube playlists/videos by retrying with user credentials when permission errors occur. Anonymous access is always attempted first to minimize account exposure.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Auth injection | Caller-level retry (Option C) | Sources stay clean, callers control auth usage |
| Private playlist import | Try anonymous URL first, auth retry on error | Consistent with general pattern |
| Playlist refresh | Try anonymous first, no tagging | Same retry pattern everywhere |
| YouTube InnerTube client | androidVr (streams) + WEB (metadata/playlists) | Matches current anonymous pattern |
| User experience | Silent retry | No toast/dialog, transparent to user |
| Scope | Full (all 6 integration points) | Play, import, refresh, detail, download, covers |

## 1. Exception Layer

### Add `isPermissionDenied` to `SourceApiException`

**File:** `lib/data/sources/source_exception.dart`

```dart
/// 权限不足（私人内容，需要登录重试）
/// 与 requiresLogin 不同：requiresLogin 表示"未登录"，
/// isPermissionDenied 表示"内容需要特定权限（如私人收藏夹/视频）"
bool get isPermissionDenied;
```

**`BilibiliApiException`** — `bilibili_source.dart`:
```dart
@override
bool get isPermissionDenied => numericCode == -403;
```

Bilibili `-403` = "访问权限不足" — returned for private favorites and private videos.

**`YouTubeApiException`** — `youtube_source.dart`:
```dart
@override
bool get isPermissionDenied =>
    code == 'login_required' ||
    code == 'private_or_inaccessible' ||
    code == 'age_restricted';
```

Note: YouTube doesn't distinguish "private" from "login_required" at the API level. `VideoUnavailableException` from youtube_explode_dart needs to be caught and mapped to a new code like `'private_or_unavailable'` — we'll refine detection in the InnerTube fallback path.

### Update `_mapCode` for Bilibili

```dart
if (code == -403) return 'permission_denied';
```

Also update `requiresLogin` to include `-403`:
```dart
bool get requiresLogin => numericCode == -101 || numericCode == -403;
```

## 2. Source Layer — Optional `authHeaders` Parameter

### 2.1 BilibiliSource Changes

**File:** `lib/data/sources/bilibili_source.dart`

Add `authHeaders` parameter to these methods:

```dart
Future<Track> getTrackInfo(String bvid, {Map<String, String>? authHeaders})
Future<AudioStreamResult> getAudioStream(String bvid, {
  AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  Map<String, String>? authHeaders,
})
Future<PlaylistParseResult> parsePlaylist(String playlistUrl, {
  int page = 1,
  int pageSize = 20,
  Map<String, String>? authHeaders,
})
Future<List<VideoPage>> getVideoPages(String bvid, {Map<String, String>? authHeaders})
Future<VideoDetail> getVideoDetail(String bvid, {Map<String, String>? authHeaders})
Future<Track> refreshAudioUrl(Track track, {Map<String, String>? authHeaders})
Future<AudioStreamResult> getAudioStreamWithCid(String bvid, int cid, {
  AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  Map<String, String>? authHeaders,
})
```

**Implementation pattern** — merge auth cookies into request:

```dart
Future<Track> getTrackInfo(String bvid, {Map<String, String>? authHeaders}) async {
  final response = await _dio.get(
    _viewApi,
    queryParameters: {'bvid': bvid},
    options: authHeaders != null ? _withAuth(authHeaders) : null,
  );
  // ... existing logic
}

/// Helper: create Options that merge auth headers with base headers
Options _withAuth(Map<String, String> authHeaders) {
  return Options(headers: authHeaders);
  // Dio merges Options.headers with BaseOptions.headers automatically.
  // For Cookie specifically, we need to append:
  // existing buvid cookies + auth cookies
}
```

**Cookie merging detail:**
Dio's `Options.headers` override `BaseOptions.headers` per-key. Since both use the `Cookie` key, we need to merge:

```dart
Options _withAuth(Map<String, String> authHeaders) {
  final baseCookie = _dio.options.headers['Cookie'] as String? ?? '';
  final authCookie = authHeaders['Cookie'] ?? '';
  final mergedCookie = authCookie.isNotEmpty
      ? '$baseCookie; $authCookie'
      : baseCookie;
  return Options(headers: {'Cookie': mergedCookie});
}
```

### 2.2 YouTubeSource Changes

**File:** `lib/data/sources/youtube_source.dart`

Add `authHeaders` parameter to these methods:

```dart
Future<Track> getTrackInfo(String videoId, {Map<String, String>? authHeaders})
Future<AudioStreamResult> getAudioStream(String videoId, {
  AudioStreamConfig config = AudioStreamConfig.defaultConfig,
  Map<String, String>? authHeaders,
})
Future<PlaylistParseResult> parsePlaylist(String playlistUrl, {
  int page = 1,
  int pageSize = 20,
  Map<String, String>? authHeaders,
})
Future<VideoDetail> getVideoDetail(String videoId, {Map<String, String>? authHeaders})
Future<Track> refreshAudioUrl(Track track, {Map<String, String>? authHeaders})
```

**Routing logic:**

```dart
Future<Track> getTrackInfo(String videoId, {Map<String, String>? authHeaders}) async {
  if (authHeaders != null) {
    return _getTrackInfoViaInnerTube(videoId, authHeaders);
  }
  // ... existing youtube_explode_dart logic
}
```

When `authHeaders` is null → existing youtube_explode_dart path (unchanged).
When `authHeaders` is provided → InnerTube API path (new).

### 2.3 New InnerTube Authenticated Methods

All three methods use the existing `_dio` instance and InnerTube constants.

#### a) `_getTrackInfoViaInnerTube(videoId, authHeaders)`

```dart
Future<Track> _getTrackInfoViaInnerTube(
  String videoId,
  Map<String, String> authHeaders,
) async {
  // POST /youtubei/v1/player with WEB client
  final response = await _dio.post(
    '$_innerTubeApiBase/player?key=$_innerTubeApiKey',
    data: jsonEncode({
      'videoId': videoId,
      'context': {
        'client': {
          'clientName': _innerTubeClientName,     // 'WEB'
          'clientVersion': _innerTubeClientVersion,
          'hl': 'en',
          'gl': 'US',
        },
      },
    }),
    options: Options(headers: authHeaders),
  );

  final data = response.data;
  final playabilityStatus = data['playabilityStatus'];
  final status = playabilityStatus?['status'];

  if (status != 'OK') {
    throw YouTubeApiException(
      code: status?.toString().toLowerCase() ?? 'error',
      message: playabilityStatus?['reason'] ?? 'Video unavailable',
    );
  }

  final videoDetails = data['videoDetails'];
  // Build Track from videoDetails...
  // Fields: title, lengthSeconds, author, channelId, thumbnail, viewCount
}
```

#### b) `_getAudioStreamViaInnerTube(videoId, authHeaders, config)`

```dart
Future<AudioStreamResult> _getAudioStreamViaInnerTube(
  String videoId,
  Map<String, String> authHeaders,
  AudioStreamConfig config,
) async {
  // Use androidVr client for audio-only streams (proven pattern)
  final response = await _dio.post(
    '$_innerTubeApiBase/player?key=$_innerTubeApiKey',
    data: jsonEncode({
      'videoId': videoId,
      'context': {
        'client': {
          'clientName': 'ANDROID_VR',
          'clientVersion': '1.57.29',
          'androidSdkVersion': 30,
          'hl': 'en',
          'gl': 'US',
        },
      },
    }),
    options: Options(headers: authHeaders),
  );

  final data = response.data;
  final streamingData = data['streamingData'];

  if (streamingData == null) {
    // Fallback: try WEB client for muxed streams
    return _getAudioStreamViaInnerTubeWeb(videoId, authHeaders, config);
  }

  // Parse adaptiveFormats for audio-only streams
  final adaptiveFormats = streamingData['adaptiveFormats'] as List? ?? [];
  // Apply same quality/format selection logic as _tryGetStream()
  // Select best audio stream based on config.qualityLevel, config.formatPriority
  // Return AudioStreamResult with url, bitrate, codec, container info
}
```

#### c) `_parsePlaylistViaInnerTube(playlistId, authHeaders, page, pageSize)`

```dart
Future<PlaylistParseResult> _parsePlaylistViaInnerTube(
  String playlistId,
  Map<String, String> authHeaders, {
  int page = 1,
  int pageSize = 20,
}) async {
  final browseId = 'VL$playlistId';

  final response = await _dio.post(
    '$_innerTubeApiBase/browse?key=$_innerTubeApiKey',
    data: jsonEncode({
      'browseId': browseId,
      'context': {
        'client': {
          'clientName': _innerTubeClientName,
          'clientVersion': _innerTubeClientVersion,
          'hl': 'en',
          'gl': 'US',
        },
      },
    }),
    options: Options(headers: authHeaders),
  );

  // Parse playlist metadata from header
  // Parse video items from contents
  // Handle continuation tokens for pagination
  // Return PlaylistParseResult with tracks, title, totalCount, hasMore
}
```

## 3. Auth Retry Utility

**New file:** `lib/core/utils/auth_retry_utils.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/track.dart';
import '../../data/sources/source_exception.dart';
import '../../providers/account_provider.dart';

/// Get auth headers for a platform, or null if not logged in.
Future<Map<String, String>?> getAuthHeadersForPlatform(
  SourceType platform,
  Ref ref,
) async {
  switch (platform) {
    case SourceType.bilibili:
      final service = ref.read(bilibiliAccountServiceProvider);
      final cookies = await service.getAuthCookieString();
      if (cookies == null) return null;
      return {'Cookie': cookies};
    case SourceType.youtube:
      final service = ref.read(youtubeAccountServiceProvider);
      return await service.getAuthHeaders(); // Cookie + SAPISIDHASH
    default:
      return null;
  }
}

/// Execute an action anonymously first, retry with auth on permission error.
/// Returns the result of the action.
/// If the action fails with a non-permission error, rethrows immediately.
/// If the action fails with a permission error but user is not logged in, rethrows.
Future<T> withAuthRetry<T>({
  required Future<T> Function(Map<String, String>? authHeaders) action,
  required SourceType platform,
  required Ref ref,
}) async {
  try {
    return await action(null); // anonymous first
  } on SourceApiException catch (e) {
    if (!e.isPermissionDenied && !e.requiresLogin) rethrow;

    final headers = await getAuthHeadersForPlatform(platform, ref);
    if (headers == null) rethrow; // not logged in, can't help

    return await action(headers); // silent retry with auth
  }
}
```

### Variant without Ref (for services that don't have Riverpod access)

Some callers like `QueueManager` and `DownloadService` don't have `Ref`. They receive account services via constructor injection.

```dart
/// Variant for non-Riverpod contexts.
/// Caller provides the auth header getter directly.
Future<T> withAuthRetryDirect<T>({
  required Future<T> Function(Map<String, String>? authHeaders) action,
  required Future<Map<String, String>?> Function() getAuthHeaders,
}) async {
  try {
    return await action(null);
  } on SourceApiException catch (e) {
    if (!e.isPermissionDenied && !e.requiresLogin) rethrow;

    final headers = await getAuthHeaders();
    if (headers == null) rethrow;

    return await action(headers);
  }
}
```

## 4. Caller Integration Points

### 4.1 QueueManager — Audio Playback

**File:** `lib/services/audio/queue_manager.dart`

**Change:** Add account service references to constructor, wrap `ensureAudioUrl()`.

```dart
QueueManager({
  required QueueRepository queueRepository,
  required TrackRepository trackRepository,
  required SettingsRepository settingsRepository,
  required SourceManager sourceManager,
  required BilibiliAccountService? bilibiliAccountService,  // NEW
  required YouTubeAccountService? youtubeAccountService,    // NEW
})
```

In `ensureAudioUrl()`, wrap the `source.getAudioStream()` / `source.refreshAudioUrl()` calls:

```dart
// Before:
final result = await source.getAudioStream(track.sourceId, config: config);

// After:
final result = await withAuthRetryDirect(
  action: (authHeaders) => source.getAudioStream(
    track.sourceId,
    config: config,
    authHeaders: authHeaders,
  ),
  getAuthHeaders: () => _getAuthHeaders(track.sourceType),
);
```

Where `_getAuthHeaders()` delegates to the appropriate account service.

### 4.2 ImportService — Playlist Import & Refresh

**File:** `lib/services/import/import_service.dart`

**Change:** Add account service references, wrap `parsePlaylist()` and `getVideoPages()`.

```dart
// In importFromUrl():
final result = await withAuthRetryDirect(
  action: (authHeaders) => source.parsePlaylist(url, authHeaders: authHeaders),
  getAuthHeaders: () => _getAuthHeaders(source.sourceType),
);

// In _expandMultiPageVideos():
final pages = await withAuthRetryDirect(
  action: (authHeaders) => bilibiliSource.getVideoPages(
    track.sourceId,
    authHeaders: authHeaders,
  ),
  getAuthHeaders: () => _getAuthHeaders(SourceType.bilibili),
);
```

### 4.3 DownloadService — Audio & Cover Download

**File:** `lib/services/download/download_service.dart`

**Change:** Wrap `source.getAudioStream()` and `source.getVideoDetail()` calls.

```dart
// Audio URL fetch:
final streamResult = await withAuthRetryDirect(
  action: (authHeaders) => source.getAudioStream(
    track.sourceId,
    config: config,
    authHeaders: authHeaders,
  ),
  getAuthHeaders: () => _getAuthHeaders(track.sourceType),
);
```

### 4.4 TrackDetailProvider — Video Detail Panel

**File:** `lib/providers/track_detail_provider.dart`

**Change:** Wrap `getVideoDetail()` call. This provider has `Ref`, so use the Ref-based variant.

```dart
// Before:
final detail = await source.getVideoDetail(track.sourceId);

// After:
final detail = await withAuthRetry(
  action: (authHeaders) => source.getVideoDetail(
    track.sourceId,
    authHeaders: authHeaders,
  ),
  platform: track.sourceType,
  ref: ref,
);
```

### 4.5 PlaylistRefresh — Refresh Provider

**File:** `lib/providers/refresh_provider.dart`

**Change:** The refresh flow calls `ImportService.refreshPlaylist()`, which internally calls `parsePlaylist()`. Since ImportService is already wrapped (4.2), this is covered automatically.

### 4.6 SearchPage — Video Page Expansion

**File:** `lib/ui/pages/search/search_page.dart`

**Change:** Wrap `getVideoPages()` call in `_loadVideoPages()`.

```dart
final pages = await withAuthRetry(
  action: (authHeaders) => bilibiliSource.getVideoPages(
    bvid,
    authHeaders: authHeaders,
  ),
  platform: SourceType.bilibili,
  ref: ref,
);
```

## 5. BaseSource Abstract Interface Update

**File:** `lib/data/sources/base_source.dart` (or wherever BaseSource is defined)

If `BaseSource` defines abstract method signatures, they need the `authHeaders` parameter too. Otherwise callers using `BaseSource` type won't see the parameter.

```dart
abstract class BaseSource {
  Future<Track> getTrackInfo(String id, {Map<String, String>? authHeaders});
  Future<AudioStreamResult> getAudioStream(String id, {
    AudioStreamConfig config,
    Map<String, String>? authHeaders,
  });
  Future<PlaylistParseResult> parsePlaylist(String url, {
    int page,
    int pageSize,
    Map<String, String>? authHeaders,
  });
  // etc.
}
```

## 6. Flow Diagrams

### 6.1 Audio Playback with Auth Retry

```
QueueManager.ensureAudioUrl(track)
         │
         ▼
withAuthRetryDirect(
  action: source.getAudioStream(id, authHeaders: ?)
)
         │
         ▼
source.getAudioStream(id, authHeaders: null)  ← anonymous
         │
    ┌────┴─────────────┐
    │ Success           │ SourceApiException
    │ → return stream   │ .isPermissionDenied?
    └──────────────────┘         │
                          ┌──────┴──────┐
                          │ No           │ Yes
                          │ → rethrow    │    │
                          └─────────────┘    ▼
                                    _getAuthHeaders(platform)
                                         │
                                    ┌────┴────┐
                                    │ null     │ headers
                                    │ → rethrow│    │
                                    └─────────┘    ▼
                              source.getAudioStream(id, authHeaders: headers)
                                         │
                                    ┌────┴────┐
                                    │ Success  │ Fail
                                    │ → return │ → rethrow
                                    └─────────┘
```

### 6.2 YouTube Source Internal Routing

```
YouTubeSource.getTrackInfo(videoId, authHeaders: ?)
         │
    ┌────┴────────────────┐
    │ authHeaders == null  │ authHeaders != null
    │                      │
    ▼                      ▼
youtube_explode_dart    InnerTube /player API
(existing path)         + WEB client + auth headers
                               │
                          Parse videoDetails
                          Return Track
```

```
YouTubeSource.getAudioStream(videoId, authHeaders: ?)
         │
    ┌────┴────────────────┐
    │ authHeaders == null  │ authHeaders != null
    │                      │
    ▼                      ▼
youtube_explode_dart    InnerTube /player API
(existing path)         + androidVr client + auth headers
                               │
                          Parse streamingData.adaptiveFormats
                          Select best audio stream
                          Return AudioStreamResult
```

## 7. Error Code Mapping

### Bilibili

| API Response Code | Semantic | Triggers Auth Retry? |
|-------------------|----------|---------------------|
| `-403` | 访问权限不足 | Yes |
| `-101` | 未登录 | Yes |
| `-404` | 资源不存在 | No (isUnavailable) |
| `-412` / `-509` | 限流 | No (isRateLimited) |
| `-10403` | 地区限制 | No (isGeoRestricted) |

### YouTube

| Error / Code | Semantic | Triggers Auth Retry? |
|-------------|----------|---------------------|
| `login_required` | LOGIN_REQUIRED from InnerTube | Yes |
| `private_or_inaccessible` | Private playlist | Yes |
| `age_restricted` | Age-gated content | Yes |
| `unavailable` / `unplayable` | Deleted/removed | No |
| `rate_limited` | Too many requests | No |

## 8. Dependency Injection Changes

### QueueManager

```
audioControllerProvider
  └── QueueManager(
        sourceManager: ...,
        bilibiliAccountService: ref.read(bilibiliAccountServiceProvider),  // NEW
        youtubeAccountService: ref.read(youtubeAccountServiceProvider),    // NEW
      )
```

### ImportService

```
importServiceProvider
  └── ImportService(
        sourceManager: ...,
        bilibiliAccountService: ref.read(bilibiliAccountServiceProvider),  // NEW
        youtubeAccountService: ref.read(youtubeAccountServiceProvider),    // NEW
      )
```

### DownloadService

```
downloadServiceProvider
  └── DownloadService(
        sourceManager: ...,
        bilibiliAccountService: ref.read(bilibiliAccountServiceProvider),  // NEW
        youtubeAccountService: ref.read(youtubeAccountServiceProvider),    // NEW
      )
```

## 9. Implementation Order

| Step | Files | Description |
|------|-------|-------------|
| 1 | `source_exception.dart`, `bilibili_source.dart`, `youtube_source.dart` | Add `isPermissionDenied` getter, update `_mapCode` |
| 2 | `auth_retry_utils.dart` (new) | Create `withAuthRetry` and `withAuthRetryDirect` utilities |
| 3 | `bilibili_source.dart` | Add `authHeaders` param to all public methods, implement `_withAuth()` |
| 4 | `youtube_source.dart` | Add `authHeaders` param, implement InnerTube fallback methods |
| 5 | `queue_manager.dart` | Inject account services, wrap `ensureAudioUrl()` |
| 6 | `import_service.dart` | Inject account services, wrap `parsePlaylist()` / `getVideoPages()` |
| 7 | `download_service.dart` | Inject account services, wrap `getAudioStream()` / `getVideoDetail()` |
| 8 | `track_detail_provider.dart` | Wrap `getVideoDetail()` |
| 9 | `search_page.dart` | Wrap `getVideoPages()` |
| 10 | Provider wiring | Update provider definitions to pass account services |

## 10. Testing Strategy

1. **Unit test `withAuthRetry`**: Mock source that throws permission error, verify retry with auth headers
2. **Test with real private content**:
   - Bilibili: `https://space.bilibili.com/352754246/favlist?fid=3981100746&ftype=create`
   - YouTube: `https://www.youtube.com/playlist?list=PLtTz-WrL9mKDXViXJsLYYWK0-KajdyPqb`
   - Bilibili private video: `BV1Qkw1zMECR`
   - YouTube private video: `_mpaMi0m3mc`
3. **Test anonymous fallback**: Ensure public content still works without auth
4. **Test not-logged-in path**: Permission error propagates correctly when no account
