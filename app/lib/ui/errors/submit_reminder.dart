import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fmp/settings/developer_settings.dart';
import 'package:fmp/ui/i18n/ui_locale.dart';

/// 把內容送出去之前的「送出前請檢查」提醒（ADR 0023 §決定 4、ADR 0025 §決定 10）。「在 GitHub
/// 回報」與診斷包、log 檔的匯出共用，也共用同一個「不再提醒」設定（`report_reminder_dismissed`）；
/// [body] 是各自要提醒的內容。
///
/// 回傳 `true` 可以繼續：設定過不再提醒（不開對話框），或使用者按了「繼續」（有勾「不再提醒」就
/// 順便寫入設定）；`false` 是使用者取消或點外面，呼叫端什麼都不做。
///
/// 設定還沒載入完時當成沒關過提醒：多問一次，比沒問就把內容送出去好。
Future<bool> confirmSubmitReminder(
  BuildContext context,
  WidgetRef ref, {
  required String body,
}) async {
  final dismissed = ref
      .read(developerProvider)
      .value
      ?.stored
      .reportReminderDismissed;
  if (dismissed == true) return true;
  // true：繼續並不再提醒；false：只繼續；null：取消，什麼都不做。
  final answer = await showDialog<bool>(
    context: context,
    builder: (_) => _ReminderDialog(body: body),
  );
  if (answer == null) return false;
  if (answer) {
    await ref.read(developerProvider.notifier).dismissReportReminder();
  }
  return true;
}

class _ReminderDialog extends ConsumerStatefulWidget {
  const _ReminderDialog({required this.body});

  final String body;

  @override
  ConsumerState<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends ConsumerState<_ReminderDialog> {
  var _dontAsk = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).errorReport;
    return AlertDialog(
      title: Text(t.reminderTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.body),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _dontAsk,
            title: Text(t.reminderDontAsk),
            onChanged: (value) => setState(() => _dontAsk = value ?? false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_dontAsk),
          child: Text(t.reminderContinue),
        ),
      ],
    );
  }
}
