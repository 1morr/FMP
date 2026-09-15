import 'package:fmp/data/sources/base_source.dart';
import 'package:fmp/data/sources/source_provider.dart';

/// 對多個音源並行搜尋，回傳成功音源的結果；單一音源失敗不影響其他音源
/// （部分結果語意）。
///
/// 這是搜尋頁與歌單匯入共用的唯一 fan-out。兩邊對失敗的處置不同 —— 搜尋頁要把
/// 失敗訊息畫出來，匯入只要略過 —— 所以錯誤透過 [onSourceError] 交回呼叫端，這裡
/// 不決定文案也不吞掉：以前 `SourceManager.searchAll` 曾經靜默吞掉單源失敗，
/// 限流與網路錯誤因此完全查不到。
Future<Map<String, SearchResult>> searchSourcesInParallel(
  SourceManager sourceManager,
  String query, {
  required Iterable<String> sourceTypes,
  int page = 1,
  int pageSize = 20,
  SearchOrder order = SearchOrder.relevance,
  required void Function(String sourceType, Object error, StackTrace stack)
  onSourceError,
}) async {
  final results = <String, SearchResult>{};
  await Future.wait(
    sourceTypes.map((type) async {
      final source = sourceManager.searchSource(type);
      if (source == null) return;
      try {
        results[type] = await source.search(
          query,
          page: page,
          pageSize: pageSize,
          order: order,
        );
      } catch (e, stack) {
        onSourceError(type, e, stack);
      }
    }),
  );
  return results;
}
