import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/radio_station.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/bilibili_live_client.dart';
import 'package:fmp/data/sources/source_http_policy.dart';
import 'package:fmp/i18n/strings.g.dart';
import 'package:fmp/services/radio/radio_source.dart';

void main() {
  setUpAll(() {
    LocaleSettings.setLocale(AppLocale.en);
  });

  test('createStationFromUrl maps live client room info to RadioStation',
      () async {
    final client = _FakeLiveClient(
      parseResult: const BilibiliLiveUrlParseResult(
        roomId: '123',
        normalizedUrl: 'https://live.bilibili.com/123',
      ),
      roomDetails: BilibiliLiveRoomDetails(
        roomId: '456',
        title: 'Live title',
        thumbnailUrl: 'https://i0.hdslb.com/cover.jpg',
        hostName: 'Host',
        hostAvatarUrl: 'https://i0.hdslb.com/avatar.jpg',
        hostUid: 789,
        viewerCount: 1000,
        liveStartTime: DateTime(2024, 1, 2, 3, 4, 5),
        isLive: true,
        description: 'Room description',
        tags: 'music',
        announcement: 'Room announcement',
        areaName: 'Singing',
        parentAreaName: 'Entertainment',
      ),
    );
    final source = RadioSource(liveClient: client);
    addTearDown(source.dispose);

    final station =
        await source.createStationFromUrl('https://live.bilibili.com/123');

    expect(client.parsedUrls, ['https://live.bilibili.com/123']);
    expect(client.roomInfoLookups, ['123']);
    expect(station.url, 'https://live.bilibili.com/123');
    expect(station.sourceType, SourceType.bilibili);
    expect(station.sourceId, '123');
    expect(station.title, 'Live title');
    expect(station.thumbnailUrl, 'https://i0.hdslb.com/cover.jpg');
    expect(station.hostName, 'Host');
    expect(station.hostAvatarUrl, 'https://i0.hdslb.com/avatar.jpg');
    expect(station.hostUid, 789);

    source.dispose();
    expect(client.disposed, isFalse);
  });

  test('getStreamUrl maps live client stream and preserves live headers',
      () async {
    final headers = SourceHttpPolicy.bilibiliLiveHeaders();
    final expiresAt = DateTime(2024, 2, 3, 4, 5, 6);
    final client = _FakeLiveClient(
      stream: BilibiliLiveStream(
        url: 'https://live.example.com/stream.flv',
        headers: headers,
        expiresAt: expiresAt,
      ),
    );
    final source = RadioSource(liveClient: client);
    addTearDown(source.dispose);

    final stream = await source.getStreamUrl(_station('246'));

    expect(client.streamLookups, ['246']);
    expect(stream.url, 'https://live.example.com/stream.flv');
    expect(stream.headers, headers);
    expect(stream.expiresAt, expiresAt);
  });

  test('getHighEnergyUserCount delegates station source id lookup', () async {
    final client = _FakeLiveClient(highEnergyUserCount: 88);
    final source = RadioSource(liveClient: client);
    addTearDown(source.dispose);

    final count = await source.getHighEnergyUserCount(_station('135'));

    expect(client.highEnergyLookups, ['135']);
    expect(count, 88);
  });

  test('parseUrl rejects YouTube and accepts Bilibili through live client', () {
    final client = _FakeLiveClient(
      parseResult: const BilibiliLiveUrlParseResult(
        roomId: '321',
        normalizedUrl: 'https://live.bilibili.com/321',
      ),
    );
    final source = RadioSource(liveClient: client);
    addTearDown(source.dispose);

    expect(
      source.parseUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      isNull,
    );

    final result = source.parseUrl('https://live.bilibili.com/h5/321');

    expect(client.parsedUrls, ['https://live.bilibili.com/h5/321']);
    expect(result?.sourceId, '321');
    expect(result?.normalizedUrl, 'https://live.bilibili.com/321');
  });
}

RadioStation _station(String sourceId) {
  return RadioStation()
    ..url = 'https://live.bilibili.com/$sourceId'
    ..title = 'Station $sourceId'
    ..sourceType = SourceType.bilibili
    ..sourceId = sourceId;
}

class _FakeLiveClient extends BilibiliLiveClient {
  _FakeLiveClient({
    this.parseResult,
    this.roomDetails,
    this.stream,
    this.highEnergyUserCount,
  }) : super(apiDio: Dio(), liveDio: Dio());

  final BilibiliLiveUrlParseResult? parseResult;
  final BilibiliLiveRoomDetails? roomDetails;
  final BilibiliLiveStream? stream;
  final int? highEnergyUserCount;
  final parsedUrls = <String>[];
  final roomInfoLookups = <String>[];
  final streamLookups = <String>[];
  final highEnergyLookups = <String>[];
  bool disposed = false;

  @override
  BilibiliLiveUrlParseResult? parseLiveUrl(String url) {
    parsedUrls.add(url);
    return parseResult;
  }

  @override
  Future<BilibiliLiveRoomDetails?> getRoomInfo(String roomId) async {
    roomInfoLookups.add(roomId);
    return roomDetails;
  }

  @override
  Future<BilibiliLiveStream> getRadioStream(String roomId) async {
    streamLookups.add(roomId);
    return stream ?? const BilibiliLiveStream(url: 'https://live.example.com');
  }

  @override
  Future<int?> getHighEnergyUserCount(String roomId) async {
    highEnergyLookups.add(roomId);
    return highEnergyUserCount;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
