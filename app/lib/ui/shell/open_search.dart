import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 巢狀導覽裡的頁面（歷史頁的空狀態）請外殼切到搜尋目的地。
///
/// 外殼在 `initState` 把 [handler] 接上（同 `OpenQueue`）；沒有外殼時（單獨測一個頁面）
/// 什麼都不做。
final openSearchProvider = Provider<OpenSearch>((ref) => OpenSearch());

final class OpenSearch {
  void Function()? handler;

  void call() => handler?.call();
}
