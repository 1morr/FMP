import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'package:fmp/data/database/app_database.dart';

/// 依裝置記住的版面狀態（design §3.4）。欄位為 `null` 表示沒記過。
@immutable
final class LayoutState {
  const LayoutState({this.panelExpanded, this.panelWidth, this.railExpanded});

  static const empty = LayoutState();

  /// 右側「正在播放」面板是否展開；沒記過是 `null`（呼叫端當作展開）。
  final bool? panelExpanded;

  /// 右側面板的寬度（dp）；沒記過是 `null`。這是記住的值，畫面上的寬度依視窗夾取。
  final double? panelWidth;

  /// 左側導覽側欄是否展開；沒記過是 `null`（呼叫端當作收合）。
  final bool? railExpanded;

  @override
  bool operator ==(Object other) =>
      other is LayoutState &&
      other.panelExpanded == panelExpanded &&
      other.panelWidth == panelWidth &&
      other.railExpanded == railExpanded;

  @override
  int get hashCode => Object.hash(panelExpanded, panelWidth, railExpanded);

  @override
  String toString() =>
      'LayoutState(panelExpanded: $panelExpanded, '
      'panelWidth: $panelWidth, railExpanded: $railExpanded)';
}

/// `layout_state` 單列表的存取：右側面板的展開與寬度、左側側欄的展開。
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
    bool? panelExpanded,
    double? panelWidth,
    bool? railExpanded,
  }) => _database
      .into(_database.layoutStateTable)
      .insertOnConflictUpdate(
        LayoutStateTableCompanion(
          id: const Value(_rowId),
          panelExpanded: Value.absentIfNull(panelExpanded),
          panelWidth: Value.absentIfNull(panelWidth),
          railExpanded: Value.absentIfNull(railExpanded),
        ),
      );

  static LayoutState _fromRow(LayoutStateRow? row) => row == null
      ? LayoutState.empty
      : LayoutState(
          panelExpanded: row.panelExpanded,
          panelWidth: row.panelWidth,
          railExpanded: row.railExpanded,
        );
}
