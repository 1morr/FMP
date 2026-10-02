import 'package:drift/drift.dart';

import 'package:fmp/data/database/converters.dart';

// Schema v2（M1 的 v1 加 M2 的 network_settings）。改這個檔案就是改 schema：bump `AppDatabase.schemaVersion`、
// 存新快照、寫 migration 與升級測試（.trellis/spec/app/data/index.md）。
// SQL 表名以 `tableName` 寫死，Dart 類別改名不會改到資料庫。

/// 外觀設定，單列（ADR 0011 §決定 7）。欄位為空＝使用者沒設定過。
@DataClassName('AppearanceSettingsRow')
class AppearanceSettingsTable extends Table {
  @override
  String get tableName => 'appearance_settings';

  /// 固定為 1；CHECK 讓第二列插不進去。
  late final IntColumn id = integer().check(id.equals(1))();
  late final themeMode = text().nullable().map(
    const ThemeModeSettingConverter(),
  )();
  late final locale = text().nullable().map(const LocaleSettingConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 「網路」設定，單列（ADR 0011 §決定 7）。欄位為空＝使用者沒設定過。
@DataClassName('NetworkSettingsRow')
class NetworkSettingsTable extends Table {
  @override
  String get tableName => 'network_settings';

  /// 固定為 1；CHECK 讓第二列插不進去。
  late final IntColumn id = integer().check(id.equals(1))();

  /// 快取上限（MiB）；空＝平台宣告的預設（ADR 0016 §決定 3）。
  late final cacheLimitMb = integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 從檔案安裝的插件（ADR 0014）。
@DataClassName('InstalledPluginRow')
class InstalledPluginsTable extends Table {
  @override
  String get tableName => 'installed_plugins';

  /// 音源 id，例如 B 站插件的 id。
  late final id = text()();
  late final version = text()();
  late final manifestJson = text()();
  late final script = text()();

  /// UTC epoch 毫秒。
  late final installedAt = integer().map(const EpochMillisecondsConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 每個插件自己的 key／value（ADR 0014 §決定 5）。移除插件時由外鍵的
/// `ON DELETE CASCADE` 一起清掉（ADR 0014 §決定 8）。
@DataClassName('PluginStorageRow')
class PluginStorageTable extends Table {
  @override
  String get tableName => 'plugin_storage';

  late final pluginId = text().references(
    InstalledPluginsTable,
    #id,
    onDelete: KeyAction.cascade,
  )();
  late final key = text()();
  late final value = text()();

  @override
  Set<Column<Object>> get primaryKey => {pluginId, key};
}
