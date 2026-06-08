# Bilibili Live Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Bilibili live-room API mechanics into `BilibiliLiveClient` while preserving existing search, radio, and account medal-wall behavior.

**Architecture:** Add a focused client in `lib/data/sources/bilibili_live_client.dart` that owns live URL parsing, real room ID resolution, room detail composition, stream URL lookup, live search, and medal wall room lookup. Keep `BilibiliSource`, `RadioSource`, and `BilibiliAccountService` public APIs compatible by making them adapters around the new client.

**Tech Stack:** Flutter, Dart, Dio, Riverpod providers, existing `SourceHttpPolicy`, `flutter_test`.

---

## Repository Rules For This Plan

- Do not commit, amend, rebase, or push unless the user explicitly requests it. The generic planning habit of frequent commits is overridden by root `AGENTS.md`.
- Use TDD: write or update the failing test first, run it to confirm the current gap, then implement.
- Preserve current runtime behavior, stream parameters, headers, provider names, and public method names.
- Keep Bilibili live radio Bilibili-only.

## File Structure

- Create: `lib/data/sources/bilibili_live_client.dart`
  - Owns Bilibili live endpoints, live response parsing, live Dio creation, and live media headers.
  - Exposes `BilibiliLiveClient`, `BilibiliLiveUrlParseResult`, `BilibiliLiveRoomDetails`, `BilibiliLiveStream`, and `BilibiliMedalWallRoom`.
- Create: `test/data/sources/bilibili_live_client_test.dart`
  - Uses fake Dio adapters to verify exact endpoint paths, query parameters, fallback behavior, DTO mapping, and header policy usage.
- Modify: `lib/data/sources/bilibili_source.dart`
  - Keeps video/search/audio source responsibilities.
  - Delegates `searchLiveRooms()`, `getLiveRoomInfo()`, and `getLiveStreamUrl()` to `BilibiliLiveClient`.
- Modify: `lib/services/radio/radio_source.dart`
  - Keeps radio-facing `ParseResult`, `LiveRoomInfo`, `LiveStreamInfo`, and `RadioStation` mapping.
  - Delegates live API mechanics to `BilibiliLiveClient`.
- Modify: `lib/services/account/bilibili_account_service.dart`
  - Keeps login, credential, and account ownership.
  - Delegates medal wall live-room lookup to `BilibiliLiveClient`.
- Modify: `test/services/radio/radio_source_http_policy_usage_test.dart`
  - Checks `bilibili_live_client.dart` for live policy usage instead of requiring live Dio ownership in old adapters.
- Modify: `test/services/account/bilibili_account_live_policy_test.dart`
  - Checks account medal-wall delegation and the new live client policy owner.
- Modify: `lib/data/sources/AGENTS.md`
  - Documents that Bilibili live room API mechanics are owned by `BilibiliLiveClient`, not `BilibiliSource`.
- Modify: `lib/services/AGENTS.md`
  - Mentions that Bilibili account medal wall import delegates live room lookup to `BilibiliLiveClient`.

## Shared Test Helpers

Use this helper in `test/data/sources/bilibili_live_client_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/live_room.dart';
import 'package:fmp/data/sources/bilibili_live_client.dart';
import 'package:fmp/data/sources/source_http_policy.dart';

typedef DioHandler = ResponseBody Function(
  RequestOptions options,
  Object? requestBody,
);

class FakeHttpClientAdapter implements HttpClientAdapter {
  FakeHttpClientAdapter(this._handler);

  final DioHandler _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final requestBody = requestStream == null
        ? null
        : utf8.decode(await requestStream.expand((chunk) => chunk).toList());
    return _handler(options, requestBody);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

Dio dioWith(DioHandler handler) {
  return Dio()..httpClientAdapter = FakeHttpClientAdapter(handler);
}
```

## Task 1: Client Skeleton, URL Parsing, And Real Room ID

**Files:**
- Create: `lib/data/sources/bilibili_live_client.dart`
- Create: `test/data/sources/bilibili_live_client_test.dart`

- [ ] **Step 1: Write failing URL parsing tests**

Add these tests under `group('parseLiveUrl', ...)`:

```dart
test('accepts standard and h5 Bilibili live URLs', () {
  final client = BilibiliLiveClient(apiDio: Dio(), liveDio: Dio());

  expect(
    client.parseLiveUrl('https://live.bilibili.com/12345')?.roomId,
    '12345',
  );
  expect(
    client.parseLiveUrl('https://live.bilibili.com/h5/67890')?.normalizedUrl,
    'https://live.bilibili.com/67890',
  );
});

test('rejects non-live URLs', () {
  final client = BilibiliLiveClient(apiDio: Dio(), liveDio: Dio());

  expect(client.parseLiveUrl('https://www.bilibili.com/video/BV1xx'), isNull);
  expect(client.parseLiveUrl('https://youtu.be/example'), isNull);
});
```

- [ ] **Step 2: Run the new parsing tests and confirm they fail**

Run:

```bash
flutter test test/data/sources/bilibili_live_client_test.dart --plain-name "accepts standard and h5 Bilibili live URLs"
```

Expected: FAIL because `bilibili_live_client.dart` does not exist.

- [ ] **Step 3: Add the client skeleton and parse result DTO**

Create `lib/data/sources/bilibili_live_client.dart` with:

