import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/ui/debug/debug_data_actions.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';
import 'package:fmp/ui/theme/app_tokens.dart';

/// Debug 頁的「重設資料」（ADR 0025 §決定 9）：說明清什麼、不動什麼，與一個按鈕。流程（備份、
/// 二次確認、清空、重啟）在 [startReset]。
class DebugReset extends ConsumerWidget {
  const DebugReset({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).debug;
    final spacing = AppTokens.of(context).spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.resetBody),
        SizedBox(height: spacing.x2),
        Text(t.resetBackupNote),
        SizedBox(height: spacing.x4),
        FilledButton.icon(
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(t.resetButton),
          onPressed: () => unawaited(startReset(context, ref)),
        ),
      ],
    );
  }
}
