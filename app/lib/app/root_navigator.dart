import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 根 `Navigator` 的 key，給 `MaterialApp.navigatorKey`（`FmpApp`）。
///
/// 提示（`Toaster`）的「詳細」「回報」不在任何頁面的 `BuildContext` 底下，要開錯誤詳細頁
/// 就經它 push（ADR 0023 §決定 4）。`ToastHost` 包在 Navigator 外面，所以推上去的全螢幕頁
/// 之上仍看得到提示。
final rootNavigatorKeyProvider = Provider<GlobalKey<NavigatorState>>(
  (ref) => GlobalKey<NavigatorState>(debugLabel: 'root navigator'),
);
