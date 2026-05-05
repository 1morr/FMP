# Source Policy and Error Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give playback, download, import, and account flows one small source policy for headers/HTTP clients and one shared semantic source-error kind for retry, skip, login, rate-limit, and unavailable decisions.

**Architecture:** Keep source-specific diagnostics and adapters explicit. Add `SourceErrorKind` to the existing `SourceApiException` hierarchy, then route existing boolean getters and `AudioController` decisions through that kind. Add one lightweight `SourceHttpPolicy` beside the source layer for constants, media headers, auth header shaping, and source API `Dio` construction; migrate only low-risk duplicated call sites and leave highly custom source internals intact.

**Tech Stack:** Flutter, Dart, Dio, Isar-backed account services, existing source exceptions, `AudioStreamManager`, `DownloadService`, and focused Flutter tests.

---

## File Structure

- Modify: `lib/data/sources/source_exception.dart:1-87`
  - Add `SourceErrorKind` and a `kind` getter to `SourceApiException`.
  - Make shared boolean getters derive from `kind` by default.
  - Extend `classifyDioError()` to return `kind`, `code`, and `message` while preserving existing `code` strings.
- Modify: `lib/data/sources/bilibili_exception.dart:1-96`
  - Map Bilibili numeric codes to `SourceErrorKind` and keep `numericCode`, `code`, and `message` diagnostics.
- Modify: `lib/data/sources/youtube_exception.dart:1-73`
  - Map YouTube diagnostic codes to `SourceErrorKind`; preserve existing `isPrivateOrInaccessible` and age-restricted boolean behavior.
- Modify: `lib/data/sources/netease_exception.dart:1-78`
  - Map Netease numeric codes to `SourceErrorKind`; keep legacy diagnostic `code` strings such as `requires_login` and `forbidden`.
- Create: `lib/data/sources/source_http_policy.dart`
  - Centralize source web/media user agents, origins, referers, API headers, media headers, Netease auth-header shaping, and source API `Dio` construction.
- Modify: `lib/core/utils/http_client_factory.dart:12-37`
  - Add an optional `contentType` parameter used by the source policy.
- Modify: `lib/core/utils/auth_headers_utils.dart:1-37`
  - Build Netease auth headers through `SourceHttpPolicy` and fix the import/comment formatting issue.
- Modify: `lib/services/download/download_media_headers.dart:1-25`
  - Keep the public helper, but delegate to `SourceHttpPolicy.mediaHeaders()`.
- Modify: `lib/services/audio/audio_stream_manager.dart:180-227`
  - Use `SourceHttpPolicy.mediaHeaders()` for playback headers and keep `defaultPlaybackUserAgent` as a compatibility alias.
- Modify: `lib/services/audio/audio_provider.dart:1879-1983,2088-2177,2235-2259,2504-2547`
  - Use `SourceErrorKind` for typed source retry/skip/rate-limit/login decisions.
  - Keep string matching only for raw `AudioService` error-stream text and non-source exceptions until those lower layers expose typed errors.
- Modify: `lib/services/account/bilibili_account_service.dart:73-86`
- Modify: `lib/services/account/bilibili_favorites_service.dart:43-57`
- Modify: `lib/services/account/youtube_account_service.dart:38-52`
- Modify: `lib/services/account/youtube_playlist_service.dart:48-64`
- Modify: `lib/services/account/netease_account_service.dart:27-52`
- Modify: `lib/services/account/netease_playlist_service.dart:82-106`
  - Replace repeated raw `Dio(BaseOptions(...))` setup with `SourceHttpPolicy.createApiDio()` while preserving interceptors, anonymous cookies, and the Netease playlist Linux UA.
- Tests:
  - Modify: `test/data/sources/source_exception_test.dart`
  - Create: `test/data/sources/source_http_policy_test.dart`
  - Modify: `test/services/download/download_media_headers_test.dart`
  - Modify: `test/services/audio/audio_stream_manager_test.dart`
  - Modify: `test/services/audio/audio_auth_retry_phase4_test.dart`
  - Create: `test/services/audio/audio_error_kind_structure_test.dart`
  - Create: `test/services/account/source_http_policy_usage_test.dart`

## Scope Guardrails

- Do not migrate `lib/services/update/`, `lib/services/radio/`, or lyrics service `Dio` constructors in this phase; they are not source playback/import/account policy paths.
- Do not hide Bilibili source anti-rate-limit cookies or YouTube InnerTube request details behind a generic adapter; keep those explicit inside their source files.
- Do not rename existing diagnostic `code` strings; tests and UI messages can continue using them.
- Do not remove `AudioStreamManager.defaultPlaybackUserAgent`; make it an alias for the new policy constant so existing callers remain stable.

## Roadmap Coverage

- Shared semantic error kinds: Tasks 1, 2, and 6 add `SourceErrorKind`, expose it from each source exception, and consume it in playback retry/skip/rate-limit decisions.
- Header/media/API policy: Tasks 3, 4, and 5 introduce `SourceHttpPolicy` and migrate playback, download, auth-header, and account-service `Dio` setup.
- Import path coverage: `ImportService` already passes source auth headers into source parsers; Task 3 moves the shared non-Riverpod auth-header builder used by playback/download/import-adjacent code to the new policy without changing import behavior.
- Gradual raw `Dio` replacement: Task 5 migrates account source clients; source internals with encryption, InnerTube, or anti-rate-limit details stay explicit by design.