```dart
import 'package:dio/dio.dart';

import '../../core/logger.dart';
import '../models/live_room.dart';
import '../models/track.dart';
import 'source_http_policy.dart';

class BilibiliLiveUrlParseResult {
  const BilibiliLiveUrlParseResult({
    required this.roomId,
    required this.normalizedUrl,
  });

  final String roomId;
  final String normalizedUrl;
}

class BilibiliLiveStream {
  const BilibiliLiveStream({
    required this.url,
    this.headers,
    this.expiresAt,
  });

  final String url;
  final Map<String, String>? headers;
  final DateTime? expiresAt;
}

class BilibiliLiveRoomDetails {
  const BilibiliLiveRoomDetails({
    required this.roomId,
    required this.title,
    this.thumbnailUrl,
    this.hostName,
    this.hostAvatarUrl,
    this.hostUid,
    this.viewerCount,
    this.liveStartTime,
    this.isLive = false,
    this.description,
    this.tags,
    this.announcement,
    this.areaName,
    this.parentAreaName,
  });

  final String roomId;
  final String title;
  final String? thumbnailUrl;
  final String? hostName;
  final String? hostAvatarUrl;
  final int? hostUid;
  final int? viewerCount;
  final DateTime? liveStartTime;
  final bool isLive;
  final String? description;
  final String? tags;
  final String? announcement;
  final String? areaName;
  final String? parentAreaName;

  LiveRoom toLiveRoom() {
    final parsedRoomId = int.tryParse(roomId) ?? 0;
    return LiveRoom(
      roomId: parsedRoomId,
      uid: hostUid ?? 0,
      uname: hostName ?? '',
      title: title,
      cover: thumbnailUrl,
      face: hostAvatarUrl,
      isLive: isLive,
      online: viewerCount,
      areaName: areaName,
      tags: tags,
      liveStatus: isLive ? LiveStatus.live : LiveStatus.offline,
    );
  }
}

class BilibiliMedalWallRoom {
  const BilibiliMedalWallRoom({
    required this.roomId,
    required this.name,
    this.avatarUrl,
    required this.uid,
    required this.liveStatus,
    required this.link,
  });

  final String roomId;
  final String name;
  final String? avatarUrl;
  final int uid;
  final int liveStatus;
  final String link;

  bool get isLive => liveStatus == 1;
}

class BilibiliLiveClient with Logging {
  BilibiliLiveClient({
    Dio? apiDio,
    Dio? liveDio,
    Options? searchOptions,
    String apiBase = _defaultApiBase,
    String liveApiBase = _defaultLiveApiBase,
  })  : _apiDio = apiDio ?? SourceHttpPolicy.createApiDio(SourceType.bilibili),
        _liveDio = liveDio ?? SourceHttpPolicy.createBilibiliLiveDio(),
        _ownsApiDio = apiDio == null,
        _ownsLiveDio = liveDio == null,
        _searchOptions = searchOptions,
        _searchApi = '$apiBase/x/web-interface/search/type',
        _roomInfoApi = '$liveApiBase/room/v1/Room/get_info',
        _anchorInfoApi = '$liveApiBase/live_user/v1/UserInfo/get_anchor_in_room',
        _roomNewsApi = '$liveApiBase/room_ex/v1/RoomNews/get',
        _playUrlApi = '$liveApiBase/room/v1/Room/playUrl',
        _roomInitApi = '$liveApiBase/room/v1/Room/room_init',
        _onlineGoldRankApi =
            '$liveApiBase/xlive/general-interface/v1/rank/getOnlineGoldRank',
        _medalWallApi = '$liveApiBase/xlive/web-ucenter/user/MedalWall',
        _oldRoomInfoApi = '$liveApiBase/room/v1/Room/getRoomInfoOld';

  static const String _defaultApiBase = 'https://api.bilibili.com';
  static const String _defaultLiveApiBase = 'https://api.live.bilibili.com';

  final Dio _apiDio;
  final Dio _liveDio;
  final bool _ownsApiDio;
  final bool _ownsLiveDio;
  final Options? _searchOptions;
  final String _searchApi;
  final String _roomInfoApi;
  final String _anchorInfoApi;
  final String _roomNewsApi;
  final String _playUrlApi;
  final String _roomInitApi;
  final String _onlineGoldRankApi;
  final String _medalWallApi;
  final String _oldRoomInfoApi;

  BilibiliLiveUrlParseResult? parseLiveUrl(String url) {
    final match = RegExp(
      r'live\.bilibili\.com(?:/h5)?/(\d+)',
      caseSensitive: false,
    ).firstMatch(url);
    if (match == null) return null;

    final roomId = match.group(1)!;
    return BilibiliLiveUrlParseResult(
      roomId: roomId,
      normalizedUrl: 'https://live.bilibili.com/$roomId',
    );
  }

  Future<String> resolveRealRoomId(String roomId) async {
    try {
      final response = await _liveDio.get(
        _roomInitApi,
        queryParameters: {'id': roomId},
      );
      if (response.data['code'] == 0) {
        return response.data['data']['room_id'].toString();
      }
    } catch (e) {
      logWarning('Failed to get real room ID for $roomId: $e');
    }
    return roomId;
  }

  void dispose() {
    if (_ownsApiDio) _apiDio.close();
    if (_ownsLiveDio) _liveDio.close();
  }
}
```

- [ ] **Step 4: Run parsing tests and confirm they pass**

Run:

```bash
flutter test test/data/sources/bilibili_live_client_test.dart --plain-name "parseLiveUrl"
```

Expected: PASS.

- [ ] **Step 5: Write failing real room ID tests**

Add:

```dart
group('resolveRealRoomId', () {
  test('returns API room_id', () async {
    final requests = <RequestOptions>[];
    final liveDio = dioWith((options, _) {
      requests.add(options);
      expect(options.path, endsWith('/room/v1/Room/room_init'));
      expect(options.queryParameters['id'], '123');
      return jsonResponse({
        'code': 0,
        'data': {'room_id': 456},
      });
    });
    final client = BilibiliLiveClient(apiDio: Dio(), liveDio: liveDio);

    await expectLater(client.resolveRealRoomId('123'), completion('456'));
    expect(requests, hasLength(1));
  });

  test('falls back to input when request fails', () async {
    final liveDio = dioWith((options, _) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    });
    final client = BilibiliLiveClient(apiDio: Dio(), liveDio: liveDio);

    await expectLater(client.resolveRealRoomId('123'), completion('123'));
  });
});
```

- [ ] **Step 6: Run real room ID tests and confirm they pass**

Run:

```bash
flutter test test/data/sources/bilibili_live_client_test.dart --plain-name "resolveRealRoomId"
```

Expected: PASS.

- [ ] **Step 7: Version-control checkpoint**

Do not commit unless the user has explicitly approved commits for this execution. If commits are approved, run:

```bash
git add lib/data/sources/bilibili_live_client.dart test/data/sources/bilibili_live_client_test.dart
git commit -m "refactor: add Bilibili live client skeleton"
```

Expected without commit approval: no command is run.

## Task 2: Room Details And High-Energy Count

**Files:**
- Modify: `lib/data/sources/bilibili_live_client.dart`
- Modify: `test/data/sources/bilibili_live_client_test.dart`

- [ ] **Step 1: Write failing room detail composition test**

Add:

```dart
group('getRoomInfo', () {
  test('combines room info, anchor info, and room news', () async {
    final paths = <String>[];
    final liveDio = dioWith((options, _) {
      paths.add(options.path);
      if (options.path.endsWith('/room/v1/Room/room_init')) {
        expect(options.queryParameters['id'], '456');
        return jsonResponse({
          'code': 0,
          'data': {'room_id': 456},
        });
      }
      if (options.path.endsWith('/room/v1/Room/get_info')) {
        expect(options.queryParameters['room_id'], '456');
        return jsonResponse({
          'code': 0,
          'data': {
            'room_id': 456,
            'uid': 42,
            'title': 'Live title',
            'user_cover': '//cover.example/live.jpg',
            'keyframe': '//cover.example/key.jpg',
            'online': 321,
            'live_status': 1,
            'live_time': '2026-06-08 12:30:00',
            'description': 'Room description',
            'tags': 'music',
            'area_name': 'Singing',
            'parent_area_name': 'Entertainment',
          },
        });
      }
      if (options.path.endsWith('/live_user/v1/UserInfo/get_anchor_in_room')) {
        expect(options.queryParameters['roomid'], '456');
        return jsonResponse({
          'code': 0,
          'data': {
            'info': {'uname': 'Anchor', 'face': '//face.example/a.jpg', 'uid': 42},
          },
        });
      }
      if (options.path.endsWith('/room_ex/v1/RoomNews/get')) {
        expect(options.queryParameters['roomid'], '456');
        return jsonResponse({
          'code': 0,
          'data': {'content': 'Announcement'},
        });
      }
      throw StateError('unexpected path: ${options.path}');
    });
    final client = BilibiliLiveClient(apiDio: Dio(), liveDio: liveDio);

    final info = await client.getRoomInfo('456');

    expect(info?.roomId, '456');
    expect(info?.title, 'Live title');
    expect(info?.thumbnailUrl, 'https://cover.example/live.jpg');
    expect(info?.hostName, 'Anchor');
    expect(info?.hostAvatarUrl, 'https://face.example/a.jpg');
    expect(info?.hostUid, 42);
    expect(info?.viewerCount, 321);
    expect(info?.isLive, isTrue);
    expect(info?.description, 'Room description');
    expect(info?.tags, 'music');
    expect(info?.announcement, 'Announcement');
    expect(info?.areaName, 'Singing');
    expect(info?.parentAreaName, 'Entertainment');
    expect(paths, hasLength(4));
  });
});
```

- [ ] **Step 2: Run the room detail test and confirm it fails**

Run:

```bash
flutter test test/data/sources/bilibili_live_client_test.dart --plain-name "combines room info, anchor info, and room news"
```

Expected: FAIL because `getRoomInfo()` is not defined.

