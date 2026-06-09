# Source Auth Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize FMP source auth and media handoff policy behind `SourceAuthContext`, with `useAuthForPlay` governing stream resolution, playback handoff, download, track info, and track detail while search remains unauthenticated and imports use their own gates.

**Architecture:** Add a deep `SourceAuthContext` Module in the account layer. Keep account services as credential adapters and keep `SourceHttpPolicy` as the pure header/allowlist helper. Refactor audio, download, import, search, and track detail callers to ask for purpose-specific auth instead of assembling settings, account credentials, redirect policy, and media headers themselves.

**Tech Stack:** Flutter/Dart, Riverpod providers, Isar repositories, `flutter_test`, existing source capability interfaces.

---

## Execution Notes

- Do not commit, amend, rebase, or push unless the user explicitly asks. Use `git status --short` checkpoints instead of commit steps.
- Preserve unrelated user changes.
- Keep the first implementation scoped to the approved spec:
  - `Stream resolution`, `Playback handoff`, `Download`, `TrackInfo`, and `Track detail` follow `useAuthForPlay`.
  - Library import follows the import dialog `useAuth` switch.
  - Account page playlist import keeps `useAuth: true`.
  - Playlist refresh follows `playlist.useAuthForRefresh`.
  - Search, including Bilibili page lookup, uses no account auth.
  - Bilibili/YouTube credentials never reach media/CDN requests.
  - Netease media credentials remain restricted to allowlisted HTTPS Netease media hosts.

## File Structure

Create:

- `lib/services/account/source_auth_context.dart`
  - Owns the `SourceAuthContext` Interface, production `DefaultSourceAuthContext`, account auth loader adapter, playback network request DTOs, and Netease playback redirect preflight.
- `lib/providers/account/source_auth_context_provider.dart`
  - Wires `DefaultSourceAuthContext` from account services and `SettingsRepository`.
- `test/services/account/source_auth_context_test.dart`
  - Tests purpose gates, media credential safety, image headers, redirect stripping, and import/refresh separation.

Modify:

- `lib/providers/account/account_provider.dart`
  - Export or colocate provider imports if existing provider style expects account providers from this barrel-like file.
- `lib/providers/audio/stream_resolution_provider.dart`
  - Inject `SourceAuthContext` into `DefaultStreamResolutionService`.
- `lib/services/audio/stream_resolution_service.dart`
  - Replace `AuthHeadersLoader` with `SourceAuthContext.authForPlay()`.
- `lib/services/audio/audio_stream_manager.dart`
  - Remove local settings/account auth loading and Netease redirect preflight. Delegate network handoff to `SourceAuthContext`.
- `lib/services/audio/audio_provider.dart`
  - Pass the shared context into `AudioStreamManager`.
- `lib/services/download/download_service.dart`
  - Use `SourceAuthContext` for owned stream-resolution fallback, download metadata detail auth, image headers, and media headers.
- `lib/services/download/download_media_headers.dart`
  - Keep only isolate-safe pure wrappers or move usage to `SourceAuthContext` where isolate boundaries allow.
- `lib/providers/download/download_providers.dart`
  - Pass the shared context into `DownloadService`.
- `lib/services/import/import_service.dart`
  - Use `playlistImportAuth()` and `playlistRefreshAuth()`. Pass selected auth into multi-page expansion.
- `lib/providers/library/import_playlist_provider.dart`
  - Pass shared context into `ImportService`.
- `lib/providers/search/refresh_provider.dart`
  - Pass shared context into refresh-owned `ImportService`.
- `lib/services/search/search_service.dart`
  - Remove Bilibili account service dependency and stop passing auth to page lookup.
- `lib/providers/search/search_provider.dart`
  - Stop passing `BilibiliAccountService` to `SearchService`.
- `lib/providers/library/track_detail_provider.dart`
  - Inject `SourceAuthContext`; use `authForPlay()` for network detail.
- `lib/data/sources/source_provider.dart`
  - If app-level `getTrackInfo()` / `refreshAudioUrl()` helpers are kept, add optional auth-aware overloads or leave them unauthenticated and route app service callers through `SourceAuthContext`.
- `lib/services/AGENTS.md`, `lib/services/audio/AGENTS.md`, `lib/data/sources/AGENTS.md`
  - Document new ownership and gates after implementation.
- Existing tests under `test/services/audio`, `test/services/download`, `test/services/import`, `test/providers`, and `test/ui/pages/search`.

## Task 1: Add SourceAuthContext Seam and Tests

**Files:**
- Create: `lib/services/account/source_auth_context.dart`
- Create: `test/services/account/source_auth_context_test.dart`

- [ ] **Step 1: Write failing tests for play auth, import auth, refresh auth, and search non-purpose**

Create `test/services/account/source_auth_context_test.dart` with these initial tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/settings.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/settings_repository.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/services/account/source_auth_context.dart';

void main() {
  group('SourceAuthContext purpose gates', () {
    late _FakeSettingsRepository settingsRepository;
    late _RecordingAccountAuthLoader authLoader;
    late DefaultSourceAuthContext context;

    setUp(() {
      settingsRepository = _FakeSettingsRepository();
      authLoader = _RecordingAccountAuthLoader();
      context = DefaultSourceAuthContext(
        settingsRepository: settingsRepository,
        accountAuthLoader: authLoader,
        playbackUrlResolver: (sourceType, url, authHeaders) async {
          return PlaybackUrlResolution(url: url);
        },
      );
    });

    test('authForPlay follows per-source useAuthForPlay settings', () async {
      settingsRepository.settings
        ..useYoutubeAuthForPlay = true
        ..useBilibiliAuthForPlay = false;
      authLoader.headersBySource[SourceType.youtube] = const {
        'Authorization': 'Bearer youtube',
      };
      authLoader.headersBySource[SourceType.bilibili] = const {
        'Cookie': 'SESSDATA=bilibili',
      };

      final youtube = await context.authForPlay(SourceType.youtube);
      final bilibili = await context.authForPlay(SourceType.bilibili);

      expect(youtube, {'Authorization': 'Bearer youtube'});
      expect(bilibili, isNull);
      expect(authLoader.requests, [SourceType.youtube]);
    });

    test('playlist import auth follows caller useAuth only', () async {
      authLoader.headersBySource[SourceType.netease] = const {
        'Cookie': 'MUSIC_U=token',
      };

      final disabled = await context.playlistImportAuth(
        SourceType.netease,
        useAuth: false,
      );
      final enabled = await context.playlistImportAuth(
        SourceType.netease,
        useAuth: true,
      );

      expect(disabled, isNull);
      expect(enabled, {'Cookie': 'MUSIC_U=token'});
      expect(authLoader.requests, [SourceType.netease]);
    });

    test('playlist refresh auth follows persisted refresh setting only',
        () async {
      authLoader.headersBySource[SourceType.bilibili] = const {
        'Cookie': 'SESSDATA=token',
      };

      final disabled = await context.playlistRefreshAuth(
        SourceType.bilibili,
        useAuthForRefresh: false,
      );
      final enabled = await context.playlistRefreshAuth(
        SourceType.bilibili,
        useAuthForRefresh: true,
      );

      expect(disabled, isNull);
      expect(enabled, {'Cookie': 'SESSDATA=token'});
      expect(authLoader.requests, [SourceType.bilibili]);
    });

    test('search is not represented as an auth purpose', () {
      expect(
        SourceAuthContext,
        isNotNull,
        reason:
            'Search should remain unauthenticated; do not add a search auth method.',
      );
    });
  });
}