---

### Task 1: Shared Source Error Kind Contract

**Files:**
- Modify: `lib/data/sources/source_exception.dart:1-87`
- Modify: `test/data/sources/source_exception_test.dart:1-222`

- [ ] **Step 1: Write failing shared-kind and Dio-classification tests**

Add `package:dio/dio.dart` to `test/data/sources/source_exception_test.dart`, then add this group before the final `SourceApiException polymorphism` group:

```dart
group('SourceErrorKind', () {
  test('classifyDioError returns timeout kind and diagnostic code', () {
    final requestOptions = RequestOptions(path: '/timeout');
    final result = SourceApiException.classifyDioError(
      DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionTimeout,
      ),
    );

    expect(result.kind, SourceErrorKind.timeout);
    expect(result.code, 'timeout');
    expect(result.message, isNotEmpty);
  });

  test('classifyDioError returns permission denied for HTTP 403', () {
    final requestOptions = RequestOptions(path: '/forbidden');
    final result = SourceApiException.classifyDioError(
      DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<void>(
          requestOptions: requestOptions,
          statusCode: 403,
        ),
      ),
    );

    expect(result.kind, SourceErrorKind.permissionDenied);
    expect(result.code, 'forbidden');
    expect(result.message, contains('403'));
  });

  test('classifyDioError returns rate limited for HTTP 429', () {
    final requestOptions = RequestOptions(path: '/rate-limited');
    final result = SourceApiException.classifyDioError(
      DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<void>(
          requestOptions: requestOptions,
          statusCode: 429,
        ),
      ),
    );

    expect(result.kind, SourceErrorKind.rateLimited);
    expect(result.code, 'rate_limited');
  });
});
```

- [ ] **Step 2: Run the focused source exception test and verify it fails**

Run: `flutter test test/data/sources/source_exception_test.dart --plain-name SourceErrorKind`

Expected: FAIL because `SourceErrorKind` and `result.kind` do not exist yet.

- [ ] **Step 3: Add `SourceErrorKind` and kind-aware Dio classification**

In `lib/data/sources/source_exception.dart`, insert the enum after the imports and update the base class to this shape:

```dart
enum SourceErrorKind {
  network,
  timeout,
  rateLimited,
  unavailable,
  permissionDenied,
  loginRequired,
  geoRestricted,
  vipRequired,
  unknown;

  bool get isRetryable =>
      this == SourceErrorKind.network || this == SourceErrorKind.timeout;

  bool get shouldSkipTrack =>
      this == SourceErrorKind.unavailable ||
      this == SourceErrorKind.geoRestricted ||
      this == SourceErrorKind.vipRequired;
}

abstract class SourceApiException implements Exception {
  const SourceApiException();

  String get code;
  String get message;
  SourceType get sourceType;
  SourceErrorKind get kind => SourceErrorKind.unknown;

  bool get isUnavailable => kind == SourceErrorKind.unavailable;
  bool get isRateLimited => kind == SourceErrorKind.rateLimited;
  bool get isGeoRestricted => kind == SourceErrorKind.geoRestricted;
  bool get requiresLogin => kind == SourceErrorKind.loginRequired;
  bool get isNetworkError => kind == SourceErrorKind.network;
  bool get isTimeout => kind == SourceErrorKind.timeout;
  bool get isPermissionDenied => kind == SourceErrorKind.permissionDenied;
  bool get isVipRequired => kind == SourceErrorKind.vipRequired;

  static ({SourceErrorKind kind, String code, String message}) classifyDioError(
    DioException e,
  ) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return (
          kind: SourceErrorKind.timeout,
          code: 'timeout',
          message: t.error.connectionTimeout,
        );
      case DioExceptionType.connectionError:
        return (
          kind: SourceErrorKind.network,
          code: 'network_error',
          message: t.error.networkError,
        );
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == null) {
          return (
            kind: SourceErrorKind.unknown,
            code: 'api_error',
            message: t.error.networkError,
          );
        }
        if (statusCode == 429 || statusCode == 412) {
          return (
            kind: SourceErrorKind.rateLimited,
            code: 'rate_limited',
            message: t.error.rateLimited,
          );
        }
        if (statusCode == 403) {
          return (
            kind: SourceErrorKind.permissionDenied,
            code: 'forbidden',
            message: 'Access forbidden (HTTP 403)',
          );
        }
        if (statusCode == 404) {
          return (
            kind: SourceErrorKind.unavailable,
            code: 'not_found',
            message: 'Resource not found (HTTP 404)',
          );
        }
        if (statusCode == 503) {
          return (
            kind: SourceErrorKind.unavailable,
            code: 'service_unavailable',
            message: 'Service temporarily unavailable (HTTP 503)',
          );
        }
        return (
          kind: SourceErrorKind.unknown,
          code: 'api_error',
          message: 'Server error: $statusCode',
        );
      default:
        return (
          kind: SourceErrorKind.network,
          code: 'network_error',
          message: t.error.networkError,
        );
    }
  }
}
```

- [ ] **Step 4: Run the focused source exception test and verify it passes**

