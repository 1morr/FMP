import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// 外殼的導覽類快捷鍵（ADR 0024 §決定 8）：Ctrl+F、Ctrl+,、F6、Esc。播放類在
// `playback_shortcuts.dart`。
//
// 綁在外殼的 `Shortcuts` 上，所以只在 FMP 在前景、焦點在外殼裡時有效（對話框
// 開著時焦點在對話框的路由裡，這些鍵不作用）。
//
// 輸入框裡的規則一句話：導覽類在輸入框內也有效，其餘都讓給輸入框。文字編輯的
// 快捷鍵（`DefaultTextEditingShortcuts`）由 `WidgetsApp` 放在 App 根，比外殼的
// `Shortcuts` 還遠，按鍵會先被外殼接走，所以非導覽類的 action 用
// [TextInputAwareAction]：焦點在 [focusInTextInput] 時停用，`Shortcuts` 就不處理，
// 按鍵往上交給文字編輯。

/// 到搜尋頁，焦點放進輸入框。
final class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

/// 到設定頁。
final class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

/// Esc：焦點在輸入框時離開輸入框（焦點回到外殼）。對話框與彈出的選單、滑桿是
/// 自己的 route 或 overlay，由 Flutter 內建的 Esc 關閉，不經外殼。
final class LeaveTextInputIntent extends Intent {
  const LeaveTextInputIntent();
}

/// 焦點移到下一區（導覽 → 內容 → 播放列 → 導覽）。
final class NextRegionIntent extends Intent {
  const NextRegionIntent();
}

/// 焦點在輸入框（`EditableText`）裡。
bool focusInTextInput() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null &&
      (context.widget is EditableText ||
          context.findAncestorWidgetOfExactType<EditableText>() != null);
}

/// 焦點在輸入框時停用的 action：給同時是文字編輯鍵的快捷鍵用。
final class TextInputAwareAction<T extends Intent> extends CallbackAction<T> {
  TextInputAwareAction({required super.onInvoke});

  @override
  bool isEnabled(T intent) => !focusInTextInput();
}

/// 導覽類快捷鍵表（外殼）。播放類在 `playback_shortcuts.dart`；這幾個在輸入框內
/// 也有效（要能從輸入框離開）。
const navigationShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.keyF, control: true): FocusSearchIntent(),
  SingleActivator(LogicalKeyboardKey.comma, control: true):
      OpenSettingsIntent(),
  SingleActivator(LogicalKeyboardKey.f6): NextRegionIntent(),
  SingleActivator(LogicalKeyboardKey.escape): LeaveTextInputIntent(),
};
