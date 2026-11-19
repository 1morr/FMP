import 'package:drift/drift.dart';

/// 設定，一個設定一列（`SettingsStore`）。值是字串，各設定自己編碼；新增設定
/// 不必改 schema。
@DataClassName('SettingRow')
class SettingEntries extends Table {
  /// 設定的名字，例如 `appearance.theme`。
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