Run: `flutter test test/data/sources/source_exception_test.dart --plain-name SourceErrorKind`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/data/sources/source_exception.dart test/data/sources/source_exception_test.dart
git commit -m "feat(source): add shared source error kinds"
```

---

### Task 2: Source-Specific Exception Kind Mapping

**Files:**
- Modify: `lib/data/sources/bilibili_exception.dart:1-96`
- Modify: `lib/data/sources/youtube_exception.dart:1-73`
- Modify: `lib/data/sources/netease_exception.dart:1-78`
- Modify: `test/data/sources/source_exception_test.dart:9-222`

- [ ] **Step 1: Add failing tests for source-specific semantic kinds**

In `test/data/sources/source_exception_test.dart`, add these expectations to existing source-specific groups:

```dart
test('maps Bilibili numeric codes to shared kinds', () {
  expect(
    const BilibiliApiException(numericCode: -412, message: 'Rate').kind,
    SourceErrorKind.rateLimited,
  );
  expect(
    const BilibiliApiException(numericCode: -101, message: 'Login').kind,
    SourceErrorKind.loginRequired,
  );
  expect(
    const BilibiliApiException(numericCode: -10403, message: 'Geo').kind,
    SourceErrorKind.geoRestricted,
  );
  expect(
    const BilibiliApiException(numericCode: 999, message: 'Unknown').kind,
    SourceErrorKind.unknown,
  );
});
```

```dart
test('maps YouTube diagnostic codes to shared kinds', () {
  expect(
    const YouTubeApiException(code: 'rate_limited', message: 'Rate').kind,
    SourceErrorKind.rateLimited,
  );
  expect(
    const YouTubeApiException(code: 'login_required', message: 'Login').kind,
    SourceErrorKind.loginRequired,
  );
  expect(
    const YouTubeApiException(code: 'age_restricted', message: 'Age').kind,
    SourceErrorKind.loginRequired,
  );
  expect(
    const YouTubeApiException(
      code: 'private_or_inaccessible',
      message: 'Private',
    ).kind,
    SourceErrorKind.permissionDenied,
  );
  expect(
    const YouTubeApiException(code: 'test', message: 'Unknown').kind,
    SourceErrorKind.unknown,
  );
});
```

```dart
test('maps Netease numeric codes to shared kinds', () {
  expect(
    const NeteaseApiException(numericCode: -460, message: 'Rate').kind,
    SourceErrorKind.rateLimited,
  );
  expect(
    const NeteaseApiException(numericCode: 301, message: 'Login').kind,
    SourceErrorKind.loginRequired,
  );
  expect(
    const NeteaseApiException(numericCode: -10, message: 'VIP').kind,
    SourceErrorKind.vipRequired,
  );
  expect(
    const NeteaseApiException(numericCode: 0, message: 'Unknown').kind,
    SourceErrorKind.unknown,
  );
});
```

- [ ] **Step 2: Run the source exception test and verify it fails**

Run: `flutter test test/data/sources/source_exception_test.dart`

Expected: FAIL because the new expectations still see `SourceErrorKind.unknown` from the base default for source-specific diagnostic codes.

- [ ] **Step 3: Implement Bilibili kind mapping and derive booleans from kind**

In `lib/data/sources/bilibili_exception.dart`, add the `kind` getter and replace source-specific boolean getters with either the base implementation or `super` calls:

```dart
@override
SourceErrorKind get kind {
  if (numericCode == -1) return SourceErrorKind.timeout;
  if (numericCode == -2 || numericCode == -3) return SourceErrorKind.network;
  if (numericCode == -412 ||
      numericCode == -509 ||
      numericCode == -799 ||
      numericCode == -429) {
    return SourceErrorKind.rateLimited;
  }
  if (numericCode == -404 || numericCode == 62002) {
    return SourceErrorKind.unavailable;
  }
  if (numericCode == -101) return SourceErrorKind.loginRequired;
  if (numericCode == -403 || numericCode == 62012) {
    return SourceErrorKind.permissionDenied;
  }
  if (numericCode == -10403) return SourceErrorKind.geoRestricted;
  return SourceErrorKind.unknown;
}

@override
bool get isUnavailable => super.isUnavailable;

@override
bool get isRateLimited => super.isRateLimited;

@override
bool get requiresLogin => super.requiresLogin;

@override
bool get isPermissionDenied => super.isPermissionDenied;

@override
bool get isGeoRestricted => super.isGeoRestricted;

@override
bool get isNetworkError => super.isNetworkError;

@override
bool get isTimeout => super.isTimeout;
```

Keep the existing `_mapCode()` implementation so diagnostics remain unchanged.

- [ ] **Step 4: Implement YouTube kind mapping while preserving private/age behavior**

In `lib/data/sources/youtube_exception.dart`, add:

```dart
@override
SourceErrorKind get kind => switch (code) {
      'timeout' => SourceErrorKind.timeout,
      'network_error' => SourceErrorKind.network,
      'rate_limited' => SourceErrorKind.rateLimited,
      'unavailable' || 'not_found' || 'unplayable' || 'no_stream' =>
        SourceErrorKind.unavailable,
      'login_required' || 'age_restricted' => SourceErrorKind.loginRequired,
      'private_or_inaccessible' => SourceErrorKind.permissionDenied,
      'geo_restricted' => SourceErrorKind.geoRestricted,
      _ => SourceErrorKind.unknown,
    };

@override
bool get isUnavailable => super.isUnavailable;

@override
bool get isRateLimited => super.isRateLimited;

@override
bool get requiresLogin => super.requiresLogin;

@override
bool get isPermissionDenied =>
    super.isPermissionDenied || code == 'age_restricted';

