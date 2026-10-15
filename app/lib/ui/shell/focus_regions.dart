import 'package:flutter/widgets.dart';

// 焦點區（ADR 0024 §決定 8）的共用動作：外殼（導覽、內容、播放列）與播放頁（控制區、
// 歌詞欄、右欄分頁）各有自己的一組 `FocusScopeNode`，F6 在組內依序換區。

/// 回到 [region] 上次的焦點，沒有就是它的第一個可聚焦項目（依該區的走訪順序：預設是
/// 閱讀順序，有 `FocusTraversalOrder` 時照它）。區不在畫面上或沒有可聚焦項目時回 `false`。
bool focusInto(FocusScopeNode region) {
  if (region.context == null || region.parent == null) return false;
  final target = _entryOf(region);
  if (target == null) return false;
  target.requestFocus();
  return true;
}

/// [scope] 裡要給焦點的那一個。選到的是另一個 scope（外殼內容區裡巢狀 Navigator 的頁面
/// route）時再往裡面找：只把焦點交給那個 scope 的話，焦點停在 scope 本身、不在頁面的項目上。
FocusNode? _entryOf(FocusScopeNode scope) {
  final previous = scope.focusedChild;
  final candidates = scope.traversalDescendants;
  final firstContext = candidates.firstOrNull?.context;
  // `traversalDescendants` 是掛上的先後，不是走訪順序；第一個要問該區的走訪策略。
  final policy = firstContext == null
      ? null
      : FocusTraversalGroup.maybeOf(firstContext);
  final target = previous != null && previous.canRequestFocus
      ? previous
      : (policy?.findFirstFocus(scope, ignoreCurrentFocus: true) ??
            candidates.firstOrNull);
  if (target is FocusScopeNode && target != scope) {
    return _entryOf(target) ?? target;
  }
  return target;
}

/// F6：從焦點所在的區往 [regions] 的下一區，跳過不在畫面上或沒有可聚焦項目的區。
/// 焦點不在任何一區時從第一區開始。焦點停在看不見的位置（scope 本身，或 Tab 走不到的節點，
/// 例如外殼內容區裡巢狀 Navigator 一建好就自動取得焦點的那一個；換目的地後焦點退回內容區的
/// scope）也當成不在任何一區：畫面上沒有焦點時，F6 一律從第一區開始。
void focusNextRegion(List<FocusScopeNode> regions) {
  final focus = FocusManager.instance.primaryFocus;
  final current =
      focus == null || focus is FocusScopeNode || focus.skipTraversal
      ? -1
      : regions.indexWhere(focus.ancestors.contains);
  for (var step = 1; step <= regions.length; step++) {
    if (focusInto(regions[(current + step) % regions.length])) return;
  }
}
