# Media Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move playback/download media byte-request URL and header policy into a deep, isolate-safe Media Handoff module, while strengthening download redirect credential stripping.

**Architecture:** `SourceAuthContext` remains the source auth gate module. A new `DefaultMediaHandoff` module prepares playback and download media requests from a source type, URL, and Stream Resolution Auth. Playback reaches it through the existing `SourceAuthContext.playbackNetworkRequest()` seam; the download isolate calls its pure hop-preparation method directly.

**Tech Stack:** Flutter/Dart, Riverpod, Isar, `flutter_test`, existing `SourceHttpPolicy`, existing source `SourceType` model.

---

## Repository Rules

- Do not commit, amend, rebase, or push unless explicitly requested.
- Use TDD: each production behavior starts with a failing test.
- Preserve unrelated working-tree changes.
- Keep Bilibili/YouTube credentials out of media/CDN headers.
- Keep Netease media credentials restricted to the existing HTTPS Netease allowlist.
- Keep download isolate progress, pause/cancel, path, and persistence behavior unchanged.

## File Structure

- Create `lib/services/media/media_handoff.dart`
  - Owns `MediaHandoffRequest`, `MediaHandoffResult`,
    `MediaPlaybackRedirectResolution`, `DefaultMediaHandoff`, and the
    `MediaHandoff` interface.
  - Uses `SourceHttpPolicy` for final media headers and Netease allowlist checks.
  - Owns playback Netease redirect preflight.
  - Owns download hop header preparation and `Range` header construction.
- Create `test/services/media/media_handoff_test.dart`
  - Tests the Media Handoff seam directly.
- Modify `lib/services/account/source_auth_context.dart`
  - Keep the public `SourceAuthContext` interface.
  - Delegate `playbackNetworkRequest()` to `MediaHandoff`.
  - Preserve legacy test constructor hooks by adapting them into Media Handoff.
- Modify `test/services/account/source_auth_context_test.dart`
  - Add a test proving `playbackNetworkRequest()` delegates to Media Handoff with Stream Resolution Auth.
- Modify `lib/services/download/download_service.dart`
  - Replace `buildDownloadMediaHeaders()` and manual range header construction with `DefaultMediaHandoff.prepareDownloadHop()`.
- Delete `lib/services/download/download_media_headers.dart`
  - Remove the shallow pass-through module once no production caller remains.
- Modify `test/services/download/download_media_headers_test.dart`
  - Remove pass-through helper tests.
  - Keep static download service tests for image headers, Dio defaults, receive timeout, and Media Handoff usage.
- Modify `lib/services/AGENTS.md`, `lib/services/audio/AGENTS.md`,
  `lib/data/sources/AGENTS.md`, and `CONTEXT.md`
  - Update ownership guidance after code changes.

## Task 1: Add Media Handoff Tests

**Files:**
- Create: `test/services/media/media_handoff_test.dart`
- Production not yet changed.

- [ ] **Step 1: Write the failing Media Handoff test file**

Create `test/services/media/media_handoff_test.dart` with this content:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/services/media/media_handoff.dart';

