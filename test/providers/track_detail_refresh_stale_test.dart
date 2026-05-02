import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/video_detail.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/netease_source.dart';
import 'package:fmp/data/sources/youtube_source.dart';
import 'package:fmp/providers/account_provider.dart';
import 'package:fmp/providers/track_detail_provider.dart';
import 'package:fmp/services/account/bilibili_account_service.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/account/youtube_account_service.dart';
import 'package:isar/isar.dart';

void main() {
  test('loadDetail treats same-source multi-page tracks as different tracks',
      () async {
    final bilibili = _CompletingBilibiliSource();
    final notifier = TrackDetailNotifier(
      bilibili,
      _CompletingYouTubeSource(),
      _CompletingNeteaseSource(),
      _FakeRef(),
    );

    final pageOne = _track('BV-SAME', SourceType.bilibili)
      ..cid = 101
      ..pageNum = 1;
    final pageTwo = _track('BV-SAME', SourceType.bilibili)
      ..cid = 202
      ..pageNum = 2;

    final firstLoad = notifier.loadDetail(pageOne);
    await pumpEventQueue(times: 2);
    bilibili.complete('BV-SAME', _detail('BV-SAME', 'Page One'));
    await firstLoad;

    final secondLoad = notifier.loadDetail(pageTwo);
    await pumpEventQueue(times: 2);

    expect(bilibili.calls, ['BV-SAME', 'BV-SAME']);

    bilibili.complete('BV-SAME', _detail('BV-SAME', 'Page Two'));
    await secondLoad;

    expect(notifier.state.detail!.title, 'Page Two');
  });

  test('refresh ignores stale detail after current track changes', () async {
    final bilibili = _CompletingBilibiliSource();
    final youtube = _CompletingYouTubeSource();
    final netease = _CompletingNeteaseSource();
    final notifier =
        TrackDetailNotifier(bilibili, youtube, netease, _FakeRef());

    final trackA = _track('BV-A', SourceType.bilibili);
    final trackB = _track('YT-B', SourceType.youtube);

    final initialLoadFuture = notifier.loadDetail(trackA);
    await pumpEventQueue(times: 2);
    bilibili.complete('BV-A', _detail('BV-A', 'Track A initial'));
    await initialLoadFuture;

    final refreshFuture = notifier.refresh();
    await pumpEventQueue(times: 2);
    expect(bilibili.calls, ['BV-A', 'BV-A']);

    final loadTrackBFuture = notifier.loadDetail(trackB);
    await pumpEventQueue(times: 2);
    youtube.complete('YT-B', _detail('YT-B', 'Track B'));
    await loadTrackBFuture;

    bilibili.complete('BV-A', _detail('BV-A', 'Track A stale refresh'));
    await refreshFuture;

    expect(notifier.state.detail!.bvid, 'YT-B');
    expect(notifier.state.detail!.title, 'Track B');
  });
}

Track _track(String sourceId, SourceType sourceType) {
  return Track()
    ..sourceType = sourceType
    ..sourceId = sourceId
    ..title = sourceId;
}

VideoDetail _detail(String sourceId, String title) {
  return VideoDetail(
    bvid: sourceId,
    title: title,
    description: '',
    coverUrl: '',
    ownerName: '',
    ownerFace: '',
    ownerId: 0,
    viewCount: 0,
    likeCount: 0,
    coinCount: 0,
    favoriteCount: 0,
    shareCount: 0,
    danmakuCount: 0,
    commentCount: 0,
    publishDate: DateTime(2026),
    durationSeconds: 0,
  );
}

class _CompletingBilibiliSource extends BilibiliSource {
  final calls = <String>[];
  final _completers = <String, List<Completer<VideoDetail>>>{};

  @override
  Future<VideoDetail> getVideoDetail(
    String bvid, {
    Map<String, String>? authHeaders,
  }) {
    calls.add(bvid);
    final completer = Completer<VideoDetail>();
    _completers.putIfAbsent(bvid, () => []).add(completer);
    return completer.future;
  }

  void complete(String sourceId, VideoDetail detail) {
    _completers[sourceId]!.removeAt(0).complete(detail);
  }
}

class _CompletingYouTubeSource extends YouTubeSource {
  final calls = <String>[];
  final _completers = <String, List<Completer<VideoDetail>>>{};

  @override
  Future<VideoDetail> getVideoDetail(
    String videoId, {
    Map<String, String>? authHeaders,
  }) {
    calls.add(videoId);
    final completer = Completer<VideoDetail>();
    _completers.putIfAbsent(videoId, () => []).add(completer);
    return completer.future;
  }

  void complete(String sourceId, VideoDetail detail) {
    _completers[sourceId]!.removeAt(0).complete(detail);
  }
}

class _CompletingNeteaseSource extends NeteaseSource {}

class _FakeRef extends Fake implements Ref {
  final _isar = _FakeIsar();

  @override
  T read<T>(ProviderListenable<T> provider) {
    if (provider == bilibiliAccountServiceProvider) {
      return _FakeBilibiliAccountService(_isar) as T;
    }
    if (provider == youtubeAccountServiceProvider) {
      return _FakeYouTubeAccountService(_isar) as T;
    }
    if (provider == neteaseAccountServiceProvider) {
      return _FakeNeteaseAccountService(_isar) as T;
    }
    throw UnimplementedError('Unexpected provider: $provider');
  }
}

class _FakeBilibiliAccountService extends BilibiliAccountService {
  _FakeBilibiliAccountService(Isar isar) : super(isar: isar);

  @override
  Future<String?> getAuthCookieString() async => null;
}

class _FakeYouTubeAccountService extends YouTubeAccountService {
  _FakeYouTubeAccountService(Isar isar) : super(isar: isar);

  @override
  Future<Map<String, String>?> getAuthHeaders() async => null;
}

class _FakeNeteaseAccountService extends NeteaseAccountService {
  _FakeNeteaseAccountService(Isar isar) : super(isar: isar);

  @override
  Future<String?> getAuthCookieString() async => null;
}

class _FakeIsar extends Fake implements Isar {}
