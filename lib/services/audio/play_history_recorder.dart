import 'dart:async';

import 'package:fmp/core/logger.dart';
import 'package:fmp/data/models/track.dart';
import 'package:fmp/data/repositories/play_history_repository.dart';
import 'package:fmp/data/repositories/settings_repository.dart';

/// 把「這首歌被播了」寫進播放歷史。
///
/// 播放路徑**不等它**：每次呼叫都排進一個 microtask，例外只記 log。寫歷史失敗
/// 是統計少一筆，不該讓歌停下來。
///
/// `repository` / `settingsRepository` 為 null 是正常情況 —— 資料庫還沒初始化時
/// `audioControllerProvider` 就是傳 null 進來的（見 `audio_provider.dart` 的
/// provider 工廠）。這時整個記錄行為靜默略過。
///
/// 它刻意不決定「什麼算一次播放」。那個判斷屬於 `AudioController`
/// （`countsAsNewPlay` 旗標），因為只有它知道這次是使用者切歌、重試、還是啟動還原。
///
/// 保留上限每次寫入都重讀一次 `Settings`：使用者調小上限之後不必等重啟，而這是
/// 一次本機的單列讀取，跟後面那次寫入比可以忽略。倉庫自己不讀設定（資料層不得往
/// 上 import），所以這個數字只能由這裡帶進去。
class PlayHistoryRecorder with Logging {
  PlayHistoryRecorder({
    PlayHistoryRepository? repository,
    SettingsRepository? settingsRepository,
  }) : _repository = repository,
       _settingsRepository = settingsRepository;

  final PlayHistoryRepository? _repository;
  final SettingsRepository? _settingsRepository;

  /// fire-and-forget 記錄一次播放。
  void record(Track track) {
    final repo = _repository;
    final settingsRepo = _settingsRepository;
    if (repo == null || settingsRepo == null) return;

    unawaited(
      Future.microtask(() async {
        try {
          final settings = await settingsRepo.get();
          await repo.addHistory(track, keepAtMost: settings.playHistoryLimit);
          logDebug(
            'Recorded play history: ${track.title} '
            '(keepAtMost: ${settings.playHistoryLimit})',
          );
        } catch (e) {
          logWarning('Failed to record play history: $e');
        }
      }),
    );
  }
}
