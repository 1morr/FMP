import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/search_history_store.dart';

/// 搜尋紀錄，新到舊。沒有資料庫時只在記憶體裡。
final searchHistoryProvider =
    AsyncNotifierProvider<SearchHistory, List<String>>(SearchHistory.new);

/// 搜尋紀錄（brief〈搜尋〉）：同一個字串再搜一次移到最前、不重複，最多
/// [SearchHistoryStore.limit] 筆，空字串不記。狀態先更新再寫入，畫面不等
/// I/O；寫入失敗只記 log（不含查詢內容），狀態照常。
class SearchHistory extends AsyncNotifier<List<String>> {
  SearchHistoryStore? get _store => ref.read(searchHistoryStoreProvider);

  /// 上一次寫的時間戳；同一毫秒內連記兩個時以後者為新。
  int _lastAt = 0;

  /// 寫入依序進行。
  Future<void> _last = Future.value();

  @override
  Future<List<String>> build() async {
    final store = ref.watch(searchHistoryStoreProvider);
    if (store == null) return const [];
    try {
      return await store.load();
    } on Object catch (error, stackTrace) {
      ref
          .read(logProvider)
          .error(
            'Loading the search history failed',
            error: error,
            stackTrace: stackTrace,
          );
      return const [];
    }
  }

  List<String> get _current => state.value ?? const [];

  /// 記下一次搜尋。[query] 先 trim，空的不記。
  Future<void> record(String query) async {
    final text = query.trim();
    if (text.isEmpty) return;
    // 還在讀時先等讀完，讀回來的清單才不會蓋掉這一筆。
    await future;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _lastAt = nowMs > _lastAt ? nowMs : _lastAt + 1;
    final at = DateTime.fromMillisecondsSinceEpoch(_lastAt);
    state = AsyncData(
      [
        text,
        for (final item in _current)
          if (item != text) item,
      ].take(SearchHistoryStore.limit).toList(),
    );
    return _write((store) => store.record(text, at));
  }

  Future<void> remove(String query) async {
    await future;
    state = AsyncData([
      for (final item in _current)
        if (item != query) item,
    ]);
    return _write((store) => store.remove(query));
  }

  Future<void> clear() async {
    await future;
    state = const AsyncData([]);
    return _write((store) => store.clear());
  }

  Future<void> _write(Future<void> Function(SearchHistoryStore) write) {
    final store = _store;
    if (store == null) return Future.value();
    final log = ref.read(logProvider);
    return _last = _last.then((_) => write(store)).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      log.error(
        'Saving the search history failed',
        error: error,
        stackTrace: stackTrace,
      );
    });
  }
}
