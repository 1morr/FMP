import 'package:flutter/material.dart';

import 'package:fmp/i18n/strings.g.dart';

/// 統一的破壞性操作確認對話框。確認鈕一律 FilledButton + colorScheme.error。
/// 回傳 `Future<bool?>`（true=確認）。
Future<bool?> showConfirmDestructiveDialog(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.general.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}
