import 'package:flutter/foundation.dart';

/// 匯入或刷新讀到哪裡了（ADR 0035 §決定 11）：每一頁寫進資料庫後回報一次。
@immutable
final class ImportProgress {
  const ImportProgress({
    required this.count,
    this.total,
    this.expectedTotal,
    this.currentTitle,
  });

  /// 這次已寫入（已讀）的項目數。
  final int count;

  /// 插件在頁面上給的總數（`PlaylistPage.total`）。
  final int? total;

  /// 呼叫端事先知道的總數（帳號歌單清單的 `trackCount`）；沒有 [total] 時才用。
  final int? expectedTotal;

  /// 最後寫入的那一首的標題（只給畫面，不寫 log）。
  final String? currentTitle;

  /// 顯示用的 M：[total] 優先，其次 [expectedTotal]；兩者都沒有或不合理（0、小於已讀）時是 `null`，
  /// 畫面改顯示「已讀 n 首」。
  int? get displayTotal {
    final m = total ?? expectedTotal;
    return m == null || m <= 0 || m < count ? null : m;
  }

  ImportProgress withExpectedTotal(int? expected) => ImportProgress(
    count: count,
    total: total,
    expectedTotal: expected,
    currentTitle: currentTitle,
  );

  @override
  bool operator ==(Object other) =>
      other is ImportProgress &&
      other.count == count &&
      other.total == total &&
      other.expectedTotal == expectedTotal &&
      other.currentTitle == currentTitle;

  @override
  int get hashCode => Object.hash(count, total, expectedTotal, currentTitle);
}

/// 使用者要求取消一次匯入。匯入在寫下一頁之前檢查 [isCancelled]。新匯入的歌單整張放棄（含已寫的頁）；
/// 既有歌單的重新匯入或刷新只是停下，已寫的頁留著（`partial`）。
final class ImportCancel {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}
