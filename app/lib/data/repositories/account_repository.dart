import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/domain/account.dart';

/// 一個插件的帳號顯示資訊（`accounts`，ADR 0029 §決定 6）。不含憑證，也不代表
/// 「已登入」：是否登入只看 `CredentialStore`。
@immutable
final class Account {
  const Account({
    required this.pluginId,
    required this.userId,
    required this.displayName,
    required this.status,
    required this.loggedInAt,
    this.avatarJson,
    this.lastRefreshAt,
    this.lastRefreshResult,
  });

  final String pluginId;
  final String userId;
  final String displayName;

  /// `Artwork[]` 的 JSON；沒有頭像為 `null`。
  final String? avatarJson;
  final AccountStatus status;

  /// 存成 UTC epoch 毫秒；讀回來是 UTC、精度到毫秒。
  final DateTime loggedInAt;
  final DateTime? lastRefreshAt;
  final RefreshResult? lastRefreshResult;

  /// 狀態與最近一次刷新的紀錄換成新的；沒給的欄位不動。
  Account withRefresh({
    AccountStatus? status,
    DateTime? refreshedAt,
    RefreshResult? result,
  }) => Account(
    pluginId: pluginId,
    userId: userId,
    displayName: displayName,
    avatarJson: avatarJson,
    status: status ?? this.status,
    loggedInAt: loggedInAt,
    lastRefreshAt: refreshedAt ?? lastRefreshAt,
    lastRefreshResult: result ?? lastRefreshResult,
  );

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.pluginId == pluginId &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.avatarJson == avatarJson &&
      other.status == status &&
      other.loggedInAt == loggedInAt &&
      other.lastRefreshAt == lastRefreshAt &&
      other.lastRefreshResult == lastRefreshResult;

  @override
  int get hashCode => Object.hash(
    pluginId,
    userId,
    displayName,
    avatarJson,
    status,
    loggedInAt,
    lastRefreshAt,
    lastRefreshResult,
  );

  @override
  String toString() =>
      'Account(pluginId: $pluginId, status: ${status.name}, '
      'loggedInAt: $loggedInAt)';
}

/// `accounts` 的存取。
final class AccountRepository {
  AccountRepository(this._database);

  final AppDatabase _database;

  /// 寫入；同插件已有帳號就覆蓋（重新登入）。
  Future<void> upsert(Account account) => _database
      .into(_database.accountsTable)
      .insertOnConflictUpdate(
        AccountsTableCompanion.insert(
          pluginId: account.pluginId,
          userId: account.userId,
          displayName: account.displayName,
          avatarJson: Value(account.avatarJson),
          status: account.status,
          loggedInAt: account.loggedInAt,
          lastRefreshAt: Value(account.lastRefreshAt),
          lastRefreshResult: Value(account.lastRefreshResult),
        ),
      );

  /// 所有帳號，依插件 id 排序。
  Future<List<Account>> list() async {
    final rows = await (_database.select(
      _database.accountsTable,
    )..orderBy([(t) => OrderingTerm.asc(t.pluginId)])).get();
    return [
      for (final row in rows)
        Account(
          pluginId: row.pluginId,
          userId: row.userId,
          displayName: row.displayName,
          avatarJson: row.avatarJson,
          status: row.status,
          loggedInAt: row.loggedInAt,
          lastRefreshAt: row.lastRefreshAt,
          lastRefreshResult: row.lastRefreshResult,
        ),
    ];
  }

  /// [pluginId] 的帳號；沒有是 `null`。
  Future<Account?> byId(String pluginId) async {
    for (final account in await list()) {
      if (account.pluginId == pluginId) return account;
    }
    return null;
  }

  /// 沒有這個帳號時什麼都不做。
  Future<void> remove(String pluginId) => (_database.delete(
    _database.accountsTable,
  )..where((t) => t.pluginId.equals(pluginId))).go();
}

/// 一個插件的匹配目標設定（`source_settings` 的兩欄，M4 design §8.3）。`null` 是沒設定過：
/// [target] 空＝依預設（是目標），[rank] 空＝排在後面、依插件清單。
@immutable
final class MatchTargetSetting {
  const MatchTargetSetting({required this.pluginId, this.target, this.rank});

  final String pluginId;
  final bool? target;
  final int? rank;

  @override
  bool operator ==(Object other) =>
      other is MatchTargetSetting &&
      other.pluginId == pluginId &&
      other.target == target &&
      other.rank == rank;

  @override
  int get hashCode => Object.hash(pluginId, target, rank);

  @override
  String toString() =>
      'MatchTargetSetting($pluginId, target: $target, rank: $rank)';
}

/// `source_settings` 的存取（每音源設定，ADR 0011 §決定 7）。
final class SourceSettingsRepository {
  SourceSettingsRepository(this._database);

  final AppDatabase _database;

  /// 「以登入身分瀏覽與播放」；`null`＝沒設定過，用 manifest 宣告的預設。
  Future<bool?> browseAsLoggedIn(String pluginId) async {
    final row = await (_database.select(
      _database.sourceSettingsTable,
    )..where((t) => t.pluginId.equals(pluginId))).getSingleOrNull();
    return row?.browseAsLoggedIn;
  }

  /// 設定開關；`null` 清回「沒設定過」。
  Future<void> setBrowseAsLoggedIn(String pluginId, {required bool? value}) =>
      _database
          .into(_database.sourceSettingsTable)
          .insertOnConflictUpdate(
            SourceSettingsTableCompanion.insert(
              pluginId: pluginId,
              browseAsLoggedIn: Value(value),
            ),
          );

  /// 每個有列的插件的匹配目標設定（兩欄都空的也在裡面），之後每次寫入再發一次。
  Stream<List<MatchTargetSetting>> watchMatchTargets() => _database
      .select(_database.sourceSettingsTable)
      .watch()
      .map(
        (rows) => [
          for (final row in rows)
            MatchTargetSetting(
              pluginId: row.pluginId,
              target: row.matchTarget,
              rank: row.matchRank,
            ),
        ],
      );

  /// 勾選或取消「匹配目標音源」（設定頁）；這一列的其他欄位不動，沒有就建一列。
  Future<void> setMatchTarget(String pluginId, {required bool target}) =>
      _database
          .into(_database.sourceSettingsTable)
          .insertOnConflictUpdate(
            SourceSettingsTableCompanion.insert(
              pluginId: pluginId,
              matchTarget: Value(target),
            ),
          );

  /// 依 [pluginIds] 的順序整批寫 `match_rank`（0、1、2…），一個 batch（設定頁拖曳後）。
  /// 每一列的其他欄位不動，沒有那一列就建一列。
  Future<void> setMatchRanks(List<String> pluginIds) =>
      _database.batch((batch) {
        batch.insertAllOnConflictUpdate(_database.sourceSettingsTable, [
          for (final (index, pluginId) in pluginIds.indexed)
            SourceSettingsTableCompanion.insert(
              pluginId: pluginId,
              matchRank: Value(index),
            ),
        ]);
      });

  /// 沒有這個設定時什麼都不做。
  Future<void> remove(String pluginId) => (_database.delete(
    _database.sourceSettingsTable,
  )..where((t) => t.pluginId.equals(pluginId))).go();

  /// `source_settings` 有任何變動時發出，給帳號頁重讀。聽 drift 的 `tableUpdates`
  /// 而不是 `watch()` 查詢，理由同 `PlayHistoryRepository.changes`。
  Stream<void> changes() => _database
      .tableUpdates(TableUpdateQuery.onTable(_database.sourceSettingsTable))
      .map((_) {});
}