- [ ] **Step 3: Implement room detail lookup**

Add these methods inside `BilibiliLiveClient`:

```dart
Future<BilibiliLiveRoomDetails?> getRoomInfo(String roomId) async {
  try {
    final realRoomId = await resolveRealRoomId(roomId);
    final roomResponse = await _liveDio.get(
      _roomInfoApi,
      queryParameters: {'room_id': realRoomId},
    );

    if (roomResponse.data['code'] != 0) return null;

    final data = roomResponse.data['data'] as Map<String, dynamic>;
    final anchor = await _getAnchorInfo(realRoomId);
    final announcement = await _getRoomNews(realRoomId);

    return BilibiliLiveRoomDetails(
      roomId: (data['room_id'] ?? realRoomId).toString(),
      title: data['title'] as String? ?? '',
      thumbnailUrl: _fixImageUrl(
        data['user_cover'] as String? ?? data['keyframe'] as String?,
      ),
      hostName: anchor.name,
      hostAvatarUrl: _fixImageUrl(anchor.avatarUrl),
      hostUid: anchor.uid ?? data['uid'] as int?,
      viewerCount: data['online'] as int?,
      liveStartTime: _parseLiveStartTime(data['live_time']),
      isLive: data['live_status'] == 1,
      description: _nonEmptyString(data['description']),
      tags: _nonEmptyString(data['tags']),
      announcement: announcement,
      areaName: data['area_name'] as String?,
      parentAreaName: data['parent_area_name'] as String?,
    );
  } on DioException catch (e) {
    logError('Failed to get live room info for $roomId: ${e.message}');
    return null;
  }
}

Future<_AnchorInfo> _getAnchorInfo(String roomId) async {
  try {
    final response = await _liveDio.get(
      _anchorInfoApi,
      queryParameters: {'roomid': roomId},
    );
    if (response.data['code'] == 0) {
      final info = response.data['data']?['info'] as Map<String, dynamic>?;
      return _AnchorInfo(
        name: info?['uname'] as String?,
        avatarUrl: info?['face'] as String?,
        uid: info?['uid'] as int?,
      );
    }
  } catch (e) {
    logWarning('Failed to get anchor info for room $roomId: $e');
  }
  return const _AnchorInfo();
}

Future<String?> _getRoomNews(String roomId) async {
  try {
    final response = await _liveDio.get(
      _roomNewsApi,
      queryParameters: {'roomid': roomId},
    );
    if (response.data['code'] == 0) {
      return _nonEmptyString(response.data['data']?['content']);
    }
  } catch (e) {
    logWarning('Failed to get room news for room $roomId: $e');
  }
  return null;
}

DateTime? _parseLiveStartTime(Object? value) {
  if (value is int && value > 0) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }
  if (value is String && value != '0000-00-00 00:00:00') {
    try {
      return DateTime.parse(value.replaceFirst(' ', 'T'));
    } catch (_) {
      return null;
    }
  }
  return null;
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return text;
}

String? _fixImageUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('//')) return 'https:$url';
  return url;
}
```

Add this private DTO after `BilibiliMedalWallRoom`:

```dart
class _AnchorInfo {
  const _AnchorInfo({this.name, this.avatarUrl, this.uid});

  final String? name;
  final String? avatarUrl;
  final int? uid;
}
```

- [ ] **Step 4: Run the room detail test and confirm it passes**

Run:

```bash
flutter test test/data/sources/bilibili_live_client_test.dart --plain-name "combines room info, anchor info, and room news"
```

Expected: PASS.

- [ ] **Step 5: Write failing tolerance and high-energy tests**

Add:

```dart
test('keeps room info when anchor and news calls fail', () async {
  final liveDio = dioWith((options, _) {
    if (options.path.endsWith('/room/v1/Room/room_init')) {
      return jsonResponse({
        'code': 0,
        'data': {'room_id': 456},
      });
    }
    if (options.path.endsWith('/room/v1/Room/get_info')) {
      return jsonResponse({
        'code': 0,
        'data': {
          'room_id': 456,
          'uid': 42,
          'title': 'Live title',
          'online': 9,
          'live_status': 0,
        },
      });
    }
    throw DioException(requestOptions: options, error: 'secondary failure');
  });
  final client = BilibiliLiveClient(apiDio: Dio(), liveDio: liveDio);

  final info = await client.getRoomInfo('456');

  expect(info?.title, 'Live title');
  expect(info?.hostName, isNull);
  expect(info?.announcement, isNull);
  expect(info?.isLive, isFalse);
});

group('getHighEnergyUserCount', () {
  test('uses room uid and returns onlineNum', () async {
    final liveDio = dioWith((options, _) {
      if (options.path.endsWith('/room/v1/Room/room_init')) {
        return jsonResponse({
          'code': 0,
          'data': {'room_id': 456},
        });
      }
      if (options.path.endsWith('/room/v1/Room/get_info')) {
        return jsonResponse({
          'code': 0,
          'data': {'uid': 42},
        });
      }
      if (options.path.endsWith('/xlive/general-interface/v1/rank/getOnlineGoldRank')) {
        expect(options.queryParameters['ruid'], 42);
        expect(options.queryParameters['roomId'], '456');
        expect(options.queryParameters['page'], 1);
        expect(options.queryParameters['pageSize'], 1);
        return jsonResponse({
          'code': 0,
          'data': {'onlineNum': 88},
        });
      }
      throw StateError('unexpected path: ${options.path}');
    });
    final client = BilibiliLiveClient(apiDio: Dio(), liveDio: liveDio);

    await expectLater(client.getHighEnergyUserCount('456'), completion(88));
  });

  test('returns null on lookup failure', () async {
    final liveDio = dioWith((options, _) {
      throw DioException(requestOptions: options, error: 'offline');
    });
    final client = BilibiliLiveClient(apiDio: Dio(), liveDio: liveDio);

    await expectLater(client.getHighEnergyUserCount('456'), completion(isNull));
  });
});
```

- [ ] **Step 6: Implement high-energy lookup**

Add:

```dart
Future<int?> getHighEnergyUserCount(String roomId) async {
  try {
    final realRoomId = await resolveRealRoomId(roomId);
    final roomResponse = await _liveDio.get(
      _roomInfoApi,
      queryParameters: {'room_id': realRoomId},
    );
    if (roomResponse.data['code'] != 0) return null;

    final uid = roomResponse.data['data']?['uid'];
    if (uid == null) return null;

    final response = await _liveDio.get(
      _onlineGoldRankApi,
      queryParameters: {
        'ruid': uid,
        'roomId': realRoomId,
        'page': 1,
        'pageSize': 1,
      },
    );

    if (response.data['code'] == 0) {
      return response.data['data']?['onlineNum'] as int?;
    }
  } catch (e) {
    logWarning('Failed to get high energy user count: $e');
  }
  return null;
}
```

- [ ] **Step 7: Run room details and high-energy tests**

Run:

```bash
flutter test test/data/sources/bilibili_live_client_test.dart --plain-name "getRoomInfo"
flutter test test/data/sources/bilibili_live_client_test.dart --plain-name "getHighEnergyUserCount"
```

Expected: PASS for both groups.

- [ ] **Step 8: Version-control checkpoint**

Do not commit unless the user has explicitly approved commits for this execution. If commits are approved, run:

```bash
git add lib/data/sources/bilibili_live_client.dart test/data/sources/bilibili_live_client_test.dart
git commit -m "refactor: move Bilibili live room details into client"
```

Expected without commit approval: no command is run.

## Task 3: Radio And Search Stream URLs

**Files:**
- Modify: `lib/data/sources/bilibili_live_client.dart`
- Modify: `test/data/sources/bilibili_live_client_test.dart`

