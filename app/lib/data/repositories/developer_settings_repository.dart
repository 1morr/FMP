import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/domain/developer.dart';

/// 「開發者」設定的值（ADR 0025 §決定 1、M3 design §3.3）。欄位為 `null` 表示使用者
/// 沒設定過，由上層套用預設值。
@immutable
final class DeveloperSettings {
  const DeveloperSettings({
    this.developerMode,
    this.logLevel,
    this.pluginDevFolder,
    this.reportReminderDismissed,
  });

  /// 全部沒設定過。
  static const empty = DeveloperSettings();

  final bool? developerMode;
  final LogLevelSetting? logLevel;

  /// 插件開發資料夾的路徑（M3 PR 16 才讀寫）。
  final String? pluginDevFolder;

  /// 「送出前請檢查」不再提醒（M3 PR 13 才讀寫）。
  final bool? reportReminderDismissed;

  @override
  bool operator ==(Object other) =>
      other is DeveloperSettings &&
      other.developerMode == developerMode &&
      other.logLevel == logLevel &&
      other.pluginDevFolder == pluginDevFolder &&
      other.reportReminderDismissed == reportReminderDismissed;

  @override
  int get hashCode => Object.hash(
    developerMode,
    logLevel,
    pluginDevFolder,
    reportReminderDismissed,
  );

  @override
  String toString() =>
      'DeveloperSettings(developerMode: $developerMode, logLevel: $logLevel, '
      'pluginDevFolder: $pluginDevFolder, '
      'reportReminderDismissed: $reportReminderDismissed)';
}

/// `developer_settings` 單列表的存取。
final class DeveloperSettingsRepository {
  DeveloperSettingsRepository(this._database);

  final AppDatabase _database;

  /// 單列的主鍵；表上的 CHECK 只允許這個值。
  static const _rowId = 1;

  SimpleSelectStatement<$DeveloperSettingsTableTable, DeveloperSettingsRow>
  get _row =>
      _database.select(_database.developerSettingsTable)
        ..where((t) => t.id.equals(_rowId));

  /// 讀目前的設定；還沒有列時回傳 [DeveloperSettings.empty]。
  Future<DeveloperSettings> read() async =>
      _fromRow(await _row.getSingleOrNull());

  /// 目前的設定，之後每次寫入再發一次。
  Stream<DeveloperSettings> watch() => _row.watchSingleOrNull().map(_fromRow);

  /// 只寫入有給的欄位；沒給的（`null`）維持原值。
  Future<void> write({
    bool? developerMode,
    LogLevelSetting? logLevel,
    String? pluginDevFolder,
    bool? reportReminderDismissed,
  }) => _upsert(
    DeveloperSettingsTableCompanion(
      id: const Value(_rowId),
      developerMode: Value.absentIfNull(developerMode),
      logLevel: Value.absentIfNull(logLevel),
      pluginDevFolder: Value.absentIfNull(pluginDevFolder),
      reportReminderDismissed: Value.absentIfNull(reportReminderDismissed),
    ),
  );

  /// 把傳 `true` 的欄位清回 `null`（沒設定過，由上層套用預設）；其他欄位不動。
  ///
  /// 和 [write] 分開：[write] 的 `null` 表示「沒給、不動」，所以清空另走這裡。
  Future<void> clear({
    bool developerMode = false,
    bool logLevel = false,
    bool pluginDevFolder = false,
    bool reportReminderDismissed = false,
  }) {
    if (!developerMode &&
        !logLevel &&
        !pluginDevFolder &&
        !reportReminderDismissed) {
      return Future.value();
    }
    Value<T?> cleared<T>(bool clear) =>
        clear ? const Value(null) : const Value.absent();
    return _upsert(
      DeveloperSettingsTableCompanion(
        id: const Value(_rowId),
        developerMode: cleared(developerMode),
        logLevel: cleared(logLevel),
        pluginDevFolder: cleared(pluginDevFolder),
        reportReminderDismissed: cleared(reportReminderDismissed),
      ),
    );
  }

  /// 關閉開發者模式（ADR 0025 §決定 1）：同一筆寫入把 `developer_mode` 設成假、
  /// `log_level` 與 `plugin_dev_folder` 清回空。分成兩次寫的話，中間的那一刻會是
  /// 「開發者模式關著、log 層級仍是 debug」。
  Future<void> turnOffDeveloperMode() => _upsert(
    const DeveloperSettingsTableCompanion(
      id: Value(_rowId),
      developerMode: Value(false),
      logLevel: Value(null),
      pluginDevFolder: Value(null),
    ),
  );

  Future<void> _upsert(DeveloperSettingsTableCompanion row) => _database
      .into(_database.developerSettingsTable)
      .insertOnConflictUpdate(row);

  static DeveloperSettings _fromRow(DeveloperSettingsRow? row) => row == null
      ? DeveloperSettings.empty
      : DeveloperSettings(
          developerMode: row.developerMode,
          logLevel: row.logLevel,
          pluginDevFolder: row.pluginDevFolder,
          reportReminderDismissed: row.reportReminderDismissed,
        );
}