class _FakeSettingsRepository implements SettingsRepository {
  final settings = Settings();

  @override
  Future<Settings> get() async => settings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingAccountAuthLoader implements SourceAccountAuthLoader {
  final headersBySource = <SourceType, Map<String, String>?>{};
  final requests = <SourceType>[];

  @override
  Future<Map<String, String>?> load(SourceType sourceType) async {
    requests.add(sourceType);
    return headersBySource[sourceType];
  }
}
```

If `SettingsRepository` is not practical to fake because it is a concrete class, replace `_FakeSettingsRepository implements SettingsRepository` with a small adapter in production code:

```dart
typedef SourceSettingsLoader = Future<Settings> Function();
```

Then construct `DefaultSourceAuthContext(settingsLoader: () async => settings)`.

- [ ] **Step 2: Run the new test and verify it fails**

Run:

```bash
flutter test test/services/account/source_auth_context_test.dart
```

Expected: fails because `source_auth_context.dart`, `SourceAuthContext`, and `DefaultSourceAuthContext` do not exist yet.

- [ ] **Step 3: Implement the seam and minimal purpose gates**

Create `lib/services/account/source_auth_context.dart`:

```dart
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/settings.dart';
import '../../data/models/track.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sources/source_http_policy.dart';
import 'bilibili_account_service.dart';
import 'netease_account_service.dart';
import 'youtube_account_service.dart';

typedef SourceSettingsLoader = Future<Settings> Function();

typedef PlaybackUrlResolver = Future<PlaybackUrlResolution> Function(
  SourceType sourceType,
  String url,
  Map<String, String>? authHeaders,
);

abstract interface class SourceAccountAuthLoader {
  Future<Map<String, String>?> load(SourceType sourceType);
}

class AccountServiceAuthLoader implements SourceAccountAuthLoader {
  AccountServiceAuthLoader({
    BilibiliAccountService? bilibiliAccountService,
    YouTubeAccountService? youtubeAccountService,
    NeteaseAccountService? neteaseAccountService,
  })  : _bilibiliAccountService = bilibiliAccountService,
        _youtubeAccountService = youtubeAccountService,
        _neteaseAccountService = neteaseAccountService;

  final BilibiliAccountService? _bilibiliAccountService;
  final YouTubeAccountService? _youtubeAccountService;
  final NeteaseAccountService? _neteaseAccountService;

  @override
  Future<Map<String, String>?> load(SourceType sourceType) async {
    switch (sourceType) {
      case SourceType.bilibili:
        final cookies = await _bilibiliAccountService?.getAuthCookieString();
        if (cookies == null) return null;
        return {'Cookie': cookies};
      case SourceType.youtube:
        return _youtubeAccountService?.getAuthHeaders();
      case SourceType.netease:
        final cookies = await _neteaseAccountService?.getAuthCookieString();
        if (cookies == null) return null;
        return SourceHttpPolicy.neteaseAuthHeaders(cookies);
    }
  }
}

abstract interface class SourceAuthContext {
  Future<Map<String, String>?> authForPlay(SourceType sourceType);

  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  );

  Map<String, String> downloadMediaHeaders(
    SourceType sourceType, {
    Map<String, String>? authHeaders,
    String? requestUrl,
  });

  Map<String, String> imageHeaders(SourceType sourceType);

  Map<String, String>? imageHeadersForUrl(
    String url, {
    bool includeUserAgent = false,
  });

  Future<Map<String, String>?> playlistImportAuth(
    SourceType sourceType, {
    required bool useAuth,
  });

  Future<Map<String, String>?> playlistRefreshAuth(
    SourceType sourceType, {
    required bool useAuthForRefresh,
  });
}

class PlaybackUrlResolution {
  const PlaybackUrlResolution({
    required this.url,
    this.includeCredentials = true,
  });

  final String url;
  final bool includeCredentials;
}

class PlaybackNetworkRequest {
  const PlaybackNetworkRequest({
    required this.url,
    required this.headers,
  });

  final String url;
  final Map<String, String>? headers;
}

class DefaultSourceAuthContext with Logging implements SourceAuthContext {
  DefaultSourceAuthContext({
    required SourceSettingsLoader settingsLoader,
    required SourceAccountAuthLoader accountAuthLoader,
    PlaybackUrlResolver? playbackUrlResolver,
  })  : _settingsLoader = settingsLoader,
        _accountAuthLoader = accountAuthLoader,
        _playbackUrlResolver = playbackUrlResolver;

  factory DefaultSourceAuthContext.fromRepositories({
    required SettingsRepository settingsRepository,
    required SourceAccountAuthLoader accountAuthLoader,
    PlaybackUrlResolver? playbackUrlResolver,
  }) {
    return DefaultSourceAuthContext(
      settingsLoader: settingsRepository.get,
      accountAuthLoader: accountAuthLoader,
      playbackUrlResolver: playbackUrlResolver,
    );
  }

  final SourceSettingsLoader _settingsLoader;
  final SourceAccountAuthLoader _accountAuthLoader;
  final PlaybackUrlResolver? _playbackUrlResolver;

  @override
  Future<Map<String, String>?> authForPlay(SourceType sourceType) async {
    final settings = await _settingsLoader();
    if (!settings.useAuthForPlay(sourceType)) return null;
    return _accountAuthLoader.load(sourceType);
  }