- [ ] **Step 1: Write failing radio stream test**

Add:

```dart
group('getRadioStream', () {
  test('uses current radio playUrl parameters and returns live headers', () async {
    final liveDio = dioWith((options, _) {
      if (options.path.endsWith('/room/v1/Room/room_init')) {
        return jsonResponse({
          'code': 0,
          'data': {'room_id': 456},
        });
      }
      expect(options.path, endsWith('/room/v1/Room/playUrl'));
      expect(options.queryParameters['cid'], '456');
      expect(options.queryParameters['platform'], 'web');
      expect(options.queryParameters['quality'], 2);
      expect(options.queryParameters['qn'], 80);
      return jsonResponse({
        'code': 0,
        'data': {
          'durl': [
            {'url': 'https://live.example/radio.flv'},
          ],
        },
      });
    });
    final client = BilibiliLiveClient(apiDio: Dio(), liveDio: liveDio);

    final stream = await client.getRadioStream('123');

    expect(stream.url, 'https://live.example/radio.flv');
    expect(stream.headers, SourceHttpPolicy.bilibiliLiveHeaders());
  });

  test('throws when playUrl returns no durl', () async {
    final liveDio = dioWith((options, _) {
      if (options.path.endsWith('/room/v1/Room/room_init')) {
        return jsonResponse({
          'code': 0,
          'data': {'room_id': 456},
        });
      }
      return jsonResponse({
        'code': 0,
        'data': {'durl': []},
      });
    });
    final client = BilibiliLiveClient(apiDio: Dio(), liveDio: liveDio);

    expect(() => client.getRadioStream('123'), throwsException);
  });
});
```

- [ ] **Step 2: Implement radio stream lookup**

Add:

```dart
Future<BilibiliLiveStream> getRadioStream(String roomId) async {
  final realRoomId = await resolveRealRoomId(roomId);
  final response = await _liveDio.get(
    _playUrlApi,
    queryParameters: {
      'cid': realRoomId,
      'platform': 'web',
      'quality': 2,
      'qn': 80,
    },
  );

  if (response.data['code'] != 0) {
    throw Exception('Failed to get stream URL: ${response.data['message']}');
  }

  final durl = response.data['data']?['durl'] as List?;
  if (durl == null || durl.isEmpty) {
    throw Exception('No stream URL available');
  }

  return BilibiliLiveStream(
    url: durl[0]['url'] as String,
    headers: SourceHttpPolicy.bilibiliLiveHeaders(),
  );
}
```

- [ ] **Step 3: Write failing search stream tests**

Add:

```dart
group('getSearchStreamUrl', () {
  test('preserves h5 quality 4 parameters', () async {
    final liveDio = dioWith((options, _) {
      expect(options.path, endsWith('/room/v1/Room/playUrl'));
      expect(options.queryParameters['cid'], 456);
      expect(options.queryParameters['platform'], 'h5');
      expect(options.queryParameters['quality'], 4);
      expect(options.queryParameters.containsKey('qn'), isFalse);
      return jsonResponse({
        'code': 0,
        'data': {
          'durl': [
            {'url': 'https://live.example/search.flv'},
          ],
        },
      });
    });
    final client = BilibiliLiveClient(apiDio: Dio(), liveDio: liveDio);

    await expectLater(
      client.getSearchStreamUrl(456),
      completion('https://live.example/search.flv'),
    );
  });

  test('returns null on playUrl failure', () async {
    final liveDio = dioWith((options, _) {
      return jsonResponse({'code': -1, 'message': 'failed'});
    });
    final client = BilibiliLiveClient(apiDio: Dio(), liveDio: liveDio);

    await expectLater(client.getSearchStreamUrl(456), completion(isNull));
  });
});
```

- [ ] **Step 4: Implement search stream lookup**

Add:

```dart
Future<String?> getSearchStreamUrl(int roomId) async {
  try {
    final response = await _liveDio.get(
      _playUrlApi,
      queryParameters: {
        'cid': roomId,
        'platform': 'h5',
        'quality': 4,
      },
    );

    if (response.data['code'] != 0) return null;

    final durl = response.data['data']?['durl'] as List?;
    if (durl == null || durl.isEmpty) return null;

    return durl[0]['url'] as String?;
  } on DioException catch (e) {
    logError('Failed to get live stream URL for room $roomId: ${e.message}');
    return null;
  }
}
```

- [ ] **Step 5: Run stream tests**

Run:

```bash
flutter test test/data/sources/bilibili_live_client_test.dart --plain-name "getRadioStream"
flutter test test/data/sources/bilibili_live_client_test.dart --plain-name "getSearchStreamUrl"
```

Expected: PASS for both groups.

- [ ] **Step 6: Version-control checkpoint**

Do not commit unless the user has explicitly approved commits for this execution. If commits are approved, run:

```bash
git add lib/data/sources/bilibili_live_client.dart test/data/sources/bilibili_live_client_test.dart
git commit -m "refactor: centralize Bilibili live stream lookup"
```

Expected without commit approval: no command is run.

## Task 4: Live Room Search And Medal Wall Lookup

**Files:**
- Modify: `lib/data/sources/bilibili_live_client.dart`
- Modify: `test/data/sources/bilibili_live_client_test.dart`

- [ ] **Step 1: Write failing live room search test**

Add:

```dart
group('searchRooms', () {
  test('merges live_room and bili_user results and enriches user rooms', () async {
    final apiDio = dioWith((options, _) {
      expect(options.path, endsWith('/x/web-interface/search/type'));
      if (options.queryParameters['search_type'] == 'live_room') {
        return jsonResponse({
          'code': 0,
          'data': {
            'numResults': 1,
            'result': [
              {
                'roomid': 100,
                'uid': 10,
                'uname': '<em>Live</em> Anchor',
                'title': '<em>Live</em> Title',
                'user_cover': '//i.example/live.jpg',
                'uface': '//i.example/face.jpg',
                'online': 12,
                'cate_name': 'Music',
                'tags': 'singing',
              },
            ],
          },
        });
      }
      if (options.queryParameters['search_type'] == 'bili_user') {
        return jsonResponse({
          'code': 0,
          'data': {
            'numResults': 1,
            'result': [
              {
                'room_id': 200,
                'mid': 20,
                'uname': 'Offline Anchor',
                'upic': '//i.example/offline-face.jpg',
              },
            ],
          },
        });
      }
      throw StateError('unexpected search type');
    });
    final liveDio = dioWith((options, _) {
      if (options.path.endsWith('/room/v1/Room/room_init')) {
        return jsonResponse({
          'code': 0,
          'data': {'room_id': 200},
        });
      }
      if (options.path.endsWith('/room/v1/Room/get_info')) {
        return jsonResponse({
          'code': 0,
          'data': {
            'room_id': 200,
            'uid': 20,
            'title': 'Offline Room',
            'live_status': 0,
          },
        });
      }
      if (options.path.endsWith('/live_user/v1/UserInfo/get_anchor_in_room')) {
        return jsonResponse({'code': -1});
      }
      if (options.path.endsWith('/room_ex/v1/RoomNews/get')) {
        return jsonResponse({'code': -1});
      }
      throw StateError('unexpected path: ${options.path}');
    });
    final client = BilibiliLiveClient(apiDio: apiDio, liveDio: liveDio);

    final result = await client.searchRooms('music');

    expect(result.rooms.map((room) => room.roomId), [100, 200]);
    expect(result.rooms.first.title, 'Live Title');
    expect(result.rooms.last.uname, 'Offline Anchor');
    expect(result.rooms.last.face, 'https://i.example/offline-face.jpg');
    expect(result.rooms.last.isLive, isFalse);
  });

  test('offline filter only returns non-live user rooms', () async {
    final apiDio = dioWith((options, _) {
      expect(options.queryParameters['search_type'], 'bili_user');
      return jsonResponse({
        'code': 0,
        'data': {
          'numResults': 1,
          'result': [
            {'room_id': 200, 'mid': 20, 'uname': 'Offline Anchor'},
          ],
        },
      });
    });
    final liveDio = dioWith((options, _) {
      if (options.path.endsWith('/room/v1/Room/room_init')) {
        return jsonResponse({
          'code': 0,
          'data': {'room_id': 200},
        });
      }
      if (options.path.endsWith('/room/v1/Room/get_info')) {
        return jsonResponse({
          'code': 0,
          'data': {'room_id': 200, 'uid': 20, 'title': 'Offline Room', 'live_status': 0},
        });
      }
      return jsonResponse({'code': -1});
    });
    final client = BilibiliLiveClient(apiDio: apiDio, liveDio: liveDio);

    final result = await client.searchRooms(
      'music',
      filter: LiveRoomFilter.offline,
    );

    expect(result.rooms, hasLength(1));
    expect(result.rooms.single.isLive, isFalse);
  });
});
```

