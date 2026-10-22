import 'package:flutter/foundation.dart';

// 備份檔的內容規則與相關型別（ADR 0034 §決定 2、3，M4 design §11）。
//
// 備份＝資料庫的副本，所以「帶不帶走」是逐表、逐欄的清單。每張表必須恰好出現在
// [backupExcludedTables] 或 [backupCarriedTables] 其中一份，
// `test/data/database/backup_format_test.dart` 的歸類閘門對著 `AppDatabase.allTables`。

/// 不帶走的整張表（SQL 表名）：版面是這台裝置的、帳號顯示資訊跟著這台的登入、插件的
/// key／value 含匿名 cookie 等裝置身分、排程的上次成功時間只對這台有意義、匯入舊版的紀錄與歌單對照是這台的事件（還原另一台的備份後不再成立）。
const backupExcludedTables = [
  'layout_state',
  'accounts',
  'plugin_storage',
  'scheduler_runs',
  'legacy_playlist_ids',
  'legacy_imports',
];

/// [backupExcludedTables] 裡還原時**帶這台的列**的表：帳號顯示資訊跟著這台的登入，版面是這台的。
/// 其餘的不帶走的表（`plugin_storage`、`scheduler_runs`）還原後是空的：插件重新取得匿名
/// cookie，排程的到期各跑一次（M4 design §11）。必須是 [backupExcludedTables] 的子集。
const backupKeptOnDeviceTables = ['accounts', 'layout_state'];

/// 帶走的表：其餘全部。
const backupCarriedTables = [
  'appearance_settings',
  'network_settings',
  'playback_settings',
  'installed_plugins',
  'plugin_indexes',
  'tracks',
  'queue_entries',
  'player_state',
  'play_history',
  'source_settings',
  'developer_settings',
  'radio_stations',
  'playlists',
  'playlist_entries',
  'playlist_remote',
  'chart_settings',
  'match_results',
  'track_origins',
];

/// 帶走的表裡只屬於這台的欄位：表名 → 欄位名。匯出時設成空值，還原時換成這台的值。
const backupDeviceColumns = <String, List<String>>{
  'playback_settings': ['output_device_id', 'output_device_name'],
  'developer_settings': ['plugin_dev_folder'],
};

/// 多列表裡只屬於這台的欄位：表名 → 以哪一欄當鍵、哪些欄位。匯出時設成空值，還原時
/// 備份裡每一列換成這台同鍵那一列的值（這台沒有那一列是空值，不新增列）。
/// `source_settings` 每個插件一列，「以登入身分瀏覽」跟著這台的登入。
const backupDeviceKeyedColumns = <String, ({String key, List<String> columns})>{
  'source_settings': (key: 'plugin_id', columns: ['browse_as_logged_in']),
};

/// `installed_plugins` 裡插件開發工具補的標記列（M3 PR 16b）：匯出時刪掉，還原時留這台的。
const backupDevMarkerTable = 'installed_plugins';
const backupDevMarkerColumn = 'from_dev_folder';

/// `20261014T123456789Z`：UTC、毫秒、不含冒號（Windows 檔名不准）；備份與暫存檔名用。
String backupTimestamp(DateTime time) {
  String pad(int value, int width) => value.toString().padLeft(width, '0');
  return '${pad(time.year, 4)}${pad(time.month, 2)}${pad(time.day, 2)}'
      'T${pad(time.hour, 2)}${pad(time.minute, 2)}${pad(time.second, 2)}'
      '${pad(time.millisecond, 3)}Z';
}

/// 備份檔被拒絕的原因（ADR 0034 §決定 3）。
enum BackupRejection {
  /// `user_version` 比這個 App 的 schema 新：「這份備份來自較新版的 FMP」。
  newerVersion,

  /// 不是 SQLite 檔、`user_version` 為 0，或 schema 不是 FMP 的（缺表、多出 trigger／view
  /// 等不認得的物件）。
  notFmpBackup,

