import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/providers/search/search_provider.dart';
import 'package:fmp/services/search/search_service.dart';
import 'package:fmp/data/repositories/search_history_repository.dart';
import 'package:fmp/data/repositories/track_repository.dart';
import 'package:fmp/data/sources/source_provider.dart';

import '../support/fakes/fake_isar.dart';
import '../support/pump_until.dart';

void main() {
  group('SearchNotifier stale pagination guards', () {
    late _CompletingSearchService service;
    late _CompletingLiveSource liveSource;
    late ProviderContainer container;
    late SearchNotifier notifier;

    setUp(() {
      service = _CompletingSearchService();
      liveSource = _CompletingLiveSource();
      // `SearchNotifier` 以前吃兩個建構子參數；`Notifier.new` 不吃，所以兩個
      // 相依都從 container 進去。直播源走 `SourceManager` 的窄能力查詢，
      // 不另外開一個具體來源的 provider。
      container = ProviderContainer(
        overrides: [
          searchServiceProvider.overrideWith((ref) => service),
          sourceManagerProvider.overrideWith(
            (ref) => SourceManager(sources: [liveSource]),
          ),
        ],
      );
      notifier = container.read(searchProvider.notifier);
    });

    tearDown(() => container.dispose());

    test(
      'loadMore ignores results when query changes before completion',
      () async {
        notifier.setSeedState(
          SearchState(
            query: 'old query',
            onlineResults: {
              SourceIds.youtube: SearchResult(
                tracks: [_track('old-page-1')],
                totalCount: 2,
                page: 1,
                pageSize: 1,
                hasMore: true,
              ),
            },
            currentPages: const {SourceIds.youtube: 1},
          ),
        );

        final loadMoreFuture = notifier.loadMore(SourceIds.youtube);
        await pumpUntil(
          () => service.sourceCalls.isNotEmpty,
          reason: 'load more should reach the search service',
        );
        expect(service.sourceCalls.single.query, 'old query');

        notifier.setSeedState(
          SearchState(
            query: 'new query',
            onlineResults: {
              SourceIds.youtube: SearchResult(
                tracks: [_track('new-page-1')],
                totalCount: 1,
                page: 1,
                pageSize: 1,
                hasMore: false,
              ),
            },
            currentPages: const {SourceIds.youtube: 1},
          ),
        );
        service.completeSource(
          SourceIds.youtube,
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
          notifier.state.onlineResults[SourceIds.youtube]!.tracks.map(
            (track) => track.sourceId,
          ),
          ['new-page-1'],
        );
      },
    );

    test(
      'loadMoreAll ignores results when sort order changes before completion',
      () async {
        notifier.setSeedState(
          SearchState(
            query: 'same query',
            searchOrder: SearchOrder.relevance,
            onlineResults: {
              SourceIds.bilibili: SearchResult(
                tracks: [_track('bili-page-1', sourceType: SourceIds.bilibili)],
                totalCount: 2,
                page: 1,
                pageSize: 1,
                hasMore: true,
              ),
              SourceIds.youtube: SearchResult(
                tracks: [_track('yt-page-1')],
                totalCount: 2,
                page: 1,
                pageSize: 1,
                hasMore: true,
              ),
            },
            currentPages: const {SourceIds.bilibili: 1, SourceIds.youtube: 1},
          ),
        );

        final loadMoreFuture = notifier.loadMoreAll();
        await pumpUntil(
          () => service.sourceCalls.length == 2,
          reason: 'load-more-all should reach both sources',
        );
        expect(service.sourceCalls, hasLength(2));

        notifier.setSeedState(
          notifier.state.copyWith(
            searchOrder: SearchOrder.playCount,
            isLoading: false,
          ),
        );
        service.completeSource(
          SourceIds.bilibili,
          'same query',
          2,
          SearchResult(
            tracks: [_track('stale-bili-2', sourceType: SourceIds.bilibili)],
            totalCount: 2,
            page: 2,
            pageSize: 1,
            hasMore: false,
          ),
        );
        service.completeSource(
          SourceIds.youtube,
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
          notifier.state.onlineResults[SourceIds.bilibili]!.tracks.map(
            (track) => track.sourceId,
          ),
          ['bili-page-1'],
        );
        expect(
          notifier.state.onlineResults[SourceIds.youtube]!.tracks.map(
            (track) => track.sourceId,
          ),
          ['yt-page-1'],
        );
      },
    );

    test(
      'loadMoreLiveRooms ignores results when filter changes before completion',
      () async {
        notifier.setSeedState(
          SearchState(
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
          ),
        );

        final loadMoreFuture = notifier.loadMoreLiveRooms();
        await pumpUntil(
          () => liveSource.calls.isNotEmpty,
          reason: 'live-room load more should reach the source',
        );
        expect(liveSource.calls.single, 'live query:2:online');

        notifier.setSeedState(
          notifier.state.copyWith(
            liveRoomFilter: LiveRoomFilter.all,
            isLoading: false,
          ),
        );
        liveSource.completeLiveRooms(
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
      },
    );

    test('all-source chip searches all direct sources', () async {
      await notifier.search('all query');

      expect(service.onlineCalls.single.sourceTypes, [
        SourceIds.bilibili,
        SourceIds.youtube,
        SourceIds.netease,
      ]);
      expect(notifier.state.currentPages.keys, [
        SourceIds.bilibili,
        SourceIds.youtube,
        SourceIds.netease,
      ]);
      expect(notifier.state.onlineResults.keys, [
        SourceIds.bilibili,
        SourceIds.youtube,
        SourceIds.netease,
      ]);
    });

    test('single-source chip searches only the selected source', () async {
      notifier.setSource(SourceIds.netease, autoSearch: false);

      await notifier.search('chip query');

      expect(service.onlineCalls.single.sourceTypes, [SourceIds.netease]);
      expect(notifier.state.currentPages.keys, [SourceIds.netease]);
      expect(notifier.state.onlineResults.keys, [SourceIds.netease]);
    });

    test('single-source chip filters visible local results', () async {
      service.localResults = [
        _track('local-bili', sourceType: SourceIds.bilibili),
        _track('local-netease', sourceType: SourceIds.netease),
        _track('local-youtube', sourceType: SourceIds.youtube),
      ];
      notifier.setSource(SourceIds.netease, autoSearch: false);

      await notifier.search('chip query');

      expect(notifier.state.localResults.map((track) => track.sourceType), [
        SourceIds.netease,
      ]);
    });

    test(
      'source changes keep previous results while refresh is in flight',
      () async {
        notifier.setSeedState(
          SearchState(
            query: 'chip query',
            onlineResults: {
              SourceIds.youtube: SearchResult(
                tracks: [_track('old-youtube')],
                totalCount: 1,
                page: 1,
                pageSize: 20,
                hasMore: false,
              ),
            },
            currentPages: const {SourceIds.youtube: 1},
          ),
        );
        final gate = service.enqueueOnlineSearchResult(
          MultiSourceSearchResult(
            query: 'chip query',
            results: {
              SourceIds.netease: SearchResult(
                tracks: [_track('new-netease', sourceType: SourceIds.netease)],
                totalCount: 1,
                page: 1,
                pageSize: 20,
                hasMore: false,
              ),
            },
          ),
        );

        notifier.setSource(SourceIds.netease);
        await pumpUntil(
          () => notifier.state.isLoading,
          reason: 'switching source should start a new search',
        );

        expect(notifier.state.isLoading, isTrue);
        expect(
          notifier.state.onlineResults[SourceIds.youtube]?.tracks.map(
            (track) => track.sourceId,
          ),
          ['old-youtube'],
        );

        gate.complete();
        await pumpUntil(
          () => !notifier.state.isLoading,
          reason: 'the new search should finish once its gate opens',
        );

        expect(notifier.state.isLoading, isFalse);
        expect(notifier.state.onlineResults.keys, [SourceIds.netease]);
      },
    );

    test(
      'search order changes keep previous results while refresh is in flight',
      () async {
        notifier.setSeedState(
          SearchState(
            query: 'sort query',
            searchOrder: SearchOrder.relevance,
            onlineResults: {
              SourceIds.youtube: SearchResult(
                tracks: [_track('old-youtube')],
                totalCount: 1,
                page: 1,
                pageSize: 20,
                hasMore: false,
              ),
            },
            currentPages: const {SourceIds.youtube: 1},
          ),
        );
        final gate = service.enqueueOnlineSearchResult(
          MultiSourceSearchResult(
            query: 'sort query',
            results: {
              SourceIds.youtube: SearchResult(
                tracks: [_track('new-youtube')],
                totalCount: 1,
                page: 1,
                pageSize: 20,
                hasMore: false,
              ),
            },
          ),
        );

        notifier.setSearchOrder(SearchOrder.playCount);
        await pumpUntil(
          () => notifier.state.isLoading,
          reason: 'changing the order should start a new search',
        );

        expect(notifier.state.searchOrder, SearchOrder.playCount);
        expect(notifier.state.isLoading, isTrue);
        expect(
          notifier.state.onlineResults[SourceIds.youtube]?.tracks.map(
            (track) => track.sourceId,
          ),
          ['old-youtube'],
        );

        gate.complete();
        await pumpUntil(
          () => !notifier.state.isLoading,
          reason: 'the reordered search should finish once its gate opens',
        );

        expect(notifier.state.isLoading, isFalse);
        expect(
          notifier.state.onlineResults[SourceIds.youtube]?.tracks.map(
            (track) => track.sourceId,
          ),
          ['new-youtube'],
        );
      },
    );

    test('clear cancels a delayed video search completion', () async {
      final onlineGate = service.enqueueOnlineSearchResult(
        MultiSourceSearchResult(
          query: 'slow query',
          results: {
            SourceIds.youtube: SearchResult(
              tracks: [_track('late-video-result')],
              totalCount: 1,
              page: 1,
              pageSize: 20,
              hasMore: false,
            ),
          },
        ),
      );

      final searchFuture = notifier.search('slow query');
      await pumpUntil(
        () => notifier.state.isLoading,
        reason: 'the slow search should be in flight before it is cleared',
      );

      notifier.clear();
      onlineGate.complete();
      await searchFuture;

      expect(notifier.state.query, isEmpty);
      expect(notifier.state.onlineResults, isEmpty);
      expect(notifier.state.localResults, isEmpty);
    });

    test('clear cancels a delayed live-room search completion', () async {
      notifier.setSeedState(
        const SearchState(liveRoomFilter: LiveRoomFilter.online),
      );

      final searchFuture = notifier.searchLiveRooms('slow live');
      await pumpUntil(
        () => liveSource.calls.isNotEmpty,
        reason: 'the slow live search should reach the source',
      );
      expect(liveSource.calls.single, 'slow live:1:online');

      notifier.clear();
      liveSource.completeLiveRooms(
        'slow live',
        1,
        LiveRoomFilter.online,
        LiveSearchResult(
          rooms: [_room(9)],
          totalCount: 1,
          page: 1,
          pageSize: 20,
          hasMore: false,
        ),
      );
      await searchFuture;

      expect(notifier.state.query, isEmpty);
      expect(notifier.state.liveRoomResults, isNull);
    });
  });
}

Track _track(String sourceId, {String sourceType = SourceIds.youtube}) {
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
        trackRepository: TrackRepository(FakeIsar()),
        searchHistoryRepository: SearchHistoryRepository(FakeIsar()),
      );

  final List<({String sourceType, String query, int page, SearchOrder order})>
  sourceCalls = [];
  final List<({String query, List<String> sourceTypes, SearchOrder order})>
  onlineCalls = [];
  final List<_PendingOnlineSearch> _pendingOnlineSearches = [];
  final Map<String, Completer<SearchResult>> _sourceCompleters = {};
  List<Track> localResults = [];

  @override
  Future<List<Track>> searchLocal(String query) async => localResults;

  Completer<void> enqueueOnlineSearchResult(MultiSourceSearchResult result) {
    final gate = Completer<void>();
    _pendingOnlineSearches.add(_PendingOnlineSearch(gate, result));
    return gate;
  }

  @override
  Future<MultiSourceSearchResult> searchOnline(
    String query, {
    List<String>? sourceTypes,
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    final requestedSources = List<String>.from(sourceTypes ?? const []);
    onlineCalls.add((
      query: query,
      sourceTypes: requestedSources,
      order: order,
    ));
    if (_pendingOnlineSearches.isNotEmpty) {
      final pending = _pendingOnlineSearches.removeAt(0);
      await pending.gate.future;
      return pending.result;
    }
    return MultiSourceSearchResult(
      query: query,
      results: {
        for (final sourceType in requestedSources)
          sourceType: SearchResult(
            tracks: [_track('$sourceType-$query', sourceType: sourceType)],
            totalCount: 1,
            page: page,
            pageSize: pageSize,
            hasMore: false,
          ),
      },
    );
  }

  @override
  Future<SearchResult> searchSource(
    String sourceType,
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
    String sourceType,
    String query,
    int page,
    SearchResult result,
  ) {
    _sourceCompleters[_sourceKey(sourceType, query, page)]!.complete(result);
  }

  String _sourceKey(String sourceType, String query, int page) =>
      '$sourceType|$query|$page';
}

class _PendingOnlineSearch {
  _PendingOnlineSearch(this.gate, this.result);

  final Completer<void> gate;
  final MultiSourceSearchResult result;
}

class _CompletingLiveSource implements LiveSource {
  @override
  String get sourceType => SourceIds.bilibili;

  final calls = <String>[];
  final Map<String, Completer<LiveSearchResult>> _liveCompleters = {};

  @override
  Future<LiveSearchResult> searchLiveRooms(
    String query, {
    int page = 1,
    int pageSize = 20,
    LiveRoomFilter filter = LiveRoomFilter.all,
  }) {
    calls.add('$query:$page:${filter.name}');
    return _liveCompleters
        .putIfAbsent(_liveKey(query, page, filter), Completer.new)
        .future;
  }

  @override
  Future<String?> getLiveStreamUrl(int roomId) async {
    return 'https://live.example/$roomId.flv';
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
