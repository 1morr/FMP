import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 啟動時資料庫出的狀況，提示層在啟動時提示一次（`ui/toast/`）。
enum StorageNotice {
  /// 資料庫開不起來：這次什麼都不保存，App 照常能搜尋、播放。
  databaseUnavailable,

  /// 上次的佇列讀不回來：讀不了的那份已另存，從空佇列開始。
  queueUnreadable,
}

/// `main` 依 `openStorage` 的結果 override 進來；沒有狀況（含測試沒給）時
/// 是 null。
final storageNoticeProvider = Provider<StorageNotice?>((ref) => null);
