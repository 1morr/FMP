import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/live_room.dart';
import 'package:fmp/data/sources/bilibili_exception.dart';
import 'package:fmp/data/sources/bilibili_live_client.dart';
import 'package:fmp/data/sources/source_http_policy.dart';

void main() {
  group('parseLiveUrl', () {
    test('accepts standard and h5 Bilibili live URLs', () {
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: Dio(),
      );
      addTearDown(client.dispose);

      final standard = client.parseLiveUrl('https://live.bilibili.com/123');
      final h5 = client.parseLiveUrl('https://live.bilibili.com/h5/456');

      expect(standard?.roomId, '123');
      expect(standard?.normalizedUrl, 'https://live.bilibili.com/123');
      expect(h5?.roomId, '456');
      expect(h5?.normalizedUrl, 'https://live.bilibili.com/456');
    });

    test('accepts legacy tolerated live URL forms', () {
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: Dio(),
      );
      addTearDown(client.dispose);

      final http = client.parseLiveUrl('http://live.bilibili.com/12345');
      final bare = client.parseLiveUrl('live.bilibili.com/12345');
      final bareH5 = client.parseLiveUrl('live.bilibili.com/h5/67890');

      expect(http?.roomId, '12345');
      expect(http?.normalizedUrl, 'https://live.bilibili.com/12345');
      expect(bare?.roomId, '12345');
      expect(bare?.normalizedUrl, 'https://live.bilibili.com/12345');
      expect(bareH5?.roomId, '67890');
      expect(bareH5?.normalizedUrl, 'https://live.bilibili.com/67890');
    });

    test('rejects non-live URLs including Bilibili video and YouTube URL', () {
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: Dio(),
      );
      addTearDown(client.dispose);

      expect(
        client.parseLiveUrl('https://www.bilibili.com/video/BV1xx411c7mD'),
        isNull,
      );
      expect(
        client.parseLiveUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isNull,
      );
    });
  });

  group('resolveRealRoomId', () {
    test('returns API room_id and sends room_init query id', () async {
      late RequestOptions request;
      final liveDio = _fakeDio((options) {
        request = options;
        return ResponseBody.fromString(
          '{"code":0,"data":{"room_id":456}}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final roomId = await client.resolveRealRoomId('123');

      expect(roomId, '456');
      expect(request.path, endsWith('/room/v1/Room/room_init'));
      expect(request.queryParameters['id'], '123');
    });

    test('falls back to input when request throws DioException', () async {
      final liveDio = _fakeDio((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'network down',
        );
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final roomId = await client.resolveRealRoomId('123');

      expect(roomId, '123');
    });
  });

  group('getRoomInfo', () {
    test('combines room info, anchor info, and room news', () async {
      final requests = <RequestOptions>[];
      final liveDio = _fakeDio((options) {
        requests.add(options);
        if (options.path.endsWith('/room/v1/Room/room_init')) {
          return _jsonResponse('{"code":0,"data":{"room_id":456}}');
        }
        if (options.path.endsWith('/room/v1/Room/get_info')) {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "room_id": 456,
                "uid": 789,
                "title": "Live title",
                "user_cover": "//i0.hdslb.com/cover.jpg",
                "keyframe": "//i0.hdslb.com/keyframe.jpg",
                "online": 1234,
                "live_time": "2024-01-02 03:04:05",
                "live_status": 1,
                "description": "Room description",
                "tags": "music,chat",
                "area_name": "Singing",
                "parent_area_name": "Entertainment"
              }
            }
          ''');
        }
        if (options.path.endsWith(
          '/live_user/v1/UserInfo/get_anchor_in_room',
        )) {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "info": {
                  "uname": "Host",
                  "face": "//i0.hdslb.com/avatar.jpg",
                  "uid": 789
                }
              }
            }
          ''');
        }
        if (options.path.endsWith('/room_ex/v1/RoomNews/get')) {
          return _jsonResponse(
            '{"code":0,"data":{"content":"Room announcement"}}',
          );
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final details = await client.getRoomInfo('123');
      final liveRoom = details!.toLiveRoom();

      expect(details.roomId, '456');
      expect(details.title, 'Live title');
      expect(details.thumbnailUrl, 'https://i0.hdslb.com/cover.jpg');
      expect(details.hostName, 'Host');
      expect(details.hostAvatarUrl, 'https://i0.hdslb.com/avatar.jpg');
      expect(details.hostUid, 789);
      expect(details.viewerCount, 1234);
      expect(details.liveStartTime, DateTime(2024, 1, 2, 3, 4, 5));
      expect(details.isLive, isTrue);
      expect(details.description, 'Room description');
      expect(details.tags, 'music,chat');
      expect(details.announcement, 'Room announcement');
      expect(details.areaName, 'Singing');
      expect(details.parentAreaName, 'Entertainment');
      expect(liveRoom.roomId, 456);
      expect(liveRoom.uid, 789);
      expect(liveRoom.uname, 'Host');
      expect(liveRoom.title, 'Live title');
      expect(liveRoom.cover, 'https://i0.hdslb.com/cover.jpg');
      expect(liveRoom.face, 'https://i0.hdslb.com/avatar.jpg');
      expect(liveRoom.liveStatus, LiveStatus.live);

      expect(requests[0].queryParameters['id'], '123');
      expect(requests[1].queryParameters['room_id'], '456');
      expect(requests[2].queryParameters['roomid'], '456');
      expect(requests[3].queryParameters['roomid'], '456');
    });

    test('keeps room info when anchor and news calls fail', () async {
      final liveDio = _fakeDio((options) {
        if (options.path.endsWith('/room/v1/Room/room_init')) {
          return _jsonResponse('{"code":0,"data":{"room_id":456}}');
        }
        if (options.path.endsWith('/room/v1/Room/get_info')) {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "room_id": 456,
                "uid": 789,
                "title": "Offline title",
                "user_cover": "",
                "keyframe": "//i0.hdslb.com/keyframe.jpg",
                "online": 12,
                "live_time": 1704164645,
                "live_status": 0,
                "description": "",
                "tags": "",
                "area_name": "Talk",
                "parent_area_name": "Life"
              }
            }
          ''');
        }
        if (options.path.endsWith(
          '/live_user/v1/UserInfo/get_anchor_in_room',
        )) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'anchor down',
          );
        }
        if (options.path.endsWith('/room_ex/v1/RoomNews/get')) {
          return _jsonResponse('{"code":-400,"data":null}');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final details = await client.getRoomInfo('123');
      final liveRoom = details!.toLiveRoom();

      expect(details.roomId, '456');
      expect(details.thumbnailUrl, 'https://i0.hdslb.com/keyframe.jpg');
      expect(details.hostName, isNull);
      expect(details.hostAvatarUrl, isNull);
      expect(details.hostUid, 789);
      expect(
        details.liveStartTime,
        DateTime.fromMillisecondsSinceEpoch(1704164645 * 1000),
      );
      expect(details.isLive, isFalse);
      expect(details.description, isNull);
      expect(details.tags, isNull);
      expect(details.announcement, isNull);
      expect(liveRoom.liveStatus, LiveStatus.offline);
    });

    test('preserves replay live status', () async {
      final liveDio = _fakeDio((options) {
        if (options.path.endsWith('/room/v1/Room/room_init')) {
          return _jsonResponse('{"code":0,"data":{"room_id":456}}');
        }
        if (options.path.endsWith('/room/v1/Room/get_info')) {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "room_id": 456,
                "uid": 789,
                "title": "Replay title",
                "online": 12,
                "live_time": 0,
                "live_status": 2
              }
            }
          ''');
        }
        if (options.path.endsWith(
          '/live_user/v1/UserInfo/get_anchor_in_room',
        )) {
          return _jsonResponse('{"code":0,"data":{"info":{}}}');
        }
        if (options.path.endsWith('/room_ex/v1/RoomNews/get')) {
          return _jsonResponse('{"code":0,"data":{"content":""}}');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final details = await client.getRoomInfo('123');
      final liveRoom = details!.toLiveRoom();

      expect(details.isLive, isFalse);
      expect(liveRoom.liveStatus, LiveStatus.replay);
      expect(liveRoom.canPlay, isTrue);
    });
  });

  group('getHighEnergyUserCount', () {
    test('uses room uid and returns onlineNum', () async {
      final requests = <RequestOptions>[];
      final liveDio = _fakeDio((options) {
        requests.add(options);
        if (options.path.endsWith('/room/v1/Room/room_init')) {
          return _jsonResponse('{"code":0,"data":{"room_id":456}}');
        }
        if (options.path.endsWith('/room/v1/Room/get_info')) {
          return _jsonResponse('{"code":0,"data":{"room_id":456,"uid":789}}');
        }
        if (options.path.endsWith(
          '/xlive/general-interface/v1/rank/getOnlineGoldRank',
        )) {
          return _jsonResponse('{"code":0,"data":{"onlineNum":99}}');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final count = await client.getHighEnergyUserCount('123');

      expect(count, 99);
      expect(requests[0].queryParameters['id'], '123');
      expect(requests[1].queryParameters['room_id'], '456');
      expect(requests[2].queryParameters, {
        'ruid': 789,
        'roomId': '456',
        'page': 1,
        'pageSize': 1,
      });
    });

    test('returns null on lookup failure', () async {
      final liveDio = _fakeDio((options) {
        if (options.path.endsWith('/room/v1/Room/room_init')) {
          return _jsonResponse('{"code":0,"data":{"room_id":456}}');
        }
        if (options.path.endsWith('/room/v1/Room/get_info')) {
          return _jsonResponse('{"code":-400,"data":null}');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final count = await client.getHighEnergyUserCount('123');

      expect(count, isNull);
    });
  });

  group('getRadioStream', () {
    test('uses current radio playUrl parameters and returns live headers',
        () async {
      final requests = <RequestOptions>[];
      final liveDio = _fakeDio((options) {
        requests.add(options);
        if (options.path.endsWith('/room/v1/Room/room_init')) {
          return _jsonResponse('{"code":0,"data":{"room_id":456}}');
        }
        if (options.path.endsWith('/room/v1/Room/playUrl')) {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "durl": [
                  {"url": "https://live.example.com/stream.flv"}
                ]
              }
            }
          ''');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final stream = await client.getRadioStream('123');

      expect(stream.url, 'https://live.example.com/stream.flv');
      expect(stream.headers, SourceHttpPolicy.bilibiliLiveHeaders());
      expect(requests[0].queryParameters['id'], '123');
      expect(requests[1].queryParameters, {
        'cid': '456',
        'platform': 'web',
        'quality': 2,
        'qn': 80,
      });
    });

    test('throws when playUrl returns no durl', () async {
      final liveDio = _fakeDio((options) {
        if (options.path.endsWith('/room/v1/Room/room_init')) {
          return _jsonResponse('{"code":0,"data":{"room_id":456}}');
        }
        if (options.path.endsWith('/room/v1/Room/playUrl')) {
          return _jsonResponse('{"code":0,"data":{"durl":[]}}');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      expect(
        client.getRadioStream('123'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('No stream URL available'),
          ),
        ),
      );
    });

    test('throws when playUrl data is malformed', () async {
      final liveDio = _fakeDio((options) {
        if (options.path.endsWith('/room/v1/Room/room_init')) {
          return _jsonResponse('{"code":0,"data":{"room_id":456}}');
        }
        if (options.path.endsWith('/room/v1/Room/playUrl')) {
          return _jsonResponse('{"code":0,"data":"bad"}');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      expect(
        client.getRadioStream('123'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('No stream URL available'),
          ),
        ),
      );
    });

    test('throws when playUrl durl url is not a string', () async {
      final liveDio = _fakeDio((options) {
        if (options.path.endsWith('/room/v1/Room/room_init')) {
          return _jsonResponse('{"code":0,"data":{"room_id":456}}');
        }
        if (options.path.endsWith('/room/v1/Room/playUrl')) {
          return _jsonResponse('{"code":0,"data":{"durl":[{"url":123}]}}');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      expect(
        client.getRadioStream('123'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('No stream URL available'),
          ),
        ),
      );
    });
  });

  group('getSearchStreamUrl', () {
    test('preserves h5 quality 4 parameters and no qn', () async {
      late RequestOptions request;
      final liveDio = _fakeDio((options) {
        request = options;
        if (options.path.endsWith('/room/v1/Room/playUrl')) {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "durl": [
                  {"url": "https://live.example.com/search.flv"}
                ]
              }
            }
          ''');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final url = await client.getSearchStreamUrl(456);

      expect(url, 'https://live.example.com/search.flv');
      expect(request.path, endsWith('/room/v1/Room/playUrl'));
      expect(request.queryParameters, {
        'cid': 456,
        'platform': 'h5',
        'quality': 4,
      });
      expect(request.queryParameters, isNot(contains('qn')));
    });

    test('returns null on playUrl failure', () async {
      final liveDio = _fakeDio((options) {
        if (options.path.endsWith('/room/v1/Room/playUrl')) {
          return _jsonResponse('{"code":-400,"message":"failed","data":null}');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final url = await client.getSearchStreamUrl(456);

      expect(url, isNull);
    });

    test('returns null when playUrl data is malformed', () async {
      final liveDio = _fakeDio((options) {
        if (options.path.endsWith('/room/v1/Room/playUrl')) {
          return _jsonResponse('{"code":0,"data":"bad"}');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final url = await client.getSearchStreamUrl(456);

      expect(url, isNull);
    });

    test('returns null when playUrl durl url is not a string', () async {
      final liveDio = _fakeDio((options) {
        if (options.path.endsWith('/room/v1/Room/playUrl')) {
          return _jsonResponse('{"code":0,"data":{"durl":[{"url":123}]}}');
        }
        throw StateError('Unexpected request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final url = await client.getSearchStreamUrl(456);

      expect(url, isNull);
    });
  });

  group('searchRooms', () {
    test('merges live_room and bili_user results and enriches user rooms',
        () async {
      final apiRequests = <RequestOptions>[];
      final liveRequests = <RequestOptions>[];
      final apiDio = _fakeDio((options) {
        apiRequests.add(options);
        if (options.queryParameters['search_type'] == 'live_room') {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "numResults": 50,
                "result": [
                  {
                    "roomid": 100,
                    "uid": 10,
                    "uname": "Live Host",
                    "title": "<em>Live</em> Title",
                    "user_cover": "//i0.hdslb.com/live-cover.jpg",
                    "uface": "//i0.hdslb.com/live-face.jpg",
                    "online": 123,
                    "cate_name": "Music",
                    "tags": "sing"
                  }
                ]
              }
            }
          ''');
        }
        if (options.queryParameters['search_type'] == 'bili_user') {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "numResults": 40,
                "result": [
                  {
                    "room_id": 200,
                    "mid": 20,
                    "uname": "Search User",
                    "upic": "//i0.hdslb.com/search-face.jpg"
                  }
                ]
              }
            }
          ''');
        }
        throw StateError('Unexpected API request: ${options.path}');
      });
      final liveDio = _fakeDio((options) {
        liveRequests.add(options);
        if (options.path.endsWith('/room/v1/Room/room_init')) {
          return _jsonResponse('{"code":0,"data":{"room_id":200}}');
        }
        if (options.path.endsWith('/room/v1/Room/get_info')) {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "room_id": 200,
                "uid": 20,
                "title": "Offline Enriched Title",
                "keyframe": "//i0.hdslb.com/offline-cover.jpg",
                "online": 0,
                "live_time": 0,
                "live_status": 0
              }
            }
          ''');
        }
        if (options.path.endsWith(
          '/live_user/v1/UserInfo/get_anchor_in_room',
        )) {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "info": {
                  "uid": 20,
                  "uname": "Enriched Anchor",
                  "face": "//i0.hdslb.com/enriched-face.jpg"
                }
              }
            }
          ''');
        }
        if (options.path.endsWith('/room_ex/v1/RoomNews/get')) {
          return _jsonResponse('{"code":0,"data":{"content":""}}');
        }
        throw StateError('Unexpected live request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: apiDio,
        liveDio: liveDio,
        apiBase: 'https://api.test',
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final result = await client.searchRooms('music');

      expect(result.rooms.map((room) => room.roomId), [100, 200]);
      expect(result.totalCount, 90);
      expect(result.hasMore, isTrue);
      expect(result.rooms[0].title, 'Live Title');
      expect(result.rooms[1].title, 'Offline Enriched Title');
      expect(result.rooms[1].uname, 'Search User');
      expect(result.rooms[1].face, 'https://i0.hdslb.com/search-face.jpg');
      expect(result.rooms[1].isLive, isFalse);
      expect(apiRequests.map((request) => request.queryParameters), [
        {
          'keyword': 'music',
          'search_type': 'live_room',
          'page': 1,
          'page_size': 20,
        },
        {
          'keyword': 'music',
          'search_type': 'bili_user',
          'page': 1,
          'page_size': 20,
        },
      ]);
      expect(liveRequests[0].queryParameters['id'], '200');
      expect(liveRequests[1].queryParameters['room_id'], '200');
    });

    test('uses latest search options provider for each request', () async {
      var currentOptions = Options(headers: {'Cookie': 'old-cookie'});
      final capturedCookies = <Object?>[];
      final apiDio = _fakeDio((options) {
        if (options.queryParameters['search_type'] == 'bili_user') {
          capturedCookies.add(options.headers['Cookie']);
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "numResults": 0,
                "result": []
              }
            }
          ''');
        }
        throw StateError('Unexpected API request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: apiDio,
        liveDio: Dio(),
        apiBase: 'https://api.test',
        searchOptionsProvider: () => currentOptions,
      );
      addTearDown(client.dispose);

      await client.searchRooms('x', filter: LiveRoomFilter.offline);
      currentOptions = Options(headers: {'Cookie': 'new-cookie'});
      await client.searchRooms('x', filter: LiveRoomFilter.offline);

      expect(capturedCookies, ['old-cookie', 'new-cookie']);
    });

    test('starts live room and user searches concurrently', () async {
      final liveRoomRequestStarted = Completer<void>();
      final liveRoomResponse = Completer<ResponseBody>();
      final biliUserRequestStarted = Completer<void>();
      ResponseBody emptySearchResponse() =>
          _jsonResponse('{"code":0,"data":{"numResults":0,"result":[]}}');
      final apiDio = _fakeDio((options) {
        if (options.queryParameters['search_type'] == 'live_room') {
          if (!liveRoomRequestStarted.isCompleted) {
            liveRoomRequestStarted.complete();
          }
          return liveRoomResponse.future;
        }
        if (options.queryParameters['search_type'] == 'bili_user') {
          if (!biliUserRequestStarted.isCompleted) {
            biliUserRequestStarted.complete();
          }
          return emptySearchResponse();
        }
        throw StateError('Unexpected API request: ${options.path}');
      });
      addTearDown(() {
        if (!liveRoomResponse.isCompleted) {
          liveRoomResponse.complete(emptySearchResponse());
        }
      });
      final client = BilibiliLiveClient(
        apiDio: apiDio,
        liveDio: Dio(),
        apiBase: 'https://api.test',
      );
      addTearDown(client.dispose);

      final search = client.searchRooms('music');
      await liveRoomRequestStarted.future;
      await pumpEventQueue(times: 5);

      expect(biliUserRequestStarted.isCompleted, isTrue);

      liveRoomResponse.complete(emptySearchResponse());
      final result = await search;
      expect(result.rooms, isEmpty);
    });

    test(
        'offline filter only returns non-live user rooms and only calls bili_user API',
        () async {
      final apiRequests = <RequestOptions>[];
      final apiDio = _fakeDio((options) {
        apiRequests.add(options);
        if (options.queryParameters['search_type'] == 'bili_user') {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "numResults": 2,
                "result": [
                  {
                    "room_id": 300,
                    "mid": 30,
                    "uname": "Offline User",
                    "upic": "//i0.hdslb.com/offline-face.jpg"
                  },
                  {
                    "room_id": 400,
                    "mid": 40,
                    "uname": "Online User",
                    "upic": "//i0.hdslb.com/online-face.jpg"
                  },
                  {
                    "room_id": 0,
                    "mid": 50,
                    "uname": "No Room",
                    "upic": "//i0.hdslb.com/no-room.jpg"
                  }
                ]
              }
            }
          ''');
        }
        throw StateError('Unexpected API request: ${options.path}');
      });
      final liveDio = _fakeDio((options) {
        if (options.path.endsWith('/room/v1/Room/room_init')) {
          return _jsonResponse(
            '{"code":0,"data":{"room_id":${options.queryParameters['id']}}}',
          );
        }
        if (options.path.endsWith('/room/v1/Room/get_info')) {
          final roomId = options.queryParameters['room_id'];
          final liveStatus = roomId == '400' ? 1 : 0;
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "room_id": $roomId,
                "uid": $roomId,
                "title": "Room $roomId",
                "online": 7,
                "live_time": 0,
                "live_status": $liveStatus
              }
            }
          ''');
        }
        if (options.path.endsWith(
          '/live_user/v1/UserInfo/get_anchor_in_room',
        )) {
          return _jsonResponse('{"code":0,"data":{"info":{}}}');
        }
        if (options.path.endsWith('/room_ex/v1/RoomNews/get')) {
          return _jsonResponse('{"code":0,"data":{"content":""}}');
        }
        throw StateError('Unexpected live request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: apiDio,
        liveDio: liveDio,
        apiBase: 'https://api.test',
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final result = await client.searchRooms(
        'music',
        filter: LiveRoomFilter.offline,
      );

      expect(result.rooms.map((room) => room.roomId), [300]);
      expect(result.rooms.single.isLive, isFalse);
      expect(apiRequests, hasLength(1));
      expect(apiRequests.single.queryParameters['search_type'], 'bili_user');
    });

    test('throws rate-limit exception when live_room search is rate-limited',
        () async {
      final apiDio = _fakeDio((options) {
        if (options.queryParameters['search_type'] == 'live_room') {
          return _jsonResponse(
            '{"code":-352,"message":"risk control","data":null}',
          );
        }
        return _jsonResponse(
          '{"code":0,"data":{"numResults":0,"result":[]}}',
        );
      });
      final client = BilibiliLiveClient(
        apiDio: apiDio,
        liveDio: Dio(),
        apiBase: 'https://api.test',
      );
      addTearDown(client.dispose);

      await expectLater(
        client.searchRooms('music'),
        throwsA(
          isA<BilibiliApiException>()
              .having((e) => e.numericCode, 'numericCode', -352)
              .having((e) => e.isRateLimited, 'isRateLimited', isTrue),
        ),
      );
    });

    test('throws API exception when live_room search returns non-zero code',
        () async {
      final apiDio = _fakeDio((options) {
        if (options.queryParameters['search_type'] == 'live_room') {
          return _jsonResponse(
            '{"code":-400,"message":"bad request","data":null}',
          );
        }
        return _jsonResponse(
          '{"code":0,"data":{"numResults":0,"result":[]}}',
        );
      });
      final client = BilibiliLiveClient(
        apiDio: apiDio,
        liveDio: Dio(),
        apiBase: 'https://api.test',
      );
      addTearDown(client.dispose);

      await expectLater(
        client.searchRooms('music'),
        throwsA(
          isA<BilibiliApiException>()
              .having((e) => e.numericCode, 'numericCode', -400)
              .having((e) => e.message, 'message', 'bad request'),
        ),
      );
    });

    test('throws API exception when search response body is malformed',
        () async {
      final apiDio = _fakeDio((options) {
        if (options.queryParameters['search_type'] == 'live_room') {
          return _jsonResponse('[]');
        }
        return _jsonResponse(
          '{"code":0,"data":{"numResults":0,"result":[]}}',
        );
      });
      final client = BilibiliLiveClient(
        apiDio: apiDio,
        liveDio: Dio(),
        apiBase: 'https://api.test',
      );
      addTearDown(client.dispose);

      await expectLater(
        client.searchRooms('music'),
        throwsA(
          isA<BilibiliApiException>().having(
            (e) => e.numericCode,
            'numericCode',
            -999,
          ),
        ),
      );
    });

    test('throws API exception when successful search data is malformed',
        () async {
      final apiDio = _fakeDio((options) {
        if (options.queryParameters['search_type'] == 'live_room') {
          return _jsonResponse('{"code":0,"data":"bad"}');
        }
        return _jsonResponse(
          '{"code":0,"data":{"numResults":0,"result":[]}}',
        );
      });
      final client = BilibiliLiveClient(
        apiDio: apiDio,
        liveDio: Dio(),
        apiBase: 'https://api.test',
      );
      addTearDown(client.dispose);

      await expectLater(
        client.searchRooms('music'),
        throwsA(
          isA<BilibiliApiException>().having(
            (e) => e.numericCode,
            'numericCode',
            -999,
          ),
        ),
      );
    });

    test('throws API exception when successful search data is missing',
        () async {
      final apiDio = _fakeDio((options) {
        if (options.queryParameters['search_type'] == 'live_room') {
          return _jsonResponse('{"code":0}');
        }
        return _jsonResponse(
          '{"code":0,"data":{"numResults":0,"result":[]}}',
        );
      });
      final client = BilibiliLiveClient(
        apiDio: apiDio,
        liveDio: Dio(),
        apiBase: 'https://api.test',
      );
      addTearDown(client.dispose);

      await expectLater(
        client.searchRooms('music'),
        throwsA(
          isA<BilibiliApiException>().having(
            (e) => e.numericCode,
            'numericCode',
            -999,
          ),
        ),
      );
    });
  });

  group('getMedalWallRooms', () {
    test('maps medal wall entries and skips failed room lookups', () async {
      final requests = <RequestOptions>[];
      final liveDio = _fakeDio((options) {
        requests.add(options);
        if (options.path.endsWith('/xlive/web-ucenter/user/MedalWall')) {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "list": [
                  {
                    "target_name": "Valid Host",
                    "target_icon": "//i0.hdslb.com/valid.jpg",
                    "live_status": 1,
                    "medal_info": {"target_id": 111}
                  },
                  {
                    "target_name": "Failed Host",
                    "target_icon": "//i0.hdslb.com/failed.jpg",
                    "live_status": 0,
                    "medal_info": {"target_id": 222}
                  },
                  {
                    "target_name": "No Uid",
                    "target_icon": "//i0.hdslb.com/no-uid.jpg",
                    "live_status": 0,
                    "medal_info": {"target_id": 0}
                  }
                ]
              }
            }
          ''');
        }
        if (options.path.endsWith('/room/v1/Room/getRoomInfoOld')) {
          if (options.queryParameters['mid'] == 111) {
            return _jsonResponse('{"code":0,"data":{"roomid":999}}');
          }
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'room lookup failed',
          );
        }
        throw StateError('Unexpected live request: ${options.path}');
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final rooms = await client.getMedalWallRooms(
        targetId: '12345',
        cookie: 'SESSDATA=abc',
      );

      expect(requests.first.queryParameters['target_id'], '12345');
      expect(requests.first.headers['Cookie'], 'SESSDATA=abc');
      expect(
        requests
            .where((request) =>
                request.path.endsWith('/room/v1/Room/getRoomInfoOld'))
            .map((request) => request.queryParameters['mid']),
        [111, 222],
      );
      expect(rooms, hasLength(1));
      expect(rooms.single.roomId, '999');
      expect(rooms.single.name, 'Valid Host');
      expect(rooms.single.avatarUrl, '//i0.hdslb.com/valid.jpg');
      expect(rooms.single.uid, 111);
      expect(rooms.single.liveStatus, 1);
      expect(rooms.single.link, 'https://live.bilibili.com/999');
    });

    test('starts medal wall room lookups concurrently', () async {
      final firstRoomLookupStarted = Completer<void>();
      final firstRoomResponse = Completer<ResponseBody>();
      final secondRoomLookupStarted = Completer<void>();
      final firstRoomJson = _jsonResponse('{"code":0,"data":{"roomid":999}}');
      final liveDio = _fakeDio((options) {
        if (options.path.endsWith('/xlive/web-ucenter/user/MedalWall')) {
          return _jsonResponse('''
            {
              "code": 0,
              "data": {
                "list": [
                  {
                    "target_name": "First Host",
                    "live_status": 1,
                    "medal_info": {"target_id": 111}
                  },
                  {
                    "target_name": "Second Host",
                    "live_status": 0,
                    "medal_info": {"target_id": 222}
                  }
                ]
              }
            }
          ''');
        }
        if (options.path.endsWith('/room/v1/Room/getRoomInfoOld')) {
          final mid = options.queryParameters['mid'];
          if (mid == 111) {
            if (!firstRoomLookupStarted.isCompleted) {
              firstRoomLookupStarted.complete();
            }
            return firstRoomResponse.future;
          }
          if (mid == 222) {
            if (!secondRoomLookupStarted.isCompleted) {
              secondRoomLookupStarted.complete();
            }
            return _jsonResponse('{"code":0,"data":{"roomid":888}}');
          }
        }
        throw StateError('Unexpected live request: ${options.path}');
      });
      addTearDown(() {
        if (!firstRoomResponse.isCompleted) {
          firstRoomResponse.complete(firstRoomJson);
        }
      });
      final client = BilibiliLiveClient(
        apiDio: Dio(),
        liveDio: liveDio,
        liveApiBase: 'https://live.test',
      );
      addTearDown(client.dispose);

      final roomsFuture = client.getMedalWallRooms(
        targetId: '12345',
        cookie: 'SESSDATA=abc',
      );
      await firstRoomLookupStarted.future;
      await pumpEventQueue(times: 5);

      expect(secondRoomLookupStarted.isCompleted, isTrue);

      firstRoomResponse.complete(firstRoomJson);
      final rooms = await roomsFuture;
      expect(rooms.map((room) => room.roomId), ['999', '888']);
    });
  });
}

Dio _fakeDio(FutureOr<ResponseBody> Function(RequestOptions options) handler) {
  final dio = Dio();
  dio.httpClientAdapter = _FakeDioAdapter(handler);
  return dio;
}

ResponseBody _jsonResponse(String body) {
  return ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _FakeDioAdapter implements HttpClientAdapter {
  _FakeDioAdapter(this._handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