- [ ] **Step 2: Implement searchRooms and helpers**

Add:

```dart
Future<LiveSearchResult> searchRooms(
  String query, {
  int page = 1,
  int pageSize = 20,
  LiveRoomFilter filter = LiveRoomFilter.all,
}) async {
  switch (filter) {
    case LiveRoomFilter.all:
      final results = await Future.wait([
        _searchLiveRoomApi(query, page, pageSize),
        _searchBiliUserWithRoomApi(query, page, pageSize),
      ]);
      return results[0].merge(results[1]);
    case LiveRoomFilter.offline:
      final userResults =
          await _searchBiliUserWithRoomApi(query, page, pageSize);
      return userResults.filter(LiveRoomFilter.offline);
    case LiveRoomFilter.online:
      final results = await Future.wait([
        _searchLiveRoomApi(query, page, pageSize),
        _searchBiliUserWithRoomApi(query, page, pageSize),
      ]);
      return results[0].merge(results[1]).filter(LiveRoomFilter.online);
  }
}

Future<LiveSearchResult> _searchLiveRoomApi(
  String query,
  int page,
  int pageSize,
) async {
  final response = await _apiDio.get(
    _searchApi,
    queryParameters: {
      'keyword': query,
      'search_type': 'live_room',
      'page': page,
      'page_size': pageSize,
    },
    options: _searchOptions,
  );

  _checkSuccess(response.data);
  final data = response.data['data'] as Map<String, dynamic>;
  final results = data['result'] as List? ?? const [];
  final total = data['numResults'] as int? ?? 0;

  return LiveSearchResult(
    rooms: results
        .whereType<Map<String, dynamic>>()
        .map(LiveRoom.fromLiveRoomSearch)
        .toList(),
    totalCount: total,
    page: page,
    pageSize: pageSize,
    hasMore: page * pageSize < total,
  );
}

Future<LiveSearchResult> _searchBiliUserWithRoomApi(
  String query,
  int page,
  int pageSize,
) async {
  final response = await _apiDio.get(
    _searchApi,
    queryParameters: {
      'keyword': query,
      'search_type': 'bili_user',
      'page': page,
      'page_size': pageSize,
    },
    options: _searchOptions,
  );

  _checkSuccess(response.data);
  final data = response.data['data'] as Map<String, dynamic>;
  final results = data['result'] as List? ?? const [];
  final total = data['numResults'] as int? ?? 0;
  final rooms = <LiveRoom>[];

  for (final item in results.whereType<Map<String, dynamic>>()) {
    final roomId = item['room_id'] as int? ?? 0;
    if (roomId <= 0) continue;

    final uname = _cleanHtmlTags(item['uname'] as String? ?? '');
    final face = _fixImageUrl(item['upic'] as String?);
    try {
      final details = await getRoomInfo(roomId.toString());
      if (details == null) {
        rooms.add(LiveRoom.fromBiliUserSearch(item));
      } else {
        rooms.add(details.toLiveRoom().copyWith(
              uname: uname.isNotEmpty ? uname : details.hostName,
              face: face ?? details.hostAvatarUrl,
            ));
      }
    } catch (e) {
      logDebug('Failed to get room info for $roomId: $e');
      rooms.add(LiveRoom.fromBiliUserSearch(item));
    }
  }

  return LiveSearchResult(
    rooms: rooms,
    totalCount: total,
    page: page,
    pageSize: pageSize,
    hasMore: page * pageSize < total,
  );
}

void _checkSuccess(Object? body) {
  if (body is Map && body['code'] == 0) return;
  final message = body is Map ? body['message'] : body;
  throw Exception('Bilibili live API error: $message');
}

String _cleanHtmlTags(String text) {
  return text.replaceAll(RegExp(r'<[^>]*>'), '');
}
```

- [ ] **Step 3: Write failing medal wall tests**

Add:

```dart
group('getMedalWallRooms', () {
  test('maps medal wall entries and skips failed room lookups', () async {
    final liveDio = dioWith((options, _) {
      if (options.path.endsWith('/xlive/web-ucenter/user/MedalWall')) {
        expect(options.queryParameters['target_id'], '99');
        expect(options.headers['Cookie'], 'SESSDATA=abc');
        return jsonResponse({
          'code': 0,
          'data': {
            'list': [
              {
                'target_name': 'Anchor A',
                'target_icon': 'https://face.example/a.jpg',
                'live_status': 1,
                'medal_info': {'target_id': 42},
              },
              {
                'target_name': 'Anchor B',
                'target_icon': 'https://face.example/b.jpg',
                'live_status': 0,
                'medal_info': {'target_id': 43},
              },
            ],
          },
        });
      }
      if (options.path.endsWith('/room/v1/Room/getRoomInfoOld')) {
        if (options.queryParameters['mid'] == 42) {
          return jsonResponse({
            'code': 0,
            'data': {'roomid': 12345},
          });
        }
        return jsonResponse({'code': -1});
      }
      throw StateError('unexpected path: ${options.path}');
    });
    final client = BilibiliLiveClient(apiDio: Dio(), liveDio: liveDio);

    final rooms = await client.getMedalWallRooms(
      targetId: '99',
      cookie: 'SESSDATA=abc',
    );

    expect(rooms, hasLength(1));
    expect(rooms.single.roomId, '12345');
    expect(rooms.single.name, 'Anchor A');
    expect(rooms.single.avatarUrl, 'https://face.example/a.jpg');
    expect(rooms.single.uid, 42);
    expect(rooms.single.liveStatus, 1);
    expect(rooms.single.link, 'https://live.bilibili.com/12345');
  });
});
```

- [ ] **Step 4: Implement medal wall lookup**

Add:

```dart
Future<List<BilibiliMedalWallRoom>> getMedalWallRooms({
  required String targetId,
  required String cookie,
}) async {
  final response = await _liveDio.get(
    _medalWallApi,
    queryParameters: {'target_id': targetId},
    options: Options(headers: {'Cookie': cookie}),
  );

  final code = response.data['code'] as int?;
  if (code != 0) {
    throw Exception('MedalWall API error: ${response.data['message']}');
  }

  final list = response.data['data']?['list'] as List? ?? const [];
  final futures = list.map((item) async {
    if (item is! Map<String, dynamic>) return null;
    final medalInfo = item['medal_info'] as Map<String, dynamic>?;
    if (medalInfo == null) return null;

    final uid = medalInfo['target_id'] as int? ?? 0;
    if (uid == 0) return null;

    try {
      final roomResponse = await _liveDio.get(
        _oldRoomInfoApi,
        queryParameters: {'mid': uid},
      );
      if (roomResponse.data['code'] != 0) return null;

      final roomId = roomResponse.data['data']?['roomid']?.toString();
      if (roomId == null || roomId == '0') return null;

      return BilibiliMedalWallRoom(
        roomId: roomId,
        name: item['target_name'] as String? ?? '',
        avatarUrl: item['target_icon'] as String?,
        uid: uid,
        liveStatus: item['live_status'] as int? ?? 0,
        link: 'https://live.bilibili.com/$roomId',
      );
    } catch (_) {
      return null;
    }
  }).toList();

  final rooms = await Future.wait(futures);
  return rooms.whereType<BilibiliMedalWallRoom>().toList();
}
```

- [ ] **Step 5: Run search and medal wall tests**

Run:

```bash
flutter test test/data/sources/bilibili_live_client_test.dart --plain-name "searchRooms"
flutter test test/data/sources/bilibili_live_client_test.dart --plain-name "getMedalWallRooms"
```

Expected: PASS for both groups.

- [ ] **Step 6: Version-control checkpoint**

Do not commit unless the user has explicitly approved commits for this execution. If commits are approved, run:

```bash
git add lib/data/sources/bilibili_live_client.dart test/data/sources/bilibili_live_client_test.dart
git commit -m "refactor: move Bilibili live search and medal wall lookup"
```

Expected without commit approval: no command is run.

## Task 5: Wire BilibiliSource As A Thin Adapter

**Files:**
- Modify: `lib/data/sources/bilibili_source.dart`
- Modify: `test/bilibili_source_test.dart` if existing constructor-based tests need new injection coverage
- Run: `test/providers/search_pagination_stale_test.dart`

- [ ] **Step 1: Write failing adapter injection test**

Add a small test in `test/bilibili_source_test.dart` near existing constructor tests:

```dart
test('searchLiveRooms delegates to injected live client', () async {
  final apiDio = Dio();
  final liveDio = Dio();
  final source = BilibiliSource(
    dio: apiDio,
    liveDio: liveDio,
    liveClient: _FakeBilibiliLiveClient(
      searchResult: const LiveSearchResult(
        rooms: [
          LiveRoom(
            roomId: 123,
            uid: 42,
            uname: 'Anchor',
            title: 'Room',
            isLive: true,
          ),
        ],
        totalCount: 1,
        page: 1,
        pageSize: 20,
        hasMore: false,
      ),
    ),
  );

  final result = await source.searchLiveRooms('anchor');

  expect(result.rooms.single.roomId, 123);
});
```

Add this fake near test helpers:

```dart
class _FakeBilibiliLiveClient extends BilibiliLiveClient {
  _FakeBilibiliLiveClient({required this.searchResult})
      : super(apiDio: Dio(), liveDio: Dio());

  final LiveSearchResult searchResult;

  @override
  Future<LiveSearchResult> searchRooms(
    String query, {
    int page = 1,
    int pageSize = 20,
    LiveRoomFilter filter = LiveRoomFilter.all,
  }) async {
    return searchResult;
  }
}
```

- [ ] **Step 2: Run the adapter injection test and confirm it fails**

Run:

```bash
flutter test test/bilibili_source_test.dart --plain-name "searchLiveRooms delegates to injected live client"
```

Expected: FAIL because `BilibiliSource` has no `liveClient` constructor parameter.

- [ ] **Step 3: Modify BilibiliSource constructor and fields**

In `lib/data/sources/bilibili_source.dart`:

```dart
import 'bilibili_live_client.dart';
```

Add fields:

```dart
late final BilibiliLiveClient _liveClient;
late final bool _ownsLiveClient;
```

Change the constructor signature:

```dart
BilibiliSource({
  Dio? dio,
  Dio? liveDio,
  BilibiliLiveClient? liveClient,
  String apiBase = _defaultApiBase,
  String liveApiBase = _defaultLiveApiBase,
}) {
```

After `_liveDio` and `_searchOptions` initialization, add:

```dart
_liveClient = liveClient ??
    BilibiliLiveClient(
      apiDio: _dio,
      liveDio: _liveDio,
      searchOptions: _searchOptions,
      apiBase: apiBase,
      liveApiBase: liveApiBase,
    );
_ownsLiveClient = liveClient == null;
```

- [ ] **Step 4: Replace BilibiliSource live methods with delegations**

Replace the bodies of the public live methods:

```dart
Future<LiveSearchResult> searchLiveRooms(
  String query, {
  int page = 1,
  int pageSize = 20,
  LiveRoomFilter filter = LiveRoomFilter.all,
}) async {
  try {
    return await _liveClient.searchRooms(
      query,
      page: page,
      pageSize: pageSize,
      filter: filter,
    );
  } on DioException catch (e) {
    throw _handleDioError(e);
  } catch (e) {
    if (e is BilibiliApiException) rethrow;
    logError('Unexpected error in searchLiveRooms: $e');
    throw BilibiliApiException(numericCode: -999, message: e.toString());
  }
}

Future<LiveRoom?> getLiveRoomInfo(int roomId) async {
  final details = await _liveClient.getRoomInfo(roomId.toString());
  return details?.toLiveRoom();
}

Future<String?> getLiveStreamUrl(int roomId) {
  return _liveClient.getSearchStreamUrl(roomId);
}
```

Delete the old private live helper methods from `BilibiliSource` after the public methods delegate:

```text
_searchLiveRoomApi
_searchBiliUserWithRoomApi
```

Also remove unused endpoint fields:

```text
_liveRoomInfoApi
_livePlayUrlApi
_liveAnchorInfoApi
```

- [ ] **Step 5: Update dispose ownership**

Change `dispose()` to:

```dart
void dispose() {
  if (_ownsLiveClient) {
    _liveClient.dispose();
  }
  _dio.close();
  if (!identical(_liveDio, _dio)) {
    _liveDio.close();
  }
}
```

Because `BilibiliLiveClient` was injected with `_dio` and `_liveDio`, its `_ownsApiDio` and `_ownsLiveDio` are false in the default `BilibiliSource` path. Closing the source-owned Dio fields remains the source's job.

- [ ] **Step 6: Run BilibiliSource and search stale tests**

Run:

```bash
flutter test test/bilibili_source_test.dart --plain-name "searchLiveRooms delegates to injected live client"
flutter test test/providers/search_pagination_stale_test.dart
```

Expected: PASS.

- [ ] **Step 7: Version-control checkpoint**

Do not commit unless the user has explicitly approved commits for this execution. If commits are approved, run:

```bash
git add lib/data/sources/bilibili_source.dart test/bilibili_source_test.dart
git commit -m "refactor: delegate Bilibili source live helpers"
```

Expected without commit approval: no command is run.

## Task 6: Wire RadioSource As A Thin Adapter

**Files:**
- Modify: `lib/services/radio/radio_source.dart`
- Run: `test/services/radio`

- [ ] **Step 1: Add test seam by constructor injection**