@override
bool get isGeoRestricted => super.isGeoRestricted;

@override
bool get isNetworkError => super.isNetworkError;

@override
bool get isTimeout => super.isTimeout;
```

- [ ] **Step 5: Implement Netease kind mapping while preserving diagnostic strings**

In `lib/data/sources/netease_exception.dart`, add:

```dart
@override
SourceErrorKind get kind {
  if (numericCode == -997) return SourceErrorKind.timeout;
  if (numericCode == -998) return SourceErrorKind.network;
  if (numericCode == -460 || numericCode == -462) {
    return SourceErrorKind.rateLimited;
  }
  if (numericCode == -200) return SourceErrorKind.unavailable;
  if (numericCode == 301) return SourceErrorKind.loginRequired;
  if (numericCode == 403) return SourceErrorKind.permissionDenied;
  if (numericCode == -10) return SourceErrorKind.vipRequired;
  return SourceErrorKind.unknown;
}

@override
bool get isUnavailable => super.isUnavailable;

@override
bool get isRateLimited => super.isRateLimited;

@override
bool get isGeoRestricted => super.isGeoRestricted;

@override
bool get requiresLogin => super.requiresLogin;

@override
bool get isNetworkError => super.isNetworkError;

@override
bool get isTimeout => super.isTimeout;

@override
bool get isPermissionDenied => super.isPermissionDenied;

@override
bool get isVipRequired => super.isVipRequired;
```

- [ ] **Step 6: Run the source exception suite and verify it passes**

Run: `flutter test test/data/sources/source_exception_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/data/sources/bilibili_exception.dart lib/data/sources/youtube_exception.dart lib/data/sources/netease_exception.dart test/data/sources/source_exception_test.dart
git commit -m "refactor(source): expose semantic exception kinds"
```

---

### Task 3: Shared Source HTTP and Header Policy

**Files:**
- Create: `lib/data/sources/source_http_policy.dart`
- Modify: `lib/core/utils/http_client_factory.dart:12-37`
- Modify: `lib/core/utils/auth_headers_utils.dart:1-37`
- Modify: `test/data/sources/source_http_policy_test.dart`

- [ ] **Step 1: Write failing policy tests**

Create `test/data/sources/source_http_policy_test.dart` with this content:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/source_http_policy.dart';

void main() {
  group('SourceHttpPolicy', () {
    test('media headers do not leak non-Netease auth headers', () {
      final bilibili = SourceHttpPolicy.mediaHeaders(
        SourceType.bilibili,
        authHeaders: const {'Cookie': 'SESSDATA=secret'},
      );
      final youtube = SourceHttpPolicy.mediaHeaders(
        SourceType.youtube,
        authHeaders: const {'Authorization': 'Bearer secret'},
      );

      expect(bilibili['Referer'], SourceHttpPolicy.bilibiliWebReferer);
      expect(bilibili['User-Agent'], SourceHttpPolicy.mediaUserAgent);
      expect(bilibili.containsKey('Cookie'), isFalse);
      expect(youtube['Origin'], SourceHttpPolicy.youtubeOrigin);
      expect(youtube['Referer'], SourceHttpPolicy.youtubeReferer);
      expect(youtube.containsKey('Authorization'), isFalse);
    });

    test('media headers preserve only allowed Netease auth media headers', () {
      final headers = SourceHttpPolicy.mediaHeaders(
        SourceType.netease,
        authHeaders: const {
          'Cookie': 'MUSIC_U=token',
          'Origin': 'https://music.163.com',
          'Referer': 'https://music.163.com/',
          'User-Agent': 'NetEase-UA',
          'X-Api-Only': 'drop-me',
        },
      );

      expect(headers['Cookie'], 'MUSIC_U=token');
      expect(headers['Origin'], SourceHttpPolicy.neteaseOrigin);
      expect(headers['Referer'], SourceHttpPolicy.neteaseReferer);
      expect(headers['User-Agent'], 'NetEase-UA');
      expect(headers.containsKey('X-Api-Only'), isFalse);
    });

    test('api headers keep source-specific referer origin and user agent', () {
      expect(SourceHttpPolicy.apiHeaders(SourceType.bilibili), containsPair(
        'Referer',
        SourceHttpPolicy.bilibiliReferer,
      ));
      expect(SourceHttpPolicy.apiHeaders(SourceType.youtube), containsPair(
        'Origin',
        SourceHttpPolicy.youtubeOrigin,
      ));
      expect(SourceHttpPolicy.apiHeaders(SourceType.netease), containsPair(
        'User-Agent',
        SourceHttpPolicy.neteaseDesktopUserAgent,
      ));
    });

    test('createApiDio applies source defaults and optional content type', () {
      final dio = SourceHttpPolicy.createApiDio(
        SourceType.youtube,
        contentType: 'application/json',
      );

      expect(dio.options.headers['Origin'], SourceHttpPolicy.youtubeOrigin);
      expect(dio.options.headers['Referer'], SourceHttpPolicy.youtubeReferer);
      expect(dio.options.contentType, 'application/json');
      expect(dio.options.connectTimeout, isNotNull);
      dio.close();
    });
  });
}
```

- [ ] **Step 2: Run the policy test and verify it fails**

Run: `flutter test test/data/sources/source_http_policy_test.dart`

Expected: FAIL because `source_http_policy.dart` does not exist.