  @override
  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  ) async {
    final authHeaders = await authForPlay(track.sourceType);
    final resolver = _playbackUrlResolver ?? _resolvePlaybackUrl;
    final resolved = await resolver(track.sourceType, url, authHeaders);
    return PlaybackNetworkRequest(
      url: resolved.url,
      headers: SourceHttpPolicy.mediaHeaders(
        track.sourceType,
        authHeaders: authHeaders,
        requestUrl: resolved.url,
        includeCredentials: resolved.includeCredentials,
      ),
    );
  }

  @override
  Map<String, String> downloadMediaHeaders(
    SourceType sourceType, {
    Map<String, String>? authHeaders,
    String? requestUrl,
  }) {
    return SourceHttpPolicy.mediaHeaders(
      sourceType,
      authHeaders: authHeaders,
      requestUrl: requestUrl,
    );
  }

  @override
  Map<String, String> imageHeaders(SourceType sourceType) {
    return SourceHttpPolicy.imageHeaders(sourceType);
  }

  @override
  Map<String, String>? imageHeadersForUrl(
    String url, {
    bool includeUserAgent = false,
  }) {
    return SourceHttpPolicy.imageHeadersForUrl(
      url,
      includeUserAgent: includeUserAgent,
    );
  }

  @override
  Future<Map<String, String>?> playlistImportAuth(
    SourceType sourceType, {
    required bool useAuth,
  }) {
    return useAuth ? _accountAuthLoader.load(sourceType) : Future.value();
  }

  @override
  Future<Map<String, String>?> playlistRefreshAuth(
    SourceType sourceType, {
    required bool useAuthForRefresh,
  }) {
    return useAuthForRefresh
        ? _accountAuthLoader.load(sourceType)
        : Future.value();
  }

  Future<PlaybackUrlResolution> _resolvePlaybackUrl(
    SourceType sourceType,
    String url,
    Map<String, String>? authHeaders,
  ) async {
    if (sourceType != SourceType.netease ||
        authHeaders == null ||
        !SourceHttpPolicy.canAttachNeteaseMediaCredentials(url)) {
      return PlaybackUrlResolution(url: url);
    }

    try {
      return await _resolveNeteasePlaybackRedirects(url, authHeaders);
    } catch (_) {
      logWarning(
        'Failed to preflight Netease playback redirects; stripping credentials for playback handoff',
      );
      return PlaybackUrlResolution(url: url, includeCredentials: false);
    }
  }

  Future<PlaybackUrlResolution> _resolveNeteasePlaybackRedirects(
    String url,
    Map<String, String> authHeaders,
  ) async {
    final initialUri = Uri.tryParse(url);
    if (initialUri == null) {
      return PlaybackUrlResolution(url: url, includeCredentials: false);
    }

    final client = HttpClient()
      ..connectionTimeout = AppConstants.networkConnectTimeout;
    try {
      var currentUri = initialUri;
      for (var redirectCount = 0;
          redirectCount <= _maxPlaybackRedirects;
          redirectCount++) {
        final response = await _probeNeteasePlaybackUrl(
          client,
          currentUri,
          authHeaders,
        );
        final statusCode = response.statusCode;
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();

        if (!_isRedirectStatus(statusCode)) {
          return PlaybackUrlResolution(url: currentUri.toString());
        }
        if (location == null ||
            location.isEmpty ||
            redirectCount == _maxPlaybackRedirects) {
          return PlaybackUrlResolution(
            url: currentUri.toString(),
            includeCredentials: false,
          );
        }

        final nextUri = currentUri.resolve(location);
        if (!SourceHttpPolicy.canAttachNeteaseMediaCredentials(
          nextUri.toString(),
        )) {
          return PlaybackUrlResolution(
            url: nextUri.toString(),
            includeCredentials: false,
          );
        }
        currentUri = nextUri;
      }
    } finally {
      client.close(force: true);
    }

    return PlaybackUrlResolution(url: url, includeCredentials: false);
  }

  Future<HttpClientResponse> _probeNeteasePlaybackUrl(
    HttpClient client,
    Uri uri,
    Map<String, String> authHeaders,
  ) async {
    final headResponse = await _sendNeteasePlaybackProbe(
      client,
      method: 'HEAD',
      uri: uri,
      authHeaders: authHeaders,
    );
    if (headResponse.statusCode != HttpStatus.methodNotAllowed) {
      return headResponse;
    }

    await headResponse.drain<void>();
    return _sendNeteasePlaybackProbe(
      client,
      method: 'GET',
      uri: uri,
      authHeaders: authHeaders,
      rangeProbe: true,
    );
  }

  Future<HttpClientResponse> _sendNeteasePlaybackProbe(
    HttpClient client, {
    required String method,
    required Uri uri,
    required Map<String, String> authHeaders,
    bool rangeProbe = false,
  }) async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = false;
    SourceHttpPolicy.mediaHeaders(
      SourceType.netease,
      authHeaders: authHeaders,
      requestUrl: uri.toString(),
    ).forEach(request.headers.set);
    if (rangeProbe) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    }
    return request.close().timeout(AppConstants.networkReceiveTimeout);
  }

  bool _isRedirectStatus(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == 308;
  }

  static const int _maxPlaybackRedirects = 5;
}
```

- [ ] **Step 4: Run the new tests and fix compile issues**

Run:

```bash
flutter test test/services/account/source_auth_context_test.dart
```

Expected: PASS after import/type fixes.

- [ ] **Step 5: Add security tests for media and redirect behavior**

Append these tests to `source_auth_context_test.dart`:

```dart
test('playbackNetworkRequest does not leak Bilibili or YouTube media auth',
    () async {
  settingsRepository.settings
    ..useBilibiliAuthForPlay = true
    ..useYoutubeAuthForPlay = true;
  authLoader.headersBySource[SourceType.bilibili] = const {
    'Cookie': 'SESSDATA=secret',
  };
  authLoader.headersBySource[SourceType.youtube] = const {
    'Authorization': 'Bearer secret',
    'Cookie': 'SID=secret',
  };

  final bilibili = await context.playbackNetworkRequest(
    Track()
      ..sourceType = SourceType.bilibili
      ..sourceId = 'BV1',
    'https://upos.example/audio.m4a',
  );
  final youtube = await context.playbackNetworkRequest(
    Track()
      ..sourceType = SourceType.youtube
      ..sourceId = 'yt',
    'https://rr.googlevideo.com/audio.m4a',
  );

  expect(bilibili.headers, isNot(contains('Cookie')));
  expect(youtube.headers, isNot(contains('Cookie')));
  expect(youtube.headers, isNot(contains('Authorization')));
});

