import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/domain/stream_preferences.dart';

/// 「播放」設定的值（design §3.3）。欄位為 `null` 表示使用者沒設定過
/// （ADR 0011 §決定 7），由上層套用預設值。
@immutable
final class PlaybackSettings {
  const PlaybackSettings({
    this.audioQuality,
    this.audioFormatPriority,
    this.rememberPosition,
    this.tempPlayRewindSeconds,
    this.skipPreviewClips,
    this.outputDeviceId,
    this.outputDeviceName,
    this.restartRewindSeconds,
    this.playHistoryLimit,
    this.autoScrollToCurrent,
  });

  /// 全部沒設定過。
  static const empty = PlaybackSettings();

  final AudioQuality? audioQuality;
  final AudioFormatPriority? audioFormatPriority;

  /// 記住播放位置。
  final bool? rememberPosition;

  /// 臨時播放回到佇列時倒退幾秒。
  final int? tempPlayRewindSeconds;

  /// 跳過試聽片段。
  final bool? skipPreviewClips;

  /// 偏好的輸出裝置（只有 Windows）：mpv 的裝置名與顯示用的描述。
  final String? outputDeviceId;
  final String? outputDeviceName;

  /// 重啟後恢復播放時倒退幾秒。
  final int? restartRewindSeconds;

  /// 播放歷史保留幾筆。
  final int? playHistoryLimit;

  /// 切歌時捲到目前歌曲。
  final bool? autoScrollToCurrent;

  @override
  bool operator ==(Object other) =>
      other is PlaybackSettings &&
      other.audioQuality == audioQuality &&
      other.audioFormatPriority == audioFormatPriority &&
      other.rememberPosition == rememberPosition &&
      other.tempPlayRewindSeconds == tempPlayRewindSeconds &&
      other.skipPreviewClips == skipPreviewClips &&
      other.outputDeviceId == outputDeviceId &&
      other.outputDeviceName == outputDeviceName &&
      other.restartRewindSeconds == restartRewindSeconds &&
      other.playHistoryLimit == playHistoryLimit &&
      other.autoScrollToCurrent == autoScrollToCurrent;

  @override
  int get hashCode => Object.hash(
    audioQuality,
    audioFormatPriority,
    rememberPosition,
    tempPlayRewindSeconds,
    skipPreviewClips,
    outputDeviceId,
    outputDeviceName,
    restartRewindSeconds,
    playHistoryLimit,
    autoScrollToCurrent,
  );

  @override
  String toString() =>
      'PlaybackSettings(audioQuality: $audioQuality, '
      'audioFormatPriority: $audioFormatPriority, '
      'rememberPosition: $rememberPosition, '
      'tempPlayRewindSeconds: $tempPlayRewindSeconds, '
      'skipPreviewClips: $skipPreviewClips, '
      'outputDeviceId: $outputDeviceId, '
      'outputDeviceName: $outputDeviceName, '
      'restartRewindSeconds: $restartRewindSeconds, '
      'playHistoryLimit: $playHistoryLimit, '
      'autoScrollToCurrent: $autoScrollToCurrent)';
}

/// `playback_settings` 單列表的存取。
final class PlaybackSettingsRepository {
  PlaybackSettingsRepository(this._database);

  final AppDatabase _database;

  /// 單列的主鍵；表上的 CHECK 只允許這個值。
  static const _rowId = 1;

  SimpleSelectStatement<$PlaybackSettingsTableTable, PlaybackSettingsRow>
  get _row =>
      _database.select(_database.playbackSettingsTable)
        ..where((t) => t.id.equals(_rowId));

  /// 讀目前的設定；還沒有列時回傳 [PlaybackSettings.empty]。
  Future<PlaybackSettings> read() async =>
      _fromRow(await _row.getSingleOrNull());

  /// 目前的設定，之後每次寫入再發一次。
  Stream<PlaybackSettings> watch() => _row.watchSingleOrNull().map(_fromRow);

