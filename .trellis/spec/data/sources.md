# Source adapters

Bilibili, YouTube and NetEase adapters live in `lib/data/sources/`. Playlist
import sources (`lib/data/sources/playlist_import/`) are a separate path, covered
at the end.

## Shape: narrow capabilities, no base class

An adapter is a plain class `with Logging implements DisposableSource, <capabilities…>`.
Each capability is an `abstract interface class … implements SourceCapability`
in `source_capabilities.dart` (`AudioStreamSource`, `SearchSource`,
`PlaylistParsingSource`, `RankingSource`, `LiveSource`, …). The only member every
capability requires is `String get sourceType => SourceIds.<id>`.

- There is deliberately no `BaseSource` (comment at the top of `base_source.dart`;
  that file now holds only value types such as `AudioStreamRequest` /
  `AudioStreamResult`).
- A capability or method nothing consumes gets deleted, not kept "for later"
  (`19f721c7`, `cde4769e`, `cd3aa568`).
- Examples: `NeteaseSource`, `BilibiliSource`, `YouTubeSource`.

## Construction and access: only `SourceManager`

- Concrete adapters are constructed only in `SourceManager`
  (`lib/data/sources/source_provider.dart`). Callers ask for a capability by id or
  URL — `audioStreamSource(type)`, `searchSource(type)`,
  `trackInfoSourceForUrl(url)` — and get a nullable interface back.
- Implementing `DisposableSource` is what gets an adapter disposed.
- UI source lists come from `registeredSourceTypesProvider` /
  `searchSourceTypesProvider` / `rankingSourceTypesProvider`; never hand-write a list.
- Branching on a source id outside `lib/data/sources/` has a per-file budget that
  can only shrink. Ask a capability, or key a table by `SourceIds.x`, instead of
  writing `if (type == SourceIds.bilibili)`.
- Gates: `test/data/static_rules/source_ownership_static_rule_test.dart`,
  `test/support/source_branch_points_static_rule_test.dart`,
  `test/support/call_site_ownership_static_rule_test.dart`.

## HTTP: always through `SourceHttpPolicy`

- Get the API client from `SourceHttpPolicy.createApiDio(SourceIds.<id>, …)` and
  accept an optional injected `Dio? dio` for tests:
  `_dio = dio ?? SourceHttpPolicy.createApiDio(SourceIds.netease)`.
- Per-source CDN / API headers, API user agent and image hosts live in one
  `_bySource` table in `source_http_policy.dart`; a new source adds a row there
  instead of writing its own headers. (API base URLs stay in the adapter.)
- `Referer` / `Origin` / `User-Agent` literals may appear only in the files listed
  in `_headerLiteralOwners`; every hard-coded host must be listed with a purpose.
  Gates: `test/support/source_http_policy_static_rule_test.dart`,
  `test/support/outbound_hosts_static_rule_test.dart`.
- **Media bytes never carry credentials.** `SourceHttpPolicy.mediaHeaders(String sourceType)`
  takes only the id, so the boundary lives in the signature
  (`c09aec10`; pinned by `test/data/sources/source_http_policy_test.dart`). Do not
  add a parameter to it.
- URLs from users or redirects go through `SourceUrlPolicy`
  (`parseTrustedHttpUrl(url, allowedHosts:)`, `resolveRedirects(...)`): exact host
  allowlists, http/https only, private hosts rejected. Never detect a platform by
  substring-matching the raw URL.

## Auth: passed in, never read

Adapters never read accounts. Credentials arrive per request as
`Map<String, String>? authHeaders` (`AudioStreamRequest.authHeaders`,
`getVideoDetail(…, {authHeaders})`, `parsePlaylist(…, {authHeaders})`), and the
adapter keeps only what it needs (`NeteaseSource._withAuth` keeps `Cookie`). The
caller side is `SourceAuthContext` in `lib/services/account/`; the terms are
defined in `CONTEXT.md`.

## Errors: one `SourceApiException` subtype per source

- Each source throws `<Source>ApiException extends SourceApiException` from
  `<source>_exception.dart`; the subtype maps its native code to
  `SourceErrorKind`. Callers read `kind` and the semantic getters
  (`isRateLimited`, `requiresLogin`, …), never the raw code.
- Most method bodies follow one shape (`NeteaseSource`, `BilibiliSource`):

  ```dart
  try {
    return await _request(...);
  } on DioException catch (e) {
    throw _handleDioError(e);            // uses SourceApiException.classifyDioError
  } catch (e) {
    if (e is NeteaseApiException) rethrow;
    logError('Unexpected error in getAudioStream: $e');
    throw NeteaseApiException(numericCode: -999, message: e.toString());
  }
  ```

  A non-success body code is raised by `_checkResponse(data)`, which itself
  `logWarning`s and throws the source exception.
- **Always `return await` inside `try`.** A returned un-awaited future escapes the
  catch, so classification never runs (`ca54669c`: YouTube rate limits went
  undetected).
- Classification order is load-bearing — NetEase "login required" is checked
  before VIP (`e2321e38`, #87). Read the dartdoc on the classifier before
  reordering.
- Lower-quality fallback is shared (`audio_stream_quality_fallback.dart`) and runs
  only when `SourceErrorKind.canFallbackToLowerAudioQuality`.
- Return the URL expiry the source reports in `AudioStreamResult.expiry`; do not
  hard-code a TTL (`b1fa0fc5`).

## Value types and parsing

- Non-persisted types: `final` fields, `const` constructor, named params,
  `const []` defaults, `factory X.empty()` where useful.
- `copyWith` uses `x ?? this.x`; a nullable field that must be clearable gets a
  `bool clearX = false` flag (`AudioStreamRequest.copyWith`).
- JSON parsing is hand-written — no freezed / json_serializable. JSON factories
  are named after the API response they read (`LiveRoom.fromRoomInfo`,
  `LiveRoom.fromLiveRoomSearch`) and read defensively: `json['k'] as int? ?? 0`,
  `(json['list'] as List<dynamic>?) ?? []`.
- `==` / `hashCode` are hand-written sparingly, only where identity matters
  (`TrackKeyParts`, `TrackSourceIdentity`, `LiveRoom` by `roomId`).
- `toString()` overrides leave out URLs and secrets (`AudioStreamResult.toString`).

## Playlist import sources

`lib/data/sources/playlist_import/` implements `PlaylistImportSource`, is
registered in `lib/services/import/playlist_import_service.dart` (not
`SourceManager`), may use `HttpClientFactory.create()` directly, and throws
`Exception(t.importSource.…)` with a translated message. Do not copy this shape
into the main adapters.

## Tests

- Inject a `Dio` and stub it: a file-local `_FakeHttpClientAdapter`
  (`test/data/sources/youtube_source_test.dart`) or an interceptor
  (`test/data/sources/netease_source_test.dart`). Fixtures are inline Dart maps;
  there is no fixture directory.
- Assert errors by kind:
  `throwsA(isA<YouTubeApiException>().having((e) => e.kind, 'kind', SourceErrorKind.loginRequired))`.
- A test that builds an adapter with its default constructor hits the network and
  must be tagged `live` (`test/support/live_source_tag_static_rule_test.dart`; a
  new adapter class is added to its `_guardedClasses`).
