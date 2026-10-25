import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 空狀態的「去搜尋」（佇列頁、巢狀導覽裡的歷史頁）請外殼切到搜尋目的地。
///
/// 外殼在 `initState` 把 [handler] 接上（同 `OpenQueue`）；沒有外殼時（單獨測一個頁面）
/// 什麼都不做。
final openSearchProvider = Provider<OpenSearch>((ref) => OpenSearch());

final class OpenSearch {
  void Function()? handler;

  void call() => handler?.call();
}