- [ ] **Step 3: Add `contentType` support to `HttpClientFactory`**

Update `lib/core/utils/http_client_factory.dart` so `create()` accepts and forwards `contentType`:

```dart
static Dio create({
  Map<String, dynamic>? headers,
  String? userAgent,
  Duration? connectTimeout,
  Duration? receiveTimeout,
  String? contentType,
}) {
  final mergedHeaders = <String, dynamic>{
    'User-Agent': userAgent ?? defaultUserAgent,
    ...?headers,
  };

  return Dio(BaseOptions(
    headers: mergedHeaders,
    contentType: contentType,
    connectTimeout: connectTimeout ?? AppConstants.networkConnectTimeout,
    receiveTimeout: receiveTimeout ?? AppConstants.networkReceiveTimeout,
  ));
}
```

- [ ] **Step 4: Create the shared source policy**

Create `lib/data/sources/source_http_policy.dart` with this content:

```dart
import 'package:dio/dio.dart';

import '../../core/utils/http_client_factory.dart';
import '../models/track.dart';

class SourceHttpPolicy {
  SourceHttpPolicy._();

  static const String mediaUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const String webUserAgent = HttpClientFactory.defaultUserAgent;
  static const String neteaseDesktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 '
      'NeteaseMusicDesktop/3.0.18.203152';
  static const String neteaseLinuxUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36';

  static const String bilibiliOrigin = 'https://www.bilibili.com';
  static const String bilibiliReferer = 'https://www.bilibili.com/';
  static const String bilibiliWebReferer = 'https://www.bilibili.com';
  static const String youtubeOrigin = 'https://www.youtube.com';
  static const String youtubeReferer = 'https://www.youtube.com/';
  static const String neteaseOrigin = 'https://music.163.com';
  static const String neteaseReferer = 'https://music.163.com/';

  static Map<String, String> mediaHeaders(
    SourceType sourceType, {
    Map<String, String>? authHeaders,
  }) {
    final headers = switch (sourceType) {
      SourceType.bilibili => <String, String>{
          'Referer': bilibiliWebReferer,
          'User-Agent': mediaUserAgent,
        },
      SourceType.youtube => <String, String>{
          'Origin': youtubeOrigin,
          'Referer': youtubeReferer,
          'User-Agent': mediaUserAgent,
        },
      SourceType.netease => <String, String>{
          'Origin': neteaseOrigin,
          'Referer': neteaseReferer,
          'User-Agent': mediaUserAgent,
        },
    };

    if (sourceType == SourceType.netease && authHeaders != null) {
      for (final key in const ['Cookie', 'Origin', 'Referer', 'User-Agent']) {
        final value = authHeaders[key];
        if (value != null && value.isNotEmpty) {
          headers[key] = value;
        }
      }
    }

    return headers;
  }

  static Map<String, String> apiHeaders(
    SourceType sourceType, {
    Map<String, String>? extraHeaders,
    String? userAgent,
  }) {
    final headers = switch (sourceType) {
      SourceType.bilibili => <String, String>{
          'User-Agent': userAgent ?? webUserAgent,
          'Referer': bilibiliReferer,
          'Origin': bilibiliOrigin,
          'Accept': 'application/json, text/plain, */*',
        },
      SourceType.youtube => <String, String>{
          'User-Agent': userAgent ?? mediaUserAgent,
          'Origin': youtubeOrigin,
          'Referer': youtubeReferer,
        },
      SourceType.netease => <String, String>{
          'User-Agent': userAgent ?? neteaseDesktopUserAgent,
          'Referer': neteaseReferer,
          'Origin': neteaseOrigin,
          'Accept': 'application/json, text/plain, */*',
        },
    };

    headers.addAll(extraHeaders ?? const <String, String>{});
    return headers;
  }

  static Map<String, String> neteaseAuthHeaders(String cookie) {
    return {
      'Cookie': cookie,
      'Origin': neteaseOrigin,
      'Referer': neteaseReferer,
      'User-Agent': neteaseDesktopUserAgent,
    };
  }

  static Dio createApiDio(
    SourceType sourceType, {
    Map<String, String>? extraHeaders,
    String? userAgent,
    String? contentType,
  }) {
    return HttpClientFactory.create(
      headers: apiHeaders(
        sourceType,
        extraHeaders: extraHeaders,
        userAgent: userAgent,
      ),
      contentType: contentType,
    );
  }
}
```

- [ ] **Step 5: Update direct auth-header construction**

In `lib/core/utils/auth_headers_utils.dart`, fix the import/comment line and replace the Netease case with:

```dart
case SourceType.netease:
  final cookies = await neteaseAccountService?.getAuthCookieString();
  if (cookies == null) return null;
  return SourceHttpPolicy.neteaseAuthHeaders(cookies);
```

Add this import:

```dart
import '../../data/sources/source_http_policy.dart';
```

- [ ] **Step 6: Run the policy and auth retry focused tests**

Run: `flutter test test/data/sources/source_http_policy_test.dart test/services/audio/audio_auth_retry_phase4_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/data/sources/source_http_policy.dart lib/core/utils/http_client_factory.dart lib/core/utils/auth_headers_utils.dart test/data/sources/source_http_policy_test.dart
git commit -m "feat(source): add shared HTTP header policy"
```

---

### Task 4: Playback and Download Media Header Migration

