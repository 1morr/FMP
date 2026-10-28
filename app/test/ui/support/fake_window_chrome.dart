import 'package:flutter/foundation.dart';
import 'package:fmp/platform/window_chrome/window_chrome.dart';

/// 記下呼叫的視窗動作（自繪標題列的測試）。
final class FakeWindowChrome implements WindowChrome {
  FakeWindowChrome({
    bool maximized = false,
    this.captionButtons = CaptionButtons.drawn,
    this.titleBarHeight,
  }) : _maximized = ValueNotifier(maximized);

  @override
  final CaptionButtons captionButtons;

  @override
  final double? titleBarHeight;

  final ValueNotifier<bool> _maximized;

  /// 依序的呼叫：`minimize`、`toggleMaximize`、`close`、`startDragging`。
  final calls = <String>[];

  /// 視窗被系統最大化或還原（例如 Win＋↑）；最大化鈕的提示跟著變。
  void setMaximized(bool value) => _maximized.value = value;

  @override
  ValueListenable<bool> get maximized => _maximized;

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> toggleMaximize() async {
    calls.add('toggleMaximize');
    _maximized.value = !_maximized.value;
  }

  @override
  Future<void> close() async => calls.add('close');

  @override
  Future<void> startDragging() async => calls.add('startDragging');
}
