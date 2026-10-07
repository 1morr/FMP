import 'package:flutter/widgets.dart';

// 焦點區（ADR 0024 §決定 8）的共用動作：外殼（導覽、內容、播放列）與播放頁（控制區、
// 歌詞欄、右欄分頁）各有自己的一組 `FocusScopeNode`，F6 在組內依序換區。

/// 回到 [region] 上次的焦點，沒有就是它的第一個可聚焦項目（依該區的走訪順序：預設是
/// 閱讀順序，有 `FocusTraversalOrder` 時照它）。區不在畫面上或沒有可聚焦項目時回 `false`。
bool focusInto(FocusScopeNode region) {
  if (region.context == null || region.parent == null) return false;
  final previous = region.focusedChild;
  final candidates = region.traversalDescendants;
  final firstContext = candidates.firstOrNull?.context;
  // `traversalDescendants` 是掛上的先後，不是走訪順序；第一個要問該區的走訪策略。
  final policy = firstContext == null
      ? null
      : FocusTraversalGroup.maybeOf(firstContext);
  final target = previous != null && previous.canRequestFocus
      ? previous
      : (policy?.findFirstFocus(region, ignoreCurrentFocus: true) ??
            candidates.firstOrNull);
  if (target == null) return false;
  target.requestFocus();
  return true;
}

/// F6：從焦點所在的區往 [regions] 的下一區，跳過不在畫面上或沒有可聚焦項目的區。
/// 焦點不在任何一區時從第一區開始。
void focusNextRegion(List<FocusScopeNode> regions) {
  final focus = FocusManager.instance.primaryFocus;
  final current = focus == null
      ? -1
      : regions.indexWhere(
          (region) => focus == region || focus.ancestors.contains(region),
        );
  for (var step = 1; step <= regions.length; step++) {
    if (focusInto(regions[(current + step) % regions.length])) return;
  }
}