**Files:**
- Modify: `lib/services/download/download_media_headers.dart:1-25`
- Modify: `lib/services/audio/audio_stream_manager.dart:180-227`
- Modify: `test/services/download/download_media_headers_test.dart:1-52`
- Modify: `test/services/audio/audio_stream_manager_test.dart`

- [ ] **Step 1: Update tests to assert policy delegation values**

In `test/services/download/download_media_headers_test.dart`, replace the `AudioStreamManager` import with:

```dart
import 'package:fmp/data/sources/source_http_policy.dart';
```

Then replace `AudioStreamManager.defaultPlaybackUserAgent` expectations with `SourceHttpPolicy.mediaUserAgent`.

In `test/services/audio/audio_stream_manager_test.dart`, add `source_http_policy.dart` import and add this test inside the `AudioStreamManager` group:

```dart
test('playback headers use shared source media policy', () async {
  final youtube = await audioStreamManager.getPlaybackHeaders(
    Track()
      ..sourceId = 'yt'
      ..sourceType = SourceType.youtube
      ..title = 'YouTube'
      ..artist = 'Tester',
  );
  final bilibili = await audioStreamManager.getPlaybackHeaders(
    Track()
      ..sourceId = 'bv'
      ..sourceType = SourceType.bilibili
      ..title = 'Bilibili'
      ..artist = 'Tester',
  );

  expect(youtube, SourceHttpPolicy.mediaHeaders(SourceType.youtube));
  expect(bilibili, SourceHttpPolicy.mediaHeaders(SourceType.bilibili));
  expect(
    AudioStreamManager.defaultPlaybackUserAgent,
    SourceHttpPolicy.mediaUserAgent,
  );
});
```

- [ ] **Step 2: Run focused media header tests and verify they fail**

Run: `flutter test test/services/download/download_media_headers_test.dart test/services/audio/audio_stream_manager_test.dart --plain-name "playback headers use shared source media policy"`

Expected: FAIL because `AudioStreamManager.defaultPlaybackUserAgent` is not yet an alias for `SourceHttpPolicy.mediaUserAgent` and playback headers are not yet delegated through the policy.

- [ ] **Step 3: Delegate download media headers to the policy**

Replace `lib/services/download/download_media_headers.dart` with:

```dart
import '../../data/models/track.dart';
import '../../data/sources/source_http_policy.dart';

Map<String, String> buildDownloadMediaHeaders(
  SourceType sourceType, {
  Map<String, String>? authHeaders,
}) {
  return SourceHttpPolicy.mediaHeaders(
    sourceType,
    authHeaders: authHeaders,
  );
}
```

- [ ] **Step 4: Delegate playback headers to the policy**

In `lib/services/audio/audio_stream_manager.dart`, import `SourceHttpPolicy` and replace `getPlaybackHeaders()` with:

```dart
@override
Future<Map<String, String>?> getPlaybackHeaders(Track track) async {
  final authHeaders = track.sourceType == SourceType.netease
      ? await _neteaseAccountService?.getAuthHeaders()
      : null;
  return SourceHttpPolicy.mediaHeaders(
    track.sourceType,
    authHeaders: authHeaders,
  );
}

static const String defaultPlaybackUserAgent = SourceHttpPolicy.mediaUserAgent;
```

- [ ] **Step 5: Run media header tests and verify they pass**

Run: `flutter test test/services/download/download_media_headers_test.dart test/services/audio/audio_stream_manager_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/download/download_media_headers.dart lib/services/audio/audio_stream_manager.dart test/services/download/download_media_headers_test.dart test/services/audio/audio_stream_manager_test.dart
git commit -m "refactor(audio): use shared media header policy"
```

---

### Task 5: Account Service API Client Policy Migration

**Files:**
- Modify: `lib/services/account/bilibili_account_service.dart:73-86`
- Modify: `lib/services/account/bilibili_favorites_service.dart:43-57`
- Modify: `lib/services/account/youtube_account_service.dart:38-52`
- Modify: `lib/services/account/youtube_playlist_service.dart:48-64`
- Modify: `lib/services/account/netease_account_service.dart:27-52`
- Modify: `lib/services/account/netease_playlist_service.dart:82-106`
- Create: `test/services/account/source_http_policy_usage_test.dart`

- [ ] **Step 1: Add a focused usage structure test**