No existing radio source unit test directly constructs `RadioSource` with fake live HTTP responses. Add `test/services/radio/radio_source_live_client_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/bilibili_live_client.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/services/radio/radio_source.dart';

void main() {
  test('createStationFromUrl maps live client room info to RadioStation', () async {
    final source = RadioSource(
      liveClient: _FakeBilibiliLiveClient(
        details: const BilibiliLiveRoomDetails(
          roomId: '123',
          title: 'Room title',
          thumbnailUrl: 'https://cover.example/room.jpg',
          hostName: 'Anchor',
          hostAvatarUrl: 'https://face.example/a.jpg',
          hostUid: 42,
          isLive: true,
        ),
      ),
    );

    final station = await source.createStationFromUrl(
      'https://live.bilibili.com/h5/123',
    );

    expect(station.sourceType, SourceType.bilibili);
    expect(station.sourceId, '123');
    expect(station.url, 'https://live.bilibili.com/123');
    expect(station.title, 'Room title');
    expect(station.thumbnailUrl, 'https://cover.example/room.jpg');
    expect(station.hostName, 'Anchor');
    expect(station.hostAvatarUrl, 'https://face.example/a.jpg');
    expect(station.hostUid, 42);
  });

  test('getStreamUrl maps live client stream to radio stream info', () async {
    final source = RadioSource(
      liveClient: _FakeBilibiliLiveClient(
        stream: BilibiliLiveStream(
          url: 'https://live.example/radio.flv',
          headers: SourceHttpPolicy.bilibiliLiveHeaders(),
        ),
      ),
    );
    final station = RadioStation()
      ..sourceId = '123'
      ..sourceType = SourceType.bilibili;

    final stream = await source.getStreamUrl(station);

    expect(stream.url, 'https://live.example/radio.flv');
    expect(stream.headers, SourceHttpPolicy.bilibiliLiveHeaders());
  });

  test('getHighEnergyUserCount delegates room id lookup', () async {
    final source = RadioSource(
      liveClient: _FakeBilibiliLiveClient(highEnergyCount: 77),
    );
    final station = RadioStation()
      ..sourceId = '123'
      ..sourceType = SourceType.bilibili;

    await expectLater(source.getHighEnergyUserCount(station), completion(77));
  });
}

class _FakeBilibiliLiveClient extends BilibiliLiveClient {
  _FakeBilibiliLiveClient({
    this.details,
    this.stream,
    this.highEnergyCount,
  }) : super(apiDio: Dio(), liveDio: Dio());

  final BilibiliLiveRoomDetails? details;
  final BilibiliLiveStream? stream;
  final int? highEnergyCount;

  @override
  BilibiliLiveUrlParseResult? parseLiveUrl(String url) {
    return const BilibiliLiveUrlParseResult(
      roomId: '123',
      normalizedUrl: 'https://live.bilibili.com/123',
    );
  }

  @override
  Future<BilibiliLiveRoomDetails?> getRoomInfo(String roomId) async {
    return details;
  }

  @override
  Future<BilibiliLiveStream> getRadioStream(String roomId) async {
    return stream ?? const BilibiliLiveStream(url: 'https://live.example/default.flv');
  }

  @override
  Future<int?> getHighEnergyUserCount(String roomId) async {
    return highEnergyCount;
  }
}
```

- [ ] **Step 2: Run the new radio adapter tests and confirm they fail**

Run:

```bash
flutter test test/services/radio/radio_source_live_client_test.dart
```

Expected: FAIL because `RadioSource` has no `liveClient` constructor parameter.

- [ ] **Step 3: Modify RadioSource constructor and remove endpoint ownership**

In `lib/services/radio/radio_source.dart`, replace the Dio import and policy import with:

```dart
import '../../data/sources/bilibili_live_client.dart';
```

Keep `SourceType` import through `track.dart`. Remove `_dio` and the Bilibili live endpoint constants from `RadioSource`.

Add fields and constructor:

```dart
late final BilibiliLiveClient _liveClient;
late final bool _ownsLiveClient;

RadioSource({BilibiliLiveClient? liveClient}) {
  _liveClient = liveClient ?? BilibiliLiveClient();
  _ownsLiveClient = liveClient == null;
}
```

- [ ] **Step 4: Replace RadioSource methods with client-backed mappings**

Keep `isYouTubeUrl()` unchanged. Replace the public method bodies:

```dart
ParseResult? parseUrl(String url) {
  if (isYouTubeUrl(url)) return null;
  final parsed = _liveClient.parseLiveUrl(url);
  if (parsed == null) return null;
  return ParseResult(
    sourceId: parsed.roomId,
    normalizedUrl: parsed.normalizedUrl,
  );
}

Future<LiveRoomInfo> getLiveInfo(RadioStation station) async {
  final details = await _liveClient.getRoomInfo(station.sourceId);
  if (details == null) {
    throw Exception('Failed to get room info: ${station.sourceId}');
  }
  return LiveRoomInfo(
    title: details.title,
    thumbnailUrl: details.thumbnailUrl,
    hostName: details.hostName,
    hostAvatarUrl: details.hostAvatarUrl,
    hostUid: details.hostUid,
    viewerCount: details.viewerCount,
    liveStartTime: details.liveStartTime,
    isLive: details.isLive,
    description: details.description,
    tags: details.tags,
    announcement: details.announcement,
    areaName: details.areaName,
    parentAreaName: details.parentAreaName,
  );
}

Future<int?> getHighEnergyUserCount(RadioStation station) {
  return _liveClient.getHighEnergyUserCount(station.sourceId);
}

Future<LiveStreamInfo> getStreamUrl(RadioStation station) async {
  final stream = await _liveClient.getRadioStream(station.sourceId);
  return LiveStreamInfo(
    url: stream.url,
    headers: stream.headers,
    expiresAt: stream.expiresAt,
  );
}

Future<bool> isLive(RadioStation station) async {
  try {
    final info = await getLiveInfo(station);
    return info.isLive;
  } catch (e) {
    return false;
  }
}

void dispose() {
  if (_ownsLiveClient) _liveClient.dispose();
}
```

Leave `createStationFromUrl()` behavior intact except that it now calls delegated `parseUrl()` and `getLiveInfo()`.

- [ ] **Step 5: Run radio tests**

Run:

```bash
flutter test test/services/radio/radio_source_live_client_test.dart
flutter test test/services/radio
```

Expected: PASS.

- [ ] **Step 6: Version-control checkpoint**

Do not commit unless the user has explicitly approved commits for this execution. If commits are approved, run:

```bash
git add lib/services/radio/radio_source.dart test/services/radio/radio_source_live_client_test.dart
git commit -m "refactor: delegate radio live API calls"
```

Expected without commit approval: no command is run.

## Task 7: Wire BilibiliAccountService Medal Wall Lookup

**Files:**
- Modify: `lib/services/account/bilibili_account_service.dart`
- Modify: `test/services/account/bilibili_account_live_policy_test.dart`
- Run: `test/services/account`

- [ ] **Step 1: Add account service constructor injection**

Change imports in `lib/services/account/bilibili_account_service.dart`:

```dart
import '../../data/sources/bilibili_live_client.dart';
```

Keep the existing `source_http_policy.dart` import because the account API Dio still uses `SourceHttpPolicy.createApiDio()`. Add fields:

```dart
final BilibiliLiveClient _liveClient;
```

Change the constructor:

```dart
BilibiliAccountService({
  required Isar isar,
  BilibiliLiveClient? liveClient,
})  : _isar = isar,
      _secureStorage = const FlutterSecureStorage(),
      _dio = SourceHttpPolicy.createApiDio(SourceType.bilibili),
      _liveClient = liveClient ?? BilibiliLiveClient();
```

Remove `_liveDio` and `_liveApiBase` if they are no longer used.

- [ ] **Step 2: Replace fetchMedalWall body with delegation**

Replace `fetchMedalWall()` with:

```dart
Future<List<MedalWallItem>> fetchMedalWall() async {
  final cookieString = await getAuthCookieString();
  if (cookieString == null) throw Exception('Not logged in');

  final mid = await getUserMid();
  if (mid == null) throw Exception('User mid not available');

  final rooms = await _liveClient.getMedalWallRooms(
    targetId: mid,
    cookie: cookieString,
  );

  return rooms
      .map(
        (room) => MedalWallItem(
          roomId: room.roomId,
          name: room.name,
          avatarUrl: room.avatarUrl,
          uid: room.uid,
          liveStatus: room.liveStatus,
          link: room.link,
        ),
      )
      .toList();
}
```