  /// 是 FMP 的備份但壞了：`integrity_check` 不過、無法 migration。
  corrupt,
}

/// 備份檔不能用；目前的資料庫完全沒動。
final class BackupRejected implements Exception {
  const BackupRejected(this.reason, [this.detail]);

  final BackupRejection reason;

  /// 給 log 的細節（英文，不含檔案內容）。
  final String? detail;

  @override
  String toString() =>
      'BackupRejected(${reason.name}${detail == null ? '' : ': $detail'})';
}

/// 備份裡的一個插件，給還原確認框列出（ADR 0034 §決定 4）。
///
/// 名稱、版本、網域取自腳本標頭的 manifest（執行時真正用的），不是 `manifest_json` 欄。
@immutable
final class BackupPlugin {
  const BackupPlugin({
    required this.id,
    required this.name,
    required this.version,
    required this.hosts,
  });

  final String id;

  /// manifest 的 `name`；腳本讀不出來用 [id]。
  final String name;
  final String version;

  /// manifest 的 `allowedHosts`；腳本讀不出來是空的（讀不出腳本的插件載入不了，連不出去）。
  final List<String> hosts;

  @override
  bool operator ==(Object other) =>
      other is BackupPlugin &&
      other.id == id &&
      other.name == name &&
      other.version == version &&
      listEquals(other.hosts, hosts);

  @override
  int get hashCode => Object.hash(id, name, version, Object.hashAll(hosts));
}

/// `installed_plugins` 的一列（不是開發標記列）→ 確認框要列的插件，[DatabaseBackups] 的
/// `readPlugin`。列與腳本標頭不一致就拋 [BackupRejected]；腳本解析不出來（載入不了）回
/// `null`，`stage` 會把那一列從暫存檔刪掉。
typedef BackupPluginReader = BackupPlugin? Function({
  required String id,
  required String version,
  required String manifestJson,
  required String script,
});

/// 已經驗過、重建成目前 schema 的備份暫存檔（`backups/staged-<UTC>.db`）。
@immutable
final class StagedBackup {
  const StagedBackup({
    required this.path,
    required this.plugins,
    this.unusablePluginIds = const [],
    this.indexUrls = const [],
  });

  final String path;
  final List<BackupPlugin> plugins;

  /// 腳本解析不出來（壞了、`apiVersion` 這個版本不支援）的插件 id：`stage` 已經從暫存檔刪掉，
  /// 還原後不會有它們；確認框另列。
  final List<String> unusablePluginIds;

  /// 備份會帶進來的自訂插件 index 網址（`plugin_indexes`），確認框列出。
  final List<String> indexUrls;
}

/// 還原時要從這台目前的資料庫帶到新資料庫的值（ADR 0034 §決定 4 第 4 條）。
///
/// 內容照 [backupKeptOnDeviceTables]、[backupDeviceColumns]、[backupDeviceKeyedColumns]、
/// [backupDevMarkerTable]
/// 的常數取，列是「欄位名 → 值」的原始 map，不依賴 schema 版本。
@immutable
final class CarriedState {
  const CarriedState({
    this.tables = const {},
    this.deviceColumns = const {},
    this.keyedDeviceColumns = const {},
    this.devMarkerPlugins = const [],
  });

  /// [backupKeptOnDeviceTables] 每張表在這台的列。
  final Map<String, List<Map<String, Object?>>> tables;

  /// [backupDeviceColumns] 每一欄在這台的值（沒設定過是 `null`）：表名 → 欄位名 → 值。
  final Map<String, Map<String, Object?>> deviceColumns;

  /// [backupDeviceKeyedColumns] 每一列在這台的值：表名 → 鍵的值 → 欄位名 → 值。
  final Map<String, Map<Object?, Map<String, Object?>>> keyedDeviceColumns;

  /// `installed_plugins` 裡 `from_dev_folder` 為真的列。
  final List<Map<String, Object?>> devMarkerPlugins;
}