Create `test/services/account/source_http_policy_usage_test.dart` with this content:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('account source HTTP policy usage', () {
    test('source account clients use SourceHttpPolicy for Dio defaults', () {
      final files = {
        'lib/services/account/bilibili_account_service.dart': 'SourceType.bilibili',
        'lib/services/account/bilibili_favorites_service.dart': 'SourceType.bilibili',
        'lib/services/account/youtube_account_service.dart': 'SourceType.youtube',
        'lib/services/account/youtube_playlist_service.dart': 'SourceType.youtube',
        'lib/services/account/netease_account_service.dart': 'SourceType.netease',
        'lib/services/account/netease_playlist_service.dart': 'SourceType.netease',
      };

      for (final entry in files.entries) {
        final source = File(entry.key).readAsStringSync();
        expect(source, contains('SourceHttpPolicy.createApiDio'));
        expect(source, contains(entry.value));
        expect(source, isNot(contains('Dio(BaseOptions')));
      }
    });
  });
}
```

- [ ] **Step 2: Run the usage test and verify it fails**

Run: `flutter test test/services/account/source_http_policy_usage_test.dart`

Expected: FAIL because the account clients still construct `Dio(BaseOptions(...))` directly.

- [ ] **Step 3: Migrate Bilibili account clients**

In both `bilibili_account_service.dart` and `bilibili_favorites_service.dart`:

1. Add imports:

```dart
import '../../data/sources/source_http_policy.dart';
```

2. Replace constructor-created `Dio(BaseOptions(...))` with:

```dart
_dio = SourceHttpPolicy.createApiDio(SourceType.bilibili),
```

For `bilibili_favorites_service.dart`, keep the interceptor line unchanged:

```dart
dio.interceptors.add(BilibiliAuthInterceptor(accountService));
```

- [ ] **Step 4: Migrate YouTube account clients**

In both `youtube_account_service.dart` and `youtube_playlist_service.dart`:

1. Add:

```dart
import '../../data/sources/source_http_policy.dart';
```

2. Replace the raw `Dio(BaseOptions(...))` construction with:

```dart
SourceHttpPolicy.createApiDio(
  SourceType.youtube,
  contentType: 'application/json',
),
```

3. Keep `YouTubeAuthInterceptor(accountService)` unchanged in `youtube_playlist_service.dart`.

- [ ] **Step 5: Migrate Netease account clients without changing special cookies or Linux UA**

In `netease_account_service.dart`:

1. Add:

```dart
import '../../data/sources/source_http_policy.dart';
```

2. Replace raw construction with:

```dart
_dio = SourceHttpPolicy.createApiDio(
  SourceType.netease,
  extraHeaders: const {'Cookie': _anonymousCookie},
  contentType: Headers.formUrlEncodedContentType,
),
```

In `netease_playlist_service.dart`:

1. Remove the local `_linuxUserAgent` constant.
2. Add `source_http_policy.dart` import.
3. Replace raw construction with:

```dart
final dio = SourceHttpPolicy.createApiDio(
  SourceType.netease,
  userAgent: SourceHttpPolicy.neteaseLinuxUserAgent,
);
```

Keep all Netease crypto request body and cookie-auth logic unchanged.

- [ ] **Step 6: Run focused usage and account-adjacent tests**

Run: `flutter test test/services/account/source_http_policy_usage_test.dart test/services/audio/audio_auth_retry_phase4_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/services/account/bilibili_account_service.dart lib/services/account/bilibili_favorites_service.dart lib/services/account/youtube_account_service.dart lib/services/account/youtube_playlist_service.dart lib/services/account/netease_account_service.dart lib/services/account/netease_playlist_service.dart test/services/account/source_http_policy_usage_test.dart
git commit -m "refactor(account): use shared source API clients"
```

---

### Task 6: Kind-Based Playback Error Decisions

**Files:**
- Modify: `lib/services/audio/audio_provider.dart:1879-1983,2088-2177,2235-2259,2504-2547`
- Modify: `test/services/audio/audio_auth_retry_phase4_test.dart:101-214`
- Create: `test/services/audio/audio_error_kind_structure_test.dart`

- [ ] **Step 1: Add failing tests for typed source-kind retry and non-retry decisions**

In `test/services/audio/audio_auth_retry_phase4_test.dart`, add imports:

```dart
import 'package:fmp/data/sources/source_exception.dart';
import 'package:fmp/data/sources/youtube_exception.dart';
```

Update `_RetryAwareSource` to include:

```dart
Object? nextStreamError;
```

Then at the top of `_RetryAwareSource.getAudioStream()`, before returning `AudioStreamResult`, add:

```dart
final error = nextStreamError;
if (error != null) {
  nextStreamError = null;
  throw error;
}
```

Add these two tests inside the existing group:

```dart
test('typed source network kind schedules retry without string matching', () async {
  final track = _track('typed-network-kind');
  sourceManager.source.nextStreamError = const YouTubeApiException(
    code: 'network_error',
    message: 'temporary socket failure',
  );

  await controller.playTrack(track);
  await pumpEventQueue(times: 20);

  expect(controller.state.isRetrying, isTrue);
  expect(controller.state.isNetworkError, isTrue);
  expect(controller.state.nextRetryAt, isNotNull);
  expect(audioService.playUrlCalls, isEmpty);
});

test('typed source permission kind does not schedule network retry', () async {
  final track = _track('typed-permission-kind');
  sourceManager.source.nextStreamError = const YouTubeApiException(
    code: 'private_or_inaccessible',
    message: 'private video',
  );

  await controller.playTrack(track);
  await pumpEventQueue(times: 20);

  expect(controller.state.isRetrying, isFalse);
  expect(controller.state.isNetworkError, isFalse);
  expect(controller.state.error, isNotNull);
});
```

Add this small base-class assertion inside the network-kind test before `await controller.playTrack(track);`:

```dart
expect(
  const YouTubeApiException(code: 'network_error', message: 'network').kind,
  SourceErrorKind.network,
);
```

Create `test/services/audio/audio_error_kind_structure_test.dart` with this content to make the intended production migration explicit:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioController source error kind usage', () {
    test('typed source errors use kind helpers before string fallback', () {
      final source = File('lib/services/audio/audio_provider.dart').readAsStringSync();

      expect(source, contains('bool _shouldRetrySourceError(SourceApiException error)'));
      expect(source, contains('error.kind.isRetryable'));
      expect(source, contains('bool _shouldSkipSourceError(SourceApiException error)'));
      expect(source, contains('error.kind.shouldSkipTrack'));
      expect(source, contains('bool _isStringNetworkError(Object error)'));
      expect(source, contains('bool _isRetryableError(Object error)'));
      expect(source, contains('if (error is SourceApiException) return error.kind.isRetryable;'));
      expect(source, isNot(contains('bool _isNetworkError(dynamic error)')));
      expect(source, contains('_onAudioError(String error)'));
      final onAudioErrorStart = source.indexOf('void _onAudioError(String error)');
      final onAudioErrorBody = source.substring(onAudioErrorStart);
      expect(onAudioErrorBody, contains('_isStringNetworkError(error)'));
    });
  });
}
```

