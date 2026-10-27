import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/core/errors/app_error.dart';
import 'package:fmp/plugins/search/all_sources_search.dart';
import 'package:fmp/plugins/source_dto.dart';
import 'package:fmp/plugins/source_plugin.dart';

import '../../playback/fake_source_plugin.dart';

// 「全部音源」搜尋的引擎（ADR 0035 §決定 9）：同時最多 3 個請求、結果依音源順序分組、
// 各組自己的頁碼與錯誤、舊搜尋的結果丟掉。全部用假插件，不連網。

/// 假插件的一次搜尋請求：測試決定什麼時候、怎麼完成。
final class _Call {
  _Call(this.pluginId, this.page);

  final String pluginId;
  final int page;
  final done = Completer<SearchPage>();
}

TrackSummary _track(String plugin, String id) => TrackSummary(
  sourceTypeId: plugin,
  sourceId: id,
  title: 'Song $id',
  uploader: null,
  duration: const Duration(minutes: 3),
  artwork: const [],
);

SearchPage _page(String plugin, List<String> ids, {bool hasMore = false}) =>
    SearchPage(
      items: [for (final id in ids) _track(plugin, id)],
      hasMore: hasMore,
    );

/// 一組假插件，每次搜尋記一個 [_Call]、等測試完成它。
final class _Fleet {
  _Fleet(List<String> ids) {
    for (final id in ids) {
      plugins.add(
        FakeSourcePlugin(
          (_) => const [],
          id: id,
          name: id,
          onSearch: (query) {
            final call = _Call(id, query.page);
            calls.add(call);
            running++;
            if (running > peak) peak = running;
            return call.done.future.whenComplete(() => running--);
          },
        ),
      );
    }
  }

  final plugins = <SourcePlugin>[];
  final calls = <_Call>[];
  var running = 0;
  var peak = 0;

  _Call call(String plugin, int page) =>
      calls.firstWhere((c) => c.pluginId == plugin && c.page == page);

  AllSourcesSearch<TrackSummary> engine({
    RequestPool? pool,
    void Function(String, AppError, int)? onError,
    List<List<SourceGroup<TrackSummary>>>? changes,
  }) => AllSourcesSearch<TrackSummary>(
    plugins: plugins,
    fetch: (plugin, page) async {
      final result = await plugin.search(SearchQuery(keyword: 'k', page: page));
      return GroupPage(items: result.items, hasMore: result.hasMore);
    },
    keyOf: (track) => (track.sourceTypeId, track.sourceId),
    pool: pool ?? RequestPool(3),
    onChanged: (groups) => changes?.add(groups),
    onError: onError ?? (_, _, _) {},
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'at most three requests are in flight; the rest wait their turn',
    () async {
      final fleet = _Fleet(['a', 'b', 'c', 'd', 'e']);
      final search = fleet.engine();
      final done = search.start();
      await _settle();

      expect(fleet.calls.map((c) => c.pluginId), ['a', 'b', 'c']);
      fleet.call('b', 1).done.complete(_page('b', ['b1']));
      await _settle();
      expect(fleet.calls.map((c) => c.pluginId), ['a', 'b', 'c', 'd']);
      fleet.call('a', 1).done.complete(_page('a', ['a1']));
      fleet.call('c', 1).done.complete(_page('c', ['c1']));
      await _settle();
      expect(fleet.calls.map((c) => c.pluginId), ['a', 'b', 'c', 'd', 'e']);
      fleet.call('d', 1).done.complete(_page('d', ['d1']));
      fleet.call('e', 1).done.complete(_page('e', ['e1']));
      await done;

      expect(fleet.peak, 3);
      expect(search.groups.every((g) => g.phase == GroupPhase.loaded), isTrue);
    },
  );

  test('groups keep the plugin order whatever order they finish in', () async {
    final fleet = _Fleet(['a', 'b', 'c']);
    final search = fleet.engine();
    final done = search.start();
    await _settle();

    fleet.call('c', 1).done.complete(_page('c', ['c1']));
    await _settle();
    expect(search.groups.map((g) => g.pluginId), ['a', 'b', 'c']);
    expect(search.groups.map((g) => g.phase), [
      GroupPhase.loading,
      GroupPhase.loading,
      GroupPhase.loaded,
    ]);
    fleet.call('a', 1).done.complete(_page('a', ['a1']));
    fleet.call('b', 1).done.complete(_page('b', ['b1']));
    await done;

    expect(search.groups.map((g) => g.pluginId), ['a', 'b', 'c']);
    expect(search.groups.map((g) => g.items.single.sourceId), [
      'a1',
      'b1',
      'c1',
    ]);
  });

