import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/live_room.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/providers/search_provider.dart';
import 'package:fmp/services/account/bilibili_account_service.dart';
import 'package:fmp/services/search/search_service.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/bilibili_source.dart';
import 'package:fmp/data/sources/source_provider.dart';
import 'package:isar/isar.dart';

void main() {
  group('SearchNotifier stale pagination guards', () {
    late _CompletingSearchService service;
    late _CompletingBilibiliSource bilibili;
    late SearchNotifier notifier;

    setUp(() {
      service = _CompletingSearchService();
      bilibili = _CompletingBilibiliSource();
      notifier = SearchNotifier(service, bilibili);
    });

    test('loadMore ignores results when query changes before completion',
        () async {
      notifier.setSeedState(
        SearchState(
          query: 'old query',
          onlineResults: {
            SourceType.youtube: SearchResult(
              tracks: [_track('old-page-1')],
              totalCount: 2,
              page: 1,
              pageSize: 1,
              hasMore: true,
            ),
          },
          currentPages: const {SourceType.youtube: 1},
        ),
      );

      final loadMoreFuture = notifier.loadMore(SourceType.youtube);
      await pumpEventQueue(times: 2);
      expect(service.sourceCalls.single.query, 'old query');

      notifier.setSeedState(
        SearchState(
          query: 'new query',
          onlineResults: {
            SourceType.youtube: SearchResult(
              tracks: [_track('new-page-1')],
              totalCount: 1,
              page: 1,
              pageSize: 1,
              hasMore: false,
            ),
          },
          currentPages: const {SourceType.youtube: 1},
        ),
      );
      service.completeSource(
        SourceType.youtube,
        'old query',
        2,
        SearchResult(
          tracks: [_track('old-page-2')],
          totalCount: 2,
          page: 2,
          pageSize: 1,
          hasMore: false,
        ),
      );
      await loadMoreFuture;

      expect(notifier.state.query, 'new query');
      expect(
        notifier.state.onlineResults[SourceType.youtube]!.tracks
            .map((track) => track.sourceId),
        ['new-page-1'],
      );
    });

    test(
        'loadMoreAll ignores results when sort order changes before completion',
        () async {
      notifier.setSeedState(
        SearchState(
          query: 'same query',
          searchOrder: SearchOrder.relevance,
          onlineResults: {
            SourceType.bilibili: SearchResult(
              tracks: [_track('bili-page-1', sourceType: SourceType.bilibili)],
              totalCount: 2,
              page: 1,
              pageSize: 1,
              hasMore: true,
            ),
            SourceType.youtube: SearchResult(
              tracks: [_track('yt-page-1')],
              totalCount: 2,
              page: 1,
              pageSize: 1,
              hasMore: true,
            ),
          },
          currentPages: const {
            SourceType.bilibili: 1,
            SourceType.youtube: 1,
          },
        ),
      );

      final loadMoreFuture = notifier.loadMoreAll();
      await pumpEventQueue(times: 2);
      expect(service.sourceCalls, hasLength(2));

      notifier.setSeedState(notifier.state.copyWith(
        searchOrder: SearchOrder.playCount,
        isLoading: false,
      ));
      service.completeSource(
        SourceType.bilibili,
        'same query',
        2,
        SearchResult(
          tracks: [_track('stale-bili-2', sourceType: SourceType.bilibili)],
          totalCount: 2,
          page: 2,
          pageSize: 1,
          hasMore: false,
        ),
      );
      service.completeSource(
        SourceType.youtube,
        'same query',
        2,
        SearchResult(
          tracks: [_track('stale-yt-2')],
          totalCount: 2,
          page: 2,
          pageSize: 1,
          hasMore: false,
        ),
      );
      await loadMoreFuture;

      expect(notifier.state.searchOrder, SearchOrder.playCount);
      expect(
        notifier.state.onlineResults[SourceType.bilibili]!.tracks
            .map((track) => track.sourceId),
        ['bili-page-1'],
      );
      expect(
        notifier.state.onlineResults[SourceType.youtube]!.tracks
            .map((track) => track.sourceId),
        ['yt-page-1'],
      );
    });

    test(
        'loadMoreLiveRooms ignores results when filter changes before completion',
        () async {
      notifier.setSeedState(SearchState(
        query: 'live query',
        liveRoomFilter: LiveRoomFilter.online,
        liveRoomResults: LiveSearchResult(
          rooms: [_room(1)],
          totalCount: 2,
          page: 1,
          pageSize: 1,
          hasMore: true,
        ),
        liveRoomPage: 1,
      ));

      final loadMoreFuture = notifier.loadMoreLiveRooms();
      await pumpEventQueue(times: 2);
      expect(bilibili.liveRoomCalls.single.filter, LiveRoomFilter.online);

      notifier.setSeedState(notifier.state.copyWith(
        liveRoomFilter: LiveRoomFilter.all,
        isLoading: false,
      ));
      bilibili.completeLiveRooms(
        'live query',
        2,
        LiveRoomFilter.online,
        LiveSearchResult(
          rooms: [_room(2)],
          totalCount: 2,
          page: 2,
          pageSize: 1,
          hasMore: false,
        ),
      );
      await loadMoreFuture;

      expect(notifier.state.liveRoomFilter, LiveRoomFilter.all);
      expect(
        notifier.state.liveRoomResults!.rooms.map((room) => room.roomId),
        [1],
      );
    });
  });
}

