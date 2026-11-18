import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 啟動時資料庫開不起來：這次什麼都不保存，App 照常能搜尋、播放，提示層在
/// 啟動時提示一次。`main` override 進來；測試沒給時是 false。
final databaseUnavailableProvider = Provider<bool>((ref) => false);
