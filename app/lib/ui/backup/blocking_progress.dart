import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/theme/app_tokens.dart';

/// 蓋住畫面的進度對話框，直到 [work] 結束（成功時行程通常已經結束了）。失敗呼叫 [onError]。
/// 備份、還原與重設資料共用：這幾件事進行中不能讓使用者再按別的。
Future<void> runBlocking(
  BuildContext context, {
  required String message,
  required Future<void> Function() work,
  required void Function(Object error, StackTrace stackTrace) onError,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final gap = SizedBox(width: AppTokens.of(context).spacing.x4);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              gap,
              Flexible(child: Text(message)),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    await work();
  } on Object catch (error, stackTrace) {
    onError(error, stackTrace);
  } finally {
    navigator.pop();
  }
}
