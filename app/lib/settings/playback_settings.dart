import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';
import 'package:fmp/domain/output_device.dart';
import 'package:fmp/domain/stream_preferences.dart';

/// 設定頁「臨時播放回佇列倒退秒數」的選項（沿用舊版 `_rewindOptions`）。
const tempPlayRewindOptionsSeconds = [0, 3, 5, 10, 15, 30];

/// 設定頁「重啟恢復倒退秒數」的選項（同臨時播放回佇列倒退）。
const restartRewindOptionsSeconds = tempPlayRewindOptionsSeconds;

/// 設定頁「播放歷史保留筆數」的選項（沿用舊版 `_options`）。
const playHistoryLimitOptions = [1000, 5000, 10000, 50000];

/// 「播放」設定套用預設之後的值（ADR 0011 §決定 7、design §3.3）。只有已經
/// 有人用的欄位；其他欄位跟著用到它的 PR 加。
@immutable
final class PlaybackPreferences {
  const PlaybackPreferences({
    required this.audioQuality,
    required this.audioFormatPriority,
    required this.rememberPosition,
    required this.tempPlayRewindSeconds,
    required this.skipPreviewClips,
    required this.outputDevice,
    required this.restartRewindSeconds,
    required this.playHistoryLimit,
    required this.autoScrollToCurrent,
    required this.stored,
  });

  /// 音質：插件依它挑串流（`StreamRequest.quality`）。
  final AudioQuality audioQuality;

  /// 格式偏好：宿主依它重排平台可播的格式再交給插件。
  final AudioFormatPriority audioFormatPriority;

  /// 記住播放位置：臨時播放結束回到佇列時從原本的位置（倒退
  /// [tempPlayRewindSeconds]）繼續，否則從頭。
  final bool rememberPosition;

  /// 臨時播放回到佇列時倒退幾秒。
  final int tempPlayRewindSeconds;

  /// 跳過試聽片段：插件說只有試聽片段時跳過並提示；關著就照播並標「試聽」
  /// （ADR 0018 §決定 7、D4）。
  final bool skipPreviewClips;

  /// 記住的輸出裝置（只有 Windows 能選）；`null` 是系統預設。沒有預設可套：
  /// 沒設定過就是系統預設。裝置不在時仍留著（design §7.6）。
  final OutputDevice? outputDevice;

  /// 重啟後恢復播放時，從存下的位置倒退幾秒（「記住播放位置」開著時才有作用）。
  final int restartRewindSeconds;

  /// 播放歷史保留筆數：每寫一筆就裁掉超過的最舊列，改小時當下裁一次。
  final int playHistoryLimit;

  /// 切歌時把佇列清單捲到目前這首（只在清單開著時：播放頁的佇列分頁或底部面板）。
  final bool autoScrollToCurrent;

  /// 使用者設定過的值；欄位為 `null` 表示沒設定過、目前用的是預設。
  final PlaybackSettings stored;

  @override
  bool operator ==(Object other) =>
      other is PlaybackPreferences &&
      other.audioQuality == audioQuality &&
      other.audioFormatPriority == audioFormatPriority &&
      other.rememberPosition == rememberPosition &&
      other.tempPlayRewindSeconds == tempPlayRewindSeconds &&
      other.skipPreviewClips == skipPreviewClips &&
      other.outputDevice == outputDevice &&
      other.restartRewindSeconds == restartRewindSeconds &&
      other.playHistoryLimit == playHistoryLimit &&
      other.autoScrollToCurrent == autoScrollToCurrent &&
      other.stored == stored;

  @override
  int get hashCode => Object.hash(
    audioQuality,
    audioFormatPriority,
    rememberPosition,
    tempPlayRewindSeconds,
    skipPreviewClips,
    outputDevice,
    restartRewindSeconds,
    playHistoryLimit,
    autoScrollToCurrent,
    stored,
  );

  @override
  String toString() =>
      'PlaybackPreferences(audioQuality: $audioQuality, '
      'audioFormatPriority: $audioFormatPriority, '
      'rememberPosition: $rememberPosition, '
      'tempPlayRewindSeconds: $tempPlayRewindSeconds, '
      'skipPreviewClips: $skipPreviewClips, outputDevice: $outputDevice, '
      'restartRewindSeconds: $restartRewindSeconds, '
      'playHistoryLimit: $playHistoryLimit, '
      'autoScrollToCurrent: $autoScrollToCurrent, stored: $stored)';
}

/// 在讀取時套用預設：沒設定過的欄位用傳進來的預設。預設值不寫進資料庫，改
/// 預設不需要 migration。
PlaybackPreferences resolvePlaybackPreferences(
  PlaybackSettings stored, {
  required AudioQuality defaultAudioQuality,
  required AudioFormatPriority defaultAudioFormatPriority,
  required bool defaultRememberPosition,
  required int defaultTempPlayRewindSeconds,
  required bool defaultSkipPreviewClips,
  required int defaultRestartRewindSeconds,
  required int defaultPlayHistoryLimit,
  required bool defaultAutoScrollToCurrent,
}) => PlaybackPreferences(
  audioQuality: stored.audioQuality ?? defaultAudioQuality,
  audioFormatPriority: stored.audioFormatPriority ?? defaultAudioFormatPriority,
  rememberPosition: stored.rememberPosition ?? defaultRememberPosition,
  tempPlayRewindSeconds:
      stored.tempPlayRewindSeconds ?? defaultTempPlayRewindSeconds,
  skipPreviewClips: stored.skipPreviewClips ?? defaultSkipPreviewClips,
  outputDevice: switch (stored.outputDeviceId) {
    final id? => OutputDevice(id: id, name: stored.outputDeviceName ?? id),
    null => null,
  },
  restartRewindSeconds:
      stored.restartRewindSeconds ?? defaultRestartRewindSeconds,
  playHistoryLimit: stored.playHistoryLimit ?? defaultPlayHistoryLimit,
  autoScrollToCurrent: stored.autoScrollToCurrent ?? defaultAutoScrollToCurrent,
  stored: stored,
);

