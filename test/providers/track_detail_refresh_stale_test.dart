import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/models/video_detail.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:fmp/providers/account/account_provider.dart';
import 'package:fmp/providers/library/track_detail_provider.dart';
import 'package:fmp/services/account/bilibili_account_service.dart';
import 'package:fmp/services/account/netease_account_service.dart';
import 'package:fmp/services/account/youtube_account_service.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;

void main() {
  test('loadDetail treats same-source multi-page tracks as different tracks',
      () async {
    final bilibili = _CompletingTrackDetailSource(SourceType.bilibili);
    final youtube = _CompletingTrackDetailSource(SourceType.youtube);
    final netease = _CompletingTrackDetailSource(SourceType.netease);
    final sourceManager = SourceManager(sources: [
      bilibili,
      youtube,
      netease,
    ]);
    addTearDown(sourceManager.dispose);

    final notifier = TrackDetailNotifier(sourceManager, _FakeRef());

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

    expect(bilibili.requests, ['BV-SAME', 'BV-SAME']);

    bilibili.complete('BV-SAME', _detail('BV-SAME', 'Page Two'));
    await secondLoad;

    expect(notifier.state.detail!.title, 'Page Two');
  });

  test('refresh ignores stale detail after current track changes', () async {
    final bilibili = _CompletingTrackDetailSource(SourceType.bilibili);
    final youtube = _CompletingTrackDetailSource(SourceType.youtube);
    final netease = _CompletingTrackDetailSource(SourceType.netease);
    final sourceManager = SourceManager(sources: [
      bilibili,
      youtube,
      netease,
    ]);
    addTearDown(sourceManager.dispose);

    final notifier = TrackDetailNotifier(sourceManager, _FakeRef());

    final trackA = _track('BV-A', SourceType.bilibili);
    final trackB = _track('YT-B', SourceType.youtube);

    final initialLoadFuture = notifier.loadDetail(trackA);
    await pumpEventQueue(times: 2);
    bilibili.complete('BV-A', _detail('BV-A', 'Track A initial'));
    await initialLoadFuture;

    final refreshFuture = notifier.refresh();
    await pumpEventQueue(times: 2);
    expect(bilibili.requests, ['BV-A', 'BV-A']);

    final loadTrackBFuture = notifier.loadDetail(trackB);
    await pumpEventQueue(times: 2);
    youtube.complete('YT-B', _detail('YT-B', 'Track B'));
    await loadTrackBFuture;

    bilibili.complete('BV-A', _detail('BV-A', 'Track A stale refresh'));
    await refreshFuture;

    expect(notifier.state.detail!.bvid, 'YT-B');
    expect(notifier.state.detail!.title, 'Track B');
  });

  test('loadDetail clears old detail while loading a different track',
      () async {
    final bilibili = _CompletingTrackDetailSource(SourceType.bilibili);
    final youtube = _CompletingTrackDetailSource(SourceType.youtube);
    final netease = _CompletingTrackDetailSource(SourceType.netease);
    final sourceManager = SourceManager(sources: [
      bilibili,
      youtube,
      netease,
    ]);
    addTearDown(sourceManager.dispose);

    final notifier = TrackDetailNotifier(sourceManager, _FakeRef());

    final trackA = _track('BV-A', SourceType.bilibili);
    final initialLoadFuture = notifier.loadDetail(trackA);
    await pumpEventQueue(times: 2);
    bilibili.complete('BV-A', _detail('BV-A', 'Track A'));
    await initialLoadFuture;

    expect(notifier.state.detail!.title, 'Track A');

    final trackB = _track('YT-B', SourceType.youtube);
    final loadTrackBFuture = notifier.loadDetail(trackB);
    await pumpEventQueue(times: 2);

    expect(notifier.state.isLoading, isTrue);
    expect(notifier.state.detail, isNull);

    youtube.completeError('YT-B', Exception('blocked'));
    await loadTrackBFuture;

    expect(notifier.state.isLoading, isFalse);
    expect(notifier.state.detail, isNull);
    expect(notifier.state.error, contains('blocked'));
  });

  test('refresh retries current track after first detail load fails', () async {
    final bilibili = _CompletingTrackDetailSource(SourceType.bilibili);
    final youtube = _CompletingTrackDetailSource(SourceType.youtube);
    final netease = _CompletingTrackDetailSource(SourceType.netease);
    final sourceManager = SourceManager(sources: [
      bilibili,
      youtube,
      netease,
    ]);
    addTearDown(sourceManager.dispose);

    final notifier = TrackDetailNotifier(sourceManager, _FakeRef());

    final track = _track('YT-B', SourceType.youtube);
    final loadFuture = notifier.loadDetail(track);
    await pumpEventQueue(times: 2);

    youtube.completeError('YT-B', Exception('blocked'));
    await loadFuture;

    expect(notifier.state.detail, isNull);
    expect(notifier.state.error, contains('blocked'));

    final refreshFuture = notifier.refresh();
    await pumpEventQueue(times: 2);

    expect(youtube.requests, ['YT-B', 'YT-B']);

    youtube.complete('YT-B', _detail('YT-B', 'Track B retry'));
    await refreshFuture;

    expect(notifier.state.detail!.title, 'Track B retry');
    expect(notifier.state.error, isNull);
  });

  test('loadDetail does not mask missing source with local metadata fallback',
      () async {
    final sourceManager = SourceManager(sources: []);
    addTearDown(sourceManager.dispose);

    final tempDir =
        await Directory.systemTemp.createTemp('track_detail_missing_source_');
    addTearDown(() => tempDir.delete(recursive: true));

    final downloadDir = await Directory(p.join(tempDir.path, 'download'))
        .create(recursive: true);
    await File(p.join(downloadDir.path, 'metadata.json')).writeAsString('''
{
  "sourceId": "BV-MISSING",
  "title": "Local metadata should not mask missing source",
  "viewCount": 123
}
''');

    final track = _track('BV-MISSING', SourceType.bilibili)
      ..setDownloadPath(1, p.join(downloadDir.path, 'audio.m4a'));
    final notifier = TrackDetailNotifier(sourceManager, _FakeRef());

    await notifier.loadDetail(track);

    expect(notifier.state.detail, isNull);
    expect(
      notifier.state.error,
      contains('Track detail source not registered: bilibili'),
    );
  });

  test('loadDetail falls back to metadata for registered source StateError',
      () async {
    final bilibili = _CompletingTrackDetailSource(SourceType.bilibili);
    final sourceManager = SourceManager(sources: [bilibili]);
    addTearDown(sourceManager.dispose);

    final tempDir =
        await Directory.systemTemp.createTemp('track_detail_source_error_');
    addTearDown(() => tempDir.delete(recursive: true));

    final downloadDir = await Directory(p.join(tempDir.path, 'download'))
        .create(recursive: true);
    await File(p.join(downloadDir.path, 'metadata.json')).writeAsString('''
{
  "sourceId": "BV-STATE",
  "title": "Local metadata after source StateError",
  "viewCount": 456
}
''');

    final track = _track('BV-STATE', SourceType.bilibili)
      ..setDownloadPath(1, p.join(downloadDir.path, 'audio.m4a'));
    final notifier = TrackDetailNotifier(sourceManager, _FakeRef());

    final loadFuture = notifier.loadDetail(track);
    await pumpEventQueue(times: 2);
    bilibili.completeError('BV-STATE', StateError('simulated detail failure'));
    await loadFuture;

    expect(notifier.state.error, isNull);
    expect(notifier.state.detail!.title, 'Local metadata after source StateError');
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

class _CompletingTrackDetailSource implements TrackDetailSource {
  _CompletingTrackDetailSource(this.sourceType);

  @override
  final SourceType sourceType;

  final requests = <String>[];
  final _completers = <String, List<Completer<VideoDetail>>>{};

  @override
  Future<VideoDetail> getVideoDetail(
    String sourceId, {
    Map<String, String>? authHeaders,
  }) {
    requests.add(sourceId);
    final completer = Completer<VideoDetail>();
    _completers.putIfAbsent(sourceId, () => []).add(completer);
    return completer.future;
  }

  void complete(String sourceId, VideoDetail detail) {
    _completers[sourceId]!.removeAt(0).complete(detail);
  }

  void completeError(String sourceId, Object error) {
    _completers[sourceId]!.removeAt(0).completeError(error);
  }
}

class _FakeRef extends Fake implements Ref {
  final _isar = _FakeIsar();

  @override
  T read<T>(ProviderListenable<T> provider) {
    if (identical(provider, bilibiliAccountServiceProvider)) {
      return _FakeBilibiliAccountService(_isar) as T;
    }
    if (identical(provider, youtubeAccountServiceProvider)) {
      return _FakeYouTubeAccountService(_isar) as T;
    }
    if (identical(provider, neteaseAccountServiceProvider)) {
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