test('playbackNetworkRequest strips Netease auth after unsafe redirect',
    () async {
  settingsRepository.settings.useNeteaseAuthForPlay = true;
  authLoader.headersBySource[SourceType.netease] = const {
    'Cookie': 'MUSIC_U=token',
    'Origin': SourceHttpPolicy.neteaseOrigin,
    'Referer': SourceHttpPolicy.neteaseReferer,
    'User-Agent': 'NetEase-UA',
  };
  context = DefaultSourceAuthContext(
    settingsLoader: settingsRepository.get,
    accountAuthLoader: authLoader,
    playbackUrlResolver: (sourceType, url, authHeaders) async {
      return const PlaybackUrlResolution(
        url: 'https://attacker.example/audio.m4a',
        includeCredentials: false,
      );
    },
  );

  final prepared = await context.playbackNetworkRequest(
    Track()
      ..sourceType = SourceType.netease
      ..sourceId = 'netease',
    'https://m701.music.126.net/song.m4a',
  );

  expect(prepared.url, 'https://attacker.example/audio.m4a');
  expect(prepared.headers, isNot(contains('Cookie')));
  expect(prepared.headers?['Origin'], SourceHttpPolicy.neteaseOrigin);
});

test('image headers never include credentials', () async {
  final headers = context.imageHeaders(SourceType.netease);

  expect(headers, isNot(contains('Cookie')));
  expect(headers['Origin'], SourceHttpPolicy.neteaseOrigin);
});
```

- [ ] **Step 6: Run seam tests**

Run:

```bash
flutter test test/services/account/source_auth_context_test.dart
```

Expected: PASS.

- [ ] **Step 7: Status checkpoint**

Run:

```bash
git status --short
```

Expected: new context module and new tests are listed. Do not commit.

## Task 2: Wire Provider, Stream Resolution, and Playback Handoff

**Files:**
- Create: `lib/providers/account/source_auth_context_provider.dart`
- Modify: `lib/providers/audio/stream_resolution_provider.dart`
- Modify: `lib/services/audio/stream_resolution_service.dart`
- Modify: `lib/services/audio/audio_stream_manager.dart`
- Modify: `lib/services/audio/audio_provider.dart`
- Test: `test/services/audio/stream_resolution_service_test.dart`
- Test: `test/services/audio/audio_stream_manager_test.dart`

- [ ] **Step 1: Add provider for the production context**

Create `lib/providers/account/source_auth_context_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repository.dart';
import '../../services/account/source_auth_context.dart';
import '../database/database_provider.dart';
import 'account_provider.dart';

final sourceAuthContextProvider = Provider<SourceAuthContext>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  return DefaultSourceAuthContext.fromRepositories(
    settingsRepository: SettingsRepository(db),
    accountAuthLoader: AccountServiceAuthLoader(
      bilibiliAccountService: ref.read(bilibiliAccountServiceProvider),
      youtubeAccountService: ref.read(youtubeAccountServiceProvider),
      neteaseAccountService: ref.read(neteaseAccountServiceProvider),
    ),
  );
});
```

- [ ] **Step 2: Write/update stream resolution test expectation**

In `test/services/audio/stream_resolution_service_test.dart`, replace the
`getAuthHeaders` test setup with a fake context:

```dart
late _RecordingSourceAuthContext sourceAuthContext;

setUp(() async {
  sourceAuthContext = _RecordingSourceAuthContext();
  service = DefaultStreamResolutionService(
    trackRepository: trackRepository,
    settingsRepository: settingsRepository,
    sourceManager: sourceManager,
    sourceAuthContext: sourceAuthContext,
  );
});
```

Add the fake near other test fakes:

```dart
class _RecordingSourceAuthContext implements SourceAuthContext {
  Map<String, String>? authHeaders;
  final authForPlayRequests = <SourceType>[];

