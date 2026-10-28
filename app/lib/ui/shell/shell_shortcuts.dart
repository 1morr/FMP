import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:fmp/platform/shortcut_modifier/shortcut_modifier.dart';

// 外殼的導覽類快捷鍵（ADR 0024 §決定 8、ADR 0035 §決定 7）：Ctrl+F、Ctrl+,、Ctrl+Q（Apple 平台是 ⌘F、⌘,、⌥⌘U）、
// F6、Esc。播放類在 `playback_shortcuts.dart`。Ctrl 是平台宣告的主修飾鍵（`ShortcutModifier`）。
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

/// Esc：焦點在輸入框時離開輸入框（焦點回到外殼）；不在輸入框時退出目前目的地巢狀導覽
/// 裡開著的頁（ADR 0033 §決定 5），已在根就不處理。對話框與彈出的選單、滑桿是自己的
/// route 或 overlay，由 Flutter 內建的 Esc 關閉，不經外殼。
final class EscapeIntent extends Intent {
  const EscapeIntent();
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

/// 切到佇列目的地（ADR 0035 §決定 7）。播放頁開著時先關播放頁（`PlayerPage` 的 action）。
final class ShowQueueIntent extends Intent {
  const ShowQueueIntent();
}

/// 主修飾鍵加 [key] 的組合鍵：Ctrl（Windows、Android 外接鍵盤）或 ⌘（Apple 平台）。
SingleActivator primaryChord(
  LogicalKeyboardKey key,
  ShortcutModifier modifier,
) => SingleActivator(
  key,
  control: modifier == ShortcutModifier.control,
  meta: modifier == ShortcutModifier.meta,
);

/// 搜尋：Ctrl+F、⌘F。
SingleActivator searchChord(ShortcutModifier modifier) =>
    primaryChord(LogicalKeyboardKey.keyF, modifier);

/// 設定：Ctrl+,、⌘,。
SingleActivator settingsChord(ShortcutModifier modifier) =>
    primaryChord(LogicalKeyboardKey.comma, modifier);

/// 選取模式全選：Ctrl+A、⌘A。
SingleActivator selectAllChord(ShortcutModifier modifier) =>
    primaryChord(LogicalKeyboardKey.keyA, modifier);

/// 開佇列：Ctrl+Q；Apple 平台是 ⌥⌘U（Apple Music 的「顯示佇列」），避開 ⌘Q（結束 App）。
SingleActivator queueChord(ShortcutModifier modifier) => switch (modifier) {
  ShortcutModifier.control => const SingleActivator(
    LogicalKeyboardKey.keyQ,
    control: true,
  ),
  ShortcutModifier.meta => const SingleActivator(
    LogicalKeyboardKey.keyU,
    meta: true,
    alt: true,
  ),
};

/// 開佇列的快捷鍵表。導覽類，所以輸入框裡也有效：Ctrl+Q、⌥⌘U 都不是文字編輯鍵。播放頁
/// 是另一個 route，不在外殼的 `Shortcuts` 之下，自己包一份。
Map<ShortcutActivator, Intent> queueShortcuts(ShortcutModifier modifier) => {
  queueChord(modifier): const ShowQueueIntent(),
};

/// 導覽類快捷鍵表（外殼）。播放類在 `playback_shortcuts.dart`；這幾個在輸入框內
/// 也有效（要能從輸入框離開）。
Map<ShortcutActivator, Intent> navigationShortcuts(ShortcutModifier modifier) =>
    {
      searchChord(modifier): const FocusSearchIntent(),
      settingsChord(modifier): const OpenSettingsIntent(),
      const SingleActivator(LogicalKeyboardKey.f6): const NextRegionIntent(),
      const SingleActivator(LogicalKeyboardKey.escape): const EscapeIntent(),
      ...queueShortcuts(modifier),
    };
