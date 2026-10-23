import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// App 根的 [ProviderScope]；`main()` 的每個 `runApp` 都用它。
///
/// Riverpod 的自動重試全域關閉（ADR 0013 §決定 4）：重試只在網路層做一層，
/// provider 失敗就停在錯誤狀態。
///
/// 同一次啟動會 `runApp` 好幾次（匯入進度、資料庫錯誤頁換成正式 App）：根的 [ProviderScope] 型別
/// 相同時 Flutter 會沿用同一個 element，override 的數量一變就觸發 Riverpod 的斷言，所以每個
/// 不同的根給不同的 [key]。
ProviderScope appProviderScope({
  Key? key,
  List<Override> overrides = const [],
  required Widget child,
}) => ProviderScope(
  key: key,
  retry: _noRetry,
  overrides: overrides,
  child: child,
);

/// 永不重試的 Riverpod retry 函式（riverpod.dev〈Automatic retry〉的寫法）。
Duration? _noRetry(int retryCount, Object error) => null;