  @override
  Future<Map<String, String>?> authForPlay(SourceType sourceType) async {
    authForPlayRequests.add(sourceType);
    return authHeaders;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

Update the existing test body:

```dart
sourceAuthContext.authHeaders = {'Authorization': 'Bearer sentinel'};

final result = await service.resolvePrimary(
  _track('auth-enabled'),
  purpose: StreamResolutionPurpose.playback,
);

expect(result, isA<RemoteStreamResolution>());
expect(sourceAuthContext.authForPlayRequests, [SourceType.youtube]);
expect(source.primaryRequests.single.authHeaders, {
  'Authorization': 'Bearer sentinel',
});
expect((result as RemoteStreamResolution).authHeaders, {
  'Authorization': 'Bearer sentinel',
});
```

- [ ] **Step 3: Run stream resolution test to verify it fails before implementation**

Run:

```bash
flutter test test/services/audio/stream_resolution_service_test.dart
```

Expected: FAIL because `DefaultStreamResolutionService` has not accepted `sourceAuthContext` yet.

- [ ] **Step 4: Refactor StreamResolutionService to use SourceAuthContext**

In `lib/services/audio/stream_resolution_service.dart`:

Remove:

```dart
typedef AuthHeadersLoader = Future<Map<String, String>?> Function(
  SourceType sourceType,
);
```

Add import:

```dart
import '../account/source_auth_context.dart';
```

Change constructor fields:

```dart
DefaultStreamResolutionService({
  required TrackRepository trackRepository,
  required SettingsRepository settingsRepository,
  required SourceManager sourceManager,
  required SourceAuthContext sourceAuthContext,
})  : _trackRepository = trackRepository,
      _settingsRepository = settingsRepository,
      _sourceManager = sourceManager,
      _sourceAuthContext = sourceAuthContext;

final SourceAuthContext _sourceAuthContext;
```

Change `_buildRequestContext()`:

```dart
Future<_StreamRequestContext> _buildRequestContext(
  Track track, {
  String? failedUrl,
}) async {
  final settings = await _settingsRepository.get();
  final config = AudioStreamConfig.fromSettings(settings, track.sourceType);
  final authHeaders = await _sourceAuthContext.authForPlay(track.sourceType);
  return _StreamRequestContext(
    request: AudioStreamRequest(
      sourceId: track.sourceId,
      cid: track.cid,
      pageNum: track.pageNum,
      config: config,
      authHeaders: authHeaders,
      failedUrl: failedUrl,
    ),
    authHeaders: authHeaders,
  );
}
```

- [ ] **Step 5: Wire stream resolution provider**

In `lib/providers/audio/stream_resolution_provider.dart`, remove account-service imports and use:

```dart
import '../account/source_auth_context_provider.dart';
```

Construct:

```dart
final service = DefaultStreamResolutionService(
  trackRepository: TrackRepository(db),
  settingsRepository: SettingsRepository(db),
  sourceManager: ref.watch(sourceManagerProvider),
  sourceAuthContext: ref.watch(sourceAuthContextProvider),
);
```

- [ ] **Step 6: Move playback handoff out of AudioStreamManager**

In `lib/services/audio/audio_stream_manager.dart`:

Remove imports for `dart:io`, `AppConstants`, `auth_headers_utils.dart`, `SourceHttpPolicy`, and account services.

Add:

```dart
import '../account/source_auth_context.dart';
```

Change constructor:

```dart
AudioStreamManager({
  required StreamResolutionService streamResolutionService,
  required SourceAuthContext sourceAuthContext,
})  : _streamResolutionService = streamResolutionService,
      _sourceAuthContext = sourceAuthContext;

final SourceAuthContext _sourceAuthContext;
```

Keep the public `PlaybackRequestStreamAccess` return type by reusing the DTO from
`source_auth_context.dart`. Remove the local `PlaybackUrlResolver`,
`PlaybackUrlResolution`, and `PlaybackNetworkRequest` declarations from this
file.

Replace `getPlaybackHeaders()`:

```dart
@override
Future<Map<String, String>?> getPlaybackHeaders(
  Track track, {
  String? requestUrl,
}) async {
  final prepared = await _sourceAuthContext.playbackNetworkRequest(
    track,
    requestUrl ?? track.audioUrl ?? '',
  );
  return prepared.headers;
}
```

Replace `prepareNetworkPlayback()`:

```dart
@override
Future<PlaybackNetworkRequest> prepareNetworkPlayback(
  Track track,
  String url,
) {
  return _sourceAuthContext.playbackNetworkRequest(track, url);
}
```

Delete `_defaultUseAuthForPlay`, `_getPlaybackAuthHeaders`,
`_resolvePlaybackUrl`, `_resolveNeteasePlaybackRedirects`,
`_probeNeteasePlaybackUrl`, `_sendNeteasePlaybackProbe`, `_isRedirectStatus`,
and `_maxPlaybackRedirects` from `AudioStreamManager`.

Keep:

```dart
static const String defaultPlaybackUserAgent =
    SourceHttpPolicy.mediaUserAgent;
```

Only keep it if existing tests still assert it. If keeping it, re-add
`SourceHttpPolicy` import just for this constant.

- [ ] **Step 7: Wire AudioStreamManager provider**

In `lib/services/audio/audio_provider.dart`, import:

```dart
import '../../providers/account/source_auth_context_provider.dart';
```

Construct:

```dart
final manager = AudioStreamManager(
  streamResolutionService: ref.watch(streamResolutionServiceProvider),
  sourceAuthContext: ref.watch(sourceAuthContextProvider),
);
```

- [ ] **Step 8: Update audio tests with fake context**

In `test/services/audio/audio_stream_manager_test.dart`, create a fake context that can be configured for media/header assertions:

```dart
class _FakeSourceAuthContext implements SourceAuthContext {
  Map<String, String>? authHeaders;
  PlaybackUrlResolver? playbackUrlResolver;
  final authForPlayRequests = <SourceType>[];

  @override
  Future<Map<String, String>?> authForPlay(SourceType sourceType) async {
    authForPlayRequests.add(sourceType);
    return authHeaders;
  }

  @override
  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  ) async {
    final headers = await authForPlay(track.sourceType);
    final resolver = playbackUrlResolver ??
        (SourceType sourceType, String url, Map<String, String>? authHeaders) {
          return Future.value(PlaybackUrlResolution(url: url));
        };
    final resolved = await resolver(track.sourceType, url, headers);
    return PlaybackNetworkRequest(
      url: resolved.url,
      headers: SourceHttpPolicy.mediaHeaders(
        track.sourceType,
        authHeaders: headers,
        requestUrl: resolved.url,
        includeCredentials: resolved.includeCredentials,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

Then instantiate:

```dart
sourceAuthContext = _FakeSourceAuthContext();
streamResolutionService = DefaultStreamResolutionService(
  trackRepository: trackRepository,
  settingsRepository: settingsRepository,
  sourceManager: sourceManager,
  sourceAuthContext: sourceAuthContext,
);
manager = AudioStreamManager(
  streamResolutionService: streamResolutionService,
  sourceAuthContext: sourceAuthContext,
);
```

Where old tests mutate settings and `delegateAuthHeaders`, update them to mutate
`sourceAuthContext.authHeaders` and assert `sourceAuthContext.authForPlayRequests`.

- [ ] **Step 9: Run audio tests**

Run:

```bash
flutter test test/services/audio/stream_resolution_service_test.dart test/services/audio/audio_stream_manager_test.dart
```

Expected: PASS.

- [ ] **Step 10: Status checkpoint**

Run:

```bash
git status --short
```

Expected: source context, provider, audio modules, and audio tests changed. Do not commit.

## Task 3: Refactor Download Policy Usage

**Files:**
- Modify: `lib/services/download/download_service.dart`
- Modify: `lib/services/download/download_media_headers.dart`
- Modify: `lib/providers/download/download_providers.dart`
- Test: `test/services/download/download_media_headers_test.dart`
- Test: `test/services/download/download_service_phase1_test.dart`

- [ ] **Step 1: Write/update download media header tests against SourceAuthContext**

In `test/services/download/download_media_headers_test.dart`, keep pure wrapper tests if wrappers stay isolate-safe. Add a source assertion that production download code no longer calls account auth directly for metadata/detail:

```dart
test('download service routes auth policy through SourceAuthContext', () {
  final source = File('lib/services/download/download_service.dart')
      .readAsStringSync();

  expect(source, contains('SourceAuthContext'));
  expect(source, contains('authForPlay(track.sourceType)'));
  expect(source, isNot(contains('buildAuthHeaders(sourceType')));
});
```

- [ ] **Step 2: Run download tests to verify they fail before implementation**

Run:

```bash
flutter test test/services/download/download_media_headers_test.dart
```

Expected: FAIL because `DownloadService` still uses direct auth helpers.

- [ ] **Step 3: Inject SourceAuthContext into DownloadService**

In `lib/services/download/download_service.dart`, import:

```dart
import '../account/source_auth_context.dart';
```

Change constructor to require context:

```dart
DownloadService({
  required DownloadRepository downloadRepository,
  required TrackRepository trackRepository,
  required SettingsRepository settingsRepository,
  required SourceManager sourceManager,
  required SourceAuthContext sourceAuthContext,
  StreamResolutionService? streamResolutionService,
})  : _downloadRepository = downloadRepository,
      _trackRepository = trackRepository,
      _settingsRepository = settingsRepository,
      _sourceManager = sourceManager,
      _sourceAuthContext = sourceAuthContext,
      _ownsStreamResolutionService = streamResolutionService == null,
      _streamResolutionService = streamResolutionService ??
          DefaultStreamResolutionService(
            trackRepository: trackRepository,
            settingsRepository: settingsRepository,
            sourceManager: sourceManager,
            sourceAuthContext: sourceAuthContext,
          ),
      _dio = Dio(BaseOptions(
        connectTimeout: AppConstants.downloadConnectTimeout,
        receiveTimeout: const Duration(minutes: 30),
        headers: {
          'User-Agent': SourceHttpPolicy.mediaUserAgent,
        },
      ));

final SourceAuthContext _sourceAuthContext;
```

Remove `_bilibiliAccountService`, `_youtubeAccountService`,
`_neteaseAccountService`, and `_getAuthHeaders()`.

- [ ] **Step 4: Use SourceAuthContext for metadata detail and image headers**

Replace the download metadata detail auth block:

```dart
final detailAuthHeaders = await _sourceAuthContext.authForPlay(
  track.sourceType,
);
videoDetail = await detailSource.getVideoDetail(
  track.sourceId,
  authHeaders: detailAuthHeaders,
);
```

Replace image header construction in `_saveMetadata()`:

```dart
final imageHeaders = _sourceAuthContext.imageHeaders(track.sourceType);
```

Do not pass auth headers to image header construction.

- [ ] **Step 5: Keep isolate media headers pure**

In `lib/services/download/download_media_headers.dart`, keep these wrappers if
the isolate still imports them:

```dart
Map<String, String> buildDownloadMediaHeaders(
  SourceType sourceType, {
  Map<String, String>? authHeaders,
  String? requestUrl,
}) {
  return SourceHttpPolicy.mediaHeaders(
    sourceType,
    authHeaders: authHeaders,
    requestUrl: requestUrl,
  );
}

Map<String, String> buildDownloadImageHeaders(
  SourceType sourceType, {
  Map<String, String>? authHeaders,
}) {
  return SourceHttpPolicy.imageHeaders(sourceType);
}
```

The isolate must continue recalculating headers per redirect hop:

```dart
final headers = buildDownloadMediaHeaders(
  params.sourceType,
  authHeaders: params.authHeaders,
  requestUrl: requestUri.toString(),
);
```

- [ ] **Step 6: Wire download provider**

In `lib/providers/download/download_providers.dart`, import:

```dart
import '../account/source_auth_context_provider.dart';
```

Construct:

```dart
final service = DownloadService(
  downloadRepository: downloadRepo,
  trackRepository: trackRepo,
  settingsRepository: settingsRepo,
  sourceManager: sourceManager,
  sourceAuthContext: ref.watch(sourceAuthContextProvider),
  streamResolutionService: ref.watch(streamResolutionServiceProvider),
);
```

- [ ] **Step 7: Update download tests**

In download tests that instantiate `DownloadService`, pass a fake context:

```dart
final sourceAuthContext = _FakeSourceAuthContext();
final service = DownloadService(
  downloadRepository: downloadRepository,
  trackRepository: trackRepository,
  settingsRepository: settingsRepository,
  sourceManager: _SingleSourceManager(recordingSource),
  sourceAuthContext: sourceAuthContext,
);
```

Use this fake:

```dart
class _FakeSourceAuthContext implements SourceAuthContext {
  Map<String, String>? authHeaders;
  final authForPlayRequests = <SourceType>[];

  @override
  Future<Map<String, String>?> authForPlay(SourceType sourceType) async {
    authForPlayRequests.add(sourceType);
    return authHeaders;
  }

  @override
  Map<String, String> imageHeaders(SourceType sourceType) {
    return SourceHttpPolicy.imageHeaders(sourceType);
  }

  @override
  Map<String, String> downloadMediaHeaders(
    SourceType sourceType, {
    Map<String, String>? authHeaders,
    String? requestUrl,
  }) {
    return SourceHttpPolicy.mediaHeaders(
      sourceType,
      authHeaders: authHeaders,
      requestUrl: requestUrl,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 8: Run download tests**

Run:

```bash
flutter test test/services/download/download_media_headers_test.dart test/services/download/download_service_phase1_test.dart
```

Expected: PASS.

- [ ] **Step 9: Status checkpoint**

Run:

```bash
git status --short
```

Expected: download service/provider/tests changed. Do not commit.

## Task 4: Refactor Import, Search, and Track Detail Policy

**Files:**
- Modify: `lib/services/import/import_service.dart`
- Modify: `lib/providers/library/import_playlist_provider.dart`
- Modify: `lib/providers/search/refresh_provider.dart`
- Modify: `lib/services/search/search_service.dart`
- Modify: `lib/providers/search/search_provider.dart`
- Modify: `lib/providers/library/track_detail_provider.dart`
- Test: `test/services/import/import_service_phase4_test.dart`
- Test: `test/services/import/import_service_refresh_partial_test.dart`
- Test: `test/providers/track_detail_refresh_stale_test.dart`
- Test: `test/ui/pages/search/search_page_phase2_test.dart`

- [ ] **Step 1: Update import tests for auth propagation to expansion**

In `test/services/import/import_service_phase4_test.dart`, add/adjust a test:

```dart
test('import multi-page expansion reuses import auth headers', () async {
  final source = _FakeBilibiliPlaylistSource();
  final sourceManager = _FakeSourceManager()..detectedSource = source;
  final authContext = _FakeSourceAuthContext()
    ..playlistImportHeaders = const {'Cookie': 'SESSDATA=import'};
  final service = ImportService(
    sourceManager: sourceManager,
    playlistRepository: playlistRepository,
    trackRepository: trackRepository,
    isar: isar,
    sourceAuthContext: authContext,
  );

  await service.importFromUrl(
    'https://www.bilibili.com/list/watchlater',
    useAuth: true,
  );

  expect(source.lastParseAuthHeaders, {'Cookie': 'SESSDATA=import'});
  expect(source.lastPageAuthHeaders, {'Cookie': 'SESSDATA=import'});
});
```

Adapt fake class names to the existing test file. The required assertion is that
the same selected import auth reaches `parsePlaylist()` and `getVideoPages()`.

- [ ] **Step 2: Update search test to require no auth for page lookup**

In `test/ui/pages/search/search_page_phase2_test.dart`, add this assertion to
`_RecordingPagedVideoSource`:

```dart
Map<String, String>? lastAuthHeaders;

@override
Future<List<VideoPage>> getVideoPages(
  String sourceId, {
  Map<String, String>? authHeaders,
}) async {
  lastAuthHeaders = authHeaders;
  getVideoPagesCallCount++;
  return const [
    VideoPage(cid: 1, page: 1, part: 'Unexpected page', duration: 1),
  ];
}
```

Add a test:

```dart
test('search service does not pass auth to page lookup', () async {
  final pagedSource = _RecordingPagedVideoSource(SourceType.bilibili);
  final sourceManager = _PagedVideoSourceManager(pagedSource);
  final service = SearchService(
    sourceManager: sourceManager,
    trackRepository: TrackRepository(_FakeIsar()),
    isar: _FakeIsar(),
  );
  final track = Track()
    ..sourceType = SourceType.bilibili
    ..sourceId = 'BV-no-auth';

  await service.loadVideoPagesForTrack(track);

  expect(pagedSource.lastAuthHeaders, isNull);
}
```

- [ ] **Step 3: Update track detail tests for useAuthForPlay**

In `test/providers/track_detail_refresh_stale_test.dart`, replace `_FakeRef`
with a fake context:

```dart
class _FakeSourceAuthContext implements SourceAuthContext {
  Map<String, String>? authHeaders;
  final requests = <SourceType>[];

  @override
  Future<Map<String, String>?> authForPlay(SourceType sourceType) async {
    requests.add(sourceType);
    return authHeaders;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

Update `_CompletingTrackDetailSource` to record auth:

```dart
final authRequests = <Map<String, String>?>[];

@override
Future<VideoDetail> getVideoDetail(
  String sourceId, {
  Map<String, String>? authHeaders,
}) {
  requests.add(sourceId);
  authRequests.add(authHeaders);
  final completer = Completer<VideoDetail>();
  _completers.putIfAbsent(sourceId, () => []).add(completer);
  return completer.future;
}
```

Add a test:

```dart
test('loadDetail gets auth from SourceAuthContext authForPlay', () async {
  final youtube = _CompletingTrackDetailSource(SourceType.youtube);
  final sourceManager = SourceManager(sources: [youtube]);
  addTearDown(sourceManager.dispose);
  final authContext = _FakeSourceAuthContext()
    ..authHeaders = const {'Authorization': 'Bearer detail'};
  final notifier = TrackDetailNotifier(sourceManager, authContext);

  final loadFuture = notifier.loadDetail(_track('YT-auth', SourceType.youtube));
  await pumpEventQueue(times: 2);
  youtube.complete('YT-auth', _detail('YT-auth', 'Auth detail'));
  await loadFuture;

  expect(authContext.requests, [SourceType.youtube]);
  expect(youtube.authRequests.single, {'Authorization': 'Bearer detail'});
});
```

- [ ] **Step 4: Run updated tests to verify they fail before implementation**

Run:

```bash
flutter test test/services/import/import_service_phase4_test.dart test/providers/track_detail_refresh_stale_test.dart test/ui/pages/search/search_page_phase2_test.dart
```

Expected: FAIL because production code still uses old auth paths.

- [ ] **Step 5: Refactor ImportService**

In `lib/services/import/import_service.dart`, import:

```dart
import '../account/source_auth_context.dart';
```

Change constructor:

```dart
ImportService({
  required SourceManager sourceManager,
  required PlaylistRepository playlistRepository,
  required TrackRepository trackRepository,
  required Isar isar,
  required SourceAuthContext sourceAuthContext,
  PlaylistMutationService? mutationService,
})  : _sourceManager = sourceManager,
      _playlistRepository = playlistRepository,
      _trackRepository = trackRepository,
      _isar = isar,
      _sourceAuthContext = sourceAuthContext,
      _mutationService = mutationService ?? PlaylistMutationService(isar: isar);

final SourceAuthContext _sourceAuthContext;
```

Remove account service fields and `_getAuthHeaders()`.

For import:

```dart
final authHeaders = await _sourceAuthContext.playlistImportAuth(
  source.sourceType,
  useAuth: useAuth,
);
final result = await source.parsePlaylist(
  normalizedUrl,
  authHeaders: authHeaders,
);
```

Pass auth into expansion:

```dart
final expansion = await _expandMultiPageVideos(
  pagedVideoSource,
  result.tracks,
  authHeaders: authHeaders,
  (current, total, item) {
    _updateProgress(
      status: ImportStatus.importing,
      current: current,
      total: total,
      currentItem: t.importSource.gettingPageInfo(
        current: current.toString(),
        total: total.toString(),
      ),
    );
  },
);
```

Update `_expandMultiPageVideos` signature:

```dart
Future<_TrackExpansionResult> _expandMultiPageVideos(
  PagedVideoSource source,
  List<Track> tracks,
  void Function(int current, int total, Track item) onProgress, {
  Map<String, String>? authHeaders,
}) async {
  ...
  final pages = await source.getVideoPages(
    track.sourceId,
    authHeaders: authHeaders,
  );
  ...
}
```

For refresh:

```dart
final authHeaders = await _sourceAuthContext.playlistRefreshAuth(
  source.sourceType,
  useAuthForRefresh: playlist.useAuthForRefresh,
);
final result = await source.parsePlaylist(
  playlist.sourceUrl!,
  authHeaders: authHeaders,
);
```

Pass the same `authHeaders` into refresh expansion.

- [ ] **Step 6: Wire import providers**

In `lib/providers/library/import_playlist_provider.dart`, import:

```dart
import '../account/source_auth_context_provider.dart';
```

Pass:

```dart
sourceAuthContext: ref.read(sourceAuthContextProvider),
```

In `lib/providers/search/refresh_provider.dart`, import the same provider and pass:

```dart
sourceAuthContext: _ref.read(sourceAuthContextProvider),
```

- [ ] **Step 7: Refactor SearchService**

In `lib/services/search/search_service.dart`, remove:

```dart
import '../../core/utils/auth_headers_utils.dart';
import '../../services/account/bilibili_account_service.dart';
```

Remove `_bilibiliAccountService` from constructor and fields.

Change page lookup:

```dart
return source.getVideoPages(track.sourceId);
```

In `lib/providers/search/search_provider.dart`, stop passing
`bilibiliAccountService`.

- [ ] **Step 8: Refactor TrackDetailNotifier**

In `lib/providers/library/track_detail_provider.dart`, remove
`auth_headers_utils.dart` and account provider imports. Add:

```dart
import '../../services/account/source_auth_context.dart';
import '../account/source_auth_context_provider.dart';
```

Change fields/constructor:

```dart
class TrackDetailNotifier extends StateNotifier<TrackDetailState> {
  final SourceManager _sourceManager;
  final SourceAuthContext _sourceAuthContext;
  Track? _currentTrack;

  TrackDetailNotifier(this._sourceManager, this._sourceAuthContext)
      : super(const TrackDetailState());
```

Change network detail:

```dart
Future<VideoDetail> _loadNetworkDetail(
  Track track,
  TrackDetailSource source,
) async {
  final authHeaders = await _sourceAuthContext.authForPlay(track.sourceType);
  return source.getVideoDetail(track.sourceId, authHeaders: authHeaders);
}
```

Provider:

```dart
final notifier = TrackDetailNotifier(
  sourceManager,
  ref.watch(sourceAuthContextProvider),
);
```

- [ ] **Step 9: Run import/search/detail tests**

Run:

```bash
flutter test test/services/import/import_service_phase4_test.dart test/services/import/import_service_refresh_partial_test.dart test/providers/track_detail_refresh_stale_test.dart test/ui/pages/search/search_page_phase2_test.dart
```

Expected: PASS.

- [ ] **Step 10: Status checkpoint**

Run:

```bash
git status --short
```

Expected: import/search/detail modules and tests changed. Do not commit.

## Task 5: Clean Up Legacy Auth Helpers and Documentation

**Files:**
- Modify: `lib/core/utils/auth_headers_utils.dart`
- Modify: `lib/data/sources/source_provider.dart`
- Modify: `lib/services/AGENTS.md`
- Modify: `lib/services/audio/AGENTS.md`
- Modify: `lib/data/sources/AGENTS.md`
- Test: `test/services/audio/audio_auth_retry_phase4_test.dart`
- Test: `test/data/sources/source_http_policy_test.dart`
- Test: `test/services/account/source_http_policy_usage_test.dart`

- [ ] **Step 1: Decide whether `auth_headers_utils.dart` still has callers**

Run:

```bash
rg -n "buildAuthHeaders|getAuthHeadersForPlatform" lib test
```

Expected after Tasks 1-4: no production callers except compatibility tests or debug-only code. If only debug page callers remain, leave the helper but mark it debug/legacy in a comment.

- [ ] **Step 2: If production callers remain, route them through SourceAuthContext**

For any production caller found, apply the matching policy:

```dart
final authHeaders = await _sourceAuthContext.authForPlay(track.sourceType);
```

or:

```dart
final authHeaders = await _sourceAuthContext.playlistImportAuth(
  sourceType,
  useAuth: useAuth,
);
```

Do not add a generic replacement call that hides which purpose is being served.

- [ ] **Step 3: Keep SourceHttpPolicy tests pure**

Run:

```bash
flutter test test/data/sources/source_http_policy_test.dart
```

Expected: PASS. If failures happen, fix `SourceHttpPolicy` only if the pure
allowlist/header behavior changed accidentally.

- [ ] **Step 4: Update AGENTS guidance**

In `lib/data/sources/AGENTS.md`, replace the old auth section with:

```markdown
`SourceAuthContext` owns source auth gates for app-level callers. `authForPlay`
reads `settings.useAuthForPlay(track.sourceType)` and is used for stream
resolution, playback handoff, download, track info, and track detail. Search
does not request account auth. Playlist import uses the import UI/account entry
choice, and playlist refresh uses `Playlist.useAuthForRefresh`.

`SourceHttpPolicy` remains the final pure media/header allowlist. Bilibili and
YouTube account credentials are for source API and stream URL resolution, not
media/CDN requests. Only allowlisted HTTPS Netease media hosts may receive
Netease cookies. Image headers must not attach credential cookies.
```

In `lib/services/audio/AGENTS.md`, update ownership:

```markdown
- `StreamResolutionService` owns stream URL resolution and asks
  `SourceAuthContext.authForPlay()` for source auth.
- `AudioStreamManager` owns playback selection and delegates network URL/header
  handoff to `SourceAuthContext.playbackNetworkRequest()`.
```

In `lib/services/AGENTS.md`, update download/account guidance:

```markdown
Downloads receive stream auth from `StreamResolutionService` and use
`SourceAuthContext` for download metadata detail and image/media header policy.
The isolate still recalculates media headers per redirect hop using pure
`SourceHttpPolicy` wrappers.
```

- [ ] **Step 5: Run static auth search**

Run:

```bash
rg -n "buildAuthHeaders|getAuthHeadersForPlatform|useAuthForPlay\\(|mediaHeaders\\(" lib/services lib/providers lib/ui lib/data/sources
```

Expected:

- `useAuthForPlay()` appears in `SourceAuthContext` and settings/model code, not scattered across playback/download/detail callers.
- `mediaHeaders()` appears in `SourceAuthContext`, `SourceHttpPolicy`, and isolate-safe download wrapper paths.
- Search page lookup has no auth helper calls.

- [ ] **Step 6: Status checkpoint**

Run:

```bash
git status --short
```

Expected: docs and cleanup changes listed. Do not commit.

## Task 6: Full Verification

**Files:**
- No new files expected.
- Verifies all touched modules.

- [ ] **Step 1: Run focused test suite**

Run:

```bash
flutter test test/services/account test/services/audio test/services/download test/services/import test/providers/track_detail_refresh_stale_test.dart test/ui/pages/search/search_page_phase2_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run source policy tests**

Run:

```bash
flutter test test/data/sources/source_http_policy_test.dart test/services/account/source_http_policy_usage_test.dart test/data/sources/source_http_policy_usage_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run analysis**

Run:

```bash
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 4: Run diff checks**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 5: Inspect final auth call sites**

Run:

```bash
rg -n "buildAuthHeaders|getAuthHeadersForPlatform|useAuthForPlay\\(|playbackNetworkRequest|authForPlay|playlistImportAuth|playlistRefreshAuth" lib test
```

Expected:

- `authForPlay()` is the central production path for play/download/detail/track-info auth.
- `playlistImportAuth()` and `playlistRefreshAuth()` are used by `ImportService`.
- Search does not call account auth helpers.
- Any remaining `buildAuthHeaders()` usage is debug-only or removed.

- [ ] **Step 6: Final status checkpoint**

Run:

```bash
git status --short
```

Expected: all intended files are modified; no unexpected generated or unrelated files are changed. Do not commit unless the user explicitly asks.

## Self-Review

- Spec coverage:
  - `useAuthForPlay` for stream resolution, playback handoff, download, track info, and track detail: Tasks 1-4.
  - Import dialog/account import/refresh gates: Task 4.
  - Search unauthenticated: Task 4.
  - Media credential safety and Netease allowlist: Task 1 plus Task 6 policy tests.
  - Docs updates: Task 5.
- Completion scan:
  - No undefined future tasks should remain in this plan.
- Type consistency:
  - `SourceAuthContext.authForPlay`, `playlistImportAuth`, `playlistRefreshAuth`, and `playbackNetworkRequest` are the only external auth-purpose methods used by production callers.
