import 'dart:async';

import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';

/// 把「這首歌被播了」寫進播放歷史。
///
/// 播放路徑**不等它**：每次呼叫都排進一個 microtask，例外只記 log。寫歷史失敗
/// 是統計少一筆，不該讓歌停下來。
///
/// `repository` 為 null 是正常情況 —— 資料庫還沒初始化時
/// `audioControllerProvider` 就是傳 null 進來的（見 `audio_provider.dart` 的
/// provider 工廠）。這時整個記錄行為靜默略過。
///
/// 它刻意不決定「什麼算一次播放」。那個判斷屬於 `AudioController`
/// （`countsAsNewPlay` 旗標），因為只有它知道這次是使用者切歌、重試、還是啟動還原。
class PlayHistoryRecorder with Logging {
  PlayHistoryRecorder({PlayHistoryRepository? repository})
    : _repository = repository;

  final PlayHistoryRepository? _repository;

  /// fire-and-forget 記錄一次播放。
  void record(Track track) {
    final repo = _repository;
    if (repo == null) return;

    unawaited(
      Future.microtask(() async {
        try {
          await repo.addHistory(track);
          logDebug('Recorded play history: ${track.title}');
        } catch (e) {
          logWarning('Failed to record play history: $e');
        }
      }),
    );
  }
}
