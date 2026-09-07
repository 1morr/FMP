import 'dart:async';

import '../../core/logger.dart';
import '../../data/models/track.dart';
import '../../data/repositories/settings_repository.dart';
import '../lyrics/lyrics_auto_match_service.dart';

/// 每次開始播一首新歌時，在背景替它找歌詞。
///
/// 播放路徑**不等它**：[onTrackStarted] 立刻回傳，比對整段跑在自己的 future 裡。
///
/// 它自己帶請求代際（[_requestId]）。切歌比配歌詞快得多，沒有這道防護的話，上一首
/// 的比對回來時會把「正在比對」的 UI 指示器關掉 —— 而那時新歌其實還在比對中。
/// `audio_controller_phase1_test.dart` 的 `stale lyrics auto-match cannot clear
/// newer loading state` 就是在守這件事。
///
/// [service] / [settingsRepository] 為 null 是正常情況（資料庫還沒初始化），這時
/// 整個自動比對靜默略過。
class LyricsAutoMatchCoordinator with Logging {
  LyricsAutoMatchCoordinator({
    LyricsAutoMatchService? service,
    SettingsRepository? settingsRepository,
  }) : _service = service,
       _settingsRepository = settingsRepository;

  final LyricsAutoMatchService? _service;
  final SettingsRepository? _settingsRepository;

  /// 通知 UI 現在是否正在比對。由 `AudioController` 轉接到
  /// `lyricsAutoMatchingProvider`。
  void Function(bool isMatching)? onStateChanged;

  int _requestId = 0;
  bool _disposed = false;

  /// 開始為 [track] 找歌詞。fire-and-forget。
  void onTrackStarted(Track track) {
    unawaited(_run(track));
  }

  /// 讓所有還在飛的比對在下一個檢查點自行放棄，並停止回報 UI 狀態。
  void dispose() {
    _disposed = true;
    _requestId++;
    onStateChanged = null;
  }

  Future<void> _run(Track track) async {
    final requestId = ++_requestId;
    final service = _service;
    final settingsRepo = _settingsRepository;
    if (service == null || settingsRepo == null) return;

    try {
      final settings = await settingsRepo.get();
      if (_isStale(requestId)) return;
      if (!settings.autoMatchLyrics) {
        logDebug('Auto-match lyrics disabled in settings');
        return;
      }

      onStateChanged?.call(true);

      // 按使用者配置的來源優先序，扣掉被停用的。
      final enabledSources = settings.lyricsSourcePriorityList
          .where((s) => !settings.disabledLyricsSourcesSet.contains(s))
          .toList();
      final matched = await service.tryAutoMatch(
        track,
        enabledSources: enabledSources,
        allowPlainLyricsAutoMatch: settings.allowPlainLyricsAutoMatch,
      );
      if (_isStale(requestId)) return;
      if (matched) {
        logInfo('Auto-matched lyrics for: ${track.title}');
      }
    } catch (e) {
      if (!_isStale(requestId)) {
        logWarning('Auto-match lyrics failed for ${track.title}: $e');
      }
    } finally {
      if (!_isStale(requestId)) {
        onStateChanged?.call(false);
      }
    }
  }

  bool _isStale(int requestId) => _disposed || requestId != _requestId;
}