void main() {
  group('DefaultMediaHandoff.prepareDownloadHop', () {
    test('bilibili media headers do not leak auth cookies', () {
      final handoff = DefaultMediaHandoff();

      final result = handoff.prepareDownloadHop(_request(
        SourceType.bilibili,
        'https://upos-sz-mirrorcos.bilivideo.com/audio.m4a',
        streamResolutionAuth: const {'Cookie': 'SESSDATA=secret'},
      ));

      expect(result.url.toString(),
          'https://upos-sz-mirrorcos.bilivideo.com/audio.m4a');
      expect(result.credentialsIncluded, isFalse);
      expect(result.headers['Referer'], SourceHttpPolicy.bilibiliWebReferer);
      expect(result.headers['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(result.headers.containsKey('Cookie'), isFalse);
    });

    test('youtube media headers do not leak authorization headers', () {
      final handoff = DefaultMediaHandoff();

      final result = handoff.prepareDownloadHop(_request(
        SourceType.youtube,
        'https://rr1---sn.googlevideo.com/videoplayback',
        streamResolutionAuth: const {
          'Authorization': 'Bearer secret',
          'Cookie': 'SID=secret',
        },
      ));

      expect(result.credentialsIncluded, isFalse);
      expect(result.headers['Origin'], SourceHttpPolicy.youtubeOrigin);
      expect(result.headers['Referer'], SourceHttpPolicy.youtubeReferer);
      expect(result.headers['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(result.headers.containsKey('Authorization'), isFalse);
      expect(result.headers.containsKey('Cookie'), isFalse);
    });

    test('netease credentials attach only to allowlisted HTTPS media hosts',
        () {
      final handoff = DefaultMediaHandoff();
      final authHeaders =
          SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token');

      final safe = handoff.prepareDownloadHop(_request(
        SourceType.netease,
        'https://m701.music.126.net/song.m4a',
        streamResolutionAuth: authHeaders,
      ));
      final unsafe = handoff.prepareDownloadHop(_request(
        SourceType.netease,
        'https://cdn.example.com/song.m4a',
        streamResolutionAuth: authHeaders,
      ));
      final insecure = handoff.prepareDownloadHop(_request(
        SourceType.netease,
        'http://m701.music.126.net/song.m4a',
        streamResolutionAuth: authHeaders,
      ));

      expect(safe.credentialsIncluded, isTrue);
      expect(safe.headers['Cookie'], 'MUSIC_U=token');
      expect(safe.headers['User-Agent'], SourceHttpPolicy.neteaseDesktopUserAgent);

      expect(unsafe.credentialsIncluded, isFalse);
      expect(unsafe.headers.containsKey('Cookie'), isFalse);

      expect(insecure.credentialsIncluded, isFalse);
      expect(insecure.headers.containsKey('Cookie'), isFalse);
    });

    test('rangeStart adds a Range header for resumed downloads', () {
      final handoff = DefaultMediaHandoff();

      final result = handoff.prepareDownloadHop(_request(
        SourceType.youtube,
        'https://rr1---sn.googlevideo.com/videoplayback',
        rangeStart: 4096,
      ));

      expect(result.headers[HttpHeaders.rangeHeader], 'bytes=4096-');
    });
  });

  group('DefaultMediaHandoff.preparePlayback', () {
    test('safe Netease redirect keeps credentials', () async {
      final authHeaders =
          SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token');
      final handoff = DefaultMediaHandoff(
        neteasePlaybackRedirectResolver: (url, authHeaders) async {
          expect(url.toString(), 'https://m701.music.126.net/song.m4a');
          expect(authHeaders['Cookie'], 'MUSIC_U=token');
          return MediaPlaybackRedirectResolution(
            url: Uri.parse('https://m802.music.126.net/song.m4a'),
          );
        },
      );

      final result = await handoff.preparePlayback(_request(
        SourceType.netease,
        'https://m701.music.126.net/song.m4a',
        streamResolutionAuth: authHeaders,
      ));

      expect(result.url.toString(), 'https://m802.music.126.net/song.m4a');
      expect(result.credentialsIncluded, isTrue);
      expect(result.headers['Cookie'], 'MUSIC_U=token');
    });

    test('unsafe Netease redirect strips credentials', () async {
      final authHeaders =
          SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token');
      final handoff = DefaultMediaHandoff(
        neteasePlaybackRedirectResolver: (url, authHeaders) async {
          return MediaPlaybackRedirectResolution(
            url: Uri.parse('https://attacker.example/song.m4a'),
            includeCredentials: false,
          );
        },
      );

      final result = await handoff.preparePlayback(_request(
        SourceType.netease,
        'https://m701.music.126.net/song.m4a',
        streamResolutionAuth: authHeaders,
      ));

      expect(result.url.toString(), 'https://attacker.example/song.m4a');
      expect(result.credentialsIncluded, isFalse);
      expect(result.headers.containsKey('Cookie'), isFalse);
    });

    test('preflight exception strips credentials and keeps the original URL',
        () async {
      final authHeaders =
          SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=token');
      final handoff = DefaultMediaHandoff(
        neteasePlaybackRedirectResolver: (url, authHeaders) async {
          throw const SocketException('preflight failed');
        },
      );

      final result = await handoff.preparePlayback(_request(
        SourceType.netease,
        'https://m701.music.126.net/song.m4a',
        streamResolutionAuth: authHeaders,
      ));

      expect(result.url.toString(), 'https://m701.music.126.net/song.m4a');
      expect(result.credentialsIncluded, isFalse);
      expect(result.headers.containsKey('Cookie'), isFalse);
    });
  });
}

MediaHandoffRequest _request(
  SourceType sourceType,
  String url, {
  Map<String, String>? streamResolutionAuth,
  int? rangeStart,
}) {
  return MediaHandoffRequest(
    sourceType: sourceType,
    url: Uri.parse(url),
    streamResolutionAuth: streamResolutionAuth,
    rangeStart: rangeStart,
  );
}
```

- [ ] **Step 2: Run the new test and verify RED**

Run:

```bash
flutter test test/services/media/media_handoff_test.dart
```

Expected: FAIL because `package:fmp/services/media/media_handoff.dart` does not exist.

## Task 2: Implement Media Handoff

**Files:**
- Create: `lib/services/media/media_handoff.dart`
- Test: `test/services/media/media_handoff_test.dart`

- [ ] **Step 1: Create the Media Handoff module**

Create `lib/services/media/media_handoff.dart` with this content:

```dart
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/sources/source_http_policy.dart';

typedef NeteasePlaybackRedirectResolver
    = Future<MediaPlaybackRedirectResolution> Function(
  Uri url,
  Map<String, String> streamResolutionAuth,
);

class MediaHandoffRequest {
  const MediaHandoffRequest({
    required this.sourceType,
    required this.url,
    this.streamResolutionAuth,
    this.rangeStart,
  });

  final SourceType sourceType;
  final Uri url;
  final Map<String, String>? streamResolutionAuth;
  final int? rangeStart;
}

class MediaHandoffResult {
  const MediaHandoffResult({
    required this.url,
    required this.headers,
    required this.credentialsIncluded,
  });

  final Uri url;
  final Map<String, String> headers;
  final bool credentialsIncluded;
}

class MediaPlaybackRedirectResolution {
  const MediaPlaybackRedirectResolution({
    required this.url,
    this.includeCredentials = true,
  });

  final Uri url;
  final bool includeCredentials;
}

abstract interface class MediaHandoff {
  Future<MediaHandoffResult> preparePlayback(MediaHandoffRequest request);

  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request);
}

class DefaultMediaHandoff with Logging implements MediaHandoff {
  DefaultMediaHandoff({
    NeteasePlaybackRedirectResolver? neteasePlaybackRedirectResolver,
  }) : _neteasePlaybackRedirectResolver = neteasePlaybackRedirectResolver;

  final NeteasePlaybackRedirectResolver? _neteasePlaybackRedirectResolver;

  @override
  Future<MediaHandoffResult> preparePlayback(
    MediaHandoffRequest request,
  ) async {
    if (!_shouldPreflightNeteasePlayback(request)) {
      return _prepareHeaders(request, url: request.url);
    }

    try {
      final resolver =
          _neteasePlaybackRedirectResolver ?? _resolveNeteasePlaybackRedirects;
      final resolution = await resolver(
        request.url,
        request.streamResolutionAuth!,
      );
      return _prepareHeaders(
        request,
        url: resolution.url,
        includeCredentials: resolution.includeCredentials,
      );
    } catch (_) {
      logWarning(
        'Failed to preflight Netease playback redirects; stripping credentials for playback handoff',
      );
      return _prepareHeaders(
        request,
        url: request.url,
        includeCredentials: false,
      );
    }
  }

  @override
  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request) {
    return _prepareHeaders(request, url: request.url);
  }

  bool _shouldPreflightNeteasePlayback(MediaHandoffRequest request) {
    return request.sourceType == SourceType.netease &&
        request.streamResolutionAuth != null &&
        SourceHttpPolicy.canAttachNeteaseMediaCredentials(
          request.url.toString(),
        );
  }

  MediaHandoffResult _prepareHeaders(
    MediaHandoffRequest request, {
    required Uri url,
    bool includeCredentials = true,
  }) {
    final requestUrl = url.toString();
    final credentialsMayAttach = includeCredentials &&
        request.sourceType == SourceType.netease &&
        request.streamResolutionAuth != null &&
        SourceHttpPolicy.canAttachNeteaseMediaCredentials(requestUrl);
    final headers = SourceHttpPolicy.mediaHeaders(
      request.sourceType,
      authHeaders: request.streamResolutionAuth,
      requestUrl: requestUrl,
      includeCredentials: credentialsMayAttach,
    );
    final rangeStart = request.rangeStart;
    if (rangeStart != null && rangeStart > 0) {
      headers[HttpHeaders.rangeHeader] = 'bytes=$rangeStart-';
    }

    return MediaHandoffResult(
      url: url,
      headers: headers,
      credentialsIncluded: credentialsMayAttach &&
          _containsHeader(headers, HttpHeaders.cookieHeader),
    );
  }

  bool _containsHeader(Map<String, String> headers, String name) {
    final normalizedName = name.toLowerCase();
    return headers.keys.any((key) => key.toLowerCase() == normalizedName);
  }

  Future<MediaPlaybackRedirectResolution> _resolveNeteasePlaybackRedirects(
    Uri url,
    Map<String, String> streamResolutionAuth,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = AppConstants.networkConnectTimeout;
    try {
      var currentUri = url;
      for (var redirectCount = 0;
          redirectCount <= _maxPlaybackRedirects;
          redirectCount++) {
        final response = await _probeNeteasePlaybackUrl(
          client,
          currentUri,
          streamResolutionAuth,
        );
        final statusCode = response.statusCode;
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();

        if (!_isRedirectStatus(statusCode)) {
          return MediaPlaybackRedirectResolution(url: currentUri);
        }
        if (location == null || location.isEmpty) {
          return MediaPlaybackRedirectResolution(
            url: currentUri,
            includeCredentials: false,
          );
        }
        if (redirectCount == _maxPlaybackRedirects) {
          return MediaPlaybackRedirectResolution(
            url: currentUri,
            includeCredentials: false,
          );
        }

        final nextUri = currentUri.resolve(location);
        if (!SourceHttpPolicy.canAttachNeteaseMediaCredentials(
          nextUri.toString(),
        )) {
          return MediaPlaybackRedirectResolution(
            url: nextUri,
            includeCredentials: false,
          );
        }
        currentUri = nextUri;
      }
    } finally {
      client.close(force: true);
    }

    return MediaPlaybackRedirectResolution(
      url: url,
      includeCredentials: false,
    );
  }

  Future<HttpClientResponse> _probeNeteasePlaybackUrl(
    HttpClient client,
    Uri uri,
    Map<String, String> streamResolutionAuth,
  ) async {
    final headResponse = await _sendNeteasePlaybackProbe(
      client,
      method: 'HEAD',
      uri: uri,
      streamResolutionAuth: streamResolutionAuth,
    );
    if (headResponse.statusCode != HttpStatus.methodNotAllowed) {
      return headResponse;
    }

    await headResponse.drain<void>();
    return _sendNeteasePlaybackProbe(
      client,
      method: 'GET',
      uri: uri,
      streamResolutionAuth: streamResolutionAuth,
      rangeProbe: true,
    );
  }

  Future<HttpClientResponse> _sendNeteasePlaybackProbe(
    HttpClient client, {
    required String method,
    required Uri uri,
    required Map<String, String> streamResolutionAuth,
    bool rangeProbe = false,
  }) async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = false;
    SourceHttpPolicy.mediaHeaders(
      SourceType.netease,
      authHeaders: streamResolutionAuth,
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

- [ ] **Step 2: Run Media Handoff tests and verify GREEN**

Run:

```bash
flutter test test/services/media/media_handoff_test.dart
```

Expected: PASS.

## Task 3: Route SourceAuthContext Through Media Handoff

**Files:**
- Modify: `test/services/account/source_auth_context_test.dart`
- Modify: `lib/services/account/source_auth_context.dart`
- Test: `test/services/account/source_auth_context_test.dart`

- [ ] **Step 1: Add a failing delegation test**

In `test/services/account/source_auth_context_test.dart`, add this import:

```dart
import 'package:fmp/services/media/media_handoff.dart';
```

Inside the existing `group('SourceAuthContext', () {` block, add this test
before the image header test:

```dart
    test('playbackNetworkRequest delegates media request to MediaHandoff',
        () async {
      settings.useNeteaseAuthForPlay = true;
      final authHeaders =
          SourceHttpPolicy.neteaseAuthHeaders('MUSIC_U=delegate');
      authLoader.headersBySource[SourceType.netease] = authHeaders;
      final mediaHandoff = _RecordingMediaHandoff(
        result: MediaHandoffResult(
          url: Uri.parse('https://m801.music.126.net/delegated.m4a'),
          headers: const {'User-Agent': 'delegated-media'},
          credentialsIncluded: true,
        ),
      );
      final context = DefaultSourceAuthContext(
        settingsLoader: () async => settings,
        accountAuthLoader: authLoader,
        mediaHandoff: mediaHandoff,
      );

      final request = await context.playbackNetworkRequest(
        _track(SourceType.netease),
        'https://m701.music.126.net/original.m4a',
      );

      expect(request.url, 'https://m801.music.126.net/delegated.m4a');
      expect(request.headers, {'User-Agent': 'delegated-media'});
      expect(mediaHandoff.requests, hasLength(1));
      expect(mediaHandoff.requests.single.sourceType, SourceType.netease);
      expect(
        mediaHandoff.requests.single.url.toString(),
        'https://m701.music.126.net/original.m4a',
      );
      expect(mediaHandoff.requests.single.streamResolutionAuth, authHeaders);
    });
```

At the bottom of the file, add this fake:

```dart
class _RecordingMediaHandoff implements MediaHandoff {
  _RecordingMediaHandoff({required this.result});

  final MediaHandoffResult result;
  final requests = <MediaHandoffRequest>[];

  @override
  Future<MediaHandoffResult> preparePlayback(
    MediaHandoffRequest request,
  ) async {
    requests.add(request);
    return result;
  }

  @override
  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request) {
    throw UnimplementedError('download hops are not used by this test');
  }
}
```

- [ ] **Step 2: Run SourceAuthContext tests and verify RED**

Run:

```bash
flutter test test/services/account/source_auth_context_test.dart
```

Expected: FAIL because `DefaultSourceAuthContext` does not accept `mediaHandoff`.

- [ ] **Step 3: Modify SourceAuthContext imports and fields**

In `lib/services/account/source_auth_context.dart`, keep `dart:io` for the
compatibility adapter. Remove `../../core/constants/app_constants.dart` and
`../../core/logger.dart` because playback redirect preflight moves to
`DefaultMediaHandoff`.

Add:

```dart
import '../media/media_handoff.dart' hide NeteasePlaybackRedirectResolver;
```

Change `DefaultSourceAuthContext` to include a Media Handoff field and
constructor parameter:

```dart
class DefaultSourceAuthContext implements SourceAuthContext {
  DefaultSourceAuthContext({
    required SourceSettingsLoader settingsLoader,
    required SourceAccountAuthLoader accountAuthLoader,
    MediaHandoff? mediaHandoff,
    PlaybackUrlResolver? playbackUrlResolver,
    NeteasePlaybackRedirectResolver? neteasePlaybackRedirectResolver,
  })  : _settingsLoader = settingsLoader,
        _accountAuthLoader = accountAuthLoader,
        _mediaHandoff = mediaHandoff ??
            _createMediaHandoff(
              playbackUrlResolver: playbackUrlResolver,
              neteasePlaybackRedirectResolver: neteasePlaybackRedirectResolver,
            );

  factory DefaultSourceAuthContext.fromRepositories({
    required SettingsRepository settingsRepository,
    required SourceAccountAuthLoader accountAuthLoader,
    MediaHandoff? mediaHandoff,
    PlaybackUrlResolver? playbackUrlResolver,
    NeteasePlaybackRedirectResolver? neteasePlaybackRedirectResolver,
  }) {
    return DefaultSourceAuthContext(
      settingsLoader: settingsRepository.get,
      accountAuthLoader: accountAuthLoader,
      mediaHandoff: mediaHandoff,
      playbackUrlResolver: playbackUrlResolver,
      neteasePlaybackRedirectResolver: neteasePlaybackRedirectResolver,
    );
  }

  final SourceSettingsLoader _settingsLoader;
  final SourceAccountAuthLoader _accountAuthLoader;
  final MediaHandoff _mediaHandoff;
```

Keep `PlaybackUrlResolver`, `NeteasePlaybackRedirectResolver`, and
`PlaybackUrlResolution` in this file for compatibility with existing tests and
the `audio_stream_manager.dart` export.

- [ ] **Step 4: Replace playbackNetworkRequest implementation**

Replace `playbackNetworkRequest()` with:

```dart
  @override
  Future<PlaybackNetworkRequest> playbackNetworkRequest(
    Track track,
    String url,
  ) async {
    final authHeaders = await authForPlay(track.sourceType);
    final prepared = await _mediaHandoff.preparePlayback(
      MediaHandoffRequest(
        sourceType: track.sourceType,
        url: Uri.parse(url),
        streamResolutionAuth: authHeaders,
      ),
    );
    return PlaybackNetworkRequest(
      url: prepared.url.toString(),
      headers: prepared.headers,
    );
  }
```

Below the class, add the compatibility adapter:

```dart
MediaHandoff _createMediaHandoff({
  PlaybackUrlResolver? playbackUrlResolver,
  NeteasePlaybackRedirectResolver? neteasePlaybackRedirectResolver,
}) {
  if (playbackUrlResolver != null) {
    return _PlaybackUrlResolverMediaHandoff(playbackUrlResolver);
  }
  return DefaultMediaHandoff(
    neteasePlaybackRedirectResolver: neteasePlaybackRedirectResolver == null
        ? null
        : (url, streamResolutionAuth) async {
            final resolution = await neteasePlaybackRedirectResolver(
              url.toString(),
              streamResolutionAuth,
            );
            return MediaPlaybackRedirectResolution(
              url: Uri.parse(resolution.url),
              includeCredentials: resolution.includeCredentials,
            );
          },
  );
}

class _PlaybackUrlResolverMediaHandoff implements MediaHandoff {
  _PlaybackUrlResolverMediaHandoff(this._resolver);

  final PlaybackUrlResolver _resolver;

  @override
  Future<MediaHandoffResult> preparePlayback(
    MediaHandoffRequest request,
  ) async {
    final resolution = await _resolver(
      request.sourceType,
      request.url.toString(),
      request.streamResolutionAuth,
    );
    final resolvedUrl = Uri.parse(resolution.url);
    final headers = SourceHttpPolicy.mediaHeaders(
      request.sourceType,
      authHeaders: request.streamResolutionAuth,
      requestUrl: resolvedUrl.toString(),
      includeCredentials: resolution.includeCredentials,
    );
    return MediaHandoffResult(
      url: resolvedUrl,
      headers: headers,
      credentialsIncluded: headers.keys.any(
        (key) => key.toLowerCase() == HttpHeaders.cookieHeader,
      ),
    );
  }

  @override
  MediaHandoffResult prepareDownloadHop(MediaHandoffRequest request) {
    throw UnsupportedError(
      'PlaybackUrlResolver compatibility adapter supports playback only',
    );
  }
}
```

This adapter uses `HttpHeaders.cookieHeader`, so keep `dart:io` imported if it
is needed for the adapter.

- [ ] **Step 5: Remove old redirect implementation from SourceAuthContext**

Delete these members from `DefaultSourceAuthContext` after the new adapter is
in place:

```dart
  final PlaybackUrlResolver? _playbackUrlResolver;
  final NeteasePlaybackRedirectResolver? _neteasePlaybackRedirectResolver;
  Future<PlaybackUrlResolution> _resolvePlaybackUrl(
    SourceType sourceType,
    String url,
    Map<String, String>? authHeaders,
  )
  Future<PlaybackUrlResolution> _resolveNeteasePlaybackRedirects(
    String url,
    Map<String, String> authHeaders,
  )
  Future<HttpClientResponse> _probeNeteasePlaybackUrl(
    HttpClient client,
    Uri uri,
    Map<String, String> authHeaders,
  )
  Future<HttpClientResponse> _sendNeteasePlaybackProbe(
    HttpClient client, {
    required String method,
    required Uri uri,
    required Map<String, String> authHeaders,
    bool rangeProbe = false,
  })
  bool _isRedirectStatus(int statusCode)
  static const int _maxPlaybackRedirects = 5;
```

Keep:

```dart
  static const String defaultPlaybackUserAgent =
      SourceHttpPolicy.mediaUserAgent;
```

- [ ] **Step 6: Run account and media tests and verify GREEN**

Run:

```bash
flutter test test/services/media/media_handoff_test.dart test/services/account/source_auth_context_test.dart
```

Expected: PASS.

## Task 4: Use Media Handoff in Download Isolate

**Files:**
- Modify: `test/services/download/download_media_headers_test.dart`
- Modify: `lib/services/download/download_service.dart`
- Delete: `lib/services/download/download_media_headers.dart`
- Test: `test/services/download/download_media_headers_test.dart`

- [ ] **Step 1: Update download static tests to expect Media Handoff usage**

In `test/services/download/download_media_headers_test.dart`:

1. Remove this import:

```dart
import 'package:fmp/services/download/download_media_headers.dart';
```

2. Delete the whole `group('buildDownloadMediaHeaders', () {` block, including
   its closing `});`.

3. Rename the remaining group from:

```dart
  group('buildDownloadImageHeaders', () {
```

to:

```dart
  group('DownloadService media handoff usage', () {
```

4. Add this test inside that renamed group:

```dart
    test('download isolate delegates hop headers and range to MediaHandoff', () {
      final source = File('lib/services/download/download_service.dart')
          .readAsStringSync();

      expect(source, contains('DefaultMediaHandoff()'));
      expect(source, contains('prepareDownloadHop('));
      expect(source, contains('MediaHandoffRequest('));
      expect(source, contains('rangeStart: params.resumePosition > 0'));
      expect(source, isNot(contains('buildDownloadMediaHeaders(')));
      expect(source, isNot(contains("request.headers.set('Range'")));
      expect(source, isNot(contains('download_media_headers.dart')));
    });
```

- [ ] **Step 2: Run the download static test and verify RED**

Run:

```bash
flutter test test/services/download/download_media_headers_test.dart
```

Expected: FAIL because `DownloadService` still imports and calls
`buildDownloadMediaHeaders()` and sets `Range` directly.

- [ ] **Step 3: Update DownloadService imports**

In `lib/services/download/download_service.dart`, remove:

```dart
import 'download_media_headers.dart';
```

Add:

```dart
import '../media/media_handoff.dart';
```

- [ ] **Step 4: Replace isolate header construction**

In `_isolateDownload(_IsolateDownloadParams params)`, after creating the
`HttpClient`, add:

```dart
    final mediaHandoff = DefaultMediaHandoff();
```

Replace this block:

```dart
      // 添加 headers。每一跳都根据最终请求 URL 重新计算，避免重定向泄漏凭据。
      final headers = buildDownloadMediaHeaders(
        params.sourceType,
        authHeaders: params.authHeaders,
        requestUrl: requestUri.toString(),
      );
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      // 断点续传
      if (params.resumePosition > 0) {
        request.headers.set('Range', 'bytes=${params.resumePosition}-');
      }
```

with:

```dart
      // 添加 headers。每一跳都根据当前请求 URL 重新计算，避免重定向泄漏凭据。
      final handoff = mediaHandoff.prepareDownloadHop(
        MediaHandoffRequest(
          sourceType: params.sourceType,
          url: requestUri,
          streamResolutionAuth: params.authHeaders,
          rangeStart: params.resumePosition > 0 ? params.resumePosition : null,
        ),
      );
      handoff.headers.forEach((key, value) {
        request.headers.set(key, value);
      });
```

- [ ] **Step 5: Delete the shallow download header helper**

Delete:

```text
lib/services/download/download_media_headers.dart
```

- [ ] **Step 6: Run download static tests and verify GREEN**

Run:

```bash
flutter test test/services/download/download_media_headers_test.dart
```

Expected: PASS.

- [ ] **Step 7: Run download service focused tests**

Run:

```bash
flutter test test/services/download/download_service_phase1_test.dart
```

Expected: PASS.

If a test fails because it asserts the exact Range header value, keep the
expected value unchanged. The header should still be observable through
`HttpHeaders.rangeHeader`.

## Task 5: Update Documentation Guidance

**Files:**
- Modify: `lib/services/AGENTS.md`
- Modify: `lib/services/audio/AGENTS.md`
- Modify: `lib/data/sources/AGENTS.md`
- Modify: `CONTEXT.md`

- [ ] **Step 1: Update service-layer download guidance**

In `lib/services/AGENTS.md`, replace the current two bullets:

```markdown
- Download media/image headers should flow through `SourceAuthContext` so
  Bilibili, YouTube, and Netease keep the correct source Referer/Origin/UA/auth
  policy. Media headers are URL-aware; only allowlisted HTTPS Netease media URLs
  may receive `MUSIC_U`, and image downloads must not include Netease cookies.
- `DownloadService` still owns isolate download loops, progress, pause/failure
  state, and final path persistence. The isolate recalculates media headers per
  redirect hop using pure `SourceHttpPolicy` wrappers rather than app-level auth
  services.
```

with:

```markdown
- Download stream auth comes from `StreamResolutionService`; the download
  isolate must convert it to Media Request Credentials through the pure
  `MediaHandoff` module for each redirect hop. Only allowlisted HTTPS Netease
  media URLs may receive `MUSIC_U`; Bilibili and YouTube account credentials
  must never reach media/CDN requests.
- `DownloadService` still owns isolate download loops, progress, pause/failure
  state, and final path persistence. The isolate uses `MediaHandoff` for
  per-hop media headers and resumed-download `Range` headers; it must not use
  Riverpod, account services, or `SourceAuthContext`.
```

- [ ] **Step 2: Update audio handoff guidance**

In `lib/services/audio/AGENTS.md`, update the `AudioStreamManager` bullet from:

```markdown
- `AudioStreamManager` owns playback selection and delegates network URL/header
  handoff to `SourceAuthContext.playbackNetworkRequest()` before handing a URL
  to the backend.
```

to:

```markdown
- `AudioStreamManager` owns playback selection and calls
  `SourceAuthContext.playbackNetworkRequest()` before handing a URL to the
  backend. `SourceAuthContext` owns the Auth For Play gate; the byte-request
  URL/header policy is delegated to `MediaHandoff`.
```

- [ ] **Step 3: Update source policy guidance**

In `lib/data/sources/AGENTS.md`, update the Media Request Credentials paragraph
from:

```markdown
Media playback/download request headers are intentionally narrower than
stream-resolution auth headers. `SourceHttpPolicy.mediaHeaders()` remains the
final pure source-aware media/header allowlist. It currently merges auth headers
only for HTTPS Netease media URLs whose host is explicitly allowlisted
(`music.163.com` / `*.music.163.com` / `music.126.net` /
`*.music.126.net`). Bilibili and YouTube account credentials are source
API/stream URL resolution credentials, not media/CDN headers. Do not forward
them to media/CDN requests unless a future design explicitly changes that
security boundary. Image/header helpers must not attach credential cookies,
including Netease `Cookie`, by default.
```

to:

```markdown
Media playback/download request headers are intentionally narrower than
stream-resolution auth headers. `MediaHandoff` is the byte-request seam for
playback and download; it delegates final source header defaults and Netease
allowlist checks to pure `SourceHttpPolicy.mediaHeaders()`. Only HTTPS Netease
media URLs whose host is explicitly allowlisted (`music.163.com` /
`*.music.163.com` / `music.126.net` / `*.music.126.net`) may receive Netease
cookies. Bilibili and YouTube account credentials are source API/stream URL
resolution credentials, not media/CDN headers. Do not forward them to media/CDN
requests unless a future design explicitly changes that security boundary.
Image/header helpers must not attach credential cookies, including Netease
`Cookie`, by default.
```

- [ ] **Step 4: Sharpen CONTEXT.md Media Handoff definition**

In `CONTEXT.md`, replace the Media Handoff definition with:

```markdown
**Media Handoff**:
The transition from a resolved stream URL to the audio or download backend,
including redirect checks, per-hop media headers, resumed-download range
headers, and Source Auth Context credentials narrowed into Media Request
Credentials.
_Avoid_: playback URL helper, download header helper
```

- [ ] **Step 5: Run documentation diff check**

Run:

```bash
git diff --check -- lib/services/AGENTS.md lib/services/audio/AGENTS.md lib/data/sources/AGENTS.md CONTEXT.md
```

Expected: no whitespace errors.

## Task 6: Focused Verification and Cleanup

**Files:**
- Verifies all touched files.

- [ ] **Step 1: Run focused media/account/download tests**

Run:

```bash
flutter test test/services/media test/services/account/source_auth_context_test.dart test/services/download/download_media_headers_test.dart test/services/download/download_service_phase1_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run source policy tests**

Run:

```bash
flutter test test/data/sources/source_http_policy_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run static analysis**

Run:

```bash
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 4: Inspect final call sites**

Run:

```bash
rg -n "download_media_headers|buildDownloadMediaHeaders|buildDownloadImageHeaders|prepareDownloadHop|preparePlayback|MediaHandoff|SourceHttpPolicy\\.mediaHeaders\\(" lib test
```

Expected:

- No production import of `download_media_headers`.
- No `buildDownloadMediaHeaders` or `buildDownloadImageHeaders` calls.
- `prepareDownloadHop` appears in `lib/services/download/download_service.dart`
  and Media Handoff tests.
- `preparePlayback` appears in `lib/services/media/media_handoff.dart`,
  `lib/services/account/source_auth_context.dart`, and tests.
- Direct `SourceHttpPolicy.mediaHeaders()` production calls are limited to
  `lib/services/media/media_handoff.dart`, `lib/services/account/source_auth_context.dart`
  compatibility adapter, debug-only pages, or source policy internals.

- [ ] **Step 5: Run full diff hygiene check**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 6: Status checkpoint**

Run:

```bash
git status --short
```

Expected: only intended files are changed or deleted:

```text
 M CONTEXT.md
 M lib/data/sources/AGENTS.md
 M lib/services/AGENTS.md
 M lib/services/account/source_auth_context.dart
 M lib/services/audio/AGENTS.md
 M lib/services/download/download_service.dart
 D lib/services/download/download_media_headers.dart
 M test/services/account/source_auth_context_test.dart
 M test/services/download/download_media_headers_test.dart
?? docs/superpowers/specs/2026-06-10-media-handoff-design.md
?? docs/superpowers/plans/2026-06-10-media-handoff.md
?? lib/services/media/media_handoff.dart
?? test/services/media/media_handoff_test.dart
```

Generated or unrelated files should not appear.

## Self-Review

- Spec coverage:
  - Deep Media Handoff module: Tasks 1-2.
  - SourceAuthContext remains public playback seam: Task 3.
  - Download isolate per-hop headers and range headers: Task 4.
  - Download redirect credential stripping: Task 1 tests and Task 4 usage.
  - Documentation updates: Task 5.
  - Verification: Task 6.
- Placeholder scan:
  - The plan contains concrete file paths, code blocks, commands, and expected outcomes.
- Type consistency:
  - `MediaHandoffRequest`, `MediaHandoffResult`, `MediaPlaybackRedirectResolution`,
    `NeteasePlaybackRedirectResolver`, and `DefaultMediaHandoff` are defined in
    Task 2 and used consistently in later tasks.
