import 'package:flutter_test/flutter_test.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_capabilities.dart';
import 'package:fmp/data/sources/source_provider.dart';

/// 最小 SearchSource fake：只實作 search（其餘能力 searchAll 用不到）。
class _FakeSearchSource implements SearchSource {
  _FakeSearchSource(this.sourceType, this._behaviour);

  @override
  final SourceType sourceType;

  final Future<SearchResult> Function(String query) _behaviour;

  @override
  Future<SearchResult> search(
    String query, {
    int page = 1,
    int pageSize = 20,
    SearchOrder order = SearchOrder.relevance,
  }) =>
      _behaviour(query);
}

void main() {
  test(
      'searchAll preserves partial results when one source throws '
      '(B9: silent catch now logs instead of swallowing)', () async {
    final manager = SourceManager(
      sources: [
        _FakeSearchSource(
          SourceType.youtube,
          (_) async => SearchResult(
            tracks: [Track()..sourceType = SourceType.youtube],
            totalCount: 1,
            page: 1,
            pageSize: 1,
            hasMore: false,
          ),
        ),
        _FakeSearchSource(
          SourceType.bilibili,
          (_) async => throw Exception('bilibili down'),
        ),
      ],
    );
    addTearDown(manager.dispose);

    final results = await manager.searchAll('any query');

    // 失敗源被略過，成功源的結果仍回傳（部分結果語義不變）。
    expect(results, hasLength(1));
    expect(results.keys, contains(SourceType.youtube));
    expect(results[SourceType.youtube]!.tracks, hasLength(1));
    expect(results.keys, isNot(contains(SourceType.bilibili)));
  });
}