  test('one failing plugin does not touch the others; retrying reloads only '
      'it', () async {
    final fleet = _Fleet(['a', 'b']);
    final errors = <(String, int)>[];
    final search = fleet.engine(
      onError: (id, _, page) => errors.add((id, page)),
    );
    final done = search.start();
    await _settle();

    fleet.call('a', 1).done.completeError(NetworkError(pluginId: 'a'));
    fleet.call('b', 1).done.complete(_page('b', ['b1'], hasMore: true));
    await done;

    final (a, b) = (search.groups[0], search.groups[1]);
    expect(a.phase, GroupPhase.failed);
    expect(a.error, isA<NetworkError>());
    expect(b.phase, GroupPhase.loaded);
    expect(b.items, hasLength(1));
    expect(errors, [('a', 1)]);

    final retry = search.retry('a');
    await _settle();
    expect(search.groups[0].phase, GroupPhase.loading);
    expect(search.groups[0].error, isNull);
    // 只有 a 重新發請求。
    expect(fleet.calls.where((c) => c.pluginId == 'b'), hasLength(1));
    fleet.calls.last.done.complete(_page('a', ['a1']));
    await retry;

    expect(search.groups[0].phase, GroupPhase.loaded);
    expect(search.groups[0].items.single.sourceId, 'a1');
    expect(search.groups[1], same(b));
    // 只有失敗的才能重試。
    await search.retry('b');
    expect(fleet.calls, hasLength(3));
  });

  test('each group has its own page counter and cursor', () async {
    final fleet = _Fleet(['a', 'b']);
    final search = fleet.engine();
    final done = search.start();
    await _settle();
    fleet.call('a', 1).done.complete(_page('a', ['a1'], hasMore: true));
    fleet.call('b', 1).done.complete(_page('b', ['b1']));
    await done;

    expect(search.groups.map((g) => (g.page, g.hasMore)), [
      (1, true),
      (1, false),
    ]);

    // b 沒有下一頁：什麼都不發。
    await search.loadMore('b');
    expect(fleet.calls, hasLength(2));

    final more = search.loadMore('a');
    await _settle();
    expect(search.groups[0].phase, GroupPhase.loadingMore);
    expect(fleet.calls.last.page, 2, reason: 'a asks for its own page 2');
    fleet.calls.last.done.complete(_page('a', ['a2'], hasMore: true));
    await more;

    expect(search.groups[0].items.map((t) => t.sourceId), ['a1', 'a2']);
    expect(search.groups[0].page, 2);
    expect(search.groups[1].page, 1);
  });

  test('a failed next page keeps the results and can be retried', () async {
    final fleet = _Fleet(['a']);
    final errors = <int>[];
    final search = fleet.engine(onError: (_, _, page) => errors.add(page));
    final done = search.start();
    await _settle();
    fleet.call('a', 1).done.complete(_page('a', ['a1'], hasMore: true));
    await done;

    final more = search.loadMore('a');
    await _settle();
    fleet.calls.last.done.completeError(NetworkError(pluginId: 'a'));
    await more;

    expect(search.groups.single.phase, GroupPhase.loaded);
    expect(search.groups.single.loadMoreFailed, isTrue);
    expect(search.groups.single.items, hasLength(1));
    expect(errors, [2]);

    final again = search.loadMore('a');
    await _settle();
    expect(fleet.calls.last.page, 2);
    fleet.calls.last.done.complete(_page('a', ['a2']));
    await again;
    expect(search.groups.single.loadMoreFailed, isFalse);
    expect(search.groups.single.items, hasLength(2));
  });

  test(
    'a page of repeats pauses auto-loading and adds nothing twice',
    () async {
      final fleet = _Fleet(['a']);
      final search = fleet.engine();
      final done = search.start();
      await _settle();
      fleet.call('a', 1).done.complete(_page('a', ['a1'], hasMore: true));
      await done;

      final more = search.loadMore('a');
      await _settle();
      fleet.calls.last.done.complete(_page('a', ['a1'], hasMore: true));
      await more;

      expect(search.groups.single.items, hasLength(1));
      expect(search.groups.single.autoLoadPaused, isTrue);
    },
  );

  test('results of a cancelled search are dropped; waiting requests are never '
      'sent', () async {
    final fleet = _Fleet(['a', 'b', 'c', 'd']);
    final changes = <List<SourceGroup<TrackSummary>>>[];
    final search = fleet.engine(changes: changes);
    final done = search.start();
    await _settle();
    expect(fleet.calls, hasLength(3));

    search.cancel();
    final before = changes.length;
    for (final call in List.of(fleet.calls)) {
      call.done.complete(_page(call.pluginId, ['x']));
    }
    await done;

    expect(changes, hasLength(before), reason: 'nothing was published');
    expect(
      fleet.calls,
      hasLength(3),
      reason: 'd was still waiting, never sent',
    );
    expect(search.groups.every((g) => g.items.isEmpty), isTrue);
  });

  test(
    'a new search shares the pool with the cancelled one still in flight',
    () async {
      final fleet = _Fleet(['a', 'b', 'c', 'd']);
      final pool = RequestPool(3);
      final old = fleet.engine(pool: pool);
      unawaited(old.start());
      await _settle();
      old.cancel();

      final fresh = fleet.engine(pool: pool);
      unawaited(fresh.start());
      await _settle();
      // 舊的三個請求還沒回來，名額還被佔著。
      expect(fleet.calls, hasLength(3));
      expect(pool.running, 3);

      fleet.call('a', 1).done.complete(_page('a', ['a1']));
      await _settle();
      expect(fleet.calls, hasLength(4));
      expect(fleet.peak, lessThanOrEqualTo(3));
    },
  );
}
