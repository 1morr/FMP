import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fmp/core/log/log.dart';
import 'package:fmp/data/database.dart';

/// 保存設定的地方；沒有資料庫時是 null，改了照樣生效、只是不保存。
final settingsStoreProvider = Provider<SettingsStore?>(
  (ref) => switch (ref.watch(appDatabaseProvider)) {
    final database? => SettingsStore(database),
    null => null,
  },
);

/// 啟動時讀回的設定（[SettingsStore.load]）：`main` 在 `runApp` 前讀好再
/// override 進來，第一個畫面就是存的主題與語言。沒有資料庫時是空的。
final savedSettingsProvider = Provider<Map<String, String>>((ref) => const {});

/// 設定存進資料庫、啟動時讀回，一個設定一列（照 Android 的
/// SharedPreferences、Firefox 的 prefs：鍵加字串值）。值怎麼編碼由各設定的
/// [SavedSetting] 決定。
class SettingsStore {
  SettingsStore(this._database);

  final AppDatabase _database;

  /// 所有存過的設定。
  Future<Map<String, String>> load() async {
    final rows = await _database.select(_database.settingEntries).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<void> write(String key, String value) => _database
      .into(_database.settingEntries)
      .insertOnConflictUpdate(
        SettingEntriesCompanion.insert(key: key, value: value),
      );
}

/// 一個存在資料庫裡的設定：啟動時從 [savedSettingsProvider] 讀回，[set] 馬上
/// 生效再寫進資料庫。存的值讀不懂（例如較新版本寫的）時用 [fallback]。
abstract class SavedSetting<T> extends Notifier<T> {
  /// 存在資料庫裡的名字。
  String get key;

  /// 沒存過或讀不懂時的值。
  T get fallback;

  /// 讀不懂時回 null。
  T? decode(String raw);

  String encode(T value);

  @override
  T build() => switch (ref.read(savedSettingsProvider)[key]) {
    final raw? => decode(raw) ?? fallback,
    null => fallback,
  };

  /// 改成 [value]：畫面馬上跟著變，回傳的 future 在寫完時完成。寫不進去時
  /// 照樣生效，log 記一筆，下次開 App 回到上次存的值。
  Future<void> set(T value) async {
    if (value == state) return;
    state = value;
    final store = ref.read(settingsStoreProvider);
    if (store == null) return;
    try {
      await store.write(key, encode(value));
    } catch (error, stackTrace) {
      ref
          .read(logProvider)
          .error(
            'Saving the setting $key failed',
            error: error,
            stackTrace: stackTrace,
          );
    }
  }
}