- [ ] **Step 3: Update static policy test**

Change `test/services/account/bilibili_account_live_policy_test.dart` to:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bilibili account live imports delegate live lookup to client', () {
    final accountSource = File('lib/services/account/bilibili_account_service.dart')
        .readAsStringSync();
    final liveClientSource =
        File('lib/data/sources/bilibili_live_client.dart').readAsStringSync();

    expect(accountSource, contains('BilibiliLiveClient'));
    expect(accountSource, contains('getMedalWallRooms'));
    expect(accountSource, isNot(contains('getRoomInfoOld')));
    expect(liveClientSource, contains('SourceHttpPolicy.createBilibiliLiveDio'));
    expect(liveClientSource, contains('MedalWall'));
    expect(liveClientSource, contains('getRoomInfoOld'));
  });
}
```

- [ ] **Step 4: Run account tests**

Run:

```bash
flutter test test/services/account/bilibili_account_live_policy_test.dart
flutter test test/services/account
```

Expected: PASS.

- [ ] **Step 5: Version-control checkpoint**

Do not commit unless the user has explicitly approved commits for this execution. If commits are approved, run:

```bash
git add lib/services/account/bilibili_account_service.dart test/services/account/bilibili_account_live_policy_test.dart
git commit -m "refactor: delegate Bilibili medal wall live lookup"
```

Expected without commit approval: no command is run.

## Task 8: Static Policy Tests, Documentation, And Verification

**Files:**
- Modify: `test/services/radio/radio_source_http_policy_usage_test.dart`
- Modify: `lib/data/sources/AGENTS.md`
- Modify: `lib/services/AGENTS.md`

- [ ] **Step 1: Update radio static policy tests**

Replace the first two tests in `test/services/radio/radio_source_http_policy_usage_test.dart` with:

```dart
test('Bilibili live client owns live HTTP policy', () {
  final source =
      File('lib/data/sources/bilibili_live_client.dart').readAsStringSync();

  expect(source, contains('SourceHttpPolicy.createBilibiliLiveDio'));
  expect(source, contains('SourceHttpPolicy.bilibiliLiveHeaders'));
  expect(source, contains('/room/v1/Room/playUrl'));
  expect(
    source,
    isNot(contains("'Referer': 'https://live.bilibili.com/'")),
  );
});

test('Bilibili source and radio source delegate live API mechanics', () {
  final bilibiliSource =
      File('lib/data/sources/bilibili_source.dart').readAsStringSync();
  final radioSource =
      File('lib/services/radio/radio_source.dart').readAsStringSync();

  expect(bilibiliSource, contains('BilibiliLiveClient'));
  expect(radioSource, contains('BilibiliLiveClient'));
  expect(bilibiliSource, isNot(contains('/room/v1/Room/playUrl')));
  expect(radioSource, isNot(contains('/room/v1/Room/playUrl')));
});
```

Keep the existing `radio cover preloader uses Bilibili live policy headers` test unchanged.

- [ ] **Step 2: Update source guidance**

In `lib/data/sources/AGENTS.md`, replace:

```markdown
- `BilibiliSource` keeps live room helpers on a separate live Dio (`_liveDio`)
  instead of reusing the search/API Dio.
```

with:

```markdown
- `BilibiliLiveClient` owns Bilibili live room helpers, live endpoint URLs,
  real room ID resolution, live room search enrichment, live stream lookup, and
  medal wall room lookup. `BilibiliSource`, `RadioSource`, and
  `BilibiliAccountService` should delegate those mechanics to the client.
```

- [ ] **Step 3: Update service guidance**

In `lib/services/AGENTS.md`, under `## Account System`, add:

```markdown
Bilibili medal wall radio import keeps credential ownership in
`BilibiliAccountService`, but live room lookup and `getRoomInfoOld` handling
belong in `BilibiliLiveClient`.
```

- [ ] **Step 4: Run static policy and targeted verification**

Run:

```bash
flutter test test/data/sources/bilibili_live_client_test.dart
flutter test test/services/radio test/services/account test/data/sources
flutter test test/providers/search_pagination_stale_test.dart
flutter analyze
```

Expected: all commands exit with code 0.

- [ ] **Step 5: Inspect working tree**

Run:

```bash
git status --short
```

Expected: only files from this plan are modified or created. If unrelated files appear, leave them untouched and mention them in the final report.

- [ ] **Step 6: Version-control checkpoint**

Do not commit unless the user has explicitly approved commits for this execution. If commits are approved, run:

```bash
git add lib/data/sources/bilibili_live_client.dart test/data/sources/bilibili_live_client_test.dart lib/data/sources/bilibili_source.dart lib/services/radio/radio_source.dart lib/services/account/bilibili_account_service.dart test/bilibili_source_test.dart test/services/radio/radio_source_live_client_test.dart test/services/radio/radio_source_http_policy_usage_test.dart test/services/account/bilibili_account_live_policy_test.dart lib/data/sources/AGENTS.md lib/services/AGENTS.md
git commit -m "refactor: deepen Bilibili live ownership"
```

Expected without commit approval: no command is run.

## Final Verification Checklist

- `BilibiliLiveClient.parseLiveUrl()` accepts `live.bilibili.com/<id>` and `live.bilibili.com/h5/<id>`.
- `BilibiliLiveClient.resolveRealRoomId()` uses `room_init` and falls back to the input ID on failure.
- `BilibiliLiveClient.getRoomInfo()` combines room info, anchor info, and room news while tolerating secondary failures.
- `BilibiliLiveClient.getHighEnergyUserCount()` preserves `getOnlineGoldRank` behavior.
- `BilibiliLiveClient.getRadioStream()` preserves radio parameters: `platform: web`, `quality: 2`, `qn: 80`.
- `BilibiliLiveClient.getSearchStreamUrl()` preserves search stream parameters: `platform: h5`, `quality: 4`.
- `BilibiliLiveClient.searchRooms()` preserves `live_room` plus `bili_user` merge and filter behavior.
- `BilibiliLiveClient.getMedalWallRooms()` maps medal wall rooms and skips individual failed room lookups.
- `BilibiliSource.searchLiveRooms()`, `getLiveRoomInfo()`, and `getLiveStreamUrl()` remain public and delegate to the client.
- `RadioSource` public methods remain compatible for `RadioController` and `RadioRefreshService`.
- `BilibiliAccountService.fetchMedalWall()` returns the same `MedalWallItem` shape as before.
- Live headers and live Dio creation are referenced through `SourceHttpPolicy` in the new client.
- Scoped `AGENTS.md` files reflect the new ownership.

## Self-Review

**Spec coverage:** Covered all approved scope items: URL parsing, real room ID resolution, room info, anchor info, room news, high-energy count, radio stream lookup, search stream lookup, live search merge/filter, medal wall lookup, adapter compatibility, static policy tests, and scoped documentation.

**Placeholder scan:** Reviewed this plan for banned planning filler, vague error-handling instructions, and references to undefined planned public methods. No matches remain outside this sentence.

**Type consistency:** Planned client types are consistent across tasks: `BilibiliLiveClient`, `BilibiliLiveUrlParseResult`, `BilibiliLiveRoomDetails`, `BilibiliLiveStream`, and `BilibiliMedalWallRoom`. Adapter method signatures preserve existing `BilibiliSource`, `RadioSource`, and `BilibiliAccountService` public interfaces.