- [ ] **Step 2: Run focused auth retry tests and verify the new tests fail if Task 6 is executed before production changes**

Run: `flutter test test/services/audio/audio_auth_retry_phase4_test.dart test/services/audio/audio_error_kind_structure_test.dart`

Expected before production changes: FAIL because the structure test cannot find the kind helper methods yet. If the behavioral network-kind test already passes because Task 2 boolean getters delegate to `kind`, still keep it as regression coverage and continue to Step 3.

- [ ] **Step 3: Add small kind helpers in `AudioController`**

In `lib/services/audio/audio_provider.dart`, replace direct typed checks in `_executePlayRequest()` and `_handleSourceError()` with helpers:

```dart
bool _shouldRetrySourceError(SourceApiException error) => error.kind.isRetryable;

bool _shouldSkipSourceError(SourceApiException error) => error.kind.shouldSkipTrack;
```

Then change:

```dart
if (e.isNetworkError || e.isTimeout) {
```

to:

```dart
if (_shouldRetrySourceError(e)) {
```

Change:

```dart
if (e.isUnavailable || e.isGeoRestricted || e.isVipRequired) {
```

to:

```dart
if (_shouldSkipSourceError(e)) {
```

Keep the rate-limit branch as `e.kind == SourceErrorKind.rateLimited` or `e.isRateLimited`; prefer the explicit kind check:

```dart
} else if (e.kind == SourceErrorKind.rateLimited) {
```

- [ ] **Step 4: Preserve string fallback only for non-source errors and audio-service text**

Rename `_isNetworkError(dynamic error)` to `_isStringNetworkError(Object error)` and keep its current string implementation. Add:

```dart
bool _isRetryableError(Object error) {
  if (error is SourceApiException) return error.kind.isRetryable;
  return _isStringNetworkError(error);
}
```

Replace retry catch sites that handle `Object e` with `_isRetryableError(e)`. Keep `_onAudioError(String error)` using `_isStringNetworkError(error)` because the audio service stream only exposes raw text.

- [ ] **Step 5: Run focused retry tests**

Run: `flutter test test/services/audio/audio_auth_retry_phase4_test.dart test/services/audio/audio_error_kind_structure_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/services/audio/audio_provider.dart test/services/audio/audio_auth_retry_phase4_test.dart test/services/audio/audio_error_kind_structure_test.dart
git commit -m "refactor(audio): use source error kinds for retry decisions"
```

---

### Task 7: Phase Verification and Documentation Boundary

**Files:**
- Modify if needed: `CLAUDE.md`

- [ ] **Step 1: Run the focused Phase 6 test suite**

Run:

```bash
flutter test test/data/sources/source_exception_test.dart test/data/sources/source_http_policy_test.dart test/services/download/download_media_headers_test.dart test/services/audio/audio_stream_manager_test.dart test/services/audio/audio_auth_retry_phase4_test.dart test/services/audio/audio_error_kind_structure_test.dart test/services/account/source_http_policy_usage_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 3: Run full Flutter tests**

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 4: Update project guidance if the source policy is now core architecture**

If Tasks 1-6 changed source policy/error architecture, update `CLAUDE.md` sections `Unified Source Exception Handling`, `Auth for Playback`, and/or `File Structure Highlights` with concise notes:

```markdown
- Source exceptions expose `SourceErrorKind` for shared retry/skip/login/rate-limit decisions while preserving source-specific diagnostic codes.
- `SourceHttpPolicy` centralizes source API/media header defaults; keep source-specific anti-rate-limit or encryption details inside the source/account service that owns them.
```

- [ ] **Step 5: Verify documentation-only changes if Step 4 edited `CLAUDE.md`**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 6: Commit final verification/documentation changes**

If `CLAUDE.md` changed:

```bash
git add CLAUDE.md
git commit -m "docs: document source policy semantics"
```

If no documentation update was needed, do not create an empty commit.

---

## Final Verification Checklist

- [ ] `flutter test test/data/sources/source_exception_test.dart test/data/sources/source_http_policy_test.dart test/services/download/download_media_headers_test.dart test/services/audio/audio_stream_manager_test.dart test/services/audio/audio_auth_retry_phase4_test.dart test/services/audio/audio_error_kind_structure_test.dart test/services/account/source_http_policy_usage_test.dart` passes.
- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.
- [ ] `SourceApiException.code`, source-specific numeric/string codes, and `toString()` diagnostics remain available.
- [ ] Bilibili and YouTube auth cookies/authorization headers are not sent as media download headers.
- [ ] Netease media playback/download can still include the Netease auth cookie and desktop user agent.
- [ ] Typed source errors use `SourceErrorKind`; raw string network detection remains only for raw audio-service text and non-source exception fallbacks.
- [ ] No push is performed.
