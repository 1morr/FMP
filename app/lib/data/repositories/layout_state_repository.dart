import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';
import 'package:fmp/domain/player_tab.dart';

/// 依裝置記住的版面狀態（design §3.4）。欄位為 `null` 表示沒記過。
@immutable
final class LayoutState {
  const LayoutState({this.playerTab, this.panelExpanded, this.panelWidth});

  static const empty = LayoutState();

  /// 播放頁右欄上次選的分頁。
  final PlayerTab? playerTab;

  /// 右側「正在播放」面板是否展開；沒記過是 `null`（呼叫端當作展開）。
  final bool? panelExpanded;

  /// 右側面板的寬度（dp）；沒記過是 `null`。這是記住的值，畫面上的寬度依視窗夾取。
  final double? panelWidth;

  @override
  bool operator ==(Object other) =>
      other is LayoutState &&
      other.playerTab == playerTab &&
      other.panelExpanded == panelExpanded &&
      other.panelWidth == panelWidth;

  @override
  int get hashCode => Object.hash(playerTab, panelExpanded, panelWidth);

  @override
  String toString() =>
      'LayoutState(playerTab: $playerTab, panelExpanded: $panelExpanded, '
      'panelWidth: $panelWidth)';
}

/// `layout_state` 單列表的存取：播放頁的分頁與右側面板的展開、寬度。
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
  Future<void> write({
    PlayerTab? playerTab,
    bool? panelExpanded,
    double? panelWidth,
  }) => _database
      .into(_database.layoutStateTable)
      .insertOnConflictUpdate(
        LayoutStateTableCompanion(
          id: const Value(_rowId),
          playerTab: Value.absentIfNull(playerTab),
          panelExpanded: Value.absentIfNull(panelExpanded),
          panelWidth: Value.absentIfNull(panelWidth),
        ),
      );

  static LayoutState _fromRow(LayoutStateRow? row) => row == null
      ? LayoutState.empty
      : LayoutState(
          playerTab: row.playerTab,
          panelExpanded: row.panelExpanded,
          panelWidth: row.panelWidth,
        );
}