  /// 只寫入有給的欄位；沒給的（`null`）維持原值。
  Future<void> write({
    AudioQuality? audioQuality,
    AudioFormatPriority? audioFormatPriority,
    bool? rememberPosition,
    int? tempPlayRewindSeconds,
    bool? skipPreviewClips,
    String? outputDeviceId,
    String? outputDeviceName,
    int? restartRewindSeconds,
    int? playHistoryLimit,
    bool? autoScrollToCurrent,
  }) => _database
      .into(_database.playbackSettingsTable)
      .insertOnConflictUpdate(
        PlaybackSettingsTableCompanion(
          id: const Value(_rowId),
          audioQuality: Value.absentIfNull(audioQuality),
          audioFormatPriority: Value.absentIfNull(audioFormatPriority),
          rememberPosition: Value.absentIfNull(rememberPosition),
          tempPlayRewindSeconds: Value.absentIfNull(tempPlayRewindSeconds),
          skipPreviewClips: Value.absentIfNull(skipPreviewClips),
          outputDeviceId: Value.absentIfNull(outputDeviceId),
          outputDeviceName: Value.absentIfNull(outputDeviceName),
          restartRewindSeconds: Value.absentIfNull(restartRewindSeconds),
          playHistoryLimit: Value.absentIfNull(playHistoryLimit),
          autoScrollToCurrent: Value.absentIfNull(autoScrollToCurrent),
        ),
      );

  /// 把傳 `true` 的欄位清回 `null`（沒設定過，由上層套用預設）；其他欄位不動。
  ///
  /// 和 [write] 分開：[write] 的 `null` 表示「沒給、不動」，所以清空另走這裡。
  Future<void> clear({
    bool audioQuality = false,
    bool audioFormatPriority = false,
    bool rememberPosition = false,
    bool tempPlayRewindSeconds = false,
    bool skipPreviewClips = false,
    bool outputDeviceId = false,
    bool outputDeviceName = false,
    bool restartRewindSeconds = false,
    bool playHistoryLimit = false,
    bool autoScrollToCurrent = false,
  }) {
    final named = [
      audioQuality,
      audioFormatPriority,
      rememberPosition,
      tempPlayRewindSeconds,
      skipPreviewClips,
      outputDeviceId,
      outputDeviceName,
      restartRewindSeconds,
      playHistoryLimit,
      autoScrollToCurrent,
    ];
    if (!named.contains(true)) return Future.value();
    Value<T?> cleared<T>(bool clear) =>
        clear ? const Value(null) : const Value.absent();
    return _database
        .into(_database.playbackSettingsTable)
        .insertOnConflictUpdate(
          PlaybackSettingsTableCompanion(
            id: const Value(_rowId),
            audioQuality: cleared(audioQuality),
            audioFormatPriority: cleared(audioFormatPriority),
            rememberPosition: cleared(rememberPosition),
            tempPlayRewindSeconds: cleared(tempPlayRewindSeconds),
            skipPreviewClips: cleared(skipPreviewClips),
            outputDeviceId: cleared(outputDeviceId),
            outputDeviceName: cleared(outputDeviceName),
            restartRewindSeconds: cleared(restartRewindSeconds),
            playHistoryLimit: cleared(playHistoryLimit),
            autoScrollToCurrent: cleared(autoScrollToCurrent),
          ),
        );
  }

  static PlaybackSettings _fromRow(PlaybackSettingsRow? row) => row == null
      ? PlaybackSettings.empty
      : PlaybackSettings(
          audioQuality: row.audioQuality,
          audioFormatPriority: row.audioFormatPriority,
          rememberPosition: row.rememberPosition,
          tempPlayRewindSeconds: row.tempPlayRewindSeconds,
          skipPreviewClips: row.skipPreviewClips,
          outputDeviceId: row.outputDeviceId,
          outputDeviceName: row.outputDeviceName,
          restartRewindSeconds: row.restartRewindSeconds,
          playHistoryLimit: row.playHistoryLimit,
          autoScrollToCurrent: row.autoScrollToCurrent,
        );
}
