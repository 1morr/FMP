import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/domain/appearance.dart';

/// 外觀設定的值。欄位為 `null` 表示使用者沒設定過（ADR 0011 §決定 7），由上層
/// 套用預設值。
@immutable
final class AppearanceSettings {
  const AppearanceSettings({this.themeMode, this.locale});

  /// 全部沒設定過。
  static const empty = AppearanceSettings();

  final ThemeModeSetting? themeMode;
  final LocaleSetting? locale;

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      other.themeMode == themeMode &&
      other.locale == locale;

  @override
  int get hashCode => Object.hash(themeMode, locale);

  @override
  String toString() =>
      'AppearanceSettings(themeMode: $themeMode, locale: $locale)';
}

/// `appearance_settings` 單列表的存取。
final class AppearanceSettingsRepository {
  AppearanceSettingsRepository(this._database);

  final AppDatabase _database;

  /// 單列的主鍵；表上的 CHECK 只允許這個值。
  static const _rowId = 1;

  SimpleSelectStatement<$AppearanceSettingsTableTable, AppearanceSettingsRow>
  get _row =>
      _database.select(_database.appearanceSettingsTable)
        ..where((t) => t.id.equals(_rowId));

  /// 讀目前的設定；還沒有列時回傳 [AppearanceSettings.empty]。
  Future<AppearanceSettings> read() async =>
      _fromRow(await _row.getSingleOrNull());

  /// 目前的設定，之後每次寫入再發一次。
  Stream<AppearanceSettings> watch() => _row.watchSingleOrNull().map(_fromRow);

  /// 只寫入有給的欄位；沒給的（`null`）維持原值。
  Future<void> write({ThemeModeSetting? themeMode, LocaleSetting? locale}) =>
      _database
          .into(_database.appearanceSettingsTable)
          .insertOnConflictUpdate(
            AppearanceSettingsTableCompanion(
              id: const Value(_rowId),
              themeMode: Value.absentIfNull(themeMode),
              locale: Value.absentIfNull(locale),
            ),
          );

  /// 把傳 `true` 的欄位清回 `null`（沒設定過，由上層套用預設）；其他欄位不動。
  ///
  /// 和 [write] 分開：[write] 的 `null` 表示「沒給、不動」，所以清空另走這裡。
  Future<void> clear({bool themeMode = false, bool locale = false}) {
    if (!themeMode && !locale) return Future.value();
    return _database
        .into(_database.appearanceSettingsTable)
        .insertOnConflictUpdate(
          AppearanceSettingsTableCompanion(
            id: const Value(_rowId),
            themeMode: themeMode ? const Value(null) : const Value.absent(),
            locale: locale ? const Value(null) : const Value.absent(),
          ),
        );
  }

  static AppearanceSettings _fromRow(AppearanceSettingsRow? row) => row == null
      ? AppearanceSettings.empty
      : AppearanceSettings(themeMode: row.themeMode, locale: row.locale);
}
