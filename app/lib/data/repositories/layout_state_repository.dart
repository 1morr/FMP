import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/domain/player_tab.dart';

/// 依裝置記住的版面狀態（design §3.4）。欄位為 `null` 表示沒記過。
@immutable
final class LayoutState {
  const LayoutState({this.playerTab});

  static const empty = LayoutState();

  /// 播放頁右欄上次選的分頁。
  final PlayerTab? playerTab;

  @override
  bool operator ==(Object other) =>
      other is LayoutState && other.playerTab == playerTab;

  @override
  int get hashCode => playerTab.hashCode;

  @override
  String toString() => 'LayoutState(playerTab: $playerTab)';
}

/// `layout_state` 單列表的存取。表上另有面板展開與寬度兩欄（M2 PR 19 用），
/// 這裡先只讀寫有人用的分頁。
final class LayoutStateRepository {
  LayoutStateRepository(this._database);

  final AppDatabase _database;

  /// 單列的主鍵；表上的 CHECK 只允許這個值。
  static const _rowId = 1;

  SimpleSelectStatement<$LayoutStateTableTable, LayoutStateRow> get _row =>
      _database.select(_database.layoutStateTable)
        ..where((t) => t.id.equals(_rowId));

  /// 讀目前的狀態；還沒有列時回傳 [LayoutState.empty]。
  Future<LayoutState> read() async => _fromRow(await _row.getSingleOrNull());

  /// 目前的狀態，之後每次寫入再發一次。
  Stream<LayoutState> watch() => _row.watchSingleOrNull().map(_fromRow);

  /// 只寫入有給的欄位；沒給（`null`）的維持原值。
  Future<void> write({PlayerTab? playerTab}) => _database
      .into(_database.layoutStateTable)
      .insertOnConflictUpdate(
        LayoutStateTableCompanion(
          id: const Value(_rowId),
          playerTab: Value.absentIfNull(playerTab),
        ),
      );

  static LayoutState _fromRow(LayoutStateRow? row) =>
      row == null ? LayoutState.empty : LayoutState(playerTab: row.playerTab);
}
