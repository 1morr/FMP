import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';

/// 「網路」設定的值。欄位為 `null` 表示使用者沒設定過（ADR 0011 §決定 7），由
/// 上層套用預設值。
@immutable
final class NetworkSettings {
  const NetworkSettings({this.cacheLimitMebibytes});

  /// 全部沒設定過。
  static const empty = NetworkSettings();

  /// 快取上限（MiB）。
  final int? cacheLimitMebibytes;

  @override
  bool operator ==(Object other) =>
      other is NetworkSettings &&
      other.cacheLimitMebibytes == cacheLimitMebibytes;

  @override
  int get hashCode => cacheLimitMebibytes.hashCode;

  @override
  String toString() =>
      'NetworkSettings(cacheLimitMebibytes: $cacheLimitMebibytes)';
}

/// `network_settings` 單列表的存取。
final class NetworkSettingsRepository {
  NetworkSettingsRepository(this._database);

  final AppDatabase _database;

  /// 單列的主鍵；表上的 CHECK 只允許這個值。
  static const _rowId = 1;

  SimpleSelectStatement<$NetworkSettingsTableTable, NetworkSettingsRow>
  get _row =>
      _database.select(_database.networkSettingsTable)
        ..where((t) => t.id.equals(_rowId));

  /// 讀目前的設定；還沒有列時回傳 [NetworkSettings.empty]。
  Future<NetworkSettings> read() async =>
      _fromRow(await _row.getSingleOrNull());

  /// 目前的設定，之後每次寫入再發一次。
  Stream<NetworkSettings> watch() => _row.watchSingleOrNull().map(_fromRow);

  /// 只寫入有給的欄位；沒給的（`null`）維持原值。
  Future<void> write({int? cacheLimitMebibytes}) => _database
      .into(_database.networkSettingsTable)
      .insertOnConflictUpdate(
        NetworkSettingsTableCompanion(
          id: const Value(_rowId),
          cacheLimitMb: Value.absentIfNull(cacheLimitMebibytes),
        ),
      );

  /// 把傳 `true` 的欄位清回 `null`（沒設定過，由上層套用預設）；其他欄位不動。
  ///
  /// 和 [write] 分開：[write] 的 `null` 表示「沒給、不動」，所以清空另走這裡。
  Future<void> clear({bool cacheLimitMebibytes = false}) {
    if (!cacheLimitMebibytes) return Future.value();
    return _database
        .into(_database.networkSettingsTable)
        .insertOnConflictUpdate(
          const NetworkSettingsTableCompanion(
            id: Value(_rowId),
            cacheLimitMb: Value(null),
          ),
        );
  }

  static NetworkSettings _fromRow(NetworkSettingsRow? row) => row == null
      ? NetworkSettings.empty
      : NetworkSettings(cacheLimitMebibytes: row.cacheLimitMb);
}