/// 「播放」設定：監看 `playback_settings` 那一列，對外是套用預設後的
/// [PlaybackPreferences]。
final playbackPreferencesProvider =
    StreamNotifierProvider<PlaybackPreferencesNotifier, PlaybackPreferences>(
      PlaybackPreferencesNotifier.new,
    );

final class PlaybackPreferencesNotifier
    extends StreamNotifier<PlaybackPreferences> {
  /// [stored] 套用目前的預設（音質：高、格式：Opus 優先，照舊版；記住播放
  /// 位置：開；倒退 10 秒，照舊版；跳過試聽片段：開，ADR 0018 §決定 7；重啟恢復倒退 0 秒；播放歷史保留 10000 筆，照舊版；切歌時捲到目前歌曲：關，照舊版）。預設
  /// 只寫在這裡；資料庫還沒讀出來時，播放控制器也以它解析空的設定。
  static PlaybackPreferences resolve(PlaybackSettings stored) =>
      resolvePlaybackPreferences(
        stored,
        defaultAudioQuality: AudioQuality.high,
        defaultAudioFormatPriority: AudioFormatPriority.opusFirst,
        defaultRememberPosition: true,
        defaultTempPlayRewindSeconds: 10,
        defaultSkipPreviewClips: true,
        defaultRestartRewindSeconds: 0,
        defaultPlayHistoryLimit: _defaultPlayHistoryLimit,
        defaultAutoScrollToCurrent: false,
      );

  static const _defaultPlayHistoryLimit = 10000;

  @override
  Stream<PlaybackPreferences> build() =>
      ref.watch(playbackSettingsRepositoryProvider).watch().map(resolve);

  /// 只寫「音質」；`null` 清回沒設定過（跟隨預設）。
  Future<void> setAudioQuality(AudioQuality? quality) {
    final repository = ref.read(playbackSettingsRepositoryProvider);
    return quality == null
        ? repository.clear(audioQuality: true)
        : repository.write(audioQuality: quality);
  }

  /// 只寫「格式偏好」；`null` 清回沒設定過（跟隨預設）。
  Future<void> setAudioFormatPriority(AudioFormatPriority? priority) {
    final repository = ref.read(playbackSettingsRepositoryProvider);
    return priority == null
        ? repository.clear(audioFormatPriority: true)
        : repository.write(audioFormatPriority: priority);
  }

  /// 只寫「記住播放位置」；`null` 清回沒設定過（跟隨預設）。
  Future<void> setRememberPosition(bool? remember) {
    final repository = ref.read(playbackSettingsRepositoryProvider);
    return remember == null
        ? repository.clear(rememberPosition: true)
        : repository.write(rememberPosition: remember);
  }

  /// 只寫「跳過試聽片段」；`null` 清回沒設定過（跟隨預設）。
  Future<void> setSkipPreviewClips(bool? skip) {
    final repository = ref.read(playbackSettingsRepositoryProvider);
    return skip == null
        ? repository.clear(skipPreviewClips: true)
        : repository.write(skipPreviewClips: skip);
  }

  /// 只寫「輸出裝置」（`output_device_id` 與顯示用的 `output_device_name`
  /// 兩欄一起）；`null` 清回沒設定過（系統預設）。
  Future<void> setOutputDevice(OutputDevice? device) {
    final repository = ref.read(playbackSettingsRepositoryProvider);
    return device == null
        ? repository.clear(outputDeviceId: true, outputDeviceName: true)
        : repository.write(
            outputDeviceId: device.id,
            outputDeviceName: device.name,
          );
  }

  /// 只寫「臨時播放回佇列倒退秒數」；`null` 清回沒設定過（跟隨預設）。
  Future<void> setTempPlayRewindSeconds(int? seconds) {
    final repository = ref.read(playbackSettingsRepositoryProvider);
    return seconds == null
        ? repository.clear(tempPlayRewindSeconds: true)
        : repository.write(tempPlayRewindSeconds: seconds);
  }

  /// 只寫「重啟恢復時倒退秒數」；`null` 清回沒設定過（跟隨預設）。
  Future<void> setRestartRewindSeconds(int? seconds) {
    final repository = ref.read(playbackSettingsRepositoryProvider);
    return seconds == null
        ? repository.clear(restartRewindSeconds: true)
        : repository.write(restartRewindSeconds: seconds);
  }

  /// 只寫「播放歷史保留筆數」；`null` 清回沒設定過（跟隨預設）。寫完當下依生效
  /// 的筆數裁掉歷史裡多的最舊列（改小時才有東西可裁）。
  Future<void> setPlayHistoryLimit(int? limit) async {
    final repository = ref.read(playbackSettingsRepositoryProvider);
    if (limit == null) {
      await repository.clear(playHistoryLimit: true);
    } else {
      await repository.write(playHistoryLimit: limit);
    }
    await ref
        .read(playHistoryRepositoryProvider)
        .trimTo(limit ?? _defaultPlayHistoryLimit);
  }

  /// 只寫「切歌時捲到目前歌曲」；`null` 清回沒設定過（跟隨預設）。
  Future<void> setAutoScrollToCurrent(bool? enabled) {
    final repository = ref.read(playbackSettingsRepositoryProvider);
    return enabled == null
        ? repository.clear(autoScrollToCurrent: true)
        : repository.write(autoScrollToCurrent: enabled);
  }
}
