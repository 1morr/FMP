import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// App 內快捷鍵（ADR 0024 §決定 8）：固定、不可自訂，M1 只有已有功能的那幾個。
//
// 綁在外殼的 `Shortcuts` 上，所以只在 FMP 在前景、焦點在外殼裡時有效（對話框
// 開著時焦點在對話框的路由裡，這些鍵不作用）。
//
// 焦點在輸入框時，文字編輯也用到的鍵（空白鍵、Ctrl／Shift 加方向鍵）要讓給
// 輸入框：輸入框的 `DefaultTextEditingShortcuts` 由 `WidgetsApp` 放在 App 根，
// 比外殼的 `Shortcuts` 還遠，按鍵會先被外殼接走。所以這幾個鍵的 action 在
// [focusInTextInput] 時停用（[TextInputAwareAction]），`Shortcuts` 就不處理，
// 按鍵往上交給文字編輯（輸入空格、以字移動、延伸選取）。Ctrl+F、Ctrl+, 與
// F6 不是文字編輯鍵，在輸入框裡也有效。

/// 播放與暫停。
final class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

final class PreviousTrackIntent extends Intent {
  const PreviousTrackIntent();
}

final class NextTrackIntent extends Intent {
  const NextTrackIntent();
}

/// 從目前位置前後移動 [offset]。
final class SeekByIntent extends Intent {
  const SeekByIntent(this.offset);

  final Duration offset;
}

/// 到搜尋頁，焦點放進輸入框。
final class FocusSearchIntent extends Intent {
  const FocusSearchIntent();
}

/// 到設定頁。
final class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
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

/// Shift+←／→ 一次移動幾秒。
const seekStepSeconds = 5;

/// 外殼的快捷鍵表。按鍵也寫在提示文字裡（翻譯檔的 `*Tooltip`），改這裡要一起改。
const shellShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.space): PlayPauseIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
      PreviousTrackIntent(),
  SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
      NextTrackIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): SeekByIntent(
    Duration(seconds: -seekStepSeconds),
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): SeekByIntent(
    Duration(seconds: seekStepSeconds),
  ),
  SingleActivator(LogicalKeyboardKey.keyF, control: true): FocusSearchIntent(),
  SingleActivator(LogicalKeyboardKey.comma, control: true):
      OpenSettingsIntent(),
  SingleActivator(LogicalKeyboardKey.f6): NextRegionIntent(),
};
