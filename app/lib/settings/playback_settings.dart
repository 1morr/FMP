import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fmp/data/providers.dart';
import 'package:fmp/data/repositories/playback_settings_repository.dart';

/// 設定頁「臨時播放回佇列倒退秒數」的選項（沿用舊版 `_rewindOptions`）。
const tempPlayRewindOptionsSeconds = [0, 3, 5, 10, 15, 30];

/// 「播放」設定套用預設之後的值（ADR 0011 §決定 7、design §3.3）。只有已經
/// 有人用的欄位；其他欄位跟著用到它的 PR 加。
@immutable
final class PlaybackPreferences {
  const PlaybackPreferences({
    required this.rememberPosition,
    required this.tempPlayRewindSeconds,
    required this.stored,
  });

  /// 記住播放位置：臨時播放結束回到佇列時從原本的位置（倒退
  /// [tempPlayRewindSeconds]）繼續，否則從頭。
  final bool rememberPosition;

  /// 臨時播放回到佇列時倒退幾秒。
  final int tempPlayRewindSeconds;

  /// 使用者設定過的值；欄位為 `null` 表示沒設定過、目前用的是預設。
  final PlaybackSettings stored;

  @override
  bool operator ==(Object other) =>
      other is PlaybackPreferences &&
      other.rememberPosition == rememberPosition &&
      other.tempPlayRewindSeconds == tempPlayRewindSeconds &&
      other.stored == stored;

  @override
  int get hashCode =>
      Object.hash(rememberPosition, tempPlayRewindSeconds, stored);

  @override
  String toString() =>
      'PlaybackPreferences(rememberPosition: $rememberPosition, '
      'tempPlayRewindSeconds: $tempPlayRewindSeconds, stored: $stored)';
}

/// 在讀取時套用預設：沒設定過的欄位用傳進來的預設。預設值不寫進資料庫，改
/// 預設不需要 migration。
PlaybackPreferences resolvePlaybackPreferences(
  PlaybackSettings stored, {
  required bool defaultRememberPosition,
  required int defaultTempPlayRewindSeconds,
}) => PlaybackPreferences(
  rememberPosition: stored.rememberPosition ?? defaultRememberPosition,
  tempPlayRewindSeconds:
      stored.tempPlayRewindSeconds ?? defaultTempPlayRewindSeconds,
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
  /// [stored] 套用目前的預設（記住播放位置：開；倒退 10 秒，照舊版）。預設只
  /// 寫在這裡；資料庫還沒讀出來時，播放控制器也以它解析空的設定。
  static PlaybackPreferences resolve(PlaybackSettings stored) =>
      resolvePlaybackPreferences(
        stored,
        defaultRememberPosition: true,
        defaultTempPlayRewindSeconds: 10,
      );

  @override
  Stream<PlaybackPreferences> build() =>
      ref.watch(playbackSettingsRepositoryProvider).watch().map(resolve);

  /// 只寫「記住播放位置」；`null` 清回沒設定過（跟隨預設）。
  Future<void> setRememberPosition(bool? remember) {
    final repository = ref.read(playbackSettingsRepositoryProvider);
    return remember == null
        ? repository.clear(rememberPosition: true)
        : repository.write(rememberPosition: remember);
  }

  /// 只寫「臨時播放回佇列倒退秒數」；`null` 清回沒設定過（跟隨預設）。
  Future<void> setTempPlayRewindSeconds(int? seconds) {
    final repository = ref.read(playbackSettingsRepositoryProvider);
    return seconds == null
        ? repository.clear(tempPlayRewindSeconds: true)
        : repository.write(tempPlayRewindSeconds: seconds);
  }
}