Track _track(String sourceId, {SourceType sourceType = SourceType.youtube}) {
  return Track()
    ..sourceType = sourceType
    ..sourceId = sourceId
    ..title = sourceId;
}

LiveRoom _room(int roomId) {
  return LiveRoom(
    roomId: roomId,
    uid: roomId,
    title: 'room $roomId',
    uname: 'host',
    cover: '',
    online: 0,
    isLive: true,
  );
}

extension on SearchNotifier {
  void setSeedState(SearchState state) {
    this.state = state;
  }
}

class _CompletingSearchService extends SearchService {
  _CompletingSearchService()
      : super(
          sourceManager: SourceManager(),
          trackRepository: TrackRepository(_FakeIsar()),
          isar: _FakeIsar(),
          bilibiliAccountService: BilibiliAccountService(isar: _FakeIsar()),
        );

  final List<
          ({SourceType sourceType, String query, int page, SearchOrder order})>
      sourceCalls = [];
  final Map<String, Completer<SearchResult>> _sourceCompleters = {};

  @override
  Future<SearchResult> searchSource(
    SourceType sourceType,
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) {
    sourceCalls.add((
      sourceType: sourceType,
      query: query,
      page: page,
      order: order,
    ));
    return _sourceCompleters
        .putIfAbsent(_sourceKey(sourceType, query, page), Completer.new)
        .future;
  }

  void completeSource(
    SourceType sourceType,
    String query,
    int page,
    SearchResult result,
  ) {
    _sourceCompleters[_sourceKey(sourceType, query, page)]!.complete(result);
  }

  String _sourceKey(SourceType sourceType, String query, int page) =>
      '${sourceType.name}|$query|$page';
}

class _CompletingBilibiliSource extends BilibiliSource {
  final List<({String query, int page, LiveRoomFilter filter})> liveRoomCalls =
      [];
  final Map<String, Completer<LiveSearchResult>> _liveCompleters = {};

  @override
  Future<LiveSearchResult> searchLiveRooms(
    String query, {
    int page = 1,
    int pageSize = 20,
    LiveRoomFilter filter = LiveRoomFilter.all,
  }) {
    liveRoomCalls.add((query: query, page: page, filter: filter));
    return _liveCompleters
        .putIfAbsent(_liveKey(query, page, filter), Completer.new)
        .future;
  }

  void completeLiveRooms(
    String query,
    int page,
    LiveRoomFilter filter,
    LiveSearchResult result,
  ) {
    _liveCompleters[_liveKey(query, page, filter)]!.complete(result);
  }

  String _liveKey(String query, int page, LiveRoomFilter filter) =>
      '$query|$page|${filter.name}';
}

class _FakeIsar extends Fake implements Isar {}
